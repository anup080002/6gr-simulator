# Short TDD run: measured failures and remaining integration work

## Received uplink timing-offset authority (2026-09-07, following d4c979a6)

The preceding turn made verified progress (PRACH/RAR repair and regression
evidence). The repository was clean at `d4c979a6` before this change.
The slot-21 failure is **not closed** by adding a timing-offset field.

Implemented the actual optional `n-TimingAdvanceOffset` SIB1 IE through
authoring schema, MATLAB tree construction, UPER encoding, actual UPER
decoding, and UE common-cell installation. The generic YAML input is
`initial_access.n_timing_advance_offset`, with `n0`, `n25600`, `n39936`;
omit it to omit the broadcast IE. The current causal profiles are unchanged
and omit it. A newly received absent IE clears any stale transmitter-side
value. The binding evidence labels absence separately from a decoded value.

At the main scheduler's actual SIB1 delivery boundary, the installed UE
configuration now resolves `ULTimingAdvanceOffset` using the received IE
and the tuned carrier's standard frequency range. `WaveformTimingApplied`
is explicitly **false**: no completed physical timing migration is implied.
This receiver binding supports both FR1 TDD and FDD; it does not infer zero
from an FDD label or 39936 from a TDD label.

Normative evidence was read directly:

- [TS 38.211 V18.6.0 clause 4.3.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138211/18.06.00_60/ts_138211v180600p.pdf):
  UL frame origin is advanced relative to the UE's received DL reference.
- [TS 38.213 V18.8.0 clause 4.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf):
  received TA and offset apply consistently to PUSCH/SRS/PUCCH in a TAG.
