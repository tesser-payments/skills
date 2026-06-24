# Sandbox funding-bank values (staging/sandbox only)

In **sandbox/staging**, the funding bank is one of OpenFX's pre-seeded sandbox accounts (org
`3010020d-…`). The skill asks the developer **which currency** they want, then registers the matching
bank with Tesser via `POST /v1/accounts/banks`. (In **production** the customer supplies their real
bank and OpenFX reviews it — this table does not apply.)

## OpenFX sandbox bank accounts (source data)

All share `bankName: "Sandbox Bank"`, `accountNumber: "0000000000"`, `status: active`, `verified: true`.

| currency | accountName | transferType | swiftCode |
|---|---|---|---|
| USD | Sandbox USD Account | SWIFT | FAKEUSXX |
| AED | Sandbox AED Account | SWIFT | FAKEUSXX |
| GBP | Sandbox GBP Account | SWIFT | FAKEUSXX |
| EUR | Sandbox EUR Account | SWIFT | FAKEUSXX |
| AUD | Sandbox AUD Account | NPP | — |
| MXN | Sandbox MXN Account | SPEI | — |
| BRL | Sandbox BRL Account | PIX | — |
| PHP | Sandbox PHP Account | PESONET | — |

## Mapping → `POST /v1/accounts/banks` request

| request field | value |
|---|---|
| `name` | the `accountName` (e.g. `"Sandbox MXN Account"`) |
| `bank_name` | `"Sandbox Bank"` |
| `bank_account_number` | `"0000000000"` |
| `bank_code_type` | the currency's **domestic rail** — e.g. `ROUTING` (USD), `CLABE` (MXN). See below. |
| `bank_identifier_code` | the rail identifier (ABA routing #, CLABE, etc.) — **required, non-empty** (API rejects null/empty) |
| `bank_swift_code` | the bank's SWIFT/BIC if it has one — set it **alongside** the domestic rail (USD sandbox is ROUTING **and** sets `FAKEUSXX`); `null` only when there's no SWIFT (e.g. MXN) |
| `tenant_id`, `counterparty_id` | `null` |

> **Use the currency's real domestic rail, not the OpenFX list's `transferType`/`swiftCode`.** The
> OpenFX source table below is informational; the Tesser bank uses the customer's actual rail values
> (USD → `ROUTING` + ABA number; MXN → `CLABE`). A SWIFT/BIC goes in `bank_swift_code` when the account
> has one — it can coexist with a domestic rail (USD sandbox is `ROUTING` **and** sets `FAKEUSXX`).
>
> **How the OpenFX match actually works** (per `platform/.../openfx/adapters/openfx.bank-adapter.ts`,
> read 2026-06-24): Tesser matches the bank to an OpenFX fiat withdrawal address **on the bank
> `accountNumber`** (`address.accountNumber === effectiveAccountNumber`) — **not** on swift or
> identifier. And the match runs **at deposit time** (the deposit adapter calls `ensureBankRegistered`
> during planning), **not** at bank creation and **not** on a timer — so `metadata.openfx` stays empty
> until the first deposit. (All sandbox accounts share `accountNumber: "0000000000"`, so the match is
> ambiguous and takes the first record — a sandbox quirk; real prod accounts have distinct numbers.)
>
> **⚠️ API limitation (probed 2026-06-24):** `bank_identifier_code` is required/non-empty at create
> (`banks-1001`), `PATCH {…:null}` → `500 "No values to set"`, and accounts have **no delete** — so
> `fiat_bank_identifier_code: null` can't be produced via the API. Per the match code above this does
> **not** affect matching (account-number keyed), but get correct field placement anyway: the swift
> code goes in `bank_swift_code`.

`bank_code_type` / `bank_identifier_code` / `bank_swift_code` per currency:

- **USD — validated 2026-06-24:** `bank_code_type: "ROUTING"`, `bank_identifier_code: "021000021"`
  (a valid ABA routing number), **and** `bank_swift_code: "FAKEUSXX"`. US uses the **ROUTING** rail
  **and** also carries the SWIFT/BIC — set all three. Created live (`33980dc4`).
- **MXN — validated:** `bank_code_type: "CLABE"`, `bank_identifier_code: "111"`, `bank_swift_code: null`.
- **AED / GBP / EUR / AUD / BRL / PHP:** use that currency's domestic rail + identifier (and a
  `bank_swift_code` only if it's genuinely a SWIFT bank). **Not yet validated** — confirm the real
  values with the team. Prefer **USD** or **MXN** for a known-good sandbox run.

> The known-working Tesser record (MXN) for reference — note `metadata.openfx.matchedAt` +
> `fiatWithdrawalAddressId` appear once Tesser matches the bank to the OpenFX fiat withdrawal address:
> ```json
> { "type":"fiat_bank", "name":"Sandbox MXN Account", "fiat_bank_name":"Sandbox Bank",
>   "fiat_bank_code_type":"CLABE", "fiat_bank_identifier_code":"111", "fiat_bank_swift_code":null,
>   "metadata":{"openfx":{"kind":"bank","status":"active","verified":true,
>     "matchedAt":"…","fiatWithdrawalAddressId":"…"}} }
> ```
> (Request fields are `bank_*`; the stored/response shape is `fiat_bank_*`.)
