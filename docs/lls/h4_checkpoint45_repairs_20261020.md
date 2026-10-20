# 100 MHz checkpoint-45 measurement repairs

All code changes are in the main checkout on `main`. No additional codebase or branch was created. Only affected tests were run; **testAll was not run**.

The interrupted run is `h4_100mhz_local_e_20261019_v3`, under `E:/SixGRResults/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/`.
Its completed checkpoint45 was verified before stopping the original MATLAB process. State SHA256: `9db68e9b442efeeb4caf6ea4f161f7e0be51ae133ec41cdc1314ad73fe6429b1`. The next slot is46. The operational resume YAML is `logs/lls_repairs/h4_checkpoint45_resume_20261020_v1/resume.yaml`.

## Follow-up: slot-50 completion failure

The continuation failed on 20 October at slot50. Its failure-recovery engine
PID24336 was stopped with explicit approval; no evidence was deleted.
The last durable restart point remains45, not49 or50.

The production callback reduced PUSCH, then immediately called
`armSharedPUCCHFeedbackRuntime`, before reducing a coincident PUCCH result.
`CoupledWaveformStream.advanceSlot` had correctly removed **all** completed
captures from `Pending` at that physical sample. The partial reducer therefore
mistook an awaiting callback result for a completed/absent occasion.
The original late-feedback guard itself was correct and remains enabled.

`testSharedSeparatePUCCHPUSCH`, extended to exercise the omitted production
re-arming boundary, reproduced the exact exception after actual successful
PUSCH reception. Evidence:
`logs/lls_repairs/h4_slot50_completion_repro_20261020_v1/receipt.json`.
The main callback and independent-transport fixture now share
`+sixgr/+truth/completeSharedReceiverBatch.m`: process the already-completed
batch in dependency order, then re-arm once before consuming any future
samples. Missing completions, new late grants and receiver crashes remain
failures. All seven affected checks passed under
`logs/lls_repairs/h4_slot50_completion_fixed_20261020_v1/`.
The actual-waveform separate-transport test observed both completions at
sample 76792 and committed independently decoded HARQ feedback. The
UCI-on-PUSCH and unselected-PUCCH producer tests also passed. These results
do not yet establish completion of the interrupted 100 MHz scenario.

Additional retained evidence, not final acceptance:

- Six committed DL trials have correct resource/channel reconciliation.
- Slot47 TRS retains13,104 paired pilot samples: diagnostic EVM7.076724% and
  post-correction common-frequency estimate8.979725Hz. Neither is an RF
  conformance claim or an independent statistical realization.
- The pre-failure slot50 PUSCH channel CSV contains305,280 compared complex
  values across64 RX branches. Recomputed NMSE is−25.992173dB with zero
  error/reference-energy arithmetic mismatches. This retained receiver
  evidence is **not** a committed UL trial or a completed slot.
- The corrected read-only trial audit reports198 arithmetic passes,
  nine source reconciliations and five unevaluated checks; no numerical
  mismatch. It now correctly distinguishes a prior-SRS timing prediction
  from a fresh PUCCH timing estimate. No primary CSV was rewritten.
- Every-slot checkpoints are configured for future launches/resumes.
  They cannot reconstruct the unsaved state after49 in the failed attempt.

