-- D90 expected primary_cause on curriculum leakage rows (before compressed hero)
select doc_number, primary_cause
from {{ ref('fct_inv_sap_cd') }}
where doc_number in (
    '5100000003', '5100000012', '5100000016', '5100000017', '5100000018',
    '5100000019', '5100000020', '5100000021', '5100000022', '5100000023',
    '5100000024', '5100000025'
)
  and (
      is_leakage is distinct from true
      or primary_cause is distinct from case doc_number
          when '5100000003' then 'payment_execution'
          when '5100000012' then 'capture'
          when '5100000016' then 'structural_terms_vs_capability'
          when '5100000017' then 'structural_insufficient_time_at_intake'
          when '5100000018' then 'pre_sap_execution_compressed'
          when '5100000019' then 'payment_execution'
          when '5100000020' then 'capture'
          when '5100000021' then 'data_quality_error'
          when '5100000022' then 'pre_sap_execution_standard'
          when '5100000023' then 'pre_sap_execution_standard'
          when '5100000024' then 'pre_sap_execution_standard'
          when '5100000025' then 'payment_execution'
      end
  )
