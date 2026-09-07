function out = applyRFImpairmentChain(x, cfg, varargin)
%APPLYRFIMPAIRMENTCHAIN Apply one ordered RF impairment pipeline to samples.
% Keep this file ASCII-only.
%
% Declared order:
%   Tx: IQ -> element analog RF -> PA -> phase noise -> CFO -> sample timing -> sample clock
%   Rx: sample timing -> LO/CFO -> phase noise -> IQ -> element analog RF -> sample clock -> AGC -> ADC

p = inputParser;
p.addParameter("SampleRateHz", double(sixgr.util.structGet(cfg, "channel_rf.sampleRateHz", 30.72e6)));
p.addParameter("RunId", "channel_rf_strict");
p.addParameter("Direction", "downlink");
p.addParameter("MeasurementPoint", "rx_input");
p.addParameter("Endpoint", "txrx");
p.addParameter("StrictMutationRequired", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("UseLegacyGlobalConfig", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("ApplyPA", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("ApplyADC", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("ResolveOnly",false,@(v)islogical(v)&&isscalar(v));
p.addParameter("Stream",[],@(v)isempty(v)||isa(v,'sixgr.rf.runtime.RFImpairmentStream'));
p.parse(varargin{:});
opt = p.Results;

fs = double(opt.SampleRateHz);
if ~isscalar(fs) || ~isreal(fs) || ~isfinite(fs) || fs <= 0
    error("sixgr:rf:BadSampleRate", "RF impairment chain requires a positive sample rate.");
end

endpoint = lower(strtrim(string(opt.Endpoint)));
if strlength(endpoint) == 0
    endpoint = "txrx";
end
if endpoint == "all"
    endpoint = "txrx";
end
if ~any(endpoint == ["tx","rx","txrx"])
    error("sixgr:rf:BadEndpoint", "RF impairment endpoint must be tx, rx, txrx, or all.");
end

stream=opt.Stream;
if isempty(stream)
    chain = localResolveChainConfig(cfg, fs, endpoint, string(opt.Direction), logical(opt.UseLegacyGlobalConfig), ...
        logical(opt.ApplyPA), logical(opt.ApplyADC));
else
    stream.assertApplying();
    chain=stream.Chain;
end
if opt.ResolveOnly
    out=struct('Config',chain,'ExecutionStage',"configured_not_executed");
    return;
end
xRef = x;
y = x;
beforeHash = localWaveformHash(y);

stageRows = repmat(localStageRowTemplate(), 0, 1);
stageOrder = strings(0, 1);
if chain.IncludeTx
    [y, stageRows] = localApplyIQStage(y, chain.TxIQ, "tx_iq", "tx", stageRows);
    [y, stageRows] = localApplyElementRFStage(y, chain.TxElementRF, cfg, "tx_element_rf", "tx", stageRows,stream);
    [y, stageRows] = localApplyPAStage(y, chain.TxPA, cfg, "tx_pa", "tx", stageRows,stream);
    [y, stageRows] = localApplyPhaseNoiseStage(y, chain.TxPhaseNoise, "tx_phase_noise", "tx", stageRows);
    [y, stageRows] = localApplyCFOStage(y, chain.TxCFO, "tx_cfo", "tx", stageRows,stream);
    [y, stageRows] = localApplyTimingStage(y, chain.TxTiming, "tx_timing", "tx", stageRows,stream);
    [y, stageRows] = localApplySampleClockOffsetStage(y, chain.TxSampleClockOffset, "tx_sample_clock_offset", "tx", stageRows);
    stageOrder = [stageOrder; "tx_iq"; "tx_element_rf"; "tx_pa"; "tx_phase_noise"; "tx_cfo"; "tx_timing"; "tx_sample_clock_offset"]; %#ok<AGROW>
end
if chain.IncludeRx
    [y, stageRows] = localApplyTimingStage(y, chain.RxTiming, "rx_timing", "rx", stageRows,stream);
    [y, stageRows] = localApplyCFOStage(y, chain.RxCFO, "rx_lo_cfo", "rx", stageRows,stream);
    [y, stageRows] = localApplyPhaseNoiseStage(y, chain.RxPhaseNoise, "rx_phase_noise", "rx", stageRows);
    [y, stageRows] = localApplyIQStage(y, chain.RxIQ, "rx_iq", "rx", stageRows);
    [y, stageRows] = localApplyElementRFStage(y, chain.RxElementRF, cfg, "rx_element_rf", "rx", stageRows,stream);
    [y, stageRows] = localApplySampleClockOffsetStage(y, chain.RxSampleClockOffset, "rx_sample_clock_offset", "rx", stageRows);
    [y, stageRows] = localApplyAGCStage(y, chain.RxAGC, "rx_agc", "rx", stageRows,stream);
    [y, stageRows] = localApplyADCStage(y, chain.RxADC, "rx_adc", "rx", stageRows,stream);
    stageOrder = [stageOrder; "rx_timing"; "rx_lo_cfo"; "rx_phase_noise"; "rx_iq"; "rx_element_rf"; "rx_sample_clock_offset"; "rx_agc"; "rx_adc"]; %#ok<AGROW>
end
if strlength(string(chain.CarrierPhase.StageName)) > 0
    [y, stageRows] = localApplyCarrierPhaseStage(y, chain.CarrierPhase, stageRows);
    stageOrder = [stageOrder; string(chain.CarrierPhase.StageName)]; %#ok<AGROW>
end

afterHash = localWaveformHash(y);
evm = localEVM(xRef, y);
replay = localBuildReplay(chain, stageRows, stageOrder, xRef, y);
replay.RFProcessingMode="independent_block";
replay.AGCControlModel="disabled";
replay.AGCDecisionCausal=~logical(chain.RxAGC.Enabled && chain.IncludeRx);
if chain.IncludeRx && chain.RxAGC.Enabled
    replay.AGCControlModel="noncausal_same_block_rms";
end
if ~isempty(stream)
    replay.RFProcessingMode="retained_sample_stream";
    replay.RFStreamStartSample=stream.NextSampleIndex;
    replay.RFStreamEndSampleExclusive=stream.NextSampleIndex+size(y,1);
    replay.RFConfigurationEpoch=stream.ConfigurationEpoch;
    replay.AGCDecisionCausal=true;
    if ~isempty(fieldnames(stream.LastAGCTrace))
        replay.AGCControlModel=string(stream.LastAGCTrace.ControlModel);
        replay.AGCStreamTrace=stream.LastAGCTrace;
        gains=stream.LastAGCTrace.AppliedGain_dB;
        replay.AGCGainIsTimeVarying=any(gains~=gains(1));
        replay.AGCGain_dB=NaN;
        if ~replay.AGCGainIsTimeVarying, replay.AGCGain_dB=gains(1); end
    end
end
rfChainId = "rf_" + localShortHash(afterHash);
replay.RFImpairmentChainId = char(rfChainId);
replay.RFInputWaveformSHA256 = char(string(beforeHash));
replay.RFOutputWaveformSHA256 = char(string(afterHash));
strictOk = localResolveStrictOk(chain, beforeHash, afterHash, stageRows, logical(opt.StrictMutationRequired));

failure = "";
if ~strictOk
    failure = localStrictFailureReason(chain, beforeHash, afterHash, stageRows, logical(opt.StrictMutationRequired));
end

out = struct();
out.Waveform = y;
out.Config = chain;
out.StageTrace = struct2table(stageRows);
out.Replay = replay;
out.Measurement = evm;
out.Row = struct( ...
    "RunId", string(opt.RunId), ...
    "TrialId", "positive_rf_impairment", ...
    "RFImpairmentChainId", rfChainId, ...
    "Direction", string(opt.Direction), ...
    "TxOrRxSide", string(opt.MeasurementPoint), ...
    "Endpoint", string(endpoint), ...
    "RFProcessingMode",string(replay.RFProcessingMode), ...
    "AGCControlModel",string(replay.AGCControlModel), ...
    "AGCDecisionCausal",logical(replay.AGCDecisionCausal), ...
    "StageOrder", strjoin(stageOrder, ">"), ...
    "CFOEnabled", logical(replay.CFOApplied), ...
    "CFOHzConfigured", double(replay.InjectedCFO_Hz), ...
    "CFOHzApplied", double(replay.InjectedCFO_Hz), ...
    "PhaseNoiseEnabled", logical(replay.PhaseNoiseConfigured), ...
    "PhaseNoiseApplied", logical(replay.PhaseNoiseApplied), ...
    "PhaseNoiseProfileId", string(replay.PhaseNoiseAvailableBackend), ...
    "PhaseNoiseLevelApplied", double(replay.PhaseNoiseLevelApplied), ...
    "PhaseNoiseWaveformBeforeHash", string(replay.PhaseNoiseWaveformBeforeHash), ...
    "PhaseNoiseWaveformAfterHash", string(replay.PhaseNoiseWaveformAfterHash), ...
    "PhaseNoiseExecutionStatus", string(replay.PhaseNoiseExecutionStatus), ...
    "PhaseNoiseTruthClassification", string(replay.PhaseNoiseTruthClassification), ...
    "IQImbalanceEnabled", logical(replay.IQImbalanceConfigured), ...
    "AmplitudeImbalanceDb", double(replay.ConfiguredIQGainImbalance_dB), ...
    "PhaseImbalanceDeg", double(replay.ConfiguredIQPhaseImbalance_deg), ...
    "PAEnabled", logical(replay.PAEnabled), ...
    "PAModel", string(replay.PAModel), ...
    "BackoffDb", double(replay.PABackoff_dB), ...
    "TimingOffsetEnabled", logical(replay.TimingOffsetApplied), ...
    "TimingOffsetSamplesConfigured", double(replay.InjectedTimingOffset_samples), ...
    "TimingOffsetSamplesApplied", double(replay.InjectedTimingOffset_samples), ...
    "SampleClockOffsetEnabled", logical(replay.SampleClockOffsetEnabled), ...
    "SampleClockOffsetPpm", double(replay.SampleClockOffsetPpm), ...
    "QuantizationEnabled", logical(replay.ADCQuantizationApplied), ...
    "ADCBits", double(replay.ADCBits), ...
    "DACBits", double(replay.DACBits), ...
    "WaveformBeforeHash", string(beforeHash), ...
    "WaveformAfterHash", string(afterHash), ...
    "WaveformChanged", string(beforeHash) ~= string(afterHash), ...
    "EVMMeasuredDb", evm.EVMDb, ...
    "EVMMeasuredPercent", evm.EVMPercent, ...
    "StrictOk", strictOk, ...
    "TruthStatus", "real_lls_evidence", ...
    "FailureReason", failure);
end

function chain = localResolveChainConfig(cfg, fs, endpoint, direction, useLegacy, applyPA, applyADC)
includeTx = any(endpoint == ["tx","txrx"]);
includeRx = any(endpoint == ["rx","txrx"]);
legacyToTx = useLegacy && includeTx;
legacyToRx = useLegacy && includeRx && ~includeTx;
direction = upper(strtrim(string(direction)));

chain = struct();
chain.ContractVersion = "sixgr.rf.ImpairmentChainConfig/v1";
chain.Endpoint = char(endpoint);
chain.Direction = char(direction);
chain.SampleRate_Hz = double(fs);
chain.Immutable = true;
chain.IncludeTx = logical(includeTx);
chain.IncludeRx = logical(includeRx);
chain.UseLegacyGlobalConfig = logical(useLegacy);
chain.TxIQ = localResolveIQConfig(cfg, "tx", legacyToTx);
chain.RxIQ = localResolveIQConfig(cfg, "rx", legacyToRx);
chain.TxCFO = localResolveCFOConfig(cfg, "tx", legacyToTx, fs);
chain.RxCFO = localResolveCFOConfig(cfg, "rx", legacyToRx, fs);
chain.TxTiming = localResolveTimingConfig(cfg, "tx", legacyToTx);
chain.RxTiming = localResolveTimingConfig(cfg, "rx", legacyToRx);
chain.TxPhaseNoise = localResolvePhaseNoiseConfig(cfg, "tx", legacyToTx, fs);
chain.RxPhaseNoise = localResolvePhaseNoiseConfig(cfg, "rx", legacyToRx, fs);
chain.TxElementRF = localResolveElementRFConfig(cfg, "tx", direction, legacyToTx);
chain.RxElementRF = localResolveElementRFConfig(cfg, "rx", direction, legacyToRx);
chain.TxSampleClockOffset = localResolveSampleClockOffsetConfig(cfg, "tx", legacyToTx);
chain.RxSampleClockOffset = localResolveSampleClockOffsetConfig(cfg, "rx", legacyToRx);
chain.TxPA = localResolvePAConfig(cfg, logical(applyPA));
chain.RxAGC = localResolveAGCConfig(cfg, logical(applyADC));
chain.RxADC = localResolveADCConfig(cfg, logical(applyADC));
chain.CarrierPhase = localResolveCarrierPhaseConfig(cfg, endpoint, legacyToTx, legacyToRx);
chain.SampleClockOffset = localMergeSampleClockOffsetConfig(chain.TxSampleClockOffset, chain.RxSampleClockOffset);
end

function cfgIQ = localResolveIQConfig(cfg, endpoint, includeLegacy)
prefix = "rf." + string(endpoint) + ".iqImbalance.";
enabled = localFirstLogical( ...
    localGetPath(cfg, prefix + "enable", []), ...
    localGetPath(cfg, prefix + "enabled", []), ...
    []);
gain = localFirstFinite( ...
    localGetPath(cfg, prefix + "gainImbalance_dB", NaN), ...
    localGetPath(cfg, prefix + "ampImb_dB", NaN), ...
    localGetPath(cfg, prefix + "amp_imbalance_db", NaN), ...
    NaN);
phase = localFirstFinite( ...
    localGetPath(cfg, prefix + "phaseImbalance_deg", NaN), ...
    localGetPath(cfg, prefix + "phaseImb_deg", NaN), ...
    localGetPath(cfg, prefix + "phase_imbalance_deg", NaN), ...
    NaN);
if includeLegacy
    enabled = localFirstLogical(enabled, ...
        sixgr.util.structGet(cfg, "rf.iqImbalance.enable", []), ...
        sixgr.util.structGet(cfg, "phy.impairments.iqImbalanceEnabled", []), ...
        []);
    gain = localFirstFinite(gain, ...
        sixgr.util.structGet(cfg, "rf.iqImbalance.gainImbalance_dB", NaN), ...
        sixgr.util.structGet(cfg, "rf.iqImbalance.ampImb_dB", NaN), ...
        sixgr.util.structGet(cfg, "phy.impairments.iqGainImbalance_dB", NaN), ...
        sixgr.util.structGet(cfg, "lls6g.impairments.iq_amplitude_imbalance_dB", NaN), ...
        0);
    phase = localFirstFinite(phase, ...
        sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImbalance_deg", NaN), ...
        sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImb_deg", NaN), ...
        sixgr.util.structGet(cfg, "phy.impairments.iqPhaseImbalance_deg", NaN), ...
        sixgr.util.structGet(cfg, "lls6g.impairments.iq_phase_imbalance_deg", NaN), ...
        0);
end
if isempty(enabled)
    enabled = false;
end
if ~isfinite(gain)
    gain = 0;
end
if ~isfinite(phase)
    phase = 0;
end
enabled = logical(enabled);
cfgIQ = struct("Enabled", logical(enabled), "GainImbalance_dB", double(gain), ...
    "PhaseImbalance_deg", double(phase), "Endpoint", char(endpoint));
end

function cfgCFO = localResolveCFOConfig(cfg, endpoint, includeLegacy, fs)
prefix = "rf." + string(endpoint) + ".";
cfoHz = localFirstFinite( ...
    localGetPath(cfg, prefix + "cfo_Hz", NaN), ...
    localGetPath(cfg, prefix + "cfoHz", NaN), ...
    localGetPath(cfg, prefix + "loOffset_Hz", NaN), ...
    NaN);
if includeLegacy
    cfoHz = localFirstFinite(cfoHz, ...
        sixgr.util.structGet(cfg, "rf.cfo_Hz", NaN), ...
        sixgr.util.structGet(cfg, "phy.impairments.cfoHz", NaN), ...
        sixgr.util.structGet(cfg, "impairments.cfo_hz", NaN), ...
        0);
end
if ~isfinite(cfoHz)
    cfoHz = 0;
end
cfgCFO = struct("Enabled", isfinite(cfoHz) && abs(cfoHz) > 0, ...
    "CFO_Hz", double(cfoHz), "SampleRate_Hz", double(fs), "Endpoint", char(endpoint));
end

function cfgTiming = localResolveTimingConfig(cfg, endpoint, includeLegacy)
prefix = "rf." + string(endpoint) + ".";
offset = localFirstFinite( ...
    localGetPath(cfg, prefix + "timingOffsetSamples", NaN), ...
    localGetPath(cfg, prefix + "sampleTimingOffset_samples", NaN), ...
    localGetPath(cfg, prefix + "timing_offset_samples", NaN), ...
    NaN);
if includeLegacy
    offset = localFirstFinite(offset, ...
        sixgr.util.structGet(cfg, "rf.timingOffsetSamples", NaN), ...
        sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", NaN), ...
        sixgr.util.structGet(cfg, "impairments.timing_offset_samples", NaN), ...
        0);
end
if ~isfinite(offset)
    offset = 0;
end
cfgTiming = struct("Enabled", isfinite(offset) && abs(offset) > 0, ...
    "TimingOffset_samples", double(offset), "Endpoint", char(endpoint));
end

function cfgPN = localResolvePhaseNoiseConfig(cfg, endpoint, includeLegacy, fs)
prefix = "rf." + string(endpoint) + ".phaseNoise.";
enabled = localFirstLogical( ...
    localGetPath(cfg, prefix + "enable", []), ...
    localGetPath(cfg, prefix + "enabled", []), ...
    []);
if includeLegacy
    enabled = localFirstLogical(enabled, ...
        sixgr.util.structGet(cfg, "rf.phaseNoise.enable", []), ...
        sixgr.util.structGet(cfg, "phy.impairments.phaseNoiseEnabled", []), ...
        sixgr.util.structGet(cfg, "impairments.phase_noise_enabled", []), ...
        sixgr.util.structGet(cfg, "lls6g.resolvedConfig.impairments.phase_noise_enabled", []), ...
        []);
end
if isempty(enabled)
    enabled = false;
end
cfgStage = cfg;
cfgStage = sixgr.util.structSet(cfgStage, "rf.phaseNoise.enable", logical(enabled));
seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + localEndpointSeedOffset(endpoint);
pn = sixgr.rf.PhaseNoiseModel(cfgStage, fs, seed);
cfgPN = struct("Enabled", logical(enabled), "Model", pn, "Seed", double(seed), ...
    "Backend", string(pn.Backend), "TruthClassification", string(pn.TruthClassification), ...
    "ApproximationReason", string(pn.ApproximationReason), "Endpoint", char(endpoint));
end

function cfgPA = localResolvePAConfig(cfg, applyPA)
enabled = logical(applyPA) && logical(sixgr.util.structGet(cfg, "rf.pa.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.paNonlinearityEnabled", false)));
backoff = double(sixgr.util.structGet(cfg, "rf.pa.backoff_dB", ...
    sixgr.util.structGet(cfg, "lls6g.impairments.pa_output_backoff_dB", 0)));
if ~isfinite(backoff)
    backoff = 0;
end
cfgPA = struct("Enabled", logical(enabled), "Backoff_dB", double(backoff), ...
    "Model", char(string(sixgr.util.structGet(cfg, "rf.pa.method", "memoryless"))));
end

function cfgElem = localResolveElementRFConfig(cfg, endpoint, direction, includeLegacy)
prefix = "rf." + string(endpoint) + ".element.";
enabled = localFirstLogical( ...
    localGetPath(cfg, prefix + "enable", []), ...
    localGetPath(cfg, prefix + "enabled", []), ...
    []);
gain = localFirstVector( ...
    localGetPath(cfg, prefix + "gain_dB", []), ...
    localGetPath(cfg, prefix + "gainError_dB", []), ...
    []);
phase = localFirstVector( ...
    localGetPath(cfg, prefix + "phase_deg", []), ...
    localGetPath(cfg, prefix + "phaseError_deg", []), ...
    []);
couplingEnabled = localFirstLogical( ...
    localGetPath(cfg, prefix + "mutualCoupling.enable", []), ...
    localGetPath(cfg, prefix + "mutualCoupling.enabled", []), ...
    localGetPath(cfg, "rf." + string(endpoint) + ".mutualCoupling.enable", []), ...
    localGetPath(cfg, "rf." + string(endpoint) + ".mutualCoupling.enabled", []), ...
    localGetPath(cfg, "rf.mutualCoupling.enable", []), ...
    localGetPath(cfg, "rf.mutualCoupling.enabled", []), ...
    []);
couplingMatrix = localFirstMatrix( ...
    localGetPath(cfg, prefix + "mutualCoupling.matrix", []), ...
    localGetPath(cfg, prefix + "mutualCouplingMatrix", []), ...
    localGetPath(cfg, "rf." + string(endpoint) + ".mutualCoupling.matrix", []), ...
    localGetPath(cfg, "rf." + string(endpoint) + ".mutualCouplingMatrix", []), ...
    localGetPath(cfg, "rf.mutualCoupling.matrix", []), ...
    localGetPath(cfg, "rf.mutualCouplingMatrix", []), ...
    localGetPath(cfg, "channel.mutualCouplingMatrix", []), ...
    []);
if includeLegacy
    enabled = localFirstLogical(enabled, ...
        sixgr.util.structGet(cfg, "rf.element.enable", []), ...
        sixgr.util.structGet(cfg, "rf.element.enabled", []), ...
        []);
    gain = localFirstVector(gain, ...
        sixgr.util.structGet(cfg, "rf.element.gain_dB", []), ...
        sixgr.util.structGet(cfg, "rf.element.gainError_dB", []), ...
        []);
    phase = localFirstVector(phase, ...
        sixgr.util.structGet(cfg, "rf.element.phase_deg", []), ...
        sixgr.util.structGet(cfg, "rf.element.phaseError_deg", []), ...
        []);
    couplingEnabled = localFirstLogical(couplingEnabled, ...
        sixgr.util.structGet(cfg, "rf.mutualCoupling.enable", []), ...
        sixgr.util.structGet(cfg, "rf.mutualCoupling.enabled", []), ...
        sixgr.util.structGet(cfg, "channel.mutual_coupling_matrix_enable", []), ...
        []);
    couplingMatrix = localFirstMatrix(couplingMatrix, ...
        sixgr.util.structGet(cfg, "rf.mutualCoupling.matrix", []), ...
        sixgr.util.structGet(cfg, "rf.mutualCouplingMatrix", []), ...
        sixgr.util.structGet(cfg, "channel.mutualCouplingMatrix", []), ...
        []);
end
if isempty(enabled)
    enabled = ~isempty(gain) || ~isempty(phase) || ~isempty(couplingMatrix) || ...
        (~isempty(couplingEnabled) && logical(couplingEnabled));
end
if isempty(gain)
    gain = 0;
end
if isempty(phase)
    phase = 0;
end
if isempty(couplingEnabled)
    couplingEnabled = ~isempty(couplingMatrix);
end
role = localEndpointRole(endpoint, direction);
cfgElem = struct("Enabled", logical(enabled), "Gain_dB", double(gain(:).'), ...
    "Phase_deg", double(phase(:).'), "Endpoint", char(endpoint), "Role", char(role), ...
    "MutualCouplingEnabled", logical(couplingEnabled), ...
    "MutualCouplingMatrix", double(couplingMatrix));
end

function cfgAGC = localResolveAGCConfig(cfg, applyADC)
enabled = logical(applyADC) && localFirstLogical( ...
    sixgr.util.structGet(cfg, "rf.rx.agc.enable", []), ...
    sixgr.util.structGet(cfg, "rf.agc.enable", []), ...
    sixgr.util.structGet(cfg, "rf.hardware.agc.enabled", []), ...
    sixgr.util.structGet(cfg, "phy.impairments.agcEnabled", []), ...
    false);
targetRms = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.rx.agc.targetRms", NaN), ...
    sixgr.util.structGet(cfg, "rf.agc.targetRms", NaN), ...
    sixgr.util.structGet(cfg, "rf.hardware.agc.targetRms", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.agcTargetRms", NaN), ...
    0.5);
maxGain = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.rx.agc.maxGain_dB", NaN), ...
    sixgr.util.structGet(cfg, "rf.agc.maxGain_dB", NaN), ...
    sixgr.util.structGet(cfg, "rf.hardware.agc.maxGain_dB", NaN), ...
    60);
minGain = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.rx.agc.minGain_dB", NaN), ...
    sixgr.util.structGet(cfg, "rf.agc.minGain_dB", NaN), ...
    sixgr.util.structGet(cfg, "rf.hardware.agc.minGain_dB", NaN), ...
    -60);
if ~(isfinite(targetRms) && targetRms > 0)
    targetRms = 0.5;
end
if ~(isfinite(maxGain) && isfinite(minGain) && maxGain >= minGain)
    maxGain = 60;
    minGain = -60;
end
cfgAGC = struct("Enabled", logical(enabled), "TargetRMS", double(targetRms), ...
    "MaxGain_dB", double(maxGain), "MinGain_dB", double(minGain), ...
    "AppliedGain_dB", NaN);
end

function cfgADC = localResolveADCConfig(cfg, applyADC)
bits = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.hardware.adc.resolutionBits", NaN), ...
    sixgr.util.structGet(cfg, "rf.adcBits", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationBits", NaN), ...
    NaN);
% Bit depth describes the selected ADC model; it is not an execution
% switch.  Treating a bit-depth field as enablement silently clipped
% absolute-power waveforms when no AGC/full-scale profile was selected.
% Only the explicit YAML-owned enable flag may activate quantization.
enableExplicit = localHasPath(cfg, "rf.adc.enable") || ...
    localHasPath(cfg, "phy.impairments.adcQuantizationEnabled");
enabled = logical(applyADC) && enableExplicit && localFirstLogical( ...
    sixgr.util.structGet(cfg, "rf.adc.enable", []), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationEnabled", []), ...
    false);
if ~isfinite(bits)
    bits = NaN;
end
if enabled && (~isfinite(bits) || bits < 2 || bits > 24 || bits ~= fix(bits))
    error('RF:ADCProfileMissing', ...
        'An enabled ADC requires the canonical quantizer range of 2 through 24 integer bits; it cannot silently become disabled.');
end
dacBits = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.dacBits", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.dacQuantizationBits", NaN), ...
    NaN);
fullScale = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.adc.fullScale", NaN), ...
    sixgr.util.structGet(cfg, "rf.adcFullScale", NaN), ...
    sixgr.util.structGet(cfg, "rf.hardware.adc.fullScale", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcFullScale", NaN), ...
    1);
fullScaleExplicit = localHasPath(cfg, "rf.adc.fullScale") || ...
    localHasPath(cfg, "rf.adcFullScale") || ...
    localHasPath(cfg, "rf.hardware.adc.fullScale") || ...
    localHasPath(cfg, "phy.impairments.adcFullScale");
if ~(isfinite(fullScale) && fullScale > 0)
    fullScale = 1;
end
strictRF = localRFStrictProfileSelected(cfg);
if logical(enabled) && strictRF && ...
        (~fullScaleExplicit || bits ~= round(bits))
    error("RF:ADCProfileMissing", ...
        "Strict ADC execution requires an integer bit depth and explicit full-scale value.");
end
cfgADC = struct("Enabled", logical(enabled), "Bits", double(bits), ...
    "DACBits", double(dacBits), "FullScale", double(fullScale));
end

function cfgPhase = localResolveCarrierPhaseConfig(cfg, endpoint, legacyToTx, legacyToRx)
phaseDeg = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.carrierPhaseOffset_deg", NaN), ...
    sixgr.util.structGet(cfg, "rf.phaseOffset_deg", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.phaseOffset_deg", NaN), ...
    sixgr.util.structGet(cfg, "impairments.phase_offset_deg", NaN), ...
    0);
if ~(legacyToTx || legacyToRx) || ~isfinite(phaseDeg) || abs(phaseDeg) <= 1e-12
    cfgPhase = struct("Enabled", false, "PhaseOffset_deg", 0, "StageName", "");
    return;
end
if legacyToTx || endpoint == "tx"
    stage = "tx_carrier_phase";
else
    stage = "rx_carrier_phase";
end
cfgPhase = struct("Enabled", true, "PhaseOffset_deg", double(phaseDeg), "StageName", stage);
end

function cfgSCO = localResolveSampleClockOffsetConfig(cfg, endpoint, includeLegacy)
prefix = "rf." + string(endpoint) + ".sampleClockOffset.";
ppm = localFirstFinite( ...
    localGetPath(cfg, prefix + "ppm", NaN), ...
    localGetPath(cfg, prefix + "offsetPpm", NaN), ...
    NaN);
if includeLegacy
    ppm = localFirstFinite(ppm, ...
        sixgr.util.structGet(cfg, "rf.sampleClockOffset.ppm", NaN), ...
        sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetPpm", NaN), ...
        sixgr.util.structGet(cfg, "impairments.sample_clock_offset_ppm", NaN), ...
        0);
end
if ~isfinite(ppm)
    ppm = 0;
end
enabled = localFirstLogical( ...
    localGetPath(cfg, prefix + "enable", []), ...
    localGetPath(cfg, prefix + "enabled", []), ...
    []);
if includeLegacy
    enabled = localFirstLogical(enabled, ...
        sixgr.util.structGet(cfg, "rf.sampleClockOffset.enable", []), ...
        sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetEnabled", []), ...
        abs(ppm) > 0);
end
if isempty(enabled)
    enabled = abs(ppm) > 0;
end
cfgSCO = struct("Enabled", logical(enabled) && abs(ppm) > 0, "PPM", double(ppm), ...
    "Endpoint", char(endpoint), "ExecutionStatus", localTernary(logical(enabled) && abs(ppm) > 0, "configured_pending_resampling", "disabled"));
end

function cfgSCO = localMergeSampleClockOffsetConfig(txCfg, rxCfg)
cfgSCO = struct( ...
    "Enabled", logical(txCfg.Enabled || rxCfg.Enabled), ...
    "PPM", double(txCfg.PPM + rxCfg.PPM), ...
    "TxPPM", double(txCfg.PPM), ...
    "RxPPM", double(rxCfg.PPM), ...
    "ExecutionStatus", localTernary(logical(txCfg.Enabled || rxCfg.Enabled), "configured_pending_resampling", "disabled"));
end

function [y, rows] = localApplyIQStage(x, stageCfg, stageName, endpoint, rows)
fn = @(z) localApplyIQModel(z, stageCfg.GainImbalance_dB, stageCfg.PhaseImbalance_deg);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "gain_imbalance_dB";
row.Parameter1Value = double(stageCfg.GainImbalance_dB);
row.Parameter2Name = "phase_imbalance_deg";
row.Parameter2Value = double(stageCfg.PhaseImbalance_deg);
if stageCfg.Enabled && ~(abs(stageCfg.GainImbalance_dB) > 1e-12 || abs(stageCfg.PhaseImbalance_deg) > 1e-12)
    row.Applied = false;
    row.Status = "configured_zero_noop";
end
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyPAStage(x, stageCfg, cfg, stageName, endpoint, rows,stream)
fn = @(z) localApplyPAWithConfig(z, cfg);
if ~isempty(stream), fn=@(z)stream.applyPA(z); end
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "backoff_dB";
row.Parameter1Value = double(stageCfg.Backoff_dB);
row.Parameter2Name = "model";
row.Parameter2Value = NaN;
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_pa_model", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyElementRFStage(x, stageCfg, cfg, stageName, endpoint, rows,stream)
fn = @(z) localApplyElementRFModel(z, stageCfg, cfg,~isempty(stream));
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "element_gain_dB_rms";
row.Parameter1Value = localRMSFinite(stageCfg.Gain_dB);
row.Parameter2Name = "element_phase_deg_rms";
row.Parameter2Value = localRMSFinite(stageCfg.Phase_deg);
row.Parameter3Name = "element_count";
if stageCfg.Enabled && isempty(stream)
    row.Parameter3Value = localResolveElementCountForStage(x, stageCfg, cfg);
else
    row.Parameter3Value = size(x, 2);
end
if stageCfg.Enabled && row.Applied && logical(stageCfg.MutualCouplingEnabled)
    row.Status = "applied_element_analog_rf_gain_phase_mutual_coupling";
else
    row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_element_analog_rf_gain_phase", row.Status);
end
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyPhaseNoiseStage(x, stageCfg, stageName, endpoint, rows)
fn = @(z) localApplyPhaseNoiseWithConfig(z, stageCfg);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "seed";
row.Parameter1Value = double(stageCfg.Seed);
row.Parameter2Name = "backend";
row.Parameter2Value = NaN;
if stageCfg.Enabled && row.Applied
    row.Status = "applied_sample_domain_phase_noise";
elseif stageCfg.Enabled
    row.Status = "configured_not_applied";
end
row.Backend = string(stageCfg.Backend);
row.TruthClassification = string(stageCfg.TruthClassification);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyCFOStage(x, stageCfg, stageName, endpoint, rows,stream)
fn = @(z) localApplyCFO(z, stageCfg.CFO_Hz, stageCfg.SampleRate_Hz);
if ~isempty(stream), fn=@(z)stream.applyCFO(z,stageCfg.CFO_Hz); end
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "cfo_Hz";
row.Parameter1Value = double(stageCfg.CFO_Hz);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_cfo_rotation", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyTimingStage(x, stageCfg, stageName, endpoint, rows,stream)
fn = @(z) sixgr.util.applyFractionalSampleDelay(z, stageCfg.TimingOffset_samples);
if ~isempty(stream), fn=@(z)stream.applyTiming(z,stageCfg.TimingOffset_samples); end
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "timing_offset_samples";
row.Parameter1Value = double(stageCfg.TimingOffset_samples);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_fractional_sample_delay", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplySampleClockOffsetStage(x, stageCfg, stageName, endpoint, rows)
fn = @(z) localApplySampleClockOffset(z, stageCfg.PPM);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "sample_clock_offset_ppm";
row.Parameter1Value = double(stageCfg.PPM);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_sample_clock_resampling", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyAGCStage(x, stageCfg, stageName, endpoint, rows,stream)
if isempty(stream)
    [gainLinear, gainDb] = localResolveAGCGain(x, stageCfg);
    fn = @(z) z .* cast(gainLinear, "like", z);
else
    gainDb=NaN; % A variable sample gain has no single applied dB value.
    fn=@(z)stream.applyAGC(z);
end
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "agc_gain_dB";
row.Parameter1Value = double(gainDb);
row.Parameter2Name = "target_rms";
row.Parameter2Value = double(stageCfg.TargetRMS);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_rx_agc_gain", row.Status);
if stageCfg.Enabled && abs(gainDb) <= 1e-12
    row.Status = "configured_unity_gain_noop";
end
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyADCStage(x, stageCfg, stageName, endpoint, rows,stream)
if stageCfg.Enabled
    if isempty(stream)
        result = sixgr.rf.runtime.ADCModel.quantize(x, struct( ...
            "Bits",stageCfg.Bits,"FullScale",stageCfg.FullScale, ...
            "Convention","signed_midtread"));
    else
        result=stream.applyADC(x);
    end
    y = result.Output;
    [~, row] = localApplyGenericStage(x, true, stageName, endpoint, @(z)y);
    row.ErrorVariance = double(result.ErrorVariance);
else
    y = x;
    [~, row] = localApplyGenericStage(x, false, stageName, endpoint, @(z)z);
end
row.Parameter1Name = "adc_bits";
row.Parameter1Value = double(stageCfg.Bits);
row.Parameter2Name = "full_scale";
row.Parameter2Value = double(stageCfg.FullScale);
row.Parameter3Name = "clipping_ratio";
row.Parameter3Value = localADCClippingRatio(x, stageCfg.FullScale);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_complex_adc_quantization", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyCarrierPhaseStage(x, stageCfg, rows)
endpoint = extractBefore(string(stageCfg.StageName), "_");
fn = @(z) z .* exp(1j * double(stageCfg.PhaseOffset_deg) * pi / 180);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageCfg.StageName, endpoint, fn);
row.Parameter1Name = "carrier_phase_offset_deg";
row.Parameter1Value = double(stageCfg.PhaseOffset_deg);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_sample_domain_constant_rotation", row.Status);
rows(end + 1, 1) = row;
end

