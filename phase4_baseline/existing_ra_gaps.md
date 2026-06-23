# Phase 4 Baseline RA Gaps

This baseline was created on branch `fix/phase4-true-prach-four-step-ra`.

## Fixed In This Slice

- Phase 4 RA entry points can require decoded SIB1 ownership via `RequireDecodedSIB1`.
- Integrated initial-access RA paths now fail closed with `UE_RACH_CONFIG_ORACLE_READ` when decoded SIB1 is missing.
- The supported SIB1 anchor profile carries PRACH Msg1 SCS and restricted-set ownership.
- Decoded SIB1 ownership artifacts are exported as `rach_config_from_decoded_sib1.csv` and `phase4_decoded_config_ownership_audit.csv`.

## Remaining Real Gaps

- Full 38.213 PRACH configuration tables are not implemented as versioned machine-readable data.
- Full SSB-to-RO mapping across all supported table entries remains pending.
- Two-UE CDL/RF end-to-end Phase 4 integration is not yet proven.
- Same-preamble collision/capture lineage is partially tested but not complete for the mobile scenario.
- Msg3 HARQ retransmission and soft-combining are not complete Phase 4 evidence yet.
- Full RRCSetup ASN.1 coverage is still constrained to the repository anchor profile.
- Phase4Ok is not yet defined as a complete scenario gate.

No placeholder primary rows were added for pending items.
