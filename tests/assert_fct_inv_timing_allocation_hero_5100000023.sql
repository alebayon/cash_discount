-- Curriculum v2: pre_sap_execution_standard with verification inv_dispute (D75)
select s.doc_number
from {{ ref('fct_inv_sap') }} s
where s.doc_number = '5100000023'
  and (
      s.is_leakage is distinct from true
      or s.primary_cause is distinct from 'pre_sap_execution_standard'
      or s.primary_cause_group is distinct from 'timing'
      or s.lost_discount_amount is distinct from 16.00
      or not exists (
          select 1
          from {{ ref('fct_inv_timing_allocation') }} a
          where a.sap_inv_key = s.sap_inv_key
            and a.phase_code = 'verification'
            and a.bucket_code = 'inv_dispute'
            and a.gross_exposure_days = 3
            and a.priority_allocated_eur > 0
      )
      or (
          select round(sum(priority_allocated_eur), 2)
          from {{ ref('fct_inv_timing_allocation') }} t
          where t.sap_inv_key = s.sap_inv_key
      ) is distinct from 16.00
  )