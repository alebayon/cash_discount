{{ config(tags=['cash_discount']) }}
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

euro_by_phase as (

    select
        '{{ period_start }}'::date as reporting_period_start,
        '{{ period_end }}'::date as reporting_period_end,
        phase_level,
        phase_code,
        count(distinct sap_inv_key) as invoice_count,
        round(sum(priority_allocated_eur), 2) as priority_allocated_eur
    from allocation
    group by
        phase_level,
        phase_code

),

days_by_phase as (

    select
        phase_level,
        phase_code,
        sum(post_deadline_days) as post_deadline_days
    from invoice_phase_days
    group by
        phase_level,
        phase_code

),

aggregated as (

    select
        e.reporting_period_start,
        e.reporting_period_end,
        e.phase_level,
        e.phase_code,
        e.invoice_count,
        e.priority_allocated_eur,
        d.post_deadline_days
    from euro_by_phase e
    inner join days_by_phase d
        on e.phase_level = d.phase_level
        and e.phase_code = d.phase_code

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