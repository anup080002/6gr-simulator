# 12 dB root-cause and closure plan

Date: 2026-09-14. This is a repair/acceptance plan, not a conformance certificate.

## Implementation checkpoint: 2026-09-14, 10:31 IST

Implementation resumed on the explicit goal continuation after the planning
response. The original 09:52:49 start and target checkpoints are unchanged.
The preceding turn added the plan and verified the concrete resource-authority
mismatch; this turn applies its repair. No detector or 12 dB pass is claimed.

Applied, runtime verification pending:

- CSI-only PUCCHResourcePlan now selects the installed CSI resource directly,
  not a HARQ resource-set PRI. resolveConfiguredCSIResourceID rejects an
  unresolved multi-resource list instead of inventing report/BWP associations.
  Multiple-report/SR/mixed-UCI coordination remains a separate unfinished step.
- resolveConfiguredPRI's legacy CSI call returns the configured resource, with
  PRIValue/ResourceSetId unavailable (NaN). HARQ-bearing combined reports retain
  HARQ PRI; the runtime no longer selects the CSI-purpose branch merely because
  a combined HARQ report also contains CSI.
- prepareDLCSIReportAssignment retains that exact plan provenance. The primary
  CSI reservation trace rejects manufactured PRI rather than backfilling one
  through the HARQ selector. No power, noise, loss or detector threshold changed.
- New testCSIOnlyPUCCHResourceAuthority distinguishes resource 23 outside HARQ
  sets from HARQ-selected resource 10, compares calendar/TX identity, checks
  PRI/list-order/payload-value independence, preserves combined HARQ PRI, checks
  unavailable trace fields and rejects ambiguous/fractional/unknown identities.
  Shared CSI RF clock tests additionally require honest reservation provenance.
- Registered the new test and two existing planning/power tests previously
  absent from testAll. Existing numerical power gates remain unchanged.

Native mlint checked the ten changed MATLAB files: no SYNER/EOLPAR in sources;
the retained malformed control produced the expected SYNER. Warnings are kept
in logs/csi_resource_authority_20260914/native_check_01.txt. git diff --check
passed. These are syntax checks, not execution proof.

The distinguishing pre-fix run was NOT executed: its memory guard rejected
launch at 1,952,944 KB free, with two full-suite workers still live. Later
checks remained below the 2,097,152 KB floor. Neither existing suite was stopped
or edited. Required next execution on this frozen checkpoint: focused resource,
power, collision, periodic calendar and shared CSI TDD/FDD/combined tests; then
testAll and applicable NR/config/scenario/export/E2E guards. Old-revision running
suites do not satisfy those obligations. Main must remain unchanged/unqualified
until the integration and full acceptance gates are actually met.

## Authoritative planning-only checkpoint: 2026-09-14, 10:22 IST

The latest request asks for a strict repair/fixture timeline and a planning
pause. This update changes documentation only: no source repair, new MATLAB
job, merge to main or detector qualification is performed. Existing MATLAB
jobs remain running. The assistant cannot itself change the application's
Plan mode; implementation is paused for this request, not blocked by a skill.
This section supersedes stale present-tense statuses below; historical failures
and receipts remain preserved.

Verified checkout state: main be983bf4 is clean; both development checkouts are
at e02aae0e and clean before this documentation update. The two live full-suite
workers are 10448 (main) and 25036 (shared-PUSCH checkpoint). Neither running
suite is a terminal pass or qualification of future changes. Focused receipts
retain 5/5 passes at c4ce36c3 and 5/5 at 8a007054; the latter explicitly records
baseline_12db_qualified=false. The normal coordinator still does not call
completeSharedPUSCHHARQFeedbackRuntime. Main is not the consolidated candidate.

### Calendar checkpoints, without resetting the previous clock

Original recorded resumption remains 14 September 2026, 09:52:49 IST.
The following are target checkpoints assuming uninterrupted resumed work,
not guaranteed successful outcomes or a promise of unattended execution.
Record this planning interruption separately. If a target is not met, retain
the original target and mark MISSED with evidence and a revised forecast.

| Original target (IST) | Deliverable | Required test at that checkpoint |
| --- | --- | --- |
| 14 Sep 10:52 (+1 h) | Finish branch/patch/failure inventory and evidence index | Account for every retained edit; distinguish running, failed, incomplete and passed runs |
| 14 Sep 13:52 (+4 h) | Timing/CRI final-source fixture rerun; explicit enabled-CFO TDD fixture | CSI execution/source/clock positives and invalid inputs; disabled CFO stays unavailable, enabled CFO is measured; TDD/FDD staged references |
| 14 Sep 21:52 (+12 h) | Source-aware CSI resource selection, configured mixed-UCI ownership and normal independent PUSCH completion | Distinct CSI/HARQ resource IDs, overlap/nonoverlap, missing/all-missed DL/UL DCI, DAI wrap, no producer, CSI-only, HARQ+CSI, SR disposition, duplicate/stale/late feedback in TDD/FDD |
| 15 Sep 01:52 (+16 h) | Decoder reference regression; detector diagnosis and candidate/holdout-policy freeze | Original failures retained; real RV/rank/CRC/erasure cases; no holdout-driven threshold adjustment |
| 15 Sep 05:52 (+20 h) | Physical detector qualification harness ready and campaign launched | Real acquired timing and RF samples; independent noise-only and signal-present episodes; frozen confidence gates |
| 15 Sep 09:52 (+24 h) | All-measurement/export checkers complete; coherent candidate frozen | Independent energy/noise/loss, reference power, SINR, EVM, channel estimates, bit/CRC/throughput, CSI/SRS and CSV/PNG checks |
| 16-17 Sep 09:52 (provisional qualification window) | Required final-source regressions and detector campaign; integrated 12 dB only after prerequisite gates pass | Terminal required test results, both detector error classes, actual integrated measurement/artifact acceptance |
| After acceptance | Consolidate/push qualified source and portable evidence, verify remote identity and clean tracked tree | Preserve branches/patch history and failures; then same-chain sweep [-30,-20,-10,0,10,12,20,30,40] |

