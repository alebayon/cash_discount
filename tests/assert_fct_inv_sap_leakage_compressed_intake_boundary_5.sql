-- 5100000018: V6 Rule 3 structural_insufficient_time_at_intake (processing_available_days=2)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000018'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'structural_insufficient_time_at_intake'
      or primary_cause_group is distinct from 'structural'
      or primary_owner is distinct from 'upstream_intake'
      or lost_discount_amount is distinct from 12.00
      or available_days is distinct from 5
      or processing_available_days is distinct from 2
      or actual_cycle_days is distinct from 9
      or is_still_feasible is distinct from false
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from false
  )