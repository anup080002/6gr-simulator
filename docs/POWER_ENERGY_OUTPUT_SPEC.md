# Power / Energy Output Spec

This document is additive-only. It does not declare that historical tables, CSVs, artifacts, browser pages, or plots should be deleted.

Runtime truth lives under `/reports`; derived study views live under `/analytics`. Missing outputs stay unavailable until a canonical DB row or artifact exists.

All major fact tables require the base context columns and value semantics from `apps/lls_output_contract.py`.

## Value Semantics

- value_role values: configured, resolved, applied, measured, estimated, derived, aggregated, placeholder, unavailable, fallback_substituted
- value_status values: OK, MISSING, NOT_AVAILABLE, PLACEHOLDER, FALLBACK_USED, PARTIAL, CRASHED, UNSUPPORTED, REVIEW_REQUIRED
- configured/resolved/applied/measured/derived values must keep explicit `value_source` and `value_definition` lineage.
- charts are never generated from smoke rows or placeholders by default.

## Sections


### Power / Energy / Thermal / Compute / Runtime

- Route: `/reports/power-energy-thermal-compute-runtime`
- Table `live_power_runtime_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_power_runtime_table`, view `live_power_runtime_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_rf_power_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_rf_power_table`, view `live_rf_power_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_bb_power_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_bb_power_table`, view `live_bb_power_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_energy_efficiency_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_energy_efficiency_table`, view `live_energy_efficiency_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_sleep_state_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_sleep_state_table`, view `live_sleep_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Chart `TX power timeline per cell`: route `/reports/power-energy-thermal-compute-runtime/charts/tx-power-timeline-per-cell`, status `unavailable_until_source_table_has_real_rows`.
- Chart `TX power timeline per UE`: route `/reports/power-energy-thermal-compute-runtime/charts/tx-power-timeline-per-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs throughput`: route `/reports/power-energy-thermal-compute-runtime/charts/power-vs-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs BLER`: route `/reports/power-energy-thermal-compute-runtime/charts/power-vs-bler`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy per bit over time`: route `/reports/power-energy-thermal-compute-runtime/charts/energy-per-bit-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `joules/GB over time`: route `/reports/power-energy-thermal-compute-runtime/charts/joules-gb-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CPU cycles and memory usage time series`: route `/reports/power-energy-thermal-compute-runtime/charts/cpu-cycles-and-memory-usage-time-series`, status `unavailable_until_source_table_has_real_rows`.
- Chart `latency breakdown stacked chart`: route `/reports/power-energy-thermal-compute-runtime/charts/latency-breakdown-stacked-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PAPR distribution`: route `/reports/power-energy-thermal-compute-runtime/charts/papr-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sleep-state timeline`: route `/reports/power-energy-thermal-compute-runtime/charts/sleep-state-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `efficiency scatter plots`: route `/reports/power-energy-thermal-compute-runtime/charts/efficiency-scatter-plots`, status `unavailable_until_source_table_has_real_rows`.

### Power / Energy / Efficiency Analytics

- Route: `/analytics/power-energy-efficiency-analytics`
- Table `power_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/power_analytics`, view `power_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `energy_efficiency_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/energy_efficiency_analytics`, view `energy_efficiency_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `runtime_power_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/runtime_power_analytics`, view `runtime_power_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `sleep_state_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/sleep_state_analytics`, view `sleep_state_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Chart `DL Tx power per cell / beam / UE`: route `/analytics/power-energy-efficiency-analytics/charts/dl-tx-power-per-cell-beam-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UL Tx power per UE`: route `/analytics/power-energy-efficiency-analytics/charts/ul-tx-power-per-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power control behavior`: route `/analytics/power-energy-efficiency-analytics/charts/power-control-behavior`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PA backoff distribution`: route `/analytics/power-energy-efficiency-analytics/charts/pa-backoff-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RF chain power`: route `/analytics/power-energy-efficiency-analytics/charts/rf-chain-power`, status `unavailable_until_source_table_has_real_rows`.
- Chart `baseband power`: route `/analytics/power-energy-efficiency-analytics/charts/baseband-power`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CPU power if available`: route `/analytics/power-energy-efficiency-analytics/charts/cpu-power-if-available`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs throughput`: route `/analytics/power-energy-efficiency-analytics/charts/power-vs-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs BLER`: route `/analytics/power-energy-efficiency-analytics/charts/power-vs-bler`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy/bit`: route `/analytics/power-energy-efficiency-analytics/charts/energy-bit`, status `unavailable_until_source_table_has_real_rows`.
- Chart `joules/GB`: route `/analytics/power-energy-efficiency-analytics/charts/joules-gb`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy efficiency by UE`: route `/analytics/power-energy-efficiency-analytics/charts/energy-efficiency-by-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy efficiency by cell`: route `/analytics/power-energy-efficiency-analytics/charts/energy-efficiency-by-cell`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sleep/idle/active state occupancy`: route `/analytics/power-energy-efficiency-analytics/charts/sleep-idle-active-state-occupancy`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PAPR vs power`: route `/analytics/power-energy-efficiency-analytics/charts/papr-vs-power`, status `unavailable_until_source_table_has_real_rows`.
- Chart `thermal/throttling analytics if available`: route `/analytics/power-energy-efficiency-analytics/charts/thermal-throttling-analytics-if-available`, status `unavailable_until_source_table_has_real_rows`.
