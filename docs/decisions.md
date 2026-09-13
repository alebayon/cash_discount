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
- Entitlement-at-clearing snapshot (baseline_date, payment_terms at clearing) — P2+ if retroactive entitlement changes on rebuild become a concern; not in P1 exclusion slice.

---

## Decisions

<!-- Copy this block for each new decision -->

2026-09-13 — Coupa vendor + slim invoice slice (seeds → src → dim / fct)

Context: P1 SAP funnel + mart complete on fct_inv_sap. Next slice per 2026-08-31 architecture: Coupa = slim header + process/diagnosis only; KPI authority remains SAP. No mirrored funnel, no seed_payment_term_coupa, no exclusion-at-clearing on Coupa. Cross-system match deferred to map_inv_sap_coupa + sap_ref_key on fct_inv_sap (posting-time link).

Decision:

Architecture (Coupa vs SAP)

KPI universe, entitlement, taken, excluded, leakage, mart KPIs: fct_inv_sap only.
fct_inv_coupa: slim header columns for workflow state and latency analysis; join to SAP later via map.
No reporting_period vars on Coupa models — period scoping lives on SAP (is_kpi_entitled, mart vars).
Cross-system match established at SAP posting (sap_ref_key = coupa_id when column added), not at Coupa creation.
P1 out of scope: Coupa approved awaiting SAP post (in-flight, not disputed/voided); SAP parked documents.

Raw (seeds)

Files: seeds/raw_vendor_coupa.csv, seeds/raw_inv_coupa.csv
Coupa API-style hyphenated column names in CSV (supplier-id, invoice-date, created-at, document-type, …).
seeds/_seeds.yml: quote_columns: true on both Coupa seeds (Snowflake requires quoted identifiers in src SQL).

Vendor seed: 7 suppliers (ids 9000001–9000007), mirroring SAP LIFNR 0000100001–0000100007 names/countries; 9000005 inactive.

Invoice seed: 15 rows in raw/src; scenario matrix:

| Bucket | coupa_ids | In fct | SAP counterpart |
|--------|-----------|--------|-----------------|
| Matched + paid | 10001–10004, 10007–10008, 10011–10013 (9) | Yes | 5100000001–0004, 0007–0008, 0011–0013 |
| Matched + approved/unpaid | 10005, 10006, 10009 (3) | Yes | 5100000005, 0006, 0009 (open KR) |
| Credit note | 10010 | No | 5100000010 (KG, src only on SAP) |
| Coupa orphan — disputed | 10014 | Yes | None (never posted) |
| Coupa orphan — voided | 10015 | Yes | None (cancelled before post) |
| SAP FB60 orphan | — | No Coupa row | 5100000014, 5100000015 |

invoice-number uses realistic supplier references (INV-5100000xxx aligned to SAP BELNR for map validation; INV-5100000014 / INV-5100000015 for Coupa-only orphans). Status encoded in status column only — not in invoice-number.

Src

Model: src_vendor_coupa (view) — rename/cast only from raw; quote all hyphenated raw columns.
id → vendor_id; name → vendor_name; country-code → country_code; postal-code → postal_code; created-at → created_at (timestamp_ntz).

Model: src_inv_coupa (view) — rename/cast only; all document types retained (including credit note).
id → coupa_id; supplier-id → vendor_id; invoice-number → invoice_number; invoice-date → invoice_date; created-at / updated-at → timestamps; paid → boolean; payment-date → payment_date; document-type → document_type.
No business filters in src.

Dim

Model: dim_vendor_coupa (table) — mirror dim_vendor_sap pattern.
Grain: one row per active vendor_id. Dedupe on vendor_id (latest created_at). Filter status = 'active' (excludes 9000005). is_active = true on all dim rows.
Output: 6 rows.

Fct

Model: fct_inv_coupa (table) — slim columns only.
Source: {{ ref('src_inv_coupa') }}.
Population filter (P1 is_invoice): document_type = 'Invoice' and vendor_id is not null. Credit note excluded (src only).
Output columns: coupa_id, vendor_id, invoice_number, status, invoice_date, created_at, updated_at, paid, payment_date.
Not on fct_inv_coupa (P1): discount fields, payment terms, exclusion *_at_clearing, is_kpi_entitled / is_taken / is_excluded / is_leakage, seed_payment_term_coupa.
Output: 14 rows.

Expected on current synthetic data

dim_vendor_coupa: 6 active suppliers.
src_inv_coupa: 15 rows. fct_inv_coupa: 14 rows.
fct_inv_sap / mart_cash_discount_kpi unchanged: 14 fct rows; funnel 6/3/1/2; leakage_eur 31.20.

Tests

File: models/dim/_dim__models.yml — dim_vendor_sap + dim_vendor_coupa: vendor_id unique/not_null; is_active not_null + accepted_values [true].
File: models/fct/_fct__models.yml — fct_inv_coupa: coupa_id unique/not_null; vendor_id not_null + relationships → dim_vendor_coupa; status accepted_values (paid, approved, disputed, voided); paid not_null.
Singular tests in tests/: assert_dim_vendor_coupa_active_count (6), assert_fct_inv_coupa_row_count (14), assert_fct_inv_coupa_excludes_credit_note, assert_fct_inv_coupa_orphan_scenarios (10014 disputed, 10015 voided), assert_fct_inv_coupa_open_matched_scenarios (10005, 10006, 10009).

