# Block To Output Capture Points

| Output Family | Current Source Or Required Capture Point |
| --- | --- |
| Scenario/topology | `reports/csv/deployment_layout_reference.csv`, `reports/csv/scenario_summary.csv`, resolved config |
| gNB/cell analytics | `system/csv/system_cell_load.csv`, `system/tables/sectors.csv`, scheduler and interference summaries |
| Channel summary | `system/csv/system_interference_detail.csv` plus channel-state exporters |
| Noise/interference | `system/csv/system_interference_detail.csv` |
| Link budget | `system/csv/system_interference_detail.csv` and RF/runtime power fields |
| Scheduler decisions | `system/csv/system_scheduler_grants.csv`, `packet_flow/csv/live_*_scheduler_grants.csv` |
| PRB allocation | Canonical scheduler grants with `PRBStart`, `PRBCount`, symbol allocation, MCS, and TBS |
| DL/UL transport blocks | Canonical DL/UL scheduler grants and raw trial exports |
| HARQ process | `system/csv/system_harq_processes.csv` |
| CQI/PMI/RI | Scheduler grant CQI/PMI/RI fields and CSI/reference-signal exporters |
| Power/energy | `rf/csv/energy_timeline_trace.csv`, generated from real raw trials and energy diagnostics |
| Root-cause analytics | Derived only from persisted runtime tables, never from fabricated rows |
| Plot-only families | Use persisted source tables first; otherwise register unavailable capture hooks |

If a capture point is missing, the output must stay unavailable or schema-only.
