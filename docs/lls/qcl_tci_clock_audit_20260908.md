# Open control-clock and beam-lineage audit

This records unqualified work, not a conformance certificate. The active
nominal-12-dB TDD `_04` run is the current integration experiment. Do not
modify its production dependencies before MATLAB terminates.

## Observed implementation issues

| Surface | Current evidence | Required verification/repair |
|---|---|---|
| Main PDCCH candidate context | Received AL/CCE coherence and frame-relative mapping repaired; 480 independent resource mappings passed. `_04` has not reached first connected DCI yet. | Inspect actual decoded candidate, received CCE, grant binding and HARQ resource selection in `_04`. |
| Strict `PDCCHTransmitter.transmit` | `AbsoluteSlot` is passed to CCE enumeration; waveform construction receives the original `strictCfg.ToolboxCarrier`. | Advance the actual carrier from the canonical control clock and reconcile DM-RS, RE indices and CCE metadata. New `testStrictPDCCHTransmitSlotAuthority` is prepared but not run. |
| Strict `PDCCHReceiver.receive` | Candidate enumeration consumes `AbsoluteSlot`, but decoding uses the original toolbox carrier. | Test reception at nonzero slots and across frame boundaries using an independently generated waveform. Do not validate TX and RX only against the same faulty clock. |
| Strict prepared receiver | `prepare` caches carrier/candidate resources at the preparation clock; `receivePrepared` accepts a later `AbsoluteSlot` without visibly rebinding them. | Treat cached configuration separately from slot-dependent resources; test reuse across slots. |
| Strict DCI event beam lineage | `PDCCHReceiver.localEventData` sets `BeamID=context.ActiveTCIStateID` and `QCLSourceID=context.CORESETID`. | Resolve real TCI-to-reference-signal/spatial-filter associations. Equal integer identifiers are not evidence of equal concepts. Preserve unavailable lineage until established. |
| Main QCL/TCI | Main active-TCI qualification gate is disabled; this does not itself prove a PHY violation or valid default QCL. | Trace the configured TCI-field presence, decoded higher-layer state, activation timing, monitored CORESET and actual selected spatial filter. Verify the applicable default case explicitly. |
| Main uplink feedback | Received Msg3/RRCSetupComplete and SRS were observed in `_03`; no connected data committed before its failure. | Verify `_04` PRACH/PUCCH/PUSCH/SRS, UCI placement, TA, K1/K2 and decoder-completion-to-scheduler delivery. |
| RSSI | Actual four-symbol, 240-subcarrier SSB-window power is exported per RX branch. `_04` snapshot hashes and component lineage pass. | Do not relabel it as complete carrier/SMTC RSSI; a full configured measurement-window implementation remains a separate requirement. |

## Normative QCL decision boundaries

Source: [ETSI TS 138 214 V18.5.0, clause 5.1.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.05.00_60/ts_138214v180500p.pdf), pages 50–53.

TCI handling depends on higher-layer configuration, DCI field presence,
activation history and the PDCCH-to-PDSCH offset. Before activation, an
initial-access SS/PBCH assumption can apply under specified conditions.
Without a TCI field, a sufficiently separated PDSCH can inherit the
scheduling CORESET's QCL assumption. A shorter offset can invoke the
lowest-ID monitored CORESET rule when Type-D is configured. Unified-TCI,
cross-carrier and multi-TCI configurations have additional rules.

Therefore neither blindly requiring an activation MAC CE for every first
PDSCH nor filling a beam column from a TCI integer is a valid generic fix.
The actual applicable state transition and reference signal must be retained
in CSV lineage and used by the physical receive/transmit spatial filters.

## Acceptance sequence

1. Finish the current main experiment and preserve all failure evidence.
2. Regress each identified clock defect independently, then repair producers.
3. Reconcile actual main-run received control, grants, data and feedback.
4. Implement/test applicable QCL/TCI state transitions and PMI associations.
5. Audit every enabled output against measured inputs and declared scope.
6. Only then qualify higher-rank/25-dB and longer impairment campaigns.

Focused passing tests do not replace the outstanding full-suite and
full-feature qualification. No proxy, fallback or invented success row is
permitted to close any item above.

## `_04` progress and newly exposed defects, 17:54 UTC

The main run passed the previous slot-31 CCE binding failure. Actual received
DL DCI authorized slots 31–33, three PDSCH rows committed with CRC success,
and received UL DCI in slot 34 authorized the first PUSCH in slot 35. The
first PUSCH passed CRC with measured SINR 11.0811002152035 dB and MCS 1
(explicit conservative bootstrap, not yet proof of adapted MCS). Its UCI
payload was empty: this observation does **not** qualify UCI-on-PUSCH.

Slot-34 PUCCH format 2 carried 10 received UCI bits, HARQ-ACK plus CSI.
Expected and decoded vectors both equal `1110111111`; the content match
passed. A zero-length UCI CRC is reported as not applicable, not passed.
SRS slot 30 now exports the actual 84-sample estimate and applied correction,
with `TimingEstimateUsed=1`, `UseIdealTimingSync=0`. Slot-35 SRS also decoded.

Two additional timing-report defects require producer fixes after this run:

- The PUCCH row carries measured/applied timing of 84 samples but
  `TimingEstimateUsed=0`. `runPUCCHWaveformTrial` copies the actual timing
  fields without the application flag; the runtime writer defaults it to
  false. Do not infer the flag in the GUI.
- PUSCH labels the injected impairment offset (zero) as true total receive
  timing, then subtracts an 84-sample capture-relative extraction offset to
  publish a residual of -84. These are different clock origins. Preserve
  actual receiver extraction evidence, but require a same-origin independent
  timing reference before publishing a physical timing error. The DL
  `localFinalizeImpairmentReplay` has analogous arithmetic and needs the same
  investigation; do not special-case TDD or UL.

The first PDSCH measured 50.128398863745 dB. The nominal-12-dB label is not
the actual SINR setpoint in this inherited thermal-noise scenario. This
run must not be advertised as measured 12-dB link-performance qualification.

## Reporting regression queue

The exhaustive retained `_03` audit covered 617 CSVs / 238,992 rows and 124
PNGs, including first-five-row previews of every CSV. It found 62 required
failed checks across 43 files, not 62 independent physical defects. Most
missing-observation failures follow the terminal slot-31 failure. Image
decoding passed; unavailable measurements still prevent qualification.

Independent new tests are prepared, **not executed while `_04` is live**:

- `testLLSDerivedBeamExecutionIdentity`: bind the same raw in-memory lifecycle
  as primary CSVs before derived P1 summaries; reject conflicting identity.
- `testDUTReferenceUnavailableIdentity`: preserve string run/block identity
  and failure reasons when there are no measured reference comparisons.
  Inspect empty-struct-to-table typing before assuming CSV pruning is the
  source of the observed NaN identity and zero-count summaries.
- `testStrictPDCCHTransmitSlotAuthority`: verify actual slot-dependent
  waveform DM-RS/resources independently, including frame boundaries.

The two headerless unavailable artifacts (`live_link_adaptation_input_table`
and `live_waveform_preview`) also need typed empty schemas or explicit
non-publication. No dummy rows may be added.

## `_04` terminal PHY failure — 18:04:29 UTC

Main execution failed in slot 42 with
`sixgr:phy:pucch:PathlossReferenceSignalMeasurementMissing`, after six DL
and two UL rows had committed. MATLAB session 53326 is still finalizing
failure artifacts as of 18:10 UTC; do not patch its dependencies yet.

The selected power-control reference is SSB resource 0, with a configured
maximum age of 20 slots. The actual measurement ledger has bursts produced
at slots 1 and 21, delivered at 6 and 26, respectively. The slot-41 burst is
queued, but the full five-subframe broadcast completion has not yet made
its measurement available when slot 42 consumes pathloss. The previous
measurement is then 21 slots old and correctly fails the freshness guard.
This is not absence of periodic SSB transmission, and is not fixed by
copying the configured 77-dB calibration pathloss into runtime evidence.

Trace: `applyUserContextImpl` clears old runtime pathloss and consumes the
configured reference through `consumeReferenceSignalPathlossImpl` /
`causalMeasurementState`; `PUCCHConfigBuilder.localPower` rejects the now
unavailable measurement. Periodic tracking currently calls the complete
SSB/MIB/SIB1 receiver through the full broadcast observation. Investigate
an actual per-SSB measurement completion for connected tracking, separate
from full-burst beam selection and SIB1 acquisition. A configured SSB-0
power reference can be measured before the entire beam set is received;
best-beam selection must still wait for its configured candidate evidence.
Do not shorten the observation by filling unavailable samples or backdate
measurements, and do not extend freshness merely to make this run pass.
Also inspect control-resource planning versus power-state binding at actual
transmission; configuration construction must not imply a measured future
power state.

UL slot 40 confirms MCS 6 (from bootstrap 1), inner loop and OLLA applied,
one OLLA update, and CRC pass at 10.8634256313349 dB measured SINR. UCI-on-
PUSCH was still not exercised: both observed PUSCH payloads have zero UCI.

New independent `tools/audit_lls_uplink_evidence.py` checks observed UCI
binary vectors, count/XOR/content closure, CRC applicability and measured
timing application flags. Seven Python regression cases pass, including
legitimate failed decodes (not converted into audit success rows) and
leading-zero corruption. The retained `_04_uplink_observed_01.json` receipt
contains two failures, precisely the slot-34/39 PUCCH timing flags. The
actual corrections are 84 and 85 samples. `testSharedPUCCHFeedbackClock`
now checks the flag for current DM-RS timing and separately protects the
pilot-free format-0 prior-measurement prediction (no invented current
timing estimate). This MATLAB extension has not yet run.

Snapshot 737d4908fa064d0b4f30566ed352fd409823b3d22b381e9e6f79a1c7a892d22c
contains 17 live measured PNGs and 45 hash-bound artifacts; all hashes
verified. The unchanged component-lineage audit checked 163 retained
component images with zero failures. This is source linkage, not complete
physical or terminal qualification. Windows extended-length paths are
required for these deep snapshot paths; a plain Path read can incorrectly
report a present file as missing.

The `_03` reference-summary JSON also contains null BlockId and zero
comparison counts. Therefore that defect exists before CSV serialization;
do not try to repair it solely by changing CSV column pruning.

### Finalization monitor, 18:19 UTC

Session 53326 remains live (worker 2896, increasing CPU use). The artifact
journal confirmed new commits through 18:18:33 and the coverage exporter
reported `done`; the MATLAB process has not exited. This is a verified
finalization wait, not permission to start a second batch or modify loaded
production files. No producer edits or MATLAB tests were performed during
this wait. The next serial batch should reproduce the prepared clock,
beam-identity, unavailable-reference and PUCCH-timing tests before repair.

Visually inspected the actual latest-checkpoint `pusch_evm_per_symbol.png`
and `reported_versus_applied_pmi.png`: both distinguish component identities
and carry partial-checkpoint/nonqualification labels. The EVM chart uses
6204 paired samples and displays separate RMS/peak series for UL slots
35 and 40. The PMI chart retains requested/applied/reported roles rather
than inventing a sweep. Visual inspection is not a conformance certificate.

### Additional source audit, 18:30 UTC

The emitted `frame_grid/csv/observed_re_allocation.csv` contains TRS,
PRACH, SRS, PDCCH, PDSCH, CSI-RS, PUCCH and PUSCH, but no SSB rows,
despite eight actual PBCH measurement rows from two received bursts.
Repair the broadcast producer's occupancy publication using actual emitted
resources and sample extents. Do not reconstruct it from a GUI schedule.
Whether periodic broadcast and connected PDSCH overlap on the same REs is
still an open audit question, not a proven collision from this table alone.

All three supplied SNR/channel/RF documents have been reviewed (the first
two have the same substantive body). They are proposals, not authority to
silently change this active diagnostic. They distinguish calibrated fixed
SNR experiments from physical link-budget experiments. Their example RF
parameters differ; neither example is a universal 3GPP requirement. The
current physical-mode execution has DL measured SINR near 45–50 dB and UL
near 11 dB; its nominal 12-dB metadata must not be presented as a calibrated
receiver setpoint. `resolveWaveformOperatingPointMetadata` currently
requires a finite label even in physical mode. A future schema correction
must preserve operating-point identity without implying a controlling SNR.
No per-slot fading normalization or replacement of receiver measurements is
an acceptable repair.

Worker 2896/session 53326 is still alive. New reporting view CSVs committed
at 18:30 UTC, so finalization is progressing. Production files remain
frozen and no second MATLAB batch has been launched.

The strict blind receiver has the same separate slot-authority defect as
its transmitter: `receive` keeps the configured carrier clock, and
`receivePrepared` reuses both the carrier and candidate list prepared for
slot zero. Added `testStrictPDCCHReceiveSlotAuthority` with independently
scheduled actual PDCCH waveforms, both receiver APIs, and frame-boundary
cases. It is prepared but not yet executed. This must not be confused with
the already-tested main shared receiver's CCE binding repair.

Finalization subsequently produced 133 files in `reports/image`. MATLAB
was waiting on its actual child `materialize_lls_contract_artifacts.py`
process (worker 8044), which consumed CPU; that child then exited and
MATLAB CPU increased again. Session 53326 still has not returned a terminal
exit. The new terminal images have not yet had the exhaustive terminal
audit; counts alone do not establish completeness or correctness.

### Exception-stack and SINR-source follow-up

The saved `meta/failure_debug_report.txt` confirms the fatal path exactly:
`completeSlotImpl -> updateHARQState -> resolvePUCCHResourceAssignment ->
PUCCHConfigBuilder.connectedHARQ -> localPower`. It occurs after an actual
DL reception while selecting a future HARQ feedback resource, not at
actual PUCCH transmission. Separate the pure resource/timing plan from
the immutable transmit assignment with its current measured power state.
Keep the latter's strict missing-reference rejection. The periodic SSB
delivery gap still needs repair for the later physical transmission.

The six DL `MeasuredSINR_dB` values are specifically receiver estimates
bounded by decision-directed equalized-symbol residuals, with source
`canonical_decision_directed_post_equalization_residual_bounded_equalizer_sinr`.
They numerically equal the separately labeled EVM diagnostic in this
high-success checkpoint. Source inspection shows nearest-constellation
decisions, not transmitted data supplied to that estimator; equality is
not proof of a substituted oracle. These estimates are nevertheless not
an independently measured antenna-input SINR or proof of a calibrated
12-dB operating point. Low-SINR decision bias and residual-bound validity
require explicit validation. UL uses a different effective-channel
post-equalization estimate. Preserve those source/domain distinctions.

Current DL/UL QCL fields explicitly state that QCL/TCI binding evidence is
not measured. Requested/applied precoder hashes do match on these rows,
but that alone does not prove a signalled, effective-time-correct QCL/TCI
chain. SRS oracle availability is marked separately from proxy execution;
the presence of a scoring reference is not proof of oracle receiver use.

## Terminal audit and first repair batch, 2026-09-09 IST

Session 53326 returned **exit 1** after 18:41:24 UTC on September 8.
The original PUCCH pathloss error remains the fatal PHY cause. Recovery
also failed with `sixgr:artifact:TerminalBrowserClosureFailed` after three
passes (`materialization=0 visual=1 lineage=1`). The retained receipt names
one missing geometry table and 29 missing chart entries. Repeated browser
closure passes explain the repeated Python child executions; these were
not restarted PHY simulations.

The read-only exhaustive audit completed with exit 1 at
`results/lls/qualification_working/short12_connected_feedback_20260908_04_full_audit`:
902 CSVs, 668284 rows, first five rows retained for each CSV, 277 PNGs,
zero CSV parse/image decode failures, 24 required semantic check failures
across 11 files, and 21 CSVs without domain contracts. Token counts such as
`proxy` or `NaN` are not independently proof of fabricated measurements.
The full semantic CSV identifies the failing rows/contracts.

`logs/clock_identity_red_20260909_01.log` reproduced all four new failures:
unavailable-reference identity, derived-beam identity, strict PDCCH TX slot,
and strict blind RX slot. After that batch exited, production repairs:

- Preserve string types by making a typed zero-row comparison table before
  appending explicitly unavailable reference diagnostics.
- Bind raw in-memory DL/UL/PBCH/RS lifecycle identity before derived
  summaries, without relabeling independently persisted component evidence.
- Bind strict PDCCH TX, live blind RX, and cached blind RX to actual
  zero-based slot/frame time; regenerate slot-dependent candidate metadata.
- Materialize configured CSS/USS explicitly instead of the Toolbox default.
- Set PUCCH timing-use flags from the actual received-reference alignment;
  preserve format-0 prior-pilot prediction as not a fresh current estimate.

All six checks in `logs/clock_identity_repair_20260909_01.log` passed,
**exit 0**, including actual TDD shared PUCCH format-2 and format-0 trials.
This is component/regression evidence, not a successful rerun of `_04`.

The exhaustive audit additionally exposed missing RunID/ExecutionID on
primary DL/UL rows. Their common canonicalization boundary now invokes
the same conflict-rejecting lifecycle binder. PDCCH regressions were also
extended across the 1024-frame SFN wrap. Serial compatibility batch
session 54425 (`logs/clock_identity_compatibility_20260909_01.log`) is live:
TX/RX wrap tests, existing DUT-reference checks, CSS/USS enumeration and
both required E2E truth/proxy tests. Do not edit dependencies until it exits.
No new main TDD/FDD run or long campaign has been launched.

Important remaining distinctions from the terminal audit: data rows retain
actual sample-indexed channel-observation manifests with exact TDD
reciprocity on each executed segment, while legacy top-level reciprocity
fields are blank/false. A correct repair must validate and summarize the
real segment evidence and its scope, not copy one segment over a whole
observation or merely relax the audit. Main SSB delivery/resource planning,
SSB occupancy, QCL/TCI, UCI-on-PUSCH coverage, scoped RSSI and missing paired
EVM/waveform outputs remain unresolved.

Clock/property reference: MathWorks `nrCarrierConfig` documents frame/slot
modulo responsibility, and `nrSearchSpaceConfig` defines explicit `ue` /
`common` types (default `ue`):
https://www.mathworks.com/help/5g/ref/nrcarrierconfig.html
https://www.mathworks.com/help/5g/ref/nrsearchspaceconfig.html

## PUCCH resource planning repair, 2026-09-09 IST

Compatibility session 54425 finished with exit 0; all seven clock/identity,
candidate-enumeration and E2E truth/proxy checks passed. No main run was
restarted and no old output was modified.

The slot-42 fatal stack requested transmit-power evidence while merely
reserving a future HARQ-ACK resource. Added immutable `PUCCHResourcePlan`
and separated `planHARQ/planCSI/planCombined` from `materialize` in
`PUCCHConfigBuilder`. Planning still validates report identity/epoch, PRI,
resource capacity, K1 and TDD ownership. It creates neither a transmit
assignment nor a waveform/measurement. Materialization revalidates current
RRC/report digests and retains strict measured-reference power validation.
Both runtime HARQ reservation and CSI resource planning use this boundary;
actual PUCCH execution still requires a fully bound transmit assignment.

`logs/pucch_planning_repair_20260909_01.log` and `_03.log` each passed
seven checks: pure planning/strict TX power, measured-reference power,
resource sets, numeric PRI, TDD K1, and actual shared format-2/format-0
PUCCH waveforms. Each batch exited 1 on the older multi-user PRI fixture.
The original fixture supplied K0=0 implicitly although its active TDRA
specified a different offset. The first fixture repair incorrectly assumed
an operator-strict context; this scenario instead uses YAML-derived TDRA.
The revised fixture now resolves that actual context before freezing the
grant. `_02.log` was a shell-quoting launch failure, not a PHY test result.
`_04.log` is the subsequent focused compatibility batch; its outcome must
be checked before claiming completion.

Remaining physical authority finding: PRACH already uses received SIB1
ss-PBCH-BlockPower minus retained UE-filtered RSRP. Connected UL in
`applyUserContext` still consumes physical TX-EPRE-minus-RSRP diagnostics.
These may agree numerically without impairments but are not interchangeable
UE authorities. TS 38.213 V18.5.0, clause 7.1.1 (page 33), specifies higher
layer referenceSignalPower minus higher-layer-filtered RSRP; CSI-RS uses
the applicable signalled powerControlOffsetSS. Preserve measured TX EPRE
for scoring; do not replace missing received authority with configured
power or a geometry value. This repair and per-occasion SSB delivery remain
open; extending measurement TTL would not repair either issue.

Reference:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.05.00_60/ts_138213v180500p.pdf

### Follow-on results and active spatial selection

`pucch_planning_repair_20260909_04.log` finished **exit 0**: revised
multi-user PRI, negative DL K0/UL K2 TDRA contracts, planning-without-power,
scheduler grant consistency and both E2E truth/proxy regressions passed.
The E2E tests use their existing FDD fixtures, not a new main FDD campaign.
The independent Python UL evidence-auditor suite also passed all 7 tests.

`pucch_spatial_relation_red_20260909_01.log` reproduced the builder's
first-entry bug: an active second spatial relation was rejected as inactive.
`localSpatial` now selects the unique active ID, rejects conflicting active
IDs/duplicate IDs/missing active state, and retains stale-state validation.
This is catalog selection only, not proof of received MAC-CE activation,
effective TCI timing, QCL source association or physical beam application.

`uplink_spatial_rssi_repair_20260909_01.log` passed all seven cases:
active spatial selection, pure resource planning, multi-user PRI, actual
PRACH mixed-numerology sample-clock/detector checks, analytic SSB-window
RSSI closure, actual TDD shared SRS/DCI/PUSCH with HARQ-ACK UCI and coincident
non-overlapping SRS, and actual TDD PUCCH HARQ+CSI reception/delivery.
The PUSCH component retained decoded bits [1;0], CRC pass and its real
channel artifacts. Its initial TAG/pathloss/UCI inputs are explicit test
fixtures, not a claim of successful main-run access-to-feedback coverage.

Another definite main-profile defect: format-2 resource 10 uses two PRBs,
but `power_control.m_rb` remains 1 and was copied into every assignment.
TS 38.213 clause 7.2.1 (page 38) binds the bandwidth term to the PUCCH
resource assignment and SCS, not a fixed scenario scalar. A dedicated
9-vector regression is being run before repairing this binding. The
separate configured DeltaTF/closed-loop/power-reference authority audit
remains open; correcting the bandwidth term alone is not full power-control
qualification.

### PUCCH resource-power repair and export propagation

`pucch_resource_power_red_20260909_01.log` reproduced the wrong bandwidth
binding. The builder now derives MRB from the selected typed resource and
mu from explicit carrier SCS, retaining the old scalar values only as
configuration diagnostics. The power controller retains these inputs and
their source. `pucch_resource_power_repair_20260909_01.log` completed with
**exit 0**, all eight cases passed: nine PRB/SCS vectors, active spatial
selection, existing FDD/TDD power checks, pure planning, actual shared TDD
format-2 PUCCH, combined CSI/HARQ reception, and both E2E regressions.

The producer's new ledger fields also need the main coupled row reducer.
`bindPUCCHPowerLedger` now copies the executed numeric inputs/outputs and
pathloss provenance into the actual control row. Shared completion obtains
its applied contribution target from retained preparation metadata and
labels it `pre_node_rf_transmitter_contribution`. It does **not** invent
isolated post-RF PUCCH power from a composite node observation. Missing
post-RF isolated measurements remain unavailable. No legacy `_04` rows
have been rewritten to make the failed run appear repaired.

`verifyPUCCHPowerExport` checks the actual shared receiver row, bandwidth
equation, clipping target and reference-plane label, then writes/reads a
temporary diagnostic CSV and verifies numeric roundtrip to 1e-12.
It is called by both shared PUCCH feedback and shared CSI/HARQ tests.
Serial session **17326**, `logs/pucch_power_export_repair_20260909_01.log`,
is the final export-focused check (power vectors, format 2, format 0,
combined CSI/HARQ and both E2E regressions). Check its terminal result
before claiming that final propagation passed; dependencies are frozen
while it remains alive.

Session 17326 update at 19:30 UTC: all four focused cases passed,
including actual format-2, format-0 and combined HARQ/CSI power-ledger CSV
roundtrips. The two E2E compatibility tests are still running serially.
This is not a completed main-run qualification. Next production work:
per-SSB-occasion causal measurement delivery and connected-UL received
reference-power authority; then actual SSB/grid collision ownership,
QCL/TCI/PMI activation and missing measurement/export contracts.

## Physical attenuation versus UE power-reference separation (Sep 9)

Session 17326 completed with exit 0: all six export-focused cases passed,
including both E2E compatibility checks. Session 86775 also completed with
exit 0, all six cases passed (`propagation_pathloss_repair_20260909_01.log`).
Its actual TDD SRS/DCI/PUSCH/UCI component executed successfully.

`propagation_pathloss_red_20260909_01.log` first reproduced that changing
only UE-estimated pathloss changed physical attenuation. The repair binds
`RuntimePropagationPathloss_dB` independently from model-owned link state,
including victim-link and waveform-truth context boundaries. Explicit
invalid physical authority fails rather than falling back to a UE estimate.
Legacy contexts without that new field retain the explicitly identified
legacy path; this is not a claim that all legacy paths are qualified.

The next regression, `testConnectedSSBPowerAuthority`, isolates another
boundary: connected UL must consume decoded reference power minus filtered
UE RSRP, not physical TX EPRE/pathloss diagnostics. It also distinguishes
future transmission slot from current scheduling knowledge for SIB1 and
measurement delivery. Its inputs are explicit component/codec fixtures,
not on-air SSB measurements. The failed main `_04` run remains unchanged
and unqualified; per-occasion SSB delivery and the other open items above
still require repair and a fresh run.

Connected SSB power integration: the red batch
`connected_ssb_power_red_20260909_01.log` exited 1 on the expected 95 dB
versus 110 dB authority mismatch. `bindSharedSSBPowerReference` now owns
the common calculation for PRACH and connected SSB-referenced UL. Its
SIB1 availability check uses the scheduling knowledge slot, not a queued
future transmission slot. It preserves the explicit UE implementation
filter source; received connected-mode QuantityConfig activation and
CSI-RS relative-power authority are still separate open audits.

Serial batch 22967 (`connected_ssb_power_repair_20260909_01.log`) passed
the repaired numeric authority assertion, then exposed a test-harness
mistake: the physical comparison reads the original unmaterialized state
instead of the state returned by applyUserContext. Correct that test after
the batch exits. RA authority, physical attenuation, actual TDD SRS/PUSCH/UCI,
PUCCH feedback and combined CSI/HARQ checks passed. E2E checks are pending.
The shared tests now supply an explicitly labeled decoded-SIB1 codec
fixture rather than an incomplete common-cell struct; no primary campaign
measurements were manufactured. Python uplink-auditor tests: 7 passed.

Read-only follow-up confirmed two unclosed associations: strict PDCCH
events still derive BeamID from ActiveTCIStateID and QCLSourceID from
CORESETID, without the actual installed/measured beam mapping; and
ChannelFactory.localAttachRuntimeGeometryMeta still labels UE-serving
pathloss as RuntimePathloss_dB rather than the new physical propagation
field. The latter is metadata, not another attenuation stage, but must be
separated before claiming all channel evidence is correctly labeled.

Terminal results: batch 22967 exited 1 solely because of the new test's
original-state assertion; its other seven cases, including both E2E
compatibility checks, passed. The test now retains the state returned by
applyUserContext. Batch 92146, `connected_ssb_power_repair_20260909_02.log`,
completed with exit 0: connected SSB power authority in both TDD/FDD
configurations (including future SIB1/measurement and missing-authority
guards), PRACH power authority, physical propagation separation and SSB
window RSSI closure all passed. No production dependency changed between
those two batches. Targeted git diff --check passed (CRLF notices only).

No MATLAB batch remains active at this checkpoint. The main `_04` run is
still failed, not silently upgraded by these component results. Next:
per-SSB-occasion measurement delivery to repair the actual stale-reference
boundary; actual shared grid/SSB ownership; received QCL/TCI/PMI activation
and beam mapping; remaining power/reference-plane and CSV/PNG contracts.
Full-suite qualification remains open under the user's focused-test scope.

## Per-occasion serving-SSB delivery implementation (Sep 9)

The receiver now supports an explicit SSB/MIB completion stage. It executes
the actual PSS/SSS/PBCH/MIB receiver and connector-power measurement, but
does not attempt SIB1 or set the full-SIB1 StrictOk flag. Canonical symbol
times plus the configured receiver timing-search guard determine each
complete prefix extent; true delay and decoded estimates do not choose it.

`ssb_occasion_reception_20260909_01.log` (session 22877) completed with exit
0. The actual noisy CDL stream delivered all four prefixes before full
burst/SIB1 completion; each decoded its own BCH identity and finite
SS-RSRP/SS-SINR. Whole-versus-chunk sample and noise-state equivalence and
no channel re-execution assertions also passed.

Production wiring now subscribes separate three-plane observations for
periodic serving-SSB tracking. SSBOccasionResultDelivery decodes at the
actual sample deadline, publishes at the first eligible slot boundary,
and retains sample-clock/RSSI evidence in the canonical exported reference
measurement ledger. Full-burst beam selection remains separate; its later
tracking reducer checks that per-occasion delivery exists rather than
updating each UE filter twice. Initial acquisition still uses its full
broadcast completion contract; this patch does not claim initial-access
latency optimization or full beam/QCL/TCI qualification.

Main-owner regression batch 83416 (`shared_ssb_occasion_delivery_20260909_01.log`)
is running serially. Its new test stopped on an invalid private-property
inspection (`owner.Components`), before exercising the new main-owner
completion path. The actual noisy-stream and connected SSB authority
checks passed. Replace that harness check with actual per-interval TX-RF
input hashes after the batch exits. Also guard acquired serving-cell
identity and pending results at independent sweep reset before claiming
the main integration qualified. No main `_04` rerun has occurred.

Batch 83416 exited 1 only on the private-property test mistake; its other
four checks passed. The harness now verifies every actual gNB TX-RF input
interval against the prepared waveform hash, including known idle samples.
Batch 24564 (`shared_ssb_occasion_delivery_20260909_02.log`) exited 0:
four actual shared-radio SSBs, earliest availability slot 2, no duplicated
waveform/filter updates, acquired-state guard and sweep-boundary censoring.

CRC outcome and measurement validity are now separate. A BCH decoded for
another cell remains CRC-successful but cannot provide serving-cell power
authority. Actual sample extents, PCI, CRC, receiver status, failure reason,
recovery scope and scoped RSSI JSON are retained in the canonical exported
measurement ledger. Batch 96592 (`shared_ssb_occasion_delivery_20260909_03.log`)
has passed the actual shared-owner test including wrong-cell/CRC separation
and CSV numeric/JSON roundtrips, and the noisy-stream test. Its remaining
compatibility checks are still running; freeze dependencies until terminal.

Standards cross-check: TS 38.215 V18.4.0 clauses 5.1.1/5.1.3 require
identity-consistent reference-signal power and explicitly scoped RSSI
time/frequency resources. The new per-occasion route retains the prior
conservative valid-BCH requirement for a usable tracking measurement; that
is NOT asserted to be a normative prerequisite for measuring SSS power.
Further low-SINR tests must address CRC-failed but correctly identified,
measurable SSS occasions. Full-carrier/SMTC RSSI and connected QuantityConfig
activation also remain unqualified. Source:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf

Session 54128 is now terminal, exit 1: nine focused tests PASS, followed by
`testGeometryScenarioAudit` FAIL at its real reduced-YAML scenario assertion
(line 371): `required_artifact_missing_or_empty` and
`measured_sinr_timeseries_empty`. Its initial geometry/audit/plot fixtures
and new shared recovery policy check passed, but the four-slot SystemLevel
execution produced ActiveUECount=0 and no grants. Do not weaken the final
assertion or claim this batch passed. No production dependency was edited
while it was alive. A read-only traffic/allocation diagnostic is running as
session 18162, log `logs/geometry_empty_grants_diagnostic_20260909_02.log`.
The preceding diagnostic `_01` had only a PowerShell/MATLAB quoting error
and exited before executing simulator code.

Final batch 96592 completed with exit 0: all five checks passed, including
both E2E compatibility tests. No MATLAB process remained before the next
launch. A fresh unchanged 55-slot nominal-12-dB TDD diagnostic is next:
`short12_ssb_occasion_timing_20260909_01`, using the normal runSingle front
door. Its destination was checked absent; no old outputs are removed.
Port 62906 currently has no listener, so this is not claimed to be a
WebGUI-launched run. Keep all production dependencies frozen during it.
Passing the component tests does not prove that the previous slot-42 main
failure is repaired end-to-end or that QCL/TCI/PMI/export qualification is
complete. Those claims require inspection of the new execution's rows.

Fresh main run is confirmed live: session **81956**, MATLAB worker **16096**
(launcher 6224), log `logs/short12_ssb_occasion_timing_20260909_01.log`.
Preflight passed TDD, nominal 12 dB, 55 slots, CSV and figure flags, and
nonexistent destination. At 20:24:24 UTC it was resolving exact DL/UL
allocations before slot zero. Filesystem artifact backend is active; the
runner selected the actual waveform bundle. Do not start another MATLAB,
alter dependencies, or restart this run solely because an observation
times out. Poll session 81956 / the same log for subsequent status.

### Live main evidence audit, 2026-09-09 (continuation)

Production dependencies remain frozen while session 81956 is alive. Added
only an independent Python SSB occasion auditor and its metadata/arithmetic
tests. The nine new tests and seven existing UL evidence tests pass. This
does not replace MATLAB PHY regression or full-suite qualification.

`tools/audit_lls_ssb_occasion_evidence.py` verifies actual retained sample
coordinates, publication after observation completion, duplicate occasion
identity, serving PCI, per-antenna dimensions, RSSI computed from mean
useful-symbol power, CSV/JSON numeric agreement, and scoped RSRQ arithmetic.
It does not substitute serving SSS-only RSRP for the window's SSS/PBCH-DMRS
reference, redefine SSS validity from BCH CRC, or call window RSSI full-carrier
RSSI. Receipts are created outside the run without overwriting prior ones.

