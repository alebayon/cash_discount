-- D64: payment phase gap is fully payment_run_wait + payment_block
select *
from {{ ref('fct_inv_timing_allocation') }}
where phase_level = 'ownership'
  and phase_code = 'payment'
  and bucket_code = 'no_recorded_blocker'