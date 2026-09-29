-- D51: default vars — one payment phase row, €28.80, 2 invoices, 25 post-deadline days
with row_count_check as (

    select count(*) as row_count
    from {{ ref('mart_timing_phase_impact') }}

),

hero_check as (

    select count(*) as hero_match_count
    from {{ ref('mart_timing_phase_impact') }}
    where phase_level = 'ownership'
      and phase_code = 'payment'
      and invoice_count = 2
      and priority_allocated_eur = 28.80
      and post_deadline_days = 25

)

select
    r.row_count,
    h.hero_match_count
from row_count_check r
cross join hero_check h
where r.row_count != 1
   or h.hero_match_count != 1