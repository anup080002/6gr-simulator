# Short TDD run: measured failures and remaining integration work

## SRS priority versus committed UL control checkpoint (2026-09-07)

The main chronological waveform owner is **still incomplete**. No new
production TDD/FDD/25 dB run was launched and no production CSV/PNG was
regenerated. The failed production run and all earlier failure evidence remain
unchanged. This checkpoint repairs another actual scheduler ordering defect,
not the original whole-stream time reversal.

Reproduction: `logs/srs_ul_commit_boundary_20260907_repro.log`, session 75127,
exit 1. The first-measurement SRS policy deleted an already DCI-authorized
PUSCH candidate while its HARQ feedback remained reserved for PUSCH UCI. The
runtime had already passed standalone PUCCH dispatch for that slot. The unit
fixture demonstrated lost transmission ownership; it is not a newly observed
production waveform or proof that the current preserve-PUSCH TDD policy took
this alternate-policy branch.

Implemented repairs:

- Main future-UL scheduling now evaluates the existing YAML first-SRS policy
  **before** PDCCH qualification. `planFirstSRSULResources` compares the
  actual Toolbox SRS/PUSCH allocations and removes only colliding tentative
  candidates. The caller releases their tentative HARQ reservations before
  transmitting DCI, rather than retracting a decoded grant later.
- `puschHasCommittedControlOrUCI` protects received DCI/binding authority,
  expected UCI including a zero-valued NACK, and live HARQ/CSI reservations
  identified in the pending/trace tables. A stale grant copy cannot erase
  a live reservation merely by omitting its UCI flag. Completed old table
  entries do not themselves protect an unrelated tentative candidate.
- Due-slot SRS arbitration now preserves these committed grants. It also
  rejects a malformed ordinal or a different-slot grant before any candidate
  HARQ cancellation. Previously ordinal rounding/filtering could silently
  discard an invalid collision record.
- Current execution and pre-DCI planning use the same SRS eligibility helper.
  Future access/attempt/success records cannot authorize an earlier decision.
  Disjoint PUSCH allocations and the default preserve-PUSCH policy remain
  unchanged. Known overlapping standalone PUCCH prevents a first-SRS resource
  reservation. A blocked measured UE's SRS does not consume the planning
  quota and starve a later UE's first measurement.
- `SRSResourceDecisions` retains the actual allocation sources, overlapping
  coordinates, control and target slots, pre-DCI stage and candidate-deferral
  flag. These rows explicitly describe planning, not received PHY samples;
  they are not inserted into the primary SRS/PUSCH trial tables. No new YAML
  mode, fixed MCS/rank, proxy measurement or success gate was introduced.

The first combined rerun, session 39718, remains failed in
`logs/srs_ul_commit_boundary_20260907_focused.log`: six tests passed, while the
new invalid-ordinal case exposed an existing two-element string used as an
`error` message. Its text is now one scalar message so the intended strict
error identifier is preserved; no assertion was weakened.

Final focused verification: session 42692, exit 0,
`logs/srs_ul_commit_boundary_20260907_verified.log`, all eight passed:
`testSRSPUSCHRuntimePriority`, `testFirstSRSULPreDCI`,
`testFutureULPlanningCausality`, `testSRSPUSCHExactCollisionFDDTDD`,
`testSRSPUCCHExactCollisionFDDTDD`, `testGrantCacheLiveUCIAuthority`,
`testRecoveredPUSCHUCIEvidence` and `testSchedulerGrantConsistency`.
`git diff --check` passed. The duplex tests materialize configured allocations;
they do not launch FDD or TDD production simulations. The UCI recovery test
checks constructed table semantics, not a new received waveform. No `testAll`
or full campaign was run. The NR-validation/result-integrity skills kept those
scope boundaries and failed evidence explicit.

Additional open issues identified during this review, not repaired here:

- Same-UE SRS/PUCCH arbitration currently compares exact time/frequency RE
  intersections. The same-carrier UE rule uses overlapping **symbols**, even
  on disjoint PRBs, and drops only the overlapping SRS symbols in the stated
  cases. Partial-symbol suppression and the aperiodic-SRS/CSI-only exception
  require producer/receiver integration; do not call the existing RE-only
  decision a complete implementation of
  [TS 38.214 v18.6.0 section 6.2.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.06.00_60/ts_138214v180600p.pdf).
- `CoupledTruthRuntime.updateHARQState` still has a missing-TB branch that
  constructs zero bits from the reported size. That branch needs a strict
  actual-payload contract and focused fixture review, not promotion to truth.
  Its execution in the last failed production run has not been established.
