# cash_discount — decisions log

Record durable choices here so new Cursor chats (and future you) stay aligned.
Update this file when you settle on naming, grain, business logic, or trade-offs.

---

## Project context

- **Project:** cash_discount (personal dbt project)
- **Purpose:** Dimensional AP / cash-discount model in dbt to measure leakage (entitled ∩ not taken ∩ not excluded) and diagnose root causes (structural / timing / capture); synthetic labeled data for portfolio and reuse.
- **Workspace:** `C:\dbt\cash_discount`

---

## Open questions

<!-- Move items to "Decisions" once resolved -->

- [ ] raw_inv_sap synthetic fields: minimum BKPF/BSEG columns for P1 (is_invoice / is_entitled)?

- [ ] Payment-terms lookup: seed table vs hardcoded mapping for ZTERM → discount %?


---

## Decisions

<!-- Copy this block for each new decision -->

2026-09-04 — SAP vendor slice implemented (seed → src → dim + tests)
Context: Phase 2 synthetic data; prove full dbt pipeline on one entity before invoices.

Decision:

Raw (seed)

File: seeds/raw_vendor_sap.csv
SAP LFA1 field names: LIFNR, NAME1, LAND1, ORT01, PSTLZ, KTOKK, LOEVM, ERDAT
7 synthetic rows (6 active, 1 deleted: LIFNR 0000100005 with LOEVM = X)
Loaded via dbt seed → AP_MODEL.DEV.RAW_VENDOR_SAP
Referenced in models via {{ ref('raw_vendor_sap') }} (not source())
Src

Model: src_vendor_sap (view, models/src/)
Reads {{ ref('raw_vendor_sap') }}
Renames: LIFNR → vendor_id, NAME1 → vendor_name, LAND1 → country_code, ORT01 → city, PSTLZ → postal_code, KTOKK → account_group, LOEVM → deletion_flag, ERDAT → created_date
Casts: erdat → date; nullif(trim(loevm), '') for deletion_flag
Includes all vendors (active and deleted)
Dim

Model: dim_vendor_sap (table, models/dim/)
Reads {{ ref('src_vendor_sap') }}
Grain: one row per vendor_id
Dedupes on vendor_id (qualify row_number() … order by created_date desc)
Active vendors only: where deletion_flag is null (deleted vendor 0000100005 excluded)
Adds is_active (= true for all rows in dim)
Output: 6 rows
Tests

File: models/dim/_dim__models.yml (per-layer schema YAML convention)
dim_vendor_sap.vendor_id: unique, not_null
Run: dbt test --select dim_vendor_sap or dbt build --select raw_vendor_sap+
Why: Validates seed → view → table pattern end-to-end. Dim holds only billable/active suppliers for downstream FK joins. Generic tests live in layer YAML; custom SQL tests in tests/ deferred until business rules need them.

Impact: Vendor lineage complete. Next slice: raw_inv_sap → src_inv_sap → fct_inv_sap (FK vendor_id → dim_vendor_sap). After seed CSV changes: dbt build --select raw_vendor_sap+


### 2026-09-03 — dbt + Snowflake dev environment

**Context:** Initial project setup on a new Snowflake trial account.

