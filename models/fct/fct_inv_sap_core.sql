{{ config(tags=['core']) }}

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
        sap_entry_date,
        clearing_date,
        discount_taken_amount,
        do_not_take_skonto_at_clearing,
        coupa_posting_ref
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
        sap_entry_date,
        clearing_date,
        discount_taken_amount,
        do_not_take_skonto_at_clearing,
        coupa_posting_ref
    from src
    where document_type = 'KR'
      and vendor_id is not null

),

with_terms as (

    select
        inv.*,
        pt.discount_pct,
        pt.discount_days,
        pt.net_days,
        case
            when inv.baseline_date is not null
             and pt.discount_days is not null
            then dateadd('day', pt.discount_days, inv.baseline_date)
        end as discount_deadline_date,
        case
            when inv.baseline_date is not null
             and pt.net_days is not null
            then dateadd('day', pt.net_days, inv.baseline_date)
        end as net_due_date
    from invoices inv
    left join {{ ref('seed_payment_term_sap') }} pt
        on inv.payment_terms = pt.zterm

),

with_coupa as (

    select
        wt.*,
        m.coupa_id,
        c.created_at::date as receipt_date
    from with_terms wt
    left join {{ ref('map_inv_sap_coupa') }} m
        on wt.sap_inv_key = m.sap_inv_key
    left join {{ ref('fct_inv_coupa') }} c
        on m.coupa_id = c.coupa_id

),

with_lifecycle as (

    select
        wc.*,
        wc.clearing_date is not null as is_cleared
    from with_coupa wc

),

with_eur as (

    select
        wl.*,
        1::number(18, 6) as document_fx_rate,
        wl.invoice_amount as invoice_amount_eur,
        wl.discount_taken_amount as discount_taken_amount_eur
    from with_lifecycle wl

),

with_elapsed as (

    select
        we.*,
        case
            when we.receipt_date is not null
             and we.sap_entry_date is not null
            then datediff('day', we.receipt_date, we.sap_entry_date)
        end as pre_sap_elapsed_days,
        case
            when we.receipt_date is not null
             and we.clearing_date is not null
            then datediff('day', we.receipt_date, we.clearing_date)
        end as actual_cycle_days
    from with_eur we

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
    invoice_amount_eur,
    currency_code,
    document_fx_rate,
    posting_date,
    sap_entry_date,
    document_date,
    clearing_date,
    discount_pct,
    discount_days,
    discount_deadline_date,
    net_days,
    net_due_date,
    discount_taken_amount,
    discount_taken_amount_eur,
    do_not_take_skonto_at_clearing,
    coupa_posting_ref,
    coupa_id,
    receipt_date,
    is_cleared,
    pre_sap_elapsed_days,
    actual_cycle_days
from with_elapsed