# CODEX PROMPT 19 — Phase-18 Recovery: Qualification Evaluator, Evidence Adapter, and Existing-Run Reanalysis

You are working in the repository:

```text
C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main
```

The current Phase-18 WebGUI run is:

```text
RunID: phase18_actual_20260728_04
Scenario: lls_webgui_full_stack_sinr_geometry_qualification
Preset: comprehensive_smoke
Source run root:
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04
```

The run was genuinely launched through the secured canonical WebGUI and the resolved/executed YAML hashes matched, but the final qualification result was FAIL. Do not start by rerunning all 31 subcases. The immediate task is to determine which failures are:

1. qualification-framework/evaluator defects;
2. artifact path or schema-adapter defects;
3. interrupted-finalization defects;
4. actual missing upstream domain evidence;
5. actual numerical/semantic domain failures.

The existing run must remain immutable. Reanalyse it read-only and write all recomputed results to a separate recovery directory.

---

## 1. Non-negotiable rules

1. Do not weaken, delete, skip, relabel, or make optional any mandatory Phase-18 rule merely to increase the pass count.
2. Do not edit the supplied qualification contract to match accidental current CSV schemas.
3. Do not replace missing measured values with configured values.
4. Do not create placeholder CSVs or blank PNGs.
5. Do not change a failed expected value, tolerance, or comparator until you prove the contract itself is wrong against its authoritative source.
6. Do not modify the source run directory.
7. Do not run the expensive full 31-subcase suite until the evaluator and status reducer are proven correct.
8. Do not create another parallel validation engine. Repair and consolidate the existing Phase-18 production implementation.
9. Do not report COMPLETE merely because focused framework tests pass. This recovery phase is complete only when the existing run has been deterministically re-evaluated and every remaining failure is accurately classified.
10. Preserve all valid current evidence and hashes.

---

## 2. First create a safe checkpoint

The Phase-18 changes are currently uncommitted on `main`. Before editing:

```powershell
git status --short
git branch --show-current
git rev-parse HEAD
```

Create a checkpoint branch and commit the current Phase-18 implementation without changing behavior:

```powershell
git switch -c integration/phase18-recovery

git add -A
git commit -m "Checkpoint Phase-18 full-stack qualification implementation and actual WebGUI run support"
```

Do not continue on an uncommitted `main` working tree.

Record the checkpoint commit in:

```text
audit/full_stack_qualification/phase18_recovery_checkpoint.json
```

---

## 3. Read the actual evidence before editing

Read at minimum:

```text
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_component_coverage_results.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_value_correctness_results.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_subcase_results.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_acceptance_results.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_artifact_audit.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/all_csv_artifact_audit.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/all_image_artifact_audit.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_config_binding.csv
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/phase18_actual_20260728_04/reports/csv/full_stack_run_manifest.csv
```

Also inspect every class under:

```text
+sixgr/+integration/+qualification/
```

and the Phase-18 tests.

Create:

```text
audit/full_stack_qualification/phase18_actual_20260728_04_failure_inventory.csv
```

with columns:

```text
FailureID
SourceLedger
RowID
SubcaseID
ComponentID
Domain
FailureCode
FailureClass
SourceArtifact
SourceExists
RequiredColumnExists
EvaluatorParsed
ComparatorExecuted
FrameworkBugSuspected
DomainFailureSuspected
Details
```

Allowed `FailureClass` values:

```text
EVALUATOR_BUG
STATUS_REDUCER_BUG
ARTIFACT_RESOLUTION_BUG
SCHEMA_ADAPTER_MISSING
FINALIZATION_ORDER_BUG
ARTIFACT_MISSING
DOMAIN_RUNTIME_FAILURE
DOMAIN_NUMERICAL_FAILURE
INTERRUPTED_REGRESSION
CONTRACT_DEFECT_PROVEN
UNCLASSIFIED
```

Do not classify a row by filename alone. Inspect the real source artifact and evaluator trace.

---

## 4. Reproduce the known framework inconsistencies

Before changing code, add failing regression tests for the following actual-run symptoms.

### 4.1 Subcase/component hierarchy inconsistency

The current run reports some subcases PASS although every listed mandatory component in that domain is FAIL. Add tests proving that this state is illegal.

Required invariant:

```text
Subcase PASS
    implies
all mandatory child components PASS
AND all mandatory child value checks PASS
AND all mandatory child negative checks PASS
AND all mandatory child artifacts valid.
```

A subcase may not be PASS while its component rows have `CorrectnessChecked=0` or `Status=FAIL`.

### 4.2 Existing artifact not found by value checker

The source run contains `reports/csv/full_stack_run_manifest.csv`, but the value ledger reports the source missing. Add a failing test using the actual relative path and the artifact manifest.

### 4.3 String-hash comparison failure

The WebGUI run showed equal resolved and executed YAML SHA-256 values, while the value evaluator raised a missing-to-char conversion error. Add a fixture and test for exact string equality without converting MATLAB `<missing>` to `char`.

### 4.4 Simple numeric-column expressions treated as literals

Rows such as:

```text
IllegalFixedDirectionOverrideCount
InvalidDCIGrantCount
FalseGrantCount
RequiredFormatsPassed
MismatchCount
ConfiguredMeasurementSubstitutionCount
```

must resolve to numeric column values, not the column-name string.

### 4.5 Aggregate expressions

Add fixtures for:

```text
all(Status)
all(isfinite(MeasuredValue))
max(GridNMSE)
max(abs(A-B))
min(CompletenessPct)
FailedTests+SkippedTests+BlockedTests
BLER(highestSNR)
BLER(lowestSNR)
```

### 4.6 Multi-source checks with different schemas

The RLC value rule currently fails because multiple source tables have different schemas. Multi-source evaluation must evaluate each source expression separately and combine scalar results. It must not vertically concatenate unrelated schemas.

### 4.7 Missing source/column behavior

A missing source or required column must produce a typed fail-closed result such as:

```text
FULLSTACK:ValueSourceMissing
FULLSTACK:ValueColumnMissing
```

It must not throw an unhandled MATLAB string-conversion exception.

### 4.8 Finalization ordering

Add a regression proving that final manifests, artifact completeness, WebGUI publication, and final acceptance are calculated only after every exporter and late integration file has finished.

---

## 5. Implement one typed value-expression engine

Repair or consolidate the existing evaluator into one typed implementation under the existing qualification package. Do not add another disconnected evaluator.

Suggested canonical classes, adapted to the existing architecture:

```text
ArtifactResolver.m
QualificationTableLoader.m
ValueExpressionParser.m
ValueExpressionAST.m
ValueExpressionEvaluator.m
ValueComparator.m
MultiSourceValueEvaluator.m
QualificationStatusReducer.m
QualificationFinalizationCoordinator.m
QualificationReevaluationRunner.m
```

### 5.1 Supported scalar types

```text
DOUBLE
INTEGER
LOGICAL
STRING
DATETIME
DURATION
ENUM
SHA256
```

### 5.2 Missing-value handling

Use typed missing values. Never blindly call `char()` on a missing string element.

Required behavior:

```text
Required value missing       -> FAIL with typed failure code
Optional value missing       -> NOT_APPLICABLE only when contract says optional
NaN/Inf in required numeric  -> FAIL
Empty required table         -> FAIL
Multiple rows for scalar     -> FAIL unless expression includes an explicit reducer
```

### 5.3 Expression grammar

Support the contract expressions actually used by Phase 18:

```text
ColumnName
all(ColumnName)
any(ColumnName)
all(isfinite(ColumnName))
max(ColumnName)
min(ColumnName)
sum(ColumnName)
count(ColumnName)
max(abs(ColumnA-ColumnB))
ColumnA+ColumnB+ColumnC
BLER(highestSNR)
BLER(lowestSNR)
```

Do not use `eval` on contract text. Parse into a small allowlisted AST.

### 5.4 Row selectors

Implement explicit selectors:

```text
highestSNR
lowestSNR
first
last
latestTime
earliestTime
where(Column == Value)
```

Ties must be deterministic and must fail when the contract expects one row but multiple ambiguous rows remain.

### 5.5 Multi-source semantics

A source specification such as:

```text
fileA.csv|fileB.csv|fileC.csv
```

means:

1. resolve each file independently;
2. evaluate the required expression against each file using its own schema;
3. produce one scalar result per source;
4. combine through the contract reducer;
5. retain source-specific evidence IDs and hashes.

It does not mean concatenating the raw tables.

---

## 6. Implement one comparator engine

Support at minimum:

