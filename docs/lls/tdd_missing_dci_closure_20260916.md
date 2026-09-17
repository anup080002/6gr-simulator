# Missing-DCI closure: active, not completed

Scope: ordinary scalar-TB Type-2 feedback, TDD; development checkout based on
`74889f1b`. Detector follow-up edits are preserved but are not this task.

## Current production repair (runtime unverified)

`completeSharedPUSCHAfterRejectedControl` previously rejected every installed
CSI obligation before the actual receiver ran. It now calls the existing
independent CSI normalizer and publication machinery through
`CoupledTruthRuntime.stageSharedReceiveOnlyPUSCHCSIRuntime`:

- Rebuild installed schedule/context and bind the actual completed observation.
- Preflight CSI value-state publication before any shared HARQ-handle mutation.
- Preserve actual receiver failure/false-detection evidence; do not infer DTX
  from transmitter absence.
- Do not mark a pending PUCCH CSI producer as transmitted/transferred on PUSCH.
- Keep duplicate identity/epoch/clock checks, no fictitious TB scoring, and
  existing guards for real PUCCH producers and receive-only retransmissions.
- Accept exact strict-noise failure flags from raw PUSCH_Rx or the normal
  throughput envelope; no relaxed missing-evidence acceptance.

New `testSharedRejectedULCSI` reuses the physical rejected-control fixture and
is registered in `testAll`. Its YAML changes only the CSI reference/report
calendar. It asserts an actual control rejection, no UE PUSCH, receiver-owned
CSI evidence, no fabricated producer/transport rows, and duplicate rejection.
It retains MAT/CSV evidence before rejecting a false usable CSI result.

Standalone Code Analyzer found no syntax errors in the changed MATLAB files;
runtime execution and mandatory full-suite/NR/config/export guards are pending.
All four old-revision engines were live at 21:13 IST. The latest memory sample
reported 82 MB available RAM. No additional MATLAB engine was launched.

## Remaining Missing-DCI acceptance requirements

1. Execute the new rejected-UL CSI regression and unchanged rejected-UL/HARQ
   regressions; repair any failures without changing negative assertions.
2. Integrate real PUCCH transmission after missed UL DCI with independently
   scheduled PUCCH/PUSCH observations and one common feedback disposition.
3. Complete receive-only retransmission using gNB-owned soft-buffer/NDI/RV
   authority; never fabricate a UE TB or claim combined decoding of one window.
4. Cover first/middle/last/all missed DL assignments, including missing whole
   DAI cycles, changed last-detected PRI/resource, and combined CSI/SR layouts.
   Preserve wrong-length rejection; do not blindly map a shorter bit prefix.
5. Run fixed-IQ TX-metadata poisoning, duplicate/stale/late/epoch and cross-
   transport tests on the final source, then required full regressions.

The existing Type-2 subset diagnostics are not those integrated acceptance
tests. Exact short-codeword ambiguity cannot be repaired by inventing unseen
DCI at the UE or ranking layouts solely by received energy.
Relevant procedure: [TS 38.213, clauses 9.1.3 and 9.2.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/17.09.00_60/ts_138213v170900p.pdf).

No claim that only the 12 dB run remains is justified: detector, SRS, reporting,
integrated measurement/export acceptance and consolidation also remain open.

## Follow-up review: unattempted TB CRC audit

The partial independent-CSI branch of `PUSCH_Rx` intentionally omits scalar
`CRCError` when data mapping is unresolved. The receive-only completion still
accessed it unconditionally. It now exports explicit `ReceiverCRCAvailable`
and NaN `ReceiverCRCError` for an unattempted TB; it also does not promote the
legacy strict-noise-stop `CRCError=true` sentinel into a measured CRC failure.
Actual attempted scalar-TB CRC results remain validated and preserved.
The physical rejected-control fixture now checks availability and CSV roundtrip
semantics. This is a source-level repair awaiting runtime execution, not a pass.

## Receive-only retransmission dependency found in source review

Do not remove `RejectedULReceiverHARQCombiningRequired` merely because a soft
combiner exists. In the baseline `runULPUSCHThroughput.m`, `currentDecodeOK` was assigned
`rx.Ok && currentBe == 0 && numel(rxBits) == numel(txBits)`; the combined pass is
also gated on transmitted-bit agreement. `CoupledTruthRuntime` consumes those
flags to clear/store the gNB soft buffer. `HARQEntity.getSoftBuffer` exposes the
buffer but does not by itself prove a receiver-only retention history.

