-- 7 suppliers total; 6 active (9000005 inactive retained on dim)
select count(*) as supplier_count
from {{ ref('dim_vendor_coupa') }}
having count(*) != 7

union all

select count(*) as active_count
from {{ ref('dim_vendor_coupa') }}
where is_active
having count(*) != 6