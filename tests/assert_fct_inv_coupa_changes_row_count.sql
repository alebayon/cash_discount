-- 77 rows: one row per Coupa revision on 18 matched invoices (+5100000022)
select count(*) as row_count
from {{ ref('fct_inv_coupa_changes') }}
having count(*) != 81