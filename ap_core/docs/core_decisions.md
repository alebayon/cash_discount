\# ap\_core — decisions log



Record durable choices for the \*\*shared AP knowledge model\*\* (`ap\_core`).

Built inside the `cash\_discount` workspace until extracted as a dbt package; consumed by cash\_discount, on\_time\_payment, working\_capital, and later products.



\*\*Related:\*\* Cash-discount–only policy and curriculum → `docs/decisions.md` (legacy log until CD is refactored onto product extensions).



\---



\## Project context



\- \*\*Package / layer name:\*\* ap\_core (dbt tag: `core`)

\- \*\*Purpose:\*\* Durable SAP invoice facts, payment terms and dates, Coupa process evidence, cross-system mapping, neutral timing spans, observed blocker intervals, and shared CD/WCO arbitration policy. No product KPI funnels (CD leakage, OTP late, WCO strategy compliance).

\- \*\*Workspace (staging):\*\* `C:\\dbt\\cash\_discount` — core models live under `models/` with tag `core` until Phase 2 extract.

\- \*\*Grain anchor:\*\* One row per in-scope SAP vendor invoice, keyed by `sap\_inv\_key`.

\- \*\*Calendar:\*\* Calendar days throughout v0 (Snowflake `datediff('day', …)`), consistent with CD decisions D6.



\---



\## Architecture



\### Repositories and dependencies (target)



ap\_core ──► cash\_discount 

ap\_core ──► on\_time\_payment 

ap\_core ──► working\_capital 

ap\_core ──► daily\_ops (later)





\- Products \*\*do not\*\* depend on each other for primary KPIs (OTP does not use CD; WCO does not require CD leakage models).

\- Shared \*\*CD/WCO arbitration\*\* lives in core; CD and WCO \*\*consume\*\* it; OTP does \*\*not\*\* use arbitration.

\- Cross-product reporting may combine marts later; no circular package dependencies.



\### Layering (in this repo, pre-extract)



| Layer | Folder | Materialization | Naming |

|-------|--------|-----------------|--------|

| Staging | `models/src/` | view | `src\_\*` |

| Intermediate | `models/int/` | ephemeral | `int\_\*` |

| Dimensions | `models/dim/` | table | `dim\_\*` |

| Maps | `models/map/` | table | `map\_\*` |

| Facts | `models/fct/` | table | `fct\_\*` |



Product-specific models (e.g. `fct\_inv\_cash\_discount`) stay in this repo under tag `cash\_discount` until repos split.



\### Invoice spine (same grain, separate models)



| Model | Owner | Role |

|-------|--------|------|

| `fct\_inv\_sap\_core` | core | Facts, terms, dates, map-based Coupa fields, neutral elapsed days |

| `fct\_inv\_cash\_discount` | cash\_discount | CD eligibility, arbitration consumption, reporting period, leakage funnel, V6 |

| `fct\_inv\_payment\_timeliness` | on\_time\_payment (later) | Net-due lateness, OTP reporting period |

| `fct\_inv\_working\_capital` | working\_capital (later) | Strategy compliance vs pursue\_cd / target\_net |



\*\*Rejected:\*\* One wide `fct\_inv\_sap` with all product columns. \*\*Accepted:\*\* Product extensions `ref('fct\_inv\_sap\_core')` + product columns.



Temporary compatibility: `fct\_inv\_sap` may point at `fct\_inv\_cash\_discount` during migration; deprecate explicitly.



\### SAP vs Coupa



| System | Core responsibility |

|--------|---------------------|

| \*\*SAP\*\* | Invoice identity, amounts, baseline/payment terms, posting/entry/clearing dates, discount posted at clearing, clearing flags |

| \*\*Coupa\*\* | Pre-SAP receipt/workflow evidence, statuses, change history |



\*\*Cross-system rule:\*\* Enrich SAP invoices with Coupa `coupa\_id` and `receipt\_date` only through \*\*`map\_inv\_sap\_coupa`\*\*. `coupa\_posting\_ref` on SAP is a matching input, not a substitute for the map.



\### Timing boundary



\*\*Core (neutral / observed):\*\*



\- `fct\_inv\_timing\_span` — ownership and subprocess intervals

\- `int\_inv\_coupa\_overlay\_intervals`, `int\_inv\_sap\_payment\_block\_intervals`

\- `fct\_inv\_timing\_overlay\_observed` — union of observed Coupa + SAP block intervals only

\- `fct\_inv\_timing\_overlay\_span\_observed` — overlap of observed intervals with neutral spans



\*\*Not in core:\*\*



\- `payment\_run\_wait` (CD payment window remainder; depends on discount deadline, leakage, V6 payment\_execution population)

