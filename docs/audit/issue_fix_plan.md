# LLS Conformance Hardening Issue Plan

This plan is intentionally fail-closed. An issue moves to `fixed` only when the
runtime behavior, exported artifacts, and regression tests all prove the
underlying implementation is present. Renaming fields, hiding rows, or changing
thresholds is not a valid closure path.

## Audit Input Status

The prompt referenced three audit files:

- `6GR_Simulator_v2_blunt_audit_report.md`
- `6GR_Simulator_v2_existing_issues.csv`
- `6GR_Simulator_v2_result_artifact_inventory.csv`

They were not present in the repository during this pass. The tracked backlog in
`docs/audit/issue_fix_backlog.csv` therefore preserves the concrete prompt
findings as `AUD-*` rows and keeps them open unless there is direct code and test
evidence. If the full 350-row CSV becomes available, import it into the same
schema and preserve its original issue IDs.

## Repair Groups

| Group | Backlog IDs | Primary Modules | Tests / Evidence |
|---|---|---|---|
| Run status and truth gates | AUD-001, AUD-002, AUD-PDSCH-001 | `+sixgr/+truth/evaluateLLSRuntimeTruthContract.m`, `+sixgr/+lls6g/+runners/runSingle.m` | `testLLSRuntimeTruthContractGates`, `testLLSStrictConformanceIssueGates`, `reports/csv/truth_contract_summary.csv` |
| Configured-vs-effective operating point | AUD-002, AUD-MIMO-RANK-001 | `+sixgr/+truth/summarizeEffectiveOperatingPoint.m`, scheduler AMC/rank selection | `testLLSEffectiveOperatingPointSummary`, `reports/csv/scenario_summary.csv` |
| RRC and initial access | AUD-015, AUD-RA-001, AUD-PRACH-001 | SSB/PBCH/SIB1/PRACH producers and control CSV exporters | `testTruthValidationControlCoverage`, RA focused tests, `control/csv/ra_attempts.csv` |
| Control channels and reference signals | AUD-PDCCH-001, AUD-TRS-001, AUD-SRS-001 | PDCCH/PUCCH/SRS/TRS runtime paths and exporters | `testTRSReferenceSignalExecution`, `test6GCSIReportingCoverage`, `air_interface/csv/pdcch_trials.csv` |
| Data-plane receiver and KPIs | AUD-KPI-UL-GOODPUT, AUD-UL-SINR-001 | PDSCH/PUSCH RX, HARQ, KPI summary/raw consistency | `testPostEqSINR`, `testLLSSummaryRawConsistency`, `air_interface/csv/ul_pusch_trials.csv` |
| Channel and RF configured-vs-applied | AUD-CHANNEL-RF-001 | `+sixgr/+channel/*`, `+sixgr/+rf/*`, strict Channel/RF mini runner | Channel/RF focused tests, `channel/csv/channel_configured_vs_applied.csv`, `rf/csv/rf_impairment_chain.csv` |
| Visual and artifact integrity | AUD-PLOT-001, AUD-ARTIFACT-DUP-001 | `+sixgr/+visual`, `tools/audit/audit_lls_visual_artifacts.py`, report bundle writers | `tests/test_audit_lls_visual_artifacts.py`, `reports/csv/visual_artifact_audit.csv` |
| Dashboard dependency and DB routing | AUD-PY-MYSQL-001 | `apps/lls_web_dashboard.py`, `apps/start_lls_web_dashboard.ps1` | `tests/test_lls_dashboard_optional_mysql.py`, Python import collection |

## Closure Rules

| Status | Meaning |
|---|---|
| `open` | The underlying behavior is not implemented or not verified. Strict runs must fail closed if this issue is mandatory. |
| `in_progress` | Code is being changed in this branch. It is not accepted until tests pass. |
| `fixed` | The issue has implementation evidence, regression test coverage, and exported artifact evidence. |
| `verified` | A run or test artifact confirms the fix after merge. |
| `waived_non_blocking` | Non-critical issue has a documented owner-approved waiver and does not affect strict conformance. |

