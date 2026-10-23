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

## Follow-up: slot-46 checkpoint inventory memory failure

The v2 continuation reached slot46, then failed in
`sixgr.util.matSave>localValidateSavedPayload` with
`sixgr:util:matSave:InvalidSerializedPayload`, caused by **Out of memory**.
This was checkpoint publication, not evidence of a PHY CRC failure.
Engine PID7652 was stopped with explicit approval; no run evidence was
deleted. The slot46 directory has no committed state/receipt pair and is
not a usable restart point. The last durable checkpoint remains45.

The root cause is `whos('-file', ...)`: while computing nested inventory
sizes/types, MATLAB can invoke `loadobj` and reconstruct saved objects
beside the still-live runtime. A new handle-object regression reproduced
that behavior before the repair. Production `+sixgr/+util/matSave.m` now
uses native `who('-file', ...)` and requires the exact intended variable
names. Full source, staging and final-file byte/hash checks remain active.
The serializer does not discard arrays, change precision, reconstruct
missing measurements or alter PHY/channel/decoder state. Inventory alone
is not full reload qualification; actual restoration still uses `load`.

Read-only measurement on the retained 1,024,634,989-byte checkpoint45:
names-only inventory took0.103s; MATLAB committed memory changed from
2.1349GiB to2.1352GiB. This is an inventory-operation measurement, **not**
a whole-run memory or speed benchmark.

All seven affected tests passed in
`logs/lls_repairs/checkpoint_inventory_focused_20261020.log`:
`testMatSaveFilesystemAtomic`, `testSlotCheckpoint`,
`testSlotCheckpointPolicy`, `testSlotCheckpointLongPath`,
`testSlotCheckpointExternalArchives`,
`testSlotCheckpointExternalArchivesLongPath`, and
`testCompletedWaveformRuntimeCheckpoint`.
The actual CDL/RF/noise, pending-observation and LDPC/HARQ continuation
test passes; changed scientific settings and corrupted dependencies still
reject. The pre-repair failing regression is retained in
`logs/lls_repairs/checkpoint_inventory_red_20261020.log`.
No testAll was run.

The v3 operational resume input is
`logs/lls_repairs/h4_checkpoint45_resume_20261020_v3/resume.yaml`.
It restores checkpoint45 and next executes46 with every-slot checkpoints.
Integrated checkpoint46/feedback50 completion, sustained DL/UL adaptation,
final export acceptance and statistical qualification remain unverified
by these component tests.

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

## Checkpoint46 completed; subsequent performance repairs

On20 October2026, checkpoint46 committed at14:41:32 UTC. The watcher
independently verified state SHA-256
`cf991457d1aff3812d0d3a6afe61b95772dd1e220c817fd30356cec22e4b5fa9`
and stopped only MATLAB24156 at14:43:36 UTC. The 13,048,376,626-byte state
remains at `after_slot_000046_f257184a-4951-462a-9010-5dfc521d3f1c/state.mat`
in the original E: checkpoint tree. All original IQ/results/logs remain.
Next executed slot is47; the partial later attempt will be preserved by
normal restart staging.

These are infrastructure changes, not new3GPP requirements or altered PHY
algorithms:

| Change | Core implementation and integrity boundary |
|---|---|
| Checkpoints49/52/55/... | `checkpoint_first_slot: 49`, `checkpoint_every_slots: 3`; operational restoration retains the original scientific identity. Anchor0 preserves old modulo behavior. |
| Shared file versions | `SlotCheckpoint.m` and `CheckpointFileStore.m`: immutable SHA-addressed private copies, verified source/object bytes, new versions for changed files; no mutable-producer hardlinks. Legacy snapshot layout stays supported. Shared objects are not garbage-collected by rolling state retention. |
| Completed sample ownership | `WaveformObservationBuffer.m`, `CompletedSampleArchive.m`, `CoupledWaveformStream.m`: independently verify exact file-backed samples before releasing their arrays. Keep unfinished RX coverage, channel/filter/RF/RNG state, scoring segments and HARQ buffers. This does not eliminate all64-port memory. |
| DL/UL scheduling intervals | `CoupledTruthRuntime.m`, `SchedulerPF.m`, `SchedulerBase.m`: budget, eligibility, common reservations, PF probes, final plan, resource/TBS, feedback AMC, active UE binding, exact freeze and DCI. Exclusive times avoid double-counting nested scopes. No scheduling shortcuts were added. |
| Unchanged live CSVs | `CSVWriteReuse.m` and `csvWriteTable.m`, scoped by the production publisher: table/schema hash plus independent existing-file hashes. Changed, missing or tampered destinations go through normal complete publication. No measurement rows are dropped. |
| Compression benchmark | `matSave.m` exposes an explicit opt-in benchmark option; the production default stays compressed. `benchmark_checkpoint_compression.ps1` runs isolated fresh MATLAB processes with memory sampling. |

The16-test affected batch passed completely:
`logs/lls_repairs/h4_checkpoint46_performance_20261020_v1/receipt.json`.
It includes exact native CDL/RF/noise/pending-window continuation, native
LDPC/HARQ retry, immutable object corruption and changed-version tests,
long paths, external archives, exact table restoration and profiler-on/off
grant/DCI equivalence. No `testAll` or new scenario was launched.

The full-slot benchmark used273 PRBs,64 ports,122.88 MSa/s and61,440 samples
with the same native OFDM sample hash in both modes. It is a bounded
serialization fixture on C:, **not** the full13GB state on E:.

| v7.3 mode | Save and verified publication | Native load | File size | OS process peak commit |
|---|---:|---:|---:|---:|
| Compressed |11.648 s|0.943 s|115.45 MiB|1.640 GiB|
| Uncompressed |5.834 s|0.240 s|120.14 MiB|1.652 GiB|

Evidence:
`logs/lls_repairs/h4_checkpoint_compression_fullband_20261020_v1/`.
Phase private/working-set peaks are sampled; the OS high-water counter is
process-lifetime, including startup. MATLAB `memory` boundary snapshots
are separately labelled and must not be substituted for peaks.
Do not extrapolate this single comparison into a promised scenario speedup.

Prepared restart configuration:
`logs/lls_repairs/h4_checkpoint46_performance_20261020_v1/resume.yaml`.
Actual slot47/49 timing, memory reduction, slot50 feedback/PUSCH completion,
sustained adaptation and final publication remain integrated acceptance work.

The additional legacy-schema1 restoration, production slot40--60 timing
preflight and completed-runtime publication guard all pass:
`logs/lls_repairs/h4_checkpoint46_followup_20261020_v1/receipt.json`.
Total:19 distinct affected MATLAB tests. The real loader regenerated the
HTML configuration/catalog snapshots;87 Python documentation/slot-window
checks subsequently pass. No test assertion or detector threshold was relaxed.

At15:06 UTC the same scenario was relaunched from checkpoint46 (engine2244,
launcher6452). Its launch log is
`logs/lls_repairs/h4_checkpoint46_performance_20261020_v1/resume_launcher.log`.
The storage watcher targets only that engine and can stop it after a newly
verified checkpoint if storage reaches the configured reserves. The earlier
repair-stop watcher is finished. A launched/restoring process is not evidence
of a completed slot47 or checkpoint49.

## Checkpoint49 repair boundary — 21 October 2026

The user chose **repair after checkpoint49, then resume slot50**. The watcher
verified checkpoint49 and stopped only engine2244 at
20 October2026 18:33:29 UTC. Its state is6,898,770,843 bytes with SHA-256
`b941df768a2e69939960f5ab6755871618192b975a932fec3b4fc330a47a1c25`.
It contains1220 dependencies. All evidence, including the partial slot50
attempt that began while hashing, remains preserved. Checkpoint49 is the
restart boundary; no completed PUSCH/slot50 result is inferred.

