-- D37 policy A: no shared calendar day between payment_run_wait and payment_block
with run_wait as (
    select
        sap_inv_key,
        interval_start_date,
        interval_end_date
    from {{ ref('fct_inv_timing_overlay_cd') }}
    where overlay_reason_code = 'payment_run_wait'
),

payment_block as (
    select
        sap_inv_key,
        interval_start_date,
        interval_end_date
    from {{ ref('fct_inv_timing_overlay_cd') }}
    where overlay_reason_code = 'payment_block'
)

select
    w.sap_inv_key
from run_wait w
inner join payment_block b
    on w.sap_inv_key = b.sap_inv_key
where greatest(w.interval_start_date, b.interval_start_date)
    < least(w.interval_end_date, b.interval_end_date)