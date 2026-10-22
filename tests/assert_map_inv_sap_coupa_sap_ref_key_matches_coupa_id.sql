select
    m.sap_inv_key,
    m.coupa_id,
    s.sap_ref_key
from {{ ref('map_inv_sap_coupa') }} m
inner join {{ ref('fct_inv_sap_cd') }} s
    on m.sap_inv_key = s.sap_inv_key
where s.sap_ref_key != m.coupa_id
   or s.sap_ref_key is null