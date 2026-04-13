# 6G 4 GHz / 100 MHz / 19 Site / 3 Sector / 100 UE Parameter Catalog

## Scope

This document is the scenario-family-facing catalog for `6G_4GHz_100MHz_19S3_100UE_UMa`.

Authoritative schema sources remain:

- [simulator/configs/schema/scenario_parameter_catalog.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/schema/scenario_parameter_catalog.yaml)
- [simulator/configs/schema/scenario_parameter_catalog_extension_01.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/schema/scenario_parameter_catalog_extension_01.yaml)
- [simulator/configs/schema/scenario_parameter_catalog_extension_02.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/schema/scenario_parameter_catalog_extension_02.yaml)
- [simulator/configs/schema/scenario_parameter_catalog_extension_03.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/schema/scenario_parameter_catalog_extension_03.yaml)
- [simulator/configs/schema/scenario_parameter_catalog_extension_04.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/schema/scenario_parameter_catalog_extension_04.yaml)
- [simulator/configs/schema/scenario_parameter_catalog_extension_05.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/schema/scenario_parameter_catalog_extension_05.yaml)

Authoritative family values and overrides remain:

- [simulator/configs/scenarios/lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml)
- [simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml)
- [simulator/configs/scenarios/variants/SCN01_CELL_EDGE_INTERFERENCE.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN01_CELL_EDGE_INTERFERENCE.yaml)
- [simulator/configs/scenarios/variants/SCN02_HIGH_MOBILITY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN02_HIGH_MOBILITY.yaml)
- [simulator/configs/scenarios/variants/SCN03_XR_LATENCY.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN03_XR_LATENCY.yaml)
- [simulator/configs/scenarios/variants/SCN04_UL_CSI_SRS_STRESS.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN04_UL_CSI_SRS_STRESS.yaml)
- [simulator/configs/scenarios/variants/SCN05_ENERGY_AWARE.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN05_ENERGY_AWARE.yaml)
- [simulator/configs/scenarios/variants/SCN06_AI_ML_BENCHMARK.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN06_AI_ML_BENCHMARK.yaml)
- [simulator/configs/scenarios/variants/SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT.yaml](/c:/Anup/6gsimulation/sixgr_foundation_v2%20(2)/simulator/configs/scenarios/variants/SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT.yaml)

## Family-Specific Catalog

The table below focuses on the scenario-family parameters that define the active study surface in the web GUI and the coupled LLS runtime.

