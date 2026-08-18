function ok = testLLSCFOEstimateLineage()
%TESTLLSCFOESTIMATELINEAGE Missing CFO estimates must not produce finalized CFO error values.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml"));
% Mutate the parsed scenario before runtime authority is installed.  This
% keeps the test YAML-authoritative while selecting the intentional
% no-estimator/no-correction CFO case and excluding unrelated CSI-RS.
sdata = scfg.toStruct();
sdata.impairments.cfo_correction_enable = false;
sdata.impairments.cfo_estimation_method = "none";
sdata.reference_signals.csi_rs_enabled = false;
scfg = sixgr.lls6g.config.ScenarioConfig(sdata, ...
    "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
    "ConfigHash", "cfo_lineage_no_estimator_authority", "Kind", scfg.Kind);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg.run.numFrames = 1;
cfg.channel.snr_dB = 10;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.run.interferenceExecutionMode = "none";
cfg.phy.impairments.cfoEstimationMethod = "none";
cfg.phy.impairments.cfoCorrectionEnabled = false;
cfg.phy.rx.cfoCorrectionEnabled = false;

multiUser = struct("Enabled", true, "NumUsers", 1, "RNTIStart", 320, "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "runtime"), multiUser, struct(), 1);
state.CurrentServingIdx(1) = 1;
state.CurrentServingMetric_dBm(1) = -70;
state.CurrentSlot = 1;
state.CurrentFrame = 1;
state.CurrentSNR_dB = 10;
state.LargeScaleState.BeamIndex(1,1) = 1;
state.LargeScaleState.BeamGain_dB(1,1) = 0;
state.LargeScaleState.RxPower_dBm(1,1) = -70;
state.LargeScaleState.BasePathloss_dB(1,1) = 100;
state.LargeScaleState.Pathloss_dB(1,1) = 100;
state.LargeScaleState.Shadow_dB(1,1) = 0;
state.LargeScaleState.O2I_dB(1,1) = 0;
state.CurrentCarrierFrequency_Hz = 7.0e8;
state.CurrentUESpeed_kmh = 30;
state.CurrentDopplerHz = 40;
[cfgDL, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg, state, 1, "DL");
[cfgUL, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg, state, 1, "UL");
cfgDL = localSingleStreamCalibrationConfig(cfgDL, "DL");
cfgUL = localSingleStreamCalibrationConfig(cfgUL, "UL");
cfgDL.phy.impairments.cfoEstimationMethod = "none";
cfgDL.phy.impairments.cfoCorrectionEnabled = false;
cfgDL.phy.rx.cfoCorrectionEnabled = false;
cfgDL.phy.pdsch.executionProfile = "phy_calibration";
cfgDL.run.pdschExecutionProfile = "phy_calibration";
cfgDL.phy.pdsch.dmrs.DMRSTypeAPosition = 3;
cfgDL.phy.pdsch.dmrs.typeAPosition = 3;
cfgUL.phy.impairments.cfoEstimationMethod = "none";
cfgUL.phy.impairments.cfoCorrectionEnabled = false;
cfgUL.phy.rx.cfoCorrectionEnabled = false;
cfgUL.phy.pusch.executionProfile = "phy_calibration";
cfgUL.run.puschExecutionProfile = "phy_calibration";
cfgUL.phy.pusch.dmrs.DMRSTypeAPosition = 3;
cfgUL.phy.pusch.dmrs.typeAPosition = 3;

dl = sixgr.link.runDLPDSCHThroughput(cfgDL, ...
    "NumFrames", 1, ...
    "SNR_dB", 10, ...
    "ExecutionProfile", "phy_calibration", ...
    "InterferenceBundle", struct([]));
ul = sixgr.link.runULPUSCHThroughput(cfgUL, ...
    "NumFrames", 1, ...
    "SNR_dB", 10, ...
    "ExecutionProfile", "phy_calibration", ...
    "InterferenceBundle", struct([]));

localAssertCFOLineage(dl.TrialTable, "DL");
localAssertCFOLineage(ul.TrialTable, "UL");
ok = true;
end

function cfg = localSingleStreamCalibrationConfig(cfg, direction)
% CFO lineage does not require the parent 64-element scheduler/beam state.
% Use an explicit one-layer/one-port waveform calibration contract so that
% this test measures CFO fields without silently inheriting a rectangular
% system-level precoder that belongs to scheduler_truth execution.
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.csirs.enable = false;
cfg.phy.csi.enable = false;
if isfield(cfg, "runtime") && isfield(cfg.runtime, "features") && ...
        isfield(cfg.runtime.features, "csi_rs")
    cfg.runtime.features.csi_rs.Enabled = false;
end
if upper(string(direction)) == "DL"
    cfg.phy.pdsch.nLayers = 1;
    cfg.phy.pdsch.numLayers = 1;
    cfg.phy.pdsch.nPorts = 1;
    cfg.phy.pdsch.numPorts = 1;
    cfg.phy.pdsch.precoding.matrix = 1;
    cfg.phy.pdsch.precoding.normalizationConvention = "semi_unitary";
    cfg.phy.pdsch.precodingMatrix = 1;
    cfg.phy.pdsch.W = 1;
else
    cfg.phy.pusch.nLayers = 1;
    cfg.phy.pusch.numLayers = 1;
    cfg.phy.pusch.nPorts = 1;
    cfg.phy.pusch.numPorts = 1;
    cfg.phy.pusch.NumAntennaPorts = 1;
    cfg.phy.pusch.precoding.matrix = 1;
    cfg.phy.pusch.precoding.normalizationConvention = "semi_unitary";
    cfg.phy.pusch.precodingMatrix = 1;
    cfg.phy.pusch.W = 1;
end
end

function localAssertCFOLineage(T, direction)
assert(istable(T) && height(T) == 1, ...
    "Expected a single %s row for CFO lineage validation.", direction);
requiredVars = {'InjectedCFO_Hz','TrueCFO_Hz','EstimatedCFO_PreCorrection_Hz','EstimatedCFO_Hz', ...
    'ResidualCFO_PostCorrection_Hz','CFOError_Hz','CFOEstimateAvailability','CFOErrorDefinition','CFOValueStatus'};
assert(all(ismember(requiredVars, T.Properties.VariableNames)), ...
    "Raw %s trial rows must expose explicit CFO lineage fields.", direction);
assert(isfinite(double(T.InjectedCFO_Hz(1))) && isfinite(double(T.TrueCFO_Hz(1))), ...
    "Raw %s trial row must preserve the injected/true CFO reference.", direction);
assert(~isfinite(double(T.EstimatedCFO_PreCorrection_Hz(1))) && ~isfinite(double(T.EstimatedCFO_Hz(1))), ...
    "Raw %s trial row must leave estimated CFO fields unavailable when no estimate was produced.", direction);
assert(~isfinite(double(T.ResidualCFO_PostCorrection_Hz(1))) && ~isfinite(double(T.CFOError_Hz(1))), ...
    "Raw %s trial row must not finalize residual/error CFO values without an estimate.", direction);
assert(strcmpi(char(string(T.CFOEstimateAvailability(1))), "missing") && ...
    strcmpi(char(string(T.CFOErrorDefinition(1))), "not_available_without_cfo_estimate") && ...
    strcmpi(char(string(T.CFOValueStatus(1))), "NOT_AVAILABLE"), ...
    "Raw %s trial row must truthfully classify missing CFO estimates.", direction);
end
