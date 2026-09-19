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
- Map the production source for receipt_date. Version 5 intentionally keeps one receipt anchor and defers submission/technical-receipt/AP-seen breakdown.
- Wrong-clock attribution remains deferred until an authoritative contractual baseline or actual AP target deadline is available.

---

## Decisions

<!-- Copy this block for each new decision -->

2026-09-19 — Timing phase layer slice 1 (ownership spans)

Context:

Version 5 classifies leakage root cause via an ordered waterfall on fct_inv_sap. Portfolio needs phase-duration instrumentation — how long pre-SAP and payment took — without changing leakage eligibility, amounts, primary_cause, or funnel flags. Slice 1 ships the instrument only; no subprocess split, overlays, or benchmarks.

Decisions (D1–D18, slice 1 scope):

- D1: fct_inv_timing_span reads fct_inv_sap only; recomputes nothing; does not alter Version 5.
- D2: Population = all 20 fct_inv_sap invoices, not leakage only (avoids outcome-conditioned metrics).
- D3: Mart period anchor = span_end_date, not clearing_date.
- D4: CPUDT → sap_entry_date is the SAP process entry milestone; BUDAT/posting_date remains accounting-only pass-through (never in CASE/WHERE/JOIN).
- D5: Spans start at receipt_date (Coupa created_at), not baseline_date/invoice_date.
- D6: Calendar days, datediff('day', …), closed-open; clock never pauses.
- D7: No single-label phase attribution column (no dominant_phase, primary_timing_subbucket, etc.).
- D8: phase_level on every row ('ownership' in slice 1; 'subprocess' deferred slice 2).
- D9: span_status ∈ {measured, not_applicable, not_ended, not_measurable}; pre_sap never not_ended; sap_entry_date not_null on fct_inv_sap.
- D10: Coupa-only in-flight (approved, not posted) out of scope — no fct_inv_sap row.
- D11: Mart percentiles use percentile_cont.
- D12: Dropped from slice 1: milestone_confidence, start_event_id, end_event_id, max_span_days.
- D13: pre_sap = minimise duration; payment = hit the window (deadline-relative runway, not raw duration as KPI).
- D14–D18: Overlay reasons, change tables, benchmarks — direction only; not built in slice 1.

CPUDT seed (raw_inv_sap.csv):

- Added column CPUDT after BLDAT on all 21 raw rows.
- Constraints: never empty; Coupa-matched CPUDT >= Coupa created-at and <= AUGDT when cleared; SAP-only (5100000014/15/21) CPUDT >= BLDAT; never copied from BUDAT (BLDAT+2/+3 artifact).
- Intent: ~3–5 day receipt-to-entry on healthy population; chronology fix on 5100000017/18/20 (BUDAT was before Coupa create — CPUDT restores order without changing Version 5 numbers).
- Heroes 5100000003 and 5100000019 unchanged for V5 attribution.

Models:

- src_inv_sap: cpudt → sap_entry_date (cast nullif trim).
- fct_inv_sap: sap_entry_date pass-through only (not in waterfall).
- fct_inv_timing_span (table): grain (sap_inv_key, phase_level, phase_code, span_seq). Ownership phases: pre_sap (receipt_date → sap_entry_date), payment (sap_entry_date → clearing_date).
- mart_timing_phase_profile (table): measured spans only; span_end_date in reporting period; grain (period_start, period_end, phase_level, phase_code).

Expected counts (confirmed on build):

| Metric | Value |
|--------|-------|
| fct_inv_timing_span rows | 40 |
| measured spans | 34 |
| pre_sap measured / not_applicable | 17 / 3 (5100000014, 5100000015, 5100000021) |
| payment measured / not_ended | 17 / 3 (5100000005, 5100000006, 5100000009) |
| not_measurable | 0 |
| mart_timing_phase_profile rows | 2 |
| mart span_count per phase (2024 period) | 16 each (5100000011 excluded — span_end in 2025) |

Tests:

- Schema: fct_inv_sap.sap_entry_date not_null; fct_inv_timing_span + mart_timing_phase_profile column tests in layer YAML.
- Singular: assert_fct_inv_timing_span_row_count, no_negative_days, reconciles_cycle, status_scenarios, no_unmeasurable, unique_grain; assert_mart_timing_phase_profile_row_count.
- Full dbt test suite: all pre-existing Version 5 tests unchanged.

Analytical reads (not tests):

- Step 9: sum(median_span_days) across ownership phases = [RUN RESULT]; standard_cycle_days = 10. [Interpretation: if sum > 10, typical phase medians exceed the sustainable cycle benchmark.]
- Step 9b runway_at_handoff on timing leakage heroes:
  - 5100000003: runway [RUN], deadline_miss_days [RUN] — entered SAP with runway but cleared 14 days past deadline; payment-side failure on D13 lens despite V5 primary_cause = timing.
  - 5100000019: runway [RUN], deadline_miss_days [RUN] — same pattern.

Version 5 unchanged: funnel 12/3/1/8; leakage_eur 123.20; heroes 0003 timing, 0012 capture, 0013 excluded.

