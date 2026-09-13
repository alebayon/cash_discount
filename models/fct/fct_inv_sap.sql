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
        discount_taken_amount,
        payment_block_at_clearing,
        dispute_open_at_clearing,
        match_or_gr_block_at_clearing,
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
        clearing_date,
        discount_taken_amount,
        payment_block_at_clearing,
        dispute_open_at_clearing,
        match_or_gr_block_at_clearing,
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

),

with_exclusion as (

    select
        wt.*,
        case
            when wt.is_kpi_entitled and not wt.is_taken
            then coalesce(wt.payment_block_at_clearing, false)
              or coalesce(wt.dispute_open_at_clearing, false)
              or coalesce(wt.match_or_gr_block_at_clearing, false)
              or coalesce(wt.do_not_take_skonto_at_clearing, false)
        end as is_excluded
    from with_taken wt

),

with_leakage as (
    select
        we.*,
        case
            when we.is_kpi_entitled
             and not we.is_taken
             and not we.is_excluded
            then true
            when we.is_kpi_entitled
             and not we.is_taken
            then false
        end as is_leakage,
        case
            when we.is_kpi_entitled
             and not we.is_taken
             and not we.is_excluded
            then we.discount_opportunity_amount - coalesce(we.discount_taken_amount, 0)
        end as lost_discount_amount,
        case
            when we.is_kpi_entitled
             and not we.is_taken
             and not we.is_excluded
            then case
                when we.clearing_date > we.discount_deadline_date
                    then 'timing'
                when we.clearing_date <= we.discount_deadline_date
                    then 'capture'
                else 'structural'
            end
        end as primary_cause
    from with_exclusion we
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
    is_taken,
    payment_block_at_clearing,
    dispute_open_at_clearing,
    match_or_gr_block_at_clearing,
    do_not_take_skonto_at_clearing,
    coupa_posting_ref as sap_ref_key,
    is_excluded,
    is_leakage,
    lost_discount_amount,
    primary_cause    
from with_leakage