Measured evidence:

- Focused MATLAB test's four actual occasion rows: zero arithmetic/timing
  failures (`logs/ssb_occasion_focused_csv_audit_20260909_01.json`).
- Main run slot 21 SSB resources 0/1 are published at slot 22; resources 2/3
  actually occur in slot 22 and are published at slot 23. All four are valid
  with passing BCH CRC. RSRP is respectively -76.15190956, -81.12849227,
  -89.57181490 and -77.54913174 dBm. These are measured, not corrected to
  a target range. All four pass the independent audit:
  `logs/short12_ssb_occasion_measurement_audit_20260909_02.json`.
- Actual shared-stream Msg1/2/3/4 captures exist at zero-based slots
  14/16/19/22, with self-loop flag zero. The four-stage capture audit passes
  sample-count, physical-segment continuity, time, direction, emitted-power
  and thermal-noise arithmetic. Receipt directory:
  `logs/short12_ssb_occasion_ra_audit_20260909_01`.
- The early UL trial-table receipt has all four channels unobserved, not
  qualified. RA stage captures and delayed canonical PRACH trial publication
  are different evidence surfaces; absence of the latter is not absence of
  the former. Re-audit canonical tables when connected UL results arrive.

Read-only QCL review reconfirms an open defect: PDCCHReceiver.localEventData
uses ActiveTCIStateID for BeamID and CORESETID for QCLSourceID, with a generic
PDCCH_DMRS label. DecodedGrantMaterializer validates beam/TCI IDs but does not
compare QCL reference identity. Do not assert these metadata fields establish
the actual RS-to-beam association. TS 38.214 V18.4.0 clause 5.1.5 describes
QCL assumptions associated with the indicated TCI state and RS, including
timing-dependent rules; repair requires tracing installed/activated state
and actual beam application, not changing labels alone. Reference:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.04.00_60/ts_138214v180400p.pdf

The current resolved YAML has conservative CQI bootstrap and
require_active_tci_state=false. Neither confirms complete QCL/TCI integration.
At this checkpoint the main run is at slot 25/55 with MATLAB alive. The
previous slot-42 failure, connected PUSCH/PUCCH/SRS, all final CSV/PNG checks,
full-carrier RSSI and full NR qualification remain OPEN.

At slot 34/55, access is complete including actual UL RRCSetupComplete
(zero-based slot 24). Canonical PRACH now has one PASS row. Actual SRS slot
30 is delivered at slot 31, with observation end sample 230392 at 7.68 MHz,
delivery time 0.030 s, received-reference correction 84 samples and measured
pilot-reconstruction SINR 12.21823903 dB. Scoring uses the already executed
channel (zero additional executions, AppliedChannelReferenceUsedByReceiver=0).
Two committed DL rows (31/32) have CRC pass, MCS 1; their approximately
50-dB values are explicitly decision-directed post-equalization residual
SINR, not a forced 12-dB measurement or proof of calibrated link SINR.

Two concrete SRS follow-ups were found by this continuation:

1. `localCollectSRSTrials` does not populate RuntimeEvidenceSource; the generic
   categorical filler turns it into `not_emitted_by_active_srs_runtime`
   although SRSRuntimeEvidenceUsable=1 and the actual source/consumer exists.
   Repair at the producer, not by rewriting this run's CSV. The independent
   UL auditor now fails this contradiction explicitly. Receipt
   `logs/short12_ssb_occasion_uplink_audit_20260909_03.json` has one failure,
   not a clean qualification result. PUCCH/PUSCH were still unobserved at
   that receipt. The same audit fixes a union-schema bug: blank generic
   TimingEstimateSource must not hide populated SRSReceiveTimingSource.
   All nine updated UL-auditor tests and nine SSB-auditor tests pass.
2. `localCompleteSharedSRS` promotes ReceivedULTimingReference only under
   `output.Ok`. In runSRSChannelEstimation, Ok includes true-channel NMSE
   qualification. This leaves a latent scoring-to-runtime timing dependency
   even though srsRuntimeEvidenceComplete already separates scheduling from
   independent NMSE. Repair promotion using practical received evidence and
   the existing strict ReceivedULTimingReference capture/identity validators.
   Preserve StrictOk/Ok qualification, add a metamorphic regression changing
   only scoring outcome with identical actual timing/capture, and verify
   failed practical timing still cannot be promoted. The current case passes
   NMSE, so it does not exercise this latent failure.

An actual live SSB-window RSSI PNG was inspected at checkpoint
`cfc287b63d7f93013cae0a13191410e4c87bc2243ace5cfcd635bfba83a5a48d`:
16 per-antenna points across burst-source slots 1 and 21, explicit useful
SSB-window scope, no invented sweep/fit, and partial-checkpoint warning.
This is not verification of every final PNG or full-carrier RSSI.

At 20:44:46 UTC the SAME MATLAB session 81956 is at slot 36/55. Do not
restart it or edit production dependencies while it remains alive.

- Actual PUCCH slot 34 format 2: expected/received UCI `1110111111`, error
  vector `0000000000`, PASS. CRCApplicable=0 and CRCPass=NaN, not fake pass.
  Two-PRB/mu=0 bandwidth term recomputes within 2.3e-15 dB; applied power
  4.10928356 dBm equals min(23 dBm, requested). Its received-SSB pathloss
  authority is SSB_UE_1_resource_0_slot_21, not configured pathloss 77 dB.
- Actual PUSCH slot 35: CRC pass, MCS 1/QPSK, post-equalization SINR
  11.03890351 dB, receiver-Hest SINR 8.11485034 dB. UCIOnPUSCHApplied=0,
  source=no_uci_payload_requested. This is NOT a main-run UCI-on-PUSCH test;
  PUCCH is in slot 34 and PUSCH in slot 35. Do not manufacture overlap.
- SRS slots 30/35 are delivered at 31/36 and both pass practical receive
  checks; their respective pilot-reconstruction SINRs are 12.21823903 and
  11.75708794 dB. Both rows still have the missing runtime-producer token.
- Final live audit receipt for this continuation:
  `logs/short12_ssb_occasion_uplink_audit_20260909_04.json`, exit 1.
  Coverage PRACH=1, PUCCH=1, PUSCH=1, SRS=2; exactly two failed checks,
  both missing SRS runtime provenance. No channel is unobserved, but this
  does not imply every implementation or PHY metric is qualified.
- UL auditor now also checks actual shared-SRS completion clock and no
  consumption of future samples. Its ten tests pass; nine SSB-auditor tests
  also pass. Only these independent Python tools/tests and this journal
  were edited during the live MATLAB batch.

Immediate continuation: monitor the same main past slot 42 and terminal
finalization, audit all completed output sources, then fix the two SRS
producer/promotion issues with focused regressions before another main run.
Keep QCL/TCI associations, scoring/timing coordinates, full RSSI scope,
main UCI multiplexing coverage and final artifact closure explicitly open.

### Continuation: immutable live checkpoint and identity audit

The prior turn made progress; session 81956 was confirmed still live with
worker 16096 at slot 37. No production source was edited. At slot 40 the
third actual shared SRS reception is complete; main terminal qualification
and the slot-42 regression are still pending.

Read-only audit of immutable checkpoint
`6304a2536e7398a87fbfe561064f1ab088799b755f75b607683e170a52dd4f99`:

- All 45 retained artifact hashes match; all 17 PNGs decode.
- Four DL and one UL retained data rows passed the existing primary-link
  arithmetic/operating-point/transport/noise checks. Expected-total-count
  qualification was deliberately excluded: this is a partial checkpoint,
  and comparing its row count to itself would not prove run completeness.
- Eight check groups failed: required columns and three identity checks for
  each direction. Live DL/UL rows lack RunID and ExecutionID. The outer
  checkpoint hashes provide lineage, but do not repair missing row identity.
- The initial read-only audit attempt hit Windows MAX_PATH. Repeating with
  the existing extended-path helper succeeded; that was not missing data.

Root cause found by inspection: localPublishCoupledTruthRuntimeState writes
rawTrials.DL/UL after localForceDirectionalRawTrialArtifacts, without calling
localBindCoupledRuntimeIdentity. Identity binding exists later in final
collection. In contrast, live SRS has the actual RunID and execution UUID.
Fix the live publisher using the existing strict identity binder before raw
CSV and derived consumers, retain conflict rejection and low-level unbound
unit-call semantics, and cover live publication rather than only final rows.
Do not rewrite already captured CSVs or copy identity from another run.

New runtime data also shows real applied precoder evolution: DL slots 31-33
use requested/applied PMI 0 and matrix digest 143f9163..., while slots 36-37
use PMI 3 and digest aba169ab.... The generic PMI column is a current
measurement field and is not interchangeable with AppliedPrecoderPMI.
CSI-RS source slot 32 is delivered through decoded PUCCH in slot 34, then
marked DeliveredSlot=35. The next DL opportunity (36) uses PMI 3 and MCS 26
instead of bootstrap MCS 1; both have passing CRC. This supports causal
feedback use, not full QCL/TCI or codebook qualification. UL adaptation still
needs the actual slot-40 data result at this checkpoint.

### Slot-42 timing regression passed; broadcast/data coexistence failure exposed

The SAME session 81956 progressed through slot 42 and into slot 43, with
successful control gating, grant preparation and actual decoded DCI at 43.
Fresh SSB resources 0/1 produced at slot 41 were available at slot 42;
measured RSRP -76.57923739/-80.83356293 dBm, BCH CRC pass. Resources 2/3
produced at 42 were available at 43. Resource 2 has BCH CRC failure and
MeasurementValid=0; resource 3 passes. The eight retained occasion rows pass
the timing/RSSI arithmetic audit, including retention of that real failure:
`logs/short12_ssb_occasion_measurement_audit_20260909_04.json`.
This closes the reproduced slot-42 stale-measurement abort, not the whole run.

UL slot 40 is committed: MCS 6/QPSK, CRC pass, post-equalization SINR
10.82149526 dB and receiver-Hest SINR 8.71752973 dB. Slot 35 was MCS 1.
The main run therefore demonstrates adaptive MCS changes in both directions.

**Highest-priority newly exposed PHY issue:** DL slots 41 and 42 fail CRC
during the serving SSB burst. Post-equalization SINR drops respectively to
-1.63031789 and 9.35828291 dB, from roughly 45 dB in earlier MCS-26 slots.
Do not mask these failures or describe the timing-regression pass as total
LLS success.

Evidence supporting missing SSB/PDSCH resource exclusion:

- Resolved config: SSB Case A, 15-kHz SCS, Lmax=4, carrier NSizeGrid=25.
- The canonical SSBCaseResolver uses [2;8]+14*n for Case A. SSB 0 therefore
  occupies symbols 2-5 of burst slot 41, including PBCH in symbol 3.
- The executed observed_re_allocation.csv row for zero-based absolute slot
  40, PDSCH_DATA, symbol 3 explicitly records subcarrier_start=0,
  subcarrier_count=300, re_count=300. Authority is executed PDSCH_Tx and
  toolbox indices, allocation_id ends frame=5|slot=41. The same full-band
  data allocation occurs in the next slot. This does not exclude SSB PRBs.
- Same-burst SSB waveform reception is independently retained; the observed
  grid ledger still lacks its own SSB occupancy rows. That omission must be
  repaired too, not treated as proof of no SSB transmission.
- TS 38.214 V18.4.0 clause 5.1.4, PDF page 43, requires same-PCI SSB PRBs
  to be unavailable to C-RNTI PDSCH in the SSB symbols, and says the UE is
  not expected to handle DM-RS overlap with unavailable REs. Reference:
  https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.04.00_60/ts_138214v180400p.pdf

The collision diagnosis is based on executed PDSCH occupancy plus configured
canonical/received SSB evidence; complete observed SSB-grid intersection
evidence is still missing. Next repair must wire actual broadcast resource
occupancy into scheduler allocation and both TX/RX rate matching before
grant/TBS finalization. Merely puncturing a finished waveform, lowering MCS,
removing CRC-fail rows, or suppressing all SSB slots would not establish a
correct generic implementation. Respect DM-RS feasibility and explicit TDRA
choices, and test alternate SSB/BWP/numerology configurations in both duplex
modes without starting an FDD main run.

Production remains frozen until session 81956 and all finalization terminate.
After that, prioritize broadcast/data exclusion, then SRS provenance/timing
promotion, live row identity, and the other previously recorded issues.

### Slot 46 failure and recovery audit (2026-09-08 21:03 UTC onward)

The main PHY stopped at slot 46 with nine committed DL and three UL rows.
The failure is `sixgr:truth:PDCCHControlSlotMismatch`: canonical control slot
45 conflicts with the inherited one-based `ControlSlot=41` (zero-based 40).
The persisted failure stack identifies `resolvePDCCHControlSlot` line 26,
called by `localQualifyCoupledGrantsWithPDCCH` line 9188. Keep this strict
check. This is not another receiver timeout and not a completed run.

The retransmission preparation refreshes `ControlAbsoluteSlot` and clears
the old K0/K1/K2/TimingDecision, but `rebindHARQRetransmissionTiming` does not
invalidate the old ControlSlot/ControlFrame aliases. The runtime HARQ merge
also copies canonical current timing without copying/clearing those aliases.
Both boundaries need regression coverage, preserving original TB/coding and
soft-buffer lineage while rebinding only the current transmission occasion.

The SSB reservation audit also found that SchedulerBase resource-accounting
calls use a PRB-count prefix rather than the actual grant PRB set, and its
cache scope omits the runtime slot and SSB/TRS resource state. Those are
important for actual resource/DM-RS feasibility, but do NOT imply that the
standard nominal TBS must change merely because SSB resources are reserved.
A transmitter-only reservation does not establish consistent scheduler,
TX/RX rate-matching and DM-RS feasibility.

Independent UL receipt `logs/short12_ssb_occasion_uplink_audit_20260909_05.json`
observes PRACH=1, PUCCH=3, PUSCH=3, SRS=4. All three PUSCH blocks pass CRC
(slots 35/40/45, MCS 1/6/6). Main UCI-on-PUSCH remains unexercised.
The receipt has eleven failed consistency checks: four SRS missing-producer
provenance failures and seven PUCCH bit-vector closure failures.

During failure recovery, PUCCH leading zeroes disappear from exported bit
strings (slot 44 declares ten bits but the exported payload has six digits;
zero-error vectors have become a single zero). Earlier immutable live
evidence retained the zeroes. `sanitizeLLSArtifactCSVs` reads primary CSVs
with unconstrained `readtable` type inference before rewriting them, and
`csvReadTable` likewise does not declare bit-vector column types. Fix the
read/write contract and test literal long/leading-zero vectors, blank cells,
numeric fields and repeated finalization. Never pad already damaged rows
and call them recovered measurement evidence.

MATLAB 16096/session 81956 remains alive in failure artifact recovery;
production dependencies are still frozen. No second MATLAB batch, FDD main
run, testAll, output deletion or retrospective evidence repair was started.

Prepared (not yet executed) `testHARQControlOccasionAliases` and
`testUCIBitVectorCSVPreservation` while the production dependency freeze
remains in effect. These are isolated metadata/export regression fixtures,
not new measured main-run evidence.

Current primary evidence still explicitly labels QCL measurement as
`not_measured_requires_QCL_TCI_binding_evidence`; do not claim QCL/TCI is
complete. The strict PDCCH event producer assigns QCLSourceID from CORESETID
and BeamID from ActiveTCIStateID, while DecodedGrantMaterializer verifies
TCI/beam but not QCL source identity. Distinct namespaces and actual installed
RS relationships need end-to-end validation. Also review the legacy nonzero
PDCCH declared-sync helper, which appends/prepends zeros; establish whether
that path can be admitted by the shared captured-sample receiver before
claiming the entire control chain has no padding shortcut.

Independent byte comparison confirms recovery, rather than the receiver,
damaged the PUCCH vector representation. Immutable checkpoint
`13135a0124cdd42c7552271f00afba8fb82048f0cc88c1cc7b2c196d032626b0` retains
`sources/air_interface/csv/pucch_trials.csv`, SHA-256
`1ccd5ee307671e1235c46bd9d18a9c26f95ad3fea6f8f3eb5b89f0010801bf1f`.
Slots 34/39 have expected=decoded `1110111111`; slot 44 has `0000111011`.
Every error vector is `0000000000`. The recovery primary bytes (observed
SHA-256 `ff494ae5d5e3bd5d7ccb4795f9d49ca572aee0715331aba783b71111bdbc135f`)
retain declared ten-bit counts but change slot 44 payloads to `111011` and
every error vector to `0`. Neither artifact was modified by this audit.

TBS/rate-matching distinction verified against the **installed** R2026a
`toolbox/5g/5g/nrPDSCHIndices.m`: lines 113-114 explicitly say NREPerPRB
does not account for reserved resources; line 324 computes it from the
scheduled symbol set and DM-RS CDM overhead. Reserved PRBs/REs instead
change the actual indices and G. `computeResourceAccounting` preserves
these separate quantities. Therefore do not replace nominal NREPerPRB by
the post-reservation RE count or label an invariant TBS cache as inherently
wrong. The repair must check actual per-occasion PRB/DM-RS feasibility and
exact G separately, keeping TS 38.214 TBS determination intact.

Further validation preparation while recovery is active:

- `testSharedPUCCHFeedbackClock` now contains a metamorphic check on its
  actual SRS capture: change only NMSE/qualification results and retain the
  same received clock; unusable practical evidence and out-of-capture
  timing must still be rejected. It awaits implementation of the new
  `sixgr.truth.retainReceivedSRSTimingReference` helper and production
  wiring after the dependency freeze ends. **Not executed or passing yet.**
- The standalone Python audit tests were rerun: uplink 10/10 and SSB
  occasion evidence 9/9 pass. These test the audit tools, not the main PHY.
- The immutable PUCCH checkpoint above passes all 33 applicable bit-vector
  consistency checks. PRACH/PUSCH had zero applicable checks in that narrow
  vector checker, so their presence is not a pass claim; the same checkpoint
  does not retain an SRS CSV. The separate primary SRS receipt remains open.
- Recovery invokes browser materialization, then a bounded terminal
  source-hash/status closure with further materialization passes. The first
  Python worker 17360 exited, and another pass (worker 8364 via 12808/2872)
  started while MATLAB 16096/session 81956 remains alive. Do not confuse the
  `exportLLSOutputCoverageArtifacts:done` line with terminal MATLAB exit.

Next production patches are still pending: HARQ stale aliases at reset,
runtime replay merge and cached-grant merge; lossless bit-vector import in
the canonical reader and sanitizer; SRS measured-clock retention independent
of scoring plus actual producer provenance; live DL/UL lifecycle binding.
Keep the stricter PDCCH mismatch check and original HARQ TB/coding context.
After focused regressions, implement actual broadcast/PDSCH exclusion and
DM-RS feasibility before another main diagnostic. No code was hot-patched
into this failed run and no historical primary CSV was repaired in place.

## 2026-09-09: terminal failure, applied causal repairs and focused verification

The `short12_ssb_occasion_timing_20260909_01` main run is terminal, exit 1.
Its PHY failed at runtime slot 46 with `PDCCHControlSlotMismatch` (current
zero-based control 45 versus a stale original alias for 40). Recovery ended
at 2026-09-08 21:48:52 UTC with `TerminalBrowserClosureFailed`. Its receipt
has 172 available tables, 20 policy-disabled tables, one missing required
table (`geometry_runtime_audit.csv`), 276 available charts, 81 disabled and
30 missing. Preserve this failed evidence; no success or main-rerun claim.

The final read-only audit is in
`logs/short12_ssb_occasion_exhaustive_20260909_01/`: 886 CSVs, 811238 rows,
first five rows of each CSV recorded, 276 decodable PNGs, 17 required CSV
semantic failures. PNG decode/source audit success is not complete physical
qualification. Keyword counts (proxy/fallback/NaN) need domain/context
review and are not themselves evidence that actual PHY used a proxy.

After both the main process and a red-reproduction MATLAB process exited,
the staged repairs were hash-checked and applied to the real workspace:

- HARQ occasion rebinding expires original ControlSlot/ControlFrame aliases;
  replay and cached-grant merges share current timing authority, preserving
  original transport block/coding and soft-buffer semantics.
- Canonical CSV import forces binary-vector columns to text before any
  conversion; sanitizer uses that reader. No old payload was padded or
  reconstructed. The red fixture reproduced leading-zero loss; its harness
  then failed because R2026a's assertion had an empty identifier rather than
  the expected identifier. The observed failure messages are recorded in
  `logs/causal_repair_red_20260909_01.log`, not presented as a passing run.
- SRS retained timing is governed by usable practical receiver evidence,
  independently of oracle/NMSE qualification. The SRS producer now exports
  RuntimeEvidenceSource. Its DetectionMetric is received reference
  correlation peak energy, not negative oracle NMSE. A noise-only false-
  alarm qualification of SRS detection remains OPEN.
- Live DL/UL tables bind the actual run/execution identity before their
  primary CSV write. No generic identity patch relabels proxy as truth.

`logs/causal_repair_focused_20260909_01.log`, session 29532, exited 0:
all 15 requested tests passed, including HARQ timing aliases/replay,
PDCCH/PDSCH timing authority, lossless UCI CSVs, wide CSV import, sanitizer
idempotency, live identity, SRS scoring separation and received timing,
actual shared SRS-to-PUCCH clock, scheduler grants, E2E FastVsTruth and
TruthPacketSemanticCampaign. The latter use their existing component
duplex fixtures; no new main FDD campaign or testAll was launched.

Subsequent patches, applied only after MATLAB exited:

- Normal completion and recovery now share geometry evidence policy and
  `runGeometryScenarioAuditIfNeeded`. Recovery invokes the audit after
  persisted runtime-derived measurements and before report reduction.
  Missing/incomplete geometry creates failed audit findings, not substitute
  trajectory or SINR rows. Explicit resolved false is not replaced by an
  internal true. Invalid boolean policy fails loudly.
- Strict PDCCH receiver events no longer set BeamID=TCIStateID or
  QCLSourceID=CORESETID. Both receiver APIs optionally accept an installed
  ControlBeamState, validate its age/activity and monitored TCI identity,
  and bind distinct RS/beam IDs plus state digest/provenance. Without that
  state, QCL/beam values remain unavailable. The materializer now checks
  QCL type/source identity as well as TCI/beam; malformed/NaN control state
  and invalid/future/stale slots are rejected.

This is an identity/provenance repair, NOT completion of QCL-Type-A/B/C/D
parameter transfer or main scheduler TCI activation/beamweight application.
TS 38.214 clause 5.1.5 distinguishes TCI/QCL source RS and spatial receive
parameters; identifiers cannot substitute for an applied RF beam:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/19.02.00_60/ts_138214v190200p.pdf

`logs/uplink_qcl_recovery_focused_20260909_01.log`, session 54128, is the
new focused verification job. At this entry it is running, not claimed
passing. Production dependencies are frozen until it exits. The main
broadcast/PDSCH resource exclusion/DM-RS feasibility issue, SSB-window RSSI
chart publication, broad RSSI scope, main UCI-on-PUSCH exercise, reciprocity
metadata, incomplete artifact contracts and statistical/FRC qualification
remain OPEN. No new main TDD run has been launched yet.

Further focused progress (same session 54128): geometry recovery policy,
ControlBeamState validation, both actual strict blind PDCCH receive APIs,
decoded grant authority/QCL rejection, beam monitoring, PUSCH UCI receiver,
recovered PUSCH UCI, shared TDD PUSCH channel artifacts and UCI phase core
have passed. The shared UL fixture executes SRS/DCI/PUSCH/UCI, retains 3522
received constellation samples (EVM 8.55060489662%), and is not the main
nominal-12-dB qualification run. `testGeometryScenarioAudit` remains running
at this entry. Python radio-plot and UL/SSB audit tests: 72 passed.

### Newly isolated RSSI/SSB producer identity defect (not patched yet)

Read-only dispatch of the RSSI chart against the untouched primary PBCH CSV
returns `Duplicate received SSB/branch RSSI identity.` This is not missing
RSSI math: actual physical four-symbol branch powers pass the chart's
linear-power-to-dBm checks until the duplicate identity.

At burst slot 41, two rows have SSBIndex=3 but distinct received timing
offsets: 8787 and 12079 samples inside the same [307200,345600) observation.
The former is the failed BCH candidate in the candidate-2 timing window;
the latter is the successful candidate-3 window. The producer currently
copies `PBCH_Recovery`'s best-DMRS (possibly failed CRC) hypothesis into
`recoverSIB1FromWaveform.SSBIndex`, then into the primary row, candidate
coordinates, power-reference selection and precoder-hash lookup.

Exact surfaces requiring repair together:

- `SSB_Rx` already retains `SelectedCandidateStartSymbol`, backed by the
  actual PSS correlation and canonical `SSBTiming.CandidateIndices` /
  `CandidateStartSymbolsWithinHalfFrame`. This is available independently
  of PBCH CRC and should identify the received measurement occasion.
- `completeCellSearchBroadcast` currently selects transmit SSS EPRE using
  `rec.SSBIndex`, even when that PBCH hypothesis failed. Keep actual
  received occasion, decoded/hypothesized identity and CRC validity separate;
  do not use failed BCH bits as applied-beam/reference-power authority.
- `localCollectCoupledPBCHBeamSweep` derives coordinates/coverage from the
  same corrupted index; selection must still require successful usable
  measurements and matching identities, never configured strength.
- `SSBOccasionResultDelivery.assertDelivered` currently checks each row's
  decoded index independently and can accept two rows against one delivered
  candidate. Enforce one-to-one observed-occasion coverage.
- `localCollectPBCHTrials` looks up the precoder hash with `SSBIndex+1`.
  That is also wrong for a sparse active SSB bitmap: look up the actual
  index in the executed active-index list, validating equal list lengths.
- Do not deduplicate/drop failed rows, relax the RSSI plot guard, or repair
  the historical primary CSV in place. Re-execute corrected producers.

Full NR carrier RSSI is still distinct from this SSB-window diagnostic.
TS 38.215 V18.4.0 clauses 5.1.3/5.1.4/5.1.21 require the actual configured
measurement symbols/bandwidth and total received power including disturbance:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf

### Latest checkpoint: both focused batches and allocation diagnostic terminal

Batch 54128 exited 1 after nine passing tests. Its last test,
`testGeometryScenarioAudit`, failed the unchanged complete-runtime assertion
at line 371: missing/empty measured SINR. Batch 29532 had already exited 0
with all 15 tests passing. Thus 24 focused MATLAB passes, one failing test,
and 72 Python passes; NOT a fully passing suite or production qualification.
No MATLAB process remained at this checkpoint. `git diff --check` passed
for the new touched tracked files (only normal LF/CRLF notices).

Read-only diagnostic 18162 exited 0. Its log
`logs/geometry_empty_grants_diagnostic_20260909_02.log` proves traffic was
NOT empty: DL offers were [36000,24000,24000,24000] bits per UE; UL offered
24000 per UE in each slot. Every DL allocation instead throws
`sixgr:phy:grid:allocREsPDSCH:TRSReservationFailed`. The actual operator
master YAML has `canonical_control.reference_signals.trs.row_number: 2`
and `symbol_location: 4`; the strict producer correctly requires one-port
density-three row 1 and an explicitly supported two-symbol tracking pair.
`SystemLevelRunner.localSlotBudgetSupportsExecutableDataGrants` catches
every exception and returns false, masking that invalid resource definition
as no active UE/no grants. Its mixed-slot UL allocation [13,1] independently
cannot carry configured Type-A DM-RS at symbol 2; that is an unavailable
data opportunity, not authority to move the DM-RS or pad an allocation.

Next repair must distinguish legitimate per-slot unschedulability from
invalid enabled PHY configuration, retain the original failure identifier,
and correct the operator TRS resource authority (not disable TRS or weaken
its strict mapping validation). Neither SystemLevelRunner nor this master
YAML was edited during this checkpoint. The geometry audit's new recovery
entry point is implemented/tested; the underlying geometry scenario is not
fixed yet. The SSB identity/power-reference/precoder issues and broadcast /
PDSCH exclusion above remain the main short-TDD rerun blockers. No main
TDD/FDD rerun, output cleanup, commit, or historical CSV rewrite occurred.

### TRS authority and received-SSB identity repair checkpoint (2026-09-09)

Production changes now applied, not yet end-to-end qualified:

- The master geometry TRS resource now declares row 1, one port, symbols
  [4,8], two consecutive slots, periodic offset 1. The generic alias map
  was missing `reference_signals.trs.period_offset`; it now forwards that
  authored field instead of allowing the internal default offset 0.
- SystemLevelRunner no longer swallows arbitrary PHY allocation failures
  as no-active-UE. Only specifically identified DM-RS infeasibility caused
  by a clipped slot allocation is treated as an unavailable opportunity.
- Received SSB occasion identity is separated from the PBCH hypothesis.
  Failed BCH hypotheses cannot relabel the observed PSS window or select
  a different transmit EPRE/precoder reference. Sparse active SSB IDs are
  matched to their executed precoder hashes, not used as array offsets.
  Duplicate slot/SSB delivery rows are rejected, not deduplicated silently.

Focused test 47552 exited 1: received-SSB identity passed, then the master
TRS slot assertion failed. Follow-up 88363 exited 1 because the diagnostic
message attempted JSON encoding of the full strict TRS structure (which
contains complex reference symbols). The diagnostic now encodes only slot
numbers. These harness failures are not claimed as PHY passes. Batch
88493 (`logs/trs_ssb_identity_focused_20260909_04.log`) is validating the
alias repair and actual waveform/delivery/reservation/scheduler/geometry
checks. Production dependencies are frozen while it runs.

The failed main short-TDD run remains unchanged. Its SSB/PDSCH resource
collision, complete QCL parameter application, full main-run UCI-on-PUSCH
coverage, carrier/SMTC RSSI scope, and missing publication artifacts remain
open. Component-level UCI receiver passes are not main-run multiplexing
proof. No fresh main campaign has been launched at this checkpoint.

The next broadcast/data reservation repair must use **PRB-symbol** exclusion
for SS/PBCH, not merely nonzero SSB REs. TS 38.214 V18.6.0 clause 5.1.4
(page 43) excludes PRBs containing same-PCI SS/PBCH in its transmitted OFDM
symbols for connected PDSCH and disallows overlapping DM-RS. CSI-RS/TRS
data reservations are instead sparse RE reservations. The exception for
SI-RNTI with system-information indicator 0 must remain explicit. See
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.06.00_60/ts_138214v180600p.pdf

Uplink batch01 stopped after real Msg1 reception: the isolated RA fixture
had no random_access.associated_ssb_index for the strict common-PDSCH QCL
guard. This was not proof of a missing main-run beam selection: the fixture
starts after acquisition without executing an SSB receiver. Its existing
configured runtime SSB index is now passed explicitly with source
configured_SSB_reference_for_RA_timing_component_not_measured_selection.
The production guard was retained; no measured-selection/TCI state was
fabricated. This test must not be cited as full acquisition/beam qualification.

Uplink batch02/session31300 completed exit0, terminal
UL_TIMING_MEASUREMENT_REGRESSION_PASS; worker10048/launcher10488 absent.
All eight listed tests passed. Specific observed evidence:

- RA planner chose Msg2=16, Msg3=19, Msg4=32, SetupComplete=34, rejecting
  two resource-conflicting candidate slots. All five actual RA stage
  receptions completed in the isolated CDL-A timing fixture. Received RAR
  TA=0 was used; this does not establish the nonzero TA of the main scenario.
- Shared TDD SRS/received UL DCI/PUSCH carried actual measured CSI and
  coded HARQ feedback; slot10 reception was correctly delivered in slot11.
  Actual captured UL EVM8.62254422951%, post-equalization SINR21.262dB,
  timing estimate90samples. These are component measurements, not new
  main-run or requested-SINR operating points.
- Late PUCCH feedback and format2 clock tests passed, including actual
  receiver power-ledger CSV round trips. SRS reference-correlation test
  recovered the deliberately introduced seven-sample component delay.
- Physical CSI-RSRP coupled case measured-77.1647686357dBm against an
  independent expected-77.1543170227dBm (difference0.010452dB). Its separate
  unattenuated analytic/unit cases are not field-power or UE main-run claims.
- RSSI/RSRQ resource/window/receive-branch checks across15/30/60kHz and
  QCL reference-state propagation passed; actual receiver parameter reuse
  remains a separate open qualification boundary.

Python: tests/test_lls_radio_measurement_plots.py,81passed. Read-only visual
inspection of the preserved old CSI-RS RSSI PNG confirmed two receive-branch
points at slot32, labelled observed operating points with no sweep/fit claim.
Old outputs remain unchanged; no full CSV/PNG/main-run all-pass claim.

Current increment total:11 focused MATLAB tests plus81 Python plot tests.
Scoped git diff --check passed (CRLF normalization warnings only). No MATLAB
remains running; no new main12dB/25dB/FDD scenario started, no commit/reset or
old-output deletion. Broad required suites and all OPEN boundaries listed
above remain pending. Goal ACTIVE, not complete or blocked.

## 2026-09-09 Msg4 TC-RNTI control migration (in progress)

The prior turn was progress. Inspected current source and MATLAB absence;
then migrated the actual Msg4 PHY path away from custom32-bit PRB/count/
symbol packing. TCMsg4DCIContext, DCISchemaEngine and DCIParser now implement
the TC-RNTI DCI1_0 field layout in TS38.212 V18.8.0 clause7.3.1.2.1 for
licensed FR1/FR2-1, default-A common TDRA, without Msg4 ACK repetition.
CORESET0 frequency sizing is explicit, including its reference origin;
unsupported missing CORESETS/common lists/repetition authority is rejected.
Legacy TC-RNTI DCI1_0 context must not fall through a C-RNTI schema.

