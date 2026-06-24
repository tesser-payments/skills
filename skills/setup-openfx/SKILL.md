---
name: setup-openfx
description: Use when a developer wants to connect (onboard) their OpenFX liquidity-provider account to Tesser — guides the OpenFX dashboard steps, registers OpenFX credentials, registers bank/wallet accounts (with Tesser and with OpenFX), coordinates VAN setup (Tesser seeds it), and verifies a deposit. Works in sandbox/staging and production. Triggered by /setup-openfx or requests like "onboard OpenFX", "set up OpenFX in prod", "register my OpenFX credentials".
---

# Onboard an OpenFX account onto Tesser

## What this is

Connecting a customer's OpenFX account to Tesser is **semi-automatic / bring-your-own-account**:
the developer does steps in **OpenFX's own dashboard**, then registers credentials and accounts with
**Tesser**. You guide both sides; in **sandbox/staging** you run the Tesser API calls for the
developer, while in **production** the sensitive credential write stays generate-only (they run it).

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
2. **Execution model (environment-conditional):**
   - **🅢 Sandbox/staging:** once the required credentials are in `.env.local`, you run the onboarding
     API calls — but **confirm each state-changing call before sending it.** Read-only calls (auth,
     `GET`s, the idempotency check) you may run while briefly narrating them; before every **write**
     (the credential write `POST /v1/organizations/secrets`, bank/wallet registration, deposit
     creation) tell the developer in one line what you're about to do — method, endpoint, purpose, and
     the non-secret params — and wait for their go-ahead, then run it. They approve rather than
     copy-paste; never display secret values in these previews.
   - **🅟 Production:** **do not execute writes — output the exact commands for the developer to run**
     (auth/read-only checks may still run). The credential write especially is theirs to run, so the
     ES256 private key and workspace token stay in their hands. Never auto-run a production write.
   - Operate on the developer's own credentials; never print secrets.
   - **Env doesn't persist between calls.** Each `Bash` call runs in a *fresh* shell, so exported vars
     (incl. `$TESSER_AUTH_URL`, `$ACCESS_TOKEN`) vanish between tool calls. Begin **every** block that
     hits the Tesser API with the Phase 0 step 2 preamble —
     `source "<skill>/scripts/dotenv.sh" && load_openfx_env <env> && mint_tesser_token` — and run that
     block's `curl`s in the *same* block.
