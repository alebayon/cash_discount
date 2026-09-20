-- D28: where all four pre-SAP subprocess phases are measured, sum = ownership pre_sap
with ownership_pre_sap as (
    select
        sap_inv_key,
        span_days as pre_sap_days
    from {{ ref('fct_inv_timing_span') }}
    where phase_level = 'ownership'
      and phase_code = 'pre_sap'
      and span_status = 'measured'
),
subprocess_phase_counts as (
    select
        sap_inv_key,
        count(*) as measured_phase_count,
        sum(span_days) as subprocess_sum
    from {{ ref('fct_inv_timing_span') }}
    where phase_level = 'subprocess'
      and phase_code in ('intake', 'verification', 'approval', 'interface')
      and span_status = 'measured'
    group by sap_inv_key
),
eligible as (
    select sap_inv_key
    from subprocess_phase_counts
    where measured_phase_count = 4
)
select
    o.sap_inv_key,
    o.pre_sap_days,
    s.subprocess_sum
from ownership_pre_sap o
inner join eligible e
    on o.sap_inv_key = e.sap_inv_key
inner join subprocess_phase_counts s
    on o.sap_inv_key = s.sap_inv_key
where o.pre_sap_days <> s.subprocess_sum