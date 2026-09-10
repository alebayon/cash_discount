-- test to capture is_taken out of kpi_entitled funnel
select *
from {{ ref('fct_inv_sap') }}
where is_taken is not null
  and not is_kpi_entitled