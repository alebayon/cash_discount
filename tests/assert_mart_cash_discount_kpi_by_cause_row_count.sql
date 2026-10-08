select count(*) as row_count
from {{ ref('mart_cash_discount_kpi_by_cause') }}
having count(*) != 7