| parameter_name | group | datatype | unit | default_value | scenario_override | derived_or_explicit | source_file | source_symbol | notes | baseline_or_study_or_lab_assumption |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `meta.scenario_group` | identity | string | n/a | `6G_4GHz_100MHz_19S3_100UE_UMa` | variant metadata | explicit | family root + variant | `meta.scenario_group` | Scenario-family anchor used by browser/results | baseline |
| `run_control.execution_mode` | runtime | string | n/a | `LLS` | browser-editable | explicit | family root | `run_control.execution_mode` | `/run` only launches this family when `LLS` is selected | baseline |
| `run_control.study_mode` | runtime | string | n/a | `baseline` | variant | explicit | family root + variants | `run_control.study_mode` | Browser-owned study tag | baseline |
| `run_control.simulation_mode` | runtime | string | n/a | `full_phy` | browser-editable | explicit | family root | `run_control.simulation_mode` | Active runs must use waveform-backed grant replay; link-to-system/SINR-to-BLER modes are rejected | baseline |
| `run_control.run_profile` | runtime | string | n/a | `normal` | browser-editable | explicit | family root + variants | `run_control.run_profile` | Browser-facing run-intent label | baseline |
| `run_control.random_seed_master` | runtime | integer | seed | `440100` | browser-editable | explicit | family root | `run_control.random_seed_master` | Seed anchor for reproducibility | baseline |
| `run_control.random_seed_list` | runtime | integer list | seed | `[440100..440104]` | browser-editable | explicit | family root | `run_control.random_seed_list` | Stored in config snapshot and DB | baseline |
| `run_control.num_seeds` | runtime | integer | count | `5` | browser-editable | explicit | family root | `run_control.num_seeds` | Campaign-oriented seed count | baseline |
| `run_control.num_drops` | runtime | integer | count | `20` | browser-editable | explicit | family root | `run_control.num_drops` | Campaign-oriented drop count | baseline |
| `run_control.warmup_time_ms` | runtime | integer | ms | `200` | browser-editable | explicit | family root | `run_control.warmup_time_ms` | Runtime summary metadata | baseline |
| `run_control.measurement_time_ms` | runtime | integer | ms | `1000` | browser-editable | explicit | family root | `run_control.measurement_time_ms` | Runtime summary metadata | baseline |
| `run_control.total_time_ms` | runtime | integer | ms | `1200` | browser-editable | explicit | family root | `run_control.total_time_ms` | Runtime summary metadata | baseline |
| `run_control.batch_size_links` | runtime | integer | links | `1` | browser-editable | explicit | family root | `run_control.batch_size_links` | Coupled grant execution chunk size | lab_assumption |
| `frequency.center_frequency_hz` | spectrum | integer | Hz | `4000000000` | browser-editable | explicit | family root | `frequency.center_frequency_hz` | Required 4 GHz anchor | baseline |
| `frequency.bandwidth_hz` | spectrum | integer | Hz | `100000000` | browser-editable | explicit | family root | `frequency.bandwidth_hz` | Required 100 MHz anchor | baseline |
| `frequency.duplex_mode` | spectrum | string | n/a | `TDD` | browser-editable | explicit | family root | `frequency.duplex_mode` | Baseline duplex choice | baseline |
| `frequency.n_size_grid` | spectrum | integer | RB | `273` | browser-editable | explicit | family root | `frequency.n_size_grid` | Must stay aligned with 30 kHz / 100 MHz numerology | baseline |
| `frame.scs_khz` | frame | integer | kHz | `30` | browser-editable | explicit | family root | `frame.scs_khz` | Baseline numerology anchor | baseline |
| `frame.tdd_pattern` | frame | string | n/a | `DDDDU` | browser-editable | explicit | family root | `frame.tdd_pattern` | Baseline TDD pattern | baseline |
| `waveform.dl_waveform` | waveform | string | n/a | `CP-OFDM` | browser-editable | explicit | family root | `waveform.dl_waveform` | DL waveform family | baseline |
| `waveform.ul_waveform` | waveform | string | n/a | `CP-OFDM` | variant | explicit | family root + SCN04 | `waveform.ul_waveform` | SCN04 switches to DFT-S-OFDM | baseline |
| `deployment_topology.layout_type` | topology | string | n/a | `hexagonal_wraparound` | browser-editable | explicit | family root | `deployment_topology.layout_type` | Browser-facing layout label | baseline |
| `deployment_topology.inter_site_distance` | topology | integer | m | `600` | browser-editable | explicit | family root | `deployment_topology.inter_site_distance` | Macro-site spacing | baseline |
| `deployment_topology.num_sites` | topology | integer | count | `19` | browser-editable | explicit | family root | `deployment_topology.num_sites` | Required exact site count | baseline |
| `deployment_topology.num_sectors_per_site` | topology | integer | count | `3` | browser-editable | explicit | family root | `deployment_topology.num_sectors_per_site` | Required exact sector count | baseline |
| `deployment_topology.num_cells` | topology | integer | count | `57` | browser-editable | explicit | family root | `deployment_topology.num_cells` | Required exact cell count | baseline |
| `deployment_topology.num_ues` | topology | integer | count | `100` | browser-editable | explicit | family root | `deployment_topology.num_ues` | Required exact UE count | baseline |
| `deployment_topology.wraparound_enabled` | topology | boolean | n/a | `true` | browser-editable | explicit | family root | `deployment_topology.wraparound_enabled` | Campaign wraparound guard | baseline |
| `mobility.ue_speed_kmh` | mobility | integer | km/h | `3` | variant | explicit | family root + SCN02 | `mobility.ue_speed_kmh` | High-mobility override reaches runtime Doppler | baseline |
| `channels.profile` | channel | string | n/a | `TDL-C` | variant | explicit | family root + SCN07 | `channels.profile` | Concrete fading profile only | baseline |
| `channels.delay_spread_ns` | channel | integer | ns | `300` | variant | explicit | family root + SCN07 | `channels.delay_spread_ns` | TDL-C reference spread | baseline |
| `channels.doppler_source_mode` | channel | string | n/a | `derive_from_ue_speed` | browser-editable | explicit | family root | `channels.doppler_source_mode` | Keeps speed and Doppler ownership separate | baseline |
| `interference.inter_cell_interference_flag` | interference | boolean | n/a | `true` | browser-editable | explicit | family root | `interference.inter_cell_interference_flag` | Must stay truly enabled | baseline |
| `interference.inter_cell_execution_mode` | interference | string | n/a | `full_per_link_channel_waveform_sum` | variant | explicit | family root + SCN07 | `interference.inter_cell_execution_mode` | No-proxy LLS requires per-link interferer waveform/channel summation; large-scale overlap modes are rejected | baseline |
| `antenna_and_array.bs_num_txrus` | antenna | integer | count | `64` | browser-editable | explicit | family root | `antenna_and_array.bs_num_txrus` | Browser-facing BS antenna abstraction | baseline |
| `antenna_and_array.bs_num_antenna_elements` | antenna | integer | count | `64` | browser-editable | explicit | family root | `antenna_and_array.bs_num_antenna_elements` | Runtime antenna object uses this | baseline |
| `antenna_and_array.ue_num_antenna_elements` | antenna | integer | count | `4` | browser-editable | explicit | family root | `antenna_and_array.ue_num_antenna_elements` | Runtime antenna object uses this | baseline |
| `mimo.n_layers` | mimo | integer | count | `1` | browser-editable | explicit | family root | `mimo.n_layers` | Current family keeps single-layer default | baseline |
| `users.n_users` | users | integer | count | `100` | browser-editable | explicit | family root | `users.n_users` | Canonical multi-user count | baseline |
| `users.execution_model` | users | string | n/a | `slot_coupled_truth` | variant | explicit | family root + SCN07 | `users.execution_model` | Family default stays on coupled truth | baseline |
| `users.beam_selection_strategy` | users | string | n/a | `fixed_first_beam` | browser-editable | explicit | family root | `users.beam_selection_strategy` | Exported explicitly as configured reference | lab_assumption |
| `control.pdcch_enabled` | control | boolean | n/a | `true` | browser-editable | explicit | family root | `control.pdcch_enabled` | Active control-plane ownership | baseline |
| `control.pucch_enabled` | control | boolean | n/a | `true` | browser-editable | explicit | family root | `control.pucch_enabled` | Active coupled PUCCH grant path | baseline |
| `control_gating.srs_required` | control | boolean | n/a | `false` | browser-editable | explicit | family root | `control_gating.srs_required` | Active gating ownership | study_item |
| `control_gating.trs_required` | control | boolean | n/a | `false` | browser-editable | explicit | family root | `control_gating.trs_required` | TRS scheduler-gating hook only | study_item |
| `reference_signals.srs_enabled` | reference_signals | boolean | n/a | `true` | variant | explicit | family root + SCN04 | `reference_signals.srs_enabled` | Active SRS trial path | baseline |
| `reference_signals.trs_enabled` | reference_signals | boolean | n/a | `true` | browser-editable | explicit | family root | `reference_signals.trs_enabled` | Active TRS runtime observation | study_item |
| `reference_signals.srs_periodicity_ms` | reference_signals | integer | ms | `10` | variant | explicit | family root + SCN02/SCN04 | `reference_signals.srs_periodicity_ms` | Variant stress knob | baseline |
| `link_adaptation.fixed_or_amc` | adaptation | string | n/a | `amc` | browser-editable | explicit | family root | `link_adaptation.fixed_or_amc` | Requested policy, not applied grant truth | baseline |
| `link_adaptation.cqi_table` | adaptation | string | n/a | `table1` | browser-editable | explicit | family root | `link_adaptation.cqi_table` | Requested CQI table | baseline |
| `harq.process_count` | harq | integer | count | `16` | browser-editable | explicit | family root | `harq.process_count` | Shared DL/UL process count | baseline |
| `harq.feedback_timing_slots` | harq | integer | slots | `4` | browser-editable | explicit | family root | `harq.feedback_timing_slots` | Active PUCCH/HARQ coupling | baseline |
| `system.scheduler.type` | scheduler | string | n/a | `PF` | variant | explicit | family root + SCN03/SCN05 | `system.scheduler.type` | Active coupled scheduler selection | baseline |
| `system.scheduler.maxActiveUEsPerSlot` | scheduler | integer | count | `16` | browser-editable | explicit | family root | `system.scheduler.maxActiveUEsPerSlot` | Per-cell scheduler cap | baseline |
| `system.measurement.periodSlots` | measurement | integer | slots | `2` | variant | explicit | family root + SCN02 | `system.measurement.periodSlots` | Active measurement cadence | baseline |
| `system.beam.updatePeriod_slots` | beam | integer | slots | `4` | variant | explicit | family root + SCN02 | `system.beam.updatePeriod_slots` | Active beam refresh cadence | baseline |
| `system.handover.enable` | handover | boolean | n/a | `true` | browser-editable | explicit | family root | `system.handover.enable` | Stored and exported, but richer interruption semantics remain secondary in coupled LLS | study_item |
| `traffic.model` | traffic | string | n/a | `mixed` | variant | explicit | family root + SCN03/SCN04/SCN05 | `traffic.model` | Active traffic source | baseline |
| `traffic.transport` | traffic | string | n/a | `MIXED` | variant | explicit | family root + variants | `traffic.transport` | Explicitly labeled if proxy semantics would be needed | baseline |
| `traffic.targetRate_Mbps` | traffic | float | Mb/s | `80` | variant | explicit | family root + variants | `traffic.targetRate_Mbps` | Family throughput/load anchor | baseline |
| `traffic.flows[*].ue_count` | traffic | integer | count | scenario-defined | browser-editable | explicit | family root | `traffic.flows[].ue_count` | Flow ownership partition across 100 UEs | baseline |
| `energy_efficiency.enabled` | energy | boolean | n/a | variant-specific | variant | explicit | SCN05 | `energy_efficiency.enabled` | Only SCN05 turns on richer energy tracing | study_item |
| `ai_ml.enabled` | ai_ml | boolean | n/a | variant-specific | variant | explicit | SCN06 | `ai_ml.enabled` | Explicitly kept in separate benchmark runner | optional_research_experiment |

