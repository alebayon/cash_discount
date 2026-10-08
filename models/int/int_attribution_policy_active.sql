select
    attribution_policy_version,
    minimum_processing_days,
    standard_processing_days,
    minimum_payment_runway_days
from {{ ref('seed_attribution_policy') }}
where is_active