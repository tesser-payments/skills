# CLAUDE.md — `tesser-skills` plugin repo

This repo is a **cross-harness plugin** (`tesser-skills`) that ships agentic skills for onboarding onto
and operating the [Tesser Payments Platform](https://docs.tesser.xyz). It is distributed to
customers' developers, who install it and run its commands in their own environment. It targets
**Claude Code** (`.claude-plugin/`, `commands/`) and **Codex** (`.codex-plugin/`); the shared skill
content in `skills/` is harness-agnostic. See `AGENTS.md` for the tool-name mapping.

## Layout

```
.claude-plugin/      # Claude Code manifest + marketplace.json
.codex-plugin/       # Codex manifest (skills: ./skills/)
AGENTS.md            # cross-harness guide + Claude Code→Codex tool-name mapping
commands/
  setup-openfx.md    # /setup-openfx — thin entrypoint that invokes the setup-openfx skill
skills/
  setup-openfx/      # customer-facing onboarding procedure (sandbox/staging + production)
    SKILL.md
    references/      # progressive-disclosure docs: openfx-dashboard-steps · tesser-secrets-endpoint · live-sources
  openfx-van-seeding/ # 🔒 Tesser-internal: seed a customer's VAN (needs DB access; not for customers)
    SKILL.md
```

## Authoring principles

- **SKILL.md is the manifest; references hold depth.** Keep essentials and triggers in `SKILL.md`;
  push deep detail into `references/` loaded only when needed (progressive disclosure).
- **Fetch, don't replicate.** For anything in Tesser's public docs, instruct the agent to fetch live
  sources (`docs.tesser.xyz/llms-full.txt`, OpenAPI) rather than copying prose that will drift. Embed
  only what an agent cannot fetch — currently the internal `POST /v1/organizations/secrets` contract and
  the manual OpenFX-dashboard steps.
- **Skill steers, the platform executes.** The skill supplies judgment and procedure. v1 executes via
  curl/SDK; MCP-first execution (for the non-secret steps) is a planned fast-follow.
- **Never auto-run the credential write.** `POST /v1/organizations/secrets` is generate-only — the
  developer runs it with their own token. See `skills/setup-openfx/references/tesser-secrets-endpoint.md`.

## Source-of-truth hierarchy

When facts conflict, prefer in this order:

1. **Tesser docs** — `https://docs.tesser.xyz` (`llms-full.txt`, OpenAPI). Primary.
2. **Tesser platform code** — `~/code/platform` (the secrets contract, `/v1` routes, the
   `/v1/webhooks/openfx/:workspaceId` handler). Secondary.
3. **OpenFX integration handoff** — `~/Documents/openfx 2` (written by the original integration
   engineer). Tertiary — best for OpenFX-side dashboard specifics that 1 and 2 don't cover. It is
   written for **local backend development** (ngrok, Basis Theory reactor, VAN seeding); take the
   OpenFX dashboard facts from it, not the local-dev plumbing.

## Design docs

- Spec: `~/code/plans/skill/superpowers/specs/2026-06-16-setup-openfx-skill-design.md`
- Origin decision: `platform/docs/adr/0001-openfx-onboarding-as-agent-skill.md`
- Domain language: `platform/CONTEXT.md` (OpenFX, provider onboarding, on/off-ramp).

## Conventions

- OpenFX is always cased **OpenFX** in prose; the provider key is `openfx`.
- Never put customer codenames in anything shipped here — write generically for any customer.
- New provider commands (e.g. a future `/setup-circle`) should copy the command + skill + references
  pattern established by `setup-openfx`.
