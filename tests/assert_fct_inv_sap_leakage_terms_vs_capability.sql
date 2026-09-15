-- 5100000016: Rule 2 structural_terms_vs_capability (Z205, discount_days=5)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000016'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'structural_terms_vs_capability'
      or primary_cause_group is distinct from 'structural'
      or lost_discount_amount is distinct from 20.00
      or available_days is distinct from 15
      or actual_cycle_days is distinct from 20
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from true
  )