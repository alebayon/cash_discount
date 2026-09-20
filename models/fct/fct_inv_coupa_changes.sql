with changes as (

    select
        coupa_change_id,
        coupa_id,
        status,
        event_at,
        event_date,
        revision_seq
    from {{ ref('src_inv_coupa_changes') }}

),

with_status_role as (

    select
        c.coupa_change_id,
        c.coupa_id,
        c.status,
        m.status_role,
        m.role_kind,
        c.event_at,
        c.event_date,
        c.revision_seq
    from changes c
    inner join {{ ref('seed_coupa_status_map') }} m
        on c.status = m.status

)

select
    coupa_change_id,
    coupa_id,
    status,
    status_role,
    role_kind,
    event_at,
    event_date,
    revision_seq
from with_status_role