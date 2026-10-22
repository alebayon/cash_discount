-- D89: derived payment_run_wait only for payment_execution (not pre-SAP execution causes)
select
    s.doc_number,
    s.primary_cause,
    o.overlay_reason_code
from {{ ref('fct_inv_timing_overlay') }} o
inner join {{ ref('fct_inv_sap_cd') }} s
    on o.sap_inv_key = s.sap_inv_key
where o.overlay_reason_code = 'payment_run_wait'
  and s.primary_cause in (
      'pre_sap_execution_compressed',
      'pre_sap_execution_standard'
  )