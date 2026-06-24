#!/usr/bin/env bash
# setup-openfx — owns .env.local setup AND safe credential loading, so the skill never has to
# `source` (execute) a dotenv-shaped file. `source` THIS file — it ships with the skill and is the
# only trusted code here — then call the functions. Nothing below prints secret values.
#
#   init_env_local [FILE]                   Create FILE (default ./.env.local) from the skill's
#                                           template if it doesn't exist, mode 0600. Idempotent: an
#                                           existing file is left intact (preserves
#                                           OPENFX_WEBHOOK_SECRET + any overrides).
#   set_openfx_webhook_secret VALUE [FILE]  Upsert the OPENFX_WEBHOOK_SECRET line (no duplicate, no echo).
#   load_openfx_env [sandbox|prod] [FILE]   PARSE (never source) .env.local + the downloaded credential
#                                           files and export TESSER_*/OPENFX_* into the current shell.
#                                           Defaults to sandbox. Returns non-zero (exporting nothing
#                                           sensitive) if a base/auth URL override points off the
#                                           Tesser/Auth0 allowlist, or if Tesser creds are missing.
#
# WHY NOT `set -a; . ./.env.local`?  Sourcing a file executes it. A dotenv-shaped file in the working
# dir (.env.local, tesser-credentials*.env) could then run arbitrary shell — code execution from a
# planted or malformed file. load_openfx_env reads KEY=value lines LITERALLY instead (no eval, no
# source), reads the OpenFX key JSON with jq (not a shell), and pins the API/Auth0 hosts.

# Path to the template that ships with this skill (this file lives in scripts/, template in templates/).
_ENV_LOCAL_TEMPLATE="$( CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd )/templates/env.local.template"

# Hosts the credential write / token mint may EVER target. A tampered .env.local cannot redirect the
# ES256 private key or the bearer/client-credentials anywhere else.
_TESSER_API_HOSTS="sandbox.tesserx.co api.tesser.xyz"
_TESSER_AUTH_HOSTS="dev-awqy75wdabpsnsvu.us.auth0.com tesser-payments.us.auth0.com"

init_env_local() {
  local file="${1:-.env.local}"
  if [ ! -f "$file" ]; then
    if [ ! -f "$_ENV_LOCAL_TEMPLATE" ]; then
      echo "setup-openfx: env template not found at $_ENV_LOCAL_TEMPLATE" >&2
      return 1
    fi
    cp "$_ENV_LOCAL_TEMPLATE" "$file"
  fi
  chmod 600 "$file" 2>/dev/null || true
}

set_openfx_webhook_secret() {
  local val="$1" file="${2:-.env.local}"
  [ -n "$val" ] || { echo "setup-openfx: set_openfx_webhook_secret needs a value" >&2; return 1; }
  init_env_local "$file" || return 1
  local tmp; tmp="$(mktemp "${file}.XXXXXX")"   # same dir => atomic mv; gitignored via '.env.local.*'
  grep -vE '^[[:space:]]*OPENFX_WEBHOOK_SECRET=' "$file" > "$tmp" 2>/dev/null || true
  printf 'OPENFX_WEBHOOK_SECRET=%s\n' "$val" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file" 2>/dev/null || true
}

# Read ONE key's value from a KEY=value file without executing the file. Honors an optional leading
# `export `, takes the last assignment, strips one layer of surrounding quotes. Prints to stdout
# (empty if absent). No eval, no source — the value is never re-interpreted by the shell.
_dotenv_get() {
  local key="$1" file="$2" line val
  [ -f "$file" ] || return 0
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | tail -n1)" || return 0
  [ -n "$line" ] || return 0
  val="${line#*=}"
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  printf '%s' "$val"
}

# Is the host of $1 in the space-separated allowlist $2?  (scheme + path + port stripped)
# Uses a quoted `case` glob rather than splitting $allow into words, so it behaves identically
# under bash and zsh (zsh does not word-split unquoted expansions by default).
_host_in_allowlist() {
  local url="$1" allow="$2" host
  host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"
  case " $allow " in
    *" $host "*) return 0 ;;
  esac
  return 1
}

