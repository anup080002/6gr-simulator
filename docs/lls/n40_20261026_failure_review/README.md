# n40 slot-58 failure and partial-report recovery

For the current applied-code state, three outstanding test failures and
remaining P0 integration work, see the
[27 October checkpoint](P0_CHECKPOINT_20261027.md).

This review concerns only `n40_integration_60slots_20261026_100846`, its
`reference_esn0_20_db` child, and the original evidence retained on E:.
The run failed at slot 58. Checkpoint 55 exists; checkpoint 60, the second
0 dB child, native 55-to-60 continuation and final acceptance remain unverified.
No new full scenario was started during this repair. Focused physical tests
remain separate from full-scenario acceptance.

The [39-family measurement inventory](measurement_inventory_review.csv) and
its [machine-readable evidence index](measurement_inventory_review.json) give
each attached item an original-run result, current repair result and remaining
qualification. A scoped arithmetic or publication PASS does not mean that all
populations, antenna reference planes or standards accuracy requirements passed.

Further MATLAB corrections found during that review include the data-SINR
status alias, CSI latency across the actual received RNTI transition, the
DTX-to-ACK denominator, multi-port spectrum normalization and opaque-byte
preservation in measurement sidecars. The original CSI latency now reconciles
to 6.4880859375 ms in a separate retained-evidence check. The original
388 modeled radiation intervals recompute exactly from their retained RF,
covariance, installed field and native-channel installation records; seven
source hashes remain unchanged. Accepted-feed and hardware qualification stay
false. All original failed attempts and intervening failed regression results
remain retained alongside their later corrections.

## Why the folder looks empty

The sweep parent contains indexes. Actual receiver results are under
`sweeps/reference_esn0_20_db`. That child has 320 current CSVs: 291 with data
and 29 without rows. Including immutable live snapshots, the inventory is
470 CSVs with 6,780,716 rows. All 61 retained raster images decode successfully.
These counts describe file contents, not scientific qualification.

Small receiver summaries were deferred until the heavy slot58 refresh. The
energy consumer failed before that refresh reached them. Other missing files
belong to terminal finalization or unexecuted events. Empty RA collision/retry
tables are not evidence that actual payload bytes or successful trials were lost.

## Confirmed defects and corrections

| Defect | Correction and evidence boundary |
|---|---|
| Native logical RA flags became NaN through text conversion, causing the fatal executed-observation rejection | Read typed numeric/logical scalars. Keep capture, identity, source, binary-flag and self-loop guards. Actual retained energy export and native/CSV equivalence are tested separately from a new RF run. |
| Channel/rank/CSI/LA/error/KPI summaries remained at startup; HARQ was one publication behind at the failing heavy milestone | Publish compact receiver summaries and committed-primary HARQ before heavy energy/plot work. Reuse full-export reducers and preserve unavailable values and runtime-owned elapsed-time throughput. |
| Scheduled SRI was NaN although original single-resource DCI selected index0 implicitly | Project from original finalized DCI bits/context, verify hashes and direction/RNTI, reject conflicting aliases. Do not substitute a sounding resource ID or current configuration. |
| Later queued CSI reports lacked scenario/config/run/execution identity | Bind at original report creation, preserve lifecycle through received-field projection, and reject source/delivery context conflicts. Do not retrofit old CSVs. |
| Empty BCH/CSI byte columns in heterogeneous PRACH rows became non-hex applicability text | Preserve opaque byte/bit and decoded-identity fields through categorical decoration. Existing malformed values are neither erased nor accepted by the audit. |
| Live MCS/CQI reference tables lacked scenario/config identity | Bind the original producer configuration lifecycle before publication, without claiming PHY execution of reference rows. |
| Audit confused future feedback scheduling with the current executed grant | Validate original frozen-grant context, MCS aliases, modulation, source and materialization status. All 12 DL and one UL original rows pass the corrected operating-point check. |
| Generic CSV audit rejected legitimate evidence fields larger than128KiB | Bound the reader by actual artifact size and preserve full quoted contents. Reparse the20 affected original files with unchanged hashes; do not rerun or replace physical evidence. |
| Four quiet SSB search candidates shared an unavailable detected-resource identity | Preserve the requested candidate and original capture identity separately. Do not deduplicate distinct searches or turn a search miss into a detection. |
| Unavailable serialized power vectors were decorated with categorical text and blocked valid physical-plane plots | Preserve empty numeric operands. Plot actual internal receive-element power with its original plane and explicit qualification limits. Reject real mixed-plane data. |
| SRS EVM CSV omitted the original isolation proof needed by the plot consumer | Export the validated scalar logical proof and original pair-record digest. A source label or digest alone remains insufficient. |
| First valid spatial feedback was subjected to the steady-state rank-up confirmation policy | Add an explicit initial-acquisition policy of one received spatial report; retain two-report confirmation for later rank increases and existing MCS/ACK guards. Keep uncalibrated SRS CQI unavailable. |
| Causal-stage PDCCH and precoder evidence was written only after successful waveform return | Reuse strict final-report reducers in compact live publication and the failed-run path. Original error status remains failed; only retained receiver rows may contribute. |
| MIMO evidence could fall back to ConfiguredPMI when applied evidence was absent | Remove the configured-only fallback. Preserve actual applied PMI and matrix-hash paths; no configuration value proves execution. |

