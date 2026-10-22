-- 5100000003: payment_execution hero (V6)
select doc_number
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000003'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'payment_execution'
      or primary_cause_group is distinct from 'timing'
      or primary_owner is distinct from 'payment'
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from true
      or available_days is distinct from 13
      or processing_available_days is distinct from 10
      or attribution_policy_version is distinct from 'v6'
  )