Main-codebase changes:

| Area | Repair and verification | Remaining limit |
|---|---|---|
| Common-resource scheduler cost | Vectorized `generateTRSSymbolsAndIndices.m` instead of scalar per-RE struct append. Independent loop/nrCSIRS comparisons preserve table values, types, ordering and RNG. Four affected scheduling/TRS tests pass. | The bounded273-PRB slot47 filter fell from261.886132 to71.721000s (3.65×); not a whole-slot speedup. Repeated reservation rebuilds remain. |
| RF inventory in energy model | `resolveLLSEnergyModelConfig.m` rejects contradictions by default. Exporter explicitly requests a new reporting model with declared64/4 RF inventory, retaining original2/2 inputs. Directional counts stay separate. | These are engineering circuit-power assumptions, not3GPP-mandated powers or hardware measurements. No frozen PHY configuration changed. |
| Endpoint energy | `integrateLLSEndpointEnergy.m` partitions explicit endpoint/population intervals, charges identical simultaneous states once, and keeps channel attribution nonadditive. Resource intervals use exact CP-aware timing where actual symbol fields exist. | The checkpoint49 prefix still lacks some actual resource operands and joint simultaneous-state authority. Complete energy totals are not qualified. Missing data does not become sleep or zero energy. |
| PDCCH resource evidence | Production writer retains actual transmitted control data/DMRS PRB union and CORESET start via `pdcchResourceIntervalEvidence.m`. Physical PDCCH export check passes. | Older generic PRB counts describe associated data allocations, not the actual control resource. No historical substitute is inserted. |
| Goodput publication | `bindTransportGoodputPublicationScope.m` validates original CRC, TB identity, credit and scope before binding late publisher RunID. Retains old key; does not change bits or double-credit retries. Six affected scope/export checks pass. | Actual resumed publication remains an integrated gate. Old checkpoint files are not rewritten. |
| Plot correctness | The materializer does not divide nonadditive channel-window energy into fictitious per-TB energy samples or average it into RF transmit power.84 affected Python tests pass. | Complete modeled endpoint totals and independently attributed RF-power relations require their own inputs. |

The final affected MATLAB selection passed4/4 after the final edits. Earlier
focused passes and the bounded before/after profiles are retained beneath
`logs/lls_repairs/h4_checkpoint49_core_20261021_v1/`.
The final checkpoint-prefix audit uses hash-verified small snapshots only,
without loading native runtime state or changing original measurement files:
`energy_prefix_final/receipt.json`. It records `ModelAvailable=true`,
`EndpointTotalsAvailable=false`, and `PrimaryStudyEligible=false`.
No full `testAll` was run.

Prepared operational restart:
`logs/lls_repairs/h4_checkpoint49_core_20261021_v1/resume.yaml`.
It starts after49, preserves the100-slot/4GHz/100MHz TDD scientific scenario
and existing frozen pending grants, and retains checkpoints52/55/58/... .
This is repaired-source diagnostic continuation, not frozen-source primary
performance evidence. A successful launch or restore does not establish
PUSCH, sustained adaptation, final publication, or statistical qualification.

Actual previous checkpoint49 profiling measured2662.546s total
(44min22s). Nested MAT-save, hashing and snapshot spans overlap and must not
be summed. The new49 state is smaller than the old46 state, but they are
different states, so this is not an apples-to-apples memory speedup.
The double native-load path remains open (H4-209); its integrity checks are
not bypassed for this restart.

## Resource recovery and endpoint-state repairs — 21 October 2026

The physical run remains stopped at verified checkpoint49. The following
work was performed in the main codebase, without rewriting the checkpoint,
its raw receiver tables, or the interrupted slot50 evidence.