| Issue | Root cause and production repair | Verified scope / remaining acceptance |
|---|---|---|
| Missing exact DL overhead counts | `PDSCH_Tx.m` canonical adapters did not expose the resource-summary schema. `pdschPlanResourceSets.m` converts immutable zero-based resource identities to explicitly one-based carrier-plane sets, including exact PRB/symbol allocation. Both facade paths now bind it. | Coded TX/RX and report propagation pass. Independent resource checks cover200 DL and200 UL allocations with zero TBS difference. New resumed rows still require integrated inspection. No TBS or waveform mapping was changed. |
| Missing TRS EVM | `scoreTRSPilotDisturbance.m` did not retain independent complex pilot pairs. It now retains exact desired/received samples by observation and RX branch; `summarizePilotEVM.m` computes pooled error/reference energies. `runTRSTracking.m`, `runWaveformLinkBundle.m` and `exportControlEVMSamples.m` carry the samples and their reference plane to CSV. | Complex arithmetic, independent-reference guards and actual CSV writing pass. This is received-pilot diagnostic EVM, **not** equalized modulation-EVM or RF-conformance qualification. No conversion from SINR/NMSE or fitted gain/phase. |
| Missing TRS post-correction frequency | `measureTRSResidualFrequency.m` measures corrected received samples with an observable different from acquisition (CP versus pilot-phase slope). `bindTRSFrequencyEvidence.m` preserves source, role and observable evidence. | Full-band273-PRB correction-on/off and poisoned-reference tests pass; direct Toolbox IQ calculation independently matches the result. For -400Hz injection, corrected result is approximately -4.28e-14Hz; uncorrected pilot estimate is -399.792486Hz. Uncorrected OFDM ICI means it is not algebraically identical to injected CFO. The original configured accuracy requirement is unchanged. This is common received frequency, not separately identified oscillator CFO. |
| SSB legend collision | `lls_radio_measurement_plots.py` omitted observation identity in series labels. | Four observations across eight sweep points remain distinct in the joint CSV/plot. No per-point split or merged-beam substitution. |
| Misleading SRS full-carrier wording | `computeSRSCoverage.m` conflated exact coverage with configured tolerance. It now distinguishes literal `full_carrier` from `within_configured_carrier_edge_tolerance`; gap, tolerance and literal-coverage flag propagate through receiver, runtime and GUI. | Actual native mapping remains272/273PRBs. Negative tests reject false full-carrier claims and excess gaps. No added pilot REs, reduced numerical gate or extrapolated measurement. |
| Broadcast memory duplication | Pending receiver contexts retained `Prototype.PreparedBroadcast` and unused `RuntimeTx` copies of large waveforms. `compactBroadcastReceiveContext.m` checks exact equality, keeps the frozen samples and actual TX grids, and removes redundant owners at queue/legacy restore. | Ownership, real four-SSB reception/delivery and CDL/RF/pending-window/HARQ checkpoint continuity pass. Actual full-band working-set reduction must still be observed in continuation; legitimate64-port IQ/channel arrays remain large. No precision reduction or skipped channel/RF evolution. |
| Live publication | Added paired TRS received-pilot EVM and measured post-correction frequency chart families and GUI metadata. Restarted WebGUI with `SIXGR_RESULTS_ROOT=E:\SixGRResults`. |254 Python checks pass. Actual new TRS/CSI/PUSCH populations and final publication remain necessary; missing historical samples were not invented. |
| Statistical qualification | Four earlier successful DL trials are not a statistical campaign. | Remains unqualified: BLER, adaptation gain, detector reliability and full conformance need separately designed populations. |

## Evidence

Latest results across the four affected-test receipts give **14 distinct MATLAB tests passing**. Earlier failed receipts are preserved; they are not rewritten. The checkpoint guard correctly rejected a mid-test source change; its frozen-source rerun passed.

- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v1/receipt.json`
- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v2/receipt.json`
- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v3/receipt.json`
- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v4/receipt.json`
- `logs/h4_checkpoint45_python_20261020_v1.xml`:254 passing tests
- Continuation launcher: `logs/h4_100mhz_local_e_20261019_v3_resume_slot45_20261020.log`

The continuation is explicitly source-repaired diagnostic evidence, not a frozen-source primary statistical result. The checkpoint system preserves the interrupted attempt and restores artifact watermarks. Earlier measurements are not retroactively replaced with later values. Configured RF/noise, seed, channel state, waveform mapping and scheduling policies remain unchanged.

## Additional SRS measurement repair before the next continuation

The production SRS runner initialized `EVM_rms` to NaN without measuring it.
`+sixgr/+phy/+srs/measureReceivedPilotEVM.m` now compares the actual received
grid with independently retained desired-link samples on the recorded RX
clock. This is **received-pilot diagnostic error**, not equalized per-port
modulation EVM or an RF conformance result. Shared CDM resources are counted
once per physical receive branch. No scoring reference enters SRS reception,
noise estimation or RI/TPMI/CQI selection; no gain/phase fit is applied.

