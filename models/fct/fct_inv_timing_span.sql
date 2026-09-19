with invoices as (

    select
        sap_inv_key,
        sap_ref_key,
        receipt_date,
        sap_entry_date,
        clearing_date
    from {{ ref('fct_inv_sap') }}

),

phase_definitions as (

    select
        'ownership' as phase_level,
        'pre_sap' as phase_code,
        1 as span_seq,
        'coupa.created_at' as start_milestone_field,
        'sap.cpudt' as end_milestone_field
    union all
    select
        'ownership',
        'payment',
        1,
        'sap.cpudt',
        'sap.augdt'

),

span_base as (

    select
        inv.sap_inv_key,
        pd.phase_level,
        pd.phase_code,
        pd.span_seq,
        pd.start_milestone_field,
        pd.end_milestone_field,
        case
            when pd.phase_code = 'pre_sap' then
                case
                    when inv.sap_ref_key is null then 'not_applicable'
                    when inv.receipt_date is null then 'not_measurable'
                    else 'measured'
                end
            when pd.phase_code = 'payment' then
                case
                    when inv.clearing_date is null then 'not_ended'
                    else 'measured'
                end
        end as span_status,
        case
            when pd.phase_code = 'pre_sap' and inv.sap_ref_key is null then null
            when pd.phase_code = 'pre_sap' then inv.receipt_date
            else inv.sap_entry_date
        end as span_start_date,
        case
            when pd.phase_code = 'pre_sap' and inv.sap_ref_key is null then null
            when pd.phase_code = 'pre_sap' then inv.sap_entry_date
            when inv.clearing_date is null then null
            else inv.clearing_date
        end as span_end_date
    from invoices inv
    cross join phase_definitions pd

),

final as (

    select
        sap_inv_key,
        phase_level,
        phase_code,
        span_seq,
        span_status,
        span_start_date,
        span_end_date,
        case
            when span_status = 'measured'
            then datediff('day', span_start_date, span_end_date)
        end as span_days,
        start_milestone_field,
        end_milestone_field
    from span_base

)

select
    sap_inv_key,
    phase_level,
    phase_code,
    span_seq,
    span_status,
    span_start_date,
    span_end_date,
    span_days,
    start_milestone_field,
    end_milestone_field
from final