\- Timing euro allocation (lost discount — CD measure)



CD keeps full overlay union, allocation, and timing marts.



\### dbt selection



Use \*\*ancestors\*\* of a product tag: `dbt build --select +tag:cash\_discount` (leading `+`).  

Do not use `tag:cash\_discount+` when the goal is to build upstream core first.



\### Implementation sequence (reference)



0\. Document contract (this file)  

1\. Split `fct\_inv\_sap\_core` + `fct\_inv\_cash\_discount` inside `cash\_discount`; keep curriculum green  

2\. Arbitration curriculum + shared policy model  

3\. Extract `ap\_core` package v0.1.0  

4\. Pin package from `cash\_discount`; remove duplicated core  

5\. CI + semver contracts  

6\. Build OTP against core only  



\---



\## Open questions



\- Production source and definition for `receipt\_date` (synthetic v0 uses Coupa `created\_at` on mapped invoices).

\- \*\*Terms at clearing / effective-dated payment terms\*\* — rebuilds can change `discount\_deadline\_date` and `net\_due\_date` if terms are read as current state; document limitation for v0; design history before production-grade OTP/CD audit claims.

\- Authoritative date for arbitration policy version if `document\_date` is replaced later.



\---



\## Decisions



\### 2026-10-20 — ap\_core scope and product boundaries \[ARCHITECTURE]



\*\*Context:\*\* Multiple AP products will share the same SAP invoice grain. CD logic currently lives in a monolithic `fct\_inv\_sap`.



\*\*Decision:\*\* Introduce `ap\_core` as the shared layer: facts, contractual terms/dates, process evidence, neutral timing, shared arbitration. Products add eligibility, KPI scope, and outcomes. Build core inside `cash\_discount` before package extract.



\*\*Why:\*\* Avoid duplicate pipelines across repos; keep product denominators and policies independent.



\*\*Impact:\*\* New `fct\_inv\_sap\_core`; CD refactor to `fct\_inv\_cash\_discount`; future OTP repo depends only on `ap\_core`.



\---



\### 2026-10-20 — `fct\_inv\_sap\_core` public contract (v0) \[CONTRACT]



\*\*Context:\*\* Consumers need a stable invoice spine without product KPIs.



\*\*Decision:\*\* Core exposes at minimum:



\- \*\*Identity / SAP:\*\* `sap\_inv\_key`, `doc\_number`, `company\_code`, `fiscal\_year`, `vendor\_id`, `document\_type`, `baseline\_date`, `payment\_terms`, `invoice\_amount`, `invoice\_amount\_eur`, `currency\_code`, `document\_fx\_rate`, `posting\_date`, `sap\_entry\_date`, `document\_date`, `clearing\_date`

\- \*\*Terms:\*\* `discount\_pct`, `discount\_days`, `discount\_deadline\_date`, `net\_days`, `net\_due\_date`

\- \*\*Payment facts:\*\* `discount\_taken\_amount`, `discount\_taken\_amount\_eur`, `do\_not\_take\_skonto\_at\_clearing`

\- \*\*Cross-system:\*\* `coupa\_posting\_ref`, mapped `coupa\_id`, mapped `receipt\_date`

\- \*\*Lifecycle:\*\* `is\_cleared`

\- \*\*Neutral elapsed:\*\* `pre\_sap\_elapsed\_days` (receipt → sap\_entry), `actual\_cycle\_days` (receipt → clearing)



EUR amounts use document-date FX; `invoice\_amount\_eur` is stable on rebuild for a given document.



\*\*Rejected on core:\*\* `is\_paid\_in\_period`, `is\_entitled`, `is\_kpi\_entitled`, `is\_taken`, `is\_excluded`, `is\_leakage`, lost discount, OTP/WCO flags, Version 6 attribution fields, `primary\_cause`.



\*\*Why:\*\* Reporting period and product classification are product-owned; core stays durable across products.



\*\*Impact:\*\* Column list for `fct\_inv\_sap\_core.sql` and `\_fct\_\_models.yml`; products derive period gates from `clearing\_date` + vars.



\---



\### 2026-10-20 — Vendor dimensions retain inactive records \[POLICY]



\*\*Context:\*\* Historical invoices must keep valid vendor keys after deactivation.



\*\*Decision:\*\* `dim\_vendor\_sap` and `dim\_vendor\_coupa` retain inactive/deleted suppliers; expose `is\_active` (or equivalent). Do not filter them out of core dimensions.



\*\*Impact:\*\* May diverge from current CD dims that filter active-only until core dims are adopted.



\---



\### 2026-10-20 — CD/WCO arbitration v1 in core \[POLICY]



