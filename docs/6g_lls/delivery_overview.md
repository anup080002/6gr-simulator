# 6G PHY LLS Delivery Overview

This document is the front-door deliverable for the config-driven 6G PHY LLS framework. It is organized in the exact structure required for review and sign-off.

## 1. Architecture overview

The complete architecture is specified in [architecture.md](architecture.md). The key front-door pieces are:

- config-only entry points:
  - `run_6g_phy_lls_single(configPath, outputDir, runTag)`
  - `run_6g_phy_lls_matrix(configPath, outputDir, runTag)`
- one resolved `ScenarioConfig` object built by:
  - `+sixgr/+lls6g/+config/loadScenarioConfig.m`
  - `+sixgr/+lls6g/+config/validateScenarioConfig.m`
- YAML catalogs as the canonical policy source:
  - `simulator/configs/schema/*.yaml`
  - `simulator/configs/defaults/*.yaml`
  - `simulator/configs/scenarios/*.yaml`
- runtime translation and execution:
  - `+sixgr/+lls6g/buildInternalConfig.m`
  - `+sixgr/+lls6g/+runners/runSingle.m`
  - `+sixgr/+lls6g/+runners/runMatrix.m`
  - `+sixgr/+truth/runWaveformLinkBundle.m`
- structured result writing:
  - `+sixgr/+report/resultLayout.m`
  - `+sixgr/+truth/exportLLSReportingBundle.m`

The canonical data flow is:

1. raw scenario YAML/JSON
2. inheritance resolution
3. resolved `ScenarioConfig`
4. schema and compatibility validation
5. internal simulator config build
6. waveform/control/RS execution
7. KPI aggregation and artifact writing

## 2. Complete config schema

The complete human-readable schema is in [config_schema_reference.md](config_schema_reference.md). The canonical machine-readable schema is:

- `simulator/configs/schema/scenario_parameter_catalog.yaml`
- `simulator/configs/schema/scenario_parameter_catalog_extension_01.yaml`
- `simulator/configs/schema/scenario_parameter_catalog_extension_02.yaml`
- `simulator/configs/schema/scenario_parameter_catalog_extension_03.yaml`
- `simulator/configs/schema/scenario_parameter_catalog_extension_04.yaml`
- `simulator/configs/schema/scenario_parameter_catalog_extension_05.yaml`
- `simulator/configs/schema/matrix_parameter_catalog.yaml`

The required top-level sections are represented there, including:

- `meta`
- `run_control`
- `config_inheritance`
- `output_control`
- `global_radio_scope`
- `frame_timing`
- `bandwidth_operation`
- `deployment_topology`
- `mobility`
- `antenna_and_array`
- `power_and_rf_frontend`
- `waveform`
- `resource_grid`
- `channel_model`
- `interference`
- `signals_and_channels_common`
- `reference_signals`
- `pdcch`
- `pdsch`
- `pusch`
- `pucch`
- `prach`
- `mimo_and_beam_management`
- `csi_acquisition_and_reporting`
- `channel_coding`
- `modulation_and_mapping`
- `link_adaptation`
- `harq`
- `synchronization_and_tracking`
- `receiver_algorithms`
- `impairments`
- `ai_ml`
- `energy_and_complexity`
- `kpi_spec`
- `sweeps_and_matrix`
- `sanity_checks`
- `processing_chains`

For each field family, the schema defines:

- allowed values
- units
- defaults
- numeric ranges
- dependency rules
- baseline vs candidate tags

## 3. Per-block Tx/Rx chain specification

The exact per-block processing-chain definitions are in:

- [block_diagrams_and_parameters.md](block_diagrams_and_parameters.md)
- [processing_chains.md](processing_chains.md)

The framework explicitly documents and configures:

- DL common-signal and initial-access Tx/Rx
- PRACH Tx/Rx
- PDCCH Tx/Rx
- PDSCH Tx/Rx
- PUSCH Tx/Rx
- PUCCH Tx/Rx
- SRS / CSI-RS / TRS / tracking-RS chains
- CSI acquisition and reporting
- HARQ
- AI/ML hooks
- energy and complexity instrumentation

The machine-readable ordered block lists live in:

- `simulator/configs/defaults/processing_chains.yaml`

## 4. Scenario family library

The scenario-family layer is documented in [scenario_family_library.md](scenario_family_library.md), with machine-readable definitions in:

- `simulator/configs/scenario_families/required_scenario_families.yaml`

This library covers the required families, including:

