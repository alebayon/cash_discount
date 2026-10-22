# Architecture decisions — cash_discount

Public summary of durable design choices for this portfolio dbt project.  
Narrative detail, term definitions, and model inventory: see [README.md](../README.md).  
Shared AP core (splits, shims, package path): [ap_core/docs/core_decisions.md](../ap_core/docs/core_decisions.md).  
A fuller internal decisions log is maintained locally and is not published.

---

## Purpose and scope

- **Goal:** Model Accounts Payable cash-discount **opportunity**, **realization**, **justified non-take**, and **leakage**, then assign each leakage invoice a single **primary cause** and (for timing causes) prorate lost euros across phases and buckets for prioritization.
- **Data:** Synthetic seeds only — illustrative policies and process design, not copied from any employer or client.
- **Systems modeled:** SAP (KPI authority) and Coupa (pre-SAP workflow context). Field names reflect common product shapes; logic is demonstrative.
- **Out of scope:** Additional ERPs, partial discount capture, business-day calendars, production orchestration, mart-driven PDF export (deferred).

---

## Design principles

### Invoice-centric KPIs

Headline metrics live at **one row per SAP vendor invoice** (`fct_inv_sap_cd`; shared spine `fct_inv_sap_core`). Marts aggregate from that grain and from reporting-period vars (`reporting_period_start` / `reporting_period_end` in `dbt_project.yml`).

### SAP as system of record

Entitlement, taken vs not taken, clearing in period, and leakage amounts use SAP. Coupa enriches receipt timing and change history; it does not define headline leakage KPIs.

### Deterministic, testable business rules

Policy thresholds and mappings live in **versioned seeds** (e.g. attribution policy). SQL references those seeds; singular tests guard a **labeled curriculum** of example invoices.

### Calendar days

All day counts use **calendar days** (warehouse `datediff` day semantics). No holiday or working-day engine in the model.

---

## Layering

| Layer | Folder | Role |
|-------|--------|------|
| Raw | `seeds/raw_*` | Synthetic extracts with source-style column names |
| Policy / maps | `seeds/seed_*` | Payment terms, status maps, attribution policy version |
| Staging | `models/src/` | Rename, cast, keys — no business rules |
| Intermediate | `models/int/` | Ephemeral — active policy row, blocker interval prep |
| Dimensions | `models/dim/` | Active vendors/suppliers |
| Bridge | `models/map/` | SAP invoice ↔ Coupa match at posting |
| Facts | `models/fct/` | Invoice fact, change streams, phase spans, overlays, timing allocation |
| Marts | `models/mart/` | Period KPIs, cause breakdown, timing action views |

**Authority model:** `fct_inv_sap_cd` owns funnel, leakage flag, `primary_cause`, and `lost_discount_amount` (built on shared `fct_inv_sap_core`). Timing allocation reads timing-type leakage only and does not change primary cause.

---

## Attribution policy (Version 6)

Stored in seed (e.g. `seed_attribution_policy`) with an active version row consumed by `int_attribution_policy_active` and echoed on invoice output.

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `minimum_processing_days` | 4 | Expedited minimum pre-SAP processing window |
| `standard_processing_days` | 7 | Sustainable standard pre-SAP allowance |
| `minimum_payment_runway_days` | 3 | Payment reserve after SAP entry before discount deadline |

**Combined contract design bar:** standard organizational need = **7 + 3 = 10** discount days (minimum feasible = **4 + 3 = 7**).

**Handoff milestone:** `sap_entry_date` from SAP CPUDT — payment ownership starts here; payment is modeled as automatic execution with clearing date as timeliness test.

**Key derived concepts:**

- `processing_available_days` — days from receipt to deadline minus payment reserve  
- `runway_at_handoff` — days from SAP entry to discount deadline  
- Contract terms evaluated **independently of** unusually early receipt (normative design test)

---

## KPI funnel (before leakage causes)

Applied on `fct_inv_sap_cd` in order:

1. **Vendor invoice** — document type vendor invoice (e.g. KR) with vendor present  
2. **Paid in period** — cleared in selected reporting period; open items excluded  
3. **KPI entitled** — discount potential and deadline fields present; else `not_entitled_reason`  
4. **Taken vs not taken** — full discount captured at clearing vs zero captured (partial capture out of scope)  
5. **Excluded vs leakage** (not taken only) — see exclusion rule below  

**Leakage:** entitled, not taken, not excluded.

---

## Exclusion rule

**Excluded** (justified non-take for headline KPI): explicit **do-not-take-discount** flag at clearing only.

Other clearing snapshots (payment block, dispute, match/GR flags) remain on the fact for audit and overlays but **do not** set `is_excluded`.

---

## Leakage primary-cause waterfall (ordered)

Exactly **one** `primary_cause` per leakage invoice. First matching rule wins.

