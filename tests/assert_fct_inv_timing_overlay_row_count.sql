-- 6 seed + 3 derived payment_run_wait (timing leakage only, D64 A) + 2 derived payment_block (5100000025 + OTP 5100000031)
select count(*) as row_count
from {{ ref('fct_inv_timing_overlay_cd') }}
having count(*) != 11