-- not_measurable is a standing guard; expect zero rows on current seed
select
    sap_inv_key,
    phase_code,
    span_status
from {{ ref('fct_inv_timing_span') }}
where span_status = 'not_measurable'