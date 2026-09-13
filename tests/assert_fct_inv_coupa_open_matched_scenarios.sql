-- matched with SAP, approved but unpaid
select
    coupa_id,
    status,
    paid
from {{ ref('fct_inv_coupa') }}
where coupa_id in ('10005', '10006', '10009')
  and (
      status != 'approved'
      or paid != false
  )