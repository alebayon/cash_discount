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
- Timing bucket report (slice 4): working-day calendar — model stays calendar days (D6); weekends only in narrative footnotes.
- Timing bucket report: rework action ownership undetermined until rejection reasons are captured on Coupa events.
- Timing bucket report: action metrics format (baseline, target, re-measure date) not fixed.
- Timing bucket report: auto-escalate `no_recorded_blocker` when it ranks ACT NOW for two consecutive periods — proposed, not decided.

---

## Decisions

<!-- Copy this block for each new decision -->

2026-10-05 — Coupa-derived timing overlays; retire raw_inv_timing_overlay (overlay v2)

Context:

Hand-authored `raw_inv_timing_overlay` simulated a source table that does not exist in Coupa or SAP. Payment overlays were already derived (`payment_block` from SAP changes, `payment_run_wait` per D64). Pre-posting blockers should be derived from Coupa change history the same way. `vendor_response_wait` implied supplier-only wait without a Coupa status; replaced by dispute intervals from changes. Stale Snowflake objects `RAW_INV_TIMING_OVERLAY` / `SRC_INV_TIMING_OVERLAY` are dropped manually after file removal (dbt does not auto-drop removed models).

Status: BUILT — seeds, `int_inv_coupa_overlay_intervals`, `fct_inv_timing_overlay`, tests, mart owner_role updated.

Decisions:

D75 Overlay sources v2 [POLICY] — supersedes D40/D60 seed path for Coupa/manual rows; amends D36 vocabulary:
- Remove `raw_inv_timing_overlay`, `src_inv_timing_overlay`, and warehouse objects if still present.
- Derive Coupa intervals in `int_inv_coupa_overlay_intervals` from `fct_inv_coupa_changes`, map `coupa_id` → `sap_inv_key` via `map_inv_sap_coupa` (matched invoices only).
- `on_hold`: status `on_hold` → `interval_start` = `event_date`; `interval_end` = next change `event_date` on same `coupa_id` (order: `event_date`, `revision_seq`, `coupa_change_id`). Informational per D27; span clock unchanged.
- `rework`: each `rejected` → from latest prior `submitted` on same `coupa_id` (`max(coupa_change_id)` &lt; reject id) through reject `event_date` (D20).
- `inv_dispute`: Coupa change status `disputed` (informational in `seed_coupa_status_map`) → same open/close interval rule as `on_hold`. Overlay code `inv_dispute` is distinct from header status `disputed` and from `dispute_open_at_clearing` on `fct_inv_sap` (exclusion snapshot at clear; unchanged).
- Union in `fct_inv_timing_overlay` with `int_inv_sap_payment_block_intervals` and derived `payment_run_wait` (D64; unchanged).
- Retire `vendor_response_wait` from active vocabulary (removed from `seed_timing_overlay_reason_map`; not renamed).

D76 Active overlay reason codes [POLICY] — amends D36/D48:
- `on_hold`, `rework`, `inv_dispute`, `payment_block`, `payment_run_wait`.
- Deferred overlay codes remain: `pending_receipt`; ServiceNow ticket intervals; sub-states inside dispute.
- Coupa `disputed` on matched invoices is modeled via **changes**, not orphan header-only rows (10014 remains out of KPI funnel per D21).

D77 Curriculum and tests [FACT]:
- `raw_inv_coupa_changes`: add `disputed` on 10019 (`900093`, 2024-10-16 → pending 2024-10-18, 2d `inv_dispute`); 10023 (`900094`, 2024-08-05 → pending 2024-08-08, 3d `inv_dispute`). **94** rows in `fct_inv_coupa_changes`.
- Heroes: 5100000019 verification `inv_dispute` + payment `payment_run_wait` (replaces verification `vendor_response_wait`); 5100000023 verification `inv_dispute` €16.00; on_hold/rework unchanged on 0008/0022/0020/0024; payment block/run-wait on 0003/0019/0025 unchanged.
- `fct_inv_timing_overlay`: **10** rows (2 on_hold + 2 rework + 2 inv_dispute + 3 payment_run_wait + 1 payment_block).
- `mart_timing_bucket_impact`: bucket `inv_dispute`, `owner_role` **resolve dispute**; tie-break `inv_dispute`, then rework, then on_hold (replaces `vendor_response_wait`).

D78 Report copy [POLICY] — amends D52/D69 where they reference `vendor_response_wait`:
- Verification/approval bucket prose: **resolve dispute** (or equivalent), not “remove supplier wait.”
- `no_recorded_blocker` wording unchanged.

Run:

```bash
dbt seed --select seed_coupa_status_map seed_timing_overlay_reason_map raw_inv_coupa_changes
dbt run --select fct_inv_coupa_changes int_inv_coupa_overlay_intervals fct_inv_timing_overlay+
dbt test
```

2026-10-04 — Stakeholder cash discount report (narrative spec)

Context:

Slice 4 marts and D64 payment_run_wait are built and tested. This entry freezes **how** the customer-facing full report is written in chat or BI copy — not new SQL. Numbers come from `mart_cash_discount_kpi`, `mart_cash_discount_kpi_by_cause`, `mart_timing_phase_impact`, `mart_timing_bucket_impact`, and `fct_inv_timing_allocation` (plus vendor names from `fct_inv_sap` / dim when D52 concentration applies).

Status: PRE-BUILD COMPLETE — narrative and checklist only; no report mart or seed.

Decisions:

D67 Audience and voice [POLICY]:
- Reader: AP / finance stakeholder for the uploading company; period is **closed**.
- Tense: amounts describe **what happened**; actions describe **what to change next period** to avoid repeating loss. Do not imply discount can still be taken on cleared invoices.
- Aggregate only: no per-invoice story lists at portfolio scale. Name a **supplier** only when one vendor holds **≥ 60%** of that **ACT** bucket’s `priority_allocated_eur` (D52). Exception: capture / DQ / terms rows may name the single hero supplier when count = 1.

D68 Page order [POLICY]:
1. Title + period + currency + calendar days footnote (D6).
2. **Where the discount went** — funnel ASCII bars: Offered, Taken, Set aside, Lost (from headline mart).
3. **Where the €{leakage_eur} was lost** — by `primary_cause` / group, descending euros; **Timing** row marked as opening below (not numbered 1–6 unless user asks).
4. **What to change next period** — same cause order as §3; one short action per non-timing cause; timing deferred to §5.
5. **Timing, opened** — only `primary_cause = 'timing'` leakage euros (must reconcile to by-cause timing row).
   - Split: **Before SAP posting** vs **Payment** (from `mart_timing_phase_impact` payment vs pre-posting phases, euros desc).
   - **Before posting:** phase bars (interface, verification, approval, intake); bucket bars inside verification and approval; ACT buckets first inside phase (75% rule from mart).
   - **Payment:** two buckets only — **Waiting to clear after the deadline** (`payment_run_wait` aggregate) and **Payment block** (`payment_block`); no payment `no_recorded_blocker` (D64–D65).
6. **Reference (not leakage)** — taken + excluded one-liners.
7. **Action checklist** — see D71 (customer PDF). Optional internal footnote: table names (D72); omit from customer PDF unless requested.

