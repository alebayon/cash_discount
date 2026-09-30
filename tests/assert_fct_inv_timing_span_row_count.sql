-- ownership only: 42 rows (21 invoices x 2 phases); 36 measured
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
where total_rows != 44
   or measured_rows != 38