`runSRSChannelEstimation.m` produces the measurements and exact complex pairs.
`runWaveformLinkBundle.m` propagates the scalar fields and retains the pairs
in hash-checked MAT detail files, rather than embedding large arrays in every
live/checkpoint table. `exportControlEVMSamples.m` and
`lls_radio_measurement_plots.py` publish `srs_evm_samples.csv` and a joint
SRS received-pilot EVM chart with sweep/observation/branch identity.

The initial implementation's struct-array construction failed three focused
checks and was corrected; its failed receipt is preserved. Latest receipts:

- `logs/lls_repairs/h4_srs_pilot_evm_20261020_v1/receipt.json`:
  scoring-reference independence and adjacent TRS scoring passed.
- `logs/lls_repairs/h4_srs_pilot_evm_20261020_v2/receipt.json`:
  all three failed checks now pass: arithmetic/export, actual four-port
  OFDM receive-clock scoring and the exact production trial collector.

The physical component retained 576 complex pilot values at each of three
timing/CFO settings: `(0 samples, 0 Hz)`, `(1, 400)` and `(16, -800)`.
Direct-grid arithmetic agrees; poisoning the scoring clock changes the
diagnostic but not the practical receiver or scheduling feedback. These are
component checks, not a new 100 MHz result or statistical population.

The next reviewed operational resume YAML is
`logs/lls_repairs/h4_checkpoint45_resume_20261020_v2/resume.yaml`.
It retains the same checkpoint and scientific configuration. Old slot45 SRS
measurements are not retrospectively relabelled or reconstructed.

The126-PRB allocations at slots41/42 remain valid under the existing contiguous-allocation policy: SSB reservations split the available band into two126-PRB segments. Slots43/44 used273PRBs. This repair does not change that policy.

## Why slots 48 and 49 are absent from the traffic table

All slot numbers here are **one-based absolute carrier slots**. Symbol bounds
are **zero-based and inclusive**.

| Slot | Actual activity and retained evidence | Why no final traffic row |
|---|---|---|
| 48, DL | `scheduler_admission_trace.csv` records 17,994,983 queued bytes, demand present, a free new-data HARQ process and access/control eligibility. `ReferenceEligible=0`, reason `inactive_or_stale_qcl_timing_reference`. | No new PDSCH was admitted. The previous TRS resource was slot27; its age at48 is21 slots, beyond the configured20-slot QCL source-age limit. The replacement resource47 is observed over two slots and becomes available at49. This is a freshness/cadence gap, not low SINR or an empty buffer. The general eligibility card does not override grant-specific QCL admission. |
| 49, special 10DL/2guard/2UL | Live grant:273PRBs, symbols2–9, rank1, MCS1, TBS5000bits. DCI accepted at sample2957970. The exact slot49 PDSCH channel-estimation CSV exists. PUCCH49 also records successful feedback. | PDSCH reception occurred, but no final CRC/goodput trial row was committed before the slot50 completion failure. Do not describe this as no transmission, or count the scheduled5000bits as delivered. |
| 50, UL | PUSCH was scheduled by control46 with K2=4; the log records SRS reception and committed four-port UL IQ. | The coincident completion/re-arming failure interrupted final trial publication. The seven-test repair receipt and a later separate-transport rerun pass; integrated continuation remains necessary. |

Exact retained sources are `air_interface/logs/run.log` lines537–570,
`packet_flow/csv/scheduler_admission_trace.csv`,
`packet_flow/csv/live_dl_scheduler_grants.csv`, and
`reports/csv/live_receiver_tracking_trace.csv`.
The independently scored slot49 PDSCH resource file is
`channel_estimation/csv/pdsch_e65e7a7a5fe6e42860c6f860ebd85a466e78b88adfcb98b91a7dccf3ae55a151.csv`.
Slots48/49 could not schedule UL into52/53 under the configured K2=4 because
those targets are DL-only. No PUSCH was due at49. Duplex guards remain enabled.

