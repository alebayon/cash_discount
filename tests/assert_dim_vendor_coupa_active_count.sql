-- 6 active suppliers (9000005 inactive excluded)
select count(*) as active_count
from {{ ref('dim_vendor_coupa') }}
having count(*) != 6