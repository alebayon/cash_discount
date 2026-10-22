-- is_excluded must be null outside kpi_entitled and not is_taken
select doc_number, is_kpi_entitled, is_taken, is_excluded
from {{ ref('fct_inv_sap_cd') }}
where is_excluded is not null
  and not (is_kpi_entitled and not is_taken)