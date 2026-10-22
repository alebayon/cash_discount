-- 5100000018: V6 Rule 4 pre_sap_execution_compressed (processing_available_days=4, runway<3)
select doc_number
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000018'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'pre_sap_execution_compressed'
      or primary_cause_group is distinct from 'timing'
      or primary_owner is distinct from 'pre_sap'
      or lost_discount_amount is distinct from 12.00
      or available_days is distinct from 7
      or processing_available_days is distinct from 4
      or runway_at_handoff is distinct from 1
      or pre_sap_elapsed_days is distinct from 6
      or intake_condition is distinct from 'compressed'
      or handoff_condition is distinct from 'reserve_not_met'
      or actual_cycle_days is distinct from 11
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from true
      or is_timing_contributor is distinct from false
  )