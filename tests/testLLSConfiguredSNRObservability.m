function ok = testLLSConfiguredSNRObservability()
%TESTLLSCONFIGUREDSNROBSERVABILITY Configured runtime SNR anchors must stay distinct from measured SINR.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg.run.numFrames = 1;
cfg.scenario.nUE = 1;
cfg.scenario.ue.nUE = 1;
cfg = sixgr.util.structSet(cfg, "lls6g.users.n_users", 1);
cfg = sixgr.util.structSet(cfg, "lls6g.users.enabled", true);
cfg = sixgr.util.structSet(cfg, "users.n_users", 1);
cfg = sixgr.util.structSet(cfg, "deployment_topology.num_ues", 1);
cfg.channel.snr_dB = 12;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.run.noiseOperatingMode = "configured_snr_anchor_after_large_scale_gain";
cfg.run.interferenceExecutionMode = "none";

multiUser = struct("Enabled", true, "NumUsers", 1, "RNTIStart", 320, "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "runtime"), multiUser, struct(), 1);
state.CurrentServingIdx(1) = 1;
state.CurrentServingMetric_dBm(1) = -70;
state.CurrentSlot = 1;
state.CurrentFrame = 1;
state.CurrentSNR_dB = 12;
state.LargeScaleState.BeamIndex(1,1) = 1;
state.LargeScaleState.BeamGain_dB(1,1) = 0;
state.LargeScaleState.RxPower_dBm(1,1) = -70;
state.LargeScaleState.BasePathloss_dB(1,1) = 100;
state.LargeScaleState.Pathloss_dB(1,1) = 100;
state.LargeScaleState.Shadow_dB(1,1) = 0;
state.LargeScaleState.O2I_dB(1,1) = 0;
state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfg, "DL", 1, 1, 1, 1, 12);
runState = sixgr.util.structGet(state, "RunState", struct());

assert(isfinite(double(runState.ConfiguredSNR_dB)) && abs(double(runState.ConfiguredSNR_dB) - 12) < 1e-9, ...
    "Run-state ConfiguredSNR_dB must preserve the configured runtime anchor.");
assert(isfinite(double(runState.CurrentSNR_dB)) && abs(double(runState.CurrentSNR_dB) - 12) < 1e-9, ...
    "CurrentSNR_dB must equal the configured anchor before any runtime feedback is available.");
assert(strcmpi(char(string(runState.ValueRole)), "configured_anchor_until_feedback") && ...
    strcmpi(char(string(runState.ValueStatus)), "configured_anchor_pending_runtime_feedback"), ...
    "Run-state SINR labeling must explicitly classify configured-anchor fallback before measured feedback exists.");
assert(contains(lower(char(string(runState.ValueDefinition))), "not a measured sinr"), ...
    "Run-state value definition must disclose that the configured anchor is not a measured SINR.");

ok = true;
end
