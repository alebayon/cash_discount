-- span_days must be >= 0 on measured spans
select
    sap_inv_key,
    phase_code,
    span_days
from {{ ref('fct_inv_timing_span') }}
where span_status = 'measured'
  and span_days < 0