Global defaults, parameter catalogs and both causal YAML profiles now carry
explicit msg4_dci control policy. The actual payload length is derived from
the schema; the old fixed32-bit alias/configuration was removed from these
profiles and the RA fixture. The strict stage generator derives PDSCH
allocation/MCS/HARQ fields from the encoded DCI and common DM-RS rules
(configuration1, port1000, single-symbol, pos2, appropriate no-data CDM
groups), no dedicated PT-RS. The default-A TABLE includes mapping types A/B;
the scheduler accepts both supported kinds from the selected table row.

Msg4 PDCCH now uses the configured/decoded Type1 common search space and
CORESET instead of a hardcoded aggregation-level/candidate override.
The receiver rebuilds common control independently and consumes decoded
DCI bits; it does not use transmitter schedule/candidate/grid/TBS/bit length.
RASIPDSCHContext requires the actual TC-RNTI context and on-air TDRA index;
the old custom payload parser and local TDRA-index0 fallback are removed.

Independent bit vectors cover24/48/96-RB CORESET0, field positions and
negative format/reserved/length/reference/repetition inputs. Actual ideal-
channel component tests remove both TX metadata arguments and the receiver's
authored PDSCH schedule. Both profile fixtures decode37bits, CRC1,TBS608;
type-B two-symbol allocations independently decodeTBS96. Both TX/RX field
tables round-trip through CSV with values/context hashes unchanged. This
is PHY/control evidence, not a complete MAC/RRC or feedback qualification.

Batch tc_msg4_control_regression_20260909_01/session7315: vectors and TDD
waveform passed; FDD's standalone profile lacked inherited msg4_dci defaults
and was correctly rejected. Added explicit YAML policy, not a runtime
fallback. Batch02/session82964 completed exit0; five tests passed:
testTCMsg4DCI, testMsg4ReceiverOwnsDCI, testRASIPDSCHStrictOwnership,
testRADuplexAllocationTiming, testTDDCausalFourStepRARuntimeTiming(14).
All five actual RA stage receptions completed on slots16/19/32/34.

After that terminal/process check, added mapping-B/legacy-context guards,
derived payload alias, and extra actual Msg4 field-export assertions.
Batch tc_msg4_export_regression_20260909_01/session46243 is RUNNING against
frozen source. TC vectors, both-mode A/B waveforms, causal RA,
test6GParameterCatalog, testLinkExportPipeline, testArtifactIntegrity and
testSchedulerGrantConsistency reached/passed before the E2E tests. The two
E2E tests remain in flight at this checkpoint; do not claim whole batch pass.

Additional honest boundaries found while implementing:

- The actual Msg4 MAC/RRC builder/parser still uses its internal bounded
  9/12-byte encoding, not TS38.321 MAC framing and TS38.331 ASN.1 RRCSetup.
  New receiver and Msg4 CSV fields explicitly label
  legacy_bounded_not_NR_MAC_RRC and MACRRCStandardsQualified=false.
  Removal of the TX bit-length oracle does not make that protocol normative.
- DCI PUCCH resource/TPC/feedback indicators are now real encoded/decoded
  fields. Actual Msg4 ACK scheduling/transmission/receipt remains unqualified;
  RecoveredSchedule.FeedbackTransmissionQualified stays false.
- Msg4PayloadHex is STILL copied from TX in localApplyMsg4, then labelled
  decoded by exportRAEvidenceArtifacts. Fix this after current MATLAB exits:
  preserve separate TransmittedPayloadHex and populate decoded PayloadHex
  only from actual recovered bytes. No existing artifact should be rewritten.
- msg4_dci_fields is produced from actual TX/RX in runFourStepRA but the
  explicit exportRAEvidenceArtifacts CSV map and two runtime accumulator
  allowlists still need wiring alongside msg2_dci_fields. Do not claim main
  runtime publication until these boundaries and their tests are complete.
- Full RA PDCCH resource/monitoring eligibility, observed RA/physical-TRS
  grid publication, shared OFDM RF phase-reference consistency, receiver
  QCL/TCI application, full main feedback/adaptation and broader suites remain
  open as previously recorded. No main scenario has been restarted.

Normative sources checked directly:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.06.00_60/ts_138214v180600p.pdf
and MathWorks `nrPDSCHConfig` / `nrPDSCHReservedConfig`: reserved indices
are BWP-relative. Scheduler feasibility, actual encoder G, and receiver
rate matching must share this map; a late composite-grid patch would not
repair the transmitted coding allocation.

### Geometry execution exposed two further failures

Batch 88493 exited 1. Five tests passed: SystemAllocationFailureVisibility,
SSBSharedReceivedBurst, SharedSSBOccasionDelivery, PDSCHTRSExactReservation,
SchedulerGrantConsistency. The sixth, GeometryScenarioAudit, executed all
four actual waveform slots and committed 384 served bits, but failed
qualification. Its remaining errors are (1) original full-slot HARQ replay
allocations exceeding a mixed-slot budget, rejected by canonical timing as
`target_flexible_symbols_unresolved`, and (2) catalog YAML serialization
rejecting an array with more than two dimensions. Thus the previous
zero-grant defect is repaired, not the entire geometry scenario.

RR and PF now check stored HARQ symbol ranges against the current resolved
budget before reserving PRBs or advancing retransmission state. Incompatible
replays stay pending with an `info.HARQDeferrals` reason; their TB, symbols,
and RV are not truncated or rewritten. `testHARQRetransmissionSymbolBudget`
checks DL/UL interval semantics and actual RR/PF pending-process retention
and resumption. Its first batch 44695 failed because its new fixture omitted
an explicit active TDRA list. The fixture now declares both tested legal
allocations; production DCI validation was not weakened. Batch 9665,
`logs/harq_symbol_budget_focused_20260909_02.log`, is the follow-up. Its
canonical scheduler fixture uses FDD timing only as a component test, not a
main FDD campaign. The main campaign remains TDD only and has not rerun.

The Windows test cleanup warning was separately repaired by closing the
test's own logger before removing its temporary directory through a single
cleanup callback. No global fclose or broad directory deletion was added.
Python measurement-plot and UL/SSB artifact-audit checks reran: 72 passed.

Batch 9665 exited 0: HARQRetransmissionSymbolBudget,
SystemAllocationFailureVisibility, HARQControlOccasionAliases, and
SchedulerGrantConsistency passed. Its nested test cleanup still emitted a
destroyed-workspace warning; cleanup was subsequently separated into outer
temporary-directory and inner logger lifetimes. This warning is not hidden.

YAML repair now uses `SixgrNumericArrayEncoding: column_major_v1` for complex
or N-D arrays, with explicit MATLAB class, shape, real and imaginary values.
The config reader reconstructs those arrays and rejects inconsistent shape
metadata. Double/single scalar formatting uses 17/9 significant digits to
preserve round-trip precision, not display-format rounding. Unsupported
typed integer classes are rejected instead of silently converted. Existing
ordinary YAML arrays retain their representation. Batch 4856,
`logs/yaml_geometry_repair_focused_20260909_01.log`, has already passed
complex-tensor (including empty and logical tensor) round trips, numeric
matrix round trips, and struct-array round trips. It is checking the cleanup
and real four-slot geometry integration after the HARQ and YAML repairs.
No production edits while this batch is running; main qualification still
open and the old failed run is preserved.

Batch 4856 is terminal, exit 0: all five focused cases passed, including
the actual four-slot GeometryScenarioAudit. The original zero-grant TRS
configuration, mixed-slot HARQ scheduling exception, and catalog N-D YAML
export exception no longer fail this unchanged geometry integration gate.
Its actual PHY committed 384 served bits; geometry CSV checks and dashboard
generation assertions passed. This is not qualification of the main
55-slot nominal-12-dB shared-stream run or all of its CSV/PNG families.
The cleanup warning did not recur in this final verification batch.

Open follow-through includes persisting the new HARQ deferral decisions in
the main scheduler's exported decision table (the RR/PF info structure now
retains them), SS/PBCH PRB-symbol exclusions before DCI/encoding, full QCL
parameter/TCI activation application, actual main UCI-on-PUSCH coverage,
carrier/SMTC RSSI scope, and the failed main publication receipt's missing
families. No testAll, fresh main FDD/25-dB campaign, cleanup of historical
outputs, or commit was performed.

Next verification is active as MATLAB session 56208, log
`logs/config_integrity_followup_20260909_01.log`: testConfig,
testStrictProxyGuards, testStrictMode_NoFallbackAnywhere,
testE2E_FastVsTruth, and testE2E_TruthPacketSemanticCampaign. Wait for its
terminal result before modifying production dependencies or launching any
other MATLAB batch. The main goal remains active, not complete or blocked.

## Continuation: SSB ownership and nominal/actual scheduler separation

Integrity batch 56208 exited 0; all five named config/strict-proxy/E2E
checks passed. These include existing FDD regression fixtures, not a new
main FDD campaign.

Added configuration-owned SS/PBCH PRB-symbol reservation using the existing
SSB timing resolver, burst plan and integer-Tc symbol boundaries. The map
includes partially overlapped PRBs, active burst indices, periodic repeats,
and BWP-relative projection. Actual PDSCH allocation reserves those resources
before rate matching and rejects SSB/DM-RS overlap instead of puncturing
DM-RS. SI-RNTI overlap requires its actual system-information indicator.
These maps are configuration evidence, not measured receiver data.

The first focused mapper batch failed on an empty-array size mismatch in a
quiet slot. Fixed the empty index set explicitly. The subsequent initial
test passed; extended tests also passed against every nonzero RE in the
actual SSB_Tx burst grid and a mixed-numerology timing-calendar case. The
mixed-numerology assertion does not qualify mixed-numerology composite RF.

The next regression exposed a real scheduler authority defect:
estimateTBS called the actual PDSCH allocator using cached PRB-count/TDRA
and a static slot-zero carrier. Consequently, a nominal TBS query inherited
an SSB/DM-RS collision from the wrong resource occasion.

Refactored the existing PDSCH config/DM-RS/PT-RS construction into one shared
factory and option parser. The nominal helper returns only exact 38.214
N_RE per PRB; it does not return G, waveform truth or a feasibility verdict.
The actual allocator retains CSI-RS, TRS, SSB and DM-RS collision checks.
Scheduler finalization separately projects ScheduledAbsoluteSlot through
the common runtime/carrier clock conversion and resolves actual PRB/symbol
allocation for BOTH DL and UL. It records actual G, data/reserved RE counts
and resource occasion, checks nominal N_RE agreement, and does not freeze
an infeasible grant. No MCS, rank, channel, or noise setting was altered.

Batch 76429 exited 0, log
logs/ssb_nominal_actual_separation_20260909_01.log:
testSSBPRBSymbolReservation,
testPDSCHNominalTBSReservationSeparation,
testPDSCHTRSExactReservation,
testSchedulerGrantConsistency,
testSchedulerExactGrantFinalization all passed.
The new regression proves a colliding slot-40 grant is rejected, a slot-43
grant is accepted without stale slot-zero reservations, and a frequency-
disjoint allocation can execute on slot 40. The main scheduler still needs
legal PRB/TDRA selection and explicit deferral publication; do not launch
the main scenario merely because the final allocation guard now works.

Read-only historical-run audit
logs/short12_uplink_evidence_recheck_20260909_02.json observed PRACH=1,
PUCCH=3, PUSCH=3, SRS=4 rows and failed 11 checks: seven PUCCH bit-string
length/XOR checks and four missing SRS RuntimeEvidenceSource checks. The
working code contains the prior literal-bit CSV preservation and SRS
producer-source repairs; no historical row was rewritten to pass.
The complete Msg1/Msg2/Msg3/Msg4/RRCSetupComplete capture audit passed its
sample-clock, physical-execution, power-reference and thermal-noise
arithmetic checks, explicitly not radio qualification.

Still OPEN: main-run UCI-on-PUSCH coverage, full TCI/QCL parameter transfer
and activation in beam application (not just identifier validation), full
carrier/SMTC RSSI scope, missing plot/export families and exhaustive fresh
main-run checks. Existing SSB-window RSSI has a 20-PRB/four-symbol scope and
must not be relabeled carrier RSSI. No blanket 3GPP/10-of-10 completion claim,
main restart, new FDD/25-dB campaign, testAll, commit, or output deletion.

Post-repair uplink batch 66714 is terminal, exit 0:
logs/uplink_after_nominal_actual_repair_20260909_01.log.
All seven focused checks passed: SharedPUSCHChannelArtifacts (TDD default),
SharedPUCCHLateFeedbackClock, SharedPUCCHLateFormat2Clock,
ReceivedSRSTimingEvidence, UCIBitVectorCSVPreservation,
ControlBeamStateValidation, HARQControlOccasionAliases.
The actual shared SRS/DCI/PUSCH/UCI component retained 3522 UL constellation
samples, RMS EVM 8.55060489662 percent, post-equalization SINR 21.333 dB,
received CFO estimate -15.292 Hz and applied timing correction 90 samples.
Its TAG/pathloss selector and HARQ bit inputs are declared component
fixtures, not simulated access or DL outcomes. It is not the main run and
does not prove main-run late-created UCI multiplexing or link adaptation.
Both late-feedback PUCCH cases also passed the actual shared-receiver power
ledger and CSV round-trip assertions.

Python measurement-plot and UL/SSB evidence checks reran: 72 passed.
Together with batch 76429 this verification sequence has 12 passing focused
MATLAB cases. This is not testAll or blanket waveform/3GPP qualification.
No MATLAB process remained after final terminal inspection, and scoped
git diff --check was clean. All existing edits and historical outputs are
preserved. The next implementation target remains main-scheduler legal
SSB-aware PRB/TDRA selection and exported resource/HARQ deferral decisions,
followed by the remaining UL/UCI, TCI/QCL, RSSI and publication gates above.

## Continuation: scheduler selection and retained deferral evidence

Previous goal turn classified as progress: actual allocation-clock repairs
and 12 focused MATLAB / 72 Python checks passed. No MATLAB process was live
at this continuation's initial authoritative inspection.

RR and PF now derive SSB/DM-RS frequency exclusions from the canonical data
occasion before selecting new-data or stored-HARQ resources. Data-only SSB
overlaps are retained for actual PHY rate matching. The shared contiguous
PRB selector does not bridge reserved gaps; it searches later runs and keeps
the existing configured minimum-PRB policy. A retransmission without a large
enough legal contiguous run remains pending without consuming TB/RV state.
PRB-underuse accounting uses actual unallocated sets rather than treating
skipped holes as transmitted resources.

Batch 94977, logs/scheduler_ssb_selection_20260909_01.log, exited 0:
SchedulerSSBResourceSelection, HARQRetransmissionSymbolBudget,
SchedulerGrantConsistency, PDSCHNominalTBSReservationSeparation passed.
With the authored TDD 25-PRB BWP, SSB leaves PRBs [0,1,23,24]. Both schedulers
reject bridging these two-PRB islands under a four-PRB minimum. An explicit
two-PRB UNIT-TEST policy produces legal grants on the islands; the main YAML
minimum, MCS, rank and reference-signal configuration were not changed.
Both schedulers resume on the later legal DL slot 42 with no stale SSB map.
These are scheduler/allocation tests, not a main waveform run.

Added production recording of HARQ deferrals even when CandidateTable is
empty. Actual RR/PF producer identities are retained, including future-K2
planning commits. Scheduler zero-based slot values are preserved in
SchedulerAbsoluteSlot0 while exported Slot is converted once to one-based.
SSB resource decisions are retained separately in
packet_flow/csv/scheduler_resource_exclusions.csv, explicitly configuration
resource evidence rather than waveform measurements. Snapshot state also
retains the resource table.

Read-only inspection found SystemLevelRunner discarded both DL and UL
scheduler info. It now uses the same recorder and retains decision/resource
tables in Details, MAT and CSV outputs, skipping empty artifacts. Its source
paths identify the actual csv/system_scheduler_* files rather than claiming
the coupled-runtime packet_flow path.

Post-SystemLevelRunner integration batch 42764 is active, log
logs/scheduler_resource_export_integration_20260909_01.log. Its first two
focused scheduler/deferral cases passed. It is checking the actual four-slot
geometry run and its persisted decision CSV, then both mandatory E2E
truth/proxy separation checks. Production dependencies stay unchanged until
that batch is authoritatively terminal.

Open verification includes main shared-run timing/SSB collision closure,
actual UL/UCI coverage, TCI/QCL application, full carrier/SMTC RSSI and the
existing missing output families. TDRA alternatives beyond the authored
allocation catalog are not invented by this PRB selector. Main FDD/25-dB or
long/impairment campaigns remain deferred; no testAll, commit, cleanup, or
historical result rewrite was performed.

Batch 42764 exited 1 after its first two cases passed. Actual geometry PHY
executed all four slots and served 384 bits, but the unchanged completion
assertion caught a decision-table recording error in the mixed slot:
StoredSymbolAllocation was a two-column table variable while generic union
padding created a one-column missing value for prior candidate rows.
SystemLevelRunner reported the scheduling error; it was not masked.

Converted the publication boundary to scalar StoredStartSymbol0,
StoredNumSymbols, AvailableStartSymbol0, AvailableNumSymbols fields while
retaining the original internal allocation arrays. HARQ deferral rows now
explicitly declare decision availability and their own truth-status label,
so mixed-table padding cannot mark an observed deferral unavailable. Added
a regression using actual initial-candidate rows followed by a deferral,
not merely a deferral appended to an empty table.

Repair rerun is MATLAB session 54595, log
logs/scheduler_resource_export_integration_20260909_02.log. The first two
focused cases passed, including mixed-table recording; actual geometry and
then both E2E checks are still running. Do not modify production until
authoritative terminal observation.

Additional HIGH-PRIORITY integrity finding from read-only inspection:
+sixgr/+phy/+pdcch/runPDCCHPhaseValidation.m localBeamEvidence (around 708)
constructs 12 rows with synthetic modulo-selected TCI/QCL/beam IDs, assigns
Decoded from not-blocked state and labels Status PASS with provenance
"configured_ssb_qcl_measurement". localGrantEvidence (around 732) similarly
constructs assignment digests and WaveformGenerated flags from loop variants,
not actual materializer/waveform execution. The function's non-FastTestMode
summary sets TruthQualified true. Actual callers include
ComponentQualificationPublisher and ComponentExecutionAdapter, plus
pdcchPhaseCase artifact-generation test. This is NOT proof that the main
55-slot run invoked that path, but these legacy phase artifacts cannot
qualify measured beam/QCL or received-grant behavior. Required follow-through:
replace those producers with actual executions and make missing evidence
fail qualification; never treat their present PASS rows as normative proof.
No production change to that legacy generator has yet been made.

## Follow-through: terminal integration and legacy phase containment

MATLAB session 54595 exited 0. All five focused cases passed in
logs/scheduler_resource_export_integration_20260909_02.log: scheduler SSB
resource selection, HARQ retransmission symbol budget, actual geometry
scenario exports, E2E FastVsTruth, and TruthPacketSemanticCampaign. The E2E
fixtures include FDD cases; no new main FDD campaign was launched. These
passes do not establish completion of the failed main TDD run.

Further inspection found PDCCH localIndependentEvidence also writes zero
mismatches and a manufactured DUT digest without comparing the DUT with
the referenced vectors. localTestSummary assigns every suite a pass.
PDCCH Phase-04 now throws unverified_phase_evidence before making an output
directory in BOTH FastTestMode and full mode. This contains false primary
evidence; it does not implement the missing phase producers. Existing phase
artifact-generation acceptance remains unsatisfied, not weakened.

The same read-only audit found PUCCH Phase-05 localIndependent hardcodes
family counts and zero mismatches, localWaveformEvidence hardcodes DMRS
CrossCorrelationPeak/IndependentMismatchCount zero and copies actual hop
positions into expected positions; localSpatial copies a selected beam
into AppliedBeamID without applying it. It now throws
sixgr:phy:pucch:UnverifiedPhaseEvidence before output publication. Real
PUCCH receiver trials in that function do not qualify those other fields.
This finding concerns legacy phase reports, not proof that the main run's
standalone or shared PUCCH waveforms were fabricated. Replacement producers
and full phase acceptance remain OPEN. A safety regression verifies both
publishers reject both execution modes without creating an output path.

Session 78128 exited 1: PDCCH quarantine passed, then the MU-MIMO scheduler
test correctly failed exact resource accounting because the enabled TRS
template inherited from master_sinr_sweep.yaml had row 2 and only symbol 4.
No HARQ lineage/strict-proxy pass is claimed for that interrupted batch.
Repaired the master template itself to row 1, one port, symbols [4,8], an
explicit two-slot burst and periodic offset 1; TRS remains disabled in the
base master and enabled by the original MU scenario authority. No TRS
disablement, fixed-MCS/rank adjustment, or grant-check relaxation was made.
Added actual TRS resource materialization to the MU scheduler regression.

Repair batch session 66616 is running with log
logs/pdcch_quarantine_scheduler_followup_20260909_02.log. Production files
remain frozen until its authoritative terminal observation. Main shared
clock/UL-UCI/TCI-QCL/RSSI/output qualification remains incomplete. No main
12/25-dB run, cleanup, commit, or historical artifact rewrite was performed.

Session 66616 exited 1 after both publisher-quarantine checks passed. The
new TRS resource was successfully materialized, but the test used isequal
against a row vector while YAML retained the same two values as a column.
Normalized orientation only in that assertion; the required symbols,
mapping row, port count and resource count are unchanged. Rerun session
90309 uses logs/pdcch_quarantine_scheduler_followup_20260909_03.log.

Normative RSSI review: TS 38.215 V18.4.0 section 5.1.3 defines NR carrier
RSSI using total received power over the specified measurement bandwidth
and OFDM symbols, with SMTC/measurement-gap conditions. The current
SSBWindowRSSIPerReceiveAntenna_dBm is deliberately a scoped SSB-window
measurement, not proof of that complete carrier measurement contract.
Source: https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf
Section 5.1.4 separately confines CSI-RSSI to configured CSI-RS occasion
symbols. Receiver diversity/combining reference must be consistent with
the associated RSRP. Full runtime measurement-window integration and
CSV/PNG closure for these quantities remain OPEN; no values were invented.

Session 90309 exited 1 after publisher quarantine and MU-MIMO grouping
PASSED. It then exposed an unrelated stale scheduler-lineage fixture:
requested PDSCH [2,12] was absent from its active DCI TDRA configuration.
Authored the fixture's matching [index,start,count,K0] rows: [0,2,12,1]
for candidate lineage and [0,2,12,0] for its existing same-slot runtime
export case. Production DCI validation is unchanged. These are explicit
unit-test timing configurations, not scenario policy changes or a main run.
Session 38427 now runs lineage and strict-proxy guards in
logs/scheduler_harq_lineage_followup_20260909_01.log. No strict-proxy result
is claimed until that case actually executes.

Session 38427 exited 0: testSchedulerHARQStateUnblockAndLineage and
testStrictProxyGuards PASSED, including actual runtime scheduler decision
CSV publication. All focused cases attempted in this continuation now have
passing reruns (nine distinct cases when including the resumed five-case
integration batch). This is not testAll or complete phase qualification.
The legacy PDCCH/PUCCH artifact-generation acceptance still intentionally
fails at the evidence quarantine until replacement producers exist. No
MATLAB batch remains active from this continuation. Full goal remains
ACTIVE; main TDD execution and all requested closure claims remain pending.

## Executed PUCCH independent comparisons (next continuation)

Previous goal turn classified PROGRESS: configuration/fixture repairs,
qualification containment, and nine focused cases with passing reruns.
Revalidated no live MATLAB worker before editing this continuation.

Replaced the legacy hardcoded independent-family counters in
runPUCCHPhaseValidation with PUCCHIndependentVectorComparison. The adapter
executes 12 available component-vector families, joins input/reference rows
by unique CaseID, verifies file hashes and row counts against the manifest,
and compares reference fields to actual component outputs. Expected values
are not passed to the DUT adapter. Field detail includes expected/observed
values, absolute numeric error, supplied tolerance, DUT-result digest and
input/reference hashes. Unsupported observations are NOT_EXECUTED and make
the family INCOMPLETE. No DMRS/hopping vector counts are invented for files
absent from the pack. These are bounded component checks, not waveform
measurements, received beam evidence, or full standard qualification.
The phase is wired to publish the detailed comparison table once its other
producers are repaired; its quarantine remains active. Its aggregate gate
also now considers every table's Status, not merely waveform failures.

Frozen-pack verification initially failed one PRI reference hash. Read-only
git history showed commit 7a230d25 replaced four SPEC_FORMULA placeholders
with numeric ordinals but left the manifest unchanged. Added independent
Python resource-list partition checks for every PRI reference using
TS 38.213 V18.8.0 section 9.2.3, then corrected the manifest hash and oracle
classification to reflect the actual committed references. No expected
ordinal was changed. Python verifier now passes all 31 manifest files / 4271
declared pack rows. This is file/floor validation, not execution of 4271
radio trials. Normative source:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

## 2026-09-09: received PUSCH occasion versus scheduler delivery

The cross-slot defect above is now repaired in both HARQ-ACK and CSI
consumers. Shared execution validates the retained received PUSCH timing,
RNTI, frozen grant identity and sample clock, and binds the reservation to
that transmission's original occasion. Actual scheduler delivery remains
at CurrentSlot; the clock is not rewound. HARQ traces retain separate
PUSCHUCITransmissionSlot and PUSCHUCIDeliverySlot. Missing fields in older
component traces initialize to NaN, not implicit zero.

Session 36989 exited 0, log
`logs/uci_cross_slot_delivery_20260909_01.log`, marker
UCI_CROSS_SLOT_DELIVERY_BATCH_PASS. Passed actual shared TDD
testSharedPUSCHLateUCIDelivery (coincident SRS), the immediate TDD
testSharedPUSCHChannelArtifacts case, and testSchedulerGrantConsistency.
The late case transported actual isolated-DL ACK/NACK bits on coded shared
PUSCH in slot 10 and applied them at scheduler slot 11, with CSV round-trip
checks. This is an explicit receiver-to-scheduler delay component, not a
claim that the physical channel tail caused a one-slot delay.
Artifact root: `C:/Users/anup0/AppData/Local/Temp/tp1b7d5849_f24a_484c_9c67_4c7a09d5dfff`.

A separate measured-CSI component passed (session 72264, terminal exit 0,
`logs/pusch_measured_csi_late_delivery_20260909_01.log`).
Its YAML overlay authors the existing feedback-delay policy so an actual
slot-7 isolated CSI-RS measurement is due on slot-10 PUSCH. No replacement
CQI/PMI/RI vector is constructed. Raw/resolved YAML, successful config
validation, seed, environment and git/worktree metadata are retained with
the component artifacts. Its verified check is actual HARQ/CSI waveform
transport plus slot-11 delivery; it does not qualify access, physical
QCL/TCI, full processing budgets or the main short run. The goal stays active.

Its actual persisted CSI source slot/due slot/delivery slot are 7/10/11,
CQI 15, RI 2, PMI 1, six decoded CSI bits, CSIUCIDecodeOk=1,
CSIUCITransport=pusch_decoded. PUSCH CRC passed with 3522 paired symbols,
EVM 8.62254422951 percent and post-equalization SINR about 21.262 dB.
Artifact root: `C:/Users/anup0/AppData/Local/Temp/tp523c14a7_81d5_4cfc_89be_72f1c012a762`.
The isolated DL source uses the existing fixed connector/noise fixture;
its measured CSI SINR is 81.5876588661 dB, NOT the inherited 12-dB label
and NOT the shared UL's SINR. This proves transport/value retention only,
not the main run's absolute CSI power or target SINR accuracy.

The generated PUSCH EVM PNG was visually inspected and its CSV first rows
inspected: actual RMS/peak receiver errors, no fitted reporter payload gain,
explicit partial-checkpoint label. First symbol: 287 pairs, error energy
1.9102300363904317, reference energy 287, RMS 8.15834161171 percent and
peak 21.60444673796 percent. The canonical HARQ TB identity remains a
separate open lineage issue; a local trial ID is not full HARQ identity.

After this pass, CSI control traces also gained distinct original PUSCH
transmission and actual delivery columns. The delayed tests now exercise
older trace schemas lacking these columns and reject a standalone PUCCH
execution label for CSI delivered on PUSCH. Focused regression batch
session 96203 exited 1: the stronger check found no CSI reservation trace
at all (not a timestamp rounding issue). The pending CSI row and decoded
payload existed, but only two HARQ reservation rows survived in CSV.
`overlappingPUCCHReservations` constructed the real configured CSI resource
plan in a local value-state copy and returned only overlap IDs/evidence;
the caller discarded its trace-table update. `setCSIGrantPUSCHReservation`
and completion then silently returned when that CSI row was absent.

Repair: the planner now returns state as a third output, and the actual
PUSCH-binding caller retains it before freezing CSI transport. Read-only
collision probes may still ignore this value. Shared CSI binding/completion
now reject a missing reservation instead of silently skipping its evidence.
No row is reconstructed from successful decode or copied from HARQ results.
The configured CSI resource plan is retained before waveform preparation.
This generic state/value fix has no TDD/FDD branch.

Session 6224 exited 0, marker PUSCH_CROSS_SLOT_REGRESSION_BATCH_PASS,
`logs/pusch_cross_slot_regression_20260909_02.log`. All six passed:
testSharedPUSCHLateCSIDelivery, testSharedPUSCHLateUCIDelivery,
testSchedulerGrantConsistency, testStrictProxyGuards, testLinkExportPipeline,
testArtifactIntegrity. Final CSI component root:
`C:/Users/anup0/AppData/Local/Temp/tp095c9866_2e17_41a0_bb65_c143cc6a298f`.
CSV has exactly two real HARQ reservations plus one actual configured CSI
reservation. All three retain transmission=10, delivery=11,
MultiplexedOnPUSCH=1, GrantExecutedFlag=0, RuntimeStateUpdated=1.
The CSI-specific payload is six bits; its CRC is explicitly NaN (no CSI
CRC for this short payload), not promoted to a fictitious CRC pass.

Session 79374 exited 0 after both repository-required E2E evidence regression
fixtures passed, log `logs/pusch_state_handoff_e2e_20260909_01.log`, marker
PUSCH_STATE_HANDOFF_E2E_REGRESSION_PASS. Seed checks 111/303/11/22/33 passed.
Existing fixture modes remain unchanged; they are not a main TDD/FDD scenario.
This makes eight distinct final-patch focused/E2E tests passed. Full
testAll/main-run qualification is open. No semantic edits followed this batch.

MATLAB 80237 exited 0, log logs/pucch_independent_comparison_20260909_01.log.
Three tests passed: independent comparison safety/mutations, PRI numeric
resolution, and both phase-publisher quarantines. Actual adapter result:
6932 executed field comparisons, 0 mismatches, 638 NOT_EXECUTED fields
(128 UCI descriptive Order fields, 350 format WaveformExpected fields,
160 collision transmission-count/multiplex-execution fields). Mutated
reference bits, leading-zero/length changes, shuffled row order, missing
cases, and duplicate IDs are tested. The safety-test PASS does NOT override
the reported incomplete families or qualify the phase.

Additional audited legacy labels remain wrong and quarantined:
localPower copies expected power into MeasuredWaveformPowerdBm; localCollision
hashes case-name strings as before/after state; localCSI copies observed bits
into ExpectedBits. Their replacement must retain actual source evidence.

Found and repaired a separate production UCI validation defect:
PUCCHUtil.bits cast numeric input to int8 before checking binary membership,
allowing fractional values to round to 0/1. It now rejects nonnumeric,
nonreal, nonfinite, or nonbinary values BEFORE conversion, preserving valid
numeric/logical/text bit sequences. New regression covers fractional,
nonfinite, complex and cell input plus the typed report/serializer boundary.
Focused rerun 13489 is active in
logs/uci_binary_and_comparison_20260909_01.log; production remains frozen
until terminal observation. No main simulation or phase qualification is
claimed complete, and no historical results were rewritten.

Session 13489 exited 0. Four tests passed after the pre-conversion UCI
validation repair: malformed binary input rejection, independent comparison
safety, leading-zero UCI CSV preservation, and actual shared PUCCH late
feedback clock reception. The latter also verified the receiver power ledger
and CSV round-trip. Independent comparison counts remain 6932 executed,
zero mismatches and 638 explicitly unverified; these were not converted to
PASS. Next focused session 66187 runs testSharedPUSCHChannelArtifacts in
its default TDD mode, log logs/uci_binary_shared_pusch_20260909_01.log.
This fixture executes shared SRS, received UL DCI and coded PUSCH/UCI but
uses explicit initial TAG/pathloss selector and HARQ-bit test inputs, so it
does not prove main-run access, full link adaptation or DL-created ACKs.

Session 66187 exited 0. testSharedPUSCHChannelArtifacts (TDD) PASSED:
actual shared SRS -> decoded UL DCI -> coded PUSCH with decoded two-bit
HARQ-ACK; TB CRC passed, UCI content matched and persisted channel evidence
validated. Actual received UL constellation: 3522 samples, RMS EVM
8.55060489662%, post-equalization SINR 21.333 dB, received timing estimate
90 samples, CFO estimate -15.292 Hz. These are component observations,
not nominal-12-dB main-run measurements. Log includes preserved temporary
artifact roots. Seven distinct focused tests passed this continuation,
plus the Python frozen-pack verifier. No testAll/full qualification or
fresh main TDD run is claimed. No MATLAB job remains active from this turn.

Read-only review also confirmed PUSCHUCIPayload, PUSCHUCIMultiplexer and
PUSCHModulator already compare numeric values before the int8 conversion;
the fractional-bit repair was therefore confined to the confirmed PUCCH
utility defect, not a speculative rewrite of all UL coding.

## 2026-09-09 continuation: actual PUCCH power and explicit figure bindings

