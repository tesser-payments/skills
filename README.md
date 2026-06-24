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

<sub>Tesser operators: append "I'm a Tesser operator" to the prompt to also surface the internal VAN-seeding tooling.</sub>

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
| 5 | Discover + seed the deposit VAN | OpenFX dashboard (you) + **Tesser-assisted** (needs Tesser DB access today) |
| 6 | Create a test deposit | Tesser API (skill) |

<details>
<summary>Install by hand (or Claude Code's native marketplace)</summary>

The [Quick start](#quick-start) prompt is the easy path; the exact steps it follows live in
[`AGENTS.md`](./AGENTS.md) (clone to `~/.tesser-skills`, then copy `setup-openfx` into your agent's
skills/prompts dir). Those steps install only the customer-facing `setup-openfx` skill;
`openfx-van-seeding` is Tesser-internal and intentionally left out.

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

Invoke it the same way in either tool — **ask your agent to "set up OpenFX on Tesser"** (in Codex you
can also type `$setup-openfx` or pick it from `/skills`). Mention the environment, which the skill maps
to its argument:

```
"set up OpenFX"            → sandbox (default)
"set up OpenFX on staging" → sandbox (staging is the sandbox environment)
"set up OpenFX in prod"    → production (you'll confirm before any write)
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
