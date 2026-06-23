# Phase 4 PRACH Receiver

The Phase 4 receiver path is a blind PRACH search over configured candidates for
the monitored occasion. A standalone correlation trace is not sufficient; the
strict RA path requires detector output to feed Msg2 RAR scheduling.

## Production Path

- `+sixgr/+phy/+ra/detectMsg1PRACH.m`
- `+sixgr/+phy/+prach/detectPRACHWaveform.m`
- `+sixgr/+phy/+ra/scheduleMsg2RAR.m`

## Evidence

- `control/csv/msg1_prach_detection.csv`
- `control/csv/ra_oracle_guard.csv`
- `control/csv/msg2_rar_trials.csv`
- `reports/image/msg1_prach_correlation.png`

## Detection Outputs

The detector records preamble candidate, timing, metric, threshold, missed
detection, false alarm, estimated delay, estimated arrival sample, and received
power fields where available.

## No-Oracle Boundary

Forbidden detector inputs include selected UE, selected preamble, exact timing,
exact propagation delay, exact transmit power, exact channel, exact CFO, exact
noise realization, and collision truth.

## Tests

- `testMsg1PRACHWaveformDetection`
- `testPRACHFalseAlarmSweep`
- `testPRACHMissedDetectionSweep`
- `testPRACHOracleGuard`

## Current Status

The strict anchor and PRACH mini-anchor provide blind detection evidence. Full
statistical false-alarm calibration over enough independent seeds is still a
known limitation.
