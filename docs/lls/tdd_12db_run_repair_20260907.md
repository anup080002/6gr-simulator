# Short TDD run: measured failures and remaining integration work

## Data-channel stream boundary checkpoint (2026-09-07)

The main scheduler is **not yet repaired or qualified**. Its last full run
remains the failed execution below. No replacement TDD, FDD or 25 dB scenario
was launched during this checkpoint.

Implemented opt-in `PrepareOnly` / `ReceivedContext` stages in both
`runDLPDSCHThroughput` and `runULPUSCHThroughput`:

- Prepare actual coded OFDM samples once, retain the frozen grant, payload,
  receiver configuration, power allocation and UL power-control state.
  Defer node PA/RF/channel execution until after transmitter composition.
  Preparation returns empty received-trial tables and does not claim RX success.
- Complete the existing receiver/metrics path from actual contiguous sample
  buffers, without rerunning TX, rescaling power, resetting the TX RNG,
  reapplying TPC, or advancing the channel. Retain separate physical TX,
  pre-RX-front-end and post-RX-front-end observations.
- Validate request identity, physical antenna counts, sample rate/origin,
  complete received coverage and equal pre/post-front-end intervals. Actual
  channel-delay tails may extend beyond the TX slot; they are not cropped or
  replaced with receiver padding by the new stage interface.
- Reject altered UCI/payload/configuration, proxy/fallback replay, incomplete
  observations and mismatched clocks before receiver execution. Stage errors
  propagate; they do not become fabricated CRC-failure rows.
- DL preparation retains authored-DCI authority; reception still requires
  decoded control binding. UL requires decoded DCI even before preparation.
- Physical transmitter-composite captures are labeled as such, not as an
  isolated channel's post-PA waveform. A nonlinear composite cannot generally
  be decomposed into unique per-contributor post-PA samples.

Eight focused checks passed in MATLAB session 46857 (exit 0):
`testDataChannelStreamStages`, `testSchedulerPDSCHTransmitAuthority`,
`testULPUSCHThroughputExecutionContract`,
`testDLPDSCHThroughputExecutionContract`, `testNoiseDomainEvidenceContract`,
`testPUSCHMeasuredReferencePowerControl`, `testPreparedWaveformPAOwnership`,
and `testSchedulerPDSCHTimingAuthority`.
Log: `logs/data_channel_stream_stages_20260907_delayed_focused.log`.

The new stage test executes actual PDSCH, PUSCH, and PUSCH plus two HARQ-ACK
bits with physical antenna projection, a declared attenuating integer-delay
test channel, fixed independently generated complex noise and complete late
samples. Exact TB recovery, HARQ-ACK recovery, sample/grid-noise identities,
one TX/one RX invocation and unchanged completion-side RNG/channel/power-control
state are asserted. The UL grant follows an actual isolated SRS waveform,
practical channel estimate and RI/TPMI selection, then actual PDCCH decoding
in a legal later TDD occasion. The analytic pathloss input and known HARQ bits
are explicitly codec-test fixtures, not measured access or scheduler feedback
from the failed production run. DL's missing channel/RF qualification-reference
gate intentionally remains failed for this component test.

An existing DL execution-contract fixture disabled PDSCH while expecting a
downstream assignment error. It now separately asserts the disabled-coverage
error and enables PDSCH for the assignment-ownership check. No production
validation or CRC assertion was weakened. Earlier failed diagnostic logs are
preserved; the earlier MU profile K0/K2 authority conflict also remains open.

**Still required:** wire these stages into the main chronological composer,
node RF and receive dispatcher alongside SSB/TRS/RA/control/SRS. Nonzero UL
timing advance is explicitly rejected by the new staging path until separate
UE-transmit and gNB-observation origins are integrated; it is not ignored or
declared fixed. Main PRACH/PUCCH timing, late-ACK collision resolution, measured
CSI feedback transport, QCL/TCI activation/use, full RF/noise reference closure,
RSSI CSV/PNG publication and the full-run output audit remain open. The legacy
CSI RSSI helper sums receive branches in normalized grid units; strict CSI
feedback instead leaves RSSI unrequested. Neither is evidence of a completed,
bandwidth/antenna/reference-plane-qualified runtime RSSI export.

