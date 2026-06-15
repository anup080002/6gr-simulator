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
| RRC and initial access | AUD-015, AUD-RA-001, AUD-PRACH-001 | SSB/PBCH/SIB1/PRACH producers and control CSV exporters | `testTruthValidationControlCoverage`, `control/csv/prach_trials.csv` |
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