Run: dbt seed --full-refresh --select raw_vendor_coupa raw_inv_coupa && dbt build --select raw_vendor_coupa+ raw_inv_coupa+

Why: Delivers Coupa process/diagnosis layer without duplicating SAP KPI logic. Keeps raw Coupa API field names; src renames once; fct holds in-scope invoice grain only.

Impact: Coupa vendor + invoice lineage complete for P1. Next: sap_ref_key on fct_inv_sap; map_inv_sap_coupa; fct_inv_coupa_changes (timing drill-down). Deferred: Coupa mart, seed_payment_term_coupa, Coupa in-flight pre-post rows, SAP parked docs.

2026-09-13 — Coupa scope design

Cross-system match is established at SAP posting (sap_ref_key = coupa_id), not at Coupa creation. Open matched pairs (Coupa approved + SAP KR without clearing) are valid map rows. Coupa-only in-flight (approved, not yet posted) and SAP parked documents are out of P1 scope; timing analysis deferred to fct_inv_coupa_changes.

2026-09-13 — SAP-only orphan invoices (direct FI posting / FB60)

Context: Before Coupa slice and map_inv_sap_coupa. Need labeled SAP invoices that never existed in Coupa (sap_ref_key null, no map row). Real pattern: manual FI vendor invoice (FB60) bypasses Coupa intake. KPI funnel remains SAP-centric; orphans must not disturb hero leakage counts.

Decision:

Raw (seed)

File: seeds/raw_inv_sap.csv — added 2 KR rows:

| BELNR | Role | ZTERM | ZFBDT | AUGDT (2024) | not_entitled_reason |
|-------|------|-------|-------|--------------|---------------------|
| 5100000014 | FB60 direct posting — net-only utility/legal | N030 | present | 2024-09-28 | no_discount_terms |
| 5100000015 | FB60 direct posting — rush manual entry, no baseline | Z210 | empty | 2024-10-18 | no_baseline_date |

Both: active vendors (0000100004, 0000100007), SKNTO = 0.00, no exclusion snapshot flags. Z210 on 0015 uses existing seed_payment_term_sap; entitlement fails on missing baseline first.

Fct behavior

Model: fct_inv_sap — same P1 filters (KR, vendor_id not null). Both rows in fct (is_invoice = true).

is_cleared / is_paid_in_period: true (paid in default reporting period 2024).

is_entitled: false on both. is_kpi_entitled: false — outside ENT/TAKEN/EXCLUDED/LEAKAGE universe (funnel flags null).

sap_ref_key: null when column added (no Coupa counterpart).

Map: no rows for these sap_inv_key values.

Expected after seed add (period 2024, default vars)

fct_inv_sap row_count: 14 (was 12). is_entitled: 8 unchanged. is_kpi_entitled: 6 unchanged. taken: 3, excluded: 1, leakage: 2, leakage_eur: 31.20 unchanged.

Tests

Update row_count only: tests/assert_fct_inv_sap_kpi_funnel_counts.sql (12 → 14), tests/assert_mart_cash_discount_kpi_expected_values.sql (fct_row_count 12 → 14). Funnel node counts and mart amounts unchanged.

Run: dbt seed --full-refresh --select raw_inv_sap && dbt build --select raw_inv_sap+ fct_inv_sap mart_cash_discount_kpi+

Why: Documents realistic SAP-only AP path without Coupa processing. Keeps leakage KPI stable while map slice can assume most other KR rows will later carry sap_ref_key.

Impact: Next: slim Coupa invoice slice + map_inv_sap_coupa; disputed/voided Coupa orphans (no SAP). Deferred: third SAP-only pattern (EDI), sap_ref_key column on fct_inv_sap.

2026-09-12 — Mart hero KPIs: mart_cash_discount_kpi

Context: P1 SAP invoice funnel complete on fct_inv_sap (ENT → TAKEN → EXCLUDED → LEAKAGE). Next slice per 2026-08-24 hero metrics: leakage_eur, leakage_rate, plus funnel sanity counts/amounts for dashboard headline numbers.

Decision:

Mart model

Model: mart_cash_discount_kpi (table, models/mart/)
Source: {{ ref('fct_inv_sap') }} — no additional period filter; is_kpi_entitled and downstream funnel flags already scope the KPI universe to invoices paid in the reporting period (dbt vars reporting_period_start / reporting_period_end).
Grain: one aggregate row per reporting period (period start/end as columns).
Materialization: table (dbt_project.yml mart default).

Metrics

leakage_eur — sum(lost_discount_amount) where is_leakage.
leakage_rate — leakage_eur / discount_opportunity_eur, where discount_opportunity_eur = sum(discount_opportunity_amount) where is_kpi_entitled.
Denominator choice: amount-based (entitled discount opportunity in EUR), not invoice count. Aligns numerator (lost EUR) with denominator (available EUR on KPI-entitled rows). Count-based alternative (leakage_count / kpi_entitled_count) documented but not used for headline rate.

