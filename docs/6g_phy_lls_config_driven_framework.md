# 6G PHY LLS Config-Driven Framework

This repository now includes a dedicated config-driven 6G PHY link-level scenario framework.

For the full architecture/specification deliverables pack, see:

- `docs/6g_lls/README.md`
- `docs/6g_lls/architecture.md`
- `docs/6g_lls/config_schema_reference.md`
- `docs/6g_lls/block_diagrams_and_parameters.md`
- `docs/6g_lls/scenario_library.md`
- `docs/6g_lls/result_specification.md`
- `docs/6g_lls/validation_rules.md`
- `docs/6g_lls/sweep_framework.md`

## Non-negotiable architecture rules

1. All scenario parameters must live in configuration files.
No PHY parameter should be hard-coded in source logic, notebooks, helper scripts, tests, or front-door runner arguments. The command line should only pass:
- config file path
- output directory
- run tag
- optional log level

2. Every module must consume one validated resolved `ScenarioConfig`.
No module should read ad hoc environment variables to drive PHY behavior. No module should keep hidden defaults that materially affect simulation behavior.

3. Config inheritance must be layered.
The intended composition order is:
- global defaults
- release or profile defaults
- band pack
- waveform pack
- channel pack
- MIMO or beam pack
- reference-signal pack
- AI or ML pack
- impairment pack
- energy-efficiency pack
- scenario override
- sweep or matrix override

4. The exact resolved config must be saved with every run.
Required reproducibility artifacts are:
- raw input configs
- resolved config after inheritance
- schema validation report
- simulator version and git hash
- random seeds
- environment summary

5. Schema validation is mandatory.
Fail fast on invalid or contradictory configuration combinations. Validation errors should name the bad field, explain the reason, show the allowed range or values, and surface any violated dependency.

6. Every feature block must expose its parameters in config.
No hidden defaults are allowed for waveform, coding, modulation, scrambling, interleaving, layer mapping, precoding, beamforming, DMRS, CSI-RS, SRS, PTRS, TRS, tracking RS, PDCCH, PDSCH, PUSCH, PUCCH, PBCH, PRACH, CSI acquisition, HARQ, receiver type, impairments, AI or ML models, or energy and complexity instrumentation.

7. Both single-run and matrix-run execution are first-class.
Single-scenario execution and native parameter sweeps must both be available without custom scripts.

8. Outputs must be both machine-readable and human-readable.
At minimum the framework should emit:
- JSON for metadata
- CSV or Parquet for KPIs
- images for major curves
- Markdown, HTML, or PDF-ready summaries
- optional HDF5 or NPZ intermediate arrays and traces

9. Baseline and candidate features must be individually switchable.
A scenario must be able to enable or disable NR-like baseline blocks, candidate 6G blocks, AI or ML blocks, extra impairments, and debug traces independently.

10. All PHY blocks must support deterministic reproducibility.
Seedable random generators, deterministic evaluation mode, reproducible sweep ordering, and same-config reproducibility within numerical tolerance are part of the architecture contract.

## Entry points

- `run_6g_phy_lls_single(configPath, outputDir, runTag)`
- `run_6g_phy_lls_matrix(configPath, outputDir, runTag)`

Only these inputs are accepted at the front door:

- scenario or matrix config path
- output directory
- optional run tag
- optional log level

All PHY, channel, MIMO, AI/ML, KPI, logging, and output behavior comes from config files.
No scenario runner is allowed to inject hidden PHY defaults for SNR, MCS, PRACH, PUCCH, CSI hooks, or AI benchmark controls.

## Config layout

The shipped packs live under:

- `simulator/configs/defaults`
- `simulator/configs/releases`
- `simulator/configs/bands`
- `simulator/configs/waveforms`
- `simulator/configs/coding`
- `simulator/configs/channels`
- `simulator/configs/mimo`
- `simulator/configs/control`
- `simulator/configs/reference_signals`
- `simulator/configs/initial_access`
- `simulator/configs/harq`
- `simulator/configs/ai_ml`
- `simulator/configs/impairments`
- `simulator/configs/energy`
- `simulator/configs/models`
- `simulator/configs/scenarios`

Mandatory study-pack scenarios are also shipped under `simulator/configs/scenarios`, including:

