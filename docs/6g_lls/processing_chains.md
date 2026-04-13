# 6G PHY LLS Exact Processing Chains

This document is the human-readable companion to the machine-readable `processing_chains` section shipped in:

- `simulator/configs/defaults/processing_chains.yaml`
- `simulator/configs/schema/scenario_parameter_catalog_extension_04.yaml`

The YAML section is the normative source for exact block order, per-block config bindings, KPI bindings, and artifact bindings.

## Chain Objects

Every chain is represented as a config object with:

- `enabled`
- `chain_label`
- `baseline_or_candidate_tag`
- `exact_order_locked`
- `ordered_blocks`
- `kpi_bindings`
- `artifact_bindings`
- `notes`

Every ordered block carries:

- `order`
- `block_id`
- `block_name`
- `baseline_or_candidate_tag`
- `config_paths`
- `outputs`
- `optional_flag`
- `notes`

## Exact Ordered Chains

### A. DL Common-Signal / Initial-Access Tx

1. `cell_common_information_generation`
2. `pss_generation`
3. `sss_generation`
4. `pbch_payload_generation`
5. `pbch_crc_coding_scrambling_modulation`
6. `pbch_dmrs_insertion`
7. `ssb_assembly`
8. `ssb_repetition_clustering_beam_sweep`
9. `common_pdcch_pdsch_for_si`
10. `re_mapping`
11. `ofdm_modulation`
12. `windowing_filtering_wola`
13. `cfr_dpd_pa_model`
14. `beamforming_antenna_mapping`
15. `rf_impairments`
16. `propagation`

Primary config surfaces:
- `signals_and_channels_common.*`
- `reference_signals.pbch_dmrs`
- `waveform`
- `power_and_rf_frontend`
- `mimo_and_beam_management`
- `channel_model`

### B. DL Common-Signal / Initial-Access Rx

1. `rf_receive_chain`
2. `agc_adc_iq_compensation`
3. `coarse_timing_detection`
4. `pss_detection`
5. `sss_detection`
6. `cell_id_timing_refinement`
7. `cfo_estimation_correction`
8. `fft`
9. `pbch_dmrs_extraction_channel_estimation`
10. `pbch_equalization_demodulation_decoding`
11. `pbch_crc_check`
12. `ssb_repetition_combining`
13. `sib1_scheduling_reception`
14. `pdcch_pdsch_for_si`
15. `search_latency_complexity_accounting`
16. `one_shot_success_accounting`

Primary config surfaces:
- `synchronization_and_tracking`
- `receiver_algorithms`
- `signals_and_channels_common.*`
- `pdcch`
- `pdsch`
- `energy_and_complexity`

### C. PRACH / Random-Access Tx

1. `access_trigger`
2. `beam_ro_ssb_association_determination`
3. `preamble_sequence_selection`
4. `root_sequence_cyclic_shift_selection`
5. `repetition_policy_application`
6. `same_beam_different_beam_policy`
7. `beam_prediction_refinement_hook`
8. `msg1_waveform_generation`
9. `prach_mapping`
10. `waveform_generation`
11. `ue_power_control`
12. `rf_impairments_pa`
13. `propagation`

Primary config surfaces:
- `prach`
- `signals_and_channels_common.ssb`
- `waveform`
- `power_and_rf_frontend`
- `ai_ml`

### D. PRACH / Random-Access Rx

1. `ro_observation`
2. `timing_hypothesis_search`
3. `frequency_hypothesis_search`
4. `preamble_correlation_detection`
5. `false_alarm_miss_detection_accounting`
6. `beam_pair_detection_accounting`
7. `collision_handling_accounting`
8. `ta_estimation`
9. `detection_latency_accounting`
10. `msg2_msg3_linkage`

Primary config surfaces:
- `prach`
- `receiver_algorithms`
- `impairments`
- `kpi_spec`

### E. PDCCH Tx

