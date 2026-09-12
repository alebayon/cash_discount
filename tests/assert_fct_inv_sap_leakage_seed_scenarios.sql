-- labeled leakage vs excluded scenarios on synthetic seed
select doc_number, is_leakage, lost_discount_amount, primary_cause
from {{ ref('fct_inv_sap') }}
where doc_number in ('5100000003', '5100000012', '5100000013')
  and (
      is_leakage is distinct from case doc_number
          when '5100000003' then true
          when '5100000012' then true
          when '5100000013' then false
      end
      or primary_cause is distinct from case doc_number
          when '5100000003' then 'timing'
          when '5100000012' then 'capture'
          when '5100000013' then null
      end
      or lost_discount_amount is distinct from case doc_number
          when '5100000003' then 17.80
          when '5100000012' then 13.40
          when '5100000013' then null
      end
  )