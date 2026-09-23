-- D41/D35: blocked coverage cannot exceed phase span_days on curriculum BELNRs
with curriculum as (
    select sap_inv_key
    from {{ ref('fct_inv_sap') }}
    where doc_number in (
        '5100000003',
        '5100000008',
        '5100000019',
        '5100000020'
    )
),

bridge as (
    select
        b.sap_inv_key,
        b.phase_level,
        b.phase_code,
        b.span_seq,
        b.span_days,
        b.overlap_start_date,
        b.reason_exposure_days
    from {{ ref('fct_inv_timing_overlay_span') }} b
    inner join curriculum c
        on b.sap_inv_key = c.sap_inv_key
),

per_row_failures as (
    select
        'reason_exposure_exceeds_span' as failure_type,
        sap_inv_key,
        phase_level,
        phase_code,
        span_seq,
        span_days,
        reason_exposure_days as blocked_days
    from bridge
    where reason_exposure_days > span_days
),

blocked_day_spine as (
    select
        b.sap_inv_key,
        b.phase_level,
        b.phase_code,
        b.span_seq,
        b.span_days,
        dateadd(day, f.value::integer, b.overlap_start_date) as blocked_date
    from bridge b,
    lateral flatten(input => array_generate_range(0, b.reason_exposure_days)) f
),

blocked_totals as (
    select
        sap_inv_key,
        phase_level,
        phase_code,
        span_seq,
        max(span_days) as span_days,
        count(distinct blocked_date) as blocked_days
    from blocked_day_spine
    group by
        sap_inv_key,
        phase_level,
        phase_code,
        span_seq
),

aggregate_failures as (
    select
        'blocked_days_exceeds_span' as failure_type,
        sap_inv_key,
        phase_level,
        phase_code,
        span_seq,
        span_days,
        blocked_days
    from blocked_totals
    where blocked_days > span_days
)

select * from per_row_failures
union all
select * from aggregate_failures