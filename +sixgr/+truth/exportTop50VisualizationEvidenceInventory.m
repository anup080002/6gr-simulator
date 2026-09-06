function out = exportTop50VisualizationEvidenceInventory(runFolder, cfg)
%EXPORTTOP50VISUALIZATIONEVIDENCEINVENTORY Audit raw-data support for 50 LLS visuals.
%
% A visual is "validated_reconstructible" only when a non-empty persisted
% source satisfies an explicit panel and column contract. A similarly named
% CSV is never promoted to that state. Feature-disabled rows remain explicit
% and no placeholder measurements or images are created.

if nargin < 2 || ~isstruct(cfg)
    cfg = struct();
end
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);

contract = localContract();
inventory = contract;
n = height(inventory);
inventory.AvailabilityStatus = strings(n, 1);
inventory.ResolvedSourceArtifact = strings(n, 1);
inventory.SourceRowCount = zeros(n, 1);
inventory.MissingValidationColumns = strings(n, 1);
inventory.FeatureState = strings(n, 1);
inventory.PlotCanBeRegeneratedFromCSV = false(n, 1);
inventory.AuditNotes = strings(n, 1);

for i = 1:n
    [featureEnabled, featureState] = localFeatureState(cfg, inventory.FeatureGate(i));
    inventory.FeatureState(i) = featureState;
    [sourcePath, sourceRows, missingColumns, validated] = localResolveSource( ...
        runFolder, inventory.CandidateSourceArtifacts(i), ...
        inventory.RequiredValidationColumns(i));
    inventory.ResolvedSourceArtifact(i) = sourcePath;
    inventory.SourceRowCount(i) = sourceRows;
    inventory.MissingValidationColumns(i) = missingColumns;

    if strlength(sourcePath) > 0 && validated
        inventory.AvailabilityStatus(i) = "validated_reconstructible";
        inventory.PlotCanBeRegeneratedFromCSV(i) = true;
        inventory.AuditNotes(i) = "Non-empty runtime source satisfies the registered panel/column contract.";
    elseif strlength(sourcePath) > 0
        inventory.AvailabilityStatus(i) = "source_present_semantic_audit_pending";
        inventory.AuditNotes(i) = "A non-empty related source exists, but the full raw-field reconstruction contract is not yet proven.";
    elseif ~featureEnabled && featureState == "disabled"
        inventory.AvailabilityStatus(i) = "not_applicable_feature_disabled";
        inventory.AuditNotes(i) = "The owning feature is explicitly disabled; no output was manufactured.";
    else
        inventory.AvailabilityStatus(i) = "missing_runtime_capture";
        if inventory.VisualID(i) == 22
            inventory.AuditNotes(i) = ...
                "No measured Doppler spectrum is available. This panel requires " + ...
                "a same-run executed path-gain time series with sufficient temporal " + ...
                "samples and observation aperture; a configured/scalar mobility " + ...
                "Doppler value is not accepted as a spectrum.";
        else
            inventory.AuditNotes(i) = "No non-empty same-run runtime source satisfied this evidence requirement.";
        end
    end
end

contractPath = fullfile(layout.ReportCSVDir, "top50_visualization_contract.csv");
inventoryPath = fullfile(layout.ReportCSVDir, "top50_visualization_evidence_inventory.csv");
sixgr.util.csvWriteTable(contractPath, contract);
sixgr.util.csvWriteTable(inventoryPath, inventory);

out = struct( ...
    "ContractCSV", string(contractPath), ...
    "InventoryCSV", string(inventoryPath), ...
    "ContractTable", contract, ...
    "InventoryTable", inventory, ...
    "ValidatedReconstructibleCount", nnz(inventory.AvailabilityStatus == "validated_reconstructible"), ...
    "SourcePresentPendingAuditCount", nnz(inventory.AvailabilityStatus == "source_present_semantic_audit_pending"), ...
    "MissingRuntimeCaptureCount", nnz(inventory.AvailabilityStatus == "missing_runtime_capture"), ...
    "DisabledCount", nnz(inventory.AvailabilityStatus == "not_applicable_feature_disabled"));
end

