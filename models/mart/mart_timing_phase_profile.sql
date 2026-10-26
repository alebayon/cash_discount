{{ config(tags=['cash_discount']) }}
{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

with measured_spans as (

    select
        phase_level,
        phase_code,
        span_days
    from {{ ref('ap_core', 'fct_inv_timing_span') }}
    where span_status = 'measured'
      and span_end_date >= '{{ period_start }}'::date
      and span_end_date <= '{{ period_end }}'::date

),

aggregated as (

    select
        '{{ period_start }}'::date as reporting_period_start,
        '{{ period_end }}'::date as reporting_period_end,
        phase_level,
        phase_code,
        count(*) as span_count,
        sum(span_days) as total_span_days,
        percentile_cont(0.5) within group (order by span_days) as median_span_days,
        percentile_cont(0.9) within group (order by span_days) as p90_span_days,
        sum(case when span_days = 0 then 1 else 0 end) as zero_day_span_count
    from measured_spans
    group by
        phase_level,
        phase_code

)

select
    reporting_period_start,
    reporting_period_end,
    phase_level,
    phase_code,
    span_count,
    total_span_days,
    median_span_days,
    p90_span_days,
    zero_day_span_count
from aggregated