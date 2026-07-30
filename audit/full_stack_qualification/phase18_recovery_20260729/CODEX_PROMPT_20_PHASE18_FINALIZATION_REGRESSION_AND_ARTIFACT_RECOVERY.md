# CODEX PROMPT 20 — Phase-18 finalization, regression, artifact-publication, and targeted evidence recovery

You are the lead MATLAB/5G Toolbox integration engineer, validation architect, WebGUI backend engineer, and release-test owner for the 6GR simulator repository.

## Mission

Fix the concrete failures from the WebGUI-launched full-stack qualification run without weakening any scientific or artifact contract.

The immediate target is not to make the dashboard green by relaxing rules. The target is to:

1. eliminate the terminal finalization exception;
2. make artifact schemas versioned, canonical, and fail-closed;
3. make finalization resumable and deterministic;
4. stabilize MATLAB, Python, WebGUI, and Playwright regression execution;
5. correctly classify and publish all evidence already generated;
6. run only the missing domain subcases needed to create genuinely absent evidence;
7. rerun the same WebGUI scenario only after the recovery gates pass;
8. obtain a trustworthy qualification result from actual measured/runtime data.

Do not return a plan-only response. Inspect the repository, edit production code, add tests, execute focused commands, recover the existing run, run targeted missing subcases, then rerun the WebGUI qualification when its prerequisites pass.

---

# 1. Authoritative failing run

Treat this run as immutable source evidence:

```text
Scenario:
lls_webgui_full_stack_sinr_geometry_qualification

Preset:
comprehensive_smoke

Run tag:
phase18_actual_20260729_01

WebGUI Run ID:
9245972537

Source run root:
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/
phase18_actual_20260729_01

Git commit used by the run:
12bacfc0f10c286d35f18e3daa04b382106c4550

MATLAB:
R2026a Update 4

5G Toolbox:
26.1

WebGUI:
http://127.0.0.1:62906/
```

The source/effective/resolved/executed YAML binding already passed. Preserve that behavior.

The terminal exception is:

```text
MATLAB:table:UnrecognizedVarName
Unrecognized table variable name 'ArtifactType'.

QualificationFinalizationCoordinator.assess line 35:
png = string(audit.ArtifactType)=="PNG";
```

Current qualification totals before correct finalization:

```text
Subcases:          0 / 31 PASS
Components:        7 / 163 PASS
Value checks:     56 / 107 PASS
Acceptance:       79 / 387 PASS
Negative tests:   14 / 77 PASS
Valid artifacts: 333 / 746
Valid CSVs:      201 / 447
Valid PNGs:      132 / 299
WebGUI published:393 / 746
Verifier exit:     2
```

Focused suites already passing:

```text
MATLAB_FULLSTACK_FOCUSED:       8 / 8
MATLAB_INTEGRATION_FOCUSED:    41 / 41
MATLAB_CONFIG_CHANNEL_GATES:    4 / 4
MATLAB_TRUTH_EXPORT_GATES:      5 / 5
```

Do not rewrite strong, passing domain kernels merely because final aggregation failed.

---

# 2. Non-negotiable rules

1. Never change an expected threshold, mandatory flag, minimum row count, or artifact requirement merely to make the run pass.
2. Never generate a placeholder CSV or PNG for missing evidence.
3. Never copy configured/model values into measured/runtime fields.
4. Never relabel a diagnostic reconstruction as observed evidence.
5. Never copy DUT output into an independent reference artifact.
6. Never call a same-implementation comparison independent.
7. Never suppress, skip, deselect, or mark unavailable mandatory tests as passing.
8. Never treat a finalization exception as a scientific PHY failure; record infrastructure and qualification status separately.
9. Never treat scientific FAIL as a finalization crash. A scientifically failed run must still finalize completely and publish its evidence.
10. Never access a table column before validating or normalizing the table schema.
11. Never use substring matching to resolve artifacts.
12. Never require MySQL merely to publish a filesystem-backed run to the canonical WebGUI.
13. Never let pytest recursively collect generated `results`, `outputs`, `artifacts`, temporary run trees, or validation-evidence directories.
14. Never hard-code operator credentials in code, test files, command lines, or logs.
15. Never rerun the complete 2.5-hour qualification until focused recovery prerequisites pass.
16. Preserve the original run root. Recovery outputs must be written to a separate sibling root or a clearly versioned recovery directory.
17. Keep exact source hashes and provenance for every adapted, regenerated, or materialized artifact.
18. Use checkpoint-sized commits with exact tests and results.

