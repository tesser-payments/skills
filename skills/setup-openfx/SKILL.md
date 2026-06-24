---
name: setup-openfx
description: Use when a developer wants to connect (onboard) their OpenFX liquidity-provider account to Tesser — guides the OpenFX dashboard steps, registers OpenFX credentials, registers bank/wallet accounts (with Tesser and with OpenFX), coordinates VAN setup (Tesser seeds it), and verifies a deposit. Works in sandbox/staging and production. Triggered by /setup-openfx or requests like "onboard OpenFX", "set up OpenFX in prod", "register my OpenFX credentials".
---

# Onboard an OpenFX account onto Tesser

## What this is

Connecting a customer's OpenFX account to Tesser is **semi-automatic / bring-your-own-account**:
the developer does steps in **OpenFX's own dashboard**, then registers credentials and accounts with
**Tesser**. You guide both sides and execute the safe parts; you never run the credential-write call
yourself.

OpenFX is a liquidity provider of the **on/off-ramp** class (`provider_key: "openfx"`). Casing is
always **OpenFX** in prose.

This skill covers **both environments**. The steps are the same except where a step is marked
**🅢 Sandbox/staging** or **🅟 Production** — production additionally requires that the bank and
wallets be registered *with OpenFX* (and the bank passes OpenFX review).

## Tooling (Claude Code and Codex)

This skill is harness-agnostic. It installs the same way in **Claude Code** (`~/.claude/skills/`) and
**Codex** (`~/.agents/skills/`) and is invoked the same way — the user asks to "set up OpenFX on
Tesser" and this skill triggers (Codex also offers `$setup-openfx` / `/skills`). The steps use Claude
Code tool names — map them to your platform (see the repo `AGENTS.md`): `Bash` → your shell,
`Read`/`Write`/`Edit` → native file tools, "fetch live docs" → your web-fetch tool **or** `curl`.
Everything operational here is plain `curl` + `jq`, which works the same everywhere.

## Operating rules (read first)

1. **Fetch, don't trust memory.** Before constructing any Tesser API call, fetch current shapes from
   the live docs in `references/live-sources.md` (web-fetch tool or `curl`). The one exception is the
   internal secrets endpoint, documented in `references/tesser-secrets-endpoint.md` because it is
   intentionally absent from public docs.
2. **Hybrid execution:** read-only calls (auth, `GET`) run automatically; non-secret writes (bank,
   wallet) show the payload, get explicit confirmation, then run; the credential write
   (`POST /v1/organizations/secrets`) is **generate-only — the developer runs it**, never you.
3. **Confirm the environment up front.** Sandbox by default. `--staging` is an alias for sandbox.
   `--prod` targets production — confirm explicitly before any write.
4. **Keep secrets out of shell history and chat.** Load Tesser creds from a dotenv file; read OpenFX
   creds straight from the downloaded key JSON with `jq`; never echo secrets.
5. **Verify every write** with a follow-up `GET`. Evidence before claiming success.

## Environment

| Environment | `BASE_URL` | `AUDIENCE` | `AUTH0_TOKEN_URL` |
|---|---|---|---|
| **Sandbox / staging** (default; `--staging` alias) | `https://sandbox.tesserx.co` | `https://sandbox.tesserx.co` | `https://dev-awqy75wdabpsnsvu.us.auth0.com/oauth/token` |
| **Production** (`--prod`) | `https://api.tesser.xyz` | `https://api.tesser.xyz` | `https://tesser-payments.us.auth0.com/oauth/token` |

