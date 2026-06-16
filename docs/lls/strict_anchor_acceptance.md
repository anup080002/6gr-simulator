# Strict Anchor Acceptance

A strict anchor passes only when the canonical root status says it passes. The
acceptance rollup is exported to:

- `reports/csv/strict_anchor_acceptance_report.csv`
- `reports/json/strict_anchor_acceptance_report.json`

Critical AUD-001 and AUD-002 cannot be waived. A critical issue with
`waived_non_blocking` still fails `ActiveIssueGateOk`.

Strict anchor acceptance also writes:

- `reports/csv/active_issue_gate_summary.csv`
- `reports/csv/conformance_matrix_runtime_audit.csv`
- `reports/csv/scenario_objective_gates.csv`

These artifacts are audit evidence only; they must not create placeholder
success rows or relabel missing capability as implemented.