- Shared TX/RX origins, persistent composite node RF, complete UCI timing,
  runtime QCL/TCI/PMI application, physical RSSI exports and operating-point
  calibration remain on the acceptance path below. Component tests cannot
  qualify those remaining requirements.

## Future-UL decision-clock checkpoint (2026-09-07)

The main shared-stream owner remains **incomplete**. This checkpoint repairs
an additional real main-scheduler look-ahead defect; it does not establish a
successful production run. The last production run still has zero committed
DL and UL data trial rows. No production scenario or CSV/PNG regeneration was
launched, and no historical outputs or failure logs were deleted.

The future-PUSCH planner previously called `startSlot` for its target K2 slot
and enqueued traffic through that future slot. `startSlot` processes due
feedback, including waveform receivers. A copied MATLAB struct does not clone
its handle-valued PHY, HARQ, scheduler and protocol objects: discarding the
planning struct could therefore leave real shared objects advanced. Future
traffic arrivals also leaked information into an earlier grant decision.

Implemented repairs:

- Main future-UL scheduling now calls `futureULPlanningView`, which binds only
  the configured target resource calendar. Physical/decision time and the
  traffic-arrival watermark remain at the actual control decision. Existing
  canonical TDD partitions and separate FDD contexts remain the authority;
  there is no hardcoded UL slot or duplex-specific replacement path.
- PHY context/channel acquisition and commit, physical slot entry, traffic
  delivery and PUCCH observation reject a tagged planning view. The helper
  does not execute future feedback or enqueue future traffic. It also rejects
  a valid latest-feedback cache entry with missing/noncausal source or
  delivery timestamps. This is not a claim that every possible public
  mutation of shared handles is now guarded.
- Reference-signal selection now distinguishes `KnownAtSlot` from its
  resource-consumer slot. Future planning selects only already-available
  measurements, while testing freshness at the future transmission. The
  default preserves ordinary consumer-slot queries. Impossible valid rows
  whose availability precedes production fail rather than being repaired.
- SRS/TRS freshness no longer accepts a future success because its computed
  age is negative. Planning checks also reject success after the control
  decision even when it precedes the resource occasion.
- Future-UL decision exports include `SchedulingKnowledgeSlot` and
  `TrafficKnowledgeThroughSlot`. These express simulator queue knowledge,
  not proof of an over-the-air SR/BSR transaction.

`testFutureULPlanningCausality` exercises the production helper with the real
TDD calendar and explicitly constructed pending/queue records. It verifies
unchanged RNG/HARQ stats, no profiled future receiver or arrival execution,
preserved pending records, current-queue demand, knowledge-time selection,
freshness, invalid-timestamp rejection and blocked execution entry points. A
source-level guard verifies the main planner uses this helper. These are
component and wiring checks, not a completed scheduled air-interface trial.

Final verification on this executable revision: session 58770, exit 0,
`logs/future_ul_planning_20260907_verified.log`, all nine focused tests passed:
`testFutureULPlanningCausality`, `testSchedulerGrantConsistency`,
`testReferenceSignalCausalProducersConsumers`, `testGrantCacheLiveUCIAuthority`,
`testUplinkTruthImpairmentDirection`, `testPDCCHPreparationReception`,
`testTRSResultDelivery`, `testTRSMeasuredResultDelivery`, and
`testCoupledTruthFeedbackDelayAuthority`. `git diff --check` also passed.
No `testAll` or full campaign was run. The earlier failed guard-placement
check remains in `logs/future_ul_planning_20260907_focused.log`: the public
PUCCH wrapper initially validated the empty fixture before reaching the
private planning guard. The public guard is now before that validation;
the final rerun passes without weakening the PUCCH contract.

Remaining acceptance order is unchanged: integrate chronological shared TX/RX
processing, qualify all UL channels and UCI/control decisions on it, implement
separate TX/RX origins for nonzero timing advance, qualify delivered CSI and
active QCL/TCI/precoding, finish source-bound physical RSSI CSV/PNG exports,
then calibrate and run the short TDD diagnostic. Neither the original channel
time-reversal guard nor any measurement/CRC gate was weakened. Required full
campaign claims remain unverified under the user's bounded-test scope.

## UL clock, access observation tail and PUCCH CCE checkpoint (2026-09-07)

