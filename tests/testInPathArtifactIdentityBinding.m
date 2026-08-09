function testInPathArtifactIdentityBinding()
%TESTINPATHARTIFACTIDENTITYBINDING Preserve component and execution hashes.

identity = struct( ...
    "RunID", "run_001", ...
    "ExecutionID", "execution_001", ...
    "ScenarioID", "scenario_001", ...
    "ConfigHash", string(repmat('a', 1, 64)));
componentHash = string(repmat('b', 1, 64));
tables = struct("trials", table([1;2], repmat(componentHash, 2, 1), ...
    'VariableNames', {'TrialId','ConfigHash'}));
bound = sixgr.runtime.bindInPathArtifactIdentity(tables, identity);
T = bound.trials;
assert(all(T.RunID == identity.RunID));
assert(all(T.ExecutionID == identity.ExecutionID));
assert(all(T.ScenarioID == identity.ScenarioID));
assert(all(T.ScenarioConfigHash == identity.ConfigHash));
assert(all(T.ComponentConfigHash == componentHash));
assert(all(T.ConfigHash == componentHash));
assert(all(T.EvidenceScope == "in_path"));
assert(all(T.SameScenarioInPathEligible));

campaign = sixgr.runtime.bindInPathArtifactIdentity( ...
    tables, identity, "same_execution_campaign");
assert(all(campaign.trials.EvidenceScope == ...
    "same_execution_campaign"));
assert(all(~campaign.trials.SameScenarioInPathEligible));

legacy = struct("trials", table([1;2], repmat("run_001", 2, 1), ...
    'VariableNames', {'TrialId','RunId'}));
legacyBound = sixgr.runtime.bindInPathArtifactIdentity(legacy, identity);
legacyNames = string(legacyBound.trials.Properties.VariableNames);
assert(nnz(strcmpi(legacyNames, "RunID")) == 1 && ...
    ismember("RunId", legacyNames) && ~ismember("RunID", legacyNames), ...
    "The binder must preserve RunId without appending a duplicate RunID column.");
assert(all(legacyBound.trials.RunId == identity.RunID));

duplicate = T;
duplicate.RunId = duplicate.RunID;
assertThrows(@() sixgr.runtime.bindInPathArtifactIdentity(duplicate, identity), ...
    "sixgr:runtime:DuplicateInPathIdentityColumn");

bad = T;
bad.ExecutionID(2) = "wrong_execution";
assertThrows(@() sixgr.runtime.bindInPathArtifactIdentity(bad, identity), ...
    "sixgr:runtime:InPathEvidenceIdentityMismatch");
assertThrows(@() sixgr.runtime.bindInPathArtifactIdentity( ...
    tables, identity, "proxy"), ...
    "sixgr:runtime:InvalidRuntimeEvidenceScope");
fprintf("PASS testInPathArtifactIdentityBinding\n");
end

function assertThrows(fn, identifier)
threw = false;
try
    fn();
catch cause
    threw = true;
    assert(string(cause.identifier) == string(identifier));
end
assert(threw, "Expected %s.", identifier);
end