**Decision:**
- **Warehouse:** Snowflake (`dbt-snowflake` adapter 1.11.3, dbt Core 1.11.7)
- **Profile:** `cash_discount`, target `dev`, profiles dir `C:\Users\albay\.dbt\`
- **Snowflake:** account `krhqpvk-sn96881`, user `dbt`, role `TRANSFORM`, warehouse `COMPUTE_WH`
- **Landing zone:** database `AP_MODEL`, default schema `DEV`
- **Auth:** key-pair (dedicated key for this account; not reused from other projects)
- **Local env:** venv `C:\dbt\course\.venv` (dbt-bootcamp)

**Role grants (TRANSFORM on AP_MODEL.DEV):**
- `USAGE` on database `AP_MODEL`
- `USAGE` on schema `AP_MODEL.DEV`
- `CREATE TABLE`, `CREATE VIEW` on schema `AP_MODEL.DEV`
- Role `TRANSFORM` granted to user `dbt`

**Why:** Separate dev landing zone from other projects; least-privilege service user for dbt runs.

**Impact:** All models materialize under `AP_MODEL.DEV` unless overridden. New schemas need the same grant pattern.

2026-09-02 — Data layering: source → raw → src → core
Context: Need a documented ingestion lineage from SAP and Coupa into the dimensional model. Raw tables use source-system field names; src_ models rename once; dim_ / fct_ models consume semantic names and add grain + business logic.

Decision: Four-layer flow per entity:

source object → raw_ → src → dim* / fct_* (source names) (landing / seeds) (rename + keys) (business logic)

Layer rules:

Source — real SAP table or Coupa API object (documentation label only; not a dbt model).
Raw — landed data with source field names. Implemented as dbt source() or seed, not models/raw/. Naming: raw__.
Src — thin 1:1 staging in models/src/. Rename, cast, dedupe, build composite keys. Materialization: ephemeral or view.
Core — dim_ / fct_ in models/dim/ and models/fct/. No source-specific field names; no re-renaming from src_.
Entity lineage:

SAP LFA1 raw_vendor_sap → src_vendor_sap → dim_vendor_sap grain: one row per vendor

SAP BKPF (+ vendor line from BSEG) raw_inv_sap → src_inv_sap → fct_inv_sap grain: one row per invoice

SAP CDHDR raw_inv_sap_changes → src_inv_sap_changes → fct_inv_sap_changes grain: one row per change event

Coupa supplier raw_vendor_coupa → src_vendor_coupa → dim_vendor_coupa grain: one row per supplier

Coupa invoice raw_inv_coupa → src_inv_coupa → fct_inv_coupa grain: one row per invoice

Coupa invoice_revision raw_inv_coupa_changes → src_inv_coupa_changes → fct_inv_coupa_changes grain: one row per revision

Key mappings (raw → src):

LIFNR → vendor_id (SAP vendor account number)
BELNR + BUKRS + GJAHR → sap_inv_key (composite PK; concatenated business key)
CHANGENR → sap_change_id (SAP change document number)
BELNR + BUKRS + GJAHR on change row → sap_inv_key (FK to parent invoice)
id (supplier) → vendor_id (Coupa supplier system id)
id (invoice) → coupa_id (Coupa invoice system id)
id (revision) → coupa_change_id (Coupa invoice revision id)
id (invoice, on revision row) → coupa_id (FK to parent invoice)
Primary keys by layer:

SAP vendor raw PK: LIFNR src/core PK: vendor_id src/core FK: —

SAP invoice raw PK: BELNR + BUKRS + GJAHR src/core PK: sap_inv_key src/core FK: vendor_id → dim_vendor_sap

SAP invoice change raw PK: CHANGENR src/core PK: sap_change_id src/core FK: sap_inv_key → fct_inv_sap

Coupa vendor raw PK: id src/core PK: vendor_id src/core FK: —

Coupa invoice raw PK: id src/core PK: coupa_id src/core FK: vendor_id → dim_vendor_coupa

Coupa invoice change raw PK: id src/core PK: coupa_change_id src/core FK: coupa_id → fct_inv_coupa

Why: Separates "what the source sent" from "how we model it." Renaming happens once in src_, keeping dim_ / fct_ free of LIFNR vs id inconsistency. Realistic raw names support synthetic data generation and portfolio storytelling.

Impact: Extends the 2026-08-31 core model with an explicit ingestion layer. map_inv_sap_coupa remains a separate core bridge (not shown on the ingestion diagram). dbt implementation: raw as seeds/sources → models/src/ → models/dim/ / models/fct/.

Note (2026-09-02): The 2026-08-31 entry originally scoped dim / fct / map only; scope now includes raw_ landing + src_ staging per this decision.


### 2026-08-31 — Core layer: SAP + Coupa invoice model (no src / mart)

**Note (2026-09-02):** Scope extended to include `raw_` landing + `src_` staging; see layering decision below.

**Context:** Minimal core dimensional model linking SAP and Coupa AP invoices for cash-discount analysis. Scope is dim / fct / map only (no staging, no marts).

**Decision:** Core models and keys:

| Model | Type | Grain / PK | FKs |
|-------|------|------------|-----|
| `dim_vendor_sap` | dim | `vendor_id` | — |
| `fct_inv_sap` | fct | `sap_inv_key` | `vendor_id` → `dim_vendor_sap` |
| `fct_inv_sap_changes` | fct | `sap_change_id` | `sap_inv_key` → `fct_inv_sap` |
| `dim_vendor_coupa` | dim | `vendor_id` | — |
| `fct_inv_coupa` | fct | `coupa_id` | `vendor_id` → `dim_vendor_coupa` |
| `fct_inv_coupa_changes` | fct | `coupa_change_id` | `coupa_id` → `fct_inv_coupa` |
| `map_inv_sap_coupa` | map | `(sap_inv_key, coupa_id)` | `sap_inv_key` → `fct_inv_sap`; `coupa_id` → `fct_inv_coupa` |

**Key definitions:**

- **`sap_inv_key`** — SAP invoice business key: `doc_number + company_code + fiscal_year` (composite, unique per SAP invoice). Suffix `_key` because it is a concatenated business key, not a single source id.
- **`coupa_id`** — Coupa invoice id (already unique per invoice). Suffix `_id`.
- **`sap_ref_key`** — Attribute on `fct_inv_sap` only (not an FK). Populated with `coupa_id` when the Coupa invoice is posted to SAP. Used to **build and validate** the map; not the SAP-side key in the map.

**Cross-system link (peer via bridge, not fact-to-fact FK):**

- Do **not** FK `fct_inv_sap` → `fct_inv_coupa` directly.
- **`map_inv_sap_coupa`** holds confirmed matches only (both FKs populated).
- **Population logic:**

```sql
SELECT s.sap_inv_key, c.coupa_id
FROM fct_inv_sap s
INNER JOIN fct_inv_coupa c
  ON s.sap_ref_key = c.coupa_id