Required before reusing that path after missed UL DCI: separate actual current
and combined decoder CRC decisions from TX-reference scoring, retain the gNB
process/NDI/epoch/coding-layout and receive-clock identity, and use only those
receiver decisions for retention/combining. TX-reference BER/false-success
scoring must remain independently visible. Reuse `combineSoftLLR` and
`decodeCombinedULSCH`; do not create a second combiner or pass a UE TB into a
receive-only path. Required tests include fixed received LLRs with poisoned TX
reference bits, stale NDI/epoch, missed-UL-command retransmission, and separate
current-window versus combined CRC evidence.

The normal-path decision boundary is now patched in production MATLAB source,
but is not runtime-qualified. `resolveULHARQReceiverOutcome` selects current
or combined decoded bits using only actual receiver CRC verdicts. The existing
`runULPUSCHThroughput` uses those decisions for HARQ/ACK and still computes
reference BER, content failure and goodput independently. A CRC pass with
incorrect reference content must remain a receiver pass and a scoring failure;
matching reference content must not rescue a failed CRC. Redundant former
bit-error-gated decision assignments were removed.

`testULHARQReceiverOutcome` checks declared decoder contracts and poisoned
reference fields. `testULReceiverOwnedHARQDecode` additionally checks the
selection boundary with actual NR-coded decoder outputs, including an exact
reference match with a failed code-block CRC. Both are registered in `testAll`.
Neither is an end-to-end missed-command retransmission test. Both subsequently
passed the Sep 17 focused run recorded below. The receive-only retransmission guard stays
in place until receiver process/epoch/buffer lifecycle integration is complete.

## Receiver-lifecycle root cause (source review, 21:43 IST)

The remaining work is not a missing call to the LDPC combiner:

- `runWaveformLinkBundle.localCompleteSharedScheduledPDCCH` queues the gNB
  receive-only window after rejected UL control, then calls
  `cancelUnexecutedHARQGrantRuntime`. For new data, that resets the tentative
  shared HARQ process. For retransmissions, cancellation intentionally does
  nothing; no new actual-TX attempt is committed.
- `HARQEntity.onTx` establishes `AwaitingFeedback`, `LastTxSlot` and `TxCount`.
  `onFeedback` rejects a different source slot or a process not awaiting
  feedback. Thus applying a missed-command receiver outcome through the
  existing normal-TX feedback entry either has no process or is stale. Calling
  `onTx` with an invented TB would falsify transmission and delivery evidence.
- `ReceivedULHARQState` is explicitly a UE transmit-bit buffer, not a gNB
  receiver buffer. Reusing it at the gNB would cross endpoint ownership.
- `combineSoftLLR.localBuffersCompatible` checks matrix dimensions and coding
  layout hash, but not the stored `HARQKey` or codeword identity. Normal
  `runULPUSCHThroughput` supplies no HARQ key. Compatible LDPC dimensions alone
  cannot prove the correct process/NDI epoch. Globally enforcing today's keys
  without reviewing callers is also unsafe: the legacy PDSCH facade supplies
  a per-assignment ID, while the strict receiver supplies a retained TB key.

Implementation order required by these findings:

1. Retain a gNB scheduled receive-attempt identity and soft-state lifecycle
   independently of actual UE transmission commits. Bind it to the physically
   transmitted UL command, installed context, UE/RNTI/cell/carrier/BWP,
   process/NDI/epoch, coding history and completed receive sample window.
2. Route normal and missed-command PUSCH reception through that same receiver
   lifecycle. Reuse existing rate recovery, position-aware combination and
   CRC decoding; do not add another decoder or use UE reference bits.
3. Separate the resulting scheduler disposition from actual-TX attempt,
   delivery and measurement ledgers. Never manufacture `onTx`, a current
   transmitted TB, BER denominator or goodput to make the feedback API accept.
4. Test normal/missed-command transitions, changed NDI/epoch, wrong process,
   same-shape foreign soft state, duplicate/late windows, and unchanged
   actual-TX/first-success ledgers before removing the retransmission guard.

This is a source-proven integration gap, not a runtime pass or a completed
repair. The four old engines were rechecked live; memory remained constrained
(90 MB available in the latest sample). No fifth MATLAB engine was started.