## Browser-Exposed vs YAML-Only Advanced

Browser-exposed and active in the coupled LLS path:

- `run_control.*`
- `frequency.*`
- `frame.*`
- `deployment_topology.*`
- `mobility.*`
- `channels.*`
- `interference.*`
- `antenna_and_array.*`
- `mimo.*`
- `users.*`
- `control.*`
- `control_gating.*`
- `reference_signals.*`
- `link_adaptation.*`
- `harq.*`
- `system.scheduler.*`
- `system.measurement.*`
- `system.beam.*`
- `traffic.*`
- `energy_efficiency.*`

YAML-only or explicitly secondary for now:

- `system.handover.*` beyond the currently exported reselection evidence
- `scenario.notes`
- `scenario.expected_outputs`
- `meta.research_class`
- `meta.maturity_tag`
- `ai_ml.*` in the SCN06 benchmark runner

## Result Traceability

Family-level parameter ownership is exported into:

- `reports/csv/config_ownership_matrix.csv`
- `reports/csv/config_exposure_summary.csv`
- `reports/csv/runtime_value_source_dictionary.csv`
- `reports/csv/config_roundtrip_verification.csv`
- `reports/csv/browser_runtime_db_consistency.csv`
- `reports/csv/value_source_audit.csv`

Those artifacts, rather than this Markdown file, remain the run-scoped proof that a submitted value reached runtime, DB, CSV, and browser payload intact.
