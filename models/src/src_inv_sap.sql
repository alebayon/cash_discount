with raw as (

    select
        belnr,
        bukrs,
        gjahr,
        lifnr,
        blart,
        zfbdt,
        zterm,
        wrbtr,
        waers,
        budat,
        bldat,
        augdt,
        sknto,
        payblk_clr,
        disp_clr,
        mgrblk_clr,
        nosknt_clr,
        xref2_hd
    from {{ ref('raw_inv_sap') }}

),

renamed as (

    select
        trim(belnr) || '-' || trim(bukrs) || '-' || trim(gjahr) as sap_inv_key,
        trim(belnr) as doc_number,
        trim(bukrs) as company_code,
        trim(gjahr) as fiscal_year,
        trim(lifnr) as vendor_id,
        trim(blart) as document_type,
        cast(nullif(trim(zfbdt), '') as date) as baseline_date,
        trim(zterm) as payment_terms,
        cast(wrbtr as number(18, 2)) as invoice_amount,
        trim(waers) as currency_code,
        cast(budat as date) as posting_date,
        cast(bldat as date) as document_date,
        cast(nullif(trim(augdt), '') as date) as clearing_date,
        cast(nullif(trim(sknto), '') as number(18, 2)) as discount_taken_amount,
        case
            when nullif(trim(augdt), '') is null then null
            else coalesce(upper(nullif(trim(payblk_clr), '')) in ('X', 'TRUE', '1'), false)
        end as payment_block_at_clearing,
        case
            when nullif(trim(augdt), '') is null then null
            else coalesce(upper(nullif(trim(disp_clr), '')) in ('X', 'TRUE', '1'), false)
        end as dispute_open_at_clearing,
        case
            when nullif(trim(augdt), '') is null then null
            else coalesce(upper(nullif(trim(mgrblk_clr), '')) in ('X', 'TRUE', '1'), false)
        end as match_or_gr_block_at_clearing,
        case
            when nullif(trim(augdt), '') is null then null
            else coalesce(upper(nullif(trim(nosknt_clr), '')) in ('X', 'TRUE', '1'), false)
        end as do_not_take_skonto_at_clearing,
        nullif(trim(xref2_hd), '') as coupa_posting_ref
    from raw

)

select
    sap_inv_key,
    doc_number,
    company_code,
    fiscal_year,
    vendor_id,
    document_type,
    baseline_date,
    payment_terms,
    invoice_amount,
    currency_code,
    posting_date,
    document_date,
    clearing_date,
    discount_taken_amount,
    payment_block_at_clearing,
    dispute_open_at_clearing,
    match_or_gr_block_at_clearing,
    do_not_take_skonto_at_clearing,
    coupa_posting_ref
from renamed