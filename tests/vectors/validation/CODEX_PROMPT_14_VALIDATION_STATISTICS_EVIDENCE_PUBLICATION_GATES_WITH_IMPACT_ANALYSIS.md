# CODEX IMPLEMENTATION PROMPT 14
# Validation, Statistics, Evidence and Publication Gates

You are the lead MATLAB validation architect, statistical-methods owner, scientific-computing reviewer, CI/release engineer and publication-evidence owner for the 6GR simulator repository.

This is an implementation task.

Do not return a plan-only response.

Modify the production source, migrate all callers, add executable MATLAB and Python tests, run the tests, generate the contracted CSV and PNG artifacts, verify their schemas and hashes, and continue correcting defects until the selected validation profile passes.

The authoritative input assets are located under:

```text
tests/vectors/validation/
```

They include:

```text
validation_statistics_evidence_publication_28_findings.csv
validation_enums.yaml
validation_canonical_point_schema.json
validation_run_manifest_schema.json
validation_oracle_registry_schema.json
independent_vector_manifest.json
validation_*_vectors.csv
validation_impact_*.csv
desired_validation_*_contract.csv
verify_validation_vector_pack.py
verify_validation_artifacts.py
verify_validation_impact_artifacts.py
```

---

# 1. Mission

Build one common, fail-closed validation engine for every simulator phase.

The engine must own:

```text
canonical schemas
point identity
point status
stop reasons
interval calculations
sequential stopping
zero-error censoring
independent-drop aggregation
reference and oracle independence
complete operating-point joins
curve comparison
runtime evidence provenance
measured-SINR authority
run-class isolation
time-window semantics
task/seed partition
deterministic distributed merge
artifact requirements
canonical scenario execution
release-archive acceptance
test-execution evidence
publication gate evaluation
```

The objective is not to make current outputs pass.

The objective is to make every accepted result scientifically and computationally defensible.

---

# 2. Non-negotiable rules

1. Never write DUT output into a file called reference, baseline, oracle, expected or golden.
2. Never use the same implementation on both sides of a mandatory independent comparison.
3. Never accept a mandatory point with an unknown, legacy or free-form point status or stop reason.
4. Never accept `Incomplete=true` without a canonical non-passing status, except a policy-approved censored completion with a valid one-sided confidence bound.
5. Never calculate a 95 percent interval when the configured confidence level is 90 or 99 percent.
6. Never repeatedly inspect ordinary fixed-sample intervals at multiple looks and report them as if optional stopping did not occur.
7. Never substitute configured SNR for receiver-measured post-equalization SINR in a run class that requires measured SINR.
8. Never call configured, model-reconstructed or diagnostic values observed runtime evidence.
9. Never allow the expected and applied sides of a validation comparison to share a disallowed configured or DUT root.
10. Never let an AWGN calibration artifact satisfy a geometry, mobility, interference, MAC or system-level gate.
11. Never let a fixture/static test satisfy a mandatory runtime scenario gate.
12. Never pass a gate because a table is nonempty.
13. Never skip a check because a column, row, threshold or table is missing.
14. Never treat NaN, Inf, empty string or wrong type as “not applicable” unless the canonical schema explicitly permits it.
15. Never count an identical retried task twice.
16. Never use last-writer-wins when the same task ID produces two different output hashes.
17. Never allow execution order to alter the canonical merged result.
18. Never use stale artifacts from a prior source tree, scenario or toolchain.
19. Never mark MATLAB-dependent validation passed when MATLAB or a required Toolbox is unavailable.
20. Never report a required skipped/blocked test as passed.
21. Never use a browser-only or headless-only artifact requirement.
22. Never present an internal numerical regression suite as a global 3GPP score.
23. Never mutate tests merely to preserve a shortcut.
24. Never copy supplied expected CSVs into the output folder.
25. Every final publication gate must be reconstructible from canonical raw trials, manifests and hashes.

---

# 3. Validation profiles

Implement explicit profiles:

```text
nr_rel18_phy_lls_strict
nr_rel18_system_lls_strict
protocol_system_study
rel20_6g_study_context
internal_numerical_regression
unsupported_extension
```

A profile determines:

```text
required run class
required point-key fields
minimum independent drops
minimum trials
minimum errors
maximum trials
look schedule
confidence level
interval method
zero-error policy
measured-SINR requirement
qualifying oracle types
required canonical scenarios
required artifacts
curve-comparison policy
calibration requirements
publication eligibility
```

The `internal_numerical_regression` profile is useful, but it cannot satisfy runtime or publication gates.

---

# 4. Canonical production architecture

Create or consolidate the implementation under:

```text
+sixgr/+validation/
    ValidationSpecificationProfile.m
    ValidationCapabilityProfile.m
    ValidationPlanningResult.m

    PointStatus.m
    StopReason.m
    RunClass.m
    OracleType.m
    EvidenceProvenanceClass.m

    OperatingPointKey.m
    CampaignPointRecord.m
    CampaignPointStateMachine.m

    ValidationSchemaRegistry.m
    CanonicalSchemaValidator.m
    CompatibilityAliasGenerator.m
    SchemaMutationGenerator.m

    BinomialIntervalEngine.m
    SequentialDesign.m
    SequentialStoppingPolicy.m
    ZeroErrorCensorPolicy.m
    IndependentDropPolicy.m
    IndependentDropAggregator.m

    OperatingPointJoiner.m
    PointComparisonResult.m
    CurveComparisonEngine.m
    MultiplicityAdjustment.m

    IndependentOracleDescriptor.m
    IndependentOracleRegistry.m
    IndependentVectorCatalog.m
    ReferenceDatasetDescriptor.m
    ReferenceDatasetRegistry.m
    CalibrationCatalog.m

    EvidenceRecord.m
    EvidenceProvenanceGraph.m
    EvidenceCircularityChecker.m
    RuntimeEvidenceGate.m
    MeasuredSINRGate.m

    TimeWindowContract.m
    KPISampleLedger.m

    DeterministicTaskPlan.m
    SeedLedger.m
    TaskOutputManifest.m
    DeterministicMergeEngine.m

    ArtifactRequirementRegistry.m
    ArtifactAuditResult.m
    CanonicalScenarioRunner.m
    ArchiveAcceptanceRunner.m
    TestExecutionLedger.m

    PublicationGateEvaluator.m
    ValidationArtifactExporter.m

    runValidationPhaseValidation.m
    runValidationImpactAnalysis.m
```

