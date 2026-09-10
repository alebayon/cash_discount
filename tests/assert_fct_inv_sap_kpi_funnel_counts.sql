-- test to count number of cases in kpi_entitled and is taken nodes
select *
from (
    select
        count(*) as row_count,
        sum(case when is_kpi_entitled then 1 else 0 end) as kpi_entitled,
        sum(case when is_taken then 1 else 0 end) as taken_true,
        sum(case when is_kpi_entitled and not is_taken then 1 else 0 end) as taken_false
    from {{ ref('fct_inv_sap') }}
) actual
where row_count != 11
   or kpi_entitled != 5
   or taken_true != 3
   or taken_false != 2