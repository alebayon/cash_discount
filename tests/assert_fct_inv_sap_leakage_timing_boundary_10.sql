-- 5100000019: payment_execution at available_days=10 (standard combined window)
select doc_number
from {{ ref('fct_inv_sap_cd') }}
where doc_number = '5100000019'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'payment_execution'
      or primary_cause_group is distinct from 'timing'
      or primary_owner is distinct from 'payment'
      or lost_discount_amount is distinct from 11.00
      or available_days is distinct from 10
      or processing_available_days is distinct from 7
      or actual_cycle_days is distinct from 21
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from true
  )