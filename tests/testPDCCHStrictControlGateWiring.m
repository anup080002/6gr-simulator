function ok = testPDCCHStrictControlGateWiring()
%TESTPDCCHSTRICTCONTROLGATEWIRING Required PDCCH gates must invoke strict evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

repoRoot = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(repoRoot, "simulator", "configs", "scenarios", ...
    "master_geometry_based.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, tmp);

targetCases = lower(strtrim(string(scfg.get("scenario.target_cases", {}))));
assert(any(targetCases == "bundle") && ~any(targetCases == "pdcch"), ...
    "Fixture must reproduce the bundle-only target case that previously skipped strict PDCCH.");
assert(logical(sixgr.util.structGet(cfg, "run.controlGating.pdcchRequired", false)), ...
    "Fixture must resolve PDCCH as a required control-gating block.");

objectives = lower(strtrim(string(sixgr.util.structGet(cfg, "validation.objectives", strings(0, 1)))));
assert(any(objectives == "pdcch_strict_validation"), ...
    "Required PDCCH control gating must resolve to cfg.validation.objectives.");

policy = sixgr.lls6g.runners.resolveStrictControlEvidencePolicy(scfg, cfg);
assert(logical(policy.ShouldRun), ...
    "Bundle scenarios with required PDCCH must run strict control-channel evidence.");
assert(logical(policy.EnablePDCCH), ...
    "Bundle scenarios with required PDCCH must enable sixgr.phy.pdcch.runStrictPDCCHValidation.");

cfgNoGate = struct();
cfgNoGate = sixgr.util.structSet(cfgNoGate, "phy.pdcch.enable", true);
cfgNoGate = sixgr.util.structSet(cfgNoGate, "phy.pucch.enable", false);
cfgNoGate = sixgr.util.structSet(cfgNoGate, "run.controlGating.pdcchRequired", false);
cfgNoGate = sixgr.util.structSet(cfgNoGate, "validation.objectives", strings(0, 1));
scfgNoGate = struct();
scfgNoGate = sixgr.util.structSet(scfgNoGate, "scenario.target_cases", {'bundle'});
scfgNoGate = sixgr.util.structSet(scfgNoGate, "control_gating.pdcch_required", false);
policyNoGate = sixgr.lls6g.runners.resolveStrictControlEvidencePolicy(scfgNoGate, cfgNoGate);
assert(~logical(policyNoGate.EnablePDCCH), ...
    "Bundle-only target cases must not run standalone strict PDCCH unless PDCCH is required or targeted.");

ok = true;
end
