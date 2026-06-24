# Tesser internal secrets endpoint — `POST /v1/organizations/secrets`

**Embedded on purpose.** This endpoint is marked `@ApiInternal()` in the Tesser backend: it is
**not** exposed as an MCP tool and **not** shown in the public API reference or the OpenAPI schema.
It is reachable through the gateway today. An agent cannot fetch this contract from public docs, so
it lives here. Verify against the backend source if behavior seems off:
`platform/apps/backend/src/organizations/` (`organizations.controller.ts`, `organizations.zod-dto.ts`,
`organization-secrets.constants.ts`, `organizations.service.ts`).

## Why generate-only

The developer runs this call themselves with their own workspace token to write their own OpenFX
credentials. The agent must **not** execute it — the ES256 private key is highly sensitive and the
endpoint is deliberately unadvertised.

## Request (A) — read straight from the downloaded key JSON (recommended)

Three of the four values live in the API-key JSON you downloaded from the OpenFX dashboard
(`orgId`, `id`, `privateKey`); only the webhook signing secret comes from the webhook step. Reading
them with `jq --slurpfile` means nothing sensitive is typed. Works the same in sandbox and prod (set
`BASE_URL`/`ACCESS_TOKEN` for the chosen environment).

```bash
OFX_JSON="$HOME/Downloads/OpenFX_api-key_<uuid>.json"   # the downloaded key file
WEBHOOK_SECRET="<paste-from-webhook-step>"

PAYLOAD=$(jq -nc --slurpfile f "$OFX_JSON" --arg ws "$WEBHOOK_SECRET" \
  '{ provider:"OPENFX", key:"OPENFX_CREDENTIALS",
     value:{ orgId:$f[0].orgId, apiKey:$f[0].id, privateKey:$f[0].privateKey, webhookSecret:$ws } }')

# sanity-check the payload parses (the privateKey has newlines):
printf '%s' "$PAYLOAD" | jq empty && echo ok

curl -sS -X POST "$BASE_URL/v1/organizations/secrets" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" -H "content-type: application/json" \
  -d "$PAYLOAD" | jq .
```

> **`apiKey` ← the JSON `id` field** (the API-key identifier). In sandbox that value carries the
> `sandbox_` prefix; store it as-is. `orgId` ← JSON `orgId`, `privateKey` ← JSON `privateKey`.

## Request (B) — from `.env.local` vars (if you don't have the JSON file handy)

```bash
# Source creds without echoing them:  set -a; . ./.env.local; set +a
# Needs: OPENFX_ORG_ID, OPENFX_API_KEY, OPENFX_PRIVATE_KEY, OPENFX_WEBHOOK_SECRET, ACCESS_TOKEN, BASE_URL
curl -sS -X POST "$BASE_URL/v1/organizations/secrets" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" \
  -H 'content-type: application/json' \
  -d "$(jq -n \
    --arg orgId "$OPENFX_ORG_ID" --arg apiKey "$OPENFX_API_KEY" \
    --arg privateKey "$OPENFX_PRIVATE_KEY" --arg webhookSecret "$OPENFX_WEBHOOK_SECRET" '
    { provider: "OPENFX", key: "OPENFX_CREDENTIALS",
      value: { orgId: $orgId, apiKey: $apiKey, privateKey: $privateKey, webhookSecret: $webhookSecret } }')"
```

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
{ "success": true, "masked_value": "****abc123" }
```

Only a masked value is ever returned; the secret is stored encrypted in the Basis Theory vault.
(The external API is snake_case, so the field is `masked_value`.)

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