Deferred (slice 3+): overlay reason intervals; fct_inv_sap_changes; frozen benchmarks; Coupa operational dashboard; wrong_clock_confirmed. Subprocess split -> see 2026-09-19 slice 2 pre-build entry.

Run: dbt seed --full-refresh --select raw_inv_sap && dbt build --select fct_inv_timing_span+ mart_timing_phase_profile+ && dbt test

2026-09-19 — Timing phase layer slice 2 pre-build (Coupa subprocess split)

Context:

Slice 1 delivered ownership-level spans only (pre_sap, payment) on all 20 fct_inv_sap invoices. Slice 2 splits pre_sap into four Coupa subprocess phases using event history, adds fct_inv_coupa_changes, and extends fct_inv_timing_span with subprocess rows plus start_event_id / end_event_id drill-through. Version 5 funnel, heroes, mart KPIs, and every existing test must remain byte-for-byte unchanged. Ownership rows (40) must be identical after Slice 2 build.

Status: PRE-BUILD — design locked; seeds and SQL not yet implemented. Row counts and reconciliation results to be filled after build.

Decisions (D19–D29, slice 2 scope):

- D19 Portfolio: retrofit only — no new raw_inv_sap / raw_inv_coupa rows. All subprocess instrumentation on existing 20 fct_inv_sap invoices (17 Coupa-matched + 3 SAP-only). Version 5 counts and heroes unchanged.
- D20 Rework: rejected maps to status_role approval_end (closes current approval visit). Rework restarts at verification (submitted / verification_start), not re-intake. New visits increment span_seq per (sap_inv_key, phase_level, phase_code). Sum visits per phase; never first-entry-to-last-exit across the invoice.
- D21 Status map (seed_coupa_status_map): phases defined by status_role, never hardcoded status strings in span SQL.

  | status | status_role | role_kind |
  |--------|-------------|-----------|
  | draft | work_start | boundary |
  | submitted | verification_start | boundary |
  | pending_approval | approval_start | boundary |
  | approved | approval_end | boundary |
  | rejected | approval_end | boundary |
  | on_hold | on_hold | informational |
  | paid | coupa_paid | informational |

  Omitted Slice 2: pending_receipt (add later if needed).
  Deferred from map / matched-invoice events: disputed, voided — Coupa-only terminal paths; obsolete/cancelled invoices out of scope for timing inefficiency analysis. Coupa orphans (10014 disputed, 10015 voided) are not in fct_inv_sap and do not enter fct_inv_timing_span.

- D22 paid events: may appear in fct_inv_coupa_changes as informational only (Coupa UI realism). Must not drive subprocess or ownership payment spans. SAP clearing_date is the only payment milestone. No propagation to other models.
- D23 Interface phase: span ends at fct_inv_sap.sap_entry_date (CPUDT), not a Coupa status. end_event_id = null; end_milestone_field = sap.cpudt. start_event_id = coupa_change_id of last approval_end boundary. Ownership rows: start_event_id and end_event_id both null.
- D24 Timestamps: date-only event dates in Slice 2 (no intraday time). Multiple events per calendar day allowed. Tie-break order: event_date, revision_seq, coupa_change_id. span_days = 0 for same-day boundaries — valid operational signal (same-day completion incentive). Contrast invoices labelled slow in a specific phase still allocate >= 1 day to that phase so subprocess mart medians remain distinguishable.
- D25 Coverage and chronology: all 17 Coupa-matched fct_inv_sap rows get full event history. Hard chronology on matched cleared rows: receipt_date (Coupa created_at) <= events <= sap_entry_date <= clearing_date when cleared. Open matched (5100000005, 5100000006, 5100000009): full workflow through approved; subprocess payment = not_ended (mirrors ownership).
- D26 fct_inv_coupa header: current state only; no enrichment to draft/submitted. Open matched rows remain approved (already true in seeds).
- D27 on_hold: informational only — does not open or close phases; span state machine ignores it. Used on 5100000008 mid-verification as substitute for pending_receipt scenario.
- D28 Reconciliation invariants (tests): where all four pre-SAP subprocess phases are measured, intake + verification + approval + interface span_days = ownership pre_sap span_days (exact). Exclude not_applicable / not_measurable from sum test. Subprocess payment must match ownership payment per sap_inv_key (days, status, dates). Ownership 40 rows unchanged vs Slice 1. Split row-count tests: ownership 40 + separate subprocess total. No assert_fct_inv_timing_span_contrast_* singular tests.
- D29 Deferred unchanged: buffer_consumption, runway_at_handoff columns, dominant_phase / primary_timing_subbucket, Coupa in-flight operational dashboard (D10), frozen benchmarks (D16/D18), overlay reason intervals (slice 3), fct_inv_sap_changes (slice 4).

Subprocess phases (phase_level = subprocess):

| phase_code | span_start milestone | span_end milestone |
|------------|---------------------|-------------------|
| intake | first work_start (per visit) | first verification_start after it |
| verification | verification_start (per visit) | first approval_start after it |
| approval | approval_start (per visit) | first approval_end after it |
| interface | last successful approval_end | sap_entry_date (fct_inv_sap) |
| payment | sap_entry_date | clearing_date |