## Normal shared UL receiver identity patch (runtime unverified)

`bindSharedPUSCHReceiverContext` now binds a stable scheduled scalar-TB key
through `scheduledULHARQReceiverKey`. The key contains UE/RNTI/serving-cell,
installed DCI context (including carrier/BWP/configuration epoch), process,
NDI and NDI epoch. Scheduled DCI bits must agree with process/NDI/RV metadata.
RV, slot and per-attempt allocation are intentionally not the retained TB key.

`runULPUSCHThroughput` independently rebuilds that key before decoding on the
independent shared-UCI path. `validateULHARQSoftBufferIdentity` rejects raw,
anonymous, wrong-process/epoch or wrong-codeword prior state before calling
the unchanged position-aware combiner. Actual returned soft buffers retain
the key. Legacy DL/key conventions and combining mathematics are unchanged.

The existing shared-PUSCH physical fixture now checks retained keys and
TX/audit-poisoning invariance; the isolated staged-data fixture explicitly
declares its first NDI epoch and checks missing/foreign keys. A focused
declared-contract identity test is registered in `testAll`. These assertions
are authored but not executed. This patch does not yet implement the separate
gNB scheduled-reception lifecycle or remove the receive-only retransmission
guard, and does not establish final-source Missing-DCI acceptance.
Standalone MATLAB Code Analyzer reported no syntax errors for these helpers,
callers and fixtures; `git diff --check` passed. Final-source runtime tests,
`testAll` and required NR/config/export guards remain unexecuted. At 21:51 IST
all four older engines were still live, with 47 MB physical RAM available.

## Bounded runtime attempt: incomplete, not a pass

At 22:01-22:02 IST a no-JVM diagnostic attempted only
`testULHARQReceiverOutcome` and `testULHARQSoftBufferIdentity`. A Windows job
limited the new launcher/children to 512 MiB committed memory and terminated
only that job when system commit headroom fell below the 768 MiB reserve.
The diagnostic exited 124; its supervisor exited 1. No MATLAB log or completed
test evidence was produced. All four selected source hashes were unchanged.

Evidence: `logs/bounded_missing_dci_20260916T163142702Z/` (supervisor log and
explicit incomplete-launch receipt). At 22:03:25 IST the new launcher and
child were absent; the four old engines and their existing workers remained
live. This exhausted the bounded low-memory runtime alternative; no larger
test process was launched and no qualification/measurement result was added.

## Sep 17 focused runtime checkpoint: 4/4 passed, not integration closure

The old engines were absent on the overnight recheck. One preserved old log
contains an LDPC MEX access violation; absence of processes does not qualify
any old full suite. The new candidate first waited for MathWorks sign-in,
then ran successfully in one R2026a Update 4 process:

- `testULHARQReceiverOutcome`: passed (declared CRC/reference separation).
- `testULHARQSoftBufferIdentity`: passed (declared ownership rejection).
- `testULReceiverOwnedHARQDecode`: passed (actual coded A=1160, 3824, 3840,
  10000; CRC16/24A and one/two code blocks, including failed CB CRC rejection).
- `testSharedRejectedULControlPreflight`: passed (negative preflight contracts).

Evidence: `logs/missing_dci_candidate_20260917_quick/`, MATLAB exit 0,
4 tests, 0 failures. The before/after aggregate over 4,624 nonignored MATLAB,
YAML, JSON, PowerShell and MEX files is unchanged:
`8D38B74BBD5C4296E289162E0C9218B44450EB681B4CBACC8ACD2F3F0B2CDE05`.
No physical missed-command episode, full-suite pass, R2023b qualification or
12 dB acceptance is asserted by this checkpoint. Those remain pending.

## Sep 17 physical checkpoint: 5/5 passed, Missing-DCI still open

The same dirty candidate completed the following in R2026a Update 4, with
MATLAB exit 0, 5 tests and 0 failures (404.40 seconds of test execution):

- `testSharedRejectedULReceiveOnly`: actual rejected UL control, no UE PUSCH,
  completed gNB capture; no fabricated transmission or TB scoring.
- `testSharedRejectedULDueHARQ`: actual scheduled DL transmission, rejected
  UL control, independent PUSCH receiver erasure and one DL HARQ disposition.
  The fixture deliberately does not execute the UE DL decoder; it does not
  cover a surviving UE PUCCH producer or qualify false-ACK probability.
