function ok = testLLSCoupledTruthBootstrapCQIConservative()
%TESTLLSCOUPLEDTRUTHBOOTSTRAPCQICONSERVATIVE Keep first-grant CQI bootstrap conservative.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

multiUser = struct( ...
    "Enabled", true, ...
    "NumUsers", 2, ...
    "RNTIStart", 401, ...
    "SeedStride", 17, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "run"), multiUser, struct(), 1);
state.CurrentServingIdx(:) = 1;
state.LargeScaleState.RxPower_dBm(1, :) = -140;
state.LargeScaleState.RxPower_dBm(1, 1) = -60;

fb = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state, 1, "DL");

assert(~logical(fb.Valid), ...
    "Bootstrap CQI before the first real CSI report must remain marked invalid.");
assert(double(fb.CQI) == 0, ...
    "Bootstrap CQI must stay at the conservative lab-default zero until measured CSI is available.");
assert(double(fb.MCSIndex) == 0, ...
    "Bootstrap MCS must stay at the conservative lab-default MCS 0 until measured CSI is available.");
assert(strcmpi(char(string(fb.Modulation)), "QPSK"), ...
    "Bootstrap modulation must stay aligned with the MCS 0 profile.");

ok = true;
end