---

# 3. First repository actions

From repository root:

```text
1. Read AGENTS.md and all nested AGENTS.md files.
2. Confirm git status and current branch.
3. Confirm commit 12bacfc0f10c286d35f18e3daa04b382106c4550 is available.
4. Create a branch:
   integration/phase18-finalization-recovery
5. Do not modify the source run root.
6. Copy the following supplied evidence into an immutable audit folder if it is not already present:
   - failure_debug_report.txt
   - full_stack_run_manifest.csv
   - full_stack_regression_summary.csv
   - all_artifact_completeness.csv
   - full_stack_image_semantic_audit.csv
7. Create:
   audit/full_stack_qualification/phase18_recovery_20260729/
```

Required recovery output root:

```text
results/lls/lls_webgui_full_stack_sinr_geometry_qualification/
phase18_actual_20260729_01_recovery
```

The recovery root may contain copied manifests and newly generated derived/finalization outputs. It must not overwrite raw source-run domain evidence.

---

# 4. Reproduce the terminal defect before fixing it

Create a focused MATLAB regression test that reproduces the exact failure using the actual artifact-audit table schema found in the source run.

Required test file, adapted to repository naming conventions:

```text
tests/testQualificationFinalizationArtifactSchema.m
```

The pre-fix test must prove:

```text
- The source audit table does not contain ArtifactType.
- QualificationFinalizationCoordinator.assess directly accesses it.
- MATLAB throws MATLAB:table:UnrecognizedVarName.
```

Also export:

```text
audit/full_stack_qualification/phase18_recovery_20260729/
source_artifact_audit_schema.csv
```

Columns:

```text
VariableIndex
VariableName
MATLABClass
ExampleValue
SourceArtifact
```

Do not guess the producer. Trace the exact call chain and table source passed into `QualificationFinalizationCoordinator.assess`.

Required trace:

```text
Producer function
Producer output schema
Intermediate adapter functions
Coordinator call site
Expected schema version
Actual schema version
```

Write the trace to:

```text
artifact_schema_call_chain.md
```

---

# 5. Implement one canonical artifact-audit schema

Create or consolidate a production schema registry under:

```text
+sixgr/+integration/+qualification/
```

Suggested classes:

```text
QualificationArtifactAuditSchema.m
QualificationArtifactAuditNormalizer.m
QualificationArtifactKind.m
QualificationArtifactStatus.m
```

Use repository naming conventions if equivalent classes already exist. Do not create duplicates.

## 5.1 Canonical artifact row

Every normalized artifact row must contain at least:

```text
SchemaVersion
RunID
ArtifactID
Domain
SubcaseID
RelativePath
ArtifactType
MIMEType
Required
Present
Valid
Status
FailureCode
SHA256
ByteCount
GeneratedUTC
SourceArtifactIDs
SourceCSVRelativePath
SourceCSV_SHA256
SemanticAuditStatus
ProvenanceClass
PublicationStatus
ArtifactTypeSource
```

Canonical `ArtifactType` values:

```text
CSV
PNG
JSON
YAML
MAT
LOG
MARKDOWN
TEXT
OTHER
```

Canonical `Status` values:

```text
PASS
FAIL
MISSING
INVALID_SCHEMA
INVALID_HASH
INVALID_SEMANTICS
UNAVAILABLE
NOT_APPLICABLE
```

## 5.2 Versioned input normalization

The normalizer must support known existing schema aliases only through an explicit versioned mapping, for example:

```text
ArtifactType <- ArtifactType
ArtifactType <- ArtifactKind
ArtifactType <- FileKind
ArtifactType <- FileType
ArtifactType <- Type
RelativePath <- RelativePath
RelativePath <- ArtifactPath
RelativePath <- Path
```

If no explicit type field exists but an exact relative path exists, deriving type from the file extension is allowed only when:

```text
- the extension is recognized;
- ArtifactTypeSource is recorded as DERIVED_FROM_EXTENSION;
- the exact derivation rule/version is recorded;
- unknown or extensionless files fail closed;
- the derivation never changes scientific validity.
```

