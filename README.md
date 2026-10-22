# cash_discount

Personal dbt project for cash discount analytics and modeling.

## Disclaimer

This project is for educational and demonstration purposes. The datasets are made to have realistic dates, amounts, and process variants. All data is synthetic, no real invoices, vendors, or company systems are used. Policies and process design are illustrative, not copied from any employer or client.

## Context

I've worked several years in Finance Operations using Process Mining. One of the things I often struggled with is how little control we had over process logic and data quality in large, complex models. Process Mining tools often focus on customer experience, fast and effective dashboarding, and multiple possibilities of executions. What I often miss is having a modular, comprehensive, and scalable quality and modeling control system. This is what I've found in dbt, an open-source tool for developing data models with end-to-end modular testing against the warehouse.

Analytics Engineering is the discipline centered on that layer: data modeling and the transformations between raw sources and dashboard-ready KPIs. It sits between Data Engineering (platforms and pipelines) and business analysis (functional specifications), where ownership of business rules is often split and neither side alone owns end-to-end logic.

The Analytics Engineer closes that gap by making transformations deterministic and explainable. When the model is trustworthy, stakeholders challenge the process, not the dashboard.

I'm building a series of dbt data solutions inspired by my Process Mining background, each addressing a major common business problem. These solutions are a strong baseline adaptable to any company and bring the end-to-end control every organization needs.

## Project Goal

This dbt project simulates an Accounts Payable domain. It measures cash discount leakage, takes raw data and policies as inputs, passes all invoices through a KPI funnel plus a leakage waterfall and resolves with a primary cause on all leakage rows and allocation on timing causes. 

It delivers a prioritized list of recommended actions that highlights where time and euros concentrate for action and will help the user to solve systemic issues for future cash discount leakage prevention.

## Design rationale

See [docs/architecture-decisions.md](docs/architecture-decisions.md) for durable architecture and policy choices (public summary).

## Term definitions

Allocation Eur: Impact expression of how much a phase or a blocker is contributing to the overall cash discount leakage in form of prorated amount. 

Attribution policy: Versioned thresholds and rules in seeds that drive entitlement and leakage attribution in SQL.

Blocker: A labeled reason (e.g. hold, rework, payment block) with a date range (overlay) that explains delay inside a phase.

Data/Domain model: The whole AP architecture (with multiple tables)

Dataset: Extraction data from a source system and the input data for the Data Model (raw_* seeds)

Dbt Model: Dbt materialized object (Table/view/ephemeral), it has its own sql file and lives under "models/" folder

Excluded: Invoices with cash discount potential not taken with a justified reason (not leakage category)

Exposure: Total time an overlay is contributing to leakage (double count if overlap). The exposure prorated is the source of allocation eur calculation

Grain: Level of aggregation of a model/table, what one row contains as distinct

Interval: Time range

Leakage (Cash Discount): Lost cash discount without a justified exclusion reason

Overlay: Date range for a blocker reason on an invoice.

Payment reserve (policy): Minimum calendar days payment must have after SAP entry before the discount deadline

Phase: Time division in a lifecycle of an invoice. There are two levels: ownership (pre_sap, payment) and subprocess (intake, verification, approval, interface).

Posting/Entry in SAP: System generated date (CPUDT) of invoice entry in SAP

Processing: Group of actions or time period happening to an invoice from receipt to SAP entry (pre-SAP time)

Primary cause: One headline leakage reason per invoice from the ordered leakage rules. Timing reasons use the same field, only those rows also split euros across timing buckets for prioritization.

Processing available days: Calendar days from receipt to discount deadline minus payment reserve.

Runway (at handoff): Actual calendar days from SAP entry to discount deadline

Span: Calendar days elapsed in a phase

## Architecture design overview:

This analytics model is built around posted vendor invoices in accounts payable. Cash-discount opportunity and leakage are amounts on those invoices, so the anchor grain is one row per invoice in SAP. Supporting models add event history, cross-system match, process timing, and period-level KPIs; the invoice fact remains the authority for funnel and leakage attribution.

### Design principles

