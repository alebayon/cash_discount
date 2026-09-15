-- 5100000021: Rule 0 data_quality_error (SAP-only, receipt_date null)
select doc_number
from {{ ref('fct_inv_sap') }}
where doc_number = '5100000021'
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from 'data_quality_error'
      or primary_cause_group is distinct from 'unclassified'
      or lost_discount_amount is distinct from 18.00
      or receipt_date is not null
      or available_days is not null
      or is_still_feasible is not null
      or requires_expedited_processing is not null
      or is_timing_contributor is not null
      or sap_ref_key is not null
  )