The following existing functions may remain as compatibility façades only:

```text
+sixgr/+stats/wilsonBinomialCI.m
+sixgr/+lls6g/+campaign/runFixedLinkCampaign.m
+sixgr/+validation/auditFixedSNRSweepRun.m
+sixgr/+analytics/evaluatePublicationReadinessGates.m
+sixgr/+analytics/exportFixedSNRSweepCurves.m
+sixgr/+truth/runWaveformLinkBundle.m
+sixgr/+truth/exportLLSReportingBundle.m
+sixgr/+analytics/buildPhase7ReadinessArtifacts.m
```

They must delegate to the canonical engine and must not retain separate confidence, stop-reason, reference, provenance or gate logic.

---

# 5. Canonical enums

Use `validation_enums.yaml` as the contract.

Point statuses are:

```text
NOT_STARTED
RUNNING
COMPLETE
CENSORED_COMPLETE
INCOMPLETE_MAX_TRIALS
FAILED_SCHEMA
FAILED_ORACLE
FAILED_PROVENANCE
FAILED_STATISTICS
BLOCKED_TOOLCHAIN
SKIPPED_NOT_APPLICABLE
```

Stop reasons are:

```text
NONE
MIN_TRIALS_NOT_MET
MIN_ERRORS_AND_CI_MET
ZERO_ERROR_UPPER_BOUND_MET
MAX_TRIALS_REACHED_INCOMPLETE
MAX_TRIALS_REACHED_CENSORED_PASS
MAX_RUNTIME_REACHED
INVALID_CONFIGURATION
NUMERICAL_FAILURE
ORACLE_FAILURE
PROVENANCE_FAILURE
DUPLICATE_TASK_CONFLICT
STALE_ARTIFACT
TOOLCHAIN_UNAVAILABLE
USER_ABORT
```

Legacy tokens are accepted only by an explicit migration layer.

Unknown tokens must raise:

```text
sixgr:validation:UnknownPointStatus
sixgr:validation:UnknownStopReason
sixgr:validation:LegacyTokenUnmapped
```

Do not retain both:

```text
max_tb_per_point_reached
max_trials_reached
```

as live production semantics.

---

# 6. Complete operating-point identity

The minimum canonical point key is:

```text
RunClass
Direction
ProfileID
ChannelModel
CarrierFrequency_Hz
Bandwidth_Hz
SCS_kHz
MCS
Rank
Receiver
SNR_dB
```

Extend the key when a result depends on:

```text
waveform
DM-RS profile
PT-RS profile
antenna/codebook profile
interference profile
channel-estimation method
component carrier
BWP
numerology
HARQ combining state
RF-impairment profile
toolchain or calibration version
```

A comparison must be one-to-one on the complete key.

Report:

```text
matched points
missing DUT points
missing reference points
extra DUT points
extra reference points
duplicate DUT points
duplicate reference points
incompatible profile points
```

Never silently use nearest SNR, nearest MCS, nearest rank or the first duplicate row.

---

# 7. Schema-first fail-closed execution

Before numerical evaluation:

1. validate the canonical schema version;
2. validate mandatory columns;
3. validate types;
4. validate finite numbers;
5. validate bounded values;
6. validate relational constraints;
7. validate primary-key uniqueness;
8. validate enum values;
9. validate hashes;
10. validate nonempty mandatory tables.

Examples of mandatory relational checks:

```text
0 <= ErrorCount <= TrialCount
0 <= Estimate <= 1
0 <= CILow <= Estimate <= CIHigh <= 1
0 < ConfidenceLevel < 1
MeasuredSINRSampleCount >= 1 when measured SINR is required
PointStatus and StopReason are a legal pair
CENSORED_COMPLETE has a one-sided bound and policy ID
COMPLETE has satisfied the declared stopping rule
```

Initialize every mandatory gate to failure.

A gate can transition to pass only after all required evidence is proven.

---

# 8. Statistical interval engine

## 8.1 Wilson two-sided interval

For observed error count `k`, trial count `n` and confidence level `1-alpha`:

```text
p_hat = k / n
z = Phi^-1(1 - alpha/2)

denominator = 1 + z^2/n

center =
    (p_hat + z^2/(2n))
    / denominator

half_width =
    z * sqrt(
        p_hat(1-p_hat)/n
        + z^2/(4n^2)
    )
    / denominator
```

Return:

```text
lower = max(0, center - half_width)
upper = min(1, center + half_width)
```

## 8.2 Clopper-Pearson exact two-sided interval

```text
lower = 0
    when k = 0
else
    BetaInv(alpha/2, k, n-k+1)

upper = 1
    when k = n
else
    BetaInv(1-alpha/2, k+1, n-k)
```

