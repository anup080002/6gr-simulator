# Browser Config Binding Fix Report

## Scope

This patch series tightened the browser/YAML/JSON configuration surface so browser-visible parameters are no longer treated as implicitly active just because they exist in YAML or resolve into MATLAB config. The new contract distinguishes:

- config resolution in MATLAB
- runtime application by a concrete consumer
- runtime measurement published by a concrete artifact
- browser display state

It does not fabricate runtime evidence for uninstrumented parameters.

## Files Changed

Key files for this browser-config binding pass:

- `+sixgr/+config/buildParameterBindingMatrix.m`
- `+sixgr/+config/filterParametersForFeature.m`
- `+sixgr/+config/publishConfigApplicationEvidence.m`
- `+sixgr/+config/exportConfigApplicationEvidence.m`
- `+sixgr/+truth/exportLLSConfigOwnershipArtifacts.m`
- `+sixgr/+lls6g/+runners/runSingle.m`
- `+sixgr/+truth/recoverLLSRunArtifacts.m`
- `+sixgr/+lls6g/buildInternalConfig.m`
- `+sixgr/+lls6g/+config/validateScenarioConfig.m`
- `+sixgr/+lls6g/+config/normalizeScenarioAliases.m`
- `+sixgr/+rach/PRACHConfig.m`
- `+sixgr/+rach/runPRACHLLS.m`
- `+sixgr/+link/runPRACHDetection.m`
- `apps/lls_web_dashboard.py`
- `simulator/configs/schema/scenario_parameter_matrix_catalog.yaml`
- `simulator/configs/schema/ui_parameter_taxonomy.yaml`
- `tests/testFeatureParameterFiltering.m`
- `tests/testLLSConfigOwnershipAuditExports.m`
- `tests/testLLSConfigRoundtripRuntimeArtifacts.m`
- `tests/testPRACHRunnerIntegration.m`
- `tests/test_lls_browser_parameter_surface.py`

## Missing Catalog / Frontend Files Found

- `simulator/configs/schema/scenario_parameter_matrix_catalog.yaml` was missing. It is now present and used as the parameter contract source.
- `simulator/configs/schema/ui_parameter_taxonomy.yaml` was missing. It is now present and used to assign feature family and UI section.
- Browser/frontend code does exist in this repo, but it is server-side/dashboard oriented rather than a standalone SPA bundle.
  - `apps/lls_web_dashboard.py`
  - `apps/lls_contract_materializer.py`
- Existing `core_parameter_catalog.yaml` and `scenario_parameter_catalog.yaml` were present, but they were not enough to prove browser-to-runtime binding on their own.

## New Parameter Contract Format

The new contract centers on one row per parameter in `parameter_binding_matrix.csv`.

Each row can carry:

- `ParameterId`
- `BrowserPath`
- `ScenarioPath`
- `InternalCfgPath`
- `FeatureFamily`
- `UILayer`
- `UISection`
- `BrowserVisible`
- `BrowserEditable`
- `SubmittedValue`
- `BaseYAMLValue`
- `ResolvedScenarioValue`
- `InternalCfgValue`
- `MATLABConsumerFunction`
- `RuntimeAppliedEvidenceArtifact`
- `RuntimeAppliedEvidenceField`
- `RuntimeAppliedEvidenceValue`
- `RuntimeMeasuredEvidenceArtifact`
- `RuntimeMeasuredEvidenceField`
- `RuntimeMeasuredEvidenceValue`
- `ConfigResolvedStatus`
- `RuntimeAppliedStatus`
- `RuntimeMeasuredStatus`
- `BrowserDisplayStatus`
- `FinalBindingStatus`

This now drives:

- `reports/csv/parameter_binding_matrix.csv`
- `reports/csv/browser_config_surface_matrix.csv`
- `reports/csv/runtime_config_application_evidence.csv`
- `reports/csv/feature_parameter_index.csv`
- `reports/csv/config_status_summary.csv`
- `reports/csv/ui_feature_filter_audit.csv`

## PRACH Before / After

Before:

- PRACH fields were browser/YAML visible, but the repo did not consistently prove that a changed PRACH parameter had reached a concrete runtime consumer.
- Browser/config exports could show PRACH parameters without a clean separation between resolved config and runtime-applied evidence.

After:

- PRACH parameters are cataloged and categorized under `Random_Access_PRACH`.
- PRACH runtime consumers publish application evidence through `publishConfigApplicationEvidence`.
- `random_access.configuration_index` and `random_access.detection_threshold` are proven through:
  - `reports/csv/runtime_config_application_evidence.csv`
  - `air_interface/csv/prach_trials.csv`
  - `reports/csv/parameter_binding_matrix.csv`
  - `reports/csv/browser_config_surface_matrix.csv`