- `testSharedRejectedULCSI`: actual rejected control with configured CSI
  obligation, independent reception and no fabricated UE CSI producer.
- `testTDDSharedPUSCHIndependentCompletion`: normal actual shared UL path,
  empty HARQ UCI, stable receiver identity and common completion receipt.
- `testTDDSharedPUSCHNonemptyCompletion`: actual DL reception and UE HARQ
  feedback carried on actual PUSCH, with one common gNB ACK commit.

Evidence: `logs/missing_dci_candidate_20260917_physical/`. Terminal log SHA256:
`CD7334648CBE505573C3D5B3BBF3CEB7967B7472236494407EAA2934CBE86BD4`.
The 4,624-file before/after source aggregate remains
`8D38B74BBD5C4296E289162E0C9218B44450EB681B4CBACC8ACD2F3F0B2CDE05`.

These results supersede the runtime-unverified label above only for the cases
listed. Receive-only retransmission lifecycle, surviving UE PUCCH ownership,
combined HARQ/CSI/SR reception, hidden DAI cycles/changed last PRI and final
integrated Missing-DCI acceptance remain open. Full-suite and 12 dB acceptance
are not claimed; no threshold or failure assertion was relaxed.

## Sep 17 receiver-state and scheduled-UL lifecycle implementation

The source changes below are in this development checkout, not yet accepted
or consolidated into the IDE checkout. They are not just diagnostic logs.

### Root causes and changes

- `bindSharedPUSCHReceiverContext` used a cached preparation-side combining
  input. It now reads the gNB receiver's own process/NDI/configuration-epoch
  state, bound to an actual transmitted command and a completed observation.
  `prepareSharedULHARQReception`, `stageSharedULHARQReception` and
  `resolveULHARQReceiverState` enforce that lifecycle for normal and no-UE-TX
  PUSCH reception. Invalid coding-domain changes, duplicate/stale windows,
  changed prior state, and cross-sweep reuse are rejected. Unattempted
  decoding does not create a CRC result or a new soft buffer.
- `runWaveformLinkBundle` canceled a TDD UL HARQ reservation on the UE's
  rejected-DCI result. That gave the gNB scheduler UE-side knowledge. It now
  registers the independently proven physical gNB command through
  `commitSharedULHARQCommand`, whether or not the UE accepted it, and does
  not cancel the TDD reservation just because UE DCI decoding failed.
- `HARQEntity` previously advanced only through `onTx`, so a missed command
  had no scheduler receive attempt to complete. Separate scheduled-command
  count/clock/context now drives gNB retries without creating `onTx` events,
  payload bits, or delivery rows. `prepareSharedULHARQSchedulerFeedback`
  validates the outstanding command before receiver CRC/availability updates
  that process. A scheduled-only coding context explicitly has no first UE
  transmission slot. Existing actual-TX context hashes are unchanged.
- A retry of a missed initial command can be the UE's first transmission.
  Preparation can read that already issued command without making it
  scheduler-eligible again; actual UE buffer state, not scheduler retry
  status, controls new-data queue reservation. The implementation follows
  the empty-buffer C-RNTI case in TS 38.321 section 5.4.2.1; this reference
  is not a blanket conformance claim.

### Completed evidence before the scheduler integration

`logs/missing_dci_receiver_state_v2_20260917/`: 6 passes, 2 failures, exit 1.
The five normal/rejected physical cases and declared receiver-state test
passed. The two failures were the sweep-reset fixture's ambiguous feedback
direction and the known-candidate fixture's contradictory enabled SIB1.
Before/after source aggregate (4,629 files):
`2239197EEED834A0C26CD1799022D6BE1968FC88B0C6A7C6E1602FE0B7D74BB9`.
Terminal log SHA256:
`E3F88BBCB7CFFED8C1D80D24A7C11130AB6561913494B5AA07B9116BF44CA52F`.

`logs/missing_dci_scheduler_20260917_quick/`: 4 passes, 2 failures, exit 1.
Passed receiver-state, TB-context, YAML RV-authority and physical receive-only
decoder tests. Failed the new declared scheduler test at first actual TX
and the old sweep-reset CSI fixture at missing CRI. The retry removes the
allocation donor's old executed TB context from the new declared process,
adds an explicit fixture CRI, and retains all failure assertions. This run
does not qualify the scheduled lifecycle.
Before/after source aggregate (4,632 files):
`6A30550BE61A02777786F877A58D54865F0E4632B347C6843003DF06A4928B4F`.
Terminal log SHA256:
`F2E631DA0FA9F4412C5C24511B2543C2ABBA05D7B84750A885E84C7F146B1413`.