## 8.3 Exact one-sided upper bound

For the one-sided confidence level `1-alpha`:

```text
upper =
    BetaInv(1-alpha, k+1, n-k)
```

For zero observed errors:

```text
upper =
    1 - alpha^(1/n)
```

Every interval result must record:

```text
method
confidence level
sidedness
success/error convention
k
n
estimate
lower
upper
look index
alpha spent
design ID
```

Remove every hard-coded:

```text
1.95996398454005
wilson_95pct
ConfidenceLevel = 0.95
```

from production campaign logic.

---

# 9. Sequential stopping and optional-stopping control

A campaign is not permitted to inspect an ordinary nominal fixed-sample interval repeatedly and then report the final interval as if no sequential selection occurred.

Implement a bounded look schedule.

Minimum required design:

```text
NominalAlpha = 1 - NominalConfidenceLevel
AlphaPerLook = NominalAlpha / MaxLooks
LookConfidenceLevel = 1 - AlphaPerLook
```

This Bonferroni design is conservative and deterministic.

A more efficient predeclared alpha-spending or confidence-sequence design may be added later, but it must have independent coverage tests.

Each profile declares:

```text
MinTrials
MinErrors
MaxTrials
MaxLooks
LookSchedule
TargetHalfWidth
TargetZeroErrorUpperBound
NominalConfidenceLevel
IntervalMethod
```

Canonical decisions:

```text
n < MinTrials
    => RUNNING / MIN_TRIALS_NOT_MET

k = 0 and one-sided upper <= target
    => CENSORED_COMPLETE / ZERO_ERROR_UPPER_BOUND_MET

k >= MinErrors and adjusted two-sided half-width <= target
    => COMPLETE / MIN_ERRORS_AND_CI_MET

n >= MaxTrials and neither completion rule is met
    => INCOMPLETE_MAX_TRIALS / MAX_TRIALS_REACHED_INCOMPLETE
```

A max-trial point is never automatically complete.

Run Monte Carlo coverage tests against known Bernoulli rates.

The empirical coverage must meet the configured design bound within the predeclared simulation tolerance.

---

# 10. High-SNR and zero-error policy

Delete a sanity rule that requires:

```text
BLER(highest SNR) < BLER(lowest SNR)
```

as the only valid behavior.

A zero-error high-SNR plateau can be valid when its one-sided upper confidence bound satisfies the objective.

The curve gate must check:

```text
valid complete/censored point state
successful-decoding or error-probability bound
non-degradation within uncertainty
objective-specific high-SNR upper bound
minimum overlap and point count
```

An actually inverted or degraded curve must still fail.

---

# 11. Independent drops and seeds

Distinguish:

```text
within-drop trials
independent channel drops
independent random seeds
retries of the same task
```

Every profile declares a minimum number of independent drops.

A repeated task with the same seed, drop identity and input hash is a retry, not a new independent sample.

Report:

```text
input rows
unique drop IDs
unique seeds
unique substreams
within-drop trials
between-drop variance
aggregate estimate
aggregate uncertainty
duplicate-drop count
duplicate-seed count
```

Do not obtain an artificially narrow interval by duplicating the same drop.

---

# 12. Independent reference and oracle registry

Qualifying mandatory oracle types are:

```text
PURE_MATH
FROZEN_EXTERNAL_VECTOR
ANALYTICAL_INVARIANT
STATISTICAL_DISTRIBUTION
```

The following are regression-only:

```text
SAME_TOOLBOX_SELF_CONSISTENCY
DUT_REGRESSION
```

Every oracle entry records:

```text
OracleID
OracleType
Feature
ProfileID
SourceName
SourceVersion
GeneratorCommand
ArtifactPath
ArtifactSHA256
IndependentOfDUT
QualifiesForMandatoryGate
License
CreatedUTC
```

A reference dataset additionally records:

```text
implementation
implementation version
source repository/commit
toolchain
profile
scenario
operating-point key
raw trial artifact
generation command
artifact hash
```

The DUT and reference source/hash must differ.

Delete all code that writes the same table to:

```text
lls_snr_sweep.csv
lls_reference_snr_sweep.csv
```

---

# 13. Confidence-aware DUT/reference comparison

For each complete matched point, compare the difference:

```text
Delta = p_DUT - p_reference
```

Implement a Newcombe score interval based on the two Wilson score intervals.

For DUT interval `[L1,U1]`, reference interval `[L0,U0]`:

```text
DeltaLower =
    Delta
    - sqrt(
        (p_DUT - L1)^2
        + (U0 - p_reference)^2
      )

DeltaUpper =
    Delta
    + sqrt(
        (U1 - p_DUT)^2
        + (p_reference - L0)^2
      )
```

Clamp the result to `[-1,1]`.

Non-inferiority with margin `M` passes only when:

```text
DeltaUpper <= M
```

Two-sided equivalence with margin `M` passes only when:

```text
DeltaLower >= -M
and
DeltaUpper <= M
```

Apply the profile-declared multiplicity policy, at minimum Holm adjustment for families of related point hypotheses.

Report effect sizes and uncertainty.

A non-significant difference is not evidence of equivalence.

---

# 14. Calibration catalog

A strict link-adaptation profile must resolve to an exact calibration key.

Minimum key:

```text
direction
channel model
waveform
receiver
MCS table
MCS
rank
SCS
bandwidth
DM-RS profile
PT-RS profile
target BLER
toolchain version
implementation version
```

Each calibration entry records:

```text
raw trials
independent drops and seeds
confidence intervals
fit method
fitted parameters
training data hash
held-out data hash
held-out prediction error
maximum permitted held-out error
generation command
```

Do not use nearest-profile or generic laboratory fallback values in strict execution.

---

# 15. Runtime evidence provenance

Permitted provenance classes:

```text
OBSERVED_RUNTIME_STATE
DERIVED_FROM_OBSERVED_RUNTIME_STATE
DECODED_RECEIVER_STATE
CONFIGURED
RECONSTRUCTED_DIAGNOSTIC
EXTERNAL_ORACLE
DUT_OUTPUT
```

For every field record:

```text
NodeID
FieldName
Value
Unit
ProvenanceClass
RootID
ParentNodeIDs
FormulaID
Producer
SourceArtifact
Timestamp
ConfigurationEpoch
```

Strict runtime evidence may use:

```text
OBSERVED_RUNTIME_STATE
DERIVED_FROM_OBSERVED_RUNTIME_STATE
DECODED_RECEIVER_STATE
```

Configuration and reconstructed diagnostics remain visible but cannot fill mandatory runtime fields.

The circularity checker rejects a comparison when:

```text
expected and applied sides share a disallowed root
reference is derived from DUT output
applied result is reconstructed from the same configured model as expected
```

---

# 16. Measured SINR authority

For every run class requiring link metrics, post-equalization SINR must be:

```text
finite
receiver-derived
associated with exact REs/layers/codewords
associated with the correct point key
associated with sample count
associated with estimator/equalizer/covariance state
associated with measurement time and age
```

Configured SNR is an input operating-point field.

It is not the measured result.

A missing or configured-derived measured SINR must fail with:

```text
sixgr:validation:MeasuredSINRMissing
sixgr:validation:MeasuredSINRInvalidProvenance
```

---

# 17. Time-window contract

Use half-open intervals:

```text
WARMUP       [start, warmupEnd)
ACQUISITION  [warmupEnd, acquisitionEnd)
STEADY_STATE [acquisitionEnd, steadyEnd)
TAIL_DRAIN   [steadyEnd, tailEnd)
```

Every raw KPI sample records:

```text
timestamp
phase
KPI
value
included/excluded
inclusion rule
owner event
run/drop/task identity
```

Examples:

```text
steady-state BLER:
    STEADY_STATE only

acquisition delay:
    ACQUISITION

delivered goodput:
    STEADY_STATE plus declared TAIL_DRAIN delivery policy

queue drain:
    TAIL_DRAIN
```

No summary KPI is accepted unless it can be reconstructed from the raw sample ledger.

---

# 18. Run-class isolation

Keep these physically separate:

```text
FIXED_LINK_CALIBRATION
GEOMETRY_LINK_LEVEL
SYSTEM_LEVEL
CONTROL_ONLY
PROTOCOL_SYSTEM_STUDY
```

Each run class owns independent:

```text
manifest
gate set
artifact set
status
failure reasons
```

Examples:

```text
missing geometry evidence cannot be satisfied by AWGN sweep data
missing scheduler evidence cannot be satisfied by link-calibration curves
control-only success cannot satisfy PDSCH/PUSCH data gates
protocol-system evidence cannot substitute for PHY reference vectors
```

The UI may display classes together only when it clearly preserves their separate status.

---

# 19. Deterministic task, seed and merge engine

Every task owns:

```text
CampaignID
TaskID
complete point key
IndependentDropID
Seed
Substream
TrialStart
TrialEnd
InputSHA256
SourceCommit
ScenarioSHA256
ToolchainID
```

The output owns:

```text
TaskID
OutputSHA256
RawTrialSHA256
RowCount
TrialCount
ErrorCount
StartUTC
EndUTC
WorkerID
RetryIndex
```

Merge policy:

```text
same TaskID and same output hash
    => idempotent retry; count once

same TaskID and different output hash
    => DUPLICATE_TASK_CONFLICT; fail campaign

different TaskIDs
    => canonical sort by immutable key before aggregation
```

Use deterministic accumulation.

For floating-point summaries, use a fixed canonical order and a stable summation method.

Serial, parallel and shuffled execution must produce:

```text
identical canonical raw rows
identical task manifest
identical summary values
identical summary hashes
```

Use explicit worker substreams rather than client/worker global RNG state. The existing hierarchical seed helper may be retained as a primitive.

---

# 20. Artifact and archive acceptance

Artifact requirements are determined by:

```text
run class
profile
scenario
enabled feature tuple
```

They are not determined by:

```text
browser launch
headless launch
direct MATLAB launch
CI launch
```

For every required artifact report:

```text
required
generated
exists
schema valid
content valid
fresh
source hash valid
artifact hash valid
semantic plot audit valid
```

The release archive acceptance runner must:

1. build the archive from a clean source tree;
2. compute the archive hash;
3. extract into a clean workspace;
4. verify source and scenario hashes;
5. verify the pinned MATLAB and Toolbox versions;
6. execute mandatory canonical scenarios;
7. execute mandatory tests;
8. reject stale result reuse;
9. verify every required artifact;
10. produce one immutable acceptance manifest.

A fixture-only archive test cannot satisfy this gate.

---

# 21. Python and YAML CI

Python module import must not require an installed MATLAB executable.

Importing the dashboard for pure unit tests must not raise `FileNotFoundError`.

MATLAB availability is checked only when a MATLAB action is invoked.

The no-MATLAB Python CI must:

```text
collect every pure Python test
run pure schema/vector/verifier tests
mock external execution capabilities
report MATLAB-dependent integration tests as explicitly separated
```