Do not silently treat every missing type as CSV or PNG.

## 5.3 Required behavior

`QualificationFinalizationCoordinator.assess` must call the normalizer before reading any variable.

The coordinator must never contain code equivalent to:

```matlab
png = string(audit.ArtifactType)=="PNG";
```

until the canonical schema has been validated.

On malformed input, the coordinator must:

```text
- not crash;
- write a schema diagnostic CSV;
- mark infrastructure finalization as FAIL;
- retain all existing evidence;
- complete the run manifest with a typed failure;
- return a structured result.
```

Typed errors:

```text
FULLSTACK:ArtifactAuditSchemaMissing
FULLSTACK:ArtifactAuditColumnMissing
FULLSTACK:ArtifactTypeUnknown
FULLSTACK:ArtifactAuditDuplicateKey
FULLSTACK:ArtifactAuditNormalizationFailed
```

---

# 6. Fix the semantic-audit/completeness contradiction

The source run contains ten full-stack PNG semantic-audit rows marked PASS with dimensions and hashes. However, the domain completeness table reports:

```text
Full Stack Qualification:
PresentPNG = 10
ValidPNG   = 0
```

This is an ordering or join defect.

Implement a one-to-one exact-path join between:

```text
required artifact registry
final normalized artifact manifest
full_stack_image_semantic_audit.csv
source CSV manifest rows
```

A PNG is valid only when:

```text
Required = true
Present = true
PNG decodes
semantic audit Status = PASS
relative path matches exactly
PNG SHA-256 matches
source CSV exists
source CSV is valid
source CSV SHA-256 matches
```

The join must use normalized relative paths, not basenames and not substrings.

Add a fixture test using the actual supplied ten-row semantic audit. The expected result is:

```text
PresentPNG = 10
ValidPNG   = 10
```

for those ten full-stack images.

Given 13 valid full-stack CSVs and 10 valid full-stack PNGs out of 26 required artifacts, the recomputed completeness before other recovery should be:

```text
(13 + 10) / (16 + 10) * 100 = 88.461538... percent
```

Do not hard-code that number in production. Use it only as a fixture expectation.

Required tests:

```text
- path separators slash/backslash normalization;
- same basename in different directories;
- stale PNG hash;
- stale source CSV hash;
- semantic PASS but source CSV invalid;
- source CSV PASS but PNG semantic row missing;
- duplicate semantic rows;
- late-created image after an earlier audit;
- repeated finalization yields identical counts and hashes.
```

---

# 7. Implement resumable, transactional finalization

Create a finalization state machine with persistent stage checkpoints.

Required stages:

```text
F00_SOURCE_RUN_LOCKED
F01_DOMAIN_EXPORTS_DISCOVERED
F02_DOMAIN_SCHEMA_NORMALIZED
F03_VALIDATION_EVIDENCE_EXPORTED
F04_INTEGRATION_EVIDENCE_EXPORTED
F05_SUMMARY_TABLES_EXPORTED
F06_PLOTS_GENERATED
F07_IMAGE_SEMANTIC_AUDIT_DONE
F08_FINAL_ARTIFACT_MANIFEST_DONE
F09_WEBGUI_PUBLICATION_DONE
F10_COMPLETENESS_DONE
F11_REGRESSION_DONE
F12_FINAL_STATUS_REDUCED
F13_FINAL_RUN_MANIFEST_WRITTEN
F14_FINALIZED
```

Each stage must record:

```text
Stage
StartUTC
EndUTC
Status
InputManifestSHA256
OutputManifestSHA256
FailureCode
Details
```

Write atomically:

```text
write temp file
flush/close
validate temp file
rename to final name
```

If interrupted, `resumeFinalize` must restart at the first incomplete or invalidated stage.

Suggested production APIs:

```matlab
result = sixgr.integration.qualification.resumeFinalize( ...
    SourceRunRoot=sourceRunRoot, ...
    RecoveryRunRoot=recoveryRunRoot, ...
    Strict=true);
```

or equivalent repository-native API.

## 7.1 Status separation

Record separate statuses:

```text
ExecutionCompletionStatus
InfrastructureFinalizationStatus
QualificationStatus
PublicationStatus
RegressionStatus
```

A run may be:

```text
ExecutionCompletionStatus       = COMPLETED
InfrastructureFinalizationStatus= PASS
QualificationStatus             = FAIL
```

