# Tesser Skills

Agentic skills for onboarding onto and operating the [Tesser Payments
Platform](https://docs.tesser.xyz). Works in **Claude Code** and **Codex**.

## Quick start

Paste this into **Claude Code or Codex** (works in either):

```text
Install the Tesser setup-openfx skill: clone https://github.com/tesser-payments/skills into
~/.tesser-skills, then follow the "Install" section of ~/.tesser-skills/AGENTS.md for whichever
agent you are. Tell me to restart when it's done.
```

The agent clones the repo and installs the skill the same way in either tool (symlinked into your
agent's skills directory), then tells you how to restart. After restarting, just **ask your agent to
"set up OpenFX on Tesser"** — the skill triggers in both Claude Code and Codex. (Codex also has the
`$setup-openfx` / `/skills` shortcuts.) You'll need a Tesser workspace API key + secret in a
`.env.local` first — see [Prerequisites](#prerequisites).

> **Harness support:** this prompt has been tested with **Claude Code** and **Codex**, but it's written
> to be **harness-agnostic** — it relies only on cloning the repo and following `AGENTS.md`, so any
> agent that can run a shell and read files should be able to install and run the skill. If your
> harness needs different steps, see the tool-name mapping in [`AGENTS.md`](./AGENTS.md).


## Commands

| Command | What it does |
|---|---|
| `/setup-openfx` | Connect your **OpenFX** liquidity-provider account to Tesser end-to-end: store OpenFX credentials, register your funding bank and wallet(s), coordinate the deposit VAN, and verify a deposit. Covers **sandbox/staging** and **production**. |

## Onboarding at a glance

OpenFX onboarding is **bring-your-own-account**: you do some steps in OpenFX's dashboard, the skill
does the Tesser API calls, and one step is Tesser-assisted. The skill walks all of it; this is the map.

| # | Step | Where / who |
|---|------|-------------|
| 1 | Authenticate, find your workspace id | Tesser API (skill, automatic) |
| 2 | Create an OpenFX API key + register a webhook | **OpenFX dashboard** (you) |
| 3 | Store the OpenFX credential bundle | Tesser API — **you run** the generated call (private key never leaves your hands) |
| 4 | Register funding bank + wallet(s) | Tesser API (skill) **and** OpenFX dashboard (you). **Production reviews these.** |
| 5 | Deposit VAN | **Tesser-assisted** (handled by Tesser staff out of band). Sandbox: just tell Tesser your workspace + currency and they create it. Production: you fetch the VAN details from OpenFX, Tesser seeds them |
| 6 | Test a deposit — first fiat→fiat (e.g. USD→USD), then fiat→USDC | Tesser API creates it; **you** trigger the funds: OpenFX dashboard *simulate* (sandbox) or a *real wire* (prod) |

<details>
<summary>Install by hand (or Claude Code's native marketplace)</summary>

The [Quick start](#quick-start) prompt is the easy path; the exact steps it follows live in
[`AGENTS.md`](./AGENTS.md) (clone to `~/.tesser-skills`, then copy `setup-openfx` into your agent's
skills/prompts dir).

**Claude Code (native marketplace):**
```
/plugin marketplace add tesser-payments/skills
/plugin install tesser-skills@tesser-skills
```

**Any other agent:** point it at `skills/setup-openfx/SKILL.md`. Everything operational is plain
`curl` + `jq`.
</details>

## Prerequisites

- **Claude Code or Codex** (or any agent that reads skill files).
- **Tesser API keys file** — download it from the Tesser dashboard → **Settings → API keys** (a
  `tesser-credentials*.env` file) and drop it in your working directory. The skill reads
  `CLIENT_ID`/`CLIENT_SECRET` from it for you (parsed as data, never executed) — no copy-paste.
  (Already have creds? Exported env vars or demo-style `TESSER_CLIENT_ID`/`TESSER_CLIENT_SECRET` /
  `TESSER_API_KEY`/`TESSER_API_SECRET` all work too.)
- **OpenFX API key file** — downloaded from the OpenFX dashboard (Phase 1); the skill parses it the
  same way. You bring your own OpenFX account.

Both downloaded credential files are gitignored (`*.env`, `OpenFX_api-key_*.json`) — they won't be
committed. Delete them once onboarding is done.

## Usage

Invoke it the same way in either tool — **ask your agent to "set up OpenFX on Tesser"** (in Codex you
can also type `$setup-openfx` or pick it from `/skills`).

### How the skill picks the environment

**The skill asks you, up front.** Its first step is to ask whether you're onboarding **sandbox/staging**
or **production** — it does not guess or default. (If you used the slash command with `--staging`/`--prod`,
that answers the question and the skill just confirms it back.) It then states the target and **confirms
again before any production write**, so you can't hit prod by accident.

```
/setup-openfx              → the skill asks: sandbox/staging or production?
/setup-openfx --staging    → sandbox/staging  (staging == the sandbox environment)
/setup-openfx --prod       → production  (the skill confirms before any write)
```

### Sandbox runs commands for you (confirming each step); production tells you what to run

- **Sandbox/staging:** once your credentials are loaded, the skill **runs the onboarding API calls for
  you** — auth, the credential write, account registration, the deposit tests — but it **previews each
  write and waits for your go-ahead first**, so you see every step. You approve rather than copy-paste.
- **Production:** the skill **does not execute writes** — it **outputs the exact commands for you to
  run**. The sensitive credential write is generate-only (you run it, so your ES256 private key and
  workspace token stay in your hands), and any other write happens only after your explicit confirmation.

### Production-only requirements

Same flow as sandbox, with these additions in production (the skill flags each):

- Your **funding bank** must be registered with OpenFX and pass **OpenFX review** (a hard gate —
  deposits won't settle until accepted).
- Each **destination wallet** must be approved on OpenFX **per network** (no default address).

## Current limitations

Two pieces are not yet self-serve — the skill calls them out and tells you what to do:

- **Deposits are validated in sandbox; production delivery unconfirmed.** As of 2026-06-24, sandbox
  deposits complete end-to-end (fiat→fiat and fiat→USDC on-ramp). The OpenFX webhook route that
  previously 404'd is resolved in sandbox; **confirm it's deployed in production** before relying on
  prod deposit completion.
- **VAN registration is Tesser-assisted.** There's no public API for it yet. In **sandbox** you just
  tell Tesser which workspace and currency you need, and Tesser creates the VAN — you don't supply any
  details. In **production** you fetch the VAN deposit details from the OpenFX dashboard and hand them
  to Tesser, who seeds them. (The seeding is a Tesser-internal, DB-level operation handled by staff out
  of band — it's not part of this repo.)

After onboarding, see [Deposit funds via a liquidity
provider](https://docs.tesser.xyz/how-tos/deposit-funds-via-a-liquidity-provider).

## Security

- **Production is generate-only.** `/setup-openfx` never runs the credential-write call for you in
  production — you run it yourself, with your own workspace token, so your ES256 private key stays in
  your hands. In **sandbox/staging** it runs writes for you but **previews each one and waits for your
  go-ahead** first.
- **Credentials are parsed, never executed.** The skill reads your downloaded credential files and
  `.env.local` as plain `KEY=value` data via its helper (`scripts/dotenv.sh`) — it does **not**
  `source`/execute them, so a malformed or planted file in your working directory can't run code. The
  ES256 private key is read straight from the OpenFX key JSON with `jq`, is never written to
  `.env.local`, and is never echoed to the chat or shell history.
- **Endpoints are pinned.** The skill only ever sends your credentials to the Tesser/Auth0 hosts on a
  fixed allowlist; an override pointing anywhere else aborts the load rather than leaking the key.
- **Nothing secret is committed.** Your downloaded files are gitignored (`*.env`,
  `OpenFX_api-key_*.json`) and `.env.local` is `chmod 600`. Delete the downloaded files once onboarding
  is done.
