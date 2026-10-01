with hero_check as (
    select count(*) as hero_match_count
    from {{ ref('mart_timing_phase_impact') }}
    where phase_level = 'ownership'
      and phase_code = 'payment'
      and invoice_count = 3
      and priority_allocated_eur = 46.80
      and post_deadline_days = 39
)
select *
from hero_check
where hero_match_count != 1