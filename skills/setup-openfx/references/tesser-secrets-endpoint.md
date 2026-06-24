# Tesser internal secrets endpoint — `POST /v1/organizations/secrets`

**Embedded on purpose.** This endpoint is marked `@ApiInternal()` in the Tesser backend: it is
**not** exposed as an MCP tool and **not** shown in the public API reference or the OpenAPI schema.
It is reachable through the gateway today. An agent cannot fetch this contract from public docs, so
it lives here. Verify against the backend source if behavior seems off:
`platform/apps/backend/src/organizations/` (`organizations.controller.ts`, `organizations.zod-dto.ts`,
`organization-secrets.constants.ts`, `organizations.service.ts`).

## Execution: sandbox runs after a confirm, production generate-only

- **Sandbox/staging:** the agent runs this call itself once the values are loaded — but **previews it
  and gets the developer's go-ahead first** (one line: `POST /v1/organizations/secrets`, "stores your
  OpenFX credential bundle"; never show the key). No copy-paste for the developer; just approval.
- **Production:** **generate-only.** The developer runs it themselves with their own workspace token;
  the agent must **not** execute it in production — the ES256 private key is highly sensitive and the
  endpoint is deliberately unadvertised.

## Request — from the `.env.local` values

`load_openfx_env` exports all four values (set up by the skill's helper — see SKILL.md Phase 0–1b;
`OPENFX_PRIVATE_KEY` is a real PEM via `jq -r`). Load via the helper (which parses the files rather
than executing them, and pins `$TESSER_BASE_URL`/`$TESSER_AUTH_URL` to the allowlist), then post —
nothing sensitive is typed, and `jq -n --arg` JSON-encodes the PEM's newlines correctly:

```bash
# One block — env vars + $ACCESS_TOKEN don't persist across calls (see SKILL.md Phase 0 step 2):
source "<skill>/scripts/dotenv.sh" && load_openfx_env sandbox && mint_tesser_token   # `prod` for production
curl -sS -X POST "$TESSER_BASE_URL/v1/organizations/secrets" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" \
  -H 'content-type: application/json' \
  -d "$(jq -n \
    --arg orgId "$OPENFX_ORG_ID" --arg apiKey "$OPENFX_API_KEY" \
    --arg privateKey "$OPENFX_PRIVATE_KEY" --arg webhookSecret "$OPENFX_WEBHOOK_SECRET" '
    { provider: "OPENFX", key: "OPENFX_CREDENTIALS",
      value: { orgId: $orgId, apiKey: $apiKey, privateKey: $privateKey, webhookSecret: $webhookSecret } }')"
```

> Mapping (handled by `.env.local`): `apiKey` ← JSON `id` (sandbox value carries the `sandbox_`
> prefix; stored as-is), `orgId` ← JSON `orgId`, `privateKey` ← JSON `privateKey`.

The literal-value shape, for reference only (do **not** paste real secrets inline — they land in
shell history):

```json
{
  "provider": "OPENFX",
  "key": "OPENFX_CREDENTIALS",
  "value": {
    "orgId": "<OpenFX organization UUID — JSON orgId>",
    "apiKey": "<API-key identifier — JSON id; sandbox_ prefix in sandbox>",
    "privateKey": "-----BEGIN PRIVATE KEY-----\n<...>\n-----END PRIVATE KEY-----",
    "webhookSecret": "<webhook signing key; sandbox_ prefix in sandbox>"
  }
}
```

### Field notes

- `provider` — must be `"OPENFX"`.
- `key` — must be `"OPENFX_CREDENTIALS"`.
- `value` — an **object** for OpenFX (not a string). Keys are sent in **camelCase** directly
  (`orgId`, `apiKey`, `privateKey`, `webhookSecret`) — they bypass the usual snake_case conversion.
- `privateKey` — PEM-encoded ES256 private key. Must start with `-----BEGIN` and contain
  `PRIVATE KEY-----`. Literal `\n` escapes are normalized to real newlines server-side, so a
  single-line JSON string is fine.
- `apiKey` / `webhookSecret` — in **sandbox** these carry a `sandbox_` prefix. Store them **as-is**;
  Tesser strips the prefix internally (`OPENFX_APP_MODE` controls the `x-app-mode` header). Going
  live means re-running onboarding with production (no-prefix) values.

## Response

```json
{ "success": true, "maskedValue": "****" }
```

Only a masked value is ever returned; the secret is stored encrypted in the Basis Theory vault.
The field is **`maskedValue`** (camelCase) — this `@ApiInternal()` endpoint's response is excluded from
the gateway's snake_case conversion (sending `x-api-client: true` does not change it). Verified against
live sandbox 2026-06-24.

## Side effects & idempotency

- On success, Tesser auto-creates an **"OpenFX Ledger"** account (provider `OPENFX`). If ledger
  creation fails, the stored secret is rolled back.
- The record is **create-only**. A second call returns `400` with error code **`secrets-0002`**
  ("OpenFX credentials are already configured for this organization"). Treat this as
  "already onboarded," not a failure — match on the `secrets-0002` code, not the message text.

## Validation errors (`400`)

- `value` not an object → "OPENFX_CREDENTIALS value must be an object containing orgId, apiKey, privateKey, and webhookSecret."
- Any of the four not a string → "OPENFX_CREDENTIALS must include string orgId, apiKey, privateKey, and webhookSecret."
- Bad PEM → "OPENFX_CREDENTIALS.privateKey must be a PEM-encoded private key (-----BEGIN ... PRIVATE KEY-----)."
