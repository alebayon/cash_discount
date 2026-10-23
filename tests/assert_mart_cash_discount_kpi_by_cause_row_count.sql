-- One row per leakage primary_cause; 6 after arbitration removed structural_terms hero (5100000016).
select count(*) as row_count
from {{ ref('mart_cash_discount_kpi_by_cause') }}
having count(*) != 6