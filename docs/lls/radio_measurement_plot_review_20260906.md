# Radio measurement plot review — 2026-09-06

Scope: saved-run analytics and output-contract registration, not a new PHY
execution or full LLS qualification. The retained source is
`results/lls/lls_causal_access_to_data_wiring_tdd_short/tdd_short_truth_20260906_02`.
Historical CSVs, MAT files and PNGs have not been overwritten.

## Implemented and generated

`apps/lls_radio_measurement_plots.py` extends the existing WebGUI materializer.
Its producers are duplex-independent: they consume executed DL/UL measurements,
not an assumed TDD/FDD schedule. Existing plots remain registered.

The separate review contains 18 CSV/PNG pairs: the six existing paired-data
EVM/throughput views plus four CSI timelines, three precoder checks,
throughput/SNR, three per-channel block-error/SINR views, and CSI-RS pilot residual.
Each review manifest records source and artifact hashes. The review is explicitly
post-processing, not evidence that the previous run published these new plots live.
The latest review is `results/lls/qualification_working/radio_plot_review_20260906_04/`.
All exported radio rows were checked against their canonical source-row indices
(123 independent field comparisons), with source/output hashes and PNG decoding
verified. This does not validate every upstream physical calculation.

| View | Measurement contract |
| --- | --- |
| CQI, RI, PMI components, CSI SINR | Report observation and actual delivery times remain separate. Censored, pending and failed delivery states are not delivered observations. Scalar PMI zero is valid; vectors retain component positions without inventing Type-I i1/i2 meanings. |
| Requested / applied / reported PMI | Requested and executed fields retain their sources. A reported value is linked only by the explicitly recorded applied feedback source slot, matching UE/direction/cell and delivery no later than the data slot. This is link-adaptation context, not proof that the PMI selected the precoder. |
| Ports/layers and matrix integrity | Recorded port/layer counts, matrix dimensions and requested/applied hashes are compared. CSV retains every trial; the raster has a bounded preview prioritizing failures and explicitly counting unavailable/mismatching trials. Missing evidence is not a passing check. Hash equality cannot establish coefficient normalization, spatial mapping or optimality. |
| Throughput/SNR and throughput/SINR | Scheduled TB bitrate and delivered goodput are distinct. The SNR axis uses actual noise-calibration fields, never configured SNR. SINR uses measured fields with approximation guards. Points are not fitted curves or controlled sweeps. |
| PDSCH/PUSCH/PUCCH error versus SINR | Individual block-error observations retain trial identity. PUCCH formats without a CRC use actual UCI decode/comparison status; absent CRC is not failure. Sparse observations do not establish a BLER waterfall. |
| CSI-RS pilot residual | Uses the recorded pilot-fit residual. It is explicitly neither independent channel NMSE nor CSI-RS EVM. |

## What the saved precoding evidence actually shows

- Six DL trials, slots 6, 7, 8, 11, 12, 13: applied PMI 0; two logical ports,
  one layer; `RankSelectionPolicy=fixed`; applied matrix 2-by-1. Requested and
  applied matrix digests match. This does **not** demonstrate adaptive multirank.
- DL CSI reports at source slots 7 and 12 contain CQI 10, RI 2 and PMI 0.
  They reach the scheduler at slots 9 and 14. The slot-12 data trial retains
  applied feedback source slot 7; the new slot-12 report must not be attached
  to it as already delivered feedback.
- One UL trial, slot 15: TPMI 0, one port and one layer, a 1-by-1 applied
  matrix, matching requested/applied hashes. Its applied adaptation source
  slot is 10. It has no uniquely matching record in the CSI feedback table;
  the plot leaves that binding unavailable rather than guessing another report.
- The UL PUSCH-DMRS report from slot 15 is due at slot 16, beyond the retained
  horizon. It is right-censored, not scheduler-delivered.
- `RequestedPrecoderSource` is an existing producer annotation partly inferred
  from current-row PMI availability. A matching numeric PMI/hash is insufficient
  to close the remaining producer-to-grant feedback-authority audit.

## Requested EVM and NMSE plots that cannot be populated yet

PRACH, SSB and CSI-RS EVM are registered with strict paired-sample adapters,
but the runtime producers do **not yet emit their required paired-sample tables**.
Saved MAT inspection also found `EVM_rms=NaN` for PRACH and cell-search/PBCH.
No EVM PNG is generated from detection scores, SINR, pilot-fit residuals,
transmitter-only IQ, or decisions reconstructed at the receiver.

Future capture contract:

- Canonical files: `air_interface/csv/prach_evm_samples.csv`,
  `ssb_evm_samples.csv`, `csi_rs_evm_samples.csv`; a common
  `control_evm_samples.csv` is an explicit alternative source.
- Preserve `SignalName`, `Direction`, `UEIndex`, frame when applicable,
  executed `RuntimeSlot`/`Slot`, `ObservationID`, `PortIndex`, `SampleIndex`.
  PRACH is UL; CSI-RS and SSB components are DL. SSB components are PSS,
  SSS, PBCH and PBCH-DMRS, not one indistinguishable pooled sequence.
- Persist actual finite `ReferenceReal`, `ReferenceImag`, `MeasuredReal`,
  `MeasuredImag`, `ReferenceSource` and `AlignmentSource`. References must be
  the independently known transmitted symbols, not decisions or same-sample fits.
- `EVMDefinition=reference_normalized_paired_symbol_evm`;
  `MeasurementDomain=equalized_sequence_symbols` for PRACH or
  `equalized_resource_elements` for SSB/CSI-RS. This is diagnostic receiver EVM,
  **not** TS 38.104/38.101 RF-conformance EVM.
- For each component/observation/port, RMS percent is
  `100*sqrt(sum(abs(measured-reference)^2)/sum(abs(reference)^2))`.
  Peak percent uses the largest error magnitude divided by the RMS reference.
  Duplicate sample identities, missing definitions and invalid domains fail closed.

This schema is not a claim that receiver capture is implemented. That work must
be wired at the real PRACH/SSB/CSI-RS producers, with independently justified
timing/equalization, before a new run can publish these three EVM plots.

The true-channel NMSE view likewise remains unavailable: it requires an explicit
`OracleNMSE_dB` and `NMSEReferenceSource`, not the generic `NMSE_dB` field that
can contain pilot residuals or noise-to-gain ratios.

