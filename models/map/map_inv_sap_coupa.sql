with sap_invoices as (

    select
        sap_inv_key,
        coupa_posting_ref
    from {{ ref('src_inv_sap') }}
    where document_type = 'KR'
      and vendor_id is not null

)

select
    s.sap_inv_key,
    c.coupa_id
from sap_invoices s
inner join {{ ref('fct_inv_coupa') }} c
    on s.coupa_posting_ref = c.coupa_id
where s.coupa_posting_ref is not null