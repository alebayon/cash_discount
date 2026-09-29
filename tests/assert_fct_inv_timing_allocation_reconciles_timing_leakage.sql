-- D50: portfolio sum equals mart_cash_discount_kpi_by_cause timing leakage_eur
with allocated as (
    select round(sum(priority_allocated_eur), 2) as total_allocated_eur
    from {{ ref('fct_inv_timing_allocation') }}
),
timing_kpi as (
    select leakage_eur
    from {{ ref('mart_cash_discount_kpi_by_cause') }}
    where primary_cause = 'timing'
)
select
    a.total_allocated_eur,
    k.leakage_eur
from allocated a
cross join timing_kpi k
where a.total_allocated_eur is distinct from k.leakage_eur