# Phase 4 Msg3 HARQ

The full prompt requires Msg3 HARQ retransmission and soft-combining evidence.
The current strict anchor records Msg3 decode success/failure but does not yet
claim complete Msg3 HARQ retransmission support.

## Current Production Touchpoints

- `+sixgr/+phy/+ra/generateMsg3PUSCHWaveform.m`
- `+sixgr/+phy/+ra/recoverMsg3PUSCH.m`
- `+sixgr/+phy/+ra/runFourStepRA.m`

## Existing Evidence

- `control/csv/msg3_pusch_trials.csv`
- `control/csv/ra_attempts.csv`
- `control/csv/ra_negative_trials.csv`

## Required Future Evidence

- HARQ process ID
- redundancy version
- retransmission cause
- soft-buffer lineage
- combining gain
- decoded TB CRC before and after combining

## Tests

- `testRANegativeMsg3CrcFail`
- Future: controlled first-transmission failure with successful retransmission

## Current Status

Pending. Do not set `Phase4Ok` based on Msg3 HARQ until retransmission and
soft-combining evidence are implemented and tested.
