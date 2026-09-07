# Short TDD run: measured failures and remaining integration work

## Retained RF and main UL slot-entry checkpoint (2026-09-07)

**The production shared-clock failure is not fully repaired.** This checkpoint
does not assert a successful 12 dB run, fully qualified UL, device conformance,
or a 10/10 simulator. The failed production outputs remain unchanged. No FDD,
25 dB or new production TDD waveform run was launched.

Implemented in the main scheduler:

- Slot entry now receives the queued UL grants and reconciles them with all
  currently pending HARQ/CSI before standalone PUCCH processing. Previously,
  `startSlot` could execute PUCCH before the caller inspected queued PUSCH;
  the earlier post-PDSCH reconciliation did not protect reservations arriving
  from another reducer between that boundary and slot entry. The new
  `startSlotWithQueuedUL` uses the existing typed UCI/overlap resolver, not a
  second payload implementation. Disabled UCI multiplexing retains the
  collision rejection. This fixes that **ordering boundary only**; PUCCH
  propagation itself is still eager, not integrated into the shared stream.
- The HARQ/UCI reducer regression had another stale `HARQEntityDL.onTx`
  fixture without a coding layout. It now supplies a 64-bit TBS and real
  resolved LDPC/rate-matching layout. Its deliberately known test payload
  remains a test fixture, not a measured production transmission. No HARQ
  validation was weakened.

Implemented in the RF producer and retained-stream API:

- `RFImpairmentStream` retains one endpoint's ordered RF state, sample clock,
  configuration epoch and physical antenna layout. It uses the existing
  ordered RF implementation: absolute-index CFO, retained integer delay,
  explicit-mask oscillator state, supported PA memory, causal sample-window
  AGC and persistent ADC dither/jitter state. Invalid clocks/epochs are rejected
  before processing; an execution exception permanently faults the owner.
- AGC decisions use completed prior detector windows. Replay retains the
  actual per-sample applied gain; a time-varying gain is not misrepresented
  as one scalar. Legacy same-block RMS AGC is explicitly labeled noncausal.
  Both replay and RF CSV rows disclose the processing mode and AGC causality.
  The common receiver can accept this retained owner, but **the main runtime
  has not yet been switched to retained RF**. Separate physical pre-RF power
  measurements and correct post-gain noise accounting remain required.
- RX processing now rejects missing sample rate and invalid direction instead
  of bypassing RF or silently selecting DL. An enabled ADC with invalid or
  unsupported bit depth now fails instead of becoming disabled. Zero-valued
  startup intervals retain complex I/Q at the ADC boundary, preventing an
  accidental ADC state-domain change when nonzero samples arrive.
- Physical stream samples are not projected through logical antenna ports
  again inside element RF. Gain/phase vectors must be finite and either scalar
  or exactly match the element count; no dropping NaNs, truncation, or repeated
  last-element values. The legacy logical-port interface remains distinct.
