-- Slice 1 ownership pre_sap span_days unchanged (explicit IN lists; no BELNR BETWEEN)
with expected as (
    select *
    from (
        values
            ('5100000001', 5),
            ('5100000002', 5),
            ('5100000003', 4),
            ('5100000004', 4),
            ('5100000005', 3),
            ('5100000006', 3),
            ('5100000007', 5),
            ('5100000008', 5),
            ('5100000009', 3),
            ('5100000011', 5),
            ('5100000012', 4),
            ('5100000013', 3),
            ('5100000016', 5),
            ('5100000017', 4),
            ('5100000018', 4),
            ('5100000019', 4),
            ('5100000020', 3)
    ) as v (doc_number, expected_pre_sap_days)
),
actual as (
    select
        f.doc_number,
        s.span_days
    from {{ ref('fct_inv_timing_span') }} s
    inner join {{ ref('fct_inv_sap') }} f
        on s.sap_inv_key = f.sap_inv_key
    where s.phase_level = 'ownership'
      and s.phase_code = 'pre_sap'
      and s.span_status = 'measured'
)
select
    e.doc_number,
    e.expected_pre_sap_days,
    a.span_days as actual_pre_sap_days
from expected e
left join actual a
    on e.doc_number = a.doc_number
where a.span_days is null
   or a.span_days <> e.expected_pre_sap_days