function [y, row] = localApplyGenericStage(x, enabled, stageName, endpoint, fn)
row = localStageRowTemplate();
row.StageName = string(stageName);
row.Endpoint = string(endpoint);
row.Enabled = logical(enabled);
row.InputPower = localMeanPower(x);
y = x;
if logical(enabled)
    row.InputHash = string(localWaveformHash(x));
    y = fn(x);
    row.OutputPower = localMeanPower(y);
    row.OutputHash = string(localWaveformHash(y));
    row.Applied = row.InputHash ~= row.OutputHash;
    row.PowerDelta_dB = 10 * log10(max(row.OutputPower, realmin) ./ max(row.InputPower, realmin));
    row.Status = localTernary(row.Applied, "applied", "configured_identity_no_sample_change");
else
    row.InputHash = "disabled_identity";
    row.OutputPower = row.InputPower;
    row.OutputHash = row.InputHash;
    row.Applied = false;
    row.PowerDelta_dB = 0;
    row.Status = "disabled_identity";
end
end

function row = localStageRowTemplate()
row = struct( ...
    "StageName", "", ...
    "Endpoint", "", ...
    "Enabled", false, ...
    "Applied", false, ...
    "Status", "", ...
    "InputPower", NaN, ...
    "OutputPower", NaN, ...
    "PowerDelta_dB", NaN, ...
    "Parameter1Name", "", ...
    "Parameter1Value", NaN, ...
    "Parameter2Name", "", ...
    "Parameter2Value", NaN, ...
    "Parameter3Name", "", ...
    "Parameter3Value", NaN, ...
    "InputHash", "", ...
    "OutputHash", "", ...
    "Backend", "", ...
    "TruthClassification", "", ...
    "ErrorVariance", NaN);