- `readObservedOFDMResourceIntervals.m` now resolves actual carrier SCS/CP
  explicitly and reads content-addressed `.bin` CSV snapshots directly.
  Tests cover normal/extended CP, chunk invariance, hashes, exact coordinates
  and rejection of planned rather than executed occupancy.
- The actual checkpoint resource object was hash verified before and after
  reading. Its1,241,707 RE rows compact to235 allocation/symbol intervals
  in125.865s, using bounded32,768-row reads. This is retained TX occupancy,
  not a new PHY realization, inferred receiver-on state or hardware energy.
- New DL/UL throughput trial producers carry per-symbol occupied PRB sets
  derived from their executed RE ledger. CSI-RS/TRS producers carry actual
  grid occupancy. `expandExecutedResourceIntervals.m` preserves absolute
  slot/symbol timing; energy integration validates original receiver TB
  credit before making nonadditive per-symbol attribution rows.
- Joint gNB model evaluation uses the union of actual simultaneous PRBs.
  Equal numeric power is no longer evidence of an identical joint state.
  UE receive/transmit model operands are checked explicitly, and one
  endpoint budget is counted once. These remain declared engineering
  models, not3GPP-mandated circuit powers or measured hardware watts.

Verified receipts:

- `logs/lls_repairs/h4_energy_recovery_guards_20261021_v1/receipt.json`:3/3.
- `logs/lls_repairs/h4_data_resource_exports_20261021_v1/receipt.json`:4/4,
  including actual DL/UL receiver trials and PDSCH/PUSCH/PDCCH/PUCCH
  resource/CSV/PNG checks. The two accounting tests overlap the first batch;
  these are five distinct affected tests, not seven distinct tests.
- `logs/lls_repairs/h4_checkpoint49_core_20261021_v1/resource_recovery/receipt.json`
  binds the recovered CSV to source hash
  `192c36de3ee9247637d4c4b9bb61acf8cf50c589aa4896bf17bae3c1f1174cbb`.

Recovered evidence confirms126-PRB PDSCH allocations at one-based slots41/42,
273 PRBs in the later completed DL allocations,272 occupied SRS PRBs, and
12 carrier PRBs in each recorded connected PDCCH candidate. Four SSB blocks
each span four symbols; their240-subcarrier placement crosses21 carrier PRBs
because it is not aligned to a carrier PRB boundary. Carrier-PRB intersection
count must not be confused with the20-RB width of the native SSB grid.

Remaining: bind the recovered intervals to historical trial identities,
handle native PRACH clocks separately, complete endpoint-state coverage,
verify all producers in resumed execution, and complete final publication.
The existence of recovered resource sets does not make the old energy audit
pass. `EndpointEnergyQualified=false` and `PrimaryStudyEligible=false` remain
explicit in the recovery receipt. No physical scenario or full testAll was
started by this recovery work.

## Exact historical binding and native PRACH clock — 2026-10-21

The core reporting adapter now binds the retained occupancy to all 28
non-PRACH receiver rows at checkpoint 49. It checks configuration, channel,
cell/UE, allocation identity and any retained population identity. It
distinguishes the DL and UL-grant PDCCH transmissions at slot 46, the four
SSB beams sharing one acquisition-report slot, and each TRS capture's
multiple resource slots. It does not select the nearest slot or fabricate
receiver outcomes. Original receiver files and checkpoint objects remain
unchanged.

`prachNativeSampleIntervals.m` independently uses the native PRACH grid,
recorded transmit origin, CP/useful sample intervals and sample rate. It
preserves the native grid/waveform hashes and their power plane. The
production post-execution RA stage publisher now supplies this evidence
through `runWaveformLinkBundle.m`. Resource-model carrier-PRB intersections
are explicitly different from native PRACH RE counts or measured RF
bandwidth. Guards and unobserved RF filter tails are not invented activity.

