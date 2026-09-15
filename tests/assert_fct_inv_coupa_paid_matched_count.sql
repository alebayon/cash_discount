-- majority path: matched and paid (14 of 19 fct rows)
select count(*) as paid_count
from {{ ref('fct_inv_coupa') }}
where status = 'paid'
  and paid = true
having count(*) != 14