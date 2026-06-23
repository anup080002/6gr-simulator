# Phase 4 PRACH Sequence And Waveform

Msg1 uses a generated PRACH waveform, not a CSV-only or expected-preamble
shortcut. The strict anchor records sequence, waveform, resource, and detection
hashes so that Msg1 evidence can be audited after the run.

## Production Path

- `+sixgr/+phy/+ra/generateMsg1PRACHWaveform.m`
- `+sixgr/+phy/+prach/generatePRACHWaveform.m`
- `+sixgr/+rach/generatePRACHSequence.m`
- `+sixgr/+phy/+ra/detectMsg1PRACH.m`

## Evidence

- `control/csv/msg1_prach_detection.csv`
- `control/csv/ra_attempts.csv`
- `control/csv/ra_artifact_manifest.csv`
- `reports/image/msg1_prach_correlation.png`

## No-Oracle Boundary

The waveform generator knows the UE-selected preamble because it is the
transmitter. The gNB detector must perform candidate search from the configured
occasion/preamble space and must not receive the selected preamble as a
production input.

## Tests

- `testPRACHWaveformGeneration`
- `testMsg1PRACHWaveformDetection`
- `testPRACHWaveformDetectionPositive`
- `testPRACHOracleGuard`

## Current Status

Waveform-backed Msg1 is implemented for the strict anchor and PRACH mini-anchor.
All-format PRACH sequence coverage, every restricted-set case, and complete
38.211/38.213 table row validation remain future work.
