# Strict TRS Tracking Reference-Signal Anchor

`AUD-TRS-001` is closed for the explicit `trs_strict_validation` mini profile.
This is a waveform-backed NR-baseline tracking-reference validation anchor, not
a blanket claim that every reference-signal family is complete.

## Implemented Path

- Scenario: `configs/lls/lls_trs_strict_mini_anchor.yaml`
- Runner profile: `trs_strict_validation`
- PHY package: `+sixgr/+phy/+trs`
- Runtime gate: `sixgr.truth.CoupledTruthRuntime.applyTRSTrial`
- Truth contract: `sixgr.truth.evaluateLLSRuntimeTruthContract`

The strict TRS path derives an NZP-CSI-RS/TRS resource from resolved YAML,
generates and maps the resource into a carrier grid, executes OFDM waveform and
AWGN channel processing, and validates receiver-side evidence for detection,
timing tracking, CFO/frequency tracking, and channel estimation.

## Required Evidence

Strict TRS acceptance requires all of these to be true in runtime rows:

- Detection was attempted and succeeded.
- Timing tracking was attempted and produced a finite timing estimate.
- Frequency/CFO tracking was attempted and produced a finite CFO estimate.
- Channel estimation was attempted and produced finite NMSE evidence.
- No proxy, skipped, toolbox-missing, or oracle-only fields were used.

Metric-only rows, old rows without attempted/available fields, and rows with
missing timing/CFO/channel evidence fail the TRS-required runtime gate.

## Exported Artifacts

The strict mini-run writes:

- `reference_signals/csv/trs_config_strict.csv`
- `reference_signals/csv/trs_trials.csv`
- `reference_signals/csv/trs_resource_mapping.csv`
- `reference_signals/csv/trs_detection_metrics.csv`
- `reference_signals/csv/trs_timing_tracking.csv`
- `reference_signals/csv/trs_frequency_tracking.csv`
- `reference_signals/csv/trs_channel_estimation.csv`
- `reference_signals/csv/trs_coverage.csv`
- `reference_signals/csv/trs_negative_trials.csv`
- `reference_signals/csv/trs_low_snr_sweep.csv`
- `reference_signals/csv/trs_timing_offset_sweep.csv`
- `reference_signals/csv/trs_frequency_offset_sweep.csv`
- `reference_signals/csv/trs_oracle_guard.csv`
- `air_interface/csv/trs_trials.csv`

JSON, text, binary, and figure artifacts are exported from the same executed
evidence. Unsupported TRS profiles must fail closed rather than emitting
placeholder truth rows.

## Validation

Focused validation covers positive detection, timing, CFO, channel estimation,
negative no-signal/wrong-config/corruption/missing-resource cases, low-SNR and
offset sweeps, oracle guards, artifact schemas, and truth-contract invariants.

The current closure does not mark SRS, PTRS, or broad DMRS/CSI-RS conformance as
fixed. Those remain separate backlog items unless equivalent waveform evidence
and strict gates are added.
