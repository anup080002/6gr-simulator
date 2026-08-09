function ok = testPRACHArtifactSchemas()
%TESTPRACHARTIFACTSCHEMAS Strict PRACH artifact schema and file guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult("WriteArtifacts", true);
runFolder = b.RunFolder;

requiredCsv = [
    "control/csv/prach_config_strict.csv"
    "control/csv/prach_strict_trials.csv"
    "control/csv/prach_detection_candidates.csv"
    "control/csv/prach_restricted_set_mapping.csv"
    "control/csv/prach_root_sequence_budget.csv"
    "control/csv/prach_zcz_cyclic_shift_mapping.csv"
    "control/csv/prach_missed_detection_sweep.csv"
    "control/csv/prach_false_alarm_sweep.csv"
    "control/csv/prach_timing_offset_sweep.csv"
    "control/csv/prach_frequency_offset_sweep.csv"
    "control/csv/prach_collision_trials.csv"
    "control/csv/prach_multi_occasion_trials.csv"
    "control/csv/prach_negative_trials.csv"
    "control/csv/prach_oracle_guard.csv"];
for ii = 1:numel(requiredCsv)
    pathValue = fullfile(runFolder, strrep(requiredCsv(ii), "/", filesep));
    assert(exist(pathValue, "file") == 2, "Missing strict PRACH CSV artifact: " + requiredCsv(ii));
    T = readtable(pathValue, "FileType", "text", "Delimiter", ",", ...
        "ReadVariableNames", true, "VariableNamingRule", "preserve");
    assert(height(T) > 0, "Strict PRACH CSV artifact must not be empty: " + requiredCsv(ii));
    names = string(T.Properties.VariableNames);
    assert(numel(unique(lower(names))) == numel(names), ...
        "Strict PRACH CSV artifact contains case-insensitive duplicate headers: " + requiredCsv(ii));
end

trialT = readtable(fullfile(runFolder, "control", "csv", "prach_strict_trials.csv"), ...
    "FileType", "text", "Delimiter", ",", "ReadVariableNames", true, "VariableNamingRule", "preserve");
assert(all(ismember(["RunId","TrialType","PreambleIndexTx","PreambleIndexDetected", ...
    "ConfigHash","WaveformHash","ProxyUsed","Skipped","ToolboxMissing","UsedOracleFields","StrictOk"], ...
    string(trialT.Properties.VariableNames))), ...
    "Strict PRACH trials CSV must include the canonical evidence/provenance columns.");

requiredJson = [
    "reports/json/prach_config_binding.json"
    "reports/json/prach_detection_summary.json"
    "reports/json/prach_conformance_summary.json"
    "reports/json/prach_false_alarm_summary.json"
    "reports/json/prach_missed_detection_summary.json"
    "reports/json/prach_restricted_set_summary.json"
    "reports/json/prach_toolbox_capabilities.json"];
for ii = 1:numel(requiredJson)
    assert(exist(fullfile(runFolder, strrep(requiredJson(ii), "/", filesep)), "file") == 2, ...
        "Missing strict PRACH JSON artifact: " + requiredJson(ii));
end

figDir = fullfile(runFolder, "reports", "figures");
normalFigures = dir(fullfile(figDir, "prach_*.*"));
assert(~isempty(normalFigures), "Strict PRACH artifact writer must produce measured PRACH figures.");
unavailable = dir(fullfile(figDir, "*unavailable*"));
assert(isempty(unavailable), "AUD-PRACH-001 strict artifacts must not use unavailable-card figures.");

manifestPath = fullfile(runFolder, "control", "csv", "prach_strict_artifact_manifest.csv");
manifestT = readtable(manifestPath, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "VariableNamingRule", "preserve");
assert(height(manifestT) >= numel(requiredCsv) + numel(requiredJson), ...
    "Strict PRACH artifact manifest must enumerate CSV and JSON artifacts.");
assert(all(ismember(["ArtifactId","FilePath","MimeType","Kind","RowCount","SHA256","ByteCount","ProducerModule"], ...
    string(manifestT.Properties.VariableNames))), ...
    "Strict PRACH artifact manifest must include path, hash, byte-count, row-count, and producer metadata.");

lineageT = readtable(fullfile(runFolder, "control", "csv", ...
    "prach_plot_lineage.csv"), "VariableNamingRule", "preserve");
assert(all(string(lineageT.Status) == "pass") && ...
    all(strlength(string(lineageT.SourceCSV_SHA256)) == 64) && ...
    all(strlength(string(lineageT.ImageSHA256)) == 64), ...
    "Strict PRACH PNG lineage must bind finalized CSV bytes to raster hashes.");

ok = true;
end
