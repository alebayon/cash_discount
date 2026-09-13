-- Coupa-posted KR rows carry sap_ref_key; FB60 orphans do not
select
    doc_number,
    sap_ref_key
from {{ ref('fct_inv_sap') }}
where doc_number in ('5100000014', '5100000015')
  and sap_ref_key is not null

union all

select
    doc_number,
    sap_ref_key
from {{ ref('fct_inv_sap') }}
where doc_number between '5100000001' and '5100000013'
  and sap_ref_key is null