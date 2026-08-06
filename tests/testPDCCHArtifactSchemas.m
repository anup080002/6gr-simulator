function ok = testPDCCHArtifactSchemas()
setup6GRSimToolkit("Verbose", false);
b = pdcchStrictAnchorResult("WriteArtifacts", true);
runFolder = b.RunFolder;
requiredCsv = [
    "control/csv/pdcch_config_strict.csv"
    "control/csv/pdcch_trials.csv"
    "control/csv/pdcch_candidates.csv"
    "control/csv/pdcch_dci_fields.csv"
    "control/csv/pdcch_grant_validation.csv"
    "control/csv/pdcch_wrong_rnti_trials.csv"
    "control/csv/pdcch_no_signal_trials.csv"
    "control/csv/pdcch_corruption_trials.csv"
    "control/csv/pdcch_false_alarm_sweep.csv"
    "control/csv/pdcch_low_snr_sweep.csv"
    "control/csv/pdcch_oracle_guard.csv"
    "air_interface/csv/pdcch_trials.csv"];
for ii = 1:numel(requiredCsv)
    p = fullfile(runFolder, strrep(requiredCsv(ii), "/", filesep));
    assert(exist(p, "file") == 2, "Missing strict PDCCH CSV artifact: " + requiredCsv(ii));
    T = readtable(p, "FileType", "text", "Delimiter", ",", ...
        "ReadVariableNames", true, "VariableNamingRule", "preserve");
    assert(height(T) > 0, "Strict PDCCH CSV artifact must not be empty: " + requiredCsv(ii));
end
figDir = fullfile(runFolder, "reports", "figures");
requiredFigures = [
    "pdcch_coreset_resource_grid.png"
    "pdcch_candidate_metrics.png"
    "pdcch_wrong_rnti_rejections.png"
    "pdcch_false_alarm_probability.png"
    "pdcch_low_snr_detection_probability.png"
    "pdcch_decode_flow.png"
    "pdcch_dci_to_grant_flow.png"];
for ii = 1:numel(requiredFigures)
    assert(exist(fullfile(figDir, requiredFigures(ii)), "file") == 2, ...
        "Strict PDCCH must atomically export every measured figure artifact: " + requiredFigures(ii));
end
assert(isempty(dir(fullfile(figDir, "*unavailable*"))), ...
    "AUD-PDCCH-001 strict artifacts must not use unavailable-card figures.");
lineagePath = fullfile(runFolder, "control", "csv", "pdcch_plot_lineage.csv");
assert(exist(lineagePath, "file") == 2, ...
    "Strict PDCCH figure publication requires source-hash lineage.");
lineageT = readtable(lineagePath, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "VariableNamingRule", "preserve");
assert(height(lineageT) == numel(requiredFigures) && all(string(lineageT.Status) == "pass"), ...
    "Strict PDCCH figure lineage must cover the complete atomic figure set.");
manifestPath = fullfile(runFolder, "control", "csv", "pdcch_strict_artifact_manifest.csv");
manifestT = readtable(manifestPath, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "VariableNamingRule", "preserve");
assert(height(manifestT) >= numel(requiredCsv), "Strict PDCCH manifest must enumerate required artifacts.");
ok = true;
end
