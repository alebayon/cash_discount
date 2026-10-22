-- D47/D49: no pre-SAP subprocess euro on payment-regime timing heroes
select
    s.doc_number,
    a.phase_level,
    a.phase_code,
    a.bucket_code,
    a.priority_allocated_eur
from {{ ref('fct_inv_sap_cd') }} s
inner join {{ ref('fct_inv_timing_allocation') }} a
    on s.sap_inv_key = a.sap_inv_key
where s.doc_number in ('5100000003', '5100000019')
  and a.phase_level = 'subprocess'