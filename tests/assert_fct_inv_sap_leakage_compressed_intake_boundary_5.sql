-- 5100000018: Rule 4 structural_compressed_intake at boundary available_days=5
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000018'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'structural_compressed_intake'
      or primary_cause_group is distinct from 'structural'
      or lost_discount_amount is distinct from 12.00
      or available_days is distinct from 5
      or actual_cycle_days is distinct from 9
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from true
      or is_timing_contributor is distinct from false
  )