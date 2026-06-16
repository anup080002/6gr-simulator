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
assert(exist(fullfile(figDir, "pdcch_coreset_resource_grid.png"), "file") == 2, ...
    "Strict PDCCH must export measured figure artifacts.");
assert(isempty(dir(fullfile(figDir, "*unavailable*"))), ...
    "AUD-PDCCH-001 strict artifacts must not use unavailable-card figures.");
manifestPath = fullfile(runFolder, "control", "csv", "pdcch_strict_artifact_manifest.csv");
manifestT = readtable(manifestPath, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "VariableNamingRule", "preserve");
assert(height(manifestT) >= numel(requiredCsv), "Strict PDCCH manifest must enumerate required artifacts.");
ok = true;
end