The main shared-clock/shared-stream integration remains **incomplete**. These
repairs do not qualify the last full run, which still failed with zero DL and
UL data trial rows. No new production TDD, FDD or 25 dB scenario was launched.
Historical CSV/PNG outputs and failed diagnostic logs were preserved.

Implemented producer/consumer repairs:

- The shared waveform impairment helper now binds the actual DL/UL direction
  into power and receiver-noise context. Previously its large-scale-context
  helper unconditionally wrote `DL`, including for UL samples. Direction
  conflicts with the retained link or power context now fail before mutable
  fading execution. Thermal-noise stream identity includes receiver direction.
- The new SRS/CDL test exposed a separate real sample-clock defect: the SRS
  producer supplied `OFDMInfo.SampleRate`, while the wrapper/channel boundary
  expected `OFDM.SampleRate`. A 7.68 MHz waveform could therefore materialize
  a 30.72 MHz channel. Initialization now forwards the resolved producer rate
  explicitly, rejects conflicting metadata or a changed retained-channel
  rate, and no longer substitutes a default rate when producer timing is absent.
- Four-step access continuation now waits for the actual complete received
  observation, including a channel/filter delay tail. It validates the exact
  producer rate and origin, permits a genuine longer typed RX observation,
  rejects a shorter one, and uses retained observations on later resumptions.
  It does not crop the tail, pad a receiver buffer, or rerun propagation.
