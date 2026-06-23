# Phase 4 Known Limitations

This branch starts the Phase 4 repair program. It does not complete the full
attached acceptance list yet.

## Still Pending

- Versioned machine-readable 38.213 PRACH configuration tables for every supported row.
- Full SSB-to-RO association for all table entries.
- Full false-alarm calibration over enough independent noise-only seeds.
- Full two-UE CDL/RF mobile Phase 4 integration run.
- Same-preamble collision/capture lineage in the mobile scenario.
- Msg3 HARQ retransmission and soft-combining evidence.
- Full RRCSetup ASN.1 coverage beyond the constrained anchor profile.
- Complete Phase4Ok gate across every listed attached-prompt requirement.

## Explicitly Out Of Scope For Phase 4

- RRCSetupComplete.
- Connected-mode UE-specific PDCCH replacement for data scheduling.
- General PUCCH.
- Scheduling request.
- Periodic CSI.
- General connected-mode HARQ.
- SRS.
- TRS.
- Rank adaptation.
- MU-MIMO.
- Final user-plane throughput.
