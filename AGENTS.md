# Tesser Skills — agent guide (Claude Code, Codex, and other harnesses)

This repo is a cross-harness plugin of agentic skills for the [Tesser Payments
Platform](https://docs.tesser.xyz). The skill content lives in `skills/` and is harness-agnostic; each
harness loads it through its own manifest.

## Harness wiring

| Harness | How to install / invoke |
|---|---|
| **Claude Code** | Installs from GitHub directly: `/plugin marketplace add tesser-xyz/skill` → `/plugin install tesser-skills@tesser-skills`. Slash command `/setup-openfx`. |
| **Codex** | No remote install — `git clone` the repo, then run Codex in it and ask *"set up OpenFX on Tesser"* (Codex auto-reads this `AGENTS.md`), or register a `/setup-openfx` prompt in `~/.codex/prompts/`. Full steps in the README. `.codex-plugin/plugin.json` is a manifest for a future native loader, not required today. |
| **Other agents** | Read `skills/setup-openfx/SKILL.md` and follow it. |

## Skills

- **`setup-openfx`** — onboard an OpenFX liquidity-provider account onto Tesser (credentials, bank +
  wallet registration, VAN coordination, deposit verification). Covers **sandbox/staging** and
  **production**. Customer-facing. See `skills/setup-openfx/SKILL.md`.
- **`openfx-van-seeding`** — 🔒 **Tesser employees only.** Internal operations step to seed a
  customer's OpenFX VAN; requires Tesser DB access. Not for customers/integrators. See
  `skills/openfx-van-seeding/SKILL.md`.

## Tool-name mapping (skills use Claude Code names)

When a skill says: | use your platform's: |
|---|---|
| `Bash` | shell / exec tool |
| `Read` / `Write` / `Edit` | native file tools |
| "fetch live docs" / `WebFetch` | your web-fetch tool, **or** `curl` |
| `Skill` (invoke a skill) | just follow the skill instructions |

Everything operational in `setup-openfx` is plain `curl` + `jq` + `psql`, so it runs the same in any
harness. The skill has no subagent/parallelism requirements.

## Conventions

- "OpenFX" is always cased that way in prose; provider key is `openfx`.
- Never put customer codenames in anything shipped here — write generically for any customer.
- Source-of-truth order: Tesser docs → Tesser platform code (`~/code/platform`) → OpenFX onboarding
  runbooks. Verify endpoints against live docs before constructing calls.
