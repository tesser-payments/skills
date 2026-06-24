---
name: setup-openfx
description: Use when a developer wants to connect (onboard) their OpenFX liquidity-provider account to Tesser — guides the OpenFX dashboard steps, registers OpenFX credentials, registers bank/wallet accounts (with Tesser and with OpenFX), coordinates VAN setup (Tesser seeds it), and verifies a deposit. Works in sandbox/staging and production. Triggered by /setup-openfx or requests like "onboard OpenFX", "set up OpenFX in prod", "register my OpenFX credentials".
---

# Onboard an OpenFX account onto Tesser

## What this is

Connecting a customer's OpenFX account to Tesser is **semi-automatic / bring-your-own-account**:
the developer does steps in **OpenFX's own dashboard**, then registers credentials and accounts with
**Tesser**. You guide both sides and execute the safe parts; you never run the credential-write call
yourself.

OpenFX is a liquidity provider of the **on/off-ramp** class (`provider_key: "openfx"`). Casing is
always **OpenFX** in prose.

This skill covers **both environments**. The steps are the same except where a step is marked
**🅢 Sandbox/staging** or **🅟 Production** — production additionally requires that the bank and
wallets be registered *with OpenFX* (and the bank passes OpenFX review).

## Tooling (Claude Code and Codex)

This skill is harness-agnostic. It installs the same way in **Claude Code** (`~/.claude/skills/`) and
**Codex** (`~/.agents/skills/`) and is invoked the same way — the user asks to "set up OpenFX on
Tesser" and this skill triggers (Codex also offers `$setup-openfx` / `/skills`). The steps use Claude
Code tool names — map them to your platform (see the repo `AGENTS.md`): `Bash` → your shell,
`Read`/`Write`/`Edit` → native file tools, "fetch live docs" → your web-fetch tool **or** `curl`.
Everything operational here is plain `curl` + `jq`, which works the same everywhere.

## Operating rules (read first)

1. **Fetch, don't trust memory.** Before constructing any Tesser API call, fetch current shapes from
   the live docs in `references/live-sources.md` (web-fetch tool or `curl`). The one exception is the
   internal secrets endpoint, documented in `references/tesser-secrets-endpoint.md` because it is
   intentionally absent from public docs.
2. **Hybrid execution:** read-only calls (auth, `GET`) run automatically; non-secret writes (bank,
   wallet) show the payload, get explicit confirmation, then run; the credential write
   (`POST /v1/organizations/secrets`) is **generate-only — the developer runs it**, never you.
3. **Confirm the environment up front.** Sandbox by default. `--staging` is an alias for sandbox.
   `--prod` targets production — confirm explicitly before any write.
4. **Keep secrets out of shell history and chat.** Load Tesser creds from a dotenv file; read OpenFX
   creds straight from the downloaded key JSON with `jq`; never echo secrets.
5. **Verify every write** with a follow-up `GET`. Evidence before claiming success.

## Environment

| Environment | `BASE_URL` | `AUDIENCE` | `AUTH0_TOKEN_URL` |
|---|---|---|---|
| **Sandbox / staging** (default; `--staging` alias) | `https://sandbox.tesserx.co` | `https://sandbox.tesserx.co` | `https://dev-awqy75wdabpsnsvu.us.auth0.com/oauth/token` |
| **Production** (`--prod`) | `https://api.tesser.xyz` | `https://api.tesser.xyz` | `https://tesser-payments.us.auth0.com/oauth/token` |

> "Staging" means the sandbox environment here — `--staging`/`--sandbox` both resolve to the sandbox
> row. Audience equals base URL in both. Tokens are `client_credentials`, last 24h, no refresh.
> Send `x-api-client: true` on Tesser calls to force snake_case responses (the gateway already sets it
> for API-key auth, but it's harmless to be explicit). A `.env.local` may override `TESSER_BASE_URL` /
> `TESSER_AUDIENCE` / `TESSER_AUTH_URL`.

## Procedure

### Phase 0 — Preflight (auto, read-only)

1. Resolve the target environment from the user's request (or an explicit `--staging`/`--prod`
   argument): sandbox by default (staging = sandbox); production only when the user says prod / passes
   `--prod` — confirm before any write. Honor `TESSER_*` overrides.
2. **Load Tesser credentials without putting them in shell history.** Prefer a gitignored `.env.local`
   sourced in-process (`set -a; . ./.env.local; set +a`), else exported env. Accept
   `TESSER_API_KEY`/`TESSER_API_SECRET` or the demo-style `TESSER_CLIENT_ID`/`TESSER_CLIENT_SECRET`.
   Never echo them. If absent, tell the developer to create `.env.local` (see README).
