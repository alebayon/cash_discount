{{ config(materialized='table') }}

with timing_invoices as (

    select
        sap_inv_key,
        primary_cause,
        lost_discount_amount,
        discount_deadline_date,
        sap_entry_date,
        clearing_date,
        receipt_date,
        runway_at_handoff,
        minimum_payment_runway_days,
        case
            when runway_at_handoff >= minimum_payment_runway_days
                then 'payment'
            else 'pre_posting'
        end as allocation_regime,
        datediff('day', discount_deadline_date, clearing_date) as post_deadline_days
    from {{ ref('fct_inv_sap_cd') }}
    -- Period: is_leakage already implies is_kpi_entitled (clearing in reporting period vars).
    -- D89: Version 6 timing-group primary causes only.
    where is_leakage
      and primary_cause in (
          'pre_sap_execution_compressed',
          'pre_sap_execution_standard',
          'payment_execution'
      )

),

measured_spans as (

    select
        s.sap_inv_key,
        s.phase_level,
        s.phase_code,
        s.span_seq,
        s.span_start_date,
        s.span_end_date,
        inv.discount_deadline_date,
        inv.clearing_date,
        inv.allocation_regime,
        greatest(
            0,
            datediff(
                'day',
                s.span_start_date,
                least(s.span_end_date, inv.discount_deadline_date)
            )
        ) as span_visit_weight_days
    from {{ ref('ap_core', 'fct_inv_timing_span') }} s
    inner join timing_invoices inv
        on s.sap_inv_key = inv.sap_inv_key
    where s.span_status = 'measured'

),

pre_posting_phase_weights as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        sum(span_visit_weight_days) as phase_weight_days
    from measured_spans
    where allocation_regime = 'pre_posting'
      and phase_level = 'subprocess'
      and phase_code in ('intake', 'verification', 'approval', 'interface')
    group by
        sap_inv_key,
        phase_level,
        phase_code

),

pre_posting_eligibility as (

    select
        sap_inv_key,
        count(*) as measured_phase_count,
        sum(phase_weight_days) as total_weight_days
    from pre_posting_phase_weights
    group by sap_inv_key
    having count(*) = 4

),

pre_posting_phase_eur_base as (

    select
        w.sap_inv_key,
        w.phase_level,
        w.phase_code,
        w.phase_weight_days,
        inv.lost_discount_amount,
        inv.post_deadline_days,
        round(
            inv.lost_discount_amount * w.phase_weight_days::float
            / e.total_weight_days,
            2
        ) as phase_eur_raw
    from pre_posting_phase_weights w
    inner join pre_posting_eligibility e
        on w.sap_inv_key = e.sap_inv_key
    inner join timing_invoices inv
        on w.sap_inv_key = inv.sap_inv_key
    where inv.allocation_regime = 'pre_posting'
      and e.total_weight_days > 0

),

pre_posting_phase_eur as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        lost_discount_amount,
        post_deadline_days,
        case
            when row_number() over (
                partition by sap_inv_key
                order by phase_weight_days desc, phase_code
            ) = 1
            then round(
                phase_eur_raw
                + (
                    lost_discount_amount
                    - sum(phase_eur_raw) over (partition by sap_inv_key)
                ),
                2
            )
            else phase_eur_raw
        end as phase_eur
    from pre_posting_phase_eur_base

),

payment_phase_eur as (

    select
        inv.sap_inv_key,
        'ownership' as phase_level,
        'payment' as phase_code,
        inv.post_deadline_days as phase_weight_days,
        inv.lost_discount_amount as phase_eur,
        inv.post_deadline_days
    from timing_invoices inv
    where inv.allocation_regime = 'payment'

),

phase_eur as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        phase_eur,
        post_deadline_days
    from payment_phase_eur

    union all

    select
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        phase_eur,
        post_deadline_days
    from pre_posting_phase_eur

),

