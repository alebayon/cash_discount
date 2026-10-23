-- ownership only: 25 invoices x 2 phases; 5100000026 adds one measured payment span (SAP-only)
select
    total_rows,
    measured_rows
from (
    select
        count(*) as total_rows,
        count(case when span_status = 'measured' then 1 end) as measured_rows
    from {{ ref('fct_inv_timing_span') }}
    where phase_level = 'ownership'
)
where total_rows != 50
   or measured_rows != 43