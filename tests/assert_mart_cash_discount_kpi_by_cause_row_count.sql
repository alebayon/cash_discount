-- One row per leakage primary_cause (7 V6 buckets on curriculum leakage)
select count(*) as row_count
from {{ ref('mart_cash_discount_kpi_by_cause') }}
having count(*) != 7
