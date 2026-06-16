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