### Newly confirmed resource-authority prerequisite: repair and fixtures

buildPeriodicCSIReportObligations.m uses the exact installed CSIResources ID.
PUCCHResourcePlan.m instead always invokes PUCCHResourceSetResolver.resolve
and selects a HARQ resource-set ordinal through PRI. resolveConfiguredPRI.m
also requires CSI resource IDs to belong to exactly one HARQ resource set,
then can select another resource in that set. Baseline coincident resource
IDs hide this disagreement. This is code-level evidence, not yet a failing
runtime reproducer or a completed fix.

1. PUCCHResourcePlan.m, PUCCHConfigBuilder.m and resolveConfiguredPRI.m:
   separate configured CSI-only resource authority from HARQ DCI PRI authority.
   Do not manufacture a decoded PRI for periodic CSI. Preserve real DCI PRI for
   HARQ-bearing combined reports. Validate report/BWP/configuration identity.
2. CoupledTruthRuntime.m / prepareDLCSIReportAssignment: retain the actual
   configured resource provenance in assignments and traces. Align the calendar
   and transmitter without deriving the gNB schedule from UE report contents.
3. Scenario YAML, schema.m, validateScenarioConfig.m and buildInternalConfig.m:
   explicitly represent applicable simultaneous HARQ/CSI configuration and
   collision policy before wiring mixed-UCI ownership. Validate timing and SR
   disposition; do not blindly combine every same-slot report.
4. Extend testPUCCHResourcePlanningWithoutPower, testPUCCHMultiUserPRIAuthority,
   testPUCCHPowerResourceAuthority and testSRSPUCCHExactCollisionFDDTDD. Include
   a configured CSI resource different from all HARQ-selected resources, CSI
   resources outside HARQ sets, reordered lists, invalid/ambiguous identities,
   combined HARQ retaining PRI, and unchanged real-resource power calculations.
5. Then complete the coordinator and actual common-commit tests described in
   section A. Pure planning, mapping and receipt tests do not replace these.

At every checkpoint report original target, actual time, commit, changed
files, positive/negative test counts, first remaining failure and /logs path.
Use distinct states: diagnosed, implemented-unverified, focused-pass,
integrated-pass. Do not call all four "fixed". No deadline authorizes weakened
assertions, proxy measurements, altered power/noise or removal of real losses.

## Implementation resumed: 2026-09-14, 09:52:49 IST

Verified second checkpoint: 8a007054 focused run also finished with five
passes, zero failures, clean unchanged source and both exit codes zero
(launcher terminal 10:11:07 IST). It covers producer mapping, receipt guard,
reservation preflight/reducer and the independent codec, NOT the complete
physical common-commit adapter. Portable receipts for both runs are in
docs/lls/evidence_20260914/shared_pusch_receiver_checkpoint/.

Verified 10:09 IST: c4ce36c3 focused run finished with 5 passes, 0 failures,
unchanged clean source and MATLAB/launcher exit codes 0. New independent CSI
calendar, 11 codec cases with malformed/CRC/unavailable/oracle negatives,
16 received UL DCIs and their gap/producer bindings, plus all staged TDD/FDD
cases passed. Run: shared-pusch-completion checkout
logs/testall_20260914T042926281Z_59290fea (terminal 10:08:29 IST).
The later common-commit adapter below is not covered by that earlier revision.

Follow-up development on work/shared-pusch-commit-path-20260914 adds the
common PUSCH completion adapter, prevalidated producer bookkeeping using
separate transmitted versus scheduled bit positions, and a retained-receipt
guard against entering the legacy HARQ reducer after independent commit.
The adapter is NOT yet called by the normal coordinator. Its physical
completion/mutation tests remain owed; pure mapping/receipt tests alone do
not qualify it. Receiver completion flags now retain the actual strict-noise
early exit, without inventing decoder output. No production threshold/power
or noise setting has changed.

Specific remaining coordinator prerequisite: overlappingPUCCHReservations
currently plans mixed resources from UE producer rows, whereas independent
gNB ownership must also work when those rows are absent. A configured CSI
calendar alone does not resolve all combined HARQ/CSI/SR resource changes.
Do not wire every scheduled DL obligation onto every same-slot PUSCH or use
the UE's UCIOnPUSCHApplied flag to choose gNB receiver widths. Finish the
payload-free scheduled resource/transport ownership decision, including
nonoverlap and no-producer cases, before installing the normal adapter.

T_resume is now recorded from the actual system clock as
2026-09-14T09:52:49.6737913+05:30. The prior turn made progress by verifying
the terminal four-test result and preserving the fixture plan. Work resumed
on the explicit goal continuation; there is no remaining planning approval
pause. Checkpoints are active-work budgets and do not imply background work
between turns. Preserve the original targets when reporting interruptions.

Current development additions, NOT YET runtime verified: independent periodic
PUSCH CSI receive-obligation construction; actual HARQ receiver normalization
including pre-demapper strict-noise failure; throughput handoff of that exact
receiver evidence; codec negatives, real staged-reception assertions and
received-UL-DAI producer/gap bindings. Normal coordinator/common-commit wiring,
missed-UL-DCI receive-only handling and combined ownership remain unfinished.
This development checkpoint is not deployable or a 12 dB qualification.

## Planning checkpoint: 2026-09-14, approximately 09:52 IST