3. **Ask which environment as your very first step — never infer it.** Before any other work, ask the
   developer explicitly whether they're onboarding **sandbox/staging** or **production**. Do not assume
   a default. (If they passed `--staging`/`--prod` to the slash command, take that as the answer and
   just confirm it back.) State the chosen environment back to the user, and get explicit confirmation
   again before any **production** write. Pass the choice to `load_openfx_env` (`sandbox`/`prod`). The
   environment decides execution (rule 2): sandbox runs (confirming each write), production outputs commands.
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
> for API-key auth, but it's harmless to be explicit). `load_openfx_env <sandbox|prod>` resolves and
> **exports** `TESSER_BASE_URL` / `TESSER_AUDIENCE` / `TESSER_AUTH_URL` for the chosen environment,
> **validated against a host allowlist**; a `.env.local` may override them only *within* that allowlist
> (an off-list host aborts the load, so the ES256 key and token can't be redirected elsewhere).

## Procedure

### Phase 0 — Preflight (auto, read-only)

1. **Ask the developer which environment — this is the first thing you do.** Explicitly ask whether
   they want **sandbox/staging** (staging = sandbox) or **production**; don't infer or default. If they
   passed `--staging`/`--prod` to the slash command, take that as the answer and confirm it back.
   Announce the choice and pass it to `load_openfx_env` (`sandbox`/`prod`), which selects + validates
   the endpoint row. Confirm again before any production write. Per rule 2, this choice decides
   execution: **sandbox — run the calls yourself, confirming each write; production — output the
   commands for the developer to run.**
2. **Load credentials via the skill's helper — never `source` a dotenv file.** The skill **owns** the
   credential-loading logic in its helper (`scripts/dotenv.sh`, the one trusted shipped script); source
   the helper, run `init_env_local`, then call `load_openfx_env`:
   ```bash
   source "<this skill's dir>/scripts/dotenv.sh"   # ships with the skill (scripts/dotenv.sh)
   init_env_local            # creates ./.env.local from the template (mode 0600) if it's missing
   load_openfx_env sandbox   # or: load_openfx_env prod  — PARSES (never executes) the credential files
   ```

   ⚠️ **Env vars do NOT persist across calls — re-establish state at the top of every block.** Agent
   harnesses run each `Bash` call in a *fresh* shell, so the vars `load_openfx_env` exports (including
   `TESSER_AUTH_URL`, needed to mint the token) vanish between tool calls. **Every** command block that
   touches the Tesser API must therefore begin with this one-line preamble, then make its `curl` calls
   in the **same** block:
   ```bash
   source "<this skill's dir>/scripts/dotenv.sh" && load_openfx_env <sandbox|prod> && mint_tesser_token
   ```
   That reloads the (allowlist-validated) endpoint vars + credentials and re-mints `$ACCESS_TOKEN` in
   that shell. Skipping it is exactly why a token mint fails with an empty `$TESSER_AUTH_URL`.

   `load_openfx_env` **parses** `.env.local` and the downloaded files as literal `KEY=value` data — it
   does **not** `source`/execute them, so a planted or malformed file cannot run code — validates the
   Tesser/Auth0 hosts against a fixed allowlist (it **aborts rather than send credentials off-list**),
   and exports the values, re-derived each call and never echoed:
   - **Tesser** from `tesser-credentials*.env`: `CLIENT_ID`→`TESSER_API_KEY`, `CLIENT_SECRET`→`TESSER_API_SECRET`.
   - **OpenFX** from `OpenFX_api-key_*.json` (if present): `orgId`→`OPENFX_ORG_ID`, `id`→`OPENFX_API_KEY`,
     `privateKey`→`OPENFX_PRIVATE_KEY` (**`jq -r`**, so the value is a real PEM with valid
     `-----BEGIN/END PRIVATE KEY-----` framing).
   - **Endpoint** `TESSER_BASE_URL`/`TESSER_AUDIENCE`/`TESSER_AUTH_URL` for the chosen env (the
     `sandbox`/`prod` argument), honoring allowlisted overrides in `.env.local`.

   `init_env_local` only **creates `.env.local` when missing** (mode `0600`); an existing file is left
   intact, so `OPENFX_WEBHOOK_SECRET` and any overrides are **preserved** and reruns are safe.

   If the Tesser file isn't in the working dir yet, tell the developer to download it (dashboard →
   **Settings → API keys**) and move it in, then re-run `load_openfx_env`. Already-exported env vars or
   demo-style `TESSER_CLIENT_ID`/`TESSER_CLIENT_SECRET` also work. The downloaded files are gitignored
   (`*.env`, `OpenFX_api-key_*.json`); their `SIGNING_*` and other extra fields are ignored.
3. **Prove auth in one self-contained block** (preamble + call together, per step 2):
   ```bash
   source "<this skill's dir>/scripts/dotenv.sh" && load_openfx_env <sandbox|prod> && mint_tesser_token
   curl -sS "$TESSER_BASE_URL/v1/accounts" -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" | jq .
   ```
   `mint_tesser_token` exports `$ACCESS_TOKEN` (Auth0 client-credentials, audience `$TESSER_AUDIENCE`).
   **Capture `workspace_id`** (`.data[0].workspace_id`, or `GET /v1/accounts/<id>` →
   `.data.workspace_id`) — needed for the webhook URL and the VAN seed.
4. Fetch the live OpenAPI / how-tos to confirm current `/v1/accounts/banks` and `/v1/accounts/wallets`
   shapes before any write.
5. **Idempotency check:** if `GET /v1/accounts` already shows a `provider: OPENFX` ledger, OpenFX is
   already onboarded — tell the developer and skip to verification.

> Endpoints use a `/v1` prefix; accounts are typed sub-paths (`/v1/accounts`, `/v1/accounts/banks`,
> `/v1/accounts/wallets`, `/v1/accounts/ledgers`); the credential write is
> `POST /v1/organizations/secrets`.

### Phase 1 — OpenFX credentials (key file + webhook)

