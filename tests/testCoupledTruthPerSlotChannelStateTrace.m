function ok = testCoupledTruthPerSlotChannelStateTrace()
%TESTCOUPLEDTRUTHPERSLOTCHANNELSTATETRACE Preserve unscheduled channel state.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
scenarioCfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scenarioCfg, fullfile(tmp, "run"));
cfg.scenario.nUE = 2;
cfg.scenario.ue.nUE = 2;
cfg = sixgr.util.structSet(cfg, "lls6g.users.n_users", 2);
cfg = sixgr.util.structSet(cfg, "users.n_users", 2);
cfg = sixgr.util.structSet(cfg, "deployment_topology.num_ues", 2);

multiUser = struct("Enabled", true, "NumUsers", 2, "RNTIStart", 8101, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize( ...
    cfg, fullfile(tmp, "runtime"), multiUser, struct(), 4);
for slot = 1:4
    state = sixgr.truth.CoupledTruthRuntime.advanceFrame( ...
        state, cfg, multiUser, slot, 18);
end

T = state.ServingTraceTable;
assert(istable(T) && height(T) == 8, ...
    "Two UEs over four canonical slots must emit eight large-scale runtime-state rows even without data grants.");
keys = unique(T(:, {'Slot','UEID'}), "rows");
assert(height(keys) == 8 && all(sort(unique(double(T.Slot))) == (1:4).'), ...
    "Per-slot serving-state keys must be unique and cover every canonical slot.");
finiteFields = ["X_m","Y_m","Z_m","Distance2D_m","Distance3D_m", ...
    "PropagationDelay_s","RadialVelocity_mps","AppliedDopplerHz", ...
    "Pathloss_dB","ServingRSRP_dBm"];
for field = finiteFields
    assert(all(isfinite(double(T.(char(field))))), ...
        "Per-slot runtime channel state contains nonfinite %s.", field);
end
fcHz = double(sixgr.util.structGet(cfg, "phy.fc_Hz", ...
    sixgr.util.structGet(cfg, "frequency.center_frequency_hz", NaN)));
expectedDoppler = abs(double(T.RadialVelocity_mps)) .* fcHz ./ 299792458;
assert(all(abs(double(T.ExpectedDopplerHz) - expectedDoppler) <= 1e-12), ...
    "Expected Doppler must use measured radial velocity, not scalar UE speed.");

ok = true;
end