Confirmed standalone PUCCHTransmitter normalized desired transmit power
over the entire slot including inactive silence. This boosts active-symbol
power by the inverse duty cycle. The shared runtime already used an explicit
active-symbol reference; the standalone transmitter now uses that same
baseband reference and exports active-symbol power separately from slot
average. The measurement sums power across ports, uses declared allocated
useful OFDM samples (not energy-detected support), and records the reference
domain, sample count, waveform scaling and sqrt_mW amplitude unit. Numerology
and PRB count in typed power control must match the actual carrier/resource.
PUCCHFixtureFactory now derives Mu from the actual carrier SCS.

This is a baseband power-reference repair, NOT RF time-mask certification.
TS 38.101-1 V18.8.0 section 6.3.3 defines separate ON/OFF/transient measurement
requirements for slot/subslot transmissions. A useful-FFT-sample measurement
does not itself implement those RF measurement masks:
https://www.etsi.org/deliver/etsi_ts/138100_138199/13810101/18.08.00_60/ts_13810101v180800p.pdf

PUCCHPowerVectorEvidence replaces the legacy copied expected-power column
with 48 actual waveform executions, driven by frozen independently checked
power-control operands and explicit pucch_power_waveform.yaml component
profile. Output includes actual measured power, independent expected power,
numeric tolerance, actual assignment/resource/power state JSON, waveform and
profile hashes, sample rate and sample count. Evidence remains explicitly
component_power_control_calibration_not_main_run, not access or scheduling
qualification. The phase quarantine remains in force for other known issues.

Session 11501: testPUCCHTransmitActivePower PASSED (formats 0-4, SCS 15/30,
direct sample-index reference, and mismatched Mu/MRB rejection). Its next
test executed all 48 waveforms successfully but failed a CSV assertion that
converted parsed doubles through display-formatted string(double). Raw CSV
retained full precision; the test now compares parsed doubles directly.
No arithmetic tolerance was relaxed.

Session 32437 exited 0, logs/pucch_active_power_evidence_20260909_02.log:
testPUCCHPowerVectorEvidence, testPUCCHMeasuredReferencePowerControl,
testPUCCHReceivedNoiseEstimation and testSharedPUCCHLateFeedbackClock PASS.
Maximum absolute error across 48 measured waveforms versus frozen power
references: 8.11795075606e-13 dB. Actual CSV retained at
C:/Users/anup0/AppData/Local/Temp/tpd82c4196_1fa9_4e52_9854_e9a5d875880e/pucch_power_control.csv.
Receiver tests decoded formats 1-4 after retained AGC/ADC; late feedback test
verified actual shared-clock reception and persisted receiver power ledger.

A separate exporter defect was confirmed: writeSemanticFigure selected
arbitrary columns, encoded text categories as numbers, duplicated series
and repeated points to satisfy minimum chart counts. Removed these paths.
Only the explicitly implemented power chart is currently supported by this
writer; unsupported figure bindings now fail rather than manufacture plots.
The three named fields are RequestedPowerdBm, AppliedPowerdBm and
MeasuredWaveformPowerdBm. X is independent CaseID in CSV row order, with no
connecting lines or false convergence/time interpretation. Contract and
dashboard registry now name this actual x-axis. Real sample counts and
source/PNG hashes are audited; short, incomplete or incompatible sources
must fail. Other PUCCH phase/impact plots need actual bindings and remain
OPEN. Session 97839 runs the focused figure/negative-input test plus phase
quarantine test; do not claim these passed until terminal observation.

No fresh main TDD or FDD run, testAll, full UL/QCL/TCI/RSSI qualification,
historical artifact rewrite, cleanup or commit occurred in this continuation.

Session 97839 exited 0: power figure positive and seven negative cases PASS,
and both phase-quarantine guards PASS. Visual inspection found inherited
dark axes with pale labels on a white canvas; explicit white axes/black
labels now make the export independent of MATLAB's UI theme. Session 26533
reruns the figure and required E2E truth/proxy and packet-semantic guards.
Its figure test passed and the corrected PNG was visually inspected:
C:/Users/anup0/AppData/Local/Temp/tp1cc4d4a8_07e2_4456_9306_4883bdcea21c/pucch_power_control_convergence.png.
This chart contains actual independent requested/applied/measured power
points, not a time convergence experiment. E2E tests use their existing
FDD fixtures; they are not a new main FDD scenario or 12-dB TDD evidence.
Full-worktree git diff --check exited 0 (line-ending warnings only).

Read-only QCL follow-up confirms a remaining integration concern:
RASIPDSCHContext.localIntegrationContext locally creates Activated=true,
SourceReferenceSignal=PDSCH-DMRS and QCLTypes=A|D with an identity-procedure
precoder. PDSCHReceiver computes integrationBinding then returns it as
metadata; there is no direct ReceiverQCL consumer elsewhere in +sixgr.
This demonstrates validation/metadata plumbing, not proof that measured
QCL source properties or a received TCI activation select the RX spatial
filter. Do not equate testPDSCHQCLStatePropagation or hash binding with
physical beam application. Trace applicable common-procedure QCL rules,
actual source RS identity/availability, TX/RX spatial filters and control
activation timing before changing this boundary. No speculative replacement
or production mutation was made while session 26533 was alive.

RSSI follow-up: measureCSIRSPhysicalResource retains per-antenna physical
nrCSIRSMeasurements results and resource/symbol/bandwidth provenance.
Separate legacy measureULLinkState fields called CSI_RSSI_dB are computed
from UL reference grids; these must not be promoted to UE CSI-RSSI/dBm
merely because names look similar. Main-run window/source bindings and
complete NR-carrier/SMTC reporting remain open as previously recorded.

Terminal observation: session 26533 exited 0. Corrected figure validation,
testE2E_FastVsTruth and testE2E_TruthPacketSemanticCampaign all PASS;
logs/pucch_power_figure_evidence_20260909_02.log contains both E2E terminal
PASS markers. All three packet-semantic seeds checked nonempty actual DL
and UL grant/HARQ evidence with finite receiver CRC outcomes. These remain
the existing regression fixtures, not a fresh main 12-dB TDD run.
verify_pucch_vector_pack.py also passed (31 manifest files, 4271 declared
vector rows, zero verifier failures). Nine distinct focused MATLAB tests
passed this continuation, including the earlier active-power test and
phase-quarantine safety test. No MATLAB job from this continuation remains
active. Broad/full qualification, main-run late UCI integration, measured
QCL/TCI application and complete RSSI/artifact reporting remain OPEN.

## 2026-09-09 continuation: runtime UCI ownership

Previous continuation classified PROGRESS: actual PUCCH power normalization,
48 waveform-backed records, explicit chart bindings, nine focused tests.
No live MATLAB worker was present at this continuation's initial check.

Main shared UCI review located the existing encoded-waveform protection:
multiplexDueHARQACKOnPUSCHImpl calls validateEncodedSharedPUSCHUCI before
and after ledger reconciliation, and validatePreparedPUSCHUCI compares the
typed payload plus HARQ/CSI source identities against retained TX evidence.
Do not claim this protection is absent or duplicate it. Full main-run late
feedback timing qualification is still not demonstrated by that guard alone.

Confirmed separate ownership defect: both HARQ/CSI reservation and PUCCH
collision exclusion matched a grant to feedback by UEIndex OR RNTI. Equal
radio identifiers could override distinct runtime UE owners. Added a
regression using distinct UEIndex values and equal RNTI; session 59923
exited 1 in logs/uci_runtime_ue_ownership_20260909_01.log with the assertion
that another UE must not acquire the first UE's HARQ-ACK. The failure is
an actual production reducer result, not a manufactured PHY trial.

Added matchRuntimeUCIOwner and integrated it into HARQ matching, CSI
matching and collision exclusion. Runtime UEIndex is now authoritative;
missing/nonfinite/fractional/nonpositive ownership fails explicitly rather
than being inferred from RNTI or a configured drop-order offset. This does
not change coded bits, PHY power, duplex profile or allocation policy.
Added HARQ and CSI regressions ensuring another UE cannot consume feedback
or lose its PUSCH through RNTI equality, plus malformed-owner tests.
Session 34594, logs/uci_runtime_ue_ownership_20260909_02.log, is running the
owner, HARQ-feedback, CSI-source-authority and grant-cache regression set.
Production dependencies remain frozen until terminal observation.

Additional unresolved policy defect found during the same trace:
excludeULGrantsCollidingWithPUCCHImpl currently uses same-slot/UE presence,
not actual symbol-time overlap; the multiplexing helper also groups by due
slot/UE before considering physical intervals. TS 38.213 V18.8.0 section
9.2.5, page 142, distinguishes nonoverlapping PUCCH/PUSCH transmissions
from overlapping resources requiring UCI multiplexing, with timing and
priority conditions. Therefore same-slot presence is not a complete NR
collision test. This needs an allocation/clock-bound integration repair,
not a diagram-only or blanket same-slot suppression adjustment. Preserve
symbol/numerology/TA and control-processing-time authority when fixing it.
Source checked directly:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

No main 12-dB restart, 25-dB run, long run, result cleanup or commit has
occurred. The ownership regression does not prove multi-cell HARQ entity
namespacing, common-procedure QCL/TCI application or full scheduler timing.

Session 34594 exited 0: testRuntimeUCIOwner,
testLLSPUSCHHARQACKRuntimeFeedback,
testCoupledTruthCSIReportSourceAuthority and testGrantCacheLiveUCIAuthority
PASS. The regression that failed before the patch now verifies exact
cross-UE HARQ ownership; CSI ownership and collision-exclusion checks also
pass. Session 10087 is running testSharedPUSCHChannelArtifacts (default TDD),
testE2E_FastVsTruth and testE2E_TruthPacketSemanticCampaign sequentially in
logs/uci_owner_shared_regressions_20260909_01.log. The latter two retain
their existing regression fixture profiles, not a new main FDD run.

Further read-only trace found a remaining malformed-input entry point:
CoupledTruthRuntime.resolveGrantExpectedUCIBits, called by
buildTrialContextFromGrantImpl, uses int8(logical(raw(:))) on legacy UCI
aliases. That can convert malformed nonbinary values before downstream
typed-payload validation. The previous PUCCHUtil.bits fix does not cover
this separate conversion. Replace it with strict pre-conversion validation
and test the real trial-context boundary, including conflicting aliases;
do not merely test the already corrected utility again. No dependency
edit was made while session 10087 was live.

Session 10087 exited 0 after terminal finalization. All three tests PASS:
testSharedPUSCHChannelArtifacts (TDD), testE2E_FastVsTruth and
testE2E_TruthPacketSemanticCampaign. Actual TDD component received 3522
PUSCH constellation samples, RMS EVM 8.55060489662%, post-equalization SINR
21.333 dB; TB CRC and the declared two-bit HARQ-ACK content checks passed.
Retained component root:
C:/Users/anup0/AppData/Local/Temp/tp22c282fb_688a_4ad6_8750_a1ac538319a1.
Constellation evidence root:
C:/Users/anup0/AppData/Local/Temp/tpf8427aba_1f50_4d29_82c6_dfb9e06945e1.
These are actual component measurements, not main nominal-12-dB observations
or proof of DL-created ACKs in this waveform fixture. Both E2E regressions
retained their original assertions and the three packet-semantic seeds
completed. Seven distinct focused MATLAB tests passed this continuation;
no full testAll or fresh main simulation was run. No MATLAB worker remains
active. Next work: strict legacy trial-context UCI validation and the
allocation/processing-time-bound PUCCH/PUSCH overlap policy, followed by
main short TDD qualification only when its required causal repairs pass.

## 2026-09-09 continuation: strict trial-context UCI authority

Previous turn classified PROGRESS: reproduced and fixed cross-UE UCI
ownership, with seven focused tests including actual shared TDD UL samples.
No MATLAB process was live at this continuation's first authoritative check.

Added testTrialContextUCIBinaryAuthority at the actual UL
CoupledTruthRuntime.buildTrialContextFromGrant entry point. A valid numeric
HARQ vector first passed, then a fractional legacy UCI input was accepted
instead of rejected. Session 74929 exited 1 in
logs/trial_context_uci_authority_20260909_01.log, reproducing the defect.
The test's grants are explicitly component metadata, not transmitted PHY
or measured DL-created feedback.

Replaced int8(logical(raw(:))) with resolveGrantHARQACKBits. All populated
legacy HARQ aliases are validated as finite real binary vectors or scalar
binary strings and must agree. Bit strings retain zeros; they are not
converted through character truthiness. Typed PUSCH HARQACK is authoritative
and checked against legacy aliases; CSI Part 1/2 does not become HARQ-ACK.
Empty legacy aliases are unpopulated, while a typed payload with no HARQ
cannot be overridden by a nonempty legacy HARQ alias. Live input is checked
before grant normalization/TB generation, then the resolved current-occasion
snapshot is checked again after HARQ merging. No coded bits are guessed or
replaced; inconsistent/malformed input fails explicitly.

The regression covers all four aliases, fractional/out-of-range/nonfinite/
complex/cell/matrix/string-array inputs, valid numeric/logical/char/string
sequences, conflicting aliases, typed-only HARQ and CSI-only payloads.
Session 42858 runs this plus HARQ-feedback, CSI-source-authority and shared
grant-preparation-clock regressions in
logs/trial_context_uci_authority_20260909_02.log. Production dependencies
remain frozen until terminal observation. No main restart or full
qualification claim has been made.

Session 42858 exited 1 after three PASS results: trial-context binary
authority, HARQ-feedback and CSI-source authority. Its final clock test
failed because its legacy PDSCH allocation overlapped 126 reserved SS/PBCH
DM-RS REs in absolute slot 0. Production validation was not changed.
Session 97860 also failed after an attempted fixture move to absolute
slot 1, which is still occupied by the configured burst. The final fixture
uses absolute slot 2 and explicitly verifies ssbPRBSymbolReservation is
empty before constructing the grant. It checks a nonzero future metadata
target while the physical owner remains at sample 0, and resets only the
test's slot label to the owner's actual slot before advancing its timer.
No waveform samples or grant results are invented by this metadata test.

Session 55206 exited 0: testSharedGrantPreparationClock and
testLLSHARQReplayCurrentGrantAuthority PASS. The latter needed no fixture
or production changes in this continuation. These results distinguish the
confirmed SS/PBCH fixture issue from speculation about stale HARQ inputs.
Logs: logs/trial_context_uci_replay_20260909_01.log (failed slot-1 fixture)
and logs/trial_context_uci_replay_20260909_02.log (both tests passed).

Added an assertion that rejected UCI consumes no payload/channel RNG state.
Session 53334 runs that strengthened regression, actual default-TDD shared
SRS/DCI/PUSCH/UCI, and the two required E2E truth/export-semantic checks in
logs/trial_context_uci_shared_regressions_20260909_01.log. Do not mark this
batch passed before its terminal result. No broad testAll, main TDD/FDD
campaign, cleanup or commit has been performed.

Terminal observation: session 53334 exited 0; strengthened trial-context
UCI validation, actual TDD shared SRS/DCI/PUSCH/UCI, testE2E_FastVsTruth and
all three testE2E_TruthPacketSemanticCampaign seeds PASS. The runtime
input test checks 43 malformed/conflicting cases and valid binary/typed
representations, including unchanged RNG state on rejection. Together
with the earlier successful focused sets, eight distinct MATLAB tests
passed this continuation. Failed fixture attempts and the original UCI
reproduction remain in their separate logs; no assertion was weakened.

Actual shared UL component measurements remain 3522 constellation samples,
RMS EVM 8.55060489662%, post-equalization SINR 21.333 dB; TB CRC and the
declared two-bit UCI check passed. Artifact root:
C:/Users/anup0/AppData/Local/Temp/tpd85f8720_5068_47ba_9e83_5b32b75d496b.
Constellation root:
C:/Users/anup0/AppData/Local/Temp/tpb4028be9_d77c_48cb_b39e_3917e1029f72.
These are unchanged component-fixture observations, not a fresh 12-dB run.
No MATLAB worker remains active. Full main qualification, actual-time
PUCCH/PUSCH collision integration, QCL/TCI physical application and complete
RSSI/artifact coverage remain open. Next priority is replacing blanket
same-slot UCI collision decisions with actual allocation/processing-time
authority without weakening the encoded-waveform or control-timing guards.

## 2026-09-09 continuation: resource-time PUCCH/PUSCH overlap

Confirmed original failure: session 76487 / log
`logs/pucch_pusch_symbol_overlap_20260909_01.log` terminated with the new
nonoverlapping-symbol assertion. The legacy runtime transferred or suppressed
same-UE PUSCH solely on a same-slot feedback identity, even when its allocation
ended before PUCCH began.

Implemented one shared overlap query in both UCI binding and standalone-PUSCH
suppression. It uses the existing typed PUCCH resource planner also consumed by
actual transmission, including combined HARQ/CSI payload resource-set changes.
The planner now has a strictly sample-free internal PlanOnly path; materializing
power/spatial state and waveform execution remain separate. Future scheduling
views may plan resources but still cannot execute or commit PHY observations.
PUSCH requires its explicit scheduled/frozen allocation; inconsistent frozen
allocations or timing decisions fail rather than silently falling back to a
full-slot assumption. Unsupported cross-carrier/BWP/serving-cell timing contexts
fail explicitly. No FDD/TDD branch or fixed scenario symbol range was added.

Intervals use AbsoluteTime's exact CP-OFDM Tc boundaries and half-open overlap.
Suppression evidence retains both start/end tick pairs and labels the domain
`scheduled_common_ul_carrier_cp_ofdm_symbols`. These are scheduling boundaries,
NOT measured transmitter sample timestamps or proof of N1/N2 processing-time
eligibility. Common-UE same-carrier timing is the supported comparison domain.

TS 38.213 V18.8.0 section 9.2.5 (page 142) distinguishes nonoverlapping PUCCH
transmissions from UCI multiplexing on overlapping PUSCH, subject to its other
timing conditions:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

Session 53058 / `_02.log`: HARQ regression PASS; CSI regression reached its
combined feedback fixture and rejected inconsistent CC/BWP (HARQ 1/1 versus
CSI/PUSCH configured 0/0). Fixture identities now come from resolved config;
production validation was not weakened. Session 41048 / `_03.log` exited 0:
HARQ and CSI regressions PASS, including separate/touching symbols, missing
PUSCH allocation rejection, CSI nonoverlap, and three-bit HARQ selecting a
format-2 resource with a different configured start symbol from the original
one-bit reservations. Those are declared scheduler reducer fixtures, not newly
measured DL ACKs or main-run waveform evidence.

Added future-planning/RNG preservation and foreign-BWP rejection checks. Session
45086 runs those tests plus actual default-TDD shared CSI PUCCH, combined
CSI/HARQ PUCCH, shared SRS/DCI/PUSCH/UCI and both E2E truth/export guards in
`logs/pucch_pusch_shared_overlap_regressions_20260909_01.log`. Its outcome must be
recorded only after terminal observation. Production and test sources are frozen
while this MATLAB process is alive.

Remaining scope is explicit: no fresh nominal-12-dB main-run qualification;
combined-UCI earliest-symbol N1/N2 processing-time closure remains open;
cross-carrier/mixed-numerology and multiple-PUSCH selection are not qualified.
The existing PUCCH physical-occasion grouping still keys on UE/cell/CC/BWP/slot,
so independent nonoverlapping PUCCH resources within that key require a separate
grouping/procedure audit; reusing that planner does not prove the wider feature.
Physical QCL/TCI, full NR RSSI window/source coverage, the previously quarantined
phase evidence, and missing/incorrect main-run artifacts remain open. No old
result was rewritten, no main TDD/FDD campaign or testAll launched, and no
cleanup/commit performed.

Follow-up terminal results: 45086 exited 1 before waveform tests because the
hand-authored HARQ fixture's serving cell (1) differed from its initialized
random-drop serving cell. The fixture now declares its intended serving cell,
as do its slot-entry clone and the existing single-cell CSI fixture. Session
95500 exited 1 in the newly added future-view test: that manual source lacked
the sweep/calendar fields normally supplied by startSlot. Added the explicit
test calendar; no production clock fallback was introduced.

Main caller audit found another instance of the same production defect:
localScheduleCoupledFutureULGrantsFromDLControl zeroed ULQueueBits for every
same-slot PUCCH UE when UCI multiplexing was disabled. Removed that blanket
eligibility rewrite. Concrete candidates are now checked after SRS reservation
and before PDCCH qualification; only overlapping uncommitted HARQ grants are
cancelled. The exact retained-candidate mask is returned by the common overlap
filter. Nonempty decision rows are retained in ControlTrials.ULControlResourceDecisions
and wired to ul_control_resource_decisions.csv with a pre-DCI stage and explicit
scheduled-resource source, never a fabricated transmission/CRC observation.
The reducer test checks the mixed retained/deferred mask and the main caller's
pre-DCI integration location; this is not a substitute for a fresh main run.

Session 21721 is the current single MATLAB batch, log
logs/pucch_pusch_shared_overlap_regressions_20260909_03.log. It includes the same
TDD shared waveform/E2E checks plus first-SRS pre-DCI ordering and future-UL
planning causality. Wait for its terminal result before editing dependencies or
claiming those checks passed. No main run was started.

Terminal observation: session 21721 exited 0. Eight distinct MATLAB tests
passed, with both TDD CSI-only and combined CSI/HARQ variants executed. Actual
PUCCH power/receiver ledger CSV round trips passed. Shared SRS/DCI/PUSCH/UCI
retained 3522 receiver constellation samples and RMS EVM 8.55060489662%, with
the declared two UCI bits decoded by the component receiver. First-SRS pre-DCI,
future-UL planning causality and both E2E integrity guards passed. The E2E guard
tests use their existing internal reference scenarios; they are not a new
user-requested nominal-12-dB TDD or FDD main run.

Inspected the actual pusch_evm_per_symbol.png and independently recomputed all
12 per-symbol CSV buckets using error/reference energies and peak error power.
Max RMS and peak discrepancies were both 0 at parsed double precision;
aggregate RMS was 8.55060489661762%. The image contains the expected 24 RMS/peak
points and an explicit partial-checkpoint label. SFN/cell_id metadata is blank
in this component artifact and remains an identified provenance gap, not an
excuse to inject assumed identities. Its received_pusch.csv has SFN=1 and
CarrierNFrame=0: the frame-index/SFN semantics need tracing before either is
used to fill those blanks. Artifact root:
C:/Users/anup0/AppData/Local/Temp/tp3a73f2fd_e3af_4a61_970b_409b5d713bc5.
The shared PUSCH trial/channel root is
C:/Users/anup0/AppData/Local/Temp/tp8cf875e4_b820_4100_8972_ffd3fef57b24.

Added a full writeTables CSV round-trip check for the new resource-decision
table, explicitly tagged declared_scheduler_resource_component_fixture.
Session 21503 exited 1 because the old manual reducer setup overwrote the
initialized MultiUser struct with only Enabled, omitting RNTIStart required by
the existing exporter. Removed that incomplete overwrite rather than weakening
the exporter. Session 17948 / logs/pucch_pusch_overlap_export_guards_20260909_02.log
is now running the strengthened HARQ test, changed PUCCH waveform regression,
scheduler grant consistency, link export pipeline, artifact integrity and E2E
artifact preservation. Its decision-CSV round trip and HARQ test have passed;
wait for terminal observation before claiming the full final set passed.
Main qualification remains open.

Final continuation results: session 17948 completed the strengthened HARQ
regression and exact decision-CSV round trip, then exited 1 in the older PUCCH
fixture. Its scheduler trace had generated reservation IDs, but the pending
feedback rows still contained empty IDs. Linked those pending rows to their
actual scheduled trace identities; the production missing-identity guard was
retained. Decision CSV fixture root:
C:/Users/anup0/AppData/Local/Temp/tp58d936a5_a3c6_4c8d_bbe1_f04f9c296680.

Session 61637 exited 0 after executing these five tests through
executeRegressionTest: testLLSPUCCHWaveformFeedback,
testSchedulerGrantConsistency, testLinkExportPipeline, testArtifactIntegrity,
testOrganizeRunResults_E2EArtifactPreservation. These test functions are silent
on success; logs/pucch_pusch_overlap_export_guards_20260909_03.log is empty, so
the authoritative completion evidence is the terminal exit-0 tool result and
the asserted test wrapper, not invented PASS lines. No MATLAB worker remains.

Thirteen distinct focused MATLAB tests passed across the successful batches
and explicitly observed completed portions of earlier batches; shared CSI was
also checked with and without HARQ. The two production fixes are resource-time
UCI/collision decisions and removal of the main scheduler's blanket same-slot
queue exclusion, including pre-DCI cancellation of overlapping candidates and
honestly labeled decision export. The result-integrity workflow required exact
CSV round trips and preservation of unavailable fields/proxy separation; it did
not authorize filling unknown values or declaring the main simulation qualified.
No testAll, fresh 12/25-dB main run, cleanup, commit or old-output rewrite.

Next work: qualify complete main shared-clock execution; close combined-UCI
processing-time and late-cancellation boundaries; audit independent PUCCH
resource grouping and SRS priority after UCI ownership changes; verify actual
PRACH/control evidence; repair physical QCL/TCI and measured PMI application;
close NR RSSI/RSRP source/window coverage and SFN/cell provenance before claiming
complete main CSV/PNG coverage. Existing failed main artifacts and quarantine
guards remain intact. Full simulator/3GPP qualification and the overall goal
are still OPEN.

## 2026-09-09: normative processing units, not waveform CP durations

Reproduced a production N1 error before editing the producer:
`logs/nr_processing_units_20260909_01.log` records the failing assertion in
`testProductionTimingCallerMigration`. The engine summed actual CP-bearing
symbol durations to convert N1/N2. TS 38.214 V18.8.0 clauses 5.3 and 6.4 instead
use `(2048+144)*64*2^-mu` Tc per processing unit, for both normal and extended
CP. Physical resource start/end boundaries still require their actual CPs.
Reference: https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf

Producer correction: `TimingPolicyCatalog.processingSymbolTicks` now owns
that exact integer-Tc conversion. `capability1ProcessingBase` selects the
largest base N1/N2 duration across the participating numerologies. Production
UL timing supplies the actual PDCCH/PUSCH numerologies; DL HARQ timing supplies
PDCCH/PDSCH/feedback numerologies. `TimingRelationEngine` uses these explicit
ticks without altering resource clocks or timing advance. Its attached
`ProcessingBase.Scope` explicitly states that this is the base capability
budget, not complete UCI processing qualification.

Tests added: independent N1/N2 table/formula expectations over 72 ordered
mixed-numerology pairs, normal/extended-CP resource boundaries with equal
normative processing units, and a production N1 formula assertion. The
existing exact-deadline and one-Tc-too-early HARQ checks remain active.
Log `nr_processing_units_20260909_02.log` contains the first two successful
markers; its terminal tool output was lost, so a fresh focused batch with
explicit final completion marker is being used for definitive completion
evidence: `logs/nr_processing_units_shared_tdd_20260909_03.log` (session 46919).
No production/test dependency is edited while this MATLAB batch runs.

### Open boundaries rechecked against the actual consumers

- PUSCH preparation still needs allocation-derived d2,1 (zero only when the
  first allocated symbol is DM-RS-only), applicable switching/priority terms,
  and complete UCI timing. The base-unit correction does not supply these.
- `updateHARQState` retains the resolved feedback slot/resource, but its
  pending-feedback schema drops the detailed source-end/processing-time
  lineage. `multiplexDueHARQACKOnPUSCHImpl` checks ownership, resource overlap,
  payload identity and encoded immutability, but not the complete group-level
  TS 38.213 clause 9.2.5 timing budget. This remains a producer/consumer repair,
  not a plotting issue or a reason to manufacture successful UCI rows.
- Main PRACH/Msg3 and connected SRS/PUSCH/PUCCH must be requalified together
  after those repairs; isolated waveform component tests do not prove the
  entire main scheduler run or its access-to-connected transition.
- RA/SI `RASIPDSCHContext.localIntegrationContext` constructs an activated
  A|D QCL record referencing PDSCH-DMRS. `PDSCHIntegrationValidator` returns
  `ReceiverQCL`, but `PDSCHReceiver` retains the integration binding as metadata.
  This is not evidence of received-source QCL activation or an applied spatial
  filter. Physical QCL/TCI/PMI application and corresponding plots remain OPEN.
- `measureCSIRSPhysicalResource` uses an explicitly physical sqrt(W) receive
  grid and retains per-antenna measurements and resource-window information.
  Legacy `measureULLinkState.CSI_RSSI_dB` instead describes normalized UL
  SRS/PUSCH-DMRS grid power. It must not become UE CSI-RSSI in dBm. Likewise,
  `SSBWindowRSSIPerReceiveAntenna_dBm` is a scoped SSB-window measurement, not
  automatically the full carrier/SMTC NR RSSI. Complete RSSI CSV/PNG bindings
  and their measurement-window/units provenance remain OPEN.

These are explicit remaining requirements, not skipped features. No fresh
main run, new instrument playback claim, synthetic output, or full qualification
claim is authorized by the focused timing-unit results.

Session 46919 subsequently exited 0 with the final
`NOMINAL_PROCESSING_SHARED_TDD_BATCH_PASS` marker: all eight requested tests
completed, including actual late-feedback PUCCH and shared SRS/DCI/PUSCH/UCI.
The per-UE scheduler test includes TDD/FDD analytical timing/packing fixtures;
the shared waveform tests ran their default TDD profile, not an FDD campaign.
Session 39195 then exited 0 with `UPLINK_RECEIVE_AND_RSSI_FOCUSED_BATCH_PASS`:
PRACH receive-origin guard/delay invariance (TDD/FDD component fixtures),
received SRS correlation timing, CSI-RS physical-resource measurement windows,
SSB-window power/units, and strict proxy guards. Thirteen distinct focused
tests passed at this checkpoint. None proves full NR RSSI reporting or complete
main-run access/connected/UCI processing qualification.

### Newly reproduced and repaired radio-identity export defect

Fresh TDD component evidence, preserved without rewriting:
`C:/Users/anup0/AppData/Local/Temp/tpbb95dccd_1f9a_4507_9251_46a713b0dd1c/received_pusch.csv`
has Slot=10, SFN=1, CarrierNFrame=0, reporting Frame=1, MCS=4,
CRCPass=1, UCIOnPUSCHApplied=1, EVM=0.0855060489661762 and
PostEqSINR=21.3331144402139 dB. Its two ACK bits are explicit fixture inputs,
not evidence of the main DL-HARQ-to-UL scheduling chain.

The associated 3522-pair capture/EVM checkpoint under
`C:/Users/anup0/AppData/Local/Temp/tp02474097_422c_4db3_91de_6fbdce105753`
was read and the actual PNG inspected. The first five plotted CSV rows have
valid energy-derived RMS/peak EVM, but blank SFN and cell_id. Both data-channel
producers initialized `trialSFN=trialFrame`, confusing a one-based reporting
coordinate with radio SFN; constellation assembly omitted available identities.

Patched both DL and UL producers: radio SFN now comes only from the executed
`tx.Carrier.NFrame` modulo 1024; absent executions retain NaN. Constellation
rows retain SFN, carrier frame/slot, UE, RNTI, base-station and serving-cell
identity from the existing executed grant/attached context. Missing cell
authority is not replaced by a guessed PCI. The raw samples, EVM and SINR
calculations are unchanged. The shared verification helper now asserts these
bindings and the live EVM CSV's SFN/cell identity, and no longer fills in UE
identity itself before export.

Validation in progress: session 44108,
`logs/executed_radio_identity_20260909_01.log`; actual TDD DL/UL staged RX,
shared TDD SRS/PUSCH/UCI, export preservation and E2E truth/proxy guards.
Do not infer completion from this launch record. Main scheduler grant-SFN
semantics and the broader timing/QCL/TCI/RSSI requirements above remain open.

Session 44108 exited 1 before the new identity assertions: the old staged-DL
fixture selected slot 0, whose full-band allocation collides with 126 actual
SSB-owned PDSCH DM-RS REs. Corrected only that fixture to use control slot 2
and explicitly assert the scheduled DL occasion is SSB-free. The production
resource-ownership guard is unchanged. Rerun: session 86311,
`logs/executed_radio_identity_20260909_02.log` (pending completion).

Additional UCI audit finding: current PUCCH exports honestly identify
`HARQACKCodebookOrderingSource=source_slot_then_harq_process_runtime_order`;
the PUSCH multiplexer uses the same source-slot/HARQ-ID sort. The pending
feedback schema shown above does not preserve decoded DAI/monitoring-occasion
lineage. A deterministic bit sort is not general qualification of configured
Type-1/Type-2 HARQ-ACK codebooks, including Type-2 PUSCH DAI rules in TS 38.213
V18.8.0 clauses 9.1.3.1/9.1.3.2. Audit/repair of the configured codebook and
missing-DCI handling must accompany processing-time integration. A passing
two-bit waveform codec fixture does not close this requirement.
Reference: https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

Final identity-export batch result: session 86311 exited 0 with
`EXECUTED_RADIO_IDENTITY_EXPORT_BATCH_PASS`. The TDD staged-data test executed
both DL and UL cases; shared TDD SRS/DCI/PUSCH/UCI, link exports, artifact
integrity, organizer preservation and both E2E integrity guards completed.
Nineteen distinct focused MATLAB tests passed across this continuation's
successful batches. This is not testAll or full-main qualification.

New verified PUSCH row:
`C:/Users/anup0/AppData/Local/Temp/tp9416a9ce_cfb6_4b03_81d9_206826e5b6e3/received_pusch.csv`
now has Slot=10, SFN=0, CarrierNFrame=0, reporting Frame=1, CRCPass=1 and
UCIOnPUSCHApplied=1; EVM remains exactly 0.0855060489661762. The new EVM
checkpoint root is
`C:/Users/anup0/AppData/Local/Temp/tpc6b933fc_bff7_4d47_8a8a_bfdb9a7d2e86`.
All 12 CSV rows carry SFN=0 and serving cell=1. Independently recomputing
RMS and peak EVM from every row's error/reference energies gives maximum
absolute difference zero for both metrics. No historical output was rewritten.

