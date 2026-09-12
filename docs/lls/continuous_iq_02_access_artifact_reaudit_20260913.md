# Previous-run access, measurement and artifact re-audit

Run: `results/lls/lls_causal_access_to_data_wiring_tdd_short_continuous_iq/tdd_12db_continuous_iq_02`.
This document does not modify that run or qualify the next source revision.
The final 58-slot run remains held. The latest approved two-port SRS/PUSCH
and QCL/TCI configuration belongs to
`simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml`.

## Why traffic starts at slot 31

The old run uses 15 kHz SCS and 1 ms slots. These are simulated radio times,
not MATLAB wall-clock durations. The following coordinates are explicitly
converted; the frame grid uses zero-based absolute slots, unlike the trial
table and progress log's one-based slots.

| Event | Absolute slot, zero-based | One-based slot | Evidence |
| --- | ---: | ---: | --- |
| PBCH acquisition becomes available | 5 | 6 | initial_access_lifecycle_trace.csv |
| PRACH Msg1 | 14 | 15 | ra_runtime_stage_waveforms.csv |
| Msg2 RAR | 16 | 17 | ra_runtime_stage_waveforms.csv |
| Msg3 PUSCH | 19 | 20 | ra_runtime_stage_waveforms.csv |
| Msg4 | 22 | 23 | ra_runtime_stage_waveforms.csv |
| RRCSetupComplete | 24 | 25 | ra_runtime_stage_waveforms.csv |
| First SRS | 29 | 30 | observed_re_allocation.csv; run.log |
| First scheduled data PDSCH | 30 | 31 | scheduler_decision_log.csv |

All five RA stage rows record actual shared-stream execution, not a synthetic
access timer. At one-based slot 26 the runtime queues SRS for slot 30. Slots
26–28 show no active data candidate while SRS is still unavailable. The
scenario explicitly requires SRS and uses measured sounding for spatial
selection. Do not remove that prerequisite while retaining a claim of measured
beam selection. A separate already-connected/full-buffer LLS profile can
avoid access latency, but that is a declared scenario choice, not this run.

The five-slot TDD pattern has three DL slots, a special slot with 10 DL /
2 flexible / 2 UL symbols, and one UL slot. The old special-slot rejection is
explicit: `configured_dl_symbol_allocation_not_available_in_tdd_slot`.
The old `[2,12]` PDSCH cannot fit 10 DL symbols. The current 12 dB YAML has
both `[index=0,start=2,length=12,K0=0]` and
`[index=1,start=2,length=8,K0=0]` TDRA rows. Actual scheduler selection of the
second row, plus a legal K1/PUCCH occasion, must pass a focused test before
claiming special-slot data is repaired. Flexible symbols are not automatically
available to either direction.

There is no universal 30-slot access-to-traffic rule. NR prescribes the RA
procedure and configured monitoring/timing constraints. For example, the RAR
window depends on the actual PRACH end and configured Type-1 common-search-space
occasion, not a fixed traffic-start delay: [TS 38.213 v18.8.0, 8.2](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).
Real UEs can wait for configured occasions, but this is not evidence that this
particular simulator schedule is latency-optimal or fully qualified.

## Fresh exhaustive file/value audit

Reproduction (read-only with respect to the run):

```powershell
python tools/audit_lls_run_exhaustive.py results/lls/lls_causal_access_to_data_wiring_tdd_short_continuous_iq/tdd_12db_continuous_iq_02 qualification_working/continuous_iq_02_full_reaudit_20260913 --strict-value-closure
```

First pass terminal exit: **1**, not PASS. That pass parsed 1,013 CSV files and
1,300,260 rows, covering 58,683 columns, but was **not exhaustive**. An
independent PowerShell enumeration found 1,048 CSVs. The missing 35 are
long-path `reports/live_measurements/<digest>/...` source/derived snapshots,
not nested SINR sweeps. The earlier sweep explanation was incorrect. Extending
file open/stat paths was insufficient: normal `Path.rglob` omitted files
before opening them. The auditor now traverses the extended Windows path,
raises traversal errors and preserves ordinary relative-path lineage.
Its enumeration agrees with PowerShell at 1,048. Deep-path/case-variant and
inaccessible-directory tests pass with the existing audit regressions (22 tests).
The existing test file rejected editing, so the new guards are in a separate
test module; no ACL or alternate-write bypass was used. The corrected full
audit is being preserved separately as
`qualification_working/continuous_iq_02_full_reaudit_20260913_longpaths/`.