This section supersedes older status statements below, not their evidence.
The four-test run on clean, unchanged eb56deb8 completed at 09:50:35 IST:
4 passed, 0 failed, MATLAB and launcher exit codes 0. TDD/FDD staged-data,
measured PUSCH power control and normalized UL power checks passed. Evidence:
measurement checkout logs/testall_20260914T041220484Z_133e0990/{launcher.json,
summary.json,test_report.json,matlab.log}. This is NOT integrated 12 dB proof.
Main remains be983bf4 with a live full testAll, not a terminal pass; that run
does not include eb56deb8. The shared-PUSCH development checkout contains
uncommitted producer work, not a complete or tested transport adapter.

### Recovery schedule and reporting contract

The user requested a planning pause. No new implementation or validation job
is launched by this documentation update; existing jobs are left running.
T_resume means the next actual implementation resumption, whose wall-clock
time must be recorded before work starts. The earlier unanchored T0 cannot be
retroactively dated. This recovery estimate does not erase earlier delays.
Deadlines below are cumulative active-work time, not promises of unattended
execution. Runtime qualification is separately budgeted and may fail.

| Checkpoint | Repair/fixture deliverable | Test and acceptance gate |
| --- | --- | --- |
| T_resume + 1 hour | Freeze inventory of branches, patches, source hashes and original failures; record start and calendar equivalents | Every change accounted for; incomplete old runs remain incomplete; no source edits in a running checkout |
| + 4 hours | Finish timing/CSI fixture closure: tests/testCSIRuntimeExecution.m, testSharedCSIReportClock.m, testCoupledTruthCSIReportSourceAuthority.m, testDataChannelStreamStages.m; add explicit enabled-CFO TDD fixture without altering the disabled scenario | Existing CSI positives/invalid-input negatives and all staged TDD/FDD cases pass on candidate source; available versus disabled measurements tested separately |
| + 12 hours | Complete normal shared-PUSCH producer, independent RX, once-only commit, missed-UL-DCI capture and mixed ownership in CoupledTruthRuntime.m, runWaveformLinkBundle.m, validatePreparedPUSCHUCI.m and codebook-binding helpers | Normal-path TDD/FDD tests: missed leading/interior/trailing/all DCI, DAI wrap, 4/8 all-missed assignments, no HARQ, CSI-only, HARQ+CSI, SR collision, late/stale/duplicate feedback. No TX-derived receiver width or invented UE transmission |
| + 16 hours | Revalidate decoder repair and independent/public-reference fixtures; finish PUCCH detector diagnosis and freeze configuration-owned candidate, qualification seeds/counts/conditions | Existing RV/rank/partial/CRC negatives retained. No threshold selected from holdout outcomes; no claim of detector qualification yet |
| + 20 hours | Finish real-RF PUCCH qualification harness: PUCCHReceiver.m, PUCCHDetector.m, resolveDetectionThreshold.m only where diagnosis warrants; noise/signal tests and validation YAML | Pilot proves actual acquired timing, RF observations, independent episodes and failure retention; launch frozen false-ACK AND signal-error campaign with predeclared confidence gates |
| + 24 hours | Complete measurement/export checkers in section E; freeze one coherent candidate and evidence index | Independently check every enabled family, unit/reference plane, missing-value policy and export provenance. Candidate-ready is not qualified |
| Next 24-48 elapsed hours, provisional | Run required full suite/guards and detector campaign on frozen final source; after these pass, run authored integrated 12 dB and inspect CSV/PNG artifacts | Terminal zero-failure required results; detector gates pass; integrated measurements and artifacts pass. Unknown test runtime or a failure can move completion, not acceptance criteria |
| After qualification | Consolidate into main, commit/push code and portable evidence index, verify remote hash and clean tracked tree; retain original logs/branches | Same source as qualification; preserved patch ancestry/content; no destructive cleanup. Then execute same-chain sweep [-30,-20,-10,0,10,12,20,30,40] |

At each checkpoint publish: target, actual time, commit, files changed, tests
passed/failed/not run, original exception and evidence path. If a target is
missed, mark MISSED at that checkpoint and give the specific remaining work
and revised estimate. Never silently restart the clock, weaken an assertion,
change power/noise to manufacture success, or call component success closure.
The 24-hour candidate and additional 24-48-hour qualification budgets are
engineering estimates, not a guarantee that unresolved bugs pass by a date.

### What is fixed versus what is genuinely missing

- CSI timing-list/CRI and canonical DL clock fixture repairs have focused
  passes. The new TDD/FDD and power-availability run also passed. Final-source
  regression and integrated availability/consumption evidence are still owed.
- Shared HARQ still has an implementation gap: producer rows cannot stand in
  for protocol gap positions or complete gNB obligations. The normal receiver
  and common commit must be wired together before producer WIP is deployable.
- PUCCH's retained 12/1024 false-ACK result still fails its configured sample
  gate. Independent replay agreement does not qualify the operating threshold.
  Signal-present error qualification is a separate mandatory gate.
- All-measurement closure is missing integrated evidence, not proof that every
  formula is wrong. Section E names exact audit locations and repair conditions.
- Consolidation is incomplete: main lacks the newer measurement commits and
  shared-PUSCH edits remain uncommitted. Preserve them; do not advertise main
  or GitHub as the final qualified codebase yet.

## TDD measurement diagnosis and fixture repair, after 09:30 IST