### Current acceptance boundary

The scheduled-lifecycle physical batch is recorded under
`logs/missing_dci_scheduler_20260917_physical/`. Its pass/fail must be read
from the terminal report, not inferred from its launch. Source freeze:
4,633 files, `C1036237BF2E5A32B2F137ABFDEC4A7380DBC494A1337DA74E66D20B904E6B01`.
It includes an explicit second physically rejected UL command and another
actual gNB capture to exercise retained receiver soft-state combining.

The physical scheduler batch completed **8/10**, exit 1. Repeated-miss
construction stopped at missing SRS metadata on the donor's runtime facade;
the retained frozen `LegacyGrantSnapshot` contains the actual SRS identity,
slot, validity and rank. The fixture now validates and copies those exact
fields as a declared retained allocation, not a fresh SRS observation.
The other failure, `testSchedulerHARQStateUnblockAndLineage`, is an FDD
fixture with an explicit UL BWP missing SCS; FDD remains deferred.
Terminal log SHA256: `8B72A9C22FC6DAA24A44E55D995C15F08CFEEEA6F259FCEAC6A90CB56852E584`.

### Actual command-transmit clock, Sep 17

Production command registration moved from the UE decode callback to the
actual gNB PDCCH transmit-prefix completion in `CoupledWaveformStream`.
`runWaveformLinkBundle` explicitly enables this TDD scheduled-UL lifecycle;
the UE decode result neither creates nor cancels the transmitted command.
`HARQEntity` preserves scheduled retry identity separately from UE TX count.
Receive-only ACK/NACK/DTX now also reaches the existing scheduler/OLLA path.
No synthetic TX, delivery or grant-result row is introduced.

`logs/missing_dci_transmit_clock_20260917/` completed **6/7**, exit 1.
Passed: scheduled lifecycle, receiver soft-state, rejected UL plus due HARQ,
rejected UL plus CSI, normal empty-UCI PUSCH, normal nonempty-HARQ PUSCH.
Frozen 4,633-file source SHA256:
`6F3CE74BDE3AC8D4C470C355A06FF6EAE70029734172BB2C145BC0B02550776E`.
Terminal log SHA256:
`D675A85D305DF964465A6D94A39A852CB0574CF586511107FCD59F819157A460`.

The repeated-miss fixture next hit `DuplicateScheduledPDCCHGrant`: its
copied donor retained the old explicit `GrantContextId`. The second
occasion now clears that override before freezing and asserts a distinct
identity. The production duplicate guard is unchanged.

### Repeated-miss retry passed, Sep 17 05:59 IST

`logs/missing_dci_repeat_retry_20260917/` completed **8/8**, exit 0:
`testSharedRejectedULRetransmission` (97.49 s), `testType2HARQACKLayout`,
`testScheduledType2DAI`, `testScheduledHARQFeedbackMapper`,
`testScheduledHARQFeedbackPreflight`, `testReceivedULTotalDAICodebook`,
`testPUSCHScheduledHARQAuthority`, `testPUSCHScheduledHARQMapping`.
The repeated-miss case retained two actual rejected PDCCH commands, two
gNB receive-only captures, receiver-owned combining and zero UE data TX.
The mapping tests retain their declared-vector versus actual-RF scopes.
No blind-prefix mapping, highest-energy layout selection, threshold change,
noise/power injection or weakened original assertion was used.

The 4,633-file source aggregate was unchanged:
`00904FC5C81BCA247F598E2B44EDB1EBD0857798B10575F8625D71379A51A2A2`.
Terminal log SHA256:
`6D480CD94A15660BD2DFBCDD34C3490AF13A11C411AC8F128A9DB05AEEDAD8D9`.
Earlier failed runs remain preserved as failed. This is a focused TDD
checkpoint, not complete Missing-DCI, detector, full-suite or 12 dB acceptance.

### Surviving UE PUCCH ownership increment, Sep 17

