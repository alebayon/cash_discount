-- D51: payment phase — two buckets, both ACT on current curriculum
with buckets as (
    select
        count(*) as row_count,
        sum(case when action_status = 'ACT' then 1 else 0 end) as act_count,
        sum(case
            when phase_level = 'ownership'
             and phase_code = 'payment'
             and bucket_code = 'payment_run_wait'
             and priority_allocated_eur = 17.80
            then 1 else 0
        end) as payment_run_wait_ok,
        sum(case
            when phase_level = 'ownership'
             and phase_code = 'payment'
             and bucket_code = 'no_recorded_blocker'
             and priority_allocated_eur = 11.00
            then 1 else 0
        end) as gap_ok
    from {{ ref('mart_timing_bucket_impact') }}
    where phase_level = 'ownership'
      and phase_code = 'payment'
)
select *
from buckets
where row_count != 2
   or act_count != 2
   or payment_run_wait_ok != 1
   or gap_ok != 1