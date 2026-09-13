-- Coupa-only orphans: never posted to SAP
select
    coupa_id,
    status,
    paid,
    payment_date
from {{ ref('fct_inv_coupa') }}
where coupa_id in ('10014', '10015')
  and (
      status not in ('disputed', 'voided')
      or paid != false
      or payment_date is not null
  )