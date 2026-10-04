-- D64/D65: derived payment_run_wait tail after block release (policy A)
select
    s.doc_number,
    o.overlay_reason_code,
    o.interval_seq,
    o.interval_start_date,
    o.interval_end_date,
    o.interval_days
from {{ ref('fct_inv_sap') }} s
inner join {{ ref('fct_inv_timing_overlay') }} o
    on s.sap_inv_key = o.sap_inv_key
where s.doc_number = '5100000025'
  and o.overlay_reason_code = 'payment_run_wait'
  and not (
      o.interval_seq = 1
      and o.interval_start_date = '2024-11-18'
      and o.interval_end_date = '2024-11-25'
      and o.interval_days = 7
  )