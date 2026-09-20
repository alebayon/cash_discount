-- 72 rows: one row per Coupa revision on 17 matched invoices
select count(*) as row_count
from {{ ref('fct_inv_coupa_changes') }}
having count(*) != 72