Validation caveat discovered during the final E2E checks: the semantic test
iterates global `rng(11/22/33)` but leaves `cfg.run.seed` unchanged, while
SystemLevelRunner creates PHY/channel streams from `cfg.run.seed`. Thus this
batch proves its actual assertions, not three independent configured PHY/
channel seeds. Repair the test's seed authority and verify the resulting
coverage before making a multi-seed robustness claim. The FastVsTruth fixture
has the same distinction between its global RNG seed and configured seed.

The constellation producer also still uses its local trial ordinal for TBId;
canonical HARQ TB identity versus explicit trial-index naming needs separate
lineage repair. No claim is made that every CSV field is now correct. Required
next work remains main shared-clock qualification, allocation-dependent N1/N2
and group-level UCI deadlines/codebooks, received QCL/TCI and physical PMI
application, and complete NR RSSI/RSRP measurement-window and artifact coverage.

## 2026-09-09: allocation-derived PUSCH preparation budget

Previous goal turn classified as progress: production timing units and radio
identity exports changed, with verified focused regressions. No MATLAB worker
was live when this continuation began. Goal remains active, not complete.

Reproduced the missing d2,1 boundary in production: session 1855 exited 1,
`logs/pusch_preparation_allocation_20260909_01.log`. A mu=1, two-symbol-PDCCH,
full-slot-PUSCH, K2=1 grant was accepted with base N2 only even though its first
symbol contains data. TS 38.214 V18.8.0 clause 6.4 requires d2,1=0 only for a
DM-RS-only first symbol and d2,1=1 otherwise.

Implemented `puschPreparationProcessingTime` using actual nrPUSCHIndices,
nrPUSCHDMRSIndices and nrPUSCHPTRSIndices, not a mapping-type shortcut or a
hardcoded first-symbol assumption. It selects the largest N2+d2,1 duration
across actual PDCCH/PUSCH numerologies in nominal processing units. Production
TimingRelationEngine now constructs the configured/grant allocation in the
active BWP and supplies that budget. Errors are returned as explicit invalid
processing-allocation decisions, not substituted budgets. The scope label
still excludes unresolved UCI/switching/other capability terms.

SchedulerBase now resolves its mapping policy before timing (previously only
after timing during exact resource accounting). Exact finalization recomputes
the budget from the final allocation and rejects a changed budget, preventing
late mapping changes from retaining a stale processing decision.

The generic full-slot timing fixture now selects legal K2=2 and retains K2=1
as a configured negative candidate. Production migration expectations follow
that actual decision. Received-TAG fixture TDRA rows include the new K2=2
allocations; its explicit K2=1 negative case remains. No main TDD YAML was
changed and no timing/DCI validation was relaxed.

Session 76075 exited 0 for the initial allocation test. Session 94021 passed
the strengthened allocation test, production adapter and scheduler consistency
checks, then exited 1 because the received-TAG fixture still had only K2=1
TDRA rows. After adding explicit K2=2 rows, session 17746 is running
`logs/pusch_preparation_shared_tdd_20260909_01.log`. It has passed allocation,
received-TAG scheduler timing and shared preparation checks at this checkpoint.
Remaining batch checks are actual TDD coincident SRS/PUSCH and shared CSI.

New tests cover normal/extended CP, DM-RS types 1/2, partial/full CDM-group
reservation, transform precoding, exact deadline/one-Tc-too-early rejection,
unchanged RNG, and rejection of a changed first-symbol mapping during final
grant construction. These are not a complete group-level UCI timing or main
access-to-data qualification claim. N1 allocation terms, UCI codebook/DAI and
processing lineage, physical QCL/TCI/PMI, RSSI coverage and prior export/test
provenance findings remain open.

Session 17746 exited 0 with `PUSCH_PREPARATION_SHARED_TDD_BATCH_PASS`.
Actual coincident SRS/PUSCH used a shared verified channel observation and
decoded PUSCH/UCI successfully. Its received PUSCH CSV is under
`C:/Users/anup0/AppData/Local/Temp/tp45087feb_6667_47f7_8d72_3508155118d9`;
3522 receiver pairs/EVM checkpoint are under
`C:/Users/anup0/AppData/Local/Temp/tp5622cff3_4380_4590_8015_d5ee1657905a`.
RMS EVM was 8.55072257645% in this coexistence component fixture. The shared
CSI test also completed: TDD, HARQ disabled, seven CSI bits, due slot 4,
receiver delivery slot 5, with actual PUCCH power/export verification.

The earlier seed-authority finding is now repaired in the test inputs:
`testE2E_FastVsTruth` sets `cfg.run.seed` to each configured scenario seed;
`testE2E_TruthPacketSemanticCampaign` sets it to each 11/22/33 seed.
`verifyCampaignSeedAuthority` checks saved master/E2E seed metadata instead
of treating a global rng change as independent PHY/channel configuration.
No production RNG or result semantics were weakened. Following the
result-integrity workflow, export/proxy/E2E guards are rerunning in session
11589, `logs/pusch_timing_configured_seed_guards_20260909_01.log`.
Do not infer multi-seed success or batch completion from this launch record.

Additional follow-up for finalization: the new guard compares N2+d2,1
budgets. A separate invariant should reject any post-decision TDRA start/
length change even when its d2,1 value happens to remain unchanged. The
runtime overlap path currently checks TargetStartSymbol/TargetNumSymbols,
but that conditional overlap check is not a universal final-grant guard.
This broader stale-allocation/timing identity audit remains open; do not
describe the budget comparison alone as complete allocation immutability.

Final continuation result: session 11589 exited 0 with
`PUSCH_TIMING_CONFIGURED_SEED_BATCH_PASS`. Export/integrity/proxy checks passed;
FastVsTruth verified configured seeds 111/303, and the packet semantic campaign
verified configured seeds 11/22/33. Each expected seed was checked against
the saved master/E2E seed rows. This closes the identified test-input seed
authority defect, not general statistical/field conformance.

Fourteen distinct focused MATLAB tests passed in this continuation:
testPUSCHPreparationAllocationTiming, testProductionTimingCallerMigration,
testSchedulerGrantConsistency, testSchedulerReceivedULTiming,
testSharedGrantPreparationClock, testSharedPUSCHChannelArtifacts (TDD with
coincident SRS), testSharedCSIReportClock (TDD, HARQ off),
testTimingRelationEngine, testStrictProxyGuards, testLinkExportPipeline,
testArtifactIntegrity, testOrganizeRunResults_E2EArtifactPreservation,
testE2E_FastVsTruth and testE2E_TruthPacketSemanticCampaign.
No MATLAB worker remained after observed terminal completion; scoped
`git diff --check` passed (line-ending conversion warnings only).

The normal verification path continues to avoid testAll under the prior
focused-test request. No fresh 12/25-dB main scenario, old-result rewrite,
cleanup, commit, instrument playback or full NR/6G qualification claim.
Next priority: universal post-decision allocation identity and actual received
processing lineage, then N1 allocation/UCI timing and configured HARQ-ACK
codebook/DAI integration before main-run qualification. All earlier QCL/TCI,
physical PMI, RSSI, artifact coverage and TB-identity requirements remain open.

## 2026-09-09: post-decision grant timing identity

The next audit reproduced an independent stale-clock defect. Red regression
`testGrantTimingIdentity`, session 78730, exited 1 in
`logs/grant_timing_identity_20260909_01.log`: reducing the scheduled duration
while keeping the first-symbol occupancy unchanged was accepted by final
PHY feasibility despite retaining the old timing decision. The prior
N2+d2,1 check alone cannot detect this change.

Production repair:

- `assertGrantTimingIdentity` checks attached issued timing against current
  direction, data slot/start/duration, control slot/allocation, supplied
  CC/BWP identities, K fields, feedback slot/allocation, and timing advance.
  It also checks DL-data/ACK source interval continuity. It does not rerun
  a historic decision against mutable present-day BWP/TAG state.
- The production timing decision retains its resolved control allocation.
- Scheduler finalization rejects changed identities, DCI packing rejects
  them before payload encoding, and PHY freezing checks before cache reuse.
- A legally rebound decision cannot reuse a previous attempt's timing
  snapshot merely because its coding/resources/precoder are unchanged.
- Symbol allocations must be exactly two real finite integers. Finalization
  no longer rounds fractional allocations or truncates extra elements.

Boundary: resource-only/calibration contracts without an attached decision
remain outside this identity check; they are not thereby timing-qualified.
The guard does not establish received-DCI timing, complete UCI processing
budgets, RF propagation, or general immutable provenance for every legacy
entry point. No proxy values or replacement result rows were introduced.

Green batch session 11634 exited 0 with `GRANT_TIMING_IDENTITY_BATCH_PASS`
in `logs/grant_timing_identity_20260909_02.log`. Five tests passed:
testGrantTimingIdentity (TDD catalog plus DL/UL FDD component contracts),
testPUSCHPreparationAllocationTiming, testSchedulerExactGrantFinalization,
testPDSCHNominalTBSReservationSeparation, and
testHARQRetransmissionTimingRebinding. No main FDD run was launched.

Follow-on session 69403 is running the focused shared-uplink/stage suite;
its result must be observed before declaring it passed. Production/test
dependencies remain frozen while that MATLAB process is alive.

Read-only follow-up confirms `updateHARQState` still reduces DL feedback
lineage to a source/due slot and PUCCH resource assignment; its
`emptyFeedbackRow` has no source-end/preparation/receive-completion ticks.
That is the next integration boundary to repair and validate before claiming
the combined PUCCH/PUSCH UCI processing deadlines are enforced. The retained
runtime SourceSlot/HarqID ordering is not a general Type-1/Type-2 DAI codebook.

Session 69403 terminal result: exit 1 after five tests completed successfully
(SchedulerReceivedULTiming, SharedGrantPreparationClock,
SharedPUSCHChannelArtifacts TDD+coincident SRS, SharedCSIReportClock TDD/HARQ
off, and all four DataChannelStreamStages TDD cases). The next test,
NewDataFrozenGrantNotRefrozen, failed strict PDSCH validation because its
fixture supplied four hand-entered DCI bits, claimed successful reception,
and used placeholder field hashes without a serialization context. No
SchedulerGrantConsistency result was reached in that batch.

The fixture is being repaired to pack real scheduler DCI with canonical
timing and actually decode PDCCH loopback samples. Production received-DCI
validation is unchanged. The TX-only `withAuthoredPDSCHDCI` helper also used
a minimal hand-authored Valid timing struct; it now calls the canonical
timing adapter rather than constructing a supposed valid decision or a
fixed K1. Its three callers are included in the focused rerun, session
36311, `logs/grant_timing_authored_fixture_20260909_01.log`. Result pending.
The two new timing regressions are registered in testAll for future full
qualification; testAll itself was not launched.

Fresh measured UL evidence from the completed shared component:

- Received CSV root: `C:/Users/anup0/AppData/Local/Temp/tpf997ee4e_c1b2_414d_91e5_ff476812bf74`.
  Slot 10, SFN/CarrierNFrame 0, CarrierNSlot 9, UE/RNTI 1,
  MCS 4, rank 1, TB CRC 1, UCIOnPUSCHApplied 1. Two actual decoded
  HARQ-ACK codec-test bits have DecodeUsable=true and CRCApplicable=false;
  they are not claimed to originate from a complete DL HARQ procedure.
- Per-symbol EVM checkpoint root:
  `C:/Users/anup0/AppData/Local/Temp/tpec70ef09_c477_483d_9c03_e4a2c3cfb438`.
  3,522 paired symbols, 12 OFDM-symbol rows, RMS EVM 8.55072257645%.
  Independent PowerShell energy-ratio recalculation matched every exported
  RMS and peak value with maximum absolute error 0. PNG was visually
  inspected; it labels partial evidence and plots the 12 measured RMS and
  12 peak values. This does not close the canonical HARQ TB-id provenance
  issue or certify every other chart/CSV field.
- Additional flattened-export discrepancy: all inspected observation
  segments report ChannelModelApplied=CDL-A, ChannelFadingObjectClass=
  nrCDLChannel, RuntimeChannelReciprocityExact=true and mode
  none_dynamic_exact, but the trial-level ChannelFadingObjectClass/mode are
  blank and RuntimeChannelReciprocityExact=0. There are 19 canonical
  observation segments; their recorded receiver-estimator-input flag is 0
  (truth observation is not receiver CSI). Flattened aggregation must be
  repaired using the actual segment evidence, not copied from configuration
  or guessed from one interval. This remains OPEN.

Session 36311 exited 1 after the repaired
`testNewDataFrozenGrantNotRefrozen` completed successfully, including its
actual decoded PDCCH, rank-two/64-element PDSCH execution and frozen HARQ
architecture assertions. The next spatial fixture failed earlier in
resource mapping: absolute slot 1 overlapped 126 PDSCH DM-RS REs with SSB.
It and the corresponding TDD rank-one/two-port test are now placed at the
next configured offset-1 CSI-RS occasion, absolute slot 5, with an explicit
assertion that the actual SSB reservation is empty. Production reservation
validation is unchanged. The spatial-only grant fixture's fake received
DCI flags/placeholder hashes have also been removed; TX-only tests must not
claim a PDCCH receive outcome. Session 24134 is rerunning the three authored
DCI helper callers and scheduler consistency in
`logs/grant_timing_spatial_fixture_20260909_01.log`; result pending.

Session 24134 exited 1: the FDD spatial contract passed, but the TDD fixture
correctly rejected the assumed slot-5 CSI-RS occasion. Its YAML period is
five slots with offset one, not the FDD fixture's four-slot period. The
test migration now derives period+offset from each actual scenario and
asserts the chosen SSB reservation is empty. The TDD test therefore uses
absolute slot 6 (runtime slot 7), while FDD uses absolute slot 5. Neither
period was changed in production or YAML. Session 84747 reruns the same
focused set, `logs/grant_timing_spatial_fixture_20260909_02.log`; pending.

Session 84747 exited 0 with `GRANT_TIMING_SPATIAL_FIXTURE_BATCH_PASS`.
All three authored-DCI helper callers and SchedulerGrantConsistency passed.
Combined with the earlier completed subsets, 15 distinct focused tests
have passed since the post-decision identity patch. The expensive
NewDataFrozenGrantNotRefrozen result is from session 36311 before its next
test failed; it was not rerun unnecessarily after unrelated spatial-only
fixture changes.

Final current verification batch: session 32039,
`logs/grant_timing_ul_integrity_20260909_01.log`, covers PRACH receive-origin,
late PUCCH feedback and format-2, generic timing, strict proxy guards,
export/artifact preservation, and the two configured-seed E2E guards.
This is pending; dependencies are frozen until terminal completion. Scoped
`git diff --check` passed before launch, with only CRLF-conversion warnings.

Final result: session 32039 exited 0 at approximately 03:28:37Z with
`GRANT_TIMING_UL_INTEGRITY_BATCH_PASS`. Configured master/E2E seeds
111/303/11/22/33 were verified against their persisted seed rows. No MATLAB
process remained after terminal completion.

Twenty-five distinct focused tests passed in this continuation (failed
pre-repair attempts are retained in their original logs, not overwritten):

- testGrantTimingIdentity; testPUSCHPreparationAllocationTiming;
  testSchedulerExactGrantFinalization; testPDSCHNominalTBSReservationSeparation;
  testHARQRetransmissionTimingRebinding.
- testSchedulerReceivedULTiming; testSharedGrantPreparationClock;
  testSharedPUSCHChannelArtifacts (TDD, coincident SRS);
  testSharedCSIReportClock (TDD, HARQ off); testDataChannelStreamStages
  (all four TDD cases).
- testNewDataFrozenGrantNotRefrozen; testCausalSpatialPortRankDependency;
  testTDDRankOneTwoPortCSIRSSpatialContract; testYAMLDrivenPDSCHPTRSExecution;
  testSchedulerGrantConsistency.
- testSharedPRACHReceiveOrigin; testSharedPUCCHLateFeedbackClock;
  testSharedPUCCHLateFormat2Clock; testTimingRelationEngine;
  testStrictProxyGuards; testLinkExportPipeline; testArtifactIntegrity;
  testOrganizeRunResults_E2EArtifactPreservation; testE2E_FastVsTruth;
  testE2E_TruthPacketSemanticCampaign.

This continuation is PROGRESS, not complete qualification. No fresh main
12/25-dB scenario or WebGUI run was started. FDD execution was limited to
focused configuration/spatial/PRACH and repository-mandated E2E regression
fixtures. No testAll run, cleanup, commit, old-output rewrite or instrument
playback. Existing worktree edits remain preserved.

Next: carry actual source/receive-completion and processing lineage through
pending HARQ/CSI reservations, enforce combined UCI deadlines with the
configured HARQ-ACK codebook/DAI, and validate this at the main shared-stream
scheduler boundary. Physical QCL/TCI activation/consumption, PMI lineage,
RSSI reference-window definitions and CSV/PNG binding, flattened channel
observation aggregation, canonical HARQ TB identity and full output coverage
remain OPEN. The passing spatial and power/EVM component checks must not be
used to declare those independent requirements solved.

## 2026-09-09: received data interval and HARQ reservation lineage

The preceding goal turn was PROGRESS (25 focused tests, terminal sessions
recorded above). This continuation rechecked that no MATLAB process remained
and traced actual data completion in `localCompleteSharedDataPlan` through
`updateHARQState`. The main receive event retained measured `ReceiveTiming`
and complete observation buffers, but neither its received allocation end
nor result-availability sample survived into pending HARQ feedback.

Current implementation under verification:

- `receivedDataSymbolTiming` derives the received allocated-symbol interval
  from the executed carrier/CP calendar and actual bounded-reference timing
  correction. It rejects oracle alignment, receive zero-padding, incomplete
  capture and a result event that precedes capture completion.
- `harqFeedbackReceiveTimingFields` binds that interval to executed direction,
  RNTI, immutable grant identity, absolute data slot and symbol allocation.
  Legacy absent input is explicitly unavailable; a shared DL HARQ commit
  requires the evidence before shared HARQ state can mutate.
- Main shared completion attaches this evidence to the retained HARQ result
  and trial row; pending feedback receives the same fields and serialized
  evidence. No source/due slot or CPU timer is converted into a supposed
  measured receive time.

This is the receive-event handoff, NOT a complete N1/UCI processing model.
`ProcessingBudgetIncluded=false` is explicit. Source symbol end and result
event availability are distinct; a full-slot capture can make the result
available later than the end of a short allocation. The downstream combined
UCI deadline/codebook integration remains open, and this field addition must
not be described as solving that entire requirement.

Verification adds exact known-delay checks and CSV/JSON roundtrips to all
four real coded TDD stages in testDataChannelStreamStages, with negative
cases for wrong RNTI/slot, absent shared evidence, oracle/padded alignment,
early result event and incorrect demodulated extent. Session 37335 exited 1
on a parenthesis typo in the new verifier after the DL waveform decoded;
no semantic test pass is claimed from that attempt. The typo was corrected.
Session 11583 exited 1: the actual completed HARQ snapshot lacked Direction.
Both DL and UL producers now retain their actual transmitter direction.
Session 18619 (`logs/received_data_timing_tdd_20260909_03.log`) then passed DL
receive timing and CSV/JSON roundtrip, but stopped after successful UL decode
because the UL snapshot also dropped ScheduledAbsoluteSlot. Unlike the DL
producer, its preserve list omitted the canonical timing decision, K0/K1/K2,
control/data/feedback slot and selected CC/BWP fields. Those original grant
fields are now preserved, not reconstructed from a row or nominal duration.
The verifier compares every present timing field against the prepared grant.
No main scenario or testAll was started; these failed attempts are not batch
qualification passes.

### Receive-lineage verification checkpoint

Session 24076 exited 0, with `RECEIVED_DATA_TIMING_TDD_BATCH_PASS` in
`logs/received_data_timing_tdd_20260909_04.log`. Passed:
testDataChannelStreamStages (all four TDD coded cases),
testExecutedHARQPayloadAuthority, testGrantTimingIdentity, and
testSharedGrantPreparationClock. The staged UL cases retained measured
alignment offsets 7, 90 and 78 samples; their transport-block CRCs passed,
and the last two decoded the explicit codec-fixture HARQ-ACK payload.
These are component inputs, not feedback manufactured from an unexecuted DL.

Session 87152 exited 0, with `RECEIVED_DATA_TIMING_SHARED_UL_BATCH_PASS` in
`logs/received_data_timing_shared_ul_20260909_01.log`. Passed
testSharedPUSCHChannelArtifacts('TDD',true) and testSchedulerGrantConsistency.
The actual shared CDL/SRS/DCI/PUSCH/UCI test now exercises the receive timing
handoff used by main completion and verifies the persisted sample clock and
JSON grant identity. Artifact root:
`C:/Users/anup0/AppData/Local/Temp/tpd309b774_73a3_4156_85ec_3a322181cd68`.
PUSCH EVM was 8.55072257645 percent, CRC passed, and coincident SRS/PUSCH
reused the same verified immutable channel observation. This remains an
explicit component fixture, not a main access-to-data or adaptation pass.

The four staged receivers also generated actual paired-symbol CSVs and
EVM-per-symbol PNGs. DL and UL PNGs were visually inspected. A separate
PowerShell/.NET CSV read recomputed all 12 UL RMS/peak rows from the 3,522
actual reference/equalized pairs, matching the saved values (not fitted
receiver symbols). Import-Csv initially rejected case-distinct Direction /
direction headers; the case-sensitive reader resolved this without editing
any source artifact. Canonical HARQ TB identity and missing component cell
identity remain separate export limitations, not fixed by EVM agreement.

This checkpoint is PROGRESS. No MATLAB process remains. No main 12/25-dB
run, main FDD run, testAll, cleanup, commit or instrument playback occurred.
Six distinct focused tests passed; the broad required suites remain open.
Main pending-feedback-to-UCI clock consumption and full N1/multiplexing
budget/codebook/DAI are still open. In particular, buildDueHARQACKStruct
currently retains only owner, source slot, ACK and reservation identity;
the new detailed receive clock must still reach that consumer. Do not call
the new exported timing fields complete UCI timing enforcement. Physical
QCL/TCI consumption, PMI lineage, RSSI measurement-window labeling/plots,
flattened channel evidence aggregation, PRACH/PUCCH full-run verification,
legacy oracle/padding audits and fresh main-run qualification remain open.

## 2026-09-09: UCI receive-availability consumer boundary

Previous goal turn: PROGRESS, six focused tests passed; no live MATLAB
remained. Current work projects the six original receive-timing fields into
PUCCH grant traces and the HARQ-ACK due collector. Shared PUCCH preparation
and PUSCH UCI binding now require valid received DL timing. The new guard
checks source slot/RNTI, common sample rate, flat/JSON agreement and actual
result availability no later than the encoding/binding event. It does not
manufacture timing from ACK content or slot counters. This is a necessary
causality condition, not a complete N1/Tproc multiplexing implementation.

Session 91043 exited 1 (`logs/uci_receive_availability_20260909_01.log`).
Actual DL stage/CSV/receive-availability negatives, testRuntimeUCIOwner and
TDD CSI-only shared PUCCH passed. testSharedPUCCHLateFeedbackClock stopped
with MissingUCIReceiveTiming because its old source ACK/NACK values and DL
TBs were declared fixtures, with no executed DL receive event. Production
validation was not weakened. The test is being converted to actual isolated
coded PDSCH/DCI reception, retaining clean ACK and high-noise NACK cases.
The isolated DL connector must not be mislabeled as propagation through the
separate shared CDL owner used by its SRS/PUCCH. TAG/pathloss inputs still
remain declared component inputs, not simulated access.

Session 26265 exited 0 for the revised late Format-0 and Format-2 tests in
`logs/uci_receive_availability_20260909_02.log`, marker
UCI_RECEIVED_DL_PUCCH_BATCH_PASS. Actual isolated DL source slots 3/6/7
produced CRC outcomes 1/0/1 with fixed sample-noise variances 1e-13/1e-4/1e-13.
Both shared PUCCH receptions and scoped power CSV roundtrips passed.

Session 47128 exited 1 (`logs/uci_receive_availability_20260909_03.log`).
Combined TDD CSI+HARQ PUCCH passed, with the HARQ source replaced by actual
isolated PDSCH. PUSCH then stopped on a new test assertion that incorrectly
looked for MultiplexedOnPUSCH in PendingFeedbackTable; the canonical pending
field is DeliveryMechanism, and MultiplexedOnPUSCH belongs to the control
trace. Corrected the verifier to assert both actual schemas. Added negative
checks at the real shared preparation/binding entry points for future and
missing receive timing (not only helper-level checks).

Session 59903 exited 1 (`logs/uci_receive_availability_20260909_04.log`).
Actual shared PUSCH decoded CRC and [1;0] UCI correctly, but application to
the two original DL HARQ processes failed the exact context binding. Code
inspection found buildGrantPHYJob resolving GrantContextId on the job
envelope without copying it into GrantSnapshot. Without an input runtime
ID, the throughput producer then composed a different replay context ID.
The job now retains its same resolved identity in its PHY payload for both
directions. Assertions cover envelope/retained-result agreement. The
reservation join was not relaxed, and receiver bits were not substituted.

Session 99514 exited 0 in `logs/uci_receive_availability_20260909_05.log`:
actual DL-derived UCI through shared TDD PUSCH, revised late PUCCH, and
scheduler grant consistency all passed. Marker:
UCI_RECEIVED_DL_BOTH_TRANSPORTS_BATCH_PASS. PUSCH retained the exact job ID,
decoded [1;0], and applied ACK/NACK to the two actual source DL HARQ
processes. Both runtime transport entry points reject future source timing;
PUSCH binding also explicitly rejects missing timing. These guards remain
enabled. Shared PUSCH artifact root:
`C:/Users/anup0/AppData/Local/Temp/tp421b7253_4f10_4082_b450_67537b1c042c`.

The final focused job-identity regression session 63075 exited 0 in
`logs/uci_identity_regression_20260909_01.log`, marker
UCI_IDENTITY_REGRESSION_BATCH_PASS. Passed: all four TDD coded stages,
testGrantCacheLiveUCIAuthority, testTrialContextUCIBinaryAuthority,
testStrictProxyGuards, testLinkExportPipeline, testArtifactIntegrity,
testE2E_FastVsTruth and testE2E_TruthPacketSemanticCampaign. Together with
session 99514 this is eleven distinct focused tests after the identity fix.
The E2E fixtures include their existing FDD truth/proxy comparison modes;
they are regression evidence, not the user's main waveform scenario.
No main 12/25-dB run, testAll, cleanup, commit or instrument playback was
started. No MATLAB process remains. The optional CSI fixture's header was
corrected afterwards to describe its actual isolated DL source accurately;
no semantic code changed after the terminal batch.

Current goal turn is PROGRESS. Source receive timing is now retained and
required at shared HARQ UCI binding/preparation, and the exact PHY job ID
survives into the decoded grant. Actual ACK/NACK sources are used in both
shared-transport component fixtures; neither missing timing nor a context
mismatch is repaired by invented values or relaxed assertions. Full main
scheduler, processing budgets, codebook/DAI, QCL/TCI, RSSI, and comprehensive
CSV/PNG qualification remain incomplete. Keep the overall goal active.

Additional open source audit: consumeDecodedPUSCHHARQACK and
consumeDecodedPUSCHCSI still compare the reservation DueSlot with
state.CurrentSlot. A completion/delivery event in a later physical slot
must instead bind the reservation to the original received PUSCH occasion,
while keeping actual delivery time distinct. The current passing shared
component completes before that boundary and does not cover this case.

Standards reread: TS 38.213 V18.8.0 pp.79-80 also constrains the relative
DL/UL DCI ordering for HARQ-ACK on PUSCH, with explicitly scoped repetition /
configured capability exceptions. Late decoder completion is not the same
as later DL DCI reception. That distinction and the full 9.2.5 timing terms
must be enforced separately from this receive-availability guard. Reference:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf

## Latest checkpoint: cross-slot UCI and CSI reservation state handoff

The immediately preceding DueSlot/CurrentSlot issue has since been repaired
and tested. See the section "received PUSCH occasion versus scheduler
delivery" earlier in this journal for the detailed evidence and failed-test
history. Original received PUSCH occasion and later scheduler delivery now
remain distinct, validated against the actual shared receive event.

A stronger measured-CSI regression exposed an additional real defect:
the overlap planner discarded a locally created CSI reservation table when
returning to the binding caller. The caller now retains that state, and
shared binding/completion cannot silently skip missing CSI reservations.
Two actual isolated-DL ACK/NACK bits and an actual measured CSI-RS report
were transmitted/decoded on shared CDL PUSCH, then delivered at slot 11
against transmission slot 10. All three control trace rows persist and do
not claim a standalone PUCCH waveform. CQI 15/RI 2/PMI 1 survive transport;
the isolated source's 81.59-dB measured CSI is not the main 12-dB scenario.

Six final focused tests passed (session 6224 exit 0), followed by both final
E2E evidence regressions (session 79374 exit 0): eight distinct tests passed.
No main run, testAll, cleanup,
commit or instrument playback is started in this continuation. Broad
processing budgets/DCI-order/codebook/DAI, full main-scheduler qualification,
physical QCL/TCI/PMI consumption, RSSI windows/units and all-output audit
remain OPEN. An older UL metric helper still combines receive branches in
normalized power while carrying a CSI/TS-38.215 label; it is not a validated
UE physical RSSI report and was not repaired in this bounded timing patch.
The overall goal remains active: this continuation makes PROGRESS, not
full-completion or blocked claims.

## 2026-09-09: UL normalized power and physical data-window RSSI

Previous goal turn: PROGRESS (two UCI state/timing fixes, eight final tests).
Current worktree/process inspection found no live MATLAB before this patch.
The remaining UL RSSI issue was confirmed at its producer: reference RE
power averaged receive branches while RSSI summed them. Repeating an
identical receive branch therefore changed the ratio by 10log10(Nrx).
It also inferred an Nx2 linear NR resource-index matrix to be subscripts.
The helper mislabeled those normalized UL diagnostics as CSI/TS-38.215
UE measurements, despite observing UL DM-RS/SRS rather than DL CSI-RS.

Replaced that power path with measureNormalizedReferencePower. It retains
all finite actual reference RE/window energies per branch, uses linear
branch means consistently, interprets NR indices as linear across transmit
ports, and retains structured calculation evidence. Deleted the unused old
power routines, including their silent catches/nonfinite omission. UL
exports now use ULNormalizedReferencePower_dB, ULNormalizedWindowRSSI_dB,
ULNormalizedWindowPowerRatio_dB and corresponding source/JSON fields.
They do not claim dBm or NR CSI-RSRP/RSRQ. Existing DL CSI exports are not
renamed by this patch. Internal pre-existing accumulator variable names are
unchanged but their primary exported meanings are explicit.

Added a distinct physical measurement to both completed DL and UL data
receivers: measureReceivedDataCarrierPower reads the actual retained
pre-RX-front-end antenna-plane observation, aligns it with the measured
received timing, demodulates the executed carrier/sample rate, and computes
per-branch carrier energy over the actual data-symbol allocation. It does
not reconstruct a waveform or use configured SNR, AGC output amplitudes,
channel-truth timing/CFO, or a selected precoder to invent watts. The retained
JSON includes symbol powers in W, per-branch dBm, waveform hash, frozen grant
identity, physical timing, sample rate/Nfft, bandwidth, reference plane and
scope. The FFT conversion is abs(grid/Nfft)^2/1000 for sqrt(mW) input.

This is explicitly DATA-WINDOW carrier RSSI, not a UE SMTC/CSI NR-RSSI
report. The distinction follows TS 38.215 V18.4.0 sections 5.1.3/5.1.4:
the UE measurement has defined time/frequency/reference-plane requirements;
an arbitrary data allocation cannot stand in for those reporting occasions.
Reference: https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.04.00_60/ts_138215v180400p.pdf

Both PDSCH/PUSCH carrier-window RSSI CSV/PNG charts use the existing
config-controlled live publication path. Their materializer checks branch
counts, sample intervals, data symbols, bandwidth, units, grant/UE/slot/hash
identity, scalar/JSON agreement, no proxy markers, no duplicates, and the
same-branch linear-power to dBm arithmetic. No materialization from a
normalized UL diagnostic is permitted.

Python: 73 test_lls_radio_measurement_plots checks passed, including the new
DL/UL 1/2/4-branch cases and malformed/proxy rejection cases. MATLAB session
32549 is in progress in logs/ul_power_measurement_boundary_20260909_01.log.
Its DL and UL isolated received stages have passed, including publication
and a 2x physical-amplitude -> 20log10(2) dB check without changing digital
receiver samples; shared CDL PUSCH+CSI remains in progress. Do not treat
the batch as terminal until the exact process exits. No semantic files are
edited during its lifetime. Main short-run/full qualification remains OPEN.

### Follow-up evidence and strict fixture repair

Session 32549 subsequently exited 0 with UL_POWER_MEASUREMENT_BOUNDARY_BATCH_PASS:
normalized-power unit checks, actual TDD DL/UL receive stages, and shared
PUSCH carrying late-delivered measured CSI all passed. The actual shared
UL RSSI CSV retained two branches (-81.1721875230241 and -81.3257735725965
dBm); its generated PNG was visually inspected. These are component-run
measurements, not main-scenario 12-dB results.

The next batch (27409, power_measurement_regression_20260909_01.log) passed
the normalized-power checks, both TDD data stages including the absolute
unit-IQ calibration (1 sqrt(mW) constant IQ -> 0 dBm carrier power), and
the SRS RI/TPMI estimator. It then failed the existing strict CSI
non-occasion fixture because that fixture supplied no serialized DCI.
Repaired its input using scheduler-authored DCI and actual coded PDCCH
loopback reception, rather than invented payload hashes/CRC success flags.
The following batch (_02.log) exposed a second fixture mismatch: its
control slot equaled the intended data slot despite configured K0=1.
The fixture now derives the control occasion from configured K0 and asserts
that the canonical timing decision reaches the intended data non-occasion.
Neither failure was hidden by weakening the production checks.