This is a scientifically failed but correctly finalized run.

A schema exception must be:

```text
ExecutionCompletionStatus       = COMPLETED
InfrastructureFinalizationStatus= FAIL
QualificationStatus             = NOT_EVALUATED or FAIL_INCOMPLETE
```

Do not conflate the two.

## 7.2 Final manifest ordering

The final artifact manifest must be written only after all finalization-generated artifacts and semantic audits exist.

If any new artifact is written after the manifest, invalidate and regenerate:

```text
semantic audit if applicable
artifact manifest
publication index
completeness
acceptance reduction
run manifest
```

---

# 8. Fix filesystem publication when MySQL is inactive

The regression log shows browser-contract materialization was skipped because the MySQL artifact store was inactive.

The canonical WebGUI must support a filesystem-backed run without requiring MySQL artifact storage.

Implement an artifact-publication abstraction:

```text
FilesystemArtifactPublisher
DatabaseArtifactPublisher
CompositeArtifactPublisher
```

Rules:

```text
- Filesystem publication is mandatory for filesystem-backed runs.
- Database publication is optional unless the deployment profile declares it mandatory.
- An inactive optional MySQL store must not suppress filesystem indexing.
- If database publication is mandatory, readiness must fail before launching the run.
- Publication must use exact RunID and artifact IDs.
- Publication must be idempotent.
- Repeated indexing must not create duplicate rows.
```

Add tests with:

```text
MySQL inactive + filesystem active     -> filesystem publication PASS
MySQL mandatory + unavailable          -> preflight FAIL
Both active                             -> both publish exactly once
Repeated finalization                   -> no duplicates
Interrupted publication and resume      -> complete exactly once
```

---

# 9. Recover the existing run before rerunning physics

After fixing schema and finalization, run a read-only recovery of:

```text
phase18_actual_20260729_01
```

into:

```text
phase18_actual_20260729_01_recovery
```

Do not execute PDSCH, PUSCH, channel, RF, MAC, or protocol simulation in this step.

The recovery must:

```text
- copy or reference immutable raw source evidence;
- normalize artifact schemas;
- regenerate late summary tables;
- regenerate full-stack plots from valid source CSVs;
- rerun semantic image audits;
- generate the final artifact manifest;
- publish every present artifact to the WebGUI filesystem index;
- recompute completeness;
- classify missing versus invalid artifacts;
- write complete manifests even though qualification remains FAIL.
```

Run recovery twice. The two recovery outputs must have identical canonical CSV content and hashes except permitted timestamps explicitly excluded from canonical hashing.

Required recovery artifacts:

```text
reports/csv/finalization_stage_ledger.csv
reports/csv/artifact_schema_normalization.csv
reports/csv/artifact_join_trace.csv
reports/csv/artifact_type_resolution.csv
reports/csv/recovered_artifact_manifest.csv
reports/csv/recovered_artifact_completeness.csv
reports/csv/recovered_webgui_publication.csv
reports/csv/recovery_failure_classification.csv
reports/csv/recovery_missing_runtime_evidence.csv
reports/csv/recovery_invalid_existing_evidence.csv
reports/csv/recovery_regeneration_candidates.csv
reports/recovery_report.md
meta/recovery_manifest.json
```

Failure categories:

```text
FINALIZATION_SCHEMA
FINALIZATION_ORDERING
ARTIFACT_PATH_RESOLUTION
ARTIFACT_HASH
ARTIFACT_SCHEMA
ARTIFACT_SEMANTIC
PUBLISHING
REGRESSION_INFRASTRUCTURE
MISSING_RUNTIME_EVIDENCE
NUMERICAL_FAILURE
PROTOCOL_SEMANTIC_FAILURE
NEGATIVE_TEST_NOT_EXECUTED
```

---

# 10. Fix Python test collection deterministically

The full pytest command failed while recursively collecting a disappearing directory under the generated run tree.

Implement all of the following:

## 10.1 Restrict test discovery

Create or update `pyproject.toml`, `pytest.ini`, or repository-equivalent configuration:

```ini
[pytest]
testpaths = tests
norecursedirs =
    results
    outputs
    artifacts
    node_modules
    .git
    .pytest_cache
    qualification_evidence
    canonical_runtime
```

