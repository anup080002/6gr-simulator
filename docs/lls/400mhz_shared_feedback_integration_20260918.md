# 400 MHz shared-feedback integration: evidence and implementation gates

## Scope and preserved result

Requested on 18 September 2026: enable real PDCCH, PUCCH, CSI reporting and
SRS for the 400 MHz, 7 GHz, 120 kHz SCS, 4096 FFT, 491.52 MS/s, four-port
TDD scenario. Preserve the 5 DL / 2 UL / 1 mixed pattern and full-buffer aim.
Keep the existing ideal-feedback benchmark and its recorded exhibition data
unchanged. Its completed run on `ef799fcb` delivered 5.926550095 Gbit/s DL
and 2.396845714 Gbit/s UL. Those numbers do not qualify physical feedback or
prove a >6 Gbit/s result.

Audit baseline: `main` at `741f87a2c4ee6871c9d373a1729599a83c6776eb`.
No new full 400 MHz execution or `testAll` is claimed by this document.

**Artifact availability notice (18 September, during focused testing):** the
user confirmed external cleanup while `connected_and_400mhz_short_uci_03`
was running and then stopped it. The prior integration-log directory was
deleted; references below describe logs that were observed before cleanup,
not a claim that those files are still present. Current console output will
be saved as a clearly labelled recovered transcript. Source edits remain
present. Do not use historical file paths as retained acceptance artifacts
without checking availability or rerunning the relevant check.

## Current implementation receipt

### DL adaptation ceiling root cause found during 400 MHz startup review

The batch-36 DL `MaxSupportedLayers=1` is not explained by the received RI
alone. The shared four-port fragment still inherits `mimo.max_dl_layers=2`
and `pdsch.layer_count=1`. `buildInternalConfig` assigns the initial count
to both `phy.pdsch.maxLayers` and `phy.maxDLLayers`, losing that capability.
`CoupledTruthRuntime.resolveMaxGrantLayers` separately takes the minimum of
capability and bootstrap/current-layer fields. UL already separates these
inputs and calls `resolveRankExecutionPolicy` for the ceiling.

Required repair after the live baseline: preserve DL YAML maximum separately
from initial rank, use the common capability policy for both directions in
the runtime, and explicitly configure four-layer DL capability in the shared
four-port fragment. Do not force rank four, alter frozen-grant rank/TBS, or
treat received RI as permission to exceed the installed ceiling.
`testDLBootstrapRankCapability` checks the current inherited two-layer
capability independently of the one-layer bootstrap and rejects a request
above that maximum. It is statically clean and queued as batch 48 after
baseline 39 (session 48003); it has not executed or passed yet.

The full-access 400 MHz path additionally still fails closed at
`generateSSB_MIB_SIB1_Waveform.localSSBGridInCarrierNumerology` for mixed
SSB/initial-BWP numerologies. Existing BWP timing/state tests do not prove
the full access waveform transition. No pre-attached flag or ideal-feedback
runner was substituted for physical startup; no runnable shared 400 MHz
configuration is claimed at this checkpoint.

### Candidate report-audit repairs after batch 36 (19 September)

Follow-up DM-RS audit repair (batches 49-53): Python's antenna-port mapping
audit now checks every measured trial count rather than modal transmitted
layers versus nominal bootstrap DM-RS count. A failing-before regression
proved that the old audit accepted a rank-four trial with only one measured
port. Rank exports must now carry and exactly reconcile
`MeasuredDMRSPortCount` to the corresponding raw receiver trial. A second
failing-before test proved the old audit accepted an invented count.
All 92 Python semantic tests pass. The read-only retained-output check
correctly identifies that batch 36 has measured raw counts (DL=1, UL=4)
but omits that column from `rank_layer_trials.csv`. The MATLAB reducer repair
is still required; this candidate audit does not turn that run into a pass.

Receiver-baseline strengthening while the same batch-36 engine remains live:
`testULReferencePortUnion` now checks paired-reference permutation invariance
and the exact -6.0206 dB response to quarter signal energy at fixed noise,
for all six bandwidth/rank combinations. `testSRSReceiverNoiseDespreading`
also scores the practical per-resource channel against the declared identity
fixture and requires practical-estimator noise provenance. Its -10 dB NMSE
bound is an engineering regression check, not a qualification claim. Neither
fixture feeds its scoring channel or noise variance into `SRS_Rx`.
Standalone MATLAB static analysis passes (only redundant suppression notices).
These assertions are **not runtime-verified yet**; existing serial queues
38/39 will execute them after batch 36 and diagnostic 37. No duplicate queue
or second MATLAB engine was started.

Changed `tools/lls_csv_semantics.py`, with failing-before/passing-after
regressions in `tests/test_lls_csv_semantics.py`:

- FER uses finalized non-fallback execution rows, including warm-up and
  unavailable-SINR trials. Absolute `Frame` takes precedence over wrapping
  SFN; crashes and failed statuses count as frame failures, matching the
  MATLAB export definition.
- Antenna logical-port validation checks every trial against its transmitted
  layers and configured port capacity, not modal ports versus bootstrap rank.
  A malformed minority trial still fails the audit.
- Nominal DM-RS metadata is checked against the bootstrap configuration
  builder's zero-based port-list/count contract, separately from adaptive
  runtime DM-RS evidence. Missing, duplicated or mismatched nominal ports fail.

All 90 tests in the Python semantic test file pass (batch 46). A read-only
candidate audit of batch 36's retained CSVs passes all seven checks across
FER, antenna-array configuration and strict MIMO configuration (batch 47).
Logs are in `logs/shared_400mhz_integration_20260918/`, with baseline failures
in batches 40, 43 and 45. No original CSV, manifest or failed run verdict was
rewritten. This fixes report-audit disagreements, not the unresolved MATLAB
runtime DM-RS gate, missing UL reference SINR, SRS noise/power measurements,
physical missing-DCI integration or integrated 400 MHz execution.

At this checkpoint engine 19528 remains live saving batch 36's optional MAT
bundle; baseline queues 37-39 have not started. No executing PHY code was
modified. `testAll` remains stopped by user instruction; MATLAB export/E2E
qualification has not been rerun for this audit-only patch.

### Latest normal run: slot-35 pilot-clock replacement failure (19 September)

Batch 32 (`shared_awgn_12db_ra_stage_repaired_20260919_0013`) completed
initial access and four CRC-passing DL receptions, then failed at slot 35
with `sixgr:phy:sync:FutureULTimingReference`. It is **not a passed run**.
The failure report and original log remain under its results root and
`logs/shared_400mhz_integration_20260918/four_port_5mhz_12db_normal_32.log`.

Root cause: SRS completion replaces `ReceivedULTimingReferences{ue}`;
`completeSharedPUCCHFeedbackRuntime` subsequently reads that newest clock
for an observation that started before the SRS was available. The stack
ends at the correct `AvailableAtSample <= observation.StartSample` guard.
The production repair stores measured SRS/PUSCH clock history and selects
the latest clock available before each producer-present or receive-only
PUCCH observation starts. It does not change alignment, identity/TAG,
freshness, noise, or capture-coverage checks.

Added focused regression `testReceivedULTimingHistory`: two actually
received SRS pilots and replay of the earlier PUCCH capture; the later
pilot must still be rejected when passed directly to alignment. It also
checks the availability boundary, no prior evidence, repeated retention,
and out-of-order retention. This is component evidence with declared
access inputs, not full initial-access or missing-DCI qualification.
At this receipt, the test is **queued, not yet passed**, behind batch 32's
post-failure report recovery. Its log target is
`logs/shared_400mhz_integration_20260918/received_ul_timing_history_33.log`.

The retained scheduler decision gives a separate concrete reason for zero
UL data rows: at control slot 34, the slot-35 candidate had 10,625 buffer
bytes but was rejected with `PDCCH_CCE_BUDGET_EXHAUSTED`. SR gating was an
unproven hypothesis and is not the recorded rejection reason. Control
capacity/fairness needs inspection after the timing repair is verified.

Follow-up: batch 32 exited naturally with code 1 after report recovery;
no interruption was needed. Batch 33 then started the focused timing test.
Its pass/fail status is still pending at this receipt.

The UL rejection is now traced more precisely. Its decision row requested
AL16 with eight CCEs remaining, whereas the resolved search space has zero
AL16 candidates. Both scheduler aggregation selectors omitted the existing
`resolveExecutableAggregationLevels` filter already used by waveform
selection. The selectors now apply that filter. In addition, UL grant
control aggregation incorrectly consumed UL SRS/PUSCH SINR even though
the DCI travels on downlink PDCCH. It now uses the same available DL
feedback source as a DL grant, leaving UL data AMC measurements unchanged.
`testSchedulerPDCCHExecutableCapacity` covers actual scheduler state and
planning-budget construction, unavailable candidates, empty-candidate
rejection and invariance to changing only UL SINR. It is not yet executed.
Physical cross-direction CCE contention still must be checked on execution;
these repairs neither enlarge the CORESET nor relax receive CRC gates.

