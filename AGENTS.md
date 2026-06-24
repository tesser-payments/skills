# Tesser Skills — agent guide (Claude Code, Codex, and other harnesses)

Cross-harness plugin of agentic skills for the [Tesser Payments Platform](https://docs.tesser.xyz).
Skill content lives in `skills/` and is harness-agnostic.

## Install (follow this when asked to install)

Clone (or update) the repo to a stable path, then install **only** the customer-facing
`setup-openfx` skill for whichever agent you are.

```bash
git clone https://github.com/tesser-payments/skills.git ~/.tesser-skills 2>/dev/null \
  || git -C ~/.tesser-skills pull --ff-only
```

Both harnesses discover **skills** in a personal skills directory, so the install is the *same shape*
in each — symlink the cloned skill into that dir (the symlink means `git pull` keeps it current). Only
the directory differs:

**Claude Code** → `~/.claude/skills/`:
```bash
mkdir -p ~/.claude/skills
ln -sfn ~/.tesser-skills/skills/setup-openfx ~/.claude/skills/setup-openfx
```

**Codex** → `~/.agents/skills/`:
```bash
mkdir -p ~/.agents/skills
ln -sfn ~/.tesser-skills/skills/setup-openfx ~/.agents/skills/setup-openfx
```

> Don't use `~/.codex/prompts/` (Codex) or `~/.claude/commands/` (Claude Code) for this — those are a
> different, non-symmetric "command/prompt" mechanism. The skills dir above is the right, uniform route.
> (Claude Code users who specifically want a `/setup-openfx` slash command can use the native
> marketplace instead — see the note below.)

### What to tell the user (default)

**Do NOT mention `openfx-van-seeding` or any "internal" skill** — it's Tesser-internal and only
confuses customers. Skip it silently. Present this summary, filling in the harness and the matching
restart line:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅  Tesser OpenFX onboarding is installed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  📦  Repo      ~/.tesser-skills
  🔌  Harness   <Claude Code | Codex>

  Next steps
  ─────────
  1.  Restart your session   →  <restart line>
  2.  Add credentials        →  cp ~/.tesser-skills/.env.example .env.local
                                 then fill in TESSER_API_KEY + TESSER_API_SECRET
  3.  Run it                 →  <invoke line>        (sandbox by default; --prod for production)
```

Fill the **restart line** and **invoke line** from the row matching your harness — be explicit, since
the invocation differs by tool and "restart the session" alone isn't enough:

| Harness | Restart line | Invoke line |
|---|---|---|
| **Claude Code** | `Quit Claude Code — Ctrl-C twice (or /exit) — then run "claude" again.` | `Say: "set up OpenFX on Tesser" (the skill triggers automatically).` |
| **Codex** | `Quit Codex — Ctrl-C twice (or Ctrl-D) — then run "codex" again.` | `Type $setup-openfx (or open /skills), or say "set up OpenFX on Tesser".` |

Both invoke the same way by intent — *"set up OpenFX on Tesser"* triggers the skill in either tool.
Codex adds the `$setup-openfx` / `/skills` shortcuts; for a Claude Code `/setup-openfx` slash command,
use the native marketplace install (below).

> Claude Code users can instead use the native marketplace:
> `/plugin marketplace add tesser-payments/skills` then `/plugin install tesser-skills@tesser-skills`.

### Tesser operators only (opt-in)

Only if the user **explicitly identifies as a Tesser employee/operator** (or asks for internal
tooling): additionally tell them the internal **`openfx-van-seeding`** skill lives at
`~/.tesser-skills/skills/openfx-van-seeding/SKILL.md` and is run directly from the clone (it needs
Tesser DB access). Do not copy it into `~/.claude`/`~/.codex`. In every other case, do not mention it.

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
