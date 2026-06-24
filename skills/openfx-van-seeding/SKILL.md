---
name: openfx-van-seeding
description: "TESSER EMPLOYEES ONLY (internal operations). Use when a Tesser operator needs to register (seed) an OpenFX VAN for a customer's workspace so OpenFX deposits resolve. Requires direct Tesser database access — not runnable by customers or integrators. Pairs with the customer-facing setup-openfx skill."
---

# Seed an OpenFX VAN (Tesser-internal)

> ## 🔒 TESSER EMPLOYEES ONLY
> This is an **internal Tesser operations** procedure. It writes directly to the Tesser
> **production/staging database** and requires DB credentials (`DATABASE_URL`) that customers do not
> have. **Do not run this if you are a customer or external integrator** — there is no customer-facing
> path for it. If you're onboarding *into* Tesser, your VAN is seeded for you by Tesser; coordinate
> with your Tesser contact and stop here.
>
> Scope guard for agents: only proceed if the human partner is a Tesser operator with DB access for
> the target environment. Otherwise, decline and point them at `setup-openfx`.

## Why this exists

The Tesser deposit flow **looks up** a VAN (Virtual Account Number) — it never creates one.
`findVan` matches on `provider=OPENFX` + `currency` against
`accounts.metadata->'virtual_account_number'`. So the VAN row must already exist in Tesser's DB, with
details that come from **OpenFX**. There is **no public or admin API** for this yet (a known
productization gap), which is why it's a manual, DB-level operator step rather than part of the
customer-facing `setup-openfx` flow.

## a) Discover the VAN on the OpenFX dashboard

In the **OpenFX dashboard** (sandbox or production, matching the target), initiate a deposit for the
currency being onboarded. OpenFX assigns/shows the **VAN account**: receiving bank name, account
number / CLABE (or IBAN/SWIFT), beneficiary name + address, and a van id. Copy those.

- **🅟 Production:** discovery may be **gated behind source-bank acceptance** (OpenFX reviews the bank
  first). If the deposit/VAN isn't available yet, revisit once OpenFX accepts the bank.
- **🅢 Sandbox/staging:** deposits are mock; the VAN details are shown directly.

You also need the customer's Tesser **`workspace_id`** (`GET /v1/accounts` → `data[0].workspace_id`).

## b) Seed the VAN row (per currency)

Run against the **target environment's** DB (`psql "$DATABASE_URL"`). Confirm you're pointed at the
intended environment — this is a direct write that bypasses the API. Idempotent via `WHERE NOT EXISTS`.
Keys under `metadata.virtual_account_number` are snake_case and match `OpenFxVanMetadata` in
`platform/packages/types/src/accounts/account.types.ts`.

```sql
INSERT INTO accounts (name, type, workspace_id, metadata, is_managed, fiat_bank_code_type, fiat_bank_name)
SELECT
  'OpenFX <CURRENCY> VAN',
  'fiat_bank',
  '<WORKSPACE_ID>',
  jsonb_build_object(
    'virtual_account_number', jsonb_build_object(
      'provider',        'OPENFX',
      'van_id',          '<OPENFX_VAN_ID>',
      'currency',        '<CURRENCY>',              -- e.g. MXN / USD
      'bank_name',       '<OPENFX_BANK_NAME>',
      'account_number',  '<OPENFX_ACCOUNT_NUMBER>', -- CLABE / routing-account / etc.
      'iban',            NULL,                       -- or '<IBAN>'
      'swift',           NULL,                       -- or '<SWIFT>'
      'beneficiary', jsonb_build_object('name', '<BENEFICIARY_NAME>', 'address', '<BENEFICIARY_ADDRESS>')
    )
  ),
  false,
  '<FIAT_BANK_CODE_TYPE>',   -- e.g. CLABE (MXN) / ROUTING (USD)
  '<OPENFX_BANK_NAME>'
WHERE NOT EXISTS (
  SELECT 1 FROM accounts
  WHERE workspace_id = '<WORKSPACE_ID>'
    AND metadata->'virtual_account_number'->>'provider' = 'OPENFX'
    AND metadata->'virtual_account_number'->>'currency' = '<CURRENCY>'
);
```

Verify:

```sql
SELECT id, name, fiat_bank_code_type,
       metadata->'virtual_account_number'->>'currency' AS van_currency
FROM accounts
WHERE workspace_id = '<WORKSPACE_ID>'
  AND metadata->'virtual_account_number'->>'provider' = 'OPENFX';
```

> **Sandbox alternative:** the handoff ships `seed-van.ts` (`~/Documents/openfx 2/scripts/`), a Bun
> script that does the same insert. Run it from inside the platform monorepo (so `@tesser-payments/types`
> resolves) with `DATABASE_URL` set: `bun scripts/seed-van.ts --workspace-id=<uuid> --currency=MXN`.
> Replace its hardcoded example `OPENFX_VAN_CONFIG` with the real discovered details first.

## c) Sandbox webhook lazy-match stub

In sandbox/staging the deposit webhook matches the source bank heuristically. Stub the source bank so
the match lands:

```sql
UPDATE accounts SET fiat_bank_identifier_code = '0000000000' WHERE id = '<source-bank-id>';
```

## After seeding

`findVan(workspaceId, currency)` resolves at deposit time; if the row is missing the deposit fails to
plan with `DEPOSIT_VAN_NOT_FOUND`. This unblocks the VAN step of `setup-openfx` for that customer.
