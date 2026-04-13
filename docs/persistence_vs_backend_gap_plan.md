# Persistence Vs Backend Gap Plan

Gap handling follows the registry classification:

- `POLICY_C_PERSISTENCE_GAP`: backend rows exist, so the exporter persists them to canonical CSV/JSON artifacts and adds manifest entries.
- `POLICY_D_API_GAP`: persisted rows exist, so `/api/run/<id>/live` exposes them in `output_coverage`.
- `POLICY_A_BACKEND_GAP`: backend rows do not exist, so only registry and honest unavailable metadata are written.
- `POLICY_F_SCHEMA_ONLY`: schema is visible, but rows remain zero unless runtime telemetry exists.
- `POLICY_R_RUNTIME_PREREQ`: compare-run or overlay outputs stay blocked until comparable run groups and metric alignment are present.

Current persistence additions:

- `rf/csv/power_energy_table.csv`
- `packet_flow/csv/live_prb_allocation.csv`
- `reports/csv/prb_allocation_heatmap.csv`
- `reports/csv/output_coverage_registry.csv`
- `reports/csv/output_completeness_table.csv`
- `reports/csv/instrumentation_coverage_table.csv`
- `reports/csv/api_exposure_audit_table.csv`
- `reports/csv/persistence_audit_table.csv`
- `reports/csv/honest_unavailable_registry.csv`
- `reports/csv/compare_run_prerequisites.csv`

Each CSV is also exported as JSON by the coverage artifact exporter where table rows exist.