If using `pyproject.toml`, use the equivalent `[tool.pytest.ini_options]` syntax.

The regression command must be explicit:

```text
python -m pytest -q tests
```

Never run bare `pytest` from repository root if it can recurse into result trees.

## 10.2 Generated-evidence tests

Any test that needs generated run evidence must receive an explicit fixture path. It must not rely on pytest discovering generated files as tests.

Use:

```text
immutable copied fixture
or
unique temporary directory owned by the test
```

Do not prune a directory while another process is collecting or reading it.

## 10.3 Required tests

```text
- pytest --collect-only -q tests succeeds repeatedly;
- generated results directory can be created/deleted concurrently without affecting collection;
- result tree containing Python-like filenames is ignored;
- full Python suite passes from repository root;
- full Python suite passes from another working directory;
- no import requires MATLAB or a run output directory to exist.
```

---

# 11. Fix WebGUI unit-test selection

The current `WEBGUI_UNIT_TESTS` shard exited with pytest code 5 because it selected zero tests.

Do not convert exit code 5 into PASS.

Create a stable marker or explicit test list, for example:

```text
@pytest.mark.webgui_unit
```

and register the marker.

The shard must first run collection:

```text
python -m pytest --collect-only -q -m webgui_unit tests
```

Require collected count > 0.

Then run:

```text
python -m pytest -q -m webgui_unit tests
```

Alternatively, use an explicit list of canonical WebGUI unit/contract test files.

The regression summary must report actual test count, not `MandatoryTests=1` for an opaque wrapper.

---

# 12. Fix secure Playwright credential propagation

The internal Playwright child reached the login page but did not receive operator credentials.

Implement a test credential broker. Do not hard-code credentials.

Preferred design:

```text
1. Parent regression coordinator requests an ephemeral operator account/session.
2. Backend creates a random high-entropy credential or one-time session.
3. Secret is stored in an ACL-restricted temporary file or passed through an inherited process environment not printed in logs.
4. Child receives only:
   SIXGR_WEBGUI_BASE_URL
   SIXGR_WEBGUI_RUN_TAG
   SIXGR_WEBGUI_TEST_USERNAME
   SIXGR_WEBGUI_TEST_PASSWORD_FILE
   or SIXGR_WEBGUI_TEST_SESSION_FILE
5. Playwright logs in or loads the one-time test session.
6. Credential/session is revoked after the test.
7. Secret file is securely deleted.
8. All logs redact password, cookie, token, and authorization values.
```

Update `tests/test_full_stack_webgui_e2e.py` to support the secure file/session mechanism while preserving the actual login-flow test where required.

Required negative tests:

```text
missing credentials -> typed setup failure
expired credential -> login rejected
viewer role -> cannot stop/delete run
operator role -> can inspect owned qualification run
credential not present in logs
credential revoked after test
```

Do not reuse the user's ordinary account.

---

# 13. Repair the MATLAB full-regression shard

The current full-regression wrapper reports one failed wrapper while `test6GScenarioMatrixRunner` exceeded 1500 seconds after substantial work.

Do not merely increase all timeouts.

## 13.1 Enumerate individual MATLAB tests

Use `matlab.unittest.TestSuite` to enumerate methods in:

```text
tests/test6GScenarioMatrixRunner.m
```

Run each method independently and export:

```text
TestName
Status
DurationSeconds
FailureIdentifier
FailureMessage
LastHeartbeat
ChildRunRoot
```

Identify the two recorded failures and the exact slow method.

## 13.2 Split the matrix runner

Refactor the test or regression coordinator so one method does not own an unbounded matrix of child runs.

Required behavior:

```text
- one matrix case or bounded group per test task;
- deterministic task IDs;
- independent output roots;
- no nested or competing parallel pools;
- per-task heartbeat every <=30 seconds;
- per-task process tree ownership;
- exact cleanup limited to the launched process tree;
- aggregate result after all tasks finish;
- actual MATLAB test counts recorded.
```

## 13.3 Timeout classes

Introduce explicit timeout classes based on measured normal runtime:

```text
UNIT
COMPONENT
INTEGRATION
SCENARIO_MATRIX
FULL_REGRESSION
```

Each class has a documented budget and rationale. A timeout remains FAIL.

For the scenario matrix, establish the budget using an isolated baseline run plus margin. Do not use an arbitrary blanket value.