Changing the QCL maximum age solely to eliminate the slot48 gap would change
scientific policy. Continuous scheduling instead needs an explicitly reviewed
reference cadence, observation latency and justified validity bound. That
configuration change is not silently applied to checkpoint45.

## Receiver, beam and synchronization evidence repairs

- New receiver-quality hashes identify the actual complete received input
  **before synchronization**. Existing TX hashes remain separately identified.
  Hashes establish provenance; they are not 3GPP radio measurements.
- The WebGUI now exposes retained RMS EVM as percent, NMSE reference aliases,
  exact capture scope and format-specific applicability. A complete legacy
  PBCH capture contradicting a default false flag is displayed with that
  conflict noted. Missing historical RX hashes are not recreated.
- PUCCH format0 uses noncoherent sequence detection. A usable result does not
  mean an explicit channel estimator/equalizer ran, or that a modulation-EVM
  value exists. Those applicability flags are corrected in the producer and UI.
- The PUCCH diagnostic now uses the actual configured QPSK or pi/2-BPSK
  constellation after `nrPUCCHDecode`, not a QPSK-only slicer for every format.
  Five native modulation cases and wrong-constellation/empty-input checks pass
  in `h4_sync_criteria_20261020_v6`. This is decision-directed receiver EVM,
  not an independent transmitted-reference or RF-conformance score.
- The retained rank1/MCS1 trials are bootstrap grants before delivered CSI.
  Their requested/applied explicit element matrices match. Scalar PMI is not
  interchangeable with a matrix hash, TCI identity or post-hoc best projection.
  The UI distinguishes those fields and no longer calls channel projection
  power an applied antenna gain or a physically measured beam sweep.
- The old CSI-RS capture had a one-slot extent and a `[0,0]` timing search.
  A zero result there did **not** demonstrate timing acquisition. The producer
  now captures the configured uncertainty tail from the physical stream,
  independently on pre-/post-front-end and scoring planes. TX duration remains
  unchanged. The gNB TX ledger is committed at TX completion, without waiting
  for the longer UE capture or its decoding outcome. The actual37-sample
  delayed-stream test passes in `h4_sync_criteria_20261020_v7`; it verifies
  pre-RF0/post-RF37 acquisition,74 timing hypotheses, independent scoring and
  TX eligibility before UE RX completion. The baseline passes in v6.
  Historical fixed-window rows stay labelled.
- First SRS pilot reception cannot yield an inter-observation phase rate.
  The current observation time is now retained even without history; a rate,
  separation and ambiguity bound require a second matched pilot observation.
  This is common-phase evolution, not an identified maximum Doppler spread.
- PDSCH symbols2–13 leave the two-symbol CORESET interval outside the data
  allocation. Symbols2–9 fit the special slot's DL region. Those ranges are
  allocation bounds, not a claim that reserved/DMRS REs carry payload.

The receiver provenance checks passed5/5 and the affected WebGUI checks
passed85/85. The real `/realtime` API and headless-rendered page were checked,
including the preserved failed run status. The latest separate PUCCH/PUSCH
waveform check also passed. This does not establish full100-slot acceptance.

## Recorded acceptance thresholds and their limits

These are the **retained run's** actual criteria, not a claim that 3GPP mandates
these detector implementation constants. No threshold was relaxed in this repair.

| Measurement / channel | Retained criterion | Interpretation |
|---|---|---|
| PSS / SSS detection | PSS0.0386021317469969; SSS0.254253689243335 | Receiver-calculated correlation thresholds for the actual search design. A configured false-alarm target is not an independently measured false-alarm probability. |
| PRACH |0.00360843918243516, source `nrPRACHDetect_default_format_LRA_repetitions_rx_antennas` | Toolbox detector threshold depending on preamble/repetition/RX dimensions. Retained result explicitly says `single_detection_not_statistical_qualification`. |
| PUCCH49, format0/two symbols |0.42, source `yaml.pucch.detection_threshold_format0_two_symbols` | Scenario detector policy. Qualify with independent noise-only and signal-present populations; a few passing feedback occasions are insufficient. |
| SRS independent channel NMSE |≤−8dB | Project qualification threshold, separate from practical receiver usability. Not a universal 3GPP NMSE limit. |
| TRS |Detection0.55, minimum resource coverage0.95 | Actual retained detector/coverage criteria. The old row omitted the NMSE limit and mis-defaulted receiver usability; the producer now exports actual strict-config criteria and individual outcomes. Do not backfill old limits from today's YAML. |
| PBCH / PDCCH / data |Applicable decoded CRC and channel-specific context checks | Not a universal EVM cutoff. Small UCI payloads with no CRC are explicitly distinguished. |
| Receiver EVM |No generic RF-conformance pass/fail limit | Decision-directed modulation EVM and independent received-pilot disturbance have different reference planes. Neither alone establishes TS38.104/38.141 compliance. |
| Slot48 QCL reference |Maximum source age20slots | Configured scheduling policy. It is not a universal 3GPP requirement or permission to apply a future TRS measurement. |

