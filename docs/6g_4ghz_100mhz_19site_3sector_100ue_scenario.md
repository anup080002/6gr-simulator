# 6G 4 GHz / 100 MHz / 19 Site / 3 Sector / 100 UE Scenario Family

## Identity

- Scenario family: `6G_4GHz_100MHz_19S3_100UE_UMa`
- Canonical family root: [simulator/configs/scenarios/lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml)
- Browser default scenario: [simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml)
- Runtime entrypoint: [run_6g_phy_lls_single.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/run_6g_phy_lls_single.m)
- Browser/backend control plane: [apps/lls_web_dashboard.py](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/apps/lls_web_dashboard.py)

## Real Execution Path

The intended live path for this family is:

`/home` -> browser `config_json` -> `/run` -> runtime YAML snapshot -> `C:\Program Files\MATLAB\R2023b\bin\matlab.exe` -> [runSingle.m](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/+sixgr/+lls6g/+runners/runSingle.m) -> system-level LLS runner plus canonical artifact adapter -> MySQL `sim_runs` / `sim_artifacts` / `sim_run_logs` -> browser `/result` and `/analytics`.

The active runtime remains OUR simulator, not a standalone Python harness and not Sionna. For this family the default execution path is an LLS-backed multi-cell waveform path with canonical browser/runtime artifacts, `full_phy` simulation mode, and `full_per_link_channel_waveform_sum` inter-cell interference. Link-to-system/SINR-to-BLER and large-scale-overlap shortcut modes are rejected before MATLAB runtime.

## Inheritance Tree

- Family root:
  [simulator/configs/scenarios/lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml)
- Root inherits:
  [simulator/configs/scenarios/lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml)
- Variants inherit the family root:
  [simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml)
  [simulator/configs/scenarios/variants/SCN01_CELL_EDGE_INTERFERENCE.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN01_CELL_EDGE_INTERFERENCE.yaml)
  [simulator/configs/scenarios/variants/SCN02_HIGH_MOBILITY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN02_HIGH_MOBILITY.yaml)
  [simulator/configs/scenarios/variants/SCN03_XR_LATENCY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN03_XR_LATENCY.yaml)
  [simulator/configs/scenarios/variants/SCN04_UL_CSI_SRS_STRESS.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN04_UL_CSI_SRS_STRESS.yaml)
  [simulator/configs/scenarios/variants/SCN05_ENERGY_AWARE.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN05_ENERGY_AWARE.yaml)
  [simulator/configs/scenarios/variants/SCN06_AI_ML_BENCHMARK.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN06_AI_ML_BENCHMARK.yaml)
  [simulator/configs/scenarios/variants/SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT.yaml)

## Baseline Core Values

The family root resolves the baseline study to:

- Carrier: `4.0e9 Hz`
- Bandwidth: `100e6 Hz`
- Duplex: `TDD`
- SCS: `30 kHz`
- TDD pattern: `DDDDU`
- Deployment: `UMa`
- Sites: `19`
- Sectors per site: `3`
- Total cells: `57`
- Total UEs: `100`
- Wraparound: `true`
- Channel family: `TDL-C`
- Interference mode: `full_per_link_channel_waveform_sum`
- Browser execution mode: `LLS`
- Simulation mode default: `full_phy`
- Output backend: `mysql_web`

## Variant Intent

| Variant | Purpose | Key override |
| --- | --- | --- |
| `SCN00_BASELINE_CAPACITY` | Agreed starting point | Browser-owned baseline system-level LLS truth |
| `SCN01_CELL_EDGE_INTERFERENCE` | Cell-edge overload stress | More hotspot overlap and higher offered load |
| `SCN02_HIGH_MOBILITY` | Doppler / tracking stress | `ue_speed_kmh=120`, faster beam and measurement cadence |
| `SCN03_XR_LATENCY` | XR latency study | XR-only low-latency traffic and latency-aware PF |
| `SCN04_UL_CSI_SRS_STRESS` | UL-heavy waveform/SRS stress | UL-biased traffic, faster SRS, DFT-S-OFDM UL |
| `SCN05_ENERGY_AWARE` | Energy-aware study | Energy-aware PF and active energy instrumentation |
| `SCN06_AI_ML_BENCHMARK` | Explicit optional AI benchmark | Uses `ai_benchmark` runner, not the waveform bundle |
| `SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT` | Reduced PHY reference case | 1 site / 1 cell / 1 UE, TDL-C sanity mode |

## Browser Ownership

Browser `/home` is the authoritative control plane for the family root and SCN00 default. The following groups are actively serialized into `config_json`, resolved into runtime YAML, and consumed by the active coupled LLS path:

- `run_control.*`
- `frequency.*`
- `frame.*`
- `deployment_topology.*`
- `mobility.*`
- `antenna_and_array.*`
- `channels.*`
- `interference.*`
- `reference_signals.*`
- `mimo.*`
- `users.*`
- `control.*`
- `control_gating.*`
- `link_adaptation.*`
- `harq.*`
- `system.scheduler.*`
- `system.measurement.*`
- `system.beam.*`
- `traffic.*`
- `energy_efficiency.*`

The current browser helper intentionally labels `system.handover.*` as secondary rather than fully active, because the coupled runtime exports serving-cell reselection evidence while richer A3-style interruption semantics remain stronger in the separate system runner.

## Canonical Artifact Family

The family root expects the browser to consume canonical DB-backed runtime artifacts first, not stale mirrors. Core artifacts for this family are:

- `meta/scenario_config_resolved.json`
- `meta/scenario_config_resolved.yaml`
- `meta/scenario_source_chain.csv`
- `reports/csv/scenario_summary.csv`
- `reports/csv/runtime_operating_mode.csv`
- `reports/csv/config_roundtrip_verification.csv`
- `reports/csv/browser_runtime_db_consistency.csv`
- `reports/csv/summary_vs_raw_consistency.csv`
- `reports/csv/value_source_audit.csv`
- `reports/csv/config_ownership_matrix.csv`
- `reports/csv/config_exposure_summary.csv`
- `reports/csv/runtime_value_source_dictionary.csv`
- `reports/csv/live_control_gating_summary.csv`
- `reports/csv/live_control_gating_state.csv`
- `reports/csv/live_channel_state_tti.csv`
- `reports/csv/live_rsrp_serving_trace.csv`
- `packet_flow/csv/live_dl_scheduler_grants.csv`
- `packet_flow/csv/live_ul_scheduler_grants.csv`
- `air_interface/csv/dl_pdsch_trials.csv`
- `air_interface/csv/ul_pusch_trials.csv`

## Approximation Boundary

This family is intentionally labeled `full_phy` by default.

What remains waveform-true in the active path:

- real grant generation
- real DL/UL waveform-backed PHY execution per scheduled grant
- raw DL/UL trial truth rows
- real control/reference-signal trial artifacts
- waveform-backed grant replay within the system-level orchestration path

What remains approximated and must stay labeled as such:

- full simultaneous 57-cell all-waveform wall-clock feasibility remains unproven for large campaign profiles
- large-scale-overlap and SINR-to-BLER interference/PHY shortcuts are blocked rather than treated as active runtime truth
- TRS shared receiver tracking is integrated in the coupled runtime, but timing/CFO correction remains limited to real runtime estimates and stays unavailable when no estimate exists
- TDL channel array geometry, which is reduced to runtime-geometry-derived Tx/Rx correlation matrices when metadata is available and remains explicitly count-only when metadata is absent
- richer handover interruption semantics in the coupled LLS browser path
