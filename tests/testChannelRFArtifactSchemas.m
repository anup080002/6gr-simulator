function testChannelRFArtifactSchemas
bundle = channelRFStrictAnchorResult("WriteArtifacts", true);
runFolder = bundle.RunFolder;
required = [
    "channel/csv/channel_rf_config_strict.csv"
    "channel/csv/link_geometry.csv"
    "channel/csv/large_scale_parameters.csv"
    "channel/csv/channel_realizations.csv"
    "channel/csv/channel_configured_vs_applied.csv"
    "channel/csv/channel_rf_plot_lineage.csv"
    "channel/image/channel_configured_vs_applied.png"
    "reports/csv/channel_rf_configured_applied.csv"
    "reports/csv/channel_rf_cdlc_realization_table.csv"
    "reports/csv/channel_rf_per_ue_realization.csv"
    "reports/csv/channel_rf_strict_summary.csv"
    "reports/csv/channel_rf_negative_trials.csv"
    "rf/csv/rf_impairment_chain.csv"
    "reports/image/rf_impairment_chain.png"
    "rf/csv/channel_rf_negative_trials.csv"
    "interference/csv/interference_topology.csv"
    "air_interface/csv/downstream_channel_references.csv"
    "reports/json/channel_rf_toolbox_capabilities.json"
    ];
for i = 1:numel(required)
    p = fullfile(runFolder, required(i));
    assert(isfile(p), "Missing Channel/RF artifact: " + required(i));
end
T = readtable(fullfile(runFolder, "channel", "csv", "channel_configured_vs_applied.csv"), "TextType", "string");
assert(height(T) > 0 && all(ismember(["TrialId","StrictOk","ExpectedOk","TruthStatus"], string(T.Properties.VariableNames))), ...
    "Configured-vs-applied artifact schema is incomplete.");
strictCfg = readtable(fullfile(runFolder, "channel", "csv", ...
    "channel_rf_config_strict.csv"), "TextType", "string");
assert(height(strictCfg) == 1 && logical(strictCfg.ConfigValidationOk) && ...
    logical(strictCfg.PathlossEnabled) && logical(strictCfg.O2IConfigured), ...
    "Strict O2I validation must atomically enable its pathloss dependency.");
largeScale = readtable(fullfile(runFolder, "channel", "csv", ...
    "large_scale_parameters.csv"), "TextType", "string");
assert(any(logical(largeScale.O2IState) & ...
    double(largeScale.O2IPenetrationLossDbApplied) > 0), ...
    "The strict indoor link must apply a real positive O2I penetration loss.");
R = readtable(fullfile(runFolder, "reports", "csv", "channel_rf_configured_applied.csv"), "TextType", "string");
assert(height(R) > 0 && all(logical(R.ExpectedOk)) && all(ismember(["ConfiguredAppliedOk","StrictOk","TruthStatus"], string(R.Properties.VariableNames))), ...
    "Report-level Channel/RF configured-applied evidence must contain positive runtime rows with explicit ConfiguredAppliedOk.");
cdl = readtable(fullfile(runFolder, "reports", "csv", "channel_rf_cdlc_realization_table.csv"), "TextType", "string");
assert(height(cdl) == 24 && all(ismember(["PathIndex","Delay_s","AveragePathGain_dB","AngleAoD_deg","AngleAoA_deg"], string(cdl.Properties.VariableNames))), ...
    "Report-level CDL-C realization table must expose the 24-path runtime channel profile.");
visualT = sixgr.visual.verifyVisualArtifacts(runFolder, table());
channelVisualMask = ismember(string(visualT.ArtifactPath), [ ...
    "channel/image/channel_configured_vs_applied.png", ...
    "reports/image/rf_impairment_chain.png"]);
assert(sum(channelVisualMask) == 2 && all(logical(visualT.IntegrityOk(channelVisualMask))), ...
    "Channel/RF PNGs must retain exact source-CSV and byte-hash lineage.");
manifestPath = fullfile(runFolder, "channel", "csv", ...
    "channel_rf_strict_artifact_manifest.csv");
manifest = readtable(manifestPath, "TextType", "string", ...
    "VariableNamingRule", "preserve");
assert(height(manifest) > 0 && all(logical(manifest.Exists)), ...
    "Channel/RF integrity manifest must enumerate only existing artifacts.");
assert(~any(strcmpi(string(manifest.FilePath), string(manifestPath))), ...
    "Channel/RF integrity manifest must not contain a self-reference row.");
for row = 1:height(manifest)
    assert(string(manifest.SHA256(row)) == localFileSHA256(manifest.FilePath(row)), ...
        "Channel/RF manifest hash mismatch for %s.", manifest.FilePath(row));
    info = dir(manifest.FilePath(row));
    assert(double(manifest.ByteCount(row)) == double(info(1).bytes), ...
        "Channel/RF manifest byte-count mismatch for %s.", manifest.FilePath(row));
end
end

function hash = localFileSHA256(pathValue)
fid = fopen(char(pathValue), "r");
assert(fid >= 0, "Unable to read Channel/RF manifest artifact.");
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid, inf, "*uint8")));
end
