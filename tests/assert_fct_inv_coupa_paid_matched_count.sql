-- majority path: matched and paid (9 of 14 fct rows)
select count(*) as paid_count
from {{ ref('fct_inv_coupa') }}
where status = 'paid'
  and paid = true
having count(*) != 9