WHERE s.sap_ref_key IS NOT NULL

Cardinality:

fct_inv_sap → map: 0..1 (SAP invoice may have no Coupa match)
fct_inv_coupa → map: 0..1 (Coupa invoice may have no SAP match, e.g. cancelled / never posted)
Map → each fact: 1 (every map row references exactly one SAP invoice and one Coupa invoice)
1:1 between matched pairs: sap_inv_key and coupa_id each unique in the map
Orphans live in the fact tables, not in the map.

Vendor dimensions:

Keep dim_vendor_sap and dim_vendor_coupa (separate id spaces).
No cross-system vendor map in P1; supplier alignment is implicit via mapped invoices.
dbt tests (map):

unique + not_null on (sap_inv_key, coupa_id)
unique on sap_inv_key and on coupa_id (1:1)
Relationship tests: map FKs → respective facts
Custom test: for mapped SAP rows, sap_ref_key = coupa_id (via join through map)
Why: Symmetric SAP↔Coupa link without directional fact coupling; stable PK-to-PK bridge; optional participation on both sides.

Impact: All cross-system joins go through map_inv_sap_coupa. Leakage KPIs remain SAP-centric on fct_inv_sap; Coupa enrichment via map + fct_inv_coupa.


2026-08-26 — is_invoice definition (P1)

Decision: is_invoice = true when:

document_type = 'KR' (P1 allowlist: KR only).

vendor_id IS NOT NULL (vendor AP document).

P1 assumptions:

One row per document; header and primary vendor line at the same grain.



