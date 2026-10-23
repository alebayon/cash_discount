-- 5100000026: Z205 acceleration > 20 days; arbitration-out, not KPI leakage
select doc_number, is_cd_eligible, not_cd_eligible_reason, is_kpi_entitled, is_leakage
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000026'
  and (
      is_cd_eligible is distinct from false
      or not_cd_eligible_reason is distinct from 'cash_acceleration_exceeds_maximum'
      or is_kpi_entitled is distinct from false
      or is_leakage is not null
  )

union all

-- 5100000015: baseline OK, potential discount below €10 minimum
select doc_number, is_cd_eligible, not_cd_eligible_reason, is_kpi_entitled, is_leakage
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000015'
  and (
      is_cd_eligible is distinct from false
      or not_cd_eligible_reason is distinct from 'potential_discount_below_minimum'
      or is_kpi_entitled is distinct from false
      or is_leakage is not null
  )
