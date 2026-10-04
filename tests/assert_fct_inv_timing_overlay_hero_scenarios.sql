-- D42 curriculum heroes: explicit IN lists; never BELNR BETWEEN
with overlay_counts as (
    select
        s.doc_number,
        count(o.sap_inv_key) as overlay_row_count
    from {{ ref('fct_inv_sap') }} s
    left join {{ ref('fct_inv_timing_overlay') }} o
        on s.sap_inv_key = o.sap_inv_key
    where s.doc_number in (
        '5100000003',
        '5100000008',
        '5100000012',
        '5100000013',
        '5100000016',
        '5100000019',
        '5100000020'
    )
    group by s.doc_number
),
expected_counts as (
    select *
    from (
        values
            ('5100000003', 1),
            ('5100000008', 1),
            ('5100000012', 0),
            ('5100000013', 0),
            ('5100000016', 0),
            ('5100000019', 2),
            ('5100000020', 1)
    ) as v(doc_number, expected_overlay_row_count)
),
count_failures as (
    select
        e.doc_number,
        e.expected_overlay_row_count,
        coalesce(c.overlay_row_count, 0) as actual_overlay_row_count
    from expected_counts e
    left join overlay_counts c
        on e.doc_number = c.doc_number
    where coalesce(c.overlay_row_count, 0) <> e.expected_overlay_row_count
),
hero_rows as (
    select
        s.doc_number,
        o.overlay_reason_code,
        o.interval_seq,
        o.interval_start_date,
        o.interval_end_date,
        o.interval_days,
        o.source_change_id
    from {{ ref('fct_inv_sap') }} s
    inner join {{ ref('fct_inv_timing_overlay') }} o
        on s.sap_inv_key = o.sap_inv_key
    where s.doc_number in (
        '5100000003',
        '5100000008',
        '5100000019',
        '5100000020'
    )
),
detail_failures as (
    select
        doc_number,
        overlay_reason_code,
        interval_seq,
        interval_start_date,
        interval_end_date,
        interval_days,
        source_change_id
    from hero_rows
    where not (
        (doc_number = '5100000003' and overlay_reason_code = 'payment_run_wait' and interval_seq = 1
         and interval_start_date = '2024-04-11' and interval_end_date = '2024-04-25'
         and interval_days = 14 and source_change_id is null)
        or
        (doc_number = '5100000008' and overlay_reason_code = 'on_hold' and interval_seq = 1
         and interval_start_date = '2024-06-08' and interval_end_date = '2024-06-09'
         and interval_days = 1 and source_change_id = '900031')
        or
        (doc_number = '5100000019' and overlay_reason_code = 'vendor_response_wait' and interval_seq = 1
         and interval_start_date = '2024-10-16' and interval_end_date = '2024-10-18'
         and interval_days = 2 and source_change_id is null)
        or
        (doc_number = '5100000019' and overlay_reason_code = 'payment_run_wait' and interval_seq = 1
         and interval_start_date = '2024-10-25' and interval_end_date = '2024-11-05'
         and interval_days = 11 and source_change_id is null)
        or
        (doc_number = '5100000020' and overlay_reason_code = 'rework' and interval_seq = 1
         and interval_start_date = '2024-11-04' and interval_end_date = '2024-11-05'
         and interval_days = 1 and source_change_id = '900067')
    )
),
ownership_payment_failures as (
    select
        s.doc_number
    from {{ ref('fct_inv_sap') }} s
    left join {{ ref('fct_inv_timing_overlay_span') }} b
        on s.sap_inv_key = b.sap_inv_key
        and b.overlay_reason_code = 'payment_run_wait'
        and b.phase_level = 'ownership'
        and b.phase_code = 'payment'
        and b.reason_exposure_days = 14
    where s.doc_number = '5100000003'
      and b.sap_inv_key is null
)
select
    'count' as failure_type,
    doc_number,
    cast(expected_overlay_row_count as varchar) as expected_value,
    cast(actual_overlay_row_count as varchar) as actual_value,
    cast(null as varchar) as overlay_reason_code,
    cast(null as date) as interval_start_date,
    cast(null as date) as interval_end_date,
    cast(null as number) as interval_days,
    cast(null as varchar) as source_change_id
from count_failures

union all

select
    'detail' as failure_type,
    doc_number,
    cast(null as varchar) as expected_value,
    cast(null as varchar) as actual_value,
    overlay_reason_code,
    interval_start_date,
    interval_end_date,
    interval_days,
    source_change_id
from detail_failures

union all

select
    'ownership_payment' as failure_type,
    doc_number,
    cast(null as varchar) as expected_value,
    cast(null as varchar) as actual_value,
    cast(null as varchar) as overlay_reason_code,
    cast(null as date) as interval_start_date,
    cast(null as date) as interval_end_date,
    cast(null as number) as interval_days,
    cast(null as varchar) as source_change_id
from ownership_payment_failures