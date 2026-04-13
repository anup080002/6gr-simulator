# 6G PHY LLS Required Scenario Families

## Scope

This document defines the required scenario-family layer that sits above the individual runnable scenario packs. The canonical machine-readable source is:

- [required_scenario_families.yaml](../../simulator/configs/scenario_families/required_scenario_families.yaml)

Each family entry provides:

- objective
- baseline config anchor
- supporting config packs
- sweep definition
- primary KPIs
- optional KPIs
- mandatory plots
- pass/fail expectations
- typical debug traces

## Required Family Index

| Family | Research Class | Baseline Config Anchor |
|---|---|---|
| `nr_like_benchmark_baseline` | `baseline_benchmark` | `simulator/configs/scenarios/dl_4ghz_baseline.yaml` |
| `band_700mhz_fdd_coverage` | `baseline_benchmark` | `simulator/configs/scenarios/dl_700mhz_coverage.yaml` |
| `band_2ghz_fdd_baseline` | `baseline_benchmark` | `simulator/configs/scenarios/mandatory_general_scope_packs.yaml::around_2ghz` |
| `band_4ghz_tdd_baseline` | `agreed_starting_point` | `simulator/configs/scenarios/mandatory_tracking_packs.yaml::tdd_4ghz_30khz` |
| `band_7ghz_wideband_high_capacity` | `agreed_starting_point` | `simulator/configs/scenarios/dl_7ghz_mimo4x4.yaml` |
| `band_30ghz_high_band_beam_centric` | `study_item_candidate` | `simulator/configs/scenarios/dl_30ghz_beam_tracking.yaml` |
| `tracking_rs_synchronization_stress` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_tracking_packs.yaml::cfo_initial_acquisition` |
| `pdcch_reliability_blind_decoding_blocking` | `study_item_candidate` | `simulator/configs/scenarios/pdcch_blind_decode_sweep.yaml` |
| `ul_waveform_cp_ofdm_vs_dfts_ofdm` | `study_item_candidate` | `simulator/configs/scenarios/ul_4ghz_cpofdm.yaml` |
| `dl_based_csi_acquisition` | `agreed_starting_point` | `simulator/configs/scenarios/mandatory_csi_acquisition_packs.yaml::dl_based_csi` |
| `ul_based_csi_acquisition` | `agreed_starting_point` | `simulator/configs/scenarios/mandatory_csi_acquisition_packs.yaml::ul_based_csi` |
| `joint_dl_ul_csi_acquisition` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_csi_acquisition_packs.yaml::joint_dl_ul_csi` |
| `prach_initial_access_beam_management` | `study_item_candidate` | `simulator/configs/scenarios/prach_detection.yaml` |
| `harq_latency_reliability_tradeoff` | `agreed_starting_point` | `simulator/configs/scenarios/harq_process_sweep.yaml` |
| `high_order_modulation_and_coding_chain` | `study_item_candidate` | `simulator/configs/scenarios/high_order_modulation_stress.yaml` |
| `probabilistic_shaping_distribution_matching` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_coding_modulation_packs.yaml::shaping_ccdm` |
| `joint_coding_modulation_candidate_studies` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_coding_modulation_packs.yaml::joint_coding_modulation_candidate` |
| `ai_demodulation` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_ai_ml_packs.yaml::ai_demodulation_candidate` |
| `ai_csi_compression_reporting` | `study_item_candidate` | `simulator/configs/scenarios/csi_ai_autoencoder.yaml` |
| `energy_efficiency_common_signal_clustering` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_energy_efficiency_packs.yaml::common_channel_clustering` |
| `bandwidth_adaptation_bwp_like_studies` | `agreed_starting_point` | `simulator/configs/scenarios/bandwidth_operation_profiles.yaml` |
| `mtrp_sfn_coordinated_transmission` | `study_item_candidate` | `simulator/configs/scenarios/lls_mimo4x4_multiuser_beamformed.yaml` with inline family overrides |
| `mrss_coexistence_stress` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_pdcch_packs.yaml::mrss_tolerant_candidate` |
| `full_duplex_self_interference_candidate_studies` | `study_item_candidate` | `simulator/configs/scenarios/mandatory_ai_ml_packs.yaml::ai_full_duplex_si_channel_estimation` with inline family overrides |

## Design Notes

- Families are not replacements for runnable scenario packs. They are the required research-facing catalog that tells a lab user which config packs, sweep axes, KPIs, plots, and debug traces define each study area.
- When a family is anchored to a `mandatory_*_packs.yaml` file, the `override_label` identifies the exact native sweep override that should be used as the baseline starting point.
- When a family needs a composed starting point that is broader than one shipped scenario, the family definition may include `inline_overrides` on top of the baseline scenario anchor.

## Usage

Use the family catalog to choose:

1. the starting scenario pack
2. the required sweep axes
3. the non-optional KPIs and plots
4. the pass/fail expectations and debug traces needed for lab analysis

The family catalog is intended to keep future scenario expansion config-only. New lab studies should extend this catalog and reference existing reusable packs before adding new source logic.
