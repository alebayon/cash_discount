with by_cause as (
    select
        sum(leakage_count) as leakage_count,
        sum(leakage_eur) as leakage_eur
    from {{ ref('mart_cash_discount_kpi_by_cause') }}
),
headline as (
    select leakage_count, leakage_eur
    from {{ ref('mart_cash_discount_kpi') }}
)
select 1
from by_cause b
cross join headline h
where b.leakage_count != h.leakage_count
   or b.leakage_eur != h.leakage_eur