No `testAll` or full E2E qualification claim is made under the bounded-test
request. Historical run outputs were not deleted, regenerated or relabeled.

## Frozen execution evidence

Run `tdd_12db_verify_20260907_0018` executed revision `9fd99e55` using
`simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml`.
MATLAB session 75994 exited **1**. The scheduled horizon was 25 slots;
execution failed at slot 16. No FDD or 25 dB diagnostic scenario was launched.
The subsequent export-regression batch did exercise its existing FDD E2E
fixtures; those are not evidence for this TDD access/timing repair.

- Slot 3: TRS requested sample 15360 (2 ms), but the eagerly executed SSB
  observation had advanced the shared TDD channel to sample 38400 (5 ms).
- Slot 13: TRS consumed its multi-slot window through sample 138240 (18 ms).
- Slot 15 prepared Msg1 for the correct current PRACH epoch, 14 ms.
- Slot 16: consuming Msg1 requested sample 107520 (14 ms), behind the
  channel's 18 ms clock. `sixgr:channel:RuntimeChannelTimeReversal` stopped
  execution. Moving the RA epoch fixed the old 4 ms target, not this overlap.
- The failure checkpoint contains `DLTrialRows=0` and `ULTrialRows=0`.
- Failure recovery also reported `sixgr:artifact:TerminalBrowserClosureFailed`
  after three passes (`materialization=0 visual=1 lineage=1`).

Log: `logs/tdd_12db_verify_20260907_0018.log`.
Run root: `results/lls/qualification_working/lls/lls_causal_access_to_data_wiring_tdd/tdd_12db_verify_20260907_0018`.
Historical artifacts were not repaired or relabeled in place.

## Output review

The separate exhaustive audit (session 69468, exit 1) used `--preview-rows 5
--strict-value-closure`. Its output is in
`results/lls/qualification_working/audits/tdd_12db_verify_20260907_0018`.
It inspected 435 CSVs, 196225 rows, 12690 columns and 68 PNGs. Parsing/raster
decoding passed; 71 required CSV semantic checks failed across 33 files.
These are failed checks, not 71 proven independent PHY bugs. Empty tables,
NaNs and diagnostic words such as "proxy" are not individually proof of
fabricated primary measurements. The primary-data absence remains a failure.

All four saved SSB candidates decoded. SSB index 0 was selected from measured
SS-RSRP (-84.7077648905873 dBm); its SS-SINR is 42.2787558330549 dB.
Recomputing RSRP from each branch's saved desired watts, SINR from its saved
desired/disturbance watts, and pathloss from TX EPRE minus RSRP reproduces all
four reported values within 3e-13 dB. This is arithmetic closure, not proof
that the incomplete combined waveform/channel/scheduler execution is valid.

Manual PNG inspection found defects not caught by the automated chart gate:

1. `channel_impulse_response.csv` explicitly records
   `ResponseType=model_average_power_delay_profile` and a source ending in
   `model_profile_metadata_not_in_path_realization`. The renderer nonetheless
   titles it "Channel Impulse Response" with a "RUNTIME MEASUREMENT" badge,
   and concatenates the repeated DL/UL tap sets on a categorical delay axis.
   Model PDP and an actually observed complex CIR must remain separate.
2. `contract__error-reliability-analytics__fer-vs-snr.csv` labels 35.776611
   as `ConfiguredSNR_dB`, sourced from four PBCH rows. The run's configured
   label was 12. The chart also lacks a visible marker for its single point.
   The selected measurement field/domain and frame-error denominator need
   to be audited; a named chart contract does not establish physical meaning.

## Bounded evidence repair

The PBCH adapter previously left generic availability flags false despite
copying valid measured receiver SINR values. The generic string filler then
replaced empty NA reasons with invented "field_not_emitted" explanations.
`bindPBCHReceiverSINREvidence` now retains receiver values/status/reasons and
the actual post-equalizer availability flag. Missing values are not filled
and an explicitly rejected observation is not promoted by a finite number.
NA reason fillers preserve the producer's empty reason instead of guessing.
The failure-log format was also corrected from a two-element string array
to one format string, so the checkpoint coordinates can be printed.