| Order | Cause | Intent |
|-------|--------|--------|
| 0 | `data_quality_error` | Missing/invalid dates, policy, or impossible chronology |
| 1 | `capture` | Cleared on or before discount deadline but discount not taken |
| 2 | `structural_terms_vs_capability` | Discount terms below standard combined capability (10 days under 4/7/3) |
| 3 | `structural_insufficient_time_at_intake` | Too little time at receipt **and** payment reserve not met at handoff |
| 4 | `pre_sap_execution_compressed` | Compressed but feasible pre-SAP window; reserve not met |
| 5 | `pre_sap_execution_standard` | Standard pre-SAP window; reserve still not met |
| 6 | `payment_execution` | Reserve met at handoff; cleared after deadline |

**Recovery rule:** If intake was structurally tight but handoff delivers full payment runway, timing accountability shifts to **payment_execution**, not intake structural.

Diagnostics (`terms_condition`, `intake_condition`, `handoff_condition`, etc.) are exposed for analysis but do not override the ordered cause.

---

## Timing phases and blockers

### Phase spans (`fct_inv_timing_span`)

- **Ownership:** `pre_sap` (receipt → SAP entry), `payment` (SAP entry → clearing)  
- **Subprocess (pre-SAP):** intake, verification, approval, interface — from Coupa change history; subprocess days reconcile to ownership pre-SAP time  

### Overlays (`fct_inv_timing_overlay_core` + `fct_inv_timing_overlay_cd`)

Dated blocker intervals explain labeled delay inside phases. Sources:

- **Coupa-derived:** on hold, rework, invoice dispute — from `fct_inv_coupa_changes` via `int_inv_coupa_overlay_intervals`  
- **SAP-derived:** payment block from invoice change events  
- **Derived:** `payment_run_wait` for post-deadline wait in payment regime (timing leakage + payment allocation only)  

Hand-maintained overlay seeds were retired in favor of event-derived intervals where possible.

---

## Timing allocation (prioritization only)

Runs on leakage rows whose primary cause is a **timing** execution cause (`pre_sap_execution_compressed`, `pre_sap_execution_standard`, `payment_execution`).

- Does **not** change `primary_cause`  
- Splits `lost_discount_amount` across phases and **timing buckets** using day-based proration (`fct_inv_timing_allocation`)  
- **Regime:** if `runway_at_handoff` ≥ payment reserve → allocate in **payment** buckets only; else allocate across **pre-SAP** subprocess phases (and verification/approval blocker buckets)  
- Euros reconcile to invoice leakage; allocation is for **management prioritization**, not a second root-cause label  

Portfolio marts: `mart_timing_phase_impact`, `mart_timing_bucket_impact` (ACT vs WATCH style ranking).

---

## Cross-system match

`map_inv_sap_coupa` links SAP invoices to Coupa at posting (e.g. posting reference). SAP-only invoices (no Coupa row) remain in KPI scope where designed; Coupa does not override SAP amounts.

---

## Build sequence (how the repo grew)

1. SAP invoice fact — entitlement, paid-in-period, taken, leakage, headline mart  
2. Coupa + match — workflow context, change history  
3. Leakage waterfall + cause mart + curriculum expansion  
4. Timing slice 1 — ownership spans  
5. Timing slice 2 — Coupa subprocess split  
6. Timing slice 3 — blocker overlays and exposure bridge  
7. Timing slice 4 — euro allocation and action marts  
8. Overlay v2 — Coupa/SAP-derived intervals; payment run wait  
9. Policy v6 — pre-SAP vs payment reserve; waterfall refresh  
10. Exclusion refinement — do-not-take flag only  
11. Sample stakeholder PDF (`reports/`) — curriculum numbers embedded in generator v1; mart-driven export deferred  

---

## Testing strategy

- **Schema tests** in `models/*/_*__models.yml` — grain, keys, relationships  
- **Singular tests** in `tests/` — curriculum heroes, funnel counts, euro reconciliation, timing allocation integrity  
- Tests are part of the design: they document expected business behavior alongside SQL  

Typical local workflow: `dbt seed` → `dbt build` (requires a configured dbt profile; credentials stay outside the repo).

---

## Stakeholder reporting

Sample PDF and generator under `reports/` illustrate narrative binding to marts (headline KPIs, cause mix, timing actions). PDF is client-facing copy without internal model names; regenerate with `_generate_cash_discount_report_2024_v1.py` after `pip install fpdf2`.

---

## Open directions (not committed)

- Entitlement snapshot strictly at clearing if terms change retroactively  
- Finer receipt-date sourcing (submission vs technical receipt)  
- Working-day calendar for narrative only vs model  
- Mart-driven PDF and CI regeneration after `dbt build`  
- Deeper rework ownership when rejection reasons are modeled on events  

---

## License and use

Portfolio / demonstration project. Not offered as production-ready software for any organization. Adapt concepts with your own data, policies, and legal review.

---

*Last updated: 2026-10-15 — aligned with README and built model behavior on `main`.*
