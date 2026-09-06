with src as (

    select
        sap_inv_key,
        doc_number,
        company_code,
        fiscal_year,
        vendor_id,
        document_type,
        baseline_date,
        payment_terms,
        invoice_amount,
        currency_code,
        posting_date,
        document_date
    from {{ ref('src_inv_sap') }}

),

invoices as (

    select
        sap_inv_key,
        doc_number,
        company_code,
        fiscal_year,
        vendor_id,
        document_type,
        baseline_date,
        payment_terms,
        invoice_amount,
        currency_code,
        posting_date,
        document_date
    from src
    where document_type = 'KR'
      and vendor_id is not null

)

select
    sap_inv_key,
    doc_number,
    company_code,
    fiscal_year,
    vendor_id,
    document_type,
    baseline_date,
    payment_terms,
    invoice_amount,
    currency_code,
    posting_date,
    document_date
from invoices