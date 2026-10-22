-- labeled exclusion vs leakage scenarios on synthetic seed
select doc_number, is_excluded, do_not_take_skonto_at_clearing
from {{ ref('fct_inv_sap_cd') }}
where doc_number in ('5100000003', '5100000012', '5100000013', '5100000001')
  and (
      is_excluded is distinct from case doc_number
          when '5100000001' then null
          when '5100000003' then false
          when '5100000012' then false
          when '5100000013' then true
      end
      or do_not_take_skonto_at_clearing is distinct from case doc_number
          when '5100000013' then true
          when '5100000001' then false
          else false
      end
  )