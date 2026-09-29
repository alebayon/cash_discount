-- PK: (sap_inv_key, phase_level, phase_code, bucket_code)
select
    sap_inv_key,
    phase_level,
    phase_code,
    bucket_code,
    count(*) as row_count
from {{ ref('fct_inv_timing_allocation') }}
group by
    sap_inv_key,
    phase_level,
    phase_code,
    bucket_code
having count(*) > 1