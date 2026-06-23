# Phase 4 PRACH Power Control

The strict RA anchor records requested and applied PRACH and Msg3 transmit
power. Power values are evidence fields, not labels copied from a success row.

## Production Path

- `+sixgr/+phy/+ra/runFourStepRA.m`
- `+sixgr/+phy/+ra/generateMsg1PRACHWaveform.m`
- `+sixgr/+phy/+ra/generateMsg3PUSCHWaveform.m`

## Evidence

- `control/csv/msg1_prach_detection.csv`
- `control/csv/msg3_pusch_trials.csv`
- `control/csv/ra_attempts.csv`

## Recorded Fields

- `PreambleTxPower_dBm`
- `PreambleTxAmplitudeScale`
- `Msg3Pathloss_dB`
- `Msg3RequestedTxPower_dBm`
- `Msg3TxPower_dBm`
- `Msg3PowerHeadroom_dB`
- `Msg3TxAmplitudeScale`

## No-Oracle Boundary

The PRACH detector may estimate received power from received samples. It must
not receive exact UE transmit power, pathloss truth, or received power truth as
inputs to detection.

## Tests

- `testInitialAccessPowerAndSSBArtifacts`
- `testRAArtifactSchemas`
- `testSIB1ToFourStepRAIntegration`

## Current Status

Anchor evidence is present. Complete multi-attempt ramping and full PCMAX edge
coverage remain future Phase 4 work.