D69 Labels and forbidden wording [POLICY]:
- Never: **“caused by”**, **“recoverable”**, **“recover €X”**, **“clear inside the discount window”** for invoices already cleared (use **schedule / propose payment while discount is still open**).
- `priority_allocated_eur` in prose: **management split** of lost discount by days; sums reconcile to invoice loss and timing by-cause total (D50).
- **Payment phase:** days after deadline with no block = **Waiting to clear after the deadline** (bucket `payment_run_wait`). Do **not** call this “no recorded reason.” **`payment_block`** = SAP block interval during the window.
- **Verification / approval:** gap bucket = **In {phase}, no blocker recorded** — not “regular operations” as a fact; optional one line that queue vs active work needs labels or capacity / task-mining; do not claim task mining is in scope.
- **Rework:** one line — record rejection reasons; Coupa may have free-text or configured reasons; this extract has status/timestamp only.
- **Curriculum hero overlay ≠ largest euro bucket:** e.g. 5100000024 — rework overlay is one day; largest share may be interface; never “rework €{full invoice loss}.”

D70 Timing payment copy [POLICY] — D64/D65:
- Combined payment run-wait line at **€37.80** (0003 + 0019 + 0025 non-block days). Nordic **€17.80**, FastPay **€20.00** — neither ≥ 60% of €37.80 → **do not** name one supplier on the whole run-wait line; say “start with Nordic / FastPay path” in actions.
- Payment block **€9.00** — smaller share / WATCH; release block during window or document forgoing discount.
- Do not resurrect payment **`no_recorded_blocker`** or three-bucket payment table (superseded D65).

D71 Action checklist [POLICY]:
- Final section for customer deliverable.
- Sort **by area** (process), then **€ descending within area**. Area order:
  1. Data quality  
  2. Terms / commercial  
  3. Intake & structural (insufficient + compressed)  
  4. Timing — pre-posting (intake → verification → approval → handoff/interface)  
  5. Timing — payment (waiting to clear, then block)  
  6. Capture  
- Columns: **Area | Do next period | € (this period) | Start with** (owner/supplier hint). Optional **Done ☐** in Excel; PDF without Done column is fine.
- Footnote on checklist: euros are **lost discount in scope** for the period, not a recovery promise.
- Optional second table: **Timing only (€{timing leakage})** — buckets in **process order**, not euro order; checkbox column.

D72 Data binding [FACT]:
- Period: `reporting_period_start` / `reporting_period_end` (default 2024-01-01 – 2024-12-31).
- Headline: `mart_cash_discount_kpi` (curriculum: 16 entitled, 3 taken, 1 excluded, 12 leakage, €190.20 / €355.21, rate 0.5355).
- By cause: `mart_cash_discount_kpi_by_cause` (6 rows; timing €95.80 / 6 invoices).
- Timing phases/buckets: `mart_timing_phase_impact`, `mart_timing_bucket_impact`, `action_status` ACT/WATCH, `owner_role` mapped to plain English (not SQL case strings in customer text).
- Supplier concentration: group-by on `fct_inv_timing_allocation` × `fct_inv_sap.vendor_id` for ACT buckets only (analysis pattern `analyses/timing_bucket_act_vendors.sql`).

D73 Out of scope for this report [POLICY]:
- ZFBDT/ZTERM phase 2; new marts; Coupa ops dashboard; changing allocation SQL; working-day engine (narrative footnote only); per-invoice 75% cover; auto-escalate `no_recorded_blocker` (still open in Open questions for product, not this PDF).

D74 When user asks for “full report” in Cursor [POLICY]:
- Read this entry plus D46–D52, D64–D66, and current mart test expected values.
- Output the full narrative per D68–D71 in one response (ASCII bars; tab-separated tables if user may paste to Excel).
- Do not

2026-10-04 — Payment remainder is payment_run_wait

D64 Payment window [POLICY] — replaces D37 authoring and D49 payment gap; adopts deferred policy C:
- Scope for ownership payment: discount_deadline_date through clearing_date.
- payment_block: SAP ZLSPR set → release, clipped to that window (unchanged, D58–D60).
- payment_run_wait: every other day in that window. It is the remainder, not an observed blocker and not a hand-typed overlay.
- No no_recorded_blocker bucket on ownership payment. Verification and approval gaps are unchanged.
- Do not author payment_run_wait in raw_inv_timing_overlay. Remove the 5100000003 row. A full-window typed row would double-count once the remainder is derived.
- Same invoice may carry payment_block and payment_run_wait on different days. The two intervals do not share a day.
D64 implementation [POLICY]:
- Derive payment_run_wait in `fct_inv_timing_overlay` (CTE chain: payment window → clip blocks → gap intervals → union). No `int_inv_sap_payment_run_wait_intervals` unless a second consumer is added later.
- `seed_timing_overlay_reason_map`: payment_run_wait source_system = derived (not manual).
D64 scope for derived payment_run_wait [POLICY] — policy A:
- Derive only where `is_leakage` and `primary_cause = 'timing'` and payment regime (`discount_deadline_date >= sap_entry_date`) and `clearing_date > discount_deadline_date`.
- Same population as timing payment-phase rows in `fct_inv_timing_allocation`. Do not derive on structural, capture, data_quality_error, or non-leakage clears (e.g. 5100000016, 5100000018, 5100000021, 5100000011).
- Expected overlay rows: 6 seed + 3 derived payment_run_wait + 1 derived payment_block (5100000025) = 10.

D65 Curriculum [FACT] — replaces the payment bucket freeze in D49 / D57-v2:
- 5100000003: payment_run_wait, 14 days, €17.80.
- 5100000019: payment_run_wait, 11 days, €11.00.
- 5100000025: payment_block 7 days €9.00 (11–18 Nov), payment_run_wait 7 days €9.00 (18–25 Nov).
- mart_timing_bucket_impact, ownership payment: payment_run_wait €37.80, payment_block €9.00. No payment no_recorded_blocker row.
- Supplier concentration: Nordic €17.80 / €37.80 and FastPay €20.00 / €37.80, both under 60%. The run-wait line names no supplier.
- Phase row unchanged: 3 invoices, €46.80, post_deadline_days 39. Headline €95.80 timing leakage unchanged.

D65 supersedes (current mart / report totals only; older entries remain historical record):
- `mart_timing_bucket_impact` ownership payment: **payment_run_wait €37.80 + payment_block €9.00** (two bucket rows). Supersedes D51 / D57-v2 freeze of three payment buckets (€17.80 run-wait, €20.00 payment `no_recorded_blocker`, €9.00 block).
- D52 supplier concentration bullets for payment: Nordic **100%** of run-wait and FastPay **100%** of payment `no_recorded_blocker` — superseded. Under D65 neither vendor reaches 60% of **€37.80** combined run-wait; payment page run-wait line names no supplier.

D66 Supersedes (narrow):
- **D60** listed `payment_run_wait` from `raw_inv_timing_overlay` — superseded; derived in `fct_inv_timing_overlay` (D64). Seed holds on_hold / vendor_response_wait / rework only.
- **D61** “policy C deferred” — superseded; split run-wait after block release is implemented in D64. Overlap test `assert_fct_inv_timing_overlay_no_run_wait_block_overlap` retained.
- **D58 / D57-v2** `fct_inv_timing_overlay` **8 rows** — historical snapshot before D64; current **10 rows** (6 seed + 3 derived run-wait + 1 SAP `payment_block`).
- **D44 chronology** full-window run-wait (start = deadline, end = clearing only) — superseded; D64 allows segments inside the payment window (hero 5100000025 tail 18–25 Nov).

