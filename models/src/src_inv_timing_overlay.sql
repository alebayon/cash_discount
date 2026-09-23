with raw as (

    select
        sap_doc_number,
        company_code,
        fiscal_year,
        overlay_reason_code,
        interval_seq,
        interval_start_date,
        interval_end_date,
        source_change_id,
        interval_notes
    from {{ ref('raw_inv_timing_overlay') }}

),

renamed as (

    select
        trim(sap_doc_number) || '-' || trim(company_code) || '-' || trim(fiscal_year) as sap_inv_key,
        trim(sap_doc_number) as doc_number,
        trim(overlay_reason_code) as overlay_reason_code,
        cast(interval_seq as integer) as interval_seq,
        cast(interval_start_date as date) as interval_start_date,
        cast(interval_end_date as date) as interval_end_date,
        nullif(trim(source_change_id), '') as source_change_id,
        nullif(trim(interval_notes), '') as interval_notes
    from raw

)

select
    sap_inv_key,
    doc_number,
    overlay_reason_code,
    interval_seq,
    interval_start_date,
    interval_end_date,
    source_change_id,
    interval_notes
from renamed