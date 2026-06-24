# Manual steps in the OpenFX dashboard

These steps happen in **OpenFX's own dashboard** (`https://app.openfx.com`), outside Tesser. The
developer does them once. The output is: the four credential values Tesser needs (step 1), a
registered webhook (step 2), and — for funds movement — the source bank (step 3) and destination
wallet(s) (step 4) registered with OpenFX.

> Source hierarchy: Tesser docs > Tesser platform code > OpenFX onboarding runbooks (the prod
> runbook + the `~/Documents/openfx 2` sandbox handoff) and OpenFX's own docs
> (`https://docs.openfx.com`). Confirm against the live OpenFX dashboard if the UI has changed.
>
> **Environment:** use the **sandbox** OpenFX dashboard for sandbox/staging, the **production** OpenFX
> dashboard for prod. Steps are the same except bank/wallet registration (steps 3–4), which production
> requires and reviews.

## What you need to produce

| Value (`OPENFX_CREDENTIALS`) | Where it comes from | Notes |
|---|---|---|
| `orgId` | API-key JSON, field `orgId` | OpenFX organization UUID |
| `apiKey` | API-key JSON, field **`id`** | The API-key identifier. Sandbox value carries a `sandbox_` prefix; store as-is (Tesser strips it) |
| `privateKey` | API-key JSON, field `privateKey` | ES256 **PEM**; signs short-lived OpenFX JWTs. Literal `\n` is fine (normalized server-side) |
| `webhookSecret` | The webhook **Signing Key** | Produced when you register the webhook (step 2). Sandbox value is prefixed `sandbox_`; store as-is |

## Step 1 — Create an API key and download its JSON

OpenFX dashboard → **API Keys & Webhooks** → create an API key (sandbox key for sandbox/staging,
production key for prod). **Download the key's JSON** and save it (e.g.
`~/Downloads/OpenFX_api-key_<uuid>.json`) — Phase 2 reads it directly. It contains:
- `orgId` — your OpenFX organization UUID → bundle `orgId`.
- `id` — the API-key identifier → bundle **`apiKey`** (sandbox value carries the `sandbox_` prefix).
- `privateKey` — the ES256 PEM private key (downloadable once; keep it secret) → bundle `privateKey`.
- `name` — of the form `org/{org-id}/apiKey/{api-key-id}` (OpenFX's JWT subject; not stored directly).

> Auth model (context): OpenFX is called with a **self-signed ES256 JWT** (2-minute TTL, one per
> request), plus headers `x-api-key: <apiKey>` and `x-app-mode: SANDBOX`. Tesser does this signing
> for you using the stored `privateKey`; you do not need to mint JWTs during onboarding.

## Step 2 — Register the webhook (this produces `webhookSecret`)

OpenFX delivers deposit/withdrawal completion via webhooks; without a registered webhook the deposit
flow stalls after planning. Register it before storing credentials.

OpenFX dashboard → **API Keys & Webhooks** → **Webhooks** tab → **Create Webhook**:
- **Webhook URL**: `{TESSER_BASE_URL}/v1/webhooks/openfx/{workspaceId}` — substitute the Tesser base
  URL for your environment (sandbox `https://sandbox.tesserx.co`, production `https://api.tesser.xyz`)
  and your **Tesser workspace UUID** (the skill captures this in Phase 0 from `GET /v1/accounts`
  → `data[0].workspace_id`). The form shows "Invalid URL" until it's a valid absolute URL.

  > Note the **`/v1`** prefix — the handler is backend-direct, routed via the gateway only under
  > `/v1`; a missing `/v1` is a 404.
  >
  > **⚠️ BLOCKER — route missing in BOTH environments (probed 2026-06-23):** `POST /v1/webhooks/openfx`
  > and `…/{workspaceId}` return **404 on both `api.tesser.xyz` (prod) and `sandbox.tesserx.co`**,
  > while Circle's equivalent returns 401 in both. The gateway lacks the
  > `/v1/webhooks/openfx/{workspaceId}` route that Circle has (`/v1/webhooks/circle/{organizationId}`).
  > This **contradicts the prod runbook's claim that the route is live** — the probe says otherwise.
  > Platform must add and deploy that gateway route (mirroring Circle) in **both** environments. You
  > can still create the webhook now to capture the Signing Key, but OpenFX deliveries will 404 — so
  > deposits stall after planning until the route ships.

- **Webhook Event**: **All Events (Deposits, Withdrawals)**.
- Save, then **copy the Signing Key** (`sandbox_…`) — **this is the `webhookSecret`.** Tesser verifies
  the `x-openfx-signature` header (HMAC-SHA256, base64) against it.

Dashboard UI reference (Webhooks tab, then the Create Webhook panel):

![OpenFX webhooks list](./screenshots/openfx-webhooks-1.png)
![Create Webhook panel](./screenshots/openfx-webhooks-2.png)

## Step 3 — Register the funding bank on OpenFX

OpenFX requires funds movement to be first-party. Register the workspace's **source bank** (the fiat
account deposits wire from) on the OpenFX dashboard. There's **no create-address API** — it's done in
the dashboard. The same bank is also registered with Tesser (skill Phase 3, `POST /v1/accounts/banks`).

- **🅟 Production — hard gate:** registration goes through OpenFX **review**. Until OpenFX marks the
  bank **accepted**, deposits will not plan/settle (the deposit flow matches the source bank against an
  OpenFX-registered account, and VAN discovery in step 5 may be gated behind acceptance). Don't run a
  deposit until it clears.
- **🅢 Sandbox/staging:** pre-approve the bank in the dashboard (no formal review). Tesser-side, an
  operator also stubs the source bank's `fiat_bank_identifier_code = '0000000000'` so the deposit
  webhook lazy-match lands (part of the internal `openfx-van-seeding` skill).

## Step 4 — Register destination wallet(s) on OpenFX (wallet flows only)

Skip if the customer only pre-funds the OpenFX ledger (no on-chain leg). Otherwise the destination
wallet (where on-ramped USDC lands) must be an approved withdrawal address. The same wallet is also
registered with Tesser (skill Phase 4, `POST /v1/accounts/wallets`).

- **🅟 Production — required, per network:** no default address is allowed. Copy each managed wallet's
  `crypto_wallet_address` (`GET /v1/accounts/<wallet-id>`) and add it on the OpenFX dashboard **for
  every network you intend to use** (Base, Ethereum, Polygon, … per OpenFX's supported list).
- **🅢 Sandbox/staging:** pre-approve the wallet address(es) in the dashboard.

## Handing values to the skill

Provide `orgId`, `apiKey`, `privateKey`, and `webhookSecret` back to the agent for Phase 2. Keep the
private key out of shared logs; the agent places it into the **generate-only**
`POST /v1/organizations/secrets` command for you to run.