Tests (D64):
- `assert_fct_inv_timing_overlay_row_count` → **10**
- `assert_fct_inv_timing_overlay_chronology` (segment bounds)
- `assert_fct_inv_timing_overlay_hero_5100000025_payment_run_wait`
- `assert_fct_inv_timing_allocation_payment_no_no_recorded_blocker`
- `assert_mart_timing_bucket_impact_curriculum` (€37.80 run-wait; 2 payment bucket rows)
- `assert_fct_inv_timing_allocation_hero_scenarios` (0019/0025 `payment_run_wait`)

Status: COMPLETE — built and tested 2026-10-04.

Run:

```bash
dbt seed --select raw_inv_timing_overlay seed_timing_overlay_reason_map
dbt run --select fct_inv_sap+ fct_inv_timing_overlay+ fct_inv_timing_allocation+ mart_timing_bucket_impact+
dbt test
```

2026-10-01 — SAP invoice changes phase 1: payment_block overlays from change events

Context:

Slice 4 curriculum v2 (D54–D57) authored payment_block for hero 5100000025 in raw_inv_timing_overlay (7 days post-deadline, €18 timing leakage; payment bucket €9.00). Phase 1 introduces the planned SAP change lineage (raw_inv_sap_changes → src_inv_sap_changes → fct_inv_sap_changes) and derives payment_block intervals from ZLSPR-style set/release events instead of hand-authored overlay seed rows for that reason. SAP changes are post-posting instrumentation; slice-4 regime, allocation, and mart SQL are unchanged. Coupa pattern (fct_inv_coupa_changes + seed_coupa_status_map) is layering reference only.

Status: COMPLETE — seeds, models, tests green.

Decisions:

D58 Scope [POLICY]:
- Phase 1: payment_block overlays only, from paired block set → release on fct_inv_sap_changes.
- Hero 5100000025: interval 2024-11-11 → 2024-11-18 (7 calendar days); vendor 0000100004; curriculum euros and mart_timing_bucket_impact payment_block €9.00 unchanged.
- Remove 5100000025 payment_block row from raw_inv_timing_overlay; fct_inv_timing_overlay **8 rows** at phase 1 close (7 seed + 1 derived; **10 rows after D64**).
- Do not change fct_inv_timing_span or fct_inv_timing_overlay_span SQL. Do not change fct_inv_timing_allocation or mart_timing_* SQL for this slice.

D59 Snapshot vs overlay [POLICY] — extends D38:
- payment_block_at_clearing on fct_inv_sap remains clearing snapshot only (PAYBLK_CLR seed / exclusion funnel).
- Overlay payment_block is duration during processing from change events; never derived from clearing snapshot flags.

D60 Overlay sources [POLICY] — amends D40 for payment_block only:
- on_hold, rework, vendor_response_wait: raw_inv_timing_overlay → src_inv_timing_overlay (unchanged). payment_run_wait from seed — **superseded by D64** (derived in fct_inv_timing_overlay).
- payment_block (source_system sap): int_inv_sap_payment_block_intervals from fct_inv_sap_changes, unioned in fct_inv_timing_overlay with reason map + fct_inv_sap join.
- source_change_id on SAP payment_block rows: set event sap_change_id; YAML relationships split by source_system (coupa → fct_inv_coupa_changes, sap → fct_inv_sap_changes).

D61 Authoring [POLICY] — D37 policy A:
- No calendar-day overlap between payment_run_wait and payment_block on the same sap_inv_key; enforce with singular test.
- Policy C (split payment_run_wait after block release) — **implemented in D64** (was deferred here at phase 1 close).

D62 Seeds and map [FACT]:
- raw_inv_sap_changes: synthetic CDHDR-style rows (minimal columns; CHANGENR → sap_change_id).
- seed_sap_payment_block_map: fname + value_old/value_new → block_event_role (set | release).
- seed_timing_overlay_reason_map: no change to payment_block / sap row.

D63 Supersedes (narrow):
- D54-v2 instruction not to edit fct_inv_timing_overlay SQL applies except union of SAP-derived payment_block (curriculum v2 2026-10-01 entry remains historical record).

Deferred (phase 1 out of scope):
- ZFBDT / ZTERM change events (phase 2).
- Full CDHDR simulation; auto-derivation of all overlay reasons from ERP.
- dispute / pending_receipt overlays; Coupa operational dashboard; entitlement-at-clearing snapshot.
- Deriving rework, on_hold, vendor_response_wait from SAP.

Tests (add or extend):
- assert_fct_inv_sap_changes_row_count (hero pair).
- assert_fct_inv_timing_overlay_hero_5100000025_payment_block.
- assert_fct_inv_timing_overlay_no_run_wait_block_overlap (D37).
- assert_fct_inv_timing_overlay_row_count **10** (was 8 at phase 1 close; D64); slice-4 curriculum tests updated per D65/D66.

Run after implementation:

dbt seed --select raw_inv_sap_changes raw_inv_timing_overlay seed_sap_payment_block_map
dbt run --select src_inv_sap_changes fct_inv_sap_changes int_inv_sap_payment_block_intervals fct_inv_timing_overlay+
dbt test


2026-10-01 — Slice 4 curriculum v2: pre-posting timing heroes + portfolio re-freeze

Context:

D54 deferred pre-posting BELNRs until additive seeds could exercise intake/verification/approval/interface allocation and verification buckets (on_hold, vendor_response_wait, rework) plus payment payment_block. Four invoices 5100000022–5100000025 added without changing payment-regime heroes 5100000003 (payment_run_wait €17.80) or 5100000019 (payment no_recorded_blocker €11.00). fct_inv_timing_allocation gained allocated_with_residual so rounded bucket euros reconcile to lost_discount_amount (fix 5100000024 €13.00 vs €13.01). mart_timing_phase_impact post_deadline_days fixed to avoid double-count across buckets on the same invoice.

Status: COMPLETE — seeds, models, tests green.

Decisions:

D54-v2 Seeds [FACT]:
- raw_inv_sap: +4 KR rows (5100000022–5100000025); fct_inv_sap row_count 24.
- raw_inv_coupa: +4 headers (10022–10025); fct_inv_coupa 23 rows; paid_matched 18.
- raw_inv_coupa_changes: extended for new Coupa paths; fct_inv_coupa_changes 92 rows.
- raw_inv_timing_overlay: +4 rows (on_hold, vendor_response_wait, rework, payment_block); fct_inv_timing_overlay 8 rows.
- map_inv_sap_coupa: 21 rows.
- Do not edit span/overlay_span model SQL for this curriculum; span totals move only via new invoices.

D55-v2 Timing leakage heroes [FACT]:
- 5100000022: pre-posting; verification on_hold 1 day; lost €20.00.
- 5100000023: pre-posting; verification vendor_response_wait 3 days; lost €16.00.
- 5100000024: pre-posting; rework 1 day; lost €13.00.
- 5100000025: payment regime (deadline on posting day); payment_block 7 days post-deadline; lost €18.00.
- Payment curriculum unchanged: 5100000003, 5100000019.
- Six timing-leakage invoices total; mart_cash_discount_kpi_by_cause timing: leakage_count 6, leakage_eur 95.80 (17.80 + 11.00 + 20.00 + 16.00 + 13.00 + 18.00).