function T = localContract()
names = [ ...
    "Run configuration dashboard"; ...
    "End-to-end PHY-chain status"; ...
    "Frame-slot-symbol timing map"; ...
    "Transmit resource grid"; ...
    "RE type and power-allocation map"; ...
    "TB/CB coding and rate-matching waterfall"; ...
    "Mapper-input constellation"; ...
    "Per-layer / antenna-port constellation"; ...
    "Transmit I/Q waveform"; ...
    "OFDM symbol, CP and windowing zoom"; ...
    "Envelope, magnitude and phase statistics"; ...
    "Transmit power spectral density"; ...
    "Occupied bandwidth and emission-mask overlay"; ...
    "PAPR complementary CDF"; ...
    "PA AM-AM characteristic"; ...
    "PA AM-PM characteristic"; ...
    "EVM versus PA output power / back-off"; ...
    "ACLR versus PA output power / back-off"; ...
    "Channel power-delay profile"; ...
    "Time-varying channel impulse response"; ...
    "Channel frequency response"; ...
    "Doppler spectrum"; ...
    "Delay-Doppler map"; ...
    "Angular power spectrum"; ...
    "MIMO channel-matrix heatmap"; ...
    "Singular values and condition number"; ...
    "Spatial-correlation matrix"; ...
    "Beam pattern and codebook-gain map"; ...
    "Received I/Q waveform"; ...
    "Received spectrum through the front end"; ...
    "Synchronization-correlation metric"; ...
    "Timing estimate and residual error"; ...
    "CFO estimate and residual"; ...
    "Phase-noise / common-phase-error trajectory"; ...
    "Estimated-channel magnitude and phase grid"; ...
    "Channel-estimation NMSE"; ...
    "Equalizer weights / post-equalization SINR"; ...
    "Post-equalization constellation"; ...
    "EVM versus SNR, MCS and number of layers"; ...
    "LLR reliability distribution"; ...
    "Pre- and post-decoder BER"; ...
    "Transport-block BLER with confidence intervals"; ...
    "Decoder convergence and iteration count"; ...
    "CRC / TB error timeline and burst map"; ...
    "Throughput and goodput"; ...
    "Spectral efficiency"; ...
    "HARQ-round performance and combining gain"; ...
    "CQI-MCS calibration and OLLA evolution"; ...
    "Rank, PMI and beam selection"; ...
    "Procedure reliability and latency suite"];

category = [repmat("scenario_mapping_baseband",10,1); ...
    repmat("waveform_spectrum_rf",10,1); ...
    repmat("propagation_mimo_received_signal",10,1); ...
    repmat("synchronization_estimation_equalization",10,1); ...
    repmat("decoding_kpi_adaptation_procedures",10,1)];
candidate = strings(50,1);
required = strings(50,1);
gate = repmat("always",50,1);

