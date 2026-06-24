# Tesser Skills

Agentic skills for onboarding onto and operating the [Tesser Payments
Platform](https://docs.tesser.xyz). Works in **Claude Code** and **Codex** (and any agent that can read
a skill file — see [`AGENTS.md`](./AGENTS.md)).

## Commands

| Command | What it does |
|---|---|
| `/setup-openfx` | Connect your **OpenFX** liquidity-provider account to Tesser end-to-end: store OpenFX credentials, register your funding bank and wallet(s), seed the deposit VAN, and verify a deposit. Covers **sandbox/staging** and **production**. |

## Onboarding at a glance

OpenFX onboarding is **bring-your-own-account**: you do some steps in OpenFX's dashboard, the skill
does the Tesser API calls, and one step is Tesser-assisted. The skill walks all of it; this is the map.

| # | Step | Where / who |
|---|------|-------------|
| 1 | Authenticate, find your workspace id | Tesser API (skill, automatic) |
| 2 | Create an OpenFX API key + register a webhook | **OpenFX dashboard** (you) |
| 3 | Store the OpenFX credential bundle | Tesser API — **you run** the generated call (private key never leaves your hands) |
| 4 | Register funding bank + wallet(s) | Tesser API (skill) **and** OpenFX dashboard (you). **Production reviews these.** |
| 5 | Discover + seed the deposit VAN | OpenFX dashboard (you) + **Tesser-assisted** (needs Tesser DB access today) |
| 6 | Create a test deposit | Tesser API (skill) |

## Install

**Claude Code** — add this repository as a plugin marketplace, then install:

```
/plugin marketplace add tesser-xyz/skill
/plugin install tesser-skills@tesser-skills
```

**Codex** — Codex has no "install from a URL" command (unlike Claude Code's marketplace), so you first
get the repo locally, then either run it in-repo or register a slash command.

1. **Clone it** (or download the ZIP from GitHub's green **Code** button and unzip):
   ```bash
   git clone https://github.com/tesser-xyz/skill.git
   cd skill
   ```
2. **Either** — run it in-repo (simplest). Start Codex from the clone and ask:
   ```bash
   codex
   ```
   > set up OpenFX on Tesser

   Codex auto-reads this repo's `AGENTS.md`, which points at `skills/setup-openfx/SKILL.md`.

   **Or** — register a reusable `/setup-openfx` slash command (works from any directory). Codex loads
   custom prompts from `~/.codex/prompts/`:
   ```bash
   mkdir -p ~/.codex/prompts
   printf 'Read and follow the setup-openfx skill at %s/skills/setup-openfx/SKILL.md to onboard an OpenFX account onto Tesser. Default to sandbox; pass --prod for production.\n' "$(pwd)" \
     > ~/.codex/prompts/setup-openfx.md
   ```
   (Run that from inside the clone so `$(pwd)` becomes the absolute path.) Then `/setup-openfx` is
   available in Codex.

`.codex-plugin/plugin.json` ships a manifest for any future native Codex plugin loader, but it is not
required for the steps above. See [`AGENTS.md`](./AGENTS.md) for the Claude Code→Codex tool mapping.

**Other agents** — point them at `skills/setup-openfx/SKILL.md` and ask them to "set up OpenFX on
Tesser." Everything operational is plain `curl` + `jq`.

## Prerequisites

- **Claude Code or Codex** (or any agent that reads skill files).
- A Tesser **workspace API key and secret**. Put them in a gitignored **`.env.local`** (not exported)
  so secrets stay out of your shell history — copy `.env.example`:
  ```bash
  cp .env.example .env.local   # then edit it:
  #   TESSER_API_KEY=...
  #   TESSER_API_SECRET=...
  ```
  The skill sources this file at startup. Exported env vars and the demo-style
  `TESSER_CLIENT_ID` / `TESSER_CLIENT_SECRET` names also work.
- An **OpenFX account** with dashboard access (sandbox or production).

## Usage

```
/setup-openfx            # sandbox (default)
/setup-openfx --staging  # alias for sandbox — "staging" is the sandbox environment
/setup-openfx --prod     # production (you'll confirm before any write)
```

The skill runs read-only checks automatically, asks for confirmation before any write, and — for the
sensitive credential step — hands you a ready-to-run command to execute yourself.

### Sandbox vs production

Same flow, with these production-only additions (the skill flags each):

- Your **funding bank** must be registered with OpenFX and pass **OpenFX review** (a hard gate —
  deposits won't settle until accepted).
- Each **destination wallet** must be approved on OpenFX **per network** (no default address).

## Current limitations

Two pieces are not yet self-serve — the skill calls them out and tells you what to do:

- **Deposit completion is blocked pending a Tesser platform change.** The OpenFX webhook route is not
  deployed (returns 404 in both production and sandbox), so a deposit plans but does not complete yet.
  Onboarding (credentials, accounts, VAN) still completes; **contact Tesser** about deposit timing.
- **VAN registration is Tesser-assisted.** There's no public API for it yet — you discover the VAN
  details on the OpenFX dashboard and hand them to Tesser, who seeds it for your workspace. (The
  seeding itself is a Tesser-internal operation; the `openfx-van-seeding` skill in this repo is for
  Tesser employees only and requires Tesser database access.)

After onboarding, see [Deposit funds via a liquidity
provider](https://docs.tesser.xyz/how-tos/deposit-funds-via-a-liquidity-provider).

## Security

`/setup-openfx` never runs the credential-write call for you. You run it yourself, with your own
workspace token, to store your own OpenFX credentials — your ES256 private key stays in your hands.
Credentials are loaded from `.env.local` or read directly from your downloaded OpenFX key file, never
typed into the chat or shell history.
