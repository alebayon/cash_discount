-- 6 seed + 3 derived payment_run_wait (timing leakage only, D64 A) + 1 derived payment_block
select count(*) as row_count
from {{ ref('fct_inv_timing_overlay') }}
having count(*) != 10