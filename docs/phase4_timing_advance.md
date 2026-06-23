# Phase 4 Timing Advance

Timing Advance is derived from Msg1 arrival timing and applied to the Msg3
waveform before gNB reception.

## Production Path

- `+sixgr/+phy/+ra/estimateTimingAdvanceFromPRACH.m`
- `+sixgr/+phy/+ra/applyMsg3TimingAdvance.m`
- `+sixgr/+phy/+ra/runFourStepRA.m`

## Evidence

- `control/csv/msg1_prach_detection.csv`
- `control/csv/msg2_rar_trials.csv`
- `control/csv/msg3_pusch_trials.csv`
- `control/csv/ra_attempts.csv`

## Acceptance Boundary

Msg3 timing must come from decoded RAR Timing Advance state. Comparing a
transmitter-side delay against another transmitter-side delay is not contention
or timing evidence.

## Tests

- `testMsg2RARWaveformDecode`
- `testMsg3PUSCHFromRARGrant`
- `testRAArtifactSchemas`

## Current Status

Anchor timing advance generation and application are implemented. Complete
quantization-boundary, clipping, and residual timing sweeps remain future work.
