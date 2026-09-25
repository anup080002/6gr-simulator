# Main development checkpoint — 25 September 2026

This user-requested consolidation preserves the current implementation and
regressions. **It is not a qualified release, a passing eight-point sweep,
or acceptance of the full physical-feedback 400 MHz scenario.**

## Source preservation

- At inventory, local `main` and freshly fetched `origin/main` both pointed
  to `5eb18317`. Only `main` and one worktree exist; no branch merge is needed.
- The checkpoint includes all 224 modified and 194 new source/config/test/tool
  files present at inventory, plus this note and its README link. No source
  reset, history rewrite, or deletion of run evidence is performed.
- Historical patches and recovery stashes are preserved, not blindly reapplied
  over newer implementations. Earlier reconciliation is recorded in
  `main_consolidation_20260923.md` and `repository_consolidation_20260913.md`.
- Generated `results/`, `logs/`, temporary files, environments and local
  settings remain local under the existing ignore rules. A clean Git working
  tree does not mean those retained files were deleted or uploaded.

## Verified scope before consolidation

- `logs/csi_rank_final_export_guards_20260925.log`: six export/integrity and
  E2E semantic guards passed. This is not `testAll`.
- `logs/csi_rank_confirmation_fix_20260925.log`: rank-confirmation/recovery
  logic and two physical CSI hold tests passed.
- `logs/csi_typeii_two_report_handoff_20260925.log`: independent two-report
  Type-II component handoff passed, not complete shared-scenario acceptance.
- `logs/channel_resource_archive_20260925.log`: physical DL/UL channel
  resource archive round-trip and shared HARQ publication checks passed.
- The v20 -10 dB run completed all 58 physical slots with successful access,
  SRS and TRS evidence. It produced zero scheduled DL/UL data grants.
  Current-run recovery gating no longer admits an isolated positive CSI
  report as a new data grant.

## Known failures and intentionally retained regressions

The active run tag is
`5mhz_4tx2rx_m10db_20260925_v20_csi_rank_measurements`, under
`results/lls/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db/`.

- Its required PDCCH and MIMO checks remain failed for missing active data
  control/trial evidence. Finalization raised
  `sixgr:lls6g:runner:MissingSealedPrimaryTrialEvidence` with
  `acquisition_not_proven_failed`; recovery/export was still active at this
  checkpoint. Successful access with no data attempts is not a decoder pass.
- CSI exports drop applied-noise metadata and contain a contradictory SINR
  definition. The standalone reference-SINR publication helper still needs
  production integration. New assertions in
  `testSharedIndependentCSIRSCompletion` expose that pending work and have
  not yet passed against this checkpoint.
- `testModulationTrackingExecutedWork` is a new, unverified regression for
  replacing grid-shape-derived detector complexity with executed counters.
  The corresponding production repair is pending.
- `logs/acquired_no_data_chart_pre_fix_20260925.xml`: 49 focused publication
  tests ran, 46 passed and 3 failed. The failed tests reproduce successful
  acquisition/zero-data chart and data-beam applicability defects. They are
  deliberately retained without skips or weakened assertions.
- PUCCH at slots 24/29/34/39/44/49/54 carries 1 SR + 10 CSI bits and no HARQ.
  Three payloads match; four contain 5/6/4/6 bit errors. The current
  `DetectionOutcome` incorrectly calls a detected-but-wrong payload
  `missed`. This reporting repair remains pending. Eleven-bit UCI has no CRC;
  receiver output availability must not be presented as payload correctness.
- Broad detector statistics, BLER/LLR qualification, cross-path noise
  equivalence, tracking/interpolation measurement repair, full measurement
  catalog CSV/PNG mapping and final 5 MHz/400 MHz acceptance remain open.

No `testAll` is launched for this checkpoint, following the user's explicit
instruction. Existing focused passes do not certify the entire changed tree.