end

function replay = localBuildReplay(chain, rows, stageOrder, xRef, y)
stageNames = string({rows.StageName}).';
phaseRows = rows(contains(stageNames, "phase_noise"));
iqRows = rows(ismember(stageNames, ["tx_iq","rx_iq"]));
paRows = rows(stageNames == "tx_pa");
cfoRows = rows(contains(stageNames, "cfo"));
timingRows = rows(contains(stageNames, "timing"));
adcRows = rows(stageNames == "rx_adc");
agcRows = rows(stageNames == "rx_agc");
sampleClockRows = rows(contains(stageNames, "sample_clock_offset"));
elementRows = rows(contains(stageNames, "element_rf"));

cfoHz = localSumRowParameter(cfoRows, "cfo_Hz");
timingOffset = localSumRowParameter(timingRows, "timing_offset_samples");
sampleClockPpm = localSumRowParameter(sampleClockRows, "sample_clock_offset_ppm");
[iqGain, iqPhase] = localLastIQConfig(chain);
iqMetrics = localMeasureIQImbalanceRuntime(xRef, y);
iqConfigured = ~isempty(iqRows) && any([iqRows.Enabled]);
iqApplied = ~isempty(iqRows) && any([iqRows.Applied]);
iqConfiguredStatus = string(iqMetrics.MeasurementStatus);
if ~iqConfigured
    iqConfiguredStatus = "disabled";
