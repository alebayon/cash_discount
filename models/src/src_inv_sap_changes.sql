with raw as (

    select
        changenr,
        belnr,
        bukrs,
        gjahr,
        fname,
        value_old,
        value_new,
        udate
    from {{ ref('raw_inv_sap_changes') }}

),

renamed as (

    select
        trim(cast(changenr as varchar)) as sap_change_id,
        trim(belnr) || '-' || trim(bukrs) || '-' || trim(gjahr) as sap_inv_key,
        trim(fname) as fname,
        nullif(trim(value_old), '') as value_old,
        nullif(trim(value_new), '') as value_new,
        cast(udate as date) as event_date
    from raw

)

select
    sap_change_id,
    sap_inv_key,
    fname,
    value_old,
    value_new,
    event_date
from renamed