**Corrected terminal result: exit 1.** All **1,048 CSVs / 1,373,809 rows /
65,344 columns** are now inventoried, matching the independent filesystem
count. All 292 PNGs decode; CSV parse and structural failure counts remain
zero. The strict gate finds the two missing primary alignment columns,
**32 uncontracted nonempty historical snapshot files**, and **three
unclassified header-only snapshot files**. Those three are the earlier
`a7be...` checkpoint's CSI-feedback, PDSCH and PUSCH source CSVs. The 32 files
belong to the later `ba9a...` checkpoint. Add explicit historical-checkpoint
lineage/domain/applicability checks; do not inherit current terminal-table
qualification for partial snapshots or invent their missing observations.
The complete path-level inventory is in `csv_file_semantic_disposition.csv`
and `first_three_row_value_assessment.csv` within the corrected audit folder.
The final focused Python suite passed **250 tests** after the enumeration fix.

The incomplete first pass had zero parse/structural failures and
all 292 PNGs decoded. The existing domain contracts evaluated 4,277 CSV and
293 chart checks without required semantic failures. Two required primary
columns remain missing in the old DL/UL tables:
`RuntimeChannelAlignmentLookaheadSamples`. The strict gate correctly fails.
All 14 header-only tables have explicit disabled or zero-event contracts.

Neither a file/row inventory nor its semantic contracts are independent proof of every PHY equation.
The plot defects below were found by visual/source inspection despite the
existing semantic checks passing. Field-domain, TA, beam and receiver-authority
issues remain separately tracked. Non-finite values are inventoried individually;
neither replacing them with zero nor treating every NaN as a failure is valid.
The per-column and per-file inventories are retained under the audit folder.

## Missing, misleading and repeated artifacts

1. The user-supplied old `6GR Simulator/_v2/_clean/_main/artifacts` path does
   not exist on this machine. The actual repository's `artifacts/` does exist
   and includes separate phase/impact tests. Those independent test results
   must not be copied into the 12 dB run and presented as its measurements.
2. `_02` contains constellation PNGs under `analytics/image/`, including
   `contract__constellation-evm-analytics__post-equalization-constellation.png`.
   Visual inspection found a real first-450-sample bias: bootstrap QPSK hid
   later modulation. The renderer now selects a deterministic preview across
   the retained sequence, deduplicates reference markers, discloses the display
   limits and keeps all source CSV rows. A late-sample regression passes.
   This does not regenerate or relabel the immutable old PNG.
3. The existing beam-pattern PNG is a heatmap of a DFT reconstruction, not a
   measured 3D applied SSB/data radiation pattern. `_first_runtime_precoder_pmi`
   accepts requested PMI and defaults to zero; `_runtime_beam_pattern_chart`
   further reduces its index modulo the element count. This is not sufficient
   identity for an applied CSI-RS-basis precoder or its physical-element
   projection. **Open mandatory defect:** replace this path with actual
   executed complex-weight/element-position/basis evidence, separated by SSB
   and data transmission. Add missing/tampered-matrix and nonzero-PMI tests.
4. The observed frame grid lacks RA coverage although the five stage-waveform
   rows are present. Current `runFourStepRA` exports only Msg1's native grid;
   downstream access PDCCH/PDSCH/PUSCH grid production remains incomplete.
   Main continuation merging was also limited to the first stage. It now
   merges each published observed table with physical-identity deduplication.
   This merging fix alone does **not** add missing later-stage producers.
   Add exact executed stage-grid producers, preserve native PRACH coordinates,
   and test stage/slot/sample identity before final validation. Never fill
   the frame grid with rectangles reconstructed from receive metadata.
5. The component-card publisher previously omitted separately derived
   CSV/PNG contracts; the earlier source repair exposes them separately.
   No live-GUI deployment is claimed. The old filesystem browser receipt says
   PASS for artifact materialization, while final `attempt_001/terminal_status`
   says FAIL / `PublicationQualificationFailed`. These are different gates:
   artifact creation did not qualify the simulation.
