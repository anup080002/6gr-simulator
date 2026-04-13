# 6G PHY LLS Validation Rules

## Validation Philosophy

Validation must fail fast on invalid or contradictory configuration, and it must distinguish:

- hard invalid combinations
- risky but permitted combinations
- candidate-only gated combinations
- reproducibility violations

## Invalid Combinations

The following combinations must be rejected:

- unknown top-level or section keys
- missing required sections or fields
- `frame.scs_khz` outside `frequency.numerology_options_khz`
- `frequency.bandwidth_hz` outside `frequency.bandwidth_options_hz`
- `waveform.ul_waveform='DFT-s-OFDM'` with `transform_precoding_enabled=false`
- `coding.data_code_type='POLAR'` for data channels
- `coding.control_code_type` not equal to `POLAR` for control scenarios
- AI enabled without `model_id`, `model_version`, `descriptor_type`, or `model_path`
- unsupported `scenario.runner_profile`
- empty `scenario.target_cases`
- `generic_sweep` without `scenario.sweep`
- invalid nested sweep overrides

## Warning Conditions

The framework should warn, but not always fail, for combinations such as:

- FR2 carrier with very low sampling assumptions that are technically allowed but likely unrealistic
- large layer count with weak antenna geometry
- aggressive high-order modulation at extremely low SNR
- beam-management features enabled without matching beam diagnostic KPIs
- candidate shaping or mixed-modulation studies without a paired benchmark scenario
- AI-enabled scenario without a declared non-AI comparison partner in the campaign plan

## Candidate-Only Feature Gating

Candidate features must remain explicitly gated and separately labeled. Examples:

- DL DFT-s-OFDM
- multi-layer DFT-s-OFDM studies
- enhanced DMRS/data multiplexing
- higher aggregation levels beyond baseline control assumptions
- PDCCH repetition and prior-aided decoding
- candidate PRACH sequences and unsymmetric SSB-RO mappings
- 1024QAM / 4096QAM / NUC / 2D-NUC
- AI beam prediction, AI CSI compression, AI channel estimation
- advanced energy-aware AI or scheduling studies

Rules:

- candidate scenarios must set `meta.research_class` to `study_item_candidate` or `optional_research_experiment`
- paired benchmark scenarios should exist for comparison
- reports must not present candidate-only performance as baseline behavior

## Reproducibility Requirements

Every valid run must record:

- scenario ID and config hash
- raw config inputs
- resolved config snapshots
- simulator version and git hash
- random seed
- deterministic mode
- run scope and run completion
- environment summary

Matrix runs must additionally record:

- matrix ID
- scenario list
- repeat count
- execution mode
- combined summary location

## Strict Validation Expectations

Strict mode should enforce:

- no hidden PHY defaults that affect behavior
- no use of environment variables for PHY behavior
- no contradictory pack inheritance
- no unsupported candidate fields sneaking into baseline runs
- no silent downgrade from requested feature to disabled behavior

## Error Message Requirements

Every validation error should identify:

- the bad field path
- the current value
- the allowed values or range
- the violated dependency
- the config file or context that triggered the issue

Example style:

```text
frame.scs_khz=120 is not allowed by frequency.numerology_options_khz in scenario X.
```

## Baseline vs Candidate Separation

Validation and reports must preserve:

- NR-like baseline assumptions
- agreed benchmark starting points
- candidate 6G features
- optional lab-specific experiments

No scenario should blur those categories.
