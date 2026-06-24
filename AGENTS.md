# Tesser Skills — agent guide (Claude Code, Codex, and other harnesses)

Cross-harness plugin of agentic skills for the [Tesser Payments Platform](https://docs.tesser.xyz).
Skill content lives in `skills/` and is harness-agnostic.

## Install (follow this when asked to install)

Assume this repo is cloned at `~/.tesser-skills`. If it isn't, clone it (or update it):

```bash
git clone https://github.com/tesser-payments/skills.git ~/.tesser-skills 2>/dev/null \
  || git -C ~/.tesser-skills pull --ff-only
```

Then install **only the customer-facing `setup-openfx` skill** for whichever agent you are:

**Claude Code** — copy the skill + command into the personal dirs Claude Code auto-discovers:
```bash
mkdir -p ~/.claude/skills ~/.claude/commands
cp -R ~/.tesser-skills/skills/setup-openfx ~/.claude/skills/
cp ~/.tesser-skills/commands/setup-openfx.md ~/.claude/commands/setup-openfx.md
```

**Codex** — register a `/setup-openfx` slash command pointing at the cloned skill:
```bash
mkdir -p ~/.codex/prompts
printf 'Read and follow ~/.tesser-skills/skills/setup-openfx/SKILL.md to onboard an OpenFX account onto Tesser. Default to sandbox; pass --prod for production.\n' \
  > ~/.codex/prompts/setup-openfx.md
```

Do **not** install `openfx-van-seeding` (Tesser-internal; see below). Finish by telling the user to
restart the session so `/setup-openfx` loads.

> Claude Code users can instead use the native marketplace:
> `/plugin marketplace add tesser-payments/skills` then `/plugin install tesser-skills@tesser-skills`.

## Skills

- **`setup-openfx`** — onboard an OpenFX liquidity-provider account onto Tesser (credentials, bank +
  wallet registration, VAN coordination, deposit verification). Covers **sandbox/staging** and
  **production**. Customer-facing. See `skills/setup-openfx/SKILL.md`.
- **`openfx-van-seeding`** — 🔒 **Tesser employees only.** Internal operations step to seed a
  customer's OpenFX VAN; requires Tesser DB access. Not for customers/integrators. See
  `skills/openfx-van-seeding/SKILL.md`.

## Tool-name mapping (skills use Claude Code names)

| When a skill says | use your platform's |
|---|---|
| `Bash` | shell / exec tool |
| `Read` / `Write` / `Edit` | native file tools |
| "fetch live docs" / `WebFetch` | your web-fetch tool, **or** `curl` |
| `Skill` (invoke a skill) | just follow the skill instructions |

Everything operational in `setup-openfx` is plain `curl` + `jq`, so it runs the same in any harness.
The skill has no subagent/parallelism requirements.

## Conventions

- "OpenFX" is always cased that way in prose; provider key is `openfx`.
- Never put customer codenames in anything shipped here — write generically for any customer.
- Source-of-truth order: Tesser docs → Tesser platform code (`~/code/platform`) → OpenFX onboarding
  runbooks. Verify endpoints against live docs before constructing calls.
