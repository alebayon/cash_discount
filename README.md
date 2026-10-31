# cash_discount

Cash discount product on the ap_core package.

## Disclaimer

This project is for educational and demonstration purposes. The datasets are made to have realistic dates, amounts, and process variants. All data is synthetic, no real invoices, vendors, or company systems are used. Policies and process design are illustrative, not copied from any employer or client.

## Context

Cash discount is possibly one of the most unsatisfying use cases in Process Mining. The business impact is clear and measurable: reduce lost cash discount today and avoid future leakage, and the lost cash discount metric gives you the exact amount you can achieve for your company's cash flow. The reward looks obvious, it's just money in front of your eyes waiting to be grabbed. There is however a problem: between the opportunity and capturing it there is an invisible maze of root cause determination.

And there is a bigger problem: most cases do not have a single root cause. They sit in a gray zone of competing explanations. How do we determine if an invoice has unfair terms, was received too late, had an illogical baseline date, was posted too late, or sat in a certain phase for too long?

This product addresses that in two steps: first a hierarchical split of ownership (structural rules, treasury arbitration, then an ordered leakage waterfall with one primary cause), and second a deeper weight allocation for timing leakage, prorating euros across phases and blocker buckets for prioritization without changing the primary cause.

## Project Goal

Within Accounts Payable, this product simulates cash discount performance. It measures cash discount leakage, takes policies and package-backed invoice data as inputs, passes in-scope invoices through a KPI funnel plus a leakage waterfall, and resolves with a primary cause on all leakage rows and allocation on timing causes.

It delivers a prioritized list of recommended actions that highlights where time and euros concentrate for action and helps address systemic issues for future cash discount leakage prevention.

## Dependency on ap_core

cash_discount is a separate dbt project from ap_core. Shared AP models (spine, match, dimensions, demo seeds, neutral timing, CD/WCO arbitration policy) ship in the ap_core package on GitHub. This repository contains cash-discount product models, seed_attribution_policy, product tests, marts, and reports.

Install the package from packages.yml at the project root, then run dbt deps. Reference shared models with ref('ap_core', 'model_name'). Build with dbt build --select +tag:cash_discount (package ancestors first).

Package repository: https://github.com/alebayon/ap_core

## Design rationale

See docs/architecture-decisions.md for cash-discount architecture and policies (public summary).

Shared AP spine, match, arbitration, and neutral timing: https://github.com/alebayon/ap_core/blob/main/docs/core_decisions.md and the ap_core README on the same repository.

## Term definitions

Terms below support the cash discount product (funnel, leakage, allocation). Shared invoice spine, match, and neutral timing are built in the ap_core package. This list still applies to how those tables are used in KPIs and marts.

Allocation Eur: Impact expression of how much a phase or a blocker is contributing to the overall cash discount leakage in form of prorated amount.

Attribution policy: Thresholds and rules in seeds that drive entitlement and leakage attribution in SQL. In this repo that is seed_attribution_policy, consumed via int_attribution_policy_active on fct_inv_sap_cd.

Blocker: A labeled reason (e.g. hold, rework, payment block) with a date range (overlay) that explains delay inside a phase.

Data/Domain model: The whole AP architecture (with multiple tables), spanning the ap_core package and this product repo.

Dataset: Synthetic demo extracts with source-style column names (raw_* and related policy/map seeds in ap_core). This repository adds seed_attribution_policy only.

Dbt model: A dbt materialized object (table, view, or ephemeral) with its own .sql file. Product models live under models/ in this repo. Shared models are installed under dbt_packages/ap_core after dbt deps and are referenced with ref('ap_core', 'model_name').

Excluded: Invoices with cash discount potential not taken with a justified reason (not leakage category).

Exposure: Total time an overlay is contributing to leakage (double count if overlap). The exposure prorated is the source of allocation eur calculation.

Grain: Level of aggregation of a model/table, what one row contains as distinct.

Interval: Time range.

Leakage (Cash Discount): Lost cash discount without a justified exclusion reason.

Overlay: Date range for a blocker reason on an invoice.

Payment reserve (policy): Minimum calendar days payment must have after SAP entry before the discount deadline.

Phase: Time division in a lifecycle of an invoice. There are two levels: ownership (pre_sap, payment) and subprocess (intake, verification, approval, interface).

