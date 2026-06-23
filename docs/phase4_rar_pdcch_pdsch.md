# Phase 4 RAR PDCCH And PDSCH

Msg2 is generated from gNB detector and MAC state, then decoded by the UE from
RA-RNTI PDCCH and RAR PDSCH waveform evidence.

## Production Path

- `+sixgr/+phy/+ra/scheduleMsg2RAR.m`
- `+sixgr/+phy/+ra/generateMsg2RARWaveform.m`
- `+sixgr/+phy/+ra/blindDecodeRARPDCCH.m`
- `+sixgr/+phy/+ra/recoverMsg2RAR.m`
- `+sixgr/+mac/+ra/encodeMACRAR.m`
- `+sixgr/+mac/+ra/decodeMACRAR.m`

## Evidence

- `control/csv/msg2_rar_trials.csv`
- `control/csv/msg2_pdcch_candidates.csv`
- `reports/json/msg2_rar_decoded.json`
- `control/csv/ra_attempts.csv`

## Acceptance Boundary

The UE must recover RAR bytes and the RAPID from the received path before Msg3
resources are considered valid. A direct function argument carrying the grant
from gNB scheduler to UE is not Phase 4 evidence.

## Tests

- `testMsg2RARWaveformDecode`
- `testRANegativeWrongRARNTI`
- `testRANegativeRARWindowExpiry`
- `testRANegativeRAPIDMismatch`

## Current Status

Implemented for the strict anchor. Broader DCI, aggregation, and low-SNR RAR
sweeps remain diagnostic/future coverage.
