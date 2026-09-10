-- test to assert is_taken is correctly captured
select doc_number, is_taken
from {{ ref('fct_inv_sap') }}
where doc_number in ('5100000001', '5100000002', '5100000003', '5100000004', '5100000012')
  and is_taken is distinct from case doc_number
        when '5100000001' then true
        when '5100000002' then true
        when '5100000003' then false
        when '5100000004' then true
        when '5100000012' then false
      end