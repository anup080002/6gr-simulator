function ok = testResumeConfigurationIdentityGuard()
%TESTRESUMECONFIGURATIONIDENTITYGUARD Resume cannot rebind persisted truth.

root = string(tempname);
cleanup = onCleanup(@()localCleanup(root)); %#ok<NASGU>
layout = sixgr.report.resultLayout(root);
if exist(layout.AirInterfaceCSVDir, "dir") ~= 7
    mkdir(layout.AirInterfaceCSVDir);
end
scenarioID = "resume_identity_fixture";
configHash = string(repmat('a', 1, 64));
T = table(["DL";"DL"], repmat(scenarioID, 2, 1), ...
    repmat(configHash, 2, 1), ...
    'VariableNames', {'Direction','ScenarioID','ConfigHash'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "dl_pdsch_trials.csv"), T);

evidence = sixgr.truth.assertResumeConfigurationIdentity(root, ...
    scenarioID, configHash);
assert(logical(evidence.Ok) && height(evidence.Table) == 1 && ...
    string(evidence.Table.Status(1)) == "exact_match", ...
    "Exact persisted configuration identity must be accepted.");

localAssertIdentifier(@()sixgr.truth.assertResumeConfigurationIdentity( ...
    root, "different_scenario", configHash), ...
    "sixgr:truth:resume:ScenarioIdentityMismatch");
localAssertIdentifier(@()sixgr.truth.assertResumeConfigurationIdentity( ...
    root, scenarioID, string(repmat('b', 1, 64))), ...
    "sixgr:truth:resume:ConfigurationHashMismatch");

emptyRoot = string(tempname);
mkdir(emptyRoot);
emptyCleanup = onCleanup(@()localCleanup(emptyRoot)); %#ok<NASGU>
localAssertIdentifier(@()sixgr.truth.assertResumeConfigurationIdentity( ...
    emptyRoot, scenarioID, configHash), ...
    "sixgr:truth:resume:MissingConfigurationIdentityEvidence");
ok = true;
end

function localAssertIdentifier(fcn, expected)
caught = false;
try
    fcn();
catch ME
    caught = true;
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, observed %s.", expected, ME.identifier);
end
assert(caught, "Expected typed error %s.", expected);
end

function localCleanup(pathValue)
if exist(char(pathValue), "dir") == 7
    rmdir(char(pathValue), "s");
end
end
