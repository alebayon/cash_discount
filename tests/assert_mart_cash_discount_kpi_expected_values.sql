select *
from {{ ref('mart_cash_discount_kpi') }}
where fct_row_count != 25
   or kpi_entitled_count != 16
   or taken_count != 3
   or excluded_count != 1
   or leakage_count != 12
   or leakage_eur != 190.20
   or discount_opportunity_eur != 355.21
   or round(leakage_rate, 4) is distinct from round(
       leakage_eur / nullif(discount_opportunity_eur, 0), 4
   )
