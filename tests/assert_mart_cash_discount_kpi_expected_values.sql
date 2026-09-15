select *
from {{ ref('mart_cash_discount_kpi') }}
where fct_row_count != 20
   or kpi_entitled_count != 12
   or taken_count != 3
   or excluded_count != 1
   or leakage_count != 8
   or leakage_eur != 123.20
   or discount_opportunity_eur != 288.21
   or round(leakage_rate, 4) != 0.4275