-- 124 subprocess rows at 24 KR invoices + 5 (5100000026 SAP-only bundle)
select count(*) as row_count
from {{ ref('fct_inv_timing_span') }}
where phase_level = 'subprocess'
having count(*) != 129