{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

with invoices as (

    select
        sap_inv_key,
        is_kpi_entitled,
        is_taken,
        is_excluded,
        is_leakage,
        discount_opportunity_amount,
        discount_taken_amount,
        lost_discount_amount
    from {{ ref('fct_inv_sap') }}

),

aggregated as (

    select
        '{{ period_start }}'::date as reporting_period_start,
        '{{ period_end }}'::date as reporting_period_end,
        count(*) as fct_row_count,
        sum(case when is_kpi_entitled then 1 else 0 end) as kpi_entitled_count,
        sum(case when is_taken then 1 else 0 end) as taken_count,
        sum(case when is_excluded then 1 else 0 end) as excluded_count,
        sum(case when is_leakage then 1 else 0 end) as leakage_count,
        round(sum(case when is_kpi_entitled then discount_opportunity_amount else 0 end), 2)
            as discount_opportunity_eur,
        round(sum(case when is_taken then discount_taken_amount else 0 end), 2)
            as realized_discount_eur,
        round(sum(case when is_excluded then discount_opportunity_amount else 0 end), 2)
            as excluded_opportunity_eur,
        round(sum(case when is_leakage then lost_discount_amount else 0 end), 2)
            as leakage_eur
    from invoices

)

select
    reporting_period_start,
    reporting_period_end,
    fct_row_count,
    kpi_entitled_count,
    taken_count,
    excluded_count,
    leakage_count,
    discount_opportunity_eur,
    realized_discount_eur,
    excluded_opportunity_eur,
    leakage_eur,
    case
        when discount_opportunity_eur > 0
        then round(leakage_eur / discount_opportunity_eur, 6)
    end as leakage_rate
from aggregated