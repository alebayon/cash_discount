select
    s.sap_inv_key,
    c.coupa_id
from {{ ref('fct_inv_sap') }} s
inner join {{ ref('fct_inv_coupa') }} c
    on s.sap_ref_key = c.coupa_id
where s.sap_ref_key is not null