The main IDE checkout now extends the existing HARQ-only preparation path
to select gNB transport independently (`buildScheduledHARQTransportReception`)
while retaining actual UE PUCCH samples. `CoupledWaveformStream` records the
producer's immutable transmit identity alongside the PUSCH selection.
`validateUnselectedPUCCHTransmission` requires actual owner and MAC sample
receipts; preparation alone is insufficient. The value-state disposition
joins only matching DL identities, marks the actual PUCCH `TX_ONLY`, and
leaves PUCCH decoder metrics unavailable. The common PUSCH commit remains
the only gNB HARQ update. Rejected-UL completion accepts an existing producer
only with this proof, rather than removing the ownership guard outright.

`testSharedUnselectedPUCCHProducer` passed in 198.36 s on the dirty main
checkout: actual shared DL DCI/PDSCH reception, actual PUCCH TX, zero PUSCH
data TX, actual scheduled gNB PUSCH capture and one HARQ update. Its UE
UL-command decoder is deliberately **unexecuted**. No fabricated rejection
or CRC flag is supplied, and this test does not qualify physical missed-DCI
probability or the complete rejected-control coordinator path.
Evidence: `logs/unselected_pucch_producer_20260917_focused/`; source 4,636
files, SHA256 `3ECA46DF175301FD131AFC3372639F4E04E8270B084AB2F86CB96F84D040B3CD`.
Terminal log SHA256 `F744EFC96D6177E801AB811C757878F7D24181014AEBF0CBE5A72A82673883C1`.
A strengthened retained-IQ observer-removal/cross-transport duplicate test
and the no-producer/normal-PUSCH regressions subsequently passed on the next
source revision; see the receipt below.

Protocol reference: [TS 38.213 V18.8.0, clause 9.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf)
describes UE UCI multiplexing for overlapping UE PUSCH/PUCCH transmissions.
The gNB's scheduled expectation is not evidence that the UE transmitted a
PUSCH. The chosen gNB receiver policy is an implementation decision, not a
claim that 3GPP requires suppressing PUCCH reception after missed UL DCI.

Still open: complete physically rejected-UL plus surviving-PUCCH qualification;
combined HARQ/CSI/SR independent reception; physical missing first/middle/
last/all DCI, wrapped DAI/changed last PRI acceptance; final coordinator
integration and the mandatory full `testAll`/guard set. Do not claim that
only the 12 dB run remains. FDD and 400 MHz are deferred.

### Surviving-PUCCH guards and regression receipt, Sep 17 06:27 IST

`logs/unselected_pucch_producer_20260917_guards/` completed **3/3**, exit 0:
`testSharedUnselectedPUCCHProducer` (215.77 s),
`testSharedRejectedULDueHARQ` (101.02 s), and
`testTDDSharedPUSCHNonemptyCompletion` (175.45 s).
The first replayed the same actual captured IQ after removing UE feedback
bookkeeping and poisoning optional expected bits: the gNB receive schema,
mapping and decoder decisions remained identical. Missing actual TX evidence,
foreign transmission identity, duplicate producer disposition and same-/cross-
transport duplicate HARQ commits were rejected. Exported PUCCH rows retained
`TX_ONLY`, no PUCCH decoder invocation, NaN bit-error/detection measurements,
and the actual independent PUSCH observation identity.

The 4,636-file source aggregate was unchanged throughout execution:
`4800D3163460EE592D2865C197F8A4CAC59A3715EDC200E8012D405A3A293519`.
Terminal log SHA256:
`C62981BC4CC047D111B04CFBA724FA66B214758C9907231971DDB46184AA1B9B`.
The no-producer test executed an actual rejected UL control reception; the
surviving-producer test deliberately left its UL control decoder unexecuted.
These remain separate component cases, not proof of their fully integrated
combination, all missing-DCI cases, detector qualification or 12 dB acceptance.
The full `testAll` running from frozen parent `951bb75b` cannot qualify this
new increment. A subsequent baseline run is diagnostic until final-source
regressions and measurement/export acceptance are complete.

## Sep 17 mapping/staged regression: 7 passed, 1 failed

The preserved run `logs/missing_dci_candidate_20260917_mapping/` exited 1.
Passed: `testType2HARQACKLayout`, `testScheduledType2DAI`,
`testScheduledHARQFeedbackMapper`, `testScheduledHARQFeedbackPreflight`,
`testReceivedULTotalDAICodebook`, `testPUSCHScheduledHARQAuthority`, and
`testPUSCHScheduledHARQMapping`. This includes 256 declared DAI sequences,
24 retained vectors, actual UL control decoding in the UL-DAI procedure test,
and separate declared mapping/authority guards; these scopes must not be
conflated with an integrated missing-command campaign.

