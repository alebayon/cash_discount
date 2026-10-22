-- every fact overlay_reason_code must exist in seed_timing_overlay_reason_map
select distinct
    o.overlay_reason_code
from {{ ref('fct_inv_timing_overlay_cd') }} o
left join {{ ref('seed_timing_overlay_reason_map') }} m
    on o.overlay_reason_code = m.overlay_reason_code
where m.overlay_reason_code is null