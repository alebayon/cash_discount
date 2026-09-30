-- slice 4 curriculum v2 step 1: payment heroes (2 rows) + pre-posting buckets on 5100000022
select count(*) as row_count
from {{ ref('fct_inv_timing_allocation') }}
having count(*) < 3