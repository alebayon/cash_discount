-- 5100000019: Rule 5 timing at boundary available_days=10 (not compressed)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000019'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'timing'
      or primary_cause_group is distinct from 'timing'
      or lost_discount_amount is distinct from 11.00
      or available_days is distinct from 10
      or actual_cycle_days is distinct from 21
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from true
  )