Runtime follow-up on 450e3467: the TDD DL reference comparison passed inside
the actual staged execution, then TDD UL case 2 failed the fixture expression
abs(NaN-NaN)<1e-12 for requested transmit power. bindPUSCHPowerControlContext
explicitly returns Enabled=false, Status=disabled and RequestedPower_dBm=NaN
for this normalized scenario; runULPUSCHThroughput preserves those fields.
The follow-up fixture requires exact disabled/unavailable semantics in that
branch and retains finite numerical equality when power control is enabled.
FDD completed all four cases successfully on 450e3467. Evidence is retained in
the measurement checkout at logs/testall_20260914T040450406Z_734232aa, including
the TDD UL case-2 input at logs/tpd62ebe0f_3371_4eb6_8998_b9b27d4c2d0e.
TDD cases 3/4 still require execution after the power-availability assertion
repair. Do not treat the earlier first-failure stop as their pass.

The original TDD capture is retained at
logs/tpd41dbd63_8f97_4864_959f_45ecbe814973/received_data_stages.mat in the main
checkout. Its measured sample SNR is 19.8773 dB: normalized occupied-RE TX,
the unchanged 77 dB connector attenuation and unchanged variance 1e-13.
The FDD fixture instead has physical-power scaling and 75.0943 dB sample SNR.
The configured 12 dB label is not the noise authority of this component fixture.

Independent original-IQ diagnosis found ideal expected EVM approximately 5.07%,
ideal observed EVM 5.06%, and public estimated-channel/unit-response-MMSE/PTRS
reception matching all 3385 production symbols to max error 5.5511e-16 at
EVM 5.4996167023%. The initially different public results omitted PTRS phase
correction and used a different CDM setting; those attempts remain preserved.
Thus the original noisy TDD input does not satisfy the high-SNR premise of the
2% fixture assertion. No power, attenuation, sample variance, estimator,
iterations, production PHY or scenario configuration was altered.

Applied fixture repair in the measurement-closure work branch (runtime proof
pending): TDD now verifies every equalized symbol, reported EVM and noise-domain
values against independent public primitives; a changed-symbol negative must
fail. It explicitly verifies unavailable CFO for the authored disabled path.
FDD retains the original abs(CFO)<5 Hz and EVM<2% assertions. This is not a
universal TDD EVM relaxation or an integrated 12 dB qualification. An additional
enabled-estimation TDD case and normal-path shared HARQ qualification remain open.

Independent scripts/results are in the main checkout's
logs/pending_integration_evidence_20260913/fixture_repairs_20260914_01/:
independent_staged_evm_ptrs.log/.mat (matched), independent_staged_evm.log/.mat
and independent_staged_evm_aligned.log/.mat (different conventions), and
compare_unbiased_evm.log/public_unbiased_comparison.mat (failed intermediate).

Server logging repair be983bf4 is pushed to main: singleton struct reports now
export one row per test with AsArray=true and record counts before CSV writing.
testServerRegressionReport independently exercised one passing and one failing
probe; both preserved counts, messages, identifiers and terminal status. This
avoids a secondary struct2table exception masking the real failure. The required
full testAll is running on clean, frozen be983bf4 under
logs/testall_20260914T035615537Z_ef864a72; it is not a completed pass.

## Latest verified checkpoint: 2026-09-14, 09:20 IST

This section supersedes the historical statuses below. Source revision
17661058069612ba9e9a61ea0f9cb09b688a0e6c is not qualified for the integrated
12 dB run. No full-suite pass is claimed.

- On 0b9096b1, the eight-test focused run finished with six passes and two
  failures. PBCH configured channel, resolved PUSCH codewords, CSI source
  authority, CSI runtime execution, shared CSI report clock and RA-associated
  SSB projection passed. Both staged-data failures were a newly added assertion
  reading Slot/Frame from the wrong frozen-grant struct level.
- 17661058 corrected that assertion to ChannelStateKey.Slot/Frame. Its two-test
  rerun terminated with one pass and one failure: all four FDD staged-data cases
  passed; TDD reached real coded DL reception and failed the CFO assertion.
- TDD observed CFO=NaN, EVM_rms=0.054996, timing offset=7 samples. Its unchanged
  gates require abs(CFO)<5 Hz and EVM_rms<0.02. The latter gate was not reached
  but the observed EVM would fail it. FDD DL observed CFO=0.0075503 Hz and
  EVM_rms=0.00014754. Different authored configurations prevent treating this
  difference alone as proof of a duplex-specific receiver defect.
- Confirmed CFO configuration/fixture mismatch: the TDD YAML explicitly sets
  impairments.cfo_correction_enable=false; buildInternalConfig maps this to
  both receiver correction flags. PDSCH_Rx/localEstimateCalibrationReceiverCFO
  returns unavailable when that flag is false. The fixture unconditionally
  requires a finite measurement. EVM's root cause remains unisolated.
- Normal shared-PUSCH adapter integration, physical PUCCH qualification,
  final-source testAll and integrated measurement/export closure remain open.

Evidence directories (preserved including failures):
logs/testall_20260914T033328430Z_901f08bf and
logs/testall_20260914T033905053Z_c92ace94. The latter finished at
03:42:38.518 UTC, duration 181.880 seconds. No MATLAB worker remained when
checked at 03:46 UTC. This checkpoint changes documentation only.

## Time-boxed repair and fixture schedule

Retain the previously recorded T0 (implementation resumption) and deadlines;
do not restart T0 after each new failure. These are accountable working-time
checkpoints, not guaranteed passing outcomes or an unattended-execution promise.
The earlier record did not establish an exact wall-clock T0, so an exact calendar
deadline cannot honestly be reconstructed from it. Record actual start/end times
on each subsequent repair and test. If a deadline is missed, record MISSED with
the original deadline, evidence, outstanding action and revised estimate.

