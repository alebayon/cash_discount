{{ config(tags=['core']) }}

with from_coupa as (

    select
        sap_inv_key,
        overlay_reason_code,
        interval_seq,
        interval_start_date,
        interval_end_date,
        source_change_id,
        interval_notes
    from {{ ref('int_inv_coupa_overlay_intervals') }}

),

from_sap_payment_block as (

    select
        sap_inv_key,
        overlay_reason_code,
        interval_seq,
        interval_start_date,
        interval_end_date,
        source_change_id,
        interval_notes
    from {{ ref('int_inv_sap_payment_block_intervals') }}

),

overlays as (

    select * from from_coupa

    union all

    select * from from_sap_payment_block

),

with_map as (

    select
        o.sap_inv_key,
        o.overlay_reason_code,
        o.interval_seq,
        o.interval_start_date,
        o.interval_end_date,
        o.source_change_id,
        o.interval_notes,
        m.reason_group,
        m.source_system
    from overlays o
    inner join {{ ref('seed_timing_overlay_reason_map') }} m
        on o.overlay_reason_code = m.overlay_reason_code
    where m.is_active

),

with_invoice as (

    select
        wm.sap_inv_key,
        wm.overlay_reason_code,
        wm.interval_seq,
        wm.interval_start_date,
        wm.interval_end_date,
        wm.source_change_id,
        wm.interval_notes,
        wm.reason_group,
        wm.source_system
    from with_map wm
    inner join {{ ref('fct_inv_sap_core') }} inv
        on wm.sap_inv_key = inv.sap_inv_key

)

select
    sap_inv_key,
    overlay_reason_code,
    interval_seq,
    interval_start_date,
    interval_end_date,
    case
        when interval_start_date is not null
         and interval_end_date is not null
        then datediff('day', interval_start_date, interval_end_date)
    end as interval_days,
    reason_group,
    source_system,
    source_change_id,
    interval_notes
from with_invoice