One vendor line per invoice in source data (no multi-line modeling).



Posted vendor invoices only; credit memos, payments, and reversals are not in the P1 extract.



Posting key 31 may be stored but is not required for the is_invoice rule in P1.

Out of scope P1: multi-line invoices, line-level SKFBT, doc types beyond KR.

2026-08-26 — is_entitled definition (P1)

Context: Need a defensible, testable rule for which paid invoices enter the cash-discount KPI universe (bucket 1.1.1 / denominator for leakage_rate). Entitlement is structural (opportunity exists in principle), not “Skonto still available at payment date.”

Decision: An invoice is is_entitled = true only when all of the following are true:





In-scope document type — vendor invoice in the AP population (not credit memo, payment-only document, reversal, or other out-of-scope doc types).



Paid in reporting period — cleared/paid within the chosen scope (e.g. company X, invoices paid in 2025).



Baseline date present — baseline_date (SAP: ZFBDT) is not null.



Discount-capable payment terms — ZTERM (or equivalent CD payment term) is present and maps to a discount percentage > 0 (e.g. 2% in 2/10 net 30).



Computable discount deadline — discount_deadline_date can be derived from baseline_date + payment terms. If no deadline can be computed (unknown/unsupported/invalid term), is_entitled = false (not_entitled_reason = 'no_deadline').



Discount base > 0 — payable value subject to Skonto is greater than zero.



Discount percentage > 0 — from payment terms (net-only terms → not entitled).

P1 simplifications (documented assumptions):





discount_base_amount = invoice_amount — full invoice amount is discount-eligible; no partial base, no line-level split, no separate SKFBT logic in P1.



Single discount tier per invoice — one % applied to the full base (e.g. 2/10 net 30 only; no multi-tier 2/10, 1/15, net 30 in P1).



Entitlement does not depend on payment timing — an invoice paid after the discount window can still be entitled if rules 1–7 hold; lateness affects taken/leakage, not entitlement.

Derived amounts (not entitlement gates):

discount_opportunity_amount = discount_base_amount × discount_pct
lost_discount_amount          = discount_opportunity_amount - discount_taken_amount   (for entitled rows)

### 2026-08-24 — Leakage funnel (bucket scope)

**Context:** Need a defensible KPI for cash discount leakage; not all late payments count.

**Decision:** Apply an ordered funnel to every invoice:
1. **Entitled?** No → out of scope (no discount opportunity).
2. **Taken?** Yes → **realized** (success).
3. **Excluded?** Yes → **explained non-take** (not leakage).
4. Else → **leakage**.

Formula: `leakage = entitled AND NOT taken AND NOT excluded`. Checks are sequential, not parallel tags.

**Why:** Separates success, valid exceptions, and true leakage before root-cause work.

**Impact:** Status/bucket columns on invoice-level facts; all downstream KPIs and tests.

---

### 2026-08-24 — Leakage root-cause categories

**Context:** After identifying leakage, analysis must explain *why* discount was lost.

**Decision:** Split **leakage only** (not realized, not excluded) into three categories:
- **Structural** — terms, baseline/receipt policy, or window vs realistic cycle time
- **Timing** — process or payment calendar too slow (blocks, approvals, pay run)
- **Capture** — in time to take, but discount not applied at payment

Attribution rules and `primary_cause` assignment are deferred to a later phase; categories are defined now.

**Why:** Matches typical AP diagnosis; keeps KPI definition separate from root-cause narrative.

**Impact:** `primary_cause` (or equivalent) on leakage rows; P2+ models and labeled scenarios.

---

### 2026-08-24 — Hero metrics

**Context:** Portfolio and diagnosis need a small set of top-level KPIs before building marts.

**Decision:** First hero metrics:
- **`leakage_eur`** — sum of lost discount amount on invoices classified as leakage
- **`leakage_rate`** — share of **entitled** invoices (or entitled discount base) that are leakage — pick one denominator and use it consistently