- `mandatory_general_scope_packs.yaml`
- `mandatory_tracking_packs.yaml`
- `mandatory_ul_waveform_packs.yaml`
- `mandatory_csi_acquisition_packs.yaml`
- `mandatory_pdcch_packs.yaml`
- `mandatory_initial_access_packs.yaml`
- `mandatory_harq_packs.yaml`
- `mandatory_coding_modulation_packs.yaml`
- `mandatory_ai_ml_packs.yaml`
- `mandatory_energy_efficiency_packs.yaml`

Scenario files compose layers using:

```yaml
inherits:
  - ../defaults/global.yaml
  - ../bands/band_4ghz.yaml
  - ../channels/tdl_c.yaml
```

Later configs override earlier ones.

The intended inheritance order is:

1. global defaults
2. release or profile defaults
3. band pack
4. waveform pack
5. channel pack
6. MIMO or beam pack
7. reference-signal pack
8. AI or ML pack
9. impairment pack
10. energy-efficiency pack
11. scenario override
12. sweep or matrix override

The shipped global and band packs now carry the shared defaults the prompt requires, including:

- band bandwidth and numerology options
- max MIMO size
- mobility defaults
- channel-model defaults
- reference-signal defaults
- power-model defaults
- energy-model defaults
- RF-impairment defaults
- CQI / PMI / RI reporting hooks
- mTRP / multi-panel readiness hooks
- AI benchmark observation count
- PRACH minimum detection trials
- control payload and blind-decode capacity

## How to add a new scenario

1. Create a new file under `simulator/configs/scenarios`.
2. Inherit from the existing packs you need.
3. Override only scenario-specific values in config.
4. Do not add new source-code constants for that scenario.
5. Run the scenario through `run_6g_phy_lls_single`.

Important: if a value affects PHY behavior, benchmark behavior, or artifact generation, put it in YAML. Do not add a silent `structGet(..., default)` in runner code.

Example skeleton:

```yaml
{
  "inherits": [
    "../defaults/global.yaml",
    "../bands/band_4ghz.yaml",
    "../waveforms/cp_ofdm.yaml",
    "../channels/tdl_c.yaml",
    "../mimo/mimo_2x2.yaml",
    "../control/pdcch_baseline.yaml",
    "../control/harq_baseline.yaml",
    "../control/ra_baseline.yaml",
    "../ai_ml/disabled.yaml"
  ],
  "meta": {
    "scenario_id": "my_new_case",
    "description": "My config-only scenario."
  },
  "scenario": {
    "runner_profile": "waveform_bundle",
    "target_cases": ["bundle"]
  }
}
```

## Output artifacts

Each single scenario run saves:

- raw input config copies
- resolved config snapshot as JSON and YAML
- schema validation report
- environment summary
- random seed summary
- source-chain CSV
- scenario manifest with git hash and config hash
- reproducibility fields including random seed, deterministic mode, runner profile, run scope, and run completion
- structured result folders under `/results/lls/<scenario_id>/<run_tag_or_current>`
- CSV tables annotated with `ScenarioID`, `ConfigHash`, and `RunnerProfile`
- optional Parquet KPI mirrors where supported
- AI benchmark metadata with model ID, version, quantization mode, runtime budget, FLOPs budget, parameter count, confidence-logging flag, and fallback flag when AI scenarios are used

## Matrix execution

Matrix configs list scenario files only. The matrix runner writes:

- matrix manifest
- combined summary CSV
- per-scenario sub-runs under the matrix root

## Validation guarantees

The framework fails fast on:

- unknown keys
- missing required sections
- ambiguous or invalid channel profiles
- band/SCS mismatches
- DFT-s-OFDM without transform precoding
- invalid rank/port combinations
- AI-enabled scenarios without a model path
- AI-enabled scenarios without model ID / version / descriptor type
- invalid multi-panel / beam-count settings
- invalid energy-per-FLOP benchmark scaling

## AI/ML benchmark coverage

The config-driven AI benchmark runner now accepts these `ai_ml.use_case` values directly from YAML:

- `channel_estimation_enhancement`
- `csi_compression_reconstruction`
- `link_adaptation_mcs_selection`
- `beam_prediction`
- `interference_classification`
- `detector_selection`
- `impairment_mitigation`
- `energy_aware_mode_selection`

Shipped descriptor examples live under `simulator/configs/models`.

## Matrix run artifacts

Each matrix run now saves:

- `meta/matrix_config_resolved.json`
- `meta/matrix_config_resolved.yaml`
- `meta/matrix_source_chain.csv`
- `meta/matrix_manifest.json`

The matrix manifest records requested parallelism, execution mode, code version, run scope, and run completion.
