function ok = testLLSCoupledTruthFallbackFeedbackSanity()
%TESTLLSCOUPLEDTRUTHFALLBACKFEEDBACKSANITY Ensure fallback feedback does not synthesize invalid PMI/CRI.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_mimo4x4_multiuser_beamformed_awgn_validation.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.PMI", []);
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.selectedCRI", []);
cfg = sixgr.util.structSet(cfg, "phy.csi.selectedCRI", []);

multiUser = struct( ...
    "Enabled", true, ...
    "NumUsers", 2, ...
    "RNTIStart", 201, ...
    "SeedStride", 17, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "run"), multiUser, struct(), 1);
state = sixgr.truth.CoupledTruthRuntime.advanceFrame(state, cfg, multiUser, 1, 28);
state.LargeScaleState.BeamIndex(:) = 6;

[cfgU, ~] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg, state, 1, "DL");

pmi = sixgr.util.structGet(cfgU, "phy.pdsch.PMI", NaN);
cri = sixgr.util.structGet(cfgU, "phy.beamManagement.selectedCRI", NaN);
if isempty(pmi)
    pmi = NaN;
end
if isempty(cri)
    cri = NaN;
end

assert(isfinite(double(pmi)) && double(pmi) == 0, ...
    "Fallback coupled-truth feedback must sanitize invalid beam-index-like PMI values to a valid codebook default.");
assert(~isfinite(double(cri)), ...
    "Fallback coupled-truth feedback must not synthesize an invalid CRI when no configured resource exists.");

ok = true;
end
