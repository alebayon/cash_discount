# After seeding 5100000022: refresh Coupa fact (often stale) then downstream.
# Run from repo root: .\scripts\rebuild_curriculum_v2_step1.ps1

dbt run --select `
  src_inv_coupa `
  fct_inv_coupa `
  fct_inv_sap_cd `
  fct_inv_coupa_changes `
  fct_inv_timing_span `
  fct_inv_timing_overlay_cd `
  fct_inv_timing_allocation `
  mart_timing_phase_impact `
  mart_timing_bucket_impact