All source YAML files must be checked for:

```text
parseability
duplicate keys
schema validity
canonical form
cross-reference validity
path validity
enum validity
```

Fix unquoted colons and every other source YAML parse failure.

---

# 22. Internal anchors versus runtime conformance

Rename the current “10/10” concept.

Use terms such as:

```text
internal_numerical_release_gate
profile_runtime_acceptance
canonical_scenario_acceptance
publication_evidence_gate
```

For every anchor report:

```text
AnchorType = RUNTIME | FIXTURE | STATIC
```

A fixture/static anchor can be valuable.

It cannot satisfy a runtime profile gate.

The final report must list the actual number and type of anchors without converting them into a universal numerical score.

---

# 23. Detailed findings


## VAL-025 — Canonical schemas and compatibility aliases

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Duplicate aliases, multiple summaries and legacy fields can diverge or mask missing canonical evidence.

### Required production implementation

Define versioned canonical schemas and generate compatibility aliases from canonical data only; add equality/reconciliation assertions.

### Mandatory tests

Schema tests detect alias divergence, duplicate semantic fields and missing canonical owners.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-001 — Canonical PointStatus/StopReason enumerations

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

The campaign emits stop reason max_tb_per_point_reached while the audit checks max_trials_reached.

### Required production implementation

Define one enum used by campaign, exporters, audits, gates and UI; migrate old tokens explicitly and reject unknown values.

### Mandatory tests

A capped incomplete point is detected by every gate and UI using the same enum; enum contract test covers all stop reasons.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-012 — Schema-first fail-closed validation

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

Missing metric columns and NaN thresholds can fail open because checks are skipped and local validity defaults true.

### Required production implementation

Validate schemas and finite/bounded thresholds before any value comparison; initialize all gates fail-closed and require mandatory columns/rows.

### Mandatory tests

Column/threshold deletion, NaN, Inf, wrong type and empty-table mutation tests all fail with explicit reasons.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-013 — Configurable statistical confidence

**Priority:** P1  
**Classification:** Confirmed defect

### Current defect

The configured confidence level is overwritten/defaulted to 0.95 in campaign paths and Wilson calculations/labels are hard-coded to 95%.

### Required production implementation

Pass confidence level into every interval routine; compute z/quantiles dynamically; record method/level; reject inconsistent metadata.

### Mandatory tests

90%, 95% and 99% fixtures match trusted calculations and produce monotonically wider intervals.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-016 — Sequential design and optional-stopping control

**Priority:** P1  
**Classification:** Validation gap

### Current defect

The stopping rule does not fully define zero-error, rare-error, censored, multiplicity and curve-comparison policies.

### Required production implementation

Document and implement a sequential design: min trials, min errors where applicable, max trials, target CI, one-sided upper bounds, and no optional stopping bias in reported intervals.

### Mandatory tests

Simulation against known Bernoulli rates demonstrates coverage and correct stop classifications.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-002 — Sequential stopping and censored-point policy

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

Rows marked Incomplete=true can escape minimum-trial/publication checks and still contribute to an accepted curve.

### Required production implementation

Fail every required incomplete point unless it has an explicit policy-approved censored status with a one-sided confidence bound that satisfies the objective.

### Mandatory tests

Zero-error/high-SNR, cap-hit, low-error and CI-miss tests produce the correct complete/censored/fail verdict.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-014 — High-SNR success-bound policy

**Priority:** P1  
**Classification:** Confirmed defect

### Current defect

The endpoint sanity check requires strictly lower BLER at high SNR, so a valid saturated zero-error plateau can fail.

### Required production implementation

Use non-increasing trend with uncertainty, successful-decoding bounds, or an objective-specific high-SNR upper confidence bound.

### Mandatory tests

Flat zero-error endpoints pass when upper bounds meet target; inverted/degraded curves fail.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-015 — Independent drop/seed aggregation

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Single-run point estimates can dominate result status without mandatory independent-drop aggregation.

### Required production implementation

Require profile-specific minimum drops/seeds and hierarchical aggregation; distinguish within-drop trials from independent channel drops.

### Mandatory tests

CI and pass/fail use independent-drop statistics; duplicated same-seed drops are detected.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-028 — Deterministic distributed task and merge engine

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Seed partitioning, retry behavior, duplicate task detection, merge order and numerical reproducibility are not fully proven for parallel/distributed campaigns.

### Required production implementation

Assign immutable task IDs/seeds, idempotent outputs, checksummed merges and deterministic aggregation independent of execution order.

### Mandatory tests

Serial and shuffled parallel execution produce identical merged raw data and summaries; duplicate/retried tasks are detected.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-027 — Calibration versus geometry run-class isolation

**Priority:** P1  
**Classification:** Claim-scope gap

### Current defect

A fixed-input AWGN sweep can be presented alongside geometry/system results in ways that imply broader channel or scheduler validation.

### Required production implementation

Keep calibration and geometry/system run classes physically and visually separate; prohibit cross-mode gate substitution.

### Mandatory tests

A missing geometry gate cannot be satisfied by AWGN artifacts and vice versa; manifests list independent status fields.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-005 — Observed runtime evidence requirements

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

Configured/model-derived geometry values are accepted as runtime evidence and can satisfy completeness.

### Required production implementation

Require observed runtime samples for all mandatory physics fields; allow derived values only when derived from observed state with an explicit formula/provenance; configuration-only values are diagnostics.

### Mandatory tests

Per-field deletion and provenance-mutation tests fail strict gates.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-006 — Evidence provenance DAG and circularity detector

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