#### Invoice-centric metrics
Net invoice value and cash-discount amounts are aggregated at invoice level. Dashboard-ready KPIs are built from that grain and from reporting period aggregates, not from single event rows alone.

#### SAP as system of record for KPIs
SAP is where invoices are ready to pay and where clearing and discount taken are recorded. When the same attribute exists in Coupa and SAP, metrics use SAP where available, on the assumption SAP reflects the latest payable state and downstream tools may not be fully reconciled.

#### Coupa for pre-SAP context only
Coupa supports workflow and timing diagnosis (changes, holds, rework) before and through posting. It does not define headline leakage KPIs; those come from the SAP invoice fact.

#### Bounded system scope
Only SAP and Coupa are modeled. Field names and flows are inspired by real products; logic and data are synthetic. Additional source systems are out of scope for this showcase.

### Minimum model grains

The design expects these distinct grains:

| Grain | Purpose |
|-------|---------|
| **Invoice (header)** | One row per payable invoice — funnel, entitlement, leakage, primary cause |
| **Change / event** | One row per status or field change — overlays and process history |
| **Supplier (master)** | One row per vendor id — names and attributes for reporting |
| **Reporting period** | Aggregated KPIs and breakdowns for a chosen clearing period |

Cross-system match, staging, phase spans, blocker overlays, timing allocation, and marts implement these grains; layer-by-layer placement is in Design layers.

### How this document is organized

- Policy & attribution — thresholds (processing days, payment reserve) that drive rules in SQL
- The funnel — how each invoice is classified through KPI scope into leakage and a single primary cause
- Timing attribution & allocation — execution causes and how timing leakage euros split across phases and buckets
- Build process — how the model was extended in slices
- Implementation — seeds, tests, dbt commands, sample report
- Model inventory — description of tables

## Design layers:

- Raw data seed files: source system data based on actual fields from tools like SAP and Coupa
- Seed setup files: mappings for raw interpretation and SLA values as initial settings
- SRC models: raw data curated. Column names changed, format adaptations and basic clean up of special characters and spaces.
- FCT models: tables of facts, here is the core of the model. Invoice and changes tables (SAP and Coupa), measurements of spans of process phases and blockers and the final allocation (eur) of overlay buckets.
- DIM models: master data tables, store information about vendors.
- INT models: intermediate ephemeral tables, act as an interface between 2 models, transforms the SLAs variables into fields and bring the blocker intervals together for the allocation
- MAP model: matching logic between the 2 systems SAP and Coupa
- MART models: last layer of transformation, it transforms the fact tables into dashboard ready tables and calculate KPIs

## Policy attributions

1. Minimum processing days: Establish the minimum feasible time for Accounts Payable team to process an invoice, even with urgency. Anything below that is unfeasible and it is the primary cause of leaking cash discount. Default value: 4
2. Standard processing days: Between this value and Minimum is considered compressed, the processing time is feasible but only under pressure, the responsibility is on the Accounts Payable to deliver on time but these cases need to be flagged and make adjustments to avoid them in the future. Above this value an available processing time is considered enough and it's on the Accounts Payable team to process with enough runway time for the payment run. This is also one component of the payment terms evaluation together with the minimum runway days. The sum of these establish the minimum payment terms days a procurement department should negotiate the contracts. Default value: 7
3. Minimum payment runway days: This is the minimum days a payment run needs for execution. The goal of the pre-SAP process is to deliver the invoice with enough payment runway days, and this is a hard line of ownership split between pre-SAP and payment run process owners. That creates a deadline for invoice processing of target deadline minus the minimum payment runway days. Default value: 3


## The Funnel

One of the main goals of this use case is to build a decision tree that assigns each invoice to a single category. Every split in the funnel has a meaningful filter and business logic split, from defining scope populations to main contributors of cash discount leakage.


### Population and KPI scope