OpenFX dashboard is `https://app.openfx.com` (use the **production** dashboard for `--prod`). This
phase fills the four `OPENFX_*` values in `.env.local`: three come from the downloaded key file (parsed
by `.env.local` itself when sourced), the fourth (the webhook secret) is added by the developer. Full
detail in `references/openfx-dashboard-steps.md`. Never echo the private key.

**1a. API key file → three values, read by re-running `load_openfx_env`.** Tell the developer: in the
OpenFX dashboard create an API key, **download the JSON**, and **move it into the working directory**
(named `OpenFX_api-key_*.json`, gitignored). Then just **re-run `load_openfx_env`** — it reads
`orgId`→`OPENFX_ORG_ID`, `id`→`OPENFX_API_KEY`, `privateKey`→`OPENFX_PRIVATE_KEY` (`jq -r`, real PEM)
straight from the JSON. No separate parse step, no ad-hoc `jq` — the helper owns it.

```bash
load_openfx_env sandbox   # re-reads OpenFX_api-key_*.json now that it's present (use `prod` for production)
```
(Ignore the file's other fields: `name`, `publicKey`, `scope`, etc.)

**1b. Webhook secret → display the URL, then paste it in.** The webhook secret is **not** in the file
— OpenFX issues it when you register a webhook. Show the developer the **literal URL** to register
(built from the Phase 0 `workspace_id`):

```
{BASE_URL}/v1/webhooks/openfx/{workspaceId}
```
e.g. sandbox → `https://sandbox.tesserx.co/v1/webhooks/openfx/<workspaceId>`. Tell them: in the OpenFX
dashboard create a webhook with **All Events** pointed at that URL, copy the **Signing Key** it
returns, and set it via the skill helper — `set_openfx_webhook_secret '<signing key>'` (upserts the
`OPENFX_WEBHOOK_SECRET` line, no duplicate, no echo). It's preserved on re-init, so reruns are safe.
Then reload: `load_openfx_env sandbox` (or `prod`).

> **Webhook route status:** 404'd on both prod and sandbox when probed 2026-06-23, but **sandbox
> deposits completed end-to-end on 2026-06-24** (deliveries now processed) — the sandbox route is
> resolved. **Production delivery still to be confirmed.** Either way, register the webhook here to
> obtain the Signing Key. See `references/openfx-dashboard-steps.md`.

### Phase 2 — Store the OpenFX credentials with Tesser

After Phase 1, `load_openfx_env` exports all four `OPENFX_*` values. Use the **helper-loaded form** in
`references/tesser-secrets-endpoint.md` (it loads via `load_openfx_env` and posts the bundle — nothing
typed):

- **🅢 Sandbox/staging — you run it, after a one-line confirm.** Preview the call to the developer
  (`POST /v1/organizations/secrets`, "stores your OpenFX credential bundle"; never show the key), get
  their go-ahead, then execute it. Don't make them copy-paste.
- **🅟 Production — generate-only.** Present the command for the developer to run (the ES256 private key
  is theirs to send); do **not** execute it yourself.

Either way:

- Expected: `{ "success": true, "maskedValue": "****" }` (camelCase — this internal endpoint's
  response bypasses snake_case conversion; verified live 2026-06-24).
- Side effect: Tesser onboards the **"OpenFX Ledger"** (probes balances via the Basis Theory reactor);
  on success it shows real balances.
- `400` code **`secrets-0002`** = already configured (not a failure; delete the vault record to rotate).
- PEM must keep its `-----BEGIN/END … PRIVATE KEY-----` markers; literal `\n` is normalized server-side.

**🅟 Production prereq:** the Basis Theory reactor must already be configured on the backend, or
OpenFX calls fail with `vault-0030`. (Prod is configured; relevant only if errors appear.)

Confirm success (developer pastes back the masked value) before continuing.

### Phase 3 — Register the funding bank (Tesser + OpenFX)

The funding bank must exist on **both** sides with the **same exact values** — Tesser matches your
registered bank against an OpenFX-registered fiat account, so any field mismatch breaks the match.

> **One funding bank per workspace.** A second `POST /v1/accounts/banks` returns
> `400 accounts-3001` ("A workspace-level bank account already exists. Only one is allowed per
> workspace."). Accounts are **`GET`/`PATCH` only — no delete** (`/v1/accounts/{id}`), so to change
> the funding bank (e.g. switch currency) you `PATCH` the existing one, not create another.

- **🅢 Sandbox/staging:** ask the developer **which currency** they want, then register the matching
  pre-seeded sandbox bank with Tesser (`POST {BASE_URL}/v1/accounts/banks`) using the values in
  `references/sandbox-bank-accounts.md`. Those mirror OpenFX's sandbox accounts, so the OpenFX side is
  **already in place** — no dashboard step. **USD and MXN** are the validated currencies. **Preview the
  `POST` and confirm with the developer, then run it** (rule 2); verify with `GET {BASE_URL}/v1/accounts/{id}`.
- **🅟 Production:** the developer supplies their **real** bank details and must do **both**:
  1. register the bank with Tesser (`POST /v1/accounts/banks`), **and**
  2. add the **same exact values** in the **OpenFX dashboard** (as a fiat funding/withdrawal account).

  OpenFX **reviews** it — a hard gate: until the bank is **accepted**, deposits won't plan/settle. The
  two registrations must match exactly (name, bank name, code type, identifier, account number, SWIFT)
  or Tesser can't match the bank to the OpenFX account.

### Phase 4 — Register destination wallet(s) (wallet flows only)

Skip if the customer only pre-funds the OpenFX ledger (no on-chain leg).

1. **With Tesser:** `POST {BASE_URL}/v1/accounts/wallets` (`is_managed: false` for self-custodial).
2. **With OpenFX** (dashboard): add each wallet as an approved withdrawal address.
   - **🅟 Production — required, per network:** no default address is allowed. Copy each managed
     wallet's `crypto_wallet_address` (`GET /v1/accounts/<wallet-id>`) and add it on the OpenFX
     dashboard **for every network you intend to use** (Base, Ethereum, Polygon, … per OpenFX's list).
   - **🅢 Sandbox/staging:** pre-approve the address(es) in the dashboard.

### Phase 5 — VAN (Tesser-assisted step)

The deposit flow **looks up** a VAN (`findVan` matches `provider=OPENFX` + currency); it never creates
one, and there's **no public/admin API** to register one. So this step is **done by Tesser**, not the
customer — but what the customer provides differs by environment:

- **🅢 Sandbox/staging:** the customer does **not** supply any VAN details. They just tell Tesser
  **which workspace (`workspace_id`) and which currency** they need a VAN for, and Tesser creates it
  (sandbox VANs are known to Tesser). Do not ask the customer to discover or hand over VAN details in
  sandbox — point them at their Tesser contact.
- **🅟 Production:** the customer **discovers** the real VAN deposit details from OpenFX (initiate a
  deposit for the currency → OpenFX shows the receiving bank, account number/CLABE, beneficiary, van
  id) and provides them to their Tesser contact, who seeds the VAN. Discovery may be gated behind
  source-bank acceptance (Phase 3) — revisit once cleared.

### Phase 6 — Test a deposit (two steps, in order)

Prereqs: creds stored (2), funding bank registered (3) — with an `account_number` matching an OpenFX
fiat withdrawal address (Tesser matches **on account number, at deposit time** — `metadata.openfx`
won't populate before this), VAN seeded (5), and — for an on-ramp to chain — a destination wallet (4).
Run **two deposits in order**, and confirm the first before attempting the second:

1. **Step A — fiat → same fiat** (e.g. **USD → USD**): lands fiat in the OpenFX ledger, no swap.
   Proves the wire → VAN → ledger plumbing before adding complexity.
2. **Step B — fiat → USDC** (e.g. **USD → USDC**): adds the on-ramp (swap to stablecoin). Only after
   Step A confirms.

Create the deposit — `<currency>` is your funding-bank currency; `to.currency` is the **same fiat**
for Step A or `USDC` for Step B; `to.account_id` is the OpenFX Ledger (or a wallet for on-ramp-to-chain).
**Sandbox:** preview this `POST /v1/treasury/deposits` and confirm with the developer before sending (rule 2):
```bash
source "<skill>/scripts/dotenv.sh" && load_openfx_env <sandbox|prod> && mint_tesser_token  # one block (state doesn't persist)
curl -sS -X POST "$TESSER_BASE_URL/v1/treasury/deposits" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" -H "content-type: application/json" \
  -d '{ "desired": {
          "from": { "account_id": "<funding-bank-id>", "amount": "<amount>", "currency": "<currency>" },
          "to":   { "account_id": "<openfx-ledger-id>", "currency": "<same-fiat | USDC>" } } }' | jq .
```
Then `GET /v1/treasury/deposits/{id}` (planned steps) and `…/{id}/instructions` (the VAN wire details).

**Trigger the inbound funds** (the manual step that actually starts the flow):
- **🅢 Sandbox/staging:** in the **OpenFX dashboard → Balances → Deposit funds**, **simulate** a mock
  deposit for that currency/amount — it fires the `deposits` webhook like a real wire. (There is **no
  Tesser-side simulate** for OpenFX; `/v1/treasury/deposits/{id}/simulate` is Circle-only.)
- **🅟 Production:** send a **real transfer/wire** to the VAN details from `…/{id}/instructions`.

OpenFX then fires the `deposits` webhook → Tesser credits the ledger (Step A complete) → for Step B the
swap runs (and, to a wallet, the on-chain withdrawal follows). Confirm completion (below) and the
OpenFX ledger balance **before** moving from Step A to Step B.

**Reading the response — which fields signal completion** (verified against `deposit.schemas.ts` /
`deposits.service.ts` in the platform backend, 2026-06-24). Two gotchas seen in a live run: the deposit
record has **no top-level `status`** field, and steps carry **`step_type`** (snake_case under
`x-api-client: true`), **not** `type` — so `.data.status` and `.data.steps[].type` are always
absent/null. Don't poll those. Completion is derived from the **steps**:

- **Done** when **every** `steps[].status == "completed"` — this mirrors the backend's own gate
  (`deposit.steps.every(s => s.status === "completed")`). The per-step status enum runs
  `created → signature_requested → signed → submitted → confirmed → completed`; **`failed`** is terminal-bad.
- On success the deposit's **`actual.to.{amount,currency}`** populates (the `actual` overlay fills only
  when the last step finalizes; it stays null on failure) — read it for what actually settled.

```bash
source "<skill>/scripts/dotenv.sh" && load_openfx_env <sandbox|prod> && mint_tesser_token  # one block (state doesn't persist)
curl -sS "$TESSER_BASE_URL/v1/treasury/deposits/<id>" \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "x-api-client: true" \
| jq '{
    complete:      (.data.steps | all(.status == "completed")),   # ← the completion signal
    any_failed:    (.data.steps | any(.status == "failed")),
    steps:         [.data.steps[] | {step_type, status}],         # field is step_type, NOT type
    settled:       .data.actual.to                                # {amount, currency, …} once complete
  }'
```
`complete: true` with `settled.amount` populated = the deposit settled. (Step A has one `transfer`
step; Step B adds a `swap` step — both must reach `completed`.)

- `amount` must clear OpenFX's per-currency minimum (e.g. **MXN ≥ 1000**) or `/trade` 400s.
- On-ramp **to a self-custodial wallet**: set `to.account_id` to the wallet and add `"network"`
  (sandbox testnets e.g. `BASE_SEPOLIA`; prod mainnets e.g. `BASE`).
- **✅ Validated end-to-end in sandbox (2026-06-24):** Step A (USD→USD) and Step B (USD→USDC, with the
  swap leg) both reached `completed` — `100 USD → 99.9925 USDC`, all steps `completed`. The webhook
  that 404'd on 2026-06-23 is now delivered/processed in sandbox. **Production delivery still to be
  confirmed.** `/v1/treasury/deposits/{id}/simulate` remains Circle-only (OpenFX uses the dashboard
  simulate / a real wire).

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
| Deposit stalls after planning (steps stuck `created`) | OpenFX webhook not being delivered. Sandbox route resolved 2026-06-24 (deposits complete); if it recurs, confirm `/v1/webhooks/openfx/{workspaceId}` is deployed for the env (prod unconfirmed) |
| Offline (can't fetch live docs) | Proceed with embedded secrets contract; verify account shapes when back online |

## References

- `references/openfx-dashboard-steps.md` — OpenFX dashboard: API key JSON, webhook, bank/wallet registration.
- `references/tesser-secrets-endpoint.md` — internal `POST /v1/organizations/secrets` contract.
- `references/live-sources.md` — live docs to fetch (auth, accounts, deposits, OpenAPI, OpenFX docs).
