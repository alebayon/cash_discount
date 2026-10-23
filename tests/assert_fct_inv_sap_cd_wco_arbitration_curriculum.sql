-- CD/WCO arbitration v1 curriculum (Z205 acceleration hero)
select doc_number, is_cd_eligible, not_cd_eligible_reason, is_kpi_entitled, is_leakage
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000016'
  and (
      is_cd_eligible is distinct from false
      or not_cd_eligible_reason is distinct from 'cash_acceleration_exceeds_maximum'
      or is_kpi_entitled is distinct from false
      or is_leakage is not null
  )

union all

-- Structural fail: arbitration reason must stay null (5100000015 no baseline)
select doc_number, is_cd_eligible, not_cd_eligible_reason, is_kpi_entitled, is_leakage
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000015'
  and (
      not_cd_eligible_reason is not null
      or is_cd_eligible is not null
      or is_kpi_entitled is distinct from false
  )