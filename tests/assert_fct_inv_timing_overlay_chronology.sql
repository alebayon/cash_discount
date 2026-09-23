-- D44: reason-specific interval bounds vs fct_inv_sap milestones
select
    o.sap_inv_key,
    s.doc_number,
    o.overlay_reason_code,
    o.interval_start_date,
    o.interval_end_date,
    s.receipt_date,
    s.sap_entry_date,
    s.clearing_date,
    s.discount_deadline_date
from {{ ref('fct_inv_timing_overlay') }} o
inner join {{ ref('fct_inv_sap') }} s
    on o.sap_inv_key = s.sap_inv_key
where
    o.interval_start_date >= o.interval_end_date
    or (
        o.overlay_reason_code in (
            'on_hold',
            'rework',
            'vendor_response_wait',
            'payment_block'
        )
        and (
            (s.receipt_date is not null and o.interval_start_date < s.receipt_date)
            or (s.clearing_date is not null and o.interval_end_date > s.clearing_date)
        )
    )
    or (
        o.overlay_reason_code = 'payment_run_wait'
        and (
            s.discount_deadline_date is null
            or s.clearing_date is null
            or s.clearing_date <= s.discount_deadline_date
            or o.interval_start_date is distinct from s.discount_deadline_date
            or o.interval_end_date is distinct from s.clearing_date
        )
    )
    or (
        o.overlay_reason_code in ('on_hold', 'vendor_response_wait', 'payment_block')
        and coalesce(o.interval_days, 0) < 1
    )
    or (
        o.overlay_reason_code = 'rework'
        and coalesce(o.interval_days, 0) < 1
    )