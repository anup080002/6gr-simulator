function out = applyRFImpairmentChain(x, cfg, varargin)
%APPLYRFIMPAIRMENTCHAIN Apply one ordered RF impairment pipeline to samples.
% Keep this file ASCII-only.
%
% Declared order:
%   Tx: IQ -> PA -> phase noise -> CFO -> sample timing
%   Rx: sample timing -> LO/CFO -> phase noise -> IQ -> ADC

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
p.parse(varargin{:});
opt = p.Results;

fs = double(opt.SampleRateHz);
if ~(isfinite(fs) && fs > 0)
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

xRef = x;
y = x;
beforeHash = sixgr.channel.hashChannelRFConfig(localWaveformHashPayload(y));
chain = localResolveChainConfig(cfg, fs, endpoint, logical(opt.UseLegacyGlobalConfig), ...
    logical(opt.ApplyPA), logical(opt.ApplyADC));

stageRows = repmat(localStageRowTemplate(), 0, 1);
stageOrder = strings(0, 1);
if chain.IncludeTx
    [y, stageRows] = localApplyIQStage(y, chain.TxIQ, "tx_iq", "tx", stageRows);
    [y, stageRows] = localApplyPAStage(y, chain.TxPA, cfg, "tx_pa", "tx", stageRows);
    [y, stageRows] = localApplyPhaseNoiseStage(y, chain.TxPhaseNoise, "tx_phase_noise", "tx", stageRows);
    [y, stageRows] = localApplyCFOStage(y, chain.TxCFO, "tx_cfo", "tx", stageRows);
    [y, stageRows] = localApplyTimingStage(y, chain.TxTiming, "tx_timing", "tx", stageRows);
    stageOrder = [stageOrder; "tx_iq"; "tx_pa"; "tx_phase_noise"; "tx_cfo"; "tx_timing"]; %#ok<AGROW>
end
if chain.IncludeRx
    [y, stageRows] = localApplyTimingStage(y, chain.RxTiming, "rx_timing", "rx", stageRows);
    [y, stageRows] = localApplyCFOStage(y, chain.RxCFO, "rx_lo_cfo", "rx", stageRows);
    [y, stageRows] = localApplyPhaseNoiseStage(y, chain.RxPhaseNoise, "rx_phase_noise", "rx", stageRows);
    [y, stageRows] = localApplyIQStage(y, chain.RxIQ, "rx_iq", "rx", stageRows);
    [y, stageRows] = localApplyADCStage(y, chain.RxADC, "rx_adc", "rx", stageRows);
    stageOrder = [stageOrder; "rx_timing"; "rx_lo_cfo"; "rx_phase_noise"; "rx_iq"; "rx_adc"]; %#ok<AGROW>
end
if strlength(string(chain.CarrierPhase.StageName)) > 0
    [y, stageRows] = localApplyCarrierPhaseStage(y, chain.CarrierPhase, stageRows);
    stageOrder = [stageOrder; string(chain.CarrierPhase.StageName)]; %#ok<AGROW>
end

afterHash = sixgr.channel.hashChannelRFConfig(localWaveformHashPayload(y));
evm = localEVM(xRef, y);
replay = localBuildReplay(chain, stageRows, stageOrder, xRef, y);
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
    "RFImpairmentChainId", "rf_" + localShortHash(afterHash), ...
    "Direction", string(opt.Direction), ...
    "TxOrRxSide", string(opt.MeasurementPoint), ...
    "Endpoint", string(endpoint), ...
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

function chain = localResolveChainConfig(cfg, fs, endpoint, useLegacy, applyPA, applyADC)
includeTx = any(endpoint == ["tx","txrx"]);
includeRx = any(endpoint == ["rx","txrx"]);
legacyToTx = useLegacy && includeTx;
legacyToRx = useLegacy && includeRx && ~includeTx;

chain = struct();
chain.ContractVersion = "sixgr.rf.ImpairmentChainConfig/v1";
chain.Endpoint = char(endpoint);
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
chain.TxPA = localResolvePAConfig(cfg, logical(applyPA));
chain.RxADC = localResolveADCConfig(cfg, logical(applyADC));
chain.CarrierPhase = localResolveCarrierPhaseConfig(cfg, endpoint, legacyToTx, legacyToRx);
chain.SampleClockOffset = localResolveSampleClockOffsetConfig(cfg);
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
enabled = logical(enabled) || abs(gain) > 1e-12 || abs(phase) > 1e-12;
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

function cfgADC = localResolveADCConfig(cfg, applyADC)
bits = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.adcBits", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationBits", NaN), ...
    NaN);