0. Overall dataset population: all documents in an Accounts Payable domain.
1. Vendor Invoices: first filter is only invoices from a registered vendor (document type = 'KR' and vendor id not null).
2. Paid in period: Open invoices are out of scope for this analysis and the period is the selection of the user (for showcase: year 2024).
3. Entitled (KPI Universe): This is the denominator of the KPI based on rates (%). Entitled means it has cash discount potential (both invoice value and discount percentage) and there is a time window for payment (baseline date and discount terms). As soon as one of the required fields is missing, there is a not-entitled reason recorded and this invoice falls outside KPI scope.
4. Realized vs Not taken: After passing the initial scope filters (Document must be a vendor invoice paid in period and cash discount entitled), the entire KPI population is split. First Realized, which in this showcase means full cash discount captured; partial capture and certain rounding error margins are out of scope for simplicity. Realized rows received the full eligible discount, and the non taken have a zero amount captured.

### Excluded and leakage

5. Excluded vs Leakage: From the not taken there is a split into leakage and excluded (justified non-take). There is a custom flag (do-not-take-skonto at clearing) which can be activated in special cases and the lost cash discount analysis does not deep-dive into the reasons. It will be still a missed discount opportunity, but not classified as leakage.

### Leakage waterfall

6. Leakage split: there are several categories in leakage. In this level the rules are not in principle exclusive, they could apply at the same time, but it is very important to establish a hierarchy of conditions that splits the ownership in a way that makes more sense. This means that every invoice with leakage will be evaluated in order, and as soon as it falls into one rule, it automatically rejects the belonging to any other categories downstream.

#### Data quality

6.1 Data quality error: Data quality is prioritized on critical fields in the analysis, if any of these fields' values are missing then no assumptions are made, it's classified as data quality error. Some of these fields are part of the not entitled and if they are missing the invoice should be not entitled, they are retained here as a redundancy safety measure, in case the entitled conditions change in the future. The fiedls are receipt date, sap entry date, cash discount deadline date, discount days as mandatory invoice fields. Policy fields such minimum processing days, standard processing days and minimum payment runway fields are required to draw the ownership line. Finally a quality check if receipt date is not after SAP entry date, and SAP entry is not after clearing date.

#### Capture

6.2 Capture: If there is no data quality error, the next priority in the leakage hierarchy is capture. This category checks whether the clearing date happened on or before the discount deadline date for an invoice with leakage. In this case no further interpretation should be done, it should have been captured and needs manual review.

#### Structural — terms

6.3 Structural terms vs capability: From this category on the clearing date is later than the deadline date, this is highly expected for most cases and the deeper analysis tries to explain why this happened.
The next consideration in the logic hierarchy is the design of contracts, and the comparison is whether the discount terms (contract) is shorter than what is considered reasonable by the policy attributions, which is the sum of the standard processing days plus the minimum runway days. Policy defaults are standard processing of 7 days and minimum runway of 3 days, that means every invoice should have at least 10 days of discount terms regardless of any execution considerations. Other approaches don't make this rule that hard and forgives a bad contract in cases the execution performance is very rapid. This approach doesn't and the reason is clear, a good baseline design prevents future issues and establish a clear boundary of ownership between the procurement contracts and the subsequent causes.
Accepting discount days below this threshold is putting by default pressure on accounting teams.

#### Structural — intake

6.4 Structural insufficient time at intake: If the previous category conditions are not met (data quality checks pass, clearing date exceeds the deadline and contract payment terms are sufficient), the next condition to evaluate is whether the invoice is received in a timely manner so the available time between receipt date and deadline date exceeds a minimum. This is necessary because invoices are received after the baseline date clock is running. Very often baseline date is set at the creation of the invoice, simply because that's a date the vendor can control and prove, while the receipt date depends on the vendor sending the invoice, the interface and the client receiving it, and this can often create disputes on who was responsible to delay the baseline date (delay baseline date means delay of payment and delay of income cash flow for the vendor). Regardless of when the baseline is set, the client can actually fairly claim to not have enough time to process the invoice, making the capture of cash discount unfeasible. If the processing available days (days from receipt until deadline) is below the policy attribution minimum processing days value and the runway at handoff is also below the minimum then the reason falls in this category and the actions should be targeting the vendor interface and client inbound process to reduce as much as possible the time period between creating the invoice and receiving the invoice.

