-- 102 subprocess rows: 20 x 5 base + 2 rework extras on 5100000020
select count(*) as row_count
from {{ ref('fct_inv_timing_span') }}
where phase_level = 'subprocess'
having count(*) != 102