Posting/Entry in SAP: System generated date (CPUDT) of invoice entry in SAP.

Processing: Group of actions or time period happening to an invoice from receipt to SAP entry (pre-SAP time).

Primary cause: One headline leakage reason per invoice from the ordered leakage rules. Timing reasons use the same field. Only those rows also split euros across timing buckets for prioritization.

Processing available days: Calendar days from receipt to discount deadline minus payment reserve.

Runway (at handoff): Actual calendar days from SAP entry to discount deadline.

Span: Calendar days elapsed in a phase.

## Architecture design overview

This analytics model is built around posted vendor invoices in accounts payable. Cash-discount opportunity and leakage are amounts on those invoices, so the anchor grain is one row per invoice in SAP. The invoice spine and cross-system match live in the ap_core package. fct_inv_sap_cd in this repo is the authority for the KPI funnel, leakage, and primary cause. Supporting product models add timing allocation and period-level marts.

### Design principles

#### Invoice-centric metrics

Net invoice value and cash-discount amounts are aggregated at invoice level. Dashboard-ready KPIs are built from that grain and from reporting period aggregates, not from single event rows alone.

#### SAP as system of record for KPIs

SAP is where invoices are ready to pay and where clearing and discount taken are recorded. When the same attribute exists in Coupa and SAP, metrics use SAP where available, on the assumption SAP reflects the latest payable state and downstream tools may not be fully reconciled.

#### Coupa for pre-SAP context only

Coupa supports workflow and timing diagnosis (changes, holds, rework) before and through posting. It does not define headline leakage KPIs. Those come from the SAP invoice fact (fct_inv_sap_cd).

#### Bounded system scope

Only SAP and Coupa are modeled. Field names and flows are inspired by real products. Logic and data are synthetic. Additional source systems are out of scope for this showcase.

### Minimum model grains

The design expects these distinct grains:

| Grain | Purpose |
| ----- | ------- |
| Invoice (header) | One row per payable invoice — funnel, entitlement, leakage, primary cause |
| Change / event | One row per status or field change — overlays and process history |
| Supplier (master) | One row per vendor id — names and attributes for reporting |
| Reporting period | Aggregated KPIs and breakdowns for a chosen clearing period |

Cross-system match, staging, phase spans, and observed blocker overlays are implemented in ap_core. Timing allocation and marts implement product grains. Layer placement is in Design layers.

### How this document is organized

