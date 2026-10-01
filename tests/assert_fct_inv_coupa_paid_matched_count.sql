-- majority path: matched and paid (15 of 20 fct rows; +5100000022)
select count(*) as paid_count
from {{ ref('fct_inv_coupa') }}
where status = 'paid'
  and paid = true
having count(*) != 18