#### Timing — overview

6.5 Timing: Until this point the evaluation process was discarding first data quality and unexpected capture issues, as well as structural problems regarding fair contract terms and avoid late receipts. If none of the above apply, the Accounting Team received the invoice with the necessary data available and with sufficient (feasible) time to process the invoice.
Unlike the other categories, where the actions are clearly targeted into a primary cause, the timing needs to be narrowed down and some impact allocations need to be performed, as there are usually multiple causes, the actions that addressed them can be prioritized if there is an estimation of the contribution of these reasons into the overall processing delay.

#### Timing — pre-SAP compressed

6.5.1.Pre-SAP execution compressed: Before establishing a hard line between the structural and execution scope it's important to consider that in reality there is a buffer between what is feasible and what is reasonable when it comes to execution. There is no such consideration in contracts, as they need to be designed without gray zones. However, when an accounting team receives an invoice with feasible but compressed time, it's worth to point out that in case of failed capture, and even though the accounting team has the ownership, the fact of being under pressure needs to be taken into account for possible future adjustments. Two policy attributions (standard and minimum processing days) define a category outside this gray zone. If the available time for processing falls between these thresholds and there is no enough runway at handoff then the primary cause is the pre-SAP compressed execution.

#### Timing — pre-SAP standard

6.5.2 Pre-SAP execution standard: If the available time for processing is above the threshold of what is considered reasonable, the logic escapes the gray zone and enters the execution-only cause. In this case, the runway at handoff is also below minimum so the window opportunity was wasted in the processing even with enough time.

#### Timing — payment execution

6.5.3 Payment execution: This is the last category of timing execution, and it has a different behavior. Unlike processing (pre-SAP period) that has multiple tasks to be performed (often many manual) and it is meant to be done as soon as possible, the payment regime is meant to wait for the deadline. While pre-SAP is desirable to be closed as fast as possible, the target of payment is to launch the payment run on the deadline (in this case cash discount but it can be a net due date otherwise), not later and not too early, so it is expected that an invoice waits inactive until the time to pay comes. As convention for this use case, payment is modeled as a process nearly fully automatic and triggered anytime (even on weekends) with no friction except setting or removing a payment block. There is only one policy attribution for minimum payment runway days (3 days by default) which is considered enough for executing a payment. This condition overwrites some of the previous rules as the opposite condition (if runway at handoff days are less than the minimum) is set for "Structural insufficient time at intake", "Pre sap execution compressed" and "Pre sap execution standard". So if the condition of this rule is true, the cases that were supposed to fall into these categories would fall into this one. The reason to do this is the hierarchy: Data quality goes first, then cases with a clearing date that should have captured the cash discount, then the contract design. The conditions of these categories are dominant over the runway minimum days, good performance cannot bypass data-quality, capture, or contract-design rules in processing, this would hide the data quality and structural design errors. For the others, there is the possibility of recovery, even with insufficient time at intake, some processes are so fast that pre-SAP period recovers the days and possibly delivers enough runway at handoff to avoid a payment-execution primary cause.

## Timing allocation

Timing allocation runs after the leakage waterfall. It applies only to invoices that are leakage with a timing primary cause (pre-SAP compressed, pre-SAP standard, or payment execution). It does not change the primary cause; it splits "lost_discount_amount" across phases and timing buckets so teams can see where days and euros concentrate.

Allocation is a management proration for prioritization. It is not a second root-cause label and it does not mean euros are recoverable.

### Allocation regime

Each timing leakage invoice is assigned one allocation regime, driven by runway at handoff (SAP entry → discount deadline) compared to minimum payment runway days from attribution policy:

| Regime | Condition | What gets allocated |
|--------|---------------------------|---------------------|
| Payment | Runway at handoff ≥ minimum payment runway | Euros only in the payment window, across payment timing buckets |
| Pre-SAP ("pre_posting") | Runway at handoff < minimum payment runway | Euros across subprocess phases (and buckets within verification/approval) |

