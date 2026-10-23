{{ config(tags=['cash_discount']) }}
{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

with base as (
    select *
    from {{ ref('fct_inv_sap_core') }}

),

with_entitlement as (

    select
        ba.*,
        case
            when ba.baseline_date is null
                then 'no_baseline_date'
            when ba.discount_pct is null or ba.discount_pct <= 0
                then 'no_discount_terms'
            when ba.discount_deadline_date is null
                then 'no_deadline'
            when ba.invoice_amount <= 0
                then 'zero_discount_base'
        end as not_entitled_reason
    from base ba

),

with_cd_arbitration as (

    select
        we.*,
        case
            when we.not_entitled_reason is null
            then arb.arbitration_policy_version
        end as arbitration_policy_version,
        case
            when we.not_entitled_reason is null
            then arb.potential_discount_eur
        end as potential_discount_eur,
        case
            when we.not_entitled_reason is null
            then arb.cash_acceleration_days
        end as cash_acceleration_days,
        case
            when we.not_entitled_reason is null
            then arb.is_cd_eligible
        end as is_cd_eligible,
        case
            when we.not_entitled_reason is null
             and arb.is_cd_eligible = false
            then arb.not_cd_eligible_reason
        end as not_cd_eligible_reason,
        case
            when we.not_entitled_reason is null
            then arb.payment_strategy
        end as payment_strategy
    from with_entitlement we
    left join {{ ref('fct_inv_cd_wco_arbitration') }} arb
        on we.sap_inv_key = arb.sap_inv_key

),

with_payment as (

    select
        wca.*,
        (
            wca.clearing_date is not null
            and wca.clearing_date >= '{{ period_start }}'::date
            and wca.clearing_date <= '{{ period_end }}'::date
        ) as is_paid_in_period,
        (
            wca.not_entitled_reason is null
            and coalesce(wca.is_cd_eligible, false)
            and wca.clearing_date is not null
            and wca.clearing_date >= '{{ period_start }}'::date
            and wca.clearing_date <= '{{ period_end }}'::date
        ) as is_kpi_entitled
    from with_cd_arbitration wca

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
            then coalesce(wt.do_not_take_skonto_at_clearing, false)
        end as is_excluded
    from with_taken wt

),

with_policy as (

    select
        we.*,
        pol.attribution_policy_version,
        pol.minimum_processing_days,
        pol.standard_processing_days,
        pol.minimum_payment_runway_days
    from with_exclusion we
    cross join {{ ref('int_attribution_policy_active') }} as pol

),

with_leakage_diagnostics as (

    select
        wp.*,
        case
            when wp.receipt_date is not null
             and wp.discount_deadline_date is not null
            then datediff('day', wp.receipt_date, wp.discount_deadline_date)
        end as available_days,
        case
            when wp.receipt_date is not null
             and wp.discount_deadline_date is not null
             and wp.minimum_payment_runway_days is not null
            then datediff('day', wp.receipt_date, wp.discount_deadline_date)
                - wp.minimum_payment_runway_days
        end as processing_available_days,
        case
            when wp.sap_entry_date is not null
             and wp.discount_deadline_date is not null
            then datediff('day', wp.sap_entry_date, wp.discount_deadline_date)
        end as runway_at_handoff,
        case
            when wp.discount_deadline_date is not null
             and wp.minimum_payment_runway_days is not null
            then dateadd(
                'day',
                -wp.minimum_payment_runway_days,
                wp.discount_deadline_date
            )
        end as latest_safe_sap_entry_date,
        case
            when wp.receipt_date is not null
             and wp.standard_processing_days is not null
            then dateadd('day', wp.standard_processing_days, wp.receipt_date)
        end as standard_sap_target_date,
        case
            when wp.receipt_date is not null
             and wp.discount_deadline_date is not null
             and wp.standard_processing_days is not null
             and wp.minimum_payment_runway_days is not null
            then least(
                dateadd('day', wp.standard_processing_days, wp.receipt_date),
                dateadd(
                    'day',
                    -wp.minimum_payment_runway_days,
                    wp.discount_deadline_date
                )
            )
        end as operational_sap_due_date,
        case
            when wp.discount_deadline_date is not null
             and wp.clearing_date is not null
            then datediff('day', wp.discount_deadline_date, wp.clearing_date)
        end as deadline_miss_days,
        case
            when wp.minimum_payment_runway_days is not null
             and wp.sap_entry_date is not null
             and wp.discount_deadline_date is not null
            then greatest(
                0,
                wp.minimum_payment_runway_days
                - datediff('day', wp.sap_entry_date, wp.discount_deadline_date)
            )
        end as handoff_reserve_shortfall_days
    from with_policy wp

),

with_v6_diagnostics as (

    select
        wd.*,
        case
            when wd.discount_days is null
              or wd.minimum_processing_days is null
              or wd.standard_processing_days is null
              or wd.minimum_payment_runway_days is null
                then null
            when wd.discount_days
                < wd.minimum_processing_days + wd.minimum_payment_runway_days
                then 'terms_below_minimum'
            when wd.discount_days
                < wd.standard_processing_days + wd.minimum_payment_runway_days
                then 'terms_below_standard'
            else 'terms_standard'
        end as terms_condition,
        case
            when wd.processing_available_days is null
              or wd.minimum_processing_days is null
              or wd.standard_processing_days is null
                then null
            when wd.processing_available_days < wd.minimum_processing_days
                then 'insufficient'
            when wd.processing_available_days < wd.standard_processing_days
                then 'compressed'
            else 'standard'
        end as intake_condition,
        case
            when wd.runway_at_handoff is null
              or wd.minimum_payment_runway_days is null
                then null
            when wd.runway_at_handoff < wd.minimum_payment_runway_days
                then 'reserve_not_met'
            else 'reserve_met'
        end as handoff_condition,
        case
            when wd.pre_sap_elapsed_days is null
              or wd.standard_processing_days is null
                then null
            else wd.pre_sap_elapsed_days > wd.standard_processing_days
        end as pre_sap_exceeded_standard
    from with_leakage_diagnostics wd

),

with_primary_cause as (

    select
        wv.*,
        case
            when wv.is_kpi_entitled
             and not wv.is_taken
             and not wv.is_excluded
            then case
                when wv.receipt_date is null
                  or wv.sap_entry_date is null
                  or wv.clearing_date is null
                  or wv.discount_deadline_date is null
                  or wv.discount_days is null
                  or wv.discount_days <= 0
                  or wv.attribution_policy_version is null
                  or wv.minimum_processing_days is null
                  or wv.standard_processing_days is null
                  or wv.minimum_payment_runway_days is null
                  or wv.minimum_processing_days <= 0
                  or wv.standard_processing_days < wv.minimum_processing_days
                  or wv.minimum_payment_runway_days <= 0
                  or wv.receipt_date > wv.sap_entry_date
                  or wv.sap_entry_date > wv.clearing_date
                    then 'data_quality_error'
                when wv.clearing_date <= wv.discount_deadline_date
                    then 'capture'
                when wv.discount_days
                    < wv.standard_processing_days + wv.minimum_payment_runway_days
                    then 'structural_terms_vs_capability'
                when wv.processing_available_days < wv.minimum_processing_days
                 and wv.runway_at_handoff < wv.minimum_payment_runway_days
                    then 'structural_insufficient_time_at_intake'
                when wv.minimum_processing_days <= wv.processing_available_days
                 and wv.processing_available_days < wv.standard_processing_days
                 and wv.runway_at_handoff < wv.minimum_payment_runway_days
                    then 'pre_sap_execution_compressed'
                when wv.processing_available_days >= wv.standard_processing_days
                 and wv.runway_at_handoff < wv.minimum_payment_runway_days
                    then 'pre_sap_execution_standard'
                when wv.runway_at_handoff >= wv.minimum_payment_runway_days
                    then 'payment_execution'
            end
        end as primary_cause
    from with_v6_diagnostics wv

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
            when wpc.primary_cause in (
                'pre_sap_execution_compressed',
                'pre_sap_execution_standard',
                'payment_execution'
            )
                then 'timing'
            when wpc.primary_cause is not null
                then 'structural'
        end as primary_cause_group,
        case
            when wpc.primary_cause = 'capture'
                then 'capture_process'
            when wpc.primary_cause = 'data_quality_error'
                then 'unclassified'
            when wpc.primary_cause = 'structural_terms_vs_capability'
                then 'procurement_contracts'
            when wpc.primary_cause = 'structural_insufficient_time_at_intake'
                then 'upstream_intake'
            when wpc.primary_cause in (
                'pre_sap_execution_compressed',
                'pre_sap_execution_standard'
            )
                then 'pre_sap'
            when wpc.primary_cause = 'payment_execution'
                then 'payment'
        end as primary_owner,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
             and wpc.primary_cause not in ('capture', 'data_quality_error')
            then wpc.processing_available_days >= wpc.minimum_processing_days
        end as is_still_feasible,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
             and wpc.primary_cause not in ('capture', 'data_quality_error')
            then wpc.processing_available_days >= wpc.minimum_processing_days
             and wpc.processing_available_days < wpc.standard_processing_days
        end as requires_expedited_processing,
        case
            when wpc.is_kpi_entitled
             and not wpc.is_taken
             and not wpc.is_excluded
             and wpc.primary_cause not in ('capture', 'data_quality_error')
            then wpc.clearing_date > wpc.discount_deadline_date
             and (
                coalesce(wpc.pre_sap_exceeded_standard, false)
                or wpc.primary_cause = 'payment_execution'
             )
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
    arbitration_policy_version,
    potential_discount_eur,
    cash_acceleration_days,
    is_cd_eligible,
    not_cd_eligible_reason,
    payment_strategy,
    is_kpi_entitled,
    is_taken,
    do_not_take_skonto_at_clearing,
    coupa_posting_ref as sap_ref_key,
    is_excluded,
    receipt_date,
    attribution_policy_version,
    minimum_processing_days,
    standard_processing_days,
    minimum_payment_runway_days,
    available_days,
    processing_available_days,
    pre_sap_elapsed_days,
    runway_at_handoff,
    latest_safe_sap_entry_date,
    standard_sap_target_date,
    operational_sap_due_date,
    deadline_miss_days,
    handoff_reserve_shortfall_days,
    actual_cycle_days,
    terms_condition,
    intake_condition,
    handoff_condition,
    pre_sap_exceeded_standard,
    is_leakage,
    lost_discount_amount,
    primary_cause,
    primary_cause_group,
    primary_owner,
    is_still_feasible,
    requires_expedited_processing,
    is_timing_contributor
from with_leakage