The GUI now includes a recorded-criteria table so actual thresholds and their
sources can be inspected alongside results. Missing old criteria are not
invented, and statistical qualification remains pending.

## Follow-up: PRACH formula, adaptation and runtime cost

The local HTML guide now contains the native PRACH threshold formula, an
interactive calculator, the exact B4/139/12-symbol/64-RX calculation, the
slot48 QCL timeline and the distinct DL/UL adaptation timelines:
`http://127.0.0.1:62907/#prach`, `#beam`, `#adaptation`, and `#recipe`.
The headless browser check passes all34 chapters,117 live source links, the
PRACH calculator (including invalid-input rejection), configuration hashes
and mobile layout:14,127 authored words and zero browser errors. The scenario
inventory check now explicitly waits for its asynchronous YAML inventory
before asserting the filtered result; no content assertion was removed.

The formula is MathWorks' empirical receiver default, **not a normative
3GPP formula**. The exact H4 native detector check passes. DL and UL
rank-confirmation consumers, QCL source-age boundaries and OLLA
retransmission exclusion pass in
`logs/lls_repairs/h4_threshold_adaptation_20261020_v1/receipt.json`.
That batch found an inconsistent older OLLA fixture: fixed rank2 from the
default config versus supplied rank1 feedback/grant. Its rank-one setup is
now explicit; the production guard remains unchanged and the test adds a
wrong-rank rejection. Its rerun passes in `h4_threshold_adaptation_20261020_v2`.

The retained CSI report has source46, due59, no delivery and
`pending_receiver_decoded_csi_uci`: RI4/CQI8/PMI3/CRI1 are UE-side report
contents, not received gNB scheduling authority. The first SRS45 reports
RI4/CQI15 but is only one of two required rank confirmations. Control46
therefore freezes PUSCH50 at bootstrap rank1/MCS1. SRS50 must not retroactively
rewrite that grant. The later full-band continuous component v4 also executed
PUSCH at slot15:273PRBs, rank4/MCS25, TB507984bits, CRC pass and zero bit
errors, with103188 EVM pairs and four DMRS ports. Its receipt is
`logs/lls_repairs/h4_continuous_ul_feedback_20261019_v4/receipt.json`.
That is stronger than the earlier consumer-only check, but its declared
boundaries remain `MACSchedulerFeedbackCommitted=false`,
`ScenarioAccepted=false`, `StatisticallyQualified=false`. Full integrated
DL/UL adaptation remains to be demonstrated after repair.

The retained slot46/47/48/49 start intervals are80.92/44.65/40.50/24.87minutes.
They include all work between boundaries, not a measured stage attribution.
This host reports11.8GiB physical RAM; E: is a USB HDD. Paging, multigigabyte
archives and repeated serialization are priority profiling targets, not
proven percentage costs. More RAM and fast active SSD storage are suggested;
no precision reduction, proxy PHY, skipped channel/RF evolution or removal
of measurements was implemented. No new100MHz scenario was started.

## Implemented lossless performance repairs — 20 October

