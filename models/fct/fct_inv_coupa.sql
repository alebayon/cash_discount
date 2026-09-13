with src as (

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
    from {{ ref('src_inv_coupa') }}

),

invoices as (

    select
        coupa_id,
        vendor_id,
        invoice_number,
        status,
        invoice_date,
        created_at,
        updated_at,
        paid,
        payment_date
    from src
    where document_type = 'Invoice'
      and vendor_id is not null

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
    payment_date
from invoices