load_openfx_env() {
  local target="sandbox" file=".env.local" a
  for a in "$@"; do
    case "$a" in
      sandbox|staging)  target="sandbox" ;;
      prod|production)  target="prod" ;;
      *)                file="$a" ;;
    esac
  done

  # Under zsh a glob that matches nothing is an error; make it pass through literally (as bash does)
  # so the `[ -f ]` guards below can simply skip. local_options restores this on return.
  if [ -n "${ZSH_VERSION:-}" ]; then setopt local_options no_nomatch 2>/dev/null || true; fi

  # 1) Endpoint hosts: start from the row for the chosen env, allow .env.local to override, then
  #    REFUSE anything off the allowlist before any credential leaves the machine.
  local base aud auth o
  if [ "$target" = "prod" ]; then
    base="https://api.tesser.xyz"; auth="https://tesser-payments.us.auth0.com/oauth/token"
  else
    base="https://sandbox.tesserx.co"; auth="https://dev-awqy75wdabpsnsvu.us.auth0.com/oauth/token"
  fi
  aud="$base"
  o="$(_dotenv_get TESSER_BASE_URL "$file")"; [ -n "$o" ] && base="$o"
  o="$(_dotenv_get TESSER_AUDIENCE "$file")"; [ -n "$o" ] && aud="$o"
  o="$(_dotenv_get TESSER_AUTH_URL "$file")"; [ -n "$o" ] && auth="$o"
  _host_in_allowlist "$base" "$_TESSER_API_HOSTS" || {
    echo "setup-openfx: refusing TESSER_BASE_URL host off allowlist ($_TESSER_API_HOSTS): $base" >&2; return 1; }
  _host_in_allowlist "$aud" "$_TESSER_API_HOSTS" || {
    echo "setup-openfx: refusing TESSER_AUDIENCE host off allowlist ($_TESSER_API_HOSTS): $aud" >&2; return 1; }
  _host_in_allowlist "$auth" "$_TESSER_AUTH_HOSTS" || {
    echo "setup-openfx: refusing TESSER_AUTH_URL host off allowlist ($_TESSER_AUTH_HOSTS): $auth" >&2; return 1; }
  export TESSER_BASE_URL="$base" TESSER_AUDIENCE="$aud" TESSER_AUTH_URL="$auth"

  # 2) Tesser workspace creds: already-exported vars win; otherwise parse tesser-credentials*.env
  #    (CLIENT_ID/CLIENT_SECRET) literally — never source it.
  : "${TESSER_API_KEY:=${CLIENT_ID:-${TESSER_CLIENT_ID:-}}}"
  : "${TESSER_API_SECRET:=${CLIENT_SECRET:-${TESSER_CLIENT_SECRET:-}}}"
  if [ -z "${TESSER_API_KEY:-}" ] || [ -z "${TESSER_API_SECRET:-}" ]; then
    local cred
    for cred in ./tesser-credentials*.env; do
      [ -f "$cred" ] || continue
      [ -n "${TESSER_API_KEY:-}" ]    || TESSER_API_KEY="$(_dotenv_get CLIENT_ID "$cred")"
      [ -n "${TESSER_API_SECRET:-}" ] || TESSER_API_SECRET="$(_dotenv_get CLIENT_SECRET "$cred")"
      break
    done
  fi
  [ -n "${TESSER_API_KEY:-}" ]    && export TESSER_API_KEY
  [ -n "${TESSER_API_SECRET:-}" ] && export TESSER_API_SECRET
  if [ -z "${TESSER_API_KEY:-}" ] || [ -z "${TESSER_API_SECRET:-}" ]; then
    echo "setup-openfx: Tesser creds not found — drop tesser-credentials*.env in this dir or export TESSER_API_KEY/TESSER_API_SECRET" >&2
    return 1
  fi

  # 3) OpenFX values from the downloaded key JSON. jq is not a shell, so reading the file can't
  #    execute anything; the multi-line PEM comes through verbatim via `jq -r`.
  local kf
  for kf in ./OpenFX_api-key_*.json; do
    [ -f "$kf" ] || continue
    OPENFX_ORG_ID="$(jq -r '.orgId // empty' "$kf")"
    OPENFX_API_KEY="$(jq -r '.id // empty' "$kf")"
    OPENFX_PRIVATE_KEY="$(jq -r '.privateKey // empty' "$kf")"
    export OPENFX_ORG_ID OPENFX_API_KEY OPENFX_PRIVATE_KEY
    break
  done

  # 4) Webhook signing secret — a plain data line in .env.local (Phase 1b), read literally.
  local ws; ws="$(_dotenv_get OPENFX_WEBHOOK_SECRET "$file")"
  [ -n "$ws" ] && export OPENFX_WEBHOOK_SECRET="$ws"

  return 0
}
