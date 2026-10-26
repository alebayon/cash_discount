{{ config(tags=['cash_discount']) }}

with observed as (

    select
        sap_inv_key,
        overlay_reason_code,
        interval_seq,
        interval_start_date,
        interval_end_date,
        interval_days,
        reason_group,
        source_system,
        source_change_id,
        interval_notes
    from {{ ref('ap_core', 'fct_inv_timing_overlay_core') }}

),

payment_windows as (

    select
        sap_inv_key,
        discount_deadline_date as win_start,
        clearing_date as win_end
    from {{ ref('fct_inv_sap_cd') }}
    where is_leakage
      and primary_cause = 'payment_execution'
      and clearing_date is not null
      and discount_deadline_date is not null
      and sap_entry_date is not null
      and clearing_date > discount_deadline_date
      and runway_at_handoff is not null
      and minimum_payment_runway_days is not null
      and runway_at_handoff >= minimum_payment_runway_days

),

blocks_clipped as (

    select
        w.sap_inv_key,
        greatest(b.interval_start_date, w.win_start) as block_start,
        least(b.interval_end_date, w.win_end) as block_end
    from payment_windows w
    inner join {{ ref('ap_core', 'int_inv_sap_payment_block_intervals') }} b
        on w.sap_inv_key = b.sap_inv_key
    where greatest(b.interval_start_date, w.win_start)
        < least(b.interval_end_date, w.win_end)

),

blocks_ordered as (

    select
        sap_inv_key,
        block_start,
        block_end,
        row_number() over (
            partition by sap_inv_key
            order by block_start, block_end
        ) as block_ord
    from blocks_clipped

),

gap_full as (

    select
        w.sap_inv_key,
        w.win_start as interval_start_date,
        w.win_end as interval_end_date
    from payment_windows w
    where not exists (
        select 1
        from blocks_clipped b
        where b.sap_inv_key = w.sap_inv_key
    )

),

gap_before_first_block as (

    select
        w.sap_inv_key,
        w.win_start as interval_start_date,
        min(b.block_start) as interval_end_date
    from payment_windows w
    inner join blocks_clipped b
        on w.sap_inv_key = b.sap_inv_key
    group by
        w.sap_inv_key,
        w.win_start
    having w.win_start < min(b.block_start)

),

gap_after_last_block as (

    select
        w.sap_inv_key,
        max(b.block_end) as interval_start_date,
        w.win_end as interval_end_date
    from payment_windows w
    inner join blocks_clipped b
        on w.sap_inv_key = b.sap_inv_key
    group by
        w.sap_inv_key,
        w.win_end
    having max(b.block_end) < w.win_end

),

gap_between_blocks as (

    select
        b1.sap_inv_key,
        b1.block_end as interval_start_date,
        b2.block_start as interval_end_date
    from blocks_ordered b1
    inner join blocks_ordered b2
        on b1.sap_inv_key = b2.sap_inv_key
       and b2.block_ord = b1.block_ord + 1
    where b1.block_end < b2.block_start

),

run_wait_gaps as (

    select
        sap_inv_key,
        interval_start_date,
        interval_end_date
    from gap_full

    union all

    select
        sap_inv_key,
        interval_start_date,
        interval_end_date
    from gap_before_first_block

    union all

    select
        sap_inv_key,
        interval_start_date,
        interval_end_date
    from gap_after_last_block

    union all

    select
        sap_inv_key,
        interval_start_date,
        interval_end_date
    from gap_between_blocks

),

derived_payment_run_wait as (

    select
        sap_inv_key,
        'payment_run_wait' as overlay_reason_code,
        row_number() over (
            partition by sap_inv_key
            order by interval_start_date, interval_end_date
        ) as interval_seq,
        interval_start_date,
        interval_end_date,
        cast(null as varchar) as source_change_id,
        'Derived: payment window minus payment_block (D64)' as interval_notes
    from run_wait_gaps
    where interval_start_date < interval_end_date

),

run_wait_with_map as (

    select
        d.sap_inv_key,
        d.overlay_reason_code,
        d.interval_seq,
        d.interval_start_date,
        d.interval_end_date,
        case
            when d.interval_start_date is not null
             and d.interval_end_date is not null
            then datediff('day', d.interval_start_date, d.interval_end_date)
        end as interval_days,
        m.reason_group,
        m.source_system,
        d.source_change_id,
        d.interval_notes
    from derived_payment_run_wait d
    inner join {{ ref('seed_timing_overlay_reason_map') }} m
        on d.overlay_reason_code = m.overlay_reason_code
    where m.is_active

),

combined as (

    select * from observed

    union all

    select * from run_wait_with_map

)

select
    sap_inv_key,
    overlay_reason_code,
    interval_seq,
    interval_start_date,
    interval_end_date,
    interval_days,
    reason_group,
    source_system,
    source_change_id,
    interval_notes
from combined