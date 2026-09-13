with raw as (

    select
        "id",
        "supplier-id",
        "invoice-number",
        "status",
        "invoice-date",
        "created-at",
        "updated-at",
        "paid",
        "payment-date",
        "document-type"
    from {{ ref('raw_inv_coupa') }}

),

renamed as (

    select
        trim(cast("id" as varchar)) as coupa_id,
        trim(cast("supplier-id" as varchar)) as vendor_id,
        trim("invoice-number") as invoice_number,
        trim("status") as status,
        cast("invoice-date" as date) as invoice_date,
        cast("created-at" as timestamp_ntz) as created_at,
        cast("updated-at" as timestamp_ntz) as updated_at,
        case
            when "paid" is null then null
            when lower(trim(cast("paid" as varchar))) in ('true', 't', '1', 'yes') then true
            when lower(trim(cast("paid" as varchar))) in ('false', 'f', '0', 'no') then false
        end as paid,
        cast(nullif(trim("payment-date"), '') as date) as payment_date,
        trim("document-type") as document_type
    from raw

)

select
    coupa_id,
    vendor_id,
    invoice_number,
    status,
    invoice_date,
    created_at,
    updated_at,
    paid,
    payment_date,
    document_type
from renamed