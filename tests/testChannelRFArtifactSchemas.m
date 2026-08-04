function testChannelRFArtifactSchemas
bundle = channelRFStrictAnchorResult("WriteArtifacts", true);
runFolder = bundle.RunFolder;
required = [
    "channel/csv/channel_rf_config_strict.csv"
    "channel/csv/link_geometry.csv"
    "channel/csv/large_scale_parameters.csv"
    "channel/csv/channel_realizations.csv"
    "channel/csv/channel_configured_vs_applied.csv"
    "reports/csv/channel_rf_configured_applied.csv"
    "reports/csv/channel_rf_cdlc_realization_table.csv"
    "reports/csv/channel_rf_per_ue_realization.csv"
    "reports/csv/channel_rf_strict_summary.csv"
    "reports/csv/channel_rf_negative_trials.csv"
    "rf/csv/rf_impairment_chain.csv"
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
end
