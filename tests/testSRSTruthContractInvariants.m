function ok = testSRSTruthContractInvariants()
setup6GRSimToolkit("Verbose", false);
b = srsStrictAnchorResult("WriteArtifacts", true);
scenarioCfg = sixgr.lls6g.config.loadScenarioConfig(b.ScenarioPath);
localWriteMinimalTruthContractMetadata(b.RunFolder);
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(b.RunFolder, scenarioCfg, b.InternalConfig);
assert(logical(verdict.Ok), "Truth contract must accept complete strict SRS artifacts.");
assert(logical(verdict.CheckDetails.SRS.SRSStrictOk), "SRS strict evidence stats must pass.");
T = b.Result.ArtifactTables.srs_trials;
passing = T(logical(T.StrictOk), :);
assert(all(logical(passing.DetectionAttempted)) && all(logical(passing.ChannelEstimateAttempted)) && ...
    all(logical(passing.SRSChannelEstimateAvailable)), ...
    "No strict SRS pass row may omit detection/channel-estimation evidence.");
assert(~any(logical(passing.FullCarrierSoundingRequired) & string(passing.BandwidthCoverageStatus) ~= "full_carrier"), ...
    "No strict full-carrier SRS pass row may use partial-band evidence.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
mkdir(fullfile(tmp, "reference_signals", "csv"));
copyfile(fullfile(b.RunFolder, "reference_signals", "csv"), fullfile(tmp, "reference_signals", "csv"));
mkdir(fullfile(tmp, "air_interface", "csv"));
copyfile(fullfile(b.RunFolder, "air_interface", "csv", "srs_trials.csv"), fullfile(tmp, "air_interface", "csv", "srs_trials.csv"));
localWriteMinimalTruthContractMetadata(tmp);
badPath = fullfile(tmp, "reference_signals", "csv", "srs_trials.csv");
badT = readtable(badPath, "TextType", "string");
badT.SRSChannelEstimateAvailable(:) = false;
writetable(badT, badPath);
bad = sixgr.truth.evaluateLLSRuntimeTruthContract(tmp, scenarioCfg, b.InternalConfig);
assert(~logical(bad.Ok), "Truth contract must fail if strict SRS channel availability is removed.");
ok = true;
end

function localWriteMinimalTruthContractMetadata(runFolder)
csvDir = fullfile(runFolder, "reports", "csv");
if exist(csvDir, "dir") ~= 7
    mkdir(csvDir);
end
writetable(table("lls_srs_strict_mini_anchor", true, 'VariableNames', {'ScenarioID','ResultOk'}), ...
    fullfile(csvDir, "scenario_summary.csv"));
writetable(table("consistent", 'VariableNames', {'ConsistencyStatus'}), ...
    fullfile(csvDir, "config_roundtrip_verification.csv"));
writetable(table("consistent", 'VariableNames', {'ConsistencyStatus'}), ...
    fullfile(csvDir, "browser_runtime_db_consistency.csv"));
end
