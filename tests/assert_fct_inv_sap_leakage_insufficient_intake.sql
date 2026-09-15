-- 5100000017: Rule 3 structural_insufficient_time_at_intake (available_days=3)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000017'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'structural_insufficient_time_at_intake'
      or primary_cause_group is distinct from 'structural'
      or lost_discount_amount is distinct from 16.00
      or available_days is distinct from 3
      or actual_cycle_days is distinct from 8
      or is_still_feasible is distinct from false
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from false
  )