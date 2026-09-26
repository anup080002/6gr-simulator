# Main consolidation — 26 September 2026

This is a source-preservation development checkpoint, not a qualified release.
The requested test is **400 MHz bandwidth at 7 GHz**, not a 4 GHz-carrier test.
The exact Windows Command Prompt launcher, YAML, recorded WebGUI command and
Keysight file mapping are in the [README](../../README.md#400-mhz--7-ghz-rank-2-keysight-waveform-demonstration).

## Source inventory and preservation

- Base `c5cdde8641089c5b7f1ed4912a9880836303a64d` matched freshly fetched
  `origin/main`. Only the `main` branch and one Git worktree exist; there is
  no separate branch to merge and no history rewrite is needed.
- All five outstanding source/test files are included: the standalone HARQ
  diagnostics repair, its new spatial-authority test, test registration, and
  the two configured-CSI clock regression updates. Assertions are retained.
- Two receiver-core candidate edits were developed in a temporary source
  snapshot to avoid changing the active sweep's receiver. Their complete diff
  is now versioned in
  [pending_received_csi_pucch_clock_20260926.patch](pending_received_csi_pucch_clock_20260926.patch).
  `git apply --check` passes against this checkpoint's unchanged receiver
  files. This is a preservation/applicability check, **not runtime verification**.
  Do not automatically apply this patch during an active execution.
- The candidate passes the causally received SRS clock into configured CSI
  PUCCH reception, retains it in observation evidence, and distinguishes an
  inapplicable clock from malformed configuration. It changes neither UCI
  ownership nor detector thresholds. At the initial checkpoint, integration
  and focused execution were pending. The follow-up below records the now
  completed candidate tests; `testConfiguredCSIReceivedClock` remains a known
  failing regression against the unchanged installed receiver.
- Both historical recovery stashes are preserved. Their previously documented
  integration commits `cd397f33` and `471334ff` are ancestors of `main`; the
  stashes are not blindly reapplied over newer source.
- `results/`, `logs/`, temporary snapshots and generated instrument files remain
  local under existing ignore rules. No cleanup deletes evidence. GitHub
  contains the source, YAMLs, tests, documentation and preserved pending patch,
  not the multi-GB IQ/results bundle.

## Implemented repair and verified scope

`+sixgr/+truth/exportLLSHARQDiagnostics.m` previously bypassed the explicit
AWGN spatial matrix. Halving the configured channel amplitude reduced power
to 0.25 in the main channel but left probe signal power unchanged at 1.0.
The probe now uses the existing `ChannelFactory` sample operator before adding
the same independently calibrated occupied-RE noise. UL receive dimensions
use the gNB's receive capability. Actual operator identity, matrix digest and
TX/RX dimensions are exported in the diagnostic rows.

The focused spatial regression covers DL and reciprocal UL, amplitudes 1/0.5,
2x2 rank one and 4x2 rank one/two: **12 physical cases passed**. The measured
probe power ratio now matches 0.25 without changing the fixed noise reference.
These cases do not prove arbitrary fading equivalence, the complete sweep or
the full 400 MHz shared-feedback scenario.

Retained evidence:

- Before repair: `logs/harq_spatial_authority_before_fix_20260926.log`.
- Initial post-repair checks: `logs/harq_spatial_authority_after_fix_20260926.log`;
  spatial authority, fixed-noise reference and runtime/probe separation passed.
- Expanded batch: `logs/harq_spatial_authority_matrix_guards_20260926.log`.
  At 01:58 IST, 10 of 11 named tests had passed: spatial authority, configuration,
  DL/UL/reference points, link export, artifact integrity, organizer preservation,
  scheduler consistency and `testE2E_FastVsTruth`.
  `testE2E_TruthPacketSemanticCampaign` was still running at that checkpoint.
  The completed log now records all 11 tests passing with process exit zero.
- No `testAll` was started, respecting the user's explicit stop instruction.
  Registering tests does not mean the entire suite was executed or passed.
- Checkpoint Python validation: **36 tests passed** for lab waveform packaging
  and no-PDCCH-observation publication guards;
  `logs/consolidation_20260926_harq_checkpoint.xml`. Dependency deprecation
  warnings remain. The PowerShell launcher parses without errors, and all ten
  checked README handoff/dashboard paths exist in the sealed local package.

The active eight-point sweep is not restarted or relabeled by this checkpoint.
Its unfinished execution and failed acceptance checks remain distinct from the
focused repair evidence. No receiver likelihood candidate or unavailable-data
publication helper is silently installed.

## 400 MHz package remains unchanged

The sealed run is
`results/vxg_vsa/7ghz_400mhz_rank2_1024qam/20260925_v1`.
It uses 120 kHz SCS, FFT 4096, 491.52 MSa/s, 264 PRBs, two ports/two layers,
and received-DMRS estimation/MMSE. It is a dedicated data-channel experiment:
access, physical control/feedback, HARQ and link adaptation are disabled.
UL 1024-QAM remains explicitly experimental.

MCS26 at 35/40 dB passed 50/50 DL and 20/20 UL transport blocks, with full-frame
goodput 3.524520/1.409808 Gbit/s. The retained 30 dB failures are not removed or
relabeled; these finite samples are not statistical BLER qualification.

The root manifest was rechecked and remains SHA-256
`dbfd394b1b1781461e41f64b8475531931050c2dbdc32f6d95bda3756a67d60b`.
This check verifies the manifest identity, not a new readback of every IQ file.
The package is transferred separately from GitHub. Physical instrument
capability and hardware import remain **UNKNOWN** pending actual instrument
identity/options and coherent-channel evidence.

## Receiver candidate preservation follow-up

This follow-up starts from `6faace8611d3ede33483302bd4cae47d7282d07c`, verified
against freshly fetched `origin/main`. There is still one branch and one Git
worktree. The active older sweep continues to use unchanged receiver source;
stopping it and applying the candidate are awaiting the user's decision.
This is a clean-source preservation checkpoint, **not a completed runtime merge**.

| Preserved source change | Exact patch | Installed on main? |
|---|---|---|
| Causally received SRS clock for configured CSI PUCCH; retain prior-clock evidence | `pending_received_csi_pucch_clock_20260926.patch` | No |
| Actual Format-2 receiver uses per-RE equalizer gain and physical covariance for UCI likelihood | `pending_pucch_format2_receiver_likelihood_20260926.patch` | No |
| Preserve physical zero noise, reject invalid noise/covariance, exclude solver loading from physical covariance; correct static-covariance test reference | `pending_equalizer_noise_authority_20260926.patch` | No |

The new regression files `tests/testEqualizerNoiseAuthority.m` and
`tests/testPUCCHFormat2ReceiverLikelihood.m` are included in this checkpoint.
Their assertions require the candidate source: committing the tests without
applying the patches does not make the installed receiver pass them. No
assertion or detector threshold was weakened to obtain a clean Git status.

All three patches pass `git apply --check` together against this checkpoint.
They cover four production files and one existing test. Candidate execution
took place in the full isolated source snapshot
`C:/Users/anup0/AppData/Local/Temp/sixgr_clock_repair_20260926_014701`, not in a
second Git branch or a mixed-source path overlay. Nine tested source/test
SHA-256 values were rechecked against
`logs/receiver_clock_candidate_20260926/candidate_v4_validation.json`; all match.
The two new main regression files also match their tested snapshot bytes.

Validation evidence:

- **15/15 focused MATLAB tests passed**, process exit zero:
  `logs/receiver_clock_candidate_20260926/gain_aware_validation_v4.log`.
  Includes 54 equalizer-noise cases and seven invalid-input guards, actual
  Format-2 waveform/decoder likelihood checks, CRC/received-noise checks,
  combined UCI, inter-layer evidence and configured-CSI clock eligibility.
  Noise-only false detections remain visible; this is not detector qualification.
- At **02:49 IST on 26 September**, the separate 20-test candidate guard batch
  had **18 passed, zero failed, one running and one not started**. The running
  test was `testE2E_FastVsTruth`; the remaining test was
  `testE2E_TruthPacketSemanticCampaign`. The snapshot's source is frozen during
  execution. Authoritative ongoing log:
  `logs/receiver_clock_candidate_20260926/candidate_v4_runtime_guards.log`.
  This historical checkpoint is not a claim that all 20 completed.
- **36 Python tests passed** again for lab package readback/sealing and the
  no-PDCCH-observation plot contract, with 13 dependency deprecation warnings:
  `logs/consolidation_20260926_receiver_checkpoint.xml`.
- The documented PowerShell launcher parsed without errors; all 11 checked
  Keysight handoff/dashboard files exist. The sealed package's manifest hash
  remains the value recorded above. This does not claim a fresh full IQ readback.
- No new MATLAB scenario or `testAll` was launched for this consolidation.
  The earlier 11 main-source guards and the 15 candidate tests are different
  validation populations and must not be combined into an end-to-end pass.

Prior failed candidate attempts, both historical recovery stashes, the source
snapshot, all logs and the sealed 400 MHz package are retained. Ignored
generated files are intentionally not committed or deleted. The README now
also includes fresh single-branch clone instructions for the 400 MHz / 7 GHz
digital package. Full 5 MHz sweep acceptance, detector qualification, pending
receiver integration and full 400 MHz physical shared-feedback acceptance
remain open.

## Conditional-presence development checkpoint

This follow-up starts from `38754c53fbe4982cdb09dfc0435bfb88dd2485c2`, again
checked against freshly fetched `origin/main`. There is one local branch,
one remote delivery branch and one Git worktree. The two recovery stashes
are retained, and both previously recorded recovery commits remain ancestors.
No result, log, snapshot, stash or sealed instrument file is deleted.

All four outstanding source/development files are included:

| File | Scope |
|---|---|
| `+sixgr/+phy/+pucch/detectFormat2EqualizedWhiteNoisePresence.m` | Conditional data-only short-UCI presence helper; not called by the scenario receiver |
| `simulator/configs/validation/pucch_whitened_presence_component.yaml` | Frozen development fixture and detector assumptions; not scenario policy |
| `tests/testPUCCHWhitenedPresence.m` | Actual OFDM/DM-RS/equalizer component matrix; not statistical qualification |
| `tests/diagnosePUCCHReceivedClockReuse.m` | Adds original/retimed conditional-presence measurements to the retained-IQ diagnostic; this extension has not yet been executed |

These four files match their isolated snapshot copies. The nine source/test
hashes in `candidate_v4_runtime_guards_receipt.json` and its guard-log hash
were also rechecked. This verifies preservation of the tested candidate;
it does not transfer that candidate's passing results to the unchanged main
runtime. All three pending runtime patches still pass `git apply --check`
together, but remain unapplied while the older main-source sweep is running.
Permission to stop that sweep and complete the runtime merge is outstanding.

The formerly unfinished broader guard batch has now completed: **20/20 tests
passed with process exit zero**, including both E2E campaigns. Evidence:
`logs/receiver_clock_candidate_20260926/candidate_v4_runtime_guards.log` and
`candidate_v4_runtime_guards_receipt.json` in the same folder. The earlier
18-passed checkpoint above is historical, not the latest result.

A subsequent four-test snapshot batch also completed with process exit zero:

1. `testPUCCHWhitenedPresence`: 24 waveform cases and 24 pilot/data-independence checks.
2. `testPUCCHFlatJointShortUCI`: 27 math/codec cases.
3. `testEqualizerNoiseAuthority`: 54 cases and seven invalid-input guards.
4. `testPUCCHFormat2ReceiverLikelihood`: eight physical receiver cases.

The authoritative launcher log is
`logs/receiver_clock_candidate_20260926/whitened_presence_v1.log`.
Component CSV and scope are retained under the isolated snapshot's
`logs/pucch_whitened_presence_20260926_031916_791/` folder. The presence
component recorded **0/12 noise-only detections**, **6/6 desired detections
at 20 dB**, and **2/6 at -10 dB**. All four low-SNR misses remain visible.
Its 64-data-RE fixture is not the 32-data-RE retained scenario allocation;
the result is neither a missed-ACK campaign nor a physical false-ACK bound.
The helper does not use injected noise variance or transmitted payload bits,
and neither installs itself nor changes the existing detection threshold.

Checkpoint verification reran **36 Python tests successfully**, with 13
dependency deprecation warnings, for lab-package readback/sealing and the
no-PDCCH-observation plot contract. Receipt:
`logs/consolidation_20260926_presence_checkpoint.xml`. The documented
PowerShell launcher parses without errors. No MATLAB scenario or `testAll`
was started for this preservation operation.

The README records the 400 MHz / 7 GHz experiment's original source identity,
its exact launch and WebGUI commands, and the instrument handoff mapping.
The sealed manifest hash remains unchanged from the value above. Generated
IQ/results/logs remain local and must be transferred separately from GitHub.
This is a clean-source checkpoint, not a claim that every candidate is merged,
that all requested SNR points pass, or that physical hardware is verified.

## Joint receiver preservation checkpoint

This checkpoint starts from `cccd601ff6e33ee89c5176f17d99f55990090f18`,
verified against freshly fetched `origin/main`. One branch and one worktree
remain. The older eight-point sweep is still executing against main; permission
to stop it and change its receiver files has not been received. No runtime
source is replaced beneath that execution. This is preservation, not a claim
that the pending receiver changes are installed.

The final v5 candidate batch completed with **16/16 named tests passing and
process exit zero**, confirmed from the completed launcher, not inferred from
an unfinished log. The authoritative log is
`logs/receiver_clock_candidate_20260926/joint_receiver_v5_final_guards.log`,
SHA-256 `37ae6602b897e4c697a6afe77fe1cfe35484d62ea6e4d263c484c0d349ad2b3c`.

The tests cover the joint receiver, gain-aware likelihood, CRC, independent
assignment equivalence, combined UCI, flat-AWGN eligibility, configuration,
strict proxy/no-fallback guards, DL/UL/reference points, scheduler consistency,
receive-only/shared PUCCH clocks and configured-CSI received-clock handling.
These tests executed in the isolated full source snapshot, not main.

| Preserved development item | Validation and integration boundary |
|---|---|
| `pending_pucch_flat_joint_receiver_20260926.patch` | Incremental v5 receiver change; apply only after the three existing v4 patches. Reverse applicability against the tested snapshot passes. It is not a standalone patch against main. |
| `tests/testPUCCHFlatJointReceiver.m` and `simulator/configs/validation/pucch_flat_joint_receiver_component.yaml` | Byte-identical to the tested snapshot; 48 waveform cases. The test requires the unapplied receiver patches. |
| `pending_pucch_shared_model_scaffold_20260926.patch` | Preserves two new snapshot files: `collectPUCCHObservationModel.m` and `pucch_flat_joint_short_uci_candidate.yaml`. Not runtime-verified, not wired through schema/builders/callbacks and not enabled by any scenario. |

The original three v4 patches still pass applicability checks together against
main. Apply them first, then the incremental v5 patch; do not pass all four to a
single applicability check that assumes every hunk targets the original main.
The scaffold is deliberately separate from the tested receiver patch.

The source inventory compared 5,487 tracked paths against the snapshot and
normalized text line endings before identifying changes. Seven text files
differ: five are covered by the pending receiver/equalizer patches; the other
two are `exportLLSHARQDiagnostics.m` and `tests/testAll.m`, where main already
contains the newer HARQ spatial repair and its test registrations. Those newer
main changes are preserved, not overwritten by the older snapshot. The only
additional snapshot source/config files are the two scaffold files above.

Rechecked candidate SHA-256 values:

- `PUCCHReceiver.m`: `904791bfec07d1aabfb079ae71aa47249ee06a5a73179df67176347dc0bccfe1`.
- `testPUCCHFlatJointReceiver.m`: `4143d3a3c1f7cf81f996b7ef0f41cdc2f641cda99fa3c7738b9b34dd349eddd8`.
- Component YAML: `2f3546b75a5bde5af00a3e4a47413bff7a4191f524589f1953477a5184bf1e49`.

The separate retained-IQ diagnostic completed seven captures with five eligible
received SRS priors. Correct best-word decoding is not automatically an accepted
word: only two of seven joint estimates met the frozen 0.99 posterior threshold.
The new component matrix recorded 0/24 noise-only detections and 12/12 correct
accepted words at 20 dB. At -10 dB, the 32-data-RE cases accepted 0/6 and the
64-data-RE cases accepted 3/6. These small development samples do not qualify
false-ACK/missed-ACK rates or prove a -10 dB scenario pass.

Remaining work includes independent prepared/receive-only runtime wiring,
schema-backed opt-in policy, truthful joint-decoder confidence/LLR/variance
export roles, physical statistical qualification and complete scenario reruns.
No detector threshold or failure assertion was weakened in this consolidation.

Consolidation checks reran **36 Python tests successfully**, with 13 dependency
deprecation warnings, for lab packaging and no-observation publication guards.
Receipt: `logs/consolidation_20260926_joint_receiver_checkpoint.xml`.
The PowerShell launcher parsed without errors. The sealed 400 MHz manifest
hash remains unchanged. No MATLAB scenario or `testAll` was started here.
Results, logs, source snapshots, recovery stashes and instrument IQ are retained.

## Shared-integration v7 preservation checkpoint

This delivery starts from `d5e26dc92d7b467e8d6fc571c89c0b7d5eb19ebc`,
equal to freshly fetched `origin/main`. One branch and one Git worktree remain.
The older main-source sweep (engine 13768) is still executing; permission to
stop it is outstanding. **Runtime integration is not complete.** No main
receiver file is replaced beneath that run.

The inventory compared 4,822 tracked MATLAB/Python/PowerShell/YAML paths with
the isolated snapshot, normalizing line endings. Twelve tracked candidate
files differ and six new candidate files exist. The two other differences are
`exportLLSHARQDiagnostics.m` and `tests/testAll.m`, where main has the newer
HARQ spatial repair/registration; those main changes are retained.

| Preserved artifact | Meaning |
|---|---|
| `pending_receiver_shared_integration_v6_20260926.patch` | Historical 17-file candidate used by the latest completed shared-receiver batch. Preserved with its failure, not accepted. |
| `pending_receiver_shared_integration_v7_20260926.patch` | Current 18-file snapshot: clock/likelihood/equalizer fixes, opt-in receiver schema and physical execution wiring, plus the subsequent legacy compatibility correction and receive-only noise audit. Latest edits have not been runtime-verified. |

Each consolidated patch is a **standalone alternative against the unchanged
main runtime**, not an incremental patch. Use v7 for future integration after
review/validation; do not stack v6, v7 or the earlier incremental patches.
Forward applicability against main and reverse applicability against the
current snapshot both pass for v7. No snapshot code or evidence was deleted.

The v6 batch is now terminal: **4 passed, 1 failed, 4 not started** out of nine:

- Passed: `testSharedPUCCHJointReceiver`, `testConfiguredCSIReceivedClock`,
  `test6GScenarioConfigValidation`, `test6GParameterCatalog`.
- Failed: `testPUCCHTrialIndependentReceive`, because the wrapper required
  `ReceiveStreamExecutionSegments` from a legacy isolated receiver context
  even when the joint policy was absent.
- Not started: `testPUCCHObservationReceiver`,
  `testPUCCHReceiverStageEvidence`, `testType2HARQACKLayout`,
  `testType2HARQRuntimePlan`.

Authoritative local log:
`logs/receiver_clock_candidate_20260926/joint_receiver_v6_shared_snr_bound.log`.
The passing shared test covers producer present, removed after transmission
and absent, with received SRS timing; it is not detector qualification or a
complete scenario. The v7 wrapper limits shared metadata requirements to the
explicit joint policy. Its new control-noise audit uses completed receiver
execution records, not transmitted bits, and is not a practical estimator
input. These later changes still require focused execution and regression.

Delivery verification: **36 Python tests passed** (13 dependency deprecation
warnings), recorded in `logs/consolidation_20260926_shared_v7_checkpoint.xml`;
the documented PowerShell launcher parses successfully. These packaging and
publication tests do not validate the pending MATLAB receiver changes.
No MATLAB scenario or `testAll` was launched for this delivery.

The README identifies the test as **400 MHz bandwidth at 7 GHz**, retains exact
Windows CMD launch/WebGUI commands and the Keysight file mapping, and separates
digital packaging from physical instrument verification. The sealed package
manifest remains SHA-256
`dbfd394b1b1781461e41f64b8475531931050c2dbdc32f6d95bda3756a67d60b`.
Generated results, logs and multi-GB IQ remain local/ignored and require a
separate transfer; they are not downloaded with the source repository.

Remaining before a complete runtime merge: safe stop/completion of the old
sweep, final-source focused validation, then integration without overwriting
main's newer HARQ repair. Full 5 MHz sweep, detector statistical qualification
and full-control 400 MHz acceptance remain open. A clean Git status does not
mean those scientific or integration tasks have passed.

## Shared-integration v8 preservation checkpoint

This checkpoint starts from `0c840c2805e746a2bd61106608b909a12f254908`,
verified against freshly fetched `origin/main`. There is one branch (`main`)
and one Git worktree. The older main-source sweep is still live; permission
to stop it remains outstanding. **This is not a completed runtime merge.**

The complete current candidate is preserved in
[pending_receiver_shared_integration_v8_20260926.patch](pending_receiver_shared_integration_v8_20260926.patch):
25 files, 798 insertions and 62 deletions; SHA-256
`3d8ff259fbda4020bd83b2fae8e00ea22eee3fa413590dbe2e98faedb9df11ad`.
This is a standalone alternative to v6/v7 and the incremental receiver patches,
not an additional patch to stack on them. Forward applicability against main
and reverse applicability against the candidate snapshot pass. All 27 source
hashes in the current combined-source checkpoint match the snapshot, including
main's HARQ spatial repair and its regression, now included in that snapshot.

The preceding candidate batch completed **11/11 focused tests with exit zero**:
receiver stage evidence, standalone SR, observation receiver, independent trial,
noise audit, observation-model collection, Type-2 layout/runtime plan, shared
joint receiver and shared receive-only/feedback clocks. The standalone-SR fix
exports receiver-derived DM-RS counts; it does not weaken the strict gate.
Historical unversioned IQ remains replayable without invented noise-audit
evidence. Current audit fields distinguish injected calibration from practical
receiver estimates and are not estimator inputs.

After that batch, the generic injected-noise source alias was removed and
main's existing HARQ repair/test registrations were included in the snapshot.
Therefore those 11 passes are not a claim about every byte of the latest
combined source. At **05:36 IST on 26 September**, its separate 23-test batch
has **9 passed, 0 recorded failures, 14 unfinished** (one running). The running
test is `testLLS_ReferencePoints`. The batch is not `testAll` and is not a full
5 MHz or 400 MHz scenario. No new MATLAB process was launched by this Git
preservation checkpoint.

Authoritative local evidence, retained outside Git:

- `logs/receiver_clock_candidate_20260926/joint_receiver_v8_dmrs_sr_guards.log`
- `logs/receiver_clock_candidate_20260926/joint_receiver_v8_dmrs_sr_receipt.json`
- `logs/receiver_clock_candidate_20260926/receiver_v8_combined_source_guards.log`
- `logs/receiver_clock_candidate_20260926/receiver_v8_combined_source_checkpoint.json`

The README retains exact CMD launch, YAML, recorded WebGUI and Keysight handoff
instructions for **400 MHz bandwidth at 7 GHz**, not a 4 GHz test. The launcher
passes PowerShell syntax parsing. The sealed `20260925_v1` package is unchanged;
its manifest identity remains the hash recorded above. Generated results,
logs, IQ, temporary source snapshots and both recovery stashes are preserved.
These large artifacts are not included in a GitHub clone. No cleanup deletes
them and no run is relabeled successful.

Remaining at the v8 checkpoint: safely install the candidate after final-source checks; repair the
separate 0 dB DL/UL PDCCH admission and blocked-observation reporting defects;
complete detector qualification and integrated 5 MHz/full-control 400 MHz
acceptance. A clean Git worktree is not evidence that these tasks are complete.

## Shared-integration v9 preservation checkpoint

Starting commit: `4095a8ded5e401f25c5a9cd172f0aaec74a877e8`, matched to freshly
fetched `origin/main`. There is one local branch (`main`) and one Git worktree.
The old main-source sweep still has live MATLAB engine 13768. Stop permission
has been requested; main runtime files have not been replaced underneath it.
**This delivery preserves the newest edits; it does not complete their runtime merge.**

The standalone [v9 patch](pending_receiver_shared_integration_v9_20260926.patch)
contains 37 files, 1,313 insertions and 71 deletions. SHA-256:
`b5245d5771c6b165d8c6f83b8f2df062a04f4d6f06938a2d0aed5867af310925`.
Forward application against main and reverse application against the candidate
snapshot both pass. It replaces, rather than stacks on, the older pending
receiver patches. A normalized-text comparison of tracked source and an
inventory of new source files found 23 modified and 14 new source files;
all are represented. Main's newer README is retained, not replaced by the
snapshot's older README. Existing HARQ spatial repairs remain in main.

The candidate adds configured joint DL/UL PDCCH candidate admission without
lowering aggregation level or overlapping control resources. At an AL8
contention occasion, the configured `ul_preschedule_first` scheduler policy
reserves the feasible UL-control allocation before waveform serialization.
This is an explicit gNB scheduling policy, not a claimed mandated 3GPP priority.
Executed receiver trials remain distinct from finalized pre-transmission
blocks. Blocks do not become CRC successes or satisfy missing UL data evidence.

Validation evidence is revision-specific:

- The v8 combined-source batch completed **23/23 focused tests**, recorded in
  `logs/receiver_clock_candidate_20260926/receiver_v8_combined_source_receipt.json`.
  This predates the new PDCCH changes and does not qualify all v9 source.
- `pdcch_joint_admission_identity_guards.log` records execution-disposition
  and candidate-admission passes, including 32 mapped composite DL/UL cases.
  That batch subsequently failed at runtime-adapter structure initialization;
  the failed batch is retained, not presented as an all-pass run.
- After that correction, `pdcch_joint_runtime_report_guards.log` records passes
  for `testJointPDCCHRuntimeAdmission` and
  `testPDCCHGrantBindingEvidenceReport`. Its MATLAB process is no longer active.
- This delivery reran the Python lab package tests: **18 passed**, with 13
  dependency deprecation warnings. Receipt:
  `logs/consolidation_20260926_v9_lab_package.xml`. The PowerShell launcher also
  passes syntax parsing. These checks validate packaging, not PHY acceptance.

No MATLAB scenario or `testAll` was launched for this preservation delivery.
The new PDCCH tests still need registration and final combined-source regression
before an integrated rerun. Detector statistical qualification, the complete
5 MHz sweep and full-control 400 MHz acceptance remain open.

The README retains exact Windows CMD commands for the **400 MHz bandwidth /
7 GHz carrier** experiment, its dedicated YAML, recorded WebGUI and Keysight
handoff files. It is not a 4 GHz test. The sealed `20260925_v1` package manifest
still hashes to
`dbfd394b1b1781461e41f64b8475531931050c2dbdc32f6d95bda3756a67d60b`.
Physical instrument capability remains UNKNOWN. Generated IQ, results and logs
are local/ignored, not included by a GitHub clone. Nothing was deleted.
Both recovery stashes and temporary source/evidence snapshots are retained;
their older consolidation commits `cd397f33` and `471334ff` are ancestors of main.

## Shared-integration v10 preservation checkpoint

Starting commit: `7f96e81c99be56c8a487f7088731f686fc592004`, matching freshly
fetched `origin/main`. One local branch and one worktree remain: `main`.
The old eight-point sweep still uses main (engine 13768); stopping it has
been requested, not approved. No active runtime files were replaced.
**This is preservation, not a completed source integration.**

The [v10 standalone patch](pending_receiver_shared_integration_v10_20260926.patch)
preserves 40 source/config/test files, 1,631 insertions and 71 deletions.
SHA-256: `6a45041f628a4b818f0c8cd03446895436982c02767924eafe398f81dbb72e1f`.
Forward applicability against main and reverse applicability against the
candidate snapshot pass. Apply this alternative only once; do not stack it
with previous preserved receiver patches.

The v9 combined-source focused batch has now completed **25/25 passes**.
The final marker is `V9_COMBINED_COMPLETE 25/25`; its MATLAB engine has exited.
Evidence: `logs/receiver_clock_candidate_20260926/pdcch_v9_combined_source_guards.log`,
SHA-256 `18b3f6070e85e1fb6006ce98f108a2dd51c1e4e6691d21250bf7cff11ef17ffb`.
This includes PDCCH allocation/runtime/reporting, DCI/DAI and scheduler guards,
config and DL/UL/reference checks, artifact checks, `testE2E_FastVsTruth` and
`testE2E_TruthPacketSemanticCampaign`. It is not `testAll` or scenario acceptance.

Beyond v9, the patch preserves three PDCCH test registrations and these new,
**unverified and not runtime-integrated** files:

- `+sixgr/+link/bindCSIReportMeasurementAudit.m`
- `tests/testCSIReportMeasurementAudit.m`
- `simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml`

The intended CSI audit distinguishes the UE measurement slot from the gNB's
configured CSI reference slot. The new helper is not yet called by production
runtime; its presence is not a claim that CSI exports are fixed.

The README retains the exact CMD generation and recorded-WebGUI commands for
**400 MHz bandwidth at 7 GHz**, its YAML, result/log locations and Keysight
handoff mapping. This is not a 4 GHz test. No sealed IQ/results were modified,
no MATLAB run or `testAll` was launched, and no files/stashes were deleted.
Generated artifacts remain local, excluded from GitHub. The physical instrument
capability remains UNKNOWN. Remaining source integration requires the old
sweep to finish or explicit approval to stop it; end-to-end qualification is
still pending afterward.
