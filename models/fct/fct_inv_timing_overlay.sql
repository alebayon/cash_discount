-- deprecated: use fct_inv_timing_overlay_cd instead
{{ config(tags=['cash_discount']) }}

select *
from {{ ref('fct_inv_timing_overlay_cd') }}