# Live sources — fetch these, don't copy them

Everything publicly documented should be **fetched at runtime** rather than frozen into this repo.
Endpoint shapes drift; the live docs are the source of truth. Embed only what an agent cannot fetch
(the internal secrets endpoint — see `tesser-secrets-endpoint.md`).

## LLM-friendly docs

| Source | URL | Use for |
|---|---|---|
| Index | `https://docs.tesser.xyz/llms.txt` | Map of available docs |
| Full docs | `https://docs.tesser.xyz/llms-full.txt` | Auth flow, accounts, deposits — full prose |
| OpenAPI schema | `https://docs.tesser.xyz/api/v1/schema.json` | Exact request/response shapes to verify before any write |
| MCP endpoint | `https://sandbox.tesserx.co/v1/mcp` | Tool-based execution (deferred to a fast-follow; not used in v1) |

## OpenFX-side sources (third-party)

| Source | URL | Use for |
|---|---|---|
| OpenFX dashboard | `https://app.openfx.com` | Create API key, register webhook, approve addresses |
| OpenFX API docs | `https://docs.openfx.com` | OpenFX HTTP API, JWT (ES256), sandbox specifics |

The manual OpenFX dashboard steps are captured in `openfx-dashboard-steps.md` (sourced from the
internal OpenFX integration handoff at `~/Documents/openfx 2` — tertiary source of truth, behind
Tesser docs and Tesser platform code).

## Specific pages worth fetching

- **Authentication** — section of `llms-full.txt`. Auth0 client-credentials flow; how to get the
  `access_token`. Sandbox audience is `https://sandbox.tesserx.co`.
- **Create an account** — `https://docs.tesser.xyz/how-tos/create-an-account` — bank/wallet/ledger
  account fields for Phase 3.
- **Liquidity providers overview** — `https://docs.tesser.xyz/overviews/liquidity-providers`.
- **Deposit funds via a liquidity provider** —
  `https://docs.tesser.xyz/how-tos/deposit-funds-via-a-liquidity-provider` — the next step after
  onboarding.

## When to fetch

- Phase 0: fetch the OpenAPI schema (and the auth section if env vars are unclear) to confirm current
  shapes before constructing any call.
- Phase 3: fetch `create-an-account` to confirm the current bank-account payload fields.

If offline, proceed only with the embedded secrets contract; warn that `/accounts` shapes could not
be verified against live docs.
