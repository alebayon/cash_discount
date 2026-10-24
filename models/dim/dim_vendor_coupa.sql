with src as (

    select
        vendor_id,
        vendor_name,
        country_code,
        city,
        postal_code,
        status,
        created_at
    from {{ ref('src_vendor_coupa') }}

),

deduped as (

    select
        vendor_id,
        vendor_name,
        country_code,
        city,
        postal_code,
        status,
        created_at
    from src
    qualify row_number() over (
        partition by vendor_id
        order by created_at desc
    ) = 1

),

final as (

    select
        vendor_id,
        vendor_name,
        country_code,
        city,
        postal_code,
        status,
        created_at,
        status = 'active' as is_active
    from deduped

)

select
    vendor_id,
    vendor_name,
    country_code,
    city,
    postal_code,
    status,
    created_at,
    is_active
from final