Funnel sanity columns (counts): fct_row_count, kpi_entitled_count, taken_count, excluded_count, leakage_count.
Funnel sanity columns (amounts): discount_opportunity_eur, realized_discount_eur (taken), excluded_opportunity_eur, leakage_eur.

Period vars: same as fct_inv_sap — var('reporting_period_start', '2024-01-01'), var('reporting_period_end', '2024-12-31'). Mart echoes period bounds in output columns.

Expected on current synthetic data (period 2024, default vars)

12 fct_row_count. 6 kpi_entitled_count. 3 taken_count. 1 excluded_count. 2 leakage_count.
discount_opportunity_eur = 196.21. realized_discount_eur = 135.01. excluded_opportunity_eur = 30.00. leakage_eur = 31.20. leakage_rate ≈ 0.159014 (31.20 / 196.21).

Deferred

Dimensional mart breakdowns (vendor, company_code, primary_cause); Coupa mart or cross-system union; sap_ref_key; map_inv_sap_coupa.

Tests

File: models/mart/_mart__models.yml — docs + not_null on period bounds and key metrics.
Singular test: tests/assert_mart_cash_discount_kpi_expected_values.sql — asserts funnel counts, leakage_eur = 31.20, discount_opportunity_eur = 196.21, round(leakage_rate, 4) = 0.1590.
Optional: partition test (realized + excluded + leakage = discount_opportunity_eur).

Run: dbt build --select mart_cash_discount_kpi+

Why: Surfaces portfolio-ready headline KPIs without re-implementing funnel logic. Mart reads classified fact flags; single source of truth remains fct_inv_sap.

Impact: P1 SAP leakage story complete end-to-end (seed → fct → mart). Next parallel tracks: Coupa invoice slice, map_inv_sap_coupa, sap_ref_key; P2+ entitlement-at-clearing snapshot.


2026-09-12 — Leakage classification on fct_inv_sap

Context: Next slice after is_excluded. Implements KPI funnel LEAKAGE node per 2026-08-24. Completes P1 SAP invoice leakage funnel: ENT → TAKEN → EXCLUDED → LEAKAGE. Dates used only for primary_cause attribution (timing vs capture), not for is_taken or is_excluded. No seed changes — labeled scenarios already in raw_inv_sap (0003 timing, 0012 capture, 0013 excluded).

Decision:

Fct enrichment

Model: fct_inv_sap (table, models/fct/) — CTE chain extended: … → with_exclusion → with_leakage.

is_leakage (KPI funnel LEAKAGE node): true when is_kpi_entitled and not is_taken and not is_excluded; false on other eligible rows (is_kpi_entitled and not is_taken); null when not is_kpi_entitled or is_taken. Same evaluation universe as is_excluded.

lost_discount_amount: populated on leakage rows only — discount_opportunity_amount − coalesce(discount_taken_amount, 0). Null when not is_leakage.

primary_cause: populated on leakage rows only. clearing_date > discount_deadline_date → timing; clearing_date <= discount_deadline_date → capture; else structural (defensive fallback). Dates not used for is_taken or is_excluded.

Funnel formula (complete)

leakage = is_kpi_entitled AND NOT is_taken AND NOT is_excluded. Sequential: ENT → TAKEN → EXCLUDED → LEAKAGE.

Expected on current synthetic data (12 fct rows, period 2024)

6 is_kpi_entitled. 3 is_taken (0001, 0002, 0004). 3 not taken (0003, 0012, 0013). 1 is_excluded (0013). 2 is_leakage (0003 timing €17.80, 0012 capture €13.40). Total lost_discount_amount on leakage rows: 31.20. Taken/open/non-KPI rows: is_leakage, lost_discount_amount, primary_cause null.

Labeled seed scenarios

| BELNR | Role | clearing | deadline | Expected primary_cause | lost_discount_amount |
|-------|------|----------|----------|------------------------|----------------------|
| 5100000003 | Timing leakage | 2024-04-25 | 2024-04-11 | timing | 17.80 |
| 5100000012 | Capture leakage | 2024-07-08 | 2024-07-11 | capture | 13.40 |
| 5100000013 | Excluded | 2024-08-08 | — | null (not leakage) | null |

Deferred

Entitlement-at-clearing snapshot (baseline_date, payment_terms at clearing); Coupa invoice slice; map_inv_sap_coupa; sap_ref_key; mart KPIs (leakage_eur, leakage_rate).

Tests

File: models/fct/_fct__models.yml — docs + not_null + accepted_values on is_leakage where is_kpi_entitled and not is_taken; not_null on lost_discount_amount and primary_cause where is_leakage; accepted_values on primary_cause (timing, capture, structural).

Singular tests in tests/: assert_fct_inv_sap_kpi_funnel_counts (leakage_true = 2, round leakage_amount_total = 31.20), assert_fct_inv_sap_is_leakage_only_on_kpi_not_taken, assert_fct_inv_sap_leakage_seed_scenarios.

Note: funnel counts test uses round(sum(lost_discount_amount), 2) for amount assertion — raw sum can differ from 31.20 literal on Snowflake NUMBER precision.

Run: dbt build --select raw_inv_sap+ fct_inv_sap

Why: Completes P1 KPI leakage funnel on SAP invoice fact with auditable root-cause attribution. Separates leakage amount (hero metric input) from funnel classification flags.