candidate(1) = "reports/csv/scenario_summary.csv|reports/csv/resolved_config.csv";
candidate(2) = "reports/csv/causal_phy_chain_audit.csv|reports/csv/e2e_phy_chain_stage_trace.csv";
candidate(3) = "control/csv/timing_synchronization_table.csv|reports/csv/frame_slot_symbol_timing.csv";
candidate(4) = "reports/csv/live_re_allocation_snapshot.csv|reports/csv/dl_resource_grid_heatmap.csv|reports/csv/ul_resource_grid_heatmap.csv";
candidate(5) = "reports/csv/live_re_allocation_snapshot.csv|reports/csv/resource_element_ownership.csv";
candidate(6) = "reports/csv/coding_rate_matching_trace.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
candidate(7) = "air_interface/csv/dl_constellation_samples.csv|air_interface/csv/ul_constellation_samples.csv|reports/csv/mapper_input_constellation.csv";
candidate(8) = "air_interface/csv/dl_constellation_samples.csv|air_interface/csv/ul_constellation_samples.csv|reports/csv/per_layer_port_constellation.csv";
candidate(9) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=time_domain;Series=tx";
candidate(10) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=ofdm_symbol_cp_samples";
candidate(11) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=time_domain;Series=tx";
candidate(12) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=spectrum;Series=tx";
candidate(13) = "analytics/csv/contract__spectrum-psd-papr-analytics__occupied-bandwidth.csv|waveform/csv/occupied_bandwidth_emission_mask.csv|rf/csv/spectral_measurements.csv";
candidate(14) = "air_interface/csv/papr_ccdf.csv|waveform/csv/papr_ccdf.csv";
candidate(15) = "rf/csv/pa_am_am_characteristic.csv";
candidate(16) = "rf/csv/pa_am_pm_characteristic.csv";
candidate(17) = "rf/csv/evm_vs_pa_backoff.csv";
candidate(18) = "rf/csv/aclr_vs_pa_backoff.csv";
candidate(19) = "channel/csv/channel_power_delay_profile.csv|reports/csv/channel_impulse_response.csv";
candidate(20) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=time_varying_channel_impulse_response|channel/csv/time_varying_channel_impulse_response.csv";
candidate(21) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=channel_estimate_grid";
candidate(22) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=doppler_spectrum|channel/csv/doppler_spectrum.csv";
candidate(23) = "isac/csv/delay_doppler_map.csv";
candidate(24) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=runtime_channel_angles|channel/csv/angular_power_spectrum.csv|reports/csv/channel_impulse_response.csv";
candidate(25) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=channel_estimate_grid";
candidate(26) = "control/csv/csi_rs_trials.csv|mimo/csv/channel_singular_values.csv";
candidate(27) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=spatial_correlation_matrix|mimo/csv/spatial_correlation_matrix.csv";
candidate(28) = "beamforming/csv/beam_score_trace.csv|beamforming/csv/beam_pattern_codebook_gain.csv|beamforming/csv/beam_precoder_table.csv";
candidate(29) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=time_domain;Series=rx";
candidate(30) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=spectrum;Series=rx";
candidate(31) = "control/csv/synchronization_correlation_metric.csv|reports/csv/prach_correlation_trace.csv";
candidate(32) = "control/csv/timing_synchronization_table.csv|control/csv/timing_estimate_residual.csv";
candidate(33) = "control/csv/timing_synchronization_table.csv|reports/csv/cfo_reconciliation.csv|control/csv/cfo_estimate_residual.csv";
candidate(34) = "rf/csv/common_phase_error_trajectory.csv";
candidate(35) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=channel_estimate_grid";
candidate(36) = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv|air_interface/csv/channel_estimation_nmse.csv";
candidate(37) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=equalizer_weights|air_interface/csv/equalizer_weights_posteq_sinr.csv";
candidate(38) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=post_equalization_constellation";
candidate(39) = "reports/csv/evm_vs_snr_mcs_layers.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
candidate(40) = "reports/csv/llr_histograms.csv|air_interface/csv/llr_reliability_distribution.csv";
candidate(41) = "reports/csv/phy_signal_diagnostic_source.csv#Panel=decoder_ber|reports/csv/pre_post_decoder_ber.csv";
candidate(42) = "air_interface/csv/dl_measured_sinr_bler_curve.csv|air_interface/csv/ul_measured_sinr_bler_curve.csv|reports/csv/fixed_snr_sweep_curve_summary.csv|reports/csv/dl_fixed_snr_bler_curve.csv|reports/csv/ul_fixed_snr_bler_curve.csv";
candidate(43) = "reports/csv/live_decoder_summary.csv|air_interface/csv/decoder_convergence_iterations.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
candidate(44) = "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv";
candidate(45) = "air_interface/csv/lls_kpi_summary.csv|reports/csv/fixed_snr_sweep_curve_summary.csv|reports/csv/throughput_goodput.csv";
candidate(46) = "air_interface/csv/lls_kpi_summary.csv|reports/csv/spectral_efficiency.csv|reports/csv/fixed_snr_sweep_curve_summary.csv";
candidate(47) = "harq/csv/harq_round_performance.csv|air_interface/csv/harq_combining_gain.csv";
candidate(48) = "reports/csv/mcs_cqi_decision_trace_table.csv|reports/csv/link_adaptation_trials.csv";
candidate(49) = "beamforming/csv/beam_score_trace.csv|beamforming/csv/beam_precoder_table.csv|reports/csv/table_cqi_pmi_ri.csv";
candidate(50) = "reports/csv/procedure_reliability_latency.csv|reports/csv/table_latency.csv";