```text
EQUAL
NOT_EQUAL
LT
LE
GT
GE
ALL_EQUAL
ALL_TRUE
ANY_TRUE
WITHIN_ABS_TOLERANCE
WITHIN_REL_TOLERANCE
STRING_EQUAL
SHA256_EQUAL
SET_EQUAL
NONDECREASING
NONINCREASING
```

### 6.1 Numeric comparison

For scalar numeric equality with tolerance:

```text
abs(observed - expected) <= tolerance
```

For vectors, the contract must explicitly specify `all`, `any`, `max`, `min`, set comparison, or monotonic behavior. Do not silently reduce a vector.

### 6.2 Strings and hashes

Compare MATLAB string scalars directly after validating they are present and nonempty. Preserve lower-case hexadecimal normalization for SHA-256 only.

### 6.3 Booleans

Accept logical values and canonical text forms only:

```text
true / false
1 / 0
PASS / FAIL when the schema declares status conversion
```

### 6.4 Comparator evidence

Every evaluated rule must export:

```text
ParsedExpression
ResolvedSourcePaths
ResolvedSourceArtifactIDs
ObservedType
ObservedScalarOrDigest
ExpectedType
ExpectedScalarOrDigest
Comparator
Tolerance
ComparatorResult
FailureCode
EvaluatorVersion
```

---

## 7. Fix artifact resolution

The value evaluator must not search by basename heuristics alone.

Resolution order:

1. exact artifact ID from the run artifact manifest;
2. exact registered relative path;
3. versioned compatibility alias from the artifact registry;
4. fail as missing.

Never choose a file through substring matching.

Required roots include:

```text
reports/csv/
reports/json/
qualification_evidence/<domain>/
validation/
artifacts/
logs/
```

The resolver must detect:

```text
zero matches
multiple matches
stale hash
path outside run root
symlink escape
schema mismatch
```

Create:

```text
reports/csv/phase18_artifact_resolution_trace.csv
```

in the recovery output.

---

## 8. Add versioned schema adapters, not contract weakening

Many earlier phases export evidence with schemas that differ from the Phase-18 canonical contract.

Implement a versioned `EvidenceAdapterRegistry` that maps an existing valid domain artifact into the Phase-18 canonical schema only when the mapping is semantically exact.

Each adapter must record:

```text
AdapterID
SourceSchemaID
TargetSchemaID
SourceColumns
TargetColumns
TransformationFormula
Lossless
SourceArtifactSHA256
AdapterVersion
OutputArtifactSHA256
```

Rules:

1. Lossless rename/unit conversion is allowed.
2. Derivation from observed runtime columns is allowed with formula and provenance.
3. Invention of missing measurements is prohibited.
4. Configured values cannot fill measured fields.
5. If a required semantic field does not exist, classify as `SCHEMA_ADAPTER_MISSING` or `ARTIFACT_MISSING`; do not fake it.

Prioritize adapters for domains whose files are already mostly present:

```text
Frame/grid
PDCCH
PUCCH
RS/link adaptation
Channel
RF
MAC
Protocol
```

Do not write adapters for entirely absent PDSCH/PUSCH/MIMO/validation evidence; those require real runtime/exporter work later.

---

## 9. Fix hierarchical status reduction

The status reducer must be deterministic and bottom-up.

### 9.1 Component status

A mandatory component is PASS only when:

```text
Executed = true
EvidencePresent = true
CorrectnessChecked = true
All mandatory component value rules pass
All mandatory component negative rules pass
All required component artifacts are valid
```

### 9.2 Subcase status

A mandatory subcase is PASS only when:

```text
Executed = true
All mandatory child components pass
All mandatory subcase value rules pass
All mandatory negative rules pass
All required subcase artifacts pass
No required test is skipped or blocked
```

### 9.3 Suite status

The suite is PASS only when every mandatory subcase passes and final artifact/WebGUI/regression gates pass.

No parent status may be PASS while a mandatory child is FAIL, BLOCKED, SKIPPED, `CorrectnessChecked=0`, or missing.

Export a parent-child reduction trace:

```text
reports/csv/phase18_status_reduction_trace.csv
```

---

## 10. Fix finalization order

The original run was interrupted during SC-30 and some late integration files appeared after an earlier audit. Implement one explicit finalization state machine:

```text
DOMAIN_RUNS_COMPLETE
DOMAIN_EXPORTERS_COMPLETE
NEGATIVE_TESTS_COMPLETE
VALUE_CHECKS_COMPLETE
COMPONENT_REDUCTION_COMPLETE
SUBCASE_REDUCTION_COMPLETE
PLOTS_COMPLETE
ARTIFACT_INDEX_COMPLETE
ARTIFACT_HASHES_FINAL
WEBGUI_PUBLICATION_COMPLETE
REGRESSION_COMPLETE
FINAL_ACCEPTANCE_COMPLETE
```

A final manifest must be generated only after every required earlier stage completes.

If the run is interrupted:

```text
FinalStatus = INTERRUPTED
FinalManifestComplete = false
PublicationComplete = false
```

Do not reuse a pre-finalization manifest as final evidence.

### SC-30 runtime handling

Do not impose a single unrealistic ten-minute timeout on the entire repository regression.

Implement:

```text
configurable total regression budget
per-suite timeout
per-test timeout
progress heartbeat
sharded execution
last-test identification
child-process-tree cleanup only for the launched batch process
```

The comprehensive preset must use a realistic configured budget determined from measured baseline runtime. A timeout remains a failure; this change is not permission to skip tests.

---

## 11. Re-evaluate the existing run without rerunning domains

Add a read-only command, for example:

```matlab
result = sixgr.integration.qualification.QualificationReevaluationRunner.run( ...
    'SourceRunRoot', fullfile(pwd,'results','lls', ...
        'lls_webgui_full_stack_sinr_geometry_qualification', ...
        'phase18_actual_20260728_04'), ...
    'OutputRoot', fullfile(pwd,'results','lls', ...
        'lls_webgui_full_stack_sinr_geometry_qualification', ...
        'phase18_actual_20260728_04_reanalysis'), ...
    'ReadOnlySource', true, ...
    'RebuildArtifactIndex', true, ...
    'ApplyLosslessSchemaAdapters', true, ...
    'Strict', true);
assert(result.Completed);
```

The reanalysis must:

1. leave the original run unchanged;
2. rebuild the artifact index from actual files;
3. verify every hash;
4. apply only approved lossless adapters;
5. re-evaluate all 107 value checks;
6. recompute all 163 component statuses;
7. recompute all 31 subcase statuses;
8. recompute all 387 acceptance rules;
9. produce a new deterministic reanalysis manifest;
10. classify every remaining failure.

Run the reanalysis twice and require byte-identical canonical CSV results and identical SHA-256 values.

---

## 12. Required recovery outputs

Write under the reanalysis output root:

```text
reports/csv/phase18_failure_triage.csv
reports/csv/phase18_artifact_resolution_trace.csv
reports/csv/phase18_schema_adapter_results.csv
reports/csv/phase18_value_evaluation_trace.csv
reports/csv/phase18_status_reduction_trace.csv
reports/csv/phase18_recomputed_value_results.csv
reports/csv/phase18_recomputed_component_results.csv
reports/csv/phase18_recomputed_subcase_results.csv
reports/csv/phase18_recomputed_acceptance_results.csv
reports/csv/phase18_remaining_missing_artifacts.csv
reports/csv/phase18_remaining_domain_failures.csv
reports/json/phase18_reanalysis_manifest.json
reports/md/PHASE18_REANALYSIS_REPORT.md
```

The triage report must give counts by:

```text
framework defect
schema adapter
missing artifact
actual numerical failure
actual semantic failure
interrupted finalization
```

---

## 13. Tests to add

Add MATLAB unit tests at minimum for:

```text
testQualificationArtifactResolver
testQualificationStringHashComparison
testQualificationNumericColumnResolution
testQualificationAggregateExpressions
testQualificationHighestLowestSNRSelectors
testQualificationMultiSourceDifferentSchemas
testQualificationMissingValueFailClosed
testQualificationComparatorTypes
testQualificationStatusHierarchy
testQualificationFinalizationOrder
testQualificationInterruptedRun
testQualificationReadOnlyReevaluation
testQualificationReevaluationDeterminism
testPhase18ActualRunRegressionFixture
```

Add Python tests for:

```text
artifact-manifest path resolution
schema adapter registry metadata
reanalysis result schemas
parent/child status consistency
no mutation of source-run hashes
WebGUI display of reanalysis versus original run
```