Impact: fct_inv_sap P1 funnel complete. Next parallel tracks: Coupa invoice slice, map_inv_sap_coupa, sap_ref_key; mart layer for leakage_eur / leakage_rate.


2026-09-11 — Exclusion snapshots at clearing: rationale and flag definitions

Context: Design record for EXCLUDED node before/during implementation. See 2026-09-11 implementation entry for seed/src/fct details.

Decision:

Why snapshot (not live ERP fields)

Block, dispute, and match status fields are routinely updated after payment. Posted facts (clearing_date, SKNTO) are durable. Snapshot only mutable status that would misrepresent state at payment.

Flag definitions at clearing

payment_block_at_clearing — explicit pay block on invoice/vendor at clearing.
dispute_open_at_clearing — invoice dispute open at clearing.
match_or_gr_block_at_clearing — three-way match or GR incomplete at clearing.
do_not_take_skonto_at_clearing — explicit instruction not to take Skonto at payment.

Any flag true → is_excluded on eligible rows. Excluded rows are explained non-take, not leakage.

P1 implementation

At-clearing values in raw_inv_sap seed columns; not dbt snapshot model. Production: payment-time landing or separate raw clearing-status table; change-log reconstruction (raw_inv_sap_changes) P2+.

Deferred

Snapshot baseline_date and payment_terms at clearing (entitlement retroactivity on rebuild).

Why: Documents business meaning and ingestion strategy separate from column implementation.

Impact: Guides production source mapping and P2 hardening without blocking P1 synthetic funnel.


2026-09-11 — Exclusion snapshots + is_excluded on fct_inv_sap

Context: Next slice after is_taken. Implements KPI funnel EXCLUDED node per 2026-08-24. Exclusion flags are point-in-time at clearing (mutable ERP status would otherwise retroactively reclassify paid-without-discount rows). Rationale for snapshot vs live fields documented 2026-09-11 (business meaning of each flag). P1: at-clearing values stored directly in seed/fact — not dbt snapshot feature. Production may use payment-time landing or raw_inv_sap_changes later. Entitlement input snapshot (baseline_date, payment_terms at clearing) deferred P2+.

Decision:

Raw (seed)

File: seeds/raw_inv_sap.csv — added columns PAYBLK_CLR, DISP_CLR, MGRBLK_CLR, NOSKNT_CLR (X = true at clearing; empty = false). Values meaningful only when AUGDT present; empty on open rows. New KR row 5100000013 (excluded scenario): entitled, paid in 2024, SKNTO 0, NOSKNT_CLR = X. Adjusted 5100000012 clearing to 2024-07-08 (in discount window — capture leakage candidate). Leakage candidates unchanged on flags: 0003 (late pay), 0012 (in-window no take). After column add: dbt seed --full-refresh --select raw_inv_sap.

Src

Model: src_inv_sap (view, models/src/) — rename/cast only. Raw → payment_block_at_clearing, dispute_open_at_clearing, match_or_gr_block_at_clearing, do_not_take_skonto_at_clearing. When AUGDT empty → null; when cleared → coalesce(X/TRUE/1 → true, else false). No is_excluded logic in src.

Fct enrichment

Model: fct_inv_sap (table, models/fct/) — CTE chain extended: … → with_taken → with_exclusion. Pass through four snapshot columns. is_excluded (KPI funnel EXCLUDED node): true when is_kpi_entitled and not is_taken and any snapshot flag true; false on other eligible rows; null when not is_kpi_entitled or is_taken. OR logic across flags. Dates not used for is_excluded.

Scope note (refines 2026-08-24)

is_excluded evaluated on is_kpi_entitled AND NOT is_taken (KPI funnel universe), not structural is_entitled alone. Open rows: snapshot flags null; exclusion not evaluated.

Funnel formula (leakage) - Note: implemented 2026-09-12

leakage = is_kpi_entitled AND NOT is_taken AND NOT is_excluded. Sequential: ENT → TAKEN → EXCLUDED → LEAKAGE.

Expected on current synthetic data (12 fct rows, period 2024)

6 is_kpi_entitled (added 0013). 3 is_taken (0001, 0002, 0004). 3 not taken (0003, 0012, 0013). 1 is_excluded (0013). 2 leakage candidates (0003 timing, 0012 capture). Taken/open/non-KPI rows: is_excluded null.

Deferred

entitlement-at-clearing snapshot; Coupa invoice slice; map_inv_sap_coupa; sap_ref_key.

Tests

File: models/fct/_fct__models.yml — docs + not_null on four snapshot flags where is_cleared; docs + not_null + accepted_values on is_excluded where is_kpi_entitled and not is_taken. Singular tests in tests/: assert_fct_inv_sap_kpi_funnel_counts (updated counts), assert_fct_inv_sap_is_excluded_only_on_kpi_not_taken, assert_fct_inv_sap_exclusion_seed_scenarios; optional assert_fct_inv_sap_snapshot_flags_null_when_open. Run: dbt build --select raw_inv_sap+ fct_inv_sap. Develop workflow: dbt run models first if tests block on new columns.

Why: Completes KPI funnel EXCLUDED node with audit-defensible point-in-time inputs. Separates explained non-take from leakage before root-cause attribution.