## 13.4 Avoid OneDrive/result-tree interaction

Child regression outputs should use a stable regression workspace that is not simultaneously scanned, pruned, or synchronized by unrelated tests.

If OneDrive synchronization is contributing to timing variability, use a configurable local scratch root for transient child runs while preserving final logs and hashes under the qualification run root.

Do not hard-code a machine path. Use a configuration/environment setting with a safe default.

---

# 14. Make validation and integration exporters execute before final completeness

The verifier reports the complete Validation domain and End-to-End Integration domain artifacts as missing.

Inspect whether their canonical phase runners exist and were implemented earlier.

Create an explicit Phase-18 dispatch map:

```text
SC-27 -> canonical validation phase runner/exporter
SC-28 -> artifact audit/finalization exporter
SC-29 -> WebGUI publication exporter
SC-30 -> regression exporter
Integration evidence -> canonical integration event/resource/waveform exporters
```

Required rule:

```text
A subcase is not Executed merely because the dispatcher visited it.
Executed=true requires the canonical runner to start and write its run/subcase manifest.
EvidencePresent=true requires the exact artifact contract to be satisfied.
CorrectnessChecked=true requires its mandatory checks to execute.
```

Generate validation/integration artifacts only from actual run data or actual validation executions.

Do not create empty files merely to satisfy filenames.

If a validation output can be derived from existing runtime evidence, record:

```text
DerivationFormula
InputArtifactIDs
InputSHA256s
ProducerVersion
ProvenanceClass=DERIVED_FROM_OBSERVED_RUNTIME_STATE
```

If the source evidence does not exist, leave it missing and schedule the owning subcase rerun.

---

# 15. Build a lossless domain-artifact adapter, not a filename copier

Many domains have present artifacts but fail because schemas or names differ from the qualification contract.

Create or consolidate:

```text
QualificationDomainArtifactAdapter.m
QualificationArtifactSchemaAdapterRegistry.m
```

For every adapter:

```text
SourceSchemaID
TargetSchemaID
Version
Exact field mapping
Derived-field formula
Input provenance
Lossless flag
Unsupported reason
Tests
```

Allowed:

```text
- exact rename of a semantically identical field;
- unit conversion with explicit formula;
- derived error column from two observed columns;
- materializing a registered alias with source artifact ID and identical hash/content.
```

Forbidden:

```text
- configured value substituted for measured value;
- dropping failed rows;
- filling missing values with zero;
- copying a different domain's table;
- manufacturing a PASS status;
- creating a plot from synthetic values;
- using a same-name field with different semantics.
```

Priority domains with existing evidence:

```text
Frame/grid
Waveform
PDCCH
PUCCH
RS/link adaptation
Channel
RF
MAC
Protocol
Full-stack summary
```

For each domain, write:

```text
reports/csv/domain_adapter_results.csv
```

with:

```text
Domain
SourceArtifact
TargetArtifact
SourceSchema
TargetSchema
RowsIn
RowsOut
Lossless
DerivedColumns
Status
FailureCode
SourceSHA256
TargetSHA256
```

---

# 16. Targeted actual reruns for genuinely missing domains

After recovery and adapter passes, classify remaining missing evidence.

The following domains currently have zero base artifacts and therefore require actual canonical runner execution unless repository inspection proves the runner wrote them under another valid schema/path:

```text
PDSCH and DL-SCH
PUSCH and UL-SCH
Initial Access
MIMO / beamforming
Validation
End-to-End Integration
```

Do not rerun the complete qualification yet.

Implement or use a targeted subcase API:

```matlab
out = sixgr.integration.qualification.runSelectedSubcases( ...
    ScenarioPath=scenarioPath, ...
    Preset="comprehensive_smoke", ...
    SubcaseIDs=[...], ...
    ParentRunID=..., ...
    OutputRoot=..., ...
    Strict=true);
```

or repository-equivalent.

## 16.1 Execution waves

### Wave A — finalization and evidence compatibility

```text
SC-00
SC-01
SC-02
SC-03
SC-07
SC-10
SC-11
SC-12
SC-15
SC-17
SC-19
SC-20
SC-21
SC-22
SC-23
SC-24
SC-27
SC-28
SC-29
```