Create a minimal fixture derived from the actual run under:

```text
tests/fixtures/phase18_actual_20260728_04_minimal/
```

Include only the smallest rows/files needed to reproduce the evaluator defects. Do not commit the full large run.

---

## 14. Mandatory commands for this recovery phase

Run:

```powershell
python -m compileall +sixgr apps tests tools
pytest -q tests/test_full_stack_webgui_contract.py tests/test_full_stack_webgui_e2e.py <new recovery tests>
```

Run focused MATLAB tests:

```powershell
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Qualification*'); assertSuccess(r);"
```

Run the existing-run reanalysis:

```powershell
matlab -batch "addpath(pwd); out=sixgr.integration.qualification.QualificationReevaluationRunner.run('SourceRunRoot',fullfile(pwd,'results','lls','lls_webgui_full_stack_sinr_geometry_qualification','phase18_actual_20260728_04'),'OutputRoot',fullfile(pwd,'results','lls','lls_webgui_full_stack_sinr_geometry_qualification','phase18_actual_20260728_04_reanalysis'),'ReadOnlySource',true,'RebuildArtifactIndex',true,'ApplyLosslessSchemaAdapters',true,'Strict',true); assert(out.Completed);"
```

Run it a second time to a second output root and compare canonical hashes.

Do not run the complete 31-subcase qualification suite during this recovery phase.

---

## 15. Recovery acceptance criteria

This immediate next step is complete only when:

1. Phase-18 work is committed on a recovery branch.
2. The original run directory is byte-for-byte unchanged.
3. Every current value-evaluator exception has a typed result rather than an unhandled MATLAB error.
4. Existing artifacts are resolved through manifest/path identity, not substring matching.
5. Simple numeric columns evaluate as numeric values.
6. Hashes and strings compare correctly.
7. Aggregate and multi-source expressions work.
8. Parent/child status inconsistency is impossible.
9. Finalization-stage ordering is explicit.
10. The existing run is re-evaluated deterministically twice.
11. Every remaining failure has exactly one primary failure class.
12. The report clearly separates framework false negatives from genuine missing domain evidence.
13. No threshold, required artifact, component, subcase, or rule was weakened.
14. All focused recovery tests pass.

Do not require the reanalysed run to pass the whole suite. Its purpose is to create a trustworthy, non-circular failure map for the next implementation wave.

---

## 16. Determine the next domain wave from the corrected evidence

After reanalysis, generate:

```text
audit/full_stack_qualification/PHASE18_NEXT_DOMAIN_ORDER.csv
```

Rank domains using:

```text
BlockingCriticalPath
MissingMandatoryArtifacts
ActualDomainFailureCount
DependentSubcasesBlocked
ExistingEvidenceReusePct
EstimatedRuntimeToVerify
```

Unless corrected evidence proves otherwise, the likely next order is:

```text
1. Frame/waveform schema and correctness closure
2. PDSCH/DL-SCH production runner and exporters
3. PUSCH/UL-SCH production runner and exporters
4. Fixed DL/UL SINR sweep SC-04/SC-05
5. Initial access SC-06
6. MIMO/beam SC-13/SC-14
7. NLOS/interference/mobility/power/handover gaps
8. Validation/oracle artifacts
9. Final artifact/WebGUI publication
10. Sharded complete regression
```

PDSCH and PUSCH are expected to remain the first true runtime blockers because their mandatory Phase-18 artifact families are currently absent, and without them the configured five-point DL/UL sweep cannot produce measured receiver results.

---

## 17. Required final Codex response

Return:

1. checkpoint branch and commits;
2. source files changed;
3. exact evaluator defects reproduced;
4. evaluator/comparator/artifact-resolution architecture implemented;
5. tests added and exact results;
6. original source-run hash preservation result;
7. first and second reanalysis output roots and manifest hashes;
8. original versus recomputed counts for values/components/subcases/acceptance;
9. counts by failure class;
10. exact remaining genuine domain blockers;
11. generated `PHASE18_NEXT_DOMAIN_ORDER.csv`;
12. next recommended domain wave;
13. final status for this recovery phase: COMPLETE, FAIL, or BLOCKED.

`COMPLETE` means the recovery/evaluator phase is trustworthy and finished. It does not mean the full LLS qualification run passes.
