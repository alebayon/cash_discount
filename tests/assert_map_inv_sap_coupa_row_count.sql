select count(*) as row_count
from {{ ref('map_inv_sap_coupa') }}
having count(*) != 21