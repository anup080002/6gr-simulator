# 6GR PDSCH Truth LLS

## Architecture

The truthful 6GR PDSCH chain lives in `+sixgr/+pdsch` and is built on top of the existing real PHY transmitter and receiver:

- `PDSCHStudyConfig` resolves and validates the study config.
- `FDRAAllocator` and `TDRAAllocator` materialize actual PRB and symbol occupancy.
- `PDSCHWaveformBuilder` performs queue-limited grant fitting before transmit, builds the actual DL-SCH/PDSCH waveform, and maps DMRS and optional PTRS.
- `PDSCHReceiver` performs OFDM demodulation, optional PTRS common-phase correction, DMRS-based channel estimation, equalization, demodulation, DL-SCH decoding, and CRC-based pass/fail.
- `runPDSCHStudyLLS` runs scenario sweeps and exports truthful trial/TB/codeword/grant metrics and plots.

## Shortcuts Removed Or Demoted

The active truth path does not use:

- scalar SINR-to-throughput lookup as the truth KPI source
- post-decode throughput clipping
- fake DMRS or PTRS mapping disconnected from the scheduled allocation
- HARQ pass/fail disconnected from CRC
- silent ideal channel estimation in realistic runs

One scheduling-side study approximation remains explicit:

- `AMCSelector` can run `study_amc_from_estimated_snr_not_from_truth_kpi` when `mcs_mode=amc`. This only chooses the attempted MCS. BLER and throughput still come from the real PHY/CRC chain.

## Baseline Assumptions

- CP-OFDM baseline
- single-codeword truth path
- NR-baseline codeword-to-layer mapping with spatial-first, frequency-second, time-third ordering
- realistic DMRS-based channel estimation for truth runs
- MMSE equalization baseline inside the active receive path
- cross-slot PDSCH and MU-MIMO remain explicit study hooks and fail loudly if requested in the active truth path

## Study Knobs Vs Frozen Behavior

Supported truth knobs:

- FDRA: `type0_bitmap`, `type1_riv`, `dynamic`
- TDRA: flexible `start_symbol` and `num_symbols`
- repetition: `none`, `intra_slot`, `inter_slot`
- DMRS additional position / ports
- PTRS enable and densities
- channel model / delay spread / speed / SNR
- rank within the current single-codeword truth path

Explicit study hooks or not-yet-materialized items:

- cross-slot PDSCH
- MU-MIMO DMRS assistance assumptions
- non-transparent transmit diversity
- AI/ML low-overhead DMRS model execution

These remain exposed as hooks and must not be mislabeled as truth support.

## How To Run

Scenario runner:

```matlab
setup6GRSimToolkit('Verbose',false);
out = sixgr.lls6g.runners.runSingle('simulator/configs/scenarios/pdsch_6gr_truth_study.yaml','results','pdsch6gr_smoke');
```

Study script presets:

```matlab
setup6GRSimToolkit('Verbose',false);
out = run6GRPDSCHStudy('simulator/configs/scenarios/pdsch_6gr_truth_study.yaml','preset1_fr1_baseline');
```

## Outputs

Outputs are written under:

- `results/pdsch6gr_truth_<timestamp>/`

Key files:

- `scenario_config.json`
- `trial_level_results.csv`
- `tb_level_results.csv`
- `codeword_level_results.csv`
- `layer_mapping_trace.csv`
- `fdra_allocations.csv`
- `tdra_allocations.csv`
- `dmrs_mapping.csv`
- `ptrs_mapping.csv`
- `channel_estimation_metrics.csv`
- `parameter_estimation_metrics.csv`
- `harq_trace.csv`
- `summary_by_*.csv`
- `complexity_summary.csv`

## Known Limitations

- The active truth path is single-codeword only.
- Cross-slot PDSCH is a study hook, not materialized.
- PTRS compensation is currently a single common-phase estimate per copy.
- `ReceiverType=MMSE_IRC` is reported as the study baseline, but the active equalization call is toolbox MMSE rather than a fully separate IRC implementation.
- The AI/ML low-overhead DMRS preset is only a hook for future model integration and does not yet run a learned model.

## Next 3GPP Study Extensions

- true multi-codeword support
- cross-slot PDSCH materialization
- fuller MMSE-IRC interference-aware receiver
- explicit MU-MIMO co-scheduled DMRS assistance signaling
- richer parameter estimation and FR2 PTRS/phase-noise studies
