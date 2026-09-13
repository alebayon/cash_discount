-- 15 src rows minus 1 credit note
select count(*) as row_count
from {{ ref('fct_inv_coupa') }}
having count(*) != 14