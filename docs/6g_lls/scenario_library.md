# 6G PHY LLS Scenario Library

## Scope

This repository ships a curated scenario library for 6G PHY link-level work. The canonical machine-readable manifest is [scenario_library_manifest.json](scenario_library_manifest.json).

The required scenario-family layer that groups these runnable packs into research-facing study families is documented in [scenario_family_library.md](scenario_family_library.md), with the machine-readable manifest [scenario_family_manifest.json](scenario_family_manifest.json) and the config source [required_scenario_families.yaml](../../simulator/configs/scenario_families/required_scenario_families.yaml).

The library is designed to satisfy these constraints:

- at least 20 well-named packs
- grouped by band, waveform, channel, feature family, and research purpose
- each scenario classified as baseline, agreed starting point, study candidate, or optional experiment
- all scenario creation and modification through configuration only

## Grouping Model

| Group | Goal |
|---|---|
| `band_coverage` | Mandatory carrier/band anchor scenarios |
| `ul_waveforms` | UL waveform baselines and candidate studies |
| `csi_acquisition` | CSI measurement, tracking, and reporting |
| `control_channel` | PDCCH/CORESET/search-space studies |
| `initial_access` | SSB, PBCH, and PRACH chains |
| `harq` | HARQ design-space studies |
| `mimo_beamforming` | Rank, beam, MU-MIMO, and panel studies |
| `ai_ml` | AI-enabled and non-AI paired scenarios |
| `energy_efficiency` | Energy-aware study packs |
| `bandwidth_profiles` | BWP-like and bandwidth-adaptation studies |
| `channel_stress` | low-SNR, high-Doppler, coverage, and fading stress |
| `impairments` | CFO, phase noise, FR2 impairment stress |
| `mandatory_catalog` | Mandatory pack families requested for the framework |

## Curated Scenario Packs

| Scenario Pack | Group | Class | Research Purpose |
|---|---|---|---|
| `dl_700mhz_coverage` | band_coverage | baseline_benchmark | low-band coverage benchmark |
| `dl_4ghz_baseline` | band_coverage | baseline_benchmark | mid-band NR-like benchmark |
| `dl_7ghz_mimo4x4` | band_coverage | agreed_starting_point | 7 GHz SU-MIMO benchmark |
| `dl_30ghz_beam_tracking` | band_coverage | study_item_candidate | FR2 beam tracking and tracking-RS study |
| `ul_4ghz_cpofdm` | ul_waveforms | baseline_benchmark | UL CP-OFDM benchmark |
| `ul_4ghz_dfts_pi2bpsk` | ul_waveforms | study_item_candidate | low-PAPR and pi/2-BPSK study |
| `ul_7ghz_srs_csi` | csi_acquisition | agreed_starting_point | SRS-based CSI benchmark |
| `pdcch_blind_decode_sweep` | control_channel | baseline_benchmark | blind-decode and AL sweep |
| `prach_detection` | initial_access | baseline_benchmark | PRACH detection reference |
| `harq_process_sweep` | harq | agreed_starting_point | HARQ process and RV sweep |
| `rank_adaptation_sweep` | mimo_beamforming | study_item_candidate | rank and layer adaptation |
| `lls_mimo4x4_multiuser_beamformed_awgn_validation` | mimo_beamforming | agreed_starting_point | MU-MIMO beamformed validation |
| `lls_mimo4x4_multiuser_beamformed` | mimo_beamforming | study_item_candidate | MU-MIMO fading study |
| `beam_prediction_ai` | ai_ml | study_item_candidate | AI beam prediction with fallback baseline |
| `ce_ai_nn` | ai_ml | study_item_candidate | AI-assisted channel estimation |
| `ce_non_ai_baseline` | ai_ml | baseline_benchmark | non-AI channel estimation benchmark |
| `csi_ai_autoencoder` | ai_ml | study_item_candidate | AI CSI compression and feedback |
| `csi_non_ai_baseline` | ai_ml | baseline_benchmark | non-AI CSI reporting benchmark |
| `energy_aware_ai_mode_select` | energy_efficiency | optional_research_experiment | AI mode switching with energy constraints |
| `bandwidth_operation_profiles` | bandwidth_profiles | agreed_starting_point | bandwidth-adaptation studies |
| `high_order_modulation_stress` | coding_modulation | study_item_candidate | higher-order modulation stress |
| `low_snr_stress` | channel_stress | baseline_benchmark | low-SNR coverage stress |
| `high_doppler_stress` | channel_stress | study_item_candidate | high-speed mobility stress |
| `cfo_stress` | impairments | baseline_benchmark | CFO acquisition/tracking stress |
| `phase_noise_stress` | impairments | study_item_candidate | phase-noise sensitivity study |
| `ul_30ghz_impairment_stress` | impairments | study_item_candidate | FR2 UL impairment study |
| `mandatory_general_scope_packs` | mandatory_catalog | baseline_benchmark | required band and carrier packs |
| `mandatory_tracking_packs` | mandatory_catalog | agreed_starting_point | required tracking packs |
| `mandatory_ul_waveform_packs` | mandatory_catalog | study_item_candidate | required UL waveform packs |
| `mandatory_csi_acquisition_packs` | mandatory_catalog | agreed_starting_point | required CSI acquisition packs |
| `mandatory_pdcch_packs` | mandatory_catalog | study_item_candidate | required PDCCH packs |
| `mandatory_initial_access_packs` | mandatory_catalog | study_item_candidate | required SSB/PRACH packs |
| `mandatory_harq_packs` | mandatory_catalog | agreed_starting_point | required HARQ packs |
| `mandatory_coding_modulation_packs` | mandatory_catalog | study_item_candidate | required coding/modulation packs |
| `mandatory_ai_ml_packs` | mandatory_catalog | study_item_candidate | required AI/ML packs |
| `mandatory_energy_efficiency_packs` | mandatory_catalog | study_item_candidate | required energy packs |

## Naming Rules

Scenario IDs should communicate:

- direction or subsystem (`dl`, `ul`, `pdcch`, `prach`, `harq`, `csi`)
- band or operating region (`700mhz`, `4ghz`, `7ghz`, `30ghz`)
- main feature axis (`beam_tracking`, `mimo4x4`, `ai`, `stress`, `baseline`)
- purpose (`validation`, `sweep`, `coverage`, `benchmark`, `stress`)

## Required Pairing Rules

When an AI scenario exists, a non-AI comparison scenario must also exist:

- `ce_ai_nn` paired with `ce_non_ai_baseline`
- `csi_ai_autoencoder` paired with `csi_non_ai_baseline`
- `beam_prediction_ai` paired with a non-AI beamforming baseline such as `lls_mimo4x4_multiuser_beamformed_awgn_validation`

## Mandatory Pack Families

The `mandatory_*_packs.yaml` files are catalog scenarios. They encode the minimum design assumptions and study directions required by the framework:

- general scope and carrier anchors
- finer tracking assumptions
- UL waveform studies
- CSI acquisition studies
- PDCCH studies
- initial access studies
- HARQ studies
- coding/modulation/shaping studies
- AI/ML studies
- energy-efficiency studies

## Recommended Usage

- Use the specific scenario files for direct lab runs and regressions.
- Use the mandatory pack families to ensure the framework still covers the required design space.
- Use [Sweep Framework](sweep_framework.md) to turn a reference pack into a larger campaign without editing source code.
