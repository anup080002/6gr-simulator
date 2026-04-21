# LLS Technical Report

## Run Metadata

- Scenario ID: `lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_5gnb_50ue_10slot`
- Runtime-qualified description: `Strict waveform-honest NR Rel-20 study-anchor LLS scenario for 4 GHz TDD, 100 MHz, 5 gNBs, 50 randomly placed UEs, and 10 canonical slots launched from the browser-owned MATLAB path. (configured intent; DL dominant effective point layer=2, rank=2, modulation=QPSK, mcs=0 (112/150), configured-match rate 0.0%; UL dominant effective point layer=1, rank=1, modulation=16QAM, mcs=10 (48/96), configured-match rate 0.0%)`
- Config hash: `a1a414876cde1a5883e2a2ab610e6603ef434ebb5b0a934bfcb8df1260a73d7c`
- Code version: `git:2756cfb`
- Random seed: `104729`
- Deterministic mode: `true`
- Run completion: `completed`
- Result OK: `true`
- Partial OK: `false`
- Artifacts generated: `true`
- Required case count: `6`
- Required failure count: `0`
- Optional/pruned case count: `0`
- Status authority: `scenario_status_aggregation_v2_runtime_truth_contract`
- Runtime seconds: `4866.816`
- Covered metrics: `177 / 220`
- Observed runtime metrics: `150`
- Derived metrics: `27`
- Config-only metrics: `12`
- Disabled metrics: `25`
- Placeholder artifacts/metrics: `0`
- Not-supported metrics: `0`
- Not-available metrics: `6`
- Not-exercised metrics: `0`
- Observed-runtime rollup count: `150`
- Config-only rollup count: `12`
- Report-derived rollup count: `27`

## Configured vs Effective Operating Point

- Runtime-qualified scenario text: `Strict waveform-honest NR Rel-20 study-anchor LLS scenario for 4 GHz TDD, 100 MHz, 5 gNBs, 50 randomly placed UEs, and 10 canonical slots launched from the browser-owned MATLAB path. (configured intent; DL dominant effective point layer=2, rank=2, modulation=QPSK, mcs=0 (112/150), configured-match rate 0.0%; UL dominant effective point layer=1, rank=1, modulation=16QAM, mcs=10 (48/96), configured-match rate 0.0%)`
- Configured nominal MIMO: `64x4 nominal rank-2`
- Configured DL nominal operating point: `layers=2, rank=2, modulation=16QAM, mcs=10`
- Configured UL nominal operating point: `layers=2, rank=2, modulation=16QAM, mcs=10`
- Active grid RBs: `273` from `frequency.n_size_grid`
- Configured legacy grid RBs: `273`
- Active duplex mode: `TDD`
- Configured TDD pattern: `DDDSU`
- Active TDD pattern: `DDDSU`
- TDD pattern applicable: `true`
- Effective DL dominant operating point: `layer=2, rank=2, modulation=QPSK, mcs=0 (112/150)`
- Effective DL layer histogram: `2:133|1:17`
- Effective DL rank histogram: `2:133|1:17`
- Effective DL modulation histogram: `QPSK:116|64QAM:30|16QAM:4`
- Effective DL MCS histogram: `0:114|26:24|22:3|11:2|4:1|8:1|13:1|15:1|18:1|20:1|24:1`
- Effective DL configured-match rate: `0.000`
- Effective UL dominant operating point: `layer=1, rank=1, modulation=16QAM, mcs=10 (48/96)`
- Effective UL layer histogram: `1:96`
- Effective UL rank histogram: `1:96`
- Effective UL modulation histogram: `16QAM:51|64QAM:45`
- Effective UL MCS histogram: `10:48|26:35|22:4|24:3|15:2|18:2|13:1|20:1`
- Effective UL configured-match rate: `0.000`
- Effective runtime note: `DL: Runtime-selected operating point diverged from the configured nominal operating point. Dominant effective point: layer=2, rank=2, modulation=QPSK, mcs=0 (112/150). Divergence: dominant recommended RI 1 while transmitted rank remained 2; dominant modulation QPSK vs configured 16QAM; dominant MCS 0 vs configured 10. Exact configured-match rate: 0/150 (0.0%). UL: Runtime-selected operating point diverged from the configured nominal operating point. Dominant effective point: layer=1, rank=1, modulation=16QAM, mcs=10 (48/96). Divergence: dominant layer 1 vs configured 2; dominant rank 1 vs configured 2. Exact configured-match rate: 0/96 (0.0%).`

## Category Coverage

