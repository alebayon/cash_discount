-- 5100000016: Z205 fails arbitration (acceleration > 20 days); not KPI leakage
select doc_number
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000016'
  and (
      is_cd_eligible is distinct from false
      or not_cd_eligible_reason is distinct from 'cash_acceleration_exceeds_maximum'
      or is_kpi_entitled is distinct from false
      or is_leakage is not null
      or primary_cause is not null
  )