Doppler/pathloss/delay reconciliation can compare values sharing the same configured source, creating circular validation.

### Required production implementation

Build a provenance DAG and prohibit comparisons whose expected and applied values share a non-observed root; use runtime channel coefficients/measurements as the independent side.

### Mandatory tests

Self-derived fixtures are rejected; analytically generated observed fixtures pass.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-011 — Mandatory receiver-measured SINR

**Priority:** P0  
**Classification:** Validation gap

### Current defect

Measured post-equalization SINR can be optional in the catalog scenario despite a tolerance and UI claim.

### Required production implementation

Make receiver-measured SINR mandatory by run class and require finite value/provenance/sample count for every point.

### Mandatory tests

Real catalog run fails when the receiver SINR column is absent/NaN/config-derived.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-007 — Independent-oracle classification and enforcement

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Many tests compare a wrapper to the same MathWorks function or re-use DUT helpers, so oracle independence is not guaranteed.

### Required production implementation

Tag every test with OracleType; require independent pure-math/golden/statistical oracles for mandatory rows and quarantine self-consistency tests as regression-only.

### Mandatory tests

CI report shows zero mandatory features whose only oracle is self_consistency/same_toolbox.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-019 — Signed independent vector catalog

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Independent frozen golden vectors are incomplete across scrambling, coding, modulation, resource mapping, control and measurements.

### Required production implementation

Create a signed vector catalog with generator/source/version/license/provenance, inputs, expected outputs and hashes; include boundary and negative vectors.

### Mandatory tests

Vector catalog validation passes without calling DUT/Toolbox reference functions at generation time.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-003 — Independent reference dataset registry

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

The primary sweep table is copied to the “reference” CSV, so the publication reference is not independent.

### Required production implementation

Stop writing DUT results as reference. Load a versioned independent dataset/run identified by source, tool/version, commit, profile and hash.

### Mandatory tests

Reference and DUT hashes/sources differ; deleting reference blocks the comparison; deliberately shifted data fails tolerance checks.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-004 — Complete operating-point join and numerical comparison

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

PublicationReferenceComparisonOk checks only that the reference table is non-empty; no point matching or numeric comparison occurs.

### Required production implementation

Join on direction/MCS/SNR/profile and compare BLER/BER/SINR/throughput with declared tolerances and confidence-aware rules; report missing/extra points.

### Mandatory tests

Known matching, shifted, missing, duplicate and incompatible-reference fixtures yield deterministic pass/fail reasons.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-017 — Curve equivalence/non-inferiority engine

**Priority:** P1  
**Classification:** Validation gap

### Current defect

No confidence-aware equivalence/non-inferiority method is defined for comparing BLER curves.

### Required production implementation

Define pointwise or model-based comparison, tolerance bands, multiple-comparison handling, minimum overlap and missing-point policy by profile.

### Mandatory tests

Synthetic equal, shifted, crossing and sparse curves produce expected verdicts with reported effect sizes/uncertainty.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-018 — Calibration catalog and hold-out validation

**Priority:** P1  
**Classification:** Validation gap

### Current defect

There is no complete calibration matrix tying MCS/rank/channel/numerology/receiver to target BLER curves and link-to-system parameters.

### Required production implementation

Build a versioned calibration catalog with raw trials, seeds, confidence intervals, receiver/toolchain versions, fitted parameters and hold-out validation.

### Mandatory tests

Every strict link-adaptation profile resolves to a matching calibration entry and passes held-out prediction bounds.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-020 — Capability-derived negative testing

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Negative testing is not complete for unsupported combinations, malformed messages, wrong identities, missing resources, stale measurements and impossible timings.

### Required production implementation

Generate negative tests from the capability/schema matrix and require typed fail-closed errors or no-detection outcomes.

### Mandatory tests

Every unsupported/invalid matrix row has a deterministic negative test and no silent downgrade.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-026 — Time-window and KPI sample contract

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Warm-up, acquisition, steady-state, drop reset, measurement window and tail-drain semantics are not uniformly defined across KPIs.

### Required production implementation

Create a time-window contract with named phases, per-KPI inclusion rules and reset behavior; export sample counts and timestamps.

### Mandatory tests

Boundary tests show exact inclusion/exclusion and KPI reconstruction from raw events.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-024 — Launch-surface-independent artifact requirements

**Priority:** P1  
**Classification:** Confirmed defect

### Current defect

Required geometry images and recursive artifact checks can be bypassed in direct/headless runs, and plot success may be forced without checking required stems.

### Required production implementation

Apply artifact requirements independent of launch surface; return required/generated/missing sets; fail status when a mandatory artifact cannot be created or is invalid.

### Mandatory tests

Headless/direct/browser runs have identical artifact verdicts; deleting each required artifact fails.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-009 — Executable canonical scenario matrix

**Priority:** P1  
**Classification:** Validation gap

### Current defect

The release scenario matrix often validates paths/tokens/configuration but does not execute every canonical scenario end-to-end.

### Required production implementation

Convert the matrix into executable smoke/full tiers with resource budgets; materialize configs, run, audit artifacts, and aggregate results.

### Mandatory tests

Every mandatory canonical scenario has a fresh run ID, manifest, status and passed artifact audit in release CI.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-010 — Clean-built archive acceptance

**Priority:** P1  
**Classification:** Validation gap

### Current defect

Archive acceptance can pass fixture artifacts rather than validating the actual built release package and fresh run outputs.

### Required production implementation

Run acceptance against the just-built archive in a clean workspace; verify source hashes, toolchain, canonical runs and no stale result reuse.

