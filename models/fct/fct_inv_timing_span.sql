with invoices as (

    select
        sap_inv_key,
        coupa_posting_ref,
        receipt_date,
        sap_entry_date,
        clearing_date
    from {{ ref('fct_inv_sap_core') }}

),

/* ------------------------------------------------------------------ */
/* Branch A — ownership (Slice 1 logic verbatim; no Coupa dependency)   */
/* ------------------------------------------------------------------ */

ownership_phase_definitions as (

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

ownership_span_base as (

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
                    when inv.coupa_posting_ref is null then 'not_applicable'
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
            when pd.phase_code = 'pre_sap' and inv.coupa_posting_ref is null then null
            when pd.phase_code = 'pre_sap' then inv.receipt_date
            else inv.sap_entry_date
        end as span_start_date,
        case
            when pd.phase_code = 'pre_sap' and inv.coupa_posting_ref is null then null
            when pd.phase_code = 'pre_sap' then inv.sap_entry_date
            when inv.clearing_date is null then null
            else inv.clearing_date
        end as span_end_date
    from invoices inv
    cross join ownership_phase_definitions pd

),

ownership_spans as (

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
        end_milestone_field,
        cast(null as varchar) as start_event_id,
        cast(null as varchar) as end_event_id
    from ownership_span_base

),

/* ------------------------------------------------------------------ */
/* Branch B — subprocess (Coupa events + SAP dates)                   */
/* ------------------------------------------------------------------ */

boundary_events as (

    select
        inv.sap_inv_key,
        inv.receipt_date,
        inv.sap_entry_date,
        ch.coupa_change_id,
        ch.event_date,
        ch.revision_seq,
        ch.status_role,
        row_number() over (
            partition by inv.sap_inv_key
            order by ch.event_date, ch.revision_seq, ch.coupa_change_id
        ) as event_ord
    from invoices inv
    inner join {{ ref('fct_inv_coupa_changes') }} ch
        on inv.coupa_posting_ref = ch.coupa_id
    where ch.role_kind = 'boundary'

),

intake_spans as (

    select
        ws.sap_inv_key,
        'subprocess' as phase_level,
        'intake' as phase_code,
        1 as span_seq,
        case
            when inv.receipt_date is null then 'not_measurable'
            else 'measured'
        end as span_status,
        ws.event_date as span_start_date,
        ve.event_date as span_end_date,
        ws.coupa_change_id as start_event_id,
        ve.coupa_change_id as end_event_id,
        'coupa.work_start' as start_milestone_field,
        'coupa.verification_start' as end_milestone_field
    from (
        select *
        from boundary_events
        where status_role = 'work_start'
        qualify row_number() over (
            partition by sap_inv_key
            order by event_ord
        ) = 1
    ) ws
    inner join invoices inv
        on ws.sap_inv_key = inv.sap_inv_key
    inner join (
        select *
        from boundary_events
        where status_role = 'verification_start'
        qualify row_number() over (
            partition by sap_inv_key
            order by event_ord
        ) = 1
    ) ve
        on ws.sap_inv_key = ve.sap_inv_key

),

verification_spans_paired as (

    select
        vs.sap_inv_key,
        case
            when inv.receipt_date is null then 'not_measurable'
            else 'measured'
        end as span_status,
        vs.event_date as span_start_date,
        aps.event_date as span_end_date,
        vs.coupa_change_id as start_event_id,
        aps.coupa_change_id as end_event_id,
        vs.event_ord
    from boundary_events vs
    inner join invoices inv
        on vs.sap_inv_key = inv.sap_inv_key
    inner join boundary_events aps
        on vs.sap_inv_key = aps.sap_inv_key
        and aps.status_role = 'approval_start'
        and aps.event_ord > vs.event_ord
    where vs.status_role = 'verification_start'
    qualify row_number() over (
        partition by vs.sap_inv_key, vs.coupa_change_id
        order by aps.event_ord
    ) = 1

),

verification_spans as (

    select
        sap_inv_key,
        'subprocess' as phase_level,
        'verification' as phase_code,
        row_number() over (
            partition by sap_inv_key
            order by event_ord
        ) as span_seq,
        span_status,
        span_start_date,
        span_end_date,
        start_event_id,
        end_event_id,
        'coupa.verification_start' as start_milestone_field,
        'coupa.approval_start' as end_milestone_field
    from verification_spans_paired

),

approval_spans_paired as (

    select
        aps.sap_inv_key,
        case
            when inv.receipt_date is null then 'not_measurable'
            else 'measured'
        end as span_status,
        aps.event_date as span_start_date,
        ape.event_date as span_end_date,
        aps.coupa_change_id as start_event_id,
        ape.coupa_change_id as end_event_id,
        aps.event_ord
    from boundary_events aps
    inner join invoices inv
        on aps.sap_inv_key = inv.sap_inv_key
    inner join boundary_events ape
        on aps.sap_inv_key = ape.sap_inv_key
        and ape.status_role = 'approval_end'
        and ape.event_ord > aps.event_ord
    where aps.status_role = 'approval_start'
    qualify row_number() over (
        partition by aps.sap_inv_key, aps.coupa_change_id
        order by ape.event_ord
    ) = 1

),

approval_spans as (

    select
        sap_inv_key,
        'subprocess' as phase_level,
        'approval' as phase_code,
        row_number() over (
            partition by sap_inv_key
            order by event_ord
        ) as span_seq,
        span_status,
        span_start_date,
        span_end_date,
        start_event_id,
        end_event_id,
        'coupa.approval_start' as start_milestone_field,
        'coupa.approval_end' as end_milestone_field
    from approval_spans_paired

),

interface_spans as (

    select
        lae.sap_inv_key,
        'subprocess' as phase_level,
        'interface' as phase_code,
        1 as span_seq,
        case
            when inv.receipt_date is null then 'not_measurable'
            else 'measured'
        end as span_status,
        lae.event_date as span_start_date,
        inv.sap_entry_date as span_end_date,
        lae.coupa_change_id as start_event_id,
        cast(null as varchar) as end_event_id,
        'coupa.approval_end' as start_milestone_field,
        'sap.cpudt' as end_milestone_field
    from (
        select *
        from boundary_events
        where status_role = 'approval_end'
        qualify row_number() over (
            partition by sap_inv_key
            order by event_ord desc
        ) = 1
    ) lae
    inner join invoices inv
        on lae.sap_inv_key = inv.sap_inv_key

),

coupa_subprocess_spans as (

    select * from intake_spans
    union all
    select * from verification_spans
    union all
    select * from approval_spans
    union all
    select * from interface_spans

),

sap_only_subprocess_spans as (

    select
        inv.sap_inv_key,
        'subprocess' as phase_level,
        pd.phase_code,
        1 as span_seq,
        'not_applicable' as span_status,
        cast(null as date) as span_start_date,
        cast(null as date) as span_end_date,
        cast(null as varchar) as start_event_id,
        cast(null as varchar) as end_event_id,
        pd.start_milestone_field,
        pd.end_milestone_field
    from invoices inv
    cross join (
        select
            'intake' as phase_code,
            'coupa.work_start' as start_milestone_field,
            'coupa.verification_start' as end_milestone_field
        union all
        select
            'verification',
            'coupa.verification_start',
            'coupa.approval_start'
        union all
        select
            'approval',
            'coupa.approval_start',
            'coupa.approval_end'
        union all
        select
            'interface',
            'coupa.approval_end',
            'sap.cpudt'
    ) pd
    where inv.coupa_posting_ref is null

),

payment_subprocess_spans as (

    select
        inv.sap_inv_key,
        'subprocess' as phase_level,
        'payment' as phase_code,
        1 as span_seq,
        case
            when inv.clearing_date is null then 'not_ended'
            else 'measured'
        end as span_status,
        inv.sap_entry_date as span_start_date,
        case
            when inv.clearing_date is null then null
            else inv.clearing_date
        end as span_end_date,
        cast(null as varchar) as start_event_id,
        cast(null as varchar) as end_event_id,
        'sap.cpudt' as start_milestone_field,
        'sap.augdt' as end_milestone_field
    from invoices inv

),

subprocess_spans_raw as (

    select * from coupa_subprocess_spans
    union all
    select * from sap_only_subprocess_spans
    union all
    select * from payment_subprocess_spans

),

subprocess_spans as (

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
        end_milestone_field,
        start_event_id,
        end_event_id
    from subprocess_spans_raw

),

/* ------------------------------------------------------------------ */
/* Union branches                                                     */
/* ------------------------------------------------------------------ */

final as (

    select * from ownership_spans
    union all
    select * from subprocess_spans

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
    end_milestone_field,
    start_event_id,
    end_event_id
from final