3. Mint a token (audience from the env row) and prove auth with `GET {BASE_URL}/v1/accounts`
   (`-H "x-api-client: true"`). **Capture `workspace_id`** (`.data[0].workspace_id`, or
   `GET /v1/accounts/<id>` → `.data.workspace_id`) — needed for the webhook URL and the VAN seed.
4. Fetch the live OpenAPI / how-tos to confirm current `/v1/accounts/banks` and `/v1/accounts/wallets`
   shapes before any write.
5. **Idempotency check:** if `GET /v1/accounts` already shows a `provider: OPENFX` ledger, OpenFX is
   already onboarded — tell the developer and skip to verification.

> Endpoints use a `/v1` prefix; accounts are typed sub-paths (`/v1/accounts`, `/v1/accounts/banks`,
> `/v1/accounts/wallets`, `/v1/accounts/ledgers`); the credential write is
> `POST /v1/organizations/secrets`.

### Phase 1 — OpenFX dashboard: API key + webhook (manual)

Walk the developer through `references/openfx-dashboard-steps.md` (dashboard at
`https://app.openfx.com`; use the **production** dashboard for `--prod`):

1. **Create an API key and download its JSON.** Fields map to the credential bundle:
   `orgId` → `orgId`, **`id` → `apiKey`** (in sandbox this carries the `sandbox_` prefix; store as-is),
   `privateKey` → `privateKey` (ES256 PEM, keep the `\n`s).
2. **Register a webhook** (All Events) at `{BASE_URL}/v1/webhooks/openfx/{workspaceId}` using the
   Phase 0 `workspace_id` (mind the `/v1` prefix). Copy the **Signing Key** → `webhookSecret`.
   - **⚠️ BLOCKER — both environments (probed 2026-06-23):** the OpenFX webhook route returns **404 on
     both prod (`api.tesser.xyz`) and sandbox**, while Circle's equivalent returns 401. The gateway is
     missing `/v1/webhooks/openfx/{workspaceId}` (Circle has `/v1/webhooks/circle/{organizationId}`).
     This contradicts the prod runbook's "route is live" claim. You can still create the webhook to get
     the Signing Key, but deliveries 404 and deposits stall after planning until platform ships the
     route. See `references/openfx-dashboard-steps.md`.

### Phase 2 — Store the OpenFX credentials with Tesser (GENERATE ONLY — developer runs it)

Build the request from `references/tesser-secrets-endpoint.md`. Prefer the **`jq --slurpfile` form**
that reads the four values straight from the downloaded key JSON + the webhook secret, so nothing
sensitive is typed. Present it for the developer to run — do not run it yourself. Tell them:

- Expected: `{ "success": true, "masked_value": "****…" }`.
- Side effect: Tesser onboards the **"OpenFX Ledger"** (probes balances via the Basis Theory reactor);
  on success it shows real balances.
- `400` code **`secrets-0002`** = already configured (not a failure; delete the vault record to rotate).
- PEM must keep its `-----BEGIN/END … PRIVATE KEY-----` markers; literal `\n` is normalized server-side.

**🅟 Production prereq:** the Basis Theory reactor must already be configured on the backend, or
OpenFX calls fail with `vault-0030`. (Prod is configured; relevant only if errors appear.)

Confirm success (developer pastes back the masked value) before continuing.

### Phase 3 — Register the funding bank (Tesser + OpenFX)

1. **With Tesser** (execute-with-confirmation): `POST {BASE_URL}/v1/accounts/banks` with `name`,
   `bank_name`, `bank_code_type` (`ROUTING`/`SWIFT`/`CLABE`), `bank_identifier_code`,
   `bank_account_number`. Verify with `GET /v1/accounts/{id}`.
2. **With OpenFX** (dashboard): register the same bank as a fiat funding/withdrawal account.
   - **🅟 Production — hard gate:** this goes through OpenFX **review**. Until OpenFX marks the bank
     **accepted**, deposits will not plan/settle (the deposit flow matches the source bank against an
     OpenFX-registered account). Don't run the deposit probe until it clears.
   - **🅢 Sandbox/staging:** pre-approve the account in the dashboard (no formal review). Tesser also
     stubs the source bank for the webhook lazy-match (part of the internal `openfx-van-seeding` step).

### Phase 4 — Register destination wallet(s) (wallet flows only)

Skip if the customer only pre-funds the OpenFX ledger (no on-chain leg).