identity = "SnapshotID|Direction|CellID|UEIndex|RNTI|SFN|Slot|AbsoluteSlot";
required(1) = "ScenarioID|RunnerProfile|ConfigHash|RunCompleted|RuntimeTruthContractOk|ActiveDuplexMode";
required(2) = "StageOrder|StageID|RequiredForScenario|ConsumerObserved|RuntimeCallCount|MeasurementArtifact|ArtifactExists|EvidenceRows|MeasuredFiniteRows|StageOutcome|StrictPass";
required(3) = "frame|slot|symbol|direction|cell_id|ue_id|injected_timing_offset_samples|applied_timing_correction_samples|residual_timing_error_post_correction_samples|timing_estimate_status|runtime_evidence";
required(4) = "absolute_slot|sfn|slot_within_frame|direction|channel|subcarrier_start|subcarrier_count|symbol_index|port_index|re_count|cell_id|ue_id|layer_count|authority|allocation_id|coordinate_precision";
required(5) = "absolute_slot|direction|channel|component|subcarrier_start|subcarrier_count|symbol_index|port_index|re_count|allocation_id|evidence_scope";
required(6) = "Direction|Frame|Slot|TBSize_bits|NumCodeBlocks|CodeBlockLength_bits|BaseGraph|EncodedBits|RateMatchedBits|RV|CRCPass|TruthStatus";
required(7) = "RuntimeDirection|RuntimeModulation|LayerIndex|ReferenceSymbolReal|ReferenceSymbolImag|TruthStatus";
required(8) = "RuntimeDirection|RuntimeModulation|LayerIndex|TxReal|TxImag|TruthStatus";
required([9,11,12,29,30]) = identity + "|SampleIndex|IValue|QValue";
required(10) = identity + "|SampleIndex|OFDMSymbolIndex|SymbolSampleIndex|CyclicPrefixLength_samples|UsefulSymbolLength_samples|IsCyclicPrefix|OFDMWindowingSamples|IValue|QValue|GridSHA256";
required(13) = "run_id|chart_name|point_index|x_value|y_value|source_table_logical_path|source_mapping_status";
required(14) = "Direction|PAPR_dB|CCDF";
required(19) = "Direction|TapIndex|TapDelay_s|TapPower_dB|NormalizedTapPower|DelayProfile|ChannelObjectClass|Source";
required(20) = identity + "|TimeIndex|Time_s|PathIndex|PathDelay_s|RxPortIndex0Based|TxPortIndex0Based|IValue|QValue|GridSHA256";
required([21,25,35]) = identity + "|SubcarrierIndex|OFDMSymbolIndex|ResourceBlockIndex|SubcarrierInResourceBlock|RxPortIndex0Based|TxPortIndex0Based|IValue|QValue|WrappedPhase_rad|UnwrappedPhaseFrequency_rad|UnwrappedPhaseTime_rad|GridSHA256";
required(22) = identity + "|PathIndex|DopplerFrequency_Hz|PowerLinear|Power_dB|GridSHA256";
required(24) = identity + "|PathIndex|PathDelay_s|AzimuthDeparture_deg|AzimuthArrival_deg|ZenithDeparture_deg|ZenithArrival_deg|PowerLinear|Power_dB|AngleCoordinateFrame|AngleEvidenceSource|RuntimeChannelStateKey|RuntimeChannelLinkKey|RuntimeChannelSeed|RuntimeChannelReciprocityExact|RuntimeChannelReciprocityDirection|RuntimeChannelReciprocitySource|RuntimeChannelReciprocityApproximationMode|GridSHA256";
required(26) = "Frame|Slot|CellID|UEIndex|NumPorts|HestRxPorts|HestTxPorts|ConditionNumber_dB|RankEstimate|SingularValues|SpatialChannelEstimateConvention|PhysicalMeasurementStatus";
required(27) = identity + "|CorrelationDomain|MatrixRowIndex0Based|MatrixColumnIndex0Based|IValue|QValue|MagnitudeLinear|GridSHA256";
required(28) = "Direction|Frame|Slot|UEIndex|SelectedBeamIndex|BestBeamIndex|BeamCandidateCount|SelectedBeamGain_dB|BestBeamGain_dB|BeamGainGap_dB|BeamSweepEnabled|BeamCountConfigured";
required(31) = "trial_id|lag_samples|correlation_abs|threshold|noise_floor|peak_lag_samples|detection_result|false_alarm|missed_detection|truth_status";
required(32) = "frame|slot|direction|ue_id|true_timing_offset_samples|applied_timing_correction_samples|residual_timing_error_post_correction_samples|timing_estimate_status|runtime_evidence";
required(33) = "frame|slot|direction|ue_id|injected_cfo_hz|estimated_cfo_pre_correction_hz|residual_cfo_post_correction_hz|cfo_estimate_availability|runtime_evidence";
required(36) = "Direction|Frame|Slot|SNR_dB|NMSE_dB|ChannelEstimateSource|ChannelEstimateAvailable|TruthStatus";
required(37) = identity + "|EqualizerREIndex|LayerIndex|RxPortIndex0Based|IValue|QValue|EqualizerPostEqSINR_dB|EqualizerAlgorithm|GridSHA256";
required(38) = identity + "|ReferenceI|ReferenceQ|EqualizedI|EqualizedQ";
required(39) = "Direction|Frame|Slot|SNR_dB|MCS|Modulation|Layers|EVM_rms|TruthStatus";
required(40) = "Direction|MetricName|BinStart|BinEnd|Count|SampleCount|SourceArtifact|Status";
required(41) = identity + "|DecoderStage|BitErrors|BitsCompared|BER|BitComparisonSource|GridSHA256";
required(42) = "Direction|PostEqSINR_dB_BinCenter|BLER|BLER_CI_Low|BLER_CI_High|TrialCount|FailureCount|SourceArtifact";
required(43) = "run_id|direction|ue_id|frame|slot|decoder_iterations|crc_pass|codeblock_bler|cbg_bler|source_artifact";
required(44) = "Direction|Frame|Slot|TBId|HARQProcessId|HARQRound|RV|CRCPass|BitErrors|BitsCompared|TruthStatus";
required(45) = "RunId|Direction|UEIndex|Throughput_Mbps|Goodput_Mbps|OfferedThroughput_Mbps|RadioDuration_s|TrialCount|KPIReconciliationPass|SourceArtifact";
required(46) = "RunId|Direction|UEIndex|SpectralEfficiency_bps_Hz|RadioDuration_s|TrialCount|KPIReconciliationPass|SourceArtifact";
required(47) = "TotalAttempts|RetransmissionAttempts|CombiningAppliedCount|CombinedRecoveryCount|MeanLLRCombiningGain_dB|RV0Attempts|RV2Attempts|RV3Attempts|RV1Attempts|EvidenceClass|SourceArtifact|Status";
required(48) = "RunId|TrialId|UEId|CellId|Slot|CQI|CQISource|CQIDerivedMCS|SelectedMCS|SelectedMCSSource|SelectedMCSReason|HARQInfluence|SelectedSpectralEfficiency|RuntimeEvidenceStatus";
required(49) = "Direction|Frame|Slot|UEIndex|SelectedBeamIndex|BestBeamIndex|AppliedPrecoderPMI|PrecodingNumPorts|PrecodingNumLayers|ExecutionModel|Status";
required(50) = "frame|slot|direction|ue_id|cell_id|compute_latency_ms|decode_latency_ms|procedure_delay_ms|air_interface_tti_ms|air_interface_observation_ms|latency_ms|latency_value_role|latency_value_status|source_artifact_ref";