Verification update: batch 33 stopped on a new test-fixture error (second
timing-advanced SRS queued after its interval started). Preparing it in the
preceding slot fixed the fixture without changing the late-enqueue guard.
Batch 34 reached the empty-candidate negative case and exposed malformed
multi-part error text in `resolveExecutableAggregationLevels`; joining the
text into a scalar preserves the intended error identifier and condition.
Both original failed logs remain retained.

Batch 35 **passed with exit code 0**:
`testSchedulerPDCCHExecutableCapacity`, `testReceivedULTimingHistory`, and
`testPUCCHObservationReceiver` (retained-IQ guards plus physical Formats
1–4). Log:
`logs/shared_400mhz_integration_20260918/timing_and_control_capacity_35.log`.
This verifies the focused repairs, not a full 12 dB or 400 MHz acceptance.
The unchanged 58-slot normal scenario is next under run tag
`shared_awgn_12db_timing_capacity_repaired_20260919_0106` and log
`logs/shared_400mhz_integration_20260918/four_port_5mhz_12db_normal_36.log`.

### SRS estimator follow-up: investigation, not a repair claim

Batch 32's slot-30 SRS row reports grid-domain estimated noise variance
1.10572552445053 and measured pilot SINR -0.444838891037364 dB, alongside
applied AWGN grid variance 0.0157739336120048 and independently scored
channel NMSE -23.9339552370767 dB. The disparity needs investigation; it
does not justify substituting injected noise for a receiver estimate.
`SRS_Rx` passes `srsInfo.CDMLengths` only when present; otherwise the native
estimator uses its documented no-despreading default. A possible cyclic-shift
despreading contribution is a hypothesis, not yet a proven root cause.

Added `diagnoseSRSNoiseDespreading` for an explicitly labelled controlled
identity-AWGN comparison of native estimator settings for 1/2/4 ports.
The diagnostic does not feed known noise or the scoring identity channel
to the estimator, does not change the active normal-run source, and does
not claim normal-run or fading-channel qualification. It is queued after
batch 36 under `logs/shared_400mhz_integration_20260918/srs_noise_despreading_37.log`.

### Normal four-port 12 dB run: failed before data traffic

The normal 58-slot run `shared_awgn_12db_20260918_2236` reached slot 9,
with broadcast acquisition complete but no DL/UL data rows, then failed with
`sixgr:truth:InvalidTRSObservationClock`. Retained evidence is in
`logs/shared_400mhz_integration_20260918/four_port_5mhz_12db_normal_15.log`
and the run's `meta/failure_debug_report.txt`. Artifact recovery is not
continued PHY execution and is not acceptance.

Source inspection found that the shared TRS reference producer emits
`applied_identity_AWGN_operator_TRS_port_reference`, while the scorer's
authority allowlist does not yet accept that executed source. A receiver
exception is caught before observation coordinates are assigned, allowing
the delivery clock error to hide the preceding exception. The physical
`testSharedAWGNTRSReceiveCompletion` reproduction confirmed
`sixgr:phy:trs:InvalidChannelScoringAuthority` in
`shared_awgn_trs_reproduce_17.log`. Its actual received IQ, applied channel
references and failed receiver output are retained in
`results/lls/shared_awgn_trs_completion/20260918_225346_988/received_trs.mat`.
The preceding `_16` attempt failed on a test-fixture omission of
`run.rootRunFolder`; it is not PHY evidence.

The scorer now accepts the explicitly identified executed identity-AWGN
reference without changing correlation, channel estimation, noise, loss,
NMSE math or thresholds. The normal shared TRS reducer stops on an actual
receiver exception with its original identifier before attempting clock
publication. The original clock and anti-oracle guards remain unchanged.
Focused scoring-authority, exception-evidence, TDD delivery-clock and
physical AWGN tests all passed in `shared_awgn_trs_repair_18.log` (exit 0).
The successful physical capture is retained under
`results/lls/shared_awgn_trs_completion/20260918_225625_119/`.
This verifies the TRS boundary only, not full 12 dB/400 MHz acceptance.

The failed normal `_15` engine exited with status 1. Recovery retained raw
and report artifacts but browser materialization also rejected the empty
DL/UL authority tables, correctly reflecting that no data trials completed.

### Four-branch common PDSCH reception: SIB1 access blocker

The `_19` normal rerun passed the old TRS boundary: slot 10 reported
`valid_trs_cells=1/1` and `tracked_serving_users=1/1`. Its original failed
TRS IQ also replayed successfully before execution, with NMSE
`-18.516020171 dB` and the executed identity-AWGN source retained.

However, the PBCH rows exposed a separate deterministic error: SIB1 DCI CRC
passed, but `RASIPDSCHContext.materialize` rejected four receive branches
for the single common-procedure layer on AWGN. At slot 15, PRACH remained
deferred because decoded SIB1 was unavailable. The agent stopped only this
identified diagnostic engine and preserved all files as **incomplete**;
the run's `meta/agent_interruption_notice.md` records this explicitly.

`RASIPDSCHContext.m` no longer equates one layer with one RX branch.
`PDSCHReceiver.m` routes unequal AWGN reference/RX dimensions through its
existing per-resource DM-RS estimator and multi-branch equalizer. The
operator remains labeled AWGN; actual RX dimensions, rank, DM-RS and oracle
checks remain enforced. Equal-port AWGN and fading paths remain distinct.

`shared_awgn_sib1_diversity_20.log` exited 0: the actual four-branch shared
12 dB capture passed PBCH/MIB, DCI, DL-SCH CRC, ASN.1 and strict receiver
evidence; existing scalar SIB1 and RA/SI ownership regressions passed too.
Capture: `results/lls/shared_awgn_sib1_diversity/20260918_230906_157/`.
Additional four-branch Msg2/Msg4 unit-waveform regressions were added to
`testRASIPDSCHStrictOwnership`; those extensions and the next normal rerun
were then sequenced before the next normal rerun. No full 12 dB or 400 MHz
acceptance is claimed.
The `_21` batch stopped before the normal run on the new Msg2 fixture's
`isequal` comparison: absent RAR backoff is represented by NaN. The test now
uses `isequaln` for decoded structures and additionally requires bit-exact
Msg2/Msg4 transport blocks. `_22` printed
`FOUR_BRANCH_MSG2_MSG4_OWNERSHIP_PASS` before starting the normal candidate
`shared_awgn_12db_common_rx_repaired_20260918_2315`. No decoder assertion was
removed or relaxed. That normal candidate is still pending acceptance.

### Msg3 must not inherit connected experimental MCS allocation

