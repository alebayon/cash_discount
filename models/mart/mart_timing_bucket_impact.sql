{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

with allocation as (

    select *
    from {{ ref('fct_inv_timing_allocation') }}
    where phase_level is distinct from 'unallocated'

),

bucket_agg as (

    select
        '{{ period_start }}'::date as reporting_period_start,
        '{{ period_end }}'::date as reporting_period_end,
        phase_level,
        phase_code,
        bucket_code,
        count(distinct sap_inv_key) as invoice_count,
        sum(gross_exposure_days) as gross_exposure_days,
        round(sum(priority_allocated_eur), 2) as priority_allocated_eur
    from allocation
    group by
        phase_level,
        phase_code,
        bucket_code

),

with_phase_totals as (

    select
        b.*,
        sum(b.priority_allocated_eur) over (
            partition by
                b.reporting_period_start,
                b.reporting_period_end,
                b.phase_level,
                b.phase_code
        ) as phase_priority_allocated_eur
    from bucket_agg b

),

with_shares as (

    select
        *,
        case
            when phase_priority_allocated_eur = 0 then 0
            else round(
                priority_allocated_eur / phase_priority_allocated_eur,
                6
            )
        end as eur_share_of_phase
    from with_phase_totals

),

ranked as (

    select
        *,
        row_number() over (
            partition by
                reporting_period_start,
                reporting_period_end,
                phase_level,
                phase_code
            order by
                priority_allocated_eur desc,
                case bucket_code
                    when 'inv_dispute' then 1
                    when 'rework' then 2
                    when 'on_hold' then 3
                    else 99
                end,
                bucket_code
        ) as bucket_rank
    from with_shares

),

with_cumulative as (

    select
        *,
        round(
            sum(eur_share_of_phase) over (
                partition by
                    reporting_period_start,
                    reporting_period_end,
                    phase_level,
                    phase_code
                order by bucket_rank
                rows between unbounded preceding and current row
            ),
            6
        ) as cumulative_eur_share
    from ranked

),

with_action as (

    select
        *,
        case
            when cumulative_eur_share - eur_share_of_phase < 0.75 then 'ACT'
            else 'WATCH'
        end as action_status,
        case bucket_code
            when 'payment_run_wait' then 'payment run'
            when 'payment_block' then 'payment run'
            when 'no_recorded_blocker' then 'investigate unlabeled days'
            when 'rework' then 'remove rework'
            when 'inv_dispute' then 'resolve dispute'
            when 'on_hold' then 'release hold'
            when 'intake_delay' then 'remove intake delay'
            when 'interface_delay' then 'remove interface delay'
        end as owner_role
    from with_cumulative

)

select
    reporting_period_start,
    reporting_period_end,
    phase_level,
    phase_code,
    bucket_code,
    invoice_count,
    gross_exposure_days,
    priority_allocated_eur,
    eur_share_of_phase,
    cumulative_eur_share,
    action_status,
    owner_role
from with_action
order by
    phase_level,
    phase_code,
    bucket_rank