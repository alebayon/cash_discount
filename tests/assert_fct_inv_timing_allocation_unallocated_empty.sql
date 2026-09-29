select *
from {{ ref('fct_inv_timing_allocation') }}
where phase_level = 'unallocated'
   or phase_code = 'unallocated'
   or bucket_code = 'unallocated'