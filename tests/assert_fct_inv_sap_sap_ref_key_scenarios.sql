-- Coupa-posted KR rows carry sap_ref_key; FB60 orphans do not
select
    doc_number,
    sap_ref_key
from {{ ref('fct_inv_sap') }}
where doc_number in ('5100000014', '5100000015', '5100000021')
  and sap_ref_key is not null

union all

select
    doc_number,
    sap_ref_key
from {{ ref('fct_inv_sap') }}
where doc_number in (
    '5100000001', '5100000002', '5100000003', '5100000004',
    '5100000005', '5100000006', '5100000007', '5100000008', '5100000009',
    '5100000011', '5100000012', '5100000013',
    '5100000016', '5100000017', '5100000018', '5100000019', '5100000020'
)
  and sap_ref_key is null