The retained Msg1 record binds 48 native allocation rows. Together with the
28 OFDM receiver rows, the represented endpoint model now integrates
without the previous missing-input or overlapping-state failures. This is
not complete-run energy: 92 executed OFDM resource intervals still need
their access/SI observation adapters (12 PDCCH, 52 PDSCH, and 28 access-stage
PUSCH intervals). Those PUSCH intervals are **not connected UL data trials**.

The primary energy summary therefore keeps total-energy/bit,
throughput-per-watt, and related complete-energy metrics unqualified.
Finite partial calculations are retained separately in
`energy_represented_interval_diagnostics.csv`. The executed delivered-bit
denominator remains 40,136 bits; no additional delivery was inferred from
resource occupancy. `EndpointTotalsAvailable` is scoped to represented
intervals, while `ResourceCoverageComplete=false`,
`CompleteRunEnergyAvailable=false`, and `PrimaryStudyEligible=false`.

Verified evidence:

- `logs/lls_repairs/h4_resource_binding_20261021_v2/receipt.json`: 3/3.
- `logs/lls_repairs/h4_native_resource_binding_20261021_v2/receipt.json`: 2/2,
  including actual short/long PRACH generation and FFT/CSV/PNG checks at
  one and two ports. This is not statistical PRACH receiver qualification.
- `logs/lls_repairs/h4_energy_coverage_20261021_v1/receipt.json`: 2/2,
  including the actual two-occasion shared-SRS collector/schema guard.
- `logs/lls_repairs/h4_energy_coverage_20261021_v2/receipt.json`: 1/1,
  including unaccounted native-transmission coverage. These overlapping
  batches cover five distinct affected tests, not eight distinct tests.
- `logs/lls_repairs/h4_checkpoint49_core_20261021_v1/energy_bound_native_v3/receipt.json`:
  hash-verified historical audit, not physical replay or hardware power.

Next work is the actual SI/RA energy-observation adapter, complete prefix
publication wiring and detailed native-clock report fields. The physical
100 MHz scenario remains stopped at the verified checkpoint-49 boundary;
no new scenario or full testAll was launched by these repairs. The new
regressions are registered in testAll for the eventual approved full-suite
verification.

## Common-signal binding and duration correction — 2026-10-21

This update supersedes the earlier statement that 92 access/SI resource
intervals remain unbound. `buildCommonSignalEnergyObservations.m` now joins
the actual SIB1 and RA executions to their exact executed resource records.
It validates run/configuration, UE/cell/attempt, beam, allocation identity,
capture clocks and runtime-versus-self-loop provenance. It retains the
recorded decode outcome; resource occupancy does not imply decode success.
Access PUSCH remains separate from connected UL payload and goodput.

The normal three-argument `exportLLSEnergyDiagnostics` path is wired through
`loadLLSEnergyResourceEvidence.m`. It reads retained artifacts and caches only
compact resource intervals by content hash, carrier parameters and parser
source hash. It neither loads the multi-GiB runtime checkpoint nor replays
PHY samples just to regenerate a report.

The hash-verified checkpoint-49 audit in
`logs/lls_repairs/h4_checkpoint49_core_20261021_v1/energy_common_v2/receipt.json`
records 28 receiver rows, one native PRACH observation, 14 common-signal
observations, and all 92 formerly unmatched intervals bound. There are zero
unbound intervals in the supplied ledger. First-delivered bits remain 40,136.
Reporting duration is 0.0245 s (49 completed slots at 30 kHz SCS), and J/frame
uses the 10-ms radio-frame duration, not the configured slot count.

Verification includes the common-signal, endpoint-integration and RF
provenance passes in `h4_common_energy_20261021_v3`, followed by the repaired
energy-integrity pass in `h4_common_energy_20261021_v4`. The v3 energy test
failure and earlier audit versions remain preserved. These are focused
checks, not a completed physical scenario or full test suite.