## Available recovered reports

Original results remain unchanged. Recovered partial reports are in:

`E:/SixGRResults/diagnostics/n40_failure_20261026_slot58/report_replay02`

The lightweight publication replay is in sibling `compact_receiver_summaries`.
These are separately identified diagnostics, not completed scenario results.

| Recovered artifact | Rows / result |
|---|---:|
| `reports/csv/live_link_adaptation_input_table.csv` | 13 |
| `reports/csv/live_channel_estimation_stats.csv` | 21 |
| `reports/csv/live_rank_estimation_stats.csv` | 6 |
| `reports/csv/live_csirs_stats.csv` | 3 |
| `reports/csv/live_error_rate_summary.csv` | 4 |
| `harq/csv/live_harq_observation_timeline.csv` | 13 |
| `rf/csv/energy_common_signal_observations.csv` | 6 |
| `rf/csv/energy_endpoint_timeline.csv` | 656 |
| `rf/csv/energy_timeline_trace.csv` | 734 |
| Scheduler receiver reconciliation | DL12 / UL1; correct original payload credit |

Energy rows are modeled accounting of retained observations. Their presence
does not prove hardware-power accuracy, complete RF coverage or full-run energy.

## UL throughput and adaptation

The only completed UL trial is slot 55: MCS 1, rank 4, CRC pass and 5,000 unique
payload bits. Its 10 Mbps rate uses 0.5 ms trial exposure. The elapsed-run value is
0.172413793 Mbps over 29 ms. Neither calculation includes the unexecuted UL60 grant.
DL delivered 16,792 bits over 12 trials: 2.798666667 Mbps summed trial-exposure goodput.
All 13 actual data trials passed CRC; DL MCS stepped from 1 to 2.

Access completed around slot 40. The first SRS at 45 became available at 46,
but the old policy waited for SRS50 before issuing control51 for PUSCH55.
The repair separates initial acquisition from later rank increases: first
valid SRS45 can authorize control46 for PUSCH50 with K2=4. Pre-SRS scheduling,
stale reports, duplicate reports and inconsistent source contexts remain rejected.
Earlier connected PUSCH would require a different legal access/SRS/grant calendar.

The selected CSI reporting period also changes from ten to five slots, with
offset three, so a report can use PUCCH44. Its ten-slot reference age remains:
report44 uses reference34 and actual CSI26, never the later CSI36. Data continues
while waiting for legally received feedback. Initial acquisition, MCS steps
and ACK confirmation are implementation policies, not 3GPP-mandated step sizes.
The retained data does not justify fabricating a CQI, ACK, intermediate rank
or completed UL60 transmission. See the
[uplink review](uplink_review.md) and [standards review](standards_review.md).

Eight affected policy tests have latest passing results across retained batches
03/04/05. The structured `initial_spatial_policy_test_receipt.json` binds each
result to its log hash and retains the earlier failed fixture attempts. The
UL50 result uses the real planner with an explicitly declared received boundary;
it does not claim physical UL50 reception. The existing n40 integration-gate
preflight and 60-slot/checkpoint horizon checks also pass.

## Measurement previews

The production publisher generated 33 diagnostic charts from unchanged original
CSV operands in `measurement_preview02`. A separate SRS replay validates three
original trial records, 55,296 paired samples and four unchanged source hashes;
its proof-bearing export provides one additional SRS chart. All 34 PNGs decode,
and their plotted-CSV and image hashes were verified in `power_plot_verification.json`.
These remain partial diagnostic previews. Internal modeled power is not a
standardized antenna-connector or hardware-accuracy qualification. A throughput
versus SNR chart remains unavailable because no measured calibration-SNR axis
exists; the configured reference Es/N0 is not substituted.