### Payment regime

Primary cause is typically payment execution (handoff met the payment reserve, but clearing missed the discount deadline).

Exposure window: from discount deadline to clearing date, only when clearing is after the deadline.

Within that window:

- Days covered by a payment block overlay → timing bucket "payment block" (SAP block interval).
- Remaining days in the window → "payment run wait" (derived post-deadline wait, not hand-typed as an arbitrary overlay).

Allocation EUR: the invoice’s timing lost discount amount is distributed across those buckets in proportion to each bucket’s "gross exposure days" in that window. There is no pre-SAP phase split in this regime, only these payment buckets.

### Pre-SAP regime

Primary causes: pre-SAP execution compressed or pre-SAP execution standard (insufficient runway at handoff after receipt/processing).

Exposure window (conceptually): measured subprocess time in the pre-SAP story: intake and interface spans (targeted toward zero elapsed time), plus verification and approval, clipped to the analysis window (through the discount deadline before SAP entry, per model rules).

Phase-level split: lost discount is first spread across phases using phase span weights (calendar days in the clipped window). Intake and interface map to dedicated buckets ("intake delay", "interface delay") with the phase total when those phases apply.

Within verification and approval:

- Blocker "overlays" (hold, rework, dispute, etc.) contribute gross exposure days per bucket code.
- Euros are prorated from the phase total using those days.
- If labeled blocker days do not fill the phase, the gap can go to "no recorded blocker" (investigate unlabeled time—not "normal operations" as fact).
- If multiple blockers overlap the same calendar days, gross days can exceed the phase clock, blocker euros are scaled so phase and invoice totals still reconcile.

### Reconciliation and outputs

For every invoice in scope, sum("priority allocated eur") = "lost discount amount". Portfolio timing allocation ties to the timing slice of leakage by cause in the headline marts.

Built in "fct_inv_timing_allocation", summarised in "mart_timing_phase_impact" (phase) and "mart_timing_bucket_impact" (bucket, ACT/WATCH prioritisation).

## Build process overview

The model was built in layers. Each layer added capability without rewriting earlier work. The order below is dependency order: what had to exist before the next step could run.

### SAP invoice foundation

- Landed SAP-style invoice and vendor extracts and payment-term reference data.
- Defined one row per payable vendor invoice as the main grain for all KPIs.
- Built structural rules for cash-discount entitlement (terms, baseline, amounts).
- Added paid-in-period scope so open items sit outside the KPI universe.
- Defined taken vs not taken from posted discount at clearing.
- Introduced excluded vs leakage for not-taken eligible invoices.
- Published headline period KPIs (counts, opportunity, leakage, rate).

### Coupa workflow and cross-system match

- Added Coupa invoice and supplier data for process context, not as a second KPI system.
- Linked Coupa to SAP at posting so each matched pair shares one business key.
- Kept SAP-only invoices in scope where no Coupa row exists.
- Stored Coupa change history for later phase and blocker logic.

### Leakage causes and cause reporting

- Replaced a simple late-vs-early split with an ordered leakage waterfall: one primary cause per leakage invoice.
- Covered data quality, capture, structural contract and intake issues, and timing execution.
- Expanded the curriculum so every cause type has at least one labeled example invoice.
- Added a reporting mart that breaks leakage euros and counts by primary cause, tied to the headline KPI.

### Timing phases (ownership and subprocess)

- Slice 1: Measured calendar time in two ownership phases (before SAP entry, and payment through clearing) without changing leakage numbers.
- Slice 2: Split pre-SAP ownership into intake, verification, approval, and interface using Coupa events, with checks that subprocess days reconcile to ownership pre-SAP time.

### Blocker overlays

- Slice 3: Added dated blocker intervals (holds, rework, supplier wait, payment blocks, post-deadline wait) as explanations inside phases.
- Joined blockers to phase spans to count exposure days; spans remain the clock, overlays explain labeled time.

### Timing allocation and action-oriented marts

