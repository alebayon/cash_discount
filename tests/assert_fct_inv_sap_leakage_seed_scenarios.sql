-- labeled leakage vs excluded scenarios on synthetic seed
select
    doc_number,
    is_leakage,
    lost_discount_amount,
    primary_cause,
    primary_cause_group,
    is_still_feasible,
    requires_expedited_processing,
    is_timing_contributor
from {{ ref('fct_inv_sap') }}
where doc_number in ('5100000003', '5100000012', '5100000013')
  and (
      is_leakage is distinct from case doc_number
          when '5100000003' then true
          when '5100000012' then true
          when '5100000013' then false
      end
      or primary_cause is distinct from case doc_number
          when '5100000003' then 'payment_execution'
          when '5100000012' then 'capture'
          when '5100000013' then null
      end
      or primary_cause_group is distinct from case doc_number
          when '5100000003' then 'timing'
          when '5100000012' then 'capture'
          when '5100000013' then null
      end
      or lost_discount_amount is distinct from case doc_number
          when '5100000003' then 17.80
          when '5100000012' then 13.40
          when '5100000013' then null
      end
      or is_still_feasible is distinct from case doc_number
          when '5100000003' then true
          when '5100000012' then null
          when '5100000013' then null
      end
      or requires_expedited_processing is distinct from case doc_number
          when '5100000003' then false
          when '5100000012' then null
          when '5100000013' then null
      end
      or is_timing_contributor is distinct from case doc_number
          when '5100000003' then true
          when '5100000012' then null
          when '5100000013' then null
      end
  )