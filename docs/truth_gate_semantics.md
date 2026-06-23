# Truth Gate Semantics

`sixgr.runtime.RuntimeTruthEvaluator` defines the Phase 1 root result expression:

```text
ResultOk =
    RuntimeExecutionOk
    AND RuntimeJournalOk
    AND WorkerShutdownOk
    AND ReportingPipelineOk
    AND ArtifactValidationOk
    AND InfrastructureAuditOk
    AND MandatoryPhyEvidenceOk
    AND KpiConsistencyOk
    AND ScenarioObjectiveOk
    AND StrictConformanceOk
```

No lower-level `PASS`, `OK`, `decoded`, `available`, or `applied` label may override this expression.

Expected completion semantics:

- `completed_success`: every root gate passed.
- `completed_with_validation_failures`: runtime/reporting infrastructure completed but mandatory PHY, KPI, scenario, or strict-conformance gates failed.
- `completed_with_reporting_failure`: reporting did not complete.
- `completed_with_artifact_failure`: artifact validation failed.
- `failed_during_runtime`: runtime execution failed before post-link reporting.
- `infrastructure_failure`: runtime journal, worker shutdown, or infrastructure audit failed.