### Mandatory tests

Tampering, stale run timestamps, changed source or missing binary provenance causes failure.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-021 — Pinned MATLAB/Toolbox runtime execution evidence

**Priority:** P0  
**Classification:** Validation gap

### Current defect

The full MATLAB test suite and canonical scenarios were not executed in the audit environment and current release evidence does not prove they pass on the declared release.

### Required production implementation

Run all required tests on the pinned MATLAB/Toolbox release in CI and preserve logs/JUnit/artifacts; never mark a gate passed when the runner is unavailable.

### Mandatory tests

Release CI shows zero failed/skipped-required MATLAB tests and successful canonical runs.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-022 — Side-effect-free Python test collection

**Priority:** P1  
**Classification:** Confirmed defect

### Current defect

Default pytest collection fails because of import-time MATLAB/path assumptions and package/import issues; a contract test also expects an obsolete section count.

### Required production implementation

Make imports side-effect free, add pytest configuration/package paths, mock external capabilities, and update assertions to semantic section IDs rather than a brittle count.

### Mandatory tests

pytest -q collects and passes in a no-MATLAB CI environment.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-023 — All-source YAML/schema validation

**Priority:** P0  
**Classification:** Validation gap

### Current defect

All source YAML files are not parsed and schema-validated in mandatory CI, allowing invalid catalog content into the package.

### Required production implementation

Add all-file YAML parsing with duplicate-key detection, schema validation, canonicalization and cross-reference checks.

### Mandatory tests

Every source YAML passes; one invalid mutation fails the exact CI job.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


## VAL-008 — Internal numerical gate versus runtime conformance suites

**Priority:** P0  
**Classification:** Confirmed defect

### Current defect

The “10/10” release suite contains nine anchors and some anchors validate metadata/fixtures rather than complete runtime scenarios.

### Required production implementation

Rename the gate, expose anchor type (runtime/fixture/static), and create separate profile conformance suites that execute canonical scenarios.

### Mandatory tests

Release report lists nine internal anchors without a numeric 3GPP score; profile suite requires runtime results.

### Codex implementation instructions

1. Locate every producer, consumer, exporter, UI reader, test fixture and compatibility alias associated with this behavior.
2. Add a failing reproduction test before changing production behavior.
3. Implement the correction in the canonical validation package; do not add another parallel audit path.
4. Migrate all callers to the canonical schema and enum.
5. Add positive, boundary, mutation, stale-artifact, wrong-run-class and deterministic-retry tests where applicable.
6. Export one canonical result row with the exact status, reason, evidence references and hashes.
7. Do not close this finding when a mandatory test is skipped, blocked or unavailable.


---

# 24. Mandatory independent vectors

Run and match every row in:

```text
validation_binomial_interval_test_vectors.csv
validation_zero_error_upper_bound_vectors.csv
validation_sequential_stopping_vectors.csv
validation_status_stop_reason_vectors.csv
validation_curve_comparison_vectors.csv
validation_curve_verdict_vectors.csv
validation_operating_point_join_vectors.csv
validation_multiseed_drop_vectors.csv
validation_multiseed_aggregation_vectors.csv
validation_provenance_dag_vectors.csv
validation_oracle_registry_vectors.csv
validation_schema_mutation_vectors.csv
validation_time_window_vectors.csv
validation_parallel_merge_vectors.csv
validation_parallel_merge_expected.csv
validation_archive_acceptance_vectors.csv
validation_run_class_isolation_vectors.csv
validation_artifact_requirement_vectors.csv
validation_calibration_catalog_vectors.csv
validation_operating_point_key_vectors.csv
validation_reference_dataset_vectors.csv
validation_measured_sinr_vectors.csv
validation_seed_partition_vectors.csv
validation_publication_gate_vectors.csv
validation_negative_test_vectors.csv
validation_capability_profile_matrix.csv
```

Do not generate expected values by calling the DUT.

The vector verifier must pass before production MATLAB validation begins.

---

# 25. Mandatory MATLAB tests

Implement every test in:

```text
validation_matlab_test_plan.csv
```

At minimum, tests must cover:

```text
canonical schemas and enums
legacy token migration
Wilson and Clopper-Pearson intervals at 90, 95 and 99 percent
zero-error upper bounds
sequential stopping and empirical coverage
high-SNR zero-error plateaus
independent drop aggregation
duplicate seed and retry detection
deterministic merge order
run-class isolation
observed evidence and provenance circularity
measured SINR requirements
oracle independence
reference dataset independence
complete point joins
non-inferiority and equivalence
multiplicity adjustment
calibration holdout
time-window boundaries
headless/browser/direct artifact parity
fresh canonical scenarios
clean archive acceptance
pinned MATLAB execution evidence
Python collection without MATLAB
all-source YAML validation
publication gate end to end
```

---

# 26. Impact analysis

Run all:

```text
64 impact families
768 experiments
384 matched pairs
96 acceptance rules
```

Every baseline/treatment pair must preserve:

```text
seed
payload
point key
channel/noise realization where applicable
drop identity
trial range
source tree
scenario
toolchain
```

Only the declared validation factor changes.

Use:

```text
Wilson or exact intervals for ordinary rates
one-sided exact bounds for zero events
McNemar tests for paired binary outcomes
paired bootstrap intervals for continuous effects
Holm correction for related hypotheses
predeclared practical-effect margins
```

A result can be:

```text
PASS
FAIL
INCOMPLETE
INCONCLUSIVE
```

Do not convert insufficient evidence into PASS.

---

# 27. Required production artifacts

