# Output Coverage Matrix

The browser `/analytics` Output Coverage dashboard reads these canonical artifacts:

| Dashboard | Canonical Artifact |
| --- | --- |
| Output Coverage Dashboard | `reports/csv/output_coverage_registry.csv` |
| Output Completeness Dashboard | `reports/csv/output_completeness_table.csv` |
| Persistence Audit Dashboard | `reports/csv/persistence_audit_table.csv` |
| API Exposure Dashboard | `reports/csv/api_exposure_audit_table.csv` |
| Honest Unavailable Dashboard | `reports/csv/honest_unavailable_registry.csv` |
| Compare-Run Prerequisites | `reports/csv/compare_run_prerequisites.csv` |

Implemented runtime-backed outputs in the current phase include scenario topology, gNB/cell table, channel summary, noise/interference table, link budget table, PRB allocation, PRB heatmap, DL/UL transport block tables when grants exist, HARQ process table, CQI/PMI/RI table, MCS/TBS evolution, power/energy table, and selected advanced analytics.

Outputs without backend telemetry are retained in the registry as unavailable or schema-only rows with blocker metadata.
