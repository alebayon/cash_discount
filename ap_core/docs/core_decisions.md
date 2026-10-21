# ap_core — decisions log

Record durable choices for the **shared AP knowledge model** (`ap_core`).
Built inside the `cash_discount` workspace until extracted as a dbt package; consumed by cash_discount, on_time_payment, working_capital, and later products.

**Related:** Cash-discount–only policy and curriculum → `docs/decisions.md` (legacy log until CD is refactored onto product extensions).

---

## Project context

- **Package / layer name:** ap_core (dbt tag: `core`)
- **Purpose:** Durable SAP invoice facts, payment terms and dates, Coupa process evidence, cross-system mapping, neutral timing spans, observed blocker intervals, and shared CD/WCO arbitration policy. No product KPI funnels (CD leakage, OTP late, WCO strategy compliance).
- **Workspace (staging):** `C:\dbt\cash_discount` — core models live under `models/` with tag `core` until Phase 2 extract.
- **Grain anchor:** One row per in-scope SAP vendor invoice, keyed by `sap_inv_key`.
- **Calendar:** Calendar days throughout v0 (Snowflake `datediff('day', …)`), consistent with CD decisions D6.

---

## Architecture

### Repositories and dependencies (target)

```
ap_core  ──►  cash_discount
ap_core  ──►  on_time_payment
ap_core  ──►  working_capital
ap_core  ──►  daily_ops (later)
```

- Products **do not** depend on each other for primary KPIs (OTP does not use CD; WCO does not require CD leakage models).
- Shared **CD/WCO arbitration** lives in core; CD and WCO **consume** it; OTP does **not** use arbitration.
- Cross-product reporting may combine marts later; no circular package dependencies.

### Layering (in this repo, pre-extract)

| Layer | Folder | Materialization | Naming |
|-------|--------|-----------------|--------|
| Staging | `models/src/` | view | `src_*` |
| Intermediate | `models/int/` | ephemeral | `int_*` |
| Dimensions | `models/dim/` | table | `dim_*` |
| Maps | `models/map/` | table | `map_*` |
| Facts | `models/fct/` | table | `fct_*` |

Product-specific models stay in this repo under product dbt tags (e.g. `cash_discount`) until repos split.

### SAP invoice fact naming

- **Pattern:** `fct_inv_sap_<suffix>` on the same grain (`sap_inv_key`).
- **`_sap`** — SAP is the authoritative invoice source; all extensions are SAP invoice–grain facts.
- **Suffixes:** `core` (shared spine), `cd`, `otp`, `wco`, etc. Short product codes, not full repo names.
- **Extensions:** `ref('fct_inv_sap_core')` + product-specific columns. Reject one wide `fct_inv_sap` with all product fields.
- **Legacy shim:** `fct_inv_sap` → `ref('fct_inv_sap_cd')` until deprecated and refs migrate.

### Invoice spine (same grain, separate models)

| Model | Owner | Role |
|-------|--------|------|
| `fct_inv_sap_core` | core | Facts, terms, dates, map-based Coupa fields, neutral elapsed days |
| `fct_inv_sap_cd` | cash_discount | CD eligibility, arbitration consumption, reporting period, leakage funnel, V6 |
| `fct_inv_sap_otp` | on_time_payment (later) | Net-due lateness, OTP reporting period |
| `fct_inv_sap_wco` | working_capital (later) | Strategy compliance vs `pursue_cd` / `target_net` |

### SAP vs Coupa

| System | Core responsibility |
|--------|---------------------|
| **SAP** | Invoice identity, amounts, baseline/payment terms, posting/entry/clearing dates, discount posted at clearing, clearing flags |
| **Coupa** | Pre-SAP receipt/workflow evidence, statuses, change history |

**Cross-system rule:** Enrich SAP invoices with Coupa `coupa_id` and `receipt_date` only through **`map_inv_sap_coupa`**. `coupa_posting_ref` on SAP is a matching input, not a substitute for the map.

### Timing boundary

**Core (neutral / observed):**

- `fct_inv_timing_span` — ownership and subprocess intervals
- `int_inv_coupa_overlay_intervals`, `int_inv_sap_payment_block_intervals`
- `fct_inv_timing_overlay_observed` — union of observed Coupa + SAP block intervals only
- `fct_inv_timing_overlay_span_observed` — overlap of observed intervals with neutral spans

**Not in core:**

- `payment_run_wait` (CD payment window remainder; depends on discount deadline, leakage, V6 `payment_execution` population)
- Timing euro allocation (lost discount — CD measure)

