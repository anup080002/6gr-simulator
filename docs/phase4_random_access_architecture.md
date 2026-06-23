# Phase 4 Random-Access Architecture

Phase 4 covers only initial random access through Msg4 contention resolution.
It does not promote the UE to `RRC_CONNECTED` and does not start connected-mode
PUCCH, CSI, SRS, TRS, rank adaptation, MU-MIMO, or user-plane scheduling.

## Implemented Anchor Flow

1. UE recovers SSB/PBCH/MIB/SIB1 from waveform evidence.
2. `installDecodedSIB1RACHConfig` installs receiver-owned common-cell and RACH configuration.
3. `runFourStepRA` is called with `RequireDecodedSIB1=true` for Phase 4 entry points.
4. Msg1 PRACH is generated from the decoded RA configuration.
5. gNB PRACH detection produces timing, metric, threshold, and preamble evidence.
6. gNB schedules Msg2 RAR from detector/MAC state.
7. UE decodes RA-RNTI PDCCH and RAR PDSCH.
8. UE derives Msg3 resources from decoded RAR UL grant.
9. gNB decodes Msg3 PUSCH and the anchor RRCSetupRequest payload.
10. gNB sends Msg4 contention-resolution payload.
11. UE decodes Msg4 and compares decoded identity against UE-local Msg3 identity.
12. Temporary C-RNTI is promoted only after contention resolution succeeds.

## No-Oracle Boundary

The Phase 4 integrated entry points must not read UE RACH common configuration
directly from YAML after SIB1 acquisition. If decoded SIB1 evidence is missing,
`runFourStepRA(..., "RequireDecodedSIB1", true)` fails with
`UE_RACH_CONFIG_ORACLE_READ`.

Standalone RA diagnostics may still use `scenario_config_pending_sib1` to test
lower-level PRACH/RAR/Msg3/Msg4 mechanics before SIB1 is present. Those runs are
not Phase 4 completion evidence.

## Primary Evidence

- `control/csv/rach_config_from_decoded_sib1.csv`
- `reports/csv/phase4_decoded_config_ownership_audit.csv`
- `control/csv/ra_attempts.csv`
- `control/csv/msg1_prach_detection.csv`
- `control/csv/msg2_rar_trials.csv`
- `control/csv/msg2_pdcch_candidates.csv`
- `control/csv/msg3_pusch_trials.csv`
- `control/csv/msg4_contention_resolution.csv`
- `control/csv/ra_oracle_guard.csv`
- `control/csv/initial_access_lifecycle_trace.csv`

## Current Standards Scope

The implementation is a constrained anchor profile. Unsupported PRACH
restricted sets and unsupported SIB1 IEs fail closed. Full 38.213
CORESET0/SearchSpace0 and PRACH table coverage is not claimed.