- NR-like benchmark baseline
- 700 MHz FDD coverage
- 2 GHz FDD baseline
- 4 GHz TDD baseline
- 7 GHz wideband / high-capacity
- 30 GHz high-band beam-centric
- tracking RS / synchronization stress
- PDCCH reliability / blind-decoding / blocking
- UL waveform CP-OFDM vs DFT-s-OFDM
- DL-based / UL-based / joint DL-UL CSI
- PRACH / initial access / beam management
- HARQ latency-reliability trade-off
- high-order modulation and coding chain
- probabilistic shaping / distribution matching
- joint coding + modulation candidates
- AI demodulation
- AI CSI compression / reporting
- energy-efficiency / common-signal clustering
- bandwidth adaptation / BWP-like studies
- mTRP / SFN / coordinated transmission
- MRSS coexistence stress
- full-duplex self-interference candidate studies

Runnable scenario packs live in:

- `simulator/configs/scenarios/*.yaml`

## 5. Validation rules

The full rule set is in [validation_rules.md](validation_rules.md), and the enforcement point is:

- `+sixgr/+lls6g/+config/validateScenarioConfig.m`

Current explicit validation includes:

- invalid-combination rejection
- candidate-only feature gating
- precise dependency errors
- reproducibility completeness checks
- AI baseline-comparator requirements
- bandwidth-switching and joint-CSI dependency checks
- high-order modulation and full-duplex gating
- no hidden-default behavior in strict config resolution

## 6. Expected-results specification

The expected-results contract is in [result_specification.md](result_specification.md), especially the section:

- `Expected Results and What a Correct 6G PHY LLS Should Be Able to Show`

That section explicitly covers:

- baseline trend directions
- low-band vs mid-band vs around-7 GHz vs 30 GHz differences
- waveform / CSI / coding / modulation / AI / energy trade-offs
- expected KPI shifts with bandwidth, SCS, delay spread, Doppler, speed, beams, rank, TRPs, CFO/TO/drift, impairments, reciprocity mismatch, and feedback application delay
- which outputs are mandatory for correctness vs only useful for debugging

## 7. Artifact/output specification

The full LLS artifact contract is also in [result_specification.md](result_specification.md). The result-output catalog is machine-readable in:

- `simulator/configs/defaults/lls_result_output_catalog.yaml`

The canonical LLS result tree is:

```text
results/lls/<scenario_id>/<run_tag_or_current>/
  meta/
  reports/csv/
  reports/mat/
  reports/image/
  logs/
  air_interface/csv/
  air_interface/mat/
  air_interface/image/
  control/csv/
  control/image/
  beamforming/csv/
  beamforming/image/
```

The report bundle is written by:

- `+sixgr/+truth/exportLLSReportingBundle.m`

## 8. Example resolved YAML configs

Representative resolved configs are saved with each run under:

- `meta/resolved_config.yaml`
- `meta/resolved_config.json`

Two representative source scenarios are:

- baseline DL:
  - `simulator/configs/scenarios/dl_4ghz_baseline.yaml`
- multi-user 4T4R validation:
  - `simulator/configs/scenarios/lls_mimo4x4_multiuser_beamformed_awgn_validation.yaml`

Illustrative resolved baseline shape:

```yaml
meta:
  scenario_id: dl_4ghz_baseline
  study_status: baseline_benchmark
run_control:
  seed: 42
  deterministic_mode: true
global_radio_scope:
  carrier_frequency_hz: 4.0e9
  channel_bandwidth_hz: 2.0e7
  scs_hz: 30000
waveform:
  dl_waveform: cp_ofdm
  ul_waveform: cp_ofdm
channel_model:
  model_family: TDL
  scenario_label: TDL-C
reference_signals:
  nzp_csi_rs:
    enabled: true
  pdsch_dmrs:
    enabled: true
pdsch:
  enabled: true
  modulation: 64QAM
  mimo_mode: su_mimo
  rank: 2
pdcch:
  enabled: true
  modulation: QPSK
```

Illustrative resolved multi-user beamformed validation shape:

```yaml
meta:
  scenario_id: lls_mimo4x4_multiuser_beamformed_awgn_validation
  study_status: baseline_benchmark
deployment_topology:
  scenario_type: single-link
  num_ues: 2
antenna_and_array:
  bs_num_antenna_elements: 4
  ue_num_antenna_elements: 4
mimo_and_beam_management:
  su_mu_mode: mu_mimo
  rank_set: [2]
  beam_sweeping: enabled
channel_model:
  model_family: AWGN
pdsch:
  layer_count: 2
  precoder_family: type1_su_mimo
reference_signals:
  pdsch_dmrs:
    enabled: true
  ptrs:
    enabled: true
```

## 9. Example sweep/matrix configs