| Deadline from T0 | Work and responsible files | Fixture/test gate | Current state |
| --- | --- | --- | --- |
| +1 active hour | Freeze failure inventory and retain original exceptions/logs | Terminal focused reports, revision/config identity | Reports retained |
| +4 active hours | CSI/PBCH fixtures; tests/testDataChannelStreamStages.m; PDSCH_Rx.m receiver tracking; runDLPDSCHThroughput.m measurement publication | CSI/PBCH positives and malformed-input negatives; all four staged-data cases in both duplex modes | CSI/PBCH and FDD pass; TDD CFO/EVM open |
| +12 active hours | CoupledTruthRuntime.m normal producer/consumer; runWaveformLinkBundle.m independent RX and missed-UL-DCI observation; validatePreparedPUSCHUCI.m binding | Missing leading/interior/trailing/all DL DCI, DAI wrap, missing UL DCI, zero HARQ, CSI coexistence, SR disposition, duplicate/stale/late feedback; actual normal path in TDD/FDD | Open |
| +16 active hours | tests/testPUSCHResolvedCodewordDecode.m, unchanged production decoder unless an independent mismatch is demonstrated | Original RV failure retained; initial/combined codewords and partial/CRC negatives, ranks 5-8, public-reference equality | Focused pass; full regression owed |
| +20 active hours | PUCCHReceiver.m/PUCCHDetector.m/resolveDetectionThreshold.m and qualification YAML/tests | Independent retained-IQ replay; frozen false-ACK and signal-error qualification with acquired timing and real RF samples | Replay diagnosed; qualification open |
| +24 active hours | Measurement families and export files in section E; freeze repair candidate | Independent power/noise/loss, reference measurements, SINR, EVM, bits/CRC/throughput, CSI/SRS, CSV/PNG checks implemented | Open |
| Additional 24-48 elapsed hours, provisional | Frozen-source full testAll, required guards and detector campaign; then authored 12 dB execution | Every required test terminal; all integrated measurement gates and exported artifacts checked | Not started on final candidate |
| After qualified 12 dB | Consolidate/publish validated main and evidence index; then same-chain sweep | Clean tracked worktree, ancestry/patch preservation, remote commit identity; sweep [-30,-20,-10,0,10,12,20,30,40] | Pending |

Immediate TDD fixture work:

1. Retain resolved config, actual prepared grant/DM-RS allocation, receiver
   tracking/synchronization state, paired constellation and pre/post-RF samples
   before assertions. Separate configuration-disabled estimation from an
   estimator failure or an export dropping an available measurement.
2. Define explicit estimation-enabled no-CFO fixtures in YAML for both duplex
   modes, retaining the original correction-disabled case as a separate negative
   availability test. Do not insert CFO=0, silently enable correction in the
   production scenario, or weaken the original finite-measurement gate.
3. Isolate EVM with the same transmitted symbols, received samples, allocation,
   precoder, channel estimate and equalizer. Account for authored reserved REs,
   active RF processing and normalization. Repair the first proven mismatch;
   no SNR/noise/power/iteration tuning to satisfy the limit.
4. Check receiver decision paths for dependence on injected impairment truth;
   audit-only truth must not choose estimator/correction behavior. In particular,
   inspect localSuppressBlindCFOCorrectionForRuntimeAligned if exercised.
5. Re-run TDD/FDD positive cases and disabled-estimation, wrong-clock,
   incomplete-observation and changed-frozen-grant negatives before a broad run.

Each completed fix requires a focused result on its recorded revision. Final
closure additionally requires one unchanged-source full regression and integrated
12 dB evidence. A disabled measurement is unavailable, never a manufactured zero;
an enabled required measurement that is unavailable blocks acceptance.

## Historical follow-up: diagnosed regression repairs applied, not yet verified

The focused run on e925ec6c terminated with 17 passes and four failures. It was
not a full testAll run. CSI runtime execution and shared CSI report-clock tests
passed. The following follow-up source repairs are now applied, with runtime
verification pending at this checkpoint:

- PBCH: explicitly configured physical-element/precoder fixture; scalar error
  messages retain typed missing/mismatched-authority guards; channel application
  validates the actual producer's spatial contract without manufacturing config.
- CSI source fixture: four resources now explicitly declare four beams; the
  test retains CRI=3 and adds the inconsistent-beam-count rejection.
- Staged DL/UL data: derive one-based data slot/frame from the canonical timing
  decision before freezing the grant; remove the fixture's post-freeze job-slot
  override; add explicit clock-mismatch negatives and a registered FDD wrapper.
- Resolved PUSCH codewords: preserve the original standalone RV=[0,2] failed
  decode and its bit-exact public reference; add independently encoded RV=[0,0]
  positives and actual retained-observation combination with RV=[0,2]. All TB
  sizes, target rates, ranks, modulation, LLR magnitude and iteration limits
  remain unchanged. Partial mapping cases cover initial and combined positives.
  The deliberate CRC-error negative now has a decodable unmodified control.

PUSCH diagnosis used the saved rank-5 failing stimulus: public encoder bits and
all observed recovered-LLR signs match; both public decoder paths and the local
decoder return identical failed TBs. A version-bound diagnostic parity-graph
audit explains the unresolved punctured positions under this iterative decoder.
At ranks 5-8, real initial-RV and combined observations decode correctly and
match direct public primitives. Public system comparisons must explicitly align
soft-buffer retention: its default flush-after-success differs from a call with
an explicitly retained prior buffer. These are codec diagnostics, not MAC/RF
qualification. No production decoder or power/threshold setting was changed.

Retained local evidence: logs/testall_20260914T021507124Z_056fa106 and
logs/pending_integration_evidence_20260913/pusch_decode_diagnosis_20260914.
The detailed diagnostic/fixture addendum remains under the same pending evidence
root as focused_fixture_plan_20260914.md. The failed originals are preserved.