SAP-only (5100000014, 5100000015, 5100000021): intake / verification / approval / interface = not_applicable; payment = measured or not_ended (mirror ownership).

Architecture:

- Branch A (unchanged): fct_inv_sap -> fct_inv_timing_span WHERE phase_level = ownership
- Branch B (new): raw_inv_coupa_changes -> src_inv_coupa_changes -> fct_inv_coupa_changes; join seed_coupa_status_map; + fct_inv_sap SAP dates -> fct_inv_timing_span WHERE phase_level = subprocess
- UNION ALL into fct_inv_timing_span. Ownership must not depend on Coupa events.

Contrast curriculum (existing BELNRs; pre_sap totals fixed by Slice 1 — only phase distribution changes):

| Role | BELNR | Notes |
|------|-------|-------|
| Happy / fast path | 5100000001 or 5100000004 | Taken; tight subprocess |
| Slow verification only | 5100000017 | Most pre_sap days in verification |
| Slow approval only | 5100000018 | Most pre_sap days in approval |
| Slow interface only | 5100000016 | Delay before CPUDT |
| Payment runway (timing hero) | 5100000003 | Rich timing story; pre_sap + payment subprocess |
| Two phases jointly slow (timing hero) | 5100000019 | Rich timing story; verification + approval share days |
| Rework | 5100000020 | span_seq > 1 on approval and/or verification |
| on_hold informational | 5100000008 | on_hold revision mid-verification; no boundary effect |
| Capture hero (fast) | 5100000012 | Minimal/fast subprocess; not timing-focused |
| Excluded hero | 5100000013 | Minimal reconciling history only |
| Remaining matched | 0002, 0005–0007, 0009, 0011, etc. | Full history; sum reconciles to ownership pre_sap |

New artifacts (to build):

Seeds:
- raw_inv_coupa_changes.csv — grain one row per Coupa revision; columns id, invoice-id, status, created-at, revision-number; quote_columns true
- seed_coupa_status_map.csv — status -> status_role map per D21

Models:
- src_inv_coupa_changes (view) — rename/cast only
- fct_inv_coupa_changes (table) — grain coupa_change_id; FK coupa_id -> fct_inv_coupa; status_role from seed join
- fct_inv_timing_span (changed) — UNION ownership + subprocess; add start_event_id, end_event_id (12 columns total)
- mart_timing_phase_profile (unchanged SQL) — grows from 2 to 7 rows (2 ownership + 5 subprocess)

Expected counts (to confirm on build):

| Metric | Expected |
|--------|----------|
| fct_inv_timing_span ownership rows | 40 (identical to slice 1) |
| fct_inv_timing_span subprocess rows | 100 base (20 x 5) + rework extras |
| mart_timing_phase_profile rows | 7 |
| fct_inv_coupa_changes rows | [TBD after seed author] |

Tests (to add / update):

- assert_fct_inv_timing_span_ownership_unchanged (new)
- assert_fct_inv_timing_span_subprocess_reconciles_pre_sap (new)
- assert_fct_inv_timing_span_subprocess_payment_matches_ownership (new)
- assert_fct_inv_timing_span_subprocess_row_count (new — set expected after build)
- assert_fct_inv_coupa_changes_row_count (new)
- assert_fct_inv_timing_span_row_count — scope to ownership only OR split
- assert_mart_timing_phase_profile_row_count — update 2 to 7
- Full dbt test suite: all slice 1 + Version 5 tests unchanged

Run (after implementation):

dbt seed --full-refresh --select raw_inv_coupa_changes seed_coupa_status_map
dbt build --select fct_inv_coupa_changes+ fct_inv_timing_span+ mart_timing_phase_profile+
dbt test

Version 5 unchanged (hard constraint): funnel 12/3/1/8; leakage_eur 123.20; heroes 5100000003 timing, 5100000012 capture, 5100000013 excluded.

2026-09-16 — Mart leakage breakdown by primary_cause

Context:

Version 5 root-cause waterfall and seed expansion labeled all six `primary_cause` buckets on `fct_inv_sap` leakage rows. `mart_cash_discount_kpi` exposes headline funnel KPIs only (one row per period). Dashboard / portfolio use needs leakage_eur and leakage_count split by Version 5 cause without changing headline mart or fact waterfall logic.

Decision:

Mart model

Model: `mart_cash_discount_kpi_by_cause` (table, `models/mart/`)
Source: `{{ ref('fct_inv_sap') }}` — read `primary_cause`, `primary_cause_group`, `lost_discount_amount` only; do not recompute attribution.
Filter: `where is_leakage` (leakage population only; `primary_cause` is null elsewhere).
Grain: one row per `(reporting_period_start, reporting_period_end, primary_cause)`.
Period vars: same as headline mart — `var('reporting_period_start', '2024-01-01')`, `var('reporting_period_end', '2024-12-31')`. Echoed on each row; no additional period filter beyond fact funnel flags.