D56-v2 Headline KPI re-freeze [FACT]:
- Funnel (fct_inv_sap): 24 rows; entitled 16; taken 3; not_taken 13; excluded 1; leakage 12; round(sum lost on leakage) 190.20.
- mart_cash_discount_kpi: discount_opportunity_eur 355.21; leakage_eur 190.20; round(leakage_rate, 4) = 0.5344.
- mart_cash_discount_kpi_by_cause unchanged grain (6 rows); timing row per D55-v2.

D57-v2 Slice 4 mart curriculum [FACT + tests]:
- mart_timing_phase_impact: ownership payment row — invoice_count 3, priority_allocated_eur 46.80, post_deadline_days 39 (5100000003, 5100000019, 5100000025); additional phase rows for pre-posting heroes (assert via full dbt test suite, not only payment row).
- mart_timing_bucket_impact (ownership payment): 3 buckets — payment_run_wait €17.80, no_recorded_blocker €20.00 (combined payment gap on heroes), payment_block €9.00 (5100000025); act_count ≥ 2 on payment page test.
- Reconciliation: sum(priority_allocated_eur) over timing leakage invoices = 95.80 = by-cause timing leakage_eur.

Timing instrumentation counts (post v2):
- fct_inv_timing_span: 48 total, 42 measured.
- fct_inv_timing_span subprocess: 124 rows.
- fct_inv_timing_overlay_span: tests unchanged in intent; overlay fact 8 rows.
- mart_timing_phase_profile: 7 rows (unchanged).

Tests added or updated:
- assert_fct_inv_timing_allocation_hero_5100000022
- assert_fct_inv_timing_allocation_row_count (minimum row guard; optional: freeze exact count after one Snowflake count)
- assert_mart_timing_phase_impact_curriculum (payment phase hero)
- assert_mart_timing_bucket_impact_curriculum (payment buckets)
- Portfolio: assert_fct_inv_sap_kpi_funnel_counts, assert_mart_cash_discount_kpi_expected_values, assert_mart_cash_discount_kpi_by_cause_expected_values
- Row counts: coupa 23, changes 92, paid_matched 18, map 21, overlay 8, span 48/42, subprocess 124

Run after seed change:

dbt seed
dbt run --select fct_inv_coupa fct_inv_coupa_changes fct_inv_sap map_inv_sap_coupa fct_inv_timing_span fct_inv_timing_overlay fct_inv_timing_allocation mart_timing_phase_impact mart_timing_bucket_impact mart_cash_discount_kpi mart_cash_discount_kpi_by_cause
dbt test

Deferred (unchanged from slice 4): dispute/pending_receipt overlays; auto-escalate no_recorded_blocker; working-day calendar; rework ownership until rejection reasons on Coupa; optional mart_timing_action_vendor / supplier concentration bullets in BI (D52).

2026-09-29 — Timing bucket report (slice 4): priority allocation, buckets, actions

Context:

Replaces the 2026-09-28 draft in full. Slice 4 turns timing-loss invoices into a stakeholder page: which phase to open, which bucket to act on, and which supplier to name. Explainability beats precision. priority_allocated_eur is a management allocation [POLICY], not “loss caused by” and not “recoverable”. no_recorded_blocker is an investigate step [INFERENCE], not a capacity finding. Measured days and euros that are sums of those allocations are [FACT].

Status: COMPLETE — built and tested 2026-09-29; curriculum v2 closed 2026-10-01.

Decisions (D46–D57):

D46 Scope and period [POLICY + FACT]:
- In scope: fct_inv_sap where is_leakage and primary_cause = 'timing' (use primary_cause in SQL and tests, consistent with mart_cash_discount_kpi_by_cause).
- Period vars: reporting_period_start and reporting_period_end, same as the KPI marts. is_leakage already requires is_kpi_entitled, so clearing_date is in period. Do not add a second clearing_date filter. Comment the anchor.
- This report is scoped by clearing_date. mart_timing_phase_profile stays on span_end_date (D3).
- Out of scope: structural, capture, and data_quality_error leakage; renegotiating the discount deadline as an operational action.

D47 Regime [POLICY]:
- If discount_deadline_date >= sap_entry_date, ownership payment receives 100% of lost_discount_amount. Ignore pre-SAP length and pre-SAP blockers. Do not allocate to subprocess payment.
- Else allocate across subprocess intake, verification, approval, and interface.
- Deadline on the posting day is payment. The cliff is not parameterised.

D48 Phase weights [POLICY + FACT]:
- Measured spans only. Computed inside fct_inv_timing_allocation. No fct_inv_timing_window.
- Pre-posting visit weight = greatest(0, datediff('day', span_start_date, least(span_end_date, discount_deadline_date))). Sum visits to the phase. phase_eur = lost_discount_amount × phase_weight_days / sum(phase_weight_days).
- Those weights sum to available_days (datediff from receipt to the deadline) when intake, verification, approval, and interface are measured and contiguous from receipt through the deadline.
- If regime is pre_posting and any of those four phases is not measured, the invoice is out of this report. No partial allocation.
- If total weight is 0, one unallocated row. Test that the curriculum has none.
- Payment phase euro is 100% of the invoice. Bucket denominator is post-deadline days: datediff('day', discount_deadline_date, clearing_date). Payment span_days are not a KPI.
- post_deadline_days is stored on the phase and repeated on its bucket rows. It carries €0.

D49 Buckets [POLICY + FACT]:
- Grain of fct_inv_timing_allocation: (sap_inv_key, phase_level, phase_code, bucket_code). Emit a row only when priority_allocated_eur > 0.
- Read gross days from fct_inv_timing_overlay_span. Do not modify that view. Do not copy its join into this fact. Do not put euros on it.
- Clip each bridge overlap to the phase weight window with greatest/least and datediff. Pre-posting window is span start through the deadline. Payment window is the deadline through clearing. No calendar generator and no 1/n split.
- Intake and interface: one bucket each, intake_delay and interface_delay, equal to the phase euro. Ignore overlays on those phases. Test that no overlay interval overlaps an intake or interface span. Do not clamp. D32 is unchanged on the overlay fact and on the view.
- Verification and approval buckets: vendor_response_wait, rework, on_hold, and no_recorded_blocker. gross_exposure_days is the clipped bridge exposure. If the sum of gross days is less than phase_weight_days, the gap is no_recorded_blocker. If the sum is greater, scale the blocker euros so they sum to the phase euro and the gap is €0. That scale-down is the accepted error when two blockers share a day.
- Payment buckets, ownership payment only: payment_run_wait and payment_block from the clipped bridge, gap no_recorded_blocker. Same scale-down if the gross days exceed the post-deadline window. Policy A (D37) stays an authoring rule. Slice 4 does not expand days to enforce it.
- 5100000003: ownership payment, payment_run_wait, 14 days, €17.80. 5100000019: ownership payment, no_recorded_blocker, 11 days, €11.00. The verification vendor-wait on 5100000019 takes none of that euro.