| Area | Main-code repair | Integrity boundary |
| --- | --- | --- |
| Separate stage timings | `+sixgr/+runtime/ExecutionStageProfiler.m`, physical channel/RF owners, canonical DL-SCH decoder, PUSCH decoder, hash/MAT/CSV utilities and runtime publication/checkpoint calls | Per-session/slot/sweep inclusive and exclusive wall time. No samples or scientific RNG in profiler state. Scope exits include failures; they are not PHY passes. |
| Duplicate capture buffers | `WaveformObservationBuffer.m` compacts completed parts into one exact array; repeated reads use MATLAB copy-on-write; `receivedWaveformEvidence.m` reuses the immutable sample digest | Single/double complex classes and all samples retained. Caller mutations cannot change the capture; checkpoint serialization round-trip tested. |
| MAT readback duplication | `matSave.m` streams SHA-256 over staged and final published files directly instead of copying each one to another temporary MAT | Both full byte/hash checks and atomic publication remain. Long-path handling, altered/invalid-write guards and prior-file preservation remain tested. |
| Excess live rendering | `liveCSVPlotDue.m`, `runWaveformLinkBundle.m`, YAML schema/defaults and builder | H4 refreshes live PNGs every5completed slots, first slot and final publication. Primary measurements and trial CSVs retain their original cadence. Final materialization is not throttled. |
| Unchanged-chart work | `publish_lls_live_csv_plots.py` reuses sealed PNG/plotted-CSV bytes for unchanged known dependencies | Producer hashes and all chart dependency hashes must match. Dynamic independent-NMSE operands are included; changed/unknown/unavailable charts are regenerated. No sampled-down data. |

H4 operational settings:

```yaml
output:
  execution_stage_profile_enabled: true
  live_csv_png_interval_slots: 5
```

Generic defaults remain profiler-off and interval1. The checkpoint comparison
excludes exactly these two non-scientific keys, not all output settings.
Changing `save_csv` or physical policy still fails compatibility. The restored
process creates a new profiler session; it does not relabel historical timing.
The audit also found that `runSingle.m` restored the original scenario object
and thereby discarded the requested operational settings. The production
restart now applies a strictly bounded operational snapshot after building
the original configuration, including requested every-slot checkpoint cadence.
Original scientific/config hashes continue to own pending grants and HARQ.
`meta/checkpoint_resume.json` records the separate requested settings; the
internal configuration records what was applied. Scientific fields cannot be
smuggled through this binding.

The timing CSV is `reports/csv/execution_stage_profile.csv` under the run
folder. `SlotOneBased=0` denotes setup; `ScopeExitCount` is execution accounting,
not a successful-decode denominator. Sum **exclusive** durations for
non-overlapping attribution; nested inclusive times must not be added
together. This is scoped timing, not a claim to capture every operating-system
wait or to replace a full MATLAB profiler.

Actual slot45 checkpoint bytes pass SHA-256 against the saved receipt. The
latest checkpoint remains45, next46—not49 or50. No new scenario was launched.
The saved scientific JSON matches the requested restart YAML after removing
only the reviewed operational/provenance keys. A checksum/config preflight
does not prove all external dependencies or full state restoration. The
restart loader must still verify those.

Latest evidence for this performance change:

- **12 distinct affected MATLAB checks pass** across
  `logs/lls_repairs/h4_performance_20261020_v1` through `v4`, using the latest
  result for each test. This includes actual shared CDL/RF evolution, DL/UL
  physical decoding with profiling on, and retained LDPC/HARQ/checkpoint
  continuation. It is not a100MHz whole-scenario acceptance run.
- The v2 profiling test caught a missing canonical DL timing hook. The core
  hook was corrected in `DLSCHDecoder.m`; v3 passes. The failed v2 receipt
  remains preserved.
- **133 Python publication/WebGUI checks pass**:
  `logs/lls_repairs/h4_performance_20261020_python.xml`.
- **19 documentation checks pass**. A new source link required an exact
  allow-list entry for the live publisher; other scripts remain inaccessible.
  Headless Chromium verifies34chapters and124source links with zero browser
  errors, including the new operational configuration fields.
- `h4_performance_20261020_v4/checkpoint_config_preflight.json` records the
  scientific match, cadence1, PNG interval5 and profiler-on. It explicitly
  records `RuntimeStateLoaded=false` and
  `AllExternalDependenciesVerified=false`.

