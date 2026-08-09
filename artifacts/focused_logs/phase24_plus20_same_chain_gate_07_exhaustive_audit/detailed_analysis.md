# Phase 24 +20 dB same-chain LLS run: exhaustive result analysis

## Scope and conclusion

This report analyzes the completed run at:

`results/lls/webgui_sinr_sweep_64x4_mu_mimo_full/phase24_plus20_same_chain_gate_07`

No new simulator run and no `testAll` execution was started for this analysis. The source run was treated as read-only. Its resolved configuration hash is `ee3eecd238bb5e9c9f232f825a11ad9b094a99c534d03f954e3658d829dda0f8`, and its execution identity is `execution_88017b60-e5a9-42f7-a89e-672dfaa751e2`.

The honest outcome is **execution-complete but qualification-failed**. The physical waveform bundle produced finalized DL and UL trials and most mandatory subsystem evidence. It did not pass the configured/effective MIMO policy gate, required artifact generation, final visual lineage gate, browser completeness contract, or final status-reduction consistency. It must not be described as a successful or publication-qualified LLS run.

## Exhaustive inventory

The offline scanner opened and profiled every CSV and every raster image under the run root:

- CSV files: 932.
- Data rows: 3,785,095.
- Columns across files: 47,311.
- CSV parse failures: 0.
- Header-only CSVs: 3.
- Columns blank in every row of their table: 2,773.
- Duplicate data rows within files: 7,993.
- Byte-identical CSV hash groups: 64.
- `NaN` tokens: 3,976,211.
- `Inf` tokens: 12.
- Raster images: 277, all PNG.
- JPEG images: 0.
- SVG images: 0.
- Raster decode failures or blank/constant images: 0.
- Byte-identical raster hash groups: 12.

The complete machine-readable inventories are:

- `all_csv_file_audit.csv`: file size, SHA-256, row/column counts, structural problems, duplicate-row count and token counts for every CSV.
- `all_csv_column_audit.csv`: blank/NaN/Inf counts, cardinality and numeric min/max/mean for every column.
- `all_raster_image_audit.csv`: SHA-256, MIME-decoded format, dimensions and pixel-variation checks for every PNG.
- `duplicate_csv_byte_hashes.csv` and `duplicate_raster_byte_hashes.csv`: every byte-identical mirror group.

The scanner exits 1 intentionally because the three header-only files are structural findings. It did not crash and did not modify the source run.

## What is correct

### Runtime identity and truth separation

- The completed evidence is bound to one scenario ID, run tag, configuration hash and execution ID.
- `truth_contract_summary.csv` reports zero proxy-guard failures, zero round-trip mismatches and zero canonical artifact gaps.
- All 30 DL and 10 UL data trials are finalized, classified `real_lls_evidence`, and have `FallbackFlag=0` and `PlaceholderFlag=0`.
- The large counts of the words `proxy`, `fallback`, and `placeholder` in the exhaustive lexical scan are mostly schema/audit fields such as `ProxyUsed=0`, `no_proxy`, policy catalogs, and provenance columns. They do not establish proxy data in a primary result table. The authoritative truth gate reports no such contamination.

### Requested radio setup

- The persisted operating point is exactly +20 dB; all DL and UL rows have `ConfiguredSNR_dB=20` and `AppliedAWGNSNR_dB=20`.
- Carrier frequency is 3.5 GHz, bandwidth is 100 MHz, SCS is 30 kHz, and duplexing is TDD.
- DL physical dimensions are 64 transmit elements and 4 receive elements in all 30 rows. `TxWaveformColumns=64` and `RxWaveformBranches=4` in every DL row.
- UL physical dimensions are 4 transmit elements and 64 receive elements in all 10 rows. `TxWaveformColumns=4` and `RxWaveformBranches=64` in every UL row.
- Rank and layers are 2 in every DL and UL data row. The earlier rank-1 execution problem is not present in this run.
- The channel-array status is `runtime_array_shape_spacing_orientation_coupled` for every data row.

### MU-MIMO and reference signals

