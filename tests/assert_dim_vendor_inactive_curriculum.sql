select vendor_id
from {{ ref('dim_vendor_sap') }}
where vendor_id = '0000100005'
  and (is_active is distinct from false or deletion_flag is distinct from 'X')

union all

select vendor_id
from {{ ref('dim_vendor_coupa') }}
where vendor_id = '9000005'
  and (is_active is distinct from false or status is distinct from 'inactive')