Next gates: focused repairs including all four staged-data cases in TDD and FDD;
then final-source full testAll and the required NR/config/channel/scenario/E2E
guards. Normal shared-PUSCH integration, PUCCH physical qualification and the
integrated 12 dB measurement/artifact audit remain open. No checkpoint commit
constitutes qualification or permission to skip these gates.

## Current checkpoint and why the work remained open

Component fixes were previously described under broad issue headings without
clearly separating source integration, a component test pass, and end-to-end
qualification. That obscured real progress and real remaining work. In
particular, a working Type-2 builder is not a working normal PUSCH adapter.

The ten retained repair packages have now been applied to main on top of
ce2539b4. All 35 resulting files were compared in full, after CRLF normalization,
against the preserved ten-patch composition. No source changes from
shared_pusch_type2_integration_wip_01 were included. Runtime qualification of
the newly applied composition is still pending at this checkpoint.

All three original MATLAB workers and their original launcher handles were
confirmed absent on 2026-09-14 around 07:36 IST. Their stale running markers do
not prove continued execution or a pass. The latest main log has 271 completed
PASS markers and 13 FAIL markers, without a terminal full-suite result. The
follow-on watcher failed closed because launcher.json was nonterminal. The
termination cause is unknown; these processes were not stopped by this repair.
Original logs and failed attempts remain intact. The integration preflight and
35-file application receipt are in logs/pending_integration_evidence_20260913/
repair_integration_20260914_02/. Do not overwrite old running markers with PASS.

## Execution order and stop conditions

1. Commit this exact integrated repair checkpoint, explicitly unqualified.
2. Run the focused timing/CSI/PUSCH/authority failures on that frozen revision.
   Read the first original exception and retained decoder diagnostics. Repair
   failures before launching another broad suite merely to rediscover them.
3. Finish the normal shared HARQ transport adapter as a coherent producer,
   receiver, once-only commit and bookkeeping change. No transmitter-only
   integration is deployable.
4. Qualify the PUCCH detector jointly for false ACKs and signal-present errors.
5. Run final-source testAll and all required NR/config/channel/export/E2E and
   config-driven scenario guards. A crash/incomplete suite is not a pass.
6. Run the authored integrated 12 dB configuration and audit all measurements,
   tables and images from that same run. Repeat only after identified fixes.
7. Run the unchanged-chain authored sweep [-30,-20,-10,0,10,12,20,30,40].
8. Publish the validated commit and evidence index. The later long impairment
   study remains a separate deliverable, not a substitute for steps 1-7.

Each failure must record: revision/config hash, test, original identifier,
reproducer, responsible function, proposed change, negative test, positive
test, evidence path, and status (open/applied/unverified/verified). No closure
solely because syntax, an isolated helper, or an older revision passed.

## A. Shared HARQ: confirmed integration defects

### What is incorrect or missing

- CoupledTruthRuntime.m / multiplexDueHARQACKOnPUSCHImpl takes one AckBit per
  matched pending row. Type-2 codebooks can contain missing-assignment NACK
  positions without corresponding UE producer rows. These widths are not equal.
- consumeDecodedPUSCHHARQACK assumes one grant/source/HARQ identity per bit and
  applies HARQ directly. It cannot represent all gNB obligations after missing
  DCI and is not the common independent scheduled-feedback commit path.
- runWaveformLinkBundle.m / localCompleteSharedDataPlan does not automatically
  supply the payload-free PUSCH UCI receive context. The throughput caller now
  supports it, but support alone is not normal coordinator integration.
- localCompleteSharedScheduledPDCCH cancels an unexecuted UL grant after missed
  DCI without installing the corresponding gNB receiver-only observation.
- Mixed HARQ/CSI/SR ownership and frozen-waveform reconciliation remain partial.
  SR is not an extra PUSCH UCI bit; its MAC disposition must be explicit.

### Exact changes

1. In +sixgr/+truth/CoupledTruthRuntime.m, build the UE payload from actual
   received UL DCI and buildReceivedHARQACKCodebook, retaining HARQACKReport.
   Store producer-to-bit positions separately from bit count. Update reservation
   and sanitization together; neither gap bits nor unseen DLs create UE rows.
2. In +sixgr/+truth/validatePreparedPUSCHUCI.m, bind the typed codebook and source
   positions through preparation/reconciliation. Reject changes after encoding.
   The ignored WIP contains the initial producer edits, not a finished fix.
3. In +sixgr/+truth/runWaveformLinkBundle.m, derive gNB receive context from the
   actual complete DL schedule, exact scheduled UL DAI, installed CSI occasion
   and completed receive window. Use buildSharedPUSCHUCIReceiveContext and
   puschUCIObservationBinding; never use ExpectedUCIPayload to choose RX widths.
4. Route real received bits through commitScheduledHARQFeedbackRuntime with
   PUSCH authority. Validate all rows before mutation, deduplicate the physical
   obligation across transports, then update legacy producer traces by identity
   only. Do not invoke HARQEntity.onFeedback a second time.
5. Add a receiver-only UL obligation after missed UL DCI: capture actual gNB
   samples without creating a prepared UE transmission, fake TBS or fake CRC.
6. Resolve CSI/SR/HARQ resource ownership before IQ preparation; retain separate
   received-field usability. HARQ may be usable while CSI Part 1/schema is not.

Already applied supporting repairs: complete physical DL ledger validation,
zero-HARQ schema without fabricated rows, same-sample DataTX-before-RX
publication, scheduled transport mapping, and independent throughput RX support.

### Closure tests

