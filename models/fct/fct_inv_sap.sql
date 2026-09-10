{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

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
        document_date,
        clearing_date,
        discount_taken_amount
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
        document_date,
        clearing_date,
        discount_taken_amount
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

),

with_payment as (

    select
        we.*,
        we.clearing_date is not null as is_cleared,
        (
            we.clearing_date is not null
            and we.clearing_date >= '{{ period_start }}'::date
            and we.clearing_date <= '{{ period_end }}'::date
        ) as is_paid_in_period,
        (
            we.not_entitled_reason is null
            and we.clearing_date is not null
            and we.clearing_date >= '{{ period_start }}'::date
            and we.clearing_date <= '{{ period_end }}'::date
        ) as is_kpi_entitled
    from with_entitlement we

),

with_amounts as (

    select
        wp.*,
        case
            when wp.not_entitled_reason is null
            then wp.invoice_amount * wp.discount_pct
        end as discount_opportunity_amount
    from with_payment wp

),

with_taken as (

    select
        wa.*,
        case
            when wa.is_kpi_entitled
             and wa.discount_taken_amount > 0
             and wa.discount_taken_amount = wa.discount_opportunity_amount
            then true
            when wa.is_kpi_entitled
            then false
        end as is_taken
    from with_amounts wa

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
    clearing_date,
    discount_taken_amount,
    discount_pct,
    discount_deadline_date,
    discount_opportunity_amount,
    not_entitled_reason is null as is_entitled,
    not_entitled_reason,
    is_cleared,
    is_paid_in_period,
    is_kpi_entitled,
    is_taken
from with_taken