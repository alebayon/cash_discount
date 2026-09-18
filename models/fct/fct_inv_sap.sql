{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}
{% set minimum_cycle_days = 5 %}
{% set standard_cycle_days = 10 %}

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
        sap_entry_date,
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
        sap_entry_date,
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
        pt.discount_days,
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

with_receipt as (

    select
        we.*,
        c.created_at::date as receipt_date
    from with_exclusion we
    left join {{ ref('fct_inv_coupa') }} c
        on we.coupa_posting_ref = c.coupa_id

),

with_cycle_benchmarks as (

    select
        wr.*,
        {{ minimum_cycle_days }} as minimum_cycle_days,
        {{ standard_cycle_days }} as standard_cycle_days
    from with_receipt wr

),

with_leakage_diagnostics as (

    select
        wb.*,
        case
            when wb.receipt_date is not null
             and wb.discount_deadline_date is not null
            then datediff('day', wb.receipt_date, wb.discount_deadline_date)
        end as available_days,
        case
            when wb.receipt_date is not null
             and wb.clearing_date is not null
            then datediff('day', wb.receipt_date, wb.clearing_date)
        end as actual_cycle_days,
        case
            when wb.receipt_date is not null
            then dateadd('day', wb.standard_cycle_days, wb.receipt_date)
        end as operational_deadline_date
    from with_cycle_benchmarks wb

),

with_primary_cause as (

    select
        wd.*,
        case
            when wd.is_kpi_entitled
             and not wd.is_taken
             and not wd.is_excluded
            then case
                when wd.receipt_date is null
                  or wd.clearing_date is null
                  or wd.discount_deadline_date is null
                  or wd.discount_days is null
                  or wd.minimum_cycle_days is null
                  or wd.standard_cycle_days is null
                  or wd.discount_days <= 0
                  or wd.minimum_cycle_days <= 0
                  or wd.standard_cycle_days < wd.minimum_cycle_days
                  or wd.receipt_date > wd.clearing_date
                    then 'data_quality_error'
                when wd.clearing_date <= wd.discount_deadline_date
                    then 'capture'
                when wd.discount_days < wd.standard_cycle_days
                    then 'structural_terms_vs_capability'
                when wd.available_days < wd.minimum_cycle_days
                    then 'structural_insufficient_time_at_intake'
                when wd.available_days < wd.standard_cycle_days
                    then 'structural_compressed_intake'
                else 'timing'
            end
        end as primary_cause
    from with_leakage_diagnostics wd

),

with_leakage as (

    select
        wpc.*,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
            then true
            when wpc.is_kpi_entitled
             and not wpc.is_taken
            then false
        end as is_leakage,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
            then wpc.discount_opportunity_amount - coalesce(wpc.discount_taken_amount, 0)
        end as lost_discount_amount,
        case
            when wpc.primary_cause = 'capture'
                then 'capture'
            when wpc.primary_cause = 'data_quality_error'
                then 'unclassified'
            when wpc.primary_cause = 'timing'
                then 'timing'
            when wpc.primary_cause is not null
                then 'structural'
        end as primary_cause_group,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
             and wpc.primary_cause not in ('capture', 'data_quality_error')
            then wpc.available_days >= wpc.minimum_cycle_days
        end as is_still_feasible,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
             and wpc.primary_cause not in ('capture', 'data_quality_error')
            then wpc.available_days >= wpc.minimum_cycle_days
             and wpc.available_days < wpc.standard_cycle_days
        end as requires_expedited_processing,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
             and wpc.primary_cause not in ('capture', 'data_quality_error')
            then wpc.clearing_date > wpc.discount_deadline_date
             and wpc.actual_cycle_days > wpc.standard_cycle_days
        end as is_timing_contributor
    from with_primary_cause wpc

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
    sap_entry_date,
    document_date,
    clearing_date,
    discount_taken_amount,
    discount_pct,
    discount_days,
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
    receipt_date,
    minimum_cycle_days,
    standard_cycle_days,
    available_days,
    actual_cycle_days,
    operational_deadline_date,
    is_leakage,
    lost_discount_amount,
    primary_cause,
    primary_cause_group,
    is_still_feasible,
    requires_expedited_processing,
    is_timing_contributor    
from with_leakage