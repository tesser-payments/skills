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
| `bank_swift_code` | the `swiftCode` if present (SWIFT currencies), else omit |
| `bank_code_type` | per currency — see below |
| `bank_identifier_code` | per currency — see below |
| `tenant_id`, `counterparty_id` | `null` |

`bank_code_type` / `bank_identifier_code` per currency:

- **MXN — validated** (a created record that matched OpenFX looked like:
  `fiat_bank_code_type: "CLABE"`, `fiat_bank_identifier_code: "111"`): use
  `bank_code_type: "CLABE"`, `bank_identifier_code: "111"`.
- **USD / AED / GBP / EUR** (SWIFT): `bank_code_type: "SWIFT"`, `bank_identifier_code: "<swiftCode>"`
  (`FAKEUSXX`). **USD create verified live 2026-06-24** (accepted, stored correctly). The OpenFX
  **match is async** — `metadata.openfx` is empty right after create and populates later (the MXN
  example matched ~18 min post-create), so don't treat empty metadata as failure.
- **AUD / BRL / PHP** (NPP / PIX / PESONET): code type **not yet validated** in sandbox. Attempt the
  rail-appropriate type, read the API response, and correct from its error if rejected. Prefer **MXN**
  for a known-good sandbox run.

> The known-working Tesser record (MXN) for reference — note `metadata.openfx.matchedAt` +
> `fiatWithdrawalAddressId` appear once Tesser matches the bank to the OpenFX fiat withdrawal address:
> ```json
> { "type":"fiat_bank", "name":"Sandbox MXN Account", "fiat_bank_name":"Sandbox Bank",
>   "fiat_bank_code_type":"CLABE", "fiat_bank_identifier_code":"111", "fiat_bank_swift_code":null,
>   "metadata":{"openfx":{"kind":"bank","status":"active","verified":true,
>     "matchedAt":"…","fiatWithdrawalAddressId":"…"}} }
> ```
> (Request fields are `bank_*`; the stored/response shape is `fiat_bank_*`.)
