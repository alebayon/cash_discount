select *
from {{ ref('mart_cash_discount_kpi') }}
where fct_row_count != 21
   or kpi_entitled_count != 13
   or taken_count != 3
   or excluded_count != 1
   or leakage_count != 9
   or leakage_eur != 143.20
   or discount_opportunity_eur != 308.21
   or round(leakage_rate, 4) != 0.4646