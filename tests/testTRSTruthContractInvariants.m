function ok = testTRSTruthContractInvariants()
setup6GRSimToolkit("Verbose", false);
b = trsStrictAnchorResult("WriteArtifacts", true, "Refresh", true);
refDir = fullfile(b.RunFolder, "reference_signals", "csv");
scfg = sixgr.lls6g.config.loadScenarioConfig(b.ScenarioPath);
localWriteMinimalTruthContractMetadata(b.RunFolder);
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(b.RunFolder, scfg, b.InternalConfig);
assert(logical(verdict.CheckDetails.TRS.TRSStrictOk), "Truth contract must accept complete strict TRS artifacts.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
mkdir(fullfile(tmp, "reference_signals", "csv"));
copyfile(refDir, fullfile(tmp, "reference_signals", "csv"));
localWriteMinimalTruthContractMetadata(tmp);
badPath = fullfile(tmp, "reference_signals", "csv", "trs_trials.csv");
T = readtable(badPath, "TextType", "string");
T.TRSTimingEstimateAvailable(:) = false;
writetable(T, badPath);
bad = sixgr.truth.evaluateLLSRuntimeTruthContract(tmp, scfg, b.InternalConfig);
assert(~logical(bad.Ok), "Truth contract must fail if strict TRS timing availability is removed.");
ok = true;
end

function localWriteMinimalTruthContractMetadata(runFolder)
csvDir = fullfile(runFolder, "reports", "csv");
if exist(csvDir, "dir") ~= 7
    mkdir(csvDir);
end
writetable(table("lls_trs_strict_mini_anchor", true, 'VariableNames', {'ScenarioID','ResultOk'}), ...
    fullfile(csvDir, "scenario_summary.csv"));
writetable(table(true, 'VariableNames', {'RoundtripOk'}), ...
    fullfile(csvDir, "config_roundtrip_verification.csv"));
writetable(table(true, 'VariableNames', {'Consistent'}), ...
    fullfile(csvDir, "browser_runtime_db_consistency.csv"));
end
