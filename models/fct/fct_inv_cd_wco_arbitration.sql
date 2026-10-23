{{ config(tags=['core']) }}

with invoices as (

    select *
    from {{ ref('fct_inv_sap_core') }}

),

with_policy as (

    select
        inv.*,
        pol.arbitration_policy_version,
        pol.minimum_potential_discount_eur,
        pol.maximum_cash_acceleration_days
    from invoices inv
    left join {{ ref('seed_cd_wco_arbitration_policy') }} pol
        on inv.document_date is not null
        and inv.document_date >= pol.effective_from::date
        and inv.document_date <= pol.effective_to::date

),

with_metrics as (

    select
        wp.*,
        case
            when wp.discount_pct is not null
             and wp.discount_pct > 0
             and wp.invoice_amount_eur is not null
            then wp.invoice_amount_eur * wp.discount_pct
        end as potential_discount_eur,
        case
            when wp.discount_deadline_date is not null
             and wp.net_due_date is not null
            then datediff('day', wp.discount_deadline_date, wp.net_due_date)
        end as cash_acceleration_days,
        (
            wp.baseline_date is not null
            and wp.discount_pct is not null
            and wp.discount_pct > 0
            and wp.discount_deadline_date is not null
            and wp.net_due_date is not null
            and wp.invoice_amount > 0
        ) as is_terms_eligible_for_arbitration
    from with_policy wp

),

with_gates as (

    select
        wm.*,
        case
            when wm.arbitration_policy_version is null
                then false
            when not wm.is_terms_eligible_for_arbitration
                then false
            when wm.potential_discount_eur < wm.minimum_potential_discount_eur
                then false
            when wm.cash_acceleration_days > wm.maximum_cash_acceleration_days
                then false
            else true
        end as is_cd_eligible,
        case
            when wm.arbitration_policy_version is null
                then null
            when not wm.is_terms_eligible_for_arbitration
                then null
            when wm.potential_discount_eur < wm.minimum_potential_discount_eur
                then 'potential_discount_below_minimum'
            when wm.cash_acceleration_days > wm.maximum_cash_acceleration_days
                then 'cash_acceleration_exceeds_maximum'
        end as not_cd_eligible_reason
    from with_metrics wm

)

select
    sap_inv_key,
    doc_number,
    document_date,
    arbitration_policy_version,
    minimum_potential_discount_eur,
    maximum_cash_acceleration_days,
    potential_discount_eur,
    cash_acceleration_days,
    is_cd_eligible,
    not_cd_eligible_reason,
    case
        when is_cd_eligible then 'pursue_cd'
        else 'target_net'
    end as payment_strategy
from with_gates