- Slice 4: For timing-type leakage only, split each invoice lost discount euros across phases and named timing buckets using day-based proration.
- Split logic into pre-SAP vs payment regimes depending on whether enough payment runway existed at SAP handoff.
- Built portfolio marts that rank phases and buckets for where to act first versus watch later.

### Richer curriculum and overlay sources

- Added more synthetic invoices to exercise pre-SAP timing, payment blocks, and payment wait after the discount deadline.
- Rebased portfolio totals and tests on the expanded curriculum.
- Derived Coupa blockers from change history instead of hand-maintained overlay rows where possible.
- Derived SAP payment blocks from posting change events; derived post-deadline payment wait from dates and non-overlap rules.

### Attribution policy refresh

- Centralized processing and payment-reserve thresholds in versioned policy seeds consumed by the invoice fact.
- Refined the leakage waterfall: contract design, intake feasibility, compressed pre-SAP execution, standard pre-SAP execution, and payment execution.
- Reconciled cause marts and timing allocation to the updated rules and curriculum.

### Exclusion rule refinement

- Narrowed excluded to an explicit do-not-take-discount flag at clearing, so other operational flags at clearing do not count as justified exclusion in the headline funnel.

### Stakeholder report

- Added a sample PDF generator for headline KPIs, cause mix, and timing actions in readable form; curriculum numbers are embedded in the script until mart-driven export is added.

### How tests evolved with the build

- Generic column and relationship tests guard grain and design on any dataset.
- Singular SQL tests guard the labeled curriculum (specific invoices, funnel counts, euro totals, reconciliation).
- New slices extended tests without removing original funnel checks unless the curriculum intentionally changed.

## Model inventory

### Tier A — core models

#### fct_inv_sap_core / fct_inv_sap_cd

Description: Shared SAP invoice spine (`fct_inv_sap_core`: terms, dates, map-based Coupa, neutral elapsed days) plus cash-discount extension (`fct_inv_sap_cd`: KPI funnel, leakage amount, primary cause). Legacy `fct_inv_sap` is a deprecated shim with no downstream refs.

Grain: one row per sap_inv_key (posted vendor invoice, KR, vendor present).

Sources (core): src_inv_sap; seed_payment_term_sap; map_inv_sap_coupa; fct_inv_coupa. Sources (CD): fct_inv_sap_core; int_attribution_policy_active.

Transformation: core payment-term join and discount deadline; CD adds structural entitlement, paid-in-period, taken/excluded/leakage, policy-driven diagnostics, ordered leakage waterfall → primary_cause, primary_cause_group, lost_discount_amount.

Consumed by: marts and timing models ref `fct_inv_sap_cd`; span/overlay core paths ref `fct_inv_sap_core`; map_inv_sap_coupa (lineage/tests on core).

Notable outputs: is_kpi_entitled, is_taken, is_excluded, is_leakage, primary_cause, lost_discount_amount, runway_at_handoff, processing_available_days (on `_cd`).

---

#### fct_inv_timing_span

Description: Calendar phase spans for process timing (how long each phase lasted).

Grain: sap_inv_key × phase_level × phase_code × span_seq.

Sources: fct_inv_sap_core; fct_inv_coupa_changes (subprocess boundaries and events).

Transformation: ownership spans (pre_sap, payment); subprocess spans (intake, verification, approval, interface, payment); measured vs not measurable status; span start/end and span_days.

Consumed by: fct_inv_timing_overlay_span, fct_inv_timing_allocation (weights), mart_timing_phase_profile.

Notable outputs: phase_level, phase_code, span_days, span_status, span_start_date, span_end_date.

---

#### fct_inv_timing_overlay_core / fct_inv_timing_overlay_cd

Description: Labeled blocker intervals explaining time inside phases (holds, rework, blocks, post-deadline wait). Core = observed Coupa + SAP blocks; CD adds `payment_run_wait`. Legacy `fct_inv_timing_overlay` is a deprecated shim with no downstream refs.

Grain: sap_inv_key × overlay_reason_code × interval_seq.

Sources: int_inv_coupa_overlay_intervals; int_inv_sap_payment_block_intervals; CD layer adds payment_run_wait from fct_inv_sap_cd; seed_timing_overlay_reason_map.