Also repaired the UL per-RB SINR coordinate helper: a multi-port matrix of
linear NR resource indices must not be interpreted as [k,l] subscripts.
Added a direct matrix/vector regression. This fixes resource grouping, not
all legacy pilot-reconstruction/SINR semantics.

Python publication/measurement/output-contract checks: 90 passed. MATLAB
session 14226 (_03.log) is still running at this journal update, with seven
focused checks requested. Later checks must not be claimed passed until
the batch actually reaches them and exits. No main run or testAll started.
Further observed legacy issues remain OPEN: configured UL rank/TPMI can
substitute for missing measurement evidence; some pilot reconstruction
paths truncate dimensions or suppress estimation errors. Full N1/N2/UCI
ordering, main shared-clock integration, physical QCL/TCI/PMI use and
UE-defined NR-RSSI reporting remain unqualified.

Session 14226 subsequently exited 0 with POWER_MEASUREMENT_REGRESSION_BATCH_PASS.
All seven requested tests passed: testULNormalizedReferencePower,
testLLSULSRSRITPMIEstimator, testCSIRuntimeExecution,
testSharedPUSCHLateCSIDelivery, testStrictProxyGuards,
testLinkExportPipeline, testArtifactIntegrity. The final shared-PUSCH
component root is C:/Users/anup0/AppData/Local/Temp/tpdf9c9935_9a5c_4f18_9156_6b8a3ae86257;
its received constellation/power publication root is
C:/Users/anup0/AppData/Local/Temp/tp25ea533f_a86c_4295_9837_45eb840f7e44.
The actual PUSCH RSSI PNG at that root was visually inspected again:
two measured antenna branches, one observed slot, no invented sweep curve.
UL EVM was 8.62254422951 percent over 3522 actual paired symbols;
the component post-equalization SINR was 21.262 dB, not a 12-dB run claim.

After MATLAB exited, fixed the publication reader's MATLAB 1x1 scalar JSON
case and added single-symbol 1/2/4-branch tests in both directions plus a
boolean-energy rejection. All 97 Python checks now pass across the same
three publication/measurement/output-contract files. The two required E2E
truth/proxy export regressions are running sequentially in session 36781,
logs/power_export_e2e_regression_20260909_01.log; do not claim them passed
until terminal evidence. No main scenario, testAll, cleanup or commit.

Final terminal evidence: session 36781 exited 0 with
POWER_EXPORT_E2E_REGRESSION_BATCH_PASS. Both E2E tests passed; persisted
log markers confirm configured seeds 111/303 and 11/22/33. Thus this
continuation closes nine MATLAB regression functions (seven focused plus
two E2E) and 97 Python checks, in addition to the earlier actual TDD
data-stage boundary tests. E2E fixtures are not main-waveform qualification.
All MATLAB batches have finished; no new main scenario was launched.

Goal checkpoint: PROGRESS, overall goal ACTIVE. Next bounded repair should
address the remaining UL measured-versus-configured RI/TPMI provenance and
its consumers before a fresh main TDD acceptance run. Full access/PRACh,
PUCCH/PUSCH/SRS timing, N1/N2/UCI ordering, QCL/TCI spatial use, UE RSSI
windows and exhaustive main CSV/PNG qualification must still be audited;
do not claim a 10/10 or complete 3GPP-compliance result from this checkpoint.

## 2026-09-09: UL spatial-measurement authority (continuation)

Previous turn classification: PROGRESS (nine MATLAB regressions and 97
Python checks terminally passed). Current inspection confirmed no MATLAB
batch alive before editing. Read NR-validation/result-integrity skills and
config-driven output guidance. No new scenario policy is introduced.

Confirmed and patched measureULLinkState: configured TPMI could become
RuntimeAppliedPMI when the actual transmitter trace was missing, an SRS
recommendation was conditioned on an applied-TPMI hint, and zero/unavailable
rank could become the configured positive layer count. These substitutions
are removed. Effective DM-RS rank remains a measured channel descriptor,
not configured rank or an SRS recommendation. Actual applied TPMI is kept
distinct from measured SRS recommendation and configured TPMI. Native
codebook support is retained as SelectedCodebookPortIndices1Based, not
SelectedBeamIndices or a fabricated BeamCandidateCount. Matrix inspection
clarified that nrPUSCHCodebook is layer-by-port: its column support was
antenna-port support, not spatial beam IDs (nor layer indices).

UL primary rows now retain ULSpatialMeasurementEvidenceJSON, including
channel-estimate domain, rank/TPMI sources, configured/applied TPMI and
SRS validity. Received shared-PUSCH regression verifies the persisted
measurement domain and actual transmitter TPMI. New analytical provenance
test passed; SRS estimator regression passed. Session 43268 is still live
in logs/ul_spatial_provenance_20260909_01.log; later tests are not yet proven.

Further read-only audit found a separate square-matrix defect in the SRS
MI scorer: localOrientPUSCHCodebookForChannel assumes a matrix with rows
equal to the port count is already port-by-layer. For full-rank native
codebooks it is actually layer-by-port, so the required transpose can be
omitted. The next repair must use explicit canonical orientation and an
independent MMSE reference, after the current batch terminates.
Reference: https://www.mathworks.com/help/5g/ref/nrpuschcodebook.html
(native orientation is the transpose of TS 38.211 section 6.3.1.5).

Remaining legacy surfaces are not cleared by this patch: non-strict
sanitizeFeedbackPMI still manufactures fallback TPMI; the UL transmitter
trace has grant-field fallbacks and labels port support as applied beam
indices; rank/condition diagnostics still contain complex averaging and
nonfinite omission. Main shared-clock, QCL/TCI spatial use and complete
12-dB acceptance remain OPEN. No code edits while MATLAB is live.

Session 43268 subsequently exited 0 with UL_SPATIAL_PROVENANCE_BATCH_PASS:
all seven focused functions passed, including actual shared TDD SRS/DCI/
PUSCH/HARQ/CSI and the persisted UL spatial JSON. Actual output roots:
component C:/Users/anup0/AppData/Local/Temp/tp48fc9a77_d0b0_4966_b847_d0cabac65c52;
constellation/power C:/Users/anup0/AppData/Local/Temp/tp7ea62733_d274_4b52_a141_3763ec9eb504.

Added testSRSCodebookOrientation BEFORE changing the scorer. Session 98885
exited 1 in logs/srs_codebook_orientation_20260909_before.log: independently
scoring the selected codebook using H*nrPUSCHCodebook(...).' did not maximize
MI. The analytical fixture uses a non-symmetric complex channel, 2/4 ports,
two noise levels and independently evaluates every catalog-valid rank/TPMI.
It also checks the selected per-layer MMSE SINR and explicitly requires
square full rank in its high-SNR calibration case. This is not a configured
25-dB waveform-run claim.

Repaired candidate construction to consume the canonical port-by-layer
output of puschCodebookProjectionMatrix. Removed dimension-based transpose
inference; scoring now rejects a wrong port axis. Port-support extraction
uses rows of this canonical matrix. No waveform, codebook candidate, MI
objective, noise or scenario policy was altered to force the result.

The same independent test now PASSES without changing its assertion.
Session 83483, logs/ul_spatial_provenance_20260909_02.log, also passed the
provenance and existing SRS estimator units and is still running the shared
PUSCH/scheduler/export checks followed by both required E2E regressions.
Do not claim the entire batch until terminal evidence. Overall goal ACTIVE.

Session 83483 reached UL_SPATIAL_FOCUSED_BATCH_PASS: all eight focused
functions passed after the orientation repair. Actual shared-TDD root:
C:/Users/anup0/AppData/Local/Temp/tp4ae1912f_7e3d_45ea_8fc7_f4b767520419;
received CSV/PNG root:
C:/Users/anup0/AppData/Local/Temp/tpf6089558_6e76_4dbe_8f10_ff4025ab3361.
Read the persisted UL row directly: RankIndicator=1, RankEstimate=1,
PMI=AppliedPrecoderPMI=0; ULSpatialMeasurementEvidenceJSON names the
effective DM-RS domain and explicitly sets SRSRITPMIValid=false rather
than claiming a newly measured SRS recommendation. The port-support list
is unavailable in that domain, not invented from scheduled TPMI. Existing
BeamScoreSource remains not_evaluated_pusch_dmrs_effective_layer_channel_cannot_rescore_tpmi.
Actual EVM remains 8.62254422951 percent for 3522 paired symbols.

Python session 84887 exited 0: 97 publication/measurement/output-contract
checks passed against this worktree. The MATLAB E2E comparisons remain
live in session 83483 at this update; no semantic dependency edits or
second MATLAB process were launched.

Final terminal evidence: session 83483 exited 0 with
UL_SPATIAL_REGRESSION_BATCH_PASS. Eight focused MATLAB functions plus both
E2E functions passed (ten distinct regression functions). E2E configured
seed markers: 111/303 and 11/22/33. Python session 84887: 97 passed.
No full testAll or full required NR/config suites were run; their acceptance
remains OPEN under the focused-test constraint. No main TDD/FDD scenario,
25-dB run, long campaign, commit, cleanup, or instrument playback started.

This goal turn is PROGRESS: real configured-versus-measured substitutions
were removed, actual UL CSV lineage was strengthened, and an independent
failing numerical test proved and then verified a square-codebook SRS
scoring correction. Overall goal remains ACTIVE, not complete or blocked.

Next audit must retain the original scope: resolve remaining UL transmitter
trace/grant fallback and port-support-versus-spatial-beam export semantics,
non-strict feedback TPMI fallback and rank provenance, then requalify the
main shared-clock TDD run. Transform-precoded codebook handling is separately
OPEN: measureULLinkState excludes transform precoding from codebook mode,
and estimateSRSRITPMI exits before TPMI selection in that mode. Today's
CP-OFDM codebook checks must not be extended to claim DFT-s-OFDM coverage.
Physical QCL/TCI use, full UCI timing budgets, access/control and exhaustive
12-dB CSV/PNG acceptance remain required before the later impairment/6G/
instrument objectives can be claimed achieved.

## 2026-09-09: transmitter-owned UL precoder and port evidence

Previous goal turn: PROGRESS, including the independently reproduced and
repaired square-codebook SRS scoring defect. No MATLAB process was alive
at the start of this continuation. Read all three applicable NR-validation,
result-integrity and config-driven output skills/references. No new runtime
scenario constant, hidden policy, or duplex-specific branch was introduced.

Patched the actual UL producer to retain native codebook support as
CodebookPortIndices1Based with explicit logical-port/non-spatial-beam
definition. It no longer fills BeamIndices from codebook antenna support.
UL raw CSV and HARQ snapshot exports now expose AppliedCodebookPortIndexSet
and AppliedCodebookPortIndexDefinition separately from AppliedBeamIndexSet.
Added PrecodingNumLogicalPorts from the actual transmitter metadata; the
existing PrecodingNumPorts remains the physical waveform matrix row count.
The WebGUI UL preview labels applied TPMI, logical ports, codebook ports
(1-based), and applied spatial beams separately. This is a preview-label
test, not a claim that a running WebGUI has been manually inspected.

New validatePUSCHPrecoderEvidence accepts no grant/config fallback input.
It validates the actual nrPUSCHConfig/PrecodeInfo pair: matrix dimensions,
logical versus physical ports, transform mode, explicit source/stage/flags,
TPMI agreement, native logical-codebook matrix, active port support, and
applied matrix digest. UL reporting and HARQ snapshot construction use it.
Removed grant fallback for applied TPMI, source/mode/stage, dimensions,
and beam/PMI metadata. The shared digest helper no longer manufactures a
requested digest from the actual applied matrix or an applied digest from
a grant claim. Missing requested evidence stays absent. Both duplicated
UL truth annotation paths no longer copy applied beams into missing requests
or equate native codebook port support with physical beam IDs.

Analytical contract tests cover 1/2/4 ports and reject missing transmitter
metadata, contradictory TPMI/matrices/port support/digest, and invalid flags.
The old UL beam-provenance assertion was corrected to require port support
and absence of fabricated spatial-beam IDs; its old coupled fixture has
NOT been run/qualified in this continuation. Actual shared PUSCH coverage
comes from testSharedPUSCHLateCSIDelivery and its strengthened CSV checks.

Session 80310: unit checks passed, then the shared CSV regression failed
because the primary row did not export logical port count. This was a real
schema omission: do not substitute physical element count for logical ports.
Added the actual logical-port export and reran rather than weakening the
matrix/port reference check. Log: pusch_transmitter_precoder_evidence_20260909_01.log,
exit 1. The received waveform itself was not diagnosed as failed by that
missing-column exception.

Python final checks: 110 passed across measurement plots, live publication,
complete output contract, and realtime component dashboard. MATLAB session
96530 in pusch_transmitter_precoder_evidence_20260909_02.log is live:
transmitter/digest units passed, shared PUSCH followed by focused guards
and both E2E export regressions are pending. Freeze dependencies until exit.
Main 12-dB/full acceptance, remaining feedback fallback, transform-codebook
selection, physical QCL/TCI and complete timing budgets remain OPEN.

Session 96530 reached the actual shared-TDD receive and CSV assertions:
component root C:/Users/anup0/AppData/Local/Temp/tpabb41a43_283d_4687_af8d_15895cae2d50;
CSV/PNG root C:/Users/anup0/AppData/Local/Temp/tp873fa93d_16e6_4356_bd67_8f461a84c86e.
Direct CSV inspection: slot 10, applied TPMI 0, physical precoder ports 1,
logical codebook ports 1, active codebook port set 1. AppliedBeamIndexSet
is empty and explicitly not_materialized_in_active_ul_path. This fixture
is single-port UL with two receive branches; it is NOT multi-port waveform
coverage. Analytical matrix/metadata tests separately cover 1/2/4 ports.

The batch then stopped progressing during export: a temporary link-export
root had CSV and MAT outputs but no PNG, with MATLAB process CPU nearly
unchanged for several minutes and a live MATLABWindow child. This suggested
the figure-generation stage, but no exact MATLAB stack was obtained. Sent
Ctrl-C to diagnostic session 96530, observed exit 1, and verified both its
MATLAB processes absent before starting another batch. No production files
or output folders were removed; partial artifacts remain. Do not interpret
the interrupted export as a pass or a solved graphics problem.

Fresh isolated export-first session 20621:
logs/pusch_transmitter_precoder_export_20260909_01.log. The unchanged
testLinkExportPipeline PASSED, followed by testArtifactIntegrity,
testStrictProxyGuards and testSchedulerGrantConsistency. No renderer
substitution, weakened assertion, or SaveFigures=false workaround was used.
Both E2E tests are now running. This leaves graphics stall reproducibility
OPEN despite the fresh-process pass. Keep dependencies frozen until exit.

Session 20621 subsequently exited 0 with
TRANSMITTER_PRECODER_EXPORT_BATCH_PASS. Both E2E regressions passed;
the MATLAB processes were absent before any further test edits. Across
the completed focused checks this continuation has nine distinct MATLAB
test functions passing and 110 Python tests passing. The interrupted
graphics stage remains separately recorded above, not erased by the retry.
Next strengthen the existing actual hybrid/transform PUSCH transmitter
fixture with the new evidence validator; this is component coverage only,
not proof of measured SRS-driven transform-codebook scheduling.

Session 99463 exited 0: testPUSCHCodebookCatalogAndHybridElementDomain
passed with the new validator exercised on actual PUSCH_Tx outputs:
two logical ports to four physical hybrid waveform columns, four-port
non-codebook transmission, and two-port transform-precoded codebook
transmission. Existing native codebook catalog comparisons and actual
waveform symbol/matrix assertions were retained. This raises the focused
MATLAB count to ten distinct passing functions; Python remains 110 passing.
These are transmitter/component tests, not a measured adaptive MIMO main
run. Confirmed MATLAB processes absent after exit. Scoped git diff --check
reported no whitespace errors (only existing LF/CRLF conversion warnings).

Handoff: no fresh main 12-dB run, no testAll, no cleanup/commit, and no
Keysight playback were performed in this continuation. The next main-run
gate still needs shared-clock/access/control requalification, physical
QCL/TCI source/activation/spatial-filter authority, complete UL processing
budgets and UCI codebook ordering, measured SRS/CSI-driven rank/TPMI/MCS,
and primary CSV/PNG semantic acceptance. Do not present per-data-window
carrier RSSI as the complete UE-reported NR-RSSI measurement procedure.

## 2026-09-09: measured feedback must not borrow rank/TPMI

Previous goal turn: PROGRESS (actual hybrid/transform transmitter regression
and terminal E2E verification). This continuation confirmed no MATLAB
process alive and reread the applicable skills and references before edits.

Read-only QCL audit reconfirmed an unresolved main integration defect:
RASIPDSCHContext.localIntegrationContext constructs Activated=true,
SourceReferenceSignal=PDSCH-DMRS, QCLTypes=A|D and an identity precoder.
The six Msg2/Msg4/SIB1 TX/RX callers do not supply the associated observed
SSB/CSI-RS or a receiver spatial-filter binding. Do not fix this by merely
renaming the DM-RS source. TS 38.214 V18.4.0 section 5.1 associates common
SI reception with the associated SS/PBCH block and RAR with the reference
used for RACH association; actual source and receiver wiring remain OPEN.
Reference: https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.04.00_60/ts_138214v180400p.pdf

A second real issue was reproduced at the existing SRS runtime test:
the test used to require that an invalid two-port TPMI 12 be replaced by
some other finite executable TPMI. Strengthened it to require unavailable
evidence instead, and to test rank/TPMI atomicity in strict and non-strict
modes. Red session 20485 exited 1 exactly at that first assertion, log
logs/srs_feedback_no_substitution_red_20260909_01.log. This is an explicit
correction of a test that previously required fabricated feedback, not a
relaxation of production validation.

Patched CoupledTruthRuntime.sanitizeFeedbackPMI to validate report values
without rounding, vector truncation, configured rank/PMI substitution, or
first-valid-codebook rescue. UL validates the exact reported rank/index
against the active configured logical port catalog without tuple clamping.
Latest SRS feedback now refreshes rank/TPMI as one observation; missing or
invalid rank/TPMI cannot retain the previous pair under a new report clock.
No TDD/FDD-specific branch or scenario constant was added.

Focused session 57548 is live in
logs/srs_feedback_no_substitution_20260909_01.log. The strengthened
testLLSULSRSRITPMIEstimator has passed (SRS_FEEDBACK_NO_SUBSTITUTION_PASS);
causal AMC, control gating, scheduler consistency and actual shared PUSCH
late CSI are still pending. Keep production and tests frozen until exit.
Main 12-dB qualification, QCL integration, full timing and broad suites
remain OPEN; this repair does not establish complete transform-codebook
SRS selection or eight-port waveform execution.

Session 57548 exited 0: all five focused functions passed, including the
actual shared TDD fixture. CSV/PNG root:
C:/Users/anup0/AppData/Local/Temp/tpa90899ed_c6ed_4fe0_b403_89c38037d2c6.
Read-only visual inspection of its PUSCH EVM, carrier-window RSSI and
requested/applied PMI PNGs confirmed measured-point presentation, not a
fabricated sweep. Independently recomputed both RSSI branches from exported
linear symbol powers: -81.17218752302415 and -81.32577357259647 dBm, with
zero numerical difference at the displayed precision. Seven PNG families
exist in this component snapshot; only those three were visually inspected
in this continuation, not all seven or all main-run outputs.

After terminal process verification, removed physical nTxAnt as a fallback
for the DL CSI logical codebook port domain; missing logical-port evidence
now remains unavailable. Registered the strengthened SRS regression in
testAll, but did not launch the full suite. Final session 11816 is live in
logs/srs_feedback_no_substitution_20260909_02.log: reruns the same five
focused tests, strict proxy guards, and both required E2E regressions.
These E2E tests retain their existing component duplex fixtures, not a new
main FDD campaign. Scoped diff --check is clean apart from CRLF warnings.
Keep code/test dependencies frozen until this exact session terminates.

Final session 11816 exited 0 at completion of
SRS_FEEDBACK_FINAL_BATCH_PASS; verified MATLAB processes absent. All eight
requested MATLAB functions passed on the final code: strengthened SRS
estimator/runtime provenance, causal AMC, control-access gating, scheduler
grant consistency, actual shared-PUSCH late CSI, strict proxy guards,
E2E FastVsTruth (seeds 111/303), and TruthPacketSemanticCampaign (11/22/33).
Python session 90467 exited 0: 110 passed in 10.55 seconds across the four
measurement/publication/output-contract/dashboard test files. Actual final
shared fixture CSV/PNG root is
C:/Users/anup0/AppData/Local/Temp/tp3a2152c9_8553_40f6_9d93_01e76a950a5d;
component root is
C:/Users/anup0/AppData/Local/Temp/tp14908439_de0a_470e_87a8_7cc2f3efa957.
It retained 3522 actual UL symbol pairs and 8.62254422951% RMS EVM.

Next continuation must address the original main integration objective,
not treat the passing feedback subset as production qualification. QCL
association must be explicit through Msg2/Msg4/SIB1 TX and RX adapters,
with actual source identity, applicable source timing/spatial reception,
and TX spatial mapping. Do not turn the current identity matrix into a
claimed beam or label common-procedure QCL as observed MAC TCI activation.
Follow that with main shared-clock/access/control and complete 12-dB
CSV/PNG qualification. Full UCI processing/codebook budgets and broader
MIMO/transform, impairments, 6G-candidate and instrument goals remain OPEN.
No main run, testAll, cleanup, commit, or historical artifact rewrite was
performed this continuation. Goal remains ACTIVE; this turn is PROGRESS.

## 2026-09-09: common DL physical projection bound to associated SSB

Previous goal turn: PROGRESS. Confirmed no MATLAB process alive and reread
all applicable skills/references. Further tracing refined the earlier QCL
diagnosis: runFourStepRA already applies an external physical antenna
projection to Msg2/Msg4. Therefore the identity precoder inside the PDSCH
adapter alone does NOT prove that the transmitted RF waveform was un-beamed.
The actual gaps are the adapter's fabricated activated TCI/QCL metadata,
source-to-receiver association, and inconsistency between the external RA
projection and SSB transmitter matrix/bitmap resolution.

The old RA projection read phy.ssb.runtimeSSBIndex independently of
random_access.associated_ssb_index. It accepted only numeric per-index
matrix rows, whereas SSBBurstPlan accepts one shared row, one row per SSB,
or a cell collection. Consequently a valid shared SSB matrix could fail
RA for a nonzero associated index, and a divergent runtime index could
select a beam unrelated to RACH. Replaced that local resolver with
resolveAssociatedSSBProjection, which validates matching explicit associated
and runtime IDs plus source, and uses SSBBurstPlan's same private bitmap,
matrix-expansion, normalization, ID-expansion and row-digest routines via
selectedPrecoderFromConfig. Inactive selected SSBs are rejected. Non-finite
and non-binary numeric bitmaps now fail rather than convert to logical true.

Actual Msg2/Msg4 physical projection uses this resolver. Both standalone
runtime-channel and shared-stream stage rows retain TxSSBAssociationJSON
with SSB identity, source, row-matrix hash and projection-matrix hash. The
projection hash is checked against the matrix before attaching evidence.
The scope explicitly excludes receiver QCL proof or MAC TCI activation.
No new YAML parameter or duplex-specific branch was introduced.

New testRAAssociatedSSBProjection uses the authored TDD config and actual
SSB_Tx IQ: a complex four-element mapping matches scalar-reference IQ
multiplied by exactly the selected non-conjugated row. It covers a nonzero
SSB index, shared/full/cell matrix forms, matrix digests, mismatched source
IDs, absent source, inactive SSB, wrong element count and malformed bitmaps.
Its association source is explicitly a component fixture, not a measured
UE selection claim. It does not by itself test received Msg2/Msg4 spatial
QCL in the complete main run.

Session 97950 in logs/ra_associated_ssb_projection_20260909_01.log exited 1:
new actual-IQ test passed, then testInitialAccessSSBPhaseCore errored because
its existing paired/Case-B carrier fixture omitted duplex authority.
Added explicit FDD to that existing paired component fixture; did not
weaken resolveDuplexMode or start a main FDD campaign.

Session 78120 is now live in logs/ra_associated_ssb_projection_20260909_02.log.
The new IQ/association test, complete SSB phase-core function suite,
RASIPDSCHStrictOwnership, strict proxy guards and scheduler consistency
passed (RA_ASSOCIATED_SSB_FOCUSED_PASS). Both E2E regressions are running.
Freeze dependencies until that exact session terminates. Full QCL/TCI
integration, shared-stage CSV integration acceptance, main 12-dB run,
full processing/UCI budgets and the remaining original goal remain OPEN.

Session 78120 exited 0 with RA_ASSOCIATED_SSB_BATCH_PASS. All seven
requested MATLAB test functions passed (the SSB phase-core function itself
contains 11 tests), including both E2E suites. Confirmed MATLAB processes
absent before modifying any test. Strengthened the existing actual
testFourStepRARuntimeStageComposer with an explicitly labelled nonzero SSB
association fixture and primary stage-table assertions: Msg2/Msg4 must
carry source ID and projection digest, while UL stages must not inherit a
downlink SSB mapping claim. Session 2107 is live in
logs/ra_associated_ssb_stage_export_20260909_01.log. No production edits
were made after the passing batch. Keep dependencies frozen until exit.

Session 2107 exited 0 with RA_ASSOCIATED_SSB_STAGE_EXPORT_PASS; MATLAB
processes are absent. Actual standalone runtime-channel Msg1 through
RRCSetupComplete completed and retained correct per-stage association
evidence. This brings the continuation to eight passing MATLAB test
functions, including the SSB function-suite and both E2E regressions.
The generated-source/row assertions do not claim a main shared-clock run
or an actual measured UE SSB-selection experiment. Scoped diff --check
has no whitespace errors, only CRLF conversion warnings.

Next: use the now-unified physical association to remove the fabricated
ActivatedTCIStates/PDSCH-DMRS self-reference in RASIPDSCHContext. Common
procedure QCL association and explicit MAC TCI activation must remain
separate concepts. Bind Msg2/Msg4 to RACH-associated SSB (CSI-RS only for
actually implemented applicable procedures), and SIB1 to its associated
generated/received SSB at the respective TX/RX authority boundaries.
Retain applicable source timing and receiver spatial-parameter semantics;
do not advertise TX matrix matching alone as applied receiver QCL.
Then requalify actual main 12-dB shared-clock/control/access/UL and output
semantics before longer/25-dB/6G-candidate/instrument work. Goal remains
ACTIVE; no main run, cleanup, commit or historical output rewrite here.

## 2026-09-09: explicit common-procedure QCL binding (in progress)

Removed the fabricated ActivatedTCIStates/PDSCH-DMRS self-reference from
RASIPDSCHContext. CommonPDSCHQCLReference requires an explicit SSB source,
procedure, serving PCI and authority. Msg2/Msg4 resolve the RACH-associated
SSB through the same canonical selector as the physical projection; SIB1
TX uses actual SSB_Tx timing identity and RX uses received PBCH identity.
Dedicated PDSCH retains its existing activated-TCI validation. Precoder
matrix/assignment/configuration digest validation is unchanged. Common
bindings explicitly say TCI activation is not applicable and receiver
parameter reuse has not been evaluated by this reference binding.

The common assignment factory still has legacy numeric TCI compatibility
fields: this patch must not be described as removing all such fields or
proving physical QCL reuse. A further physical-domain SIB1 review found
that standalone SI waveform composition may pad a single logical SI port
beside an already multi-element SSB waveform without matching its selected
beam. Investigate actual domain ownership before applying any projection;
the logical-RF-chain mode has an external mapping owner.

Session 94596 is running logs/common_qcl_association_20260909_01.log.
Strict common decode/ownership, dedicated QCL and TCI, associated SSB IQ,
actual RA stages, strict proxy guards and scheduler consistency passed
before the batch entered both E2E suites. Dependencies remain frozen
until the session is terminal and MATLAB processes are absent. Main TDD
and remaining UL/RSSI/QCL qualification are still OPEN.

Session 94596 exited 0 with COMMON_QCL_ASSOCIATION_BATCH_PASS; MATLAB
processes absent before further editing. All nine test functions passed.
Then corrected the standalone physical-domain SIB1 composition: its actual
post-IFFT SI waveform is multiplied by the selected row retained by the
actual SSB producer. Logical-RF-chain mode leaves mapping to its external
owner and explicitly records MatrixAppliedHere=false. SIB1Grid remains
the logical pre-spatial-mapping grid with an explicit domain field. The
TX object retains the used matrix, generated SSB matrix hash, domain,
owner and dimensions. No receiver-QCL-reuse claim is inferred from this.

The strengthened ownership test compares noiseless scalar and four-element
complex mappings sample-for-sample, including total composed waveform,
decodes through an explicitly labelled analytic unit-fixture channel, and
checks logical mode does not apply the matrix twice. New focused batch:
logs/common_qcl_ul_verification_20260909_01.log. It includes PRACH physical
origin, UL TX/RX clock/TA/TDD guards, actual PUCCH and SRS received timing,
late UCI/CSI on PUSCH, SRS RI/TPMI validity, normalized UL power and SSB
window power, followed by both E2E regressions. Dependencies now frozen.

Session 70375 reached COMMON_QCL_UL_FOCUSED_PASS: all ten focused functions
passed, including the new SIB1 complex physical-element IQ regression.
The actual TDD late-HARQ PUSCH component retained 3522 received symbol pairs,
8.55072257645% RMS EVM, TB CRC=1 and UCIOnPUSCHApplied=1. Primary CSV:
C:/Users/anup0/AppData/Local/Temp/tp61f17f03_01ef_4fd3_9dbf_79b930d07ae2/received_pusch.csv.
Independently recomputed each branch RSSI from its persisted
AllocationCarrierPowerMeasurementJSON.SymbolPowerPerAntenna_W as
10*log10(1000*mean(symbol powers)): -81.170415264764273 and
-81.336816006119278 dBm, matching stored values within 1e-10 dB. Scope
remains received_data_symbol_window_full_carrier_not_ue_NR_RSSI_report.

The actual TDD late-CSI/HARQ component also passed with 3522 received symbol
pairs and 8.62254422951% RMS EVM, retaining CSI-RS feedback across slot-10
physical PUSCH reception and slot-11 delivery. Component primary root:
C:/Users/anup0/AppData/Local/Temp/tp52a7bcf9_05e8_4339_9154_9ca47b6ffeff.
These are explicitly component fixtures, not a completed main run or
adaptation/conformance qualification. Both E2E suites are now running.

After terminal exit and MATLAB process absence, next action is the normal
runSingle front door with unchanged lls_causal_tdd_connected_feedback_fixture
(55 slots, nominal 12 dB, TDD, real CSV/figures enabled), fresh tag
short12_common_qcl_ul_recheck_20260909_01. Its destination was checked absent.
Port 62906 currently has no listener; do not claim a WebGUI-launched run.
Preserve earlier outputs and freeze dependencies throughout main execution.
No main-run qualification or instrument-ready export claim is authorized by
these component results. Broad testAll/NR suites remain OPEN under the
focused-test restriction; goal remains ACTIVE.

Session 70375 exited 0 with COMMON_QCL_UL_BATCH_PASS. All twelve test
functions passed, including both E2Es after the SIB1 physical-IQ patch.
Confirmed no MATLAB process alive; scoped diff --check has no errors.
Launched the fresh main nominal-12-dB TDD diagnostic using the normal
runSingle front door, log logs/short12_common_qcl_ul_recheck_20260909_01.log.
The launch command asserts TDD, nominal SNR 12, 55 slots, enabled CSV and
figure/PNG flags and absent destination before invoking runSingle. Treat
startup as unconfirmed until its preflight marker and process/log appear.
Do not edit production/test/app dependencies or start another MATLAB
while it executes, including finalization. Main completion is not yet
observed and must not be reported as a qualification pass.

Launch wrapper correction: session 22520 incorrectly used result.Status;
runSingle exposes result.ScenarioStatus. Detected before runtime execution,
verified worker 18264 and launcher 10180 command lines belonged to this
exact diagnostic, then stopped them. A startup race emitted preflight and
Preparing LLS run before termination (exit 1); preserve any _01 startup
artifacts. No scheduling slots executed in the retained log. This is a
launcher defect, not a PHY failure and not a reason to change production.
Restart with fresh _02 tag/log and correct ScenarioStatus field only after
both processes are absent. Do not reuse/clean the _01 destination.

Corrected main session 15390 is LIVE, worker 13068 and launcher 17764,
log logs/short12_common_qcl_ul_recheck_20260909_02.log. Observed
SHORT12_COMMON_QCL_UL_PREFLIGHT_PASS at 07:36 UTC: TDD, nominal 12 dB,
55 slots, actual CSV/PNG flags and fresh destination passed. Dependencies
remain frozen. Next continuation must monitor THIS session/log, not start
another MATLAB or rerun passing component suites. Confirm process exit
before any edits; audit actual main UL/DL/access/source-clock rows and
all CSV/PNG semantics after completion or genuine failure. Exhaustive audit
tool supports --preview-rows 5 and --strict-value-closure; use a separate
audit output directory and retain all measured primary output unchanged.

Current turn: PROGRESS, not full qualification. Two concrete common-DL
repairs completed: explicit common SSB/QCL association without fabricated
activated TCI binding, and actual physical-domain SIB1 post-IFFT beam
mapping. Latest twelve-function MATLAB batch passed. Main shared-clock,
complete receiver QCL/TCI use, common assignment legacy TCI compatibility
fields, UE-defined NR-RSSI, all artifact semantics and wider original goal
remain OPEN. No commit, cleanup or historical-output rewrite performed.

## 2026-09-09: main preflight now exposes stale PDSCH occasion allocation

