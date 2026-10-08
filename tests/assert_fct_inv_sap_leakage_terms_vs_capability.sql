-- 5100000016: V6 Rule 2 structural_terms_vs_capability (Z205, discount_days=5)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000016'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'structural_terms_vs_capability'
      or primary_cause_group is distinct from 'structural'
      or primary_owner is distinct from 'procurement_contracts'
      or lost_discount_amount is distinct from 20.00
      or available_days is distinct from 15
      or processing_available_days is distinct from 12
      or pre_sap_elapsed_days is distinct from 5
      or pre_sap_exceeded_standard is distinct from false
      or actual_cycle_days is distinct from 20
      or terms_condition is distinct from 'terms_below_minimum'
      or is_still_feasible is distinct from true
      or requires_expedited_processing is distinct from false
      or is_timing_contributor is distinct from false
  )