intake_interface_buckets as (

    select
        p.sap_inv_key,
        p.phase_level,
        p.phase_code,
        case p.phase_code
            when 'intake' then 'intake_delay'
            when 'interface' then 'interface_delay'
        end as bucket_code,
        p.phase_weight_days as gross_exposure_days,
        p.phase_eur as priority_allocated_eur,
        p.post_deadline_days
    from phase_eur p
    where p.phase_code in ('intake', 'interface')

),

overlay_clipped as (

    select
        inv.sap_inv_key,
        p.phase_level,
        p.phase_code,
        p.phase_weight_days,
        p.phase_eur,
        p.post_deadline_days,
        os.overlay_reason_code,
        os.overlap_start_date,
        os.overlap_end_date,
        case
            when p.phase_level = 'ownership' and p.phase_code = 'payment' then
                greatest(
                    os.overlap_start_date,
                    inv.discount_deadline_date
                )
            else
                greatest(
                    os.overlap_start_date,
                    os.span_start_date
                )
        end as clip_start_date,
        case
            when p.phase_level = 'ownership' and p.phase_code = 'payment' then
                least(
                    os.overlap_end_date,
                    inv.clearing_date
                )
            else
                least(
                    os.overlap_end_date,
                    os.span_end_date,
                    inv.discount_deadline_date
                )
        end as clip_end_date
    from phase_eur p
    inner join timing_invoices inv
        on p.sap_inv_key = inv.sap_inv_key
    inner join {{ ref('fct_inv_timing_overlay_span') }} os
        on p.sap_inv_key = os.sap_inv_key
        and p.phase_level = os.phase_level
        and p.phase_code = os.phase_code
    where p.phase_code in ('verification', 'approval', 'payment')

),

overlay_gross_by_bucket as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        phase_eur,
        post_deadline_days,
        overlay_reason_code as bucket_code,
        sum(
            greatest(
                0,
                datediff('day', clip_start_date, clip_end_date)
            )
        ) as gross_exposure_days
    from overlay_clipped
    where clip_start_date < clip_end_date
    group by
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        phase_eur,
        post_deadline_days,
        overlay_reason_code

),

overlay_gross_totals as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        phase_eur,
        post_deadline_days,
        coalesce(sum(gross_exposure_days), 0) as total_blocker_gross_days
    from overlay_gross_by_bucket
    group by
        sap_inv_key,
        phase_level,
        phase_code,
        phase_weight_days,
        phase_eur,
        post_deadline_days

),

phases_needing_blocker_buckets as (

    select
        p.sap_inv_key,
        p.phase_level,
        p.phase_code,
        p.phase_weight_days,
        p.phase_eur,
        p.post_deadline_days
    from phase_eur p
    where p.phase_code in ('verification', 'approval', 'payment')

),

blocker_bucket_base as (

    select
        ph.sap_inv_key,
        ph.phase_level,
        ph.phase_code,
        b.bucket_code,
        coalesce(b.gross_exposure_days, 0) as gross_exposure_days,
        ph.phase_weight_days,
        ph.phase_eur,
        ph.post_deadline_days,
        coalesce(t.total_blocker_gross_days, 0) as total_blocker_gross_days
    from phases_needing_blocker_buckets ph
    left join overlay_gross_totals t
        on ph.sap_inv_key = t.sap_inv_key
        and ph.phase_level = t.phase_level
        and ph.phase_code = t.phase_code
    left join overlay_gross_by_bucket b
        on ph.sap_inv_key = b.sap_inv_key
        and ph.phase_level = b.phase_level
        and ph.phase_code = b.phase_code

),