Also track realized and excluded counts/amounts for funnel sanity checks.

**Why:** Results-first modeling; hiring managers see outcome before schema detail.

**Impact:** Mart KPIs, dashboard headline numbers, synthetic test expected values.

---

## Model inventory

| Model | Layer | Grain | Notes |
|-------|-------|-------|-------|
| _example_ | src | one row per … | _not built yet_ |

---

## Conventions (stable)

Fill in as you go; mirror in `.cursor/rules/project.mdc` if the AI should always follow them.

- **Project name / profile:** _TBD_
- **Default schema:** _TBD_
- **Staging prefix:** `src_`
- **Key tests:** uniqueness, not_null on primary keys

---

## Chat handoff notes

<!-- Paste a short summary when switching to a new chat -->

_Last updated: 2026-08-24_

**Decision:** Exclusion inputs are **point-in-time at clearing**:

- Snapshot at `clearing_date`: `payment_block_at_clearing`, `dispute_open_at_clearing`, `match_or_gr_block_at_clearing`, `do_not_take_skonto_at_clearing`.
- Values are **immutable** on the invoice payment fact after clearing (no refresh from current Coupa/SAP status).
- `is_excluded` is derived only from these snapshot fields, evaluated when `is_entitled AND NOT is_taken`.
- Not paid: snapshot fields NULL; exclusion not evaluated for paid-period leakage KPIs.

### 2026-08-26 — `is_invoice` definition (P1)

**Decision:** `is_invoice = true` when:

1. `document_type = 'KR'` (P1 allowlist: KR only).
2. `vendor_id IS NOT NULL` (vendor AP document).

**P1 assumptions:**

- One row per document; header and primary vendor line at the same grain.
- One vendor line per invoice in source data (no multi-line modeling).
- Posted vendor invoices only; credit memos, payments, and reversals are not in the P1 extract.
- Posting key `31` may be stored but is not required for the `is_invoice` rule in P1.

**Out of scope P1:** multi-line invoices, line-level `SKFBT`, doc types beyond KR.

### 2026-08-26 — `is_entitled` definition (P1)

**Context:** Need a defensible, testable rule for which paid invoices enter the cash-discount KPI universe (bucket 1.1.1 / denominator for `leakage_rate`). Entitlement is structural (opportunity exists in principle), not “Skonto still available at payment date.”

**Decision:** An invoice is **`is_entitled = true`** only when **all** of the following are true:

1. **In-scope document type** — vendor invoice in the AP population (not credit memo, payment-only document, reversal, or other out-of-scope doc types).
2. **Paid in reporting period** — cleared/paid within the chosen scope (e.g. company X, invoices paid in 2025).
3. **Baseline date present** — `baseline_date` (SAP: `ZFBDT`) is not null.
4. **Discount-capable payment terms** — `ZTERM` (or equivalent CD payment term) is present and maps to a **discount percentage > 0** (e.g. 2% in 2/10 net 30).
5. **Computable discount deadline** — `discount_deadline_date` can be derived from `baseline_date` + payment terms. If no deadline can be computed (unknown/unsupported/invalid term), **`is_entitled = false`** (`not_entitled_reason = 'no_deadline'`).
6. **Discount base > 0** — payable value subject to Skonto is greater than zero.
7. **Discount percentage > 0** — from payment terms (net-only terms → not entitled).

**P1 simplifications (documented assumptions):**

- **`discount_base_amount = invoice_amount`** — full invoice amount is discount-eligible; no partial base, no line-level split, no separate `SKFBT` logic in P1.
- **Single discount tier per invoice** — one % applied to the full base (e.g. 2/10 net 30 only; no multi-tier 2/10, 1/15, net 30 in P1).
- **Entitlement does not depend on payment timing** — an invoice paid after the discount window can still be entitled if rules 1–7 hold; lateness affects taken/leakage, not entitlement.

**Derived amounts (not entitlement gates):**

