-- 40 rows total (20 invoices x 2 ownership phases); 34 measured
select
    total_rows,
    measured_rows
from (
    select
        count(*) as total_rows,
        count(case when span_status = 'measured' then 1 end) as measured_rows
    from {{ ref('fct_inv_timing_span') }}
)
where total_rows != 40
   or measured_rows != 34