CD keeps full overlay union, allocation, and timing marts.

### dbt selection

Use **ancestors** of a product tag: `dbt build --select +tag:cash_discount` (leading `+`).
Do not use `tag:cash_discount+` when the goal is to build upstream core first.

### Implementation sequence (reference)

0. Document contract (this file)
1. Split `fct_inv_sap_core` + `fct_inv_sap_cd` inside `cash_discount`; keep curriculum green
2. Arbitration curriculum + shared policy model
3. Extract `ap_core` package v0.1.0
4. Pin package from `cash_discount`; remove duplicated core
5. CI + semver contracts
6. Build OTP against core only

---

## Open questions

- Production source and definition for `receipt_date` (synthetic v0 uses Coupa `created_at` on mapped invoices).
- **Terms at clearing / effective-dated payment terms** — rebuilds can change `discount_deadline_date` and `net_due_date` if terms are read as current state; document limitation for v0; design history before production-grade OTP/CD audit claims.
- Authoritative date for arbitration policy version if `document_date` is replaced later.

---

## Decisions

### 2026-10-20 — ap_core scope and product boundaries [ARCHITECTURE]

**Context:** Multiple AP products will share the same SAP invoice grain. CD logic currently lives in a monolithic `fct_inv_sap`.

**Decision:** Introduce `ap_core` as the shared layer: facts, contractual terms/dates, process evidence, neutral timing, shared arbitration. Products add eligibility, KPI scope, and outcomes. Build core inside `cash_discount` before package extract.

**Why:** Avoid duplicate pipelines across repos; keep product denominators and policies independent.

**Impact:** New `fct_inv_sap_core`; CD refactor to `fct_inv_sap_cd`; future OTP repo depends only on `ap_core`.

---

### 2026-10-20 — `fct_inv_sap_core` public contract (v0) [CONTRACT]

**Context:** Consumers need a stable invoice spine without product KPIs.

**Decision:** Core exposes at minimum:

- **Identity / SAP:** `sap_inv_key`, `doc_number`, `company_code`, `fiscal_year`, `vendor_id`, `document_type`, `baseline_date`, `payment_terms`, `invoice_amount`, `invoice_amount_eur`, `currency_code`, `document_fx_rate`, `posting_date`, `sap_entry_date`, `document_date`, `clearing_date`
- **Terms:** `discount_pct`, `discount_days`, `discount_deadline_date`, `net_days`, `net_due_date`
- **Payment facts:** `discount_taken_amount`, `discount_taken_amount_eur`, `do_not_take_skonto_at_clearing`
- **Cross-system:** `coupa_posting_ref`, mapped `coupa_id`, mapped `receipt_date`
- **Lifecycle:** `is_cleared`
- **Neutral elapsed:** `pre_sap_elapsed_days` (receipt → sap_entry), `actual_cycle_days` (receipt → clearing)

EUR amounts use document-date FX; `invoice_amount_eur` is stable on rebuild for a given document.

**Rejected on core:** `is_paid_in_period`, `is_entitled`, `is_kpi_entitled`, `is_taken`, `is_excluded`, `is_leakage`, lost discount, OTP/WCO flags, Version 6 attribution fields, `primary_cause`.

**Why:** Reporting period and product classification are product-owned; core stays durable across products.

**Impact:** Column list for `fct_inv_sap_core.sql` and `_fct__models.yml`; products derive period gates from `clearing_date` + vars.

---

### 2026-10-20 — Vendor dimensions retain inactive records [POLICY]

**Context:** Historical invoices must keep valid vendor keys after deactivation.

**Decision:** `dim_vendor_sap` and `dim_vendor_coupa` retain inactive/deleted suppliers; expose `is_active` (or equivalent). Do not filter them out of core dimensions.

**Impact:** May diverge from current CD dims that filter active-only until core dims are adopted.

---

### 2026-10-20 — CD/WCO arbitration v1 in core [POLICY]

**Context:** Some terms-eligible invoices should not be CD targets (immaterial saving or excessive cash acceleration).

**Decision:** Core holds `seed_cd_wco_arbitration_policy` and a shared arbitration model (grain `sap_inv_key`). v1 parameters:

- `minimum_potential_discount_eur` = 10
- `maximum_cash_acceleration_days` = 20 (inclusive)

Derived:

- `potential_discount_eur` = `invoice_amount_eur * discount_pct`
- `cash_acceleration_days` = calendar days from `discount_deadline_date` to `net_due_date`
- `is_cd_eligible` (for CD consumption) = terms eligible AND amount gate AND acceleration gate (AND, no compensation)
- `payment_strategy` = `pursue_cd` | `target_net`
- `not_cd_eligible_reason` per handoff vocabulary