Critical issues cannot be waived. High and medium issues block strict anchor
conformance unless explicitly marked `waived_non_blocking` with a justification
and the scenario declares that the affected block is not part of the objective.

## Current Truth-Gate Closure Notes

`AUD-001` is closed for the runtime truth-contract/status gate. Strict runs now
separate run completion from truth/conformance status, count active
critical/high/medium issue-registry rows as mandatory blockers, and export those
counts through `truth_contract_summary.csv`, `scenario_summary.csv`, and the
scenario manifest. Rows remain blocking until their status is one of the
resolved statuses such as `fixed`, `verified`, `closed`, or an explicitly
documented non-blocking waiver.

`AUD-002` is closed for fixed operating-point objective gating. The effective
operating-point summary preserves configured nominal DL/UL rank/layers,
modulation, and MCS separately from observed runtime histograms. Strict fixed
operating-point scenarios fail `ScenarioObjectiveOk` when the configured-match
rate from raw DL/UL trial rows is below the required threshold. Adaptive
CQI-driven scenarios are not forced through this exact-match gate.

## Current UL Data-Plane Closure Notes

`AUD-UL-SINR-001` is in progress. The current working-tree patch adds a strict
UL PUSCH receiver evidence gate and exports it in `ul_pusch_trials.csv`.
Strict/no-proxy UL rows must now prove DM-RS channel estimation, PUSCH resource
extraction, equalization, UL-SCH decode evidence, finite LLRs, and
receiver-derived post-equalization SINR. Configured-SNR/proxy/fallback/oracle-
looking SINR sources are rejected by `validatePUSCHReceiverEvidence`.

This does not close the entire AUD-UL-SINR-001 prompt yet. Remaining closure
items include the strict mini scenario artifacts, high-rank/256QAM fixed-anchor
positive validation, the full negative fault matrix, and configured-vs-effective
rank/modulation validation. KPI raw-vs-summary accounting is closed separately
under `AUD-KPI-UL-GOODPUT`; this receiver gate must not be used to claim that
KPI closure by itself.

## Current KPI Accounting Closure Notes

`AUD-KPI-UL-GOODPUT` is closed for raw-to-summary KPI accounting. The link KPI
exporter now reconstructs the legacy scalar summary from direction-filtered raw
DL/UL trial rows and writes canonical audit artifacts under `reports/csv/`:
formula registry, source manifest, raw schema audit, reconstruction summary,
row-level contributions, HARQ delivery trace, direction isolation, legacy alias
map, known-bug regression, unit conversion, duration source, and objective
binding. `Goodput_UL_max_Mbps` is generated only from `Direction=UL` rows and
the audited DL-to-UL copy case (`DL=40.137091 Mbps`, `UL=7.952 Mbps`) is covered
by `testKPIULGoodputNotCopiedFromDL`.

This closure is intentionally scoped. It implements HARQ deduplication for KPI
goodput accounting only; it does not claim full MAC/HARQ timing/procedure
conformance. MAC and application goodput formulas are registered but remain
unavailable unless the corresponding MAC SDU or application packet delivery rows
exist. `AUD-UL-SINR-001` remains tracked separately for receiver-chain evidence.

## Current Initial-Access Closure Notes

`AUD-RA-001` is closed for the explicit unrestricted contention-based four-step
anchor profile only. The implementation exercises MSG1 PRACH detection, MSG2
RA-RNTI PDCCH plus MAC RAR over PDSCH, Msg3 PUSCH from the decoded RAR UL
grant, and Msg4 contention resolution using the temporary C-RNTI. Exported
evidence lives under `control/csv/ra_*.csv` and `reports/json/msg*_*.json`.

`AUD-PRACH-001` is closed for the implemented NR-baseline strict PRACH mini
profile only. The strict profile derives PRACH configuration from resolved YAML,
uses waveform generation/detection, validates long-sequence unrestricted,
restricted-set type A, and restricted-set type B N_CS/ZCZ/root-budget mappings,
and exports positive, missed-detection, false-alarm, timing, frequency-offset,
collision, multi-occasion, negative wrong-config, and oracle-guard evidence.
Unsupported PRACH profiles remain fail-closed and must not be counted as fixed
without equivalent waveform artifacts.

