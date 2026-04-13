# Advanced Analytics Catalog

The current advanced analytics outputs are generated only when their source tables exist:

| Output | Source |
| --- | --- |
| `root_cause_candidate_table` | PRB allocation, noise/interference, transport block, and energy tables |
| `cell_edge_analytics_table` | `system/csv/system_ue_summary.csv` and serving-cell/channel summaries |
| `beam_stability_analytics_table` | `system/csv/system_beam_events.csv` |
| `energy_root_cause_table` | `rf/csv/power_energy_table.csv` |

Dashboards exposed in `/analytics`:

- Root Cause Dashboard
- Cell-Edge Dashboard
- Beam Stability Dashboard
- Energy Root Cause Dashboard
- Output Coverage Dashboard
- Persistence Audit Dashboard
- API Exposure Dashboard
- Honest Unavailable Dashboard

Hotspot, control-overhead, resource-overhead, latency-root-cause, anomaly-window, and cross-layer-correlation outputs remain registry-driven until their backend telemetry contracts are satisfied.
