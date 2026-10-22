with changes as (

    select
        sap_change_id,
        sap_inv_key,
        fname,
        value_old,
        value_new,
        event_date
    from {{ ref('src_inv_sap_changes') }}

),

mapped as (

    select
        c.sap_change_id,
        c.sap_inv_key,
        c.fname,
        c.value_old,
        c.value_new,
        c.event_date,
        m.block_event_role
    from changes c
    inner join {{ ref('seed_sap_payment_block_map') }} m
        on c.fname = m.fname
       and coalesce(c.value_old, '') = coalesce(m.value_old, '')
       and coalesce(c.value_new, '') = coalesce(m.value_new, '')

)

select
    m.sap_change_id,
    m.sap_inv_key,
    m.fname,
    m.value_old,
    m.value_new,
    m.event_date,
    m.block_event_role
from mapped m
inner join {{ ref('fct_inv_sap_core') }} inv
    on m.sap_inv_key = inv.sap_inv_key