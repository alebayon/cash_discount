-- slice 4 curriculum: two timing leakage invoices, one bucket row each
select count(*) as row_count
from {{ ref('fct_inv_timing_allocation') }}
having count(*) != 2