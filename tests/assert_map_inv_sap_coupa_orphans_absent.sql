select
    m.sap_inv_key,
    m.coupa_id
from {{ ref('map_inv_sap_coupa') }} m
where m.coupa_id in ('10010', '10014', '10015')
   or exists (
       select 1
       from {{ ref('fct_inv_sap_core') }} s
       where s.sap_inv_key = m.sap_inv_key
         and s.doc_number in ('5100000014', '5100000015', '5100000021')
   )