Columns

- `reporting_period_start`, `reporting_period_end`
- `primary_cause` — Version 5 detailed bucket (not null on leakage)
- `primary_cause_group` — denormalized roll-up (`capture`, `structural`, `timing`, `unclassified`)
- `leakage_count` — `count(*)` per cause
- `leakage_eur` — `round(sum(lost_discount_amount), 2)` per cause
- `leakage_share` — `leakage_eur / total leakage_eur` (decimal 0–1, 6 dp)
- `leakage_count_share` — `leakage_count / total leakage_count` (decimal 0–1, 6 dp)

Headline mart `mart_cash_discount_kpi` unchanged.

Expected on current synthetic data (period 2024, default vars) — 6 rows, 8 leakage invoices

| primary_cause | primary_cause_group | leakage_count | leakage_eur |
|---------------|---------------------|---------------|-------------|
| capture | capture | 2 | 28.40 |
| timing | timing | 2 | 28.80 |
| structural_terms_vs_capability | structural | 1 | 20.00 |
| data_quality_error | unclassified | 1 | 18.00 |
| structural_insufficient_time_at_intake | structural | 1 | 16.00 |
| structural_compressed_intake | structural | 1 | 12.00 |
| **Total** | | **8** | **123.20** |

Invoice detail (for test comments):

- capture €28.40 = 5100000012 (€13.40) + 5100000020 (€15.00)
- timing €28.80 = 5100000003 (€17.80) + 5100000019 (€11.00)

Reconciliation invariants (must hold):

- `sum(leakage_count) = 8` = `mart_cash_discount_kpi.leakage_count`
- `sum(leakage_eur) = 123.20` = `mart_cash_discount_kpi.leakage_eur`
- `round(sum(leakage_share), 4) = 1.0`
- 6 distinct `primary_cause` values

Tests

File: `models/mart/_mart__models.yml` — docs + `not_null` on period bounds, counts, amounts; `accepted_values` on `primary_cause` (6 Version 5 buckets) and `primary_cause_group`.

Singular: `assert_mart_cash_discount_kpi_by_cause_row_count` (6 rows), `assert_mart_cash_discount_kpi_by_cause_expected_values` (per-cause count/EUR), `assert_mart_cash_discount_kpi_by_cause_reconciles_to_headline` (sums match headline mart).

Unchanged: `assert_mart_cash_discount_kpi_expected_values`, `fct_inv_sap` waterfall logic, hero scenarios, existing fct leakage singular tests.

Run: `dbt build --select mart_cash_discount_kpi_by_cause+` then `dbt test --select mart_cash_discount_kpi_by_cause mart_cash_discount_kpi`.

Deferred (unchanged): mart by vendor / company_code; mart by `primary_cause_group` only (derive in BI from this mart); Coupa mart; timing sub-buckets; wrong_clock_confirmed.

Why: Surfaces portfolio-ready leakage breakdown by Version 5 cause while keeping headline KPI mart stable and fact attribution as single source of truth.

Impact: BI can filter/roll up by `primary_cause` or `primary_cause_group`; totals reconcile to headline mart.

2026-09-15 — Version 5 seed expansion (primary_cause bucket coverage)

Context:

Version 5 root-cause waterfall was implemented on `fct_inv_sap` but synthetic seeds only covered two leakage buckets (`timing` on 5100000003, `capture` on 5100000012). Structural sub-buckets, `data_quality_error`, and key `available_days` boundaries had no labeled scenarios or singular tests.

Decision:

Strategy **Option A** — add new KR + Coupa rows and update funnel/mart count tests (heroes unchanged).

Seeds

- `seed_payment_term_sap.csv` — added **Z205** (2/5 net 30; discount_pct 0.02, discount_days 5) so Rule 2 (`structural_terms_vs_capability`) can fire.
- `raw_inv_sap.csv` — added 6 KR rows (5100000016–5100000021).
- `raw_inv_coupa.csv` — added 5 rows (10016–10020); no Coupa row for 5100000021 (SAP-only FB60).

Scenario matrix (leakage rows)

| BELNR | coupa_id | ZTERM | primary_cause | available_days | lost € | Notes |
|-------|----------|-------|---------------|----------------|--------|-------|
| 5100000003 | 10003 | Z210 | timing | 13 | 17.80 | **hero** — unchanged |
| 5100000012 | 10012 | Z210 | capture | 13 | 13.40 | **hero** — unchanged |
| 5100000016 | 10016 | Z205 | structural_terms_vs_capability | 15 | 20.00 | Rule 2; discount_days (5) < standard (10) |
| 5100000017 | 10017 | Z210 | structural_insufficient_time_at_intake | 3 | 16.00 | Rule 3; cleared after deadline |
| 5100000018 | 10018 | Z210 | structural_compressed_intake | 5 | 12.00 | Rule 4; boundary available_days = minimum (5) |
| 5100000019 | 10019 | Z210 | timing | 10 | 11.00 | Rule 5; boundary available_days = standard (10) |
| 5100000020 | 10020 | Z210 | capture | 7 | 15.00 | Rule 1 wins despite compressed intake |
| 5100000021 | — | Z210 | data_quality_error | null | 18.00 | SAP-only; empty XREF2_HD; receipt_date null |

