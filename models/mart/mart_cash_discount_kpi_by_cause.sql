{{ config(tags=['cash_discount']) }}
{% set period_start = var('reporting_period_start', '2024-01-01') %}
{% set period_end   = var('reporting_period_end', '2024-12-31') %}

with leakage as (

    select
        primary_cause,
        primary_cause_group,
        lost_discount_amount
    from {{ ref('fct_inv_sap_cd') }}
    where is_leakage

),

by_cause as (

    select
        primary_cause,
        primary_cause_group,
        count(*) as leakage_count,
        round(sum(lost_discount_amount), 2) as leakage_eur
    from leakage
    group by
        primary_cause,
        primary_cause_group

),

with_shares as (

    select
        '{{ period_start }}'::date as reporting_period_start,
        '{{ period_end }}'::date as reporting_period_end,
        primary_cause,
        primary_cause_group,
        leakage_count,
        leakage_eur,
        round(
            leakage_eur / sum(leakage_eur) over (), 6
        ) as leakage_share,
        round(
            leakage_count::float / sum(leakage_count) over (), 6
        ) as leakage_count_share
    from by_cause

)

select *
from with_shares
order by leakage_eur desc