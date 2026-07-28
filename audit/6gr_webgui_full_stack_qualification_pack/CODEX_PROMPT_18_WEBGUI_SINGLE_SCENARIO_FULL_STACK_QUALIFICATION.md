# Codex implementation prompt — one WebGUI YAML, full-stack SINR + geometry qualification with actual runs

You are modifying the current production 6GR MATLAB simulator repository after the frame, waveform, PHY data/control, reference-signal, MIMO, channel/RF, MAC/HARQ, protocol, validation and WebGUI phases have already been implemented.

Do **not** return a review or a plan-only answer. Build the integration orchestrator, map the supplied YAML into the canonical schema, start the run from the canonical WebGUI, execute the real MATLAB subcases, inspect all generated values and artifacts, fix integration defects, and continue until the selected bounded qualification preset passes or a precise blocker remains.

## Critical design clarification

A single flat radio timeline cannot simultaneously be:

- a controlled AWGN SNR sweep;
- a LOS geometry run;
- an NLOS/O2I/blockage run;
- a multi-cell interference run;
- a handover run;
- and a no-signal negative test.

Therefore, implement **one WebGUI scenario suite** with:

```text
one scenario YAML
one immutable configuration revision
one WebGUI RunID
one consolidated output root
multiple child subcases
one final artifact manifest
one final component/value/acceptance result
```

This satisfies the user's requirement to run and inspect everything from the same WebGUI scenario without corrupting physical causality by mixing incompatible environment assumptions in one slot stream.

The comprehensive preset is a **bounded full-stack functional qualification**, not an exhaustive 3GPP parameter-combination or publication campaign. It must exercise every declared component at least once and verify every required value/artifact. The deep preset additionally executes the previously defined impact-analysis contracts.

## Supplied pack inputs

Read and use all files in this pack:

```text
lls_webgui_full_stack_sinr_geometry_qualification.yaml
full_stack_subcase_matrix.csv
full_stack_component_coverage_matrix.csv
full_stack_value_correctness_contract.csv
full_stack_negative_fault_injection_matrix.csv
full_stack_acceptance_rules.csv
full_stack_required_artifact_registry.csv
full_stack_webgui_page_contract.csv
full_stack_artifact_manifest_schema.json
verify_full_stack_qualification_artifacts.py
FULL_STACK_WEBGUI_RUN_GUIDE.md
```

Counts in this pack:

```text
Mandatory child subcases: 31
Component coverage rows: 163
Value-correctness checks: 107
Negative/fault cases: 77
Acceptance rules: 387
Comprehensive required artifacts: 746 (447 CSV, 299 PNG)
Deep required artifacts: 1248 (623 CSV, 625 PNG)
```

## Non-negotiable rules

1. Reuse the already implemented canonical component packages. Do not create a second waveform, receiver, channel, scheduler, protocol or artifact path.
2. The exact resolved YAML displayed in WebGUI must be the file executed by MATLAB. No hidden CLI scientific override is allowed.
3. No mock, placeholder, empty, copied or synthetic result artifact may satisfy a required runtime artifact.
4. Deterministic test/vector artifacts must be labelled `INDEPENDENT_ORACLE` or `TEST_OR_CONFIGURATION`; runtime measurements must be labelled `RUNTIME_MEASURED_OR_DERIVED`.
5. Configured SNR, geometry, channel, CFO, timing, CSI, ACK, grant or RRC truth cannot be relabelled as observed/decoded runtime state.
6. Dynamic connected PDSCH/PUSCH grants require valid decoded DCI. The receiver cannot be given the scheduler's original grant.
7. CSI, UCI, HARQ, beam, SRS, RRC and packet state must come from decoded/measured events.
8. Do not clamp, retry, default or downgrade unsupported strict input.
9. Every mandatory child subcase must execute. A failed subcase remains failed; do not silently skip it.
10. Every selected-preset artifact in the registry must be generated, hashed, schema-checked, semantically checked and published in WebGUI.
11. A missing measurement must appear as a failing row, not as a configured replacement or blank chart.
12. Same-implementation self-consistency is useful but cannot be the only oracle where the component contract requires an independent oracle.
13. Do not weaken previously passing component tests to make this suite pass.
14. Do not report `COMPLETE` if MATLAB, 5G Toolbox, frontend, Playwright or mandatory tests were unavailable or skipped.
15. Do not call this an unbounded full-3GPP or Release-20 conformance result.

# 1. Create one canonical integration orchestrator

Create or extend a package such as:

```text
+sixgr/+integration/+qualification/
    FullStackQualificationProfile.m
    FullStackQualificationRunner.m
    FullStackRunContext.m
    FullStackSubcase.m
    FullStackSubcaseRegistry.m
    CanonicalComponentRegistry.m
    ComponentExecutionAdapter.m
    ComponentEvidenceLedger.m
    CrossDomainCausalityLedger.m
    ValueCorrectnessEngine.m
    ArtifactRequirementRegistry.m
    ArtifactCompletenessEngine.m
    WebGUIPublicationLedger.m
    FullStackAcceptanceEvaluator.m
    FullStackArtifactExporter.m
```

The runner owns orchestration only. Scientific logic remains in the canonical component packages.

Each child subcase follows:

```text
PLAN
  validate profile/capability/configuration
  bind exact implementation IDs and source hashes

EXECUTE
  run the actual production component chain
  emit runtime events and raw data

EXPORT
  call the canonical domain exporter
  write all domain base artifacts required by the selected preset

VERIFY
  execute domain verifier and value-correctness checks
  append component and acceptance evidence
```

Every subcase row contains:

```text
RunID
SubcaseID
ConfigurationRevisionID
ResolvedYAMLSHA256
ImplementationRegistrySHA256
Seed/Substream
StartedUTC
CompletedUTC
Executed
Status
FailureCode
OutputManifestSHA256
```

# 2. Map the semantic YAML into the real canonical schema

Create the final source scenario at:

```text
simulator/configs/scenarios/lls_webgui_full_stack_sinr_geometry_qualification.yaml
```

Requirements:

- The supplied YAML is a semantic contract. Map it to existing canonical keys.
- Add a schema extension only when no canonical representation exists.
- Reject unknown or ignored keys.
- Show Source YAML, Effective YAML, Resolved YAML and Diff in WebGUI.
- Store and display source/effective/resolved/executed hashes.
- `ResolvedYAMLSHA256 == ExecutedYAMLSHA256` is mandatory.
- All subcase parameters and preset selection come from YAML, not hidden code constants.
- `comprehensive_smoke` is the default preset.
- `deep_acceptance` uses the same scenario and orchestrator but enables impact contracts and larger counts.

# 3. One common implementation across all environments

Record implementation ID, source path and source SHA-256 for at least:

```text
frame/grid/timing
resource transaction manager
waveform mapper/modulator/demodulator
PDCCH/PDSCH/PUSCH/PUCCH
SSB/PBCH/PRACH
DMRS/PTRS/CSI-RS/CSI-IM/SRS/TRS
channel and geometry
RF front end
synchronization and tracking
channel estimator/equalizer/demapper/decoder
MIMO/codebook/precoder/beam management
HARQ/MAC/scheduler
RLC/PDCP/SDAP/RRC/traffic
validation/statistics/oracle registry
artifact exporter
```

Fail when equivalent functionality is provided by hidden mode-specific implementations.

# 4. Execute all child subcases

Load `full_stack_subcase_matrix.csv` as the mandatory subcase registry. Implement every listed subcase, including:

```text
configuration/toolchain preflight
frame/grid/duplex
DL and UL no-noise waveform
DL and UL fixed-SINR sweeps
initial access and connected RRC
PDCCH/DCI matrix
PDSCH/DL-SCH matrix
PUSCH/UL-SCH/UCI matrix
PUCCH formats 0-4
reference signals and measurements
CSI/link adaptation/OLLA
MIMO/antenna/precoding
beam management/BFR
LOS channel
NLOS/O2I/blockage
mobility/Doppler continuity
multi-cell sample-domain interference
RF tracking and RF front end
all UL power-control channels
MAC/HARQ/scheduler
RLC/PDCP/SDAP/RRC
traffic/lineage
handover/RLF/re-establishment
negative/fault injection
validation/oracles/statistics
all-artifact audit
WebGUI publication
complete repository regression
```

## 4.1 Fixed-SINR sweep

Use exactly:

```text
SNR = [-8, -4, 0, 4, 10] dB
DL and UL
MCS 10 main sweep
rank 1 main sweep
seeds from selected preset
```

Also run bounded one-shot modulation/rank/mapping probes required by the component matrix. Export configured input SNR and receiver-measured input/post-EQ SINR as separate values.

## 4.2 Initial access and connected control

Execute the actual chain:

```text
PSS/SSS
PBCH/MIB
Type-0 CSS
SI-RNTI DCI 1_0
PDSCH/SIB1
PRACH Msg1
RAR Msg2
Msg3/RRCSetupRequest
Msg4/RRCSetup
SRB1
RRCSetupComplete
RRC_CONNECTED
```

The connected data subcases must use decoded control and UCI.

## 4.3 LOS and NLOS environments

The LOS, NLOS/O2I/blockage, mobility and interference subcases are separate child environments within the same RunID.

For NLOS, require actual runtime evidence:

```text
Observed LOS state = NLOS
applied NLOS pathloss profile
applied CDL/selected NLOS channel profile
O2I material/indoor-distance state
blockage state transitions
receiver channel estimate
measured SINR/EVM/CRC
```

No configured NLOS label alone is sufficient.

## 4.4 RF

Inject and estimate/correct actual CFO, timing and SCO. Run bounded phase-noise, IQ, PA, DPD, DAC/AGC/ADC and blocker probes. RF research results are clearly separated from ideal PHY strict results.

## 4.5 L2/L3 and traffic

Exercise bounded exact RLC UM/AM, PDCP COUNT/security/reordering, SDAP mapping, RRC reconfiguration, handover and deterministic packet delivery. Require exact first-delivery de-duplication and conservation.

# 5. Component coverage must be complete

Load `full_stack_component_coverage_matrix.csv`.

Write:

```text
full_stack_component_coverage_results.csv
```

For every component:

```text
Mandatory
Executed
EvidencePresent
CorrectnessChecked
Status
FailureCode
EvidenceArtifactIDs
```

A component passes only when all four booleans are true and its correctness requirement passes.

The component matrix is the answer to “did every TX/RX, PHY, antenna, control, channel, RF, MAC, L2/L3 and traffic component run?”

# 6. Check every value and outcome

Load `full_stack_value_correctness_contract.csv` into `ValueCorrectnessEngine`.

Write:

```text
full_stack_value_correctness_results.csv
```

Each check must report:

```text
ObservedValue
ExpectedValue
Comparator
Tolerance
Units
Status
FailureCode
EvidenceArtifactID
```

Rules:

- deterministic values compare to independent vectors or analytical invariants;
- runtime values compare to physically valid tolerances and provenance;
- stochastic outcomes use the declared bounded smoke criteria or confidence policy;
- a missing/nonfinite field fails;
- no check initializes to PASS;
- no NaN threshold skips a comparison;
- no configured value can replace a required measurement.

# 7. Generate and audit every artifact

Load `full_stack_required_artifact_registry.csv`.

Selected preset requirements:

```text
comprehensive_smoke: 746 artifacts (447 CSV, 299 PNG)
deep_acceptance:     1248 artifacts (623 CSV, 625 PNG)
```

The comprehensive preset requires all base artifacts from every implemented technical domain and the integration layer. The deep preset additionally requires all impact-analysis artifacts.

For every CSV:

```text
exists
nonempty
required columns
minimum rows
primary-key uniqueness
finite required numeric fields
valid status values
SHA-256
actual evidence class
```

For every PNG:

```text
exists
valid decode
minimum dimensions
nonblank pixels
source CSV exists
source CSV SHA-256 matches
semantic title/x/y/axes/series/finite-point checks
PNG SHA-256
```

Write:

```text
full_stack_artifact_manifest.csv
full_stack_artifact_audit.csv
all_csv_artifact_audit.csv
all_image_artifact_audit.csv
all_artifact_completeness.csv
full_stack_image_semantic_audit.csv
```

No required artifact may be generated from an empty placeholder table or copied reference image.

# 8. Publish everything from WebGUI

The run must start from the canonical secured WebGUI. A direct MATLAB run may be used for debugging, but it cannot satisfy the WebGUI gate.

Implement the page contract in `full_stack_webgui_page_contract.csv`.

The global selected RunID must drive:

```text
Configure
Live
Overview
TX Chain
RX Chain
Control and Access
MIMO and Beam
Channel and RF
MAC and Protocol
Results
Validation
Artifact Explorer
```

For every required artifact:

```text
visible in the correct domain section
previewable when supported
downloadable by artifact ID
provenance/evidence badge visible
source CSV relationship visible for PNG
schema/hash/validity visible
failed/unavailable state visible
```

Write `full_stack_webgui_publication.csv`. The required unpublished artifact count must be zero.

Add Playwright E2E that:

1. logs in;
2. selects this scenario;
3. selects preset;
4. confirms source/effective/resolved YAML values and hash;
5. launches the run;
6. observes each mandatory subcase on Live;
7. waits for final completion;
8. opens every page in the page contract;
9. verifies component/value/acceptance failures are not hidden;
10. verifies every required artifact is present in Artifact Explorer;
11. downloads representative CSV/PNG from every domain and checks hashes;
12. captures WebGUI screenshots as run artifacts.

# 9. Negative and fault-injection matrix

Execute every row in `full_stack_negative_fault_injection_matrix.csv`.

Every case must satisfy:

```text
ExpectedRejected = true
ExpectedStateMutation = false
ExpectedWaveformOrPDUProduced = false
ActualError = ExpectedError
```

Do not convert a negative rejection into a warning or diagnostic pass.

# 10. Cross-domain causality

Write `full_stack_cross_domain_causality.csv` linking:

```text
measurement -> report -> decoded report -> scheduler decision
decoded DCI -> grant -> waveform -> decode -> UCI -> HARQ
traffic packet -> SDAP -> PDCP -> RLC -> MAC -> TB -> HARQ -> first delivery
geometry/mobility -> channel -> RF samples -> receiver measurement
beam report -> TCI activation -> applied precoder
handover measurement -> report -> reconfiguration -> target RA -> completion
```

Every edge must have valid identity and time ordering. Future state, scheduler truth, configured truth or geometry-oracle shortcuts fail.

# 11. Acceptance engine

Load `full_stack_acceptance_rules.csv` and write `full_stack_acceptance_results.csv`.

`FinalStatus = PASS` only when:

```text
all mandatory subcases pass
all mandatory components pass
all value-correctness checks pass
all negative cases reject correctly
all selected-preset artifacts pass
all WebGUI publication rows pass
all regression suites pass with zero mandatory fail/skip/block
```

# 12. Required tests

Add MATLAB tests for:

```text
scenario schema and exact YAML binding
subcase registry and execution order
canonical implementation reuse
component coverage completeness
value-correctness engine
artifact-registry completeness
CSV and PNG semantic verification
fixed-SINR DL/UL
initial access and RRC completion
PDCCH/PDSCH/PUSCH/PUCCH
reference signals/link adaptation
MIMO/antenna/beam
LOS/NLOS/O2I/blockage
mobility/interference
RF and power control
MAC/HARQ/scheduler
RLC/PDCP/SDAP/RRC/traffic
handover/RLF
negative matrix
WebGUI publication ledger
final acceptance
```

Add Python/frontend tests for:

```text
all source YAML parsing
scenario appears in WebGUI
resolved/executed hash binding
all artifact registry rows indexed
CSV schema/primary-key/minimum-row checks
PNG/source-hash/semantic checks
WebGUI role and ownership
Playwright complete workflow
```

# 13. Actual execution commands

Adapt paths to repository-native entry points without changing scientific intent.

```bash
python -m compileall apps backend frontend tests
pytest -q
```

```bash
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*FullStack*'); assertSuccess(r);"
matlab -batch "addpath(pwd); r=runtests('tests','IncludeSubfolders',true,'Name','*Integration*'); assertSuccess(r);"
```

Start the canonical WebGUI on `0.0.0.0`, then execute the Playwright launch of:

```text
lls_webgui_full_stack_sinr_geometry_qualification
preset = comprehensive_smoke
```

After completion:

```bash
python tests/vectors/full_stack_qualification/verify_full_stack_qualification_artifacts.py \
  <actual-run-output-directory> \
  tests/vectors/full_stack_qualification \
  --preset comprehensive_smoke
```

Then run the complete repository MATLAB regression.

For the optional exhaustive preset, launch the same scenario with:

```text
preset = deep_acceptance
```

and run the verifier with `--preset deep_acceptance`.

# 14. Failure investigation order

1. YAML/source/effective/resolved/executed mismatch.
2. Wrong subcase dispatch or hidden alternate implementation.
3. Frame/timing/resource transaction.
4. Waveform/power/noise reference.
5. Synchronization/estimation/equalization.
6. Control/grant/UCI ownership.
7. Data coding/mapping/HARQ.
8. Reference signals/CSI/SRS/OLLA.
9. MIMO/antenna/beam/covariance.
10. Geometry/channel/interference.
11. RF/power-control.
12. MAC/scheduler.
13. RLC/PDCP/SDAP/RRC/traffic.
14. Artifact export/hash/schema/semantic plot.
15. WebGUI indexing/publication.
16. Acceptance evaluator.

Never inject downstream truth to bypass an upstream failure.

# 15. Required Codex final response

Return:

1. files added/modified/deleted;
2. source/effective/resolved/executed YAML and hashes;
3. WebGUI URL, RunID, owner, preset and output directory;
4. exact commands and toolchain versions;
5. one row per mandatory child subcase;
6. component coverage totals and every failed component;
7. value-correctness totals and every failed check;
8. five-point DL/UL SNR tables;
9. initial-access/RRC states;
10. control/data/UCI/HARQ results;
11. reference-signal/link-adaptation results;
12. MIMO/antenna/beam results;
13. LOS/NLOS/O2I/blockage/mobility/interference results;
14. RF and power-control results;
15. MAC/L2/L3/traffic/handover results;
16. required artifact counts by domain;
17. missing/invalid/unpublished artifacts;
18. all test pass/fail/skip/block counts;
19. artifact-verifier exit code;
20. final `COMPLETE`, `FAIL` or `BLOCKED`.

Do not return `COMPLETE` unless the WebGUI-launched run passed every selected-preset requirement and the complete regression passed.
