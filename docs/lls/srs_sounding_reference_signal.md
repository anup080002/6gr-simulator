# Strict SRS Sounding Reference Signal

`AUD-SRS-001` is closed for the explicit `srs_strict_validation` mini profile.
This is NR-baseline/study behavior, not a normative 6G conformance claim.

## Implemented Profile

- Scenario: `configs/lls/lls_srs_strict_mini_anchor.yaml`
- Runner profile: `srs_strict_validation`
- Carrier/BWP: FR1 4 GHz, 30 kHz SCS, 24 RB
- SRS resource: periodic, non-codebook, one port, one symbol, comb 2, full-carrier PRB coverage
- Receiver: gNB regenerates expected SRS resources from allowed config, extracts received REs, correlates with the configured SRS sequence, and estimates the UL channel by LS on SRS REs

## Truth Rules

- Strict SRS success requires `DetectionAttempted`, `ResourceExtractionAttempted`, `ChannelEstimateAttempted`, and `SRSChannelEstimateAvailable`.
- Full-carrier claims require actual SRS PRB coverage to be `full_carrier`.
- Partial-band SRS may be valid only when the scenario explicitly allows partial-band evidence.
- Aperiodic SRS requires decoded DCI trigger provenance; missing trigger evidence fails closed.
- Semi-persistent activation is unsupported in this profile and fails closed.
- Receiver pass/fail does not use transmitter-private SRS symbols, transmitted indices, channel taps, perfect channel estimate, or success labels.

## Artifacts

- `reference_signals/csv/srs_config_strict.csv`
- `reference_signals/csv/srs_resource_sets.csv`
- `reference_signals/csv/srs_resources.csv`
- `reference_signals/csv/srs_resource_mapping.csv`
- `reference_signals/csv/srs_tx_waveform.csv`
- `reference_signals/csv/srs_rx_extraction.csv`
- `reference_signals/csv/srs_detection_metrics.csv`
- `reference_signals/csv/srs_channel_estimation.csv`
- `reference_signals/csv/srs_coverage.csv`
- `reference_signals/csv/srs_trigger_events.csv`
- `reference_signals/csv/srs_negative_trials.csv`
- `reference_signals/csv/srs_low_snr_sweep.csv`
- `reference_signals/csv/srs_timing_offset_sweep.csv`
- `reference_signals/csv/srs_multi_ue_trials.csv`
- `reference_signals/csv/srs_oracle_guard.csv`
- `air_interface/csv/srs_trials.csv`
- `reports/json/srs_toolbox_capabilities.json`

## Negative Evidence

The strict runner exports falsification rows for no signal, wrong sequence ID,
wrong resource mapping, wrong comb/cyclic shift, wrong port, corrupted symbols,
partial band claimed as full carrier, and missing aperiodic DCI trigger.

## Known Limitations

- Only the one-port periodic strict mini profile is accepted as implemented.
- Advanced SRS usages, antenna switching, positioning SRS, broad FR2 coverage,
semi-persistent activation, and frequency-hopping profiles beyond the explicit
coverage gate are unsupported unless separate waveform evidence is added.
- SRS-derived channel quality can be consumed by downstream UL scheduling or
rank/beam modules only through explicit evidence references; this does not close
UL SINR, MIMO/rank, HARQ, or KPI-goodput blockers by itself.
