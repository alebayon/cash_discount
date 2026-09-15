-- hero timing leakage: secondary flags on structural/timing path
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000003'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'timing'
      or primary_cause_group is distinct from 'timing'
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from true
      or available_days is distinct from 13
      or actual_cycle_days is distinct from 27
  )