- DL has 18 MU-MIMO rows in 9 two-user shared-slot groups; UL has 4 MU-MIMO rows in 2 two-user groups. The other rows are honest single-user scheduling rows.
- The UL MU rows apply the configured IRC receive combiner. DL rows do not report a separate MU receive-combiner application; that is not automatically wrong at the UE, but the interference/equalizer definition must be made explicit in the contract.
- PTRS is enabled and CPE correction is applied in all 30 DL and 10 UL data rows.
- Four SSB beams were executed. `ssb_pbch_sib1_beam_sweep.csv` contains SSB indices 0-3 / beam indices 1-4, all PASS.
- Every CSI-RS trial reports 8 configured and 8 measured resources and a 64-element physical CSI-RS transmission model. All 30 CSI reports are exactly bound to measured CSI evidence. Four reports at slots 37-38 are correctly marked pending because their causal due slots 41-42 fall beyond the 40-slot run; they are not silently treated as delivered.
- Eight SRS rows cover all four UEs, two rows per UE, and pass. Two TRS rows pass. All 38 PUCCH rows pass.

### Control and initial access

- All 40 required data grants have waveform-decoded PDCCH binding, CRC success and matching DCI/grant hashes.
- Four PBCH/MIB/SIB1 beam trials pass.
- Four PRACH/four-step-RA rows pass and carry the configured waveform stages through Msg2, Msg3, Msg4 and RRC setup evidence.
- The PRACH and PDCCH statistical qualification table passes. PRACH detection at required +6/+12 dB has 750 trials per point and zero misses, with exact upper confidence interval below 0.01. PRACH false-alarm testing has 7,750 noise-only trials across five operating points and an exact upper confidence interval below 0.001.
- The 40,553 literal failure tokens in `statistical_campaigns/prach/control/csv/prach_strict_trials.csv` are expected negative/noise trial outcomes and field labels, not 40,553 failed acceptance gates.

### SNR and noise-domain physics

- The occupied-grid noise calibration is internally correct: `SignalEnergyPerOccupiedRE / ReplayGridNoiseVariance = 100`, which is exactly 20 dB, in the sampled DL and UL rows.
- DL receiver-Hest and post-equalization SINR are now identical and finite: min 4.912 dB, median 9.185 dB, mean 8.330 dB, max 12.546 dB. EVM-derived SINR is close: median 8.213 dB. The former negative canonical DL SINR defect is not reproduced.
- DL EVM RMS ranges 0.248-0.584 and channel-estimate NMSE ranges -18.68 to -9.51 dB. These are compatible with a fading, rank-2 link whose post-equalization SINR is substantially below the configured AWGN injection SNR.
- `NoiseVariance` is explicitly aliased to different domains by direction: post-equalization in DL and pre-equalization in UL. The detailed domain/source fields make the rows interpretable. Dashboards must not compare this generic alias across directions without using those domain fields.

### Image mechanics

- All 277 raster artifacts are valid PNG files; none is SVG, JPEG, unreadable, implausibly small, blank, or constant.
- Dimensions range from 877x227 to 1984x938. Common standardized sizes are 1100x620 and 1100x520.
- The raster-only output requirement is satisfied mechanically. The visual qualification failure is a lineage-hash problem, not corrupt pixels.

## Formal run failures

`truth_contract_failures.csv` contains five final failures:

1. `AUD-002`: configured/effective MIMO policy evidence failed.
2. The scenario objective gate failed.
3. The active mandatory issue gate failed because `AUD-002` remains active and non-waivable.
4. The visual artifact gate failed: 34 rows in `visual_artifact_integrity.csv` and 17 rows in `visual_artifact_audit.csv` failed.
5. The root result status failed due the combined objective, configured/effective, active-issue and visual failures.

`truth_contract_summary.csv` therefore correctly reports `RuntimeTruthContractOk=0`, `ResultOk=0`, five strict failures, and four required runtime-evidence omissions.

## MIMO / link-adaptation failure

The spatial dimensions are correct, but the nominal operating-point reporting is not:

- Configured DL and UL modulation/MCS are shown as 256QAM/MCS 20.
- The resolved link-adaptation authority is `bounded_adaptive`, with initial/bootstrap MCS 1 and maximum MCS 20.
- DL executes QPSK/MCS 1 for 27 rows and QPSK/MCS 0 for 3 rows.
- UL executes QPSK/MCS 1 for 8 rows and 64QAM/MCS 19 for 2 rows.
- Exact configured/effective operating-point match is therefore 0/40 even though rank, layers and physical arrays match 40/40.
- `mimo_configured_vs_effective.csv` correctly fails DL: spatial match is 100%, but adaptive-policy and execution-contract match are only 15/30 (50%). UL passes its adaptive-policy evidence 10/10.

The configuration currently mixes two different concepts: a fixed rank-2 spatial anchor and adaptive MCS. That is technically supportable, but the report must call 256QAM/MCS20 a maximum/nominal bound, not an exact executed operating point. If an exact MCS20 anchor is desired, the YAML must select a fixed operating-point policy and the scheduler must use it. If adaptive MCS is desired, the four-gate comparator must validate causal CQI/OLLA/range authority rather than demand exact MCS20.

There is also a direct report contradiction: `mimo_kpi_reconciliation.csv` says both `DLConfiguredEffectiveExactOk=1` and `ULConfiguredEffectiveExactOk=1`, even though `configured_effective_operating_point.csv` contains 0 exact rows. It is treating “inside configured MCS range” as “exact.” That status and column definition must be corrected; it cannot be used as passing evidence.

The first-data bootstrap behavior is also questionable at +20 dB. Scheduler evidence has derived MCS19 but still holds DL at bootstrap MCS1 for many rows because feedback remains classified as pending. The causal delay is legitimate for initial slots, but persistent 50% DL policy mismatch indicates the feedback-consumption/eligibility transition or its audit definition still needs repair.

## PHY measurements requiring correction or clarification

### Statistical adequacy

- Empirical data BLER is 0/30 DL and 0/10 UL, but those sample counts are too small for a strong reliability claim. With zero observed errors, the one-sided 95% upper bounds are approximately 9.50% DL and 25.89% UL.
- A single +20 dB point cannot define a waterfall or BLER-vs-SNR curve. It was correctly intended as an execution gate, not the final scientific sweep.
- The artifact generator therefore passes both BLER CSVs but fails `pdsch_bler_vs_snr.png` and `pusch_bler_vs_snr.png`: each has one axis but zero renderable series/finite curve points. Overall artifact contract result is 4/6 PASS and 2/6 FAIL.
- Do not generate fake curves or duplicate the +20 point. The correct repair is to make the single-point gate's figure contract explicitly not applicable, then require real multi-point curve artifacts only for the later `[-20,0,+20]` campaign.

### DL results

- All 30 DL CRCs pass and raw BER is zero. Symbol error rate is not zero: median about 2%, mean 5.48%, max 13.07%, which is plausible after channel coding at low MCS.
- Goodput ranges 16.896-27.152 Mbit/s, mean 26.126 Mbit/s.
- All DL compute/decode/air-interface latency columns are blank. This is a real measurement/export gap because latency charts are requested and the UL path does capture latency.
- DL PAPR is 21.33-23.71 dB, median 23.07 dB. That is unusually high for a conventional scalar OFDM-port PAPR. It may be measuring an aggregated 64-element-domain envelope; the reference plane and aggregation rule must be documented and checked before treating it as RF-chain PAPR.
- `NumRFChains=32` in every DL row and `NumLogicalPorts=32` in the 18 MU rows, while the same rows report a 64x2 precoding matrix and the strict configuration describes two logical ports / a different RF-chain capacity. These fields are semantically inconsistent or ambiguously named. Per-user, group, RF-chain, element and logical-port counts need separate columns and exact reconciliation.

### UL results

- All 10 UL CRCs pass and raw BER is zero. Goodput is 29.712 Mbit/s in MCS1 rows and 401.616 Mbit/s in two MCS19 rows.
- UL post-equalization SINR and EVM-derived SINR agree closely, with medians 27.735 and 27.251 dB. However, receiver-Hest SINR has median 15.459 dB and is as low as 9.49 dB. The large gap needs a documented per-layer/combiner/reference-plane reconciliation, particularly for the high-MCS rows. It is not valid to treat the two fields as interchangeable.
- UL decode latency ranges 37.95-5070.86 ms, median 94.40 ms and mean 617.94 ms. The 5.07 s outlier is a serious performance problem and should be tied to trial/MCS/stage profiler evidence.
- `NumLogicalPorts` and `NumRFChains` are blank in every UL data row despite physical 4x64 execution. Those runtime architecture fields are missing from the UL export.