- `A` Run metadata outputs: `6 / 15` covered, `4` observed, `2` derived, `9` config-only, `0` disabled, `0` placeholder, `0` not supported
- `B` Basic PHY performance outputs: `11 / 12` covered, `11` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `C` Coding/decoder outputs: `9 / 11` covered, `9` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `D` Modulation / shaping outputs: `10 / 10` covered, `10` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `E` Channel-estimation / tracking outputs: `11 / 11` covered, `11` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `F` PDCCH/control outputs: `14 / 16` covered, `14` observed, `0` derived, `0` config-only, `2` disabled, `0` placeholder, `0` not supported
- `G` PDSCH outputs: `10 / 11` covered, `10` observed, `0` derived, `0` config-only, `1` disabled, `0` placeholder, `0` not supported
- `H` PUSCH / PUCCH outputs: `9 / 9` covered, `9` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `I` CSI outputs: `15 / 16` covered, `15` observed, `0` derived, `1` config-only, `0` disabled, `0` placeholder, `0` not supported
- `J` Beam-management outputs: `9 / 10` covered, `9` observed, `0` derived, `0` config-only, `1` disabled, `0` placeholder, `0` not supported
- `K` Initial-access / random-access outputs: `16 / 18` covered, `16` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `L` HARQ outputs: `10 / 10` covered, `10` observed, `0` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported
- `M` Energy-efficiency outputs: `13 / 14` covered, `13` observed, `0` derived, `0` config-only, `1` disabled, `0` placeholder, `0` not supported
- `N` Complexity / implementation outputs: `7 / 9` covered, `4` observed, `3` derived, `1` config-only, `1` disabled, `0` placeholder, `0` not supported
- `O` AI/ML outputs: `0 / 18` covered, `0` observed, `0` derived, `0` config-only, `18` disabled, `0` placeholder, `0` not supported
- `P` Debug / trace outputs: `10 / 12` covered, `5` observed, `5` derived, `1` config-only, `1` disabled, `0` placeholder, `0` not supported
- `Q` Aggregated reporting outputs: `17 / 18` covered, `0` observed, `17` derived, `0` config-only, `0` disabled, `0` placeholder, `0` not supported

## Key Artifacts

- `air_interface/csv/lls_kpi_summary.csv`
- `air_interface/csv/lls_snr_sweep.csv`
- `harq/csv/probe_harq_summary.csv`
- `beamforming/csv/probe_beam_management.csv`
- `beamforming/csv/beam_management_state_trace.csv`
- `beamforming/csv/beam_management_event_trace.csv`
- `rf/csv/probe_rf_energy.csv`
- `reports/csv/lls_output_spec_coverage.csv`
- `reports/csv/artifact_inventory.csv`

## Metrics with Real Runtime Values

- `A/execution_timestamp` `started_utc` [derived]: `2026-04-17T11:33:33Z`
- `A/execution_timestamp` `completed_utc` [derived]: `2026-04-17T12:54:40Z`
- `A/warnings_validation_messages` `message_count` [derived]: `1` `count` from `reports/csv/validation_messages.csv`
- `A/effective_layer_histogram` `histogram` [observed]: `2:133|1:17` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_layer_histogram` `dominant_layer` [observed]: `2` `layer_index` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_layer_histogram` `sample_count` [observed]: `150` `count` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_layer_histogram` `histogram` [observed]: `1:96` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_layer_histogram` `dominant_layer` [observed]: `1` `layer_index` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_layer_histogram` `sample_count` [observed]: `96` `count` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_rank_histogram` `histogram` [observed]: `2:133|1:17` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_rank_histogram` `dominant_rank` [observed]: `2` `rank_index` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_rank_histogram` `sample_count` [observed]: `150` `count` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_rank_histogram` `histogram` [observed]: `1:96` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_rank_histogram` `dominant_rank` [observed]: `1` `rank_index` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_rank_histogram` `sample_count` [observed]: `96` `count` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_modulation_histogram` `histogram` [observed]: `QPSK:116|64QAM:30|16QAM:4` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_modulation_histogram` `dominant_modulation` [observed]: `QPSK` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_modulation_histogram` `sample_count` [observed]: `150` `count` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_modulation_histogram` `histogram` [observed]: `16QAM:51|64QAM:45` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_modulation_histogram` `dominant_modulation` [observed]: `16QAM` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_modulation_histogram` `sample_count` [observed]: `96` `count` from `air_interface/csv/ul_pusch_trials.csv`
- `A/effective_mcs_histogram` `histogram` [observed]: `0:114|26:24|22:3|11:2|4:1|8:1|13:1|15:1|18:1|20:1|24:1` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_mcs_histogram` `dominant_mcs` [observed]: `0` `mcs_index` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_mcs_histogram` `sample_count` [observed]: `150` `count` from `air_interface/csv/dl_pdsch_trials.csv`
- `A/effective_mcs_histogram` `histogram` [observed]: `10:48|26:35|22:4|24:3|15:2|18:2|13:1|20:1` from `air_interface/csv/ul_pusch_trials.csv`

## Generated Plots

- `reports/image/bler_vs_snr.png`
- `reports/image/throughput_vs_snr.png`
- `reports/image/nmse_vs_snr.png`
- `reports/image/control_pass_rates.png`
- `reports/image/metric_coverage_by_category.png`