**Readiness:** suitable for a guarded diagnostic continuation from45→46,
subject to the normal dependency/state restoration checks. Not a declaration
that all100slots, adaptation, measurements or scientific qualification pass.
No `testAll` or new100MHz scenario was started.

### Remaining acceptance before claiming the whole run is fixed

| Priority | Pending item | What is still required |
| --- | --- | --- |
| P0 | Integrated slot49/50 handoff and UL trial | Resume actual saved state, save completed49, publish actual PDSCH49 and PUSCH50 outcomes without the repaired completion-batch race. Component passes do not close this. |
| P0 | Sustained DL/UL adaptation | Receive/decode CSI-UCI, apply causal confirmation rules, then verify actual MCS/rank/precoder grants and TB outcomes through the100-slot horizon. Bootstrap41–49 must not be rewritten. |
| P1 | QCL/TRS calendar gap | Slot48's age-based deferral remains correct under the frozen policy. Eliminating the gap requires a justified calendar/freshness change in a separate configuration; no future reference or arbitrary age relaxation. |
| P1 | Integrated measurements and final publication | Verify all applicable resource counts, RX provenance, EVM/NMSE operands, timing fields, CSV/PNG data identity and WebGUI results. Historical missing samples cannot be manufactured. |
| P1 | Whole-run memory and throughput cost | Use the new stage CSV and host memory measurements during continuation. Large64-port channel arrays remain real; no percentage speedup or no-paging promise follows from focused tests. |
| Qualification | Statistical/standards claims | Detector H0/H1 populations, BLER/HARQ calibration, RF procedure qualification and independent validation remain separate work.100slots alone do not qualify them. |

Absolute dBm is not available from this normalized fixed-Es/N0 experiment
without an absolute calibration plane; first-observation SRS phase evolution
requires another observation. These are measurement-domain limits, not
permission to fill cells with assumed values. Bounded access is not a
complete commercial RRC/network conformance claim.

## Standards boundary

SRS bandwidth uses the TS38.211 section6.4.1.4 resource mapping, including its discrete bandwidth table; a tolerance label is not additional measured coverage. See [MathWorks SRS configuration](https://www.mathworks.com/help/5g/ref/nrsrsconfig.html).

RF-conformance EVM requires the specified waveform and measurement procedure, not merely a paired-error formula. See [MathWorks NR EVM measurement and TS38.104/38.141 distinction](https://www.mathworks.com/help/5g/ug/evm-measurement-of-5g-nr-downlink-waveforms.html). TRS diagnostics here do not claim that qualification.

The PUCCH constellation/deprecoding interface follows
[nrPUCCHDecode and its TS38.211 sections6.3.2.3–6.3.2.6 references](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html).
PRACH's implementation-specific normalized threshold is documented by
[nrPRACHDetect](https://www.mathworks.com/help/5g/ref/nrprachdetect.html).

## Subsequent continuation and documentation consolidation

The earlier “no new scenario was launched” statements above describe the
focused-repair stages. A later explicitly requested diagnostic continuation
was launched using
`logs/lls_repairs/h4_checkpoint45_resume_20261020_v2/resume.yaml`.
Observed at **20 October 2026 10:01 UTC**, it had completed checkpoint-file
restoration and entered radio slot46, retaining the previous failed attempt.
This dated observation is not a slot50 or terminal acceptance receipt.
Current state must be read from its launcher, runtime and checkpoint receipts.

The same main checkout's HTML guide now includes a method authority register,
channel-by-channel production flows, calculation examples, measurement-plane
contracts, the completion barrier, restart staging and threshold attribution.
Every chapter distinguishes standards structures/models from MATLAB,
engineering, research and software-infrastructure choices.
The expanded guide passes22 documentation tests; the combined focused Python
publication/WebGUI/audit selection passes437 tests. Headless browser checks
pass41 chapters,42 methods,15 walkthroughs and148 local source links with no
browser errors. These receipts do not close the integrated/statistical
acceptance rows above.

No running MATLAB source or primary measurements were edited during this
documentation update. Existing logs, IQ and checkpoints remain preserved.
