function ok = testSRSArtifactSchemas()
setup6GRSimToolkit("Verbose", false);
b = srsStrictAnchorResult("WriteArtifacts", true);
root = b.RunFolder;
required = [
    "reference_signals/csv/srs_config_strict.csv"
    "reference_signals/csv/srs_resource_sets.csv"
    "reference_signals/csv/srs_resources.csv"
    "reference_signals/csv/srs_resource_mapping.csv"
    "reference_signals/csv/srs_tx_waveform.csv"
    "reference_signals/csv/srs_rx_extraction.csv"
    "reference_signals/csv/srs_detection_metrics.csv"
    "reference_signals/csv/srs_channel_estimation.csv"
    "reference_signals/csv/srs_channel_estimation_per_prb.csv"
    "reference_signals/csv/srs_channel_estimation_per_port.csv"
    "reference_signals/csv/srs_coverage.csv"
    "reference_signals/csv/srs_trigger_events.csv"
    "reference_signals/csv/srs_negative_trials.csv"
    "reference_signals/csv/srs_low_snr_sweep.csv"
    "reference_signals/csv/srs_timing_offset_sweep.csv"
    "reference_signals/csv/srs_multi_ue_trials.csv"
    "reference_signals/csv/srs_oracle_guard.csv"
    "air_interface/csv/srs_trials.csv"
    "control/csv/srs_config_strict.csv"
    "control/csv/srs_trials.csv"
    "control/csv/srs_measurement_table.csv"
    "reports/csv/srs_config_strict.csv"
    "reports/csv/srs_trials.csv"
    "reports/csv/srs_measurement_table.csv"
    "reports/json/srs_config_binding.json"
    "reports/json/srs_detection_summary.json"
    "reports/json/srs_coverage_summary.json"
    "reports/json/srs_toolbox_capabilities.json"
    "reports/text/srs_config_dump.txt"
    "reports/text/srs_trial_hashes.txt"
    "reports/binary/srs_positive_grid.bin"
    "reports/binary/srs_no_signal_grid.bin"
    "reports/figures/srs_resource_grid.png"
    "reports/figures/srs_strict_flow.png"];
for ii = 1:numel(required)
    assert(exist(fullfile(root, required(ii)), "file") == 2, "Missing SRS artifact: %s", required(ii));
end
T = readtable(fullfile(root, "reference_signals", "csv", "srs_trials.csv"), "TextType", "string");
assert(all(ismember(["DetectionAttempted","ResourceExtractionAttempted","SRSChannelEstimateAvailable","FullCarrierClaimValid"], ...
    string(T.Properties.VariableNames))), "SRS trial schema must carry strict attempted/available/coverage columns.");
det = readtable(fullfile(root, "reference_signals", "csv", "srs_detection_metrics.csv"), "TextType", "string");
ch = readtable(fullfile(root, "reference_signals", "csv", "srs_channel_estimation.csv"), "TextType", "string");
assert(all(ismember(["PerREEstimateAvailable","PerPRBEstimateAvailable","PerPortEstimateAvailable","NumPRBEstimates"], ...
    string(ch.Properties.VariableNames))), "SRS channel-estimation schema must expose measured per-RE/per-PRB/per-port columns.");
assert(height(det) >= height(T) && height(ch) >= height(T), ...
    "SRS strict evidence must include detection and channel-estimation rows for every emitted trial row.");
assert(all(ismember(["NMSEReferenceSource","RIEstimate","TPMIEstimate","RISource","TPMISource"], ...
    string(ch.Properties.VariableNames))), ...
    "SRS channel-estimation schema must expose NMSE truth source plus RI/TPMI derivation fields.");
prb = readtable(fullfile(root, "reference_signals", "csv", "srs_channel_estimation_per_prb.csv"), "TextType", "string");
assert(height(prb) > 0 && all(ismember(["PRB","Port","EstimateI","EstimateQ","EstimateAvailable"], string(prb.Properties.VariableNames))), ...
    "SRS per-PRB estimator artifact must expose measured PRB/port channel estimates.");
figs = dir(fullfile(root, "reports", "figures", "srs_*_unavailable.png"));
assert(isempty(figs), "Strict SRS figures must not be unavailable cards.");
ok = true;
end
