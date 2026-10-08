-- 5100000018: timing-group compressed — allocation reconciles to lost discount
select s.doc_number
from {{ ref('fct_inv_sap') }} s
where s.doc_number = '5100000018'
  and (
      s.is_leakage is distinct from true
      or s.primary_cause is distinct from 'pre_sap_execution_compressed'
      or (
          select round(sum(priority_allocated_eur), 2)
          from {{ ref('fct_inv_timing_allocation') }} t
          where t.sap_inv_key = s.sap_inv_key
      ) is distinct from 12.00
  )