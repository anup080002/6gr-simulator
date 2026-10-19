# LLS core repair matrix — 2026-10-16

**Partial repair, not all 35 items closed. Consolidated into main; not a ready-to-run acceptance certificate.**

Main checkout: `C:/Users/anup0/OneDrive/Documents/Simulator/6GR Simulator_v2_clean_main`.
Initial verification used a temporary isolated copy as requested in the audit prompt. The user's later single-codebase instruction superseded that boundary; continued development and verification use this main checkout only.
Base revision: `ad68dad5ecd4f1a91900f29beb83b6cf58d9f604`, including pre-existing dirty edits (not a clean-commit claim). No original logs/results were edited. The initial consolidation did not launch a full scenario or testAll. The separately approved 100-slot execution was started on 2026-10-17 as recorded below; testAll remains stopped.

MATLAB observed: **R2026a Update 4, 26.1.0.3312084**, 5G Toolbox 26.1, 6G Exploration Library 26.1.5. Exact installed inventory is in each test batch's `environment.json`. H4 retains its configured `38.214-v18.8.0-cap1-dmrs-pos0-mu1` capability profile and four-port Type-I Single-Panel CSI contract; two physical panels do not mean a Type-I Multi-Panel feedback wire format. The bounded RA/RRC profile is not full MAC/RRC qualification. Requested audit reference versions are recorded without upgrading the implementation baseline.

## Reading the matrix

### Measurement/export repair follow-up, 2026-10-17

The 100-slot run is **not running**. Its slot-41 failure and raw artifacts
remain unchanged. No scenario or full testAll was launched for these checks.
Production repairs are in the main checkout:

| Issue | Repair and verified boundary | Still required |
|---|---|---|
| H4-46 live CSV memory | Disk-backed snapshots; streaming validation/hashes/control-EVM input. Two 20,000-row inputs preserve all rows with 2,246,811 Python-traced peak bytes, versus 92,234,740 before. Torn/changing sources cannot replace latest. | Whole-process RSS and data-constellation consumers; not a full-run memory certificate. |
| H4-86 CSI sample paths | Writer uses configured run root; reader stays inside that run, including explicit legacy component-root layout. Cross-run rescue and competing paths reject. Original slots 6/26 each restore 559,104 identical primary/mirror pairs with unchanged source CSV hash. | Fresh integrated publication; CSI channel-NMSE qualification is separate. |
| H4-84 selected SSB SINR | PBCH callback retains selected SS-SINR, method/plane and source/availability clocks in beam CSV/GUI. Other-candidate and PBCH-DMRS values cannot substitute. | New physical-run verification, not rank-performance qualification. |
| H4-88 PRACH trace | Per-target outcomes remain tri-state. Detector scope, pre-guard, raw/corrected timing and point identity survive CSV/plot adapters; missing CFO no longer becomes zero. | Full-run trace and independent noise-only qualification. |
| H4-93 FDD calendar | Newly reproduced: period-4/offset-2 CSI-RS overlaps SIB1 on 48 REs at absolute slot 2. TDD validates. Default both-mode regression remains failed; no guard/catalog weakened. | Author a legal complete FDD calendar and verify feedback timing. Not a 100 MHz TDD collision. |

Focused receipts under `logs/lls_repairs`:

- `h4_live_snapshot_20261017_v1/receipt.json`: publication integration **1/1**.
- `h4_evm_root_before_20261017_v1/receipt.json`: **0/2**, wrong root and cross-run lookup reproduced.
- `h4_evm_root_after_20261017_v1/receipt.json`: actual shared CSI reception and 25/273-PRB lossless storage **2/2**.
- `h4_retained_csi_binding_20261017_v1.json`: read-only original-run audit, not a rerun.
- `h4_beam_sinr_before_20261017_v2/receipt.json`: selected-SINR loss reproduced after completing fixture cell/power-plane metadata.
- `h4_beam_sinr_after_20261017_v1/receipt.json`: beam binding, causal broadcast delivery and physical TCI admission **3/3**.
- `h4_prach_trace_before_20261017_v1/receipt.json`: false-alarm default reproduced.
- `h4_prach_trace_after_20261017_v1/receipt.json`: **3/4**; FDD calendar fails separately.
- `h4_prach_trace_tdd_20261017_v2/receipt.json`: explicitly TDD origin check and trace/Msg1 guards **4/4**. Default both-mode test was not relabeled passing.
- `h4_measurement_export_20261017_v2_python.xml`: **167/167** live snapshot, control-EVM streaming, dashboard and materializer checks.

Ten passing scoped MATLAB invocations and 167 Python checks do not establish
full-scenario acceptance, statistical qualification, or all-mode readiness.

### Post-failure core repair verification, 2026-10-17 05:20 IST

The physical run's report recovery finished at 05:06 IST. Its receipt remains
`Ok=false`, `sixgr:protocol:InvalidPacketSegmentRanges`, slot41/100. No raw
result was edited and no replacement scenario was started for these checks.

- **H4-92:** the unchanged core reproduced the slot41 assertion in the
  DL/UL one-committed-SDU plus queued-owner fixture. Normalizing the sorted
  segment sequence to a column fixes the empty-index orientation mismatch;
  duplicate/gapped segments, wrong offsets, missing owners and byte
  conservation remain guarded. This is a production-code repair, not a
  scenario change or suppressed assertion.
- **H4-27:** the actual receiver LLR vector now owns the generic availability
  and finite flags. RAR evidence retains actual receiver CCE starts rather
  than writing NaN. Missing evidence stays unknown; corrupt CCE values fail.
  Coded PDCCH reception and actual AL2/4/8 RAR round trips pass.
- **H4-91, partial:** the production directional eligibility resolver exposes
  effective SRS requirements, causal usability/status and its blocking gate.
  WebGUI renders DL and UL separately. These fields are explicitly not a
  promise of queued traffic, a free HARQ process, legal K2 resources or a
  completed grant. The codebook SRS guard is unchanged. The older two-UE
  test fixture now explicitly initializes independent receiver-owned TRS
  state; the production ownership guard was not weakened.
- The shared-data physical queue fixture had bypassed the production new-TB
  preparation boundary. It now calls `buildTrialContextFromGrant` before
  freezing both grants. Actual physical TX and TX/RX ledger-identity checks
  pass with distinct preserved logical TB IDs. This test explicitly does
  **not** establish a data CRC pass or integrated access/adaptation acceptance.

Evidence below is focused validation, not `testAll`, not statistical
qualification, and not a passing 100-slot run:

| Receipt under `logs/lls_repairs` | Result |
| --- | --- |
| `h4_slot41_accounting_before_20261017_v1` | 0/3; expected reproductions |
| `h4_slot41_accounting_after_20261017_v1` | 3/3 |
| `h4_slot41_adjacent_20261017_v1` | 7/7 |
| `h4_admission_before_20261017_v1` | Old fixture failed receiver ownership |
| `h4_admission_before_20261017_v2` | Missing production admission fields reproduced |
| `h4_admission_after_20261017_v1` | 2/2 |
| `h4_slot41_physical_after_20261017_v1` | 2/3; standalone fixture lacked original TB binding |
| `h4_slot41_physical_after_20261017_v2` | 2/2; affected fixture and RX identity guard |

There are **15 distinct passing MATLAB tests** across those final focused
checks, plus **63 passing Python tests** in the realtime dashboard,
failed-runtime status and packet-conservation audit modules. Other open
measurement, memory and physical-qualification items in the issue ledger
are not closed by these results.

### Retained slot41 PDCCH and regression preparation, 2026-10-17 04:46 IST

The failed run retains one actual connected PDCCH row with CRC pass,
operational RNTI4660, AL4 and50 decoded DCI bits with zero transmitted-bit
audit errors. Its32 hypotheses represent16 unique AL/candidate identities;
one hypothesis (zero-based index25) is accepted. This is one received
waveform observation, not32 independent reliability trials.

Independent arithmetic checks reconcile216 data RE,72 DMRS RE,
432 decoder LLRs and288 compared pilot-channel values (four UE receive
dimensions). Decision-directed EVM is3.8486510072063154%, from error
energy0.319941674825836/reference energy216. The separately scored
effective-pilot-response NMSE is-25.801413523363024dB, from
0.0345498492866148/13.1397623217656, without gain or phase fitting.
This checks retained operands, not an external or statistical qualification.
The control CSV SHA256 is
`a2caf5380d36bd3badb4d34069eead0871b54ebde1e8348f2979a68fd4ac9d08`.
The matching converter clipping/error and OFDM noise-transform arithmetic
also reconcile. Connected PDSCH and HARQ timeline rows remain empty;
control success must not be substituted for their missing outcomes.

H4-27 has an additional concrete export conflict: this same PDCCH row has
`PDCCHLLRCount=432` and finite actual decoder statistics but generic
`LLRAvailable=0` and `LLRFinite=0`. `PDCCH_Rx` retains `DecoderLLRs`;
`bindPDCCHReceiverObservation` copies the statistics without updating
the generic flags initialized false by the common row template. The
existing physical export test now asserts exact vector/flag agreement
and missing/empty/nonfinite-vector semantics. It has not run while the
failed MATLAB evaluation is still recovering reports.

Two new Python regressions in
`tests/test_lls_realtime_component_dashboard.py` were executed in isolation
and both fail as expected with missing `dl_scheduling_eligible`: the
adapter drops the directional fields. They also require absent directional
evidence to remain unknown, rather than inherit a shared eligible flag.
No application or MATLAB production file has yet been patched; the failed
run, logs and raw measurements remain unchanged.

### Slot41 terminal simulation failure, 2026-10-17 04:38:44 IST

The scenario subsequently stopped with
`sixgr:protocol:InvalidPacketSegmentRanges`. The retained
`reports/csv/runtime_failure_checkpoint.csv` identifies
`reconcilePacketBitConservation.m:50` called through
`refreshApplicationPacketDeliveries`, `publishPacketDeliveryLedgers`, and
the slot-completion live-state publisher. No connected DL/UL trial was
completed at this checkpoint; an accepted DCI is not a successful PDSCH.
The dashboard status resolver independently reports `failed`,
`result_ok=false`, with this failure checkpoint as authority. MATLAB is
still handling failure recovery; it cannot advance this scenario.

H4-92 records the reproduction target: one committed SDU range with other
queued application owners. The current assertion compares vector shapes
as well as sequence values, so the empty-match orientation is a plausible
cause, not yet a MATLAB-proven root cause. The added regression exercises
both DL and UL, both packet orderings and actual reservation/HARQ state,
with explicit declared component outcomes rather than fake physical CRCs.
It also retains negative missing-sequence and owner-mismatch checks.
The test has not been executed and no production change has been made
while recovery remains active. Existing logs/IQ/results are preserved.

### Bounded RRC completion and first connected-control checkpoint, 2026-10-17 04:38 IST

The approved run has completed RRCSetupComplete at absolute slot39
(zero-based; runtime slot40). Its actual receiver row has CRC=1,
Decoded=1, ReceiverOk=1 and RRCConnected=1. Transaction ID0, SRB1 LCID1
and UE identity `UE-1` match the decoded values. The received and transmitted
payload SHA256 both equal
`2f789ca206b275c3da43a74b4ebe9e9ff88326f9ae73cedea10ac44636865158`.
The eight endpoint/event rows preserve the earlier SRB1=false state,
receiver-only CRC evidence and the transition to CONNECTED. This verifies
H4-42 on this integrated access execution, not full NR MAC/RRC conformance:
`MACRRCStandardsQualified=0` remains explicit.

The received SetupComplete capture is `[2393331,2457343)` at122.88MSa/s,
ending at19.997908528645834ms, before the20ms decision boundary for
runtime slot41. The lifecycle's13ms procedure delay is its explicitly
declared inclusive-slot interval `[7,20)`ms, not total startup time or an
independently measured decoder latency. Source and availability clocks
must remain distinct.

At slot41, access=1, shared eligibility=1, DL eligibility=1 and UL
eligibility=0. A DL grant was scheduled and the actual shared DCI was
accepted at sample2466450; the connected PDSCH outcome is still pending
at this checkpoint. The bidirectional full-buffer scenario enables
codebook PUSCH. `ulRequiresCausalSRS` therefore requires a received, usable
SRS even though the separate global `control_gating.srs_required` is false.
Its first post-attach SRS is queued for runtime slot45. Do not remove this
requirement or report an UL decode before that waveform executes.

An observability gap remains (H4-91): the control CSV contains both
directional eligibility booleans, but the UE-card adapter exposes only
the current-direction boolean and the general `SRSValidityState` value
`not_required`. The scheduler also reports only `no_active_eligible_users`.
The effective UL prerequisite and its causal measurement status must be
exported, not guessed by the UI from absence of grants.

Read-only arithmetic for the same SetupComplete capture reconciles ADC
clipping43/4096768 (0.001049607886021371%) and DAC clipping0/256048. Counts
equal64012 capture samples times64 receive dimensions or4 transmit
dimensions respectively. Converter sample-domain RMS errors are
0.10659699305417987% (ADC) and0.14168563199816356% (DAC); these are not
post-equalization modulation EVM. Executed sample noise2.44140625e-8
times the4096 OFDM transform gain equals grid noise1e-4, consistent with
unit reference energy and40dB configured Es/N0. This arithmetic does not
require measured receiver SINR to equal40dB.

Checkpoint SHA256 values:

- `control/csv/rrc_setup_complete.csv`:
  `7acc66a26605a7f74bc39bea21c00b9044195c1094795be4b1a6c2fbc65928d4`.
- `control/csv/rrc_connection_events.csv`:
  `c2cae8a20e4b3545116ac4044ff7387604a06cebfa34815c9354df4cc7bb3c87`.
