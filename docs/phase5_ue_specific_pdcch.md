# Phase 5 UE-Specific PDCCH

Status: strict anchor implemented for DCI 1_0 and 0_0; connected grant lineage
pending.

Existing relevant files:

- `+sixgr/+phy/+dl/PDCCH_Tx.m`
- `+sixgr/+phy/+dl/PDCCH_Rx.m`
- `+sixgr/+phy/+pdcch/blindDecodePDCCH.m`
- `+sixgr/+phy/+pdcch/decodeDCIPayload.m`
- `+sixgr/+phy/+pdcch/buildPDCCHConfigFromScenario.m`
- `tests/testPDCCHBlindDecodePositiveDCI10.m`
- `tests/testPDCCHBlindDecodePositiveDCI00.m`
- `tests/testPDCCHWrongRNTIReject.m`

Phase 5 requires the UE to learn its UE-specific CORESET/SearchSpace from
decoded dedicated configuration and to reconstruct PDSCH/PUSCH grants only from
successfully decoded C-RNTI DCI. The UE receiver must not receive scheduler
grant objects, selected candidates, expected PRBs, expected MCS, expected TBS,
or expected CRC.

DCI 1_1 and 0_1 are not currently claimed by the strict mini-anchor.