`AUD-PDCCH-001` is closed for the implemented NR-baseline strict PDCCH mini
profile only. The strict profile derives CORESET/search-space/RNTI/DCI config
from resolved YAML, uses the waveform-backed PDCCH Tx/Rx path with
`nrDCIEncode`, `nrPDCCHResources`, `nrPDCCH`, `nrPDCCHDecode`, and
`nrDCIDecode`, exports candidate-level blind-search rows, DCI field equality,
decoded-grant validation, wrong-RNTI/no-signal/corruption/wrong-format/invalid
grant negative evidence, false-alarm and low-SNR sweeps, and an oracle guard.
Unsupported DCI/RNTI/search-space combinations remain fail-closed and must not
be counted as fixed without equivalent waveform artifacts.

`AUD-TRS-001` is closed for the implemented NR-baseline strict TRS mini profile
only. The strict profile derives NZP-CSI-RS/TRS resource configuration from
resolved YAML, executes real resource mapping, waveform/channel, detection,
timing tracking, CFO/frequency tracking, and channel-estimation checks, exports
positive, negative, sweep, and oracle-guard evidence, and extends the runtime
TRS-required gate so metric-only rows cannot mark a cell valid. Unsupported
multi-port or advanced TRS profiles remain fail-closed and must not be counted
as fixed without equivalent waveform artifacts.

`AUD-SRS-001` is closed for the implemented NR-baseline strict SRS mini profile
only. The strict profile derives `nrSRSConfig` from resolved YAML, generates real
SRS symbols/indices/waveform, extracts SRS from received UL grids at the gNB,
estimates the UL channel from receiver SRS REs, validates configured/full-carrier
coverage from actual PRB occupancy, and exports trigger, coverage, low-SNR,
timing-offset, multi-UE, negative, and oracle-guard evidence. Unsupported SRS
resource types/usages, incomplete hopping coverage, semi-persistent activation,
and aperiodic SRS without decoded DCI trigger evidence remain fail-closed and
must not be counted as fixed without equivalent waveform artifacts.

`AUD-CHANNEL-RF-001` is closed for the implemented strict Channel/RF mini profile
only. The strict profile derives Channel/RF settings from resolved YAML, rejects
bare TDL/CDL family names, builds geometry evidence, applies large-scale
pathloss/shadow/O2I to waveform samples, executes AWGN/TDL/CDL channel
realizations with path gains and snapshots, applies Doppler, waveform-overlap
interference, thermal noise, and RF CFO/IQ/PA/timing/quantization to samples,
and exports configured-vs-applied positive/negative rows plus oracle/downstream
reference guards. This closure does not claim that every production PDSCH/PUSCH
trial row is now fully wired to ChannelRealizationId/RFImpairmentChainId; that
lineage expansion must be closed separately with equivalent runtime evidence.

`AUD-MIMO-RANK-001` is closed for the implemented MIMO rank/layer/beam evidence
gate. The link KPI export now writes MIMO evidence artifacts under
`beamforming/csv/` and `reports/csv/` from raw DL PDSCH and UL PUSCH trial rows.
The artifacts separate nominal physical antenna/RF/port capability from
scheduled, transmitted, receiver-estimated, and effective decoded rank/layers.
Effective decoded rank/layers are populated only from CRC/decode/receiver-usable
rows with finite per-layer receiver evidence; nominal configuration alone leaves
the strict objective failed. Fixed-anchor rows fail when rank/layers,
modulation, or MCS collapse, and multi-layer rows require PMI/precoder and beam
lineage before top-level MIMO `StrictOk` can pass.

This closure is intentionally scoped. It does not claim exhaustive MIMO
conformance, full high-rank UL throughput, Type-II/multi-panel codebooks,
MU-MIMO, CoMP/multi-TRP, FR2 hybrid beamforming, polarization/XPR modeling, or
full channel/RF lineage in every production trial row. Unsupported combinations
must remain fail-closed until equivalent runtime artifacts and tests are added.
