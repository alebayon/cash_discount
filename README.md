# cash_discount

Personal dbt project for cash discount analytics and modeling.

##Disclaimer

This project is for educational purposes, the datasets are made to have realistic throughput times and attributes, and it's completely synthetic, no real invoice data is used.
The SLAs, process steps and KPI strategies are based on standards available on the internet and personal knowledge, nothing is taken from a real company.

##Project goals

I've worked several years in Finance Operations using Process Mining. One of the things I used to struggle with is the lack of process and data control on a large and complex data model. Process Mining often focus on the customer experience, fast and effective dashboarding and multiple possibilities of executions. What I miss sometimes is to have a modulated, comprehensive and scalable quality and modeling control. This is what I've found in dbt, an open source tool for developing data models end to end.
The Analytics Engineer role dominates the core of a data solution: from RAW data until dashboard ready KPI there are multiple transformations, often is the shadow interface between the Data Engineer and the Business Analyst, where some magic is happening without the full ownership of the engineer and the understanding of the stakeholder. Here is where the Analytics Engineer bring the bridge, making the data logic completely predictive and explainable, making the business question the process before the data.
This project simulates an Accounts Payable model that leaks cash discount, the model takes raw data and SLAs as inputs, and delivers a prioritized list of recommended actions that could have prevented such leakage and will help the user to solve systemic issues for future cash discount recovery.

##Architecture overview:

- Invoice data dominates, invoice value (net/cash discount) is what needs to be aggregated, therefore a table with a grain of one line per invoice is the design choice as the main dbt model.
- SAP data dominates: SAP is the last system where the invoices arrive when they are ready to be paid, therefore because of this and because it contains the latest information of the invoice (assuming it's possible that the downstream systems don't get updated from SAP), SAP data is considered as the source for all metrics as long as they are available and overwrites any equivalent field from another system.
- Systems involved: SAP and Coupa. Coupa is a real tool and some of the attributes are similar of what a user would find in that tool. However all the logics and fiels are synthetic, only inspired on the real setup of Coupa. No other systems are considered for this data model for now, as it is only adding complexity without providing useful showcase insights.
- The architecture needs as minimum models with these grains: 1. A main grain of invoice (one line or header per invoice), 2. tables of changes with one row per change, 3. supplier master data with one row per supplier id, 4. reporting tables with aggregated data per reporting period.
- Secondary models: 1. Mapping table between systems (Coupa-SAP) with inner join (no orphans) and grain one invoice per row. 2. Sources or staging models (usually views) to make a first transformation of data from the seed/source. Usually column names and format conversion (data cleansing) for later transformation. 3. Calculation fact tables for measuring phase spans, blocker intervals, overlapping blocker-phase, allocation of exposure (impact of blockers) into the phases and buckets. 4. Reporting tables with different grains: phase, blocker buckets, cash discount total per reporting period, cash discount total per cause bucket. 5. intermediate models to make a separated transformation (for better control) for specifically important elements like the policy values (SLAs), the blockers from Coupa or SAP.
- Tests: 1. General tests per columns (e.g. not null, unique, relationships etc.) that evaluates the design (so it works with any input dataset). 2. Specific tests to control the dataset expectations, from logic rules to specific invoice values of the design dataset.
- Raw and seeds: csv format of datasets and configuration files
- Report generator: a python script that converts the analysis results into a PDF with readable results


##Architecture structure:

Raw data seeds: source system data based on actual fields from tools like SAP and Coupa
Seed setup: mappings for raw interpretation and SLA values as initial settings
SRC models: raw data curated. Column names changed, format adaptations and basic clean up of special characters and spaces.
FCT models: tables of facts, here is the core of the model. Invoice and changes tables (SAP and Coupa), measurements of spans of process phases and blockers and the final allocation (eur) of overlay buckets.
DIM models: master data tables, store information about vendors.
INT models: intermediate ephemeral tables, act as an interface between 2 models, transforms the SLAs variables into fields and bring the blocker intervals together for the allocation
MAP model: matching logic between the 2 systems SAP and Coupa
MART models: last layer of transformation, it transforms the fact tables into dashboard ready tables and calculate KPIs

##Service Level Agreement (SLA)