The focused session 36464 exited 0: `testPBCHSINRRuntimeBinding`,
`testRuntimeIdentityFillerIsolation`, and `testPBCHSINRDomainContract` passed.
The new binding test uses actual SSB/PBCH decoding with reference AWGN at
12 dB, plus unavailable/contradictory receiver cases. This does not repair
the physical scheduler overlap. Export regression session 29847 also exited
0: `testLLSSINRFieldTruth`, `testLinkExportPipeline`, `testArtifactIntegrity`,
`testOrganizeRunResults_E2EArtifactPreservation`, `testSchedulerGrantConsistency`,
`testE2E_FastVsTruth`, and `testE2E_TruthPacketSemanticCampaign` passed. Results
are in `logs/pbch_evidence_export_regressions_20260907.log`. The full `testAll`
suite was not run, following the user's bounded-test instruction.

## Random-access receive-boundary repair

`runFourStepRA` now accepts a `WaveformObservationBuffer` in each existing
`RuntimeStageWaveforms.<Stage>RxWaveform` field. Before decoding, it checks
the actual sample rate, scheduled absolute sample origin, window extent and
complete contiguous received coverage. The existing receive-time bound still
prevents early decoding even when a complete buffer is supplied. This path
does not execute TX/RF/noise/channel processing again. It publishes observed
sample coordinates separately from channel/noise provenance; coverage alone
does not assert that fading or noise was applied. Non-finite or malformed
legacy numeric RX inputs are now rejected rather than passed to a receiver.

The checkpoint contract is `ra_stage_continuation_v3`, reflecting the added
observation schema. Old v2 checkpoints are rejected; begin a fresh attempt
instead of silently interpreting old state under the new contract.

Focused session 3796 exited 0, logged in
`logs/ra_received_observation_boundary_20260907.log`:

- `testRAReceivedObservationBoundary`: all five actual coded TDD stages
  decoded through externally supplied unit-channel sample buffers; incomplete
  coverage, wrong origin/rate/length, malformed values and stale checkpoints
  were rejected. This unit-channel fixture does not claim RF qualification.
- `testWaveformObservationBuffer`, `testWaveformReceiveDispatcher`, and
  `testFourStepRARequireRuntimeWaveformsFailClosed` passed.
- `testTDDCausalFourStepRARuntimeTiming(15)` passed the existing measured
  CDL-A/thermal-noise RA chain at the later PRACH epoch. This remains an
  isolated RA test, not the combined SSB/TRS/access/data scheduler.

The main scheduler still must prepare and propagate all due contributors
chronologically and dispatch actual received samples into these buffers.
It has not yet been wired to this new receive-boundary path. No replacement
full TDD run or instrument playback was launched following this patch.

## Transmit preparation and PA correctness repair

SSB/TRS shared-stream preparation previously ran the configured PA inside
`applyPowerContext`, despite advertising RF deferral. `ApplyPA=false` now
retains exact generated samples plus linear power scaling; configured PA
enablement remains intact. `PAExecutionDeferred` and its status distinguish
pending execution from a disabled device. Unexecuted PA output/compression
remain NaN. The immediate single-waveform callers explicitly retain their
existing PA execution; this does not yet move the main run to node-level RF.

Further numerical/model audit found and repaired:

1. The legacy `softlimiter` used a square root over a fourth-power envelope
   term. Its large-input amplitude folded back toward zero. It now implements
   normalized Rapp smoothness 2, `y=x/(1+abs(x)^4)^(1/4)`, using reciprocal
   ratios above saturation to avoid overflow. Tests compare the independent
   equation, monotonic saturation, phase, port independence and single/double
   precision, including finite amplitudes of 1e200. This is an explicit
   engineering amplifier model, not a claim of 3GPP hardware conformance.
2. A substring check incorrectly classified `memoryless` as a memory model.
   Model selection and explicit memory enablement must now agree. The power
   ledger also no longer labels memoryless execution as memory polynomial.