gate(15:18) = "rf.pa.enable";
gate(23) = "isac.enabled";
gate(34) = "rf.phaseNoise.enable";
gate(47) = "phy.harq.enable";
gate(48) = "phy.linkAdaptation.innerLoopFlag";

T = table((1:50).', category, names, candidate, required, gate, ...
    repmat("runtime_measurement_only_no_proxy_or_placeholder",50,1), ...
    VariableNames=["VisualID","Category","VisualName", ...
    "CandidateSourceArtifacts","RequiredValidationColumns","FeatureGate","EvidencePolicy"]);
end

function [enabled, state] = localFeatureState(cfg, path)
path = string(path);
if path == "always"
    enabled = true;
    state = "required";
    return;
end
value = sixgr.util.structGet(cfg, path, []);
if isempty(value)
    enabled = true;
    state = "unknown";
elseif (islogical(value) || isnumeric(value)) && isscalar(value)
    enabled = logical(value);
    if enabled
        state = "enabled";
    else
        state = "disabled";
    end
else
    enabled = true;
    state = "unknown";
end
end

function [resolved, rowCount, missingColumns, validated] = localResolveSource(runFolder, candidateText, requiredText)
resolved = "";
rowCount = 0;
missingColumns = "";
validated = false;
candidates = split(string(candidateText), "|");
for i = 1:numel(candidates)
    token = strtrim(candidates(i));
    if strlength(token) == 0
        continue;
    end
    pieces = split(token, "#");
    relativePath = pieces(1);
    fullPath = fullfile(runFolder, replace(relativePath, "/", filesep));
    if exist(fullPath, "file") ~= 2
        continue;
    end
    try
        T = sixgr.util.csvReadTable(fullPath, "TextType", "string");
    catch
        continue;
    end
    if numel(pieces) > 1
        T = localApplySelector(T, pieces(2));
    end
    if isempty(T)
        continue;
    end
    resolved = relativePath;
    rowCount = height(T);
    required = split(string(requiredText), "|");
    required = required(strlength(strtrim(required)) > 0);
    present = string(T.Properties.VariableNames);
    missing = required(~ismember(lower(required), lower(present)));
    missingColumns = strjoin(missing, "|");
    validated = ~isempty(required) && isempty(missing);
    return;
end
end

function T = localApplySelector(T, selector)
clauses = split(string(selector), ";");
for clause = reshape(clauses, 1, [])
    pair = split(clause, "=");
    if numel(pair) ~= 2
        T = T([],:);
        return;
    end
    field = strtrim(pair(1));
    value = strtrim(pair(2));
    names = string(T.Properties.VariableNames);
    idx = find(lower(names) == lower(field), 1);
    if isempty(idx)
        T = T([],:);
        return;
    end
    T = T(lower(strtrim(string(T.(char(names(idx)))))) == lower(value), :);
end
end