explicit = localHasPath(cfg, "rf.adcBits") || localHasPath(cfg, "phy.impairments.adcQuantizationBits") || ...
    localHasPath(cfg, "rf.adc.enable") || localHasPath(cfg, "phy.impairments.adcQuantizationEnabled");
enabled = logical(applyADC) && explicit && localFirstLogical( ...
    sixgr.util.structGet(cfg, "rf.adc.enable", []), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationEnabled", []), ...
    true);
if ~isfinite(bits)
    bits = NaN;
end
enabled = logical(enabled) && isfinite(bits) && bits > 0 && bits < 32;
dacBits = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.dacBits", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.dacQuantizationBits", NaN), ...
    NaN);
cfgADC = struct("Enabled", logical(enabled), "Bits", double(bits), "DACBits", double(dacBits));
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

function cfgSCO = localResolveSampleClockOffsetConfig(cfg)
ppm = double(sixgr.util.structGet(cfg, "rf.sampleClockOffset.ppm", ...
    sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetPpm", ...
    sixgr.util.structGet(cfg, "impairments.sample_clock_offset_ppm", 0))));
if ~isfinite(ppm)
    ppm = 0;
end
enabled = logical(sixgr.util.structGet(cfg, "rf.sampleClockOffset.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetEnabled", abs(ppm) > 0)));
cfgSCO = struct("Enabled", logical(enabled) && abs(ppm) > 0, "PPM", double(ppm), ...
    "ExecutionStatus", localTernary(logical(enabled) && abs(ppm) > 0, "configured_not_supported", "disabled"));
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

function [y, rows] = localApplyPAStage(x, stageCfg, cfg, stageName, endpoint, rows)
fn = @(z) localApplyPAWithConfig(z, cfg);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "backoff_dB";
row.Parameter1Value = double(stageCfg.Backoff_dB);
row.Parameter2Name = "model";
row.Parameter2Value = NaN;
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_memoryless_pa", row.Status);
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

function [y, rows] = localApplyCFOStage(x, stageCfg, stageName, endpoint, rows)
fn = @(z) localApplyCFO(z, stageCfg.CFO_Hz, stageCfg.SampleRate_Hz);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "cfo_Hz";
row.Parameter1Value = double(stageCfg.CFO_Hz);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_cfo_rotation", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyTimingStage(x, stageCfg, stageName, endpoint, rows)
fn = @(z) sixgr.util.applyFractionalSampleDelay(z, stageCfg.TimingOffset_samples);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "timing_offset_samples";
row.Parameter1Value = double(stageCfg.TimingOffset_samples);
row.Status = localTernary(stageCfg.Enabled && row.Applied, "applied_fractional_sample_delay", row.Status);
rows(end + 1, 1) = row;
end

function [y, rows] = localApplyADCStage(x, stageCfg, stageName, endpoint, rows)
fn = @(z) localQuantizeComplex(z, stageCfg.Bits);
[y, row] = localApplyGenericStage(x, stageCfg.Enabled, stageName, endpoint, fn);
row.Parameter1Name = "adc_bits";
row.Parameter1Value = double(stageCfg.Bits);
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
row.InputHash = string(sixgr.channel.hashChannelRFConfig(localWaveformHashPayload(x)));
y = x;
if logical(enabled)
    y = fn(x);
    row.OutputPower = localMeanPower(y);
    row.OutputHash = string(sixgr.channel.hashChannelRFConfig(localWaveformHashPayload(y)));
    row.Applied = row.InputHash ~= row.OutputHash;
    row.PowerDelta_dB = 10 * log10(max(row.OutputPower, realmin) ./ max(row.InputPower, realmin));
    row.Status = localTernary(row.Applied, "applied", "configured_identity_no_sample_change");
else
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
    "InputHash", "", ...
    "OutputHash", "", ...
    "Backend", "", ...
    "TruthClassification", "");
end

function replay = localBuildReplay(chain, rows, stageOrder, xRef, y)
stageNames = string({rows.StageName}).';
phaseRows = rows(contains(stageNames, "phase_noise"));
iqRows = rows(ismember(stageNames, ["tx_iq","rx_iq"]));
paRows = rows(stageNames == "tx_pa");
cfoRows = rows(contains(stageNames, "cfo"));
timingRows = rows(contains(stageNames, "timing"));
adcRows = rows(stageNames == "rx_adc");