end

phaseApplied = ~isempty(phaseRows) && any([phaseRows.Applied]);
phaseEnabled = ~isempty(phaseRows) && any([phaseRows.Enabled]);
phaseBefore = localFirstRowHash(phaseRows, "InputHash");
phaseAfter = localLastRowHash(phaseRows, "OutputHash");
phaseBackend = localUniqueTokenSet(string({phaseRows.Backend}));
phaseTruth = localUniqueTokenSet(string({phaseRows.TruthClassification}));
phaseRMS = NaN;
if phaseApplied
    phaseDelta = angle(double(y(:)) .* conj(double(xRef(:))));
    phaseRMS = sqrt(mean(double(unwrap(phaseDelta)).^2, "omitnan"));
end

replay = struct( ...
    "RFImpairmentChainContract", string(chain.ContractVersion), ...
    "RFEndpoint", string(chain.Endpoint), ...
    "RFStageOrder", strjoin(stageOrder, ">"), ...
    "RFDisabledIdentity", ~any([rows.Enabled]) && ~any([rows.Applied]), ...
    "RFConfiguredStageCount", double(nnz([rows.Enabled])), ...
    "RFAppliedStageCount", double(nnz([rows.Applied])), ...
    "RFInputPower", localMeanPower(xRef), ...
    "RFOutputPower", localMeanPower(y), ...
    "RFPowerDelta_dB", 10 * log10(max(localMeanPower(y), realmin) ./ max(localMeanPower(xRef), realmin)), ...
    "InjectedCFO_Hz", double(cfoHz), ...
    "CFOApplied", ~isempty(cfoRows) && any([cfoRows.Applied]), ...
    "InjectedTimingOffset_samples", double(timingOffset), ...
    "TimingOffsetApplied", ~isempty(timingRows) && any([timingRows.Applied]), ...
    "SampleClockOffsetEnabled", ~isempty(sampleClockRows) && any([sampleClockRows.Enabled]), ...
    "SampleClockOffsetApplied", ~isempty(sampleClockRows) && any([sampleClockRows.Applied]), ...
    "SampleClockOffsetPpm", double(sampleClockPpm), ...
    "SampleClockOffsetExecutionStatus", localStageSetStatus(sampleClockRows), ...
    "PhaseNoiseConfigured", logical(phaseEnabled), ...
    "PhaseNoiseApplied", logical(phaseApplied), ...
    "PhaseNoiseAvailableBackend", char(phaseBackend), ...
    "PhaseNoiseTruthClassification", char(phaseTruth), ...
    "PhaseNoiseApproximationReason", "", ...
    "PhaseNoiseExecutionStatus", localPhaseNoiseStatus(phaseRows), ...
    "PhaseNoiseRMS_rad", double(phaseRMS), ...
    "PhaseNoiseSeed", localFirstPhaseNoiseSeed(rows), ...
    "PhaseNoiseLevelApplied", localMeanPhaseNoiseLevel(chain), ...
    "PhaseNoiseWaveformBeforeHash", char(phaseBefore), ...
    "PhaseNoiseWaveformAfterHash", char(phaseAfter), ...
    "IQImbalanceConfigured", logical(iqConfigured), ...
    "IQImbalanceApplied", logical(iqApplied), ...
    "IQImbalanceModel", "widely_linear_alpha_beta", ...
    "ConfiguredIQGainImbalance_dB", double(iqGain), ...
    "ConfiguredIQPhaseImbalance_deg", double(iqPhase), ...
    "ConfiguredIQImbalanceSource", "sixgr.rf.applyRFImpairmentChain", ...
    "IQImbalanceMirrorPowerRatio_dB", double(iqMetrics.MirrorPowerRatio_dB), ...
    "IQImbalanceImageRejection_dB", double(iqMetrics.ImageRejection_dB), ...
    "IQImbalanceIQPowerRatio_dB", double(iqMetrics.IQPowerRatio_dB), ...
    "IQImbalanceIQCorrelation", double(iqMetrics.IQCorrelation), ...
    "IQImbalanceEstimatedAlphaAbs", double(iqMetrics.EstimatedAlphaAbs), ...
    "IQImbalanceEstimatedBetaAbs", double(iqMetrics.EstimatedBetaAbs), ...
    "IQImbalanceMeasurementSource", char(iqMetrics.MeasurementSource), ...
    "IQImbalanceMeasurementStatus", char(iqConfiguredStatus), ...
    "IQImbalanceDiagnosticStatus", char(iqMetrics.MeasurementStatus), ...
    "PAEnabled", ~isempty(paRows) && any([paRows.Enabled]), ...
    "PAApplied", ~isempty(paRows) && any([paRows.Applied]), ...
    "PAModel", string(chain.TxPA.Model), ...
    "PABackoff_dB", double(chain.TxPA.Backoff_dB), ...
    "PACompression_dB", localStagePowerDelta(paRows), ...
    "PAExecutionStatus", localStageStatus(paRows), ...
    "ElementRFEnabled", ~isempty(elementRows) && any([elementRows.Enabled]), ...
    "ElementRFApplied", ~isempty(elementRows) && any([elementRows.Applied]), ...
    "ElementRFExecutionStatus", localStageSetStatus(elementRows), ...
    "ElementRFStageCount", double(nnz([elementRows.Enabled])), ...
    "MutualCouplingEnabled", logical(chain.TxElementRF.MutualCouplingEnabled || chain.RxElementRF.MutualCouplingEnabled), ...
    "MutualCouplingApplied", localMutualCouplingApplied(chain, elementRows), ...
    "MutualCouplingMatrixSize", char(localMutualCouplingMatrixSize(chain)), ...
    "AGCEnabled", ~isempty(agcRows) && any([agcRows.Enabled]), ...
    "AGCApplied", ~isempty(agcRows) && any([agcRows.Applied]), ...
    "AGCGain_dB", localSumRowParameter(agcRows, "agc_gain_dB"), ...
    "AGCTargetRMS", double(chain.RxAGC.TargetRMS), ...
    "AGCExecutionStatus", localStageStatus(agcRows), ...
    "ADCQuantizationApplied", ~isempty(adcRows) && any([adcRows.Applied]), ...
    "ADCBits", double(chain.RxADC.Bits), ...
    "ADCFullScale", double(chain.RxADC.FullScale), ...
    "ADCClippingRatio", localSumRowParameter(adcRows, "clipping_ratio"), ...
    "ADCQuantizationErrorVariance", localLastFiniteRowValue(adcRows, "ErrorVariance"), ...
    "DACBits", double(chain.RxADC.DACBits), ...
    "SampleClockOffsetTxPpm", double(chain.SampleClockOffset.TxPPM), ...
    "SampleClockOffsetRxPpm", double(chain.SampleClockOffset.RxPPM));
