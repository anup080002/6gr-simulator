function ok = testTRSArtifactSchemas()
setup6GRSimToolkit("Verbose", false);
b = trsStrictAnchorResult("WriteArtifacts", true);
root = b.RunFolder;
required = [
    "reference_signals/csv/trs_config_strict.csv"
    "reference_signals/csv/trs_trials.csv"
    "reference_signals/csv/trs_resource_mapping.csv"
    "reference_signals/csv/trs_resource_grid_power.csv"
    "reference_signals/csv/trs_plot_lineage.csv"
    "reference_signals/csv/trs_detection_metrics.csv"
    "reference_signals/csv/trs_timing_tracking.csv"
    "reference_signals/csv/trs_frequency_tracking.csv"
    "reference_signals/csv/trs_channel_estimation.csv"
    "reference_signals/csv/trs_coverage.csv"
    "reference_signals/csv/trs_negative_trials.csv"
    "reference_signals/csv/trs_oracle_guard.csv"
    "air_interface/csv/trs_trials.csv"
    "control/csv/trs_config_strict.csv"
    "control/csv/trs_trials.csv"
    "reports/csv/trs_config_strict.csv"
    "reports/csv/trs_trials.csv"
    "reports/json/trs_config_binding.json"
    "reports/json/trs_detection_summary.json"
    "reports/json/trs_tracking_summary.json"
    "reports/json/trs_toolbox_capabilities.json"
    "reports/text/trs_config_dump.txt"
    "reports/text/trs_trial_hashes.txt"
    "reports/binary/trs_positive_grid.bin"
    "reports/binary/trs_no_signal_grid.bin"
    "reports/figures/trs_resource_grid.png"
    "reports/figures/trs_tracking_flow.png"];
for ii = 1:numel(required)
    assert(exist(fullfile(root, required(ii)), "file") == 2, "Missing TRS artifact: %s", required(ii));
end
T = readtable(fullfile(root, "reference_signals", "csv", "trs_trials.csv"), "TextType", "string");
assert(all(ismember(["DetectionAttempted","TRSTimingEstimateAvailable","TRSCFOEstimateAvailable","TRSChannelEstimateAvailable"], ...
    string(T.Properties.VariableNames))), "TRS trial schema must carry strict attempted/available columns.");
lineage = readtable(fullfile(root, "reference_signals", "csv", "trs_plot_lineage.csv"), "TextType", "string");
assert(height(lineage) == 8 && all(lineage.Status == "pass") && all(lineage.SourceExists), ...
    "Every strict TRS PNG must have passing exact-source lineage.");
ok = true;
end
