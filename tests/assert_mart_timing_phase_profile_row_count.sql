-- one row per ownership phase for default 2024 reporting period
select count(*) as row_count
from {{ ref('mart_timing_phase_profile') }}
having count(*) != 7