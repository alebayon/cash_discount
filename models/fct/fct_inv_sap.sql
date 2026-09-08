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

),

with_terms as (

    select
        inv.*,
        pt.discount_pct,
        case
            when inv.baseline_date is not null
             and pt.discount_days is not null
            then dateadd('day', pt.discount_days, inv.baseline_date)
        end as discount_deadline_date
    from invoices inv
    left join {{ ref('seed_payment_term_sap') }} pt
        on inv.payment_terms = pt.zterm

),

with_entitlement as (

    select
        wt.*,
        case
            when wt.baseline_date is null
                then 'no_baseline_date'
            when wt.discount_pct is null or wt.discount_pct <= 0
                then 'no_discount_terms'
            when wt.discount_deadline_date is null
                then 'no_deadline'
            when wt.invoice_amount <= 0
                then 'zero_discount_base'
        end as not_entitled_reason
    from with_terms wt

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
    document_date,
    discount_pct,
    discount_deadline_date,
    not_entitled_reason is null as is_entitled,
    not_entitled_reason
from with_entitlement