## CSV and schema findings

### Three header-only files

1. `mobility/csv/trajectory_constraint_conflicts.csv`: no conflicts in a fixed-SINR/non-mobility run. This should be omitted or explicitly published as a zero-conflict summary/not-applicable artifact.
2. `reports/csv/dl_pdsch_objective_failures.csv`: no DL objective-failure rows. This needs an explicit zero-count status or omission, not an ambiguous empty public table.
3. `reports/csv/live_cell_reselection_events.csv`: reselection is not applicable to this fixed-SINR run and should be policy-disabled rather than header-only.

### Broad union schemas

The 2,773 all-blank columns and 3.98 million `NaN` tokens are dominated by common raw schemas that carry fields for unrelated signal families. This is mostly honest N/A data, not fabricated evidence, but it makes CSVs very wide and difficult to use. The public component tables should expose narrow domain-specific schemas, while the full union schema remains an internal raw/provenance artifact.

The 12 `Inf` tokens occur only in `ExpectedMax` fields in `generated_value_plausibility_audit.csv` and its `phy_value_invariant_checks.csv` mirror. They represent intentionally unbounded thresholds, not non-finite runtime measurements. A text value such as `unbounded` would be clearer than numeric `Inf` in public CSVs.

### Duplicate rows and files

The 7,993 duplicate rows are mainly legitimate repeated occupancy/sample values, but several analytic outputs lack an explicit aggregation key. The largest examples are CSI-RS occupancy maps (3,276 duplicate rows in each of two mirrors), active-bandwidth-vs-power (260), constellation samples (232), rank-vs-power (171), and condition-number distributions (95 per mirror). These need key/aggregation metadata so repeated values cannot be confused with accidental overwrite or append duplication.

Sixty-four byte-identical CSV groups and twelve byte-identical PNG groups are mostly deliberate analytics/report mirrors. They are not row overwrites, but they inflate the WebGUI and make the output hierarchy confusing. The canonical artifact should be stored once, with aliases in a manifest rather than duplicate physical files.

### Corrupt Phase-7 CSV serialization

`phase7_truth_gates.csv` has a real table-shape/semantic corruption. Failure codes spill from `FailureCodes` into `PrimaryFailureCode`, `GeneratedAt`, `ProducerModule`, `RunClass`, applicability columns and generated `Var77` through `Var108`. For example, `GeneratedAt` contains `MobilityStateContinuousOk_false`, while the actual timestamp is displaced to `Var101`. The writer is constructing a non-scalar failure-code value and MATLAB expands it across columns. The failure list must be serialized to one scalar string/list field before table construction, and a schema regression test must reject any `VarN` columns.

## Status-reduction and finalization defects

Several final status artifacts contradict the authoritative final truth table:

- `result_status_summary.csv` says `TruthContractOk=1` and `RuntimeTruthContractOk=1`, while the later final `truth_contract_summary.csv` says both runtime truth and result are false.
- `scenario_objective_gates.csv` records the runtime-truth objective as observed true/pass despite the final truth failure.
- `strict_anchor_acceptance_report.csv` marks artifact completeness and runtime truth as passing based on stale status values even though the artifact contract and final truth contract fail.
- `result_issue_registry_evaluation.csv` says `IssueRowCount=0`, while `result_issue_registry.csv` contains active critical `AUD-002`. If the former counts only source-derived issues, it must be named and scoped accordingly; it cannot appear to evaluate the final registry.
- `scenario_consistency_check_table.csv` expects inter-cell interference enabled, but the resolved YAML explicitly has `inter_cell_interference_flag=false`, `inter_cell_execution_mode=none`, and a one-cell topology. That failure is produced by an incorrect expectation reducer, not by the runtime.
- `live_required_vs_optional_case_status.csv` correctly sees the ten required component blocks, but separately marks many enabled features—HARQ, initial access, PDCCH, PRACH, PUCCH, SRS, RF impairments, raw capture and others—as `not_observed`. Its feature-policy rows are not bound to the component evidence rows and are misleading.