Hero / excluded (unchanged)

- 5100000013 → excluded (`do_not_take_skonto_at_clearing`), not leakage.

Expected counts (period 2024, default vars)

| Metric | Value |
|--------|-------|
| fct_inv_sap rows | 20 |
| fct_inv_coupa rows | 19 |
| map_inv_sap_coupa rows | 17 |
| fct_inv_coupa paid matched | 14 |
| kpi_entitled | 12 |
| taken | 3 |
| excluded | 1 |
| leakage | 8 |
| leakage_eur | 123.20 |
| discount_opportunity_eur | 288.21 |
| leakage_rate (4 dp) | 0.4275 |

Tests

Updated: `assert_fct_inv_sap_kpi_funnel_counts`, `assert_mart_cash_discount_kpi_expected_values`, `assert_map_inv_sap_coupa_row_count`, `assert_fct_inv_coupa_row_count`, `assert_fct_inv_coupa_paid_matched_count`, `assert_fct_inv_sap_sap_ref_key_scenarios` (explicit `IN` lists — string `BETWEEN` on BELNR is unsafe), `assert_map_inv_sap_coupa_orphans_absent` (added 5100000021).

Added singular tests per bucket: `assert_fct_inv_sap_leakage_terms_vs_capability`, `assert_fct_inv_sap_leakage_insufficient_intake`, `assert_fct_inv_sap_leakage_compressed_intake_boundary_5`, `assert_fct_inv_sap_leakage_timing_boundary_10`, `assert_fct_inv_sap_leakage_capture_compressed`, `assert_fct_inv_sap_leakage_data_quality`; optional `assert_fct_inv_sap_leakage_v5_bucket_coverage`.

Unchanged: hero tests `assert_fct_inv_sap_leakage_seed_scenarios`, `assert_fct_inv_sap_leakage_timing_hero_flags`.

Run: `dbt seed --full-refresh` then `dbt build --select fct_inv_coupa fct_inv_sap+ map_inv_sap_coupa+` then `dbt test --select fct_inv_sap mart_cash_discount_kpi`.

Deferred (unchanged): timing sub-buckets, wrong_clock_confirmed. Mart breakdown by primary_cause → see 2026-09-16 entry.

Why: Completes labeled curriculum for all six Version 5 `primary_cause` buckets without changing waterfall logic or hero scenarios.

Impact: Every `primary_cause` value has at least one auditable seed scenario; funnel/mart totals reflect expanded synthetic portfolio.

2026-09-14 — Leakage root-cause waterfall Version 5

Context:

The 2026-09-12 P1 implementation classified leakage only as capture when paid within the discount deadline and timing when paid afterward, with structural as a defensive fallback. That attribution was provisional.

Version 4 introduced receipt-relative structural diagnosis, but defined the operational window as receipt_date + discount_days. This produced a “long-terms loophole”: generous contractual terms could give AP an unrealistically long operational allowance.

Decision:

Scope

This waterfall applies only after an invoice is confirmed as leakage:

is_leakage = is_kpi_entitled AND NOT is_taken AND NOT is_excluded

It does not change leakage eligibility, lost_discount_amount, funnel counts, leakage_eur, or leakage_rate. It only refines root-cause attribution.

The existing leakage funnel remains:

ENTITLED → TAKEN → EXCLUDED → LEAKAGE

Version 5 is a root-cause waterfall after LEAKAGE, not a replacement funnel.

Definitions

contractual_deadline_date:
The existing discount_deadline_date. Derived from baseline_date + discount_days.

receipt_date:
The single authoritative intake timestamp used by Version 5. Supplier submission, technical receipt, AP availability, and first-touch timestamps are not separated yet. Therefore, receipt_date alone must not be treated as proof of vendor responsibility.

discount_days:
Contractual discount-window duration.

minimum_cycle_days:
The defensible absolute minimum elapsed time required to complete processing under expedited conditions. This must not be based on a single fastest historical outlier.

standard_cycle_days:
The sustainable, reasonably expected elapsed processing cycle under normal operations. This represents the standard required lead time or agreed operational SLA, not an unfiltered historical average.

available_days:
datediff('day', receipt_date, contractual_deadline_date)

actual_cycle_days:
datediff('day', receipt_date, clearing_date)

If operational_deadline_date is materialized for reporting, it is:

receipt_date + standard_cycle_days

It is no longer receipt_date + discount_days.

minimum_cycle_days, standard_cycle_days, discount_days, available_days, and actual_cycle_days must use the same calendar convention and unit. Benchmark values and segmentation are implementation follow-ups.

Benchmark constraints:

minimum_cycle_days > 0
standard_cycle_days >= minimum_cycle_days
discount_days > 0

Ordered root-cause logic

Apply the following CASE only to leakage rows:

CASE
    -- Rule 0: Data quality
    WHEN receipt_date IS NULL
      OR clearing_date IS NULL
      OR contractual_deadline_date IS NULL
      OR discount_days IS NULL
      OR minimum_cycle_days IS NULL
      OR standard_cycle_days IS NULL
      OR discount_days <= 0
      OR minimum_cycle_days <= 0
      OR standard_cycle_days < minimum_cycle_days
      OR receipt_date > clearing_date
        THEN 'data_quality_error'

    -- Rule 1: Capture failure
    -- The discount was contractually available at clearing, but was not taken.
    WHEN clearing_date <= contractual_deadline_date
        THEN 'capture'

    -- Rule 2: Structural — terms vs capability
    -- Contractual terms do not provide the standard required processing time.
    WHEN discount_days < standard_cycle_days
        THEN 'structural_terms_vs_capability'

    -- Rule 3: Structural — insufficient time at intake
    -- The remaining time was below the absolute expedited minimum.
    WHEN datediff('day', receipt_date, contractual_deadline_date)
         < minimum_cycle_days
        THEN 'structural_insufficient_time_at_intake'

    -- Rule 4: Structural — compressed intake
    -- The invoice remained feasible, but required expedited processing.
    -- Rule 3 already guarantees available_days >= minimum_cycle_days.
    WHEN datediff('day', receipt_date, contractual_deadline_date)
         < standard_cycle_days
        THEN 'structural_compressed_intake'

    -- Rule 5: Timing / execution
    -- Standard processing time was available, but the deadline was missed.
    ELSE 'timing'
END

Boundary rules

available_days < minimum_cycle_days:
Physically infeasible under the defined benchmark.

minimum_cycle_days <= available_days < standard_cycle_days:
Feasible only through acceleration or expedited processing.

available_days >= standard_cycle_days:
Standard processing time was available. A missed contractual deadline is timing/execution.

Equality with standard_cycle_days belongs to timing because the complete standard lead time was available.

Rule precedence intentionally assigns one primary cause. Other conditions may still be recorded as contributors; the primary bucket is not a claim that no secondary contributor existed.

Secondary flags

For valid leakage rows that missed the contractual deadline:

is_still_feasible =
    available_days >= minimum_cycle_days

requires_expedited_processing =
    available_days >= minimum_cycle_days
    AND available_days < standard_cycle_days

is_timing_contributor =
    clearing_date > contractual_deadline_date
    AND actual_cycle_days > standard_cycle_days

The flags are NULL on data-quality rows, non-leakage rows, and capture rows.

is_still_feasible means feasible at receipt, not feasible at the current date.

requires_expedited_processing identifies invoices that could still have succeeded at receipt, but not through the normal processing cycle.

is_timing_contributor identifies structural cases where AP also exceeded its standard cycle. It does not replace the ordered primary cause.

Cause roll-up

Detailed outcomes roll up to the existing broad taxonomy:

capture → capture
structural_* → structural
timing → timing
data_quality_error → unclassified

Responsibility interpretation

capture:
Payment execution or discount-capture process.

structural_terms_vs_capability:
Procurement/contracts ownership. If discount_days is below minimum_cycle_days, the terms are physically infeasible. If it is between minimum and standard, the terms require non-standard acceleration.

structural_insufficient_time_at_intake:
Upstream intake ownership. Vendor responsibility may only be assigned when submission timestamps or contractual evidence support it.

structural_compressed_intake:
Shared-risk warning. Upstream intake failed to provide standard lead time, while AP still had an expedite opportunity.

timing:
Internal AP/process execution, to be broken down in a later timing-attribution phase.

Use accountability/ownership language rather than asserting blame where source evidence is unavailable.

Wrong clock

Wrong clock is removed from the date-derived primary bucket list.

A difference between baseline_date and receipt_date does not prove that the clock was wrong. It may represent supplier transmission, mailroom handling, integration latency, or a contractually correct invoice-date baseline.

A future wrong_clock_confirmed flag requires evidence that the ERP baseline or AP target deadline contradicted the authoritative contract or approved policy. Until that evidence exists, Rules 3 and 4 describe the observable intake condition without assigning a wrong-clock cause.

Implementation status

**Implemented in `fct_inv_sap` (2026-09-15).**

P1 implementation choices:

- **contractual_deadline_date:** implemented as existing column `discount_deadline_date` (baseline_date + discount_days). No rename in P1.
- **receipt_date:** `fct_inv_coupa.created_at::date`, joined on `sap_ref_key = coupa_id`. Null on SAP-only rows (5100000014, 5100000015). Leakage without receipt → `data_quality_error`.
- **discount_days:** passed through from `seed_payment_term_sap` in `with_terms`.
- **minimum_cycle_days / standard_cycle_days:** flat dbt vars in `fct_inv_sap` — **5** and **10** calendar days. Segmentation and benchmark governance deferred.
- **Day convention:** calendar days throughout (`datediff('day', …)`).
- **CTE chain:** … → with_exclusion → with_receipt → with_cycle_benchmarks → with_leakage_diagnostics → with_primary_cause → with_leakage.
- **Columns added:** receipt_date, discount_days, minimum_cycle_days, standard_cycle_days, available_days, actual_cycle_days, operational_deadline_date, primary_cause_group, is_still_feasible, requires_expedited_processing, is_timing_contributor. `primary_cause` uses Version 5 detailed buckets.