- Policy and attribution — Thresholds such as processing days, payment reserve, etc. in this repo
- The funnel — KPI scope, leakage, and a single primary cause per leakage invoice
- Timing attribution and allocation — execution causes and how timing leakage euros split across phases and buckets
- Build process — how the portfolio was extended in slices, including the ap_core package split
- Implementation — dbt deps, build commands, tests
- Model inventory — product models in this repo, shared spine and match documented in ap_core
- Shared AP spine, match, dims, and neutral timing — ap_core package (https://github.com/alebayon/ap_core)
- Sample stakeholder report — PDF under reports/

## Design layers

Models are split between the installed ap_core package (shared AP) and this repository (cash discount product). Run dbt deps before building. Shared models are referenced with ref('ap_core', 'model_name').

### (A) Installed package — ap_core

https://github.com/alebayon/ap_core

- Raw seeds (raw_*): Synthetic source-style extracts (SAP and Coupa invoices, vendors, change history).
- Policy / map seeds: Payment terms, CD/WCO arbitration policy, Coupa status map, SAP payment-block map, timing overlay reason map. Product attribution thresholds live in this repo, not in the package.
- SRC (src_*): Views — rename, cast, trim. No KPI business rules.
- DIM (dim_vendor_*): Vendor/supplier master. Inactive suppliers retained (is_active).
- MAP (map_inv_sap_coupa): Confirmed SAP invoice ↔ Coupa match at posting.
- INT (int_*): Ephemeral — Coupa overlay intervals and SAP payment-block intervals (inputs to observed overlays).
- FCT (core facts): Tables — SAP invoice spine (fct_inv_sap_core), CD/WCO arbitration (fct_inv_cd_wco_arbitration), Coupa invoice and change streams, SAP invoice changes, neutral phase spans (fct_inv_timing_span), observed blocker overlays (fct_inv_timing_overlay_core). No reporting-period gates, leakage waterfall, timing euro allocation, or marts.

### (B) This repo — cash_discount

- Seed: seed_attribution_policy (processing and payment-reserve thresholds).
- INT: int_attribution_policy_active (active policy row for the invoice fact).
- FCT (product facts): fct_inv_sap_cd (KPI funnel, structural entitlement, arbitration consumption, leakage, primary_cause), fct_inv_timing_overlay_cd (package observed overlays plus CD-only rows such as payment_run_wait), fct_inv_timing_allocation (timing leakage euros across phases/buckets), fct_inv_timing_overlay_span (exposure bridge for allocation). Product facts without a _cd suffix still live only here.
- MART (mart_*): Period headline KPIs, leakage by cause, timing phase/bucket action views.

Layer detail for shared models: ap_core README and docs/core_decisions.md on GitHub (https://github.com/alebayon/ap_core).

## Policy attributions

1. Minimum processing days: Establish the minimum feasible time for Accounts Payable team to process an invoice, even with urgency. Anything below that is unfeasible and it is the primary cause of leaking cash discount. Default value: 4
2. Standard processing days: Between this value and Minimum is considered compressed, the processing time is feasible but only under pressure, the responsibility is on the Accounts Payable to deliver on time but these cases need to be flagged and make adjustments to avoid them in the future. Above this value an available processing time is considered enough and it's on the Accounts Payable team to process with enough runway time for the payment run. This is also one component of the payment terms evaluation together with the minimum runway days. The sum of these establish the minimum payment terms days a procurement department should negotiate the contracts. Default value: 7
3. Minimum payment runway days: This is the minimum days a payment run needs for execution. The goal of the pre-SAP process is to deliver the invoice with enough payment runway days, and this is a hard line of ownership split between pre-SAP and payment run process owners. That creates a deadline for invoice processing of target deadline minus the minimum payment runway days. Default value: 3

## The Funnel

One of the main goals of this use case is to build a decision tree that assigns each invoice to a single category. Every split in the funnel has a meaningful filter and business logic split, from defining scope populations to main contributors of cash discount leakage.

### Population and KPI scope

1. Overall dataset population: all documents in an Accounts Payable domain.
2. Vendor Invoices: first filter is only invoices from a registered vendor (document type = 'KR' and vendor id not null). Spine scope from ap_core (fct_inv_sap_core).
3. Structural entitlement: Cash discount potential (baseline, terms, deadline, positive invoice base). Missing fields set not_entitled_reason (outside structural universe). Evaluated on fct_inv_sap_cd.
4. CD/WCO arbitration: Treasury policy in ap_core (seed_cd_wco_arbitration_policy, fct_inv_cd_wco_arbitration) — minimum potential discount EUR and max cash-acceleration days. When structural OK, is_cd_eligible false sets not_cd_eligible_reason (e.g. below minimum EUR or excessive acceleration). That is not merged into structural reasons.
5. Paid in period: Open invoices and clears outside the reporting window are out of scope (showcase: calendar year 2024).
6. KPI entitled: Vendor invoice AND structural OK AND CD eligible AND paid in period (is_kpi_entitled).
7. Realized vs Not taken: After entering the KPI universe, split taken (full discount captured) vs not taken (zero captured at clearing, partial capture out of scope).

### Excluded and leakage

1. Excluded vs Leakage: From the not taken there is a split into leakage and excluded (justified non-take). There is a custom flag (do-not-take-skonto at clearing) which can be activated in special cases and the lost cash discount analysis does not deep-dive into the reasons. It will be still a missed discount opportunity, but not classified as leakage.

### Leakage waterfall

1. Leakage split: there are several categories in leakage. In this level the rules are not in principle exclusive, they could apply at the same time, but it is very important to establish a hierarchy of conditions that splits the ownership in a way that makes more sense. This means that every invoice with leakage will be evaluated in order, and as soon as it falls into one rule, it automatically rejects the belonging to any other categories downstream.

#### Data quality

6.1 Data quality error: Data quality is prioritized on critical fields in the analysis, if any of these fields' values are missing then no assumptions are made, it's classified as data quality error. Some of these fields are part of the not entitled and if they are missing the invoice should be not entitled, they are retained here as a redundancy safety measure, in case the entitled conditions change in the future. The fields are receipt date, sap entry date, cash discount deadline date, discount days as mandatory invoice fields. Policy fields such minimum processing days, standard processing days and minimum payment runway fields are required to draw the ownership line. Finally a quality check if receipt date is not after SAP entry date, and SAP entry is not after clearing date.

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

6.5.1 Pre-SAP execution compressed: Before establishing a hard line between the structural and execution scope it's important to consider that in reality there is a buffer between what is feasible and what is reasonable when it comes to execution. There is no such consideration in contracts, as they need to be designed without gray zones. However, when an accounting team receives an invoice with feasible but compressed time, it's worth to point out that in case of failed capture, and even though the accounting team has the ownership, the fact of being under pressure needs to be taken into account for possible future adjustments. Two policy attributions (standard and minimum processing days) define a category outside this gray zone. If the available time for processing falls between these thresholds and there is no enough runway at handoff then the primary cause is the pre-SAP compressed execution.

#### Timing — pre-SAP standard

6.5.2 Pre-SAP execution standard: If the available time for processing is above the threshold of what is considered reasonable, the logic escapes the gray zone and enters the execution-only cause. In this case, the runway at handoff is also below minimum so the window opportunity was wasted in the processing even with enough time.

#### Timing — payment execution

6.5.3 Payment execution: This is the last category of timing execution, and it has a different behavior. Unlike processing (pre-SAP period) that has multiple tasks to be performed (often many manual) and it is meant to be done as soon as possible, the payment regime is meant to wait for the deadline. While pre-SAP is desirable to be closed as fast as possible, the target of payment is to launch the payment run on the deadline (in this case cash discount but it can be a net due date otherwise), not later and not too early, so it is expected that an invoice waits inactive until the time to pay comes. As convention for this use case, payment is modeled as a process nearly fully automatic and triggered anytime (even on weekends) with no friction except setting or removing a payment block. There is only one policy attribution for minimum payment runway days (3 days by default) which is considered enough for executing a payment. This condition overwrites some of the previous rules as the opposite condition (if runway at handoff days are less than the minimum) is set for Structural insufficient time at intake, Pre-SAP execution compressed and Pre-SAP execution standard. So if the condition of this rule is true, the cases that were supposed to fall into these categories would fall into this one. The reason to do this is the hierarchy: Data quality goes first, then cases with a clearing date that should have captured the cash discount, then the contract design. The conditions of these categories are dominant over the runway minimum days. Good performance cannot bypass data-quality, capture, or contract-design rules in processing, this would hide the data quality and structural design errors. For the others, there is the possibility of recovery, even with insufficient time at intake, some processes are so fast that pre-SAP period recovers the days and possibly delivers enough runway at handoff to avoid a payment-execution primary cause.

## Timing allocation

Timing allocation runs after the leakage waterfall. It applies only to invoices that are leakage with a timing primary cause (pre-SAP compressed, pre-SAP standard, or payment execution). It does not change the primary cause. It splits lost_discount_amount across phases and timing buckets so teams can see where days and euros concentrate.

Allocation is a management proration for prioritization. It is not a second root-cause label and it does not mean euros are recoverable.

### Allocation regime

Each timing leakage invoice is assigned one allocation regime, driven by runway at handoff (SAP entry → discount deadline) compared to minimum payment runway days from attribution policy:

| Regime | Condition | What gets allocated |
| ------ | --------- | ------------------- |
| Payment | Runway at handoff ≥ minimum payment runway | Euros only in the payment window, across payment timing buckets |
| Pre-SAP (pre_posting) | Runway at handoff < minimum payment runway | Euros across subprocess phases (and buckets within verification/approval) |

### Payment regime

Primary cause is typically payment execution (handoff met the payment reserve, but clearing missed the discount deadline).

Exposure window: from discount deadline to clearing date, only when clearing is after the deadline.

Within that window:

- Days covered by a payment block overlay → timing bucket payment block (SAP block interval).
- Remaining days in the window → payment run wait (derived post-deadline wait, not hand-typed as an arbitrary overlay).

Allocation EUR: the invoice's timing lost discount amount is distributed across those buckets in proportion to each bucket's gross exposure days in that window. There is no pre-SAP phase split in this regime, only these payment buckets.

### Pre-SAP regime

Primary causes: pre-SAP execution compressed or pre-SAP execution standard (insufficient runway at handoff after receipt/processing).

Exposure window (conceptually): measured subprocess time in the pre-SAP story: intake and interface spans (targeted toward zero elapsed time), plus verification and approval, clipped to the analysis window (through the discount deadline before SAP entry, per model rules).

Phase-level split: lost discount is first spread across phases using phase span weights (calendar days in the clipped window). Intake and interface map to dedicated buckets (intake delay, interface delay) with the phase total when those phases apply.

Within verification and approval:

- Blocker overlays (hold, rework, dispute, etc.) contribute gross exposure days per bucket code.
- Euros are prorated from the phase total using those days.
- If labeled blocker days do not fill the phase, the gap can go to no recorded blocker (investigate unlabeled time—not normal operations as fact).
- If multiple blockers overlap the same calendar days, gross days can exceed the phase clock. Blocker euros are scaled so phase and invoice totals still reconcile.

### Reconciliation and outputs

For every invoice in scope, sum(priority allocated eur) = lost discount amount. Portfolio timing allocation ties to the timing slice of leakage by cause in the headline marts.

Built in fct_inv_timing_allocation, summarised in mart_timing_phase_impact (phase) and mart_timing_bucket_impact (bucket, ACT/WATCH prioritisation).

## Build process overview

The portfolio was built in layers: each step added capability without rewriting earlier work. The order below is dependency order (what had to exist before the next step). Most early steps were implemented in a single repository first. Shared AP was extracted to the ap_core package on 2026-10-26. Maintained today: spine, match, and neutral timing in ap_core. Cash discount KPIs, leakage, allocation, and marts live in this repo.

### SAP invoice foundation

In ap_core (then extracted):

- Landed SAP-style invoice and vendor extracts and payment-term reference data.
- Defined one row per payable vendor invoice as the grain for all downstream products (fct_inv_sap_core).
- Joined payment terms and computed discount and net dates, amounts, clearing facts, and neutral elapsed days on the spine.

In this product repo:

- Added structural cash-discount entitlement rules and diagnostics on fct_inv_sap_cd (built on the package spine).
- Added paid-in-period scope, taken vs not taken, excluded vs leakage, and headline period KPIs (counts, opportunity, leakage, rate).

### Coupa workflow and cross-system match

In ap_core:

- Added Coupa invoice and supplier data for process context, not as a second KPI system.
- Linked Coupa to SAP at posting so each matched pair shares one business key (map_inv_sap_coupa).
- Kept SAP-only invoices in scope where no Coupa row exists.
- Stored Coupa change history for later phase and blocker logic.

In this product repo:

- Consumes package Coupa, map, and spine via ref('ap_core', …). Headline leakage KPIs remain on fct_inv_sap_cd.

### Leakage causes and cause reporting

- Replaced a simple late-vs-early split with an ordered leakage waterfall: one primary cause per leakage invoice.
- Covered data quality, capture, structural contract and intake issues, and timing execution.
- Expanded the curriculum so every cause type has at least one labeled example invoice.
- Added a reporting mart that breaks leakage euros and counts by primary cause, tied to the headline KPI.

### Timing phases (ownership and subprocess)

In ap_core:

- Slice 1: Measured calendar time in two ownership phases (before SAP entry, and payment through clearing) without changing leakage numbers.
- Slice 2: Split pre-SAP ownership into intake, verification, approval, and interface using Coupa events, with checks that subprocess days reconcile to ownership pre-SAP time.

In this product repo:

- Uses package spans for allocation weights and phase profile marts. Does not change leakage primary cause by itself.

### Blocker overlays

In ap_core:

- Slice 3: Added dated blocker intervals from Coupa (holds, rework, dispute) and SAP (payment blocks) as observed overlays.
- Joined blockers to phase spans to count exposure days. Spans remain the clock, overlays explain labeled time.

In this product repo:

- Added payment_run_wait and the CD overlay union on fct_inv_timing_overlay_cd. Timing allocation uses overlay span exposure where eligible.

### Timing allocation and action-oriented marts

- Slice 4: For timing-type leakage only, split each invoice lost discount euros across phases and named timing buckets using day-based proration.
- Split logic into pre-SAP vs payment regimes depending on whether enough payment runway existed at SAP handoff.
- Built portfolio marts that rank phases and buckets for where to act first versus watch later.

### Richer curriculum and overlay sources

- Added more synthetic invoices to exercise pre-SAP timing, payment blocks, and payment wait after the discount deadline.
- Rebased portfolio totals and tests on the expanded curriculum.
- Derived Coupa blockers from change history instead of hand-maintained overlay rows where possible (ap_core).
- Derived SAP payment blocks from posting change events (ap_core). Derived post-deadline payment wait from dates and non-overlap rules (CD overlay layer).

### Attribution policy refresh

- Centralized processing and payment-reserve thresholds in policy seeds consumed by the invoice fact (seed_attribution_policy and int_attribution_policy_active in this repo).
- Refined the leakage waterfall: contract design, intake feasibility, compressed pre-SAP execution, standard pre-SAP execution, and payment execution.
- Reconciled cause marts and timing allocation to the updated rules and curriculum.

### Exclusion rule refinement

- Narrowed excluded to an explicit do-not-take-discount flag at clearing, so other operational flags at clearing do not count as justified exclusion in the headline funnel.

### Stakeholder report

- Added a sample PDF generator for headline KPIs, cause mix, and timing actions in readable form. Curriculum numbers are embedded in the script until mart-driven export is added.

### Package split (2026-10-26)

- Published shared models as ap_core v0.1.0 on GitHub. Pinned from this repo via packages.yml and dbt deps.
- Removed duplicate core SQL and seeds from cash_discount. Product models reference the package with ref('ap_core', 'model_name').
- Verified end-to-end with dbt build --select +tag:cash_discount.

### How tests evolved with the build

- Generic column and relationship tests guard grain and design on product models in YAML. Core model tests live in the ap_core package.
- Singular SQL tests in this repo guard the labeled curriculum (specific invoices, funnel counts, euro totals, reconciliation).
- New slices extended tests without removing original funnel checks unless the curriculum intentionally changed.

## Implementation

Profile: cash_discount in ~/.dbt/profiles.yml (Snowflake target as configured locally).

Install the shared package (after clone or when packages.yml changes):

    dbt deps

Build product models and upstream ap_core:

    dbt build --select +tag:cash_discount

Package pin: packages.yml at the project root (revision: ap_core tag, e.g. v0.1.0). Product SQL references shared models with ref('ap_core', 'model_name').

Tests: schema tests on product YAML, singular tests under tests/ for CD curriculum. Core model tests ship in the ap_core package.

Typical order: dbt deps, then dbt build --select +tag:cash_discount. Credentials stay outside the repo (profiles.yml not committed).

## Model inventory

Product tables live in this repository. Shared models (spine, map, dims, src, core timing, arbitration, demo seeds) are documented in the ap_core package: https://github.com/alebayon/ap_core — installed under dbt_packages/ap_core after dbt deps.

### Tier A — product models (this repo)

#### fct_inv_sap_cd

Description: Cash-discount SAP invoice fact. Structural entitlement, CD/WCO arbitration consumption, reporting-period paid gate, taken/excluded/leakage, attribution policy diagnostics, ordered leakage waterfall to primary_cause and lost_discount_amount. Built on the package spine.

Grain: one row per sap_inv_key (posted vendor invoice, KR, vendor present).

Sources: ref('ap_core', 'fct_inv_sap_core'), ref('ap_core', 'fct_inv_cd_wco_arbitration'), int_attribution_policy_active.

Transformation: structural entitlement, arbitration join (is_cd_eligible, not_cd_eligible_reason), paid-in-period (is_kpi_entitled), taken/excluded/leakage, attribution policy fields, leakage waterfall.

Consumed by: all CD marts and timing models that need KPI scope or leakage amounts.

Notable outputs: not_entitled_reason, is_cd_eligible, not_cd_eligible_reason, is_kpi_entitled, is_taken, is_excluded, is_leakage, primary_cause, lost_discount_amount, runway_at_handoff, processing_available_days.

---

#### fct_inv_timing_overlay_cd

Description: Canonical CD overlay intervals: package observed Coupa and SAP block intervals plus CD-only payment_run_wait where eligible.

Grain: sap_inv_key × overlay_reason_code × interval_seq.

Sources: ref('ap_core', 'fct_inv_timing_overlay_core'), ref('ap_core', 'int_inv_sap_payment_block_intervals'), fct_inv_sap_cd for payment_run_wait, seed_timing_overlay_reason_map via package.

Transformation: union core observed rows with derived payment_run_wait, reason metadata from package seed maps.

Consumed by: fct_inv_timing_overlay_span, fct_inv_timing_allocation (via span). Overlay tests target this model.

Notable outputs: interval_start_date, interval_end_date, interval_days, reason_group, source_system.

---

#### fct_inv_timing_allocation

Description: Splits timing-type leakage euros across phases and timing buckets for prioritisation. Does not change primary_cause.

Grain: sap_inv_key × phase_level × phase_code × bucket_code (only rows with priority_allocated_eur > 0).

Sources: fct_inv_sap_cd (timing primary causes only), ref('ap_core', 'fct_inv_timing_span'), fct_inv_timing_overlay_span.

Transformation: payment vs pre_posting regime from runway at handoff, phase and bucket proration, reconciliation to lost_discount_amount.

Consumed by: mart_timing_phase_impact, mart_timing_bucket_impact, sample PDF / analyses.

Notable outputs: priority_allocated_eur, gross_exposure_days, bucket_code.

---

#### mart_cash_discount_kpi

Description: Headline cash-discount KPIs for the reporting period.

Grain: one row per reporting_period_start × reporting_period_end (vars).

Sources: fct_inv_sap_cd.

Transformation: counts and sums for entitled, taken, excluded, leakage, opportunity, realized, excluded, and leakage EUR, leakage rate.

Consumed by: dashboards, sample report, portfolio tests.

Notable outputs: kpi_entitled_count, leakage_count, leakage_eur, leakage_rate, discount_opportunity_eur.

---

#### mart_cash_discount_kpi_by_cause

Description: Leakage broken down by primary cause (reconciles to headline mart).

Grain: one row per reporting period × primary_cause.

Sources: fct_inv_sap_cd.

Transformation: filter leakage rows, group by primary_cause (and group), sum counts and EUR.

Consumed by: dashboards, sample report, cause reconciliation tests.

Notable outputs: primary_cause, leakage_count, leakage_eur.

---

#### mart_timing_bucket_impact

Description: Portfolio view of timing leakage by phase and timing bucket with action ranking.

Grain: one row per reporting period × phase_level × phase_code × bucket_code.

Sources: fct_inv_timing_allocation, fct_inv_sap_cd (vendor, period context as needed).

Transformation: aggregate allocation euros and exposure days, cumulative share, ACT vs WATCH, owner_role for narrative.

Consumed by: timing action report, sample PDF.

Notable outputs: priority_allocated_eur, action_status, owner_role, gross_exposure_days.

---

### Shared models (ap_core — reference only)

Full inventory and column contract: https://github.com/alebayon/ap_core/blob/main/docs/core_decisions.md and ap_core README.

| Model | Role in CD product |
| ----- | ------------------ |
| fct_inv_sap_core | Spine, ref('ap_core', 'fct_inv_sap_core') from fct_inv_sap_cd |
| fct_inv_cd_wco_arbitration | Treasury gates, joined on fct_inv_sap_cd |
| fct_inv_timing_span | Phase weights for allocation, ref from fct_inv_timing_allocation |
| fct_inv_timing_overlay_core | Observed overlays, unioned into fct_inv_timing_overlay_cd |
| map_inv_sap_coupa, fct_inv_coupa, change facts, dims, src_* | Upstream of spine and timing (package only) |

### Tier B — other models (this repo)

| Model | Grain | Role |
| ----- | ----- | ---- |
| seed_attribution_policy | policy row | Processing and payment-reserve thresholds (only seed in this repo) |
| int_attribution_policy_active | ephemeral | Active policy row for fct_inv_sap_cd |
| fct_inv_timing_overlay_span | overlap rows | Exposure bridge for allocation (not euro allocation itself) |
| mart_timing_phase_impact | period × phase | Phase-level timing EUR for prioritisation |
| mart_timing_phase_profile | period × phase | Phase duration portfolio (instrumentation) |

Shared src, dim, map, Coupa/SAP change streams, and core ints are not listed here. See ap_core model inventory.

## Sample stakeholder report

Synthetic 2024 curriculum period — client-style summary of headline KPIs, leakage by cause, and timing actions (numbers align with mart tests).

- PDF: [cash_discount_report_2024_v6.pdf](reports/cash_discount_report_2024_v6.pdf)