-- D50 / D89: allocation sum equals timing-group leakage (three V6 causes)
with allocated as (
    select round(sum(priority_allocated_eur), 2) as total_allocated_eur
    from {{ ref('fct_inv_timing_allocation') }}
),
timing_kpi as (
    select round(sum(leakage_eur), 2) as leakage_eur
    from {{ ref('mart_cash_discount_kpi_by_cause') }}
    where primary_cause_group = 'timing'
)
select
    a.total_allocated_eur,
    k.leakage_eur
from allocated a
cross join timing_kpi k
where a.total_allocated_eur is distinct from k.leakage_eur