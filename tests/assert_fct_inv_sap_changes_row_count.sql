-- Phase 1 hero: two ZLSPR events on 5100000025
select count(*) as row_count
from {{ ref('fct_inv_sap_changes') }}
having count(*) != 2