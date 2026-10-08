-- D50: per-invoice bucket sum equals lost_discount_amount
with per_invoice as (
    select
        sap_inv_key,
        round(sum(priority_allocated_eur), 2) as allocated_eur
    from {{ ref('fct_inv_timing_allocation') }}
    group by sap_inv_key
)
select
    s.doc_number,
    s.lost_discount_amount,
    p.allocated_eur
from per_invoice p
inner join {{ ref('fct_inv_sap') }} s
    on p.sap_inv_key = s.sap_inv_key
where s.is_leakage
  and s.primary_cause_group = 'timing'
  and abs(p.allocated_eur - round(s.lost_discount_amount, 2)) > 0.01