Retain testType2HARQACKLayout, testScheduledHARQACKMapping,
testPUSCHScheduledHARQAuthority, testPUSCHIndependentReceiveBoundary,
testDataChannelStreamStages and shared PUCCH/PUSCH clock tests. Add actual
normal-path cases for leading/interior/trailing missed DL DCI, modulo-four
wrap, all DL DCI missed (including 4/8 assignments), missed UL DCI, zero HARQ,
CSI-only, HARQ+CSI, SR collision, late completion, stale NDI and duplicate
cross-transport commit. Verify gNB attempts once, UE producers only when real,
and independent IQ replay equivalence. Both TDD and FDD are required.

Type-2 scope: ordinary configured unicast, single codeword/cell/BWP and no
unsupported CBG/SPS extensions. Use TS 38.213 v18.8.0 clauses 9.1.3.1/9.1.3.2:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

## B. PUCCH detector: failure confirmed, physical root cause not yet proven

The retained two-bit noise result is 12 false ACK bits / 1024 = 1.171875%,
above the configured 1% sample gate. This does not by itself prove the true
population rate exceeds 1%, or establish which implementation mechanism is
responsible. The current threshold is unchanged. The small signal preflight
does not supply sufficient independent acquired-timing evidence.

Files: +sixgr/+phy/+pucch/PUCCHReceiver.m, PUCCHDetector.m,
resolveDetectionThreshold.m; +sixgr/+link/receivePUCCHObservation.m;
tests/testPUCCHBaselineNoiseRF.m, testPUCCHBaselineSignalClock.m;
simulator/configs/validation/pucch_baseline_dtx.yaml and the resolved scenario
PUCCH threshold/resource configuration.

1. Replay retained IQ and independently recompute the exact normalized
   correlation, hypothesis maximum, branch/symbol combining and ACK mapping.
   Separate metric/normalization defects from a legitimately excessive null tail.
2. Check actual post-RF noise coloring, AGC, branch dependence and timing-search
   multiplicity against the mathematical detector model. For Format 0, malformed
   metrics/thresholds must not become confident ACKs. Preserve other formats'
   explicit CRC/detection semantics when reviewing PUCCHDetector.
3. Correct proven detector math/implementation defects at their source. If the
   math is correct but threshold design is inadequate, derive a configuration-
   owned threshold on development data/model, then freeze it before holdout.
   The analytical 0.4509429931640625 experiment is NOT approved for production.
4. Build a fresh physical qualification campaign with real SRS-acquired timing,
   independent episode seeds, retained pre/post-RF IQ and all failed trials.
   Cover 1-bit 0/1, 2-bit 00/01/10/11 and noise-only at both widths.
5. Freeze count/error/confidence policy before outcomes. The prospective design
   is 600 independent episodes per case, family alpha 0.05 over eight cases and
   a 1% event-error upper bound; also report original per-bit metrics. Confirm
   applicability before execution. Do not pool correlated bits as independent
   trials or increase the sample count after looking at results.

Acceptance: both false-ACK and signal-present wrong/erased-payload confidence
gates pass on the final receiver at declared conditions. Keep engineering
12 dB qualification separate from normative hopping/channel/SNR test setups
in TS 38.104 clauses 8.3.1/8.3.2:
https://www.etsi.org/deliver/etsi_ts/138100_138199/138104/18.08.00_60/ts_138104v180800p.pdf

## C. CSI and DL timing: specific causes and applied repairs

| Failure | Confirmed cause | Applied files/change | Required proof |
| --- | --- | --- | --- |
| Original HARQExecutedClockMismatch | Fixture passed a control slot to resolveWaveformGrant's one-based frame argument and overwrote execution timing | Earlier fixture repair retained canonical frame/data/control identities | Coded DL timing assertions and CSI binding on final source |
| Current testCSIRuntimeExecution / InvalidFeedbackTimingList | Strict non-occasion scheduled grant had no explicit receiver dl-DataToUL-ACK list | tests/testCSIRuntimeExecution.m plus simulator/configs/fixtures/csi_runtime_execution.yaml: independently declared list, missing/empty negatives and received PDCCH K1 check | Whole test passes, not merely its early coded-DL portion |
| testSharedCSIReportClock / InvalidCRI | A one-resource fixture omitted CRI | tests/testSharedCSIReportClock.m: explicit CRI 0, malformed-input rejection, delivered CRI preservation | Actual PUCCH delivery and all old clock/power assertions |
| testCoupledTruthCSIReportSourceAuthority / InvalidCRI | Initial CRI missing; later CRI 3 supplied to a one-resource report | Dedicated lls_csi_source_authority_fixture.yaml declares four resources; original nonzero preservation test retained | Exact measurement-source authority and report roundtrip |
| CRI validation weakness | Sanitizer selected first element and rounded values/counts, hiding malformed inputs | +sixgr/+truth/validateMeasuredCRI.m and CoupledTruthRuntime.m: reject fractional/vector/Inf/out-of-range values; no fallback CRI | Positive, missing and malformed source tests |

Retain already integrated clock/calendar fixes: receiver completion through
publication and consumers, configured periodic obligations, measurement-gap
suppression and non-occasion resource capacity. Re-run testCSIMixedClockConsumer,
testCSIPhysicalKnowledgeConsumer, testPeriodicCSIReportObligations,
testPeriodicCSIRuntimeProducer, testSharedPeriodicCSIProducer,
testCSIRSPlannedCalendar, testCSIRSNonoccasionDataCapacity and
testSharedPUSCHLateCSIDelivery. Never select the newest CSI before it is available.

## D. Additional current PUSCH failures that block honest closure

- testPUSCHIndependentReceiveBoundary incorrectly required hard decisions on
  every uncoded data position, including HARQ-punctured erasures. The applied
  test compares the complete LLR vector with public nrULSCHDemultiplex,
  requires exact zero at punctures and correct decisions on observed positions.
  It adds erasure-fill and observed-bit mutation negatives; no decoder gate relaxed.
