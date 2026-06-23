# Phase 4 PRACH Occasion Derivation

PRACH occasions are derived from the decoded RACH common configuration and the
resolved frame/TDD timing. The strict anchor exposes occasion, timing, frequency,
and RA-RNTI fields in runtime CSVs.

## Production Path

- `+sixgr/+phy/+ra/buildPRACHConfigFromRACHCommon.m`
- `+sixgr/+rach/mapPRACHToOccasion.m`
- `+sixgr/+phy/+ra/generateMsg1PRACHWaveform.m`
- `+sixgr/+phy/+prach/computeRARNTIFromPRACHOccasion.m`

## Evidence

- `control/csv/msg1_prach_detection.csv`
- `control/csv/ra_state_transitions.csv`
- `control/csv/ra_attempts.csv`
- `control/csv/ra_timer_events.csv`

## Legality Checks

The selected occasion must be legal for the configured TDD slot and symbol
layout. Unsupported, reserved, or contradictory configurations must fail closed
rather than being shifted into a convenient UL symbol.

## Independent Reference

The independent reference for the anchor is the project-owned occasion mapping
and RA-RNTI calculation checked against the strict PRACH and RA tests. Full
versioned 38.213 table coverage remains pending.

## Tests

- `testPRACHConfigStrictValidation`
- `testPRACHMultiOccasionRARNTI`
- `testSIB1ToFourStepRAIntegration`

## Current Status

Anchor occasion derivation is implemented. Exhaustive PRACH table support and
full TDD occasion enumeration are still listed in `phase4_known_limitations.md`.
