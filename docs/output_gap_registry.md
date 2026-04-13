# Output Gap Registry

The runtime-generated registry is:

`reports/csv/output_coverage_registry.csv`

It is produced by:

`+sixgr/+truth/exportLLSOutputCoverageArtifacts.m`

Required columns:

`output_name`, `ui_section`, `block_module`, `required_flag`, `classification_code`, `current_status`, `fix_now_flag`, `backend_source_exists_flag`, `persisted_flag`, `api_exposed_flag`, `ui_rendered_flag`, `export_supported_flag`, `compare_run_supported_flag`, `blocker_reason`, `target_phase`.

The registry intentionally mixes implemented outputs and honest gaps. A row with `classification_code=a` or `current_status=unavailable` is not a fake output; it is the browser-visible backlog contract.

Fix-now outputs covered by the current implementation:

- `power_energy_table`
- `live_prb_allocation`
- `prb_allocation_heatmap`
- `compare_run_prerequisites`

Advanced and unavailable outputs remain visible through registry status instead of being silently omitted.