1. Minimum processing days: Establish the minimum feasible time for Accounts Payable team to process an invoice, even with urgency. Anything below that is unfeasible and it is the primary cause of leaking cash discount. Default value: 4
2. Standard processing days: Between this value and Minimum is considered compressed, the processing time is feasible but only under pressure, the responsibility is on the Accounts Payable to deliver on time but these cases need to be flagged and make adjustments to avoid them in the future. Above this value an available processing time is considered enough and it's on the Accounts Payable team to process with enough runway time for the payment run. This is also one component of the payment terms evaluation together with the minimum runway days. The sum of these establish the minimum payment terms days a procurement department should negotiate the contracts. Default value: 7
3. Minimum payment runway days: This is the minimum days a payment run needs for execution. The goal of the pre-SAP process is to deliver the invoice with enough payment runway days, and this is a hard line of ownership split between pre-SAP and payment run process owners. That creates a deadline for invoice processing of target deadline minus the minimum payment runway days. Default value: 3


##The Funnel

One of the main goals of this use case is to build a decision tree that classifies every invoice into one category each. Every split in the funnel has a meaningful filter and business logic split, from defining scope populations until main contributors of cash discount leakage.

0. Overall dataset population: all documents in an Accounts Payable department.
1. Vendor Invoices: first filter is only invoices from a registered vendor (document type = 'KR' and vendor id not null)
2. Paid in period: Open invoices are not considered for analysis (they are for the operational use case out of this scope), and the period is the selection of the user (for showcase: year 2024).
3. Entitled (KPI Universe): Here lives is the denominator of the KPI based on rates (%). Entitled means it has cash discount potential (both invoice value and discount percentage) and there is a time window for payment (baseline date and discount terms). As soon as one of the required fields is missing, there is a non entitled reason recorded and this invoice is set out of scope.
4. Realized/Not taken: After passing the initial scope filters (Document must be a vendor invoice paid in period and cash discount entitled), we have the entire population of the KPIs with a split. First Realized, which in our case means full cash discount captured, for simplicity reasons we don't consider partial cash discount achieved, also we could but we don't consider for this use case certain error margin with rounding. All realized have been realized in full eligible amount, and the non taken have a zero amount captured.
5. Excluded/Leak: From the not taken there is a split leakage and justified lost cash discount or excluded. There is a custom flag (not take skonto at clearing) which can be activated in special cases and the lost cash discount analysis won't try to deep dive into the reasons. It will be counted as lost cash discount, though.
6. Leakage split: there are several buckets in leakage. In this level the conditions of the buckets are not exclusive by themselves, one invoice could fall into more than one bucket, so it is very important to establish a hierarchy of conditions that splits the ownership in the a that makes more sense. This means that every invoice with leakage will be evaluated in order, and as soon as it falls into one bucket, it automatically rejects the belonging to any other bucket downstream.
6.1 Quality quality error: I want to prioritize data quality on critical fields in the analysis, if any of these fields' values are missing then no assumptions are made, it's classified as data quality error. Some of these fields are part of the not entitled and if they are missing the invoice should be not entitled, we keep them here as redundancy safety measure, in case the entitled conditions change in the future. The fiels are receipt date, sap entry date, cash discount deadline date, discount days as mandatory invoice fields. Policy SLA fields such minimum processing days, standard processing days and minimum payment runway fields are required to draw the ownership line. Finally a quality check if receipt date is not later than sap entry date and this not later than clearing date will avoid having negative span values.
6.2 Capture: If there is no data quality error, the next priority in our hierarchy is capture. This bucket checks whether the clearing date happened on or before the discount deadline date for an invoice with leakage. In this case no further interpretation should be done, it's a case that should be captured and needs a manual evaluation.
6.3 Structural terms vs capability: From this bucket on the clearing date is later than the deadline date, this highly expected for most cases and the deeper analysis tries to explain why this happened.
The next consideration in the logic hierarchy is the design of contracts, and the comparison is whether the discount terms (contract) is shorter what is considered reasonable by the SLAs, which is the sum of the standard processing days plus the minimum runway days. I established by default standard processing of 7 days and minimum runway of 3 days, that means every invoice should have at least 10 days of discount terms regardless any execution considerations. Other approaches don't make this rule that hard and forgives a bad contract in cases the execution performance is very rapid. This approach doesn't and the reason is clear, a good baseline design prevents future issues and establish a clear border of ownership between the procurement contracts and the subsequent causes.
Accepting discount days below this threshold is putting by default pressure in accounting teams.
6.4 Structural insufficient time at intake: If the previous buckets conditions are not met (there is quality of data, clearing date exceed the deadline and contract payment terms are sufficient), the next condition to evaluate is whether the invoice is received in a timely manner so the available time between receipt date and deadline date exceeds a minimum. This is necessary because invoices are received after the baseline date clock is running. Very often baseline date is set at the creation of the invoice, simply because that's a date the vendor can control and proof, while the receipt date depends on the vendor sending the invoice, the interface and the client receiving it, and this can often create disputes on who was responsible to delay the baseline date (delay baseline date means delay of payment and delay of income cash flow for the vendor). Regardless when the baseline is set, the client can actually fairly claim to not have enough time to process the invoice, making the capture of cash discount unfeasible. If the processing available days (days from receipt until deadline) is below the SLA minimum processing days value and the runway is also below the minimum then the reason falls in this category and the actions should be targeting the vendor interface and client inbound process to reduce as much as possible the time period between creating the invoice and receiving the invoice.
6.5 Timing: Until this point the evaluation process was discarding first data quality and unexpected capture issues, as well as structural problems regarding fair contract terms and avoid late receipts. If non of these conditions are fulfilled, it means that the Accounting Team received the invoice with the necessary data available and with sufficient (feasible) time to process the invoice.
Unlike the other buckets, where the actions are clearly targeted into a primary cause, the timing bucket needs to be narrowed down and some impact allocations need to be performed, as there are usually multiple causes, the actions that addressed them can be prioritized if there is an estimation of the contribution of these reasons into the overall processing delay.

