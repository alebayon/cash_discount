-- 8 vendors total; 7 active (0000100005 LOEVM=X retained)
select count(*) as vendor_count
from {{ ref('dim_vendor_sap') }}
having count(*) != 8

union all

select count(*) as active_count
from {{ ref('dim_vendor_sap') }}
where is_active
having count(*) != 7