3. The native memoryless object applied AM/PM internally, then the wrapper
   applied a second conversion. Native AM/PM now executes once; an independent
   native-object comparison verifies authored backoff/gain and complex output.
4. A missing/failed native backend or unknown model no longer silently selects
   the soft limiter. Initialization failures retain their original cause.

The [MathWorks amplifier documentation](https://www.mathworks.com/help/comm/ref/comm.memorylessnonlinearity-system-object.html)
defines the normalized Rapp exponent and native AM/PM property. The installed
backend warns that AMPMConversion will be removed in a future release; the
warning was retained, not suppressed. Future backend migration needs its own
equivalence validation.

Verification, with no replacement full scenario run:

- Session 73260 exited 0 (`logs/prepared_pa_ownership_20260907_retry1.log`):
  `testPreparedWaveformPAOwnership`, `testPowerContextPhysicalUnits`,
  `testTRSPreparationAuthority`, `testTRSReceiveCompletion`,
  `testSSBSharedReceivedBurst`, `testBroadcastTRSNoisyStream`.
- Session 10630 exited 0 (`logs/pa_response_math_20260907.log`): new limiter
  response test, power-unit test and PA-enabled preparation test.
- Session 36410 exited 0 (`logs/pa_model_authority_20260907_retry1.log`):
  `testPAModelSelectionAuthority`, `testPASoftLimiterResponse`,
  `testPowerContextPhysicalUnits`, `testRFImpairmentOrderedChain`,
  `testPreparedWaveformPAOwnership` on the final model changes.
- The first preparation fixture incorrectly treated immutable ScenarioConfig
  as a struct; it was corrected via toStruct and full scenario validation.
  The first ordered-RF regression reproduced the old square-root equation;
  its expected equation was corrected, retaining the same numerical tolerance,
  power-delta check and EVM check. Both failed attempts remain in their logs.

No historical CSV/PNG was rewritten. Composite per-transmitter RF ordering,
continuous PA memory, calibrated absolute input/reference planes, receiver
noise/interference composition and the main scheduler remain separate work.
These bounded tests do not establish all-impairment or instrument qualification.

## Scheduler transmitter authority and DCI timing repair

The configuration-oriented `scheduler_truth` PDSCH transmitter previously
required `ControlDecodeOk` and `PDCCHGrantBindingOk` before generating gNB
samples. That is the wrong causal boundary for a composed downlink stream.
The receiver still requires those checks; they were not removed from RX.

- `PDSCHAssignmentFactory.forSchedulerTransmission` now creates an immutable,
  explicitly transmitter-owned scheduler assignment. It carries the authored
  DCI identity, empty decoded identity, false decode/CRC flags and no decoded
  RNTI. Canonical PDSCH reception rejects this transmitter assignment.
- The active `PDSCH_Tx` adapter now validates actual authored DCI bits and
  their immutable serialization context against the materialized allocation,
  MCS/RV, RNTI, HARQ/NDI, frozen HARQ identity and absolute control/data timing.
  It produces actual coded/precoded/OFDM samples without claiming reception.
  RX retains separate decoded-grant assignment materialization. TX source
  labels no longer describe its assignment as a decoded PDCCH result.
- `DCIContextFactory.fromScheduledGrant` now binds connected DCI contexts to
  the actual scheduled UE RNTI, preserving the installed RRC layout without
  mutating its shared template. The stricter check exposed the prior use of
  template RNTI 4660 for a grant addressed to a different UE.
- TDRA selection now matches K0 for DL and K2 for UL as well as the symbol
  allocation. Conflicting timing aliases, an incompatible explicit row index,
  or no matching row fail before DCI serialization. Symbol-identical rows
  with different future-slot offsets are no longer interchangeable.
- The active DCI schema still has one TB's MCS/NDI/RV. Two-codeword scheduler
  signaling is explicitly rejected, not implemented by duplicating TB1's
  fields. This limitation does not alter the canonical calibration chain's
  separately supported codeword geometry.

Verification on the final code:

- `logs/scheduler_pdsch_transmit_authority_20260907_final_focused.log`, MATLAB
  exit 0: seven assertion-based checks executed: TDRA failure diagnostics,
  per-UE DCI context identity, scheduler TX authority, TX/RX separation,
  scheduler PDSCH timing, TDD rank-one/two-port CSI-RS and YAML PT-RS execution.
- `logs/scheduler_dci_context_matlab_unittest_20260907.log`, MATLAB exit 0:
  `testDCIWrongContextRejection` and `testDCIPackParseRoundTrip` executed using
  `runtests` with `assertSuccess`; `testCausalSpatialPortRankDependency` also
  passed actual PDSCH/PUSCH layer-to-port waveform checks. Earlier direct
  calls to those two function-based suites only constructed test objects;
  they are not counted as test execution.
- Ten focused checks passed. This is not `testAll`, a full TDD/FDD scenario,
  or the failed MU-MIMO regression described below. No new complete run was
  launched while its known shared-clock failure remains unresolved.

The focused coded TDD boundary test generates PDSCH before PDCCH reception,
verifies rejection without decoded control, then executes the actual PDCCH
decoder and recovers the same PDSCH TB bit-exactly using its immutable coding
plans. This is a unit-channel codec/authority check, not a new complete run
or a physical SINR, interference, RF, or link-adaptation qualification.

Failed attempts remain in `logs/scheduler_pdsch_transmit_authority_20260907*.log`.
They exposed two implementation integration mistakes (a missing source-label
argument and an unnormalized `DCI_1_1` alias), corrected TX-only fixtures that
previously invented reception flags, and stale PT-RS fixture symbol/K0 values.
The fixtures now pack actual DCI and use the installed TDRA allocation.

**Open regression:** `testSchedulerMUMIMOGrouping` reaches an actual
configuration conflict in the older 64x4 repair profile: the scheduler's
K0=0 differs from the active operator DCI table's K0=4. Static inspection of
its inherited UL table also finds K2=1 while the derived profile selects K2=4. Neither conflict
has been rewritten or bypassed to make a test pass. Align the profile's
canonical timing declarations and legal TDD occasions before rerunning that
profile. The current 5 MHz causal TDD profile is a different configuration.

PDSCH time-domain allocation includes the DCI-selected K0 and symbol span;
matching symbols alone does not establish a matching transmission occasion
([TS 38.214 V18.8.0, section 5.1.2.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf)).
No standard edition was changed by these repairs.

## Ordered work still required

1. **P0: main scheduler sample ownership.** Replace eager multi-slot physical
   execution with prepared TX contributions, one chronological node/carrier
   sample stream, and complete received-window dispatch. Register SSB/TRS,
   RA stages, control and data before consuming their common intervals.
   Prepare gNB PDCCH/PDSCH from the same grant without making transmission
   depend on an already completed UE DCI decoder. Apply PA/TX RF to each
   transmitter's composed antenna samples, not independently to contributors.
   Preserve TDD reciprocity and FDD independent carrier states. Do not reset,
   rewind, clamp clocks, clone future tails or disable conflicting resources.
2. **P0: RA reception integration.** The existing prepared-stage continuation
   API does not yet connect its waveform to the common sample owner. Its
   typed receive-buffer path now validates sample-clock and coverage, but
   still needs the common owner's receiver-noise and transport evidence.
   Complete each stage from the actual stream, then expose decoded RAR,
   timing advance, contention identity and RRC state at the correct deadline.
3. **P0: reference-SNR authority.** The current YAML resolves physical thermal
   noise and geometry; its 12 dB is noncontrolling metadata. A genuine 12 dB
   reference-SNR run needs a declared RE/branch reference and frozen
   independent calibration, not per-faded-waveform measured-power AWGN.
   Keep link-budget operation separate; never force instantaneous SINR to 12.
4. **P1: actual data/feedback closure.** Execute and inspect PDSCH/PUSCH CRC,
   adaptive MCS/rank/precoder, CSI/SRS age, PUCCH overlap and HARQ delivery on
   the repaired timeline. Zero trials cannot establish correctness.
5. **P1: output semantics and coverage.** Repair the model-PDP/CIR and
   configured-SNR/estimated-SINR chart distinctions; close remaining audited
   identity, required-schema, reciprocity, stage-evidence and publication
   failures using actual outputs. Repeat all first-five-row/value reviews.
6. **After correct LLS: instrument export.** User targets M9384B/M9383B and
   89600 VSA/89601201C. Preserve actual continuous complex IQ per physical
   transmitter branch with sample clock, RF center, units/scaling, absolute
   origin, TDD activity and hashes. Existing grant IQ snippets are not the
   all-channel stream. Verify file round trips and model-specific playback;
   do not claim instrument validation without executing it.

The three supplied Downloads prompts are supporting engineering requirements,
not authority to silently replace this 5 MHz/CDL-A single-UE experiment with
their differing 100 MHz/CDL-C/two-UE RF examples or upgrade pinned NR editions.
Keep waveform receiver estimates separate from standardized SS/CSI quantities
([TS 38.215 V18.2.0, clauses 5.1.1/2/5/6](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf)).
Reference-SNR normalization must document RE/antenna and FFT conventions
([MathWorks SNR definition](https://www.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html)).
No full-simulator, all-impairment, instrument, or 6G conformance claim is made.

## Explicit uplink, spatial-control and RSSI acceptance scope

User-requested extension: after closing the shared-clock failure and main
stream integration, verify all of the following on the actual same run.
These are OPEN checks, not claims of already implemented or qualified output.
The last complete attempt produced zero PUSCH trial rows; isolated PRACH
tests cannot substitute for that missing run-level evidence.

- PRACH: actual scheduled occasion, waveform sample origin/duration, UE TX
  versus gNB receive timing, detection/correlation, timing advance, decoded
  RAR and subsequent Msg3/Msg4/RRC availability. Trace each stage through the
  common stream, without legacy self-loop, future-tail or proxy substitution.
- PUSCH: decoded UL DCI authority, actual K2/N2/TA timing, exact frozen TBS,
  LDPC/rate matching, RV/NDI/HARQ state, DM-RS/precoder/rank, practical channel
  estimates, CRC, power control/PHR and offered-versus-delivered payload bits.
  Check both TDD symbol ownership and FDD directional/carrier separation in
  code; do not launch a FDD scenario without a new user request.
- PUCCH and UCI: actual scheduled SR, CSI and HARQ-ACK bits, format/resource
  selection, K1/N1 and codebook timing, coding/CRC applicability and complete
  receiver outcomes. Trace late ACK reservations onto already queued PUSCH,
  exact UCI-on-PUSCH coding/multiplexing/rate matching and receiver recovery;
  do not count one feedback payload as both standalone PUCCH and multiplexed
  UCI. Verify policy-driven suppression is explicit and cannot silently
  starve UL data.
- SRS: configured occasions, comb/cyclic shift/port mapping, physical antenna
  samples, actual gNB estimation, feedback age and UL rank/TPMI/precoder use.
  Do not use an unavailable future SRS result or relabel a DL estimate as an
  observed UL sounding result. Preserve TDD reciprocity versus FDD separation.
- QCL/TCI and beamforming: trace source RS identity, configured QCL type,
  activated TCI state and effective slot through spatial processing. Keep
  spatial receive-filter assumptions separate from a PMI transmit matrix.
  Export actual activation/selection/use evidence to CSV and evidence-backed
  plots; distinguish configured states from states actually used.
- CSI feedback/PMI: trace measured CSI-RS through RI/PMI/CQI selection,
  reporting/transport delay, decoded feedback availability, scheduler
  decisions and frozen applied precoders. Flag stale or bootstrap values
  explicitly, and reconcile CSV/PNG identities with executed samples.
- RSSI: verify the applicable NR measurement definition, measurement symbols
  and bandwidth, antenna/branch aggregation, linear total received power,
  receiver reference plane and units. Export the actual value plus that
  context to CSV and runtime PNG; do not substitute RSRP, a link-budget
  prediction, a plotted SNR setting, or fabricated unavailable values.

Audit legacy callers and shortcuts for every channel above. Preserve absent
or inapplicable evidence with explicit reasons; never create primary rows or
plots simply to make channel coverage appear complete.