##Timing breakdown
6.5.1.Pre sap execution compressed: Before establishing a hard line between the structural and execution blame it's important to consider that in reality there is a buffer between what is feasible and what is reasonable when it comes to execution. There is no such consideration in contracts, as they need to be designed without gray zones. However, when an accounting team receives an invoice with feasible but compressed time, it's important to point out that in case of failed capture, and even though the accounting team has the ownership, the fact of being under pressure needs to be taken into account for possible future adjustments. This is why I established 2 SLAs: standard and minimum processing days, to have a bucket out of this gray zone. If the available time for processing falls between these thresholds and there is no enough runway time at posting then the primary cause is the pre-sap compressed execution.
6.5.2 Pre sap execution standard: if the available time for processing is above the threshold of what is considered as reasonable, the logic escapes the gray zone and enters the execution-only cause. In this case, the runway time at posting is also below minimum so the window opportunity was wasted in the processing even with enough time.
6.5.3 Payment execution: This is the last sub-bucket of timing execution, and it has a different behavior. Unlike processing (pre-sap period) that has multiple tasks to be performed (often many manual) and it is meant to be done as soon as possible, the payment regime is meant to wait for the deadline. While pre-sap is desirable to be closed as fast as possible, the target of payment is to launch the payment run on the deadline (in this case cash discount but it can be a net due date otherwise), not later and not too early, so it is expected an invoice waiting inactive until the time to pay comes. As convention for this use case, we assumed a payment process almost automatic and triggered anytime (even on weekends) with no friction except setting or removing a payment block. There is only one SLA for minimum payment runway days (3 days by default) which is considered enough for executing a payment. This condition overwrites some of the previous buckets as the opposite condition (if runway days are less than the minimum) is set for "Structural insufficient time at intake", "Pre sap execution compressed" and "Pre sap execution standard". So if the condition of this bucket is true, the cases that were supposed to fall into these buckets would fall into this one. The reason to do this is the hierarchy: Data quality goes first, then cases with a clearing date that should have captured the cash discount, then the contract design. The conditions of these buckets are dominant over the runway minimum days, there is no option to avoid these buckets after a good performance in processing, this would hide the data quality and structural design errors. For the others, there is the possibility of recovery, even with insufficient time at intake, some processes are so fast that pre-sap period recovers the days and possibly delivers enough runway to avoid payment execution allocation.

##The Timing allocation

The allocation regime: either pre-SAP or payment depending on runway days at posting compared to the SLA minimum payment runway days

Payment regime: here the exposure window is from the deadline until the clearing date (only if clearing is after deadline). The span days with payment block in this window are counted into the bucket "payment block at clearing" and the rest of days in this window are "payment run wait"

Pre-SAP regime: the exposure window is compound by the full span days of intake and interface (as they are targeted to be zero) plus the exposure days in verification and approval. The window starts with verification start and ends with deadline if deadline happened before posting, otherwise posting date (entry date in sap). Every phase is counted separately for later allocation between phases and it's the difference between the start of the phase and the earlier between the end of the phase or the deadline, if deadline is after start, otherwise it's zero.


## Setup

1. Configure your warehouse connection in `~/.dbt/profiles.yml` (profile name: `cash_discount`).
2. From this folder:

```bash
dbt debug
dbt run
dbt test
```

## Project docs

- `docs/decisions.md` — architecture and modeling decisions
- `.cursor/rules/` — Cursor AI conventions for this workspace