D50 Euros [POLICY]:
- Additive. Sum of priority_allocated_eur on an invoice equals lost_discount_amount. Sum over in-scope invoices equals mart_cash_discount_kpi_by_cause.leakage_eur where primary_cause = 'timing' (€95.80 after curriculum v2; see D54 table and 2026-10-01). Not the headline leakage_eur of all causes.
- Never label the metric “caused by” or “recoverable”.

D51 Ranking and the page [POLICY]:
- mart_timing_phase_impact grain: (reporting_period_start, reporting_period_end, phase_level, phase_code). Columns: invoice_count, priority_allocated_eur, post_deadline_days. Sort by euros. That is the page order. Curriculum v2 payment phase row: ownership payment, 3 invoices, €46.80, post_deadline_days 39 (plus additional phase rows for pre-posting heroes).
- mart_timing_bucket_impact grain: (reporting_period_start, reporting_period_end, phase_level, phase_code, bucket_code). Columns: invoice_count, gross_exposure_days, priority_allocated_eur, eur_share_of_phase, cumulative_eur_share, action_status, owner_role.
- Inside a phase, rank buckets by priority_allocated_eur. ACT = walk until cumulative share reaches 75% of the phase total, including the whole bucket that crosses the line. The rest are WATCH. WATCH stays in the mart and in the totals.
- Tie-break on equal euros only: vendor_response_wait, then rework, then on_hold.
- No per-invoice 75% cover. A short phase keeps its small euro share.
- Curriculum v2 ownership payment buckets: payment_run_wait €17.80, no_recorded_blocker €20.00, payment_block €9.00; ACT/WATCH per 75% rule (see assert_mart_timing_bucket_impact_curriculum).
- rework: if it is ACT in verification or approval, the report prints one bullet on the earlier of those pages and adds the other phase’s rework euros into that bullet. The mart keeps both phase rows.

D52 Actions [POLICY]:
- A bullet is a remedy, not a vendor. owner_role is a fixed case on bucket_code in the bucket mart (payment run, investigate unlabeled days, remove rework, remove supplier wait, release hold, remove intake delay, remove interface delay). No seed_timing_reason_owner. Prose titles stay in the report, not in SQL.
- Suppliers are a group-by of fct_inv_timing_allocation joined to fct_inv_sap.vendor_id, for the ACT buckets on the page. There is no mart_timing_action_vendor.
- is_concentrated when one vendor_id holds >= 60% of that bucket’s priority_allocated_eur. The flag only decides whether the bullet names the supplier. It does not change the remedy.
- On the current page: 0000100003 holds 100% of payment_run_wait; 0000100004 holds 100% of the payment no_recorded_blocker bucket.

D53 What is not built:
- Rejected for this slice: fct_inv_timing_window, fct_inv_timing_regime, fct_inv_timing_window_day_reason, fct_inv_timing_bucket, mart_timing_action_vendor, a day generator, and the 1/n split. Gross clipped exposure is the estimate. exclusive_blocker_days is not stored.
- fct_inv_timing_overlay_span remains the overlap view for every invoice, including non-timing rows, and remains the target of the slice 3 bridge tests.

D54 Portfolio [POLICY + FACT]:
- Curriculum v2 adds **additive** seeds only: `raw_inv_sap` (+5100000022–5100000025), `raw_inv_coupa` (+10022–10025), `raw_inv_coupa_changes` (extended paths), `raw_inv_timing_overlay` (+4 intervals). Do **not** move dates on payment heroes **5100000003** or **5100000019**.
- Do **not** edit model SQL for `fct_inv_timing_span`, `fct_inv_timing_overlay`, or `fct_inv_timing_overlay_span`; row counts move via seeds only.
- Pre-posting allocation is **tested** on **5100000022** (on_hold), **5100000023** (vendor_response_wait), **5100000024** (rework). Payment **payment_block** tested on **5100000025**.

Architecture:

Inputs: `fct_inv_sap`, `fct_inv_timing_span`, `fct_inv_timing_overlay_span` (seeds extended in v2).

Persisted:
- `fct_inv_timing_allocation` (table) — grain `(sap_inv_key, phase_level, phase_code, bucket_code)`. CTEs for regime, visit weights, clipped gross exposure; **phase-level and invoice-level cent residuals** so `sum(priority_allocated_eur)` = `lost_discount_amount` per invoice (D50).
- `mart_timing_phase_impact` (table) — `post_deadline_days` = **max per invoice × phase**, then summed (no double-count across buckets).
- `mart_timing_bucket_impact` (table).

Built artifacts:

Models: `fct_inv_timing_allocation` (table); `mart_timing_phase_impact` (table); `mart_timing_bucket_impact` (table).  
Fact columns: `sap_inv_key`, `phase_level`, `phase_code`, `bucket_code`, `gross_exposure_days`, `priority_allocated_eur`, `post_deadline_days`.

Actual counts (confirmed on build, curriculum v2):

| Metric | Value |
|--------|-------|
| `fct_inv_sap` rows | 24 |
| `fct_inv_coupa` rows | 23 |
| `fct_inv_coupa_changes` rows | 92 |
| `map_inv_sap_coupa` rows | 21 |
| `fct_inv_timing_span` total / measured | 48 / 42 |
| `fct_inv_timing_span` subprocess | 124 |
| `fct_inv_timing_overlay` rows | 8 |
| `fct_inv_timing_allocation` rows | ≥ 3 (singular test minimum; optional: freeze exact `count(*)` after build) |
| `mart_timing_phase_profile` rows | 7 (unchanged) |
| KPI funnel (entitled / taken / excluded / leakage) | 16 / 3 / 1 / 12 |
| `leakage_eur` (headline mart) | 190.20 |
| `discount_opportunity_eur` | 355.21 |
| `round(leakage_rate, 4)` | 0.5344 |
| timing `leakage_eur` (by cause) | 95.80 (6 timing-leakage invoices) |

Reconciliation (tests pass):

- Sum `priority_allocated_eur` over timing-leakage invoices = `mart_cash_discount_kpi_by_cause.leakage_eur` where `primary_cause = 'timing'` (**€95.80**).
- Per-invoice: sum `priority_allocated_eur` = `lost_discount_amount` (invoice reconcile tests).
- Payment heroes unchanged: **5100000003** `payment_run_wait` 14 d, **€17.80**; **5100000019** `no_recorded_blocker` 11 d, **€11.00** (no pre-SAP euro).
- Pre-posting heroes: **5100000022** €20.00 + verification `on_hold`; **5100000023** €16.00 + `vendor_response_wait`; **5100000024** €13.00 + `rework`; **5100000025** €18.00 + payment `payment_block`.
- `mart_timing_phase_impact`: ownership **payment** — 3 invoices, **€46.80**, **39** `post_deadline_days` (curriculum test).
- `mart_timing_bucket_impact`: ownership **payment** — 3 rows (`payment_run_wait` €17.80, `no_recorded_blocker` €20.00, `payment_block` €9.00); curriculum test expects **≥ 2** ACT on payment page.
- Unallocated grain empty; no overlay_span on intake/interface (overlap test).
- Slice 3 overlay bridge tests remain in suite; overlay **row count** updated to 8.

Tests (slice 4 + v2):

