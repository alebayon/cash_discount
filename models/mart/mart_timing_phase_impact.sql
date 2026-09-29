{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

with allocation as (

    select *
    from {{ ref('fct_inv_timing_allocation') }}
    where phase_level is distinct from 'unallocated'

),

invoice_phase_days as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        max(post_deadline_days) as post_deadline_days
    from allocation
    group by
        sap_inv_key,
        phase_level,
        phase_code

),

aggregated as (

    select
        '{{ period_start }}'::date as reporting_period_start,
        '{{ period_end }}'::date as reporting_period_end,
        a.phase_level,
        a.phase_code,
        count(distinct a.sap_inv_key) as invoice_count,
        round(sum(a.priority_allocated_eur), 2) as priority_allocated_eur,
        sum(d.post_deadline_days) as post_deadline_days
    from allocation a
    inner join invoice_phase_days d
        on a.sap_inv_key = d.sap_inv_key
        and a.phase_level = d.phase_level
        and a.phase_code = d.phase_code
    group by
        a.phase_level,
        a.phase_code

)

select
    reporting_period_start,
    reporting_period_end,
    phase_level,
    phase_code,
    invoice_count,
    priority_allocated_eur,
    post_deadline_days
from aggregated
order by priority_allocated_eur desc