- `control/csv/initial_access_lifecycle_trace.csv`:
  `10b3df4a508a4927470c964ac196fc6c2043dada4ff9abd2a362a9e2912cd8b2`.
- `control/csv/ra_receiver_rf_observations.csv` (seven rows):
  `5a7f7a95e7875ed6c5a159036ee6e47812b657c3e6f92f644ce624c404bb0ff2`.
- `reports/csv/live_control_gating_state.csv` (slot41 checkpoint):
  `8fb017312b58c94709911fce113dc1a1a13a11bbb87be7e6cbe6a85789cd7634`.

No production/configuration files or original results were changed, and
no additional MATLAB execution was launched. The current run is still
active, not an accepted100-slot or statistically qualified result.

### Received Msg4 checkpoint, 2026-10-17 04:26 IST

The same active run has now decoded Msg4 at absolute slot37 (zero-based).
PDCCH CRC, PDSCH CRC and contention-identity comparison all pass. The
receiver recovers `000000000001` and the exact transmitted payload
`020000000000011234320001`. `msg4_contention_resolution.csv` explicitly
retains `MACEncodingProfile=legacy_bounded_not_NR_MAC_RRC` and
`MACRRCStandardsQualified=0`; this success is not full NR MAC/RRC conformance.
RRCSetupComplete and connected-mode data remain pending at this checkpoint.

The three independent UE contention-monitoring rows show no decoded DCI
at slots35/36, then successful DCI/TB/identity at slot37. These earlier
monitoring outcomes must not be reported as failures of an already-issued
Msg4: configured SetupComplete K2=2 plus the actual DDD-S-U pattern requires
a DL Msg4 slot whose slot+2 permits the complete UL allocation. The retained
actual Msg4 slot37 meets that timing condition. No arbitrary attach deadline
was introduced.

Read-only checks find exact TX/RX agreement for all12 retained DCI fields,
valid field widths/bit positions, matching payload/identity, and reception
within the real contention window. Its timer begins at34380464 Tc, exactly
the saved Msg3 transmit end2148779 samples times16 Tc/sample. Msg4 capture
`[2273291,2334845)` completes before the97295024-Tc expiry. Receiver-reported
SINR is22.941064078888 dB with5,184 finite LLRs and one decoder iteration;
the missing detailed SINR/CFO definitions remain H4-90, not assumed correct
or filled from the configured40-dB reference.

The matching RF observation is named `ContentionMonitoring`, not `Msg4`:
its identity is the same UE/attempt/capture interval. It records2 clipped
ADC samples out of246,216 and zero DAC clipping out of3,939,456; both
fractions recompute exactly. There are six RF-observation rows at this
checkpoint, including the two preceding monitoring captures, rather than
four independent successful access stages. Do not merge those populations.

Checkpoint SHA256 values:

- `control/csv/msg4_contention_resolution.csv`:
  `6156e31084f703902710f31e50d722e7626949274a5a1f8eee810e34e9017522`.
- `control/csv/msg4_dci_fields.csv`:
  `c8bd14ce63f414228fe2359582ccde483381f53d4c65dae7e07cf742ada1b591`.
- `control/csv/contention_monitoring_observations.csv`:
  `81297f2bc846010acfa197e422b59e4d9fe7cc0396b50b67e9da86e2e6f251fb`.
- `control/csv/ra_receiver_rf_observations.csv` (six rows):
  `f1a60aeeea499aece45508b7d763b240c25a42ebae4d457e1b6279f5cd2d622c`.

These are arithmetic/identity audits of actual execution, not additional
physical trials or statistical qualification. All3,076 frozen production,
application, script and configuration hashes still matched at04:22 IST.
Only this matrix and the existing issue ledger were updated during the audit.

### Received Msg3 and actual UE-IQ audit, 2026-10-17 04:21 IST

The same approved 100-slot run is still executing. Access-stage Msg3 has
passed UL-SCH CRC and recovered the RRCSetupRequest payload exactly; this is
not yet complete attachment or a connected-mode PUSCH trial. Its retained
`control/csv/msg3_pusch_trials.csv` has SHA256
`2708dd62e49546f71c50f82a729f83f87353f004f5c9ac588668b5be75fea6c4`.

The decoded RAR grant independently resolves to PRBs0..23, TDRA0, MCS0,
QPSK, and absolute slot34 (zero-based, runtime slot35). Default-A K2=1
plus Msg3 delta3 places it four slots after the slot30 RAR. The row records
736 TB bits,6,336 finite demapper LLRs and one decoder iteration. Under the
executed configuration's three DMRS symbols with two CDM groups without
data, the corresponding arithmetic is24*(12*14-3*12)=3,168 data RE,
Qm=2 and R=120/1024: Ninfo742.5 quantizes to736. The small-TB value is in
[TS38.214 v18.8.0 table5.1.3.2-1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).
This configuration/row agreement is not a substitute for the missing
observed-RE export identified below.

The actual post-RF continuous UE waveform was inspected independently,
without invoking MATLAB or changing any retained data. Files
`waveform/raw/continuous_tx_iq_ue_1_port{1..4}_cf64le.bin` contain interleaved
little-endian real/imaginary doubles,16 bytes per complex sample. Across
the bounded sample window `[2085500,2151500)`, port1 has precisely one
nonzero interval `[2087339,2148779)` of61,440 samples; ports2..4 are zero.
This is the rank-one access transmission, not a test of four-layer UL data.

The interval matches the received-clock timing path:
`34*61440 + 11 - 1600 - 32 = 2087339`, where11 is the received DL phase,
1600 samples represent the FR1 common timing offset, and32 samples are the
received absolute RAR TA command. The complete waveform is advanced, not
shortened by32 samples. Receiver capture starts at2086131 and includes a
1,229-sample search pre-roll; its raw DMRS timing estimate of1,229 is not
itself a propagation-delay estimate. Source owners are
`receivedDLTimingReference.m`, `resolveULTimingAdvanceOffset.m`, and
`sharedULStageTiming.m`. The retained executed interval agrees with these
clocks; their complete conformance is not inferred from one success.

The exact61,440-sample port1 interval has SHA256
`991a04bb2bd1dedb6544cf93afae928c649fc4faf6bbaf489a418ff611eb36df`.
Independent FFT/CP inspection used Nfft4096 at122.88 MSa/s,30-kHz spacing,
and CP lengths352 followed by thirteen288-sample prefixes. All14 symbols
fit the retained extent. Excluding the first64 prefix samples from this
diagnostic, CP-to-tail correlation is at least0.99999739. Each symbol has
99.9091%..99.9096% of its FFT energy in the expected24-PRB band; approximately
0.0902%..0.0905% lies in the mirror band. These are measured post-RF waveform
diagnostics, not a claimed RF-conformance EVM or independent receiver decode.
The mirror component must remain visible under the configured IQ impairment.

Msg3 receiver RF arithmetic also closes:40 clipped complex samples out of
4,096,768 ADC samples and zero out of256,048 DAC samples. Converter RMS
errors from retained error/input energies are0.114075% ADC and0.141365% DAC,
not modulation EVM. The three-row RF CSV hash is
`ebee49682d0f3f8aef359c5a8396a4f5a94077fdcd203463164848381f1107a0`;
the three-row stage-waveform CSV hash is
`1439283cdf98aaab9322e2fc31650d0e6013b8f4f382c407bfc6d9010b11de26`.
Earlier two-row hashes below describe an earlier checkpoint, not corruption.

**H4-89 remains open:** `runFourStepRA.m` builds its observed allocation
table only from Msg1, both in continuation and finalization. Actual Msg2,
Msg3, Msg4 and SetupComplete TX objects are available but omitted from that
producer. The437,656-row current NR-grid map and its live mirror have the
same SHA256 `5d2c68b793236dc2a401e116a202b9f9772033dc49e3b059012397c627e1f35a`
and no Msg2/Msg3 allocations. The repair must collect exact executed
PDCCH/PDSCH/PUSCH/DMRS/PTRS indices through `buildObservedREAllocation`,
retain physical-versus-logical mapping and stage identity, and publish
failed-decode transmissions too. Prepared future waveforms must remain
absent. Continuations/retries/finalization must not duplicate allocations.
No planned rectangle or successfully decoded TB may stand in for actual
RE occupancy. Production changes and affected tests await completion of
the frozen run; this audit did not modify source/configuration or raw output.

**H4-90 also remains open:** the Msg3 row exports post-equalizer SINR
39.8758010090971 dB and pilot/Hest SINR29.3779956944092 dB without the
definitions already computed by `PUSCH_Rx`. Their difference is not by
itself a receiver defect. `runFourStepRA.localApplyPDSCHRxDiagnostics`
retains a short scalar whitelist, and the PUSCH adapter delegates to it.
The core receiver's source/status, equalizer reduction, residual-bound and
CFO estimate/correction/residual-role fields are dropped before stage CSV
publication. Extend the common adapter and actual stage row writers, then
the GUI, preserving the exact receiver semantics and unattempted/partial
states. Do not replace a missing CFO estimate with the injected400 Hz or
describe same-window estimator consistency as an independent residual.
`testRAStageEvidencePublication`, the actual Msg3 and Msg4 receiver tests,
and no-decode stage cases are the affected verification boundary.

An apparently missing RF count is **not** another measurement defect:
Msg3's scalar `TxRFAppliedStageCount` is NaN because the receive window
includes silent UE intervals. The retained `TxRFEndpointMetadataAuditJSON`
contains all five intervals, with applied-stage counts0/4/4/4/0 and
configured/executed counts4 throughout; its active interval agrees with
the saved IQ. RX has six executed/applied operators in every interval.
Both endpoint validation statuses are explicitly passed in
`ra_receiver_rf_observations.csv`. A scalar count must not replace that
time-varying evidence or claim sample mutation during silence.

### Received Msg1 and RAR audit, 2026-10-17 04:01 IST