- [TS 38.133 V18.8.0 clause 7.1.2, table 7.1.2-2](https://www.etsi.org/deliver/etsi_ts/138100_138199/138133/18.08.00_60/ts_138133v180800p.pdf),
  printed pages 469-470: PRACH uses N_TA=0, not N_TA,offset=0. Absent IE
  defaults to 25600 Tc for FR1, including FDD; the pinned FR2 table gives
  13792 Tc. A signalled 39936 is also permitted for FDD. The full PDF was
  retrieved locally because its size exceeded the web reader's limit.
- [TS 38.331 V18.9.0 ServingCellConfigCommonSIB](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.09.00_60/ts_138331v180900p.pdf):
  the offset is an optional, three-valued enumeration. Unsupported explicit
  FR2 offset-IE combinations fail closed in this bounded implementation.

### Verification and current integration boundary

`python -m pytest tests/test_sib1_common_control.py -q`: **22 passed**;
181 existing ASN.1 parser deprecation warnings, not PHY failures.
Independent official-schema qualification compiled the hash-checked
`38331-i90.zip` using `asn1tools`, independently constructed four full SIB1
messages, decoded them with the production pycrate implementation, and
verified exact byte equality and independent reverse decoding. All four
passed. Schema SHA256:
`b54f593035fbdb90c79398ed85d718cce3c8c5dbcf44e084bdb6fb25b91363b9`.
Each payload is 58 bytes; payload SHA256 values:

| Offset IE | Independent UPER SHA256 |
| --- | --- |
| absent | `0e5acb583eb8a2191270a061f9ed30f4540a8c8faff956aa949d43de20f9a0a5` |
| n0 | `bc7e228f84158b710f197a92937d2da1c8cc33f5772e3b044823ee1d380a5daf` |
| n25600 | `be5e6a6db2b358b00ce6a585c9cf493915120b1d69a547ec0d2c791d96874bd9` |
| n39936 | `45ecb0d4133ea2c6fedd1ce1e5280256e31744ebc4999d674fc433059da7a55d` |

The first MATLAB batch exited 1 solely because the new fixture accessed
`cfg.initial_access` before creating that optional section. Its other 12
tests passed: decoded common authority, shared PRACH power, ASN.1 round-trip,
no-oracle SIB1, independent frozen UPER vectors, config, DL, UL, reference
points, grant consistency and both strict proxy/no-fallback guards. Log:
`logs/ul_timing_offset_authority_20260907.log`. The fixture was corrected
after the process ended; production source remained frozen during execution.
The corrected timing-offset fixture, scenario schema, parameter catalog and
both E2E/export-integrity tests passed in
`logs/ul_timing_offset_authority_verified_20260907.log`. That batch exited 1
because the older WebGUI scenario exposed the real DCI timing mismatch
described below. No production assertion was weakened to clear it.

### Repaired authored DCI timing mismatch

`test6GScenarioPromptCompliance` failed in
`DCIContextFactory.fromScheduledGrant`: the finalized DL allocation `[2 12]`
had K0=0, but the inherited configured TDRA row advertised K0=4. Both master
profiles had this disagreement with their explicit scheduling timing. The
WebGUI child additionally requested UL K2=4 while inheriting master K2=1
TDRA rows.

- Corrected the DL rows in `master_geometry_based.yaml` and
  `master_sinr_sweep.yaml` to the already authored K0=0.
- Added explicit UL TDRA rows with K2=4 to
  `webgui_sinr_sweep_64x4_mu_mimo_full.yaml`, matching its existing scheduling
  relation. Allocation indices, start symbols and lengths are unchanged.
- No runtime auto-rewrite of DCI rows, offset guessing, or relaxed grant
  validation was added. This is configuration consistency, not proof that
  every listed allocation is legal in every TDD slot; the timing engine
  still decides slot/symbol legality.
- New `testConfiguredDCITimingOffsets` executes all 96 DL/UL table bindings
  across the three profiles, verifies immutable tables, and checks that
  mismatched scheduler offsets still fail closed.

All six follow-up tests passed, exit 0, in
`logs/configured_dci_timing_20260907.log`: configured DCI offsets, unchanged
scenario prompt compliance, received UL timing-offset authority, scenario
schema, parameter catalog, and scheduler grant consistency. No `testAll`,
25 dB run, or new FDD campaign was launched. The E2E/component tests include
their existing explicitly scoped FDD compatibility fixtures.

The fresh 25-slot nominal-12 dB main TDD diagnostic exited **1** at scheduler
slot 21 with `WAVEFORM:TDDChannelTailNotConsumed`: 16 actual zero-input
samples required, zero observed. Actual SIB1 delivery passed the newly
installed offset resolver; PRACH was detected, and RAR at absolute slot 16
had DCI CRC, PDSCH CRC, RAPID match and UL-grant validation all equal to 1.
Msg3's 7,680 samples were generated, but the UL-to-DL reversal happened
before its receiver completed. No Msg3 CRC, completed access, or connected
DL/UL trial is claimed. The strict guard remains intact.

Run: `C:/Users/anup0/AppData/Local/Temp/main_shared_ra_20260907_204106`;
log: `logs/timing_offset_main_tdd_20260907.log`. Source was frozen throughout
this execution. The trace-unit repair below was made **after** it terminated.

The exhaustive first-five-row/all-CSV audit is in
`results/lls/qualification_working/reviews/timing_offset_main_first5_20260907`.
All 54 CSVs parsed: 11,288 rows, 3,452 columns, no structural or infinity
failures. Strict value closure still **fails**: 42 populated files lack
applicable domain contracts and 12 header-only tables lack completed
applicability classification. These counts are not physical qualification.
There are no PNGs because this diagnostic explicitly uses `SaveFigures=false`.
The measured SSB SINRs span 36.31-48.86 dB, so the configured 12 dB label is
not evidence of a calibrated 12 dB received operating point. That calibration
and full CSV/PNG acceptance remain open.

### PRACH trace RAR command/sample unit repair

The four-step adapter incorrectly placed `TimingAdvanceCommand` in
`timing_advance_samples`. It now calls `receivedRARTimingOnTraceClock`, using
the actual received RAR N_TA in Tc and the correlation trace's actual sample
rate. The helper checks the source and consistency with the original
PUSCH-clock TA samples. Missing received timing remains NaN; a gNB estimate
is not substituted. This duration excludes N_TA,offset and does not claim
that an absolute UE transmit origin or shared timing has been applied.

`testRARTimingTraceUnits` passed actual MAC RAR decoding plus independent
PRACH/PUSCH clock arithmetic, provenance rejection and inconsistent-unit
rejection. RAR timing authority, production adapter binding, correlation
normalization and primary truth-table tests also passed. Both final
E2E/export-integrity regressions passed; the seven-test batch exited 0 in
`logs/rar_trace_units_verified_20260907.log`. This does not change the failed
main-run result or qualify the missing shared UL transmissions.
The three new regression functions are registered in `tests/testAll.m` for
future suite execution; the full suite was not invoked, per the focused-test
restriction for this work.

Next coupled change must include all of these boundaries together:

1. Derive the UE DL reference from actual decoded SSB timing/index and
   received sample-clock evidence, with explicit implementation-delay
   calibration and cell/beam/epoch/availability lineage. A PSS candidate's
   within-burst timestamp is not itself a propagation delay.
2. Advance the **complete, uncropped** UE TX waveform by received/default
   offset plus applicable received TA, retaining distinct gNB observation
   origins. PRACH, Msg3 and subsequent UL need consistent time units.
3. Schedule direction-switch events at actual TX boundaries, including
   starts advanced into nominal guard intervals. `advanceSlot` currently
   retargets at nominal symbol boundaries; changing a timestamp alone can
   route early UL samples through the wrong directional channel.
4. Keep observation completion, RAR window timing, processing deadlines and
   pending channel/RF tails causal on that clock. Never lower the tail guard,
   crop a transmitted prefix, append fake received zeros, or switch early
   merely to make slot 21 pass.
5. Rerun the main TDD access chain, then qualify connected PUSCH/PUCCH/SRS,
   UCI, beam/CSI and measurement outputs on actual shared observations.

## PRACH receiver policy and identity repair (2026-09-07)

This repair does **not** qualify all uplink channels or the complete shared
scheduler. The following evidence is separate from the older failed-access
checkpoint below; no old run files were overwritten or promoted to a pass.

- Replayed the two original actual Msg1 captures. The logical and physical
  emitted waveforms decode the correct preamble with correlation 1. The
  received captures have decision peaks 0.340459538 and 0.443858178: the old
  fixed threshold 0.5 rejects them. The toolbox default for this actual
  B4/LRA-139/12-repetition/2-RX configuration is 0.0204124145 and decodes
  preamble 0 at 7 samples on both captures. TX active-window power and
  whole-capture mean power differ because of inactive/guard samples; this
  is not evidence of an extra attenuation requiring a power boost.
- Ran 12,000 independent complex-white-noise receiver trials, with fixed
  sample count and four predeclared YAML seeds, without outcome-dependent
  stopping or threshold fitting. There were zero false alarms; the exact
  two-sided 95% binomial upper bound is approximately 0.00030736, below
  0.001. This is receiver-algorithm evidence for the captured noise/array
  configuration, **not** a full RF false-alarm or detection-probability
  qualification. Results: `C:/Users/anup0/AppData/Local/Temp/`
  `prach_receiver_noise_qualification_20260907`; log:
  `logs/prach_receiver_noise_qualification_20260907.log`.
- Both causal YAML profiles now explicitly select `auto`. Fixed-threshold
  operation remains supported. The intentional high-threshold main retry
  test uses `lls_causal_tdd_ra_retry_fixture.yaml`, explicitly labeled as a
  negative research fixture, rather than requiring the production receiver
  to remain insensitive. This is a receiver-implementation policy, not a
  claimed 3GPP-mandated numerical threshold. See
  [nrPRACHDetect](https://www.mathworks.com/help/5g/ref/nrprachdetect.html)
  and the separate
  [PRACH detection/false-alarm example](https://www.mathworks.com/help/5g/ug/5g-nr-prach-detection-test.html).
- The full-trace wrapper had a genuine identity bug: the actual decoder
  returned preamble 7, but a subsequent maximum over tied root metrics
  selected preamble 0 and its NaN timing. It now retains the decoded
  identity and refines only that candidate's timing. The unrelated
  matched-filter statistic no longer replaces the decision peak; the
  silent alternate-detector catch/fallback and unused heuristic threshold
  implementation were removed. Diagnostic trace thresholds are unavailable
  where they would mix two different statistics; actual decision thresholds
  remain separately exported. Unused PFA/CFAR inputs are not labeled as
  measured decision inputs or a statistical qualification.
- The PRACH fixture now supplies internally consistent FDD/TDD authority,
  with an explicit negative test preserving contradictory-duplex rejection.
  Its missed-detection trace uses actual noise and a legal threshold, not a
  threshold greater than the receiver's supported maximum of 1.

### Fresh main run and remaining failure

`C:/Users/anup0/AppData/Local/Temp/main_shared_ra_20260907_190456`, log
`logs/prach_auto_main_tdd_20260907.log`, MATLAB **exit 1**. Configured limit:
25 slots; nominal receiver-noise operating-point label: 12 dB (not calibrated
measured SINR). Actual shared-stream evidence:

- Msg1 at absolute slot 14: received samples `[111360,115215)` at 7.68 MHz.
- First UE RAR observation, absolute slot 15: genuine DCI CRC failure.
- Next observation, absolute slot 16: actual DCI and PDSCH CRC passes,
  matching RAPID, valid decoded UL grant and RAR accepted. Samples
  `[122880,130575)`, with `ProxyUsed=0` and `FallbackUsed=0`.
- At scheduler slot 21 (absolute slot 20), the UL-to-DL direction reversal
  fails with `WAVEFORM:TDDChannelTailNotConsumed`: required 16 actual idle
  samples, observed zero. The pending Msg3 receive window has not completed;
  no Msg3 CRC, completed access, or connected DL/UL data pass is claimed.

The native reciprocal-object swap resets its input filter. The current
owner therefore cannot swap away a still-pending UL response. The guard
remains intact. Do not fix this by truncating received samples, resetting
the channel, inventing idle samples, or changing the TDD pattern to rescue
the test. Resolve actual UE DL-reference / UE TX / gNB RX origins first,
including decoded/default `N_TA,offset` authority and received TA, then
preserve pending directional FIR responses where required. Current shared
RA still rejects nonzero RAR TA and does not implement `N_TA,offset`; this
is unfinished integration, not a verified timing solution. Timing authority:
[TS 38.213 clause 4.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

Exhaustive available-output audit with **five** leading rows of every CSV:
`results/lls/qualification_working/reviews/prach_auto_main_first5_20260907/`.
54 CSVs, 11,288 rows, 3,452 columns; zero parse/structural/infinity failures.
Strict value-closure **fails**: 42 populated files have no applicable domain
contract in this aborted checkpoint and 12 header-only files lack completed
applicability classification. Zero semantic-check entries is not a pass.
There are zero PNGs (`SaveFigures=false` diagnostic), and no plot-completeness
claim. Token matches containing `proxy` include explicit unavailable-proxy
labels; they are not automatically evidence of executed approximations.

The four `pbch_trials.csv` rows were also checked by **column name**, not
position in a long CSV row. Actual `ReferenceSignalTxEPRE_dBm` is
5.00000000000006 dBm, `SignalledSSPBCHBlockPower_dBm` is 5 dBm, and the
reported delta is approximately 6.4e-14 dB for every beam. Their measured
SS-RSRP values are -80.9243, -89.2872, -77.4934 and -76.0461 dBm for SSB
indices 1, 2, 3 and 0 respectively. There is no demonstrated signalled-versus-
transmitted SSS EPRE mismatch in these rows. This does not close the overall
geometry/beam/noise/SINR calibration or make the nominal 12 dB label a
measured operating point.

### Verification status

The first identity rerun command used a nonexistent `runTests` helper and
failed before any test execution; it was corrected to `runFocusedTests`.
`testPRACHThresholdPolicy` then passed. The following `testPRACHLLS` execution
caused severe memory pressure and was explicitly stopped without completion;
that suite is **not passed**. Its remaining checks require a bounded rerun
and its full-trace accumulation/resource scaling needs separate attention.
The failure is retained in `logs/prach_receiver_identity_focused_verified_20260907.log`.

Subsequent named execution localized the resource problems. The smoke
fixture inherited **4 TX / 64 RX** from `core_parameter_catalog.yaml`; its
collision case committed over 26 GB of private memory. The smoke fixture
now declares **1 TX / 2 RX** without changing production configuration or
the dedicated antenna-dimension tests. The NR multi-SNR and wrong-preamble
tests had passed before that interrupted collision execution. The optional
ZC-DPE runner was separately stopped incomplete while its many direct
full-waveform convolutions were still running; no interrupted suite is
counted as a complete pass.

Following the MATLAB-performance skill, correlation-table accumulation now
retains columnar per-occasion blocks with the same sample rows, order, types
and labels. `fullWaveformCorrelation` performs the full zero-padded linear
correlation with FFTs, preserving all lags and candidate searches. Its
numerical parity test compares against `conv` for single/double precision,
unequal lengths, amplitude scales, impulse timing and empty/nonfinite
reference-kernel semantics. No signal-quality threshold, trial count,
sampling resolution or decoder assertion was weakened for speed.

ZC-DPE no longer inherits an NR decision-threshold source or exports the NR
reference trace with DPI outcomes. Its threshold is explicitly an
unqualified research-detector policy. The NR trace remains separately
diagnostic; an unavailable research decision trace is not fabricated.

The corrected complete **15/15 PRACH subtests** and correlation-kernel
parity test passed in `logs/prach_linear_correlation_final_20260907.log`.
This includes actual noisy miss/false-alarm traces, fractional preamble-7
timing, collision, reproducibility and the optional ZC-DPE smoke tests.
This limited study check is not 6G standards conformance.

The earlier 13-entry NR/config/grant/export batch passed with MATLAB exit 0:
`logs/prach_policy_export_nr_focused_20260907.log` (Msg1, B4 timing, trace
integrity, TA, config, DL, UL, reference points, grants, strict proxies and
both E2E truth/export checks). Eight bounded PRACH subtests and eight
access/hybrid/strict regressions also passed in
`logs/prach_identity_bounded_final_20260907.log`; that process then exited 1
because the skill's `selftest6GRSimToolkit` command is absent from this
checkout. Do not describe that batch as an exit-0 run or invent a substitute
self-test.

The final `prach_linear_correlation_final_20260907.log` process completed
with **exit 0**: kernel parity, all 15 PRACH subtests, then 10/10 focused
tests (RAR receive window, received-observation boundary, shared PRACH power,
threshold policy, hybrid, calibration coverage, strict proxy guards,
no-fallback guards and both E2E truth/export checks). The post-FFT boundary
batch also completed with **exit 0**, 5/5 tests: Msg1 waveform detection,
B4 short-format timing, correlation trace adapter, primary trace integrity
and received RAR TA authority. Log:
`logs/prach_post_fft_boundary_verified_20260907.log`.

The newly explicit high-threshold negative main-retry YAML compiles and its
threshold policy is asserted, but the 36/58-slot negative main fixtures
were not rerun in this checkpoint. No `testAll`, 25 dB scenario or new FDD
campaign was launched; existing tests include explicit FDD compatibility
and E2E fixtures.

### Not yet closed by these passes

1. Shared UL clock: distinct received-DL reference, UE TX and gNB RX origins,
   received/default timing-advance offset, received TA application without
   cropping, and pending reciprocal channel response at direction reversal.
2. Actual Msg3 CRC, RAR-granted Msg3 power-control authority and subsequent
   Msg4/RRC completion in the main shared stream.
3. Main-run connected PUSCH/PUCCH/SRS, UCI-on-PUSCH/PUCCH and late-created
   HARQ-ACK scheduling, with actual decoded evidence and no standalone replay
   substituted for shared observations.
4. Main-run CSI PMI/RI/CQI, SRS precoding, and QCL/TCI activation and beam
   usage traced from received control to physical samples and CSV/PNG.
5. Defined SS/CSI RSSI measurement scope, physical power/noise calibration,
   and completed CSV/PNG value contracts. Total time-sample power is not
   interchangeable with a resource-specific RSSI measurement.
6. The four-step RA correlation exporter currently places a RAR command
   index into `timing_advance_samples`; that unit mismatch remains to be
   corrected with an explicit sample-rate/TA source contract and regression.
7. Continuous, traceable IQ export and instrument playback qualification
   remain later work, after shared-stream physical correctness.

## UE-filtered PRACH reference checkpoint (previous, 2026-09-07)

**The main run still fails access qualification. Do not describe it as a
fully verified uplink, calibrated 12 dB run, or production-qualified LLS.**
This checkpoint closes the PRACH reference-power input boundary, not the
remaining Msg3, connected control/data, measurement or playback contracts.

### Corrected producer and consumer authority

- Initial acquisition and serving-SSB tracking no longer require diagnostic
  transmitter-derived pathloss to publish a usable UE SS-RSRP measurement.
- Actual decoded SIB1 common configuration is retained per UE at broadcast
  delivery, with received-tree hash, serving-cell context and epoch.
- A retained UE filter operates independently per UE/cell/SSB/configuration
  and sweep start. It initializes from the first actual observation, filters
  logarithmic RSRP in dBm, adjusts its coefficient for elapsed producer time,
  rejects future/reversed/mutated input, and does not re-filter duplicate reads.
- Both causal YAML profiles explicitly declare preconnection coefficient
  `k=4` and reference period `20 ms`. These are UE implementation choices,
  **not** a claim that SIB1 carries QuantityConfig, that these choices are
  mandatory NR defaults, or that measurement-performance requirements have
  been independently qualified. An absent policy does not synthesize a
  filtered reference. An incomplete/invalid policy is rejected before PHY.
- Shared PRACH binds decoded `ss-PBCH-BlockPower - filtered SS-RSRP` and
  checks cell, selected SSB, configuration, measurement age and delivery
  availability. A deferred attempt clears its earlier numeric pathloss.
  Changing or removing transmitter-only EPRE/pathloss diagnostics cannot
  change this UE decision. Those diagnostics remain separately exported.
- Primary reference and PRACH decision CSVs retain raw/filtered RSRP,
  filter source/hash/count/coefficient, received SIB1 power/hash/availability,
  and diagnostic physical pathloss without merging their meanings.

The PRACH pathloss equation is specified in
[TS 38.213 V18.8.0 clause 7.4](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
The filter recurrence, logarithmic domain, initialization and time adaptation
are based on
[TS 38.331 V18.8.0 clause 5.5.3.2](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.08.00_60/ts_138331v180800p.pdf).
Dedicated received QuantityConfig installation remains unqualified.

### Fresh main TDD evidence

Run: `C:/Users/anup0/AppData/Local/Temp/main_shared_ra_20260907_175527`.
`testMainSharedRARetry` completed successfully: 58 scheduler slots, three
four-beam SSB bursts, two real shared-stream PRACH transmissions, one actual
UE RAR timeout and one stale-reference deferral. The test independently
reconstructs the logarithmic filter for all 12 SSB rows.

| PRACH decision slot | Raw SS-RSRP dBm | Filtered SS-RSRP dBm | UE pathloss dB | Outcome |
| --- | ---: | ---: | ---: | --- |
| 15 | -76.046058 | -76.046058 | 81.046058 | Actual first preamble |
| 45 | unavailable fresh reference | unavailable | unavailable | Deferred: age 24 > configured 20 slots |
| 55 | -76.276058 | -76.187521 | 81.187521 | Actual second preamble, filter update 3 |

Decoded SIB1 power is 5 dBm. First/second PRACH requested powers are
-11.953942/-9.812479 dBm and target powers are -93/-91 dBm. Their actual
detector metrics are 0.340459538/0.443858178, both below the unchanged 0.5
threshold. Both captured results have `ProxyUsed=false` and
`RuntimeSelfLoopWaveformsUsed=false`. These flags qualify those captures,
not every legacy code path. The second RAR window is still pending at the
58 ms boundary; no completed expiry or successful access is invented.
PDSCH/PUSCH data trial counts remain zero.

The configured 12 dB is still an operating-point label, not a calibrated
measured SINR. This diagnostic uses `SaveFigures=false`: PNG count is zero,
not evidence that requested plots were implemented or verified.

### Verification and output audit

- Passed: `testReferenceRSRPFilter`, `testSharedRAPowerReference`,
  `testSIB1DecodedCommonAuthority`, `testConfig` in
  `logs/ue_filtered_ra_power_units_20260907.log` (MATLAB exit 0).
- Passed: actual main retry/filter reconstruction in
  `logs/ue_filtered_ra_power_main_20260907.log` (MATLAB exit 0).
- The 30-entry UL/control/beam/export batch initially passed 27 tests and
  failed three in `logs/ue_filtered_ra_power_ul_regressions_20260907.log`
  (exit 1). Full-stack reruns traced the failures to this patch's overly
  restrictive positive-epoch check: the catalog permits epoch 0 and the FDD
  profile uses it. The validator now accepts nonnegative integer epochs,
  without changing either scenario, and still rejects negative epochs.
- The first correction rerun exposed an incomplete PUCCH test fixture:
  it claimed a valid SSB observation using only a pathloss scalar. Its
  explicit analytical cell/RSRP/EPRE inputs are now complete, with a negative
  assertion proving the incomplete row is still rejected. No production
  measurement validation was relaxed to rescue the fixture.
- Final rerun: all nine selected entries passed, exit 0, in
  `logs/ue_filtered_ra_power_final_focused_20260907.log`: filter, PRACH
  reference binding, SRS/PUCCH collisions, PUSCH and PUCCH power, PUCCH/PUSCH
  reservations, UCI-on-PUSCH YAML authority, config and decoded SIB1.
  Thus every test in the original 30-entry set has a passing execution,
  including the corrected three. The original passing checks cover actual
  DL/UL staged waveforms, sample clocks, RAR, SRS RI/TPMI, UCI recovery/core,
  QCL/TCI/PMI, physical CSI/SS measurements, strict proxy/grant guards and
  both required E2E truth/export regressions. They are not substituted for
  the missing main-run uplink evidence.
- The main TDD capture above preceded the epoch-0/fixture corrections; its
  epoch-1 execution path is unchanged. Epoch 0 and equivalent measurement
  timing at 1 ms / 0.5 ms slot durations are explicitly regression-tested.
  No `testAll`, new FDD campaign, 25 dB run or long campaign was started.
- Exhaustive audit with first-five-row previews:
  `results/lls/qualification_working/reviews/ue_filtered_ra_power_first5_20260907/`.
  It inspected 166 CSVs / 16,699 rows, with no parse failures or infinity
  tokens. It found 61 empty files, six structural-header issue files, 125
  required CSV semantic failures and one required chart failure. Exit 1 is
  retained. These findings are not 125 independent newly discovered PHY
  bugs; incomplete access and unavailable primary evidence account for many.
  Lexical proxy/fallback tokens are inventory findings, not proof that a
  primary PHY row used a proxy. No acceptance assertion was weakened.
  Empty-header files are `air_interface/csv/multiuser_user_summary.csv`,
  both air/control `pdcch_trials.csv`, control `csi_rs_trials.csv` and
  `srs_trials.csv`, and `reports/csv/live_link_adaptation_input_table.csv`.

### Remaining work, in dependency order

1. Independently diagnose PRACH detection and UL spatial/receive mapping;
   calibrate operating-point and detection/false-alarm behavior rather than
   lowering the threshold to manufacture successful access.
2. Finish acquired-UE clock/TA origins and full Msg2/Msg3/Msg4/RRC causal
   integration. Audit SIB1 receiver acceptance separately from validation-
   harness `StrictOk`/TX-tree comparison gating. Audit retained broadcast
   state across sweep/cell/configuration transitions.
3. Replace the remaining generic Msg3 power calculation with its actual
   decoded common/RAR authority, numerology and power-adjustment state.
   `runFourStepRA.localResolveRATransmitPower` still uses generic P0/alpha
   defaults, `10*log10(mRB)` and headroom from capped output power. These
   are not evidence of qualified Msg3/UE-PHR behavior. Compare against
   [TS 38.213 clause 7.1.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf),
   including the RAR-specific parameter set, before executing Msg3.
4. Demonstrate real main PUSCH, PUCCH, SRS and UCI-on-PUSCH after access;
   verify late ACK binding, cancellation, receive ownership and grant clocks.
   Focused component tests cannot replace that end-to-end evidence.
5. Qualify received CSI/PMI/RI, SRS/TPMI, QCL/TCI and physical precoder usage
   through main scheduler rank/MCS/HARQ/OLLA decisions in both duplex modes.
6. Complete scoped RSSI/CSI/SS/PHR and pending-stage CSV publication, resolve
   structural/applicability failures, and verify actual generated PNGs.
7. Only then qualify continuous all-channel IQ with common timing and
   traceable playback metadata for M9384B/M9383B and 89600 VSA. No instrument
   compatibility or full NR/6G conformance is claimed by this checkpoint.

## SIB1 / actual SSS power checkpoint (previous, 2026-09-07)

**The full main run is still NOT qualified.** This checkpoint repairs the
SS/PBCH power declaration/transmitter mismatch in both causal profiles and
verifies a fresh 58-slot TDD diagnostic. It does not qualify completed access,
main PUSCH/PUCCH/SRS/UCI, calibrated 12 dB operation, all PNGs, or playback.

### Implemented and measured

- Root cause: the configured 30 dBm full-BWP budget over 300 subcarriers
  produced 5.228787453 dBm SSS EPRE, while SIB1 used the legacy -25 dBm
  declaration. The difference was 30.228787453 dB, not a propagation effect.
- Added catalog-owned `ssb_power_reference_policy` and optional integer
  `ss_pbch_block_power_dbm`. Both causal YAML profiles select
  `quantized_full_bwp_epre`. Its network implementation policy is
  `floor(PfullBWP - 10*log10(12*NRB) + configuredCommonSSBOffset)`.
  This integer allocation policy is not claimed to be mandated by 3GPP.
- A common resolver feeds both the actual SSB burst plan and the encoded
  SIB1 field. It applies the relative correction before waveform generation;
  common fixed-EPRE normalization preserves that correction. The authored
  unit-norm physical-element precoders are retained. Repeated resolution
  does not accumulate a second power correction.
- The real decoded SIB1 installer now preserves `ss-PBCH-BlockPower` in UE
  common configuration and its field/hash evidence. Main PBCH CSVs separately
  expose decoded `SignalledSSPBCHBlockPower_dBm`, its source, measured
  `ReferenceSignalTxEPRE_dBm`, and their actual difference. Post-RF deviations
  are not overwritten with the nominal declaration.
- The waveform regression measured all four beams on the authored two-
  element transmitter: a 30 dBm budget yielded actual/decoded SSS EPRE of
  5 dBm; a 33 dBm budget yielded 8 dBm. Actual SSS-sample closure tolerance
  is 1e-6 dB. Configuration checks independently cover 25/52/106-RB budgets,
  repeated resolution and conflicting/missing authority rejection.
- The contract currently rejects mixed SSB/carrier numerology, unequal
  per-SSB power offsets, allocation-dependent total-power normalization,
  and inherited data-grant power authority. These are explicit coverage
  limits, not assertions that NR prohibits these configurations. Unconfigured
  legacy/unit-waveform callers remain unqualified for this absolute-power
  contract and still require migration; no global completion is claimed.

Standards basis: the field meaning and integer range are defined in
[TS 38.331 V18.8.0, ServingCellConfigCommonSIB / SS-PBCH field descriptions](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.08.00_60/ts_138331v180800p.pdf).
The UE PRACH pathloss reference and higher-layer-filtered RSRP requirement
are in [TS 38.213 V18.8.0 clause 7.4](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

### Main evidence

Run: `%LOCALAPPDATA%/Temp/main_shared_ra_20260907_171109`.
All 58 slots completed and `testMainSharedRARetry` passed.

- Twelve actual SSB rows (producer slots 1, 21, 41) all decoded 5 dBm and
  measured 5.00000000000006 dBm transmitted SSS EPRE. Received SS-RSRP
  spanned -89.931667 to -76.046058 dBm; SS-SINR spanned 35.051961 to
  49.711129 dB. The configured 12 dB label is **not** calibrated/measured
  12 dB SINR. Independent reconstruction from the exported per-antenna
  signal/disturbance powers closed SS-RSRP within 5.685e-14 dB and SS-SINR
  within 4.974e-14 dB. This proves arithmetic consistency, not every aspect
  of measurement-estimator accuracy.
- Actual Msg1 at 14.5 ms: measurement slot 1, age 14 slots; pathloss
  81.046057648 dB; target -93 dBm; requested TX -11.953942352 dBm;
  detector metric 0.340459538 versus unchanged threshold 0.5 (miss).
- UE RAR expiry was 35 ms / 68,812,800 Tc. Slot 45 was deferred because
  the selected reference was stale, without a model-pathloss replacement.
- Actual retry at 54.5 ms: measurement slot 41, age 14; transmission/power
  counters both 2; pathloss 81.276058065 dB; requested TX -9.723941935 dBm;
  detector metric 0.448173099 versus threshold 0.5 (miss). Its RAR window
  remained pending at the 58 ms diagnostic boundary.
- DL and UL data trial rows remain zero. Main PUSCH/PUCCH/UCI/SRS and their
  rank, precoding, power/PHR and timing are not qualified by this run.

### Executed tests and artifact review

- `logs/ssb_power_reference_waveforms_20260907.log`: both
  `testSSBPowerReferenceContract` and `testSSBSharedReceivedBurst` passed.
- `logs/ssb_power_main_tdd_verified_20260907.log`: decoded common authority,
  ASN.1 round trip, two independent UPER-vector cases (actually executed
  with `run`/`assertSuccess`), no-oracle receiver, SIB1 artifact schemas,
  SSB-window power, and the 58-slot main retry assertions passed.
- Two earlier test-driver failures are retained, not counted as passes:
  `ssb_power_reference_contract_20260907.log` used the wrong receiver field
  name; `ssb_power_main_tdd_20260907.log` asserted a test-suite object instead
  of executing it. Neither failure was repaired by weakening production
  validation. The successful logs above supersede those attempts.
- `logs/ssb_power_ul_nr_regressions_20260907.log`: all 26 focused entries
  passed and the MATLAB batch exited successfully: config, DL, UL, reference
  points, strict proxy guards, scheduler grants, physical slot/sample clock,
  RAR BI codec, RAR UL-grant codec, retry state, RAR receive window, fresh
  RA reference selection, RA receive boundary, staged UL control, staged
  data (including real coded HARQ-ACK on PUSCH), UL SRS RI/TPMI estimator,
  persisted UCI evidence recovery, frozen SRS-driven PUSCH grant, PDSCH
  QCL and TCI bindings, PMI precoding, CSI-RS physical measurements, PUSCH
  and PUCCH power control, and both required E2E/export-integrity tests.
  The metadata-recovery test uses explicit table fixtures; it is not itself
  waveform evidence. The staged PHY tests use declared isolated channel/
  payload fixtures, not main access measurements. Existing FDD compatibility
  and E2E fixtures ran in this batch, separately from the authored TDD run.
- First-five-row/exhaustive audit:
  `results/lls/qualification_working/reviews/ssb_power_reference_first5_20260907/`.
  All 166 CSVs parsed (16,699 rows, 8,744 columns), with no Inf tokens.
  Qualification remains FAIL: 61 empty CSVs, six structural/header issues,
  125 required CSV semantic failures and one chart failure. There are
  19 duplicate rows and 25 identical-file groups requiring source-aware
  classification. NaN/blank/inapplicable columns have not been fabricated
  into values. Proxy/fallback text matches are lexical audit flags, not
  evidence that those backends executed. `SaveFigures=false` was explicit;
  PNG count zero is not successful PNG publication.

### Remaining work, in causal order (none waived)

1. Make UE power control consume the decoded reference declaration and
   correctly configured, causal higher-layer-filtered RSRP. The main PRACH
   selector still consumes the physical TX/RX diagnostic pathloss; equality
   of nominal and actual TX power here does not qualify UE-side authority.
   Audit PRACH spatial filtering/combining, detector margin and Msg3 power
   separately; do not lower the threshold merely to obtain access.
2. Complete acquired UE-DL and nonzero-TA UE-TX/gNB-RX time origins, real
   Msg3/contention deadlines, Msg4/control/RRC framing, receive cancellation
   and upper-layer exhaustion signalling on the shared stream.
3. Complete main shared scheduler ownership of PDCCH/PDSCH/PUSCH/PUCCH/SRS,
   including late HARQ-ACK binding to queued PUSCH and real UCI recovery on
   both transports. Retain no-eager-execution and no-proxy guards.
4. Qualify measured CSI/SRS feedback through CQI/RI/PMI/TPMI, QCL/TCI age and
   activation, actual physical precoders, rank/MCS/HARQ/OLLA and their main
   CSV/PNG outputs. Component passes are not end-to-end evidence.
5. Publish immutable observed RA stages before attempt finalization; repair
   CSV applicability/header failures and actual PNG publication. Qualify
   RSSI with its correct observation scope: the available SSB-window RSSI
   is not a full-carrier/SMTC NR Carrier RSSI result. Complete CSI/UL/PHR
   power, noise/interference, bandwidth, antenna and timing reconciliation.
6. Independently calibrate the intended 12 dB operating point, then qualify
   continuous actual post-IFFT all-channel IQ and Keysight playback. No
   authored FDD or 25 dB production campaign or `testAll` was launched.
   Long impaired runs and further 6G study features remain later goal work.

## UE retry, backoff, receive-plane and fresh-reference checkpoint (previous, 2026-09-07)

**NOT qualified as a complete NR link-level run.** The fresh 58-slot TDD
diagnostic proves the repairs below, not completed access/data, calibrated
12 dB SINR, all-channel PNGs, or continuous instrument playback.

### Repairs implemented and executed

- The main UE now owns separate preamble transmission and power-ramping
  counters. Actual UE RAR expiry advances the transmission counter; a gNB
  detector miss is not a UE retry trigger. Power ramping follows the retained
  reference and explicit lower-layer indication inputs, not an attempt-ID
  shortcut. The component checks cover unchanged/changed reference, ramp
  suspension, LBT failure, backoff eligibility and maximum-attempt exhaustion.
  Main licensed CBRA has no LBT/suspension producer yet; no such coverage is
  claimed. Exhaustion stops further attempts; an actual upper-layer RRC
  problem indication remains to be integrated.
- MAC RAR BI is encoded into real transmitted octets. Decoding handles a
  leading BI, multiple CBRA RAPIDs, BI-only PDUs and implicit padding. All
  14 defined BI values have independent byte/value assertions; reserved
  encodings are rejected. Absent BI means zero backoff, whereas BI index 0
  means 5 ms. An actual coded wrong-RAPID RAR carrying BI=2 drives the UE's
  20 ms backoff parameter; all remaining receive occasions and expiry execute
  before the seeded uniform draw is used. Value copies retain independent
  RNG state. SI-request RAPID-only, prioritized/LTM/NTN and two-step variants
  are not qualified by these CBRA changes.
- Retry decisions are exported as `ra_retry_events.csv`, with real expiry,
  counter, random-draw and backoff provenance. RAR monitoring retains decoded
  BI state/source; final Msg2 rows now expose actual decoded BI fields instead
  of an unconditional NaN.
- Actual RAR acceptance exposed a caller bug: the gain-compensated receiver
  buffer was supplied to the raw post-RF provenance check. The caller now
  supplies raw post-RF samples, and the existing strict validator derives the
  decoder plane itself. No assertion was weakened and neither plane is
  overwritten. The intermediate 48-slot main diagnostic reached actual RAR
  acceptance after this repair, but its power path was still defective.
- A second real defect was found in that intermediate run: when the SSB
  pathloss measurement aged out, generic user context silently substituted
  large-scale model pathloss. The retry's requested power jumped about 15 dB
  despite only a 2 dB ramp and a roughly 0.1 dB SS-RSRP change. Shared PRACH
  now requires the selected SSB's identified, causally available physical-
  reference measurement; model/base pathloss cannot satisfy that check.
  `ra_power_reference_decisions.csv` records usable and deferred decisions.
  Deferred attempts do not increment transmitted-attempt accounting. The
  existing YAML age limit is retained; no new fixed NR age constant is claimed.

### Main evidence and limits

Latest run: `%LOCALAPPDATA%/Temp/main_shared_ra_20260907_162452`.
The main retry assertions passed after all 58 slots executed.

| Evidence | First attempt | Retry |
| --- | --- | --- |
| Actual PRACH start | 14.5 ms / sample 111360 | 54.5 ms / sample 418560 |
| Transmission / power-ramping counter | 1 / 1 | 2 / 2 |
| Selected SSB | 0 | 0 |
| Measurement producer / available / consumed slot (one-based) | 1 / 6 / 15 | 41 / 46 / 55 |
| Physical-reference pathloss | 81.046095612 dB | 81.276075549 dB |
| Requested/applied PRACH power | -11.953904388 dBm | -9.723924451 dBm |
| Detector metric / unchanged threshold | 0.340461278 / 0.5 | 0.448173950 / 0.5 |
| Actual RAR monitor observations within this run | 16 | 2 |

The first UE response window expires at exactly 35 ms / 68,812,800 Tc.
Slot 45 is explicitly deferred: the delivered SSB-0 reference is 24 slots
old versus the configured limit of 20; its decision row contains no numeric
pathloss substitute. A later delivered SSB measurement enables the actual
slot-55 retry, aged 14 slots. Both PRACH attempts remain below threshold.
There are zero DL/UL data trial rows; the second RAR window is still running
at the diagnostic stop, not falsely declared expired.

**New confirmed signalling/power defect:** the retained CRC-decoded SIB1
tree in the first Msg1 capture contains
`servingCellConfigCommon.ss_PBCH_BlockPower = -25 dBm`, while the associated
physical-reference row measures transmitted SSS EPRE at
`+5.228787453 dBm`. The discrepancy is approximately 30.2288 dB.
`buildBCCHDLSCHMessage` supplies a -25 default when the field is absent;
the shared power path currently consumes measured TX/RX reference powers,
not a qualified received-SIB1-power plus UE higher-layer-filtered-RSRP
contract. The freshness repair does **not** close this separate defect.
Bind a configuration-owned transmitter EPRE budget to the actual broadcast
value, install that decoded value at the UE, and implement/verify its
higher-layer RSRP filtering before claiming TS 38.213 power-control closure.

References: [TS 38.321 V18.8.0, 5.1.3/5.1.4 and 7.2](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.08.00_60/ts_138321v180800p.pdf),
[TS 38.213 V18.8.0, 7.4](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

### Verification record

- `logs/ra_retry_backoff_components_20260907.log`: the five preceding
  component calls passed; batch exit 1 because a function-test suite object
  was passed to `assertSuccess` without executing it. Corrected the command,
  not production code or assertions.
- `logs/ra_retry_main_20260907.log`: both offline multi-attempt tests passed;
  the main run failed at actual RAR acceptance with
  `PhysicalRAObservationMismatch`. Retained run: `main_shared_ra_20260907_160316`.
- `logs/ra_retry_receive_plane_20260907.log`: exit 0 after correcting the raw
  receive-plane handoff; components and 48-slot retry test passed. Retained
  run: `main_shared_ra_20260907_161240`. That test's arithmetic-only power
  assertion was insufficient to detect stale-reference model substitution;
  it is not a power qualification pass and was strengthened accordingly.
- `logs/ra_retry_fresh_reference_20260907.log`: exit 0. Fresh/stale/future/
  wrong-reference and same-row power checks, received-BI retry tests and the
  stronger 58-slot main test passed. Both actual PRACH captures and their
  measurement identities/timing/power equations were checked.
- `logs/ra_retry_ul_regressions_20260907.log`: exit 0. All 28 focused test
  entry points completed, including the two-case multi-attempt suite:
  RAR codec/grant/window/retry, fresh-reference and five-stage received-buffer
  checks; RA artifact schemas and exact sample clock; `testConfig`,
  `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`,
  `testStrictProxyGuards`, `testE2E_FastVsTruth`,
  `testE2E_TruthPacketSemanticCampaign`, `testSchedulerGrantConsistency`,
  `testUplinkControlStreamStages`, `testDataChannelStreamStages`,
  `testLLSULSRSRITPMIEstimator`, `testRecoveredPUSCHUCIEvidence`,
  `testPUSCHCausalSRSFrozenGrant`, `testPDSCHQCLStatePropagation`,
  `testPDSCHTCIStateBinding`, `testPMIPrecodingRuntime`,
  `testCSIRSPhysicalResourceMeasurements`,
  `testPUSCHMeasuredReferencePowerControl` and
  `testPUCCHMeasuredReferencePowerControl`. Existing FDD compatibility/E2E
  fixtures are separate from the authored TDD main diagnostic. These passes
  do not establish main-stream access, connected UL or full NR conformance.

Final first-five-row audit:
`results/lls/qualification_working/reviews/ra_retry_fresh_reference_first5_20260907/`.
It inspected all 166 CSVs: 16,690 rows and 8,730 columns; zero parse failures
or infinities, 61 empty files, 19 duplicate rows and 25 byte-hash mirror
groups. There are 125 required CSV semantic failures and one chart failure;
the strict value-review gate is FAIL. Six files lack headers: multiuser
summary, both PDCCH copies, CSI-RS, SRS and live LA input. Token counts
(209 proxy, four fallback, three placeholder, zero synthetic) are lexical
review flags, not proof of which execution backend ran. `SaveFigures=false`
was explicit, and there are zero PNGs; this is not PNG publication evidence.

### Remaining acceptance work (not waived)

1. Repair signalled SS/PBCH reference power, waveform EPRE authority and UE
   filtered-RSRP consumption; then evaluate PRACH beam/spatial filtering and
   receiver margin without changing thresholds to force access. Audit Msg3
   power-control inputs/formula and reference age at actual transmission
   separately from ordinary PUSCH component tests.
2. Complete acquired UE-DL clock origin, nonzero-TA UE-TX/gNB-RX origins,
   final-window FDD tail handling and actual Msg3/contention timer deadlines.
   Preserve guards against immediate UE failure inferred from a gNB decoder.
3. Complete main shared PDCCH/PDSCH/PUSCH/PUCCH/UCI/SRS scheduling/receive
   ownership, actual control and RRC framing, upper-layer RA exhaustion
   signalling, and cancellation of stopped receive windows. Do not permit
   legacy eager PHY execution on the stream-owned channel.
4. Publish already measured per-stage PRACH/Msg2/Msg3/Msg4 primary rows while
   access is pending, with immutable receiver outcomes and separate attempt
   lifecycle events. At present the detailed primary RA stage tables still
   wait for terminal attempt finalization; raw runtime stage/IQ evidence is live.
5. Qualify late HARQ-ACK on queued PUSCH, PUCCH/PUSCH UCI recovery, SRS-driven
   UL rank/TPMI and CSI CQI/PMI/RI, physical precoders and QCL/TCI source/age
   binding in the actual main stream. Component passes alone are insufficient.
6. Qualify RSSI/SS/CSI RSRP/SINR and PHR with explicit power plane, reference,
   antenna and bandwidth/window definitions; repair CSV applicability/schema
   and real PNG publication. Then establish independently calibrated 12 dB
   operation and continuous all-channel Keysight playback. No authored FDD,
   25 dB production scenario, or `testAll` was launched in this checkpoint.

## Executed UE RAR window and canonical IQ checkpoint (previous, 2026-09-07)

**The main run remains NOT qualified.** This checkpoint closes the immediate
gNB-miss-to-UE-failure defect for the authored TDD diagnostic. It does not
claim completed shared-stream access, uplink data, all-channel measurements,
PNG publication, or instrument-ready continuous playback.

Implemented and verified:

- The UE arms actual Type1 receive observations before Msg1 propagation.
  No gNB detector result or generated Msg2 waveform is accepted as receiver
  evidence. Every applicable occasion runs the blind PDCCH/RAR receiver on
  actual gain-compensated shared-stream samples, including occasions with
  no RAR transmission. Other real SSB/TRS transmissions remain in the stream.
- A gNB PRACH miss now leaves the UE waiting. Failure occurs at the exact
  response-window expiry; missing earlier receiver observations are an
  error, not an excuse to finalize a delayed stored gNB failure. Actual
  receive completions at a deadline are handled before the timer event.
- A decoded response for another RAPID does not stop monitoring. Accepted
  responses require actual CRC-valid control/data, matching RAPID, valid
  decoded UL grant, covered PDSCH allocation and response-window timing.
  Subsequent slot fields are bound to the received RAR/TDRA rather than the
  initially planned Msg2 slot. The shared path uses one blind decoder per
  observation, with Msg2 transmission separate from UE monitoring.
- Shared physical advancement, downlink preparation origins and RA stage
  timestamps use exact CP-OFDM slot sample boundaries. Independent public
  `nrOFDMInfo` comparisons pass for mu 0 through 4 and 60-kHz extended CP,
  including the unequal normal-CP slot extents at higher numerologies.
  This does not qualify every other scheduler/time-origin caller.
- Three source-labelled RAR monitoring CSVs are registered in both live and
  final writers. Actual TX-after-RF, RX-before/after-RF and digital-gain-
  compensated RX samples are retained per observation under
  `air_interface/mat/rar_monitoring_observations`. These MATs are diagnostic
  receive windows, **not** complete continuous instrument-playback files.
- Shared captures and RA result folders now consume the explicit configured
  run root. The discovered `air_interface/air_interface/mat` nesting defect
  was fixed at the caller, not by moving or concealing old diagnostic files.
- Unexecuted Msg1/Msg2/Msg3/Msg4 primary trial tables retain their schema but
  no invented rows. The preamble-transmission event now uses the absolute
  PRACH slot and actual attempt identifier instead of within-frame slot 4
  and a hardcoded attempt-1 status. Actual main retry counters remain open.

References:
[TS 38.321 V18.8.0, clauses 5.1.3 and 5.1.4](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.08.00_60/ts_138321v180800p.pdf),
[TS 38.213 V18.8.0, clause 8.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

### Tests and retained failures

- `logs/rar_receive_window_component_20260907.log`: exit 0. Actual coded
  TDD/FDD unit-channel RAR windows, wrong-RAPID then valid-RAPID reception,
  no-RAR decoding through expiry, skipped/premature observation guards, and
  all five coded TDD received-buffer stages.
- `logs/rar_receive_window_main_20260907.log`: exit 1. The 36-slot main run
  completed, but its inherited test still expected four SSB rows. Inspection
  proved two distinct real four-beam bursts at slots 1 and 21. The fixture
  now requires all eight rows with exact burst origins and identities; its
  CRC assertions were not weakened.
- `logs/rar_receive_clock_ul_regressions_20260907.log`: exit 1 at the final
  main capture-location assertion. Before that, the clock/window/stage and
  RA artifact tests, `testConfig`, `testLLS_DL`, `testLLS_UL`,
  `testLLS_ReferencePoints`, `testStrictProxyGuards`, `testE2E_FastVsTruth`,
  `testE2E_TruthPacketSemanticCampaign`, `testSchedulerGrantConsistency`,
  `testUplinkControlStreamStages`, `testDataChannelStreamStages`,
  `testLLSULSRSRITPMIEstimator`, `testRecoveredPUSCHUCIEvidence`,
  `testPUSCHCausalSRSFrozenGrant`, `testPDSCHQCLStatePropagation`,
  `testPDSCHTCIStateBinding`, `testPMIPrecodingRuntime`, and
  `testCSIRSPhysicalResourceMeasurements` completed. The misplaced captures
  exposed a real producer-path defect. This entire batch is not a pass.
- `logs/rar_receive_canonical_export_20260907.log`: exit 0 after correcting
  that producer. Re-ran the exact clock, RAR receiver/window and five-stage
  received-buffer checks, followed by a fresh full 36-slot main diagnostic.
  It verifies canonical capture paths/counts and forbids nested component
  roots and unexecuted primary-stage rows. No `testAll`, authored FDD
  scenario, or 25 dB run was launched. Existing compatibility fixtures
  exercised FDD separately from the TDD main diagnostic.

Latest main run: `%LOCALAPPDATA%/Temp/main_shared_ra_20260907_153343`.
It completed 36 scheduling slots and two four-beam SSB/SIB1 bursts with all
BCH/DCI/DL-SCH CRCs passing. PRACH detection remains 0.340461277865219 versus
the unchanged 0.5 threshold. The UE executed all 16 Type1 monitoring
occasions: zero-based slots 15-18, 20-23, 25-28 and 30-33. All had actual
candidate decoding and no accepted RAR. There are 16 matching receive-IQ
captures, and actual expiry at 35 ms (68,812,800 Tc). DL/UL data trial counts
are both zero. The 12 dB number is still a noncontrolling label, not a
measured physical SINR claim.

Final first-five-row audit:
`results/lls/qualification_working/reviews/rar_receive_canonical_first5_20260907/`.
All 164 CSVs were inspected: 16,257 rows, 8,682 columns, zero parse errors or
infinities; 61 empty files, six structural-issue files, 125 required CSV
semantic failures and one chart failure. No synthetic tokens were found;
proxy/fallback token counts alone are not proof of proxy execution. The
qualification gate remains FAIL. `SaveFigures=false` was explicit for these
diagnostics, so no runtime PNG publication is claimed.

### Remaining main-runtime work (not waived by component passes)

| Area | Open repair / acceptance evidence |
| --- | --- |
| PRACH detection and retry | Investigate measured DL reference pathloss versus the actual UL beam/spatial filter and detector margin. Implement separate UE transmission/power-ramping counters, maximum-attempt handling, decoded BI/backoff and the next legal PRACH occasion after actual expiry. The main caller still defaults to attempt 1. Do not lower the detector threshold merely to obtain access. |
| Shared timing | Complete acquired UE-DL timing-origin and nonzero-TA UE-TX/gNB-RX handling, including filter/propagation tails at the final FDD receive deadline. Qualify successful shared Msg2/Msg3 reception, stopped-window cancellation, and remaining nominal-slot callers. |
| Msg3 / Msg4 / SRB1 | Start contention timing from actual Msg3 transmission completion; replace private Msg4 control/framing assumptions; validate all real receiver deadlines. |
| Main data/control stream | Complete chronological PDCCH/PDSCH/PUSCH/PUCCH/UCI/SRS ownership. The legacy-execution guard must stay enabled; zero data here is not successful integration. |
| PUCCH / PUSCH UCI | Demonstrate late DL ACK reservations reaching already queued PUSCH, actual UCI multiplexing or justified suppression, frozen grant/TB/coding layouts and recovered feedback on the main stream. |
| SRS / CSI / PMI / TCI / QCL | Prove measured/reported state, timing, age, beam association and actual precoders are connected to main grants and their CSV/PNG evidence. Focused component checks passed; main end-to-end use is not yet qualified. |
| RSSI / RSRP / SINR / PHR | Preserve antenna, reference, bandwidth, power-plane and window definitions. Existing measured SSB-window RSSI is not universal carrier/SMTC RSSI. Verify actual UL/CSI/PHR measurements and plots once their transmissions execute. |
| Exports / calibration / playback | Resolve remaining CSV applicability/semantic failures and actual PNG generation; establish independent fixed-reference 12 dB calibration; only then qualify continuous all-channel IQ for the specified Keysight instruments. |

## Type1 RAR window planning and uplink regression checkpoint (previous, 2026-09-07)

**The main run is still NOT qualified.** This checkpoint repairs the RAR
opportunity planner and backoff arithmetic, not the remaining main UE
receive-window/retry state machine. Component passes below must not be
promoted to successful end-to-end uplink or instrument-playback evidence.

Changes made and tested:

- The actual PRACH CP/useful-sample end is now retained in exact Tc ticks,
  including long and short formats and later repetitions of the selected
  PRACH resource. Guard zeros are not counted as transmitted PRACH symbols.
- Common Type1 PDCCH configuration is resolved independently of a chosen
  Msg2 slot. Both TX/RX and the RA planner consume the same decoded common
  CORESET/search-space authority; no additional scenario-specific constants
  or relaxed CCE/candidate checks were introduced.
- `RARMonitoringWindow` finds the first configured, DL-available CORESET
  separated from the last PRACH symbol by at least one Type1-SCS symbol.
  Periodicity, offset, monitoring duration, symbol position, actual CP
  boundaries, TDD availability and partial final slots are retained.
  The window and its expiry follow TS 38.213 clause 8.2; they are explicitly
  a receive-opportunity plan, not executed blind-decoder evidence.
- `RAEventScheduler` now searches those monitoring occasions rather than
  every slot. Msg2 PDSCH must fit inside the response window and its encoded
  K2+delta must yield a legal Msg3 UL allocation. The same code resolves
  both TDD and FDD configurations. Multiple in-slot RAR monitoring starts
  still fail explicitly; they have not been silently truncated or qualified.
- Backoff arithmetic starts after an unsuccessful response-window expiry,
  not its beginning. Continuous BI-times-uniform-draw delay is represented
  in Tc, and the earliest complete slot boundary is rounded upward. This
  is a candidate restart boundary, not evidence that a retry was executed.
  Existing independent-attempt and phase/impact callers were migrated to
  explicit window authority; the contention impact model also now converts
  its slot-based latency estimate to milliseconds using the actual SCS.
- RA timer CSVs retain response-window `StartTicks`,
  `ExpiryTicksExclusive`, and `ClockSource`. Planned start rows are labelled
  `planned_not_timer_execution` rather than claiming a running UE timer.

Normative reference:
[TS 38.213 V18.8.0, clause 8.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

Verification:

- `logs/rar_monitor_window_initial_20260907.log`: **failed** initial batch.
  My fixture-regeneration edit accidentally produced NaN expected backoff
  columns; a second fixture also retained an obsolete window-origin
  assumption. Both test inputs were corrected, without changing or weakening
  their assertions. This log is not a passing result.
- `logs/rar_monitor_window_boundary_20260907.log`: exit 0. Exact one-Tc
  boundary/period/duration tests, all eight initial-access phase-core tests,
  real RAR DCI/PDSCH, TDD/FDD allocation checks, five coded TDD received
  stages, RA config/repetition/artifact tests, and the main access-boundary
  regression passed. The main regression intentionally verifies a genuine
  failed-access/no-data outcome; it is not a qualification pass.
- `logs/rar_window_ul_regressions_20260907.log`: exit 0. Rechecked the window,
  eight phase-core tests and two independent-attempt tests; then `testConfig`,
  `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`, `testStrictProxyGuards`,
  `testE2E_FastVsTruth`, `testE2E_TruthPacketSemanticCampaign`,
  `testSchedulerGrantConsistency`, `testUplinkControlStreamStages`,
  `testDataChannelStreamStages`, `testLLSULSRSRITPMIEstimator`,
  `testRecoveredPUSCHUCIEvidence`, `testPUSCHCausalSRSFrozenGrant`,
  `testPDSCHQCLStatePropagation`, `testPDSCHTCIStateBinding`,
  `testPMIPrecodingRuntime`, and `testCSIRSPhysicalResourceMeasurements`.
  No `testAll`, production FDD scenario, or 25 dB run was launched; existing
  focused E2E compatibility fixtures include FDD execution.

Actual main diagnostic: `%LOCALAPPDATA%/Temp/main_shared_ra_20260907_142140`.
It completed 16 slots, four successfully decoded SSB/SIB1 candidates and an
actual shared-stream PRACH, but **zero DL/UL data trials**. PRACH detection
remains 0.340461277865219 against the unchanged 0.5 threshold. The exported
response-window plan is [15 ms, 35 ms), i.e. slots 15 through 34 inclusive
with zero-based indexing. The 16-slot run ends before that window expires.

Offline reprocessing of the retained samples (same regression log) found:
TX-after-RF detects the correct preamble with metric 1; RX-before-RF is
already below threshold at 0.340461; RX-after-RF is 0.340284; actual digital
gain compensation restores 0.340461. Thus receiver AGC/display scaling is
not the cause of this miss. The capture ledger records 94.1081 dB applied
base pathloss and 7 dB receiver NF. The selected downlink beam's measured
pathloss reference used by PRACH power control is a different quantity;
its UL spatial-filter consistency still needs investigation, not an
arbitrary power correction or lower detector threshold.

CSV review: `results/lls/qualification_working/reviews/rar_window_first5_20260907/`.
All 162 CSVs were parsed and their first five rows retained: 15,841 rows,
8,650 columns, zero parse failures/infinities, 57 empty files, six structural
issue files, 121 required CSV semantic failures and one chart failure.
The qualification gate remains **FAIL**. The extra three columns are exact
timer-clock provenance, not extra measured trials. This diagnostic used
`SaveFigures=false`; no runtime PNG publication is claimed.

Remaining work, without dropping any requested family:

| Area | Remaining main-runtime verification/repair |
| --- | --- |
| PRACH and RA timers | Do not expose gNB detection failure as an immediate UE failure. Execute actual Type1 receive observations through expiry, then update retry/power-ramping counters and bind the next legal PRACH occasion. The independent-attempt wrapper is not this main shared-stream state machine. |
| Msg3 / Msg4 / SRB1 | Start contention timing after actual Msg3 transmission, retain distinct nonzero-TA UE-TX/gNB-RX origins, migrate private Msg4 control framing, and verify actual receiver completion against deadlines. |
| Main shared clock and streams | Complete chronological PDCCH/PDSCH/PUSCH/PUCCH/UCI/SRS integration, including unequal higher-numerology slot sample extents. Component stage tests do not close this. |
| PUCCH / PUSCH UCI | Verify late-created HARQ feedback, decoded grants, frozen TB/coding layouts, multiplexed UCI and suppression decisions on the main stream after successful access. |
| SRS / CSI / rank / PMI / TCI / QCL | Prove actual sounded/reported state reaches the main grants and physical precoders with correct age and beam association; component tests alone are insufficient. |
| RSSI / RSRP / SINR / PHR | Retain explicit antenna/reference/window/bandwidth/power units and source identities. SSB-window RSSI is not full-carrier/SMTC RSSI. Main UL/CSI/PHR measurements remain unavailable without those transmissions. |
| CSV / PNG / evidence | Remove or distinguish remaining unexecuted planned stage fields from primary measurements; resolve empty-table applicability and actual runtime plot publication. The preambleTransMax event still uses the within-frame slot rather than the absolute runtime slot and hardcodes attempt 1 in its status. |
| Nominal 12 dB / Keysight | The current 12 dB value is a noncontrolling operating-point label. Declare and verify a fixed independent reference calibration before claiming measured 12 dB. Continuous, traceable all-channel IQ/VSG playback remains unqualified. |

## RA-RNTI waveform and decoded main-scheduler authority (preceding checkpoint, 2026-09-07)

**Still not a qualified production LLS.** The repairs below do not establish
successful main-run access, data, UCI, SRS, CSI feedback or continuous
instrument playback. The full-main timing/integration checklist stays open.

Implemented at the actual producer/receiver boundary:

- Msg2 now uses canonical RA-RNTI DCI 1_0: reference-width FDRA, four TDRA
  bits, VRB mapping, MCS, TB scaling and reserved bits. It no longer uses
  the private 32-bit allocation payload or C-RNTI HARQ/NDI/RV fields.
  CORESET0 provides the frequency reference when configured; otherwise the
  initial DL BWP does. The canonical packer/parser and real polar chain
  execute these bits. This bounded implementation rejects shared-spectrum,
  FR2-2, configured common TDRA lists and interleaved RAR PDSCH rather than
  silently substituting licensed/default-A/noninterleaved behavior.
- TX and blind RX independently materialize Type-1 common PDCCH from the
  decoded common CORESET/search-space IEs, including monitoring periodicity,
  start symbol, candidates and CCE capacity. Physical scrambling uses zero
  RNTI; the RA-RNTI masks the DCI CRC. Both scenario YAMLs now declare their
  common resources. No production FDD or 25 dB scenario was launched.
- Msg2 RX derives its PDSCH allocation, MCS, mapping, TBS and LDPC layout
  from decoded DCI plus UE common configuration. It no longer consults the
  TX PDCCH/PDSCH objects, expected DCI bits, TX TBS or RAR payload length.
  Default-A normal/extended-CP tables and MIB DMRS position are explicit.
- Msg2 rank-one/QPSK, additional DMRS position 2, CDM no-data ownership,
  zero xOverhead and the decoded TB scaling reach actual nrTBS/LDPC/grid
  generation. Common PDSCH DMRS amplitude now derives from the standard
  data-to-DMRS EPRE ratio. An independent generated-grid power check catches
  the former unboosted CDM2 defect even when matching TX/RX assumptions
  would pass CRC. This does not alter connected-data FRC calibration policy.
- The main broadcast capsule previously discarded decoded MIB/CORESET0
  fields while retaining SIB1. The slot-15 failure in
  `logs/rar_final_ul_main_regressions_20260907.log` exposed that handoff.
  The capsule now retains those actual receiver fields; the main regression
  checks their arrival in the RA continuation and DCI frequency reference.
- Msg3's three silent setting-assignment catches were removed. Invalid
  transform-precoding/PT-RS flags now fail before transmission; they cannot
  silently select Toolbox defaults. Delayed coded Msg3/SRB1 recovery and
  measured PRACH timing remain distinct from a full-main access pass.
- Canonical DCI parsing validates binary values before integer conversion.
  SIB1 semantic comparison normalizes equivalent scalar string/character
  and singleton SEQUENCE OF representations while still rejecting a changed
  decoded IE. No PHY assertion or failure threshold was weakened.
- `control/csv/msg2_dci_fields.csv` records only actual TX fields and
  CRC-valid RX fields with context identity and reference provenance. An
  unexecuted Msg2 leaves a typed empty table, not planned decoded evidence.
- RAR candidate export no longer hardcodes AL4 or creates a selected
  candidate when Msg2 never ran. It preserves actual decoder aggregation,
  CRC, attempted RNTI and reduced hypothesis selection. Unpublished CCE
  start remains explicitly unavailable; candidate ordinal is not substituted
  for a CCE index. Actual AL2/4/8 waveform cases exercise this mapping.

Normative references: [TS 38.212 V18.8.0, 7.3.1.2.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf),
[TS 38.214 V18.7.0, 4.1, 5.1.2.1, 5.1.3 and 5.1.6.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.07.00_60/ts_138214v180700p.pdf).

Verification completed before the final candidate-export rerun:

- `logs/rar_sib1_semantics_20260907.log`, exit 0: decoded SIB1 authority,
  semantic comparison and SIB1-to-four-step-RA integration passed.
- `logs/rar_final_ul_main_regressions_20260907.log`: all 24 named checks
  before the main test passed, including config, DL/UL/reference points,
  proxy guards, grant/E2E/export integrity, PUCCH/SRS, data, QCL/TCI/PMI,
  SRS RI/TPMI and late/recovered UCI. Main then failed on the missing MIB
  capsule described above. This batch is retained as a failure, not a pass.
- After DMRS power, strict UL settings and MIB capsule corrections,
  `logs/rar_epre_main_ul_final_20260907.log`, exit 0: all 12 named focused
  checks plus four function-based DCI suites executed with `assertSuccess`
  passed. Includes actual main execution, delayed RA reception, PUCCH/SRS,
  coded DL/UL, recovered PUSCH UCI and export integrity.
- Python codec/reporting/contract set: 77 passed, with 181 third-party
  deprecation warnings. `testAll` was not run per the user's restriction.
  Existing FDD E2E fixtures are not a production FDD run or qualification.

The pre-candidate-export main run is retained at
`C:\Users\anup0\AppData\Local\Temp\main_shared_ra_20260907_134534`.
Its first-five-row review is
`results/lls/qualification_working/reviews/rar_main_first5_20260907_1350/`:
162 CSVs / 15,842 rows, zero parse failures or infinities, 56 empty files,
six structural/schema failures, 120 required semantic-check failures and
one chart-check failure. The strict value-review gate remains **FAIL**.
These are contract failures, including absent main data/campaign-finalizer
artifacts, not 120 independently diagnosed physical-layer defects.

Its post-run measured RSSI review is
`results/lls/qualification_working/reviews/rar_main_rssi_20260907_1350/`.
The eight observed SSB/receive-branch rows span -66.47 to -52.67 dBm and
close to their linear four-symbol powers within 1.43e-14 dB. The PNG was
visually inspected and source/output hashes retained. This is explicitly
20-PRB/four-symbol SSB-window RSSI, not full-carrier or SMTC RSSI, and not
runtime PNG publication (the boundary diagnostic uses SaveFigures=false).
All unobserved UL/CSI/PMI/EVM curves remain unavailable with reasons.

Final candidate-export verification:

- `logs/rar_candidate_evidence_final_20260907.log`, session 32759, exit 0:
  canonical Msg2 at actual AL2/4/8, the RA CSV/PNG artifact-schema and
  source-lineage test, and the actual main boundary all passed. The main
  test also asserts zero candidate/DCI rows for unexecuted Msg2.
- Final retained main:
  `C:\Users\anup0\AppData\Local\Temp\main_shared_ra_20260907_135354`.
  All 16 scheduling slots completed; four SSB/SIB1 candidates passed BCH,
  DCI and DL-SCH CRC. The actual PRACH metric remains 0.340461277865219
  against threshold 0.5. `RACompleted=0`, `StrictOk=0`, `ProxyUsed=0`,
  `Skipped=0`, failure `preamble_not_detected`; DL/UL data trial rows are zero.
- Final review:
  `results/lls/qualification_working/reviews/rar_candidate_final_first5_20260907/`.
  162 CSVs / 15,841 rows / 8,647 columns; zero parse failures or infinities,
  57 empty files and six structural failures. There are 121 required CSV
  semantic-check failures and one chart-check failure: the gate remains
  **FAIL**. Removing the fake candidate row correctly reduces the row count
  by one; the generic empty-table contract now flags its absence too. Do not
  reinstate that row to improve an audit score. Four `fallback` and three
  `placeholder` token matches are metric-catalog column-name descriptions,
  not evidence of executed fallback waveforms. Global legacy correctness
  still requires the remaining causal and physical checks above.
- Final measured plot review:
  `results/lls/qualification_working/reviews/rar_candidate_final_rssi_20260907/`.
  Eight measured RSSI rows and provenance were regenerated without modifying
  the run. Its PNG hash equals the visually inspected preceding review;
  values and exact measurement scope are unchanged. No main runtime PNG
  publication or absent UL/CSI curve is claimed.

Still required, in causal order:

1. Correct RAR monitoring-window start from the actual PRACH end and Type-1
   monitoring occasions; integrate expiry, continuous backoff, retries and
   UE knowledge of failure. Validating one planned Msg2 slot is not that
   receiver monitoring state machine. Multiple in-slot monitoring starts
   and reuse of SearchSpaceZero remain unsupported, explicitly rejected.
2. Replace the remaining private TC-RNTI Msg4 layout and TX-derived receiver
   assumptions; verify contention-resolution/HARQ feedback timing. Msg2's
   migration does not qualify Msg4 or full ASN.1 on-air RRC/SRB1 framing.
3. Finish chronological main PDCCH/PDSCH/PUSCH/PUCCH/UCI/SRS ownership and
   nonzero-TA TX-versus-RX origins; repair higher-numerology cumulative CP
   clocks and mixed-numerology PRACH grid coordinates. Component delayed
   receivers do not establish these main-scheduler invariants.
4. Close physical PRACH detection/access without lowering thresholds to
   force a pass. Establish a declared reference-SNR calibration separately
   from geometry/thermal-noise mode; the current 12 dB label is not measured
   instantaneous SINR or a controlling noise reference.
5. Then qualify actual UL CRC/LA/rank/TPMI, late UCI transport, activated
   QCL/TCI and CSI RI/PMI/CQI use, power/PHR, SS/CSI/RSSI measurements and
   runtime CSV/PNG publication on the same main run. Planned power fields
   for unexecuted RA stages and remaining missing schemas still need repair.

## Decoded common-control and UL BWP authority (previous checkpoint, 2026-09-07)

**Not a qualified production LLS.** This checkpoint fixes the SIB1/UE
configuration boundary; it does not close the remaining scheduler, retry,
TA, UL/UCI or full-main beam/measurement integration below.

Concrete repairs:

- `installDecodedSIB1RACHConfig` now decodes `locationAndBandwidth` as a
  type-1 RIV with reference width 275. A 25-RB BWP has encoded RIV 6600;
  it is not a 6600-RB allocation. Shifted intervals and both RIV branches
  survive actual UPER encoding and UE installation.
- The installed UL BWP uses its own decoded SCS, not PRACH SCS. The current
  profile has 15-kHz data-carrier spacing and 30-kHz B4 PRACH spacing.
  Decoded DL/UL BWP RIVs, SCS and CP are preserved independently rather than
  reconstructed from carrier bandwidth. These are codec/installation tests,
  not qualification of every shifted-BWP waveform consumer.
- The SIB1 builder no longer invents MIB-only `pdcch-ConfigSIB1` or DMRS
  type-A position, or unencoded common PDSCH/PUSCH/PUCCH defaults. Absent
  common-channel configuration stays absent at the UE. Unsupported IEs
  are rejected instead of discarded and reported as a complete decode.
- Explicit `initial_access.sib1.pdcch_config_common` (or internal
  `rrc.sib1.pdcch_config_common`) now traverses the real generated UPER
  codec. The bounded implementation preserves common CORESET resources,
  CCE/REG mapping, common search-space periodicity/offset/symbol bitmap,
  candidates and RA search-space identity. Its UE installation/evidence
  is distinct from qualification of actual RAR monitoring.
- A whole-message semantic reconstruction guard rejects unrepresented
  fields, including an otherwise silently replaced UL carrier definition.
- The independent vector generator had a real non-octet BIT STRING bug:
  metadata cell identity 17 encoded as 1. It now left-aligns significant
  bits, asserts decoded meaning, and regenerates vectors using asn1tools
  from the hash-pinned official `38331-i90.zip`. The ZIP contains a DOCX;
  the script now reproducibly extracts tagged ASN.1 text with tabs preserved
  and inlines the standard SetupRelease CHOICE. Source/expanded hashes are
  updated to those reproducible representations. The independent mapper
  does not import the production common-control mapper. Seven positive
  vectors (including noninterleaved/interleaved common control) and three
  negative vectors are retained.

Normative references: [TS 38.331 V18.9.0, BWP and PDCCH-ConfigCommon IEs](https://www.etsi.org/deliver/etsi_ts/138300_138399/138331/18.09.00_60/ts_138331v180900p.pdf),
[TS 38.213 V18.6.0, 8.2 and 10.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.06.00_60/ts_138213v180600p.pdf),
[official source archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-i90.zip).

Verification:

- `logs/sib1_common_authority_20260907.log`, session 18395, exit 0:
  new decoded-authority test, ASN.1 round-trip, then-current independent
  byte vectors, validation comparison and SIB1-to-four-step-RA integration.
- `logs/sib1_common_main_regressions_20260907.log`, session 5835, exit 0:
  all 23 named focused checks passed. Includes config, no-proxy guards,
  DL/UL/reference points, grant consistency, both required E2E regressions,
  export integrity, staged SRS/PUCCH/PDSCH/PUSCH, QCL/activated-TCI, PMI,
  SRS rank/TPMI and late-UCI authority. Its main run is
  `C:\Users\anup0\AppData\Local\Temp\main_shared_ra_20260907_123351`.
- After the final semantic-loss guard and independent-vector repair,
  `logs/sib1_final_semantic_uplink_20260907.log`, session 23287, exit 0:
  regenerated independent tests and all eight named checks passed,
  including no-oracle SIB1 waveform recovery, delayed Msg3/SRB1 bit/CRC
  recovery, actual detected-preamble-to-RAR binding, all five received-buffer
  TDD RA stages and the actual main boundary again.
- Final Python codec/reporting/contract set: 77 passed (session 47394,
  exit 0). There are 181 third-party asn1tools/pyparsing deprecation warnings;
  they are not failed PHY assertions. `testAll` was not run, per the user's
  explicit restriction. Existing FDD unit/E2E fixtures are not production
  FDD execution or full-FDD qualification.

Latest retained main run:
`C:\Users\anup0\AppData\Local\Temp\main_shared_ra_20260907_124424`.
All 16 scheduling slots completed with four successful SSB/SIB1 candidate
observations and a real failed PRACH. Detection remains 0.340461277865219,
below the unchanged 0.5 threshold; access is not complete and DL/UL data
tables have zero rows. No new main-run PUSCH/PUCCH/SRS or CSI/PMI success
is inferred from isolated component tests.

The strict first-five-row audit is saved under
`results/lls/qualification_working/reviews/sib1_common_first5_20260907_1247/`.
It covers 161 CSVs / 15,842 rows: zero parse failures or infinities, 55
empty/header-only files, six structural/schema-less files, 119 failed
required CSV semantic checks and one failed chart check. The gate remains
**FAIL**. These counts include absent data and missing campaign-finalizer
contracts in the direct boundary diagnostic, not 119 distinct PHY bugs.

A separate post-run measured review is under
`results/lls/qualification_working/reviews/sib1_common_rssi_20260907_1247/`.
The actual eight-branch SSB-window RSSI CSV/PNG was regenerated, source/output
hashes saved and PNG visually inspected. Values close to
`10*log10(1000*mean(symbol_powers_w))` within 1e-12 dB. Its measurement scope
is 240 subcarriers / four SSB symbols, **not full-carrier or SMTC RSSI**.
The diagnostic has SaveFigures=false; this is a post-run review, not a
claim of runtime PNG publishing. Other requested curves stay unavailable
with explicit reasons because their measured sources are absent.

Additional open defects found at this boundary:

1. Main YAML still needs actual common-control configuration, and Msg2
   generation/reception must consume the decoded CORESET/search-space
   rather than the current AL4/candidate/localized-resource constants.
   The new codec capability alone does not repair those consumers.
2. `scheduleMsg2RAR` still builds a private 32-bit allocation layout, not
   the normative RA-RNTI DCI 1_0 field layout. Repair TX, blind RX and
   decoded allocation authority together; do not merely change the label.
3. RAR response-window start must use the first valid Type-1 monitoring
   occasion after the PRACH sample extent, including the symbol gap.
   `RAEventScheduler` and `RATimingService` still use PRACH end slot + 1.
   Backoff currently starts from response-window start rather than expiry.
   Main retry counters and delayed UE failure knowledge remain unintegrated.
4. RA result rows contain planned Msg3/Msg2/Msg4 power values even when those
   stages were never transmitted. They need explicit planned-versus-applied
   roles; finite planned powers are not measurements of executed stages.

Next sequence: actual common-control/DCI consumer integration and causal
MAC timers/retries; shared main UL/control/data ownership and nonzero TA;
then full-main QCL/TCI/PMI, power/PHR/RSSI and output qualification. Preserve
all remaining issues in the following checklist rather than claiming 10/10.

## Shared Msg1 integration and uplink timing (previous checkpoint, 2026-09-07)

**Still not a qualified production run.** The former slot-15 eager-channel
failure has been crossed: the actual main scheduler now transmits and
receives Msg1 through its retained physical stream. Access still fails on
the first measured PRACH, and there are zero DL/UL data trials. The older
checkpoint below describes the previous boundary, not the current status.

Implemented in this work:

- Main RA stage preparation now queues actual power-scaled physical-antenna
  samples. Completion receives contiguous TX/pre-RX-RF/post-RX-RF observations
  from the same physical owner. It does not execute a second channel or
  inject received-tail padding. Actual analogue AGC compensation is applied
  digitally after ADC, without removing noise or quantization errors.
- Completed RA-stage evidence is published immediately, including at the
  last simulated slot; it no longer depends on another scheduler iteration.
  A window extending beyond the run remains incomplete, not fabricated.
- Configured raw-IQ capture now saves the real RA planes and execution
  segments even though the internal runner disables per-link `saveMAT`.
  These are diagnostic stage captures, **not** continuous Keysight playback.
- PRACH waveform origin is its own nominal PRACH-slot origin, including
  the modulator's internal offsets only once. Here PRACH slot 29 begins at
  14.5 ms, not carrier-slot 14's 14.0 ms. Its active CP/useful samples touch
  carrier symbols 7–12. PRACH-grid symbol numbers are not carrier symbols.
  Mapping uses actual CP/useful/guard sample lengths and cumulative carrier
  CP lengths, including unequal adjacent-slot lengths at higher numerologies.
- The selected occasion now carries distinct PRACH-clock RA-RNTI coordinates.
  This case uses `s_id=0`, `t_id=9`, RA-RNTI 127, not the data-carrier slot 4.
  The TDD YAML's explicit carrier-coordinate selector is corrected to symbol
  7. This is not a duplex-specific arithmetic branch or an altered threshold.
- PRACH detector correlation peaks are preserved exactly. A decoded cyclic
  shift wins a root-metric tie via its decoded identity, not a fabricated
  epsilon added to a measured peak. The gNB RAR uses the actual detected
  preamble, not the UE's intended transmitted preamble as an oracle.
- Shared Msg3 and SRB1 receivers no longer skip measured timing acquisition
  or treat an untrimmed waveform as already aligned. Measured arrival is
  applied once; modeled path/filter delays are not subtracted as though
  already removed. PRACH TA separately calibrates only the known implementation
  filter delay, while retaining raw arrival and calibrated delay separately.
- `DELTA_PREAMBLE` now comes from executed format and PRACH SCS under
  TS 38.321 7.3. B4/30 kHz requires 3 dB, not the old default zero. Conflicting
  legacy offsets are rejected rather than overriding the normative value.
- RA rows now retain actual RF stage counts/status, physical projection
  digest, applied loss, thermal-noise PSD/bandwidth and gain-compensation
  evidence. Only invariant segment metadata is flattened into a scalar.

Sources: [PRACH OFDM sample contract](https://www.mathworks.com/help/5g/ref/nrprachofdmmodulate.html),
[PRACH grid indices](https://www.mathworks.com/help/5g/ref/nrprachindices.html),
[TS 38.321, 5.1.3/5.1.4 and 7.3](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.02.00_60/ts_138321v180200p.pdf).

Verification so far:

- `logs/shared_ul_timing_main_r2_20260907.log`, session 51967, exit 0:
  delayed real Msg3/SRB1 LDPC payload/CRC and PRACH timing calibration;
  actual alternate-preamble-to-RAR test; all five received-buffer TDD RA
  stages; runtime repetition/occasion binding; actual 16-slot main boundary.
  The PRACH correlation estimator measured 19.0286 samples for an injected
  19-sample FIR delay; calibration subtracts exactly 11 implementation
  samples, not a guessed propagation delay. Timing accuracy is checked to
  one input sample, not asserted to be an exact-delay oracle.
- Main output before the format-power correction:
  `C:\Users\anup0\AppData\Local\Temp\main_shared_ra_20260907_113542`.
  All four actual PBCH/SIB1 candidates and one actual failed Msg1 are retained.
  The main boundary test explicitly does not treat this as an access/data pass.
- 65 focused Python radio-measurement/artifact/runtime-contract tests passed.
- Format-power, all 1,031 PRACH configuration-row sample-mapping checks and
  a fresh main run passed in `logs/prach_power_main_verified_20260907.log`
  (session 33938, exit 0). This is boundary/test success, not access success.
  The retained run is
  `C:\Users\anup0\AppData\Local\Temp\main_shared_ra_20260907_114238`.
  Actual Msg1 TX power is -11.9539043881 dBm, target -93 dBm,
  measured-reference pathloss 81.0460956119 dB; requested power closes on
  target plus measured pathloss and is below PCMAX 23 dBm. Actual received
  detection metric is 0.3404612779 against the unchanged threshold 0.5.
  The decoded-index field remains unavailable and access is honestly failed.
  Earlier intermediate failures are retained: two obsolete PRACH-grid test
  assumptions, a higher-numerology test clock origin, and a stale fixture
  missing the required absolute RA coordinates. Assertions now compare
  actual generated support; production validation was not weakened.
- `logs/shared_ul_spatial_regressions_20260907.log`, session 28463, exit 0:
  `testUplinkControlStreamStages`, `testDataChannelStreamStages`,
  `testPDSCHQCLStatePropagation`, `testPDSCHTCIStateBinding`,
  `testPMIPrecodingRuntime`, `testLLSULSRSRITPMIEstimator`,
  `testFutureULPlanningCausality`, `testGrantCacheLiveUCIAuthority`, and
  `testRecoveredPUSCHUCIEvidence` all completed. These verify actual coded
  isolated DL/UL reception, SRS/PUCCH received-buffer processing, exact UCI,
  precoding, and scheduling causality; they do not qualify main access.
  Offline diagnosis of the actual retained Msg1 confirms that TX samples
  detect, while pre-RF and digitally gain-compensated received planes both
  give the same failed metric (0.340461). ADC/AGC is not hiding this failure.
- Real eight-branch SSB-window RSSI CSV/PNG were rendered from this run to
  `results/lls/qualification_working/reviews/shared_ra_rssi_20260907_1150/`.
  `provenance.json` records source/output SHA256 and absent-chart reasons.
  The PNG was visually inspected. These are **post-run measured reviews**,
  not new PHY execution or full-carrier RSSI. The diagnostic itself explicitly
  disables figure generation. No data/CSI/precoder curves were invented.
- Exhaustive audit of the same run, including the first **five** rows of
  each CSV, is under
  `results/lls/qualification_working/reviews/shared_ra_first5_audit_20260907_1200/`.
  It parsed 161 CSV files / 15,842 rows with zero parse failures or infinity
  tokens. Qualification fails: 55 zero-row files, six schema-less exports,
  and 119 failed semantic checks plus missing campaign chart lineage.
  These are not 119 distinct PHY bugs: many require completed data trials
  and the campaign finalizer/identity wrapper omitted by this direct main
  boundary diagnostic. The failures remain recorded, not waived.
  Six concrete schema-less exports are `multiuser_user_summary`, PDCCH
  (air-interface and control mirrors), CSI-RS, SRS, and live LA inputs.
- All ten focused cases in `logs/shared_ra_config_truth_regressions_20260907.log`
  passed (session 73884, exit 0): PRACH power, canonical RA-RNTI,
  `testConfig`, `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`,
  `testStrictProxyGuards`, `testSchedulerGrantConsistency`,
  `testE2E_FastVsTruth`, and `testE2E_TruthPacketSemanticCampaign`.
  Some existing regression fixtures use FDD; these are not a production FDD
  run or qualification of the current main shared-stream integration.
  The explicit user restriction against `testAll` is retained.
- Recomputed the persisted per-branch linear-power ratios for all four SSB
  candidates: maximum SS-SINR arithmetic discrepancy is 3.56e-14 dB; all
  eight RSSI values close exactly on the saved per-symbol watt measurements
  at displayed precision. Beam 0 has the greatest SS-RSRP (-75.8173 dBm),
  matching the actual PRACH association. Its SS-SINR is 49.0833 dB, so this
  is clearly **not** a measured 12-dB reference-SNR experiment. Arithmetic
  closure does not qualify the missing full-run measurement/timing paths.

Remaining critical issues (do not omit from qualification):

1. Main RA retries still restart with attempt 1: MAC response-window expiry,
   retained transmission/power-ramping counters, beam-change rules and
   decoded backoff must be integrated causally. gNB missed detection is not
   an immediate UE-known random-access failure.
2. Main nonzero TA still has an explicit guard: true separate UE TX/gNB RX
   origins are required. The legacy cropped/zero-filled finite-waveform TA
   routine must not be used to claim continuous-stream correctness.
3. Main data PDCCH/PDSCH/PUSCH, PUCCH/UCI and SRS still need complete shared
   owner integration. Their component successes do not prove the current
   main run, which has no completed data grants. Preserve chronological
   received DCI, K1/K2, late ACK multiplexing, HARQ, CSI/SRS and frozen precoders.
4. `buildObservedREAllocation` still treats PRACH-grid coordinates like
   carrier RE coordinates. Mixed-numerology PRACH frequency/time export and
   WebGUI overlay need an explicitly scoped conversion; a filled carrier
   rectangle must not be labeled exact orthogonal PRACH REs.
5. The main scheduler still assumes equal slot durations in its absolute
   sample-boundary helper. The PRACH mapper now handles cumulative CP lengths,
   but that repair is not yet propagated to all higher-numerology producers.
6. Full-main QCL/activated-TCI/PMI consumption, per-channel UL power/PHR,
   correct CSI/SS measurement resources and all requested CSV/PNG remain
   unqualified. SSB-window RSSI is not full-carrier/SMTC RSSI.
7. The profile's nominal 12 dB remains a label under geometry plus thermal
   noise. It is not a controlled/measured 12 dB reference-SNR experiment.
8. Bounded Msg3/SRB1 message builders use custom payload framing; this is not
   evidence of full on-air ASN.1 RRC/MAC protocol conformance. Preserve the
   distinction between real NR-coded PHY payloads and protocol conformance.

## Main physical owner, receiver gain and SS power repair (previous checkpoint)

**Not a completed/qualified production run. The actual main scheduler reaches
slot 15, then rejects its unmigrated eager RA channel acquisition. It retains
zero DL/UL data trial rows; these are not filled with stand-ins.**

The main scheduler now owns one retained sample stream for the prepared
SSB/SIB1 and TRS transmissions. RF/channel/noise execute chronologically at
actual OFDM symbol boundaries, including TDD guard intervals. Completed
received buffers, not precomputed decoder results, reach the receiver reducer.
The initial main-clock error is not declared fully repaired while RA and the
data/control producers still require migration.

Changes and evidence:

- Real retained SIB1 IQ decoded before RX RF but failed after AGC/ADC. The
  applied gain changed within OFDM symbols. Digital compensation now uses
  the actual recorded per-sample analogue gain **after the ADC**. It does
  not remove noise, replay fading/RF, or undo clipping/quantization. The
  previously failing retained IQ decodes after this receiver repair.
- Main execution publishes all four measured PBCH/SIB1 candidates at delivery
  slot 6 and completes the multi-slot TRS window at delivery slot 9. The
  first ten-slot test's missing PRACH was not proof of a multi-frame bug:
  this profile uses period 10, occasion 5, so acquisition at slot 6 must
  wait until slot 15. The main boundary test was extended accordingly.
- Independently, generic PRACH gating did use a radio-frame modulo instead
  of the resolved repetition period, and its canonical-engine path had a
  one-based/zero-based mismatch. Both are repaired. A real FR1 unpaired
  configuration-0 fixture resolves period 160 / one-based occasion 20;
  two periods now agree with the canonical engine. The authored profile
  remains unchanged at configuration 157 / period 10 / occasion 5.
- The SS power audit found a genuine estimator mismatch: squared coherent
  reference averaging was being treated as linear per-RE power, then a full
  per-RE noise variance was subtracted. SS-RSRP now uses linear SSS RE power;
  disturbance is estimated per RX branch from the received SSS reference
  REs using `nrChannelEstimate`. An unconfigured null-RE window is no longer
  substituted for the SS-SINR measurement resources. This is a practical
  receiver estimator, **not proof of UE measurement-accuracy conformance**.
- A phase-selective fixture proves phase rotation cannot erase measured
  per-RE SSS power. Common amplitude scaling preserves SINR and shifts dBm
  correctly. Poisoning non-SSS REs leaves this reference-scoped estimate
  unchanged. The previous source-string assertion was changed to the new
  actual estimator, not weakened to accept arbitrary sources.
- SSB-window RSSI now retains each receive branch, all four symbol powers,
  exact 240-subcarrier/20-PRB bandwidth, units and source in the PBCH CSV.
  Its specialized chart is wired into the normal CSV/PNG materializer.
  Linear symbol-power/dBm closure, branches, scope and duplicates are
  validated. It is deliberately **not** labeled a full SMTC/carrier-RSSI
  report. No new scenario-specific policy or synthetic plot points were added.
- The final SSB/RA artifact regression exposed a separate RA producer defect:
  applying the received RAR power command copied planned power state over
  completed Msg1/Msg2 amplitude evidence, resetting their actual scales to
  NaN; the CSV writer subsequently pruned those empty columns. Applied
  transmission scales have now been removed from the *planned* power state
  (they remain in the actual transmitter/result records). A staged RA
  regression requires each scale to survive all later received stages.
  This repairs provenance, not PHY power by substituting a display value.

Definitions used: [TS 38.215 V18.2.0, 5.1.1/5.1.3/5.1.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138215/18.02.00_60/ts_138215v180200p.pdf)
and [MathWorks SSB measurement API](https://www.mathworks.com/help/5g/ref/nrssbmeasurements.html).
The latter's coherent RSRP estimator is retained only as explicitly scoped
reference evidence inside the RSSI measurement record; it is not the repaired
primary SS-RSRP value.

Bounded verification:

- `logs/coupled_waveform_stream_gain_fixed_20260907.log`: session 66891 exited
  0; applied-gain compensation, actual SSB/SIB1/TRS stream, and the retained
  physical-owner CDL/RF/noise clock and tail-safe reciprocal reversal passed.
- `logs/main_shared_access_boundary_r4_20260907.log`: session 75064 exited 0.
  PRACH period/index guards; main SSB/TRS-to-unmigrated-RA boundary; staged
  SRS/PUCCH; PUCCH formats 1–4 after retained AGC/ADC; actual HARQ-ACK on
  PUSCH; five received-buffer RA stages; TDD CDL-A RA with decoded TA=0,
  Msg3 CRC and no duplicate timing correction; QCL, activated TCI, and
  SRS RI/TPMI estimator checks completed. These component checks do not
  qualify the combined main scheduler.
- `logs/main_shared_access_boundary_r3_20260907.log` failed before any UL
  tests: its new multi-frame test initially selected a single-frame fixture.
  This test-input error was corrected using the actual multi-frame table.
- `logs/shared_stream_rssi_regressions_20260907.log`: session 46202 was
  deliberately stopped after discovery of the SS estimator defect. Its
  initial RSSI/AGC/physical-owner checks passed, but it is not a full batch pass.
- `logs/sss_linear_measurement_20260907.log`: session 74129 exited 0 after
  the repaired SSS/RSSI, actual composed stream and main boundary tests;
  `testConfig`, strict proxy/fallback guards, `testLLS_DL`, `testLLS_UL`,
  `testLLS_ReferencePoints`, grant consistency, both required E2E truth/packet
  regressions, link export, artifact integrity and E2E artifact preservation.
  Existing E2E FDD fixtures are not production-run qualification evidence.
- 53 Python radio-measurement chart tests and 32 output-contract/running
  materialization tests passed (85 total). An integration check on
  the actual latest main diagnostic PBCH CSV produced eight branch records
  and valid PNG bytes (57,644 bytes), not simulated plot points. The existing
  materializer persisted `reports/diagnostics/ssb_window_rssi_received.csv`
  and `.png` under that diagnostic folder; the PNG was visually inspected.
  It shows the actual eight SSB/RX-branch observations at burst source slot
  1, without a fitted line or invented time samples. This is not a complete
  production-run plot set. All eight exported SS-SINR ratios
  closed on their recorded desired/disturbance powers within 4.27e-14 dB.
- `logs/ssb_artifact_measurement_regression_20260907.log` failed at the
  missing Msg1 amplitude column, after the acquisition/beam checks.
  `logs/ra_power_evidence_regression_20260907.log` exited 0 (session 96191)
  after staged TDD RA and the same complete SSB/RA artifact regression.
  Final review also removed the coherent RSRP initialization from the primary
  measurement reducer's failure path; unavailable received-reference power
  must remain unavailable, not be labeled `available_rsrp`.
- `logs/ss_power_availability_final_20260907.log` exited 0 (session 54624):
  linear SS power (including silent-observation rejection), SSB-window RSSI,
  the complete SSB/RA artifact regression and strict proxy/fallback guards
  passed after the final measurement-availability change. No `testAll` or
  new production FDD/25 dB run was launched.

The latest main diagnostic source is
`C:/Users/anup0/AppData/Local/Temp/main_shared_access_20260907_102144`.
Its four SS-RSRP values (SSB indices 1,2,3,0) are approximately
-80.696, -89.059, -77.265, -75.817 dBm. Their SS-SINRs are approximately
44.523, 36.541, 48.227, 49.083 dB. **The YAML's 12 dB label is not a measured
12 dB condition in geometry/thermal-noise mode.** Arithmetic consistency
does not establish interference completeness, measurement accuracy, or
end-to-end qualification.

### Remaining work: none of the requested areas is silently waived

| Area | Current evidence / remaining repair |
| --- | --- |
| Main shared clock/stream | SSB/SIB1 and TRS use the owner; RA, PDCCH, data, PUCCH and SRS still need main-queue migration. Legacy acquisition is rejected, not bypassed. |
| Capture duration / run horizon | Check the five-subframe broadcast receive extent against the actual last required SIB1 sample and timing uncertainty. With first usable PRACH at slot 15, the 25-slot scenario may leave insufficient post-access data time. Prove the timeline before extending the horizon; do not hide an avoidable receive delay by simply lengthening the run. |
| PRACH / Msg1–4 / RRC | Canonical PRACH timing fixed; actual standalone staged RA passed. Prepare and queue every main RA stage, attach received execution/noise evidence, and reduce only at actual RX completion. |
| UL timing advance | Decoded TA=0 tested. Nonzero TA still needs distinct UE TX / gNB RX sample origins instead of finite-buffer cropping/zero filling. |
| PUCCH / UCI | Formats 1–4 received-DM-RS tests passed. Format 0 still needs valid received disturbance evidence; main UCI timing/delivery and collision resolution remain open. |
| PUSCH / HARQ / adaptation | Component UCI-on-PUSCH passes; queued grants must consume late-created ACKs and actual decoded DCI at the right boundary. No new main PUSCH rows exist yet. |
| SRS / UL PMI-rank | Staged reception and RI/TPMI component checks passed. Main preparation, receive completion and delayed scheduler consumption still required; independently qualified true-channel NMSE is not replaced by pilot residual. |
| CSI feedback / power | Main CSI delivery and consumed precoder identity remain unverified. CSI power callers still use `nrCSIRSMeasurements` coherent resource averaging; audit phase-selective/CDM/port-specific behavior before claiming CSI-RSRP correct. |
| QCL / TCI / beamforming | Component propagation and activated-TCI binding pass. Main activation timing, source-RS identity, actual applied beam/PMI matrices and their CSV/PNG lineage still need joined validation. |
| RSSI | Actual SSB-window RSSI is implemented; CSI-window charts already exist. Full configured carrier/SMTC RSSI and separately defined UL measurement windows are not supplied by these narrower captures. |
| Multiple UEs / channel ownership | Resolve per-UE TRS state vs old per-cell delivery, initial-UL TDD binding, TX projection before direction switches, dynamic loss/mobility updates, interference cross-links and sweep-epoch ownership. |
| Output / instrument capture | Fresh complete TDD CSV/PNG inventory, RE-collision audit and continuous post-IFFT TX IQ/playback are pending. No qualified Keysight capture is claimed. |

Next order: migrate main RA with absolute TX/RX timing and actual execution
evidence; migrate main control/data/SRS/PUCCH and timed feedback; close the
CSI/beam/RSSI measurement domains; run the short TDD scenario and inspect its
real tables/images; only then prepare continuous IQ for the named instruments.
No production FDD/25 dB run or `testAll` was launched at this checkpoint.

## Actual PDCCH receive boundary and legacy grant shortcuts (earlier checkpoint)

**The main chronological shared-stream scheduler is still incomplete. No new
production 12 dB TDD run, FDD run, 25 dB run or instrument capture is qualified
by this checkpoint.** These changes close specific control-path defects and
separate its receive reducer; they do not claim the remaining scheduler
migration has happened.

- PDCCH preparation derives its receive extent from the actual monitored
  PDCCH/DM-RS REs and OFDM symbol/CP lengths, across numerologies and slot
  positions. A fractional declared sample origin is rejected, not rounded.
- PDCCH RX no longer pads unreceived time samples or OFDM symbols to a whole
  slot. A short capture must cover all monitored symbols after timing
  alignment. Missing timing prehistory, incomplete independent noise samples
  and requested timing-estimation failures are explicit errors.
- The first test failed because the index/symbol `nrChannelEstimate` API
  requires a whole slot. The documented **reference-grid** signature now
  estimates the actual received prefix. Reference-grid zeros denote
  non-pilot REs; no received waveform/grid padding or scalar fading-channel
  estimate is introduced. See
  [nrChannelEstimate](https://www.mathworks.com/help/5g/ref/nrchannelestimate.html).
- The main collector has a separate `localCompletePDCCHTrial` reducer,
  consuming retained TX metadata and an actual completed observation. It
  does not execute a transmitter, channel or RF chain. Its caller still
  invokes physical execution eagerly; event-driven main integration remains
  required.
- A pre-attached access state no longer substitutes for actual DCI reception
  in the DL/UL grant qualifier. Invalid UE bindings and missing scheduled
  DCI payloads fail explicitly; no generic 64-bit DCI replaces a grant.
- Removed the independent noise-only RF pass from the primary PDCCH path.
  Primary false-grant evidence comes from the actual received candidate set;
  `NoiseFalseAlarmFlag` remains unavailable, not a fabricated zero. Dedicated
  no-signal false-alarm campaigns remain separate tests. Missing noise/sample
  rate authority no longer falls back to generic AWGN or 30.72 MHz.
- The row producer retains actual observation start/end/completion time,
  minimum receive samples, demodulated symbols and receive-padding status.
  Preparation alone does not publish an observed RE allocation. These are
  producer changes, not a claim that fresh production CSVs already exist.

Validation so far: the failed initial batch **64658** is retained in
`logs/pdcch_actual_receive_boundary_20260907.log`; the repaired boundary batch
**94426** exited 0 (`logs/pdcch_actual_receive_boundary_r2_20260907.log`),
covering 15/30/60 kHz and multiple slot/start-symbol positions, incomplete
capture rejection, exact shared PDCCH allocation, and an early actual DCI
decode from the noisy CDL SSB/TRS/PDCCH stream. The full transmit waveform
continues through the stream after that early receiver event. Whole/chunk
sample equality and the unchanged receive-completion channel clock passed.

The allocator's built-in FDD component fixture is not a production FDD run.
Only bounded tests are used, respecting the request not to run `testAll`.
The main-caller structural regression is explicitly labeled structural, not
end-to-end scheduler execution evidence. CSI-RSSI/RSRQ plot validation was
rerun: **41 Python tests passed**.

Batch **63769** exited 0
(`logs/pdcch_runtime_causal_boundary_final_20260907.log`): main-caller
structural guards, PDCCH preparation/reception, receive-decision boundary,
shared allocation, actual DCI/grant gate, control-slot authority, scheduled
PDSCH transmit authority, first-SRS-before-UL-DCI ordering, staged SRS/PUCCH,
received-DM-RS PUCCH formats 1–4 after retained AGC/ADC, actual HARQ-ACK on
PUSCH, and the early PDCCH/SSB/TRS noisy CDL stream passed.

Batch **74159** exited 0 (`logs/pdcch_functiontests_execution_20260907.log`):
`runtests` actually executed both function-based PDCCH no-signal false-alarm
and CFO/timing cases, followed by `assertSuccess`. Merely calling their
test-factory functions is not counted as execution.

Final regression batch **40367** exited 0
(`logs/pdcch_ul_truth_regressions_20260907.log`): five-stage received RA
coverage/origin/tail guards; actual TDD CDL-A RA and decoded TA=0/Msg3 CRC;
QCL propagation; activated TCI binding; SRS RI/TPMI and applied PUSCH
precoder-domain checks; `testConfig`; strict proxy/fallback guards;
`testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`;
`testSchedulerGrantConsistency`; `testE2E_FastVsTruth`; and
`testE2E_TruthPacketSemanticCampaign`. The E2E regressions used their own FDD
fixtures. Neither those fixtures nor the source-structure guard qualify the
unfinished main chronological scheduler. All MATLAB validation processes
finished before this checkpoint was committed; previous run outputs were
not deleted.

The remaining-area table below still applies. Specifically: integrate all
prepared access/control/data contributors with the physical event owner;
handle nonzero UL TA and format-0 disturbance evidence; commit HARQ/CSI/SRS
at actual RX completion; verify QCL/TCI/PMI activation and consumed precoder
identity; define SS/UL RSSI observation windows separately; then run and
inspect fresh TDD CSVs/PNGs before continuous instrument IQ/playback work.

## UL received-reference noise boundary (subsequent checkpoint)

The preceding absolute-noise/retained physical-owner changes are committed
as `f48509fb`. The main shared-stream migration remains **open**.

The SRS/PUCCH staged receiver interface previously required a finite scalar
post-front-end sample noise variance even when retained AGC/ADC could not
provide that scalar honestly. It now accepts the explicit physical-owner
state `unavailable_requires_received_reference_estimation`, with no
numerical substitute:

- SRS uses its actual received-reference `nrChannelEstimate` variance in
  resource-grid units. Its independent NMSE/true-channel qualification gate
  is unchanged; absence of that reference is still not a qualification pass.
- PUCCH formats 1–4 can explicitly estimate disturbance from their actual
  received DM-RS, including when the propagation model is AWGN but the
  composite receiver RF/channel gain is not unity. This requires per-resource
  channel estimates and a usable received variance; there is no supplied
  scalar rescue when estimation fails.
- PUCCH format 0 has no DM-RS. It still rejects unknown post-RF variance
  until independent, correctly scoped received disturbance evidence is wired.
  A scalar full-grid channel, configured SNR or zero variance is not inserted.
- A measured pilot residual cannot be added to a separately supplied
  interference covariance again. Explicit covariance mode retains its
  provided thermal variance; received-DM-RS estimation mode rejects a second
  disturbance authority.

This uses the practical estimator documented by
[nrChannelEstimate](https://www.mathworks.com/help/5g/ref/nrchannelestimate.html)
and feeds the receiver-domain variance required by
[nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html).
The residual is a receiver disturbance estimate, not an exact decomposition
of thermal noise, interference, RF distortion and estimation error.

An additional staged **multi-antenna format-2** test exposed a real legacy
AWGN shortcut: direct resource extraction passed an N_RE-by-N_RX matrix
to `nrPUCCHDecode`, which requires one combined column for formats 2–4.
Batch **56234** failed with `Expected SYM to be a column vector`; it is not
counted as a pass. AWGN propagation also does not imply unity transmit
power or receiver gain. Formats 1–4 now use their actual per-resource DM-RS
channel estimates and MMSE antenna combining on AWGN as well as fading.
Format 0 retains its reference-free noncoherent receiver. The old test that
required bypassed DM-RS processing for format 2 now requires actual DM-RS
processing, with its CRC/payload assertions unchanged. No antenna was
dropped and no channel estimate was synthesized to satisfy the interface.

PUCCH primary `NoiseVariance` / `NoiseVarSource` / `NoiseVarianceDomain`
now describe the resource-grid variance actually consumed by the receiver;
`ReceiverInputSampleNoiseVariance` and its domain remain separate (NaN
when unknown). The canonical PUCCH row writer and SRS row writer retain
those measurement-domain distinctions. These are new measured metadata,
not finite replacements for unavailable physical inputs.

Batch **29662**, exit 0 (`logs/ul_received_noise_estimation_20260907.log`):
actual PUCCH formats 1–4 UCI decoded after retained causal AGC/ADC using
received DM-RS variance; SRS and PUCCH staged contracts passed. These tests
use explicitly labeled isolated connector/control fixtures, not main-run
access decisions or a completed production TDD slot calendar.

Batch **28240**, exit 0 (`logs/ul_received_noise_regressions_20260907.log`):
40-case `testPUCCHPhase05`, PUCCH feedback, UL noise validation, absolute
thermal noise, shared physical owner, HARQ-on-PUSCH, coded data stages and
CSI-RS physical measurements passed. The multi-antenna AWGN defect found
after this batch is recorded above; those earlier passes alone did not
close the newly exposed defect.

Final batch **8404**, exit 0
(`logs/ul_receiver_dmrs_combining_final_20260907.log`), after that repair:

- `testUplinkControlStreamStages` (SRS, format-0 PUCCH, and the added
  multi-antenna DM-RS PUCCH case) and `testPUCCHReceivedNoiseEstimation`;
- `testLLSPUCCHWaveformFeedback` and all 40 `testPUCCHPhase05` cases;
- `testConfig`, `testStrictProxyGuards`, `testStrictMode_NoFallbackAnywhere`,
  `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`,
  `testSchedulerGrantConsistency`, `testE2E_FastVsTruth`, and
  `testE2E_TruthPacketSemanticCampaign`.

The integrity regressions exercised their built-in FDD fixtures. No new
production FDD or TDD scenario was launched. This was bounded validation,
not `testAll`, a 12 dB production qualification, or proof that every open
integration item is implemented.

The existing CSI-RS physical RSSI/RSRQ calculation and plot code was also
inspected. It retains the measured resource, receive branch, bandwidth and
symbol window; the displayed RSRP/RSSI/RSRQ use the same branch. The plotting
pipeline verifies `RSRQ_dB = 10*log10(N_RB) + RSRP_dBm - RSSI_dBm` and rejects
duplicate or incomplete resource identities. Python validation:
`python -m pytest -q tests/test_lls_radio_measurement_plots.py`, **41 passed**.
This does not certify new production PNGs: no new production run was started,
and the unfinished combined runtime must first produce those measurements.
SS-RSSI and UL-specific received-power windows still need their own explicit
definitions; the CSI-RS metric cannot be relabeled as either one.

### Remaining combined-runtime acceptance work

| Requested area | Evidence now | Still required before qualification |
| --- | --- | --- |
| Main clock / shared stream | Retained node RF, per-link fading, receiver noise and DL/UL tail-safe direction switch tested | Replace eager access/control/data executions with prepared transmissions and chronological receiver-completion callbacks in the actual collector |
| PRACH / four-step RA | All five actual RA stages and TA=0 Msg3 CRC passed with physical sample-noise closure | Integrate staged RA with broadcast/TRS/data; implement and verify nonzero TA and separate UE TX / gNB RX origins |
| PUCCH / UCI | Formats 1–4 received-DM-RS estimation and real UCI decode; legacy format-0 detector coverage | Format-0 independent post-RF disturbance observation; commit feedback only after its actual RX completion |
| PUSCH / UCI | Actual coded staged PUSCH and UCI-on-PUSCH component tests; late ACK reservation reducers | Same physical stream as due SRS/PUCCH/other UEs; end-to-end received DCI, K2, HARQ and CSI delivery timing |
| SRS | Actual staged resource estimation and strict noise/NMSE checks | Shared-stream oracle diagnostics without rerunning RF/channel; resource priority and feedback applied at actual observation completion |
| Control / QCL / TCI / PMI | Exact coding/resource components and QCL/TCI/source-authority reducers tested; independent primary PDCCH noise-only RF pass removed in latest checkpoint | Verify activation time, beam/precoder actually used, and report-to-grant identity in the combined run |
| RSSI / CSV / PNG | CSI-RS resource/branch/bandwidth/symbol measurements and strict plot checks exist | Fresh measured combined-run rows/PNGs; SS-RSSI and UL observation definitions cannot be inferred from CSI-RS or whole-slot power |
| Continuous instrument IQ | Actual post-IFFT contributions and retained physical sample planes exist | End-to-end common-clock capture across all enabled channels, complete provenance, then instrument-specific playback validation |

No FDD-only or TDD-only workaround, forced MCS/rank/SINR, relaxed CRC/NMSE
assertion, synthetic output row or fabricated PNG completes any open item.

Two additional legacy evidence paths found by static inspection are **not
yet repaired by this checkpoint**: `annotateControlReferenceSINRColumnsImpl`
can infer `ChannelFadingApplied` from channel/profile/class strings plus
absence of a crash, rather than only retaining the producer's consumed-link
evidence; SRS `RuntimeNoiseApplied` currently follows a positive receiver
grid estimate rather than independently proving injected receiver noise.
Neither flag by itself is accepted here as physical execution proof. Their
producer/row authority must be corrected during the combined-stream migration.

## Absolute receiver noise and physical-stream owner (2026-09-07, subsequent checkpoint)

The main collector is **still not fully integrated with the chronological
stream**. No new production run, 25 dB run or hardware waveform
export has been claimed. The previously failed production CSV/PNG artifacts
have not been rewritten to look successful.

An additional real producer defect was found in the main PDSCH, PUSCH,
PUCCH, SRS, TRS, PDCCH and four-step RA paths. Their TX waveforms already
had absolute `sqrt(mW)` units, but the thermal-noise functions still
multiplied noise by `receivedWaveformPower / servingLinkBudgetPower`.
That lets fading, beam gain, duty cycle and unrelated serving-power metadata
change the receiver noise floor. The standalone PDCCH runner also lacked
the matching TX-power/RF boundary and applied RX RF before adding noise.

These paths now use `resolveReceiverThermalNoiseVariance`:

`sample noise variance [mW] = thermal power over B [mW] * Fs/B`.

The same noise PSD must cover the complex sample-rate bandwidth, not just
the occupied BWP. This is consistent with the
[complex-baseband thermal-noise sample-rate definition](https://www.mathworks.com/help/comm/ref/comm.thermalnoise-system-object.html)
and the distinction between
[sample-domain and occupied-RE SNR](https://www.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html).
No serving RSRP, measured fading gain or configured `12 dB` label is an input
to that variance. The broadcast path uses the same helper. Replay exposes
sample noise bandwidth, PSD and variance separately from the integrated
channel-bandwidth noise power. The legacy `AppliedAWGNSNR_dB` link-budget
field has an explicit **prediction, not measurement/noise-control** role;
it must not be displayed as measured SINR. RA stage CSV rows now also retain
the pre-front-end variance and sample-bandwidth/PSD closure.

`SharedWaveformPhysicalRuntime` provides the physical callback for the
existing event runtime: composed physical TX samples go through each node's
retained TX RF once, each actual link is filtered once, link outputs are
summed per receiver, then one persistent receiver noise stream and one RX
RF stream execute. It preserves separate TX, pre-RF and post-RF sample
planes. Duplicate channel ownership and outside clock advancement are
rejected. Thermal-noise identity belongs to the receiver, not the incoming
link. This callback is implemented and tested, **not yet selected by the
main eager grant/access collectors**.

The TDD reversal method preserves the same reciprocal fading owner and
requires actual outgoing TX silence sufficient to consume the channel FIR
tail before swapping. The installed toolbox's direction-swap implementation
resets the selected input filter; a swap is not permission to truncate
unconsumed RX samples. Profile/frequency/physical-link changes are rejected
as different operations, not silently accepted as a direction reversal.
FDD must retain independent carrier/direction links. The required legacy
E2E integrity regressions used their own FDD fixtures; no new production
FDD scenario or high-SNR adaptation run was launched.

Time-varying or missing applied AGC gains can no longer become unity in
`applyCompositeFrontEndVarianceReplay`. Nonstationary post-RF noise needs
actual reference-resource estimation/covariance handling. The new physical
owner intentionally does not invent a scalar post-RF variance when RF
processing occurred. Its interval-wide sample power is explicitly **not**
SS-RSSI or CSI-RSSI. Full UL RX estimator integration, measurement-defined
RSSI exports, nonzero TA, scheduler UCI deadlines and main QCL/TCI/PMI
consumption remain open.

Verification so far:

- `logs/shared_physical_absolute_noise_20260907.log`: absolute PSD/Fs power
  contract and broadcast thermal-noise/CFO continuity passed. The initial
  physical-owner test exposed a char/string direction comparison; repaired.
- Terminal batch **73303**, exit 0,
  `logs/shared_physical_thermal_tdd_20260907.log`: shared physical owner,
  actual five-stage TDD RA, staged SRS/PUCCH and coded DL/UL/UCI data passed.
  Whole/split actual CDL/RF/noise samples agree; direction reversal retains
  the clock and rejects an unconsumed tail. The RA test decoded **TA = 0**
  at 7.68 MHz and passed Msg3 CRC with the corrected absolute noise.
  SRS/PUCCH/data stage tests retain their explicitly limited standalone
  fixtures; they do not qualify the main combined runtime.
- Terminal batch **42021**, exit 0,
  `logs/physical_noise_focused_validation_20260907.log`: absolute noise,
  scalar-gain/ADC-assumption authority, broadcast continuity, `testConfig`,
  `testLLS_DL`, `testLLS_UL`, `testLLS_ReferencePoints`, `testStrictProxyGuards`,
  `testStrictMode_NoFallbackAnywhere`, `testE2E_FastVsTruth` and
  `testE2E_TruthPacketSemanticCampaign` completed successfully. This was the
  bounded requested validation, not `testAll` or full conformance.
- Terminal batch **53940**, exit 0,
  `logs/physical_noise_ul_final_20260907.log`: final scalar-noise metadata,
  shared physical clock (UL reversal at the authored 4 ms full-UL boundary),
  RA stage-noise CSV round-trip, HARQ-on-PUSCH, CSI source authority,
  future-UL planning, SRS/PUSCH priority, PDSCH QCL/TCI and CSI-RS physical
  resource measurement regressions passed. These are component/reducer
  checks; QCL/TCI activation and PMI use still require the combined run.
- Terminal batch **89202**, exit 0,
  `logs/broadcast_trs_pdcch_absolute_noise_20260907.log`: actual shared noisy
  CDL SSB/SIB1, TRS and PDCCH receivers passed with the new PSD/Fs conversion.
  This remains the pre-RF component composition test, not the main loop.

The subsequent standalone RA metadata rerun (**14311**) failed a next-stage
assertion despite the earlier combined passes. The fixture inherited global
MATLAB payload/noise RNG state from whichever test ran previously. It now
uses the **unchanged authored scenario seed 4702601**, restores the caller's
execution RNG state, and diagnoses a failed received stage before attempting
another preparation. There is no seed search, reduced noise or relaxed CRC
assertion. The authored-seed rerun (**5953**,
`logs/ra_authored_seed_absolute_noise_20260907.log`) exited 0 with all five
stages and the final noise/SNR CSV closure assertions passing. The repeat
from caller `rng(123,'twister')` also passed all five stages and assertions
(`logs/ra_seed_order_verification_20260907.log`); no MATLAB process remained
after the diary's final PASS. This is fixture-order independence, not a
multi-seed BLER qualification. The stage CSV also now closes
its SNR against actual pre-noise waveform reference power and injected
sample variance, explicitly labeled as a simulation reference, not a UE
report or requested-SNR echo.

Remaining legacy paths found during this review also include independent
PDCCH noise-only diagnostic executions and scalar post-RF covariance
assumptions beyond constant AGC. They have not been reclassified as measured
primary observations. The main chronological migration must replace those
with actual received windows and source-specific estimator evidence.

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
