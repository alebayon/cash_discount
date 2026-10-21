-- deprecated: use fct_inv_sap_cd instead
{{ config(tags=['cash_discount']) }}

select *
from {{ ref('fct_inv_sap_cd') }}