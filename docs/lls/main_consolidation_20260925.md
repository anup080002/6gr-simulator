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

## Later same-day source consolidation

This section updates the earlier snapshot above; it does not rewrite the
identity or outcomes of retained runs. The user requested preservation of all
current edits and the 400 MHz / 7 GHz Keysight instructions on one branch.

### Preserved changes

- Freshly fetched `origin/main` and local `main` matched `1b8c24d9` before
  this update. There is one local branch and one worktree; no branch merge
  or history rewrite is needed. All 19 outstanding source/test files are
  included, together with this note and the README update.
- Independent CSI-RS publication now retains executed noise-calibration
  metadata for audit and separately labels measured reference SINR and the
  selected-precoder receiver objective. Audit metadata does not replace
  receiver estimates.
- DL/UL trial exports now carry instrumented equalizer solve/factorization
  counters. Grid-size products are no longer presented as measured detector
  operation counts.
- Completed physical execution with no data grants is distinguished from
  failed acquisition and from lost receiver evidence. Publication keeps data
  measurements unavailable and scenario acceptance failed; it does not invent
  a constellation or successful data rows.
- README commands and output locations refer to the existing rank-2
  400 MHz bandwidth / 7 GHz carrier lab test, not a 4 GHz carrier test.
  Its disabled control/feedback and experimental UL limitations remain stated.

### Verification at this consolidation checkpoint

- `logs/main_source_consolidation_20260925.xml`: **67 Python tests passed**,
  covering completed-no-data publication and lab waveform packaging. Only
  dependency deprecation warnings were emitted.
- `logs/5mhz_core_measurement_repair_20260925.log`: the CSI reference
  publication, independent CSI completion and executed-work tests passed.
  The 96-case noise-estimator diagnostic completed, but completion does not
  mean its measured estimator bias is fixed.
- The existing 18-test focused MATLAB batch has **13 completed passes and
  no recorded failures at this snapshot**. This includes DL/UL/reference
  points, config, strict proxy guards, scheduler consistency, export/artifact
  guards and `testE2E_FastVsTruth`. `testE2E_TruthPacketSemanticCampaign`
  and later tests are not claimed as passed until their completion records.
  Log: `logs/5mhz_core_measurement_guards_20260925.log`.
- The already queued runtime follow-up and an integrated target-scenario rerun
  are not counted as completed verification. Neither `testAll` nor a new
  scenario execution is launched by this consolidation.
- The sealed lab-package root manifest still has SHA-256
  `dbfd394b1b1781461e41f64b8475531931050c2dbdc32f6d95bda3756a67d60b`.
  This check confirms the manifest is unchanged; the earlier complete
  artifact verification is documented in `vxg_vsa_validation_20260925.md`.

The pending PUCCH detection-label defect, generic CSI noise-estimator bias,
statistical qualification and full shared-scenario acceptance are not closed
by committing this work. The 400 MHz lab package still retains its 30 dB
decoding failures and `PHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN`.

Both historical recovery stashes remain preserved; their documented
integration commits `cd397f33` and `471334ff` were verified as ancestors of
`main`. They are not reapplied over newer code. Generated results, logs and
the approximately 12 GB lab package remain local under existing ignore rules,
not deleted for a clean working tree and not silently included in the push.

## PUCCH reporting checkpoint

This later checkpoint includes `f20b73e7` on the same `main` branch. Receiver
signal detection is now exported independently of UCI payload correctness:
detected but corrupted payloads remain failed payloads, not missed detections.
Invalid detector metrics remain unavailable and fail closed. No detection
threshold, decoder decision or physical acceptance gate was relaxed.

Verified retained evidence:

- `logs/pucch_detection_outcome_20260925.log`: **8/8 focused MATLAB tests
  passed**, including actual waveform, independent receiver, receive-only
  shared clock and export checks.
- `logs/pucch_detection_publication_20260925_v2.xml`: **99/99 Python tests
  passed**, with zero failures, errors or skips.
- The earlier batches have now finished: `logs/5mhz_core_measurement_guards_20260925.log`
  reports **18/18 passed**, and `logs/5mhz_core_runtime_followup_20260925.log`
  reports **4/4 passed**. These were run before the latest PUCCH reporting
  commit and do not replace final-source full-scenario acceptance.

The detector is **not statistically qualified**. The focused format-2
component matrix detected all four tested noise-only observations; those
failures are retained in
`logs/tp4f0e02d6_30f4_4255_a4dc_ca9f2685f920/receiver_presence_and_payload.csv`.
A reporting-test pass confirms faithful publication, not an acceptable
false-detection rate. Generic CSI estimation bias and full measurement,
5 MHz sweep and physical-feedback 400 MHz acceptance remain open.

The eight-point 5 MHz sweep was already running when this documentation-only
consolidation was made. Its tag is
`5mhz_4tx2rx_snr_sweep_20260925_v21_pucch_presence`, with the matching log
under `logs/` and results under
`results/lls/lls_tdd_5mhz_rank2_shared_awgn_snr_sweep/`. No completed sweep
result is claimed here. No active MATLAB/YAML source was changed, no process
was restarted and no `testAll` was launched for this consolidation.

The README's dedicated 400 MHz section identifies the **7 GHz carrier,
400 MHz bandwidth, rank-2 VXG/VSA lab experiment**, its exact Windows commands,
output locations and hardware handoff files. Its sealed package and historical
measurements are unchanged. Generated artifacts and both historical recovery
stashes are preserved locally; only source, tests, configuration and documentation
are delivered through Git.
