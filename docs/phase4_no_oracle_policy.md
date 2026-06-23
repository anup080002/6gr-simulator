# Phase 4 No-Oracle Policy

Phase 4 distinguishes UE protocol state, gNB configured search space, and
post-run truth. Production receivers must not consume transmitter truth.

## Forbidden Production Inputs

- selected UE ID
- selected preamble index
- selected root sequence
- selected cyclic shift
- exact transmit timing
- exact propagation delay
- exact transmit power
- exact received power
- exact channel
- exact CFO
- exact noise realization
- collision truth

## Allowed State

The UE may retain its locally selected SSB, PRACH occasion, preamble, RA-RNTI,
RAR window, Temporary C-RNTI, and Msg3 identity as protocol state. The gNB may
know configured PRACH occasions and the configured preamble search space.

## Production Guards

- `RequireDecodedSIB1=true` fails with `UE_RACH_CONFIG_ORACLE_READ` when decoded
  SIB1 RACH ownership is absent.
- `control/csv/ra_oracle_guard.csv` records forbidden field access status.
- Primary artifacts must not promote proxy, fallback, or diagnostic rows as
  strict RA success.

## Tests

- `testSIB1ToFourStepRAIntegration`
- `testRAOracleGuard`
- `testPRACHOracleGuard`

## Current Status

Implemented for the strict anchor. Any new Phase 4 receiver path must extend
the oracle guard before it can contribute to Phase4Ok.
