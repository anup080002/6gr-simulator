# 6G 4 GHz / 100 MHz / 19 Site / 3 Sector / 100 UE Assumption Traceability

## Purpose

This table separates what this study family treats as:

- baseline assumptions
- study-item assumptions
- lab-only assumptions
- explicit approximation boundaries

The goal is to keep the browser-owned study package honest about what is truly configured and what still remains simplified in the active coupled LLS path.

| Area | Current assumption | Classification | Source | Runtime status | Notes |
| --- | --- | --- | --- | --- | --- |
| Carrier | `4 GHz` | baseline | family root `frequency.center_frequency_hz` | active | Required family anchor |
| Bandwidth | `100 MHz` | baseline | family root `frequency.bandwidth_hz` | active | Required family anchor |
| Duplex | `TDD` | baseline | family root `frequency.duplex_mode` | active | Baseline duplex choice |
| Numerology | `30 kHz`, `273 RB`, `DDDDU` | baseline | family root `frame.*`, `frequency.n_size_grid` | active | Must stay numerically aligned |
| Topology | `19 sites`, `3 sectors/site`, `57 cells`, `100 UEs` | baseline | family root `deployment_topology.*`, `users.n_users` | active | Checked by scenario validation |
| Wraparound | `enabled` | baseline | family root `deployment_topology.wraparound_enabled` | active | Stored in resolved snapshots |
| Channel profile | `TDL-C`, `300 ns` | baseline | family root `channels.profile`, `channels.delay_spread_ns` | active | Concrete fading profile only |
| Deployment scenario label | `UMa` | baseline | family root `deployment_topology.cell_type` | active | Browser-visible scenario identity |
| Inter-cell interference | enabled | baseline | family root `interference.inter_cell_interference_flag` | active | Canonical scheduler grants and raw trials show active interference mode |
| Interference execution mode | `full_per_link_channel_waveform_sum` | baseline | family root `interference.inter_cell_execution_mode` | active | Large-scale overlap shortcuts are rejected in no-proxy LLS mode |
| Simulation mode | `full_phy` | baseline | family root `run_control.simulation_mode` | active | Link-to-system/SINR-to-BLER runtime mode is rejected before MATLAB execution |
| Scheduler | `PF` | baseline | family root `system.scheduler.type` | active | Variants override to latency/energy-aware modes |
| Beam policy | `runtime_best_beam_per_link` | baseline | family root `users.beam_selection_strategy` | active | Exported as runtime beam-selection policy for the active multi-cell study family |
| TRS consumer | shared receiver-tracking state integrated in coupled runtime; scheduler/runtime gating consumes that shared state when configured | study_item | coupled runtime exports and receiver-tracking trace | active | Shared tracking state is active in the runtime path. Timing/CFO correction remains limited to real estimates only and stays unavailable when no runtime estimate exists |
| TDL array handling | runtime-geometry-backed reduced spatial correlation when antenna metadata is available | approximation | channel runtime exports | active | `nrTDLChannel` consumes custom Tx/Rx correlation matrices derived from runtime array geometry; it still does not consume full runtime array objects, pose, element pattern, polarization angles, or per-path angles |
| TR38901 pathloss backend | `nrPathLoss` when available; explicit FSPL fallback or ABG abstraction otherwise | approximation_boundary | channel runtime metadata | active | The runtime now exposes which backend was used so FSPL/ABG can stay labeled approximate instead of being mistaken for TR 38.901 truth |
| Spatial non-stationarity | random placeholder visibility masks | approximation | channel runtime metadata | active | Placeholder masks are now exported as approximate rather than geometry-calibrated truth |
| Phase-noise execution | configured helper backend disclosed; active no-proxy waveform replay does not currently materialize phase-noise impairment | approximation_boundary | waveform impairment replay metadata | active | `PhaseNoiseModel` may resolve to `comm.PhaseNoise` or the Wiener proxy helper, but the active waveform truth path still only replays large-scale gain, timing offset, and CFO |
| PUCCH | explicit coupled grant/resource trace | baseline | coupled runtime exports | active | Deterministic resource assignment remains a lab simplification |
| Handover | reselection evidence in coupled LLS | study_item | `system.handover.*` | secondary | Full A3-style interruption semantics remain richer in the separate system runner |
| Traffic mix | mixed eMBB/FTP3-like/XR/VoIP/UL-heavy | baseline | family root `traffic.*` | active | Browser-owned and config-driven |
| FTP3-like flow | UDP-labeled approximation, not truthful TCP | lab_assumption | family root `traffic.flows[ftp3_bursty_broadband]` | active | Proxy TCP shaping is forbidden in strict no-proxy mode |
| AI/ML benchmark | separate `ai_benchmark` runner in SCN06 | optional_research_experiment | SCN06 variant | separate mode | Explicitly not folded into SCN00 waveform-bundle truth |
| SCN07 | reduced reference-equivalent single-link mode | baseline_benchmark | SCN07 variant | active | Keeps PHY sanity checks inside the same repo architecture |

## Approximation Boundary Summary

The following components are still approximated and must remain labeled as such in browser/runtime artifacts:

- `run_control.simulation_mode = full_phy`
- `interference.inter_cell_execution_mode = full_per_link_channel_waveform_sum` in the family root
- TDL channel array handling uses a reduced runtime-geometry correlation adapter when metadata is available; it falls back to explicit count-only status when runtime geometry is absent
- TR38901 large-scale pathloss must stay labeled with its actual backend: `nrPathLoss` when available, `free_space_path_loss_fallback` or ABG abstraction otherwise
- spatial non-stationarity remains a random placeholder visibility model and must not be described as geometry-coupled truth
- TRS shared receiver tracking is integrated, but timing/CFO correction remains estimate-driven and unavailable whenever no runtime estimate exists
- configured phase noise is not currently materialized in the active no-proxy waveform replay path and must remain labeled that way
- coupled LLS serving-cell reselection evidence without full system-runner handover interruption semantics

## Truth Artifacts To Check

For any real run of this family, the assumption boundary above should be corroborated by:

- `reports/csv/runtime_operating_mode.csv`
- `reports/csv/value_source_audit.csv`
- `reports/csv/config_ownership_matrix.csv`
- `reports/csv/browser_runtime_db_consistency.csv`
- `packet_flow/csv/live_dl_scheduler_grants.csv`
- `packet_flow/csv/live_ul_scheduler_grants.csv`
- `air_interface/csv/dl_pdsch_trials.csv`
- `air_interface/csv/ul_pusch_trials.csv`
