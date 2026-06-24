# Phase 5 PDSCH Chain

Status: live PDSCH waveform primitives exist; connected decoded-DCI lineage is
pending.

Existing surfaces:

- `+sixgr/+phy/+dl/PDSCH_Tx.m`
- `+sixgr/+phy/+dl/PDSCH_Rx.m`
- `+sixgr/+pdsch/TBSCalculator.m`
- `tests/testDLPDSCHReceiverEvidenceGate.m`

Phase 5 PDSCH truth requires:

- Grant reconstructed from decoded C-RNTI DCI.
- Exact PRB, symbol, DM-RS, layer, RV, NDI and HARQ process fields.
- Exact RE accounting and TBS reconciliation.
- Receiver estimated channel and noise, not ideal channel or true noise.
- TB CRC driving ACK/NACK, then feedback over PUCCH.
- Packet delivery exactly once after HARQ completion.

Do not pass transmitted TB bits, expected CRC, expected MCS, expected PRBs,
expected symbols, ideal channel, true noise variance or expected ACK into the UE
PDSCH receiver.