```text
discount_opportunity_amount = discount_base_amount × discount_pct
lost_discount_amount          = discount_opportunity_amount - discount_taken_amount   (for entitled rows)

### 2026-08-24 — Leakage funnel (bucket scope)

**Context:** Need a defensible KPI for cash discount leakage; not all late payments count.

**Decision:** Apply an ordered funnel to every invoice:
1. **Entitled?** No → out of scope (no discount opportunity).
2. **Taken?** Yes → **realized** (success).
3. **Excluded?** Yes → **explained non-take** (not leakage).
4. Else → **leakage**.

Formula: `leakage = entitled AND NOT taken AND NOT excluded`. Checks are sequential, not parallel tags.

**Why:** Separates success, valid exceptions, and true leakage before root-cause work.

**Impact:** Status/bucket columns on invoice-level facts; all downstream KPIs and tests.

---

### 2026-08-24 — Leakage root-cause categories

**Context:** After identifying leakage, analysis must explain *why* discount was lost.

**Decision:** Split **leakage only** (not realized, not excluded) into three categories:
- **Structural** — terms, baseline/receipt policy, or window vs realistic cycle time
- **Timing** — process or payment calendar too slow (blocks, approvals, pay run)
- **Capture** — in time to take, but discount not applied at payment

Attribution rules and `primary_cause` assignment are deferred to a later phase; categories are defined now.

**Why:** Matches typical AP diagnosis; keeps KPI definition separate from root-cause narrative.

**Impact:** `primary_cause` (or equivalent) on leakage rows; P2+ models and labeled scenarios.

---

### 2026-08-24 — Hero metrics

**Context:** Portfolio and diagnosis need a small set of top-level KPIs before building marts.

**Decision:** First hero metrics:
- **`leakage_eur`** — sum of lost discount amount on invoices classified as leakage
- **`leakage_rate`** — share of **entitled** invoices (or entitled discount base) that are leakage — pick one denominator and use it consistently

Also track realized and excluded counts/amounts for funnel sanity checks.

**Why:** Results-first modeling; hiring managers see outcome before schema detail.

**Impact:** Mart KPIs, dashboard headline numbers, synthetic test expected values.

---

## Model inventory


| Model | Layer | Grain | Notes |
|-------|-------|-------|-------|
| raw_vendor_sap | seed | one row per vendor | SAP LFA1 names; 7 rows in CSV |
| src_vendor_sap | src (view) | one row per vendor | Rename + cast; includes deleted vendors |
| dim_vendor_sap | dim (table) | one row per active vendor | deletion_flag is null; 6 rows |
| _dim__models.yml | schema | — | unique + not_null on vendor_id |
| src_smoke_test | src (view) | — | Connection smoke test |
| raw_inv_sap | seed | one row per invoice | not built yet |
| src_inv_sap | src (view) | one row per invoice | not built yet |
| fct_inv_sap | fct (table) | one row per invoice | not built yet; FK to dim_vendor_sap |

---

## Conventions (stable)

Fill in as you go; mirror in `.cursor/rules/project.mdc` if the AI should always follow them.

- **Project name / profile:** `cash_discount` / profile `cash_discount` in `~/.dbt/profiles.yml`
- **Default schema:** `DEV` (database `AP_MODEL`)
- **Staging prefix:** `src_`
- **Key tests:** uniqueness, not_null on primary keys

---

## Chat handoff notes

<!-- Paste a short summary when switching to a new chat -->

Last updated: 2026-09-04

SAP vendor slice complete: raw_vendor_sap (seed, 7 rows) → src_vendor_sap (view) → dim_vendor_sap (table, 6 active vendors). Tests in models/dim/_dim__models.yml (unique + not_null on vendor_id). Pipeline validated with dbt seed, dbt run, dbt test. Next: synthetic raw_inv_sap seed and src_inv_sap / fct_inv_sap with FK to dim_vendor_sap.
