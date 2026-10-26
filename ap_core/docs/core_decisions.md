# ap_core — decisions log

Record durable choices for the **shared AP knowledge model** (`ap_core`).
Extracted as dbt package **v0.1.0** ([`alebayon/ap_core`](https://github.com/alebayon/ap_core)); consumed by cash_discount, on_time_payment, working_capital, and later products.

**Related:** Cash-discount–only policy and curriculum → `docs/decisions.md` (legacy log until CD is refactored onto product extensions).

---

## Project context

- **Package / layer name:** ap_core (dbt tag: `core`)
- **Purpose:** Durable SAP invoice facts, payment terms and dates, Coupa process evidence, cross-system mapping, neutral timing spans, observed blocker intervals, and shared CD/WCO arbitration policy. No product KPI funnels (CD leakage, OTP late, WCO strategy compliance).
- **Package repo:** `https://github.com/alebayon/ap_core` (local dev: `C:\dbt\ap_core`). **cash_discount** pins the package in root `packages.yml`; core SQL/seeds no longer live in the product repo.
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

### Fact naming (spine pairs vs in-repo-only)

| Pattern | When | Examples |
|---------|------|----------|
| `fct_inv_sap_core` + `fct_inv_sap_<product>` | SAP invoice grain; cross-repo contract | `fct_inv_sap_cd`, later `fct_inv_sap_otp` |
| `fct_inv_timing_overlay_core` + `fct_inv_timing_overlay_<product>` | Overlay interval grain; observed in core, CD adds derived rows | `fct_inv_timing_overlay_cd` (`payment_run_wait`) |
| No product suffix | Core building blocks, or product-only models with no core pair | `map_inv_sap_coupa`, `mart_cash_discount_kpi`, `fct_inv_timing_allocation` |

dbt tags (`core`, `cash_discount`, …) drive builds; suffixes mark **cross-package spine pairs**, not every file in a product folder.

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
- `fct_inv_timing_overlay_core` — union of observed Coupa + SAP block intervals only (built)
- `fct_inv_timing_overlay_span_observed` — overlap of observed intervals with neutral spans (planned)

**Not in core:**

- `payment_run_wait` (CD payment window remainder; depends on discount deadline, leakage, V6 `payment_execution` population)
- Timing euro allocation (lost discount — CD measure)

CD keeps full overlay union, allocation, and timing marts.

### dbt selection

Use **ancestors** of a product tag: `dbt build --select +tag:cash_discount` (leading `+`).
Do not use `tag:cash_discount+` when the goal is to build upstream core first.

### Implementation sequence (reference)

0. Document contract (this file)
1. Split `fct_inv_sap_core` + `fct_inv_sap_cd` inside `cash_discount`; keep curriculum green — **done** (shims removed 2026-10-23)
2. Arbitration curriculum + shared policy model — **done** (2026-10-23); labeled heroes 5100000015 / 5100000016 / 5100000026 (see 2026-10-23 CD KPI funnel)
3. Extract `ap_core` package v0.1.0 — **done** (2026-10-26); tag `v0.1.0` on GitHub
4. Pin package from `cash_discount`; remove duplicated core — **done** (2026-10-26); `ref('ap_core', …)` on CD facts; `dbt build --select +tag:cash_discount` green
5. CI + semver contracts
6. Build OTP against core only

---

## Open questions

- Production source and definition for `receipt_date` (synthetic v0 uses Coupa `created_at` on mapped invoices).
- **Terms at clearing / effective-dated payment terms** — rebuilds can change `discount_deadline_date` and `net_due_date` if terms are read as current state; document limitation for v0; design history before production-grade OTP/CD audit claims.
- Authoritative date for arbitration policy version if `document_date` is replaced later.
---

## Decisions

### 2026-10-26 — ap_core package v0.1.0 extract and cash_discount pin [ARCHITECTURE]

**Context:** Steps 3–4 of implementation sequence; avoid duplicate warehouse objects and split-brain core edits.

**Decision:**

- Publish shared AP as dbt package **`ap_core`** v0.1.0 (models, seeds, core tests, `docs/core_decisions.md`).
- **cash_discount** depends via root `packages.yml` + `dbt deps`; product models use `ref('ap_core', '<model>')` for core nodes.
- Product repo retains only CD layer: `fct_inv_sap_cd`, timing overlay `_cd`, allocation, overlay span, marts, `int_attribution_policy_active`, `seed_attribution_policy`.

**Consumer build:** `dbt build --select +tag:cash_discount` (builds package ancestors first).

**Impact:** Core changes ship in `ap_core` with semver tags; bump `revision` in `packages.yml` to adopt releases. Next: step 5 CI + semver contracts.

### 2026-10-21 — Model naming: ap_core vs product extensions [CONVENTION]

**Context:** Monorepo today; later `ap_core`, `cash_discount`, `on_time_payment`, and other product repos. Need scannable names without redundant suffixes on every CD model.

**Decision:**

**ap_core (tag `core`; future `ap_core` package)**

- Use **`_core`** on **spine facts** that have a matching product extension at the **same grain** and are part of the **cross-repo public contract**.
  - Examples: `fct_inv_sap_core`, `fct_inv_timing_overlay_core` (observed Coupa + SAP block intervals only).
- Other core models (`src_*`, `dim_*`, `map_*`, `int_*`, `fct_inv_coupa`, …): **no product suffix** — ownership is core via tag / package.

**Product repos (e.g. tag `cash_discount`; future `cash_discount` repo)**

- Use **`_<product>`** (e.g. **`_cd`**) only when the model **structurally depends on** a published ap_core model (extension or union on top of core at the same grain).
  - Examples: `fct_inv_sap_cd` → `ref('fct_inv_sap_core')`; `fct_inv_timing_overlay_cd` → `ref('fct_inv_timing_overlay_core')` plus CD-only logic (e.g. `payment_run_wait`).
- **Do not** suffix CD-only models that live entirely in the product repo and do not form a `_core` / `_<product>` pair with ap_core.
  - Examples: `mart_cash_discount_kpi`, `fct_inv_timing_allocation`, CD-only ints — **no `_cd`**; repo (later) and dbt tag identify ownership.

**Future products:** same pattern — `fct_inv_sap_otp`, `fct_inv_sap_wco` only where they extend `fct_inv_sap_core`; marts and secondary facts in those repos without `_otp` / `_wco` unless useful for clarity.

**No unsuffixed alias models:** use explicit spine pairs (`*_core` / `*_cd` on the same stem). Temporary pass-through shims are discouraged; if needed during a migration, remove them once refs and tests point at canonical models (see 2026-10-23).

**Lineage:** “Extends core” vs “CD-only” is **not** encoded with a second naming flag (e.g. double suffix). Use paired names (`*_core` / `*_cd` on the same stem), `ref()` lineage, and model inventory.

**Why:** Cross-repo contracts stay explicit; in-repo-only models stay short; multi-repo layout replaces folder scanning for marts and ancillary facts.

**Impact:** Invoice and timing overlay splits are implemented: `fct_inv_sap_core` / `fct_inv_sap_cd`, `fct_inv_timing_overlay_core` / `fct_inv_timing_overlay_cd`.

### 2026-10-22 — Deprecated shim dependency guard [CONVENTION]

**Context:** `fct_inv_sap` and `fct_inv_timing_overlay` remain as pass-through shims while the repo migrates to `fct_inv_sap_cd` and `fct_inv_timing_overlay_cd`.

**Decision:** Run `assert_no_deprecated_model_dependencies()` on every `dbt run` / `test` / `build` via `on-run-start`. Any model, test, analysis, or snapshot that depends on a shim fails at compile time. Shims may only `ref()` their canonical replacements.

**Why:** Makes shim removal a safe delete of two SQL files once CI is green; prevents new refs from re-coupling the DAG.

**Impact:** `macros/assert_no_deprecated_model_dependencies.sql` and `on-run-start` hook (temporary).

**Status (2026-10-23):** Completed. Shims `fct_inv_sap` and `fct_inv_timing_overlay` deleted; macro and hook removed after green `dbt build`. Historical record only — do not reintroduce without a new dated decision.

### 2026-10-23 — Legacy shim models removed [CONVENTION]

**Context:** Migration from monolithic `fct_inv_sap` / `fct_inv_timing_overlay` to spine pairs finished; compile-time guard (2026-10-22) confirmed zero downstream refs.

**Decision:** Delete deprecated pass-through models `fct_inv_sap` and `fct_inv_timing_overlay`, their YAML stubs, and `assert_no_deprecated_model_dependencies`. Canonical models are `fct_inv_sap_cd` and `fct_inv_timing_overlay_cd` only.

**Why:** Remote repo is treated as production-ready; no alias layer in the DAG reduces confusion before `ap_core` package extract.

**Impact:** No `ref('fct_inv_sap')` or `ref('fct_inv_timing_overlay')` in the project. Future temporary aliases require explicit inventory + removal plan.

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

**Impact:** Implemented in monorepo (2026-10-24). SAP: `is_active` = `deletion_flag is null` (LOEVM). Coupa: `is_active` = `status = 'active'`; `status` on dim. Marts filter `is_active` when current supplier lists are needed.

**Status (2026-10-24):** **done.** Curriculum inactive heroes: SAP `0000100005`, Coupa `9000005`. Row counts: SAP 8 (7 active), Coupa 7 (6 active).

---

### 2026-10-24 — Vendor dimensions: inactive rows on dim [CONVENTION]

**Context:** Core policy (2026-10-20) required historical vendor keys on dims; CD dims previously filtered to active-only.

**Decision:** Remove active-only `where` clauses from `dim_vendor_sap` and `dim_vendor_coupa`. Expose `is_active` on both; add `status` on Coupa dim.

**Why:** Invoice and Coupa facts keep valid FKs to dim for deactivated suppliers; product layers choose active filters.

**Impact:** Tests `assert_dim_vendor_sap_row_and_active_count`, `assert_dim_vendor_coupa_row_and_active_count`, `assert_dim_vendor_inactive_curriculum`. No change to CD KPI funnel.

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
- `not_cd_eligible_reason` vocabulary (v1): `potential_discount_below_minimum`, `cash_acceleration_exceeds_maximum` (first failing gate wins when structural terms qualify for arbitration).

Policy version selected by effective date; v1 evaluation date = `document_date`.

**Not in v1:** hurdle rates, vendor overrides, weighted scoring, single gate overriding the other.

**Impact:** `seed_cd_wco_arbitration_policy` + `fct_inv_cd_wco_arbitration` (tag `core`); `fct_inv_sap_cd` joins and gates KPI funnel; OTP ignores.

**Status (2026-10-23):** Implemented in monorepo. WCO product consumption deferred.

---

### 2026-10-23 — CD KPI funnel: arbitration gate on ENT [CONVENTION]

**Context:** Arbitration is treasury/program policy, not SAP structural entitlement. CD headline leakage should measure invoices the organization targets for CD, not every terms-eligible row.

**Decision:**

**SQL evaluation order on `fct_inv_sap_cd`:** structural `not_entitled_reason` → CD arbitration (`with_cd_arbitration`, join `fct_inv_cd_wco_arbitration`) → reporting period (`is_paid_in_period`, `is_kpi_entitled`).

**Columns (product fact):** `arbitration_policy_version`, `potential_discount_eur`, `cash_acceleration_days`, `is_cd_eligible`, `not_cd_eligible_reason`, `payment_strategy`. When `not_entitled_reason` is set, arbitration reason columns stay **null** (policy not evaluated); do not merge policy into `not_entitled_reason`.

**KPI ENT:** `is_kpi_entitled` = structural OK ∧ `coalesce(is_cd_eligible, false)` ∧ cleared in reporting period. `is_excluded` (do-not-take at clearing) unchanged — downstream of ENT.

**Curriculum (synthetic v0, 2024 reporting vars):**

| BELNR | Role |
|-------|------|
| `5100000015` | Structural OK (`ZFBDT` set); `potential_discount_below_minimum` → not KPI ENT |
| `5100000016` | **Z525** (2/5 net 25); CD-eligible; V6 `structural_terms_vs_capability` leakage (€20) |
| `5100000026` | **Z205**; `cash_acceleration_exceeds_maximum` → not KPI ENT (SAP-only arbitration hero) |

**Payment terms:** `Z525` in `seed_payment_term_sap` — 5 discount days, 25 net days (acceleration 20 days, passes arbitration).

**Why:** Separates feasibility from program scope; shared arbitration fact supports WCO without redefining structural entitlement.

**Impact:** `fct_inv_sap_cd` / marts: **25** KR rows; KPI ENT **16**, leakage **12**, leakage EUR **190.20**, opportunity **355.21**; mart by-cause **7** rows. `fct_inv_timing_span` ownership **50** / **43** measured; subprocess **129**.

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

**Rejected:** `fct_inv_cash_discount` as the long-term model name (product code `_cd` aligns with `_core`).

**Impact:** `fct_inv_sap_cd` is the CD invoice fact; unsuffixed `fct_inv_sap` removed (2026-10-23).

---

## Model inventory

Update row counts after `dbt build`.

| Object | Layer | Grain | Status | Notes |
|--------|-------|-------|--------|-------|
| `src_*` | src | per source | existing | Tagged `core` in dbt_project.yml |
| `dim_vendor_sap` | dim | vendor | existing | 8 rows (7 active); `is_active`; inactive `0000100005` |
| `dim_vendor_coupa` | dim | supplier | existing | 7 rows (6 active); `status`, `is_active`; inactive `9000005` |
| `map_inv_sap_coupa` | map | (sap_inv_key, coupa_id) | existing | 21 rows; SAP side from `src_inv_sap` + `fct_inv_coupa` |
| `fct_inv_coupa` | fct | coupa invoice | existing | |
| `fct_inv_coupa_changes` | fct | change event | existing | |
| `fct_inv_sap_changes` | fct | change event | existing | |
| `seed_payment_term_sap` | seed | ZTERM | existing | Z210, Z205, Z525, N030; includes `net_days` |
| `seed_cd_wco_arbitration_policy` | seed | policy version | existing | v1; effective on `document_date`; tag `core` |
| `fct_inv_sap_core` | fct | sap_inv_key | existing | 25 KR rows; tag `core`; public contract v0 |
| `fct_inv_timing_span` | fct | span grain | existing | Core; refs `fct_inv_sap_core`; 25 inv.; ownership 50 (43 measured); subprocess 129 |
| `int_inv_coupa_overlay_intervals` | int | interval | existing | Core |
| `int_inv_sap_payment_block_intervals` | int | interval | existing | Core |
| `fct_inv_timing_overlay_core` | fct | overlay interval | existing | 7 rows; observed Coupa + SAP blocks; tag `core` |
| `fct_inv_timing_overlay_cd` | fct (CD) | overlay interval | existing | 10 rows; canonical CD overlay; `_core` ∪ `payment_run_wait`; tag `cash_discount` |
| `fct_inv_timing_overlay_span` | fct | overlap | existing | CD; refs `fct_inv_timing_overlay_cd` + `fct_inv_timing_span` |
| `fct_inv_timing_overlay_span_observed` | fct | overlap | planned | Optional: span on `_core` only |
| `fct_inv_cd_wco_arbitration` | fct | sap_inv_key | existing | 25 rows; tag `core`; gates + `payment_strategy`; WCO/CD consume |
| `fct_inv_sap_cd` | fct (CD) | sap_inv_key | existing | 25 rows; extends core + arbitration; ENT includes `is_cd_eligible`; V6 leakage |

---

## Conventions (stable)

- **Decision file:** This file is authoritative for core grains, columns, and shared policy.
- **SAP invoice facts:** `fct_inv_sap_<suffix>` (`core`, `cd`, `otp`, `wco`); same `sap_inv_key` grain.
- **Tag:** `core` on models that move to `ap_core` package; product tags (e.g. `cash_discount`) on CD models/marts.
- **Keys:** `sap_inv_key` on SAP invoice facts; map tests guard orphan keys.
- **Handoff:** Proposed changes to this file = one full copy-paste block per dated entry. Proposed SQL/YAML/seeds = complete file contents (see `.cursor/rules/project.mdc`).
- **Model inventory:** Update the table when adding or completing a core model.
- **Versioning (post-extract):** Semantic versioning for `ap_core`; products pin releases in `packages.yml`.
- **Naming (ap_core vs product):** `_core` on published spine facts that pair with product extensions; other core models unsuffixed. `_cd` (or `_otp`, `_wco`) only on models that `ref()` those core spines at the same grain—not on marts or CD-only facts that have no ap_core sibling. No unsuffixed alias models. See decisions 2026-10-21 and 2026-10-23.

---

## Chat handoff notes

Last updated: 2026-10-26

Package **v0.1.0** on GitHub; **cash_discount** pinned (duplicate core removed). Spine unchanged: `fct_inv_sap_core` → `fct_inv_cd_wco_arbitration` → `fct_inv_sap_cd` (**25** KR). Curriculum heroes **0015** / **0016** / **0026**; dims 8 / 7 with `is_active`. **Next:** CI + semver (step 5); optional prune duplicate core singular tests in cash_discount.