`testDataChannelStreamStages` passed its first three TDD cases, then failed
case 4 at `scheduledULHARQReceiverKey`: `missing_dci_context`, missing
`pdcch_strict`. Root cause: the older stage-only YAML has no installed
`connected_dci` configuration, but case 4 now requests an independent gNB
connected receiver key. The production strict context check is correct.
The TDD case-4 fixture now loads the existing installed connected-DCI YAML
before constructing its grant. It retains the stage test's explicit AWGN
connector, fixed noise, every receive assertion and all production guards.
FDD is not changed or claimed qualified. The focused retry is recorded in
`logs/missing_dci_stage_case4_20260917/`; no retry pass is asserted here.

### Case-4 retry completed successfully, 04:52 IST

`testDataChannelStreamStages('TDD',4)` exited 0 after the fixture repair.
It executed real SRS/control/data component stages, accepted TB CRC and
two HARQ UCI bits, and retained the missing/foreign receiver-key rejection
assertions. Actual receive timing was 78 samples and measured EVM was
0.0577179879701 (fraction). This is the explicit connector/noise fixture,
not a measured 12 dB scenario or acquired shared-runtime acceptance.

The 4,624-file source aggregate was unchanged during the retry:
`027440D5059BCDB05ABFBBC472D30F01F6C0863F6671B43E5033FCBBD795120C`.
Terminal log SHA256:
`FB286A0DF77FC65AEC6DD5B22B6E2B25F60EF3D42135C74EB848582AFAC59D8C`.
The original mapping batch remains failed; only its failing TDD case was
rerun here. No full `testDataChannelStreamStages`, `testAll`, required guard
set, FDD, R2023b or 12 dB pass is inferred from this subset invocation.

## Sep 17 SR fixture repair: focused 4/4, integrated 12 dB still running

The parent-revision full suite at `951bb75b` was stopped as superseded after
125 completed passes and one failure; `testSSBSharedReceivedBurst` was still
in progress. Its original log and external incomplete disposition remain in
`logs/missing_dci_checkpoint_951bb75b_testall_20260917/`. It is not a full-suite
pass, and its wrapper's pre-stop `running` summary is not terminal evidence.

The recorded failure in `testPUCCHNormalizedMaterialization` came from an
inherited slot-19 SR opportunity without explicit UE SR procedure state.
The fixture now asserts that missing state is rejected, then supplies an
explicit idle state and checks the negative SR bit. Original waveform,
normalization, power/pathloss and invalid-input assertions remain unchanged.

The first four-test retry retained three passes and exposed a second stale
fixture: `testConfiguredSRCalendar` inspected the old PUCCH-only preparation
function name. The actual caller now uses `buildScheduledHARQTransportReception`
to select the gNB transport independently. The structural check now requires
that call and additionally requires its installed SR-calendar and overlap
guard. No production guard, calendar expectation or RF assertion was relaxed.

The second batch, `logs/tdd_sr_fixture_retry_20260917/`, exited 0: all four
tests passed (`testPUCCHNormalizedMaterialization`,
`testPUCCHNormalizedTransmitReference`, `testPUCCHMultiplexingPermission`,
`testConfiguredSRCalendar`). Source 4,636 files was unchanged, SHA256
`15B98A7450D2A35749CCA8A521385ADB69CD1FA22CECF993599F89FDE0F1DB66`;
terminal log SHA256
`9FDFFD3745AF9CBD560C408CA1549E478311F058CF20EF13558058772DFCA02A`.
These are fixture/configuration checks, not detector or full-suite qualification.

The unchanged 58-slot 5 MHz/configured-12-dB scenario is executing from frozen
production commit `68140bb9`. By slot 36 it had completed random access,
received SRS and actual connected DL/UL DCI, and exported its first UL data
CRC pass (0/640 bit errors). The first three retained DL rows had CRC passes
and 0/3,192 bit errors. Independent export-algebra checks and snapshots are
under `logs/tdd_5mhz_12db_68140bb9_20260917/`; they do not establish receiver
accuracy, all-measurement closure or terminal acceptance. All open combined-
feedback, physical missing-DCI and qualification items above remain explicit.
GitHub publication and 400 MHz remain after accepted 12 dB, as requested.
