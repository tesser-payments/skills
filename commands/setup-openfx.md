---
description: Onboard your OpenFX liquidity-provider account onto Tesser (semi-automatic provider onboarding)
argument-hint: "[--staging|--prod]"
allowed-tools: Read, Bash, WebFetch
---

Invoke the **`setup-openfx`** skill and follow its procedure exactly to connect the
developer's OpenFX account to Tesser.

Arguments passed to this command: `$ARGUMENTS`

- Target environment defaults to **sandbox** (`--staging` is an alias for sandbox — same environment).
- If `--prod` appears in the arguments, target **production** — and confirm explicitly with the
  developer before issuing any write (credential registration or account creation).

Do not skip the skill's preflight checks, and never execute the credential-write call on the
developer's behalf — that step is generate-only by design (see the skill).
