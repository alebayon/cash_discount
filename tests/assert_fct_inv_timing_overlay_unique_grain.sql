-- PK: (sap_inv_key, overlay_reason_code, interval_seq)
select
    sap_inv_key,
    overlay_reason_code,
    interval_seq,
    count(*) as row_count
from {{ ref('fct_inv_timing_overlay_cd') }}
group by
    sap_inv_key,
    overlay_reason_code,
    interval_seq
having count(*) > 1