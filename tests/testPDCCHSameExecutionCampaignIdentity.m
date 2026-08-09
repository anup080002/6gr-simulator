function ok = testPDCCHSameExecutionCampaignIdentity()
%TESTPDCCHSAMEEXECUTIONCAMPAIGNIDENTITY Bind actual PDCCH campaign rows.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(repoRoot, "configs", "lls", ...
    "lls_pdcch_strict_mini_anchor.yaml");
runFolder = string(tempname);
mkdir(runFolder);
cleanup = onCleanup(@() localCleanup(runFolder)); %#ok<NASGU>
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
scenarioHash = lower(string(scfg.ConfigHash));
executionID = "pdcch_same_execution_identity_test";
runID = "pdcch_same_execution_run";

result = sixgr.phy.pdcch.runStrictPDCCHValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", runID, ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "ExecutionID", executionID, ...
    "ScenarioConfigHash", scenarioHash, ...
    "EvidenceScope", "same_execution_campaign", ...
    "WriteArtifacts", false);

T = result.ArtifactTables.pdcch_false_alarm_sweep;
required = ["RunId","ExecutionID","ScenarioID","ScenarioConfigHash", ...
    "EvidenceScope","SameScenarioInPathEligible","ComponentConfigHash"];
assert(all(ismember(lower(required), ...
    lower(string(T.Properties.VariableNames)))));
assert(all(string(T.RunId) == runID));
assert(all(string(T.ExecutionID) == executionID));
assert(all(string(T.ScenarioID) == string(scfg.ScenarioID)));
assert(all(lower(string(T.ScenarioConfigHash)) == scenarioHash));
assert(all(string(T.EvidenceScope) == "same_execution_campaign"));
assert(all(~logical(T.SameScenarioInPathEligible)));
assert(all(strlength(string(T.ComponentConfigHash)) == 64));
assert(~logical(result.StatisticallyQualified), ...
    "The deliberately tiny mini campaign must not be promoted to qualified truth.");
ok = true;
fprintf("PASS testPDCCHSameExecutionCampaignIdentity\n");
end

function localCleanup(runFolder)
if isfolder(runFolder)
    rmdir(runFolder, "s");
end
end