end

function strictOk = localResolveStrictOk(chain, beforeHash, afterHash, rows, strictMutationRequired)
configuredAny = any([rows.Enabled]);
appliedAllEnabled = all(~[rows.Enabled] | [rows.Applied] | startsWith(string({rows.Status}), "configured_zero"));
if strictMutationRequired && configuredAny
    mutationOk = string(beforeHash) ~= string(afterHash);
else
    mutationOk = true;
end
strictOk = logical(appliedAllEnabled && mutationOk);
end

function tf = localMutualCouplingApplied(chain, elementRows)
enabled = logical(chain.TxElementRF.MutualCouplingEnabled || chain.RxElementRF.MutualCouplingEnabled);
tf = false;
if ~enabled || isempty(elementRows)
    return;
end
tf = any([elementRows.Applied]) && any(contains(string({elementRows.Status}), "mutual_coupling"));
end

function txt = localMutualCouplingMatrixSize(chain)
sizes = strings(0, 1);
if logical(chain.TxElementRF.MutualCouplingEnabled) && ~isempty(chain.TxElementRF.MutualCouplingMatrix)
    sizes(end + 1, 1) = "tx:" + localMatrixSizeToken(chain.TxElementRF.MutualCouplingMatrix); %#ok<AGROW>
end
if logical(chain.RxElementRF.MutualCouplingEnabled) && ~isempty(chain.RxElementRF.MutualCouplingMatrix)
    sizes(end + 1, 1) = "rx:" + localMatrixSizeToken(chain.RxElementRF.MutualCouplingMatrix); %#ok<AGROW>