Impact: SAP invoice fact ready for leakage bucket + primary_cause slice (timing on 0003, capture on 0012). Coupa/map remain parallel tracks.


2026-09-10 — SAP discount taken amount + is_taken on fct_inv_sap

Context: Next slice after paid-in-period gate. Taken is driven by actual SAP cash discount posted (SKNTO), not by clearing_date vs discount_deadline_date. Dates reserved for leakage root-cause (timing vs capture) on not-taken rows later.

Decision:

Raw (seed)

File: seeds/raw_inv_sap.csv — added column SKNTO (SAP cash discount amount in doc currency). Empty = open/uncleared; 0.00 = cleared with no discount taken. Labeled scenarios: full take (0001, 0002, 0004), paid no take (0003, 0012), open (0005, 0006, 0009), paid not entitled (0007, 0008), paid outside period with take (0011 → 84.00). After column add: dbt seed --full-refresh --select raw_inv_sap.

Src

Model: src_inv_sap (view, models/src/) — rename/cast only: SKNTO → discount_taken_amount (cast(nullif(trim(sknto), '') as number(18, 2))). No coalesce to 0; null = open, 0 = cleared with no discount.

Fct enrichment

Model: fct_inv_sap (table, models/fct/) — CTE chain extended: … → with_payment → with_amounts → with_taken. Pass-through discount_taken_amount after clearing_date. discount_opportunity_amount = invoice_amount × discount_pct on structurally entitled rows (not_entitled_reason is null). is_taken (KPI funnel TAKEN node): true when is_kpi_entitled and discount_taken_amount > 0 and discount_taken_amount = discount_opportunity_amount; false on other is_kpi_entitled rows; null when not is_kpi_entitled.

Entitlement vs KPI vs taken

is_entitled = structural, period-agnostic (opportunity exists). is_kpi_entitled = funnel ENT node (is_entitled AND is_paid_in_period). On PAID rows, is_kpi_entitled and NOT is_entitled are complements — no gap, no overlap. is_taken applies only to is_kpi_entitled rows.

Taken vs diagnosis

is_taken = cash outcome from SAP amount (full capture). clearing_date and discount_deadline_date are not used for is_taken. Leakage attribution (timing / capture / structural) deferred to rows where is_kpi_entitled and not is_taken and not is_excluded.

Expected on current synthetic data (11 fct rows, period 2024)

5 is_kpi_entitled (unchanged). 3 is_taken (0001, 0002, 0004). 2 not taken (0003, 0012). 0011 has discount_taken_amount = 84.00 but is_taken null (not KPI entitled). Open rows: discount_taken_amount null.

Deferred

is_excluded, exclusion snapshot flags at clearing (payment_block_at_clearing, dispute_open_at_clearing, match_or_gr_block_at_clearing, do_not_take_skonto_at_clearing); leakage buckets, lost_discount_amount, primary_cause; captured-but-not-entitled edge cases; sap_ref_key for map_inv_sap_coupa.

Tests