> "Staging" means the sandbox environment here — `--staging`/`--sandbox` both resolve to the sandbox
> row. Audience equals base URL in both. Tokens are `client_credentials`, last 24h, no refresh.
> Send `x-api-client: true` on Tesser calls to force snake_case responses (the gateway already sets it
> for API-key auth, but it's harmless to be explicit). A `.env.local` may override `TESSER_BASE_URL` /
> `TESSER_AUDIENCE` / `TESSER_AUTH_URL`.

## Procedure

### Phase 0 — Preflight (auto, read-only)

1. Resolve the target environment from the user's request (or an explicit `--staging`/`--prod`
   argument): sandbox by default (staging = sandbox); production only when the user says prod / passes
   `--prod` — confirm before any write. Honor `TESSER_*` overrides.
2. **Get Tesser credentials from the downloaded API-keys file (no copy-paste).** If `.env.local`
   already has `TESSER_API_KEY`/`TESSER_API_SECRET` (or they're exported, incl. demo-style
   `TESSER_CLIENT_ID`/`TESSER_CLIENT_SECRET`), use those. Otherwise tell the developer to download their
   API keys from the Tesser dashboard → **Settings → API keys** (a dotenv file named
   `tesser-credentials*.env`) and **move it into the working directory**, then parse `CLIENT_ID` →
   `TESSER_API_KEY` and `CLIENT_SECRET` → `TESSER_API_SECRET` (upsert into `.env.local`; never echo;
   ignore the file's `SIGNING_*` fields):
   ```bash
   CREDFILE=$(ls tesser-credentials*.env 2>/dev/null | head -1)
   [ -f "$CREDFILE" ] || echo "Download API keys (dashboard → Settings → API keys) and move tesser-credentials*.env into $(pwd)."
   val(){ grep -E "^$1=" "$CREDFILE" | head -1 | sed -E "s/^$1=//; s/^[\"']//; s/[\"']$//"; }
   touch .env.local
   grep -vE '^TESSER_(API_KEY|API_SECRET)=' .env.local > .env.local.tmp
   { printf 'TESSER_API_KEY=%s\n' "$(val CLIENT_ID)"; printf 'TESSER_API_SECRET=%s\n' "$(val CLIENT_SECRET)"; } >> .env.local.tmp
   mv .env.local.tmp .env.local
   ```
   The file is gitignored (`*.env`); it also holds `SIGNING_*` keys (payment signing) you don't need
   for onboarding — leave them. Then load: `set -a; . ./.env.local; set +a`.
3. Mint a token (audience from the env row) and prove auth with `GET {BASE_URL}/v1/accounts`
   (`-H "x-api-client: true"`). **Capture `workspace_id`** (`.data[0].workspace_id`, or
   `GET /v1/accounts/<id>` → `.data.workspace_id`) — needed for the webhook URL and the VAN seed.
4. Fetch the live OpenAPI / how-tos to confirm current `/v1/accounts/banks` and `/v1/accounts/wallets`
   shapes before any write.
5. **Idempotency check:** if `GET /v1/accounts` already shows a `provider: OPENFX` ledger, OpenFX is
   already onboarded — tell the developer and skip to verification.

> Endpoints use a `/v1` prefix; accounts are typed sub-paths (`/v1/accounts`, `/v1/accounts/banks`,
> `/v1/accounts/wallets`, `/v1/accounts/ledgers`); the credential write is
> `POST /v1/organizations/secrets`.

### Phase 1 — OpenFX credentials (parse the key file + register the webhook)

OpenFX dashboard is `https://app.openfx.com` (use the **production** dashboard for `--prod`). This
phase fills the four `OPENFX_*` values in `.env.local`: three are parsed from the downloaded key file,
the fourth (the webhook secret) is pasted by the developer. Full detail in
`references/openfx-dashboard-steps.md`. Never echo the private key.

**1a. API key file → parse three values.** Tell the developer: in the OpenFX dashboard create an API
key, **download the JSON**, and **move that file into the working directory** (next to `.env.local`;
it's named `OpenFX_api-key_*.json` and is gitignored). Then parse it into `.env.local`:

```bash
KEYFILE=$(ls OpenFX_api-key_*.json 2>/dev/null | head -1)   # the file the developer moved in
[ -f "$KEYFILE" ] || echo "Move your downloaded OpenFX_api-key_*.json into $(pwd) first."
# UPSERT into .env.local — strip any existing/placeholder lines first, then write.
# (.env.local copied from .env.example already has empty OPENFX_*= lines; a naive append
#  would leave duplicates, and skip-if-present would never fill the blanks. Safe to re-run.)
touch .env.local
grep -vE '^OPENFX_(ORG_ID|API_KEY|PRIVATE_KEY)=' .env.local > .env.local.tmp
{
  printf 'OPENFX_ORG_ID=%s\n'      "$(jq -r .orgId "$KEYFILE")"
  printf 'OPENFX_API_KEY=%s\n'     "$(jq -r .id "$KEYFILE")"        # the sandbox_-prefixed key
  printf 'OPENFX_PRIVATE_KEY=%s\n' "$(jq -c .privateKey "$KEYFILE")" # PEM as one \n-escaped line
} >> .env.local.tmp
mv .env.local.tmp .env.local
```
Mapping: `id` → `OPENFX_API_KEY`, `orgId` → `OPENFX_ORG_ID`, `privateKey` → `OPENFX_PRIVATE_KEY`.
(Ignore the file's other fields: `name`, `publicKey`, `scope`, etc.)

**1b. Webhook secret → display the URL, then paste it in.** The webhook secret is **not** in the file
— OpenFX issues it when you register a webhook. Show the developer the **literal URL** to register
(built from the Phase 0 `workspace_id`):

```
{BASE_URL}/v1/webhooks/openfx/{workspaceId}
```
e.g. sandbox → `https://sandbox.tesserx.co/v1/webhooks/openfx/<workspaceId>`. Tell them: in the OpenFX
dashboard create a webhook with **All Events** pointed at that URL, copy the **Signing Key** it
returns, and add it to `.env.local` as `OPENFX_WEBHOOK_SECRET=<paste>`.

> **Webhook route status:** 404'd on both prod and sandbox when probed 2026-06-23, but **sandbox
> deposits completed end-to-end on 2026-06-24** (deliveries now processed) — the sandbox route is
> resolved. **Production delivery still to be confirmed.** Either way, register the webhook here to
> obtain the Signing Key. See `references/openfx-dashboard-steps.md`.

### Phase 2 — Store the OpenFX credentials with Tesser (GENERATE ONLY — developer runs it)

After Phase 1, all four `OPENFX_*` values are in `.env.local`, so build the request from the
**`.env.local` form** in `references/tesser-secrets-endpoint.md` (it sources `.env.local` and posts the
bundle — nothing sensitive is typed). Present it for the developer to run — do not run it yourself.
Tell them:

- Expected: `{ "success": true, "maskedValue": "****" }` (camelCase — this internal endpoint's
  response bypasses snake_case conversion; verified live 2026-06-24).
- Side effect: Tesser onboards the **"OpenFX Ledger"** (probes balances via the Basis Theory reactor);
  on success it shows real balances.
- `400` code **`secrets-0002`** = already configured (not a failure; delete the vault record to rotate).
- PEM must keep its `-----BEGIN/END … PRIVATE KEY-----` markers; literal `\n` is normalized server-side.

**🅟 Production prereq:** the Basis Theory reactor must already be configured on the backend, or
OpenFX calls fail with `vault-0030`. (Prod is configured; relevant only if errors appear.)

Confirm success (developer pastes back the masked value) before continuing.

### Phase 3 — Register the funding bank (Tesser + OpenFX)

The funding bank must exist on **both** sides with the **same exact values** — Tesser matches your
registered bank against an OpenFX-registered fiat account, so any field mismatch breaks the match.

> **One funding bank per workspace.** A second `POST /v1/accounts/banks` returns
> `400 accounts-3001` ("A workspace-level bank account already exists. Only one is allowed per
> workspace."). Accounts are **`GET`/`PATCH` only — no delete** (`/v1/accounts/{id}`), so to change
> the funding bank (e.g. switch currency) you `PATCH` the existing one, not create another.

- **🅢 Sandbox/staging:** ask the developer **which currency** they want, then register the matching
  pre-seeded sandbox bank with Tesser (`POST {BASE_URL}/v1/accounts/banks`) using the values in
  `references/sandbox-bank-accounts.md`. Those mirror OpenFX's sandbox accounts, so the OpenFX side is
  **already in place** — no dashboard step. **MXN** is the validated currency. Execute-with-confirmation
  (you authorized sandbox runs); verify with `GET {BASE_URL}/v1/accounts/{id}`.
- **🅟 Production:** the developer supplies their **real** bank details and must do **both**:
  1. register the bank with Tesser (`POST /v1/accounts/banks`), **and**
  2. add the **same exact values** in the **OpenFX dashboard** (as a fiat funding/withdrawal account).

  OpenFX **reviews** it — a hard gate: until the bank is **accepted**, deposits won't plan/settle. The
  two registrations must match exactly (name, bank name, code type, identifier, account number, SWIFT)
  or Tesser can't match the bank to the OpenFX account.

### Phase 4 — Register destination wallet(s) (wallet flows only)

Skip if the customer only pre-funds the OpenFX ledger (no on-chain leg).

1. **With Tesser:** `POST {BASE_URL}/v1/accounts/wallets` (`is_managed: false` for self-custodial).
2. **With OpenFX** (dashboard): add each wallet as an approved withdrawal address.
   - **🅟 Production — required, per network:** no default address is allowed. Copy each managed
     wallet's `crypto_wallet_address` (`GET /v1/accounts/<wallet-id>`) and add it on the OpenFX
     dashboard **for every network you intend to use** (Base, Ethereum, Polygon, … per OpenFX's list).
   - **🅢 Sandbox/staging:** pre-approve the address(es) in the dashboard.

### Phase 5 — VAN (Tesser-internal step)

The deposit flow **looks up** a VAN (`findVan` matches `provider=OPENFX` + currency); it never creates
one, and there's **no public/admin API** to register one. So this step is **done by Tesser**, not the
customer: the customer **discovers** the VAN details on the OpenFX dashboard (initiate a deposit for
the currency → OpenFX shows the receiving bank, account number/CLABE, beneficiary, van id) and hands
them to their Tesser contact, who **seeds** the VAN row.

- **If you are the customer/integrator:** collect the VAN details and your `workspace_id`, then ask
  Tesser to seed it. You're done with this phase once Tesser confirms.
- **If you are a Tesser operator:** use the **`openfx-van-seeding`** skill (Tesser-internal; requires
  DB access). It also covers the sandbox source-bank lazy-match stub.
- **🅟 Production:** VAN discovery may be gated behind source-bank acceptance (Phase 3) — revisit once
  cleared.

### Phase 6 — Test a deposit (two steps, in order)

Prereqs: creds stored (2), funding bank registered (3) — with an `account_number` matching an OpenFX
fiat withdrawal address (Tesser matches **on account number, at deposit time** — `metadata.openfx`
won't populate before this), VAN seeded (5), and — for an on-ramp to chain — a destination wallet (4).
Run **two deposits in order**, and confirm the first before attempting the second:

1. **Step A — fiat → same fiat** (e.g. **USD → USD**): lands fiat in the OpenFX ledger, no swap.
   Proves the wire → VAN → ledger plumbing before adding complexity.
2. **Step B — fiat → USDC** (e.g. **USD → USDC**): adds the on-ramp (swap to stablecoin). Only after
   Step A confirms.

Create the deposit — `<currency>` is your funding-bank currency; `to.currency` is the **same fiat**
for Step A or `USDC` for Step B; `to.account_id` is the OpenFX Ledger (or a wallet for on-ramp-to-chain):
```bash
curl -sS -X POST "{BASE_URL}/v1/treasury/deposits" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" -H "content-type: application/json" \
  -d '{ "desired": {
          "from": { "account_id": "<funding-bank-id>", "amount": "<amount>", "currency": "<currency>" },
          "to":   { "account_id": "<openfx-ledger-id>", "currency": "<same-fiat | USDC>" } } }' | jq .
```
Then `GET /v1/treasury/deposits/{id}` (planned steps) and `…/{id}/instructions` (the VAN wire details).

**Trigger the inbound funds** (the manual step that actually starts the flow):
- **🅢 Sandbox/staging:** in the **OpenFX dashboard → Balances → Deposit funds**, **simulate** a mock
  deposit for that currency/amount — it fires the `deposits` webhook like a real wire. (There is **no
  Tesser-side simulate** for OpenFX; `/v1/treasury/deposits/{id}/simulate` is Circle-only.)
- **🅟 Production:** send a **real transfer/wire** to the VAN details from `…/{id}/instructions`.

OpenFX then fires the `deposits` webhook → Tesser credits the ledger (Step A complete) → for Step B the
swap runs (and, to a wallet, the on-chain withdrawal follows). Confirm via `GET /v1/treasury/deposits/{id}`
reaching completion and the OpenFX ledger balance, **before** moving from Step A to Step B.

- `amount` must clear OpenFX's per-currency minimum (e.g. **MXN ≥ 1000**) or `/trade` 400s.
- On-ramp **to a self-custodial wallet**: set `to.account_id` to the wallet and add `"network"`
  (sandbox testnets e.g. `BASE_SEPOLIA`; prod mainnets e.g. `BASE`).
- **✅ Validated end-to-end in sandbox (2026-06-24):** Step A (USD→USD) and Step B (USD→USDC, with the
  swap leg) both reached `completed` — `100 USD → 99.9925 USDC`, all steps `completed`. The webhook
  that 404'd on 2026-06-23 is now delivered/processed in sandbox. **Production delivery still to be
  confirmed.** `/v1/treasury/deposits/{id}/simulate` remains Circle-only (OpenFX uses the dashboard
  simulate / a real wire).

## Error handling

| Condition | What to do |
|---|---|
| Missing `TESSER_API_KEY`/`SECRET` (or `CLIENT_ID`/`SECRET`) | Stop; env-setup guidance |
| Auth `401` | Stop; check key/secret and audience-vs-environment |
| Duplicate secret `400` (code `secrets-0002`) | Already onboarded; skip to verification |
| `vault-0030` after secret write | Basis Theory reactor not configured on backend (esp. non-prod) |
| Malformed PEM | Fix `-----BEGIN/END … PRIVATE KEY-----` markers and `\n` |
| Deposit `DEPOSIT_VAN_NOT_FOUND` | VAN not seeded for this workspace+currency (Phase 5) |
| 🅟 Deposit won't plan/settle | Source bank not yet **accepted** by OpenFX (Phase 3) |
| Deposit stalls after planning (steps stuck `created`) | OpenFX webhook not being delivered. Sandbox route resolved 2026-06-24 (deposits complete); if it recurs, confirm `/v1/webhooks/openfx/{workspaceId}` is deployed for the env (prod unconfirmed) |
| Offline (can't fetch live docs) | Proceed with embedded secrets contract; verify account shapes when back online |

## References

- `references/openfx-dashboard-steps.md` — OpenFX dashboard: API key JSON, webhook, bank/wallet registration.
- `references/tesser-secrets-endpoint.md` — internal `POST /v1/organizations/secrets` contract.
- `references/live-sources.md` — live docs to fetch (auth, accounts, deposits, OpenAPI, OpenFX docs).
- `../openfx-van-seeding/SKILL.md` — **Tesser-internal** VAN seeding (operators only; the customer
  just discovers the VAN details and hands them to Tesser).