- Corrected the PUCCH resource-set-0 mapping for more than eight resources.
  The previous modulo-full-list expression was not the normative equation.
  The implementation now uses the piecewise PRI-group/CCE mapping in
  [TS 38.213 v18.8.0, section 9.2.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
  Four vectors previously containing `SPEC_FORMULA` now contain independently
  calculated expected ordinals; production validation rejects a missing
  numeric oracle rather than accepting a placeholder. Additional cases cover
  resource counts not divisible by eight and CCE boundaries.
- Main grant annotation now retains the received PDCCH's first CCE and actual
  CORESET capacity. These values flow into the DL HARQ feedback reservation,
  PUCCH grant trace, resource assignment and interfering-PUCCH context, replacing
  fixed `0/24` operands. Retransmission-cache merging copies live operands or
  clears stale ones. Small direct-mapped resource sets do not require unused
  CCE operands; a large set fails when real CCE evidence is missing. The main
  annotation/feedback path is wired in code, not yet qualified by a full run.

Final focused verification on the executable checkpoint:

- Session 50308, exit 0, `logs/pucch_cce_20260907_final.log`: all **40**
  `testPUCCHPhase05` checks, `testPUCCHResourceIndicatorNumeric`,
  `testUplinkTruthImpairmentDirection`, `testRAReceivedObservationBoundary`,
  `testUplinkControlStreamStages`, and main-runner parsing passed.
- Session 71951, exit 0, `logs/beam_feedback_contracts_20260907_focused.log`:
  `testPDSCHTCIStateBinding`, `testPDSCHQCLStatePropagation`,
  `testPMIPrecodingRuntime`, and `testLLSULSRSRITPMIEstimator` passed.
  These establish isolated binding/precoding/estimator contracts, not delivered
  runtime CSI, live TCI activation, or complete scheduler beamforming.
- Earlier session 4860, exit 0,
  `logs/ul_clock_ra_tail_20260907_focused.log`, also passed access continuation,
  noisy broadcast/TRS stream and noise-domain checks on the clock/RA revision.
- Earlier session 92629 passed live-UCI cache authority, standalone retained
  channel state, actual staged PDSCH/PUSCH reception, measured PUCCH power
  control and canonical wideband SRS checks, but the combined batch failed
  later. Its overall result remains **failed**, not a successful batch.

Failure history remains available: session 16194 first exposed the SRS/channel
sample-rate mismatch; session 10588 exposed CSV header auto-detection in the new
test; session 92629 exposed a misplaced new assertion and two fading fixtures
without carrier-frequency context. The fixtures now supply explicit RF/carrier
identity, the assertion is in the PRI test, and the final rerun passes without
weakening production validation. Phase-05 artifact tests use explicitly
non-qualified temporary test artifacts; they are not new production CSV/PNGs.

The UL clock test uses actual prepared SRS, reciprocal CDL propagation and
thermal receiver noise, with an explicitly analytic pathloss fixture. Whole
and partitioned processing agree to the asserted tolerance on independent test
streams; failed preflight checks leave the tested stream unconsumed. The access
test uses all five coded TDD stages and an actual FIR delay tail, and checks
that even a complete retained buffer cannot be decoded before its sample end.
Neither fixture is a field calibration or a successful full scheduling run.

### Remaining work and acceptance order

1. Integrate one chronological physical-stream owner into the main scheduler.
   Compose each node's real TX contributions before PA/RF, advance each
   persistent physical link monotonically, and deliver actual receiver windows
   only after complete coverage. Current eager SSB/TRS/RA/control execution can
   still consume future samples before an earlier UL request; the original
   time-reversal guard must not be disabled, rewound or bypassed.
2. Bind PRACH, Msg3, PUCCH, PUSCH and SRS transmit/receive origins and processing
   deadlines on that clock. Nonzero UL timing advance remains explicitly
   unsupported by the prepared interfaces; separate UE TX and gNB observation
   origins are required, not waveform-head trimming and RX zero padding.
3. Qualify late HARQ-ACK creation against already queued PUSCH, PUCCH/PUSCH UCI
   arbitration, decoded DCI authority, K1/K2, CSI payload delivery, SRS-to-UL
   scheduling and HARQ/LA updates in the complete TDD run. Component codec and
   mapping checks are not a substitute for this causal test.
4. Qualify QCL/TCI activation and the actually applied receive beam/precoder.
   This TDD YAML currently sets `mimo.phase07_strict.require_active_tci_state`
   to `false`; isolated TCI validation passing does not prove that the run
   activates or consumes TCI. SRS `QCLAccuracy` remains a correlation diagnostic.
   Do not just enable a gate or label a correlation as standardized TCI state.
5. Export physical RSSI with its resource, bandwidth, symbol window, RX branch
   and reference plane. The physical CSI receiver already calls
   `nrCSIRSMeasurements` but retains only RSRP, discarding its per-antenna RSSI
   and RSRQ. Strict CSI sets RSSI unavailable; legacy DL/UL helpers sum RX
   branches in normalized grid units. Those legacy values must not be renamed
   dBm. Carry the actual measurement through resource selection, canonical CSV
   and source-bound PNG generation; test antenna count, AGC invariance,
   bandwidth/noise changes and RSSI/RSRQ closure.
6. Complete independent 12 dB operating-point calibration, then execute the
   short TDD-only diagnostic and audit every resulting primary CSV and PNG.
   Geometry/thermal noise mode does not make a configured `12 dB` label the
   measured SINR. Shared RF state and any finite-SIR Gaussian interference path
   still require review; this checkpoint does not certify all legacy paths.
7. Prepare traceable complete-channel IQ/playback for the specified Keysight
   instruments only after the LLS stream and measurements qualify.

RSSI reference: [MathWorks CSI-RS physical measurements](https://www.mathworks.com/help/5g/ref/nrcsirsmeasurements.html)
returns separate antenna/resource RSSI in dBm and RSRQ in dB; see also
[TS 38.215 sections 5.1.2 and 5.1.4](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf).
No RSSI export repair or RSSI plot is claimed in this checkpoint. No `testAll`
or new full qualification campaign was run under the earlier bounded-test
request. The NR-validation and result-integrity skills kept unavailable
measurements, unsupported timing and failed runs explicit instead of supplying
replacement values or successful-looking artifacts.

## Uplink control and scheduler job boundary checkpoint (2026-09-07)

The main chronological scheduler integration is **still incomplete**. Its last
full-run evidence remains the failed 25-slot-horizon run below, with zero DL
and UL data trial rows. No new TDD/FDD/25 dB scenario was launched here.

Repairs made in this checkpoint:

- Added retained, linearly power-allocated SRS and typed PUCCH transmit stages,
  before node PA/RF/channel execution. Receive stages consume complete actual
  observations without regenerating the transmitter, resetting the RNG,
  executing propagation or consuming power-control state a second time.
- Bound the control occasion, physical antenna dimensions, configuration,
  UCI/receiver context, sample rate and observation interval. Reject incomplete
  coverage, changed requests, proxy/fallback replay and mislabeled noise
  domains before decoding. Separate pre/post-front-end and physical transmitter
  observations remain required. Missing isolated noise samples do not become
  purported measured PUCCH input noise or EVM values. Absent PUCCH is rejected
  by this active-transmitter staging API; receive-only DTX monitoring must be
  integrated separately, not replaced by an active TX contribution.
- Removed SRS's synthetic-Doppler reference rescue. Missing noiseless reference
  samples leave true-channel NMSE unavailable and fail the existing strict gate.
- Corrected SRS NMSE to `mean(abs(Hest-Href).^2)/mean(abs(Href).^2)` in its
  retained pilot-reference domain. The previous fitted complex multiplier hid
  gain/phase errors; it was a shape residual, not absolute channel NMSE.
- This exposed a second SRS defect: the immediate runner compared a pre-AGC
  reference with a post-AGC estimate (wideband regression NMSE -2.6588 dB,
  despite reference correlation 0.9998). It now carries the gain recorded by
  the actual RX AGC into the reference plane. No gain is fitted from Hest,
  no RF/channel is rerun, and other receiver impairments remain in the residual.
  The source string identifies that reference convention; the applied gain is
  available as `NMSEReferenceAGCGain_dB` in the runner result.
- Removed the SRS branch that replaced rejected grid-domain noise variance with
  unconverted time-sample variance and cleared its failure flag. `SRS_Rx` owns
  the OFDM noise transform and strict validation.
- Routed preparation/completion options through `buildGrantPHYJob` and
  `executeGrantPHYJob`. Prepared jobs cannot commit receiver/LA/channel results
  and are not worker-safe; readiness after reception is not CRC/qualification
  success. The old immediate main batch explicitly rejects a prepared-only job
  instead of passing an empty trial into the normal commit path.

Ten focused checks passed on the final executable revision:

- Session 97036, exit 0, `logs/ul_control_stream_stages_20260907_final_focused.log`:
  `testUplinkControlStreamStages`, `testDataChannelStreamStages`,
  `testSRSRuntimeCanonicalWidebandResource`, `testPreparedWaveformPAOwnership`,
  `testPUCCHMeasuredReferencePowerControl`, `testNoiseDomainEvidenceContract`,
  plus a main-runner parsing check.
- Session 25037, exit 0, `logs/ul_control_scheduler_job_regressions_20260907.log`:
  `testSchedulerGrantConsistency`, `testSchedulerPDSCHTransmitAuthority`,
  `testULPUSCHThroughputExecutionContract`,
  `testDLPDSCHThroughputExecutionContract`.

No `testAll` or new E2E qualification campaign was run under the bounded-test
request. Existing FDD/TDD unit fixtures in the power-control checks are not
new production scenario launches. Historical outputs were not deleted or
regenerated. The NR-validation/result-integrity constraints kept missing
measurements and timing support as explicit failures, not replacement rows.

Failed diagnostics are preserved: session 23468 passed SRS then failed the new
PUCCH fixture's nonexistent `cfg.phy.rnti` field (corrected to the configured
PUSCH RNTI). Session 90530 passed both new stage tests and the data-job test,
then exposed the SRS AGC-reference mismatch. Session 99354 recorded that NMSE
failure and independently passed PA ownership, PUCCH power control and noise
domain checks. Session 86724 subsequently passed the six-check set after the
AGC-plane repair; session 97036 repeated it with the final absent-PUCCH guard.

The control tests use the TDD profile's full-UL slot, actual generated SRS and
HARQ-ACK PUCCH samples, physical antenna projection, an explicitly analytic
connector and standalone occupied-RE 12 dB AWGN. They test wrong noise planes,
incomplete coverage, configuration changes, proxies, missing SRS reference and
an intentionally wrong reference gain. These are bounded codec/measurement
tests, not measured access, production thermal-noise calibration, CSI report
transport, fading qualification, or full scheduler execution.

Still open, not skipped or claimed fixed: main node-composite chronological
execution; PRACH/Msg1-4 integration on that clock; nonzero UL timing advance
(the staging interfaces reject it explicitly); due PUCCH/PUSCH-UCI arbitration
and feedback delivery; measured SRS-to-UL scheduling and CSI/PMI report transport;
actual QCL/TCI activation and applied beam/precoder lineage; physical RSSI
measurement/export with bandwidth, antenna and reference-plane authority;
production 12 dB reference calibration; waveform IQ playback; and a fresh
complete CSV/PNG semantic audit. The legacy SRS `QCLAccuracy` scalar remains a
waveform-reference correlation diagnostic, not proof of standardized QCL/TCI
state activation. Strict CSI still does not publish RSSI; its legacy helper
sums RX branches in normalized grid units. Neither is a qualified RSSI export.

Noise-plane rationale: [MathWorks NR SNR definition](https://www.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html).
RSSI must include total received power over its specified measurement resources,
not a substituted RSRP or sum of unlabeled antenna branches; see
[TS 38.215](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf).

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