The `_22` normal run passed strict SIB1 on all four SSB candidates and valid
TRS, then initiated PRACH at slot 15. It failed at slot 17 while preparing
Msg3: `sixgr:research:TransportGeometryMismatch`. The retained stack shows
`generateMsg3PUSCHWaveform` supplied the RAR allocation to `PUSCH_Tx`, but
the inherited connected `experimental_square_qam_v1` table activated the
research allocator and conflicted with that common-procedure allocation.
The original failure/checkpoint/profiler were preserved; only expensive
report recovery was interrupted (see that run's interruption notice).

`localizeMsg3PUSCHConfig` now validates the RAR table/modulation/rate/rank
against the common Msg3 MCS context and localizes a configuration copy.
Both Msg3 TX and RX use it and pass the actual grant MCS index explicitly.
The connected-data configuration and experimental geometry guard remain
unchanged; this is not a fallback from an experimental data grant.

`msg3_common_mcs_isolation_23.log` exited 0. The Msg3 test proves native
counterpart waveform equality, invariance under changed connected
modulation/rank, actual CRC and bit-exact TB reception, unchanged input
configuration, and rejection of contradictory common fields. The existing
experimental frozen-grant test also passes. Saved evidence is under
`results/lls/msg3_common_mcs_isolation/20260918_233011_556/`.
The normal rerun after this repair remains pending; no completed data or
full 12 dB/400 MHz acceptance is inferred from these component passes.

### Periodic CSI planning before received TA application

Normal `_24` (`shared_awgn_12db_msg3_repaired_20260918_2332`) completed
slot 17 and cleared the previous Msg3 preparation geometry error. Entry to
slot 18 failed in `armConfiguredCSIReception` with
`sixgr:link:ConnectedULBeforeTAApplication`: a received RAR timing context
existed, but its application time was later than the next CSI occasion.
The strict transmission guard was correct; calendar arming did not check
the TAG lifetime. No connected data or Msg3 reception pass was established.
The failure/checkpoint/profiler and IQ were preserved, and only post-failure
report recovery was stopped (see that run's interruption notice).

`CoupledTruthRuntime.configuredCSIReceiveTiming` now uses the strict timing
resolver to defer periodic CSI outside the received TAG application/expiry
interval. Both calendar arming and fresh report production use the gate.
Future received authority and inconsistent metadata still fail; existing
grants, waveforms, noise and the strict timing resolver are unchanged.
Configured obligations remain retained; no decoded CSI or feedback is
invented for a deferred occasion.

`configured_csi_tag_repair_29.log` exited 0: the scheduling regression tests
not-yet-effective/expired timing, exact valid boundaries, idempotent arming,
future-received authority and inconsistent RAR rejection. The existing
`testConnectedULTransmissionTiming` also passed. These are scheduling and
analytic guards, not physical reception or full-run acceptance. Earlier
`_25`–`_27` runs exposed fixture initialization omissions; `_28` verified
that future received authority is rejected before calendar arming. Those
failures are retained and are not reported as successful runtime tests.
`periodic_csi_regression_and_12db_30.log` subsequently printed
`PERIODIC_CSI_TAG_GATE_PHYSICAL_REGRESSIONS_PASS`: the producer-present
physical PUCCH case recovered CQI 10 / RI 1 / PMI 0 and passed power export;
the producer-absent case performed one actual observation with no fabricated
TX and no decoded CSI. These use declared CSI/TAG component inputs and do
not qualify CSI-RS measurement generation or detector error rates. Retained
final component evidence is under `logs/tp7ed34cef_a67e_44ea_b1c1_1ca5eddb7fd4`
and `logs/tp651c811a_0f36_42b0_b382_dc5a62a229e6`.
The same batch then began the normal candidate
`shared_awgn_12db_csi_tag_repaired_20260918_2354`; its acceptance is pending.

At that candidate's completed TRS observation, the exported
`RuntimeNoiseVarianceMean` is `3.08084640859469e-05` with
`RuntimeNoiseApplied=1`. The saved resolved YAML declares FFT 512,
7.68 MS/s and `awgn_reference_re_energy: 0.25`. The canonical transform
gives `0.25 / (512 * 10^(12/10)) = 3.080846408594694e-05`;
using unit reference instead would give `1.2323385634378775e-04`.
This is runtime evidence of the intended fixed reference on TRS, not a
claim that every connected DL/UL noise plane or measurement is closed.
TRS NMSE is `-18.5160201710111 dB` against the explicitly labeled executed
identity-AWGN reference; unavailable independent TRS SINR stays NaN.

### Setup-completion sibling PUSCH path

Normal `_30` passed the repaired slot-18 boundary and retained a physical
four-branch Msg3 observation, then failed at slot 23 in
`generateRRCSetupCompleteWaveform` with
`sixgr:research:TransportGeometryMismatch`. This separate PUSCH entrypoint
still localized only the carrier, so the connected experimental table
again reached a common-stage native allocation. The prior Msg3 repair did
not cover this sibling. Only post-failure report recovery was stopped;
the original failure, checkpoint, profiler and IQ remain retained.

The helper is now `localizeRAPUSCHConfig`, shared by Msg3 and setup-completion
TX/RX with explicit stage context. Setup completion copies its own installed
MCS table rather than inheriting the decoded RAR table, passes its actual
initial MCS index, and uses the final C-RNTI instead of the temporary one.
The research transport geometry guard and connected configuration remain
unchanged. All direct initial-access PUSCH TX/RX call sites were checked.

`ra_pusch_stage_isolation_31.log` exited 0: both stage-isolation checks,
the existing untrimmed Msg3/SRB1 timing/CRC/payload regression, and the
experimental frozen-grant regression passed. Setup isolation explicitly
uses a different native table, nonzero MCS index and final C-RNTI, with
native waveform equality, immunity to connected-policy changes and invalid
rate rejection. Captures are under
`results/lls/msg3_common_mcs_isolation/20260919_001147_152/`.
These passes do not establish the full normal access or data outcome.

The subsequent normal candidate
`shared_awgn_12db_ra_stage_repaired_20260919_0013` (`_32.log`) passed the
former slot-23 failure. Its exported `ra_attempts.csv` records Msg2 DCI and
PDSCH, Msg3 PUSCH, and Msg4 PDCCH/PDSCH CRCs all passing, `RACompleted=1`,
`StrictOk=1`, `ProxyUsed=0`, and an empty failure reason. `prach_trials.csv`
also records `RRCSetupCompleteCRC=1`, `RRCSetupCompleteDecoded=1`,
`SRB1Installed=1`, transaction 0, SRB1 LCID 1 and decoded identity `UE-1`.
The normal runtime queued its first SRS at decision slot 26 for source slot
30. This establishes the repaired initial-access sequence, not yet the
connected-data/feedback or complete 12 dB acceptance gates.

The same `_32` candidate subsequently received shared SRS at slot 30
(`status=PASS`, measured timing 77 samples, NMSE approximately -23.934 dB)
and decoded the actual connected DL DCI at slot 31. Its first exported
`air_interface/csv/dl_pdsch_trials.csv` row has `CRCPass=1`, `Layers=1`,
QPSK, MCS 1, rate 0.1533203125, `CurrentTBSBits=1064`, `BitErrors=0`,
`RawBER=0`, and RMS EVM 0.134607460400797. The receiver's raw equalizer
SINR is 18.1609384787104 dB; its explicitly labeled decision-residual-bounded
scheduling SINR is 17.4186173875141 dB. Neither is the configured 12 dB
reference. These are one actual DL reception and a sounding observation,
not a completed bidirectional/feedback acceptance or throughput campaign.

### Scheduled allocation and physical SRS capture boundary

The next normal-path check reproduced an experimental allocation rejection
in `SchedulerBase.attachCanonicalTimingDecision`: the processing-time helper
still called the native PUSCH allocator with `1024QAM`. The allocation boundary
now separates native RE/DM-RS geometry from the actual experimental modulation
and coded-bit budget. Scheduler feasibility, timing, collision checks, planned
RE allocation and normal UL grant hydration use that boundary. Reporting uses
the executed transport descriptor instead of its geometry-only QPSK object.

`testPUSCHTransportAllocation` passed in
`logs/shared_400mhz_integration_20260918/scheduled_research_shared_csi_02.log`:
rank-2/4 Qm=10 budgets, matching RE geometry, native-path identity and rejection
of inconsistent transport evidence. This is not a full scheduler/run pass.

The new bounded 5 MHz shared test recovered SS/PBCH timing, then exposed a
separate physical/logical antenna mismatch. Diagnostic run `_03.log` recorded
SRS capture start `30543/30543`, sample rate `7680000/7680000`, matching end
`38377`, but actual/expected receive branches `4/2`. The shared owner already
operates in physical-element coordinates; prepared SRS/PUCCH reception had
used the runtime logical-port count. `PreparedUplinkControlTransmission` now
binds the configured physical gNB array and retains the unchanged sample/
coverage/branch guard. Integrated rerun remains required before closure.

Follow-up `_05.log` passed the capture boundary and reached the SRS receiver.
It then stopped on `out.Ok`; allocation, scheduler consistency, link-export,
strict-proxy and config tests in the same batch all passed. Source inspection
found that `runSRSChannelEstimation` recognized scoring availability only by
the `applied_channel_gain_truth` prefix, excluding the validated identity-AWGN
reference. It now accepts successful `sharedSRSReferenceGrid` validation while
preserving the distinct identity-AWGN source and existing NMSE thresholds.
The `_06.log` integrated rerun determines closure, not this source inspection.
Run `_04.log` failed a test-only private-property access in the added assertion;
that assertion was corrected to use the public configured physical-array
authority before `_05`. No failed batch is being counted as an integration pass.

Run `_06.log` subsequently passed SRS reception and the first scheduled
noise-only PUCCH reception (`decoded=0`). Its next failure was
`CSIRSPMIPrecoderOutsidePDSCHSubspace`: the inherited two-port PDSCH projection
could not represent the CSI-RS precoder on four physical elements (relative
residual 0.5). The new fixture now configures four CSI-RS/PDSCH logical ports,
row-4 CSI-RS and the corresponding four-port Type-I report tuple, keeping all
subspace assertions intact. `_07.log` is the next focused integrated attempt;
it is not yet acceptance evidence. The original native fixtures are unchanged.

The new experiment fixture is
`lls_tdd_four_port_research_pusch_csi_fixture.yaml`; its outputs go under
`results/lls/shared_research_pusch_csi/`, with batch logs under `logs/`.
The isolated calibration helper's missing TPMI remains a separate reproduced
boundary (`scheduled_research_grant_02.log`); the shared test uses measured SRS
to provide TPMI instead of inventing a calibration value or decoded grant.

### Executed AWGN artifacts and shared UCI reducer (next checkpoint)

`scheduled_research_shared_csi_07.log` completed shared DL decoding and CSI
measurement, then failed coefficient export: `CoupledWaveformStream` requested
data-channel coefficients only when `UseFading` was true. The shared identity
operator was therefore executed but its requested observation had no retained
coefficient capture. Capture and normal data/SRS publication now recognize the
actual `IdentityAWGNRuntime` state as well as fading; exporter coverage/source
and no-additional-execution assertions remain unchanged.

Run `_08.log` passed the new physical/logical-branch regression and exported
the actual shared DL block (`ACK=1`) and channel artifact. It then reached
normal PUSCH feedback reduction and rejected the experimental UCI source tag.
`puschUCIFieldUsable` now distinguishes native evidence from the explicit
Qm=10 codec, requiring modulation, nonstandard flag and research classification
for the latter. Length, CRC and conditional short-UCI confidence checks are
unchanged. Normalized HARQ evidence retains an experimental source label.

In `_09.log`, the following focused checks passed before shared integration:

- Experimental decoder/reducer: counts 0, 1, 2, 7, 12 and 20, with deliberate
  native relabeling and missing classification rejected.
- Existing native decoder evidence and actual failed-CRC rejection.
- Existing short-UCI confidence: 55 math cases and retained weak false-ACK
  rejection; explicitly not physical detector qualification.
- Independent experimental UCI/CSI: four 25/264-PRB, rank-2/4 cases including
  normal HARQ/CSI reducer acceptance and unresolved-CSI fail-closed checks.

Retained executed DL CSV from `_08`:
`results/lls/shared_research_pusch_csi/tpc8b90f96_9538_4c3c_a2ea_82507ab7f806/shared_received_dl_harq.csv`.
It records QPSK/rank 1, CRC pass, identity-AWGN channel source, reference energy
0.25, configured 30 dB, injected grid variance 0.00025 and sample variance
4.8828125e-7 with transform gain 512. Practical pre-equalization noise estimate
is 0.000249080541421388. These are bounded 5 MHz source-block measurements,
not 400 MHz peak-throughput or all-measurement acceptance.

The new four-port CSI schema also produced a received CSI decode on the
slot-5 **no-transmission** PUCCH capture in `_07`/`_08`/`_09`. This is retained
false-report evidence, not a successful transmission or detector qualification.
The shared test deliberately preserves the actual decision. `_09` terminated
with an export readback failure, not a receiver CRC failure: the numeric
`UEHARQAttempt` was imported as a string. The independent constellation check
had passed (14,400 received UL symbols, 4.42669604473 percent RMS EVM).
`csv_type_diagnosis_10.log` confirms MATLAB inferred all 914 columns of the
78 MB received-evidence row as text, including CRC and sample-clock fields.
The saved numeric values are present; type inference is not a schema.

`csvReadTable` now accepts explicit `ColumnTypes`, rejects missing declared
columns and malformed numeric cells, and retains literal bit-vector strings.
The shared roundtrip check supplies types from its exported table; assertions
and measured values are unchanged. `testCSVDeclaredColumnTypes` exercises
these contracts; its result and existing CSV guards are recorded in
`csv_schema_guards_11.log`. This repair needs the shared rerun before closure.
The shared constellation helper now saves its CSV/PNG outputs under each
run's `results/` folder instead of global temporary storage. The experimental
wrapper releases each completed receiver state before its next replay.

`csv_schema_guards_11.log` completed successfully: declared-schema checks,
literal UCI bit preservation and existing wide-CSV reconstruction all passed.
The focused shared rerun is logged separately in
`scheduled_research_shared_csi_12.log`; launch is not acceptance. The earlier
`_09` constellation artifacts were copied, without deleting their temporary
originals, into that failed run's `received_constellation/ul_slot_10` folder.

The first `_12` shared execution (`forget_producer=0`) has now printed
`TDD_INDEPENDENT_SHARED_HARQ_PASS` and `SHARED_PUSCH_CHANNEL_ARTIFACTS_PASS`:
actual DL/UL, one common feedback commit, ACK=1, SRS/DCI/PUSCH/UCI and artifact
readback assertions passed. Its output root is
`results/lls/shared_research_pusch_csi/tpbe94db84_b1c1_4f1e_a3fa_161a4cc4154c`.
The enclosing two-replay test subsequently completed with exit 0 and
`SHARED_RESEARCH_PUSCH_CSI_COMPLETION_PASS`. The second run
(`tp20c01ab2_7a56_4b15_b651_16a5619b47cd`, `forget_producer=1`) also passed;
the wrapper verified identical received scheduler CSI after producer-state
removal/poisoning. This closes the bounded 5 MHz/30 dB component, not
5 MHz/12 dB or full 400 MHz acceptance. Noise-only PUCCH false-report evidence
remains explicitly unqualified.

Follow-up source audit (while `_12` runs, without modifying its loaded PHY):

- `freezePHYGrant.m` captures `CodingLayout.MCSTable` but not the installed
  experimental table rows or UCI policy. `applyPHYGrantToConfig.m` restores
  MCS index/modulation/rate but does not restore the table name. Reuse compares
  a pre-existing config hash, not the actual current coding-policy contents.
  `testExperimentalFrozenGrantContext.m` specifies snapshot, replay and
  changed-context rejection checks. After both `_12` PHY replays completed,
  grant creation/reuse and replay were patched to preserve/validate the full
  table and UCI policy with an integrity digest. Native coding behavior is
  unchanged. `_13` exposed a private-hash-method access error in the new
  implementation; that call now uses public `sixgr.util.sha256Hex` instead.
  The native frozen-waveform replay check passed, but the batch was stopped
  during its broader 64-element regression to prioritize four-port TDD.
  `_13` is failed/incomplete, not a qualification receipt. In
  `experimental_frozen_context_14.log`, the corrected experimental-context
  test, four-port scenario configuration test and existing causal-SRS frozen
  UL grant test all passed (exit 0). `_12` predates the new guard.
- Independent parsing of the retained `_09` CSV found 78,266,879 characters
  in `UCIReceiverEvidenceJSON`; the next largest field is only 36,762.
  `receiveWithCSIPresence.m` retains both complete candidate decoder outputs
  under `CandidateDataEvidence`, including codeword/rate-recovery evidence,
  and `runULPUSCHThroughput.m` serializes that tree into every trial row.
  No evidence has been removed. Compact referenced binary storage may be
  needed for 400 MHz; any change must preserve exact receiver evidence and
  cannot alter presence decisions, CRCs, confidence thresholds or provenance.

### Normal four-port 5 MHz / 12 dB candidate

`lls_tdd_5mhz_four_port_shared_awgn_12db.yaml` inherits the full 58-slot access/
control coordinator, with reusable `mimo/shared_four_port_control.yaml`, the
explicit shared identity channel and fixed 0.25-RE noise reference. It keeps
initial access/RA/real feedback enabled and starts UL at experimental-catalog
QPSK, not forced 1024-QAM. The original 5 MHz and ideal 400 MHz profiles are
unchanged. Schema/internal-config checks passed in `_14`; these are not
executed throughput or measurement acceptance.

The normal front-door run was launched with tag
`shared_awgn_12db_20260918_2236`; its log is
`logs/shared_400mhz_integration_20260918/four_port_5mhz_12db_normal_15.log`.
Outputs belong under
`results/lls/lls_tdd_5mhz_four_port_shared_awgn_12db/`.
No terminal result is claimed until that batch and its artifacts are checked.

The 400 MHz initial-access audit additionally found the explicit
`MixedNumerologyCollisionValidationRequired` guard in
`generateSSB_MIB_SIB1_Waveform.m`: differing SSB/initial-BWP SCS is not yet
composed safely. Connected lab initialization versus full initial access has
been raised as a scope choice; neither option may fabricate decoded access
evidence or replace the requested physical control/feedback channels.

### Experimental connected UL transport (follow-up implementation)

The catalog now defines `experimental_square_qam_v1` with explicit lab
codepoints for square-QAM/rate pairs, including 1024-QAM rates 0.5, 0.82,
0.85 and 0.9. These are **not standardized NR UL MCS indices, calibrated
ILLA thresholds, or evidence that every rate meets a BLER target**.
The original ideal-feedback peak scenario remains unchanged.

`research_connected_ul_mcs.yaml` selects the table and explicit UCI policy.
Scenario/core validation requires the research classification and CP-OFDM
without PTRS. Normalization no longer copies a directional MCS override into
the common table, and initial MCS validation uses its directional table.
The installed DCI context binds the full experimental table contents and
transport policy; undefined codepoints and modified definitions fail closed.

The connected allocation, UE new-TB/HARQ transmission and PUSCH TX/RX entry
points now build/use the explicit transport adapter. The native QPSK object
owns RE/DM-RS geometry only; actual Qm=10 owns TBS, G, coding and demapping.
The gNB rebuilds its transport from its own scheduled configuration and UCI
obligation, not a copied UE transmission or decoded UE grant.

`connected_research_pusch_combining_03.log` completed with exit 0 and seven
passing tests. It includes eight actual blind-PDCCH/coded-PUSCH cases:
25 PRBs/15 kHz and 264 PRBs/120 kHz, ranks 2/4, RV 0 then RV 2, five ACK
bits, fixed 0.25-EPRE/30-dB reference, code rate 0.5. All exact TB/CRC/ACK
checks passed with receiver-owned soft combining on retransmission. TBS
values are 35,856/71,688 and 376,896/753,816 bits respectively. This batch
used direct AWGN samples, not the production shared-clock physical owner.

Keep the failures as evidence: `research_mcs_config_01.log` exposed the
directional-to-global alias leak; `_02.log` exposed the missing explicit
core-catalog choice. `connected_research_pusch_diagnosis_02.log` shows that
the standalone rank-4 RV=2 decoding failed CRC at the unchanged test point,
with correct ACK bits and no prior soft buffer. This is not overwritten by
the later successful combined decoding result.

The production-owner extension in `connected_research_shared_clock_04.log`
initially failed because the new fixture passed post-AGC samples directly
to the FFT/decoder. The existing production receive path already calls
`compensateReceivedAGC`; the fixture now uses that same applied-gain-trace
compensator after the actual RF/ADC stages. It does not reconstruct clipping,
remove quantization, change noise, or infer gain from a wanted waveform.
`connected_research_shared_clock_05.log` subsequently passed both selected
tests (eight waveform cases plus experimental configuration guards). The
same rank-2/4, RV-0/2 TB/CRC/ACK checks pass at both widths through the actual
shared physical owner, retained RF/ADC, applied-gain compensation and
receiver-owned soft combining. The owner also executes the silent gap
between HARQ attempts on actual CP-OFDM sample boundaries, retaining AGC
and noise state. The configured grid noise stays 0.00025; receiver estimates
range from about 0.000226 to 0.000266 in these finite observations.

Scope: PDCCH is genuinely waveform-decoded but remains a separately prepared
control observation in this fixture. PUSCH uses the production physical
owner. This is not yet a common PDCCH/PUCCH/CSI-RS/SRS/data timeline under the
coupled coordinator, not a missing-DCI campaign and not throughput acceptance.

Batch `_04` completed with **11 passes and the one fixture failure above**
(overall exit 1). Passing guards include `testConfig`, strict proxy/no-fallback
checks, scheduler-grant consistency, native connected rank 2/4 and HARQ,
configured AWGN reference energy, `testLLS_DL`, `testLLS_UL`, and
`testLLS_ReferencePoints`. The failure was not hidden by those native passes.

Still required: normal scheduled/frozen-grant preparation and completion
through the coupled coordinator, including consumers in
`runULPUSCHThroughput` that currently read geometry-only `tx.PUSCH.Modulation`;
actual combined CSI/SR ownership, physical missing-DCI cases, final calendar,
measurement exports, and both complete requested runs. Component passes do
not close those gates or establish a new throughput figure.

### Connected MCS-context closure (after cleanup stopped)

`ConnectedDCIProfile.fromRuntimeConfig` previously omitted the installed
directional MCS tables from the context digest. Therefore retained,
CRC-accepted DCI could reach materialization after that context changed.
`mcs_context_reproduction_01.log` retains the new four-port regression's
pre-fix failure (`test:MissingRejection`), using actual blind PDCCH reception.

The production context now includes `DLMCSTable` and `ULMCSTable`. Changing
either table invalidates the paired installed context before semantic
materialization or data allocation. This does not add bits to DCI, change
standard MCS meanings, or bind bootstrap MCS/NSCID/TPMI/scoring data as RX
authority. The existing allocation test now expects the earlier
`stale_bwp_context` rejection instead of the later table-only guard.

Focused verification is recorded in
`logs/shared_400mhz_integration_20260918/mcs_context_binding_01.log`.
All seven selected tests passed; MATLAB exited 0: connected DCI profile,
four-port UL rank 2/4, DL/UL materialization, coded data allocation,
modulation-only HARQ MCS semantics, received UL HARQ retransmission/TB
retention, and multi-DCI blind monitoring. No MCS/CRC/noise assertion was
relaxed; bootstrap/scoring poisoning invariance remains tested.
This table-name repair alone did not enable the experimental bridge. The
subsequent implementation described above adds the experimental definition
and contents/policy binding; full 5 MHz/400 MHz execution remains unqualified.
No `testAll` was launched.

The opt-in identity-AWGN shared-clock prerequisite has been implemented
locally. `channels.shared_identity_awgn_enabled` is schema-backed and maps to
the physical runtime; incompatible channels and the old research runner are
rejected. The completed peak scenario is unchanged. This is **not yet a
complete shared-control 400 MHz scenario**, and no replacement peak YAML or
full-feedback throughput result is being advertised.

Focused batch `logs/shared_400mhz_integration_20260918/identity_runtime_04.log`
completed successfully:

- `testSharedIdentityAWGNRuntime`: four-port exact identity, split clock,
  common-owner DL/UL reversal, source-preserving CSV/MAT export/readback and
  negative configuration/dimension/source guards. Artifacts are retained
  under `results/diagnostics/shared_identity_awgn/`.
- `testType2HARQACKLayout`: gaps/wraps, 256 DAI sequences and serialization.
- `testScheduledHARQFeedbackMapper`: 13 declared cases, 28 guards (not RF).
- `testPUSCHScheduledHARQMapping`: 48 declared cases (not RF).
- `testResearchDLHeavyConfig`: original 50 DL / 20 UL opportunities retained
  (configuration test, not another throughput execution).

Earlier logs are preserved. Batch 02 failed on a char-vector equality in the
new test's state-key assertion; the assertion was corrected to compare scalar
strings. No production assertion was relaxed. Batch 04 tested the corrected
source plus the artifact and YAML guards.

The active goal retains experimental 1024-QAM DCI/UCI integration. A
supported-modulation plumbing test is not permission to replace the requested
1024-QAM peak scenario with 256-QAM or to label research codepoints as NR MCS.

### Follow-up repair receipt (18 September)

Three bounded repairs now have focused verification; neither complete scenario
has been rerun or accepted on these edits:

1. **Fixed AWGN reference authority.** YAML
   `simulation.awgn_reference_re_energy` maps to
   `channel.awgnReferenceREEnergy`. The catalog default remains 1; the existing
   fixed-four-port fragment explicitly selects 0.25. Shared and standalone
   fixed-SNR receivers use the same resolver. Conflicting research/reference
   values fail validation. Receiver registration fixes the noise variance;
   neither rank, received power nor CRC recalibrates it. Actual sample tests
   passed at 25 PRB / 15 kHz and 264 PRB / 120 kHz, including exact split-clock
   continuity and quarter variance / half amplitude. Measured grid variances
   were 0.000249824303907 and 0.000249697506845 for configured 0.00025.
   Evidence: `logs/shared_400mhz_integration_20260918/configured_noise_01.log`.
2. **Ports versus layers evidence.** The retained 5 MHz run used two actual
   UL precoder ports for one layer. `resolveNominalVsEffectiveMIMO` incorrectly
   required equality. It now checks each row's layer/port capacity and rejects
   invalid explicit port evidence, rather than comparing modal port count to
   configured rank. Positive two-port/rank-one and negative minority-row
   tests pass. Existing full-element/rank evidence tests also pass.
   Evidence: `logs/shared_400mhz_integration_20260918/port_rank_noise_regression_02.log`
   (also passed existing research calendar and physical PBCH AWGN/fading checks).
   Batch 01 retained a new-test fixture error: its configured port count was
   one while the test declared two. The fixture now explicitly configures two.
3. **CSI report acceptance contract.** Four retained DL reports at delivery
   slots 40, 45, 50 and 55 had decoded CQI/RI/PMI/CRI. Their SINR was correctly
   unavailable because this payload does not report SINR. The TDD audit had
   incorrectly required it in the received report. SINR is now required on
   the upstream actual CSI-RS measurement; the report gate requires decoded
   fields, report identity/delivery evidence and decode success. Generic
   `any` success gates now require success on a row with valid measurements,
   preventing an unrelated UL or incomplete row from satisfying the gate.
   Positive and negative audit tests pass in
   `logs/shared_400mhz_integration_20260918/csi_audit_01.log`.

These repairs do not establish physical missed-DCI qualification, a complete
400 MHz control calendar, the experimental 1024-QAM shared adapter, or final
measurement/report acceptance. Those remain implementation gates below.
`testAll` remains stopped at the user's request; no release qualification is
claimed. Changes are local and not yet committed or pushed.

The unchanged fading-path regression also passed:
`logs/shared_400mhz_integration_20260918/tdd_channel_regression_01.log`.
`testRuntimeChannelContinuousSamples` compared 38,400 actual TDD CDL samples
with the toolbox object and independent partitions; whole-waveform relative
error was 1.78821e-16. This is not a full data/control decoder regression.

### Explicit-Qm UCI and four-port CSI implementation receipt

The existing PUSCH multiplex/demultiplex receiver now accepts an explicitly
typed research resource adapter. Native `nrPUSCHConfig` execution is retained
unchanged. `coding/research_pusch_uci.yaml` selects the experimental map;
it does not enable physical shared feedback in the peak scenario by itself.

- `PUSCHUCIResourceAdapter` derives whole-symbol UCI positions from the public
  QPSK geometry map with the actual UL-SCH TB/segmentation, then expands each
  symbol to its configured Qm. Unsupported geometry and UCI-only allocations
  fail closed. Qm=10 remains explicitly experimental, not native NR PUSCH.
- Short one/two-bit UCI uses an explicit Qm=10 extension with independent
  placeholder reconstruction. Native modulation paths and confidence gates
  remain unchanged; no invalid-metric rescue was added.
- `PUSCHUCIDemultiplexer.receive` uses receiver-installed HARQ/CSI identities;
  received CSI Part 1 determines Part 2 length. It does not consume the TX
  payload. Unresolved received CSI retains only independently invariant maps.
- The independent receive test exposed the actual four-port rank ceiling in
  `TypeISinglePanelCodebook`, `CodebookEngine`, `MIMOCapabilityProfile` and
  both CSI schema/wire guards in `CSIReportConfiguration`. Four-port ranks
  3/4 now use TS 38.214 Tables 5.2.2.2.1-4/-7/-8. Larger-port high ranks remain
  unsupported; no generic DFT substitute was installed.

Completed focused receipts:

| Log in `logs/shared_400mhz_integration_20260918/` | Verified scope |
| --- | --- |
| `research_uci_adapter_01.log` | 100 maps: 80 native modulation comparisons and 20 Qm=10 cases, 25/264 PRBs and ranks 2/4 |
| `research_uci_codec_01.log` | Four actual 1024-QAM/AWGN LDPC+UCI cases with exact TB/CRC recovery; 55 existing short-UCI confidence cases |
| `four_port_csi_and_independent_uci_02.log` | 64 independent rank-3/4 matrix comparisons; 128 received CSI round trips on PUCCH/PUSCH; four independent Qm=10 HARQ/CSI receive cases; existing native resource-invariance and receiver-evidence tests |
| `typei_and_uci_regression_01.log` | 35,232 existing rank-1/2 matrix comparisons passed; batch then failed on a pre-existing PUCCH fixture requiring nonempty PUSCH Part 2 |
| `typei_and_uci_regression_02.log` | Corrected four-port CSI engine transport test, PUCCH padding ownership, four independent Qm=10 receivers with stale prior RI=1, 100 resource maps, four actual LDPC+UCI decodes and 55 short-UCI confidence cases passed; exit 0 |
| `four_port_high_rank_selection_02.log` | 64 matrices/128 CSI round trips reverified, plus production CSI selection/report/decode with allowed ranks [2,4] for both codebook modes using an explicitly analytic component input; exit 0 |

The fixture explicitly checks nonempty Part 1/2 for PUSCH, transcodes to
the single padded PUCCH payload, and verifies received RI/PMI/CQI/CRI. The
original failed log is retained. Independent Qm=10 reception was also rerun
with the receiver's prior rank fixed at 1 while transmitted ranks are 2/4.
The initial added selection fixture failed the measurement object's required
`measured_` provenance prefix. Its corrected label explicitly includes
`input_fixture_analytic_identity_not_air_capture`; no primary result is
exported and this is not presented as an actual CSI-RS capture. The failed
`four_port_high_rank_selection_01.log` remains retained.

These tests are **component/symbol-level**, not a physical missing-DCI campaign
or the integrated 400 MHz throughput run. The remaining next boundary is
connecting the adapter to actual shared-clock PUSCH waveform execution and
the decoded-DCI scheduling contract, followed by the physical PUCCH/CSI/SRS
calendar. The existing ideal-feedback benchmark is still unchanged.

### Production PUSCH waveform bridge (next runtime boundary)

`PUSCH_Tx` and `PUSCH_Rx` now accept the typed `ResearchTransport` descriptor
while retaining a separate native RE/DMRS geometry object. Actual modulation
owns TBS, coded budgets, UCI mapping, scrambling/demapping and LDPC recovery.
The receiver requires a payload-free installed UCI context. Native calls
without this descriptor still use their existing path.

`production_shared_pusch_01.log` completed four actual shared-owner AWGN
waveforms: 25 PRB/15 kHz and 264 PRB/120 kHz, each at ranks 2/4 over four
physical ports. Exact TB/CRC, HARQ-ACK and received CSI fields passed.
This fixture installs the scheduling obligations explicitly; it does not
prove decoded-PDCCH scheduling, missing DCI or the full coordinator.

**The noise discrepancy was isolated and repaired, not normalized away.**
`dmrsPUSCH.m` lost `CDMLengths` when the toolbox indices API returned only
one output. Without OCC despreading metadata, the estimator interpreted
multiport pilot structure as noise (0.0917119 instead of approximately 0.000025).
It now obtains the authoritative computed `puschCfg.DMRS.CDMLengths` when
indices metadata is unavailable and fails closed on invalid lengths.
`production_shared_pusch_noise_02.log` retains the pre-fix comparison.
`production_shared_pusch_02.log` passed all four waveforms after repair:
receiver noise exactly matched independently configured toolbox estimation;
264-PRB ranks 2/4 gave 2.53659e-5 / 2.53185e-5 against actual sample variance
2.51051e-5. Data TB/CRC and five HARQ bits plus CSI still decoded exactly.
The bounded fixture is at 40 dB/reference-rate 0.5, **not** the target 30-dB
throughput qualification. The first diagnostic log
(`production_shared_pusch_noise_01.log`) failed only while printing a nonexistent
`rx.ChannelEstimateInfo` field; estimator metadata lives in the second RX
output (`info.ChannelEstimation`). Its failed log remains preserved.

The native 64-RX regression exposed a reference-plane error in its assertion:
per-branch pilot SINR was compared with post-combining SINR within 6 dB.
`native_pusch_sinr_planes_02.log` passes independent sample/analytic references:
pilot 27.1986 versus 27.1835 dB; raw post-equalization 42.2496 versus 42.235 dB.
Noise agrees with independently OFDM-demodulated actual noise. The CRC,
conservative residual bound, aligned-timing and MU projection assertions
remain and pass. No power, noise or production confidence threshold was tuned.
The old failure is retained in `native_pusch_sinr_planes_01.log`.

`production_short_pusch_01.log` passes physical 25-PRB/rank-2 transport with
0, 1 and 2 HARQ bits plus independently resolved CSI, and the existing native
DMRS EPRE and received-CSI waveform tests. Other short-feedback width/rank
combinations remain pending. `testAll` has not been resumed.

### Four-port connected DCI boundary

An additional concrete integration blocker was found: `ULPrecodingField.m`
only implemented two-port signaling, and `ConnectedDCIProfile.m` enforced
rank-one UL even though production data supports more layers. Four-port
Tables 7.3.1.1.2-2/-3 from TS 38.212 V18.8.0 are now implemented, with
noncompacted codepoints, maximum-rank and reserved-value rejection. The
connected profile retains port/SRS agreement and disallows multilayer PTRS
until its received association is implemented. A reusable YAML fragment
`control/connected_four_port_ul.yaml` owns this configuration.

`connected_four_port_ul_01.log` passed 333 independent table rows plus
reserved/rank guards and native codebook-dimension checks. Its waveform test
then correctly rejected a fixture-only PTRS override conflicting with the
resolved YAML. The corrected fixture inherits the explicit PTRS-off fragment;
`connected_four_port_ul_06.log` subsequently passed actual blind PDCCH
reception, received rank/TPMI/DMRS materialization, UE-generated four-port
PUSCH, and independent gNB TB decoding at ranks 2/4 (TBS 1,032/2,088 bits).
The existing connected-DCI regression passed in the same batch. This is a
six-PRB native-modulation component test on the 5-MHz carrier, not a full
400-MHz execution. No runtime feature guard was bypassed. Failed fixtures
02-05 retain evidence of inherited DMRS-pool, array-codebook and PTRS-CPE
dependencies, now explicitly declared in YAML. A subsequent fixture attempt
(`connected_and_400mhz_short_uci_01.log`) correctly failed contradictory
initial-rank aliases. This exposed a separate production translation gap:
`buildInternalConfig.m` assigned UL `maxLayers` from the initial selected
rank rather than `mimo.max_ul_layers`, and the SRS rank search had no installed
ceiling independent of that initial rank. The translator now preserves the
YAML ceiling in `phy.pusch.maxLayers`, `maxRankDefault` and `phy.maxULLayers`.
The connected profile requires matching DCI/runtime ceilings, preserves the
selected-rank limit and uses the UL capability in the UL context. The fixture
starts at rank one with a four-layer ceiling instead of contradicting initial
DL/UL rank aliases. Final-source verification and 400-MHz short-UCI cases are
initially failed in `connected_and_400mhz_short_uci_02.log`: a later
compatibility-alias copy still overwrote the ceiling with `pusch.num_layers`.
That incorrect copy was removed. The actual normal UL grant-cap helper in
`CoupledTruthRuntime.m` also took the minimum with bootstrap rank; it now
reuses `resolveRankExecutionPolicy`'s physical-port/codebook capacity.
Full coordinator execution of that last change remains pending.

Batch 03 then passed the four-port table/control/data checks, all six actual
264-PRB/rank-2/4 short-HARQ-plus-CSI cases, and the existing two-port/connected
DCI tests. Exit code was 0. Its original logfile was deleted by the external
cleanup noted above; captured stdout is saved in
`logs/shared_400mhz_integration_20260918/recovered_connected_and_400mhz_short_uci_03.md`.
`final_rank_ceiling_checks_01.log` subsequently passed the final-source
four-port test including rank-one-start/four-layer-ceiling assertions,
existing fixed-rank no-collapse checks and PF/RR causal-SRS propagation.
The final `testPUSCHMasterYAMLAuthority` call in that batch **only discovered**
three MATLAB function tests; they were not executed and are not counted as
passes. Full regression remains unqualified.
This is separate from the still-pending experimental MCS contract.

### Configured 30-dB production transport checkpoint

`production_shared_pusch_30db_01.log` passes all four actual shared-owner
waveforms at 25/264 PRBs and ranks 2/4 with experimental 1024-QAM, real
LDPC/CRC, five HARQ bits and independently resolved CSI. Code rate is **0.5**,
not the peak candidate's 0.9. At 264 PRBs, actual grid noise was 0.000249789;
receiver estimates were 0.000254708 / 0.000254593, matching direct toolbox
estimation. All transport bits and feedback fields decoded exactly.
The existing TDD CSI-report/source audit also passed in that batch.

This proves the bounded production transport at the requested SNR, **not**
combined PDCCH/PUCCH/PUSCH/CSI-RS/SRS coordinator operation, missing-DCI
qualification, high-rate link adaptation, or a new throughput result. Next
gates remain: experimental MCS/configuration identity through received DCI;
400-MHz numerology-3 control/feedback calendar and explicit initialization;
physical missing-DCI/combined-feedback cases; integrated measurement exports.
The existing peak scenario is still not switched to this unfinished path.

## Confirmed findings, not recycled historical failures

| Finding | Evidence | Required work |
| --- | --- | --- |
| The successful runner bypasses the shared coordinator | `+sixgr/+lls6g/+runners/runSingle.m` dispatches `research_tdd_link` directly to `runResearchTDD.m`; that runner rejects PDCCH/PUCCH/CSI/SRS and uses `IdealDelayedHARQ` | Separate shared scenario and use `CoupledTruthRuntime`/`CoupledWaveformStream`, not two concurrent coordinators or an ideal CRC feedback shortcut |
| AWGN originally did not select the shared owner | `ChannelFactory.requiresRuntimeChannelState` originally selected TDL/CDL only; `runWaveformLinkBundle.m` uses this predicate to initialize the shared stream | Opt-in identity runtime and focused checks are implemented; full shared scenario execution remains pending |
| Shared 1024-QAM is not a YAML switch | `resolveMCSProfile.m` and `resolveConnectedMCS.m` only cover the existing tables through 256-QAM; `PUSCHModulator` rejects 1024-QAM. A direct R2026a probe also rejects `nrPUSCHConfig.Modulation='1024QAM'` | Bind an explicitly experimental candidate/MCS contract through scheduler, transmitted DCI, UE grant decoding, LDPC/UCI rate matching and gNB decoding. Never silently run 256-QAM under a 1024-QAM label |
| Connected UL signaling originally supported two ports/rank one only | `ULPrecodingField.m` and `ConnectedDCIProfile.m` blocked four-port rank-2/4 grants before data execution | Four-port tables and actual blind-control-to-data component execution now pass; integrated SRS-driven selection and the 400-MHz calendar still need execution |
| Existing Type-2/combined-feedback work must be reused | Independent scheduled reception, received-DCI UE books, PUSCH total-DAI mapping and common completion already exist in `+sixgr/+truth` | Test their integration at this carrier; do not rewrite them or reintroduce transmitted-payload authority |
| Short HARQ/SR resource hypotheses remain explicitly unsupported | `buildScheduledHARQTransportReception.m` rejects `UnresolvedSRPUCCHReceiveHypothesis` | Independently schedule and qualify the allowed RX hypotheses, retain ambiguous outcomes as DTX; no strongest-energy layout selection |
| Original detector invalid-metric rescue is already removed | `PUCCHDetector.m` rejects invalid metrics | Keep this fix. The old 12/1024 false-ACK result is historical, not a new-source measurement; independent noise-only and signal-present qualification is still required |
| Ideal feedback and CSI are not over-the-air feedback | Research runner queues receiver CRC/noise directly after a configured delay; CSI/SRS signals are disabled | Replace only in the new shared profile with received control/UCI completion, measured CSI-RS/SRS and expiry-aware consumers |
| The two runners originally used different SNR reference energies | The benchmark selected 0.25 while the shared receiver originally fixed 1, a 6.0206 dB noise discrepancy | Explicit validated reference-energy authority and actual-sample tests are now implemented (receipt above); new shared scenario must select the intended reference |
| Ideal-run tail only drains feedback | `runResearchTDD.m` suppresses all TX after the data horizon | Define bounded retransmission drain separately from measurement horizon; retain pending/dropped TBs and unique payload accounting |
| Existing peak calibration is not transferable automatically | `loadAWGNCalibration.m` binds the research codec/profile, not the new shared allocation, UCI puncturing or all transitive source dependencies | Recalibrate affected allocations and record dependency hashes; independent holdout trials after candidate freeze |
| Some research guards are absent from the default test registry | New fixed-port/HARQ/adaptation/calibration/IQ/DL-heavy tests are not all listed in `tests/testAll.m` | Register relevant tests later; keep full-suite execution stopped until requested |

## Implementation order and completion gates

1. **Shared AWGN foundation (in progress).**
   - Files: `+sixgr/+channel/IdentityAWGNRuntime.m`, `ChannelFactory.m`,
     `+sixgr/+truth/SharedWaveformPhysicalRuntime.m`, shared-reference consumers,
     `+sixgr/+lls6g/buildInternalConfig.m`, channel catalogs/fragments.
   - Test exact four-port samples, split/whole clock equivalence, reversible
     TDD ownership, receiver-noise continuity, invalid dimensions/configuration
     rejection and truthful identity-vs-fading artifact sources.
   - The first bounded channel-operator test passed. It is not an integrated
     control-channel or throughput test.

2. **400 MHz connected-control configuration and runtime ownership.**
   - Add a separate YAML integration gate, initially using supported NR
     modulation to isolate control plumbing. Do not overwrite the peak YAML.
   - Map carrier/BWP/CORESET/TDRA, four-port DMRS/CSI-RS/SRS, CSI/SR calendars,
     PUCCH resources and PUSCH overlap reservations to the same resolved config.
   - Use the existing numerology-3 processing catalog, not inherited mu-0
     timing constants. Verify each selected K1/K2 against actual symbols.
   - Preserve the requested SNR definition explicitly: fixed 0.25 reference
     RE energy for the retained four-port experiment versus the existing
     shared runtime's unit-RE definition. Configure and export that authority;
     never recalibrate noise from instantaneous rank, received power or CRC.
   - Explicitly install any preconnected LLS context with its own provenance;
     never fabricate decoded SIB1/RAR/acquisition evidence. Initial access is
     a distinct capability, not implied by the requested connected benchmark.
   - Gate: actual PDCCH CRC/decoded grant -> actual scheduled DL/UL data on
     one physical owner. No direct TX `attemptConfig` fed to a supposed blind RX.

3. **Received HARQ/CSI/SR ownership across transports.**
   - Reuse `buildScheduledHARQTransportReception`,
     `buildSharedPUSCHUCIReceiveContext`, `buildReceivedHARQACKCodebook`,
     `bindScheduledPUSCHHARQMapping`, `mapScheduledHARQTransportFeedback` and
     `CoupledTruthRuntime` completion methods.
   - Prove normal combined PUCCH and overlapping PUSCH UCI, no producer,
     unselected producer, duplicate/cross-transport commit, stale/late and
     wrong-UE/epoch rejection. Preserve soft buffers/TB identity on retry.
   - Existing component fixtures are reusable evidence, not a substitute for
     the normal coordinator executing this new scenario.

4. **Missing DCI and detector qualification.**
   - Physical tests: first/interior/last/all DL DCI missed, UL DCI missed,
     >=4 and >=8 assignments for DAI wrap, changed final PRI, overlapping CSI/SR.
   - Keep exact-width checks and full scheduled identity. A shorter payload
     must not be blindly prefix-mapped to outstanding grants.
   - Poison retained producer bookkeeping while holding receiver IQ and
     installed context fixed; received field ownership must not change.
   - Independently frozen noise-only/ACK/NACK/DTX episodes with acquired timing,
     prespecified false-ACK and missed-ACK confidence bounds. Do not weaken
     the original assertions or tune thresholds on the qualification sample.

5. **Experimental 1024-QAM bridge and adaptation.**
   - Retain the requested experimental 1024-QAM target explicitly.
   - Preserve the now-explicit experimental codepoint semantics through
     normal scheduler/frozen-grant preparation; research candidate IDs must
     not masquerade as standardized MCS indices.
   - Preserve real LDPC/CRC, G/TBS and UCI rate matching, retransmission frozen
     allocation rules, rank/port selection and unique-TB goodput.
   - CSI publication must wait for actual RX availability. Scheduler rank,
     PMI/CQI and SRS consumers must reject stale or unavailable measurements.
   - Recalibrate changed allocations before OLLA/ILLA performance claims.

6. **Final measurements and execution.**
   - Reconcile TX/loss/noise reference planes, RSRP/RSSI/RSRQ on their actual
     applicable resources, practical post-equalization SINR versus reference
     error SINR, per-layer EVM, channel NMSE, BER, first/attempt/residual BLER,
     HARQ counts, CSI/SRS source/availability and unique delivered throughput.
   - Deduct actual control/RS/UCI overhead; include elapsed TDD/drain time in
     the declared headline denominator. Do not promise the ideal benchmark's
     throughput after enabling additional physical channels.
   - Run bounded smoke first, then final-source 400 MHz/30 dB. Save artifacts
     under `results/` and execution logs under `logs/`.
   - Full regression/release qualification and GitHub delivery follow explicit
     authorization to resume the stopped full suite. No claim of completion
     based only on YAML loading, component passes or a `ResultOk` flag.

## What to remove or replace

- In the new shared path only: ideal CRC/noise feedback queues, TX-authored RX
  allocation/layout assumptions and detached control-channel donor results.
- Replace hardcoded channel-reference source strings with the actual executed
  source. Never relabel the identity lab operator as measured fading.
- Do not delete the existing benchmark, calibration/results/logs, Type-2
  identity/length guards, invalid-metric rejection or existing assertions.

## Schedule policy

### Live normal-run receipt: batch 36, 19 September 2026

Evidence root: `results/lls/lls_tdd_5mhz_four_port_shared_awgn_12db/shared_awgn_12db_timing_capacity_repaired_20260919_0106`.
Execution log: `logs/shared_400mhz_integration_20260918/four_port_5mhz_12db_normal_36.log`.

- Actual DL and UL DCI at control slot 34 decoded; the UL grant executed at
  slot 35 and its PUSCH transport block passed CRC (`ul_pusch_trials.csv`).
- Slot 34 PUCCH transmitted four HARQ bits without CSI; the independent
  scheduled receiver expected 15 combined bits and rejected the CRC.
  The report reference cutoff was slot 29. The first actual CSI-RS row was
  slot 32, available at slot 33, so it cannot supply that earlier report.
  Do not remove this failure or derive the receive schema from UE presence.
- Slot 39 PUCCH transmitted and independently decoded 16 combined HARQ/CSI
  bits with CRC pass. `received_csi_reports.csv` records successful CSI
  delivery to the runtime scheduler. This is normal-coordinator evidence,
  not merely a component-fixture pass.
- Slot 44 independently decoded the next 13-bit combined PUCCH payload with
  CRC pass. UL PUSCH slots 35 and 40 both passed transport-block CRC.
- The 58-slot physical timeline subsequently completed and sealed 445440
  samples per port for two physical transmitters. All 17 DL and five UL data
  rows retained `SignalEnergyPerOccupiedRE=0.25` and injected equivalent grid
  variance `0.0157739336120048`, matching `0.25/10^(12/10)` with no mismatches.
  This verifies the injected reference for this 5 MHz execution, not the
  SRS receiver's independent noise estimate or the pending 400 MHz run.
- All five UL rows executed four-layer QPSK with CRC pass. The inherited DL
  maximum remained one layer despite successfully received RI=4 CSI reports;
  this candidate is not four-layer DL throughput validation. Slots 49 and 54
  also independently decoded their 16-bit combined PUCCH payloads with CRC
  pass. Three repeated DL TBs after the earlier missed feedback were marked
  `DeliverTransportBlock=0` in the received protocol-decision table.
- The run is still live at this receipt. These observations do not establish
  final acceptance, detector qualification, physical missing-DCI closure,
  measurement closure, or integrated 400 MHz execution.

Later finalization checkpoint, 19 September 02:43 IST: the waveform bundle
and strict control evaluation returned `ok=1`, but the runner reported
`completed_with_failures`, one required failure. `case_status.csv` identifies
`MIMO_NominalEffectiveEvidence`; `mimo_strict_gate_summary.csv` identifies
`antenna_port_mapping` for UL. The process was still exporting at this check.
`localAntennaPortMapping` in `resolveNominalVsEffectiveMIMO.m` compares the
modal transmitted layer count (four) to a nominal one-layer bootstrap DM-RS
count synthesized by `buildMIMOConfigFromScenario`. All five raw UL rows
instead carry `MeasuredDMRSPortCount=4` and four decoded layers. The required
repair is per-trial measured DM-RS validation, not deletion of the gate or
replacement of nominal metadata with runtime values. The new, not-yet-run
`testMIMORuntimeDMRSPortMapping` covers rank 1/2/4, bad minority rows and
missing counts in both directions. No final acceptance is claimed.

At 02:49 IST the preliminary truth audit also reported one round-trip
mismatch: `value_source_audit.csv` marks UL `ReceiverHestSINR_dB` unavailable
for all five trials. Source inspection found that `measureULLinkState`
extracts the physical union of reference REs but then reshapes the original
per-port symbol matrix without mapping its disjoint port resources to that
union. The existing `sixgr.phy.rx.referenceSignalMetrics` already performs
index-aligned reconstruction. Reuse that helper after baseline verification;
do not fill the missing metric with configured or post-equalization SINR.
`testULReferencePortUnion` independently checks native PUSCH DM-RS layouts
at ranks 1/2/4 for both carrier geometries, using explicitly declared channel
fixtures. It and the MIMO reducer regression are queued in batch 39 after
baseline 38; they have not executed yet. The three preliminary missing
artifact checks (issue registry, visual audit, duplicate audit) must be
rechecked after finalization rather than classified from this interim state.

Final required-artifact checkpoint, 19 September 03:22 IST: the runner
published its terminal failure status and began the optional MAT result
bundle. Engine 19528 was still alive; queued baselines had not started.
The final truth audit reduced to two failures (round-trip mismatch and the
root failed result), with zero missing-runtime-evidence entries. The Python
publisher rejected these concrete semantic disagreements before replacing
rasters:

- `fer_summary.csv`: both DL scopes report three observed frames, consistent
  with all 17 finalized DL rows at frames 4/5/6. In `tools/lls_csv_semantics.py`,
  the FER branch calls `_raw_rows_for_scope`, which excludes warm-up and
  unavailable-SINR rows. FER's declared all-executed-trial population must
  instead use finalized non-fallback trials, including warm-up failures.
- `antenna_array_config.csv`: the Python logical-port/layer formula still
  disagrees with the MATLAB per-row port-capacity contract. Keep independent
  per-row validation, including invalid minority rows; do not certify using
  only modal counts or force precoder output ports equal to input layers.
- `mimo_config_strict.csv`: the Python audit compares nominal bootstrap
  `DMRSPorts` to the modal runtime port list. Keep nominal configuration and
  directly measured per-trial DM-RS evidence separate in both reducers.

These publisher failures are retained. They are not repaired by rewriting
the captured trial values, weakening the gates, or declaring this run passed.

### Bounded SRS repair investigation while batch 36 remains live

No executing receiver source is being edited mid-run. Source inspection
identified these concrete boundaries in `+sixgr/+phy/+ul/SRS_Rx.m`:

1. `localEstimateSRSNoHop` requests despreading only when the index-info
   structure contains `CDMLengths`. Native `nrSRSIndices` does not return that
   field. Derive the applicable despreading from the actual installed SRS
   port/resource arrangement; do not supply the known injected noise instead.
2. `localSRSChannelEstimateWindow` does not read native `KTC` and can default
   a comb-4 allocation to comb 2. Read the actual configured comb.
3. `localSRSFrequencyHoppingEnabled` reads `FrequencyHopping`, absent from
   native `nrSRSConfig`. Native frequency hopping is controlled by `BHop`
   and `BSRS`; the existing per-hop estimator is therefore bypassed.

`diagnoseSRSNoiseDespreading` is queued as batch 37 after the normal engine.
It also compares the existing SRS-to-PUSCH SINR anchoring against an
independent identity-channel MMSE/codebook calculation. Do not force PUSCH
per-layer SINR to equal SRS pilot SINR or erase precoder power division.

`testSRSReceiverNoiseDespreading` is queued serially as baseline batch 38.
Its 24 cases cover the 25-PRB/15-kHz and 264-PRB/120-kHz geometries, one/two/four
ports, combs 2/4, and hopping on/off. Both the injected noise and aligned
OFDM-loopback timing are explicit diagnostic fixture inputs, not normal-run
or acquired-timing evidence. Receiver noise is estimated from received data;
the known variance is only an independent comparison. These new tests have
not yet executed at this receipt.

Work one gate at a time. Gate 1 can be verified with bounded component tests;
Gates 2-5 need integration and physical tests before a trustworthy runtime
estimate exists. Report the first failing boundary and retained log at each
checkpoint. No guaranteed two-hour full-integration or >6 Gbit/s claim.

## External capability reference

The installed MATLAB rejection agrees with the documented
[nrPUSCHConfig modulation choices](https://www.mathworks.com/help/5g/ref/nrpuschconfig.html),
which list modulation through 256-QAM. This is a toolbox/interface limitation,
not a statement that 1024-QAM research waveforms cannot be implemented.

The new four-port rank-3/4 matrices follow
[TS 38.214 V18.9.0, clause 5.2.2.2.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.09.00_60/ts_138214v180900p.pdf).
The channel-specific CSI layouts and UL-SCH/UCI symbol budgets are checked
against [TS 38.212 V18.6.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.06.00_60/ts_138212v180600p.pdf),
clauses 6.3.1.1.2, 6.3.2.1.2 and 6.3.2.4. The experimental Qm=10 extension
does not establish standardized UL 1024-QAM capability or full conformance.
