-- D51 / D65: payment phase — derived run_wait + SAP payment_block
with buckets as (
    select
        count(*) as row_count,
        sum(case when action_status = 'ACT' then 1 else 0 end) as act_count,
        sum(case
            when phase_level = 'ownership'
             and phase_code = 'payment'
             and bucket_code = 'payment_run_wait'
             and priority_allocated_eur = 37.80
            then 1 else 0
        end) as payment_run_wait_ok,
        sum(case
            when phase_level = 'ownership'
             and phase_code = 'payment'
             and bucket_code = 'no_recorded_blocker'
            then 1 else 0
        end) as payment_no_recorded_blocker_rows,
        sum(case
            when phase_level = 'ownership'
             and phase_code = 'payment'
             and bucket_code = 'payment_block'
             and priority_allocated_eur = 9.00
            then 1 else 0
        end) as payment_block_ok
    from {{ ref('mart_timing_bucket_impact') }}
    where phase_level = 'ownership'
      and phase_code = 'payment'
)
select *
from buckets
where row_count != 2
   or act_count < 1
   or payment_run_wait_ok != 1
   or payment_no_recorded_blocker_rows != 0
   or payment_block_ok != 1