# 6G PHY LLS Sweep Framework

## Goals

The sweep framework must support native campaign generation without custom scripts.

It must support:

- SNR/SINR sweeps
- delay spread sweeps
- speed sweeps
- impairment sweeps
- bandwidth sweeps
- antenna/rank/beam/TRP sweeps
- AI/ML generalization sweeps

## Native Sweep Mechanisms

There are two native mechanisms:

1. `scenario.runner_profile='generic_sweep'`
2. matrix execution through `run_6g_phy_lls_matrix`

## Generic Sweep Structure

```yaml
scenario:
  runner_profile: generic_sweep
  target_cases: [bundle]
  notes: Delay-spread sweep
  sweep:
    base_profile: waveform_bundle
    output_name: delay_spread_sweep
    overrides:
      - label: ds_30ns
        config:
          channels:
            delay_spread_ns: 30
      - label: ds_100ns
        config:
          channels:
            delay_spread_ns: 100
      - label: ds_300ns
        config:
          channels:
            delay_spread_ns: 300
```

## SNR / SINR Sweeps

Use:

- `simulation.snr_db`
- `simulation.snr_sweep_offsets_db`

For interference-oriented studies, create scenario overrides that change:

- beam overlap
- channel profile
- interference model settings
- receiver type

## Delay Spread Sweeps

Sweep:

- `channels.delay_spread_ns`
- `channels.profile`

Recommended anchor values:

- `30`
- `100`
- `300`
- `1000`

## Speed Sweeps

Sweep:

- `channels.mobility_kmph`
- `channels.doppler_hz`

Recommended anchor values:

- `3`
- `10`
- `120`
- `350`
- `500`

## Impairment Sweeps

Sweep:

- `impairments.cfo_hz`
- phase-noise enable and severity packs
- IQ imbalance
- PA nonlinearity
- ADC/DAC quantization bits
- timing offset

## Bandwidth Sweeps

Sweep:

- `frequency.bandwidth_hz`
- optionally `frame.scs_khz` where band policy allows it

Anchor values already represented in the required packs:

- `5 MHz`
- `20 MHz`
- `100 MHz`

## Antenna / Rank / Beam / TRP Sweeps

Sweep:

- `mimo.n_tx_ant`
- `mimo.n_rx_ant`
- `mimo.n_layers`
- `mimo.beam_count`
- `mimo.panel_count`
- `mimo.trp_count`
- `mimo.precoding_granularity`

This family covers:

- SU-MIMO rank sweeps
- MU-MIMO user-count sweeps
- beam count sweeps
- panel-count sweeps
- multi-TRP sweeps

## AI/ML Generalization Sweeps

Sweep:

- `ai_ml.model_id`
- `ai_ml.model_version`
- `ai_ml.download_mode`
- `ai_ml.benchmark_observations`
- mismatch conditions such as band, delay spread, speed, SNR, or impairment shifts
- explicit fallback-to-non-AI enable/disable comparisons

Every AI sweep should include:

- one or more AI cases
- one non-AI baseline case
- fallback metrics

## Matrix Campaign Structure

Use the matrix runner when the campaign is best described as a list of scenario configs instead of inline overrides.

Example shape:

```yaml
meta:
  matrix_id: ai_generalization_regression
execution:
  repeat_count: 1
  stop_on_failure: false
  max_parallel_jobs: 4
  save_combined_summary: true
scenarios:
  - simulator/configs/scenarios/ce_non_ai_baseline.yaml
  - simulator/configs/scenarios/ce_ai_nn.yaml
  - simulator/configs/scenarios/csi_non_ai_baseline.yaml
  - simulator/configs/scenarios/csi_ai_autoencoder.yaml
```

## Sweep Output Requirements

Every sweep should write:

- per-case run folder
- sweep summary CSV
- matrix combined summary when using matrix mode
- per-case manifest and report
- stable labels for each override case

## Deterministic Sweep Ordering

Sweep execution must be reproducible:

- override cases execute in declared order
- matrix scenario list order is preserved unless explicit independent parallelism is requested
- seeds remain deterministic across reruns
