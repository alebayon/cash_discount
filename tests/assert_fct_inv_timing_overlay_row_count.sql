-- 4 rows: curriculum overlay intervals on 5100000003, 0008, 0019, 0020
select count(*) as row_count
from {{ ref('fct_inv_timing_overlay') }}
having count(*) != 8