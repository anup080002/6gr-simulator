function testStrictComponentExecutionPolicy()
%TESTSTRICTCOMPONENTEXECUTIONPOLICY In-path evidence is explicit and bound.

root = string(tempname);
cleanup = onCleanup(@() localCleanup(root)); %#ok<NASGU>
mkdir(root);
hash = string(repmat('a', 1, 64));
cfg = struct();
cfg.run = struct("runTag", "run_policy_test", ...
    "executionID", "execution_policy_test");
cfg.meta = struct("configHash", hash);
cfg.validation.strict_component_evidence = struct( ...
    "enabled", true, ...
    "execution_scope", "in_path", ...
    "required_components", {{"prach","pdcch","srs"}});
scfg = struct("ScenarioID", "policy_test", "ConfigHash", hash);

prach = sixgr.lls6g.runners.resolveStrictComponentExecutionPolicy( ...
    scfg, cfg, "prach", root);
assert(prach.ExecutionScope == "in_path");
assert(prach.SameScenarioInPathEligible);
assert(prach.ArtifactRoot == root);
assert(prach.RunID == "run_policy_test");
assert(prach.ExecutionID == "execution_policy_test");
assert(prach.ConfigHash == hash);

pdcch = sixgr.lls6g.runners.resolveStrictComponentExecutionPolicy( ...
    scfg, cfg, "pdcch", root);
assert(pdcch.ExecutionScope == "in_path");
assert(pdcch.SameScenarioInPathEligible);
assert(pdcch.RunID == "run_policy_test");
assert(pdcch.ExecutionID == "execution_policy_test");
assert(pdcch.ConfigHash == hash);

trs = sixgr.lls6g.runners.resolveStrictComponentExecutionPolicy( ...
    scfg, cfg, "trs", root);
assert(trs.ExecutionScope == "component_anchor");
assert(~trs.SameScenarioInPathEligible);
assert(contains(replace(trs.ArtifactRoot, "\", "/"), ...
    "/component_anchors/trs"));

cfgMissing = rmfield(cfg, "run");
assertThrows(@() sixgr.lls6g.runners.resolveStrictComponentExecutionPolicy( ...
    scfg, cfgMissing, "prach", root), ...
    "sixgr:lls6g:InPathEvidenceIdentityMissing");
fprintf("PASS testStrictComponentExecutionPolicy\n");
end

function assertThrows(fn, identifier)
threw = false;
try
    fn();
catch cause
    threw = true;
    assert(string(cause.identifier) == string(identifier), ...
        "Expected %s, received %s.", identifier, cause.identifier);
end
assert(threw, "Expected %s.", identifier);
end

function localCleanup(root)
if isfolder(root)
    rmdir(root, "s");
end
end
