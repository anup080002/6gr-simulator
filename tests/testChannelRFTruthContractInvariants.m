function testChannelRFTruthContractInvariants
bundle = channelRFStrictAnchorResult("WriteArtifacts", true);
layout = sixgr.report.resultLayout(bundle.RunFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), table( ...
    string("lls_channel_rf_strict_mini_anchor"), true, true, ...
    'VariableNames', {'ScenarioID','RunCompleted','ResultOk'}));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "config_roundtrip_verification.csv"), table( ...
    string("channel_rf"), string("consistent"), ...
    'VariableNames', {'Check','ConsistencyStatus'}));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "browser_runtime_db_consistency.csv"), table( ...
    string("channel_rf"), string("consistent"), ...
    'VariableNames', {'Check','ConsistencyStatus'}));
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(bundle.RunFolder, bundle.ScenarioConfig, bundle.Config);
assert(verdict.Ok, "Strict Channel/RF truth contract should pass with complete evidence.");

badPath = fullfile(bundle.RunFolder, "channel", "csv", "channel_configured_vs_applied.csv");
T = readtable(badPath, "TextType", "string");
T.StrictOk(1) = false;
writetable(T, badPath);
verdictBad = sixgr.truth.evaluateLLSRuntimeTruthContract(bundle.RunFolder, bundle.ScenarioConfig, bundle.Config);
assert(~verdictBad.Ok, "Strict Channel/RF truth contract must fail when positive evidence is invalidated.");
end
