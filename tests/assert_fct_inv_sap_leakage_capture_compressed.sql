-- 5100000020: Rule 1 capture wins despite compressed intake (available_days=7)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000020'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'capture'
      or primary_cause_group is distinct from 'capture'
      or lost_discount_amount is distinct from 15.00
      or available_days is distinct from 7
      or is_still_feasible is not null
      or requires_expedited_processing is not null
      or is_timing_contributor is not null
  )