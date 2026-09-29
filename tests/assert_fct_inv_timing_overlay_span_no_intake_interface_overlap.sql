-- D49: overlay bridge must not overlap intake or interface subprocess spans
select
    sap_inv_key,
    overlay_reason_code,
    phase_level,
    phase_code,
    reason_exposure_days
from {{ ref('fct_inv_timing_overlay_span') }}
where phase_code in ('intake', 'interface')