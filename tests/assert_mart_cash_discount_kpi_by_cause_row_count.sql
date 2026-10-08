-- Six causes on leakage; pre_sap_execution_compressed omitted until curriculum hero (D90)
select count(*) as row_count
from {{ ref('mart_cash_discount_kpi_by_cause') }}
having count(*) != 6