Previous turn was PROGRESS (two actual fixes, twelve passing MATLAB
functions, main launch). Main session 15390/worker13068 is still live in
failure finalization, NOT available for a second MATLAB. Its _02 log now
proves a pre-slot-zero failure at 07:37:03 UTC:
sixgr:truth:EnabledAllocationUnresolved wrapping
sixgr:phy:grid:allocREsPDSCH:SSBDMRSCollision. Slot 0 configured baseline
PDSCH has 126 DM-RS REs inside the SS/PBCH reserved region. No scheduling
slot executed. Persisted components/frame_grid/csv/allocation_resolution_preflight.csv
shows only PDSCH unresolved; FRAME, SSB/PBCH, Type0, SIB1, PDCCH, CSI-RS,
TRS, PRACH, PUCCH, PUSCH and SRS produced planned coordinates. None of this
is runtime reception evidence. Preserve the failed run and its status.

Root cause located in buildPlannedREAllocation.localPDSCH: it invokes
allocREsPDSCH on the initial carrier BEFORE looping over data occasions,
then reuses the returned PDSCH object for every slot. This both bypasses
the scheduler's existing SSB-safe PRB selection and reuses occasion-owned
CSI-RS/TRS/SSB ReservedPRB exclusions. SchedulerBase.ssbSafePRBSet already
uses actual TimingRelationEngine data slot plus actual DM-RS indices to
exclude colliding PRBs before TBS/coding; the low-level collision guard
must remain strict. Main failure is not caused by the new common-QCL
binding (materialization was not reached).

Next implementation, only AFTER session terminal and all MATLAB absent:
extract the existing DM-RS-index-to-BWP-PRB exclusion arithmetic into a
shared pure grid helper used by SchedulerBase and planning. Rebuild each
DL planning occasion from applyRuntimeCarrierTimeline and the config
factory, select its available PRB pool before allocREsPDSCH, then retain
exact indices from that occasion. Keep resource pools explicitly planning
evidence, not actual scheduler grants or runtime occupancy. No mutation of
DM-RS, MCS, waveform timing, or YAML to evade the guard. Also resolve the
UL planning allocation on its own actual slot rather than cloning slot 0.
Add regression over active/repeated SSB and quiet slots, verifying no
planned PDSCH RE overlaps the reservation and no stale exclusion leaks
into quiet slots. Re-run testExactDLULAllocationPreflight (existing FDD
fixture), authored TDD preflight, testSSBPRBSymbolReservation and
testSchedulerSSBResourceSelection; preserve the original collision
negative tests. Then both E2E regressions and a NEW main TDD tag.

No executable changes in this continuation yet: finalization remains live
and all production/test/app dependencies are frozen. Current turn has
PROGRESS via authoritative main failure/root-cause evidence plus verified
wait on session15390; goal remains ACTIVE, not blocked or completed.

## 2026-09-09: per-occasion preflight and false UE-control chart repair

Session15390 exited 1 after finalization; MATLAB processes absent before
patching. Original SSB/DM-RS preflight failure retained. Recovery also
reported sixgr:artifact:TerminalBrowserClosureFailed after three passes
(materialization=0, visual=1, lineage=1). No main scheduling slot executed.

While finalization was live, visually inspected its newly generated
contract__ue-side-state-ue-power-ue-control__ue-control-report-timeline.png.
It falsely labelled three points at x=2,5,11 as runtime measurements.
The aliased reports/csv/live_ue_control_state.csv actually contained
pusch_pucch_outputs coverage rows (Availability=config_only/not_available),
not UE observations. The chart mapped generic ValueNumeric and substituted
row ordinal for absent slots. This was not a real runtime evidence source.

Removed the coverage-summary source from live_ue_control_state alias.
The chart now uses actual packet_flow/csv/live_pucch_grants.csv feedback
state (including that ledger's multiplexed feedback semantics), requires
ControlObservationAvailable=1, explicit Slot, and RuntimeStateUpdated.
Y label specifies received feedback applied (0/1). Explicit metric chart
adapter also rejects config/unavailable/disabled and proxy/placeholder
rows. This is not a substitute for a broader full UE-control state model.
Python: 32 passed in test_lls_ue_control_chart_authority.py and
test_lls_contract_materialization.py. Original failed-run CSV/PNG unchanged.

Extracted existing SchedulerBase DM-RS-to-BWP-PRB exclusion arithmetic into
sixgr.phy.grid.pdschPRBsWithoutReservedDMRS; scheduler uses the same helper.
Preflight now creates the config factory per data occasion, derives that
occasion's SSB reservation, excludes colliding DM-RS PRBs before coding
allocation and refreshes CSI-RS/TRS/SSB reservations there. PUSCH planning
also resolves on its own slot. These exported pools can have multiple
islands and are explicitly NOT scheduler grants; actual schedulers still
enforce contiguous chunks, queue and capability restrictions. Empty pools
have no primary rows and all-blocked windows still fail NoPDSCHOccasion.
No collision exception, fake TBS, scenario-specific YAML or MCS change.

New registered testPDSCHOccasionAllocationPreflight uses the authored
55-slot TDD config, checks every represented occasion against SSB
reservations, requires quiet-slot DM-RS retention, and rejects an all-blocked
window. Session71413 is LIVE in logs/occasion_preflight_repair_20260909_01.log.
It runs that test, existing FDD exact preflight, SSB collision tests,
RR/PF selection, scheduler consistency, strict proxy guards, and both E2Es.
Dependencies frozen until terminal exit and MATLAB absence. Scoped diff
--check clean. Main recheck, full output semantics and entire goal OPEN.

Session71413 reached OCCASION_PREFLIGHT_FOCUSED_PASS: all six focused
MATLAB functions passed. Existing FDD exact preflight produced 64889
planned rows / 597778 exact RE coordinates, not executed waveform rows.
Both E2E regressions still running; worker12264 and launcher8248 alive.
Additional Python checks (running contract materialization, realtime control
preview, browser output coverage, radio measurement plots): 80 passed.
Together with the first 32, 112 Python tests passed. Generic direct-chart
fallback was inspected: it requires canonical x_value/y_value schema and
does not convert arbitrary coverage values into replacement observations.

Next fresh main destination checked absent:
results/lls/lls_causal_tdd_connected_feedback_fixture/short12_occasion_preflight_recheck_20260909_01.
Launch only after batch exit0 and all MATLAB processes absent; normal
runSingle with authored unchanged 55-slot nominal12 TDD and CSV/PNG flags.
Use result.ScenarioStatus, not nonexistent result.Status. Preserve _02
failed preflight and false-chart artifacts as regression evidence; do not
rerender them using changed code and call them original run output.

Session71413 exited0 with OCCASION_PREFLIGHT_BATCH_PASS: eight MATLAB test
functions passed, including both E2Es. All MATLAB processes absent before
next launch; scoped diff --check clean. New main launch uses the authored
55-slot nominal12 TDD config and tag short12_occasion_preflight_recheck_20260909_01,
log logs/short12_occasion_preflight_recheck_20260909_01.log. Correct runner
field result.ScenarioStatus. Freeze dependencies until that main process
is terminal; no main success/publication claim yet. Current turn PROGRESS:
shared allocation fix, false runtime chart fix, eight MATLAB and 112 Python
checks passed. Original broader qualification gates remain OPEN.

Main session99553 confirmed LIVE: MATLAB worker8064, launcher2624.
Observed SHORT12_OCCASION_PREFLIGHT_CONFIG_PASS and Preparing LLS run at
08:00:55 UTC. This marker is CONFIG preflight only; exact RE allocation
preflight and scheduling have not yet been observed complete. Monitor this
same handle/log. Do not start another MATLAB or edit production/test/app
dependencies. All old failed-run evidence remains unchanged.

Main advanced past the original exact-allocation failure into slot1/55
at 08:02 UTC. Actual log shows acquired=0/access=0/eligible=0 and no data
grants; UL K2 prescheduling was legitimately deferred because its target
hits the opposite fixed TDD direction. This proves startup integration
past preflight, NOT complete access/connected-data execution. Session99553
still live; continue monitoring rather than starting another run. Complete
semantic/physical CSV and PNG audit remains pending measured main output.

## 2026-09-09: nominal12 main reaches PRACH; capture publication failure

Session99553 advanced to slot17/55 and failed at 08:08:15 UTC with
MATLAB:save:unableToWriteToMatFile in exportSharedRARObservation. The
temporary v7.3 file under rar_monitoring_observations has an absolute path
length of 261 characters and zero bytes; C: has about 193 GB free. This
matches the already-documented long-path/synchronized-tree hazard handled
by sixgr.util.matSave. RA, RAR and UL-control exporters still bypass that
validated writer with save(tempname(folder),'-v7.3') plus movefile. Planned
repair after process exit: use the existing validated filesystem writer,
retain capture wrapper and ForceV73, preserve duplicate guards and all IQ.
No production/test/app edits while MATLAB finalizes failure evidence.

Read-only measured checks: four SSB/PBCH/SIB1 rows decoded with all CRCs
passing. Actual beam IDs 1,2,3,0 have SS-RSRP -80.9243,-89.2872,-77.4934,
-76.0461 dBm respectively. Selected beam0 is strongest; SelectionSource
is coupled_receiver_measured_single_received_ssb_pbch_burst. All four
observations cover samples [0,38400), fs=7680000, delivered at slot6.
All per-branch SS-SINR values independently close to 10log10(desired/noise)
within 1e-8 dB. This checks arithmetic, not complete estimator conformance.
The window reference RSRP is the toolbox coherent SSS/PBCH-DMRS estimator,
distinct from primary linear SSS power; do not merge those quantities.

The main persisted one actual Msg1 UL stage at zero-based slot14, sample
interval [111183,115192), tx3840/rx4009 samples. Shared fading/channel/RF
evidence exists, SelfLoopWaveformUsed=0. Its power decision uses decoded
SIB1 5 dBm minus filtered selected SS-RSRP -76.0460576482401 dBm, giving
81.0460576482401 dB pathloss; ProxyUsed=0 and FallbackUsed=0. This is
actual PRACH execution evidence, NOT completed access or connected UL.
Current run stopped with zero PDSCH/PUSCH trial rows. PUCCH, PUSCH, SRS,
UCI, full shared-clock completion and the broader goal remain OPEN.

Session99553 exited1 at 08:22:34 UTC; all MATLAB processes then absent.
Failure recovery also reported TerminalBrowserClosureFailed (3 passes,
materialization=0, visual=1, lineage=1). Original artifacts preserved.
Read-only HDF5 inspection of the real Msg1 capture confirms PreambleDetected=1,
PreambleIndexTx=PreambleIndexDetected=0, metric0.3373883159686892 above
threshold0.020412414523193152, ProxyUsed=0, RuntimeSelfLoopWaveformsUsed=0.
audit_lls_ra_capture.py passed all10 arithmetic/clock/coverage checks for
the ONE observed Msg1 row; terminal_qualification=false, not full access.

After exit, patched exportSharedRAObservation, exportSharedRARObservation,
exportSharedULControlObservation to use existing sixgr.util.matSave with
struct('capture',capture), UseArtifactStore=false, ForceV73=true. All
duplicate guards, actual samples, nested evidence and v7.3 format retained.
Extended testMatSaveFilesystemAtomic with exact complex-IQ (single/double),
clock, nested replay/table and NaN round-trips under all three deep folders.
Scoped diff --check clean. Session38945 is the single MATLAB regression
batch, logs/shared_capture_persistence_20260909_01.log; its long-path
MAT_CAPTURE_LONG_PATH_ROUNDTRIP_PASS marker observed. Seven total test
functions include export/manifest/preservation/scheduler and both E2Es.
Freeze executable dependencies until this batch exits.

Terminal-run exhaustive audit (Python session87364 exited1) is separate:
results/lls/qualification_working/audits/short12_capture_failure_20260909_01.
520 CSVs,227119 rows,17863 columns; first FIVE rows of every CSV retained;
87 PNGs,zero raster decode/issue failures,zero chart semantic failures.
58 required CSV semantic failures across41files: mainly missing downstream
trials/runtime evidence, plus missing identity/reference metadata. Two
structural failures are empty headers in live_link_adaptation_input_table.csv
and live_waveform_preview.csv. No false pass is inferred from zero executed
PDSCH/PUSCH rows or from 27 coherent terminal-status mirrors.

New confirmed report-producer bug: localLowPAPRRows in exportLLSReportingBundle
sets papr=NaN when no UL samples exist, then exports mean/p95 as available
(normalized to observed), CountsTowardCoverage=1, ValueNumeric=NaN. The same
two false rows appear in both pusch_pucch_outputs and lls_output_metric_rows.
Fix after regression exit: retain feature_enabled as config_only; emit
measured PAPR statistics only for actual finite UL PAPR evidence. Remove
the implied measured-gain/zero-by-configuration wording from these PAPR
rows; no comparator gain has been observed. Add empty and finite-evidence
report regressions. Other audit failures remain open for separate source
repair and complete-main recheck, not synthetic coverage completion.

Session38945 exited0 with SHARED_CAPTURE_PERSISTENCE_BATCH_PASS; all seven
MATLAB functions passed. Confirmed no MATLAB processes before the next patch.
Then repaired localLowPAPRRows: keep feature_enabled config_only; return
without observed rows when finite PAPR evidence is empty; otherwise compute
actual mean/p95 and explicitly disclaim measured reduction/gain without a
matched comparator. No zero-gain configuration inference is appended there.
Extended testLLSAvailabilityAggregation for empty, NaN-only, and finite-plus-
NaN report-only fixtures; exact mean/p95, no missing-value coverage credit.
Production fixtures/old main artifacts were NOT rewritten.

LIVE session2194, worker9932/launcher10040:
logs/ul_papr_reporting_authority_20260909_01.log.
Observed UL_PAPR_MEASUREMENT_AVAILABILITY_PASS: the three report cases passed.
Remaining six functions (link export, artifact integrity, preservation,
scheduler consistency, both E2Es) must finish before any executable edits or
new MATLAB main launch. This is a second single-worker focused batch, NOT
testAll or a new main FDD campaign. The broad regression/NR suites remain
open and no complete simulator qualification claim is made.

Next after terminal exit0 and MATLAB absence: fresh unchanged authored
55-slot nominal12 TDD main via runSingle, tag
short12_occasion_preflight_recheck_20260909_02 (check absent before launch).
Retain CSV/PNG/raw IQ settings and physical thermal-noise mode, no forced
measured-SINR values. Monitor through the former slot17 RAR save boundary,
then Msg2/3/4/RRC, CSI/SRS/control/data/UCI clocks, deferred HARQ and final
publication. Do NOT count the old slot17 run as passed or rerender its
failed artifacts with patched producers. Full UL, QCL/TCI receiver use,
RSSI windows and all semantic audit failures remain original-goal gates.
Current goal turn PROGRESS (two concrete fixes + independent measured
checks + complete failed-run inventory), not blocked and not complete.

## 2026-09-09: capture repair verified in the main TDD stream

Previous turn classified PROGRESS. Session2194 exited0 with
UL_PAPR_REPORTING_AUTHORITY_BATCH_PASS at 08:38:02 UTC; all seven functions
passed, including the expanded availability test and both E2Es. Confirmed
all MATLAB processes absent before launching the unchanged 55-slot TDD main.

LIVE main session6869, worker10232/launcher12856, start14:09 IST:
logs/short12_occasion_preflight_recheck_20260909_02.log.
Output results/lls/lls_causal_tdd_connected_feedback_fixture/short12_occasion_preflight_recheck_20260909_02.
SHORT12_CAPTURE_RECHECK_CONFIG_PASS verifies nominal12,TDD,55slots,CSV/PNG
and rawIQ/saveRawWaveforms enabled. Exact allocation passed; physical runtime
mode is receiver_noise_figure_thermal_noise, no forced measured12dB.
Executable dependencies remain frozen until main/finalization process exits.

The existing WebGUI was not listening. Verified existing venv imports
sys/yaml/mysql.connector/waitress and Python>=3.10 before starting existing
apps/start_lls_web_dashboard.ps1 with BindHost127.0.0.1,Port62906,threading,
NoBrowser,SkipFirewallRule. No dependency installation or firewall changes.
Service session94815, listening PID11820. /realtime returns200; /api/status
returns401 without authentication, which remains intact. User must sign in
normally; no authenticated browser/live-table verification is claimed.
Current filesystem virtual run id, using the existing stable path hash:
9813259350; viewer /realtime?run_id=9813259350. Main launched via runSingle,
not the WebGUI launch action. No additional MATLAB was started by the viewer.

All four current PBCH/SSB rows have passing BCH/SIB1 CRCs; SS-RSRP and
SS-SINR exactly equal the previous main's corresponding per-beam values.
Independent HDF5 readback also proves Msg1 TXAfterRF,RXBeforeRF,RXAfterRF,
RXAfterDigitalGainCompensation arrays exactly equal the old run's arrays.
At slot18 the former failure is crossed: real RAR_15.mat (6312240bytes) and
RAR_16.mat (6793943bytes), both250-character target paths, reopen via HDF5.
Their actual intervals are [115200,122895) and [122880,130575), fs7680000.
The stage CSV includes Msg1 UL zero14 and Msg2 DL zero16. Slot19 observed
live at08:48UTC; access/connected UL/full qualification not yet complete.

Read-only new grid gap: at slot13 the observed grid contains600 TRS rows
but NO SSB/PBCH/SIB1 occupancy despite actual received PBCH evidence. Source
trace: localCompleteSharedControlObservations PBCH branch completes the real
receiver and enqueues BroadcastResultDelivery, but unlike TRS it neither
builds nor appends actual TX observed RE allocation. Delivery also does not
append it. prepareCellSearchBroadcast retains the actual Tx, including
PDCCHTx,PDSCHTx,SIB1Grid/SIB1SpatialMapping,SSBInfo,SSBWaveInfo,SSBBurstPlan.
After this main exits, implement and test publication from that retained
transmitter evidence and committed physical interval; do NOT substitute
planned allocation or infer signal-specific RE ownership from decoder
success. Preserve slot origins, SSB/carrier numerology and logical-vs-physical
port domains, cell broadcast deduplication and common SIB1 channel labels.
The same old audit's two empty-header sources are also traced: waveform
preview directly exports meta.WaveformPreviewTable default table(); link
adaptation returns table() when no DL/UL trials. These remain open, not fixed
by current MATLAB work or by UI restoration. Full goal remains ACTIVE.

Main continuation reached slot22/55 at08:50:44UTC. Actual stage CSV now
contains Msg3 UL zero19, interval[145743,153592),tx7680/rx7849 samples,
SelfLoopWaveformUsed=0. Independent HDF5 read of its received-stage capture
shows Msg3PUSCHCrcPass=1 and Msg3DecoderIterations=1. This is actual Msg3
PUSCH CRC evidence, not connected data/HARQ adaptation qualification. Keep
monitoring session6869; do not restart, edit dependencies, or declare the
main done. Next expected work: Msg4/RRC then received SRS/CSI and connected
DL/UL grants, deferred HARQ/UCI clocks, all remaining output/protocol gates.
This goal turn is PROGRESS: second regression batch completed, current
TDD main crossed the exact prior RAR failure, verified unchanged Msg1 IQ
and SSB measurements plus Msg3 CRC, restored authenticated loopback viewer,
and identified the real missing shared-broadcast observed-grid binding.

## 2026-09-09 current main terminal: access/SRS pass, queued UL slot corruption

Main short12_occasion_preflight_recheck_20260909_02 / session6869 exited1.
Worker absence verified before patches. Actual access capture audit passed
all five stages, including Msg3 PUSCH CRC, Msg4 PDCCH/PDSCH CRC and received
RRCSetupComplete CRC/RRCConnected/StrictOk. ProxyUsed and self-loop flags0.
At slot30 received SRS PASS, NMSE -21.6336032135016 dB, rank1, usable runtime
update delivered31. Two PDSCH rows committed before failure. First slot31
CRC1, actual1064-bit TB, rank1/MCS1 conservative bootstrap, measured post-EQ
SINR50.128398863745 dB. Configured12 is a label in thermal-noise mode, not
a measured-SINR clamp or proof of link adaptation convergence.

At control34 actual UL DCI decoded for data35; preparation then failed
TimingIdentityMismatch:ScheduledAbsoluteSlot, before any connected PUSCH
trial. Root cause is localPrescheduleCoupledULGrants queue metadata assigning
one-based dueSlot35 over scheduler canonical zero-based ScheduledAbsoluteSlot34.
No canonical timing guard changed. New bindQueuedULGrantOccasion validates
the existing canonical identity and queue relation, preserves all timing/DCI
fields and stamps only one-based queue/display labels. Main uses this helper.
testGrantTimingIdentity exercises it with both FDD and authored TDD timing,
including wrong queue and already-corrupted canonical slot rejection.
Focused batch session78854 / logs/queued_ul_canonical_slot_20260909_01.log
started (timing identity, received UL timing, HARQ rebinding, grant consistency).
Outcome pending. No main rerun yet; full qualification remains OPEN.

Failure finalization additionally reported MATLAB:invalidConversion:
Conversion to double from cell is not possible during truthful artifact
recovery. This is a separate OPEN export failure, not repaired by slot fix.
Shared SSB observed-grid binding and empty-header outputs remain OPEN.
No connected main PUSCH/PUCCH/UCI pass or complete CSI/QCL/TCI/RSSI closure
claimed. Existing run outputs and unrelated worktree changes preserved.

Queued-slot focused batch78854 exited0: all four functions passed, including
TDD/FDD canonical queue identity and PF/RR received timing. MATLAB absence
verified. Next sequential batch logs/shared_ul_control_regression_20260909_01.log
runs actual shared TDD PUSCH late HARQ/CSI delivery, late format2 PUCCH,
first-SRS pre-DCI ownership, and both E2E truth/proxy export guards.
These are focused component/regression checks, not a main FDD campaign or
a completed main TDD run. Dependency edits frozen until batch terminal.

Read-only exhaustive audit69908 exited1 with first-five-row previews for
all267 CSVs (229642 rows,13068 columns), zero parse failures,22 required
semantic failures across12 files, and NO PNGs. Saved separately under
results/lls/qualification_working/audits/short12_queued_slot_failure_20260909_02.
Failure classes: missing connected UL trials/curves/grants, missing terminal
manifests/qualification artifacts after recovery crash, missing identity on
MCS/CQI reference and beam-procedure rows, absent waveform preview, channel
reciprocity/angle lineage, and IQ manifest authority vocabulary mismatch.
The IQ row says actual_transmitter_composite_observation; do not change it
to an old whitelist label just to pass an audit. Check actual source before
classifying this as unmeasured IQ. Generic blank/proxy/fallback token counts
are not proof of invented data. Primary raw rows remain preserved.

Actual current CSI row32: MeasurementRSRP_dBm=-76.2143925328849,
MeasurementRSSI_dBm=-51.2060814239442, measured pre-front-end antenna plane,
same-branch RSSI aggregation. Selected SSB0 RSRP=-76.0460576482401. The old
~70dB serving-vs-CSI discrepancy is not present in these source rows.
CSI ReferenceMeasuredSINR_dB=23.0185048549516 and receiver-objective
SINR_dB=27.4979068106181 coexist with generic unavailable ReceiverHest/
MeasuredTrial SINR fields: check semantic mapping, do not equate unlike
SINR domains or claim feedback already consumed by scheduling.

Batch14295 first actual TDD PUSCH late-HARQ-UCI test passed: slot10 received,
delivery11;3522 actual constellation samples,EVM8.55072257645%,postEQ21.333dB.
Other tests still pending; no main PUSCH pass claimed. During read-only
report source inspection, numerical reducers use double(cellColumn) on
CSV-imported all-blank optional measurement columns (e.g. QCLAccuracy).
This is a candidate for the recovery invalidConversion; reproduce exact
stack on a diagnostic copy after current MATLAB exits before repairing.

Continuation checkpoint09:20UTC: batch14295 remains LIVE (MATLAB10344,
launcher18532). Actual late CSI-on-PUSCH test passed (EVM8.62254422951%,
postEQ21.262dB), as did late format2 shared PUCCH feedback clock and power
CSV roundtrip, and first-SRS/pre-DCI arbitration. Remaining existing E2E
regressions run sequential multi-seed fixtures; no batch terminal marker
yet. Do not edit dependencies/start another MATLAB until terminal+absence.
Next: collect final result, reproduce reporting invalidConversion using a
fresh diagnostic copy of current persisted CSVs (never rewrite old run),
fix actual blank-optional numeric import boundary with measured-vs-missing
regression, then remaining observed-grid/channel/CSI identity publication
before next fresh nominal12 TDD main. No25dB/long/mainFDD authorized now.
This turn is PROGRESS: canonical UL queue corruption repaired with four
passed focused functions; actual shared UL/UCI component checks passed;
full267-CSV audit and concrete remaining export gaps preserved. GoalACTIVE.

Terminal update: batch14295 exited0, SHARED_UL_CONTROL_REGRESSION_PASS.
All six functions passed, including both E2E truth/proxy guards. MATLAB
absence verified. No background MATLAB remains; normal existing WebGUI
service is separate. Total this repair: four timing/grant functions plus
six shared UL/control/export functions passed. Main TDD has NOT rerun.

## 2026-09-09 report numeric evidence repair

Previous goal turn classified PROGRESS (verified queue fix and ten passed
functions). Revalidated MATLAB absent before new work. Diagnostic36764
copied air_interface/control/beamforming CSV folders to a fresh temp tree,
leaving original failed run untouched. It reproduced exact main recovery
error: localNumericTrialSummaryRows line1215 double(cell) on DL QCLAccuracy,
called by qcl_estimation_accuracy line671. Log short12_reporting_reproduce_20260909_01.
Exited1; MATLAB absence confirmed before patch.

Added numericMeasurementColumn: missing/blank scalar cells remainNaN,
numeric text parses numerically (never ASCII), real scalar numeric/logical
values retained; malformed nonempty text, vectors/complex/struct fail with
InvalidNumericMeasurementColumn. Physical-range validation is not replaced.
Four numeric/RMSE/ratio/indicator report reducers now use this decoder.
No QCL value, zero replacement, fallback waveform, or status bypass added.
New testNumericMeasurementColumn covers exact values/missing/invalid cases.
testLLSAvailabilityAggregation now includes all-blank QCL CSV input and
asserts no QCL coverage credit. Main scenario or physical samples unchanged.

Batch38532 / logs/short12_reporting_numeric_recheck_20260909_01.log runs
both tests then fresh copied-main CSV report reproduction. Outcome pending;
freeze dependencies while alive. Original artifact audit remains failed,
and successful copied reporting would not qualify original main or UL.

Batch38532 exited0 with NUMERIC_MEASUREMENT_COLUMN_PASS,
UL_PAPR_MEASUREMENT_AVAILABILITY_PASS and PERSISTED_REPORT_COPY_PASS. Copied
report tree is C:/Users/anup0/AppData/Local/Temp/tpb476da35_300e_4576_a8db_58845e9b3fac.
The original failed run remains unchanged. No PNGs are expected directly
from exportLLSReportingBundle when the canonical artifact engine owns
rasters; do not turn legacy plots on to bypass that authority.

After verified MATLAB absence, started required focused export regression
batch84130 logs/report_numeric_export_integrity_20260909_01.log (four export/
grant tests and both E2E truth/proxy suites). Pending terminal. Separately,
copied original resolved config JSON/YAML and failed manifest into diagnostic
tree so filesystem publisher can resolve exact policy. Initial publisher
call rejected absent run metadata; this was a diagnostic-copy setup omission,
not a production failure. Script uses explicit supplied tree as run_folder,
not original folder in copied metadata. No replacement/delete flag used.
Publisher10937 is live, --strict; missing UL evidence must remain failed.
No original output rewrite or completed main qualification claim.

Publisher10937 exited1 as expected for this partial diagnostic source copy:
159 available charts/159 actual PNGs,94 available tables;79 missing tables,
147 missing charts, policy-disabled20 tables/81 charts. It generated413
artifacts without deleting old rasters or writing placeholders. These are
NOT main-run missing counts (many source folders deliberately not copied).
Visually inspected CSI-RSSI: two receive branches at slot32, -51.21/-51.87dBm,
scatter/no invented sweep. Inspected requested/applied PMI0 at31/32 and
identified misleading "Reported" title with no bound delivered feedback.

Export batch84130 exited0 REPORT_NUMERIC_EXPORT_INTEGRITY_PASS (six functions),
MATLAB absence verified. Publisher already terminal. Patched radio plot
display title only when no reported PMI is bound, preserving contract ID,
CSV chart_name, source rows and causal-feedback eligibility. Bumped renderer
cache version to v61 so stale titles cannot be reused silently. Positive
bound-feedback and negative requested-only title tests added;81 radio plot
tests passed. Two contract/running-materialization Python test modules now
running. No main MATLAB simulation started or old-run PNG regenerated.

Other read-only reporting concerns remain OPEN: localCoerceNumericVector
elsewhere can turn single-character numeric cells into character codes;
legacy per-layer/per-codeword BLER reducers mirror aggregate TB Status and
need actual per-codeword evidence rather than inferred layer-level BLER.
Do not interpret this turn's numeric import repair as closure of those
different semantic defects. Shared SSB/SI observed-grid binding remains
required before the next main, along with existing channel/CSI identity gaps.

Terminal: both Python materialization modules passed28 tests (109 total
Python tests for this patch). This turn also passed two focused MATLAB
numeric/report functions, copied-main report reproduction, and six MATLAB
export/E2E functions. No live MATLAB or diagnostic publisher remains.
Broad testAll/NR/config/full qualification suites remain OPEN under the
current focused-run scope; no whole-simulator conformance claim. GoalACTIVE.
This turn is PROGRESS: reproduced and repaired actual report crash, proved
copied measured CSV report completion, materialized/inspected actual PNGs,
fixed PMI evidence labeling with regression/cache invalidation. Next work
must address remaining semantic/physical wiring, not relabel failures PASS.

## 2026-09-09 shared broadcast observed-grid implementation

Previous goal turn PROGRESS. Confirmed MATLAB absent; reread NR-validation
and result-integrity skills/references. Source verified PBCH shared-reception
branch omitted observed grid entirely despite actual TX/complete observation.
SSB_Tx retained logical multi-beam grid but not the mapped waveform-port grid.
New producer retention applies the SAME per-component matrix as the existing
actual waveform multiplication, without changing TX waveform generation.
Uniform single-port path also retains actual Toolbox grid.

buildObservedBroadcastREAllocation now checks full committed observation,
actual slot origin/sample rate/ports, SSB/carrier numerology and validated
Point-A offsets. Validates PSS/SSS/PBCH/DMRS support against retained logical
grid and maps exact per-beam waveform-port indices across carrier slots.
SIB1 uses retained PDCCH/PDSCH grids and actual associated-SSB map; carries
SI-RNTI65535 and separate SSB index/domain/grid hashes/sample interval.
Main PBCH completion appends/deduplicates this cell-broadcast evidence
independently of decoder success. No planned-grid or CRC-based substitution.

Inspection72580 exited1 only because diagnostic requested nonexistent
CandidateTable (actual plan field Rows); no production failure claimed.
First regression74157 exposed real adapter mismatch: strict RA/SI PDSCH has
canonical zero-based resource-plan indices, not legacy tx.PDSCH. Added
canonical branch to buildObservedREAllocation requiring immutable assignment/
resource plan and exact per-port symbols matching the actual TX grid. It
does not manufacture a legacy nrPDSCHConfig. Existing legacy branch remains.
Broadcast tests cover generated waveform/grid equivalence, exact support,
frame/slot origins, distinct SS/PBCH components, SI-RNTI, per-cell dedup and
rejection of incomplete/wrong-origin/wrong-PCI/wrong-SI-offset evidence.

Current regression25275 logs/observed_broadcast_grid_20260909_02.log runs
testObservedBroadcastREAllocation (TDD main config plus FDD component),
testObservedREAllocationRuntimeTruth and testObservedREAllocationDeduplication.
Outcome pending. Freeze dependencies until terminal and MATLAB absence.
Main short12 still not rerun. Existing run artifacts remain unchanged.

Broadcast follow-up:25275 exited1 because the independent test demodulator
used default zero-Hz phase reference, while actual SSB generation declares
its carrier frequency. Test now uses the actual retained carrier frequency
and sample rate, without fitting phase or changing waveform samples.
57550 then passed both broadcast configurations (TDD error2.45e-16, FDD
component error2.19e-16), but existing runtime-grid test failed: legacy
PDSCH facade inherits canonical ContractVersion while exposing one-based
Toolbox index aliases. Canonical branch now applies only to the direct
interface without legacy PDSCH config; legacy branch still verifies its
actual indices against Toolbox materialization. No validation was weakened.
33706/log observed_broadcast_grid_20260909_04 exited0: all three focused
functions passed. MATLAB absence confirmed before further edits.
Added negative actual canonical-grid tampering assertion; verification
pending. Full scheduler, broad NR/testAll, instrument qualification OPEN.

Batch81091/log broadcast_ul_qcl_regression_20260909_01 exited0 with all
eight functions passed: broadcast grid (including altered-grid rejection),
shared received SSB, QCL propagation, activated TCI binding, channel-correlation
diagnostic isolation, actual TDD SRS/DCI/PUSCH/UCI channel artifacts, and both
E2E truth/proxy functions. Four actual SSB candidate BCH/SIB1 decodes passed.
PUSCH component retained3522 constellation samples,EVM8.55060489662%; its
initial timing/pathloss and isolated received DL feedback are explicitly
component inputs, not a main access-chain qualification. Python occupancy,
physical-axis and uplink-audit modules passed30 tests.

Read-only RSSI review confirmed antenna-plane CSI measurement and separate
SSB-window/allocation-window scopes. Checked installed nrCSIRSMeasurements
RSSI averaging against https://www.mathworks.com/help/5g/ug/5g-nr-csi-rs-measurements.html .
This does not qualify every main-row RSSI/CSI/PMI binding or configured SMTC
NR-carrier RSSI. Main connected PUSCH, feedback adaptation, complete CSV/PNG,
PRACH native-grid publication, common QCL activation applicability and
shared SSB/SI/data phase-reference consistency remain to be checked.

After MATLAB absence, repaired another evidence guard: localExecutedPart
must reject fractional/nonfinite/complex/text/out-of-range indices, not round
them to plausible RE coordinates. Added16 PDCCH/PUCCH rejection cases and
registered the three grid tests plus numeric measurement regression in testAll.
Focused final verification pending; broad testAll remains unexecuted.

Terminal40071/log observed_grid_strict_indices_20260909_01 exited0: all six
functions passed, including16 malformed PDCCH/PUCCH index cases, broadcast
grid TDD/FDD component equivalence, dedup, numeric import and both E2Es.
Eleven distinct focused MATLAB functions and30 Python tests passed across
this work; full suite/whole-simulator conformance remains OPEN. Confirmed
MATLAB absent and scoped diff --check clean before launch. Fresh main tag
short12_broadcast_grid_recheck_20260909_01 checked absent. Launch uses
unchanged55-slot nominal12 TDD YAML with CSV/PNG enabled through runSingle;
not a new FDD or25dB main. Original failed run remains untouched. Outcome
pending; freeze production/test/app dependencies while main MATLAB lives.

Main session86506 LIVE, worker13324/launcher7188. Log
logs/short12_broadcast_grid_recheck_20260909_01.log has
SHORT12_BROADCAST_GRID_CONFIG_PASS. Config guard only: scheduling/access/
connectedUL/publication not yet proven. Continue monitoring this exact
process; do not start another MATLAB or edit dependencies during execution.
Goal ACTIVE. This turn PROGRESS: actual broadcast-grid wiring, strict
index guard and11 focused MATLAB/30 Python tests; fresh main in progress.

## 2026-09-09 main broadcast runtime evidence and remaining occupancy contract

Previous goal turn PROGRESS. Revalidated session86506 live, worker13324 and
launcher7188; no production/test/app edits while main runs. Reread result-
integrity and NR-validation skills/references. Main preflight passed and
advanced into the same55-slot nominal12 TDD physical-NF thermal-noise run.
At slot6 acquisition completed. Main observed_re_allocation.csv now contains
2352 SSB contiguous-run rows,6640 physical port-REs (4beams x830RE x2ports),
SSBindices0..3,ports0..1, and actual SIB1 PDCCH/PDSCH plus TRS rows. This
exercises the new broadcast producer in the real main, not only a fixture.

Read-only early audit receipt:
results/lls/qualification_working/audits/short12_broadcast_grid_live_20260909_01/early_csv_snapshot
Parsed97CSV/51032rows/6087columns, first5rows captured perCSV;0parseerrors,
40emptyfiles,89requiredsemanticfailures,0PNG at that early checkpoint.
It is a live non-atomic snapshot, not final qualification; missing terminal
summary/trials and not-yet-published columns must not be counted as proven
completed-run defects. ssb_checkpoint_01/02 only inspect periodic per-occasion
rows (0observed), not initial PBCH acquisition. uplink_checkpoint_01 had all
four UL channels unobserved;0failedchecks is NOT an UL pass.

First actual live PNG subsequently published in snapshot
157e735aebfea89e49bde7c3f086438df4f67b1800134e6fff95b3e25001b1d3:
reports/live_measurements/<snapshot>/image/ssb_window_rssi_timeline.png.
Visually inspected all8beam/receive-branch points. CSV linear symbol-power
average -> dBm closes within1.4210854715202004e-14dB. All snapshot artifact
hashes verified with0mismatches. Scope explicitly20PRB/four-symbol SSB-window,
not full-carrier/SMTC NR-RSSI. Initial PBCH rows retain measured SSB0 RSRP
-76.0460576482401dBm and SS-SINR48.8619977614611dB; configured12 is not forced.

CONFIRMED NEW BLOCKER FOR OCCUPANCY PNG: apps/lls_resource_occupancy_plots.py
symbol_occupancy_chart requires active_flag, but buildObservedREAllocation
localEmptyRow/localRows never emits it. Both actual observed and live CSV
headers omit it. latest.json charts reports frame/slot/symbol occupancy
unavailable_at_checkpoint/source_row_count0 despite valid actual rows.
Fix AFTER MATLAB terminal: emit active_flag at validated executed TX producer
(these rows already require actual occupied REs); retain strict renderer
guard. Add an actual producer->CSV->renderer regression, not only analytic
Python fixtures that already supply the missing field. Do not patch live
dependencies, fill GUI defaults, or rerender old snapshots as original output.

Additional PRACH audit: generatePRACHWaveform keeps native nrPRACHGrid and
nrPRACHIndices; runFourStepRA.localMsg1ObservedAllocation sends them through
generic carrier-symbol/subcarrier mapping. ChannelAllocationMaterializer's
materializePRACH also labels native nrPRACHIndices as carrier REs. Official
https://www.mathworks.com/help/5g/ref/nrprachgrid.html specifies K=(carrierSCS/
prachSCS)*12*NSizeGrid and PRACH-format-dependent L, not generic carrier grid.
Thus mixed-numerology/native-symbol coordinate authority needs repair and
tests; inspect this main's retained PRACH waveform/config when available.
Also verify physical-port grid after any Msg1 spatial waveform mapping;
generator repeats multiantenna waveform but retains single-port native grid.
These findings do not yet prove wrong PRACH waveform generation/decoding.

