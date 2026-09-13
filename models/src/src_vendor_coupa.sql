with raw as (

    select
        "id",
        "name",
        "country-code",
        "city",
        "postal-code",
        "status",
        "created-at"
    from {{ ref('raw_vendor_coupa') }}

),

renamed as (

    select
        trim(cast("id" as varchar)) as vendor_id,
        trim("name") as vendor_name,
        trim("country-code") as country_code,
        trim("city") as city,
        trim("postal-code") as postal_code,
        trim("status") as status,
        cast("created-at" as timestamp_ntz) as created_at
    from raw

)

select
    vendor_id,
    vendor_name,
    country_code,
    city,
    postal_code,
    status,
    created_at
from renamed