assert_fct_inv_timing_allocation_unique_grain  
assert_fct_inv_timing_allocation_row_count  
assert_fct_inv_timing_allocation_unallocated_empty  
assert_fct_inv_timing_allocation_reconciles_timing_leakage  
assert_fct_inv_timing_allocation_invoice_reconciles  
assert_fct_inv_timing_allocation_hero_scenarios  
assert_fct_inv_timing_allocation_hero_5100000022  
assert_fct_inv_timing_allocation_no_pre_sap_euro_on_heroes  
assert_fct_inv_timing_overlay_span_no_intake_interface_overlap  
assert_mart_timing_phase_impact_curriculum  
assert_mart_timing_bucket_impact_curriculum  

Plus portfolio row-count / KPI tests (`assert_fct_inv_sap_kpi_funnel_counts`, `assert_mart_cash_discount_kpi_expected_values`, `assert_mart_cash_discount_kpi_by_cause_expected_values`, Coupa/map/span/overlay counts).

Schema: `models/fct/_fct__models.yml` — `fct_inv_timing_allocation`; `models/mart/_mart__models.yml` — `mart_timing_phase_impact`, `mart_timing_bucket_impact`.

Run:

```bash
dbt seed
dbt build --select fct_inv_coupa+ fct_inv_sap+ fct_inv_timing_allocation+ mart_timing_phase_impact+ mart_timing_bucket_impact+ mart_cash_discount_kpi+
dbt test
```

Deferred: dispute and pending_receipt overlays; SAP change expansion beyond phase 1 payment_block (ZFBDT/ZTERM, full CDHDR); auto-derivation from ERP; payment_block versus payment_run_wait policy C; working-day calendar (D6); BI supplier bullets on ACT buckets (D52).

---

2026-09-22 — Timing phase layer slice 3 (blocker overlay intervals)

Context:

Slices 1–2 deliver phase-duration instrumentation on all 20 fct_inv_sap invoices: ownership spans (pre_sap, payment) and subprocess spans (intake, verification, approval, interface, payment) with Coupa event drill-through. Slice 3 adds blocker overlay intervals — labeled date ranges explaining why calendar time was consumed or blocked inside those spans. Still instrumentation/diagnosis; not Version 5 re-attribution and not a replacement for primary_cause or span_days. Version 5 funnel, heroes, slice 1–2 span row counts, mart_timing_phase_profile (7 rows), and every existing test must remain byte-for-byte unchanged.

Status: COMPLETE — built and tested 2026-09-23.

Decisions (D31–D45, slice 3 scope):

D31 Grain: fct_inv_timing_overlay grain = (sap_inv_key, overlay_reason_code, interval_seq). interval_seq restarts per (sap_inv_key, overlay_reason_code).

D32 Overlap: blocker intervals may overlap each other and may cross phase boundaries. Join to spans by date overlap only; never alter span_days. No global must-overlap-subprocess-span test; chronology plus hero tests are sufficient.

D33 Fact duration: fact stores interval_start_date, interval_end_date, interval_days (datediff calendar days, D6). blocked_days, unblocked_days, reason_exposure_days are derived in bridge/view — not stored on fact.

D34 Zero-day and rework semantics:

Schema allows zero-day intervals; slice 3 curriculum does not author zero-day blockers except where noted below.
on_hold, vendor_response_wait, payment_block: interval_days >= 1 in seeds.
rework: failed-visit window from verification_start (submitted) of that visit through approval_end (rejected) that closes the visit. Successful revisit (span_seq > 1) is not tagged rework. reject → immediate resubmit (D30) is not a separate overlay.
Curriculum 5100000020: rework 2024-11-04 → 2024-11-05, interval_days = 1; source_change_id anchors to submitted event 900067.
payment_run_wait: naturally >= 1 when clearing after deadline.

D35 Coverage naming (derived at invoice × subprocess phase):

span_days — phase clock (existing; source of truth).
blocked_days — distinct calendar days in phase where at least one blocker interval is active; blocked_days <= span_days.
unblocked_days — span_days minus blocked_days.
reason_exposure_days — per (phase, reason): overlap of that interval with that phase; sum across reasons may exceed blocked_days.

D36 Reason vocabulary — five overlay codes only (seed_timing_overlay_reason_map):

on_hold (reason_group hold, source_system coupa) — Coupa hold; informational per D27; does not pause span clock.
rework (reason_group rework, source_system coupa) — failed visit submit → reject.
vendor_response_wait (reason_group vendor, source_system manual) — supplier wait inside a phase.
payment_block (reason_group block, source_system sap) — block duration set → release; not clearing snapshot.
payment_run_wait (reason_group payment_execution, source_system manual) — deadline miss window.
Not overlay codes (use spans instead): approval_queue, verification_backlog, interface_failure, integration_lag. Interface failure = subprocess interface span where span_days > 0 (e.g. 5100000016).
Deferred reason codes: dispute, pending_receipt.

D37 payment_run_wait: interval_start = discount_deadline_date, interval_end = clearing_date; only when clearing_date > discount_deadline_date and no overlapping payment_block on same days. Anchored to ownership payment span (deadline → clearing lens, D13), not subprocess payment duplicate. vs payment_block: no double-label same days (policy A); split after block release (policy C) noted for future production.

D38 payment_block vs snapshot: payment_block_at_clearing on fct_inv_sap = point-in-time exclusion at clear. Overlay payment_block = duration during processing — separate grains; do not derive overlay from clearing snapshots.

D39 Interface: no interface overlay in slice 3; read slow interface from subprocess interface span_days > 0.

D40 Source: seed-only for slice 3 — raw_inv_timing_overlay → src_inv_timing_overlay → fct_inv_timing_overlay. Optional source_change_id → fct_inv_coupa_changes.coupa_change_id (YAML relationships test where not null; no join in fact SQL). No changes to raw_inv_coupa_changes or slice 2 span logic.

D41 Reconciliation: blocked_days <= span_days per phase where testable. No requirement that sum(reason_exposure_days) = span_days. Overlays explain; spans measure.

D42 Population: all 20 fct_inv_sap rows in scope; author intervals on curriculum BELNRs only. Open matched 5100000005, 5100000006, 5100000009: zero overlay rows in slice 3 seeds. SAP-only 5100000014, 5100000015, 5100000021: zero rows unless explicitly authored later.

D43 Aggregation / mart: slice 3 ships fact plus fct_inv_timing_overlay_span view (date overlap join to fct_inv_timing_span). No mart in slice 3; portfolio coverage table possible in a later slice. mart_timing_phase_profile unchanged (7 rows).

D44 Chronology (reason-specific bounds):

on_hold, rework, vendor_response_wait, payment_block: interval within receipt_date → clearing_date when cleared; pre-SAP blockers may end <= sap_entry_date.
payment_run_wait: discount_deadline_date → clearing_date.

D45 Portfolio / regression (hard constraint): retrofit only — no new raw_inv_sap / raw_inv_coupa header rows. Do not change raw_inv_coupa_changes. Frozen after slice 3 build: fct_inv_coupa_changes 72; fct_inv_timing_span ownership 40; subprocess 102; total 142; mart_timing_phase_profile 7; Version 5 funnel 12/3/1/8; leakage_eur 123.20.

Architecture:

