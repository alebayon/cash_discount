-- every Version 5 primary_cause bucket represented on at least one leakage row
with expected_buckets as (
    select column1 as primary_cause
    from values
        ('data_quality_error'),
        ('capture'),
        ('structural_terms_vs_capability'),
        ('structural_insufficient_time_at_intake'),
        ('structural_compressed_intake'),
        ('timing')
),
actual_buckets as (
    select distinct primary_cause
    from {{ ref('fct_inv_sap') }}
    where is_leakage
)
select e.primary_cause
from expected_buckets e
left join actual_buckets a
    on e.primary_cause = a.primary_cause
where a.primary_cause is null