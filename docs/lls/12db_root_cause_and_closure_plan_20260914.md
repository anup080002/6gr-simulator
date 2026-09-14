# 12 dB root-cause and closure plan

Date: 2026-09-14. This is a repair/acceptance plan, not a conformance certificate.

## Follow-up checkpoint: diagnosed regression repairs applied, not yet verified

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