File: models/fct/_fct__models.yml — docs on discount_taken_amount, discount_opportunity_amount, is_taken; not_null on is_taken where is_kpi_entitled. Singular tests in tests/: assert_fct_inv_sap_kpi_funnel_counts, assert_fct_inv_sap_is_taken_only_on_kpi_entitled, assert_fct_inv_sap_is_taken_seed_scenarios (use -- comments, not #). Run: dbt build --select raw_inv_sap+ fct_inv_sap

Why: Completes KPI funnel TAKEN node from actual posted discount, not a date proxy. Aligns with leakage funnel: classify from amounts, diagnose from dates later.

Impact: SAP invoice fact ready for exclusion-at-clearing slice and leakage root-cause. Coupa invoice slice and map_inv_sap_coupa remain next parallel tracks.

2026-09-10 — SAP discount taken amount + is_taken on fct_inv_sap

Context: Next slice after paid-in-period gate. Taken is driven by actual SAP cash discount posted (SKNTO), not by clearing_date vs discount_deadline_date. Dates reserved for leakage root-cause (timing vs capture) on not-taken rows later.

Decision:

Raw (seed)

File: seeds/raw_inv_sap.csv — added column SKNTO (SAP cash discount amount in doc currency). Empty = open/uncleared. Labeled scenarios: full take (0001, 0002, 0004), paid no take (0003, 0012), open (0005, 0006, 0009), paid not entitled (0007, 0008), paid outside period with take (0011 → 84.00). After column add: dbt seed --full-refresh --select raw_inv_sap.

Src

Model: src_inv_sap (view, models/src/) — rename/cast only: SKNTO → discount_taken_amount (cast nullif(trim(sknto), '') as number(18, 2)). No coalesce to 0; null = open, 0 = cleared with no discount.

Fct enrichment

Model: fct_inv_sap (table, models/fct/) — CTE chain extended: … → with_payment → with_amounts → with_taken. Pass-through discount_taken_amount after clearing_date. discount_opportunity_amount = invoice_amount × discount_pct on structurally entitled rows (not_entitled_reason is null). is_taken (KPI funnel TAKEN node): true when is_kpi_entitled and discount_taken_amount > 0 and discount_taken_amount = discount_opportunity_amount; false on other is_kpi_entitled rows; null when not is_kpi_entitled.

Taken vs diagnosis

is_taken = cash outcome from SAP amount. clearing_date and discount_deadline_date are not used for is_taken. Leakage attribution (timing / capture / structural) deferred to rows where is_kpi_entitled and not is_taken and not is_excluded.

Expected on current synthetic data (11 fct rows, period 2024)

5 is_kpi_entitled (unchanged). 3 is_taken (0001, 0002, 0004). 2 not taken (0003, 0012). 0011 has discount_taken_amount but is_taken null (not KPI entitled). Open rows: discount_taken_amount null.

Deferred

is_excluded, exclusion snapshot flags at clearing; leakage buckets, lost_discount_amount, primary_cause; captured-but-not-entitled edge cases; sap_ref_key for map_inv_sap_coupa.

Tests

File: models/fct/_fct__models.yml — docs on discount_taken_amount, discount_opportunity_amount, is_taken. Run: dbt build --select raw_inv_sap+ fct_inv_sap

Why: Completes KPI funnel TAKEN node from actual posted discount, not a date proxy. Aligns with leakage funnel: classify from amounts, diagnose from dates later.

Impact: SAP invoice fact ready for exclusion-at-clearing slice and leakage root-cause. Coupa invoice slice and map_inv_sap_coupa remain next parallel tracks.

2026-09-09 — SAP clearing / paid-in-period on fct_inv_sap

Context: Next slice after structural entitlement; add clearing date from seed, reporting-period gate, and KPI universe column (is_kpi_entitled). Defer is_taken, exclusion snapshots at clearing, leakage amounts.

Decision:

Raw (seed)

File: seeds/raw_inv_sap.csv — added column AUGDT (SAP clearing date). Empty = open/uncleared. Labeled scenarios: paid in 2024 (0001–0004, 0007, 0008, 0012), open (0005, 0006, 0009), paid outside default period (0011 cleared 2025-02-05). After column add: dbt seed --full-refresh --select raw_inv_sap (existing Snowflake table lacks new column otherwise).

Src

Model: src_inv_sap (view, models/src/) — rename/cast only: AUGDT → clearing_date (cast nullif(trim(augdt), '') as date). No period logic, no joins.

Reporting period (project vars)

File: dbt_project.yml — vars: reporting_period_start: '2024-01-01', reporting_period_end: '2024-12-31'. Defaults align with synthetic seed; override at run time via --vars. SQL fallback in fct: var('reporting_period_start', '2024-01-01') and var('reporting_period_end', '2024-12-31').

Fct enrichment

Model: fct_inv_sap (table, models/fct/) — CTE chain extended: … → with_entitlement → with_payment. with_payment columns: is_cleared = clearing_date is not null; is_paid_in_period = cleared and clearing_date between period_start and period_end; is_kpi_entitled = not_entitled_reason is null and is_paid_in_period (same as structural is_entitled AND paid in period). is_entitled unchanged — structural only, period-agnostic.

Entitlement vs KPI universe

is_entitled = structural pre-payment gate (all KR rows). is_kpi_entitled = funnel ENT node for leakage KPIs (entitled ∩ paid in reporting period). Taken, excluded, leakage apply only to is_kpi_entitled rows (deferred).

Expected on current synthetic data (11 fct rows, period 2024)

8 is_entitled (unchanged). 8 is_cleared. 7 is_paid_in_period. 5 is_kpi_entitled (0001–0004, 0012). Not KPI: 0005/0006 open entitled; 0011 entitled paid in 2025; 0007/0008 paid but not entitled; 0009 open not entitled.

Deferred

is_taken, discount_taken_amount; exclusion snapshot flags at clearing (payment_block_at_clearing, dispute_open_at_clearing, match_or_gr_block_at_clearing, do_not_take_skonto_at_clearing) per 2026-08-24; is_excluded, leakage buckets, discount_opportunity_amount, primary_cause; company-code filter on reporting period; sap_ref_key for map_inv_sap_coupa.

Tests

File: models/fct/_fct__models.yml — added docs + not_null on is_cleared, is_paid_in_period, is_kpi_entitled; clearing_date documented. Run: dbt build --select raw_inv_sap+ fct_inv_sap

Why: Completes paid-in-period gate so leakage funnel ENT node is materialized. clearing_date is timeless; is_paid_in_period / is_kpi_entitled are relative to dbt vars (rebuild fact when period changes in P1).

Impact: SAP invoice fact ready for is_taken and exclusion-at-clearing slice. Coupa invoice slice and map_inv_sap_coupa remain next parallel tracks.

2026-09-08 — Payment terms seed + P1 structural entitlement on fct_inv_sap Context: Next slice after SAP invoice fact; map ZTERM to discount metadata and implement is_entitled / not_entitled_reason per 2026-08-26 P1 rules. Defer paid-in-period, taken, leakage.

Decision:

Raw (seed)

File: seeds/seed_payment_term_sap.csv SAP-style key: ZTERM Columns: ZTERM, term_description, discount_pct, discount_days, net_days 2 rows: Z210 (2/10 net 30 — discount_pct 0.02, discount_days 10, net_days 30), N030 (Net 30 — discount_pct 0.00, discount_days null, net_days 30) Loaded via dbt seed → AP_MODEL.DEV.SEED_PAYMENT_TERM_SAP Referenced in models via {{ ref('seed_payment_term_sap') }} (not source()) Naming: file/table uses singular seed_payment_term_sap (not seed_payment_terms_sap)

Fct enrichment

Model: fct_inv_sap (table, models/fct/) Still reads {{ ref('src_inv_sap') }}; grain unchanged (one row per sap_inv_key; 11 KR rows) CTE chain: src → invoices (KR + vendor_id not null) → with_terms → with_entitlement with_terms: left join seed_payment_term_sap on payment_terms = zterm Adds discount_pct from seed Adds discount_deadline_date = dateadd(day, discount_days, baseline_date) when baseline_date and discount_days both not null; else null with_entitlement: not_entitled_reason = first failing rule (case order): no_baseline_date — baseline_date is null no_discount_terms — discount_pct is null or <= 0 (covers N030 and unknown ZTERM) no_deadline — discount_deadline_date is null (after above checks) zero_discount_base — invoice_amount <= 0 (P1 discount_base_amount = invoice_amount) is_entitled = not_entitled_reason is null (boolean)

P1 is_entitled scope this slice

Implemented: in-scope doc type (invoices filter), baseline present, discount-capable terms (pct > 0), computable deadline, discount base > 0, discount pct > 0 Deferred: paid in reporting period (full KPI universe ENT in leakage funnel requires this gate later) Deferred: is_taken, is_excluded, leakage buckets, discount_opportunity_amount, primary_cause

Expected on current synthetic data (11 fct rows)

8 entitled (Z210, baseline present, invoice_amount > 0) 3 not entitled: 5100000007 N030 → no_discount_terms; 5100000008 null baseline → no_baseline_date; 5100000009 zero amount → zero_discount_base

Structural is_entitled is evaluated on all invoice-grain rows regardless of payment status. KPI universe (leakage funnel ENT) is is_entitled AND paid_in_period; taken/leakage/exclusion apply only to that subset

Tests

File: models/fct/_fct__models.yml Existing: sap_inv_key unique/not_null; vendor_id not_null/relationships → dim_vendor_sap Added column docs: discount_pct, discount_deadline_date, is_entitled (not_null), not_entitled_reason Run: dbt build --select seed_payment_term_sap+ fct_inv_sap

Why: Completes payment-terms lookup and structural entitlement on SAP invoice fact. Funnel diagram ENT node fully applies only after paid-in-period is added; current is_entitled is structural pre-payment gate.

Impact: SAP invoice slice ready for clearing/payment enrichment and Coupa/map work. Resolved open question: payment-terms lookup = seed table seed_payment_term_sap.

# 2026-09-06 — SAP invoice slice implemented (seed → src → fct + tests)
Context: Phase 2 synthetic data; prove invoice pipeline with FK to dim_vendor_sap before entitlement / leakage logic.

Decision:

Raw (seed)

File: seeds/raw_inv_sap.csv
SAP BKPF/BSEG-style field names: BELNR, BUKRS, GJAHR, LIFNR, BLART, ZFBDT, ZTERM, WRBTR, WAERS, BUDAT, BLDAT
12 synthetic rows (11 KR vendor invoices, 1 KG credit memo for out-of-scope boundary)
LIFNR values match active vendors in dim_vendor_sap (0000100001–0000100007 except deleted 0000100005)
Labeled scenarios in seed: net-only ZTERM (N030), null ZFBDT, zero WRBTR, non-KR doc type (KG)
Loaded via dbt seed → AP_MODEL.DEV.RAW_INV_SAP
Referenced in models via {{ ref('raw_inv_sap') }} (not source())

Src

Model: src_inv_sap (view, models/src/)
Reads {{ ref('raw_inv_sap') }}
Composite key: trim(belnr) || '-' || trim(bukrs) || '-' || trim(gjahr) → sap_inv_key
Renames: LIFNR → vendor_id, BLART → document_type, ZFBDT → baseline_date, ZTERM → payment_terms, WRBTR → invoice_amount, WAERS → currency_code, BUDAT → posting_date, BLDAT → document_date; also exposes doc_number, company_code, fiscal_year
Casts: zfbdt → date (nullif empty); wrbtr → number(18,2); budat/bldat → date
Includes all document types (KR and non-KR); no business filters; payment_terms kept as SAP code (no mapping yet)

Fct

Model: fct_inv_sap (table, models/fct/)
Reads {{ ref('src_inv_sap') }}
Grain: one row per invoice (sap_inv_key)
Invoice population filter (P1 is_invoice): document_type = 'KR' and vendor_id is not null
Non-KR rows remain in src only (e.g. KG row excluded from fct)
FK: vendor_id → dim_vendor_sap (enforced via relationships test)
Output: 11 rows
Deferred to next slice: is_entitled, discount_pct, discount_deadline_date, taken/leakage buckets (require payment-terms lookup and clearing data)

Tests

File: models/fct/_fct__models.yml (per-layer schema YAML convention)
fct_inv_sap.sap_inv_key: unique, not_null
fct_inv_sap.vendor_id: not_null, relationships → dim_vendor_sap.vendor_id
Run: dbt build --select raw_inv_sap+ dim_vendor_sap
After seed CSV changes: dbt build --select raw_inv_sap+ dim_vendor_sap

Why: Validates seed → view → table pattern for invoices with FK to vendor dim. Src holds full AP document extract; fct holds invoice grain only. ZTERM mapping and entitlement logic deferred until payment-terms seed is added.

Impact: SAP invoice lineage complete for P1 structural columns. Next: seed_payment_terms_sap (ZTERM → discount % / days) and enrich fct_inv_sap with is_entitled; then Coupa invoice slice and map_inv_sap_coupa.

Resolved (moved from open questions): minimum raw_inv_sap columns for P1 slice — BELNR, BUKRS, GJAHR, LIFNR, BLART, ZFBDT, ZTERM, WRBTR, plus WAERS, BUDAT, BLDAT for realistic staging; clearing / taken fields not required for this vertical slice.

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

Impact: Vendor lineage complete. Invoice slice also complete; next is payment-terms seed + is_entitled.


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

- **`sap_inv_key`** — implemented as doc_number || '-' || company_code || '-' || fiscal_year.
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
```

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

### 2026-08-24 — Exclusion inputs at clearing (P1)

**Context:** The leakage funnel step "Excluded?" needs defensible inputs. Exclusion must reflect status at payment/clearing time, not current SAP/Coupa document status.

**Decision:** Exclusion inputs are **point-in-time at clearing**:

- Snapshot at `clearing_date`: `payment_block_at_clearing`, `dispute_open_at_clearing`, `match_or_gr_block_at_clearing`, `do_not_take_skonto_at_clearing`.
- Values are **immutable** on the invoice payment fact after clearing (no refresh from current Coupa/SAP status).
- `is_excluded` is derived only from these snapshot fields, evaluated when `is_entitled AND NOT is_taken`.
- Not paid: snapshot fields are NULL; exclusion is not evaluated for paid-period leakage KPIs.

**Why:** Avoids retroactive reclassification when blocks/disputes are resolved after payment. Matches how AP audit and leakage analysis are done in practice.

**Impact:** Clearing/payment columns and snapshot flags on `fct_inv_sap` (or a payment sub-fact); synthetic scenarios for excluded vs leakage rows. Deferred until after entitlement + payment-terms slice.

---

## Model inventory


| Model | Layer | Grain | Notes |
|-------|-------|-------|-------|
| raw_vendor_sap | seed | one row per vendor | SAP LFA1 names; 7 rows in CSV |
| src_vendor_sap | src (view) | one row per vendor | Rename + cast; includes deleted vendors |
| dim_vendor_sap | dim (table) | one row per active vendor | deletion_flag is null; 6 rows |
| src_smoke_test | src (view) | — | Connection smoke test |
| seed_payment_term_sap | seed | one row per ZTERM | Z210, N030; 2 rows | Update fct_inv_sap note: 11 rows; discount_pct, discount_deadline_date, is_entitled, not_entitled_reason
| raw_inv_sap | seed | one row per AP document | SAP BKPF-style; 13 rows; AUGDT, SKNTO, PAYBLK_CLR, DISP_CLR, MGRBLK_CLR, NOSKNT_CLR |
| src_inv_sap | src (view) | one row per AP document | Rename + sap_inv_key; clearing_date, discount_taken_amount, four *_at_clearing flags |
| fct_inv_sap | fct (table) | one row per vendor invoice (KR) | 14 rows; full P1 funnel: is_kpi_entitled, is_taken, is_excluded, is_leakage, lost_discount_amount, primary_cause |
| raw_vendor_coupa | seed | one row per supplier | Coupa API names; 7 rows; quote_columns |
| src_vendor_coupa | src (view) | one row per supplier | Rename + cast; includes inactive |
| dim_vendor_coupa | dim (table) | one row per active supplier | status = active; 6 rows; is_active |
| raw_inv_coupa | seed | one row per invoice doc | 15 rows; quote_columns |
| src_inv_coupa | src (view) | one row per invoice doc | All doc types incl. credit note |
| fct_inv_coupa | fct (table) | one row per Coupa invoice | 14 rows; slim header; no KPI funnel |
| _dim__models.yml | schema | — | vendor_id + is_active tests (SAP + Coupa) |
| _fct__models.yml | schema | — | SAP funnel tests + fct_inv_coupa slim column tests |
| tests/ | singular | — | SAP funnel + Coupa row counts, credit note, orphans, open matched |
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

Last updated: 2026-09-13

SAP P1 complete: fct_inv_sap full funnel + mart_cash_discount_kpi (6/3/1/2, €31.20). fct_inv_sap row_count 14 (incl. FB60 orphans 5100000014/0015, sap_ref_key null when added).

Coupa P1 complete: raw_vendor_coupa → src_vendor_coupa → dim_vendor_coupa (6 active); raw_inv_coupa → src_inv_coupa → fct_inv_coupa (14 slim rows). Credit note 10010 src only. Coupa orphans 10014 disputed, 10015 voided (no SAP). Match at SAP posting (not Coupa create); no in-flight Coupa-only approved rows in P1.

Next: sap_ref_key on fct_inv_sap; map_inv_sap_coupa; fct_inv_coupa_changes. Deferred P2+: entitlement-at-clearing snapshot; Coupa pre-post in-flight; SAP parked docs.