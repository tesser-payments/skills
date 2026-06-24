---
description: Onboard your OpenFX liquidity-provider account onto Tesser (semi-automatic provider onboarding)
argument-hint: "[--staging|--prod]"
allowed-tools: Read, Bash, WebFetch
---

Invoke the **`setup-openfx`** skill and follow its procedure exactly to connect the
developer's OpenFX account to Tesser.

Arguments passed to this command: `$ARGUMENTS`

- **If no `--staging`/`--prod` flag is given, ask the developer which environment** (sandbox/staging or
  production) as the first step — don't default. `--staging` is an alias for sandbox (same environment).
- If `--staging` or `--prod` is present, take it as the answer and confirm it back. For `--prod`,
  confirm explicitly with the developer again before issuing any write (credential registration or
  account creation).

Do not skip the skill's preflight checks. Follow the skill's execution model: in **sandbox/staging**
it runs the onboarding API calls (including the credential write), but **previews each write and waits
for the developer's go-ahead** first; in **production** the credential write is generate-only (the
developer runs it) and other writes require explicit confirmation (see the skill).