cfoHz = localSumRowParameter(cfoRows, "cfo_Hz");
timingOffset = localSumRowParameter(timingRows, "timing_offset_samples");
[iqGain, iqPhase] = localLastIQConfig(chain);
iqMetrics = localMeasureIQImbalanceRuntime(xRef, y);

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
    "IQImbalanceConfigured", ~isempty(iqRows) && any([iqRows.Enabled]), ...
    "IQImbalanceApplied", ~isempty(iqRows) && any([iqRows.Applied]), ...
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
    "IQImbalanceMeasurementStatus", char(iqMetrics.MeasurementStatus), ...
    "PAEnabled", ~isempty(paRows) && any([paRows.Enabled]), ...
    "PAApplied", ~isempty(paRows) && any([paRows.Applied]), ...
    "PAModel", string(chain.TxPA.Model), ...
    "PABackoff_dB", double(chain.TxPA.Backoff_dB), ...
    "PACompression_dB", localStagePowerDelta(paRows), ...
    "PAExecutionStatus", localStageStatus(paRows), ...
    "ADCQuantizationApplied", ~isempty(adcRows) && any([adcRows.Applied]), ...
    "ADCBits", double(chain.RxADC.Bits), ...
    "DACBits", double(chain.RxADC.DACBits), ...
    "SampleClockOffsetEnabled", logical(chain.SampleClockOffset.Enabled), ...
    "SampleClockOffsetPpm", double(chain.SampleClockOffset.PPM), ...
    "SampleClockOffsetExecutionStatus", char(string(chain.SampleClockOffset.ExecutionStatus)));
end

function strictOk = localResolveStrictOk(chain, beforeHash, afterHash, rows, strictMutationRequired)
configuredAny = any([rows.Enabled]);
appliedAllEnabled = all(~[rows.Enabled] | [rows.Applied] | startsWith(string({rows.Status}), "configured_zero"));
sampleClockOk = ~logical(chain.SampleClockOffset.Enabled);
if strictMutationRequired && configuredAny
    mutationOk = string(beforeHash) ~= string(afterHash);
else
    mutationOk = true;
end
strictOk = logical(appliedAllEnabled && sampleClockOk && mutationOk);
end

function reason = localStrictFailureReason(chain, beforeHash, afterHash, rows, strictMutationRequired)
parts = strings(0, 1);
bad = [rows.Enabled] & ~[rows.Applied] & ~startsWith(string({rows.Status}), "configured_zero");
if any(bad)
    parts(end + 1, 1) = "configured_stage_not_applied:" + strjoin(string({rows(bad).StageName}), ","); %#ok<AGROW>
end
if logical(chain.SampleClockOffset.Enabled)
    parts(end + 1, 1) = "sample_clock_offset_configured_but_unsupported"; %#ok<AGROW>
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
pa = sixgr.rf.PAModel(cfg);
y = pa.apply(x);
end

function y = localApplyPhaseNoiseWithConfig(x, stageCfg)
y = stageCfg.Model.apply(x, stageCfg.Model.SampleRate_Hz);
end

function y = localApplyIQModel(x, gainImb_dB, phaseImb_deg)
g = 10.^(double(gainImb_dB) / 20);
phi = double(phaseImb_deg) * pi / 180;
alpha = 0.5 * (1 + g * exp(-1j * phi));
beta = 0.5 * (1 - g * exp(1j * phi));
y = alpha .* x + beta .* conj(x);
end

function y = localQuantizeComplex(x, bits)
levels = 2^max(1, round(double(bits)));
scale = max(max(abs([real(double(x(:))); imag(double(x(:)))])), eps);
yr = round((real(x) ./ scale) * (levels / 2 - 1)) ./ (levels / 2 - 1) .* scale;
yi = round((imag(x) ./ scale) * (levels / 2 - 1)) ./ (levels / 2 - 1) .* scale;
y = complex(yr, yi);
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
if isfinite(desiredPower) && desiredPower > 0 && isfinite(imagePower) && imagePower > 0
    metrics.MirrorPowerRatio_dB = 10 * log10(imagePower / desiredPower);
    metrics.ImageRejection_dB = 10 * log10(desiredPower / imagePower);
    metrics.MeasurementStatus = "measured";
elseif isfinite(desiredPower) && desiredPower > 0
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

function payload = localWaveformHashPayload(x)
payload = struct("Real", real(double(x(:).')), "Imag", imag(double(x(:).')), "Size", size(x));
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
    if string(rows(i).Parameter1Name) == string(name) && isfinite(double(rows(i).Parameter1Value))
        value = value + double(rows(i).Parameter1Value);
    end
end
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
