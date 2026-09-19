-- PK: (sap_inv_key, phase_level, phase_code, span_seq)
select
    sap_inv_key,
    phase_level,
    phase_code,
    span_seq,
    count(*) as row_count
from {{ ref('fct_inv_timing_span') }}
group by
    sap_inv_key,
    phase_level,
    phase_code,
    span_seq
having count(*) > 1