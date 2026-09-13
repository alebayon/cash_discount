select *
from {{ ref('mart_cash_discount_kpi') }}
where fct_row_count != 14
   or kpi_entitled_count != 6
   or taken_count != 3
   or excluded_count != 1
   or leakage_count != 2
   or leakage_eur != 31.20
   or discount_opportunity_eur != 196.21
   or round(leakage_rate, 4) != 0.1590