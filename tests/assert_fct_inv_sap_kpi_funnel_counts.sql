-- test to count number of cases in kpi funnel nodes
select *
from (
    select
        count(*) as row_count,
        sum(case when is_kpi_entitled then 1 else 0 end) as kpi_entitled,
        sum(case when is_taken then 1 else 0 end) as taken_true,
        sum(case when is_kpi_entitled and not is_taken then 1 else 0 end) as not_taken,
        sum(case when is_excluded then 1 else 0 end) as excluded_true,
        sum(case when is_leakage then 1 else 0 end) as leakage_true,
        round(sum(case when is_leakage then lost_discount_amount else 0 end), 2) as leakage_amount_total
    from {{ ref('fct_inv_sap') }}
) actual
where row_count != 20
   or kpi_entitled != 12
   or taken_true != 3
   or not_taken != 9
   or excluded_true != 1
   or leakage_true != 8
   or leakage_amount_total != 123.20