Branch C (new): raw_inv_timing_overlay → src_inv_timing_overlay → fct_inv_timing_overlay; join seed_timing_overlay_reason_map + fct_inv_sap.
Bridge (view): fct_inv_timing_overlay_span — overlap join overlay intervals × fct_inv_timing_span (measured spans); derives reason_exposure_days at query time; blocked_days / unblocked_days roll up in BI.
Branches A + B (unchanged): fct_inv_timing_span ownership + subprocess; mart_timing_phase_profile.

Contrast curriculum (authored in raw_inv_timing_overlay):

| BELNR | overlay_reason_code | interval | source_change_id | Notes |
|-------|---------------------|----------|------------------|-------|
| 5100000003 | payment_run_wait | 2024-04-11 → 2024-04-25 (14d) | — | timing hero; deadline miss |
| 5100000008 | on_hold | 2024-06-08 → 2024-06-09 (1d) | 900031 | verification hold |
| 5100000019 | vendor_response_wait | 2024-10-16 → 2024-10-18 (2d) | — | slow verification |
| 5100000020 | rework | 2024-11-04 → 2024-11-05 (1d) | 900067 | failed visit 1 only |

Zero overlay rows: 5100000001, 5100000004, 5100000012, 5100000013, 5100000016, 5100000014, 5100000015, 5100000021, 5100000005, 5100000006, 5100000009, and remaining matched filler BELNRs. Optional 5100000017 / 5100000018 not authored in slice 3.

Built artifacts:

Seeds: seed_timing_overlay_reason_map.csv (5 rows); raw_inv_timing_overlay.csv (4 rows).
Models: src_inv_timing_overlay (view); fct_inv_timing_overlay (table); fct_inv_timing_overlay_span (view, materialized view).
Fact columns: sap_inv_key, overlay_reason_code, interval_seq, interval_start_date, interval_end_date, interval_days, reason_group, source_system, source_change_id, interval_notes.

Actual counts (confirmed on build):

| Metric | Value |
|--------|-------|
| seed_timing_overlay_reason_map rows | 5 |
| raw_inv_timing_overlay rows | 4 |
| fct_inv_timing_overlay rows | 4 |
| fct_inv_timing_span total rows | 142 (unchanged) |
| fct_inv_coupa_changes rows | 72 (unchanged) |
| mart_timing_phase_profile rows | 7 (unchanged) |
| Version 5 funnel | 12 / 3 / 1 / 8 |
| leakage_eur | 123.20 |

Reconciliation (tests pass):

- Full dbt test suite green before and after slice 3 build.
- blocked_days <= span_days on curriculum BELNRs (assert_fct_inv_timing_overlay_blocked_lte_span).
- payment_run_wait on 5100000003 overlaps ownership payment span with reason_exposure_days = 14.
- rework on 5100000020 does not appear on span_seq > 1.
- source_change_id 900031 and 900067 relate to fct_inv_coupa_changes.

Implementation notes:

- fct_inv_timing_overlay_span uses date overlap: interval_start_date < span_end_date AND interval_end_date > span_start_date.
- Hero test uses count(o.sap_inv_key) on left join (not count(*)) for zero-overlay BELNRs.
- payment_block code in reason map only; no curriculum row in slice 3 seeds.

Tests (added):

assert_fct_inv_timing_overlay_row_count (4)
assert_fct_inv_timing_overlay_unique_grain
assert_fct_inv_timing_overlay_chronology
assert_fct_inv_timing_overlay_reason_map_coverage
assert_fct_inv_timing_overlay_hero_scenarios
assert_fct_inv_timing_overlay_blocked_lte_span
Schema: models/fct/_fct__models.yml — fct_inv_timing_overlay + fct_inv_timing_overlay_span; source_change_id relationships → fct_inv_coupa_changes where not null.

Run:

dbt seed --full-refresh --select seed_timing_overlay_reason_map raw_inv_timing_overlay
dbt build --select fct_inv_timing_overlay+ fct_inv_timing_overlay_span+
dbt test

Version 5 unchanged (hard constraint): funnel 12/3/1/8; leakage_eur 123.20; heroes 5100000003 timing, 5100000012 capture, 5100000013 excluded.

Deferred (slice 4+): dispute/pending_receipt overlays; SAP change phase 2+ (ZFBDT/ZTERM, full CDHDR); mart_timing_blocker_coverage; auto-derivation from ERP; payment_block vs payment_run_wait policy C split.

---

2026-09-19 — Timing phase layer slice 2 (Coupa subprocess split)

Status: COMPLETE — built and tested 2026-09-20.

Decisions (D30, gap-free event authoring):

- D30: Coupa change events must form a contiguous chain from receipt to CPUDT so subprocess pre-SAP phases reconcile to ownership pre_sap without per-invoice day tuning (extends D28).
  - First `draft` event `created-at` = `raw_inv_coupa.created-at` for that invoice.
  - Rework: `rejected` immediately followed by `submitted` on same `event_date` (0-second auto-resubmit); higher `revision-number` on `submitted`.
  - Rework restarts at verification (`submitted`), not intake (`draft`) — D20 unchanged.
  - Tail: interface span_end = sap_entry_date (CPUDT) — D23 unchanged.

Actual counts (confirmed on build):

| Metric | Value |
|--------|-------|
| fct_inv_coupa_changes rows | 72 |
| fct_inv_timing_span ownership rows | 40 (unchanged vs slice 1) |
| fct_inv_timing_span subprocess rows | 102 (100 base + 2 rework on 5100000020) |
| fct_inv_timing_span total rows | 142 |
| mart_timing_phase_profile rows | 7 |
| Version 5 funnel | 12 / 3 / 1 / 8 |
| leakage_eur | 123.20 |

Reconciliation (tests pass):

- Ownership pre_sap span_days unchanged vs slice 1 logic (17 measured Coupa-matched).
- Corrected pre_sap reference (Snowflake datediff): 5100000001 = 5, 5100000003 = 4 (handover table had 4/3).
- Subprocess intake + verification + approval + interface = ownership pre_sap where all four measured.
- Subprocess payment matches ownership payment per sap_inv_key.
- Rework 5100000020: span_seq 1 and 2 on verification and approval.

Implementation notes:

- span_seq for verification/approval computed after QUALIFY dedup (`*_paired` CTEs) to avoid 1,3 skip on rework.
- No assert_fct_inv_timing_span_contrast_* tests (D28).
- Mart verification/approval span_count = 17 in 2024 (rework extra visit); other phases = 16.

Run:

dbt seed --full-refresh --select raw_inv_coupa_changes seed_coupa_status_map
dbt build --select fct_inv_coupa_changes+ fct_inv_timing_span+ mart_timing_phase_profile+
dbt test

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

Deferred (slice 3+): overlay reason intervals (SAP-derived beyond payment_block — see D58); frozen benchmarks; Coupa operational dashboard; wrong_clock_confirmed. Subprocess split -> see 2026-09-19 slice 2 pre-build entry.

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
- D29 Deferred unchanged: buffer_consumption, runway_at_handoff columns, dominant_phase / primary_timing_subbucket, Coupa in-flight operational dashboard (D10), frozen benchmarks (D16/D18), overlay reason intervals (slice 3), SAP change phase 2+ (slice 4+; phase 1 payment_block complete per D58).

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

