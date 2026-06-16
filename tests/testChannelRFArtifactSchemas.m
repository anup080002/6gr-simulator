function testChannelRFArtifactSchemas
bundle = channelRFStrictAnchorResult("WriteArtifacts", true);
runFolder = bundle.RunFolder;
required = [
    "channel/csv/channel_rf_config_strict.csv"
    "channel/csv/link_geometry.csv"
    "channel/csv/large_scale_parameters.csv"
    "channel/csv/channel_realizations.csv"
    "channel/csv/channel_configured_vs_applied.csv"
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
end