At latest poll main reached slot14/55; still running with acquisition1,
access0 before Msg1 opportunity. No main connectedUL, adaptation, fullCSV/PNG,
all-impairments,25dB,long,or instrument qualification claimed. Goal ACTIVE.

Further main progress: session86506 still live at slot20/55 (worker13324).
control/csv/ra_runtime_stage_waveforms.csv retains Msg1UL slot14zero-based,
capture[111183,115192), and Msg2DL slot16zero-based,[122880,130575),fs7.68MHz.
Both RuntimeStageWaveformUsed1/SelfLoopWaveformUsed0. Read-only
tools/audit_lls_ra_capture.py receipt ra_checkpoint_01 in the live audit
directory passed19checks (two stage directions, sample count/completion,
contiguous physical execution, channel binding, TXpower and thermal-noise
arithmetic, plus stage-presence). Explicitly not detector/fullRA qualification;
Msg3/Msg4/RRCSetupComplete and connectedUL not yet observed here. Actual Msg1
MAT capture is under air_interface/mat/ra_received_observations/
shared_ra_ue1_slot15_Msg1_111183.mat. Continue same live process, no restart.

## 2026-09-09 main native PRACH domain proof and received Msg3

Previous turn PROGRESS (new actual main grid/RSSI evidence and identified
producer/renderer schema failure). Session86506/worker13324 revalidated LIVE;
no code edits, second MATLAB or main restart. Result-integrity and
NR-validation skills/references reread. At slot24/55 main still running.

Read-only h5py inspection of retained Msg1 capture establishes this is not
only a hypothetical mixed-numerology concern: RAConfig.PRACHSubcarrierSpacing
30kHz, carrier15kHz/NSizeGrid25; Msg1Tx.Grid MATLAB shape150x14 (HDF5 14x150).
Retained native indices cover subcarriers2..140 and symbols0..11, Nfft256,
fs7.68MHz. Actual OFDMInfo retains CP121samples, per-symbol lengths and guards.
Prepared logical waveform is3840x1, physical waveform3840x2; actual TXAfterRF
and RX captures4009x2. RA stage labels logical TxPortCount1 while physical
stream has2elements. Therefore generic carrier-grid coordinate and port
interpretation is insufficient for THIS main's PRACH visualization. Repair
native-PRACH timing/frequency/physical-domain evidence after MATLAB terminal;
do not label projected support as exact mapped carrier REs or invent ports.
No assertion made that PRACH waveform generation is wrong: detector succeeded.

Actual Msg3 capture now exists:
air_interface/mat/ra_received_observations/shared_ra_ue1_slot15_Msg3_145743.mat.
ReceivedResult scalar fields: PreambleDetected1, Msg2DCICrcPass1,
Msg2PDSCHCrcPass1, Msg3PUSCHCrcPass1, Msg3PostEqSINR11.570884759800288dB,
Msg3Raw/AppliedTimingCorrection84samples, Msg3TimingEstimateUsed1,
Msg3TimingAdvanceApplied1, TBS736bits, MCS0 (RA grant, not connected LA),
Msg3Requested/TxPower-1.3610414642918869dBm, PHR24.361041464291887dB,
ProxyUsed0/RuntimeSelfLoopWaveformsUsed0. Msg4/RRC fields in this intermediate
capture are not-yet-executed zeros, not demonstrated CRC failures.
One exploratory HDF5 listing hit an opaque MATLAB Msg3Rx dataset (not a group);
read the retained scalar ReceivedResult instead; no PHY re-execution/proxy.

ra_checkpoint_02 audit receipt now covers Msg1/Msg2/Msg3 and passes arithmetic,
coverage, directions/power/noise checks (terminal_qualification=false).
Msg3 UL slot19zero-based received interval[145743,153592),fs7.68MHz,
RuntimeStageWaveformUsed1/SelfLoopWaveformUsed0. Full access, connectedUL/UCI,
SRS/CSI adaptation, all artifacts and full qualification remain OPEN.
Goal ACTIVE. Continue same main session, keep dependencies frozen.

## 2026-09-09 access completion, received SRS, and late-UCI slot-domain defect

Main short12_broadcast_grid_recheck_20260909_01 completed actual Msg1 through
Msg4 and RRC Setup Complete. ra_attempts: RACompleted/StrictOk=1,
Msg3PUSCHCrcPass/Msg4PDCCHCrcPass/Msg4PDSCHCrcPass=1,
ProxyUsed/RuntimeSelfLoopWaveformsUsed=0. rrc_setup_complete: CRC/Decoded/
RRCConnected/ReceiverOk=1, TBS736, PostEqSINR11.5871953734265dB.
The five-stage ra_checkpoint_complete_01 receipt passes capture arithmetic,
coverage and direction checks; terminal_qualification remains false.

SRS slot30 received samples[222543,230392), timing84samples,
NMSE-21.6336032135016dB, runtime usable/updated=1, delivered slot31 at0.03s.
CSI slot32 observed/available=1, RSRP-76.2143925328849dBm,
RSSI-51.2060814239442dBm, reference SINR23.0185048549516dB,
CQI15/RI1/PMI3. This is measurement evidence, not yet received CSI feedback
or completed link-adaptation qualification. Nominal12 remains a scenario label
under receiver_noise_figure_thermal_noise, not forced measured SINR.

Main failed slot34 after two DL trials and zero connected UL trials:
sixgr:truth:UCIOverlapTimingAuthorityMismatch. Exact stack:
prepareSharedPUCCHFeedbackRuntime -> reconcileQueuedPUSCHAfterDLFeedbackImpl
-> multiplexDueHARQACKOnPUSCHImpl -> overlappingPUCCHReservations.
The late-feedback reconciliation reads canonical zero-based
ScheduledAbsoluteSlot as the one-based runtime dueSlot. The guard compares
DataDecision.TargetAbsoluteSlot to dueSlot-1 and correctly rejects it.
The same faulty alias preference exists in pending queue lookup/pop and
SRS/PUSCH collision selection in runWaveformLinkBundle. Existing resource-only
component fixtures used one-based ScheduledAbsoluteSlot without a canonical
TimingDecision, so did not catch this producer/consumer domain mismatch.
Repair queued: central validated runtime-slot conversion and real canonical
decision coverage, retaining exact timing/identity guards. No code edits while
MATLAB session86506 worker13324 is still finalizing partial failure artifacts.

Other confirmed open exports: observed RE producer omits active_flag required
by strict occupancy renderer; native PRACH30kHz150x14 grid was exported as if
it were carrier15kHz300-subcarrier grid. These are not solved by guessed ports,
default GUI values or relabeling projected footprints as exact mapped REs.
Goal remains ACTIVE; full connected UL/UCI, receiver QCL/TCI reuse and complete
CSV/PNG qualification remain open.

Recovery-time read-only inventory receipt (not terminal/atomic):
qualification_working/audits/short12_broadcast_grid_live_20260909_01/
recovery_csv_snapshot_01. 426CSV,281594rows,22781columns, first5rows/file,
0parse failures,1structural issue (empty_header in live_waveform_preview.csv),
23required semantic failures across14files. No PNG at inventory start;
browser publication subsequently began and31PNGs were seen. Classify results
after terminal publication: missing connected UL rows are expected from the
aborted run, while observed-grid data_allocation_missing_UE_identity includes
broadcast SI-RNTI rows and needs a valid common-transmission audit contract,
not a fabricated UE. Schema/authority mismatches and duplicate beam metric
keys remain unresolved, not automatically waived as incomplete-run effects.
Source CSV/PNG bytes have not been overwritten by the external audit.

Main session86506 terminated exit1 at11:01:23UTC; worker13324/launcher7188
were absent before source edits. Recovery additionally reported
TerminalBrowserClosureFailed after3passes (materialization0,visual1,lineage1).
Final external receipt terminal_failed_run_01:840CSV/388417rows/41388columns,
254PNG,0CSVparse/0rasterdecode/0rasterissues,23requiredCSVsemantic failures
across14files,0available-chart semantic failures,27status mirrors consistent.
This is a FAILED run, not a successful publication: browser receipt retains
2missing tables (live_ul_scheduler_grants/live_bsr_state) and52missing charts.

Applied runtimeULGrantSlot.m: runtime Slot is explicitly positive one-based;
issued canonical timing remains zero-based and is fully identity-validated,
then must agree with Slot=DataAbsoluteSlot+1. Missing/invalid runtime Slot and
stale timing are rejected. Resource-only component inputs are not promoted
to timing or waveform evidence. No scheduler decision is rebuilt or shifted.
Migrated late-HARQ/CSI reconciliation, pending-UL lookup/pop, SRS/PUSCH
selection, first-SRS pre-DCI planning, SRS priority arbitration, and collision
report's runtime PUSCHGrantSlot. PUCCH ledger's existing one-based fields are
not blanket-rewritten. No duplex-specific exception or policy change.

Focused batch session66687, worker5848/launcher19416,
logs/queued_ul_runtime_slot_regression_20260909_01.log. Passed so far:
testGrantTimingIdentity (new malformed/mismatched runtime-slot negatives),
testFirstSRSULPreDCI (new actual canonical TDD timing decision),
testSRSPUSCHRuntimePriority, testLLSPUSCHHARQACKRuntimeFeedback,
testCoupledTruthCSIReportSourceAuthority, testSharedPUSCHChannelArtifacts,
testSharedPUSCHLateCSIDelivery. Actual TDD received DCI now crosses the same
queued late-UCI reconciliation method as main; PUSCH CRC/HARQ content pass,
3522 constellation samples,EVM8.55060489662percent. Late measured-CSI/UCI
case EVM8.62254422951percent, slot10 reception delivered in slot11. Initial
TAG/pathloss and isolated DL ACK/NACK inputs remain explicit component
fixtures, not a main access/adaptation qualification. Two E2E guards still
running at this journal checkpoint; keep code frozen until batch terminal.

Additional read-only legacy branch concern (not proven used in this run):
runWaveformLinkBundle/localBuildConnectedPUCCHInterferer defaults missing
ACK bits to1 and missing target to sourceSlot+1, yet labels K1Source decoded_dci.
Trace caller authority and reject/explicitly classify missing evidence before
qualifying multi-cell interferer control. Do not treat this branch finding as
proof that the current single-UE received PUSCH used synthetic UCI.

First focused batch terminal: session66687 exit0,
QUEUED_UL_RUNTIME_SLOT_REGRESSION_PASS at11:11:52UTC. All9 named functions
passed, including both E2E truth/proxy and packet-semantic guards. No MATLAB
process remained before the next launch. Standalone PUCCH follow-up started
session68381, logs/queued_ul_pucch_clock_regression_20260909_01.log:
testSharedPUCCHLateFeedbackClock and testSharedPUCCHLateFormat2Clock.
Keep production/test/app code frozen for this batch. Full testAll and broad
config/NR suites are still OPEN; no main FDD/25dB/long run was launched.

Reference checked for overlap/timing scope (not a conformance certification):
ETSI TS138213 v18.5.0 / 3GPP TS38.213 clause9.2.5,
https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.05.00_60/ts_138213v180500p.pdf.
The patch corrects implementation index-domain crossings; it does not relax
the existing symbol-overlap, processing-time, allocation or UCI-lineage guards.

Standalone PUCCH batch session68381 terminal exit0; worker17708/launcher12272
absent. Both late-feedback and late-format2 shared-clock regressions passed,
including actual receiver-ledger power-plane CSV round trips. Total11 named
focused test functions passed after this patch; no assertion weakened, no
fabricated primary row, no production policy changed. Scoped git diff --check
passed (only repository CRLF warnings). No MATLAB process remains.

Next work: native PRACH domain/actual physical projection evidence and missing
observed active_flag, producer-to-renderer integration, remaining failed-run
CSV/publication contracts, then a fresh same nominal12 TDD main qualification.
Receiver QCL/TCI reuse, PMI/CSI end-to-end adaptation and RSSI/SINR domain
closure remain explicit work; do not declare all channels or 10/10 qualified.
Current goal turn PROGRESS: seven slot-domain consumers repaired and tested,
main uplink/access evidence and complete failed-artifact audit retained.
Goal ACTIVE. Full testAll/config/NR suites and instrument playback still OPEN.

## 2026-09-09 native PRACH grid and producer/publication repair

The failed main run's PRACH indices belonged to the native PRACH OFDM grid,
not the carrier CP-OFDM grid. In the TDD profile the native grid is 150 by 14
at 30 kHz while the carrier is 300 subcarriers at 15 kHz. Reusing native
indices as carrier RE coordinates was physically misleading. The old
materializer also manufactured a carrier-PRB envelope from those indices.

Implemented explicit carrier_cp_ofdm / prach_native_ofdm domains, separate
planned and observed native PRACH CSVs, native symbol/subcarrier axes, actual
OFDM useful/CP sample intervals, sample rate, grid/waveform hashes, complete
grid and port counts. The actual PRACH generator retains its normalized
waveform-port grid. Shared Msg1 preparation retains the applied spatial
matrix and corresponding normalized physical-port grid; their dimensions,
values and digest are checked before export. This does not claim calibrated
power, PSD, a carrier-RE footprint, or full scheduler PRACH collision closure.

Added an observed active_flag at the executed-grid producer; the former
renderer-only fixture had hidden this missing producer column. Carrier
occupancy now refuses PRACH/native-domain rows. The new native PRACH chart
shows the latest observed occasion and all mapped ports, with that selection
explicit; source CSV preserves all occasions. Reporter contract is v62.

Actual native waveform FFT support and producer -> CSV -> PNG checks passed
for TDD short-format and FDD long-format component cases, one and two ports.
These are not new main FDD simulations and not receiver/access qualification.
The tests reject malformed timing, fractional indices, mapping/hash tampering.
Resolved occasion.AbsoluteSlot now supplies the test's exported carrier origin.

Focused MATLAB logs native_prach_grid_regression_20260909_01 through _04
retain all failures: uint fractional-index test construction, real/complex
matrix-cast fixture mismatch, then a narrow-carrier SSB fixture mismatch and
its genuine SSB/DM-RS collision. Only test inputs were corrected; the valid
SSB configuration remains enabled, and the collision now has an explicit
negative assertion before the legal later-slot positive case. No production
guard was relaxed. Batch _05/session44164 is still running at this checkpoint.
Native PRACH and observed DL/UL/control producer-to-PNG checks passed; both
actual broadcast waveform demodulations matched retained grids at about
2.2e-16 to 2.5e-16 relative error. Exact allocation preflight remains pending.

107 focused Python tests passed (native/occupancy plots, materialization,
running/complete output contracts, applicability and sweep). Actual PNGs
were visually inspected; carrier/BWP identities not supplied by the
component source remain labeled unknown, not invented.

Additional code-review finding queued until MATLAB exits: Msg1 applies
preamble power control before observed-grid export, so its waveform hash
must not be labeled as the pre-power generator waveform. Add explicit
producer-owned hash-plane metadata and regress both stages. The normalized
grid itself is intentionally not a calibrated-power measurement.

Still OPEN: fresh main shared Msg1 projection handoff, native-grid run/config
identity exports, true PRACH carrier reservation/collision geometry, complete
main PUCCH/PUSCH/SRS/UCI integration qualification, receiver QCL/TCI reuse,
PMI/CSI feedback and adaptation closure, RSSI/SINR domain closure, and the
remaining failed-run artifact contracts. No full testAll/config/NR campaign,
25 dB or instrument playback claim. Goal remains ACTIVE with concrete progress.

Batch _05/session44164 subsequently completed exit0 with
NATIVE_PRACH_GRID_REGRESSION_PASS; all five named MATLAB functions passed,
including exact preflight (64889 typed allocation rows, 597778 mapped REs).
Worker6924/launcher5296 were absent before the next edit. These planned
preflight counts are not measured main-run transmission counts.

The waveform-hash-plane defect is now repaired at the actual producers:
generatePRACHWaveform labels the raw generator output, and runFourStepRA
updates that authority immediately after real preamble power control.
annotatePRACHNativeAllocation requires the explicit plane, hashes the actual
retained Waveform, and separately labels native grid values as normalized
pre-power/pre-RF data. Missing plane authority is rejected rather than guessed.
The RA stage-composer test checks the post-power hash/plane against Msg1Tx;
the generator test checks raw-plane binding and missing-authority rejection.

Follow-up batch session32604, log native_prach_power_plane_regression_20260909_01:
testPRACHNativeGridEvidence, testFourStepRARuntimeStageComposer and
testSharedPRACHReceiveOrigin passed; both required E2E truth/proxy regressions
are still executing at this checkpoint. Production/test/app files are frozen
until terminal exit and MATLAB process absence. Scoped git diff --check passed
(CRLF conversion warnings only). No existing run outputs were rewritten.

Follow-up session32604 completed exit0 with
NATIVE_PRACH_POWER_PLANE_REGRESSION_PASS. Both E2E tests passed, including
configured seeds111/303 and packet-semantic seeds11/22/33 with actual UL/DL
grant and CRC evidence; the final persistence checkpoint was11:57:43UTC.
Worker18736/launcher11980 are absent. Nine distinct focused MATLAB functions
passed across the two final batches, and107 focused Python tests passed.
No MATLAB process or main simulation is left running at this checkpoint.

Full testAll and required broader config/NR/export-organizer/scheduler suites
remain OPEN; these focused results are not certification. Main qualification
must next check the retained physical Msg1 grid through the actual shared
stream, missing run/config identities and artifact contracts, and the complete
UL data/UCI/CSI/QCL/TCI/RSSI measurement chain. Do not discard any open issue
listed above, and do not count an unavailable measurement as a passing value.

## 2026-09-09 observed-grid publication identity boundary

Previous goal turn classified PROGRESS: native PRACH domain/power-plane
repair and nine distinct focused MATLAB functions plus107 Python tests passed.
Rechecked the prior terminal log and MATLAB process absence before editing.

Extracted the existing runtime grid publication into
writeObservedREAllocationArtifacts, called directly by
CoupledTruthRuntime.writeTablesImpl. It binds available ScenarioID/ConfigHash
from CfgMobility, retains explicit context-source paths, rejects conflicting
existing identities before any write, splits native PRACH from carrier REs,
and preserves all producer rows, authority/resolver labels and native timing.
No guessed hash, missing-value rescue, source relabel or new measurement row.
Empty checkpoint cleanup affects only the four exact grid snapshot paths.

Both actual native PRACH and carrier-grid tests now exercise this production
writer and both component/report mirrors before rendering PNGs. Test context
hashes describe the actual component generator inputs, not a claimed main
scenario. Conflicting identity tests verify previously written bytes remain
unchanged. Missing context stays missing. Empty snapshot cleanup is tested
only in a newly created component-test subdirectory; old run outputs untouched.

Batch observed_grid_identity_regression_20260909_01/session95745 is executing.
testPRACHNativeGridEvidence and testObservedREAllocationRuntimeTruth passed;
the batch subsequently reached E2E execution, so the intervening
testLinkExportPipeline, testArtifactIntegrity,
testOrganizeRunResults_E2EArtifactPreservation and
testSchedulerGrantConsistency also returned passing results. The two E2E
tests remain in flight at this checkpoint. Freeze all production/test/app/tool
dependencies until terminal exit and MATLAB process absence.

Read-only follow-up audit confirmed the old RE semantic validator requires a
UE ID for every PDSCH, including actual SIB1/SI-RNTI broadcast rows. Correction
must require explicit executed broadcast/hash/interval evidence, not exempt
all missing-UE rows. TS38.321 tables7.1-1/7.1-2 identify SI-RNTI=FFFF as
broadcast System Information on DL-SCH/BCCH:
https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/16.20.00_60/ts_138321v162000p.pdf.
Also inspect cell-scoped collision keys and reject native PRACH mislabeled as
carrier REs. These audit edits are queued, not yet applied at this checkpoint.

Identity batch session95745 completed exit0, terminal marker
OBSERVED_GRID_IDENTITY_REGRESSION_PASS; final persistence12:08:41UTC.
All eight named tests passed. Worker11988/launcher6188 absent before further
edits. No main TDD/FDD/25dB run was started. The runtime coverage exporter
reads these same component/report snapshots and preserves populated columns;
the added uppercase identities are not discarded by its finalization helper.

Applied the observed-RE semantic audit repair: SI-RNTI PDSCH without a UE ID
requires the exact executed-broadcast authority, physical-element domain,
valid transmit-grid hash, associated SSB/cell identity, and a committed sample
interval covering that carrier slot. SI-RNTI alone is not an exemption. A
qualifying cell-broadcast row claiming a unicast UE is rejected. Native PRACH
is rejected from carrier RE tables. Collision keys now include cell identity;
distinct cells are distinct transmitter-port domains, while same-cell RE
overlap and missing cell identity remain failures. 126 focused Python tests
passed, including malformed-broadcast/missing-authority negatives, same-cell
collision positives and cross-cell ownership negatives.

Re-audited the preserved failed main CSV READ-ONLY (9064 rows):620 genuine
SI-broadcast rows meet the explicit broadcast evidence contract. The old file
still FAILS: missing ConfigHash/ScenarioID (new writer not retroactively
applied),12 native PRACH rows in its old carrier-domain table, and FOUR
remaining conflicting contiguous rows between TRS and SIB1 PDSCH DATA in
absolute slots2/22. Four rows do not mean only four collided REs: each broad
SIB1 contiguous run overlaps multiple TRS pilot REs.

Concrete overlap: slot2/symbol4/port0 TRS subcarrier0 belongs to
trs_slot_2, while sib1_pdsch_cell_1_burst_0 claims DATA subcarriers0..287.
TRS in that slot has150 mapped RE rows across symbols4/8, subcarriers through
296. The authored TDD TRS slots[2,3,7,8] avoid SSB slots0/1 but not SIB1 slot2.
The FDD causal YAML also authors[2,3,7,8]; do not assume a duplex-only defect.
SIB1 generation uses its strict RASIPDSCHContext, not the connected-data
allocREsPDSCH TRS-reservation helper. It is not valid to silently puncture
SIB1 around an unprovided dedicated CSI-RS configuration or to hide the
collision in exported occupancy. Also inspect Msg2/Msg4 common PDSCH paths
and missing full RA stage occupancy before choosing a generic coexistence
repair. Blindly moving a TRS burst could merely collide with another common
transmission. No TRS scheduling/config change has been made yet.

Next priority: exact common-broadcast/RA/TRS shared-grid ownership and
preflight/runtime conflict handling, then fresh nominal12 TDD qualification.
Native shared Msg1 projection handoff, complete UCI/CSI/QCL/TCI/RSSI closure,
broader NR/config/testAll suites and remaining artifact requirements remain
OPEN. Goal ACTIVE; this turn made production publication and validator
changes, verified eight MATLAB/126 Python tests, and isolated a real
previously obscured PHY coexistence defect. No unsupported all-pass claim.

## 2026-09-09 common-DL reservation repair and uplink revalidation

Confirmed an additional real collision from preserved receive timestamps:
Msg4 started at sample168960 (7.68MHz), i.e. carrier slot22, which also
contained SIB1 and TRS. RAEventScheduler previously checked duplex and timing
windows but not common-DL resource ownership.

Implemented CommonDLResourcePlan and wired its PDSCH eligibility callback
into RAConfig/RAEventScheduler before selecting Msg2 and Msg4. Reservations
use the authored stage PRB/symbol allocation, canonical SSB PRB-symbol
exclusions, actual nrCSIRSIndices for TRS, and shared transmitter SIB1/Type0
allocation builders. This is CONFIGURED ownership, not measured evidence;
it does not generate waveforms, consume RNG, alter a coded TB, or fabricate
received control. Rejected candidate owners/counts are retained in the
v4 timing schedule. ControlMonitoringQualified and SetupCompleteGrantQualified
remain false: this check alone does not qualify control encoding or reception.

Both causal YAML profiles now explicitly use one TRS set [7,8] per carrier
frame instead of the conflicting [2,3,7,8]. TRS remains enabled. The FDD
profile's descriptive periodicity is corrected to10ms to match these explicit
within-frame occasions. Common SI/TRS collisions are rejected over their
joint recurrence cycle at RA planning and broadcast preparation, not removed
from output grids. Public configuredSIB1Allocation and
resolveSIB1ControlOccasion are shared with the actual broadcast generator;
the preflight no longer reconstructs SIB1 with min(24,NSizeGrid), and its
broadcast rows no longer claim UE1. Fractional MIB pdcch-ConfigSIB1 is rejected
instead of rounded by the shared helper.

Regression01/session80088: new both-profile resource test passed; legacy
anchor exposed an erroneous new assumption that Type0 must occur in the
first SSB period. Corrected the implementation to retain its full absolute
offset and validate one joint cycle starting from that offset. No test
assertion or actual waveform was bypassed.

Regression02/session87332 completed exit0; MATLAB absent before more edits:
testCommonDLResourceScheduling, testRADuplexAllocationTiming,
testObservedBroadcastREAllocation all passed. Actual broadcast waveform/grid
relative errors: TDD2.45e-16, FDD2.19e-16. Planning tests independently check
old slot22 conflict, TRS slot27 conflict, free slot32, a nonoverlapping PRB
in an SI slot, negative old-TRS schedule, dynamic SIB1 PRB count, late Type0,
and unchanged RNG. FDD RA fixture now legitimately selects[3,6,9,10] rather
than[2,5,6,7]; the former avoided SIB1 slot2 and TRS slots7/8.

Uplink/measurement regression01/session85354 is running against frozen code:
testTDDCausalFourStepRARuntimeTiming(14), testSharedPUSCHLateCSIDelivery,
testSharedPUCCHLateFeedbackClock, testSharedPUCCHLateFormat2Clock,
testReceivedSRSTimingEvidence, testCSIRSRPPhysicalMeasurement,
testCSIRSPhysicalResourceMeasurements, testPDSCHQCLStatePropagation.
Do not report these as passed until terminal evidence is checked.

Still OPEN, not masked by the above repair:

- Msg4 uses custom32-bit DCI packing and hardcoded control aggregation;
  migration to TC-RNTI-specific NR payload/control semantics is required.
- Common-DL eligibility checks PDSCH ownership, not the full RA PDCCH
  candidate resource ledger or all scheduled-data/control collisions.
- Full observed grids for Msg2/Msg3/Msg4/setup-complete and physical TRS port
  mapping still need publication/integration review.
- Full main shared-clock run must reverify UL scheduling, late UCI/CSI
  delivery, decoded-control authority, SRS consumption and adaptation.
- QCL/TCI binding tests do not prove complete physical receiver reuse;
  PMI/RI/MCS feedback consumption and RSSI CSV/PNG closure remain main-run gates.
- All other unresolved artifact, proxy-boundary and full-suite items above
  remain open. No fresh main TDD/FDD/25dB scenario has been launched here.

Standards context: TS38.214 V18.6.0 clauses5.1.4/5.2 address PDSCH resource
mapping and CSI-RS/TRS configuration. The particular nonoverlapping RA
scheduling policy is this implementation's allocation decision, not a claim
that 3GPP mandates these particular slot numbers:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.06.00_60/ts_138214v180600p.pdf

### Msg4 control and receive-payload publication follow-up

The detailed TC-RNTI migration entry earlier in this journal records the
new contextual DCI codec, independent receiver allocation/TBS decoding,
common-control configuration and scoped negative vectors. Its terminal
export-regression batch (session46243,
logs/tc_msg4_export_regression_20260909_01.log) exited0 with
TC_MSG4_EXPORT_REGRESSION_PASS. All nine named tests passed, including the
two E2E truth/proxy regressions; MATLAB processes were absent before edits.

Found and repaired a separate source-provenance defect in BOTH directions:
localApplyMsg3/localApplyMsg4 copied transmitted MAC bytes into PayloadHex,
which the JSON/text publisher called decoded. These fields now contain only
actual parsed, CRC-valid receiver bytes; TransmittedPayloadHex preserves
the independently labeled actual TX body. Msg3/Msg4 CSV rows and primary
runtime rows retain both. Failed reception cannot populate decoded payloads
from TX state. JSON includes the payload evidence role and actual CRC flag.
This corrects evidence provenance, not the still-bounded MAC/RRC encoding.

The new actual msg4_dci_fields table is wired into the standalone artifact
map and both main-runtime publication allowlists alongside Msg2 fields.
Negative-control reception retains actual encoded TX fields but no RX fields.
The new testRAPayloadExportOwnership executes real coded TDD Msg1-3, erases
the prepared Msg4 receiver samples, then checks published DCI CSV, decoded
JSON and text. It has passed; testRANegativeMsg3CrcFail and the identity
mismatch negative have also passed, followed by the measured five-stage
TDD timing test. Current session46795 is still running the export/E2E
regressions against frozen source; do not claim its terminal result yet.

No new main 12-dB/25-dB/FDD scenario, commit or output cleanup. Full main
shared-stream qualification, Msg3/Msg4 NR MAC/RRC encoding, actual Msg4
HARQ-ACK scheduling/reception, full control-resource ownership, QCL/TCI
receiver reuse and all-channel CSV/PNG/main-run acceptance remain OPEN.