Final status generation is not atomic. `result_status_summary.csv` was written at 06:31:06, the truth contract was re-evaluated at 06:31:08, and only the scenario summary/manifest were rewritten. All dependent status and acceptance artifacts must be generated after every terminal gate, from one immutable terminal status object, or invalidated and regenerated together.

The optional MAT bundle also failed with `iolib:badbit`; MATLAB warned that `Result` was not saved and recommended MAT v7.3 for variables larger than 2 GB. The writer must use `-v7.3` or store a compact result index instead of embedding massive tables.

The post-run helper then asserted that the canonical coupled slot trace was missing. This is an object-wiring defect: both `reports/csv/slot_trace.csv` and `packet_flow/csv/slot_trace.csv` exist with 40 rows. The returned `Result` object did not expose/reload the persisted trace after resumed finalization.

## Visual lineage and browser coverage

### Visual integrity

Seventeen unique component figures fail lineage verification; they appear twice in `visual_artifact_integrity.csv`, producing 34 failed rows. All are valid PNGs, but their current source CSV bytes differ from the source hash recorded when the figure lineage was created.

The affected plots are seven PDCCH plots and ten PRACH plots: CORESET grid, candidate metrics, wrong-RNTI rejection, false-alarm probability, low-SNR detection, decode flow, DCI-to-grant flow, PRACH grid, positive/noise correlation, false-alarm/missed-detection curves, timing histogram, restricted-set comparison, collision peaks, occasion map and detection flow.

The likely ordering defect is that source CSVs are annotated or rewritten after plot-lineage hashes are recorded. Source tables must be finalized first, then hashed, then plotted, and neither the plot nor its source may be mutated afterward. The integrity table should contain one row per plot rather than duplicate audit representations.

### Strict WebGUI materialization

- Tables: 171 available, 18 policy-disabled, 4 missing out of 193.
- Charts: 231 available, 55 policy-disabled, 82 missing out of 368.

The four missing tables are `live_site_table.csv`, `live_sector_table.csv`, `live_trp_table.csv`, and `live_ue_table.csv`. In a fixed one-cell LLS run, some topology views may be not applicable, but the contract currently labels them missing rather than policy-disabled.

The 82 missing charts include genuine enabled-feature gaps: PRACH timelines/distributions, DMRS/PTRS occupancy, PHR/power-control and HARQ combining views, PDCCH/PBCH/CSI/LDPC/channel-estimation/equalizer latency, waveform stage overlays, true/estimated impulse and frequency responses, channel heatmaps, impairment decomposition, RF-chain/UE power, compute/worker/DB/export telemetry and determinism comparisons. The exact semicolon-separated list is preserved in `contract_materialization_coverage.csv` and the finalization log.

`honest_unavailable_registry.csv` contains 37 rows. It is useful because it does not fabricate plots, but several rows are only broad `backend_source_missing` labels even though related raw evidence exists elsewhere. Those schema adapters need direct identity-bound source mappings.

## Component-folder publication

The requested run-local component hierarchy is not active. The resolved configuration has:

`output.component_artifact_views.enabled: false`

and finalization logs `Publishing component artifact views: enabled=0 required=0`. Therefore the run does not contain complete canonical `/prach`, `/pdsch`, `/pusch`, `/pdcch`, `/mimo`, `/waveform`, and other component views. The only `component_anchors` content is limited protocol evidence.

The separate root `results/lls/canonical_component_rebuild/qualification_wave_01` contains 321 CSVs and 209 PNGs from component validation campaigns. It is not a substitute for this run: its manifest identifies `component_validation_campaign`, not this run's execution ID/config hash. Its own summary also fails channel, integration and MIMO qualification. Historical files under `artifacts/initial_access_phase`, `artifacts/pdcch_dci_phase`, `artifacts/pdsch_dlsch_phase`, and `artifacts/pusch_ulsch_phase` date from July 25-26 and must not be represented as outputs of this August 9 run.

## Runtime source-usage audit defect

`phy_package_execution_audit.csv` claims a complete 4,995-function profile, but reports zero called files for all PDSCH, PUSCH, PUCCH and RX package inventories. It does record 34 PDCCH and 5 MIMO files. This conflicts with the persisted 30 PDSCH, 10 PUSCH and 38 PUCCH waveform rows.