Method references: [EVM normalization](https://www.mathworks.com/help/comm/ref/comm.evm-system-object.html),
[NR CSI reporting and PMI components](https://www.mathworks.com/help/5g/ug/5g-nr-downlink-csi-reporting.html),
[PDSCH scheduling with CSI feedback](https://www.mathworks.com/help/5g/ug/nr-pdsch-throughput-using-csi-feedback.html).
The result-integrity skill determined the fail-closed missing-measurement behavior.

## Verification and short-run gate

- The focused Python set passed 237 tests, including CSV semantics, exhaustive
  and visual auditing, EVM normalization, missing evidence, false CSI delivery,
  directional precoder mismatches and materialization.
- `logs/radio_plot_required_export_regressions_20260906.log` ends with
  `RADIO_PLOT_REQUIRED_EXPORT_REGRESSIONS_PASS`: link export, artifact integrity,
  organizer preservation, scheduler consistency and both truth/proxy E2E tests.
  The packet-semantic fixture still warns of zero delivered UL traffic; it is
  not a throughput qualification.
- The repository-required full MATLAB suite was started separately. It exposed
  failures in `testFixedLinkMasterYAMLAuthority` and
  `testPrompt2TopologySRSPRACHRuntimeWiring` before the repairs below. This
  suite is not a passing qualification of the final revision. It was stopped
  after its cached pre-edit schema rejected the newly added RAR configuration
  fields. The mixed-revision failure log is preserved in
  `logs/radio_plot_required_testAll_20260906.log`; a fresh full suite is required.
- The existing authenticated dashboard process has not been restarted. Module
  registration is tested; live-page publication in that process is not verified.

The user's conditional short 12 dB run is **not launched**. Required gates are
not all closed: missing control EVM capture; absolute TDD channel start-time
ordering; and explicit 12 dB noise/SINR authority. The old baseline's configured
12 dB does not override its geometry/thermal-noise operating mode. See
`tdd_causal_repair_status_20260906.md` for the broader remaining gates. A sparse
saved-data plot review cannot certify every CSV value or full 3GPP compliance.

## Additional preflight failures repaired

1. Non-codebook PUSCH correctly resolved empty PMI/TPMI, but scalar trial
   annotation and HARQ/precoder status reporting assumed a nonempty value. The
   first failure was an assignment-size mismatch; after fixing that boundary,
   the HARQ snapshot exposed the same assumption in a scalar logical condition.
   A shared local optional-index validator now retains absent indices as NaN,
   rejects non-scalar/fractional/negative values, and leaves the transmitted
   matrix authority and native codebook validation unchanged. No index-zero
   substitution or successful-CRC row was introduced.
2. The two-cell bootstrap scheduler fixture set SRS-valid booleans but had no
   causal SRS availability event. Production correctly blocked both UEs. The
   fixture now first asserts that flags alone cannot pass the gate, then supplies
   a source-labelled scheduler-test event at the configured earlier SRS occasion
   through the production publisher. Its unmeasured SINR/CQI remain NaN; it is
   an isolated state-machine fixture, not waveform evidence or a primary export.
   The expected one-cell, alternating-cell and eventual two-cell grant assertions
   are unchanged. Production scheduler gating was not relaxed.

`logs/radio_preflight_failure_repairs_20260906.log` ends with
`RADIO_PREFLIGHT_FAILURE_REPAIRS_PASS`: both repaired tests, `testLLS_UL`, and
`testReferenceSignalCausalProducersConsumers`. The master-authority test executes
one actual DL and one actual UL transport block and checks that non-codebook
ConfiguredPMI remains unavailable. A new user scenario has not been launched.

## Deferred channel clock repair

The new `testRuntimeChannelDeferredIdleClock` reproduced a separate production
defect before the patch: advancing an unmaterialized channel by 187 and 23 samples
then materializing it reported sample 420, not 210. Pending idle was consumed
through a function that advanced both the physical object and the already
advanced logical counter. A nonzero initial `AbsoluteSampleIndex` had the inverse
problem: it changed the reported clock without advancing the physical object.

`ChannelFactory` now consumes deferred idle on the physical channel exactly once
without incrementing the logical clock again. An initial nonzero offset is also
consumed physically. AWGN accounting retains the actual OFDM sample rate when
available and leaves elapsed seconds unavailable when the rate is unknown.

The fading regression compares actual deterministic input/output waveforms for
immediate versus deferred materialization and initial-offset creation, using
CDL-A and TDL-C in both duplex modes. It checks numerical waveform equality,
sample/time accounting and a single initialization reset. It is registered in
`testAll`. `logs/runtime_deferred_idle_after_fix_20260906.log` contains
`RUNTIME_DEFERRED_IDLE_CLOCK_REPAIR_PASS`, including the existing continuity and
dynamic TDD reciprocity tests. The added explicit AWGN accounting case also
passes in `logs/runtime_deferred_idle_required_regressions_final_20260906.log`;
that batch now ends with `DEFERRED_CLOCK_REQUIRED_REGRESSIONS_PASS` (config,
strict proxy/no-fallback guards, DL, UL and reference-point tests). The enhanced
five-stage absolute-sample assertions also pass in
`logs/ra_absolute_sample_clock_regressions_final_20260906.log`, with the existing
continuity and dynamic reciprocity tests. This sample-clock fixture does not
test whether those five stages occupy legal TDD symbols.

This repair does **not** close the separate RA absolute-time ordering gate or
prove that configured RA allocations respect the TDD symbol map. No channel
reset, time rewind, direction override or fabricated measurement is used to
make those outstanding checks pass.

## Confirmed TDD access-schedule launch blocker

The read-only production-config audit in
`logs/ra_tdd_schedule_readonly_audit_final_20260906.log` resolves `RAConfig` and
checks its actual allocations against `SlotFormatResolver` using the YAML's
5 ms common pattern (three DL slots, 10 DL/2 UL symbols in the mixed slot, one
UL slot). Indices below are zero based:

| Stage | Slot | Direction / symbols | Availability |
| --- | ---: | --- | --- |
| Msg2 | 5 | DL / 2–13 | Available |
| Msg3 | 6 | UL / 0–13 | **Invalid: fixed DL symbols** |
| Msg4 | 7 | DL / 2–13 | Available |
| RRCSetupComplete | 8 | UL / 0–13 | **Invalid: mixed DL/flexible/UL slot** |

For the last row the resolver returns `flexible_symbols_unresolved` first;
the allocation also crosses the ten fixed DL symbols. Resolving the flexible
symbols to UL cannot make a full-slot PUSCH legal there. The applicable common
pattern rules and restriction on overriding fixed directions are in
[TS 38.213 v18.8.0 clause 11.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

`RAEventScheduler.resolve` currently receives delays/timers but no duplex
allocation authority, so it cannot validate these symbol directions. Repair
must bind legal RA time-domain allocations and their signalled timing to the
canonical frame map, then execute them on the causal runtime timeline. Merely
moving an exported slot label, changing the reported direction, or advancing
past an earlier scheduled time is not a fix. These are outstanding blockers,
not repaired by the deferred channel-clock patch.

## RAR grant producer/consumer repair in progress

Tracing the scheduling boundary uncovered a separate on-air encoding defect.
The old encoder used a private 10-bit PRB start/count packing, five MCS bits,
and a transform-precoding bit; its decoder agreed with the same private format,
forced QPSK/120/1024 and subsequently copied the planned modulation/rate back
over the decoded fields. That agreement was not standards interoperability.

The production builder and Msg2 receiver now use `RARULGrantCodec`: licensed
RAR fields of widths 1/14/4/4/3/1, type-1 RIV frequency allocation including
small-BWP truncation, and modulation/rate derived from the received MCS index
and the receiver's PUSCH table context. Transform precoding remains a configured
waveform property, not an invented on-air bit. Invalid or unrepresentable
allocations and unsupported hopping/TDRA cases fail explicitly. The caller no
longer overwrites the decoded MCS interpretation with transmitter plan values.

The neutral TPC command is explicitly configured as index 3 (0 dB), not the old
index 1 (-4 dB). The decoded command now updates the existing Msg3 power budget
before actual waveform scaling. Missing physical budget inputs remain missing.
This is a TPC wiring repair, not certification of the entire Msg3 power-control
formula, PHR semantics, or every release-specific RAR variant. MAC field-range
validation also rejects invalid input instead of silently clamping it.

Configuration authority is in `random_access.rar_grant`, declared in global
and core YAML catalogs and the self-contained active scenario profiles. These
wire-format rules are independent of TDD/FDD; the slot-map repair is still open.
The current TDRA support remains default-A row 1 only, and no claim is made that
the old configured Msg3 delay implements the additional normative Msg3 timing.

`testRARULGrantStandardsCodec` includes an independently specified 27-bit vector,
small and large BWP RIV cases, MCS/TPC boundaries, malformed fields, and a receiver
context whose planned MCS deliberately contradicts the received index. The
first corrected-config batch also passes actual AWGN Msg3 decoding and the
existing RA MCS-authority test in
`logs/rar_standard_field_and_waveform_regressions_final_20260906.log`.
The final field-validation and power-command assertions, RA config binding,
MCS authority, AWGN four-step RA, Msg3 grant consumption, TDD sample clocks and
strict RA PDSCH ownership tests pass in
`logs/rar_codec_final_focused_20260906.log` (`RAR_CODEC_FINAL_FOCUSED_PASS`).
The cross-subsystem batch completed with
`RAR_CODEC_REQUIRED_CROSS_SUBSYSTEM_PASS` in
`logs/rar_codec_required_cross_subsystem_20260906.log`. It includes config,
DL/UL/reference-point, export/integrity, grant-consistency and E2E tests. Its
randomized truth campaign warns that generated UL traffic delivered no UL
packets in the sampled seeds: passing semantic/accounting assertions does not
qualify that QoS outcome. The full batch in
`logs/rar_codec_required_testAll_20260906.log` is still running. A separate
noiseless actual-waveform MCS-10 diagnostic
passes in `logs/rar_mcs10_actual_waveform_diagnostic_final_20260906.log`:
MCS 10, 16QAM, CRC pass, actual TBS 4224 bits. The initial diagnostic had
contradictory Msg3/global transform-precoding settings and correctly failed the
production ownership guard; both configured authorities were aligned in the
final diagnostic, without changing that guard. It is a noiseless unit waveform
diagnostic, not the requested short 12 dB TDD scenario.
The initial Msg3 table selection now also rejects a dedicated 256QAM/low-SE
data table; this RAR branch uses the applicable qam64 table under TS 38.214
6.1.4.1. That additional guard passes in
`logs/rar_mcs_table_authority_20260906.log` (`RAR_MCS_TABLE_AUTHORITY_PASS`).
Standards source: [TS 38.213 v18.8.0, clauses 8.2–8.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

## RA carrier-slot and default-A allocation repairs

The following repairs supersede the row-1-only codec limitation above, but
**do not close the TDD scenario launch gate**.

The Msg2, Msg3 and Msg4 transmitters previously inherited a default carrier
slot while their schedule/evidence records referred to later slots. The Msg2
PDCCH receiver independently inherited that same default, allowing a mutually
wrong transmitter/receiver pair to pass CRC. RRCSetupComplete set an absolute
slot directly without decomposing it into frame and slot-in-frame.

`localizeCarrierConfig` now binds each RA data/control TX and RX to its explicit
zero-based stage slot using the canonical numerology catalog. Slot-in-frame
and the unwrapped simulation frame are set together; invalid/fractional slots
fail explicitly. This does not change duplex direction or fake a slot label.
`testRAStageCarrierSlotBinding` checks TDD/FDD-independent clock conversion,
normal/extended CP, frame boundaries, a long unwrapped clock, all four actual
coded data/control stages, and Msg3 DM-RS against an independently constructed
Toolbox carrier. The fixture explicitly distinguishes the correct DM-RS from
the slot-zero sequence. These isolated waveform allocations do not represent
a qualified TDD scenario schedule.

`TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA` now contains all
16 rows for normal and extended CP and the specified numerology-dependent j
and additional Msg3 delta values. `RARULGrantCodec` decodes the received index
into the actual start/length, mapping type, K2 and delta, rather than forcing
row 1. The PUSCH producer consumes the decoded mapping type. The transmitter
rejects configured start/length values that disagree with the signalled row.
Mu=4 is explicitly rejected for this table; no j/delta value is interpolated.
A decoded common TDRA list is explicitly rejected until its separate codec
is supported, rather than being silently replaced by default A.

`testRARDefaultATimeAllocation` checks every normal/extended-CP row, exact
j/delta values, real extended-CP PUSCH RE materialization, and a real coded
mapping-B Msg3. Its receiver context deliberately has a different planned TDRA
index, so success requires consuming the on-air index. The slot-binding and
allocation tests plus the existing CDL-A RA clock regression pass in
`logs/rar_tdra_and_stage_slot_focused_20260906.log`
(`RAR_TDRA_AND_STAGE_SLOT_FOCUSED_PASS`). The fresh follow-up batch below has
also passed the added common-list rejection, codec, carrier-slot, and TDD
CDL-A RA clock tests; its remaining cross-subsystem tests are still running.

Sources: [TS 38.214 v18.8.0, clause 6.1.2.1.1 and tables -2 through -5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf),
[MathWorks carrier configuration](https://www.mathworks.com/help/5g/ref/nrcarrierconfig.html),
[MathWorks PUSCH DM-RS sequence parameters](https://www.mathworks.com/help/5g/ug/nr-pusch-resource-allocation-and-dmrs-and-ptrs-reference-signals.html).

After these patches, fresh repository-required verification was started in:

- `logs/rar_stage_tdra_required_regressions_20260906.log` — focused RA tests,
  config, DL/UL/reference points and both E2E campaigns.
- `logs/rar_stage_tdra_required_testAll_20260906.log` — complete `testAll`.

They are **running**, not reported as passed. The earlier complete-suite
process is retained, but it started before the latest edits and cannot by
itself qualify the final tree.

The radio-plot module was independently rechecked after this repair slice:
`python -m pytest tests/test_lls_radio_measurement_plots.py -q` completed
with **31 passed**. These are adapter/provenance/mathematics checks, not proof
that the missing control-signal capture producers or live publication exist.

Remaining access/runtime gates are concrete and separate:

1. `RAEventScheduler` still schedules Msg3 from a configured offset rather
   than consuming the decoded/default-A K2 plus additional Msg3 delta. Merely
   exporting those decoded values does not implement their causal use.
2. The actual RA allocation plan still needs canonical TDD symbol legality
   and response/contention-window checks. The illegal slots documented above
   are not fixed by the carrier-slot repair.
3. Full four-step RA currently executes future stages inside one outer runtime
   call. The shared channel can therefore advance beyond pending events on
   the outer timeline; this requires staged causal execution, not a clock
   reset or silently clamping a backwards request.
4. RRCSetupComplete currently uses an explicit configured PUSCH allocation
   after the RAR. Its separate scheduling/UL-grant authority needs validation;
   copying a Msg3 grant and overwriting its allocation is not proof of an
   independently received SRB1 UL grant.

PRACH/SSB/CSI paired-symbol EVM capture, full-allocation data EVM capture,
authenticated live publication, and the actual 12 dB noise-power authority
remain open as described above. No new short 12 dB, 25 dB or FDD user scenario
was launched while these gates remained open.

## RAR timing and duplex-allocation repair

The subsequent repair closes the configured-offset-only Msg3 planning defect
and the **stage allocation** part of the TDD gate above. It does not qualify
the whole control procedure or the outer runtime timeline.

`RAEventScheduler` now consumes the actual encoded RAR plan's default-A K2,
additional Msg3 delta and symbol allocation. The configured `msg3_k2_slots`
must agree with that signalled row; a contradictory value fails rather than
changing the decoded timing. Msg2 and Msg4 processing delays are minimums,
and the planner searches their bounded windows for legal canonical duplex
allocations. The new `resolveMsg3SlotFromRAR` independently consumes the
decoded timing at both actual Msg3 TX and RX and rejects disagreement with
the queued stage slot. It does not replace a received field with a planned
value. This RA path currently uses a single DL/UL numerology; cross-numerology
RA is not claimed as qualified by this sum.

The production TDD YAML now explicitly uses `setup_complete_k2_slots: 2`.
Its old value 1 cannot pair the configured full-length Msg4 allocation with
a full-slot PUSCH in the five-slot pattern. The corrected zero-based plan is:

| Stage | Slot | Direction | Actual configured symbols |
| --- | ---: | --- | --- |
| Msg1 | 4 | UL | Canonical PRACH occasion |
| Msg2 | 6 | DL | 2–13 |
| Msg3 | 9 | UL | 0–13 |
| Msg4 | 12 | DL | 2–13 |
| RRCSetupComplete | 14 | UL | 0–13 |

The FDD profile independently resolves Msg2/Msg3/Msg4/SetupComplete to
2/5/6/7. No FDD user scenario was run; the unit planner checks use its actual
resolved paired-carrier configuration. FDD availability does not remove the
Msg3→Msg4 causal dependency: even a zero configured processing delay cannot
place Msg4 before Msg3's allocated symbols have finished.

`RAConfig` also validates the selected PRACH's entire symbol span against the
canonical duplex map, even if a previously resolved occasion claims UL
availability. Absolute frame/slot and the final occupied PRACH slot are now
explicit. The long-preamble 30 kHz unit fixture spans slots 2–3, so its
slot-granularity response window begins at slot 4. Its explicit TDD map was
corrected to place that preamble in UL; no production direction override was
introduced to accommodate the old fixture. Actual response-window exports
now use the same final-PRACH-slot origin.

`logs/rar_duplex_schedule_focused_20260906.log` ends with
`RAR_DUPLEX_SCHEDULE_FOCUSED_PASS`, including actual RA waveform slot binding,
mapping-B Msg3 and the CDL-A RA clock test on the corrected plan. The fresh
expanded batch in `logs/rar_duplex_schedule_final_focused_20260906.log` has
passed TDD/FDD allocation checks, invalid-schedule rejection, the enhanced
CDL-A stage-legality/sample-clock assertions, codec/waveform tests, YAML
authority, and all eight `testInitialAccessRAPhaseCore` tests. It subsequently
completed the AWGN RA, SIB1-to-RA and runtime MCS-authority checks and ends
with `RAR_DUPLEX_SCHEDULE_FINAL_FOCUSED_PASS`.

The previous cross-subsystem batch completed with
`RAR_STAGE_TDRA_REQUIRED_REGRESSIONS_PASS`; it predates the allocation-planner
repair. Two superseded `testAll` processes (log names
`rar_codec_required_testAll_20260906.log` and
`rar_stage_tdra_required_testAll_20260906.log`) were explicitly stopped after
checking their live process identities. Their logs remain intact. They were
not stopped because of a connection timeout and are not claimed as completed
qualifications; their loaded code predates the current tree.

A single fresh complete batch is now running in
`logs/rar_duplex_schedule_full_required_20260906.log` (session 14782). It
rechecks the final allocation test, then runs `testAll`, the explicit
config/strict-proxy/DL/UL/reference, export/integrity/grant/E2E tests and the
config-driven scenario-framework test set. Its final success marker is
`RAR_DUPLEX_SCHEDULE_FULL_REQUIRED_PASS`; that marker has **not** yet been
observed. A running batch is not a completed qualification.

Remaining launch gates still include PDCCH monitoring/response-window timing
qualification, the separately received SRB1 UL grant, staged outer-runtime
execution without future channel-clock advancement, missing paired-symbol
captures, live publication and actual 12 dB noise authority. The planner's
metadata explicitly keeps `ControlMonitoringQualified=false` and
`SetupCompleteGrantQualified=false`; legal allocation is not a substitute
for these checks. No short 12 dB user scenario has been launched yet.

## Receiver EVM: remove payload-assisted reporting correction

The next audit found a separate measurement defect in
`deriveModulationTrackingMetrics`. After the receiver had equalized the data,
the reporter estimated another complex gain using the known transmitted
payload. It divided the receiver output by that gain and then normalized
received and reference powers independently. This could remove residual
amplitude/phase errors from both the EVM and symbol-decision diagnostics.
That is not an independent measurement of the receiver's output.

The reporter now preserves the actual equalized samples and computes
`sqrt(sum(abs(receiver-reference).^2)/sum(abs(reference).^2))`.
Only resource-domain matching is performed; no payload-derived gain or phase
correction is introduced. Invalid nonfinite pairs fail at the evidence
boundary rather than disappearing through `omitnan`. A zero receiver vector
has EVM 1 (100%), while any finite positive reference power is accepted,
including powers below machine epsilon. Per-sample EVM uses the full
observation's average reference power, not each individual QAM point's power
or the preview's average. The DL/UL callers preserve the new explicit
normalization label. Export adapters no longer invent a normalization when
the producer did not record one.

The normalization is independently compared with the documented
[MathWorks comm.EVM reference-signal normalization](https://www.mathworks.com/help/comm/ref/comm.evm-system-object.html).
This is receiver-link diagnostic EVM, **not** a claim of 3GPP RF conformance
measurement, RF test-window qualification or compliance with an EVM limit.

`testReceiverEVMReferenceNormalization` checks both direction branches with
TDD and FDD fixture labels, QPSK/16QAM, scales 1e-10/1/10, amplitude/phase
errors, zero output, full-observation versus preview normalization, and
nonfinite inputs. Duplex labels do not exercise scheduling: actual waveform
coverage comes from the accompanying symbol-domain, CP/DFT PUSCH,
UCI-on-PUSCH, grant-driven TX and YAML-driven PDSCH PTRS regressions.
The batch ends with `RECEIVER_EVM_REFERENCE_FOCUSED_PASS` in
`logs/receiver_evm_reference_focused_20260906.log`.

The WebGUI materializer now prefers the persisted `RawEqualizedReal/Imag`
fields from historical captures over their payload-fitted `Equalized*`
fields. Without raw samples, it requires explicit no-payload-fit receiver
provenance. Invalid raw pairs cannot fall through to apparently perfect
fitted values. Materializer version v55 invalidates the previous cache.
The expanded Python EVM/radio/running-contract/materialization/output-contract
set completed with **82 passed**.

The new review `radio_plot_review_20260906_06` contains 18 CSVs and 18 PNGs
from the same retained run (no PHY rerun). All 11 source hashes, both producer
hashes, all 36 artifact hashes and all 18 PNG decodes were checked. An
independent calculation from raw receiver pairs matched RMS and peak values
in all 20 PDSCH/PUSCH per-symbol buckets. The two data-EVM PNGs were visually
inspected. The observed RMS ranges changed as follows:

| Channel | Old payload-fitted preview EVM | Raw-receiver preview EVM |
| --- | ---: | ---: |
| PDSCH | 0.61–1.42% | 0.59–1.29% |
| PUSCH | 10.17–10.37% | 10.40–10.61% |

These are **subset** ranges, not full-allocation statistics. Existing review
directories, including the intermediate `_05` review before the cache-version
bump, were preserved. No historical trial rows or scalar EVM results were
rewritten. The new materializer can recalculate only observations for which
raw receiver samples were actually retained.

The prior full regression (session 14782, MATLAB root PID 11088) was confirmed
live and left running. It predates this EVM patch and does not qualify the
current tree. A fresh complete required set is queued in session 80602 behind
that exact process, with output destined for
`logs/receiver_evm_full_required_20260906.log` and final marker
`RECEIVER_EVM_FULL_REQUIRED_PASS`. It is not claimed complete or started
until the process/log evidence says so. A separate focused export/integrity/
plot-data/grant/E2E batch is running in session 32334, log
`logs/receiver_evm_export_required_20260906.log`; its terminal marker is
`RECEIVER_EVM_EXPORT_REQUIRED_PASS`.

Remaining gates above are unchanged: the PRACH/SSB/CSI paired-symbol capture
producers and full-allocation data capture are still missing; fixing EVM
math does not produce missing observations. RA outer-timeline causality,
control/grant qualification, 12 dB noise authority and live publication also
remain open. No new short 12 dB, 25 dB or FDD user scenario was launched.

## Full paired-allocation capture and export provenance

`output.constellation_capture_scope` now declares `preview` or
`full_allocation` in the YAML catalog and global defaults. Both causal TDD
and FDD profiles explicitly request full capture; neither profile was run.
The internal `outputs.constellationCaptureScope` reaches the common data
measurement producer. Full capture requires the complete actual transmitter
QAM count and exact finite, unique layer resource-order identities. Missing
allocation counts, coordinates or codeword-to-layer mappings fail explicitly.
The previous 512-symbol cap remains only for the declared preview mode.

All returned pairs carry observation/captured counts, scope, receiver-output
provenance and symbol-coordinate domain. Codeword indices now come from the
transmitter mapping instead of a constant zero. Mixed-codeword modulation
labels are resolved per layer/sample; there is no fabricated single Qm for
a mixed-modulation allocation. Inverse-DFT QAM positions are identified as
`pre_transform_qam_positions`: OFDM-symbol EVM remains meaningful, but these
positions are not presented as measured physical-subcarrier EVM.

Live MySQL-mode publication selects the canonical `*_constellation_samples`
path for a full capture. Shared persistence downsampling does not truncate a
table that contains explicitly full observations. This is a code-path
repair, not a claim that authenticated WebGUI publication has been exercised.
The materializer (v56) independently verifies sample counts, unique sample
and layer/resource identities, and consistent full-capture declarations
before labeling a plot full-allocation. Missing, duplicate or inconsistent
rows fail rather than silently downgrading the claim. Historical subset
captures retain their subset status; no prior capture is relabeled full.

A separate alias defect was found in `exportLLSReportingBundle`: absent raw
receiver columns were copied from `Equalized*` even when those values were
legacy payload-fitted samples. Raw columns now require explicit no-payload-fit
provenance; otherwise they remain unavailable. The export test fixture was
also missing mandatory duplex authority and now explicitly declares TDD.
The new assertion accepts absent or all-NaN raw columns (the sanitizer can
remove all-missing columns) but rejects fabricated numeric raw samples.

Validation evidence:

- `logs/full_constellation_final_waveform_20260906.log` ends with
  `FULL_CONSTELLATION_FINAL_WAVEFORM_PASS`. It covers YAML authority for both
  profiles, 3000-symbol full/preview and invalid-input fixtures, mixed
  QPSK/16QAM sample-label tests, receiver-EVM normalization, actual CP/DFT UL
  waveform/CRC/LLR tests, actual PDSCH ranks 1–8 with one/two codewords, and
  symbol-domain/post-equalization SINR tests. These are component tests, not
  a new user scenario or a link-adaptation campaign.
- The expanded Python EVM/radio/running-contract/materialization/output
  contract set completed with **92 passed**.
- `git diff --check` passed.

The first capture/export batch (session 63371) passed its waveform checks,
then failed the new export assertion because an all-NaN column had been
removed. That assertion has been corrected as described above; the failed
log remains preserved. The repaired export/integrity/grant/E2E batch is now
in session 57183, log `logs/full_constellation_export_required_20260906.log`,
root MATLAB PID 19332 / child 356. Its final marker is
`FULL_CONSTELLATION_EXPORT_REQUIRED_PASS` and has not yet been observed.

The old full batch loaded its parameter catalog before the new capture key
existed and began rejecting that key from the subsequently edited global
YAML. These cached-schema errors are not claimed to qualify the final tree.
After verifying exact process commands, root PID 11088 and child 17856 were
stopped; their logs were preserved. The already queued fresh suite (session
80602) started as root MATLAB PID 16104 / child 11136 and is executing
`testAll` plus the explicit required checks from current sources, with log
`logs/receiver_evm_full_required_20260906.log`. Its terminal marker
`RECEIVER_EVM_FULL_REQUIRED_PASS` has not yet been observed.

Full data capture is implemented and component-tested, but full-capture
CSVs/PNGs from a new integrated user scenario have not yet been produced or
audited. PRACH/SSB/CSI paired-symbol capture, staged RA outer-timeline
execution, control/grant qualification, real 12 dB authority and live
publication remain open launch gates. No new short 12 dB, 25 dB or FDD user
scenario has been launched.

## Beam CSV readback and NR symbol-decision audit

The export batch in session 57183 failed on `beamOutputsT.MetricKey`, and
the diagnostic rerun in `logs/plot_export_fixture_diagnostic_20260906.log`
identified the cause. The persisted CSV has the correct comma-separated
14-column header and eight scoped beam rows. MATLAB's automatic delimiter
detection instead interpreted the space-rich, quoted notes as a different
table format. The test now uses `sixgr.util.csvReadTable`, the same explicit
comma/header contract already used by the production reader. The diagnostic
did not justify altering the producer's values or dropping the identity
assertions. The test additionally checks that aggregates whose cited raw
beam trace is absent remain `not_available` and do not count toward coverage.

The corrected export batch is session 38325, root MATLAB PID 3324 / child
19672, with log `logs/plot_export_csv_contract_required_20260906.log` and
terminal marker `PLOT_EXPORT_CSV_CONTRACT_REQUIRED_PASS`. It has progressed
past `testLLSPlotDataValidation` into downstream system/E2E checks; the final
marker was not yet observed at this update. Its earlier diagnostic log also
contains MathWorks service error 5006 warnings; these are retained, not
hidden or counted as successful antenna validation.

An additional measurement defect was confirmed in
`deriveModulationTrackingMetrics`: the hard-decision alphabet was learned
from the transmitted payload's observed points, and bit labels were assigned
from their first-appearance order. This could exclude legal receive decisions
and miscount pre-decoder bit errors. The reporter now uses `nrSymbolDemodulate`
and `nrSymbolModulate` with the NR mapping, independently of payload coverage
or point order. Reference symbols are checked against that mapping and
normalization. Undeclared reference scaling and unsupported NR constellations
have unavailable decision statistics; their actual paired-reference EVM is
still measured without a gain/phase fit. No study mapping is guessed. These
diagnostics do not replace decoded transport-block BER or CRC.

The mapping reference is the official
[NR symbol demodulator documentation](https://www.mathworks.com/help/5g/ref/nrsymboldemodulate.html),
which specifies inverse TS 38.211 section 5.1 mapping and normalization.
`SymbolDecisionStatus` is retained in both DL/UL trial schemas and sample
evidence. The old artificial QPSK test uses actual `nrSymbolModulate` symbols
now, rather than a non-NR amplitude with no normalization authority.

`tests/testNRMeasuredSymbolDecisions.m` covers sparse alphabets, absent TX
points appearing at RX, exact bit/symbol error counts, payload-order
invariance, BPSK through 1024QAM, UL pi/2-BPSK, and unavailable mapping/scale
provenance. Both this test and the independent receiver-EVM normalization
test have passed in `logs/nr_measured_symbol_decisions_focused_20260906.log`
(session 75942, root PID 20004 / child 4620). The remaining full-capture and
actual PDSCH/PUSCH waveform checks in that batch are still in progress; its
terminal marker is `NR_MEASURED_SYMBOL_DECISIONS_FOCUSED_PASS`.

The earlier full suite (session 80602) remains running. It began before this
latest symbol-decision patch, so it is not by itself final qualification of
the newly edited tree. All changes and older logs/outputs remain preserved.
The short 12 dB TDD launch is still gated by the previously documented RA
outer-timeline execution, control/grant qualification, measured 12 dB noise
authority, missing independent PRACH/SSB/CSI EVM capture, and authenticated
live publication. This update is not a claim that every CSV/PNG is complete.

Subsequent terminal results in this turn:

- Session 75942 exited 0 with `NR_MEASURED_SYMBOL_DECISIONS_FOCUSED_PASS`.
  Actual PUSCH CP/DFT/UCI and PDSCH ranks 1–8 checks completed, along with
  symbol-domain and post-equalization SINR regressions. The PDSCH test reports
  maximum BER 0 and exact layer inverse mapping in its no-noise fixtures.
- Session 38325 reached `PLOT_EXPORT_CSV_CONTRACT_REQUIRED_PASS`, including
  the corrected plot test, export/integrity/preservation/grant checks and
  both required E2E comparisons. The randomized truth campaign warns that
  UL traffic was generated but none was delivered across its sampled seeds.
  Accounting semantics passed; UL QoS/service delivery is not qualified by
  that result. This warning must remain visible in the launch audit.
- A fresh final-source qualification is queued in session 31889 after the
  still-running full-suite child PID 11136. It runs `testAll` and the explicit
  config/strict/PHY/reference/export/E2E/scenario checks, with log
  `logs/nr_symbol_decisions_full_required_20260906.log` and terminal marker
  `NR_SYMBOL_DECISIONS_FULL_REQUIRED_PASS`. At this update it is waiting,
  not complete. The older suite was not killed or reset.
- `git diff --check` passed. No existing run artifacts were deleted or
  rewritten and no new user scenario was launched.

## Reject hidden channel-clock reversal

The next causal audit confirmed a masking defect in
`ChannelFactory.advanceRuntimeChannelStateToTime`: it passed
`targetSample-currentSample` to a helper that used `max(0, ...)`. Thus a
waveform requested in the past silently executed at the channel's newer
physical epoch. Agreement between reported counters did not prove correct
time placement. The factory now rejects backwards requests with
`sixgr:channel:RuntimeChannelTimeReversal`, reporting the state key and both
requested/current samples and times. Invalid target times, unresolved sample
rates for absolute-time requests, invalid current counters, and negative or
fractional idle sample counts are also explicit errors. Same-sample requests
remain valid no-ops. No channel reset or replay was introduced.

`testRuntimeChannelDeferredIdleClock` now checks those boundaries in addition
to the existing deferred-materialization equivalence. With actual TDL-C and
CDL-A objects in both duplex modes, it rejects the invalid requests and then
compares the next propagated waveform against an untouched twin. This proves
that rejection does not mutate the handle-backed fading clock, not merely
that the struct counter is unchanged. Explicit AWGN is covered too.

`logs/runtime_causal_clock_guard_focused_20260906.log` ends with
`RUNTIME_CAUSAL_CLOCK_GUARD_FOCUSED_PASS` (session 49507 exited 0). The batch
also passed actual RA carrier-slot waveform binding, TDD/FDD allocation
timing, and the TDD causal-wiring CDL-A Msg1/2/3/4/SetupComplete chain.
`git diff --check` passed. The full suite in session 80602 remains live;
the fresh-source suite in session 31889 is still waiting on that process
and will include this patch. Neither full suite has been claimed complete.

This is a necessary integrity repair, **not completion of the outer-runtime
timing repair**. `localCollectCoupledPRACHTrials` still invokes a complete
`runFourStepRA` attempt from the PRACH opportunity. The component waveform
chain is correctly ordered internally but can run into later slots before
the caller reaches them. The new guard prevents subsequent callers from
silently consuming an already-future channel epoch; it does not yet defer
RA state transitions or publish stages at their actual runtime slots.

The implementation still needed is receiver-owned, resumable stage execution
on the outer timeline, with only executed stages committed to access state
and exports. Long PRACH and broadcast waveforms that span slots need actual
sample-span scheduling, not a shifted timestamp or replay of completed PHY
work. Other callers also advance the same state for SSB/SIB1, SRS and data;
same-slot signals must be composed/propagated coherently before the receiver
front end. The existing multi-user contribution path already deep-forks a
canonical slot-start state for linear channel propagation, but that alone
does not establish shared nonlinear receiver-front-end execution for all
control/data signals. Those broader integration requirements remain open.

## Receiver-owned RA continuation boundary

The production `runFourStepRA` API now accepts `StopAfterStage` and
`Continuation`, returning a second output containing retained attempt state.
The coupled `CoupledTruthRuntime.runFourStepRARuntime` API exposes the same
boundary. This is runtime execution control, not a new scenario PHY-policy
override; all carrier, grant, coding, beam and timing parameters still come
from the validated configuration and decoded protocol evidence.

Completed stages are not regenerated or replayed when resuming. The state
retains decoded timing advance/RAR grant, receiver results, waveform evidence,
event/timer records and channel state. A supplied canonical channel update
must retain identity/seed/contract and cannot predate the saved state.
Configuration and non-runtime attempt options cannot silently change during
resume. A caller stopping early must retain the second output. A malformed
checkpoint, already-executed requested stage, or mismatched authority fails.

Pending results are explicitly `pending_next_stage`, with the next stage and
its resolved absolute source slot. They expose only completed runtime stage
rows, events, measured Msg1 grid evidence and available TX/RX stage results.
They do not invoke the complete-attempt exporter. `StrictOk` and RRC success
are not asserted before the required receivers finish. A decoded rejection
terminates the attempt with an empty continuation instead of executing later
PHY stages. Completed/failed attempts carry `RuntimeExecutionState=terminal`.

Two source-labeling defects were also corrected:

- Final Msg1 grid allocation previously used the caller's current slot.
  After resume that would relocate old PRACH evidence to a later stage.
  Both partial and final results now use the actual resolved PRACH absolute
  occasion, through one allocation helper.
- All RA events previously inherited the Msg1 frame/slot/symbol. Msg2,
  Msg3, Msg4 and SetupComplete events now use their own source-waveform
  frame/slot, including frame crossings. Their symbol field is unavailable
  for these slot-level decoder events, not copied from PRACH. These are
  source coordinates, not host execution/decoder-completion timestamps.

`testRAStageContinuation` compares actual coded self-loop waveforms in TDD
and FDD, full-attempt versus staged execution. It verifies unchanged prior
rows, exact final waveforms/events, a MAT checkpoint round trip, invalid
continuation rejection, no premature full-attempt artifacts, and failure
termination after a wrong decoded RAR RAPID. Self-loop fixtures are explicit
component evidence, not claims of RF-channel qualification. The existing
`testTDDCausalFourStepRARuntimeTiming` now uses the public coupled continuation
API and explicitly resumes all five stages on the physical CDL-A channel.

Validation snapshots:

- `logs/ra_stage_continuation_focused_20260906.log` reached
  `RA_STAGE_CONTINUATION_FOCUSED_PASS`, including the coded-stage comparison,
  TDD CDL-A chain and actual RA carrier-slot binding tests.
- A subsequent batch, session 23920, log
  `logs/ra_stage_continuation_final_focused_20260906.log`, includes the
  partial-evidence and failed-RAR checks. Further event-coordinate assertions
  were added during that batch, so it is not by itself final-source proof.
- Final frozen-source focused qualification is queued in session 48736 after
  child PID 3568, with log `logs/ra_stage_continuation_final_v2_20260906.log`
  and marker `RA_STAGE_CONTINUATION_FINAL_V2_PASS`. It includes the new
  nonempty live Msg1 grid and decoded-event frame/slot assertions. The marker
  has not yet been observed at this update.
- The earlier full suite remains live in session 80602; fresh full-source
  qualification remains queued in session 31889. No process was restarted
  because of a polling timeout. `git diff --check` passed.

This is implemented stage execution infrastructure, **not yet integration
of pending attempts into the outer per-slot scheduler**. The outer
`localCollectCoupledPRACHTrials` still requests a complete attempt. It must
retain continuations by UE/attempt, resume due stages independently of new
PRACH opportunities, and commit only newly observed state and rows. Moving
radio context must be separated from immutable attempt protocol authority.
Long PRACH and multi-slot broadcast waveforms also need prepared TX/received
sample-span handling in the shared slot waveform compositor. A decoded-stage
pause alone does not solve these spans or simultaneous nonlinear receiver
front-end processing. Those integration gates, real 12 dB authority,
independent PRACH/SSB/CSI EVM capture and authenticated live publication remain
open. No new short 12 dB, 25 dB or FDD user scenario has been launched.

Final update for the continuation patch: session 48736 exited 0 with
`RA_STAGE_CONTINUATION_FINAL_V2_PASS`. The frozen-source test set passed the
nonempty partial Msg1 grid, corrected stage event coordinates, failed-RAR
termination, TDD/FDD checkpoint equivalence, real coupled TDD CDL-A staged
execution, carrier-slot binding, and clock-reversal/deferred-clock checks.
Session 23920 also exited 0. The only remaining MATLAB process pair at this
update is full-suite root PID 16104 / child PID 11136; session 31889 remains
queued for fresh full-source qualification. This focused pass does not close
the outer-scheduler, sample-span/compositor, or other scenario launch gates.

## Prepared RA transmission boundary and conditional 12 dB launch

The RA API now also supports `StageAction=prepare_next_stage`. Its v2
continuation retains the actual generated stage waveform and decoded inputs,
without propagating channel samples or asserting receiver success. The
`PreparedTransmission` record identifies the stage, direction, absolute slot,
sample rate, sample/port counts and duration. Its amplitude plane is explicitly
after RA power/TA processing but **before** runtime power-context and TX RF
processing. It is not an observed RF waveform or a completed transmission.
Repeated preparation reuses the stored buffer; receiving the prepared stage
does not regenerate its transmitter. Full-attempt execution remains supported.

The initial focused batch (`logs/ra_prepared_stage_focused_20260906.log`)
passed the coded TDD/FDD preparation comparison but failed the physical TDD
resume with `RAContinuationChannelChanged`. The preparation checkpoint kept
the supplied canonical channel internally, but its public result still held
empty channel defaults because no receiver stage had appended a row yet.
Returning those defaults to the next call correctly triggered the identity
guard. The fix publishes the retained canonical states in every checkpoint
result, without changing those states or weakening the identity guard.
The physical-channel regression now checks complete returned state identity,
not merely a zero sample counter. The second batch
(`logs/ra_prepared_stage_focused_v2_20260906.log`) then reached the unchanged
prior-stage-table comparison and failed there. Converting an empty struct
array had lost the column types required by the received-stage table. Empty
runtime evidence now uses a typed schema with zero rows; no placeholder
observation is exported. The unchanged comparison remains mandatory. A third
batch is running in `logs/ra_prepared_physical_tdd_v3_20260906.log`; it is not
counted as passing until its terminal marker and successful exit are observed.

The five Python EVM, radio-plot and output-contract modules were rerun after
this repair: **92 tests passed**. The retained measurement review contains
18 CSVs and 18 PNGs, with all 36 artifact hashes rechecked against the saved
manifest after this repair. Its manifest explicitly identifies post-run processing
of an earlier run and sample-subset EVM; these artifacts are not evidence of
a new full-allocation scenario or of all requested signal EVM producers.

The user's conditional short 12 dB TDD launch remains unfulfilled, not
silently started. Remaining launch gates include outer-scheduler integration
of pending RA attempts, shared sample-span/front-end handling, common-control
and grant qualification, independent PRACH/SSB/CSI EVM measurement capture,
and authenticated live publication. The current TDD YAML also declares
`configured_snr_is_link_authority: false`, thermal receiver noise, and disabled
TX windowing. Its `snr_db: 12` field alone cannot establish an actual 12 dB
operating point or enabled windowing. These boundaries must be resolved and
verified before claiming all outputs and physical calculations are qualified.

Final focused update: session 48952 exited 0 with
`RA_PREPARED_PHYSICAL_TDD_V3_PASS`. The physical TDD CDL-A prepared/received
Msg1-through-SetupComplete chain, deferred channel-clock checks, actual RA
carrier-slot/CRC binding, and TDD/FDD coded continuation comparisons all
passed. Preparation retained the complete channel states and added zero
receiver observations; reception preserved previously completed stage rows.
This closes the two preparation-handoff regressions above, not the remaining
outer-scheduler or scenario-output launch gates. The full required suite is
still running in session 80602, with fresh-source qualification queued in
session 31889; neither is claimed complete.

## Exact RA source coordinates and CSI policy authority

The access-ledger adapter had a separate timing defect after waveform stage
execution was corrected: `canonicalRASlot` guessed whether a number was
relative or absolute, substituted response-window starts/missing-slot
offsets, and shifted Msg3/Msg4/SetupComplete with `max(previous+1, ...)`.
These operations could fabricate coordinates that disagreed with actual
waveform evidence, including an off-by-one conversion of absolute NR slots.

`runFourStepRA` now declares `RASlotTimeBase=absolute_zero_based` and the
actual `Msg1ScheduledSlot`, alongside the existing later-stage slots. The
canonical PRACH adapter retains these fields. The access ledger performs
only the declared zero-/one-based conversion, preserves each raw coordinate
in `SourceRASlot` with `SourceRASlotTimeBase`, and rejects missing, fractional,
or backward stage coordinates. Msg1 no longer inherits a later caller slot.
The legacy `LocalRASlot` column remains empty for absolute source evidence.
Equal-slot events are not moved by the projector: fine-grained intra-slot
causality still belongs to symbol/sample allocation validation.

`testPrachAccessStateMachine` now tests both explicit coordinate bases, caller
slot independence, malformed/missing coordinates, backward slots, and no
artificial shift of equal-slot events. The physical TDD CDL-A timing test
projects its actual five received stages into the access ledger and checks
every source/canonical slot. These checks passed in the initial focused
batch before a separate control-gating test failure described below.

The PRACH row adapter also no longer writes overall RA success as PRACH
`CRCPass`. It emits `CRCPass=NaN`, `CRCApplicable=false`, and
`CRCOutcome=not_applicable`; procedure acceptance and actual later-stage
transport CRCs retain their separate fields. This follows the distinction
between correlation-based [PRACH detection](https://www.mathworks.com/help/5g/ref/nrprachdetect.html)
and decoded transport blocks. State-machine tests exercise detection success
and failure with no PRACH CRC, and the producer dependency guard checks the
adapter contract. This is a producer repair, not a rewrite of old CSV values.

The expanded batch failed `testLLSControlAccessGating` because its moving-TDD
fixture assumed dynamic physical reciprocity was unavailable. The runtime
now maintains a shared moving channel, with separate tests of actual path
gains, antenna reversal and clocks. Physical reciprocity does not establish
unchanged CSI across time, nor select a CSI-consumption policy; see the
[CDL channel direction-swap reference](https://www.mathworks.com/help/5g/ref/nrcdlchannel.swaptransmitandreceive.html).
Tracing that fixture also found a real policy override: the runtime ORed
`tdd_reciprocity` orientation into the DL SRS dependency even when
`csi_acquisition_mode=dl_based` was explicitly declared.

An explicit CSI mode now governs that consumption: joint/UL-based CSI may
use reciprocal SRS; DL-based CSI does not. Orientation is consulted only
when the older config supplies no CSI mode. Physical channel sharing is
unchanged. The regression now checks missing-SRS rejection for joint CSI,
independent DL admission for DL-based CSI on the same moving TDD channel,
continued UL SRS gating, no injection of UL SRS into DL-only feedback, and
preservation of the measured signature/source age for joint CSI. Existing
freshness and measured-AMC assertions remain mandatory.

Validation in progress: `logs/ra_csi_policy_focused_20260906.log` includes the
updated gating test, moving/static TDD physical reciprocity, access-state
coordinate checks and the producer guard. The earlier coordinate batches
retain their real control-gating failure and are not reported as passing
whole batches. Full required regression remains live/queued as above. No
short user scenario has been launched; outer pending-attempt/sample-span
integration and the previously documented measurement/output gates remain
open.

The CSI-policy focused rerun then reached a further genuine configuration
gap: `lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml` enabled TRS but
declared neither transmission slots nor a period. Exact PDSCH TBS accounting
rejected the unresolved NZP-CSI-RS reservation. That browser scenario now
declares zero-based TRS slots `[2, 7]` in YAML; these are DL slots in the
test's explicit 15 kHz TDD pattern and are also DL-capable in its original
FDD profile. The gating fixture checks that the resolved builder retains the
YAML slot authority. TRS remains enabled and exact reservation remains
mandatory. This does not qualify the broader TRS resource-set or waveform
composition requirements. The first CSI-policy failure log is retained;
the new batch is `logs/ra_csi_policy_focused_v2_20260906.log`.

That second rerun stopped on a new assertion's incorrect direct access to
the immutable `ScenarioConfig` object; the fixture now reads its `.Data`
resolved tree. No production assertion was removed. The third rerun reached
the next real scenario mismatch: spatial DL grants require DCI 1_1 while
the inherited search space advertised only DL 1_0. The same browser YAML
now explicitly selects the advanced pair `[1_1, 0_1]`, with a builder
regression assertion. Scheduler rejection of unmonitored formats remains
unchanged. This applies to the spatial scenario in either duplex mode, not
an automatic format substitution for arbitrary scenarios.

Current fresh-source export/PHY/CSI qualification is session 62673,
`logs/ra_coordinates_csi_export_final_v2_20260906.log`, after the verified
prior process PID 6108. The prior export batch stopped at its already-loaded
old DCI configuration and is not a pass. The new batch must reach
`RA_COORDINATES_CSI_EXPORT_FINAL_V2_PASS` and exit successfully before it can
qualify these changes. The five Python output-contract/plot modules were
rerun and all 92 tests passed. The broad full suite continues in session
80602; its Python artifact-materialization subprocess was also observed
live, so the MATLAB wait was not treated as a stopped run or restarted.

RA ledger definitions explicitly call their coordinates source-waveform
slots, not intra-slot decoder-completion timestamps. Exact sample-span and
receiver-completion integration remains a separate open requirement; the
coordinate repair does not certify end-to-end initial-access latency.

The fresh batch has now passed the updated control/access-gating test and
the actual TDD waveform-to-ledger coordinate checks, coded TDD/FDD
continuation checks, and moving/static reciprocity tests, then reached
export/E2E regression execution. It has not yet produced the whole-batch
terminal marker. The mandatory E2E fixtures include their own FDD cases;
they are not the user's requested scenario launch.

A follow-through audit found the same fictitious PRACH CRC in the
detection-only collector and in its crash rows. Those paths now also retain
`CRCApplicable=false` and `CRCPass=NaN`. A missing detector metric remains
NaN instead of being replaced by the detection Boolean. The source guard
now isolates the exact collector rather than accidentally matching its
similarly named sweep wrapper. These final collector edits have a separate
fresh check in `logs/prach_producer_no_crc_guard_20260906.log` (session
70739); the already-running export batch predates those edits and is not
claimed as final-source coverage for them.

Final validation update for this patch set:

- Session 62673 exited 0 with `RA_COORDINATES_CSI_EXPORT_FINAL_V2_PASS`.
  It passed control/access gating, actual TDD RA waveform-to-ledger binding,
  coded TDD/FDD continuation, dynamic/static TDD reciprocity, link export,
  artifact integrity/preservation, scheduler grant consistency, and both
  required E2E semantic/comparison tests. This is focused evidence, not a
  completed full-suite qualification.
- The randomized E2E semantic campaign again warned that it generated UL
  traffic but delivered none across its sampled seeds. Passing semantic
  accounting must not be promoted into an UL throughput/service verdict;
  that outcome remains an open issue.
- Session 70739 failed because the tightened source guard also matched
  collector call sites. The guard was corrected to anchor the actual
  multiline function definition (one match verified), not weakened.
  Its fresh rerun, session 17360, exited 0 with
  `PRACH_PRODUCER_NO_CRC_GUARD_V2_PASS`, including the updated producer guard
  and access-state/coordinate negative checks.
- `git diff --check` passed. The broad full-suite child PID 11136 remains
  live, and PowerShell PID 6968 still holds the fresh full-source suite
  queued in session 31889. No user TDD/FDD scenario, cleanup, or commit was
  performed in this patch set.

## Scheduler failure propagation and bidirectional execution coverage

The earlier zero-UL-delivery warning has now been traced to an execution
defect, not established as a physical QoS outcome. The reproduction in
`logs/e2e_scheduler_failure_diagnosis_20260906.log` exposed real DL and UL
`sixgr:SchedulerBase:RequiredDCIFormatNotMonitored` exceptions. The canonical
default advertised only DL DCI 1_0 despite configuring multi-layer DL and
bidirectional traffic. Its scheduler required DL 1_1 and had no monitored
UL format. Both scheduler catch blocks appended errors but left the system
result `Ok=true`, permitting an empty coupled replay to pass accounting.

Repairs:

- DL and UL scheduler exceptions now set `out.Ok=false` and preserve the
  typed identifier, direction, slot and cell in the error. No substitute
  grants are inserted; the E2E caller rejects the failed system result.
- The canonical YAML catalog now explicitly monitors the advanced DL/UL
  pair `[1_1, 0_1]`, with scalar DL default 1_1. The production scheduler's
  strict format compatibility check is unchanged. This is separate from
  the earlier browser-scenario YAML repair.
- `testSystemSchedulerFailureStatus` deliberately removes each direction's
  monitored format in turn and requires a failed result, retained typed
  error and zero substitute grants. It is registered in `testAll`.
- The randomized semantic campaign now also requires nonempty DL and UL
  scheduler/HARQ traces, positive real grant allocations and binary receiver
  CRC outcomes per seed. Accounting success alone is insufficient execution
  coverage. CRC failure remains a legitimate measured result, not replaced
  by success to pass this guard.

Verification: session 53998 exited 0 with
`SYSTEM_SCHEDULER_FAILURE_STATUS_FOCUSED_PASS` in
`logs/system_scheduler_failure_status_focused_20260906.log`. It passed the
new negative test, `testConfig`, and the E2E semantic campaign with actual
DL/UL waveform grants and nonzero served data. The subsequent strengthened
bidirectional trace assertions and the required FastVsTruth regression are
running separately in session 77835, log
`logs/e2e_bidirectional_execution_coverage_20260906.log`; no result is
claimed for that batch until its terminal marker and exit status.

This does not clear the short user-run gate. The outer RA slot queue and
shared sample-span integration remain incomplete; paired PRACH/SSB/CSI EVM
evidence remains unavailable; final-source broad qualification is pending.
The TDD YAML still uses geometry/thermal-noise authority with
`configured_snr_is_link_authority=false`, so `snr_db: 12` is not evidence of
an actual 12 dB operating point. Its `windowing_enabled: false` is also still
an explicit unmet user requirement. No new user scenario has been launched.

### Verification and user scope update

Session 77835 exited 0 with `E2E_BIDIRECTIONAL_EXECUTION_COVERAGE_PASS` in
`logs/e2e_bidirectional_execution_coverage_20260906.log`. Both the strengthened
semantic campaign (actual DL/UL scheduler and CRC trace coverage per seed)
and `testE2E_FastVsTruth` passed. This supersedes the pending status above;
it does not qualify the independent outer-slot RA orchestration.

The user subsequently asked to leave transmit windowing disabled if it is
not mandatory for LLS and prioritize the other activities. Transmit
windowing is therefore **not a short-run launch requirement**. Receiver
FFT-window placement/timing still needs validation. An unwindowed run must
not be represented as demonstrating a windowed transmitter's OOB performance.
The TDD YAML has not been changed to enable windowing.

The optional SSB-windowing investigation found that `SSB_Tx` currently forces
zero windowing. A proposed opt-in patch and its new mixed-numerology fixture
were tested in session 42548; that batch exited 1 because the fixture supplied
a 30 kHz SS burst without a corresponding SCS carrier in wavegen. This is
not a qualification pass and not evidence of a failure in the current
single-numerology TDD profile. In response to the user's reprioritization,
only the new optional edits to `SSB_Tx.m` and `testSSBTimingResolver.m` were
reversed with an exact patch. Both files now have zero diff from their
pre-investigation versions. No previous user/runtime changes or output files
were removed. Broader mixed-numerology SSB support remains an open capability,
not silently accepted by the generator.

Source for the distinction between explicit OFDM transmit windowing and the
underlying modulator: https://www.mathworks.com/help/5g/ref/nrofdmmodulate.html
and the generator's FFT-relative percentage convention:
https://www.mathworks.com/help/5g/ref/nrdlcarrierconfig.html .

## Absolute receive-time boundary for staged RA

`runFourStepRA` and the coupled runtime facade now accept
`ReceiveThroughTime_s`. This is runtime clock input, not a PHY policy or an
SNR override. The existing offline/full-attempt API remains unbounded when
no clock is supplied. A finite bound requires the continuation output.

Before each of Msg1, Msg2, Msg3, Msg4 and RRCSetupComplete is propagated or
decoded, the engine checks the complete actual waveform interval against
that bound. An incomplete interval retains the generated sample buffer and
decoded predecessor state in a prepared continuation. It does not advance
the fading object, draw receiver noise, or create a received-stage row.
Prepared transmissions now retain absolute `StartTime_s` and
`EndTimeExclusive_s`, derived from their scheduled slot, actual sample rate
and buffer length. No nominal one-slot assumption is imposed on PRACH.
Resuming may advance the bound but cannot move it backward; omitting the
bound retains the previous bound rather than silently removing it.

Evidence: session 27070 exited 0 with
`RA_RECEIVE_TIME_BOUNDARY_FOCUSED_PASS` in
`logs/ra_receive_time_boundary_focused_20260906.log`:

- Coded TDD/FDD continuation tests exercise all five stage boundaries one
  sample before completion and at completion. Prepared waveform identity,
  prior evidence and random-number state are preserved while waiting.
- The real TDD CDL-A test checks both direction-view clocks and
  `TotalObjectInputSamples` while waiting. All five receiver stages then
  complete, with real Msg3 CRC/TA and exact shared-channel sample accounting.
- PRACH access-state checks passed in the same focused batch.

After adding an explicit omitted-clock inheritance assertion, a fresh batch
is running in session 41872, log
`logs/ra_receive_clock_final_regression_20260906.log`. It includes the final
continuation test, access gating, adapter dependency checks and both E2E
regressions. No terminal result is yet claimed for that batch. The existing
broad suite and its queued fresh-source successor remain separate gates.

Remaining integration is explicit: `localCollectCoupledPRACHTrials` still
calls the full attempt without a finite bound. The outer loop must retain
per-UE continuations, dispatch due stages before dependent scheduling, and
coordinate actual sample spans with SSB/control/data on shared channel/RF
objects. Supplying a receive bound alone is not shared-waveform composition;
the new API is not claimed to have completed that work. No user short run
was launched, and transmit windowing remains disabled as requested.

## Outer-slot RA continuation dispatch (qualification incomplete)

The coupled PRACH collector now retains per-UE `PendingRAAttempts` instead
of unconditionally running the entire procedure at its initial occasion.
Pre-scheduling revisits pending attempts before its serial TRS/PBCH/control
consumers on every slot, including DL slots. It passes the absolute start
of the current slot as `ReceiveThroughTime_s`; samples belonging to the
slot being scheduled are not already available to its scheduler.

The attempt retains its initial validated config and decoded predecessor
state, while acquiring the current canonical channel views on resume. A
pending attempt leaves access pending and emits no terminal PRACH verdict.
`ra_runtime_stage_waveforms` receives only newly executed stage rows.
Msg1 correlation/grid evidence is appended once, when Msg1 actually executes.
Finalization emits the complete-attempt artifacts without duplicating those
earlier live stage rows. Another PRACH opportunity does not restart an
already-pending attempt.

A delayed terminal PRACH row retains one-based `SourceObservationSlot` and
`SourceObservationFrame` for its original Msg1, with separate
`RuntimeEvidenceAvailableSlot`. The common control annotator preserves those
source coordinates instead of relocating the measurement to the RRC-completion
slot. RA producer fields remain absolute zero-based as explicitly labeled.

Verification boundaries:

- Session 41872 exited 0 with `RA_RECEIVE_CLOCK_FINAL_REGRESSION_PASS`:
  final clock-inheritance/coded-continuation, control gating, adapter guards,
  and both E2E regressions passed. This batch predates the outer dispatcher;
  it is not dynamic qualification of the newly connected queue.
- Session 72629 exited 0 with `RA_OUTER_DISPATCH_STATIC_PASS`, covering the
  new adapter/dispatch source guards and MATLAB parse check. Static checks
  are not a substitute for executing the integrated slot loop.
- Session 10141 is running the fresh focused continuation, real CDL-A,
  access gating and adapter checks in
  `logs/ra_outer_dispatch_final_focused_20260906.log`. No terminal result is
  claimed until verified.

The already-running broad suite produced a concrete independent timeline
failure in `test6GLLSMultiUserBeamforming`: the DL channel was at sample
61440 (1 ms), but slot-0 PDSCH requested sample 0. The exception is
`sixgr:channel:RuntimeChannelTimeReversal`, surfaced as
`sixgr:link:StrictCoverageUnsupported`, in
`logs/receiver_evm_full_required_20260906.log` at 11:50:50 UTC. This is an FDD
regression fixture, not a user FDD scenario launch. It proves that generic
control/data shared-waveform orchestration still needs repair in addition
to the RA queue; the clock must not be reset or clamped to make it pass.
That process remains live while recovering failure artifacts, not a terminal
successful suite.

Remaining queue/integration work includes direct integrated-slot execution
coverage, shared sample-span/RF composition, simulation-end draining or
explicit right-censoring of pending stages, and sweep-reset ownership.
The short user-run gate is therefore still closed. No user scenario was
launched and no existing outputs were deleted.

## Shared control-slot allocation and timing follow-up

Windowing remains disabled at the user's request. Transmit windowing is not
a prerequisite for the short NR link-level diagnostic; this deferral does
not waive receiver timing or waveform/sample continuity checks.

Previously pending focused batches have now exited successfully:

- Session 10141 exited 0 with `RA_OUTER_DISPATCH_FINAL_FOCUSED_PASS`.
  It covers adapter/source guards, continuation, the real CDL-A TDD RA
  timing fixture and access gating. It does not dynamically qualify the
  complete outer slot dispatcher.
- Session 2079 exited 0 with `CONTROL_WAVEFORM_ABSOLUTE_CLOCK_PASS`.
  Control-channel initialization now binds to an explicitly declared
  absolute waveform start, and an integrated UL DCI uses its DL control
  slot rather than its future PUSCH slot. The focused fading-clock checks
  compare against actual idle-sample propagation in both duplex modes.

The multi-user broad regression log identifies the exact earlier clock
conflict: UE 1's DL assignment PDCCH and future-UL-grant PDCCH each consume
a full DL slot buffer before its slot-0 PDSCH is submitted. This is not a
PBCH or TRS overlap in that fixture (both have zero executions). The new
absolute-clock validation exposes overlap sooner; it does not yet compose
the control and data waveforms. Rewinding/cloning the channel or declaring
an undecoded DCI successful would not repair the physical timeline.

Further source inspection found the resource-plane counterpart: the DL
and UL qualification passes each created fresh scalar CCE counters, while
PDCCH_Tx used candidate 1 on every call. This could allocate overlapping
physical resources even when the summed CCE count appeared legal.

The active qualifier now passes exact occupied PDCCH data and DM-RS REs
through `PDCCHSlotResourceLedger`. Reservations use the absolute control
slot and serving cell, not the data direction, UE, search-space ID or
CORESET ID. Coordinates are relative to CRB0, so different carrier-grid
origins cannot hide a collision. The value-owned ledger does not mutate
saved checkpoints through a shared map. A later slot clears current
reservations; a backward slot is rejected. Incompatible numerologies in
one shared-cell control ledger are explicitly rejected pending a common
time/frequency overlap resolver, not silently treated as independent.

`allocateNonoverlappingCandidate` searches only configured monitored
candidates using `nrPDCCHResources`; no arbitrary CCE offset or fabricated
candidate is inserted. Explicit CCE placement cannot be silently moved.
An exhausted candidate set is a blocked, unattempted decode with no CRC
measurement, not a fabricated CRC failure. Allocated resources remain
reserved if subsequent decoding fails. The unused scalar-count capacity
helpers were removed; no run outputs were removed.

Session 90426 exited 0 with `PDCCH_SHARED_SLOT_RESOURCES_PASS` in
`logs/pdcch_shared_slot_resources_20260906_02.log`. This verifies exact
non-overlap, exhaustion, logical-CORESET aliases, shifted grid origins,
cell/slot isolation, and two known-location DCI decodes from ONE composite
OFDM waveform propagated once through real TDL-C in TDD/FDD configurations.
Existing candidate-capacity and integrated-evidence-gate checks also
passed. The first attempt (session 30449) failed because the new fixture
placed a nonzero CORESET at an invalid RB alignment; the fixture alignment
was corrected without relaxing production validation.

The receiver also needs a multi-DCI consumption path: the existing scalar
PDCCH_Rx API correctly refuses to choose arbitrarily among different
CRC-valid payloads, but a same-UE composite may legitimately carry more
than one DCI. PDCCH_Rx now preserves `info.CRCValidHypotheses` as raw
measured observations. This does not authorize any grant or weaken the
scalar ambiguity gate. The complete runtime still needs to consume and
validate the decoded set without consulting expected transmit payloads.

Session 45828 checked the final expanded allocation matrix (24/48 RB,
AL1/2/4/8, interleaved/noninterleaved), a blind receiver's preservation of
two actual same-UE CRC-valid DCIs without ExpectedDCIBits, existing
hypothesis/evidence guards, and MATLAB parse checks. It exited 0 with
`PDCCH_SHARED_SLOT_RESOURCES_FINAL_PASS` in
`logs/pdcch_shared_slot_resources_final_20260906.log`. The working-tree
whitespace check also exited 0. This is final-source success for those
focused checks only, not full runtime or end-to-end qualification.

Outstanding integration remains substantial: generate the full same-slot
TX composite before advancing a channel, separate TX grant construction
from RX DCI success, process channel/RF/noise on the shared sample stream,
then consume the decoded DCI set to authorize the actual data receivers.
The earlier broad MATLAB suite (PID 11136) is still live and has recorded
the clock failure; its continuing artifact exports do not constitute a
pass. The fresh required suite is queued in PowerShell PID 6968 after
that process. All-output correctness and the short user TDD-run gate remain
unproven. No 12 dB/25 dB user scenario has been launched in this follow-up.

## PDSCH authority, timing, and spatial-fixture follow-up

Windowing remains deferred at the user's request. The causal scenario has
`waveform.windowing: false` and `windowing_enabled: false`; the TDD overlay
also disables windowing. This is not a waiver of receiver FFT timing,
cyclic-prefix, sample-clock, or channel-state correctness. No claim about
spectral-mask/OOB conformance is made from a windowing-disabled diagnostic.

The canonical assignment factory now supports connected scheduled-TX
authority without inventing a successful receiver DCI. The receiver rejects
TX-owned assignments, including common-procedure assignments, until a real
receiver-owned assignment is provided. The focused initial batch passed in
`logs/pdsch_tx_rx_authority_20260906_02.log`. The final authority fixture was
then changed to derive its connected transport-block sizes with `nrTBS`
from the actual allocation rather than using the codec fixture's arbitrary
short TB. That final fixture passed in
`logs/pdsch_timing_spatial_final_20260906.log` (session 40799).

`resolveSchedulerPDSCHTiming` replaces the calibration adapter's hardcoded
K0=0 with validated explicit control/data-slot authority. Its tests passed
in the same final-source batch, including frame-wrap cases, alias conflicts,
and rejection of missing control timing. The YAML PTRS and TDD rank-one /
two-port CSI-RS tests also completed before that batch failed in the next
spatial fixture. This is not an all-tests pass.

The spatial fixture had two stale assumptions: eight generic beam candidates
for strict two-port rank-two PMI, and unit power per layer rather than unit
total precoder power. TS 38.214 Table 5.2.2.2.1-1 instead specifies two rank-two
matrices, each scaled by 1/2. The test now checks both matrices against an
independent explicit reference, preserves zero-based PMI versus one-based
runtime indexing, and rejects a generic DFT approximation. The four-beam SSB
sweep remains separately checked and unchanged. Reference:
https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf

The corrected matrix check then exposed absent strict precoder/SRS inputs
in that same spatial-only fixture. Explicit test inputs were added without
relaxing production validation. The SRS decision is a labeled unit fixture,
not a claimed waveform measurement or primary runtime row. Session 41061,
`logs/pdsch_spatial_fixture_final_20260906.log`, failed because the direct
resolver call still lacked the selected-matrix digest. The fixture now
freezes its selected grant and projects that immutable context through
`applyPHYGrantToConfig` before resolving the precoder. Session 13558,
`logs/pdsch_spatial_fixture_final_20260906_02.log`, is the pending rerun; do
not count it as passed until its terminal result is checked.

Remaining gates include the full same-slot channel/RF/noise composition and
decoded-DCI-set consumption, integrated RA continuation/drain coverage,
measurement power-domain verification, and all requested measured CSV/PNG
coverage. The canonical transmitter's standalone TB-size checks also need
review against the actual allocation and original HARQ retransmission layout;
the new exact-TBS fixture does not establish that every production path
enforces this independently.

The old-source broad suite remains live, with failures recorded for mobile
UE processing-time policy, shared DL channel clock reversal, and missing
absolute PDCCH control-slot binding. Its passing export steps do not repair
those failures. The fresh required suite remains queued behind it. No user
scenario, output cleanup, or commit was performed in this follow-up.

## Control-slot and regression-execution authority follow-up

Previous goal turn classification: progress (spatial fixture corrected;
authority/timing tests completed; additional failing assertions identified).
The spatial fixture itself subsequently passed in session 13558, proving
the configured SSB sweep and strict rank-two data/CSI port dimensions with
actual transmitter waveforms. That batch then failed at the MU scheduler
fixture's unconfigured UL [0 10] symbol allocation. Its error was obscured
by a MATLAB string-array error message. Both TDRA rejection messages now
use scalar strings, and the MU fixture uses its resolved YAML PUSCH
allocation rather than an unrelated hardcoded allocation. The MU test is
not yet claimed passed.

The integrated control collector was overlooking scheduler-owned zero-based
`ControlAbsoluteSlot` while searching for the one-based `ControlSlot`
alias. `resolvePDCCHControlSlot` now reconciles the canonical field, a valid
zero-based TimingDecision, the explicit alias, and the current runtime
control slot. Conflicts and malformed values fail. It never treats a
future data Slot as control authority. The integrated qualifier persists
the resolved alias, and waveform construction uses the same resolver.
This does not fix the separate same-slot multi-waveform channel-clock
composition defect.

Session 3347 exited 0 with `PDCCH_CONTROL_SLOT_AUTHORITY_PASS` in
`logs/pdcch_control_slot_authority_20260906.log`. Control-slot and PDSCH K0
checks, 22 assignment vectors, RA/SI strict ownership, and frozen UL SRS
authority tests executed successfully. Its direct call to
`testDCIContextValidation` only constructed a function-based TestSuite and
is explicitly NOT counted as executed validation.

This exposed a broader harness defect: testAll and runFocusedTests merely
called suite factories and reported success without executing their test
bodies. There were 93 functiontests-bearing files at inspection (not a
claim that every one is registered in testAll). Both runners now delegate
to executeRegressionTest, which executes returned TestSuite objects and
requires every TestResult to pass. Empty suites, false returns, failed
reports, and incomplete tests cannot pass. No-output CLI invocations now
throw after aggregating failures, so process exit success cannot silently
represent a failed regression report. Report-returning calls retain the
explicit report.ok contract for callers that aggregate multiple sets.

The harness self-test deliberately produces failed and incomplete probe
results to verify rejection and verifies the test body really executed.
Those expected negative probe messages are not production regressions.
It passed along with typed DL/UL TDRA rejection diagnostics and the
control-slot test in session 25992. That command later exited 1 because
its test-name argument accidentally concatenated character vectors; no
claim is made for those unexecuted DCI tests. The corrected cell-array
command is session 7029, log
`logs/regression_execution_authority_20260906_02.log`, currently pending.

Final focused result: session 7029 exited 0 with
`REGRESSION_EXECUTION_AUTHORITY_PASS`. The harness self-test, TDRA error
diagnostics, and control-slot reconciliation passed. The repaired focused
runner actually executed and passed testDCIContextValidation,
testDCIWrongContextRejection, testDecodedDCIGrantAuthority, and
testSchedulerMUMIMOGrouping (55.51 s for the latter). Thus the MU fixture's
active-allocation correction is now verified; it did not require changing
the production TDRA acceptance rule. The whitespace check exited 0.

Prior broad-suite green lines from suite-factory-only calls are not valid
qualification evidence. PID 11136 remains an old-source diagnostic;
the queued fresh full suite (PowerShell PID 6968) must execute the repaired
harness before broad qualification can be assessed. Existing runtime and
artifact gaps remain open. No user TDD/FDD/25 dB scenario was launched.

## User-requested checkpoint and restricted 12 dB scope

The user requested minimizing further work, committing all existing edits,
and proceeding only with the next short 12 dB TDD diagnostic. The owned
long-running broad diagnostic and queued full suite were stopped to respect
that scope; their logs are preserved, and neither is claimed qualified.
Focused successes above remain valid only for their tested scope. All
current edits are checkpointed together, not certified production-ready.
The short run retains strict gates and measured-output provenance. The
known same-slot PDCCH/PDSCH shared-channel ordering defect is still open:
a diagnostic run may expose it and must not bypass it to claim success.
Windowing remains disabled. Further optional work and 25 dB/FDD scenarios
are deferred; no old output directories are removed.

The checkpoint TDD diagnostic subsequently failed at slot 6: TRS requested
2 ms and PRACH requested 4 ms after the reciprocal channel had advanced to
6 ms. The broadcast collector passes a one-based coupled slot into the
zero-based cell-search RuntimeSlot API; this boundary is now corrected.
The focused physical-element TDL SIB1 waveform regression passed (session
69888, `logs/sib1_runtime_slot_boundary_20260906.log`, marker
`SIB1_RUNTIME_SLOT_BOUNDARY_PASS`). The separate multi-slot acquisition
capture/commit ordering problem remains open. This correction is not a
claim that the TDD scenario now passes; no repeat scenario was launched.

### Acquisition sample-span check: padding is not the causal repair

A production-transmitter-only probe using the unchanged TDD YAML completed
with exit code 0 (session 44482,
`logs/tdd_broadcast_sample_span_20260906.log`). No channel, noise, or receiver
success was inferred from this probe. The generated capture has 38,400
samples at 7.68 MHz (5 ms). Zero-based slots 0 and 1 each contain 4,384
nonzero transmitted samples; Type-0 SIB1 occupies slot 2, starting at sample
15,360 and spanning 7,680 samples. Slots 3 and 4 contain zero TX samples.

Consequently, trimming the trailing two milliseconds cannot make this a
single-slot acquisition. SIB1 samples through 3 ms are genuinely transmitted,
while the coupled caller invokes acquisition in its first slot. The failed
run also schedules TRS in one-based slot 3, within that broadcast capture.
Zero TX samples must not be confused with absent channel tails or receiver
noise. Do not fix this by clipping real SIB1, skipping TRS/PRACH, resetting
the channel clock, or declaring acquisition complete before its samples.
The required repair is chronological shared-waveform composition and
buffering, followed by receiver completion at the actual observation end;
beam candidates must consume the same received burst rather than cause
separate channel executions. This remains unimplemented and unqualified.

### Shared received-burst candidate decoding implemented

The SIB1-enabled coupled beam sweep now invokes the transmitter and waveform
channel once, then decodes each requested SSB candidate from the identical
received burst. `runCellSearch_MIB_SIB1.CandidateSSBIndices` returns the actual
per-candidate receiver results; the coupled collector normalizes those
results without re-executing TX/channel/noise. Selection provenance explicitly
identifies a single received burst. The PBCH-only legacy path is unchanged
and does not claim this new provenance. Missing candidate results fail closed.

Focused MATLAB session 3362 exited 0 with `SHARED_BURST_FOCUSED_PASS` in
`logs/ssb_shared_received_burst_20260906.log`. The new registered regression
`testSSBSharedReceivedBurst` uses the TDD YAML and runtime fading. Profiler
assertions prove one broadcast TX, one impairment/channel invocation, and
four receiver invocations. It also checks identical received-waveform replay
and channel end-sample across all candidates, and equality with the original
single-candidate execution using the same seed. All four BCH/SIB1 decoders
passed; measured SS-RSRPs were -85.7227, -90.2984, -100.796, and -87.4135 dBm.
`testSIB1PhysicalElementTDLCausalRecovery` also passed in that same batch.

This closes repeated channel execution within a beam sweep, not multi-slot
acquisition dispatch or shared control/data composition. No replacement TDD
scenario was launched. The prior failed scenario session 45796 has now
terminated with exit code 1. Full-suite and export qualification remain
deferred under the user's restricted short-run scope; no production-grade
or complete-artifact qualification is claimed.