| Object | Layer | Grain | Notes |
|--------|-------|-------|-------|
| raw_vendor_sap | seed | one row per vendor | SAP LFA1 names; 7 rows |
| raw_inv_sap | seed | one row per AP document | SAP BKPF-style; 25 rows; incl. 5100000022–5100000025 (curriculum v2) |
| raw_vendor_coupa | seed | one row per supplier | Coupa API names; 7 rows; quote_columns |
| raw_inv_coupa | seed | one row per invoice doc | 24 rows; quote_columns; +10022–10025 |
| raw_inv_coupa_changes | seed | one row per Coupa revision | 94 rows; quote_columns; +disputed on 10019/10023 (D75) |
| seed_payment_term_sap | seed | one row per ZTERM | Z210, N030, Z205; 3 rows |
| seed_coupa_status_map | seed | one row per Coupa status | 8 rows; +disputed informational (D75) |
| seed_timing_overlay_reason_map | seed | one row per overlay_reason_code | 5 rows; inv_dispute replaces vendor_response_wait (D75) |
| src_smoke_test | src (view) | — | Connection smoke test |
| src_vendor_sap | src (view) | one row per vendor | Rename + cast; includes deleted vendors |
| src_inv_sap | src (view) | one row per AP document | sap_inv_key; clearing_date, sap_entry_date, discount_taken_amount, four *_at_clearing flags |
| src_vendor_coupa | src (view) | one row per supplier | Rename + cast; includes inactive |
| src_inv_coupa | src (view) | one row per invoice doc | All doc types incl. credit note |
| src_inv_coupa_changes | src (view) | one row per revision | event_at, event_date, revision_seq |
| src_inv_sap_changes | src (view) | one row per change event | sap_change_id; rename/cast from raw_inv_sap_changes |
| dim_vendor_sap | dim (table) | one row per active vendor | deletion_flag is null; 6 rows |
| dim_vendor_coupa | dim (table) | one row per active supplier | status = active; 6 rows |
| fct_inv_sap | fct (table) | one row per vendor invoice (KR) | 24 rows; funnel 16/3/1/12; leakage €190.20 |
| fct_inv_coupa | fct (table) | one row per Coupa invoice | 23 rows; 18 paid matched |
| fct_inv_coupa_changes | fct (table) | coupa_change_id | 94 rows; status_role from seed_coupa_status_map |
| fct_inv_sap_changes | fct (table) | sap_change_id | 2 rows; block_event_role; FK sap_inv_key → fct_inv_sap (D58) |
| int_inv_sap_payment_block_intervals | int (ephemeral) | one row per derived block interval | ZLSPR set→release; feeds fct_inv_timing_overlay (D60) |
| int_inv_coupa_overlay_intervals | int (ephemeral) | one row per Coupa-derived interval | on_hold, rework, inv_dispute (D75) |
| fct_inv_timing_span | fct (table) | (sap_inv_key, phase_level, phase_code, span_seq) | 48 total; 42 measured; subprocess 124 |
| fct_inv_timing_overlay | fct (table) | (sap_inv_key, overlay_reason_code, interval_seq) | 10 rows (Coupa derived + 3 run-wait + 1 SAP block; D75); FK sap_inv_key → fct_inv_sap |
| fct_inv_timing_overlay_span | fct (view) | overlay interval × measured span overlap | reason_exposure_days derived; D32/D35 |
| map_inv_sap_coupa | map (table) | (sap_inv_key, coupa_id) | 21 confirmed matches |
| mart_cash_discount_kpi | mart (table) | one row per reporting period | leakage_eur 190.20; opportunity 355.21 |
| mart_cash_discount_kpi_by_cause | mart (table) | one row per period × primary_cause | 6 rows; reconciles to headline mart |
| mart_timing_phase_profile | mart (table) | one row per period × phase_level × phase_code | 7 rows; 2 ownership + 5 subprocess phases |
| _dim__models.yml | schema | — | dim_vendor_sap + dim_vendor_coupa tests |
| _map__models.yml | schema | — | map_inv_sap_coupa bridge tests |
| _fct__models.yml | schema | — | fct_inv_sap funnel, Coupa, SAP changes, timing span, timing overlay, timing allocation |
| _mart__models.yml | schema | — | mart KPI, by-cause, timing phase profile, timing bucket report |
| tests/ | singular | — | Version 5, mart, map, Coupa, timing slices 1–4, SAP phase 1 (D58), payment_run_wait D64 |
| seeds/_seeds.yml | seed config | — | quote_columns on Coupa seeds; seed column tests |
| fct_inv_timing_allocation | fct (table) | (sap_inv_key, phase_level, phase_code, bucket_code) | timing leakage; ≥3 rows (slice 4 + v2) |
| mart_timing_phase_impact | mart (table) | one row per period × phase_level × phase_code | multi-phase; payment row in curriculum test |
| mart_timing_bucket_impact | mart (table) | one row per period × phase × bucket_code | payment 2 buckets (run-wait €37.80 + block €9.00; D65); ACT/WATCH + owner_role |
| raw_inv_sap_changes | seed | one row per change document | 2 rows; phase 1 ZLSPR hero 5100000025 (D62) |
| seed_sap_payment_block_map | seed | (fname, value_old, value_new) | 2 rows; ZLSPR set/release roles (D62) |
---

## Conventions (stable)

Fill in as you go; mirror in `.cursor/rules/project.mdc` if the AI should always follow them.

- **Project name / profile:** `cash_discount` / profile `cash_discount` in `~/.dbt/profiles.yml`
- **Default schema:** `DEV` (database `AP_MODEL`)
- **Staging prefix:** `src_`
- **Key tests:** uniqueness, not_null on primary keys
-   **CSV handoff:** When proposing seed CSV content, always give markdown table + copy-paste CSV block.
-   **Model inventory:** Keep the table in this file current when adding seeds, models, or a completed slice; update row counts after `dbt build`. Do not duplicate the full table in `.cursor/rules/project.mdc` — the rule file already points here via "Read docs/decisions.md".
- **Decisions log handoff:** When the assistant proposes new or updated content for this file (decisions, policy, dated entries), deliver it as **self-contained copy-paste blocks** — one block per paste action (e.g. one dated decision entry per block). Do not split a single entry across multiple partial snippets.
- **Seeds and models handoff:** When the assistant proposes a change to any seed file or dbt model (new file, replace file, or material edit), deliver the **complete file contents** (or the full SQL/YAML for that file) in a single copy-paste block, not diffs-only or “add this CTE” fragments unless you explicitly ask for a minimal patch.
## Handoff format (mandatory)
- Proposed **decisions.md** additions: one copy-paste block per entry (full section text).
- Proposed **seed, model, test, or YAML** changes: **complete file contents** for every path mentioned — not bullet instructions like “update the test” or “add a CTE”.
- If only one hunk changes, still provide either the **full file** or a **single fenced block** labeled with the exact path that can replace the entire file.
- **No exceptions:** the reader must be able to implement without opening the chat for missing lines.

---

## Chat handoff notes

<!-- Paste a short summary when switching to a new chat -->

Last updated: 2026-10-04

D64/D65/D66: payment_run_wait derived (timing leakage + payment regime only); overlay 10 rows; payment mart buckets run-wait €37.80 + block €9.00; no payment no_recorded_blocker. SAP phase 1 (D58–D63) unchanged for ZLSPR block. dbt test green. Optional next: stakeholder report pre-build in decisions.md; SAP phase 2 (ZFBDT/ZTERM).