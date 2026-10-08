select *
from {{ ref('mart_cash_discount_kpi_by_cause') }}
where (primary_cause, leakage_count, leakage_eur) not in (
    ('capture', 2, 28.40),
    ('data_quality_error', 1, 18.00),
    ('structural_terms_vs_capability', 1, 20.00),
    ('structural_insufficient_time_at_intake', 1, 16.00),
    ('pre_sap_execution_compressed', 1, 12.00),
    ('pre_sap_execution_standard', 3, 49.00),
    ('payment_execution', 3, 46.80)
)