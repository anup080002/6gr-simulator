# 6G PHY LLS Configuration Schema Reference

## Canonical Schema Files

The full machine-readable schema for the 6G framework is carried by:

- `simulator/configs/schema/scenario_parameter_catalog.yaml`
- `simulator/configs/schema/matrix_parameter_catalog.yaml`
- `simulator/configs/schema/core_parameter_catalog.yaml`

This document is the human-readable companion. When there is any ambiguity, the YAML catalogs are the canonical source for:

- allowed values
- numeric ranges
- required vs optional status
- top-level ordering
- nested-sweep rules
- value maps such as modulation-order mappings

## Config Formats

Scenario configs may be written in YAML or JSON.

### YAML Example

```yaml
inherits:
  - ../defaults/global.yaml
  - ../defaults/logging.yaml
  - ../defaults/kpi.yaml
  - ../releases/nr_ofdm_nr_baseline.yaml
  - ../bands/band_4ghz.yaml
  - ../waveforms/cp_ofdm.yaml
  - ../channels/tdl_c.yaml
meta:
  scenario_id: dl_4ghz_example
  description: Mid-band DL benchmark
  version: 1.0.0
  owner: ran1_lab
  research_class: baseline_benchmark
  maturity_tag: regression
scenario:
  runner_profile: waveform_bundle
  target_cases: [bundle, dl, pdsch, pdcch, ssb, pbch]
  notes: NR-like mid-band DL benchmark
simulation:
  link_direction: dl
  n_frames: 10
  n_slots: 20
  n_subframes: 10
  monte_carlo_iterations: 20
  random_seed: 42
  deterministic_mode: true
  snr_db: 10
  min_duration_s: 0.01
  snr_sweep_offsets_db: [-6, -3, 0, 3, 6]
```

### JSON Example

```json
{
  "inherits": [
    "../defaults/global.yaml",
    "../bands/band_30ghz.yaml",
    "../waveforms/cp_ofdm.yaml",
    "../channels/cdl_d.yaml"
  ],
  "meta": {
    "scenario_id": "fr2_tracking_example",
    "description": "FR2 tracking and beam study",
    "version": "1.0.0",
    "owner": "ran1_lab",
    "research_class": "study_item_candidate",
    "maturity_tag": "experimental"
  },
  "scenario": {
    "runner_profile": "generic_sweep",
    "target_cases": ["bundle", "dl", "csi_rs", "trs"],
    "notes": "Tracking study",
    "sweep": {
      "base_profile": "waveform_bundle",
      "output_name": "fr2_tracking_example"
    }
  }
}
```

## Layered Inheritance Model

Required merge order:

1. global defaults
2. release/profile defaults
3. band pack
4. waveform pack
5. channel pack
6. MIMO/beam pack
7. reference-signal pack
8. AI/ML pack
9. impairment pack
10. energy-efficiency pack
11. scenario override
12. sweep/matrix override

## Required Top-Level Sections

The resolved scenario schema now includes these required top-level sections:

1. `meta`
2. `run_control`
3. `config_inheritance`
4. `output_control`
5. `global_radio_scope`
6. `frame_timing`
7. `bandwidth_operation`
8. `deployment_topology`
9. `mobility`
10. `antenna_and_array`
11. `power_and_rf_frontend`
12. `waveform`
13. `resource_grid`
14. `channel_model`
15. `interference`
16. `signals_and_channels_common`
17. `reference_signals`
18. `pdcch`
19. `pdsch`
20. `pusch`
21. `pucch`
22. `prach`
23. `mimo_and_beam_management`
24. `csi_acquisition_and_reporting`
25. `channel_coding`
26. `modulation_and_mapping`
27. `link_adaptation`
28. `harq`
29. `synchronization_and_tracking`
30. `receiver_algorithms`
31. `impairments`
32. `ai_ml`
33. `energy_and_complexity`
34. `kpi_spec`
35. `sweeps_and_matrix`
36. `sanity_checks`
37. `processing_chains`

Legacy compatibility surfaces such as `simulation`, `frequency`, `frame`, `channels`, `control`, and `random_access` are still preserved so existing scenarios and runners keep working while the newer architecture sections become first-class.

## `processing_chains`

This section is the canonical machine-readable definition of the exact ordered PHY processing chains required by the 6G LLS framework. Each chain object contains:

- `enabled`
- `chain_label`
- `baseline_or_candidate_tag`
- `exact_order_locked`
- `ordered_blocks`
- `kpi_bindings`
- `artifact_bindings`
- `notes`

Each `ordered_blocks` entry contains:

- `order`
- `block_id`
- `block_name`
- `baseline_or_candidate_tag`
- `config_paths`
- `outputs`
- `optional_flag`
- `notes`

The shipped defaults for this section live in `simulator/configs/defaults/processing_chains.yaml`, and the schema contract is defined in `simulator/configs/schema/scenario_parameter_catalog_extension_04.yaml`.

## Section Reference

## `meta`

| Field | Type | Units | Allowed / Range | Required | Classification |
|---|---|---|---|---|---|
| `scenario_id` | string | n/a | non-empty | yes | baseline metadata |
| `description` | string | n/a | non-empty | yes | baseline metadata |
| `version` | string | n/a | non-empty | yes | baseline metadata |
| `owner` | string | n/a | non-empty | yes | baseline metadata |
| `research_class` | string | n/a | `baseline_benchmark`, `agreed_starting_point`, `study_item_candidate`, `optional_research_experiment` | recommended | feature classification |
| `maturity_tag` | string | n/a | `baseline`, `smoke`, `regression`, `stress`, `experimental`, `lab` | yes | baseline metadata |
| `scenario_group` | string | n/a | free text | optional | library grouping |
| `tags` | list[string] | n/a | free text list | optional | indexing |

## `scenario`

| Field | Type | Units | Allowed / Range | Required | Classification |
|---|---|---|---|---|---|
| `runner_profile` | string | n/a | `waveform_bundle`, `pdcch_blind_decode_sweep`, `prach_detection`, `generic_sweep`, `ai_benchmark` | yes | execution control |
| `target_cases` | list[string] | n/a | `bundle`, `dl`, `ul`, `pdsch`, `pusch`, `pdcch`, `pucch`, `pbch`, `ssb`, `prach`, `csi_rs`, `srs`, `dmrs`, `trs`, `harq` | yes | execution control |
| `notes` | string | n/a | non-empty | yes | execution metadata |
| `sweep` | struct | n/a | must match nested sweep schema | conditional | sweep framework |
| `ai_benchmark` | struct | n/a | AI benchmark nested rules | optional | AI/ML |
| `expected_outputs` | list[string] | n/a | artifact IDs | optional | reporting |

## `simulation`

| Field | Type | Units | Allowed / Range | Required | Classification |
|---|---|---|---|---|---|
| `link_direction` | string | n/a | `dl`, `ul`, `both` | yes | baseline |
| `n_frames` | integer | frames | `>= 1` | yes | baseline |
| `n_slots` | integer | slots | `>= 1` | yes | baseline |
| `n_subframes` | integer | subframes | `>= 1` | yes | baseline |
| `monte_carlo_iterations` | integer | runs | `>= 1` | yes | baseline |
| `random_seed` | integer | n/a | `>= 0` | yes | reproducibility |
| `deterministic_mode` | boolean | n/a | true/false | yes | reproducibility |
| `snr_db` | number | dB | finite | yes | baseline |
| `min_duration_s` | number | s | `> 0` | yes | baseline |
| `snr_sweep_offsets_db` | list[number] | dB | finite list | yes | sweep control |

## `frequency`

| Field | Type | Units | Allowed / Range | Required | Classification |
|---|---|---|---|---|---|
| `range_name` | string | n/a | `FR1`, `FR2`, `FR3` | yes | baseline |
| `center_frequency_hz` | number | Hz | `> 0` | yes | baseline |
| `bandwidth_hz` | number | Hz | `> 0` | yes | baseline |
| `duplex_mode` | string | n/a | `FDD`, `TDD` | yes | baseline |
| `carrier_count` | integer | carriers | `>= 1` | yes | baseline |
| `carrier_aggregation_enabled` | boolean | n/a | true/false | yes | candidate-ready |
| `band_name` | string | n/a | non-empty | yes | baseline |
| `bandwidth_options_hz` | list[number] | Hz | finite list | yes | validation anchor |
| `numerology_options_khz` | list[number] | kHz | `15, 30, 60, 120, 240` | yes | validation anchor |
| `max_mimo_size` | integer | layers/ports | `>= 1` | yes | baseline |
| `max_supported_center_frequency_hz` | number | Hz | `> 0` | optional | capability description |
| `custom_frequency_override_allowed` | boolean | n/a | true/false | optional | lab override |
| `mobility_defaults_kmph` | number | km/h | `>= 0` | yes | baseline |
| `channel_model_defaults` | string | n/a | free text | yes | metadata |
| `reference_signal_defaults` | string | n/a | free text | yes | metadata |
| `power_model_defaults` | string | n/a | free text | yes | metadata |
| `energy_model_defaults` | string | n/a | free text | yes | metadata |
| `rf_impairment_defaults` | string | n/a | free text | yes | metadata |
| `n_size_grid` | integer | RB grid units | `>= 1` | yes | baseline |