1. `dci_payload_generation`
2. `crc_attachment_masking`
3. `channel_coding`
4. `rate_matching`
5. `interleaving`
6. `scrambling`
7. `modulation`
8. `cce_reg_reg_bundle_mapping`
9. `dmrs_insertion`
10. `coreset_mapping`
11. `ofdm_modulation`
12. `beamforming_mu_mimo_mtrp`

Primary config surfaces:
- `pdcch`
- `channel_coding`
- `modulation_and_mapping`
- `reference_signals.pdcch_dmrs`
- `mimo_and_beam_management`

### F. PDCCH Rx

1. `search_space_determination`
2. `candidate_generation`
3. `fft_coreset_extraction`
4. `dmrs_channel_estimation`
5. `equalization`
6. `blind_decoding`
7. `crc_checking`
8. `dci_selection`
9. `false_alarm_miss_detection_logging`
10. `blind_decode_complexity_energy_logging`
11. `prior_info_aided_decoding`
12. `two_stage_multi_stage_dci_handling`
13. `optional_detection_feedback_generation`

Primary config surfaces:
- `pdcch`
- `reference_signals.pdcch_dmrs`
- `receiver_algorithms`
- `energy_and_complexity`
- `harq`

### G. PDSCH Tx

1. `payload_generation`
2. `tb_crc`
3. `segmentation`
4. `cb_crc`
5. `outer_coding_packet_level_coding`
6. `ldpc_encoding`
7. `rate_matching`
8. `cb_cross_cb_interleaving`
9. `distribution_matching_shaping`
10. `scrambling`
11. `modulation_nuc_mixed_joint`
12. `codeword_to_layer_mapping`
13. `layer_mapping`
14. `precoding`
15. `dmrs_ptrs_csi_rs_coexistence_handling`
16. `re_mapping`
17. `ofdm_modulation`
18. `windowing_filtering_cfr_dpd`
19. `rf_antenna_beamforming`
20. `propagation`

Primary config surfaces:
- `pdsch`
- `channel_coding`
- `modulation_and_mapping`
- `reference_signals.pdsch_dmrs`
- `reference_signals.ptrs`
- `reference_signals.nzp_csi_rs`
- `mimo_and_beam_management`

### H. PDSCH Rx

1. `fft_resource_extraction`
2. `synchronization_refinement`
3. `dmrs_based_ce`
4. `ptrs_phase_tracking`
5. `channel_interpolation`
6. `equalization_detection`
7. `residual_interference_estimation`
8. `demapping`
9. `descrambling`
10. `deinterleaving`
11. `rate_dematching`
12. `ldpc_decoding`
13. `outer_decoding`
14. `crc_checks`
15. `harq_combining`
16. `throughput_bler_logging`
17. `llr_iteration_complexity_logging`

Primary config surfaces:
- `receiver_algorithms`
- `reference_signals.pdsch_dmrs`
- `reference_signals.ptrs`
- `channel_coding`
- `harq`

### I. PUSCH Tx

1. `ul_sch_payload`
2. `uci_multiplexing`
3. `crc`
4. `segmentation`
5. `ldpc_or_control_coding`
6. `rate_matching`
7. `scrambling`
8. `modulation`
9. `transform_precoding`
10. `low_papr_option_handling`
11. `layer_mapping`
12. `precoding`
13. `dmrs_ptrs_insertion`
14. `re_mapping`
15. `ofdm_modulation`
16. `power_control_pa_rf`
17. `propagation`

Primary config surfaces:
- `pusch`
- `channel_coding`
- `modulation_and_mapping`
- `reference_signals.pusch_dmrs`
- `reference_signals.ptrs`
- `waveform`

### J. PUSCH Rx

1. `fft_extraction`
2. `dmrs_based_ce`
3. `equalization_mimo_detection`
4. `demapping`
5. `uci_separation`
6. `descrambling`
7. `rate_dematching`
8. `ldpc_decoding`
9. `crc_checks`
10. `harq_combining`
11. `ul_throughput_bler_latency_logging`

