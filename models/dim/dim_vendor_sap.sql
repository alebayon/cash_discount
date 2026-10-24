with src as (

    select
        vendor_id,
        vendor_name,
        country_code,
        city,
        postal_code,
        account_group,
        deletion_flag,
        created_date
    from {{ ref('src_vendor_sap') }}

),

deduped as (

    select
        vendor_id,
        vendor_name,
        country_code,
        city,
        postal_code,
        account_group,
        deletion_flag,
        created_date
    from src
    qualify row_number() over (
        partition by vendor_id
        order by created_date desc
    ) = 1

),

final as (

    select
        vendor_id,
        vendor_name,
        country_code,
        city,
        postal_code,
        account_group,
        deletion_flag,
        created_date,
        deletion_flag is null as is_active
    from deduped

)

select
    vendor_id,
    vendor_name,
    country_code,
    city,
    postal_code,
    account_group,
    deletion_flag,
    created_date,
    is_active
from final