Policy version selected by effective date; v1 evaluation date = `document_date`.

**Not in v1:** hurdle rates, vendor overrides, weighted scoring, single gate overriding the other.

**Impact:** Seed + model in core; `fct_inv_sap_cd` consumes; OTP ignores.

---

### 2026-10-20 — OTP v1 rule (documented for core consumers) [POLICY]

**Context:** OTP will be a separate product on core only.

**Decision:** OTP v1 uses `net_due_date` and `clearing_date` from core. `otp_grace_days` default 0. `is_late` when `days_after_net_due > otp_grace_days`. No CD arbitration in OTP v1.

**Impact:** Core must ship valid `net_due_date`; OTP repo not started until core contract tested.

---

### 2026-10-21 — SAP invoice product fact naming [CONVENTION]

**Context:** Product extensions share SAP invoice grain; naming should reflect SAP as source and use short product suffixes.

**Decision:**

- Shared spine: `fct_inv_sap_core`
- Cash discount extension: `fct_inv_sap_cd` (dbt tag remains `cash_discount`)
- Future: `fct_inv_sap_otp`, `fct_inv_sap_wco`
- Legacy compatibility: `fct_inv_sap` is a deprecated shim to `fct_inv_sap_cd` until removed

**Rejected:** `fct_inv_cash_discount` as the long-term model name (product code `_cd` aligns with `_core`).

**Impact:** Rename `fct_inv_cash_discount.sql` → `fct_inv_sap_cd.sql` and update refs; YAML and tests follow.

---

## Model inventory

Update row counts after `dbt build`.

| Object | Layer | Grain | Status | Notes |
|--------|-------|-------|--------|-------|
| `src_*` | src | per source | existing | Tagged `core` in dbt_project.yml |
| `dim_vendor_sap` | dim | vendor | existing | Move to retain inactive + `is_active` (later) |
| `dim_vendor_coupa` | dim | supplier | existing | Same |
| `map_inv_sap_coupa` | map | (sap_inv_key, coupa_id) | existing | 21 rows; SAP side from `src_inv_sap` + `fct_inv_coupa` |
| `fct_inv_coupa` | fct | coupa invoice | existing | |
| `fct_inv_coupa_changes` | fct | change event | existing | |
| `fct_inv_sap_changes` | fct | change event | existing | |
| `seed_payment_term_sap` | seed | ZTERM | existing | Includes `net_days` |
| `seed_cd_wco_arbitration_policy` | seed | policy version | planned | |
| `fct_inv_sap_core` | fct | sap_inv_key | existing | 24 rows; tag `core`; public contract v0 |
| `fct_inv_timing_span` | fct | span grain | existing | Core (not yet refactored to core-only deps) |
| `int_inv_coupa_overlay_intervals` | int | interval | existing | Core |
| `int_inv_sap_payment_block_intervals` | int | interval | existing | Core |
| `fct_inv_timing_overlay_observed` | fct | overlay interval | planned | Observed only |
| `fct_inv_timing_overlay_span_observed` | fct | overlap | planned | |
| `int_*` / `fct_*` arbitration | core | sap_inv_key | planned | Name TBD |
| `fct_inv_sap_cd` | fct (CD) | sap_inv_key | in progress | CD logic built; SQL file still `fct_inv_cash_discount` until rename |

---

## Conventions (stable)

- **Decision file:** This file is authoritative for core grains, columns, and shared policy.
- **SAP invoice facts:** `fct_inv_sap_<suffix>` (`core`, `cd`, `otp`, `wco`); same `sap_inv_key` grain.
- **Tag:** `core` on models that move to `ap_core` package; product tags (e.g. `cash_discount`) on CD models/marts.
- **Keys:** `sap_inv_key` on SAP invoice facts; map tests guard orphan keys.
- **Handoff:** Proposed changes to this file = one full copy-paste block per dated entry. Proposed SQL/YAML/seeds = complete file contents (see `.cursor/rules/project.mdc`).
- **Model inventory:** Update the table when adding or completing a core model.
- **Versioning (post-extract):** Semantic versioning for `ap_core`; products pin releases in `packages.yml`.

---

## Chat handoff notes

Last updated: 2026-10-21

`fct_inv_sap_core` built (24 rows); map on `src_inv_sap`; CD logic on `fct_inv_cash_discount` (rename to `fct_inv_sap_cd` per 2026-10-21 convention). Next: rename + `fct_inv_sap` shim, then full `dbt build`.