- testPUSCHPartialCSIReception assumed rank-dependent CSI Part 2 length in a
  configuration where both ranks have the same length. The applied fixture
  retains fixed-length cases and adds LI-enabled variable-length cases.
- testPUSCHReceivedCSIWaveform's negative fixture similarly entered a resolved
  rather than partial branch. LI-enabled geometry is now explicit; PHY gates remain.
- testPUSCHResolvedCodewordDecode still has an UNISOLATED failure. Its applied
  change is diagnostic only: retain real encoder stages and LLRs and compare
  decodeResolvedULSCH with public nrULSCHDecoder before the original assertion.
  Next isolate CRC/segmentation/rate matching/RV/soft-buffer behavior at identical
  parameters. Fix the implementation or an objectively invalid test assumption;
  do not lower rate, raise SNR/iterations or remove RV cases simply to pass.

## E. All-measurement closure on one integrated execution

There is no evidence that every remaining measurement is numerically wrong.
The confirmed gap is missing final-source integrated proof across all families.
Repair measured discrepancies, not values merely different from the input SNR.

| Family | Files to inspect/change if the independent check fails | Required same-run check |
| --- | --- | --- |
| Power/noise/loss | +sixgr/+rf/PowerContext.m, applyPowerContext.m; +sixgr/+channel/ChannelFactory.m; shared physical runtime and replay exports | Actual sample/grid energy, FFT convention, port/element projection, each channel/RF gain/loss applied once, complex-noise variance per branch and declared reference plane |
| RSRP/RSSI/RSRQ | +sixgr/+phy/+refsig/measureCSIRSPhysicalResource.m, selectCSIRSBranchMeasurements.m, measureSSBWindowPower.m, measureCSIRSRPFromWaveform.m | Declared RE/symbol/RB window and antenna branch; linear power average; RSRQ = N*RSRP/RSSI with matching numerator/denominator. Never label an SSB-local window full-carrier RSSI |
| Reference/post-EQ SINR | +sixgr/+phy/+rx/computePostEqSINR.m; +sixgr/+phy/+refsig/measureCSISINRFromResourceGrid.m; +sixgr/+truth/bindReferenceSignalSINREvidence.m | Separate noise-reference, received reference-signal and per-layer post-equalization definitions; independent signal/interference/noise accounting, not configured-value substitution |
| EVM/channel estimates | +sixgr/+phy/+waveform/WaveformEVMMeasurement.m; +sixgr/+phy/+rx/channelEstimate.m; PDSCH_Rx.m/PUSCH_Rx.m | Paired symbol errors with exact normalization and corrected/raw stage labeling; per-RE fading estimates, applied-channel comparison audit-only; no scalar full-grid fading estimate |
| BER/BLER/HARQ/throughput | +sixgr/+link/runDLPDSCHThroughput.m, runULPUSCHThroughput.m; CoupledTruthRuntime.m; +sixgr/+link/exportLinkKPIs.m | Actual bits/CRC attempts, explicit first-transmission versus post-HARQ denominators, weighted aggregation, unique delivered bits over actual elapsed time; no retry double counting |
| CSI/SRS feedback | CSI measurement/report functions, +sixgr/+phy/+srs/estimateSRSRSRP.m, estimateSRSSINR.m, CoupledTruthRuntime.m | Actual received resource/beam/rank identity, source time, availability time, report wire value and scheduler consumption time; no future or oracle feedback |
| CSV/PNG/manifests | +sixgr/+truth/exportLLSMeasurementSidecars.m; +sixgr/+link/exportLinkKPIs.m; +sixgr/+report/OrganizeRunResults.m; measured plot generators | Exact source-row/array roundtrip, units/axes/legends, finite and missing-value policies, hashes and run identity; inspect rendered PNGs against plotted CSV data |

Use TS 38.215 definitions with the declared measurement resource/window:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf
An independent simulator comparison must match channel, timing, allocation,
coding/RV, estimators, normalization and seeds/statistics. A different setup's
curve or a matching-looking PNG is not a numerical reference.

Physical path loss and RF impairments must remain when configured. Removing
legitimate losses to get 12 dB would be incorrect. Conversely, no unexplained
scaling, duplicated loss, adaptive power injection or artificial SINR offset is
allowed. In normalized mode, unavailable absolute dBm must remain unavailable.

## Final gates and delivery

Run the repository-mandated testAll plus testConfig, testStrictProxyGuards,
testStrictMode_NoFallbackAnywhere, testLLS_DL, testLLS_UL,
testLLS_ReferencePoints, testSchedulerGrantConsistency, testLinkExportPipeline,
testArtifactIntegrity, testOrganizeRunResults_E2EArtifactPreservation,
testE2E_FastVsTruth, testE2E_TruthPacketSemanticCampaign and the config-driven
scenario/config/matrix/prompt/catalog guards. Include test12dBSameChainSweepConfig.

12 dB YAML: simulator/configs/scenarios/
lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml.
Sweep YAML: lls_causal_access_to_data_wiring_tdd_short_snr_sweep.yaml, retaining
the same PHY/config authority except explicitly declared sweep controls.

Done means: the normal adapter is implemented; both detector error classes are
qualified; all required tests terminate successfully on the final revision;
integrated 12 dB and all enabled measurements/artifacts pass; the same-chain
sweep is present and subsequently qualified; code and reproducibility evidence
are committed/published with a clean main checkout. No failed history is deleted.

The later long impairment-enabled study must declare compatible feature packs,
duration/seeds and benchmark/study/experiment taxonomy in YAML. Research-only,
unsupported or incompatible features cannot all be enabled together and called
3GPP conformant. That feature-by-feature standards/implementation audit remains
part of the full goal after the baseline is genuinely closed.
