# PRACH LLS

## Architecture

The PRACH LLS lives under `+sixgr/+rach/` and keeps the chain waveform-faithful:

1. `PRACHConfig` resolves and validates a reproducible PRACH study config.
2. `mapPRACHToOccasion` finds concrete PRACH occasions in slot/time space.
3. `generatePRACHSequence` builds the actual toolbox PRACH symbols and indices.
4. `generatePRACHWaveform` maps PRACH onto an occasion grid and OFDM-modulates to time domain.
5. `runPRACHLLS` applies timing offset, CFO, optional phase noise, TDL/CDL/AWGN channel, and noise.
6. `PRACHDetector` performs correlation-based detection and optional residual CFO estimation.
7. `PRACHMetrics` aggregates detection, miss, false-alarm, wrong-preamble, timing, and optional frequency KPIs.

`+sixgr/+link/runPRACHDetection.m` now uses the same `sixgr.rach` chain for single-case PRACH execution, so the repo uses one PRACH Tx/channel/Rx path instead of separate drifting implementations.

## Supported Scenarios

The default runner matrix in `sixgr.rach.runPRACHLLS` includes:

1. FR1, FDD, 700 MHz, PRACH SCS 1.25 kHz, single UE, TDL-C, 3 km/h
2. FR1, 2 GHz, FDD, single UE, CFO enabled
3. 4 GHz, TDD, realistic timing uncertainty
4. 7 GHz, TDD, higher Doppler
5. collision scenario with 2 UEs per RO
6. false alarm scenario with no PRACH transmission
7. inter-cell interference scenario

`scripts/runPRACHStudy.m` can also take a custom `ScenarioMatrix`.

## Outputs

Each run writes under:

`results/prach_lls_<timestamp>/`

Artifacts:

- `scenario_config.json`
- `trial_level_results.csv`
- `summary_by_snr.csv`
- `summary_by_scenario.csv`
- `confusion_detection_types.csv`
- `timing_error_samples.csv`
- `optional_frequency_error_samples.csv` when frequency estimation is active
- `plots/*.png`

## Assumptions

- The PRACH sequence, indices, grid mapping, and OFDM modulation use MATLAB 5G Toolbox NR PRACH APIs.
- PRACH detection is correlation-based with either a fixed threshold or an auto-threshold derived from correlation peak statistics.
- Residual frequency estimation is an optional lab-default phase-increment estimator, not a 3GPP-mandated algorithm.
- Multi-UE and inter-cell cases are superposed in the waveform domain before detection; there is no correlator-domain shortcut.

## Limitations

- The current detector is single-shot per PRACH occasion and returns the strongest detected preamble plus a multi-candidate flag; it is not yet a full multi-peak list decoder.
- Optional type-1/type-2/mixed false-detection labels are study-oriented classifications derived from transmitted serving/interferer truth, not standardized 3GPP output fields.
- The default baseline matrix is intentionally short enough for targeted LLS validation; larger sweeps should be run through `runPRACHStudy` with a custom scenario matrix.

## How To Rerun

```matlab
setup6GRSimToolkit("Verbose", false);
out = runPRACHStudy;
```

For the focused regression:

```matlab
setup6GRSimToolkit("Verbose", false);
testPRACHLLS;
```
