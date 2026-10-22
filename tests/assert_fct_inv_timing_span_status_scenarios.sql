-- explicit IN lists; string BETWEEN on BELNR is unsafe
select
    f.doc_number,
    s.phase_level,
    s.phase_code,
    s.span_status
from {{ ref('fct_inv_timing_span') }} s
inner join {{ ref('fct_inv_sap_cd') }} f
    on s.sap_inv_key = f.sap_inv_key
where f.doc_number in ('5100000014', '5100000015', '5100000021')
  and s.phase_code = 'pre_sap'
  and s.phase_level = 'ownership'
  and s.span_status != 'not_applicable'

union all

select
    f.doc_number,
    s.phase_level,
    s.phase_code,
    s.span_status
from {{ ref('fct_inv_timing_span') }} s
inner join {{ ref('fct_inv_sap_cd') }} f
    on s.sap_inv_key = f.sap_inv_key
where f.doc_number in ('5100000005', '5100000006', '5100000009')
  and s.phase_code = 'payment'
  and s.phase_level = 'ownership'
  and s.span_status != 'not_ended'

union all

select
    f.doc_number,
    s.phase_level,
    s.phase_code,
    s.span_status
from {{ ref('fct_inv_timing_span') }} s
inner join {{ ref('fct_inv_sap_cd') }} f
    on s.sap_inv_key = f.sap_inv_key
where f.doc_number in ('5100000014', '5100000015', '5100000021')
  and s.phase_level = 'subprocess'
  and s.phase_code in ('intake', 'verification', 'approval', 'interface')
  and s.span_status != 'not_applicable'

union all

select
    f.doc_number,
    s.phase_level,
    s.phase_code,
    s.span_status
from {{ ref('fct_inv_timing_span') }} s
inner join {{ ref('fct_inv_sap_cd') }} f
    on s.sap_inv_key = f.sap_inv_key
where f.doc_number in ('5100000005', '5100000006', '5100000009')
  and s.phase_level = 'subprocess'
  and s.phase_code = 'payment'
  and s.span_status != 'not_ended'