`ResourceCoverageComplete=true` refers to the supplied executed ledgers.
`CompleteRunEnergyAvailable=false` and `PrimaryStudyEligible=false` remain:
full endpoint TX/RX/monitoring/idle/sleep-state coverage is not established.
No absent interval is assigned zero power or sleep, and the configured
circuit-power model is not a hardware measurement or normative 3GPP wattage.

## Committed RF execution recording — 2026-10-21

The actual shared RF runtime now records every committed TX/RX operator
interval when the existing resolved energy-evidence flag is enabled. This
includes processing outside channel-specific receiver observation windows.
The compact recorder retains clocks, registered endpoint/port identities,
mean-square measurements, actual all-zero-input flags, existing waveform
hashes and executed stage counts. It does not retain another IQ/channel
array, draw random values, or change receiver samples. Zero mean-square
alone is not classified as zero input: a tested underflow case has nonzero
samples whose squared magnitudes underflow to zero.

`publishRFEndpointExecutionLedger.m` writes the interval CSV, coverage CSV
and hash-bound manifest under `rf/csv`. Seventeen-digit numeric serialization
preserves exact double roundtrip; retained report-only reading validates
the CSV hash, declared types and execution/configuration identity. An old
checkpoint starts recording at its actual saved sample clock. It never
claims the previously unrecorded prefix.

Evidence: `h4_rf_execution_20261021_v7/receipt.json` has three passing tests:
the recorder/publisher and corruption guards, actual shared AGC/converter
metadata, and shared CDL/RF/noise whole-versus-partitioned equivalence. The
earlier v2 receipt covers energy integrity and common-signal binding. The v6
receipt covers nine slots through the production coupled stream, including
four PBCH candidates, the actually transmitted SIB1 and TRS. The measured
TRS NMSE is -18.9866 dB against the unchanged scenario gate of -8 dB; this
threshold is a configured qualification criterion, not a universal 3GPP
requirement. Earlier fixture failures remain preserved.

This closes a missing **RF execution recorder**, not complete hardware-state
modeling or the 100-slot scenario. Full-run circuit energy still requires an
explicit operating-state model and complete coverage. Neither zero input nor
absence of a decoded channel establishes sleep. No physical 100 MHz replay
or full testAll was launched by these focused RF checks.

## Single-owner checkpoint restore — 2026-10-21

`SlotCheckpoint.prepareResume` can now return a transient native-state
owner. Production `runSingle` passes that owner through execution options
to `runWaveformLinkBundle`; it is never inserted in the scientific YAML,
configuration snapshots or the next checkpoint. The PHY consumer takes it
exactly once and the temporary owner releases its large payload. A cleanup
handler also releases it if setup fails before consumption. Ordinary
two-output preflight and direct checkpoint readers remain supported.

The handoff rechecks state bytes, receipt identity, current source identity
and scientific configuration. It does not run native `loadobj` a second
time. Any changed receipt/state/source rejects rather than silently loading
a substitute. A lease cannot be serialized or reused after consumption.
Dependency preflight, hash verification and failed-attempt preservation are
unchanged. Read/validation, external-dependency verification, artifact
restoration and handoff verification times are reported separately.

`logs/lls_repairs/h4_checkpoint_single_owner_20261021_v1/receipt.json` passes
four affected checks: the one-load/corruption fixture, exact physical
CDL/RF/noise and pending-window continuation plus actual LDPC/HARQ soft
combining, schema-1 compatibility, and source/config/storage policy guards.
The physical test also verifies shared native object identity after the
handoff. Its checkpoint is a bounded 148,628,412-byte component fixture;
its 33.5500705-second read/validation time is not a benchmark of the retained
multi-GiB 100 MHz checkpoint. No whole-slot speedup is claimed yet.

The physical 100 MHz run remains stopped. The next execution must still
verify slot-50 data/feedback, sustained adaptation and complete publication.
Whole-run energy remains incomplete, separately from this restore repair.
