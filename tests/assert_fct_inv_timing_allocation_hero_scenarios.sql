-- D49: payment-regime timing heroes
select
    s.doc_number,
    a.phase_level,
    a.phase_code,
    a.bucket_code,
    a.gross_exposure_days,
    a.priority_allocated_eur
from {{ ref('fct_inv_sap') }} s
inner join {{ ref('fct_inv_timing_allocation') }} a
    on s.sap_inv_key = a.sap_inv_key
where s.doc_number in ('5100000003', '5100000019')
  and not (
      (s.doc_number = '5100000003'
       and a.phase_level = 'ownership'
       and a.phase_code = 'payment'
       and a.bucket_code = 'payment_run_wait'
       and a.gross_exposure_days = 14
       and a.priority_allocated_eur = 17.80)
      or
      (s.doc_number = '5100000019'
       and a.phase_level = 'ownership'
       and a.phase_code = 'payment'
       and a.bucket_code = 'no_recorded_blocker'
       and a.gross_exposure_days = 11
       and a.priority_allocated_eur = 11.00)
  )