Expected on current synthetic data (period 2024, default vars):

- Funnel: 12 kpi_entitled / 3 taken / 1 excluded / 8 leakage / leakage_eur 123.20.
- Heroes unchanged: 5100000003 → `timing`; 5100000012 → `capture`; 5100000013 → excluded.
- All six `primary_cause` buckets covered on leakage rows (see 2026-09-15 seed expansion entry).
Deferred:

- Timing sub-buckets (Coupa phase breakdown).
- wrong_clock_confirmed.
- Benchmark seed table / segmentation by invoice type.
- Production receipt_date source mapping.

Run: `dbt build --select fct_inv_coupa fct_inv_sap+` then `dbt test --select fct_inv_sap`.

2026-09-13 — SAP posting reference (XREF2_HD) + map_inv_sap_coupa
Context: Coupa P1 slim slice complete (fct_inv_coupa, 14 rows). Next per 2026-08-31 architecture: cross-system match at SAP posting via sap_ref_key on fct_inv_sap and bridge table map_inv_sap_coupa. KPI authority remains SAP-only; no funnel or mart changes. Rejected BELNR-derived shortcuts — reference must live in raw SAP data as integration would stamp it.
Decision:
Raw (seed)
File: seeds/raw_inv_sap.csv — added column XREF2_HD (BKPF reference key 2, header).
Simulates Coupa → SAP integration auto-stamping Coupa invoice id at posting time (not manual AP entry).
Populated with coupa_id for Coupa-posted documents 5100000001–5100000013 → 10001–10013.
Empty on FB60 SAP-only orphans 5100000014, 5100000015 (no Coupa counterpart).
KG credit note 5100000010 carries 10010 in raw/src only; excluded from fct by document_type filter.
No XBLNR / invoice-number on SAP for map join — coupa_id is the system key.
Src
Model: src_inv_sap (view) — rename/cast only.
XREF2_HD → coupa_posting_ref (varchar; nullif empty trim).
Fct
Model: fct_inv_sap (table) — pass-through only; no derived join logic.
coupa_posting_ref → sap_ref_key in final select.
Funnel CTEs unchanged. FB60 orphans: sap_ref_key null.
Map
Model: map_inv_sap_coupa (table, models/map/).
Grain: (sap_inv_key, coupa_id) — 1:1, 12 rows.
Population:
```sql
SELECT s.sap_inv_key, c.coupa_id
FROM fct_inv_sap s
INNER JOIN fct_inv_coupa c ON s.sap_ref_key = c.coupa_id
WHERE s.sap_ref_key IS NOT NULL
Orphans excluded from map (remain in facts only): SAP FB60: 5100000014, 5100000015. Coupa: 10014 disputed, 10015 voided. Credit note: 10010 (not in fct_inv_coupa).

Expected on current synthetic data

fct_inv_sap: 14 rows; 12 with sap_ref_key populated; 2 null (0014/0015). map_inv_sap_coupa: 12 rows. fct_inv_coupa: 14 rows unchanged. mart_cash_discount_kpi unchanged: funnel 6/3/1/2; leakage_eur 31.20.

Tests

File: models/fct/_fct__models.yml — sap_ref_key documented on fct_inv_sap. File: models/map/_map__models.yml — sap_inv_key + coupa_id unique/not_null; relationships → respective facts. Singular: assert_map_inv_sap_coupa_row_count (12), assert_map_inv_sap_coupa_sap_ref_key_matches_coupa_id, assert_map_inv_sap_coupa_orphans_absent, assert_fct_inv_sap_sap_ref_key_scenarios. SAP funnel + mart tests unchanged.

Run: dbt seed --full-refresh --select raw_inv_sap && dbt build --select raw_inv_sap+ map_inv_sap_coupa+

Why: Models realistic Coupa-SAP integration (automatic id stamping at post) without bypassing raw. Single join key (coupa_id); symmetric bridge without fact-to-fact FK.

Impact: Cross-system invoice match complete for P1. Next: fct_inv_coupa_changes (timing drill-down). Deferred: XBLNR for supplier-ref realism, Coupa mart, Coupa pre-post in-flight, SAP parked docs, entitlement-at-clearing snapshot (P2+).

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

Dimensional mart breakdowns (vendor, company_code); Coupa mart or cross-system union. `primary_cause` breakdown → `mart_cash_discount_kpi_by_cause` (2026-09-16). sap_ref_key and map_inv_sap_coupa implemented 2026-09-13.

Tests

File: models/mart/_mart__models.yml — docs + not_null on period bounds and key metrics.
Singular test: tests/assert_mart_cash_discount_kpi_expected_values.sql — asserts funnel counts, leakage_eur = 31.20, discount_opportunity_eur = 196.21, round(leakage_rate, 4) = 0.1590.
Optional: partition test (realized + excluded + leakage = discount_opportunity_eur).

Run: dbt build --select mart_cash_discount_kpi+

Why: Surfaces portfolio-ready headline KPIs without re-implementing funnel logic. Mart reads classified fact flags; single source of truth remains fct_inv_sap.

Impact: P1 SAP leakage story complete end-to-end (seed → fct → mart). Next parallel tracks: Coupa invoice slice, map_inv_sap_coupa, sap_ref_key; P2+ entitlement-at-clearing snapshot.


2026-09-12 — Leakage classification on fct_inv_sap

Supersession note (2026-09-14):

The leakage formula, lost_discount_amount, and KPI results in this entry remain current. The date-only primary_cause attribution and its accepted values were provisional and are superseded at the design level by the 2026-09-14 Version 5 root-cause waterfall. The existing SQL continues to represent the implemented P1 state until Version 5 is implemented.

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

Resolution note (2026-09-14):

The deferred attribution rules were resolved by the Version 5 root-cause waterfall. The original broad categories remain valid; Version 5 adds detailed structural subtypes and secondary feasibility/contributor flags.

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
| seed_payment_term_sap | seed | one row per ZTERM | Z210, N030, Z205; 3 rows |
| raw_inv_sap | seed | one row per AP document | SAP BKPF-style; 21 rows; incl. XREF2_HD, 5100000016–5100000021 |
| src_inv_sap | src (view) | one row per AP document | Rename + sap_inv_key; clearing_date, discount_taken_amount, four *_at_clearing flags |
| fct_inv_sap | fct (table) | one row per vendor invoice (KR) | 20 rows; P1 funnel + Version 5 root-cause (all buckets covered) |
| raw_vendor_coupa | seed | one row per supplier | Coupa API names; 7 rows; quote_columns |
| src_vendor_coupa | src (view) | one row per supplier | Rename + cast; includes inactive |
| dim_vendor_coupa | dim (table) | one row per active supplier | status = active; 6 rows; is_active |
| raw_inv_coupa | seed | one row per invoice doc | 20 rows; quote_columns |
| src_inv_coupa | src (view) | one row per invoice doc | All doc types incl. credit note |
| fct_inv_coupa | fct (table) | one row per Coupa invoice | 19 rows; 14 paid matched |
| _dim__models.yml | schema | — | vendor_id + is_active tests (SAP + Coupa) |
| _fct__models.yml | schema | — | SAP funnel tests + fct_inv_coupa slim column tests |
| tests/ | singular | — | Version 5 bucket tests + mart by-cause reconciliation |
| map_inv_sap_coupa | map (table) | (sap_inv_key, coupa_id) | 17 confirmed matches |
| mart_cash_discount_kpi | mart (table) | one row per reporting period | Headline funnel KPIs; leakage_eur 123.20 |
| mart_cash_discount_kpi_by_cause | mart (table) | one row per period × primary_cause | 6 rows; leakage breakdown; reconciles to headline |
| fct_inv_timing_span | fct (table) | (sap_inv_key, phase_level, phase_code, span_seq) | 40 rows; ownership pre_sap + payment |
| mart_timing_phase_profile | mart (table) | period × phase_level × phase_code | 2 rows; measured spans by span_end_date |
| fct_inv_timing_span | fct (table) | (sap_inv_key, phase_level, phase_code, span_seq) | Slice 1: 40 ownership rows; Slice 2 adds subprocess + event IDs |
| mart_timing_phase_profile | mart (table) | one row per period x phase_level x phase_code | Slice 1: 2 rows; Slice 2 target: 7 rows |
| raw_inv_coupa_changes | seed | one row per Coupa revision | Slice 2 pre-build; quote_columns |
| seed_coupa_status_map | seed | one row per Coupa status | Slice 2 pre-build; D21 vocabulary |
| src_inv_coupa_changes | src (view) | one row per revision | Slice 2 pre-build |
| fct_inv_coupa_changes | fct (table) | coupa_change_id | Slice 2 pre-build; FK coupa_id -> fct_inv_coupa |---

## Conventions (stable)

Fill in as you go; mirror in `.cursor/rules/project.mdc` if the AI should always follow them.

- **Project name / profile:** `cash_discount` / profile `cash_discount` in `~/.dbt/profiles.yml`
- **Default schema:** `DEV` (database `AP_MODEL`)
- **Staging prefix:** `src_`
- **Key tests:** uniqueness, not_null on primary keys

---

## Chat handoff notes

<!-- Paste a short summary when switching to a new chat -->

Last updated: 2026-09-19

Timing slice 1 complete (ownership 40 spans, mart 2 rows). Slice 2 pre-build locked (D19–D29): retrofit only; fct_inv_coupa_changes + seed_coupa_status_map; subprocess phases intake/verification/approval/interface/payment; on_hold informational on 5100000008; no pending_receipt; no contrast singular tests; ownership rows must stay identical. Version 5 unchanged (12/3/1/8; leakage_eur 123.20). Next: implement slice 2 seeds/SQL, then slice 3 overlay reasons or slice 4 fct_inv_sap_changes.