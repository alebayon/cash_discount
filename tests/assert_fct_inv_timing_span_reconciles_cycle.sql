-- ownership level: where both phases measured, sum(span_days) = actual_cycle_days
with both_measured as (

    select sap_inv_key
    from {{ ref('fct_inv_timing_span') }}
    where phase_level = 'ownership'
    group by sap_inv_key
    having sum(case when span_status = 'measured' then 1 else 0 end) = 2

),

reconciled as (

    select
        s.sap_inv_key,
        sum(s.span_days) as span_sum,
        f.actual_cycle_days
    from {{ ref('fct_inv_timing_span') }} s
    inner join both_measured b
        on s.sap_inv_key = b.sap_inv_key
    inner join {{ ref('fct_inv_sap') }} f
        on s.sap_inv_key = f.sap_inv_key
    where s.phase_level = 'ownership'
      and s.span_status = 'measured'
    group by
        s.sap_inv_key,
        f.actual_cycle_days

)

select
    sap_inv_key,
    span_sum,
    actual_cycle_days
from reconciled
where span_sum <> actual_cycle_days