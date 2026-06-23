# Phase 4 RAR MAC PDU

The RAR MAC PDU carries RAPID, timing advance, Temporary C-RNTI, and the Msg3 UL
grant. Phase 4 accepts the RAR only after the UE decodes and parses the received
RAR PDSCH payload.

## Production Path

- `+sixgr/+mac/+ra/encodeMACRAR.m`
- `+sixgr/+mac/+ra/decodeMACRAR.m`
- `+sixgr/+mac/+ra/buildRARULGrant.m`
- `+sixgr/+mac/+ra/validateRARULGrant.m`

## Evidence

- `control/csv/msg2_rar_trials.csv`
- `reports/json/msg2_rar_decoded.json`
- `control/csv/ra_attempts.csv`

## No-Oracle Boundary

The RAR is generated from gNB detection and MAC state. It must not be built from
the UE transmit object or from a known selected preamble shortcut.

## Tests

- `testMsg2RARWaveformDecode`
- `testRANegativeRAPIDMismatch`
- `testMsg3PUSCHFromRARGrant`

## Current Status

Anchor RAR encoding/decoding is implemented. Exhaustive malformed subPDU and
multi-RAPID layout coverage remains future work.