1. **With Tesser:** `POST {BASE_URL}/v1/accounts/wallets` (`is_managed: false` for self-custodial).
2. **With OpenFX** (dashboard): add each wallet as an approved withdrawal address.
   - **🅟 Production — required, per network:** no default address is allowed. Copy each managed
     wallet's `crypto_wallet_address` (`GET /v1/accounts/<wallet-id>`) and add it on the OpenFX
     dashboard **for every network you intend to use** (Base, Ethereum, Polygon, … per OpenFX's list).
   - **🅢 Sandbox/staging:** pre-approve the address(es) in the dashboard.

### Phase 5 — VAN (Tesser-internal step)

The deposit flow **looks up** a VAN (`findVan` matches `provider=OPENFX` + currency); it never creates
one, and there's **no public/admin API** to register one. So this step is **done by Tesser**, not the
customer: the customer **discovers** the VAN details on the OpenFX dashboard (initiate a deposit for
the currency → OpenFX shows the receiving bank, account number/CLABE, beneficiary, van id) and hands
them to their Tesser contact, who **seeds** the VAN row.

- **If you are the customer/integrator:** collect the VAN details and your `workspace_id`, then ask
  Tesser to seed it. You're done with this phase once Tesser confirms.
- **If you are a Tesser operator:** use the **`openfx-van-seeding`** skill (Tesser-internal; requires
  DB access). It also covers the sandbox source-bank lazy-match stub.
- **🅟 Production:** VAN discovery may be gated behind source-bank acceptance (Phase 3) — revisit once
  cleared.

### Phase 6 — Deposit & verify

With creds stored (2), bank registered/accepted (3), wallets registered if needed (4), and the VAN
seeded (5):

```bash
curl -sS -X POST "{BASE_URL}/v1/treasury/deposits" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" -H "content-type: application/json" \
  -d '{ "desired": {
          "from": { "account_id": "<funding-bank-id>", "amount": "1000", "currency": "MXN" },
          "to":   { "account_id": "<dest-wallet-or-ledger-id>", "currency": "USDC", "network": "<network>" } } }' | jq .
```
- `amount` must clear OpenFX's per-currency minimum (e.g. **MXN ≥ 1000**) or `/trade` 400s.
- `network`: sandbox uses testnets (e.g. `BASE_SEPOLIA`); production uses mainnets (`BASE`, etc.). For
  ledger-only pre-fund, set `to` to the OpenFX ledger and the same fiat currency (no on-ramp).
- Then `GET /v1/treasury/deposits/{id}` (4 planned steps) and `…/{id}/instructions` (VAN wire details).
- Funds wired to the VAN → OpenFX fires the `deposits` webhook → Tesser credits → swap → withdrawal.
- **Both environments:** completion is currently blocked until the OpenFX webhook gateway route ships
  (Phase 1 BLOCKER — 404 in prod *and* sandbox). `/v1/treasury/deposits/{id}/simulate` does **not**
  help — it's Circle-only, OpenFX has no simulate.

## Error handling

| Condition | What to do |
|---|---|
| Missing `TESSER_API_KEY`/`SECRET` (or `CLIENT_ID`/`SECRET`) | Stop; env-setup guidance |
| Auth `401` | Stop; check key/secret and audience-vs-environment |
| Duplicate secret `400` (code `secrets-0002`) | Already onboarded; skip to verification |
| `vault-0030` after secret write | Basis Theory reactor not configured on backend (esp. non-prod) |
| Malformed PEM | Fix `-----BEGIN/END … PRIVATE KEY-----` markers and `\n` |
| Deposit `DEPOSIT_VAN_NOT_FOUND` | VAN not seeded for this workspace+currency (Phase 5) |
| 🅟 Deposit won't plan/settle | Source bank not yet **accepted** by OpenFX (Phase 3) |
| Webhook never arrives / deposit stalls (both envs) | Gateway OpenFX webhook route not deployed — 404 in prod and sandbox (Phase 1) |
| Offline (can't fetch live docs) | Proceed with embedded secrets contract; verify account shapes when back online |

## References

- `references/openfx-dashboard-steps.md` — OpenFX dashboard: API key JSON, webhook, bank/wallet registration.
- `references/tesser-secrets-endpoint.md` — internal `POST /v1/organizations/secrets` contract.
- `references/live-sources.md` — live docs to fetch (auth, accounts, deposits, OpenAPI, OpenFX docs).
- `../openfx-van-seeding/SKILL.md` — **Tesser-internal** VAN seeding (operators only; the customer
  just discovers the VAN details and hands them to Tesser).