end
if isempty(sizes)
    txt = "";
else
    txt = strjoin(sizes, ";");
end
end

function txt = localMatrixSizeToken(M)
txt = string(size(M, 1)) + "x" + string(size(M, 2));
end

function reason = localStrictFailureReason(chain, beforeHash, afterHash, rows, strictMutationRequired)
parts = strings(0, 1);
bad = [rows.Enabled] & ~[rows.Applied] & ~startsWith(string({rows.Status}), "configured_zero");
if any(bad)
    parts(end + 1, 1) = "configured_stage_not_applied:" + strjoin(string({rows(bad).StageName}), ","); %#ok<AGROW>
end
if strictMutationRequired && any([rows.Enabled]) && string(beforeHash) == string(afterHash)
    parts(end + 1, 1) = "rf_configured_waveform_unchanged"; %#ok<AGROW>
end
reason = strjoin(parts, "|");
end

function y = localApplyCFO(x, cfoHz, fs)
y = x;
if ~(isfinite(fs) && fs > 0 && isfinite(cfoHz) && abs(cfoHz) > 0)
    return;
end
n = (0:size(x, 1)-1).';
rot = exp(1j * 2 * pi * double(cfoHz) / double(fs) .* n);
y = x .* cast(rot, "like", x);
end

function y = localApplyPAWithConfig(x, cfg)
[profile,canonical] = sixgr.rf.runtime.PAProfile.fromConfiguration(cfg);
if canonical
    [y,~] = sixgr.rf.runtime.PAProfile.apply(x,profile);
    return;
end
pa = sixgr.rf.PAModel(cfg);
y = pa.apply(x);
end

function y = localApplyElementRFModel(x, stageCfg, cfg,physicalSamples)
if physicalSamples
    % The stream composer has already projected logical ports. Applying
    % that matrix again would corrupt physical antenna gains/coupling.
    M=eye(size(x,2));
else
    M = localResolvePortToElementMatrixForStage(x, stageCfg, cfg);