Use existing evidence where valid. Run only the minimum canonical tests/exporters needed.

### Wave B — missing data PHY

```text
SC-08 PDSCH/DL-SCH
SC-09 PUSCH/UL-SCH
```

Required before fixed sweep:

```text
all PDSCH/PUSCH base CSV contracts
all PDSCH/PUSCH base PNG contracts
no-noise roundtrip
receiver-derived SINR
DM-RS/PT-RS
coding chain
precoder application
HARQ/UCI
```

### Wave C — fixed SINR sweep

Only after Wave B passes:

```text
SC-04 DL fixed SINR sweep
SC-05 UL fixed SINR sweep
```

SNR grid:

```text
[-8, -4, 0, 4, 10] dB
```

Require:

```text
actual TB trials
receiver-measured post-EQ SINR
BER/BLER/EVM
configured-vs-measured error <= contract
high-SNR success
low-SNR error behavior
canonical stop status
no incomplete point accepted
```

### Wave D — initial access and MIMO/beam

```text
SC-06
SC-13
SC-14
```

### Wave E — NLOS/interference/handover gaps

```text
SC-16
SC-18
SC-25
SC-26
```

### Wave F — regression and finalization

```text
SC-27
SC-28
SC-29
SC-30
```

Each wave must pass its focused verifier before proceeding.

---

# 17. Fix component/subcase/suite reduction

Use one deterministic hierarchy:

```text
Component PASS =
    Mandatory implication:
    Executed
    AND EvidencePresent
    AND CorrectnessChecked
    AND mandatory value checks PASS
    AND mandatory negative checks PASS
    AND mandatory artifacts valid

Subcase PASS =
    every mandatory component PASS
    AND every subcase value check PASS
    AND every subcase negative check PASS
    AND subcase runner completed

Suite PASS =
    every mandatory subcase PASS
    AND all selected-preset artifacts valid
    AND WebGUI publication complete
    AND regression clean
    AND finalization infrastructure PASS
```

A subcase must never pass while a mandatory child component fails.

Add invariant tests over all 31 subcases and 163 components.

---

# 18. Required focused tests

Add or update tests covering at least:

## MATLAB

```text
testQualificationArtifactAuditSchema
testQualificationArtifactAuditNormalizer
testQualificationFinalizationCoordinator
testQualificationFinalizationResume
testQualificationFinalizationIdempotence
testQualificationImageSemanticJoin
testQualificationArtifactCompleteness
testQualificationFilesystemPublication
testQualificationDomainArtifactAdapters
testQualificationSelectedSubcases
testQualificationStatusReduction
testQualificationRegressionSharding
```

## Python

```text
test_pytest_collection_isolated_from_results
test_full_stack_webgui_contract
test_full_stack_webgui_unit_marker_collects
test_full_stack_webgui_e2e_credentials
test_full_stack_artifact_verifier_recovery
test_artifact_paths_are_exact
test_no_secret_in_logs
```

## Required mutation tests

```text
remove ArtifactType
rename ArtifactType to FileKind
unknown extension
same basename in two folders
corrupt PNG hash
corrupt source CSV hash
semantic audit row missing
late artifact after manifest
MySQL inactive
zero WebGUI unit tests selected
Playwright credential missing
Playwright credential expired
pytest generated directory disappears
scenario-matrix child timeout
finalization interrupted at every stage
```

---

# 19. Required commands

Use repository-native commands where available. At minimum execute the equivalent of:

```text
python -m compileall apps backend tools tests
python -m pytest --collect-only -q tests
python -m pytest -q tests
```

Focused MATLAB:

```text
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*QualificationFinalization*'); assertSuccess(r);"

matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Artifact*'); assertSuccess(r);"

matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*FullStack*'); assertSuccess(r);"

matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Integration*'); assertSuccess(r);"
```

Run exact scenario-matrix methods independently and export their results.

Recovery:

```text
matlab -batch "addpath(pwd); out=sixgr.integration.qualification.resumeFinalize(...); assert(out.CompletedWithoutException);"
```

Artifact verification:

```text
python tests/vectors/full_stack_qualification/verify_full_stack_qualification_artifacts.py <recovery-root> <contract-root> --preset comprehensive_smoke
```

The recovery verifier may still return nonzero due genuinely missing domain evidence, but it must no longer fail because of finalization-schema, finalization-ordering, path-resolution, or publication bugs.

