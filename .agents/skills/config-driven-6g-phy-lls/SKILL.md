---
name: config-driven-6g-phy-lls
description: Design and implement a production-grade, fully config-driven 6G PHY link-level simulator framework for this repository. Use when tasks involve 6G PHY LLS architecture, RAN1-style waveform scenario design, moving hardcoded PHY or scenario policy into YAML catalogs, adding DL/UL PHY chains or signals, tagging features as benchmark vs study vs experiment, or expanding results/KPIs so new scenarios can be created by editing configuration only.
---

# Config-Driven 6G PHY LLS

Use this skill when building or extending the 6G PHY LLS scenario framework in this repo.

## Core Rules

1. Treat YAML as the source of truth for configurable policy.
- Put defaults, allowed values, ranges, enums, and scenario inheritance in `simulator/configs/`.
- Do not hardcode scenario-specific constants in MATLAB if a researcher should be able to vary them.
- The command line may only pass:
  - config file path
  - output directory
  - run tag
  - optional log level

2. Keep the research taxonomy explicit.
- Tag every feature and scenario as exactly one of:
  - `baseline_benchmark`
  - `agreed_starting_point`
  - `study_item_candidate`
  - `optional_research_experiment`
- Keep NR-like benchmark behavior separate from 6G study features and lab-only experiments.

3. Keep code generic.
- If code changes are required, they must enable a reusable capability, not encode a one-off scenario.
- A new scenario must be creatable by editing YAML only once the capability exists.

4. Keep outputs exhaustive and honest.
- Enabled blocks must emit structured outputs, KPIs, logs, and reproducibility metadata.
- Do not silently skip key artifacts for enabled PHY blocks.

5. Route all behavior through one validated resolved config.
- Every module must read from a single validated `ScenarioConfig` object.
- Do not read ad hoc environment variables to control PHY behavior.
- Do not keep hidden defaults that materially affect simulation behavior.

6. Make config inheritance explicit and layered.
- Support composition across:
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

7. Save the exact resolved config with every run.
- Required reproducibility artifacts are:
  - raw input configs
  - resolved config after inheritance
  - schema validation report
  - simulator version and git hash
  - random seeds
  - environment summary

8. Keep validation mandatory and precise.
- Use schema-backed validation and fail fast on contradictory combinations.
- Error messages must identify the bad field, why it is invalid, the allowed range or values, and any dependency that caused the rejection.

9. Expose every feature block through config.
- No hidden defaults for waveform, coding, modulation, scrambling, interleaving, layer mapping, precoding, beamforming, DMRS, CSI-RS, SRS, PTRS, TRS, tracking RS, PDCCH, PDSCH, PUSCH, PUCCH, PBCH, PRACH, CSI acquisition, HARQ, receiver type, impairments, AI or ML models, or energy and complexity instrumentation.

10. Keep execution and outputs first-class.
- Support both single-run and matrix-run execution natively.
- Make outputs both machine-readable and human-readable:
  - JSON metadata
  - CSV or Parquet KPIs
  - plots or images for major curves
  - Markdown, HTML, or PDF-ready summaries
  - optional HDF5 or NPZ intermediate traces

11. Keep feature gating explicit.
- Baseline NR-like blocks, candidate 6G blocks, AI or ML blocks, extra impairments, and debug traces must all be individually switchable in config.

12. Preserve deterministic reproducibility.
- Support seedable generators, deterministic evaluation mode, reproducible sweep ordering, and same-config reproducibility within numerical tolerance.

## Workflow

1. Start with YAML surfaces.
- Update the relevant catalogs and defaults under `simulator/configs/schema/`, `simulator/configs/defaults/`, and the appropriate family under `simulator/configs/` before touching runners.
- Prefer inheritance from reusable band, channel, control, waveform, MIMO, and AI fragments over large duplicated scenarios.

2. Wire YAML into the runtime path.
- Typical touchpoints are:
  - `+sixgr/+lls6g/+config/schema.m`
  - `+sixgr/+lls6g/+config/validateScenarioConfig.m`
  - `+sixgr/+lls6g/buildInternalConfig.m`
  - `+sixgr/+lls6g/+runners/*.m`
  - `+sixgr/+truth/runWaveformLinkBundle.m`
- Reject hidden defaults and silent scenario downgrades.

3. Validate coverage against the full PHY surface.
- Read [framework-surfaces.md](references/framework-surfaces.md) when adding new configurable domains, PHY blocks, or result outputs.

4. Preserve simulator integrity.
- Keep truth/proxy labeling honest.
- Keep fading/profile semantics concrete.
- Avoid fallback behavior that hides missing capability.

5. Verify before claiming completion.
- Run:
```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); test6GScenarioConfigValidation; test6GScenarioRunner; test6GScenarioMatrixRunner; test6GScenarioPromptCompliance; test6GParameterCatalog;"
matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testLLS_DL; testLLS_UL; testLLS_ReferencePoints;"
matlab -batch "setup6GRSimToolkit('Verbose',false); testAll;"
```
- If the change also touches truth/proxy or result exports, run:
```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign;"
```

## Repo Guidance

- Keep scenario creation config-only after the generic capability lands.
- Prefer catalog-backed validation over ad hoc runtime checks.
- Keep result layout aligned with `+sixgr/+report/resultLayout.m` and the existing structured `results/lls/...` layout.
- If a requested feature cannot be supported honestly yet, fail closed and state the boundary instead of hardcoding a shortcut.
