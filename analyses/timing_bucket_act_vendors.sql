with act_buckets as (

    select
        reporting_period_start,
        reporting_period_end,
        phase_level,
        phase_code,
        bucket_code,
        owner_role
    from {{ ref('mart_timing_bucket_impact') }}
    where action_status = 'ACT'

),

vendor_bucket as (

    select
        b.reporting_period_start,
        b.reporting_period_end,
        b.phase_level,
        b.phase_code,
        b.bucket_code,
        b.owner_role,
        s.vendor_id,
        round(sum(a.priority_allocated_eur), 2) as priority_allocated_eur
    from act_buckets b
    inner join {{ ref('fct_inv_timing_allocation') }} a
        on b.phase_level = a.phase_level
        and b.phase_code = a.phase_code
        and b.bucket_code = a.bucket_code
    inner join {{ ref('fct_inv_sap_cd') }} s
        on a.sap_inv_key = s.sap_inv_key
    group by
        b.reporting_period_start,
        b.reporting_period_end,
        b.phase_level,
        b.phase_code,
        b.bucket_code,
        b.owner_role,
        s.vendor_id

),

with_share as (

    select
        *,
        sum(priority_allocated_eur) over (
            partition by
                reporting_period_start,
                reporting_period_end,
                phase_level,
                phase_code,
                bucket_code
        ) as bucket_total_eur
    from vendor_bucket

)

select
    reporting_period_start,
    reporting_period_end,
    phase_level,
    phase_code,
    bucket_code,
    owner_role,
    vendor_id,
    priority_allocated_eur,
    bucket_total_eur,
    priority_allocated_eur / nullif(bucket_total_eur, 0) >= 0.6 as is_concentrated
from with_share
order by
    phase_level,
    phase_code,
    bucket_code,
    priority_allocated_eur desc