- The PRACH feature filter keeps unrelated PDSCH/PUSCH/PUCCH fields out of the PRACH view except for shared dependencies.

## Examples Of Status Levels

Resolved-only:

- Example: `simulation.noise_operating_mode`
- Meaning: the value resolved in MATLAB config and is browser-visible, but there is no dedicated runtime consumer evidence row for it yet.

Runtime-applied:

- Example: `random_access.detection_threshold`
- Meaning: a concrete PRACH runtime consumer published an applied-value evidence row in `runtime_config_application_evidence.csv`.

Runtime-measured:

- Example: `users.beam_selection_strategy`
- Meaning: the resolved config is reflected by a real measured/raw artifact field, here `ConfiguredBeamSelectionStrategy` in `air_interface/csv/dl_pdsch_trials.csv`.

## Why The Old Homepage Said "Unavailable"

The old dashboard wording overloaded one generic unavailable message for several different cases:

- config not submitted
- config resolved in MATLAB but no runtime consumer instrumentation
- runtime consumer applied a value but no measured artifact was published
- feature disabled by config
- unsupported backend

That made resolved config look absent, and it made missing runtime evidence look like missing config.

## New Homepage Status Semantics

The dashboard now distinguishes:

Config state:

- `not_submitted`
- `submitted_in_browser_overlay`
- `inherited_from_base_yaml`
- `catalog_default_used`
- `resolved_in_matlab`

Application state:

- `applied_to_runtime_object`
- `consumer_not_instrumented`
- `consumer_missing`
- `not_applicable_for_selected_feature`
- `unsupported_backend`

Measurement state:

- `measured_runtime_evidence_published`
- `runtime_evidence_not_published`
- `evidence_artifact_missing`
- `evidence_field_missing`
- `evidence_not_applicable`
- `evidence_unavailable_because_feature_disabled`

The dashboard wording in `apps/lls_web_dashboard.py` now reflects those distinctions instead of a generic unavailable label.

## Important Runtime Fix

One real bug was uncovered while tightening the browser surface:

- The recovery path for `sixgr:link:PrimarySummarySkipped` could leave the browser/binding CSVs on an earlier intermediate snapshot.
- That made rows like `users.beam_selection_strategy` lose the final measured runtime value in the exported browser matrix even though the underlying raw trial artifact was correct.
- Fixed by refreshing config-ownership exports after final runtime/report exports on the normal path, and by forcing one final post-recovery export in `runSingle` using the original `ScenarioConfig` context.

This was required to make the roundtrip browser proof honest for recovered LLS runs.

## Tests Run

Passed:

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testFeatureParameterFiltering; testLLSConfigOwnershipAuditExports; testPRACHRunnerIntegration;"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLLSConfigRoundtripRuntimeArtifacts;"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testLLS_DL; testLLS_UL; testLLS_ReferencePoints;"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign;"`
- `python tests/test_lls_browser_parameter_surface.py`

Did not complete:

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"`
  - Timed out at the 4-hour wrapper limit.
  - I stopped the background MATLAB process after timeout.
  - I am not claiming a clean full `testAll` pass.

## Remaining Unresolved / Uninstrumented Parameters

The browser surface is more honest now, but not every browser-visible parameter is fully runtime-applied or runtime-measured yet.

Remaining common statuses:

- `consumer_not_instrumented`
- `consumer_missing`
- `runtime_evidence_not_published`
- `unsupported_backend`
- `resolved_in_matlab` without measured evidence

This is expected for parameters that are currently:

- shared config toggles without a dedicated runtime evidence publisher
- backend-specific fields that only apply on `mysql_web`
- output/report controls that are config-resolved but not waveform-measured
- feature families outside the PRACH-first proof slice

## Exact Blockers

- Browser contract materialization is still skipped on filesystem-only runs when the MySQL artifact store is inactive. That is honest behavior, not a hidden success path.
- Some browser-editable parameters still resolve only to MATLAB config because their runtime consumers are not yet instrumented.
- Some measured fields still depend on raw artifact availability and will remain `runtime_evidence_not_published` when the feature is disabled or not executed.
- A clean full `testAll` pass has not been proven in this cycle because the batch timed out after 4 hours.

## Bottom Line

This patch series did not try to make every browser-visible field look implemented. It made the browser/config surface stricter about what is merely resolved, what is actually applied, and what is proven by runtime evidence. PRACH now has a clean browser-to-runtime proof path, the browser status wording is no longer ambiguous, and the recovered LLS roundtrip path now republishes the final binding matrix instead of a stale intermediate snapshot.
