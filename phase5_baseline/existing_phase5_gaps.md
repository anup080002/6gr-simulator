# Phase 5 Existing Connected-Mode Gaps

This baseline was recorded on branch `fix/phase5-connected-pucch-harq-data`
from parent commit `6efc0155d4c0ea250e1c14eb6e0cc5b86146366f`.

The repository already has useful live components: abstract RRC/SRB1 flow,
PDCP/RLC helpers, MAC CE helpers, PF/RR schedulers, strict C-RNTI PDCCH
mini-anchor tests, PDSCH/PUSCH waveform paths, PUCCH waveform feedback, HARQ
process state, and an LLR soft-combining helper. These are not yet sufficient
to assert the full Phase 5 acceptance criteria.

## Current Fail-Closed Status

| Gate area | Current status | Reason |
|---|---|---|
| RRCSetupComplete ASN.1 | Pending | `+sixgr/+l3/+rrc/RRC.m` encodes RRC messages as UTF-8 JSON for simulator use, not ASN.1/PER. |
| Dedicated CellGroupConfig | Pending | No decoded dedicated configuration installer is mapped for UE and gNB connected context. |
| UE-specific PDCCH | Partial | Strict C-RNTI DCI 1_0/0_0 evidence exists, but connected-mode grant use is not fully wired to UE-side decoded DCI. |
| Dynamic PDSCH/PUSCH grants | Partial | Schedulers and waveform chains exist; Phase 5 requires UE/gNB grant reconstruction only from decoded C-RNTI DCI. |
| PUCCH Format 0/1 HARQ feedback | Partial | Waveform-backed PUCCH evidence exists; connected SR/DTX/NACK policy still needs full runtime gating. |
| SR/BSR/PHR | Partial | BSR/PHR helpers exist; decoded MAC PDU ownership into scheduler state is pending. |
| DL/UL HARQ soft combining | Partial | HARQ process state and LLR combining exist; full connected packet delivery and both-direction buffer persistence remain pending. |
| UE2 slot-24 failure | Pending | The exact failing grant has not been reproduced in this Phase 5 scaffold. |
| Packet delivery | Pending | Full queue-to-radio-to-delivery lineage for at least one DL and UL packet per UE is not yet proven. |

## Non-Claims Preserved

- `Phase5Ok` remains false until every Phase 5 gate has runtime evidence.
- Full scenario `ResultOk` must not be inferred from this scaffold.
- Test traffic before standards-established DRB must be labeled
  `LLS_TEST_DATA_BEARER`, not DRB.
- Phase 5 remains rank 1. Rank-2, multi-layer transmission, MU-MIMO, SRS, TRS,
  CSI-RS, CSI reporting and PUCCH Format 2 CSI are later-phase items.
- Missing primary runtime data must stay empty, skipped, or failed loudly. Do
  not add fallback rows to primary Phase 5 tables.

## Next Runtime Work

1. Add real RRCSetupComplete ASN.1 encode/decode support and keep SIB1 ASN.1
   helpers independent.
2. Install decoded dedicated configuration at UE and gNB, including SRB1,
   PDCCH/PDSCH/PUSCH/PUCCH, SR, BSR, PHR, HARQ timing, and power-control fields.
3. Route scheduler grants through C-RNTI PDCCH and require UE-side blind DCI
   decode before any PDSCH or PUSCH configuration is built.
4. Route DL ACK/NACK/DTX through PUCCH waveform decode only before updating
   gNB DL HARQ state.
5. Route UL scheduling through decoded SR and decoded BSR/PHR state only.
6. Reproduce UE2 slot 24 before changing MCS, seeds, channel, decoder
   iterations, or scheduler behavior.
