with changes as (

    select
        coupa_change_id,
        coupa_id,
        status,
        event_date,
        revision_seq
    from {{ ref('fct_inv_coupa_changes') }}

),

ordered as (

    select
        coupa_change_id,
        coupa_id,
        status,
        event_date,
        revision_seq,
        lead(event_date) over (
            partition by coupa_id
            order by event_date, revision_seq, coupa_change_id
        ) as next_event_date
    from changes

),

status_intervals as (

    select
        coupa_id,
        case
            when status = 'on_hold' then 'on_hold'
            when status = 'disputed' then 'inv_dispute'
        end as overlay_reason_code,
        coupa_change_id as source_change_id,
        event_date as interval_start_date,
        next_event_date as interval_end_date,
        case
            when status = 'on_hold' then 'Coupa on_hold until next change (D75)'
            when status = 'disputed' then 'Coupa disputed until next change (D75)'
        end as interval_notes
    from ordered
    where status in ('on_hold', 'disputed')
      and next_event_date is not null
      and event_date < next_event_date

),

rejects as (

    select
        coupa_change_id,
        coupa_id,
        event_date
    from changes
    where status = 'rejected'

),

rework_intervals as (

    select
        r.coupa_id,
        'rework' as overlay_reason_code,
        s.coupa_change_id as source_change_id,
        s.event_date as interval_start_date,
        r.event_date as interval_end_date,
        'Coupa submitted through rejected visit (D20/D75)' as interval_notes
    from rejects r
    inner join changes s
        on r.coupa_id = s.coupa_id
       and s.status = 'submitted'
       and s.coupa_change_id = (
            select max(c2.coupa_change_id)
            from changes c2
            where c2.coupa_id = r.coupa_id
              and c2.status = 'submitted'
              and c2.coupa_change_id < r.coupa_change_id
        )
    where s.event_date <= r.event_date
      and s.event_date < r.event_date

),

coupa_intervals as (

    select
        coupa_id,
        overlay_reason_code,
        source_change_id,
        interval_start_date,
        interval_end_date,
        interval_notes
    from status_intervals

    union all

    select
        coupa_id,
        overlay_reason_code,
        source_change_id,
        interval_start_date,
        interval_end_date,
        interval_notes
    from rework_intervals

),

with_sap as (

    select
        m.sap_inv_key,
        i.overlay_reason_code,
        row_number() over (
            partition by m.sap_inv_key, i.overlay_reason_code
            order by i.interval_start_date, i.interval_end_date, i.source_change_id
        ) as interval_seq,
        i.interval_start_date,
        i.interval_end_date,
        i.source_change_id,
        i.interval_notes
    from coupa_intervals i
    inner join {{ ref('map_inv_sap_coupa') }} m
        on i.coupa_id = m.coupa_id

)

select
    sap_inv_key,
    overlay_reason_code,
    interval_seq,
    interval_start_date,
    interval_end_date,
    source_change_id,
    interval_notes
from with_sap