## Audit interpretation and reproducibility

The original semantic audit retains1081 checks with87 required failures plus
one chart failure. The separate triage preserves every failure:78 concern
interrupted/unreached exports, two concern stale HARQ publication, two concern
the old scheduling-audit contract, and six concern the three producer identity/
opaque-literal issues. These are failed checks, not88 independent PHY crashes.
The only logged fatal runtime identifier is
`sixgr:truth:UnexecutedCommonSignalObservation`.

Diagnostic root:
`E:/SixGRResults/diagnostics/n40_failure_20261026_slot58`.
`semantic_early/required_failure_triage.json` preserves original audit hashes;
`large_field_audit_recheck/receipt.json` records all20 successful wide-field
rechecks. The original exhaustive audit remains retained with its original
reader failures. `updated_operating_point_audit.json` records the corrected
check against unchanged raw DL/UL rows.

Focused MATLAB checks and original-data replays are recorded in that directory.
137 Python audit regressions passed. The first report replay exposed a
diagnostic-only assumption that all CRCs were available; its correction preserves
legitimate NaNs. Replay02 passed all four production reporting stages, while its
extra scheduler comparison exposed an optional-column assumption in the harness.
The small follow-up reconciliation links those passing stages by hashes rather
than claiming another energy or waveform execution. Failed harness attempts are
preserved alongside corrected receipts.

A fresh two-point 60-slot integration gate is still required to establish
checkpoint60, the actual continuation and complete final reports. No repair or
replay in this review makes the failed original run pass that gate.

## Issue ledger cleanup

All 221 original active rows were reviewed on 26 October. Thirteen scoped repairs
were moved out of the active HTML list. Fresh native completion, wider branches
and independent statistical qualification remain open once in their proper scope.
The per-row disposition is retained in [gap_review.json](gap_review.json); original
HTML and full evidence notes remain in the diagnostic directory.

| Removed active item | Closure scope |
|---|---|
| P0 — SRS noise receipt and isolated-pilot EVM publication | RESOLVED SRS RECEIPT/PROOF PUBLICATION DEFECT |
| P0 — Persisted RF recovery execution identity | RESOLVED SCOPED DEFECT — move to closure inventory |
| P0 — TRS continuation OFDM metadata | RESOLVED SCOPED DEFECT — move to closure inventory |
| P0 — SRS/PUCCH resource repair: full n40 verification | RESOLVED SCOPED DEFECT — move to closure inventory |
| P0 — Slot-45 timing outcome repair: full n40 verification | RESOLVED SCOPED DEFECT — move to closure inventory |
| P0 — SRS retained-reference preparation: integrated verification | RESOLVED SCOPED DEFECT — move to closure inventory |
| P0 — Failed recovery measurement parsing: integrated publication | RESOLVED SCOPED DEFECT — move to closure inventory |
| P0 — Causal-audit downstream publication and integrated acceptance | RESOLVED STAGE PUBLICATION — 28/28 retained-evidence replay checks pass |
| P1 — Parameter-consumer provenance | RESOLVED CURRENT PARAMETER-CONSUMER BINDINGS |
| P0 — Off-centre SSB receiver OFDM phase reference | RESOLVED OFF-CENTRE SSB PHASE DEFECT |
| P0 — Initial acquisition waits for full archive and misses first SI | RESOLVED INITIAL-CAPTURE DELIVERY DEFECT |
| P0 — CSI/TRS acquisition and installation: full integration | RESOLVED ORIGINAL CSI CELL-STAMP DEFECT |
| “BLER” is derived from a generic scalar such as min(1,Value/100) . | RESOLVED FABRICATED RF BLER DEFECT |

The original causal-stage export remains failed with 17 PASS and 11 blocked or
missing-publication stages. The corrected live publisher passes all 28 stages
in separate retained-data replay03: 15 control bindings, 13 applied precoder
rows and 13 link-adaptation rows (five applied/eight unapplied). All 23 original
file hashes and RNG remain unchanged. Its 85/85 parameter-consumer bindings
are a distinct passing check. None of these diagnostics completes the failed
native run or replaces its original receipts.