The sweep framework is described in [sweep_framework.md](sweep_framework.md). Concrete shipped examples include:

- `simulator/configs/scenarios/pdcch_blind_decode_sweep.yaml`
- `simulator/configs/scenarios/rank_adaptation_sweep.yaml`
- `simulator/configs/scenarios/harq_process_sweep.yaml`
- `simulator/configs/scenarios/bandwidth_operation_profiles.yaml`
- `simulator/configs/scenarios/matrix_regression.yaml`

Example matrix config:

```yaml
meta:
  matrix_id: regression_suite_v1
execution:
  stop_on_failure: false
  max_parallel_jobs: 4
  repeat_count: 1
scenarios:
  - simulator/configs/scenarios/dl_700mhz_coverage.yaml
  - simulator/configs/scenarios/dl_4ghz_baseline.yaml
  - simulator/configs/scenarios/dl_7ghz_mimo4x4.yaml
  - simulator/configs/scenarios/dl_30ghz_beam_tracking.yaml
  - simulator/configs/scenarios/ul_4ghz_cpofdm.yaml
  - simulator/configs/scenarios/ul_4ghz_dfts_pi2bpsk.yaml
```

Example generic sweep shape:

```yaml
scenario:
  runner_profile: generic_sweep
  target_cases: [bundle]
  sweep:
    base_profile: waveform_bundle
    output_name: delay_spread_sweep
    overrides:
      - label: ds_30ns
        config:
          channel_model:
            delay_spread_ns: 30
      - label: ds_300ns
        config:
          channel_model:
            delay_spread_ns: 300
```

## 10. Implementation roadmap

The recommended implementation order is:

1. keep YAML schema/catalog coverage complete before adding new runtime behavior
2. keep `buildInternalConfig.m` aligned with every newly exposed config surface
3. keep `validateScenarioConfig.m` as the single compatibility gate
4. expand runtime support block-by-block:
   - RS and tracking
   - CSI reporting and payload packing
   - link adaptation
   - beamforming and multi-user MIMO
   - HARQ and control studies
   - AI/ML baselines and candidates
5. keep result export honest by marking unsupported metrics as `not_available`
6. preserve strict no-proxy truth behavior in all primary outputs
7. add scenario packs and family entries only after runtime support exists

Near-term roadmap focus should remain:

- widening bit-exact or near-bit-exact runtime coverage where still simulator-level
- strengthening multi-user fading validation for high-rank LLS studies
- reducing path-reset noise during stable `current` folder refreshes

## 11. Test plan

The required regression surface for this framework includes:

- schema/catalog validation:
  - `test6GScenarioConfigValidation`
  - `test6GParameterCatalog`
  - `test6GValidationRules`
  - `test6GTopLevelSchemaSections`
- deliverables/docs coverage:
  - `test6GDeliverablesPack`
  - `test6GRequiredScenarioFamilies`
  - `test6GProcessingChainsSchema`
  - `test6GReferenceSignalChainCoverage`
- runtime PHY/LLS correctness:
  - `testLLS_DL`
  - `testLLS_UL`
  - `testLLS_ReferencePoints`
  - `testCSIRuntimeExecution`
  - `testCSIPayloadPackingRuntime`
  - `testPMIPrecodingRuntime`
  - `testTRSReferenceSignalExecution`
  - `testLLSReportBundle`
- full suite:
  - `testAll`

Minimum sign-off commands:

```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); test6GDeliverablesPack;"
matlab -batch "setup6GRSimToolkit('Verbose',false); testAll;"
```

## 12. Success condition and sign-off criteria

The design is successful only if all of the following are true in practice, not just in documentation:

### 12.1 A new band / waveform / CSI / HARQ / AI / energy scenario can be created without editing code

Required evidence:

- the scenario is expressible by adding or composing YAML only under:
  - `simulator/configs/defaults/`
  - `simulator/configs/scenarios/`
  - `simulator/configs/scenario_families/`
  - `simulator/configs/schema/` only when the new feature surface itself is being introduced
- no MATLAB source changes are required for a pure scenario instantiation once the capability exists
- the front-door invocation remains:
  - config path
  - output directory
  - run tag
  - optional log level
- the run saves:
  - raw config inputs
  - resolved config
  - validation context
  - reproducibility metadata
  - scenario summary

Acceptance proof:

- create at least one new composed scenario pack by inheritance only
- execute it through `run_6g_phy_lls_single`
- verify that `meta/resolved_config.yaml` and `meta/scenario_manifest.json` fully reflect the new scenario without code changes

### 12.2 Every PHY block is visible and configurable

Required evidence:

- every major PHY block has a named configuration surface in the schema and resolved config:
  - waveform
  - modulation and mapping
  - coding
  - layer mapping
  - precoding
  - beamforming
  - DMRS / PTRS / CSI-RS / SRS / TRS / tracking-RS
  - PDCCH / PDSCH / PUSCH / PUCCH / PBCH / PRACH
  - CSI acquisition and reporting
  - synchronization and tracking
  - HARQ
  - receiver algorithms
  - impairments
  - AI/ML
  - energy and complexity instrumentation
- every block is listed in:
  - `processing_chains.yaml`
  - the top-level schema catalog
  - the human-readable processing-chain docs
- no hidden runtime defaults materially change behavior outside the resolved config

Acceptance proof:

- dump a resolved config for representative DL, UL, control, initial-access, CSI, AI, and energy scenarios
- confirm that the enabled block parameters are present in `resolved_config.yaml`
- confirm that the corresponding block outputs appear in the artifact inventory or are explicitly marked `not_available`

### 12.3 Every important result is exported in machine-readable form

Required evidence:

- every enabled major study area writes machine-readable artifacts:
  - JSON metadata
  - CSV KPI tables
  - MAT bundles where MATLAB replay matters
- the LLS result-output catalog covers:
  - run metadata
  - basic PHY performance
  - coding/decoder metrics
  - modulation/shaping metrics
  - CE/tracking metrics
  - control metrics
  - PDSCH metrics
  - PUSCH/PUCCH metrics
  - CSI metrics
  - beam-management metrics
  - initial-access metrics
  - HARQ metrics
  - energy metrics
  - complexity metrics
  - AI/ML metrics
  - debug/trace references
  - aggregated summaries
- if a metric is not implemented for a given run, it is exported as `not_available` in coverage or summary artifacts rather than being silently omitted or faked

Acceptance proof:

- inspect:
  - `reports/csv/lls_output_spec_coverage.csv`
  - `reports/csv/lls_output_metric_rows.csv`
  - `reports/csv/artifact_inventory.csv`
  - `meta/runtime_summary.json`
- verify that every enabled subsystem has at least one real machine-readable artifact path

### 12.4 Baseline and candidate features are cleanly separated

Required evidence:

- every scenario and feature is tagged as exactly one of:
  - `baseline_benchmark`
  - `agreed_starting_point`
  - `study_item_candidate`
  - `optional_research_experiment`
- candidate-only features require explicit gating in validation
- reports and manifests preserve the benchmark/candidate classification
- no candidate result is presented as baseline behavior in summaries, plots, or family manifests

Acceptance proof:

- inspect scenario YAML, resolved config, manifest, and report for:
  - research/study classification
  - baseline comparator links where required
  - candidate-only validation behavior
- confirm that paired baseline scenarios exist for AI, high-order modulation, shaping, advanced CSI, and other candidate studies

### 12.5 A researcher can reproduce a paper-ready 6G PHY LLS campaign from config and artifacts alone

Required evidence:

- a single scenario or matrix run stores enough information to recreate the campaign:
  - raw inputs
  - resolved config
  - validation messages
  - simulator version
  - git hash
  - seeds
  - environment summary
  - runtime summary
  - KPI tables
  - plots
  - markdown summaries
- the result tree is stable, structured, and machine-readable
- the generated artifacts are sufficient to rebuild publication figures without manual notebook-only reconstruction

Acceptance proof:

- rerun a shipped matrix such as `simulator/configs/scenarios/matrix_regression.yaml`
- regenerate comparison curves and summary tables using only saved artifacts
- confirm that publication-facing outputs can be built from:
  - resolved configs
  - KPI CSVs
  - report plots
  - manifest metadata

### 12.6 Final engineering sign-off checklist

Do not call the framework complete unless all of the following are true:

- no new scenario instantiation requires MATLAB code edits
- no major PHY block is hidden from resolved config
- no enabled block is missing from the processing-chain or output contract
- no candidate-only feature can run as an unlabeled baseline
- no primary KPI/export path depends on proxy or synthetic substitution
- no result bundle lacks the minimum reproducibility metadata
- no paper-facing comparison depends on undocumented post-processing logic

The final sign-off artifacts should include:

- `docs/6g_lls/delivery_overview.md`
- `docs/6g_lls/result_specification.md`
- `docs/6g_lls/scenario_family_library.md`
- `docs/6g_lls/validation_rules.md`
- `reports/csv/lls_output_spec_coverage.csv`
- `reports/csv/artifact_inventory.csv`
- `meta/resolved_config.yaml`
- `meta/scenario_manifest.json`