Primary config surfaces:
- `receiver_algorithms`
- `reference_signals.pusch_dmrs`
- `channel_coding`
- `harq`
- `kpi_spec`

### K. PUCCH Tx/Rx

1. `payload_selection`
2. `format_and_multiplexing_selection`
3. `coding_policy_application`
4. `scrambling_modulation`
5. `low_papr_handling`
6. `dmrs_insertion`
7. `resource_mapping`
8. `waveform_generation`
9. `power_control_rf`
10. `propagation`
11. `fft_extraction`
12. `channel_estimation_equalization`
13. `detection_demultiplexing`
14. `harq_ack_sr_csi_decoding`
15. `simultaneous_pucch_pusch_resolution`
16. `false_alarm_miss_detection_energy_logging`

Primary config surfaces:
- `pucch`
- `pucch.formats`
- `pucch.harq_ack_policy`
- `pucch.sr_policy`
- `pucch.csi_policy`
- `pusch`
- `energy_and_complexity`

### L. SRS / CSI-RS / TRS / Tracking-RS

1. `generation`
2. `mapping`
3. `port_handling`
4. `beam_handling`
5. `power`
6. `observation`
7. `estimation`
8. `interpolation`
9. `kpi_extraction`
10. `overhead_logging`
11. `energy_logging`

Primary config surfaces:
- `reference_signals.pdsch_dmrs`
- `reference_signals.pdcch_dmrs`
- `reference_signals.pbch_dmrs`
- `reference_signals.pusch_dmrs`
- `reference_signals.ptrs`
- `reference_signals.nzp_csi_rs`
- `reference_signals.zp_csi_rs`
- `reference_signals.srs`
- `reference_signals.trs`
- `reference_signals.tracking_rs`
- `reference_signals.self_interference_rs`
- `reference_signals.custom_rs`

### M. CSI Acquisition / Reporting

1. `measurement_rs_selection`
2. `channel_estimation`
3. `feature_extraction`
4. `codebook_cri_candidate_generation`
5. `cqi_pmi_ri_cri_computation`
6. `compression_encoding_analog_mapping`
7. `multiplexing_with_uci_data`
8. `reporting`
9. `delay_periodicity_application_modeling`
10. `scheduler_link_adaptation_application`
11. `kpi_logging`

Primary config surfaces:
- `csi_acquisition_and_reporting`
- `reference_signals`
- `mimo_and_beam_management`
- `link_adaptation`
- `ai_ml`
- `energy_and_complexity`

This chain explicitly covers:
- `PMI` with `type1_su_mimo`, `type2_mu_mimo`, and `etype2_candidate` codebook modes
- `RI`
- `CRI`
- aggregate CSI payload construction and application

### N. HARQ

1. `initial_transmission_tagging`
2. `feedback_generation`
3. `ack_nack_dtx_detection`
4. `rv_selection`
5. `retransmission_scheduling`
6. `combining`
7. `stop_criteria`
8. `latency_accounting`
9. `coverage_reliability_accounting`
10. `overhead_accounting`

Primary config surfaces:
- `harq`
- `pucch`
- `pdcch`
- `link_adaptation`
- `energy_and_complexity`

### O. AI/ML

1. `baseline_feature_extraction`
2. `ai_model_input_preparation`
3. `inference_call`
4. `confidence_fallback`
5. `post_processing`
6. `integration_with_standard_phy_pipeline`
7. `complexity_accounting`
8. `invocation_frequency_accounting`
9. `generalization_tagging`
10. `failure_logging`

Primary config surfaces:
- `ai_ml`
- `receiver_algorithms`
- `reference_signals`
- `link_adaptation`
- `mimo_and_beam_management`
- `energy_and_complexity`

## Validation Expectations

- `exact_order_locked` must remain true for shipped baseline chains.
- `ordered_blocks.order` must be contiguous and start at 1.
- Every block must bind to at least one config path.
- Candidate-only blocks must keep their `baseline_or_candidate_tag`.
- Optional blocks must remain explicit and never disappear silently from the chain definition.
