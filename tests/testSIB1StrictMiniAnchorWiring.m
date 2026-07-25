function ok = testSIB1StrictMiniAnchorWiring()
%TESTSIB1STRICTMINIANCHORWIRING Required SIB1/PBCH gates must invoke strict evidence.

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
assert(any(targetCases == "bundle") && ~any(targetCases == "sib1"), ...
    "Fixture must reproduce the bundle-only target case that previously skipped strict SIB1.");
assert(logical(sixgr.util.structGet(cfg, "run.controlGating.pbchRequired", false)), ...
    "Fixture must resolve PBCH/SIB1 acquisition as a required control-gating block.");
assert(logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false)), ...
    "Fixture must enable SIB1 waveform evidence.");

policy = sixgr.lls6g.runners.resolveStrictSupplementalEvidencePolicy(scfg, cfg);
assert(logical(policy.ShouldRun) && logical(policy.EnableSIB1), ...
    "Bundle scenarios with required PBCH/SIB1 must run sixgr.phy.broadcast.runSIB1StrictMiniAnchor.");
assert(any(string(policy.Reasons) == "sib1_target_objective_or_required"), ...
    "SIB1 supplemental evidence policy must disclose why the strict mini-anchor is required.");

cfgObjective = struct();
cfgObjective = sixgr.util.structSet(cfgObjective, "phy.sib1.enable", true);
cfgObjective = sixgr.util.structSet(cfgObjective, "validation.objectives", "cell_search_mib_sib1");
scfgObjective = struct();
scfgObjective = sixgr.util.structSet(scfgObjective, "scenario.target_cases", {'bundle'});
policyObjective = sixgr.lls6g.runners.resolveStrictSupplementalEvidencePolicy(scfgObjective, cfgObjective);
assert(logical(policyObjective.EnableSIB1), ...
    "cell_search_mib_sib1 validation objective must invoke strict SIB1 evidence.");

cfgNoGate = struct();
cfgNoGate = sixgr.util.structSet(cfgNoGate, "phy.sib1.enable", true);
cfgNoGate = sixgr.util.structSet(cfgNoGate, "validation.objectives", strings(0, 1));
cfgNoGate = sixgr.util.structSet(cfgNoGate, "run.controlGating.pbchRequired", false);
scfgNoGate = struct();
scfgNoGate = sixgr.util.structSet(scfgNoGate, "scenario.target_cases", {'bundle'});
scfgNoGate = sixgr.util.structSet(scfgNoGate, "control_gating.pbch_required", false);
policyNoGate = sixgr.lls6g.runners.resolveStrictSupplementalEvidencePolicy(scfgNoGate, cfgNoGate);
assert(~logical(policyNoGate.EnableSIB1), ...
    "Bundle-only target cases must not run SIB1 strict evidence unless SIB1/PBCH is required or targeted.");

ok = true;
end
