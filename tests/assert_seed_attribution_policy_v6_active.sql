-- D83: one active policy row; V6 parameters 4 / 7 / 3
with active as (
    select
        attribution_policy_version,
        minimum_processing_days,
        standard_processing_days,
        minimum_payment_runway_days
    from {{ ref('seed_attribution_policy') }}
    where is_active
),
violations as (
    select 'not_exactly_one_active_row' as violation
    from active
    having count(*) != 1

    union all

    select 'active_not_v6_or_wrong_thresholds' as violation
    from active
    where attribution_policy_version is distinct from 'v6'
       or minimum_processing_days is distinct from 4
       or standard_processing_days is distinct from 7
       or minimum_payment_runway_days is distinct from 3
       or standard_processing_days < minimum_processing_days
       or minimum_processing_days <= 0
       or minimum_payment_runway_days <= 0
)
select violation
from violations