The base phase requires:

```text
32 CSV files
22 PNG files
```

The impact phase requires:

```text
16 CSV files
30 PNG files
```

Combined:

```text
48 CSV files
52 PNG files
100 artifacts
```

The exact contracts are:

```text
desired_validation_csv_contract.csv
desired_validation_image_contract.csv
desired_validation_impact_csv_contract.csv
desired_validation_impact_image_contract.csv
```

Every PNG must be generated from its declared source CSV.

Every semantic-audit row must record:

```text
source CSV
source CSV SHA-256
PNG SHA-256
actual width and height
axes count
series count
finite plotted-point count
actual title
actual x label
actual y label
status
```

Do not report an image as valid merely because a nonempty PNG exists.

---

# 28. Required commands

Run from repository root.

```bash
python tests/vectors/validation/verify_validation_vector_pack.py tests/vectors/validation
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Validation*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Campaign*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Publication*'); assertSuccess(r);"
```

```bash
matlab -batch "addpath(pwd); s=sixgr.validation.runValidationPhaseValidation( ...
    'VectorRoot',fullfile(pwd,'tests','vectors','validation'), ...
    'OutputDir',fullfile(pwd,'artifacts','validation_phase'), ...
    'ConfidenceLevels',[0.90 0.95 0.99], ...
    'SeedList',[11 23 47 89], ...
    'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/validation/verify_validation_artifacts.py artifacts/validation_phase
```

```bash
matlab -batch "addpath(pwd); s=sixgr.validation.runValidationImpactAnalysis( ...
    'ExperimentMatrix',fullfile(pwd,'tests','vectors','validation','validation_impact_experiment_matrix.csv'), ...
    'OutputDir',fullfile(pwd,'artifacts','validation_impact'), ...
    'SeedList',[11 23 47 89 131 197], ...
    'ConfidenceLevel',0.95, ...
    'Strict',true); assert(s.Passed);"
```

```bash
python tests/vectors/validation/verify_validation_impact_artifacts.py artifacts/validation_impact
```

```bash
pytest -q
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true); assertSuccess(r);"
```

---

# 29. Completion restrictions

Do not report `COMPLETE` while any of the following remains:

```text
max_tb_per_point_reached and max_trials_reached coexist as live semantics
hard-coded 95 percent confidence
hard-coded 1.95996398454005 in campaign/gate code
DUT output copied to a reference CSV
reference gate checks only table presence
incomplete mandatory point accepted
zero-error point accepted without one-sided bound
ordinary fixed-sample intervals repeatedly inspected without sequential design
missing columns or NaN thresholds skip checks
local gate validity defaults true
measured SINR optional for a required run class
configured/reconstructed SINR presented as measured
configured geometry presented as runtime observation
circular expected/applied comparison
same-Toolbox test presented as independent
partial point key or nearest-point matching
missing/extra/duplicate points ignored
non-inferiority claimed without confidence bound
equivalence inferred from non-significance
independent drop minimum not enforced
duplicate seeds counted as independent
retry counted twice
same task ID with conflicting hashes accepted
parallel merge depends on execution order
warm-up/acquisition/steady/tail semantics undefined
AWGN artifact satisfies geometry/system gate
headless/direct launch bypasses artifact checks
fixture/static anchor satisfies runtime gate
stale archive artifact reused
source/scenario/toolchain hashes absent
MATLAB unavailable but gate passed
required test skipped/blocked but gate passed
Python import requires MATLAB
any source YAML fails parsing/schema checks
any required CSV or PNG is absent
either artifact verifier returns nonzero
complete repository regression fails
```

---

# 30. Definition of done

The phase is complete only when:

```text
all 28 findings are closed
all canonical status/reason producers and consumers are migrated
all schemas fail closed
90/95/99 percent interval vectors pass
sequential coverage tests pass
zero-error censor policy passes
all independent-drop policies pass
all reference datasets are independent and hash verified
all mandatory oracle rows use qualifying oracle types
all point joins are one-to-one on complete keys
curve comparison and multiplicity rules pass
all mandatory runtime fields have qualifying provenance
measured SINR is receiver-derived and complete
serial and shuffled parallel results are identical
all canonical scenarios execute freshly
the clean built archive passes
all required MATLAB tests execute and pass
pytest collects and passes without requiring MATLAB at import time
all source YAML files parse and validate
all 768 impact experiments execute
all 96 impact rules have valid evidence
all 48 CSVs pass
all 52 PNGs pass
both artifact verifiers return exit code 0
the complete repository MATLAB regression passes
```

---

# 31. Required Codex final response

At the end of implementation, report:

1. findings closed and still open;
2. files added, modified and deleted;
3. canonical schemas and enum versions;
4. statistical design and confidence levels;
5. independent oracle and reference entries;
6. exact commands executed;
7. MATLAB and Toolbox versions;
8. MATLAB/Python test counts: executed, passed, failed, skipped-required and blocked-required;
9. canonical scenario run IDs and hashes;
10. point counts by COMPLETE, CENSORED_COMPLETE and INCOMPLETE;
11. missing/extra/duplicate join counts;
12. provenance circularity count;
13. measured-SINR missing/invalid count;
14. independent drop and seed counts;
15. duplicate task and conflict counts;
16. all CSV row counts and hashes;
17. all PNG dimensions and hashes;
18. verifier exit codes;
19. complete repository regression result;
20. final status: `COMPLETE`, `FAIL` or `BLOCKED`.

A plan-only response, unexecuted source changes, copied expected outputs, or missing runtime evidence does not satisfy this prompt.
