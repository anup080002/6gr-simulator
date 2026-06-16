# LLS Result Status Semantics

`RunCompleted` only means the runner reached a terminal state. It does not mean
the run is truthful, standards-conformant, or scenario-successful.

The canonical status artifact is:

- `reports/csv/result_status_summary.csv`
- `reports/json/result_status_summary.json`

`ResultOk` is true only when every required gate passes:

- `RunCompleted`
- `ArtifactsWritten`
- `TruthContractOk`
- `RuntimeTruthContractOk`
- `StandardsConformanceOk`
- `ScenarioObjectiveOk`
- `ConfiguredEffectiveOk`
- `MandatorySubsystemsOk`
- `ActiveIssueGateOk`
- `KpiConsistencyOk` when KPI objectives are enabled
- `VisualArtifactGateOk` when visual objectives are enabled
- `DuplicateArtifactGateOk` when artifact integrity objectives are enabled

Dashboards and reports must prefer `result_status_summary.csv` over legacy
summary fields when it exists.