After targeted waves pass, launch a new WebGUI run and execute the full verifier again.

---

# 20. Required recovery gates before another full WebGUI run

Do not launch the full 31-subcase scenario again until all of these pass:

```text
GATE-R01 ArtifactType crash reproduced by a pre-fix test.
GATE-R02 Canonical artifact schema normalization tests pass.
GATE-R03 Finalizer never throws on malformed artifact tables.
GATE-R04 Existing run recovery completes twice with deterministic hashes.
GATE-R05 Ten supplied full-stack images count as valid in completeness.
GATE-R06 Filesystem publication works with MySQL inactive.
GATE-R07 pytest collection is restricted to tests and passes repeatedly.
GATE-R08 WebGUI unit shard collects at least one test and passes.
GATE-R09 Playwright receives a revocable ephemeral operator credential securely.
GATE-R10 test6GScenarioMatrixRunner methods are individually identified and bounded.
GATE-R11 The two actual failing matrix tests are fixed, not hidden.
GATE-R12 Validation and integration exporters execute before final manifest.
GATE-R13 Component/subcase/suite reduction invariants pass.
GATE-R14 PDSCH and PUSCH targeted base phases pass.
GATE-R15 Fixed DL/UL five-point sweep produces actual measured results.
GATE-R16 Initial access and MIMO/beam targeted phases pass.
GATE-R17 No required present artifact is classified invalid due only to stale ordering.
GATE-R18 Recovery failure list contains only genuine missing/numerical/semantic evidence.
```

---

# 21. New full WebGUI rerun

After all recovery gates pass, launch the same scenario from the secured canonical WebGUI:

```text
lls_webgui_full_stack_sinr_geometry_qualification
preset=comprehensive_smoke
```

Use a new run tag. Do not reuse or overwrite either previous run.

The WebGUI run must record:

```text
RunID
Owner
Source/Effective/Resolved/Executed YAML hashes
Git commit
MATLAB/Toolbox versions
Finalization schema version
Artifact registry version
Regression-plan version
```

Monitor each subcase. If one subcase fails, do not wait hours before collecting its evidence; export and classify its failure immediately while allowing independent subcases to continue where safe.

---

# 22. Final definition of done

Do not report COMPLETE unless all are true:

```text
No ArtifactType or table-schema exception.
No finalization exception of any kind.
InfrastructureFinalizationStatus = PASS.
Qualification finalization is idempotent.
Final manifest is the last inventory step.
All generated PNG semantic rows join correctly.
All filesystem artifacts are published to the WebGUI.
No optional MySQL dependency blocks filesystem publication.
pytest collects only tests and passes.
WebGUI unit tests collect >0 and pass.
Playwright login and full-stack workflow pass with secure ephemeral credentials.
Full MATLAB regression completes without timeout.
test6GScenarioMatrixRunner has actual per-method results and zero failures.
All mandatory tests are executed; none skipped or blocked.
All 31 mandatory subcases pass.
All 163 components pass.
All 107 value checks pass.
All 77 negative tests pass.
All 387 acceptance rules pass.
All 447 required CSVs are present and valid.
All 299 required PNGs are present and valid.
All 746 required artifacts are published in WebGUI.
Independent artifact verifier exits 0.
Resolved and executed YAML hashes match.
No configured value substitutes for runtime evidence.
No placeholder artifact exists.
Repository is clean after the final commit.
```

A correctly finalized scientific FAIL is acceptable during recovery, but final COMPLETE requires the full list above.

---

# 23. Required Codex response after each checkpoint

Return:

```text
1. Active branch and commit.
2. Checkpoint objective.
3. Root cause reproduced.
4. Files changed.
5. Exact schema/API changes.
6. Tests added.
7. Exact commands executed.
8. Test counts: passed/failed/skipped/blocked.
9. Recovery run root and hashes.
10. Artifact counts before and after.
11. Remaining failures by category.
12. Targeted subcases rerun.
13. WebGUI publication result.
14. Regression result with exact failed test names.
15. Final status: COMPLETE, FAIL, or BLOCKED.
16. Next dependency-ordered action.
```

Begin with the exact `ArtifactType` reproduction and canonical schema correction. Do not launch another complete qualification run until the recovery gates in Section 20 pass.