blocker_bucket_eur as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        bucket_code,
        gross_exposure_days,
        post_deadline_days,
        case
            when bucket_code is null then null
            when phase_weight_days = 0 then 0
            when total_blocker_gross_days <= phase_weight_days then
                round(phase_eur * gross_exposure_days::float / phase_weight_days, 2)
            when total_blocker_gross_days > 0 and gross_exposure_days > 0 then
                round(phase_eur * gross_exposure_days::float / total_blocker_gross_days, 2)
            else 0
        end as priority_allocated_eur
    from blocker_bucket_base
    where bucket_code is not null
      and gross_exposure_days > 0

),

blocker_gap as (

    select
        ph.sap_inv_key,
        ph.phase_level,
        ph.phase_code,
        greatest(
            0,
            ph.phase_weight_days - coalesce(t.total_blocker_gross_days, 0)
        ) as gap_days,
        ph.phase_weight_days,
        ph.phase_eur,
        ph.post_deadline_days,
        coalesce(t.total_blocker_gross_days, 0) as total_blocker_gross_days
    from phases_needing_blocker_buckets ph
    left join overlay_gross_totals t
        on ph.sap_inv_key = t.sap_inv_key
        and ph.phase_level = t.phase_level
        and ph.phase_code = t.phase_code

),

no_recorded_blocker_rows as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        'no_recorded_blocker' as bucket_code,
        gap_days as gross_exposure_days,
        post_deadline_days,
        case
            when gap_days > 0 and phase_weight_days > 0
                 and total_blocker_gross_days <= phase_weight_days then
                round(phase_eur * gap_days::float / phase_weight_days, 2)
            else 0
        end as priority_allocated_eur
    from blocker_gap
    where gap_days > 0

),

unallocated_rows as (

    select
        inv.sap_inv_key,
        'unallocated' as phase_level,
        'unallocated' as phase_code,
        'unallocated' as bucket_code,
        cast(null as integer) as gross_exposure_days,
        inv.post_deadline_days,
        inv.lost_discount_amount as priority_allocated_eur
    from timing_invoices inv
    inner join pre_posting_eligibility e
        on inv.sap_inv_key = e.sap_inv_key
    where inv.allocation_regime = 'pre_posting'
      and e.total_weight_days = 0

),

allocated_union as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        bucket_code,
        gross_exposure_days,
        priority_allocated_eur,
        post_deadline_days
    from intake_interface_buckets
    where priority_allocated_eur > 0

    union all

    select
        sap_inv_key,
        phase_level,
        phase_code,
        bucket_code,
        gross_exposure_days,
        priority_allocated_eur,
        post_deadline_days
    from blocker_bucket_eur
    where priority_allocated_eur > 0

    union all

    select
        sap_inv_key,
        phase_level,
        phase_code,
        bucket_code,
        gross_exposure_days,
        priority_allocated_eur,
        post_deadline_days
    from no_recorded_blocker_rows
    where priority_allocated_eur > 0

    union all

    select
        sap_inv_key,
        phase_level,
        phase_code,
        bucket_code,
        gross_exposure_days,
        priority_allocated_eur,
        post_deadline_days
    from unallocated_rows
    where priority_allocated_eur > 0

),

allocated_with_residual as (

    select
        u.sap_inv_key,
        u.phase_level,
        u.phase_code,
        u.bucket_code,
        u.gross_exposure_days,
        u.post_deadline_days,
        case
            when row_number() over (
                partition by u.sap_inv_key
                order by u.priority_allocated_eur desc, u.phase_code, u.bucket_code
            ) = 1
            then round(
                u.priority_allocated_eur
                + (
                    inv.lost_discount_amount
                    - sum(u.priority_allocated_eur) over (partition by u.sap_inv_key)
                ),
                2
            )
            else u.priority_allocated_eur
        end as priority_allocated_eur
    from allocated_union u
    inner join timing_invoices inv
        on inv.sap_inv_key = u.sap_inv_key

)

select
    sap_inv_key,
    phase_level,
    phase_code,
    bucket_code,
    gross_exposure_days,
    priority_allocated_eur,
    post_deadline_days
from allocated_with_residual
where priority_allocated_eur > 0