\*\*Context:\*\* Some terms-eligible invoices should not be CD targets (immaterial saving or excessive cash acceleration).



\*\*Decision:\*\* Core holds `seed\_cd\_wco\_arbitration\_policy` and a shared arbitration model (grain `sap\_inv\_key`). v1 parameters:



\- `minimum\_potential\_discount\_eur` = 10  

\- `maximum\_cash\_acceleration\_days` = 20 (inclusive)



Derived:



\- `potential\_discount\_eur` = `invoice\_amount\_eur \* discount\_pct`  

\- `cash\_acceleration\_days` = calendar days from `discount\_deadline\_date` to `net\_due\_date`  

\- `is\_cd\_eligible` (for CD consumption) = terms eligible AND amount gate AND acceleration gate (AND, no compensation)  

\- `payment\_strategy` = `pursue\_cd` | `target\_net`  

\- `not\_cd\_eligible\_reason` per handoff vocabulary  



Policy version selected by effective date; v1 evaluation date = `document\_date`.



\*\*Not in v1:\*\* hurdle rates, vendor overrides, weighted scoring, single gate overriding the other.



\*\*Impact:\*\* Seed + model in core; `fct\_inv\_cash\_discount` consumes; OTP ignores.



\---



\### 2026-10-20 — OTP v1 rule (documented for core consumers) \[POLICY]



\*\*Context:\*\* OTP will be a separate product on core only.



\*\*Decision:\*\* OTP v1 uses `net\_due\_date` and `clearing\_date` from core. `otp\_grace\_days` default 0. `is\_late` when `days\_after\_net\_due > otp\_grace\_days`. No CD arbitration in OTP v1.



\*\*Impact:\*\* Core must ship valid `net\_due\_date`; OTP repo not started until core contract tested.



\---



\## Model inventory



Update row counts after `dbt build`. Status: \*\*planned\*\* until core split lands.



| Object | Layer | Grain | Status | Notes |

|--------|-------|-------|--------|-------|

| `src\_\*` | src | per source | existing | Shared staging; tag core when split complete |

| `dim\_vendor\_sap` | dim | vendor | existing | Move to retain inactive + `is\_active` |

| `dim\_vendor\_coupa` | dim | supplier | existing | Same |

| `map\_inv\_sap\_coupa` | map | (sap\_inv\_key, coupa\_id) | existing | Required for core Coupa enrichment |

| `fct\_inv\_coupa` | fct | coupa invoice | existing | |

| `fct\_inv\_coupa\_changes` | fct | change event | existing | |

| `fct\_inv\_sap\_changes` | fct | change event | existing | |

| `seed\_payment\_term\_sap` | seed | ZTERM | existing | Includes `net\_days` |

| `seed\_cd\_wco\_arbitration\_policy` | seed | policy version | planned | |

| `fct\_inv\_sap\_core` | fct | sap\_inv\_key | planned | Public contract above |

| `fct\_inv\_timing\_span` | fct | span grain | existing | Core |

| `int\_inv\_coupa\_overlay\_intervals` | int | interval | existing | Core |

| `int\_inv\_sap\_payment\_block\_intervals` | int | interval | existing | Core |

| `fct\_inv\_timing\_overlay\_observed` | fct | overlay interval | planned | Observed only |

| `fct\_inv\_timing\_overlay\_span\_observed` | fct | overlap | planned | |

| `int\_\*` / `fct\_\*` arbitration | core | sap\_inv\_key | planned | Name TBD |

| `fct\_inv\_cash\_discount` | fct (CD) | sap\_inv\_key | planned | Product extension |



\---



\## Conventions (stable)



\- \*\*Decision file:\*\* This file is authoritative for core grains, columns, and shared policy.

\- \*\*Tag:\*\* `core` on models that move to `ap\_core` package.

\- \*\*Keys:\*\* `sap\_inv\_key` on SAP invoice facts; map tests guard orphan keys.

\- \*\*Handoff:\*\* Proposed changes to this file = one full copy-paste block per dated entry. Proposed SQL/YAML/seeds = complete file contents (see `.cursor/rules/project.mdc`).

\- \*\*Model inventory:\*\* Update the table when adding or completing a core model.

\- \*\*Versioning (post-extract):\*\* Semantic versioning for `ap\_core`; products pin releases in `packages.yml`.



\---



\## Chat handoff notes



<!-- Paste a short summary when switching to a new chat -->



Last updated: 2026-10-20



Next build step: scaffold `fct\_inv\_sap\_core` (terms + `net\_due\_date` + map-based `receipt\_date`); keep `fct\_inv\_sap` shim until CD split is green. CD behavior unchanged in `docs/decisions.md` until refactor.