The run was resumed/finalized across MATLAB processes; the exported profiler appears to cover only one process segment while `ProfilerComplete=1` is interpreted as complete for the entire run. The audit must merge profiler segments by execution ID and process/segment ID, or explicitly report `partial_resume_segment_profile`. Until then it cannot prove that every production function under the requested package roots participated in the same Tx/Rx chain.

## Repair order before another sweep

1. **Make terminal status atomic.** Finalize artifact generation, visual lineage, browser materialization and issue reduction first; then write one terminal status object and regenerate every dependent CSV/report from it. Add cross-file equality tests for truth, objective, strict-anchor, scenario-summary and issue counts.
2. **Repair CSV serialization.** Scalarize Phase-7 failure lists, prohibit `VarN` spill columns, and distinguish an empty event table from a missing/not-applicable artifact.
3. **Resolve MCS authority semantics.** Keep fixed rank and adaptive MCS as separate gates. For adaptive mode, compare every grant with its causal CQI/OLLA/bounds decision; for a fixed anchor, disable adaptation and require exact configured MCS/modulation. Correct `mimo_kpi_reconciliation.csv` so range conformance is never called exact conformance.
4. **Repair DL feedback transition.** Explain or fix why derived MCS19 remains held at bootstrap MCS1 for half the DL rows; bind report-due/delivered/consumed CSI state to each scheduled grant.
5. **Correct configuration consistency.** Derive inter-cell expectations from the explicit inter-cell flag/mode, not broad intra-cell/MU interference enablement.
6. **Repair visual lineage ordering.** Finalize source CSVs before hashing/plotting and prohibit post-lineage annotation rewrites. Remove duplicate integrity rows.
7. **Enable identity-bound component views.** Publish each canonical component folder from this exact execution, with source hashes and execution/config identity. Do not copy historical phase artifacts into the run.
8. **Make profiling resume-aware.** Persist and merge per-process profiler segments; do not call a partial segment complete. Reconcile exported package usage against trial `RuntimeEvidenceSource` and function-call edges.
9. **Complete measurement exports.** Add DL stage/decode latency, UL logical-port/RF-chain evidence, explicit PAPR reference planes, and a documented relation among H-estimate, post-equalization and EVM SINR. Investigate the 5.07 s UL decode outlier.
10. **Repair final result storage.** Use MAT v7.3 or a compact artifact index and reload the persisted 40-row slot trace into the returned result object.
11. **Close browser gaps by policy or evidence.** Mark genuinely inapplicable fixed-LLS topology/mobility views disabled; implement the enabled waveform, RS, HARQ, RF, latency and compute charts from direct runtime evidence.
12. **Only then run the three-point campaign.** The +20 gate must first pass its applicable contracts. The later `[-20,0,+20]` run must use enough frames/error events for confidence intervals and real BLER curves; no values or plots may be synthesized from configuration.

## Final classification

- **Correct:** physical array dimensions, rank/layers, real waveform provenance, PDCCH-to-grant binding, four-beam SSB, eight-resource CSI-RS measurement, SRS/TRS/PUCCH execution, strict PRACH/PDCCH statistics, occupied-grid 20 dB noise calibration, DL post-equalization SINR correction, raster PNG integrity.
- **Failing:** configured/effective DL adaptive policy, scenario objective, active issue gate, two required BLER PNG contracts, 17 unique source-lineage checks, strict browser completeness, root truth/result status.
- **Incorrect reports:** stale result/anchor/objective truth flags, false MIMO exact-match reconciliation, displaced Phase-7 columns, issue-registry count mismatch, inter-cell expectation mismatch, non-cumulative profiler completeness.
- **Missing/incomplete:** run-local component publication, DL latency, UL logical/RF port counts, valid single-point artifact applicability, 82 strict charts, four live topology tables or correct policy classification, successful MAT bundle, returned slot trace wiring, full three-point statistical campaign.

This run is valuable evidence that the principal waveform execution path now works at +20 dB, but it is **not yet a 10/10 production-grade or publication-qualified 3GPP LLS result**.
