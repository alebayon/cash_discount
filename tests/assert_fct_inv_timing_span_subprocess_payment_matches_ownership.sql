-- D28: subprocess payment must match ownership payment per sap_inv_key
select
    o.sap_inv_key,
    o.span_status as ownership_status,
    p.span_status as subprocess_status,
    o.span_start_date as ownership_start,
    p.span_start_date as subprocess_start,
    o.span_end_date as ownership_end,
    p.span_end_date as subprocess_end,
    o.span_days as ownership_days,
    p.span_days as subprocess_days
from {{ ref('fct_inv_timing_span') }} o
inner join {{ ref('fct_inv_timing_span') }} p
    on o.sap_inv_key = p.sap_inv_key
where o.phase_level = 'ownership'
  and o.phase_code = 'payment'
  and p.phase_level = 'subprocess'
  and p.phase_code = 'payment'
  and (
      o.span_status <> p.span_status
      or o.span_start_date <> p.span_start_date
      or o.span_end_date is distinct from p.span_end_date
      or o.span_days is distinct from p.span_days
  )