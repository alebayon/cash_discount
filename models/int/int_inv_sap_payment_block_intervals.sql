with changes as (

    select
        sap_change_id,
        sap_inv_key,
        event_date,
        block_event_role
    from {{ ref('fct_inv_sap_changes') }}
    where block_event_role in ('set', 'release')

),

sets as (

    select
        sap_change_id,
        sap_inv_key,
        event_date
    from changes
    where block_event_role = 'set'

),

paired as (

    select
        s.sap_inv_key,
        s.sap_change_id,
        s.event_date as interval_start_date,
        min(r.event_date) as interval_end_date
    from sets s
    inner join changes r
        on s.sap_inv_key = r.sap_inv_key
       and r.block_event_role = 'release'
       and r.event_date >= s.event_date
    group by
        s.sap_inv_key,
        s.sap_change_id,
        s.event_date

)

select
    sap_inv_key,
    'payment_block' as overlay_reason_code,
    row_number() over (
        partition by sap_inv_key
        order by interval_start_date, sap_change_id
    ) as interval_seq,
    interval_start_date,
    interval_end_date,
    sap_change_id as source_change_id,
    'SAP ZLSPR set to release' as interval_notes
from paired
where interval_end_date is not null