- Fixed the one-order/multiple-memory-tap PA matrix orientation. Also fixed
  canonical PA input backoff: it now attenuates the drive **before** the
  nonlinear function, not its compressed output. Analytic tests distinguish
  those operations. Retained PA memory contains the backed-off input history;
  no output-power restoration is applied. This is model correctness, not
  calibration against a measured hardware PA. See the
  [MathWorks memory-PA model documentation](https://www.mathworks.com/help/simrf/ref/poweramplifier.html)
  for the measured-coefficient modeling context.
- Added explicit AGC implementation coefficients through a reusable TDD YAML
  catalog and equivalent self-contained FDD configuration. These are labeled
  implementation/research choices, not 3GPP-mandated AGC coefficients. Merely
  declaring them does not enable an impairment or select a new execution mode.

Verified terminal batches:

| Batch / diary | Result and scope |
| --- | --- |
| 43436; `logs/causal_rf_stream_20260907_verified.log` | Exit 0: RF stream, causal AGC, ordered RF and common-RX ordering tests. |
| 45845; `logs/rf_slot_entry_uci_20260907_verified.log` | Exit 0: RF memory/phase, RF stream, HARQ-on-PUSCH reducer and CSI source/binding tests, including the main slot-entry method. |
| 95293; `logs/rf_retained_final_20260907_verified.log` | Exit 0: final PA-backoff/element-vector changes; five focused RF tests and all 17 `testRFCanonicalRuntimeCoverage` cases. |
| 22885; `logs/slot_entry_ul_tdd_20260907_verified.log` | Exit 0: all 12 focused RF/config-parity, HARQ/CSI slot-entry, future-UL planning, SRS priority, actual staged UL/data, RAR conversion, TDD four-step RA, frozen SRS/PUSCH and QCL/TCI binding checks. |
| 57533; `logs/rf_export_mode_20260907_verified.log` | Exit 0: actual RF execution CSV round-trip retains legacy/causal mode labels; receiver evidence integrity and ordered RF regressions passed. |
| 77998; `logs/rf_adc_range_final_20260907_verified.log` | Exit 0: RF stream/config-parity/export checks repeated with ADC constructor rejection aligned to the canonical 2--24-bit quantizer support. |

The actual four-step TDD test measured decoded RAR **TA = 0**, at 7.68 MHz,
and passed the CDL-A Msg3 CRC check without a duplicate timing correction.
This does not qualify nonzero-TA continuous UL transmission. FDD parity above
is configuration/reducer coverage, not a FDD waveform execution.

Earlier failures are retained: the first ADC test exposed loss of complex
storage after an all-zero delay interval; the next negative test used the
wrong SCO configuration key. An oscillator test mask could not meet the
existing 1 dB fit bound. A supported explicit mask is used for positive state
retention tests, and the rejected mask remains a **negative** test requiring
the original failure and faulted owner. The fit tolerance was not relaxed.
An element-vector negative test exposed the legacy truncation behavior and
now requires the production dimension error. Test diaries may contain prior
failed entries because MATLAB diary appends; terminal batches above identify
the completed checks.

Remaining work, not skipped or claimed complete:

1. One chronological main owner for access, TRS, PDCCH, SRS, PUCCH and data,
   with each physical TX summed before RF, each link consumed once, and RX
   noise/RF applied once after summing links. The present main scheduler
   still eagerly propagates entire observation windows; slot-entry UCI
   reconciliation does not repair that shared-channel time reversal.
2. Complete UE received-DL, UE-TX and gNB-RX clock relations, nonzero RAR TA,
   `N_TA,offset`, fractional timing/SCO bridges and actual received tails.
   Prepared UL stages still reject unsupported nonzero TA. Retained RF
   rejects advancing/fractional finite-buffer timing, SCO and enabled DAC
   rather than silently substituting an unsupported implementation.
3. Fully qualify UCI processing deadlines and SRS/PUCCH symbol arbitration
   through actual complete UL execution. Reducer fixtures are not waveform
   decode evidence. The existing actual coded UL component tests have a
   separate, explicitly limited scope.
4. QCL/TCI activation and CSI PMI/RI use through the completed main stream;
   component binding tests do not establish complete run behavior.
5. SS- and UL-specific RSSI measurement definitions, physical reference planes
   and CSV/PNG publication. Earlier CSI-RS RSSI/RSRQ producer work does not
   establish RSSI coverage for every signal. No generic sample power is being
   relabeled as a standardized RSSI measurement.
6. Calibrate the requested 12 dB operating point from actual physical power/
   noise, run the short TDD scenario, then audit actual CSV/PNG artifacts and
   prepare traceable hardware I/Q. No replacement plots or measurement rows
   were fabricated during this checkpoint.

The config-driven, NR-validation, result-integrity and MATLAB-kernel skills
guided explicit authorities, analytic comparisons and narrowed evidence
claims. Broad repository regression qualification remains outstanding; the
earlier user request for bounded testing was retained instead of `testAll`.

## Chronological coordinator and physical CSI-RSSI checkpoint (2026-09-07)

**The main scheduler's shared-clock/shared-stream integration is still open.**
No new production TDD, FDD or 25 dB simulation was launched. The failed
`tdd_12db_verify_20260907_0018` run and its failure evidence were not rewritten.
This checkpoint adds verified infrastructure and repairs measurement/report
producers; it does not establish a completed or production-qualified 12 dB run.

Implemented:

- `WaveformEventRuntime` composes each physical transmitter, invokes one
  retained processing callback per consumed interval, and dispatches its
  actual samples to registered receiver planes. Consumption stops at the
  earliest receiver completion or scheduler decision boundary. Every
  transmitter must explicitly commit all contributors (or intentional
  silence) through that interval; unknown future scheduling cannot silently
  become zero-valued TX samples. Past/committed contributions cannot change.
  Missing RX planes, interval mismatches, nonfinite samples and contradictory
  proxy/fallback evidence fail. A processing exception permanently faults the
  instance: no automatic replay, channel clone or RX-padding rescue occurs.
  Physical fading, RF, noise, power and duplex policy remain the callback
  owner's responsibility; the coordinator does not invent those policies.
- The actual noisy-CDL broadcast/TRS/PDCCH diagnostic now uses this coordinator.
  It decodes each complete observation before consuming later samples. SSB/
  SIB1 at 0--5 ms, PDCCH at 12--13 ms and the TRS capture at 12--18 ms complete
  without time reversal. Chunked samples match an independent whole-stream
  test reference within relative `1e-12`; the receiver-noise state also agrees.
  The independent channel clone exists only for that test comparison, never
  to replay a failed production interval. This is a **pre-RF DL diagnostic**,
  not the complete main scheduler or a shared UL/nonzero-TA execution.
- PDSCH's physical CSI measurement now retains the actual per-resource,
  per-receive-antenna RSSI and RSRQ returned alongside RSRP. It no longer
  filters finite branch values into a vector that loses branch identity.
  A configuration bundle cannot silently flatten multiple resources into
  one antenna vector. The scalar RSSI/RSRQ comes from the same selected
  resource and strongest-RSRP branch, not independent maxima. A selected
  unmeasured resource cannot inherit another resource's measured power.
  CSI CSV rows retain branch vectors, resource JSON, bandwidth, PRB origin,
  SCS, symbol window, selection and existing physical-plane/source metadata.
  [Toolbox measurement definition](https://www.mathworks.com/help/5g/ref/nrcsirsmeasurements.html)
  references TS 38.215; RSSI is not legacy normalized CSI grid power.
- Registered CSI-RS RSSI and RSRQ timeline producers in the existing CSV/PNG
  output contract. They retain every measured resource/branch and check
  same-branch `RSRQ = 10*log10(N_RB) + RSRP - RSSI`, bandwidth and source
  identity. Missing evidence yields an explicit unavailable result, not a
  fabricated measurement plot. PNG rasterization was tested with declared
  schema fixtures; **new production-run PNG publication remains unverified**.
- Repaired a pre-existing browser source alias that labeled a serving-cell
  topology map as a sector coverage footprint. A footprint now requires its
  own source. The browser regression also lacked the publication manifest
  required by the current acceptance gate; its legacy-layout unit fixture
  now supplies that authority, rejects the manifest-free case, and cannot
  invent numeric charts for artifacts excluded by the production selector.

Verification:

| Terminal batch | Result and scope |
| --- | --- |
| 9235; `logs/waveform_event_runtime_20260907_focused.log` | Exit 0: `testWaveformEventRuntime`, `testWaveformStreamComposition`, `testWaveformReceiveDispatcher`, `testBroadcastTRSNoisyStream(13,true)`. |
| 21882; `logs/waveform_event_proxy_guard_20260907_verified.log` | Exit 0: coordinator regression repeated after extending rejection to approximation source labels and prefixed flags such as `FallbackUsedForPathloss`. |
| 3399; `logs/csi_rssi_physical_20260907_verified.log` | Exit 0: `testCSIRSPhysicalResourceMeasurements`, `testCSIRSRPPhysicalMeasurement`, `testCSIRSMultiResourceYAMLAuthority`, `testCSIRSPhysicalRuntimePortProjection`. Includes real DL receiver/AGC checks, CSI CSV round-trip, 15/30/60 kHz analytic measurement tests and physical-port projection tests. |
| 47392; `logs/event_rssi_ul_control_20260907_verified.log` | Exit 0: `testUplinkControlStreamStages`, `testDataChannelStreamStages`, `testRARTimingAdvanceAuthority`, `testTDDCausalFourStepRARuntimeTiming`, `testSRSPUSCHRuntimePriority`, `testPUSCHCausalSRSFrozenGrant`, `testPDSCHQCLStatePropagation`, `testPDSCHTCIStateBinding`. |
| Python | 69 pytest cases passed in `test_lls_radio_measurement_plots.py` and `test_lls_contract_materialization.py`; `python tests/test_lls_browser_plot_browser.py` passed separately. |

The first RSSI batch (14661) failed on a newly written unit fixture's illegal
CSI-RS period of 2 slots. It was corrected to a legal 4-slot period before the
same four-test batch passed; production CSI configuration validation was not
weakened. The browser failure was reproduced against the prior Python code
before correcting the source alias and test publication inputs.

The actual TDD RA test again measured **RAR TA = 0** at 7.68 MHz and decoded
Msg3 successfully. Nonzero TA is covered only by conversion/codec tests,
not a complete shared-stream UL waveform. PUSCH HARQ-ACK and standalone
PUCCH payloads are actual codec executions with explicitly known unit
payloads; these are not fabricated main-run feedback results. QCL/TCI tests
prove their local propagation/binding contracts, not runtime activation in
the failed production profile. The physical-power test's coupled AWGN case
measured CSI-RSRP -74.66894 dBm versus power-closure expectation -74.68345 dBm;
this is a separate calibration test, not the requested 12 dB operating point.

No `testAll`, full campaign, production PNG regeneration, hardware IQ export
or FDD waveform run was performed. The earlier bounded-testing request was
retained; the repository's complete regression qualification is outstanding.
The config-driven, NR-validation and result-integrity skills guided the
explicit configuration/clock authorities, fail-closed checks and limited
evidence claims.

Next required work (still open, not silently skipped):

1. Integrate the coordinator into the **main** access/TRS/SRS/control/data
   scheduler, replacing eager whole-window propagation rather than merely
   delaying delivery of already computed future results.
2. Give physical node TX/RX RF processing retained streaming state, apply it
   once to summed node samples, and preserve separate pre-/post-RF planes.
   Several legacy RF timing/SCO/AGC paths remain per-call/block-based.
3. Complete shared UL timing with received-DL/UE-TX/gNB-RX origins,
   `N_TA,offset`, nonzero TA and actual received tails. Prepared UL stages
   still reject unsupported nonzero TA instead of trimming/padding samples.
4. Qualify all runtime UCI feedback deadlines and same-UE SRS/PUCCH symbol
   arbitration; qualify QCL/TCI activation and measured CSI PMI/RI consumption
   through the complete scheduler, not only isolated calls.
5. Calibrate the requested 12 dB operating point against actual physical
   signal/noise measurements, then execute the short TDD run and audit its
   actual CSV/PNG values and publication manifests. SS-/UL-specific RSSI
   coverage is not established by the CSI-RS addition above.

## Executed HARQ and decoded RAR timing checkpoint (2026-09-07)

The main scheduler shared-clock/shared-stream repair is **not complete**.
No production TDD/FDD/25 dB simulation was launched in this checkpoint.
The failed `tdd_12db_verify_20260907_0018` run and its CSV/PNG evidence remain
unchanged. Passing the component checks below is not full-run qualification.

Two further production defects were repaired:

1. `CoupledTruthRuntime.updateHARQState` fabricated an all-zero transport
   block from a trial's reported size when the actual transmitted payload
   was absent. It also reconstructed missing UL executed grants from current
   configuration and overwrote contradictory size aliases before checking.
   `validateExecutedHARQPayload` now requires the retained actual payload and
   executed grant for both directions. It checks binary values before casts,
   byte alignment, trial/grant/frozen coding sizes, retained context aliases
   and decoded payload availability. Rejection happens before HARQ handle
   allocation/mutation. Actual zero-valued transmitted blocks remain valid;
   a CRC pass does not replace differing decoder bits with transmitter bits.
   The completion entry point also rejects a future resource-planning view.
2. PRACH-to-RAR TA used `round(delaySamples/16)` independent of sampling
   rate/numerology, while Msg3 used the unquantized detector sample count
   rather than the actually decoded RAR. The absolute RAR relation is
   `N_TA = T_A * 1024 / 2^mu` in Tc units, with the first scheduled UL's SCS;
   this is distinct from a relative MAC-CE adjustment. The conversion now
   uses the existing numerology and absolute-time authorities. Nearest-step
   selection is explicitly the gNB quantization policy, not an invented
   standard requirement. Out-of-range commands and unrepresentable fractional
   shifts are rejected rather than silently clipped or rounded. See
   [TS 38.213 v18.8.0 section 4.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

   Msg3 and RRCSetupComplete now apply the command recovered from MAC RAR
   bytes, converting its time to each actual UL waveform's sample rate.
   A gNB proposed command is separately labeled and is not exposed as a
   received UE command before successful RAR reception. Native RA/Msg3 CSV
   rows and the main canonical adapter retain command, Tc ticks, sample rate,
   source and quantization residual. The canonical microsecond value comes
   from Tc, not a guessed PRACH/PUSCH sample-rate equivalence.

Verification (eleven distinct focused tests across four terminal batches):

- Session 22625, exit 0, `logs/executed_harq_authority_20260907_focused.log`:
  `testExecutedHARQPayloadAuthority`, `testDataChannelStreamStages`,
  `testHARQTBContextInvariants`, `testFutureULPlanningCausality`,
  `testSchedulerGrantConsistency`.
- Session 59865, exit 0, `logs/executed_harq_ul_components_20260907_verified.log`:
  `testExecutedHARQPayloadAuthority`, `testUplinkControlStreamStages`,
  `testTDDCausalFourStepRARuntimeTiming`, `testLLSULSRSRITPMIEstimator`.
  This batch preceded discovery of the RAR conversion defect; its timing
  pass alone did not demonstrate the correct command conversion.
- Session 64308, exit 0, `logs/rar_timing_authority_20260907_focused.log`:
  `testRARTimingAdvanceAuthority`, `testMsg1PRACHWaveformDetection`,
  `testTDDCausalFourStepRARuntimeTiming`, `testLLSULSRSRITPMIEstimator`.
- Session 34593, exit 0, `logs/rar_timing_harq_exports_20260907_verified.log`:
  `testExecutedHARQPayloadAuthority`, `testRARTimingAdvanceAuthority`,
  `testFourStepRAResultAdapterDependencies`,
  `testTDDCausalFourStepRARuntimeTiming`, including an actual receiver-derived
  Msg3 timing table CSV write/read round-trip.

The data-stage test actually executes coded PDSCH/PUSCH and HARQ-ACK on
PUSCH, with retained TX and contiguous RX samples. SRS and standalone PUCCH
tests use actual generation/reception at an explicitly isolated 12 dB AWGN
operating point. Their connector and access/UCI inputs are declared unit
fixtures, not field measurements or a completed scheduler run. The strict
DL channel/RF qualification gate remains failed where the reference is absent.
The SRS RI/TPMI test uses constructed channel matrices and is not over-air CSI
feedback qualification; missing Toolbox support now raises rather than passes.

The TDD RA test uses the configured CDL-A physical link and completes all
five access/RRC waveform stages. It also poisons stale diagnostic TA sample
caches before Msg3 preparation to prove consumption of decoded RAR authority.
**Its measured RAR TA was zero** (0 Tc, 0 samples at 7.68 MHz). Nonzero
quantization was checked analytically across seven catalog numerologies and
four sample rates, and with real MAC RAR encoding/decoding, not a nonzero-TA
shared-stream fading run. There was no FDD waveform run, `testAll`, full
campaign, production PNG generation or instrument export in this checkpoint.

Remaining requested work, not skipped or claimed complete:

| Area | Remaining integration/qualification |
| --- | --- |
| Main shared clock | Replace eager complete SSB/TRS/SRS/control/data propagation with one chronological owner; current code still advances beyond pending RA windows. |
| Shared UL timing | Distinct received-DL/UE-TX/gNB-RX origins, configured N_TA,offset, nonzero TA and exact sample coverage. The existing finite-window RA shift is not the shared-stream solution; prepared SRS/PUCCH/PUSCH still reject nonzero TA. |
| UCI/control | Actual component PUCCH and PUSCH UCI decoding passed; full-run grant/reservation/decode/feedback ordering and all configured formats remain to qualify. |
| SRS overlap | Same-UE same-carrier symbol-based SRS/PUCCH rules and partial SRS-symbol suppression, including the aperiodic exception, remain open. |
| QCL/TCI/PMI | Runtime activation, availability, selected resource/precoder use and source-bound CSV/PNG need full-run evidence; the current profile does not require an active TCI state. |
| RSSI | The physical CSI measurement call returns per-antenna RSSI/RSRQ, but PDSCH_Rx retains only RSRP from it. Retain resource/branch/window/bandwidth/power-plane evidence and wire CSV/PNG; never relabel normalized legacy dB as dBm. |
| Operating point/artifacts | Calibrate and distinguish the 12 dB request from geometry/thermal measured SINR; rerun the complete TDD chain and audit every actual CSV/PNG after integration. |

The NR-validation and result-integrity skills governed the fail-closed
checks, units, source labels and these limited verification claims. No
primary table was filled with replacement measurements or payloads.

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
