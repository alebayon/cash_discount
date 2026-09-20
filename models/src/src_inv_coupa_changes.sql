with raw as (

    select
        "id",
        "invoice-id",
        "status",
        "created-at",
        "revision-number"
    from {{ ref('raw_inv_coupa_changes') }}

),

renamed as (

    select
        trim(cast("id" as varchar)) as coupa_change_id,
        trim(cast("invoice-id" as varchar)) as coupa_id,
        trim("status") as status,
        cast("created-at" as timestamp_ntz) as event_at,
        cast("created-at" as date) as event_date,
        cast("revision-number" as integer) as revision_seq
    from raw

)

select
    coupa_change_id,
    coupa_id,
    status,
    event_at,
    event_date,
    revision_seq
from renamed