## `frame`

| Field | Type | Units | Allowed / Range | Required | Classification |
|---|---|---|---|---|---|
| `scs_khz` | number | kHz | `15, 30, 60, 120, 240` | yes | baseline |
| `cp_type` | string | n/a | `normal`, `extended` | yes | baseline |
| `slot_format` | string | n/a | `dl`, `ul`, `flexible`, `mixed` | yes | baseline |
| `tdd_pattern` | string | n/a | non-empty | yes | baseline |

## `waveform`

| Field | Type | Units | Allowed / Range | Required | Classification |
|---|---|---|---|---|---|
| `dl_waveform` | string | n/a | `CP-OFDM`, `DFT-s-OFDM` | yes | baseline |
| `ul_waveform` | string | n/a | `CP-OFDM`, `DFT-s-OFDM` | yes | baseline/candidate |
| `fft_size` | integer | samples | `>= 64` | yes | baseline |
| `sample_rate_hz` | number | Hz | `> 0` | yes | baseline |
| `windowing_enabled` | boolean | n/a | true/false | yes | baseline |
| `transform_precoding_enabled` | boolean | n/a | true/false | yes | baseline |
| `experimental_dl_dfts_ofdm_enabled` | boolean | n/a | true/false | optional | candidate |
| `ul_layer_support_mode` | string | n/a | `all_supported_layers`, `single_layer_baseline`, `multi_layer_candidate` | optional | candidate |
| `low_papr_mode` | string | n/a | `none`, `tone_reservation`, `frequency_domain_truncation`, `candidate_enhanced` | optional | candidate |
| `tone_reservation_enabled` | boolean | n/a | true/false | optional | candidate |
| `frequency_domain_truncation_enabled` | boolean | n/a | true/false | optional | candidate |
| `flexible_dft_size_enabled` | boolean | n/a | true/false | optional | candidate |
| `noncontiguous_mapping_enabled` | boolean | n/a | true/false | optional | candidate |
| `dmrs_data_multiplexing_mode` | string | n/a | `baseline`, `enhanced_candidate` | optional | candidate |
| `ue_coherence_mode` | string | n/a | `coherent`, `partially_coherent` | optional | candidate |
| `ue_power_limited` | boolean | n/a | true/false | optional | candidate |

## Remaining Sections

The remaining sections are fully defined in the canonical schema YAML and include:

- `channels`
- `reference_signals`
- `mimo`
- `users`
- `coding`
- `modulation`
- `control`
- `harq`
- `random_access`
- `impairments`
- `ai_ml`
- `energy_efficiency`
- `kpis`
- `logging`
- `output`

Representative parameters across those sections include:

- channel model/profile, delay spread, Doppler, pathloss, shadowing
- SSB/PBCH/DMRS/CSI-RS/SRS/PTRS/TRS/tracking-RS enable and configuration
- antenna counts, layers, beam counts, panel counts, TRP counts, precoder type
- LDPC/Polar families, base graph selection, decoder iterations
- modulation order, MCS, pi/2-BPSK, constellation shaping
- CORESET, REG/CCE/search-space assumptions, blind decoding, PDCCH repetition candidates
- HARQ process count, RV sequence, combining mode, feedback timing, stop condition
- PRACH format, root sequence, ZCZ, repetition, beam mapping
- CFO, phase noise, IQ imbalance, PA nonlinearity, quantization, timing offset
- AI model identity, mode, fallback behavior, download mode, observation count
- UE/NW energy, RF-chain energy, duty cycle, bandwidth adaptation
- KPI switches, logging strictness, output save controls

## Dependency Rules

The validator enforces dependency rules such as:

- `waveform.ul_waveform='DFT-s-OFDM'` requires `transform_precoding_enabled=true`
- `frame.scs_khz` must be present in `frequency.numerology_options_khz`
- `frequency.bandwidth_hz` must be present in `frequency.bandwidth_options_hz`
- AI-enabled scenarios must provide model identity and descriptor fields
- candidate-only features must be paired with non-AI or baseline comparison scenarios when applicable

## Baseline vs Candidate Tags

Each field should be treated as one of:

- baseline benchmark
- agreed starting point
- candidate study control
- optional experiment control

The primary tag lives at `meta.research_class`. Feature-specific candidate status is represented by:

- candidate-specific enum values
- scenario pack choice
- scenario-library classification

## Matrix Schema

Matrix configs contain:

- matrix metadata
- execution settings
- scenario list

The canonical matrix schema is `simulator/configs/schema/matrix_parameter_catalog.yaml`.
