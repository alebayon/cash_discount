-- credit note stays in src only
select s.coupa_id
from {{ ref('src_inv_coupa') }} s
inner join {{ ref('fct_inv_coupa') }} f
    on s.coupa_id = f.coupa_id
where s.document_type = 'Credit Note'