Transformation: union Coupa-derived and SAP-derived intervals; derive payment_run_wait where eligible; map reason codes and metadata.

Consumed by: fct_inv_timing_overlay_span, fct_inv_timing_allocation (via span; tests target `_cd`).

Notable outputs: interval_start_date, interval_end_date, interval_days, reason_group, source_system.

---

#### fct_inv_timing_allocation

Description: Splits timing-type leakage euros across phases and timing buckets for prioritisation.

Grain: sap_inv_key × phase_level × phase_code × bucket_code (only rows with priority_allocated_eur > 0).

Sources: fct_inv_sap_cd (timing primary causes only); fct_inv_timing_span; fct_inv_timing_overlay_span.

Transformation: payment vs pre_posting regime from runway at handoff; phase euro split by clipped span weights; intake/interface delay buckets; verification/approval blocker buckets with gap and overlap scaling; payment block and payment_run_wait; cent residuals so euros reconcile to lost_discount_amount.

Consumed by: mart_timing_phase_impact, mart_timing_bucket_impact, sample PDF / analyses.

Notable outputs: priority_allocated_eur, gross_exposure_days, bucket_code.

---

#### mart_cash_discount_kpi

Description: Headline cash-discount KPIs for the reporting period.

Grain: one row per reporting_period_start × reporting_period_end (vars).

Sources: fct_inv_sap_cd.

Transformation: counts and sums for entitled, taken, excluded, leakage; opportunity, realized, excluded, and leakage EUR; leakage rate.

Consumed by: dashboards, sample report, portfolio tests.

Notable outputs: kpi_entitled_count, leakage_count, leakage_eur, leakage_rate, discount_opportunity_eur.

---

#### mart_cash_discount_kpi_by_cause

Description: Leakage broken down by primary cause (reconciles to headline mart).

Grain: one row per reporting period × primary_cause.

Sources: fct_inv_sap_cd.

Transformation: filter leakage rows; group by primary_cause (and group); sum counts and EUR.

Consumed by: dashboards, sample report, cause reconciliation tests.

Notable outputs: primary_cause, leakage_count, leakage_eur.

---

#### mart_timing_bucket_impact

Description: Portfolio view of timing leakage by phase and timing bucket with action ranking.

Grain: one row per reporting period × phase_level × phase_code × bucket_code.

Sources: fct_inv_timing_allocation; fct_inv_sap_cd (vendor, period context as needed).

Transformation: aggregate allocation euros and exposure days; cumulative share; ACT vs WATCH; owner_role for narrative.

Consumed by: timing action report, sample PDF.

Notable outputs: priority_allocated_eur, action_status, owner_role, gross_exposure_days.

---

### Tier B — other models (summary)

| Model | Grain | Role |
|-------|-------|------|
| src_* | same as raw grain | Rename, cast, trim; no business rules |
| dim_vendor_sap / dim_vendor_coupa | active vendor/supplier | Master data for reporting names |
| map_inv_sap_coupa | sap_inv_key ↔ coupa_id | Cross-system match at posting |
| fct_inv_coupa | Coupa invoice (invoice filter in fact) | Process context; feeds receipt_date on SAP fact |
| fct_inv_coupa_changes | coupa_change_id | Event stream for spans and Coupa overlays |
| fct_inv_sap_changes | sap_change_id | Event stream for SAP payment blocks |
| fct_inv_timing_overlay_span | overlap rows | Exposure bridge (not euro allocation) |
| mart_timing_phase_impact | period × phase | Phase-level timing EUR for prioritisation |
| mart_timing_phase_profile | period × phase | Phase duration portfolio (instrumentation) |
| int_* | ephemeral | Policy row, Coupa/SAP blocker interval prep |

## Sample stakeholder report

Synthetic **2024** curriculum period — client-style summary of headline KPIs, leakage by cause, and timing actions (numbers align with mart tests).

- **PDF:** [cash_discount_report_2024_v6.pdf](reports/cash_discount_report_2024_v6.pdf)
