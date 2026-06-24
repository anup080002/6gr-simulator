# Phase 5 PUSCH Chain

Status: live PUSCH waveform primitives exist; connected SR/BSR/decoded-DCI
lineage is pending.

Existing surfaces:

- `+sixgr/+phy/+ul/PUSCH_Tx.m`
- `+sixgr/+phy/+ul/PUSCH_Rx.m`
- `tests/testULPUSCHReceiverEvidenceGate.m`

Phase 5 PUSCH truth requires:

- UL grant reconstructed from decoded C-RNTI DCI.
- UL MAC PDU containing BSR and PHR when enabled.
- Exact PUSCH RE accounting and TBS reconciliation.
- gNB receiver estimated channel and noise.
- UL HARQ state and retransmission DCI when CRC fails.
- gNB soft-buffer persistence and rate-recovered combining.

Do not pass expected UL TB bits, expected CRC, expected BSR, expected SR state,
ideal channel or true noise variance into the gNB PUSCH receiver.