6. The old receipt explicitly records raster replacement, 292 old rasters
   removed, and an exact-source-cache miss. That explains at least one full
   rerender, not every perceived refresh. The short YAML already defers heavy
   live refresh. Repeated finalization/cache invalidation remains to be traced
   and tested for one-pass/idempotent publication; do not assert it is solved.

## IQ and synchronization

The current independent continuous-IQ checker was executed again against the
old run: **zero failures**. It checked both endpoints, all four port files and
116 endpoint segments against byte hashes, actual finite samples, sample-clock
coverage and waveform/RF hashes. This verifies stored transmitter-IQ integrity,
not M9384B/M9383B import, MIMO synchronization, RF-level calibration or VSA
demodulation. Hardware playback remains a separate acceptance test.

Old timing rows show a seven-sample DL crop and zero reported residual. Their
definition explicitly references the pre-correction estimate; that alone is
not an independent timing-error measurement. The old final control snapshot
has UL alignment 84 samples (10.9375 us at 7.68 Msps), sourced from an UL data
receiver estimate. Do not equate that receiver window correction with a fully
qualified applied MAC timing-advance command. Mandatory reconciliation still
covers received RAR TA, TAG state, N_TA_offset, physical UL emission origin,
propagation, channel filter delay, receiver capture origin and measured residual.
Use known-delay perturbation tests across PRACH/Msg3/SRS/PUCCH/PUSCH and actual
clock receipts; never use expected payload bits to declare synchronization.

Additional recheck: `audit_lls_uplink_evidence.py` observed PRACH=1, PUCCH=4,
PUSCH=5 and SRS=6 rows, with zero failures in its existing consistency checks.
The immutable receipt is `evidence_20260913/old_run_uplink_reaudit.json`.
For all five PUSCH rows, the recorded total TA is 25,600 Tc, or 100 samples
at 7.68 Msps (Tc = 1/1,966,080,000 s). Nominal slot start minus actual TX start
is also 100 samples, with TA available before TX. TX start minus RX capture
start is 77 samples; the exported timing truth and applied crop are 84 samples,
giving zero residual. This is consistent with the seven-sample channel-arrival
term, not a second 84-sample TA command. The current truth producer explicitly
uses capture displacement plus executed channel arrival and RF delay, not the
receiver estimate. The five-row arithmetic is retained in
`evidence_20260913/old_run_pusch_timing_arithmetic.csv`; this bounded baseline
check does not replace the known-delay perturbation/main-path tests above.

## Ordered mandatory gate and future capability boundary

Before the next 12 dB run:

1. Complete main DL received-assignment/report-adapter/UE-HARQ integration,
   without TX-derived receive parameters, double combining or duplicate delivery.
2. Qualify dynamic DAI, PUCCH/PUSCH UCI and received QCL/TCI on the main path.
3. Close the special-slot, access-grid, applied-beam and TA/synchronization
   issues above. Extend semantic tests so the known plot errors cannot pass.
4. Verify requested/applied YAML values, approved two-port SRS/PUSCH TPMI,
   CSI/SS/data power and noise domains, RSSI/EVM and all channel trial counters.
5. Close the newly exposed historical-checkpoint semantic/applicability gate,
   finish focused tests and the recorded disabled-power fixture repair;
   retain every failed attempt. Commit/push the source and evidence checkpoint.
6. Run one fresh 58-slot configured-12-dB scenario, then audit all CSV/PNG/IQ,
   finalization receipts and artifact links. No `testAll` or E2E campaign.

Eight layers are not currently qualified merely because YAML is editable:
the connected DL DCI adapter explicitly supports one codeword and rejects
two-codeword requests. Antenna, logical-port, rank, reference-signal, coding,
codebook and receiver dimensions must be validated together. Unsupported
combinations must fail clearly, not silently reduce rank or modulation.
Single-carrier 400 MHz / 7 GHz, experimental DL 4096-QAM and UL 1024-QAM,
and their 30 dB scenario remain subsequent implementation/qualification work.
Do not call these baseline NR conformance or imply that changing one field
already enables a complete supported chain.

The configuration, NR-validation and result-integrity skills constrained this
audit to actual execution evidence, explicit measurement domains and no
synthetic replacement rows. Full standard/vendor/statistical qualification
has not been achieved by these focused checks.
