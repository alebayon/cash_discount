select *
from {{ ref('mart_cash_discount_kpi') }}
where fct_row_count != 22
   or kpi_entitled_count != 14
   or taken_count != 3
   or excluded_count != 1
   or leakage_count != 10
   or leakage_eur != 159.20
   or discount_opportunity_eur != 324.21
   or round(leakage_rate, 4) != 0.4910