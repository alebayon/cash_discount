-- D58/D60: SAP-derived payment_block matches curriculum v2 window
select
    s.doc_number,
    o.overlay_reason_code,
    o.interval_seq,
    o.interval_start_date,
    o.interval_end_date,
    o.interval_days,
    o.source_system,
    o.source_change_id
from {{ ref('fct_inv_sap_cd') }} s
inner join {{ ref('fct_inv_timing_overlay_cd') }} o
    on s.sap_inv_key = o.sap_inv_key
where s.doc_number = '5100000025'
  and o.overlay_reason_code = 'payment_block'
  and not (
      o.interval_seq = 1
      and o.interval_start_date = '2024-11-11'
      and o.interval_end_date = '2024-11-18'
      and o.interval_days = 7
      and o.source_system = 'sap'
      and o.source_change_id = '4900000101'
  )