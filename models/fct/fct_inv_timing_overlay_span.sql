{{ config(materialized='view') }}

with measured_spans as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        span_seq,
        span_start_date,
        span_end_date,
        span_days
    from {{ ref('fct_inv_timing_span') }}
    where span_status = 'measured'

),

overlaps as (

    select
        o.sap_inv_key,
        o.overlay_reason_code,
        o.interval_seq,
        s.phase_level,
        s.phase_code,
        s.span_seq,
        s.span_start_date,
        s.span_end_date,
        s.span_days,
        o.interval_start_date,
        o.interval_end_date,
        o.interval_days,
        o.reason_group,
        o.source_system,
        o.source_change_id,
        greatest(o.interval_start_date, s.span_start_date) as overlap_start_date,
        least(o.interval_end_date, s.span_end_date) as overlap_end_date
    from {{ ref('fct_inv_timing_overlay_cd') }} o
    inner join measured_spans s
        on o.sap_inv_key = s.sap_inv_key
        and o.interval_start_date < s.span_end_date
        and o.interval_end_date > s.span_start_date

)

select
    sap_inv_key,
    overlay_reason_code,
    interval_seq,
    phase_level,
    phase_code,
    span_seq,
    span_start_date,
    span_end_date,
    span_days,
    interval_start_date,
    interval_end_date,
    interval_days,
    reason_group,
    source_system,
    source_change_id,
    overlap_start_date,
    overlap_end_date,
    datediff('day', overlap_start_date, overlap_end_date) as reason_exposure_days
from overlaps