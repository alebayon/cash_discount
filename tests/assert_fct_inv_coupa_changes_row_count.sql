-- 94 rows after D75 disputed curriculum events on 10019 and 10023
select count(*) as row_count
from {{ ref('fct_inv_coupa_changes') }}
having count(*) != 94