end
g = localElementComplexGain(stageCfg, size(M, 1));
coupling = localElementMutualCouplingMatrix(stageCfg, size(M, 1));
if size(x, 2) == size(M, 1)
    xElem = x .* cast(reshape(g, 1, []), "like", x);
    y = xElem * cast(coupling.', "like", x);
    return;
end
xElem = x * cast(M.', "like", x);
xElem = xElem .* cast(reshape(g, 1, []), "like", x);
xElem = xElem * cast(coupling.', "like", x);
y = xElem * cast(M, "like", x);
end

function y = localApplyPhaseNoiseWithConfig(x, stageCfg)
y = stageCfg.Model.apply(x, stageCfg.Model.SampleRate_Hz);
end

function y = localApplyIQModel(x, gainImb_dB, phaseImb_deg)
[y,~] = sixgr.rf.runtime.IQImbalanceProfile.apply( ...
    x,gainImb_dB,phaseImb_deg,0);
end

function y = localApplySampleClockOffset(x, ppm)
y = x;
ppm = double(ppm);
if ~(isfinite(ppm) && abs(ppm) > 0) || isempty(x)
    return;
end
n = size(x, 1);
if n <= 1
    return;
end
resampler = sixgr.rf.runtime.StatefulSampleRateOffsetResampler( ...
    1, ppm, 0.4, 1);
[y, ~] = resampler.process(x, "PreserveLength", true);
end

function [gainLinear, gainDb] = localResolveAGCGain(x, stageCfg)
gainLinear = 1;
gainDb = 0;
if ~logical(stageCfg.Enabled) || isempty(x)
    return;
end
rmsIn = sqrt(mean(abs(double(x(:))).^2, "omitnan"));
if ~(isfinite(rmsIn) && rmsIn > 0)
    return;
end
gainDb = 20 * log10(double(stageCfg.TargetRMS) / rmsIn);
gainDb = min(max(gainDb, double(stageCfg.MinGain_dB)), double(stageCfg.MaxGain_dB));
gainLinear = 10.^(gainDb ./ 20);
end

function y = localQuantizeComplex(x, bits, fullScale)
levels = 2^max(1, round(double(bits)));
scale = max(double(fullScale), eps);
maxCode = levels / 2 - 1;
xr = min(max(real(double(x)), -scale), scale);
xi = min(max(imag(double(x)), -scale), scale);
yr = round((xr ./ scale) * maxCode) ./ maxCode .* scale;
yi = round((xi ./ scale) * maxCode) ./ maxCode .* scale;
y = complex(yr, yi);
end

function ratio = localADCClippingRatio(x, fullScale)
ratio = NaN;
if isempty(x) || ~(isfinite(fullScale) && fullScale > 0)
    return;
end
vals = [abs(real(double(x(:)))) > double(fullScale); abs(imag(double(x(:)))) > double(fullScale)];
ratio = mean(double(vals), "omitnan");
end

function evm = localEVM(ref, meas)
err = double(meas(:)) - double(ref(:));
den = sqrt(mean(abs(double(ref(:))).^2, "omitnan"));
num = sqrt(mean(abs(err).^2, "omitnan"));
evmPct = 100 * num / max(den, eps);
evm = struct("EVMPercent", double(evmPct), "EVMDb", 20 * log10(max(evmPct / 100, eps)));
end

function metrics = localMeasureIQImbalanceRuntime(xRef, yObs)
metrics = struct( ...
    "MirrorPowerRatio_dB", NaN, ...
    "ImageRejection_dB", NaN, ...
    "IQPowerRatio_dB", NaN, ...
    "IQCorrelation", NaN, ...
    "EstimatedAlphaAbs", NaN, ...
    "EstimatedBetaAbs", NaN, ...
    "MeasurementSource", "sample_domain_widely_linear_fit_after_iq_stage", ...
    "MeasurementStatus", "not_measured");
x = double(xRef(:));
y = double(yObs(:));
mask = isfinite(real(x)) & isfinite(imag(x)) & isfinite(real(y)) & isfinite(imag(y));
if nnz(mask) < 8
    metrics.MeasurementStatus = "insufficient_samples";
    return;
end
x = x(mask);
y = y(mask);
A = [x, conj(x)];
if rank(A) < 2
    metrics.MeasurementStatus = "degenerate_reference";
    return;
end
coeff = A \ y;
alpha = coeff(1);
beta = coeff(2);
metrics.EstimatedAlphaAbs = abs(alpha);
metrics.EstimatedBetaAbs = abs(beta);
desiredPower = mean(abs(alpha .* x).^2, "omitnan");
imagePower = mean(abs(beta .* conj(x)).^2, "omitnan");
numericImageFloor = max(realmin, eps(max(1, abs(double(desiredPower)))));
if isfinite(desiredPower) && desiredPower > 0 && isfinite(imagePower) && imagePower > 0
    rawMirrorRatio_dB = 10 * log10(imagePower / desiredPower);
    rawImageRejection_dB = 10 * log10(desiredPower / imagePower);
    if abs(beta) < 1e-9 || imagePower <= numericImageFloor || rawImageRejection_dB > 100
        metrics.MirrorPowerRatio_dB = -100;
        metrics.ImageRejection_dB = 100;
        metrics.MeasurementStatus = "below_numeric_floor_capped";
    else
        metrics.MirrorPowerRatio_dB = max(-100, min(100, rawMirrorRatio_dB));
        metrics.ImageRejection_dB = max(-100, min(100, rawImageRejection_dB));
        metrics.MeasurementStatus = "measured";
    end
elseif isfinite(desiredPower) && desiredPower > 0 && isfinite(imagePower) && imagePower <= numericImageFloor
    metrics.MirrorPowerRatio_dB = -100;
    metrics.ImageRejection_dB = 100;
    metrics.MeasurementStatus = "below_numeric_floor_capped";
end
iVar = var(real(y), 1, "omitnan");
qVar = var(imag(y), 1, "omitnan");
if isfinite(iVar) && isfinite(qVar) && iVar > 0 && qVar > 0
    metrics.IQPowerRatio_dB = 10 * log10(iVar / qVar);
end
rho = corrcoef(real(y), imag(y));
if isequal(size(rho), [2 2]) && isfinite(rho(1, 2))
    metrics.IQCorrelation = rho(1, 2);
end
end

function hash = localWaveformHash(x)
if isempty(x)
    hash = sixgr.util.sha256Hex(uint8(char("empty:" + string(class(x)))));
    return;
end
if ~(isnumeric(x) || islogical(x))
    hash = sixgr.channel.hashChannelRFConfig(struct("Class", class(x), "Size", size(x)));
    return;
end
header = uint8(char("waveform:" + string(class(x)) + ":"));
dimBytes = reshape(typecast(uint64(size(x)), "uint8"), [], 1);
realBytes = reshape(typecast(double(real(x(:))), "uint8"), [], 1);
imagBytes = reshape(typecast(double(imag(x(:))), "uint8"), [], 1);
hash = sixgr.util.sha256Hex([header(:); dimBytes; realBytes; imagBytes]);
end

function M = localResolvePortToElementMatrixForStage(x, stageCfg, cfg)
numCols = size(x, 2);
M = [];
role = lower(string(stageCfg.Role));
if role == "bs"
    antenna = sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingBSAntenna", struct());
else
    antenna = sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeUEAntenna", struct());
end
if isstruct(antenna)
    M = double(sixgr.util.structGet(antenna, "PortToElementMatrix", []));
end
if isempty(M)
    M = double(sixgr.util.structGet(cfg, "rf." + role + ".PortToElementMatrix", []));
end
if isempty(M)
    M = eye(numCols);
end
if ~ismatrix(M) || size(M, 2) ~= numCols
    if size(M, 1) == numCols
        M = eye(numCols);
    else
        error("sixgr:rf:ElementRFPortMappingMismatch", ...
            "Element RF stage for %s has PortToElementMatrix size %dx%d but waveform has %d column(s).", ...
            upper(char(role)), size(M, 1), size(M, 2), numCols);
    end
end
end

function nElem = localResolveElementCountForStage(x, stageCfg, cfg)
M = localResolvePortToElementMatrixForStage(x, stageCfg, cfg);
nElem = size(M, 1);
end

function C = localElementMutualCouplingMatrix(stageCfg, nElem)
nElem = max(1, round(double(nElem)));
enabled = logical(sixgr.util.structGet(stageCfg, "MutualCouplingEnabled", false));
raw = sixgr.util.structGet(stageCfg, "MutualCouplingMatrix", []);
if isempty(raw)
    if enabled
        error("sixgr:rf:MutualCouplingMatrixMissing", ...
            "Mutual coupling is enabled but no element-domain coupling matrix was configured.");
    end
    C = eye(nElem);
    return;
end
C = double(raw);
if ~ismatrix(C) || ~isequal(size(C), [nElem nElem]) || any(~isfinite(C(:)))
    error("sixgr:rf:MutualCouplingMatrixMismatch", ...
        "Mutual coupling matrix must be finite and sized %dx%d for the element-domain waveform.", ...
        nElem, nElem);
end
end

function g = localElementComplexGain(stageCfg, nElem)
gainDb = localExpandVector(stageCfg.Gain_dB, nElem, 0);
phaseDeg = localExpandVector(stageCfg.Phase_deg, nElem, 0);
g = 10.^(gainDb ./ 20) .* exp(1j .* phaseDeg .* pi ./ 180);
end

function role = localEndpointRole(endpoint, direction)
endpoint = lower(string(endpoint));
direction = upper(string(direction));
if endpoint == "tx"
    role = "bs";
    if direction == "UL"
        role = "ue";
    end
else
    role = "ue";
    if direction == "UL"
        role = "bs";
    end
end
end

function out = localExpandVector(values, n, defaultValue)
n = max(1, round(double(n)));
values = double(values(:).');
if ~isreal(values) || any(~isfinite(values))
    error('sixgr:rf:InvalidElementRFVector','Element gain/phase values must be finite real data.');
end
if isempty(values)
    values = double(defaultValue);
end
if numel(values) == 1
    out = repmat(values, 1, n);
elseif numel(values) == n
    out = values;
else
    error('sixgr:rf:ElementRFVectorSizeMismatch', ...
        'Declare one shared value or exactly %d physical element values; do not truncate or repeat the last entry.',n);
end
end

function value = localRMSFinite(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = 0;
else
    value = sqrt(mean(values.^2, "omitnan"));
end
end

function token = localShortHash(hashValue)
txt = string(hashValue);
txt = strip(txt);
if strlength(txt) == 0
    token = "empty";
    return;
end
token = extractBetween(txt, 1, min(12, strlength(txt)));
if isempty(token)
    token = txt;
else
    token = token(1);
end
end

function p = localMeanPower(x)
if isempty(x)
    p = NaN;
else
    p = mean(abs(double(x(:))).^2, "omitnan");
end
end

function value = localFirstFinite(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function value = localFirstVector(varargin)
value = [];
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if ~isnumeric(raw) || ~isreal(raw) || ~isvector(raw) || any(~isfinite(raw(:)))
        error('sixgr:rf:InvalidElementRFVector', ...
            'Configured element gain/phase must be a finite real scalar or vector.');
    end
    raw = double(raw(:).');
    if ~isempty(raw)
        value = raw;
        return;
    end
end
end

function value = localFirstMatrix(varargin)
value = [];
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~isnumeric(raw) || ~ismatrix(raw)
        continue;
    end
    raw = double(raw);
    if ~isempty(raw) && all(isfinite(raw(:)))
        value = raw;
        return;
    end
end
end

function value = localFirstLogical(varargin)
value = [];
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if islogical(raw) || isnumeric(raw)
        value = logical(raw(1));
        return;
    end
    if ischar(raw) || isstring(raw)
        token = lower(strtrim(string(raw(1))));
        if any(token == ["true","1","yes","on","enabled"])
            value = true;
            return;
        elseif any(token == ["false","0","no","off","disabled"])
            value = false;
            return;
        end
    end
end
end

function value = localGetPath(s, path, defaultValue)
value = defaultValue;
parts = split(string(path), ".");
cur = s;
for i = 1:numel(parts)
    f = char(parts(i));
    if ~(isstruct(cur) && isfield(cur, f))
        return;
    end
    cur = cur.(f);
end
value = cur;
end

function tf = localHasPath(s, path)
parts = split(string(path), ".");
cur = s;
for i = 1:numel(parts)
    f = char(parts(i));
    if ~(isstruct(cur) && isfield(cur, f))
        tf = false;
        return;
    end
    cur = cur.(f);
end
tf = true;
end

function out = localTernary(cond, a, b)
if cond
    out = string(a);
else
    out = string(b);
end
end

function offset = localEndpointSeedOffset(endpoint)
if string(endpoint) == "rx"
    offset = 4301;
else
    offset = 3001;
end
end

function value = localSumRowParameter(rows, name)
value = 0;
if isempty(rows)
    return;
end
for i = 1:numel(rows)
    for pi = 1:3
        nameField = "Parameter" + string(pi) + "Name";
        valueField = "Parameter" + string(pi) + "Value";
        if isfield(rows(i), char(nameField)) && string(rows(i).(char(nameField))) == string(name) && ...
                isfield(rows(i), char(valueField)) && isfinite(double(rows(i).(char(valueField))))
            value = value + double(rows(i).(char(valueField)));
        end
    end
end
end

function value = localLastFiniteRowValue(rows, fieldName)
value = NaN;
if isempty(rows) || ~isfield(rows, char(fieldName))
    return;
end
values = double([rows.(char(fieldName))]);
values = values(isfinite(values));
if ~isempty(values)
    value = values(end);
end
end

function tf = localRFStrictProfileSelected(cfg)
profile = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "rf.specification.profile_id", ...
    sixgr.util.structGet(cfg, "rf.profile.id", "")))));
tf = strlength(profile) > 0 && any(profile == [ ...
    "ideal_phy_strict","rf_impaired_research", ...
    "rf_conformance_emulation_bs_fr1", ...
    "rf_conformance_emulation_ue_fr1", ...
    "rf_conformance_emulation_fr2"]);
end

function [gain, phase] = localLastIQConfig(chain)
gain = 0;
phase = 0;
if chain.RxIQ.Enabled
    gain = chain.RxIQ.GainImbalance_dB;
    phase = chain.RxIQ.PhaseImbalance_deg;
elseif chain.TxIQ.Enabled
    gain = chain.TxIQ.GainImbalance_dB;
    phase = chain.TxIQ.PhaseImbalance_deg;
end
end

function value = localUniqueTokenSet(values)
values = string(values(:));
values = values(~ismissing(values));
values = strip(values);
values = values(strlength(values) > 0);
if isempty(values)
    value = "";
else
    value = join(unique(values, "stable"), ";");
end
end

function status = localPhaseNoiseStatus(rows)
if isempty(rows) || ~any([rows.Enabled])
    status = "disabled";
elseif any([rows.Applied])
    status = "applied_sample_domain_phase_noise";
else
    status = "configured_not_applied";
end
end

function seed = localFirstPhaseNoiseSeed(rows)
seed = NaN;
for i = 1:numel(rows)
    if contains(string(rows(i).StageName), "phase_noise") && string(rows(i).Parameter1Name) == "seed"
        seed = double(rows(i).Parameter1Value);
        return;
    end
end
end

function level = localMeanPhaseNoiseLevel(chain)
levels = [];
if chain.TxPhaseNoise.Enabled
    levels = [levels, double(chain.TxPhaseNoise.Model.Level_dBcHz(:).')]; %#ok<AGROW>
end
if chain.RxPhaseNoise.Enabled
    levels = [levels, double(chain.RxPhaseNoise.Model.Level_dBcHz(:).')]; %#ok<AGROW>
end
levels = levels(isfinite(levels));
if isempty(levels)
    level = NaN;
else
    level = mean(levels);
end
end

function hash = localFirstRowHash(rows, fieldName)
hash = "";
if isempty(rows)
    return;
end
hash = string(rows(1).(fieldName));
end

function hash = localLastRowHash(rows, fieldName)
hash = "";
if isempty(rows)
    return;
end
hash = string(rows(end).(fieldName));
end

function delta = localStagePowerDelta(rows)
delta = NaN;
if ~isempty(rows)
    delta = double(rows(end).PowerDelta_dB);
end
end

function status = localStageStatus(rows)
status = "disabled";
if ~isempty(rows)
    status = string(rows(end).Status);
end
end

function status = localStageSetStatus(rows)
if isempty(rows) || ~any([rows.Enabled])
    status = "disabled";
elseif all([rows.Enabled] == [rows.Applied])
    status = "applied";
elseif any([rows.Applied])
    status = "partially_applied";
else
    status = string(rows(end).Status);
end
end