The approved run remains active, not accepted. Its measured Msg1 uses native
B4 PRACH, 64 gNB receive dimensions and 12 repetitions. Preamble 0 is detected.
The configured automatic threshold is `0.1/sqrt(64*12) =
0.00360843918243516`, matching the installed R2026a implementation and
[MathWorks' documented detector policy](https://www.mathworks.com/help/5g/ref/nrprachdetect.html).
This is not a universal 3GPP threshold or statistical qualification. The native
receiver returns the strongest detected preamble, not a complete detection set.

`control/csv/rar_monitoring_observations.csv` now records one actual accepted
RAR at absolute slot 30 (zero-based): DCI CRC, RAR-PDSCH CRC, RAPID matching and
UL-grant validity all pass. The capture is `[1843211,1904765)` at 122.88 MSa/s.
`msg2_rar_trials.csv` records post-equalization SINR 23.3872787795296 dB,
5,184 finite demapper LLRs and one decoder iteration. These are access-stage
measurements, not connected-mode data or complete attachment.

Independent byte arithmetic on retained `4000098870061234` gives RAPID 0,
12-bit TA command 1, 27-bit grant `001100010000111000000000110`, and temporary
C-RNTI 4660. These agree with the export. Field widths follow
[TS38.321 v18.5.0 section6.2.3](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.05.00_60/ts_138321v180500p.pdf).
At the configured 30-kHz first-UL SCS, the absolute TA conversion in
[TS38.213 v18.5.0 section4.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.05.00_60/ts_138213v180500p.pdf)
gives 512 Tc = 32 samples = 0.2604166667 microseconds. Received command
agreement does not yet prove application by a subsequent Msg3 transmission.

A read-only independent Python arithmetic audit passes **41/41 checks** of
these two receive windows: sample/port populations, clipped-sample fractions,
converter error energy/MSE, contiguous RF interval coverage, configured/applied
AWGN identity, noise transform, RAR fields and response-window membership.
This is not a MATLAB rerun or independent statistical performance population.

| Observation | RX ADC clipping | TX DAC clipping | ADC / DAC RMS converter error |
|---|---|---|---|
| Msg1, 64,012 samples | 2 / 4,096,768 | 0 / 256,048 | 0.083623% / 0.385403% |
| RAR, 61,554 samples | 6 / 246,216 | 0 / 3,939,456 | 0.160279% / 0.279510% |

Converter errors are `100*sqrt(error_energy/input_energy)` on each actual
converter plane, **not** post-equalization or standards-qualified RF EVM.
Actual capture-scoped RF evidence remains separate from decoded PHY success.
At this checkpoint the four audited source SHA256 values are:

- `control/csv/msg1_prach_detection.csv`:
  `c2237f53a6b8dc73f0e1e434f509368a1f4ce3a20c3e60bc527feb5618954931`.
- `control/csv/ra_receiver_rf_observations.csv` (two rows):
  `e6a3692bd5f0599a995cd5fe3e4b4f3f19d2ac784dfc3faa3f71c7c4292e804f`.
- `control/csv/ra_runtime_stage_waveforms.csv` (two rows):
  `24085367083e95cec4f5947af330b6874bc995bb6b10026caac55ceadbcc0360`.
- `reports/csv/prach_correlation_trace.csv` (one peak):
  `a7f6466cd3fc923caf9afb495018fff4aa6f96b92e1d014394349b4dde3f833a`.

Three reporting/measurement gaps are now traced to exact production owners:

1. **H4-87:** the strongest-detector path calls a lower-tail median of
   candidate maxima a PDP noise floor. It does not execute the existing
   independent repetition-difference estimator. That estimator is wired only
   through AWGN SIC; enabling SIC on CDL-C is not a valid repair. Implement
   same-capture, native-symbol background measurement separately from the
   unchanged native detector, preserving noise-plus-time-variation semantics
   and matching metric normalization. Retain the candidate-background statistic
   only under its own definition, not as measured thermal noise.
2. **H4-88:** `localBuildFourStepRACorrelationTraceTable` defaults an absent
   `ra.FalseAlarm` to false, while the detailed Msg1 table correctly retains
   unknown false-alarm status. It also drops `toolbox_peak_only_evidence` and
   timing-origin metadata. A single real peak is not a full correlation curve.
   Keep unknown/true/false distinct; retain native-input, capture and calibrated
   timing coordinates separately. Any requested full diagnostic trace must use
   the same captured samples without silently refining the decision timing.
   Existing `full_trace` code changes timing; it cannot simply replace
   `toolbox_peak` as a supposedly export-only fix. Missing all-NaN columns in
   this live CSV are explained by `csvWriteTable` schema pruning, not evidence
   of an older loaded source version or an overwritten raw capture.
3. **H4-27 follow-up:** `PDCCH_Rx` now records actual candidate CCE indices,
   but `rarPDCCHCandidateEvidence` still emits literal NaN and an obsolete
   not-published reason. Its physical AL2/4/8 test explicitly expects that old
   absence. Repair the adapter and strengthen the test against the actual
   receiver's identity, not a manufactured index or transmitter schedule.

No active MATLAB source/configuration or retained output was edited for this
audit. Production fixes and affected MATLAB tests remain queued until this
frozen execution is terminal; no testAll or second scenario was started.

### CSI paired-MAT root binding, 2026-10-17

H4-86 is an integration/export-path defect, not missing waveform samples.
The actual slot6/26 `ControlEVMSamplesMATFile` values start with
`air_interface/mat/control_evm/`, but the physical files reside under
`air_interface/air_interface/mat/control_evm/` below this run. Both file
checksums match and the complete expanded CSV was independently reconciled.

`completeSharedCSIRSReception` passes `state.RunFolder` into
`retainControlEVMPairs`, whose argument is a run root. In full-bundle
execution `state.RunFolder` is the air-interface component directory;
the canonical root is separately installed as `cfg.run.rootRunFolder` by
`runWaveformLinkBundle`. The existing component/storage tests pass the same
directory as component and run root, so they do not cover this distinction.

A read-only reproduction of `readControlEVMPairs` path-search logic resolves
both files when starting from `air_interface/csv/csi_rs_trials.csv`, but
resolves neither when starting from the identical bindings in
`control/csv/csi_rs_trials.csv`. Direct resolution relative to the declared
run root also fails. This is not a new MATLAB test or a demonstrated terminal
exception: the live mirrored writer currently expands samples only from
the air-interface path.

After the frozen execution, fix the production caller's root authority and
bound the reader to that run. Test real distinct component/root directories,
primary and mirror consumers, relocation, checksums, and a same-named parent
artifact that must not rescue a missing local file. Existing retained files
must remain intact; any legacy resolution must explicitly identify the old
component-root contract, not scan another run or rewrite historical identity.

### Statistical population-design defect, 2026-10-17

H4-85 blocks a valid PRACH statistical campaign until its trial identity is
repaired. `runStrictPRACHValidation.m:localRunStatisticalBatchTrial` selects
a cyclic configured seed base and adds `trialNumber`. With this scenario's
four bases `[240616,240631,240641,240659]`, H0 trials 2 and 17 both pass
340634 to `rng(...,'twister')` at the first sweep point. Further examples
are trials 6/21 and 10/25. Exact enumeration gives:

| Planned H0 rows | Distinct actual noise seeds | Repeated seed rows |
|---|---|---|
| 3,000 | 2,254 | 746 |
| 7,750 | 5,816 | 1,934 |
| 12,000 | 9,004 | 2,996 |

At a fixed SNR and waveform size these H0 resets produce repeated noise-only
observations, yet every row enters the independent binomial denominator.
The H1 generator uses the same colliding construction (a different constant
offset does not remove collisions). Independent fading realizations do not
justify asserting independent receiver observations with reused noise.
The exported H0 `NoiseSeed` also precedes the generator's `+1` adjustment.
This is source/seed-arithmetic evidence, not a newly executed PHY campaign.

The required repair is deterministic collision-free stream/domain identity,
recording the actual RNG seed/substream, and full-design uniqueness plus
serial/parallel/resume tests. Affected old campaigns must retain their
original evidence and have their qualification reassessed; do not silently
recount repeated rows as independent or change the interval thresholds.
The existing `sixgr.phy.pdcch.noiseTrialIdentity` already defines injective
Threefry substreams with overflow and duplicate-family guards; prefer reusing
that approach through a shared owner, with explicit disjoint H0/H1 and point
domains, rather than adding another additive seed formula. Its existing
`testPDCCHFalseAlarmSweep` cases are adjacent guards, not proof of repaired
PRACH wiring. The PRACH producer must actually consume and export the new
stream identity; a unique ID column alone would not correct repeated noise.
The active 100-slot integration run disables statistical qualification, so
this defect does not establish a failure in its physical initial-access path.

For planning **after** independent trial generation is fixed, the configured
95% two-direction, multiple-look Clopper-Pearson rule has per-direction
alpha `0.05/(2*48)` for H0 and `0.05/(2*40)` for H1. With hypothetical zero
errors, the first allowed passing batches would be 7,750 H0 trials and 750
H1 trials per required 6/12 dB point. Their upper bounds are respectively
0.0009750186 and 0.0097887867. These are design calculations, not measured
results, not universal 3GPP requirements and not acceptance of the currently
colliding generator. No new MATLAB job or statistical campaign was started.

### Live-publication memory audit, 2026-10-17

The terminal control-EVM streaming tests do not cover every publisher.
`scripts/publish_lls_live_csv_plots.py:publish` currently reads every source
into bytes, decodes it into a string and constructs a complete
`list(csv.reader(...))` before retaining the source payloads for rendering.
The first 10,000 actual CSI data records (plus their header) occupy 5,833,891
CSV bytes; a read-only bounded reproduction of this parser operation uses
16,668,602 retained and 40,021,503 peak Python-traced bytes. This is not
process RSS or a measured full-publisher peak. The complete current CSI
file has 559,104 data records and 328,010,988 bytes.

H4-46 now explicitly includes this unbounded live path, not only terminal
rendering/native channel ownership. Its pending repair must stream source
validation, hashing and immutable copying, retain exact chart input identity,
and reject torn sources without discarding samples. No publisher was run
manually and no active output was changed. At 03:16 IST MATLAB remained live
with about 9.64 GiB private memory and Windows reported 23.8 GiB free commit;
no live-publisher out-of-memory failure was observed in this run.

### Live projection audit at slot 21, 2026-10-17

The selected SSB index 1 has a measured `SS_SINR_dB` of 25.5806996009459 in
`air_interface/csv/pbch_trials.csv`, with an SSS-based measurement method and
normalized received-grid reference plane. Its three P1 transitions in
`beamforming/csv/beam_management_state_trace.csv` omit that measurement.
`stageMeasuredSSBBeamRuntime` takes only the selected RSRP and explicitly
passes `NaN` SINR to each transition. H4-84 tracks the required selected-row
projection repair and negative tests; PBCH-DMRS SINR 27.3803084708637 is a
different measurement and must not fill the SS-SINR field.

H4-57 is now explicitly partial: the actual startup message correctly says
that no standalone anchor cases executed, but subsequent progress publishers
hardcode `AnchorKPIsReady=true`. Slot 21's live status confirms that incorrect
readiness flag. This does not establish an anchor test or a full scenario
pass. The repair must cover all publishers, not just the startup message.
Both findings were audited without changing the running production source
or any retained measurement. At 03:12 IST all 3,076 frozen production/config
file hashes still matched the launch manifest.

### PDCCH configuration-authority audit, 2026-10-17

Ledger H4-83 records an inherited metadata mismatch found during the active
100-slot run. Its immutable resolved JSON says `pdcch.crc_length: 16`, copied
from the legacy causal-access scenario/default catalog. The executable
`PDCCH_Tx.m` calls `nrDCIEncode`; `PDCCH_Rx.m` calls `nrDCIDecode`. The strict
profile and independent CRC class specify CRC24C with 24 CRC bits and a
16-bit RNTI mask. Production MATLAB search found no consumer of the advertised
lowercase `crc_length` field; `buildInternalConfig.m` binds its PDCCH control
settings from `control`. This finding does **not** prove that the current
waveform uses a 16-bit CRC or explain a physical decode failure.

The pending repair is to align the NR defaults and inherited declaration,
then validate the declared width against the installed NR profile rather
than silently accepting or rewriting incompatible values. The schema
currently accepts any nonnegative integer. Required affected checks include
rejecting a 16-bit NR declaration, retaining a valid 24-bit declaration,
and actual encoding/decoding with RNTI masking. Explicit experimental
control profiles must remain separate. No production/configuration file,
saved run configuration or old measurement was changed during this audit.

References: [TS 38.212 v18.8.0, section 7.3.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf)
and [MathWorks nrDCIEncode](https://www.mathworks.com/help/5g/ref/nrdciencode.html).

### 2026-10-17 approved 100-slot execution

The main-checkout run `h4_100mhz_40db_adaptation_20261017_v1` entered slot 1/100
at 02:16:45 IST. Scenario:
`simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml`.
It retains 4 GHz / 100 MHz TDD, physical initial access and feedback, CDL-C/RF,
64 gNB dimensions, four UE chains and configured DL/UL rank ceilings of four.
Results:
`results/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/h4_100mhz_40db_adaptation_20261017_v1/`.
WebGUI filesystem run ID: `9122298978`. The launch manifest
`logs/h4_100mhz_40db_adaptation_20261017_v1_source_manifest.json` hashes 3,076
production/configuration files. This records a launch and first-slot entry,
not completed access, data reception, adaptation or final acceptance.
Production sources are left unchanged during this execution. Its terminal
receipt and independent measurement/export audit remain pending.

#### Read-only interim audit at 02:42 IST

The same MATLAB engine (PID 19728) advanced to slot 10/100 with increasing
CPU time and no terminal receipt. Tracking state reports valid TRS; access
remains pending and no connected DL/PUSCH trial has completed. These are
interim observations, not a scenario-pass claim.

The first actual CSI-RS row (resource slot 6, delivery slot 7) reports RI 2,
CQI 14 and CRI 1. Reference-RE SINR is 29.010306 dB; the selected
rank/precoder receiver objective is 21.978930 dB. Their declared planes
are different. The physical CSI feedback table is still empty, so this
observation is not evidence of delivered CSI or an adapted data grant.
Six operand-arithmetic checks and two per-plane synchronization-metadata
checks pass. These checks establish internal consistency, not independent
receiver accuracy or statistical performance.

A subsequent read-only audit covered the complete `MeasurementPhysicalResourcesJSON`
for that first observation: eight resource IDs 0--7, four receive branches
per resource and four logical reference ports. All resource symbols
`[3,4,5,6,8,9,10,12]`, 273-PRB bandwidths and 98.28 MHz occupied spans match
the resolved configuration. Ninety-six branch-level RSRP/SINR/RSRQ operand
checks agree within `7.11e-15` dB. Resource 1 has the maximum recorded
receiver-capacity objective and is the selected CRI; resource 0 has the
highest RSRP instead. This checks the recorded selection identity and
arithmetic, not an independent recomputation of its channel/codebook
objective, a decoded CSI report or a scheduler-applied grant.

The stable `air_interface/csv/csi_rs_evm_samples.csv` contains all 559,104
retained pairs (8,736 for each of 64 physical TX ports), with no malformed
rows or nonfinite paired components. Every row explicitly identifies
`raw_gain_inclusive_TX_pair_error_not_standardized_modulation_EVM` and
`StandardizedModulationEVMQualified=0`. Direct recomputation gives
59.015348--59.029518 percent raw gain-inclusive error across ports. This
includes configured TX gain/backoff and is neither RX constellation EVM
nor standards-qualified modulation EVM.

Ledger H4-82 records a newly identified summary-definition gap:
`localBuildCSIRSStatsTable` maps `PilotResidualNMSE_dB` into the same
`MeanNMSE_dB` column used for independently scored channel errors in other
signal families. The current summary has not yet received its heavy
refresh; no completed plot defect is asserted from an empty live table.
The producer needs distinct definitions and source-backed independent
scoring, not a renamed fabricated measurement. This is queued for repair
after the frozen execution; this interim audit changes documentation only.

#### Second CSI observation and exact joint-export audit, 03:41 IST

The same MATLAB engine advanced through slot 26 and entered slot 28/100.
The completed slot-26 primary row retains capture `[1536000,1597440)` at
122.88 MSa/s, RI2/CQI14/CRI1/PMI18, reference-RE SINR 28.945322 dB and
selected rank/precoder objective SINR 22.037585 dB. These are different
measurement planes. ADC clipping is 9/245760 samples and DAC clipping is
0/3932160 samples. The pre-access CSI observations are not delivered CSI
reports or proof of scheduler adaptation; attachment and data remain pending.

The two-row `air_interface/csv/csi_rs_trials.csv` has SHA256
`6395afefc0daafe07f233e88b036254a6b9a887c28f8ac2b8386e9005655a66c`.
Its joint paired-sample CSV contains 559104 rows from each of slots 6 and26,
covering all 64 physical TX ports at each occasion. A bounded streaming
read-only comparison checked **all 1118208 records** against the two
checksum-verified retained MAT files: every complex component matches
exactly, with complete unique sample identities and correct source-row,
direction, UE and SNR bindings. The stable 658213846-byte CSV has SHA256
`7cbd74b4e63a522b91e597d34271da32b18d4adbc8c67e730ad0b5744850afbc`.
This establishes lossless export, not standards-qualified modulation EVM.

Across both CSI observations, 192 per-resource/per-branch power/SINR/RSRQ
operand checks agree within 7.11e-15 dB. The CSI-IM covariance matrices are
Hermitian, positive definite and have diagonals equal to their exported
branch disturbance powers. Both retain 1092 configured measurement REs
and the correct zero-based source slot. These are consistency checks, not
an independent remeasurement of receiver IQ. The primary CSI/PBCH/TRS
audit now has 46 arithmetic passes, four synchronization-metadata passes,
one unevaluated TRS-EVM check and no arithmetic mismatch.

The deeper H4-82 source trace identifies an upstream gap, not merely a
column-name issue. `CoupledWaveformStream.queueDownlink` registers desired
scoring observations for TRS/PBCH but not CSI-RS. The generic
`sharedLinkScoringObservation` has no prepared-CSI-RS struct branch.
`completeSharedCSIRSReception` calculates practical feedback and retains
TX pairs, but does not publish its RX samples/channel estimates or perform
independent channel scoring. No persisted CSI-RS RX-IQ capture was found
for either completed observation; a new offline receiver-IQ remeasurement
was therefore **not** claimed.

The post-run repair must register exact CSI observation/reference windows,
retain the actual receiver estimate and installed resource/CDM/port/beam
identity, and score after practical reception. Multiport CDM requires a
port-resolved reference; dividing a composite desired waveform by one
pilot is not a valid per-port channel reference. Reuse actual executed
channel/clock/projection evidence without rerunning the channel or giving
the reference to the practical receiver. Export independent channel NMSE
and pilot-reconstruction residual under separate definitions, with complete
complex-sample operands and bounded retention. Extend focused tests for
multiple resources/ports, distinct residual versus channel error, actual
RX-clock correction, and unchanged CSI/RI/PMI output when scoring is
enabled. This finding does not establish an error in the received CSI
recommendation itself. Frozen production/configuration files and original
results were not modified.

At 03:46 IST the second TRS row (resource slot27) was published. The
two-row primary TRS CSV SHA256 is
`21206a21d70951268a2234ca829d3357f97bb327b4aab39f35ee8807a2eee4e9`.
It retains independent NMSE -24.992069 dB from error energy 1.44752480860419
and reference energy 456.912333286198, with 3276 pilot resources and13104
complex comparisons. Its window `[1597440,1720320)` completes at the
slot29 scheduling boundary; receiver timing correction is16 samples and
estimated CFO is440.311383 Hz. ADC clipping is23/491520 and DAC clipping
is0/7864320. Both primary/control TRS tables contain the same two resource
occasions. The combined primary audit now has52 arithmetic passes, four
synchronization-metadata passes and two unevaluated TRS-EVM rows, with no
arithmetic mismatch. This closes neither TRS-EVM nor broad statistical
qualification. PRACH preparation at slot29 is not yet a detection outcome.

At 02:53 IST, the first completed TRS row (resource slot 7, delivery slot 9)
was audited from `air_interface/csv/trs_trials.csv`, SHA256
`c99f8bb050c73a0c42796ebe4fbc9a2b7494f8bb409b4701839dc06547ca2d7a`.
The previously missing qualification mode, reference plane, 3,276 pilot
resources and 13,104 compared complex values are now present. Its error and
reference energies reproduce NMSE -24.821237 dB. Independently summing the
retained per-slot/per-branch energy operands reproduces pilot SNDR
22.974946 dB and the complete compared-value count. Both applied timing
windows fit the recorded 122,880-sample receive capture. ADC clipping is
20/491,520 complex samples; DAC clipping is 0/7,864,320. This verifies the
first integrated metadata/operand projection, not the estimator's statistical
accuracy. TRS EVM is unmeasured, and offline complex-sample recomputation of
TRS NMSE has not been established from the currently published artifacts.
The combined CSI/TRS arithmetic audit has 12 arithmetic passes, two CSI
synchronization-metadata passes, one unevaluated TRS EVM check and no
arithmetic mismatch. The full run was still active at slot 14/100.

#### Actual IQ and acquisition cross-check at 03:01 IST

Without another MATLAB execution, NumPy FFT extraction from the actual
`waveform/raw/continuous_tx_iq_gnb_1_port*_cf64le.bin` files reproduced all
559,104 measured CSI-RS pairs on all 64 physical TX ports. The checked
half-open interval is `[307200,368640)`: 61,440 samples at 122.88 MSa/s,
FFT 4096, 3,276 occupied subcarriers and 14 symbols. CP lengths are
`[352,288,288,288,288,288,288,288,288,288,288,288,288,288]` for this slot.
The extraction uses the production demodulator's explicit 0.5-CP FFT
window and the corresponding cyclic-shift phase correction; no gain,
phase or timing parameter was fitted to the exported samples. Worst
relative complex error is `4.1690596838807094e-14`. The ordered per-port
bounded-capture identity digest is
`54cd64fd9189b4dfb5269d27f434694ee25cee516684c3390d6abc6ef7c04235`.
This strengthens E09's actual-waveform/clock/export evidence for one
CSI-RS observation; it does not qualify the complete capture, PDSCH/PUSCH
modulation, lab-file conversion or physical Keysight playback.

The slot-26 retained MAT artifact was also independently checked while the
primary CSV publication was still pending at 03:31 IST. Its filename is
`9d0f48dd5c1d6964f000b9c03b4240e313e637fc1d7441e484dee5381467a27d.mat`
under `air_interface/air_interface/mat/control_evm`, with file SHA256
`6f9f439d5e1ebfaae7ecb93b96130f16e1541bbdad02fecca5237e9b09fc8a7a`.
Its numeric trial identity is UE 1 / cell 1 / RNTI 1 / slot 26 / 40 dB.
All 559,104 pairs are finite, with unique sample indices on each of 64 ports.
Independent FFT/CP extraction of actual TX samples `[1536000,1597440)`
reproduces every measured pair, worst relative error
`4.169177704790387e-14`. The ordered bounded-capture identity digest is
`9baea860b52ab117ceafb807e2eab31d027f85769e388168d8a9609df96f2986`.
Pair `PortIndex` is zero-based; recorder file port ordinals are one-based,
as specified by their respective producers. Raw gain-inclusive pair error
is 59.017369--59.031315 percent, retaining PA backoff/gain rather than fitting
it away. This extends the actual IQ/export check to a second CSI period,
not a received CSI report, adaptive data grant, RF-conformance EVM or
completed publication claim. No new PHY execution or capture was generated.

The run subsequently published four PBCH CRC passes and successful SIB1
DCI/DL-SCH/ASN.1 checks. SSB index 1 is selected; acquisition became
available at slot 15 after the complete 7 ms observation. The PBCH CSV
SHA256 is `f282e85aaf30ddd795b5ee70acc0f8f8037a4a7306289e7b8fad4af5610748d5`.
Recomputing NMSE from each retained 144-by-4 complex Hest/Href pair matches
all four exported values. Recomputing paired-transmitted-reference EVM
also matches the separately identified decision-directed EVM in this
successful capture: SSB 0/1/2/3 are approximately 5.090/5.085/9.666/18.362
percent, with 432 symbols each. Such agreement must not be assumed for
other captures or converted into a transmitter-conformance claim. The
repaired CFO/timing-used flags and applied AWGN reference are present in
all four rows. Combined primary-row audit: 40 arithmetic passes, two CSI
synchronization-metadata passes, one unmeasured TRS EVM check, no arithmetic
mismatch. At this check the run was active at slot 16; PRACH, attachment,
connected data, adaptation and final artifact acceptance remained pending.

### 2026-10-17 physical CSI/UCI integration

`testH4100SharedCSIUCI` **PASS** on the unchanged 11-file production snapshot,
elapsed 3,508.87 seconds. Receipt:
`logs/lls_repairs/h4_csi_sync_physical_20261017_v1/receipt.json`.
Retained data:
`results/lls/h4_shared_csi_uci/20261017_010152_601/`.

The actual 100 MHz / 64-TX / four-RX CDL-C+RF receiver measured CSI at slots
6 and 26. Independently received PUCCH at slots 19 and 39 recovered 15/15
bits with CRC pass. Both reports had RI 2, CQI 14 and CRI 1; PMI was 20 then
18. Scheduler-accepted rank stayed 1 after the first confirmation and became
2 after the second. CSI alone did not activate a TCI state. The final CSI CSV
SHA256 is `f26520ae43117f0c6ce4cd302cf3f219a0c7197aef374c5e911cbbfbfc902511`;
12 operand-arithmetic and four per-plane synchronization metadata checks pass.

This is a 40-slot shared CSI/UCI component with declared preconnected access
and TAG inputs, not physical initial acquisition, an executed adaptive data
grant, a full 100-slot run or statistical UCI qualification. Its source
snapshot and scope are retained in `configuration.mat`/`received_evidence.mat`.

### 2026-10-17 publication follow-up

**171 affected Python checks pass** in
`logs/joint_evm_constellation_20261017_v2.xml`. This verifies production
materialization, live publication, filesystem cache invalidation and WebGUI
contract integration, not PHY performance. Ledger entries H4-78 through H4-80
record the reproduced defects and production repair in
`apps/lls_contract_materializer.py`:

- Preserve sweep/SNR/run/seed/attempt identities in EVM observations and CSVs;
  incomplete points cannot fill each other's missing samples.
- Keep every EVM profile point in its image, with explicit per-point series.
- Use one canonical raw receiver source for all five constellation views,
  including 1024-QAM; preview/report aliases do not add extra samples.
- Keep individual trial RMS EVM rather than averaging across operating points.
- Count paired-symbol error histogram samples rather than averaging unit
  counts; export exact errors and bin definitions for reconstruction. These
  errors are not hard-decision SER or RF-conformance EVM.

The regression set independently recomputes all 3,522 errors in a retained
receiver capture and checks plotted CSV/PNG lineage. Eight-point fixtures
exercise serialization only, not eight newly executed PHY operating points.
Earlier source evidence was not modified. The full 100-slot run and
statistical acceptance remain pending; this receipt does not close them.

`CONFIRMED_FIXED` is limited to the stated producer defect and executed fixtures; it does not imply an end-to-end scenario pass. `BLOCKED_WITH_EVIDENCE` includes an uncompleted required qualification or implementation: the blocker and next work are explicit. Tests not executed for an acceptance scope are `TEST_NOT_RUN`, even if an adjacent helper passed.

Class abbreviations below expand to: **IMPL** `IMPLEMENTATION_CORRECTION`; **EXPORT** `EXPORT_ONLY_CORRECTION`; **VERIFY** `VERIFICATION_ONLY`; **PROFILE** `SIXGR_PROFILE_CORRECTION`; **OPT-IN** `NEW_OPT_IN_CAPABILITY`. Proposed classes on unfinished rows are not claims of implementation.

All MATLAB test names below are reusable commands through:

```matlab
addpath('scripts'); runLLSRepairChecks('new_unique_label',{'testName'});
```

Use a MATLAB batch process with its working directory at the main repository. Do not change a running scenario's source or paths. New numerical receipts are under `logs/lls_repairs/<label>/receipt.json`; never count failed before/baseline reproductions as passing repairs. Original isolated evidence is preserved under `logs/lls_repair_consolidation_20261016` with its original source paths intact.

The affected-test list is `scripts/runLLSRepairRegression.m` (originally 44 tests; now 47, not testAll). All 42 original checks passed in the isolated final-source receipt. After consolidation and the receiver-delivery timing repair, **44/44 main-folder MATLAB checks passed**, including two additional timing checks; **82/82 Python export checks passed**. Main evidence is `logs/lls_repairs/main_consolidated_20261016_v1/receipt.json` and `logs/lls_repair_consolidation_20261016/python_main.xml`. Receipts record original paths; an isolated pass is not relabelled as a main execution. Earlier receipts are development evidence because a recursive-path issue could select archived test copies; they are retained, not overwritten. The retired copy is recoverable from the Windows Recycle Bin and `logs/lls_repair_consolidation_20261016/retired_copy_backup.zip`.

Additional main-folder checks passed: the physical **PUSCH-UCI variant** in
`logs/lls_repairs/main_pusch_timing_20261016_v1/receipt.json`, plus the resolved
100-slot manifest, exact scheduler-grant/TBS consistency and strict proxy guards
in `logs/lls_repairs/main_manifest_guards_20261016_v1/receipt.json`. These are
four additional affected executions, not closure of the historical 48-failure
list or all 35 audit items. The verified next-run manifest is
`logs/lls_repairs/next_run_fixture_20261016_195716_239/manifest.json`.

## All 35 items

Publication follow-up: four affected checks pass in
`logs/lls_repairs/packet_attempt_publication_after_20261016_v1/receipt.json`.
The final-source physical PUCCH and PUSCH variants also pass in
`logs/main_packet_publication_physical_20261016_v1.log`
(`PACKET_PUBLICATION_PHYSICAL_FINAL_SOURCE_PASS`). Independent CSV audits
pass 15/15 PUCCH and 30/30 PUSCH checks under the affected-check folder.
This closes the missing public live/final attempt-journal wiring defect;
it does not close full-run, loss/cancellation or reassembly qualification.

Transport-identity follow-up: the focused regression list now contains 47
checks (the original 44 plus two identity guards and one packet-delivery guard), and is not testAll. The 14
identity/reservation/replay checks in
`logs/lls_repairs/tb_identity_final_source_20261016_v1/receipt.json` all pass.
Two retained before-fix receipts reproduce contradictory TB aliases and a
shared RX/TX identity mismatch. A legacy negative fixture was also corrected
to declare its installed UE count; its original rejection assertions remain.
No historical result files were repaired or relabelled.

The expanded physical checks also pass on the repaired source: PUCCH in
`logs/lls_repairs/tb_packet_physical_final_20261016_v1/receipt.json` and the
PUSCH variant in `logs/main_tb_packet_physical_final_20261016_v1.log`.
The latter retains `physical_packet_sdu_delivery.csv`,
`physical_packet_arrivals.csv` and `physical_packet_harq_attempts.csv` in
`logs/lls_repairs/tb_packet_pusch_final_20261016_v1`.
Actual DL/UL CRC-confirmed payloads are 2088/2152 bits; delivery availability is
46095/76792 samples at 7.68 MSa/s in this narrow-band component fixture.
Application delivery remains false in metadata-only mode. These are not
100 MHz performance numbers or a multi-TB protocol-reassembly qualification.
The earlier physical attempt exposed missing allocator-epoch binding in the
component's pre-transmission grant; that fixture now copies its real allocated
epoch before freezing. Its failed receipt remains preserved.

Packet-delivery follow-up: `packet_first_success_before_20261016_v1`
reproduces lost first-success proof after a duplicate callback;
`packet_reassembly_before_20261016_v1` reproduces cross-UE application completion.
Both use the actual coded PDSCH output, not transmitted bits substituted at RX.
The production `applyPacketHARQReception` and `refreshApplicationPacketDeliveries`
reducers fix these paths and reject overlapping/gapped fragment coverage or
inconsistent decoder hashes. Five checks pass in
`logs/lls_repairs/packet_reassembly_after_20261016_v1/receipt.json`.
Two independently encoded, nonrepeating TB fragments complete one application
packet; repeat reconciliation does not duplicate delivered bits. The injected
duplicate/failed callbacks are not claimed as additional PHY trial samples.
Full shared-radio multi-TB/reordering/loss/cancellation qualification remains open.

Final fresh-process packet regression: **9/9 checks PASS**, including physical
combined PUCCH reception; the additional physical PUSCH-UCI variant also PASS.
`logs/lls_repairs/packet_delivery_final_20261016_v1/verification.json` records
the unchanged source hashes and terminal launcher exit code 0. The shared
DL/UL fixtures retain 2088/2152 CRC-confirmed payload bits, and deliberately
retain zero application delivered bits in metadata-only mode. No full scenario
or statistical campaign was run for this follow-up.

| ID / priority | Class and fixture | Actual producer → consumer | RCA / implemented or required change | Behavior / schema migration | Test evidence and closure / remaining work |
|---|---|---|---|---|---|
| F01 / P1 | IMPL. TB 4104/8976/5000, G 26712/57872/32212 | `phy/phycode/rateMatchLDPC`, `resolveCodingLayout` → `link/deriveCodingTrialMetrics`, DL/UL runners, `truth/runWaveformLinkBundle`, live stage exports | Position-map labels omitted encoder filler markers; encoded-length export used already rate-matched codeword length. Map now follows actual filler exclusion; counts derive per-CB selections. Repetitions reproduce 4616/10400/6660, not inserted constants. | Coded output unchanged; position-aware combining can change because its map is repaired. `LDPCSelectionAccounting/v2`; inherent 2Z puncturing separate. | **CONFIRMED_FIXED for tested selection/accounting**. `testLDPCAccountingEvidence` failed before and passes after; both BGs, all RVs, finite Nref, short/repeated output. `testCodingLayoutContracts`: 100 noiseless round trips pass. Full UCI-multiplexed PUSCH/HARQ matrix remains TEST_NOT_RUN. |
| F02 / P1 | EXPORT. Same three segmented TBs plus unsegmented/multiple CW | `resolveCodingLayout` → `deriveCodingTrialMetrics`, `codingAccountingExport`, DL/UL and live exports | Padding arithmetic included CB CRC. Now sum actual filler, CB CRC and K×C separately per codeword. | Export-only; no encoder modification. New CBCRCBits, CodeBlockInputBits, SegmentationOverheadBits. | **CONFIRMED_FIXED**, `testLDPCAccountingEvidence`, `testCodingLayoutContracts`, `testPDSCHSISORegression` PASS. Receiver scalar/multiple-CW broader regression remains bounded by these fixtures. |
| F05 / P1 | EXPORT. Two competing UEs / one selected grant | `l2/mac/SchedulerPF` → candidate/grant trace consumers | Candidate rate used probe PRBs while estimated TBS was overwritten with final TBS. Probe/final counts, rates, denominator and PF basis now separate. | PF selection unchanged. `SchedulerCandidate/v2`; legacy rate agrees with legacy final TBS. | **CONFIRMED_FIXED**, `testSchedulerProbeFinalAccounting` PASS; selected/unselected rows and PF argmax preserved. |
| F07 / P1 | EXPORT. DL/UL QPSK,16/64/256-QAM hard decisions | `deriveModulationTrackingMetrics` → DL/UL, live tables, `exportLLSReportingBundle`, Python materializer plots | Hard-decision residual was named interference. New exact error/reference energy, count, symbol-power and ratio fields; plots use residual semantics, not external interference or dBm. | Receiver arithmetic unchanged. Legacy field remains compatibility only; exact zero residual may be −Inf. | **CONFIRMED_FIXED for named residual export**, `testReceiverDiagnosticDefinitions`, `testModulationTrackingExecutedWork`, Python availability checks PASS. Independent inter-layer leakage is NOT supplied by this metric. |
| E01 / P1 | EXPORT. False applied flag with absent feedback; bootstrap-only rows | `runWaveformLinkBundle.localRepairLinkTrialEvidenceColumns`, `analytics/applyTrialMeasurementPhase` → canonical live/primary CSV | Phase was computed before causal evidence reconciliation. Recompute after repair; canonicalizer reconciles bootstrap from the same row only. | No state/grant/rank/MCS change. Old rows not rewritten from future CSI. | **CONFIRMED_FIXED for this ordering/schema defect**. `testLLSBootstrapEvidenceCSV`, `testTrialMeasurementPhase` PASS. Full access-to-adaptive runtime is TEST_NOT_RUN. |
| E02 / P1 | EXPORT. Actual segmented TX/RX converter and AGC captures | `summarizeSharedRFEndpoint`, `bindSharedRFExecutionEvidence` → control/data RF columns | Metadata-only return omitted stage counts; mixed-segment booleans lacked explicit coverage. Counts now bound before early return; interval/any/all segment audit retained. | No RF operator change. Unknown/time-varying counts remain NaN, not zero. | **CONFIRMED_FIXED for compact counts/coverage**. `testSharedAGCConverterMeasurement` PASS including cropped sample populations and metadata-only/full equality. Per-sample impairment qualification remains separate. |
| E05 / P1 | EXPORT. Missing beam/PMI/SINR definitions with available status | `canonicalizeLLSLiveSignalChainTable`, `measurementValuePresent` → Python materializer | Descriptive companions/sentinels were treated as values. Known fields now require actual values; scalar PMI versus matrix hash statuses separate. | No invented zero/PMI/measurement. MATLAB and Python corrected known contradictions; contract v2. | **BLOCKED_WITH_EVIDENCE**: focused MATLAB test and 3 Python tests PASS; full producer-specific measurement-plane schema and constellation embedded-vs-archived sample counters still require verification. |
| E06 / P1 | EXPORT + IMPL identity binding. 4 attempts,1 frame,4 logical ACKs,2 occasions,5 information bits | `exportLLSLiveDerivedTables`, `summarizeHARQPhysicalPopulations`, standalone SR/receiver-only completion in `CoupledTruthRuntime` → HARQ CSVs | Frame count used row count. New separate counters; logical/physical identities deduplicated independently. Physical test additionally exposed missing occasion IDs on standalone/receiver-only PUCCH rows; now bound from existing frozen context key. | Counts/reporting only; receiver-only is not transmission. `HARQPhysicalPopulations/v2`. Conflicting duplicate widths rejected. | **CONFIRMED_FIXED for these populations**. `testHARQPhysicalPopulationAccounting`, `testLLSHARQFailureRateTruth`, physical `testRuntimeHARQFeedbackPhysicalPublication` PASS after repair. Counts are physical PUCCH, not PUSCH-UCI occasions or coded-bit totals. |
| ID01 / P1 | IMPL + EXPORT. Retx/process reuse/constellation | `CoupledTruthRuntime`, `resolveGrantTransportBlockIdentity`, `validateExecutedHARQPayload`, `validateSharedDataReceptionTX` → HARQ/packet joins and `bindTransportExportIdentity` | In addition to the ordinal export defect, negative tests proved contradictory logical aliases and replaced RX TB identity were accepted. Core now reconciles all populated aliases, allocates a namespaced ID only before new-data preparation, forbids MAC/current-attempt fallback at reservation/delivery, and compares RX logical TB/retained epoch to actual TX. | Existing logical IDs unchanged; new IDs use `logical_tb:`. Attempts remain separate. Legacy inputs with no epoch do not qualify epoch behavior. No payload/rank/MCS change. | **BLOCKED_WITH_EVIDENCE overall; named core identity defects fixed**. Fourteen affected final-source checks PASS in `tb_identity_final_source_20261016_v1`, including before/after reproduction, no-mutation negatives and retained DL/UL replay. Connection/config epoch migration and full duplicate/stale/reordered physical matrix remain open. |
| ID02 / P1 | IMPL partial. Historical UE ID versus current C-RNTI4660 | `CoupledRadioIdentity`, `CoupledTruthRuntime`, `matchPacketTransportBlock` → packet/SDU joins | Delivery now uses stable UEIndex and frozen radio/cell/process/NDI epoch. A further reproduced defect counted another UE's same-labelled packet when assigning segment numbers; reservation now includes UE and application ID. Packet IDs still lack explicit session/config epoch. | Preserve historical RNTI; no mutable current-RNTI lookup at SDU reception. Typed reattachment/session bindings with effective sample still required. | **BLOCKED_WITH_EVIDENCE overall; fragment ownership repaired**. `packet_fragment_owner_before_20261016_v1` fails on cross-UE segment numbering; after-repair four checks PASS. Full reattachment and time-namespace regression TEST_NOT_RUN. |
| I08 / P1 | IMPL + EXPORT. 3km/h trajectory; repeated consumers; delayed receiver row | `CoupledTruthRuntime.advanceFrameImpl`, new `advanceMobilityClock`, `bindPositionClock`, `preserveServingGeometry` → serving trace | Mutable scheduling cursor doubled as physical clock; delayed results overwrote historical geometry. Independent monotonic owner and immutable prior geometry now used. | Can change physical trajectory where old cursor skipped/doubled evolution; adds validity/snapshot clocks and version. No historical interpolation. | **BLOCKED_WITH_EVIDENCE for full acceptance**. Helper PASS; production eight-slot owner test PASS. Old per-slot test FAIL identically on untouched baseline because it demands applied Doppler without constructing channel. Full access transition/sweep-reset execution remains TEST_NOT_RUN. |
| I04 / P1 | IMPL/EXPORT partial. CRC-mapped SDUs versus real application bytes | `CoupledTruthRuntime.updatePacketDeliveryFromHARQ` → `applyPacketHARQReception`, `refreshApplicationPacketDeliveries`, `protocol/WaveformProtocolBridge` → SDU/app tables | Reproduced and fixed duplicate callbacks erasing first decoder proof, plus application matching by packet label without UE ownership. The reducer now preserves first-success proof, publishes latest-attempt status separately and validates exact fragment coverage/hash binding before completion. | `DeliveryEvidenceMode` names the contract, not a success flag. New `LastAttemptProtocol*` columns are distinct from first-success fields. No metadata promotion to application delivery. | **BLOCKED_WITH_EVIDENCE overall; named defects fixed**. Two-TB actual noiseless PDSCH → strict protocol/SDU reducer → one application completion PASS; cross-UE, overlap and wrong-hash negatives PASS. Full shared-radio multi-TB/reorder/loss/cancel/reassembly qualification remains open. |
| F04 / P1 | EXPORT + IMPL. 7ms→19.5ms versus13ms; receiver availability114 samples after nominal slot end | `deriveInitialAccessProcedureDelay`; `harqFeedbackReceiveTimingFields` → `CoupledTruthRuntime` HARQ timeline, delivery helper and first-success SDU ledger | Access inclusive extent now separate. Core previously copied only TX timing into the HARQ row and delivered packets at nominal slot end. It now carries validated receive timing and uses receiver-result availability for delivery; shared execution rejects missing timing. | `AccessTiming/v2` distinguishes13ms/12.5ms. Delivery adds sample/rate/source, availability-slot and explicitly nominal attribution fields. It does not claim hardware decoding latency: source contract retains ProcessingBudgetIncluded=false. Nonshared legacy timing is explicitly nominal, never measured. | **BLOCKED_WITH_EVIDENCE for complete packet acceptance; core handoff repaired**. Physical PUCCH/PUSCH checks now cover production traffic enqueue → actual TX reservation → actual DL/UL decoder → SDU first-success timestamp and CSVs, not only the timing helper. Metadata-only application delivery remains false. Full multi-TB SDU/reassembly acceptance remains open. |
| F06 / P1 | IMPL/EXPORT partial. Scheduled-but-not-delivered SDUs | `allocatePacketSegmentsToGrant`, `refreshApplicationPacketDeliveries`, `reconcilePacketHARQAttempts`, `reconcilePacketBitConservation` → packet delivery/conservation exports | RemainingBits means unscheduled bits. Attempt counts were updated only at full application completion and summed per fragment. Core refresh now counts distinct receiver-completed TB attempts and partitions committed segment ranges into disjoint states. Missing receiver outcomes cannot establish a drop; transmitter release is distinct from application drop. | `packet_bit_ranges/v1`; range offsets and seven disjoint counters reconcile to offered bits. Retries do not reserve twice, and first-success proof survives later failures. The common publisher is integrated into public live/final publication; it writes the actual HARQ attempt journal before derived packet counters, including timeline-only and known-empty cases. | **BLOCKED_WITH_EVIDENCE overall; attempt/range reducers repaired**. MAC reservation/retry/DTX/false-ACK/cancellation negatives, two actual noiseless PDSCH fragments and independent DL/UL CSV audits pass. `testPacketLedgerRuntimePublication` now passes with live/final, missing/empty and timeline-only cases. Four final-source affected checks and physical PUCCH/PUSCH publication variants pass; see the publication follow-up below. Full shared-radio cancellation/drop/reassembly and full-run acceptance remain open. |
| I01 / P1 | IMPL/VERIFY. CSI pre/post-front-end versus scoring planes | `phy/refsig/receiveCSIRSWaveform`, `truth/buildIndependentCSIRSTrialRow`, shared CSI completion → measurement/CSI/CSV consumers | Post-front-end timing/CFO previously synchronized the separate antenna-plane samples. Actual RX CFO/timing toggles reproduced a power change with unchanged antenna samples. Each received plane now synchronizes independently; practical post-front-end CSI is unchanged. | Separate measured pre/post timing, CFO, sample count, source and clock-domain fields; no clean scoring H fed to the receiver. Typed empty CSV schema preserved. | **FOCUSED FIX VERIFIED; integrated acceptance open**. Isolated/combined RF toggles, reference-amplitude/metadata poisoning and shared CSV tests PASS; native 273-PRB 64x4 CDL/RF component PASS in `csi_h4_cdl_rf_after_20261017_v1`. Retained-capture replay preserves CSI bits/RI/PMI/CQI when antenna reference amplitude changes. Current-source physical CSI-UCI two-report check and full100-slot acceptance remain pending. |
| I02 / P1 | VERIFY. Raw35.626dB/final33.119dB successful QPSK | `deriveModulationTrackingMetrics`, post-EQ SINR bound → scheduling/measurement consumers | Decision residual is not independent of EVM when decisions are correct. Named diagnostics now distinct; no asserted estimator-formula bug. | Receiver reference remains hard decisions; offline TX poisoning cannot alter its residual. | **BLOCKED_WITH_EVIDENCE**. `testReceiverDiagnosticDefinitions`, `testPostEqSINRResidualBound` PASS. Multi-layer error-transition/RF-toggle calibration TEST_NOT_RUN. |
| F08 / P2 | EXPORT. Coarse-H reconstruction error/std versus loss/sensitivity labels | `deriveModulationTrackingMetrics.localTrackingMetrics` → diagnostics export and live stages | Existing interpolation diagnostic is Hest-vs-coarsened-Hest error ratio; sensitivity field is channel magnitude standard deviation. Added names, formula descriptions, energies/count. | No channel-estimator change. Legacy fields retained, not calibrated loss claims. | **CONFIRMED_FIXED for diagnostic definitions**, receiver diagnostic/zero-reconstruction tests PASS. No matched receiver-performance sensitivity experiment claimed. |
| E08 / P1 | EXPORT + pending qualification. 31.488dBm hypothetical value; relative CSI power | `buildLargeScaleStateCache` → `bindServingPowerEvidence`, serving/measurement traces, `exportLLSEnergyDiagnostics` | Large-scale score leaked into receiver-labelled RxPower. New model-specific field; normalized-mode compatibility absolute field empty. Energy consumer also incorrectly accepted relative CSI/per-RE RSRP as total RX dBm; aliases removed. | Cell selection/PHY scale unchanged. Model power remains explicitly model-only. Absolute measurement still requires actual calibrated plane. | **BLOCKED_WITH_EVIDENCE** overall. `testServingPowerPlaneEvidence`, `testLLSEnergyEvidenceIntegrity` PASS. Calibrated absolute-power fixture and downstream power-control/coverage audit TEST_NOT_RUN. |
| S01 / P1 | PROFILE/VERIFY. Existing successful bounded RA/RRC | `mac/ra` codecs, `l3/rrc18/RRCConnectionEstablishment`, `phy/ra/buildRRCConnectionEvidence` → access control/state/export | Bounded connection profile must not imply complete MAC/RRC. Trace contention identity, decoded/preconfigured SI, search space/timers within selected profile. | Preserve successful access; no forced slot35/40 attach deadline. | **PROFILE_DEPENDENT**. Full profile-specific contention/retry/identity regression TEST_NOT_RUN this patch. No upgrade to complete NR attachment claimed. |
| S02 / P1 | VERIFY. MCS16/17 SE transition; exact TBS | `pdsch/PDSCHMCSResolver`, `phy/ul/pusch/PUSCHMCSResolver`, `computeResourceAccounting`, TX chains → grants/decoder | SE need not be monotonic across constellation transitions; TBS estimate and actual RE/G are separate. No table monotonicity repair applied. | Keep installed profile and capability checks; retain reserved-index rejection. | **PROFILE_DEPENDENT**. `testPDSCHMCSResolver` PASS against installed toolbox tables. Full UL/transform-precoding/TBS-boundary matrix TEST_NOT_RUN in this patch. |
| S03 / P1 | VERIFY. TA32 versus total1632 samples | `resolveRARTimingAdvance`, `receivedRARTimingOnTraceClock`, `TimingAdvanceGroupState` → timing trace/UL | Absolute RAR, relative commands, NTA+offset and sample-clock conversions are distinct. Numerical difference alone is not defect. | No command/PHY timing changed. Keep unit and effective-time provenance. | **PROFILE_DEPENDENT**. `testRARTimingTraceUnits` PASS; full TAG/relative-command/effective-sample matrix TEST_NOT_RUN. |
| I06 / P1 | IMPL + VERIFY. Received-report confirmation ownership | `CoupledTruthRuntime.applyLinkAdaptationToCSIReport` → CSI/SRS consumer → future scheduler grants | Negative checks reproduced duplicate CSI and SRS callbacks counting as fresh rank confirmations. Core now deduplicates report/occasion identities and rejects older-source or backward-delivery events before ILLA/rank state mutation. OLLA remains HARQ-owned. | No forced rank/MCS or confirmation bypass. `AdaptationDeliveryStatus` distinguishes ignored callbacks from accepted delivery. The two-report confirmation is the configured SixGR policy, not a claimed mandatory NR algorithm. | **BLOCKED_WITH_EVIDENCE overall; named consumer defects fixed**. Seven affected checks PASS in `adaptation_delivery_final_20261016_v1`; DL/UL duplicate and stale guards preserve accepted quality/rank/age, and OLLA exclusion passes. Full physical duplicate/stale/reordered feedback and bootstrap-exit loop remains open. |
| I07 / P2 | VERIFY. TRS updates and receiver correction stages | `runTRSTracking`, `PDSCH_Rx`, `PUSCH_Rx`, RF streams → timing/frequency evidence | Arithmetic injected−applied is not measured residual. Need per-window estimator quality/reuse and effective-sample ownership. | No extra correction after aligned window; no estimator changes here. | **BLOCKED_WITH_EVIDENCE**. Signed CFO/phase/chunk boundary and post-correction residual suite TEST_NOT_RUN. |
| I03 / P2 | IMPL partial. ~48MB paired-sample JSON per CSI row | `completeSharedCSIRSReception` → `retainControlEVMPairs` → `readControlEVMPairs`/`exportControlEVMSamples`; physical observation ownership | CSI rows retained full paired-sample JSON through repeated live snapshots. They now retain immutable MAT path/checksum/count bindings; every sample stays available. Physical capture duplication remains a separately scoped concern. | Versioned lossless detail storage, legacy inline reader, unchanged expanded CSV; missing/corrupted/misbound files reject even on cache hits. No CSI estimator, channel, RF or scheduler change. | **BLOCKED_WITH_EVIDENCE overall; inline retention fixed**. Actual shared completion, 25/273-PRB roundtrip, CSV identity and corruption checks PASS; full-band 64-port live row 90.4MB→5.4KB with all559104 pairs retained. Full-run peak memory/exclusive-stage qualification still pending. |
| I05 / P2 | VERIFY/OPT-IN. Two legal126PRB spans | SSB reservation and `SchedulerPF`, DCI RIV encoding/reconstruction → allocation traces | One contiguous126PRB span is valid for contiguous RIV, not proof of lost252PRB support. | Export reservation/symbol scopes and limiting reason; only opt into legal reconstructible noncontiguous allocation. | **PROFILE_DEPENDENT**. `testSSBPRBSymbolReservation`/DCI roundtrip expanded-span coverage TEST_NOT_RUN here. No unsafe RIV expansion made. |
| I09 / P1 for energy claims | IMPL/PROFILE. Energy populations, clock and overlapping endpoints | `resolveLLSEnergyModelConfig`, `exportLLSEnergyDiagnostics`, RF EnergyModelBS/UE → joule/bit-per-joule summaries | Fixed control bits being included in delivered data and absolute Slot receiving a second frame offset. Different configured RF-chain and physical-element counts are not inherently contradictory. The current aggregate still sums overlapping per-channel energy rows. | Retain watts as engineering-model inputs. Replace per-channel sums with authoritative endpoint event/state integration, charge static/PA once and bind the unique receiver-delivery denominator. Whole-slot model intervals are now explicitly distinguished from measured RF active intervals. | **PARTIAL**. Four checks PASS in `energy_payload_clock_affected_20261016_v1`: energy evidence, causal KPI events, physical power units and numerology callers. H4 slot47 starts at23ms rather than43ms; zero-/one-based clocks reconcile and contradictions reject. Endpoint-union energy and hardware-architecture qualification remain open; no qualified energy-efficiency claim. |
| F03 / P2 | EXPORT.18144gross/4536DMRSreservation/252PTRS/13356data | `computeResourceAccounting`, new `summarizeResourceSets`, modulation diagnostics → DL/UL raw and live exports | Added union-based carrier-plane data/pilot counts and separately named gross-allocation and data-plus-pilot fractions. CDM holes are not occupied DMRS. | `ResourceSets/v2`. No mapping/TBS change; unoccupied is explicitly relative to this channel, not idle airtime or absence of another signal. | **CONFIRMED_FIXED for exact-set denominators**. `testResourceSetDenominators` PASS; `testResourceAccountingExact` PASS: 200 DL + 200 UL cases, 16 rank/modulation pairs each, direct toolbox G/TBS comparisons. Impossible two-port fixture indices repaired without changing its intended count. |
| M01 / P1 | IMPL/VERIFY proposed. Signal-present and empty PRACH occasions | `phy/prach/scorePRACHDetection`, PRACH campaign → detection statistics | Scorer separates receiver result from TX scoring metadata; population must be independent occasions, with wrong/multiple preambles and no-signal trials. | Keep TX preamble out of detector; preserve denominator/status for every trial. | **BLOCKED_WITH_EVIDENCE**. Full empty/no-signal/multi-preamble confidence campaign TEST_NOT_RUN. One detected preamble is not a qualified false-alarm rate. |
| M02 / P2 | VERIFY/OPT-IN. Signed timing | `rf/runtime/RFImpairmentStream.validateStatefulStages` → retained RF timing stream | Existing retained stream explicitly rejects negative or fractional timing without a clock bridge. This is safer than silently implementing advance as delay. | No new advancing-clock capability added; keep explicit rejection. | **PROFILE_DEPENDENT**. Signed/negative guard execution test TEST_NOT_RUN in this patch. Full clock bridge remains new capability. |
| E03 / P2 | IMPL/EXPORT. Repeated successful TB counted again | `CoupledTruthRuntime.completeSlotImpl`, `kpi/creditTransportGoodput`, `kpi/transportGoodputBits`, `exportLLSLiveDerivedTables.localBuildSymbolThroughputTable` → runtime/user/symbol goodput | Reproduced one 800-bit TB credited as1600 bits after two successful attempts. Runtime completion and symbol export now use a common first-CRC-success ledger, scoped by logical UE/direction/TB and retained experiment/session identity. Original per-attempt values remain explicitly named. | Validate stored credits against original CRC, size and key; never infer identity from attempt/slot. Symbol rates remain apportioned TB metrics, not symbolwise decoding or application delivery. | **CONFIRMED_FIXED for runtime/symbol duplicate credit**. Five accounting/clock/packet checks pass; the stricter contract and four existing KPI guards pass in separate receipts. Actual shared PUCCH/PUSCH completion/publication passed, then current guards accepted retained DL2088/UL2152-bit physical rows. Full100MHz, standalone link-runner semantics and application-throughput acceptance remain open. |
| E04 / P2 | EXPORT/VERIFY.3HARQ+1SR, not4HARQ | `PUCCHConfigBuilder.planCombined`, scheduled reception, `runPUCCHWaveformTrial`, runtime completion → UCI tables | ReceiverExpectedHARQ/SR/CSI fields exist; primary UCIType alone is insufficient. Need TX/RX typed ordering and logical bit associations preserved at every exporter. | No extra CRC for short UCI; no forced CSI into ineligible occasions. | **BLOCKED_WITH_EVIDENCE**. Physical combined regression rerun in profile batch; all typed field-role/absent-CSI/missed-DCI permutations not rerun. |
| E07 / P2 | EXPORT. Mixed slot10DL/2flex/2UL versus explicit guard | `FrameStructureEngine.SlotPartitionFromState`, new `summarizeSlotSymbolRoles`, `CoupledTruthRuntime` → slot trace/run state | Summary omitted unresolved common flexible symbols. Actual resolved role map now exported with explicit flexible/guard/unused/reserved counts. | `SlotSymbolRoles/v2`, zero-based JSON array. No scheduler changes; unknown roles reject rather than become schedulable symbols. | **CONFIRMED_FIXED for summary coverage**. `testSlotSymbolRoleEvidence` PASS; production slot-entry `testLLSMobilityRuntimeOwnership` verifies all14 roles. Full special-slot waveform regression TEST_NOT_RUN. |
| E09 / P1 before hardware claim | VERIFY.61440×64,122.88MSa/s first composite0.5ms | `exportRuntimeTxIQCapture`, `phy/research/exportLabIQ` → CSV/MAT/int16/Keysight | Short record and repeated port hashes are not automatically incorrect. Existing exporter has common normalization and int16 error bounds. | No waveform replacement, per-port renormalization or implicit repetition. Canonical MAT/CSV and WIQ/VSA-MAT remain separate formats. | **BLOCKED_WITH_EVIDENCE** overall. `testRuntimeTxIQCapture` and `testCoherent64PortIQRoundtrip` PASS for complete 1024-sample fixtures, common scale, all64 file hashes, float/CSV/int16/single roundtrips and deliberately equal ports. Actual retained61440 capture clock/RF-stage handoff and hardware playback remain unverified; physical capability UNKNOWN. |
| ID03 / P1 | VERIFY/EXPORT proposed.2panels×4×4×2pol=64 | `ran1_h4_64txru_4rx.yaml`, ChannelFactory, frozen precoder/TCI exports → spatial trace | Existing YAML separates physical panels from four logical CSI ports. Compact trace omits full geometry/matrix basis. | Preserve valid16-active-element bootstrap and taper; export basis, normalization, RF/layer mapping and received TCI effective sample. | **BLOCKED_WITH_EVIDENCE**. Complete requested→decoded→mapped→applied beam/TCI matrix acceptance TEST_NOT_RUN here. |
| ID04 / P1 for reciprocity | VERIFY. CDL-C average PDP/100ns; no-geometry delay | `ChannelFactory`, `CoupledWaveformStream`, `buildChannelImpulseResponseTable` → channel manifests/CSV | Average PDP is model metadata, not instantaneous coefficients. Geometry delay and actual executed reference differ legitimately; avoid second reciprocal swap. | No propagation/angle/profile changes made. Need realization/segment/observation identities and actual coefficient comparison. | **BLOCKED_WITH_EVIDENCE**. `testH4RuntimeDopplerAuthority` actual native64x4/4x64 short-channel check PASS; full chunk-equivalence/reciprocity/delay/orientation acceptance TEST_NOT_RUN. |

## Additional findings

Unique transport-goodput repair: `unique_transport_before_20261016_v1`
reproduces800 bits credited as1600 after two CRC-successful attempts of one
TB. `unique_transport_affected_20261016_v1` passes five accounting/export/
clock/packet checks. The actual shared PUCCH and PUSCH variants completed in
`logs/main_unique_transport_physical_20261016_v1.log` with
`UNIQUE_TRANSPORT_PHYSICAL_FINAL_SOURCE_PASS` and a five-file frozen-source
hash receipt. The subsequent stored-credit guard repair reproduces and rejects
altered size, CRC and identity in `unique_transport_contract_before_20261016_v1`
and `unique_transport_contract_after_20261016_v1` (four PASS).
Four existing KPI guards pass in `goodput_kpi_adjacent_20261016_v1`.
The current guards also accept the retained actual DL2088-bit and UL2152-bit
rows without changing their CRC or contents. This is a post-hoc contract
check, not another PHY execution or statistical population. The explicit
affected list now has59 tests; that inventory is not an all59-pass receipt.

Energy follow-up: `energy_payload_clock_before_20261016_v1` reproduces the
control-payload denominator defect. The production exporter now excludes
control bits from data delivery and uses the absolute slot clock without a
second frame offset. Four related checks pass in
`energy_payload_clock_affected_20261016_v1`, including30kHz slot47=23ms,
explicit index-base conversion and conflicting-clock rejection. The separate
endpoint-overlap energy problem remains uncorrected; nominal whole-slot
model rows are not renamed measured active intervals.

2026-10-17 energy denominator follow-up: the retained before-fix receipt
`energy_crc_identity_before_20261017_v1` proves a `Status=PASS, CRCPass=0`
row was incorrectly credited. `exportLLSEnergyDiagnostics` now consumes
the same receiver-owned `creditTransportGoodput`/`transportGoodputBits`
contract as the shared runtime. It preserves repeated-success zero credit,
scopes same-labelled TBs by UE/direction/sweep and no longer manufactures
connected TB IDs from MAC/SDU/grant/slot labels. Missing CRC or identity makes
the denominator unknown; a qualification FAIL does not erase a real CRC pass.
The independent fixed-link producer is separately identified by its declared
no-HARQ Monte Carlo hierarchy (point/drop/trial/seed), not by a connected
attempt index. Eight targeted checks PASS in
`logs/lls_repairs/energy_crc_identity_final_20261017_v1/receipt.json`.
An older causal-KPI fixture now explicitly declares its single logical UE;
its original 1000-bit denominator assertion is unchanged.

The new exporter also consumes the retained actual DL2088-bit and UL2152-bit
receiver CSVs from `unique_transport_pusch_20261016_v1`, obtaining4240 bits.
Input checksums are unchanged; post-hoc output and source hashes are under
`logs/lls_repairs/energy_actual_receiver_rows_20261017_v1`.
No extra waveform samples or statistical population were created.
**I09 remains PARTIAL:** joules still sum per-channel whole-slot models;
authoritative endpoint-state/resource integration, observed-versus-sleep
coverage and paired energy-saving baselines are not qualified.

Read-only retained-v5 audit while the full-band CSI component runs:
`logs/lls_repairs/retained_full_audit_20261016_v1/trial_arithmetic.csv`
contains 194 passing operand reconciliations and six not-evaluated rows
(PRACH EVM/NMSE, SRS EVM and three TRS EVM rows). These missing receiver
metrics must not be replaced with transmitter-pair EVM or a pilot-fit score.
All six archived DL complex channel-resource scores reconcile in
`channel_resources.csv`; this proves archived arithmetic/identity, not
estimator accuracy, RF coverage or a BLER population.

F06 is now reproduced independently by the reusable
`apps/audit_lls_measurement_catalog.py --packet-conservation` mode.
`packet_conservation.csv` has 299 passing counter comparisons and one failure:
`DL_ue1_frame1_pkt1.HARQAttemptCount=0`, although six distinct executed grant
identities own its received SDUs. Root cause: `refreshApplicationPacketDeliveries`
updates that counter only at full protocol application completion and skips it
entirely in metadata-only mode. The repair now updates attempt accounting
independently of application completion and counts each receiver-completed TB
attempt once, even if one TB holds several fragments; summing fragment callback
counts was insufficient. Its 45136 scheduled bits consist of 40136 CRC-mapped bits and
5000 pending bits; its remaining 2954864 bits are **unscheduled**. Application
delivered bits correctly remain zero. The UL packet has 7824 reserved bits and
no completed attempt in this snapshot. Historical files remain unchanged.
Nineteen Python audit regressions pass in `packet_audit_python_20261016_v1.xml`,
including absent/duplicate attempt evidence and cross-UE ownership negatives.
This is diagnostic coverage, not a claim that the MATLAB F06 repair is complete.

The new production reducer is integrated into `refreshApplicationPacketDeliveries`
before its protocol-disabled, pending and already-delivered branches. The exact
runtime defect fails in `packet_attempt_runtime_before_20261016_v1`; the reducer,
runtime binding, stable TB ownership and receiver-timing checks pass in
`packet_attempt_runtime_after_20261016_v1`. That batch also exposed the expected
stricter orphan-SDU rejection in an existing negative fixture. The fixture now
requires that rejection, without weakening the delivery/coverage assertions.
It and delivery-accounting, latency and DL/UL tentative-cancellation checks pass
in `packet_attempt_guard_repaired_20261016_v1` (**eight distinct affected tests**
across the two receipts). The two actual noiseless PDSCH fragments retain exact
decoder proof; injected callbacks are not counted as extra PHY evidence.
The count is explicitly **completed receiver attempts**, not all started TXs or
feedback messages. These count fixes preserve delivered/remaining/queued bit values.

The subsequent range repair is implemented in `reconcilePacketBitConservation`
and integrated into the same production refresh. `packet_ranges_integrated_20261016_v1`
passes four checks, including actual two-fragment PDSCH decoder proof and HARQ
transmitter lifecycle. A new terminal-clock negative exposed malformed assertion
arguments; the guard now supplies a proper error ID/message and its rerun passes
in `packet_ranges_negative_guards_fixed_20261016_v1`. Declared MAC events are
explicitly not waveform measurements or statistical evidence.

`packet_ranges_publication_20261016_v1` verifies the new common publisher for
both DL and UL; its independent `dl_csv_audit.csv` and `ul_csv_audit.csv` each
contain 15 passing arithmetic/identity checks. Twenty-two Python regressions
pass in `packet_ranges_python_20261016_v1.xml`. The public live writer still
omits these ledgers, reproduced in `packet_runtime_publication_before_20261016_v1`.
The frozen CSI physical gate subsequently finished successfully, after which
`CoupledTruthRuntime.writeTablesImpl` and `writeLiveStateTablesImpl` were wired
to the common publisher. The first integration test exposed a missing installed
sweep point in its declared-MAC fixture and malformed error-message arguments
in `captureHARQTransmitterLifecycle`; the fixture now installs its point and the
production guard rejects with its intended error ID, not a MATLAB formatting
error. No missing-identity guard was weakened. All three affected checks pass in
`packet_runtime_publication_guards_20261016_v1`; its `final_csv_audit.csv` has
30 passing DL/UL published-counter checks. Actual shared PUCCH/PUSCH follow-up
is tracked separately in `logs/main_packet_publication_physical_20261016_v1.log`.

An additional E06 producer defect was found in the runtime process summary:
`buildHARQSummary` still assigned `height(slice)` to `FramesObserved`, although
the other exporter had already been repaired. The extended public runtime
test reproduces this in `runtime_harq_frames_before_20261016_v1`; it passes in
`packet_runtime_publication_after_20261016_v1` after reusing the common population
counter and adding `TransportAttemptsObserved`. Four attempts in one frame,
two independent sweep/frame keys, and missing-frame identity are checked.
CRC success remains distinct from an independently received ACK. The same
batch's publisher fixture failed as described above; it is not an all-pass
receipt.

This repair changed the separate packet-delivery reducers, not the running
CSI-only component's call path. Its six frozen source hashes were rechecked and
remain unchanged. No second full-band scenario or testAll was launched.

Follow-up verification in main: all five checks in
`adaptation_adjacent_repaired_20261016_v1/receipt.json` pass. Duplicate feedback
also retains the accepted outage-recovery counters in the returned report,
without changing scheduler state or emitting a new MCS. The bounded physical
PUSCH/CSI/UCI check passed in `adaptation_delivery_physical_20261016_v1` before
that report-telemetry follow-up; it is not relabelled as a full current-source
H4 acceptance result.

I03 storage repair: the retained three-row CSI CSV has 145761080 bytes, with
about 48 MB of `ControlEVMSamplesJSON` per row. `completeSharedCSIRSReception`
now calls `report/retainControlEVMPairs`; `exportControlEVMSamples` reads the
checksum-bound exact MAT detail using `readControlEVMPairs`. No paired samples
are removed and the legacy/new expanded CSV is byte-identical in the bounded
comparison. `csi_detail_before_20261016_v1` reproduces inline retention;
`csi_detail_after_20261016_v1` passes actual shared CSI reception plus lossless
25/273-PRB storage tests. Full-band 64-port storage retains 559104 paired values,
with live row bytes reduced from 90367383 to 5417. Detailed benchmark:
`logs/lls_repairs/evm_detail_20261016_211803_849/storage_measurements.csv`.
This closes that retention path only: full-run exclusive-time/peak-memory
qualification and other overlapping channel-reference paths remain open.
The explicit affected list now contains 57 tests including the packet-attempt,
range, public-writer and timing/channel checks, not testAll; adding a test does
not claim all 57 were rerun or passed.

`timing_channel_affected_20261016_v1/receipt.json` passes three existing focused
checks on main. S03: received RAR command application time, TA versus capture
extraction, native SRS correlation with two pre-roll windows, delayed samples,
stale pilot state and TAG expiry are verified; relative-command/full RA coverage
is still not claimed. ID04: actual two-port TDL-C/CDL-C idle chunking matches
monolithic execution and rejects finite-snapshot CDL repartitioning; this is not
64-port reciprocal-channel qualification. I07: 12 actual DL/UL decodes with
430-Hz CFO retain identical receiver outputs when injection-audit metadata is
zero, wrong or absent; aligned captures avoid a second timing shift. Same-window
residual estimation remains explicitly labelled estimator consistency, not an
independent post-correction measurement. Signed-CFO/RF-transition coverage remains
open. These tests did not alter the frozen full-band CSI component source.

Adjacent checks: PBCH paired-CSV compatibility and waveform-event retention
pass in `csi_detail_adjacent_20261016_v1`. Its CSI report-clock fixture failed
because it hardcoded 12 dB while its installed YAML physically executed 60 dB.
The fixture now uses the resolved operating point, with a new equality check;
no physical noise, detection policy or mismatch guard changed. The repaired
clock test and two production noise-authority guards pass in
`csi_detail_clock_repaired_20261016_v1`.

All **141 Python measurement-plot/control-EVM streaming checks PASS** in
`logs/lls_repairs/csi_detail_python_20261016_v1.xml`. The dedicated physical
`testH4100SharedCSIUCI` completed all 40 slots and PASSED in
`h4_csi_detail_physical_20261016_v1/receipt.json`; the launcher exited 0 and
printed `H4_CSI_DETAIL_FINAL_SOURCE_PASS` after checking all six frozen hashes.
Results are in `results/lls/h4_shared_csi_uci/20261016_212433_529`.
The slot-19/39 independent PUCCH reports each decode 15/15 bits and report RI2,
CRI1, CQI14; measured PMI changes from20 to18. The first report defers rank
increase; the second completes the configured two-report confirmation. CSI
creates a pending TCI choice but does not activate TCI without received DCI.
Elapsed component time is 3714.9 seconds. This is a preconnected component
gate, not the approved full 100-slot access/data scenario or statistical
qualification. The subsequent runtime edits are confined to packet publication
and HARQ summary counts; they are checked separately, not relabelled as part of
that frozen-source physical pass.

| Finding | Source repair / fixture correction | Evidence / limitation |
|---|---|---|
| Archived tests could shadow current tests | `setup6GRSimToolkit.m` now excludes/prunes `repair_outputs` as it already does logs/results. Harness checks test/source paths and test hashes. | `testSetupExcludesLogSnapshots` extended; final-source receipt is authoritative. Does not modify the active session's path. |
| Audited two-port resource fixture described unallocated RE | `testResourceAccountingExact` used consecutive indices rather than a carrier-plane stride. Corrected the fixture, preserving expected G and port count; production overflow check retained. | 400 independent native allocation checks PASS in the main-folder rerun. |
| RF-memory fixture omitted PA reference domain | `testRFStreamMemoryAndPhase` now explicitly declares waveform-sample PA coefficients and retains a negative missing-domain test. No PA guard disabled. | Final-source receipt controls status; no physical PA calibration claim. |
| Existing per-slot trace test demands applied Doppler before channel execution | `testCoupledTruthPerSlotChannelStateTrace` fails on both untouched baseline and patch; no fake applied value added. | Remains open. Production-owner fixture explicitly expects unmaterialized Doppler; separate actual native-channel test checks executed Doppler. |
| Next-run manifest omitted resolved YAML groups | Manifest builder used `isfield` on the `ScenarioConfig` object. It now exports `toStruct()` data and hashes every inherited source YAML. | `testLLSRepairNextRunManifest` PASS: full resolved-data equality,100 slots,4 GHz/100 MHz TDD,273 PRBs,30 kHz SCS,64/4 physical dimensions and DL/UL rank caps4. No waveform executed. |

## CSI-RS independent channel scoring (2026-10-17)

The actual shared CSI-RS completion previously retained transmitter EVM pairs,
but no independent port-resolved channel error. `PilotResidualNMSE_dB` was
also copied into the summary's `MeanNMSE_dB`. These are different quantities.

The production path now registers same-execution channel capture, retains the
mapper's exact per-resource precoder, and scores the practical estimates only
after CSI selection. The comparison uses the nominal linear propagation
channel, actual TX amplitude/loss and RX timing/CFO coordinates. Other RF
distortion remains in the estimate; this is explicitly not RF EVM or an
RF-free estimator qualification. No channel rerun, fitted phase/gain, or
scoring reference enters the receiver. Every compared complex pilot/port is
retained in CSV/MAT. The reduction processes one FFT window at a time.

Independent experiments exposed a second reference defect: returned NR
TDL/CDL path gains already include configured output normalization. The
coefficient-based data/SRS/TRS scorers applied another `1/sqrt(Nrx)`. That
duplicate factor has been removed, without changing the actual channel or
receiver. The new CSI scorer passes **84 actual AWGN/TDL-C/CDL-C OFDM basis
transmissions**, including 1/2/4 ports, negative/positive residual timing and
two FFT positions. These are operator checks, not BLER populations.

Evidence: `h4_csi_nmse_before_20261017_v1` reproduces the missing score;
`h4_csi_reference_20261017_v5` passes the independent operator check;
`h4_csi_reference_20261017_v2` passes shared CSI with unchanged feedback and
both existing data-reference tests (its earlier incomplete basis fixture
failure is retained). `h4_csi_nmse_adjacent_20261017_v1` passes five adjacent
checks; its missing-empty-NMSE-column failure was repaired with explicit CSV
schema preservation and passes in the first check of
`h4_csi_fullband_20261017_v1`. The latter's bounded full-band CSI check is
now superseded by the successful 4/4 receipt in `h4_csi_fullband_20261017_v2`.
The actual six-slot 64x4 component retained 69,888 paired complex values.
The production reader and plot reducer independently recompute nominal-linear
NMSE **-4.461573587451597 dB**, distinct from pilot reconstruction residual
**-22.368335519288113 dB**, and validate the retained hashes and rendered data.
`h4_csi_nmse_web_20261017_v1.xml` has 47 passing checks;
`h4_csi_nmse_plot_20261017_v1.xml` has 148. All receipts are under
`logs/lls_repairs`. Full 100-slot execution and statistical qualification
remain pending.

Reference method follows the separation between practical estimation and
independent channel comparison in [MathWorks CSI-RS channel estimation](https://www.mathworks.com/help/5g/ug/nr-channel-estimation-using-csirs.html).
The installed R2026a TDL/CDL implementations and actual basis transmissions
were checked for normalization; documentation alone was not used to assume
whether returned coefficients were already normalized.

## Follow-up clock, CRC and RA diagnostic repairs (2026-10-17)

- **H4-83, focused pass:** NR PDCCH declares and validates CRC24C/24 bits
  throughout YAML, the internal configuration, direct TX/RX entry points and
  strict configuration exports. The RNTI mask remains separately identified
  as 16 bits. Malformed/16-bit declarations reject. Native encoded/decoded
  AL1/2/4/8/16 checks and the physical mini-anchor pass. The separate
  experimental `ctrl6gr` codec was not redefined as an NR procedure.
- **H4-95, focused and full-band component pass:** the first six-slot H4 CSI
  component failed because the new scorer treated native channel-object time
  as physical time. `ChannelFactory` consumes warm-up before physical sample
  zero. It now retains and validates the actual object-input-count offset;
  native timestamps are not overwritten. The independent basis tests include
  256 actually executed warm-up samples and a wrong-offset negative. Actual
  H4 64x4 whole/split capture tests pass with coefficient error about 2.22e-16
  and waveform error about 6.29e-16. This is not full-scenario acceptance.
- **H4-90, physical component pass:** production RA
  completion now retains compact PDSCH/PUSCH receiver diagnostics through
  Msg2/Msg3/Msg4/RRCSetupComplete tables. It takes no injected CFO or configured
  SNR input. Pilot/Hest SINR, post-equalizer SINR, residual-bound decisions,
  estimated/applied CFO, same-estimator consistency and independently measured
  residuals retain their separate meanings. A default `Ok=false` structure is
  not receiver diagnostic evidence. New WebGUI projections pass 48 tests;
  the subsequent actual causal-RA test passes. The first physical check exposed
  aliases in `RASIPDSCHContext`: it used independent channel NMSE as pilot
  residual and omitted the bounded post-equalizer SINR source. The adapter now
  retains those distinct measurements and preserves actual timing correction.
  Helper, actual RA and negative SetupComplete CRC checks pass 3/3 in
  `h4_ra_diagnostics_20261017_v2`. The physical component is 5 MHz CDL, not a
  full 100 MHz or live WebGUI deployment claim.

Receipts: `logs/lls_repairs/h4_pdcch_crc_width_20261017_v3`,
`logs/lls_repairs/h4_csi_clock_and_crc_20261017_v1` (4/4), and
`logs/lls_repairs/h4_csi_fullband_20261017_v2` (the full-band repeat).
The original failed full-run and failed first CSI component are retained.
Reference: [MathWorks nrDCIEncode](https://www.mathworks.com/help/5g/ref/nrdciencode.html),
implementing TS 38.212 sections 7.3.2–7.3.4. The new checks validate specific
code paths; they do not establish blanket 3GPP conformance.

## Remaining execution boundary

The 2026-10-17 receiver-export rerun completed at 02:08 IST: both
`testTransportExportIdentity` and `testIsolatedDataChannelScoring` PASS in
`logs/lls_repairs/live_count_receiver_after_20261017_v1/receipt.json`.
The latter exercises eight actual DL/UL cases with timing offsets 0/16 samples
and CFO 0/400 Hz, checking baseline versus independently scored reception.
Its prior failure exposed a missing executed `Seed` in both core constellation
producers; `runDLPDSCHThroughput.m` and `runULPUSCHThroughput.m` now retain it.
No waveform, receiver threshold or old capture was changed. The independent
snapshot ownership checks also PASS. These are focused export fixes, not a
certificate for full-scenario or statistical acceptance.

The approved full 100 MHz run **failed at slot 41/100; recovery has finished and no replacement run is active**. The all-impairment error-transition campaign, large-population qualification and instrument playback remain uncompleted. On 2026-10-17 the user explicitly authorized **testAll after focused repairs**; it has not yet started and must not overlap the focused MATLAB batch. The older configuration-only next-run manifest is historical: its `ExecutionAuthorized=false` does not supersede the user's subsequent run authorization, and its `ReadyForEndToEndAcceptance=false` remains an appropriate qualification boundary. Launch is not acceptance.

### Focused follow-up receipts (2026-10-17)

- PRACH statistical RNG: disjoint Threefry population/point/trial substreams
  replace the proven additive-seed collisions. 48,000 identities are unique;
  an actual bounded H0 waveform is reproducible bit-for-bit from exported
  identity. Serial/two-worker primary tables and receiver waveform hashes
  match. This does not qualify a false-alarm or detection probability.
- RA resource maps: `appendObservedStageAllocation` now appends every completed
  physical stage, including CRC failures, and rejects prepared-only occupancy.
  Exact PDCCH/PDSCH/PUSCH RE counts, native PRACH coordinates, stage/attempt/UE
  identity and continuation deduplication pass. No logical-port count is
  relabelled as final 64-TXRU occupancy.
- FDD calendar: offset 3 is disjoint from SSB/SI/TRS over the full repeating
  calendar; the original offset-2/SIB1 collision still rejects. Both-mode Msg4
  and PRACH-origin physical tests pass. A separate CSI fixture now installs
  the existing two-port FDD DCI context without changing RF/channel/noise.
  Fixed-rank rejection is not a CSI decoding failure; its revised assertion
  now passes with all four physical shared-CSI feedback variants. Rank2 is
  preserved when the decoded RI1 report is correctly held by fixed-rank policy.
- Anchor readiness: the core publication boundary reads actual run-local KPI
  rows. Missing/header-only artifacts cannot turn ready at later stages;
  failed but present KPI rows are not called qualified. Focused test passes.
- GUI/NMSE projection: 62 Python checks pass in
  `h4_ra_csi_gui_20261017_v3.xml`. No running server reload is claimed.
- Native PRACH background: the strongest-preamble path now uses receiver-only
  useful-repetition differences on native FFT/CP coordinates. It reports noise
  plus inter-repetition variation, not a claimed thermal-noise measurement.
  Candidate-peak lower-tail statistics remain separate; native RAPID, timing,
  threshold and decision peaks are unchanged. AWGN/CDL-C, CFO/time variation,
  1/4/64 RX, unavailable repetitions and primary/mirror export checks pass.
  The actual 273-PRB/122.88-MS/s/64-RX AWGN component has estimated-to-injected
  sample-variance ratio 0.999694. Its auxiliary cyclic-correlation lag is not
  substituted for the native timing decision. This is not full 64x4 fading
  access or statistical detector qualification.

Receipts are under `logs/lls_repairs`: `h4_prach_noise_identity_20261017_v1`
(3/3), `h4_prach_ra_adjacent_20261017_v1` (parallel RNG and two RA guards pass;
its older FDD failure remains retained), `h4_ra_calendar_20261017_v1` (4/5,
CSI variants failed), and `h4_ra_calendar_20261017_v2` (3/4, CSI fixture's
fixed-rank expectation failed). The final `h4_native_prach_20261017_v3` receipt
passes 4/4: PRACH runtime export, native repetition measurement, shared CSI
clock variants and runtime-status integrity. The publication follow-up
`h4_native_prach_publication_20261017_v1.xml` passes 142/142 Python tests with
no errors or skips. Earlier failed receipts are preserved. These are not
full-suite or full-run results.

The full-suite provenance preflight also found that `sha256File` rejected an
existing MEX binary because MATLAB classifies it with `exist(...,'file')=3`.
The core file check now uses `isfile`; missing paths and directories still
reject. Known-byte binary/source/P-code/MEX-extension checks pass, and the
actual AWGN MEX digest matches independent PowerShell SHA-256. The guard is
registered in `testAll` (now 1,135 tests). Evidence:
`logs/lls_repairs/h4_source_hash_check_20261017_v1.json`. This changes file
provenance handling, not a numerical PHY algorithm.

## Standards references used without changing the installed baseline

The LDPC selection audit follows [TS38.212 v18.5.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.05.00_60/ts_138212v180500p.pdf) and the documented selection/interleaving/buffer behavior of [nrRateMatchLDPC](https://www.mathworks.com/help/5g/ref/nrratematchldpc.html). Remaining requested specifications are version-pinned in the manifest, not blanket certificates that every module has passed conformance. PF policy, rank confirmation thresholds, estimator designs, RF masks, energy watt values and instrument formats are implementation/profile choices, not universal 3GPP requirements.
