function out = runPRACHDetection(cfg, varargin)
%RUNPRACHDETECTION PRACH Tx/Rx detection KPI case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 12), @(x) isnumeric(x) && isscalar(x));
p.addParameter("DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));
p.addParameter("CanonicalSlot", NaN, @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.addParameter("PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);
detectionThreshold = localResolveDetectionThreshold(cfg, p.Results.DetectionThreshold);
canonicalSlot = double(p.Results.CanonicalSlot);
preambleIndex = p.Results.PreambleIndex;
carrierSlot = localResolveCarrierSlot(cfg, canonicalSlot);
if isempty(preambleIndex)
    preambleIndex = sixgr.util.structGet(cfg, "phy.prach.preambleIndex", []);
end

out = struct();
out.Ok = false;
out.Skipped = false;
out.Detected = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.DetectionMetric = NaN;
out.CorrelationPeak = NaN;
out.DetectionThreshold = localScalarOrNaN(detectionThreshold);
out.DetectionThresholdMode = "";
out.NoiseOnlyDetectionMetric = NaN;
out.DetectorNoiseFloor = NaN;
out.MissedDetection = false;
out.FalseAlarm = false;
out.PreambleIndex = [];
out.RequestedPreambleIndex = localScalarOrNaN(preambleIndex);
out.DetectedPreambleIndex = NaN;
out.PreambleIndexFromPeak = NaN;
out.PRACHRootSequenceIndex = NaN;
out.PRACHZeroCorrelationZone = NaN;
out.PRACHConfigurationIndex = NaN;
out.PRACHOccasionIndex = NaN;
out.PRACHCarrierSlot = double(carrierSlot);
out.TimingOffset_samples = NaN;
out.TimingAdvance_samples = NaN;
out.TimingAdvance_us = NaN;
out.ComputeLatency_ms = NaN;
out.AccessDelay_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.RAResponseWindow_slots = NaN;
out.ContentionResolutionTimer_slots = NaN;
out.SlotDuration_ms = NaN;
out.FalseAlarmFlag = 0;
out.NoiseVariance = NaN;
out.NoiseVarStatus = "NOT_AVAILABLE";
out.NoiseVarSource = "";
out.NoiseVarReason = "";
out.ConfiguredSNR_dB = double(snr_dB);
out.AppliedAWGNSNR_dB = NaN;
out.AppliedLargeScaleGain_dB = NaN;
out.AppliedLargeScaleLoss_dB = NaN;
out.AppliedBasePathloss_dB = NaN;
out.AppliedPathloss_dB = NaN;
out.AppliedShadowFading_dB = NaN;
out.AppliedO2I_dB = NaN;
out.AppliedLargeScaleGainSource = "";
out.ServingRSRP_dBm = NaN;
out.ServingRSRPSource = "";
out.LargeScaleSINR_dB = NaN;
out.LargeScaleSINRSource = "";
out.InjectedCFO_Hz = NaN;
out.InjectedTimingOffset_samples = NaN;
out.ChannelModelApplied = "";
out.ChannelFadingApplied = false;
out.Notes = "";

if ~logical(sixgr.util.structGet(cfg, "phy.prach.enable", true))
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.prach.enable=true for PRACH coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.prach.enable=false";
    return;
end

if exist("nrPRACH","file") ~= 2 || exist("nrPRACHDetect","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrPRACH/nrPRACHDetect for PRACH coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPRACH/nrPRACHDetect unavailable.";
    return;
end

try
    prachCfg = sixgr.rach.PRACHConfig(cfg, "PreambleIndex", preambleIndex);
    occasion = localResolveOccasion(prachCfg, carrierSlot);
    if isempty(fieldnames(occasion))
        out.Skipped = true;
        out.Ok = true;
        out.Notes = "Skipped: no PRACH occasion is active for carrier slot " + string(carrierSlot) + ...
            " with configuration_index=" + string(sixgr.util.structGet(cfg, "phy.prach.configurationIndex", NaN)) + ".";
        return;
    end
    tx = sixgr.rach.generatePRACHWaveform(prachCfg, "Occasion", occasion, "PreambleIndex", preambleIndex);
    out.RequestedPreambleIndex = localScalarOrNaN(tx.PreambleIndex);
    out.PRACHRootSequenceIndex = double(sixgr.util.structGet(prachCfg, "SequenceIndex", NaN));
    out.PRACHZeroCorrelationZone = double(sixgr.util.structGet(prachCfg, "ZeroCorrelationZone", NaN));
    out.PRACHConfigurationIndex = double(sixgr.util.structGet(prachCfg, "PRACHConfigurationIndex", NaN));
    out.PRACHOccasionIndex = double(sixgr.util.structGet(occasion, "OccasionIndex", NaN));
    out.PRACHCarrierSlot = double(carrierSlot);
    [rxWave, replay, noiseOnlyWave] = localApplyPRACHChannelAndNoise(tx.Waveform, cfg, tx, snr_dB);
    out.NoiseVariance = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
    out.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
    out.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
    out.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
    out.AppliedBasePathloss_dB = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
    out.AppliedPathloss_dB = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
    out.AppliedShadowFading_dB = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
    out.AppliedO2I_dB = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
    out.AppliedLargeScaleGainSource = string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", ""));
    out.ServingRSRP_dBm = double(sixgr.util.structGet(replay, "ServingRSRP_dBm", NaN));
    out.ServingRSRPSource = string(sixgr.util.structGet(replay, "ServingRSRPSource", ""));
    out.LargeScaleSINR_dB = double(sixgr.util.structGet(replay, "LargeScaleSINR_dB", NaN));
    out.LargeScaleSINRSource = string(sixgr.util.structGet(replay, "LargeScaleSINRSource", ""));
    out.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
    out.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN));
    out.ChannelModelApplied = string(sixgr.util.structGet(replay, "ChannelModelApplied", ""));
    out.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
    if isfinite(out.NoiseVariance) && out.NoiseVariance > 0
        out.NoiseVarStatus = "OK";
        out.NoiseVarSource = string(sixgr.util.structGet(replay, "NoiseVarianceSource", "prach_awgn_replay"));
    elseif isinf(snr_dB) || snr_dB >= 90
        out.NoiseVarStatus = "NOT_APPLIED";
        out.NoiseVarSource = "noise_free_reference_trial";
    else
        out.NoiseVarStatus = "NOT_AVAILABLE";
        out.NoiseVarReason = "nonpositive_or_unresolved_prach_noise_variance";
    end
    sixgr.config.publishConfigApplicationEvidence("record", ...
        "random_access.detection_threshold", "Random_Access_PRACH", "phy.prach.detectionThreshold", ...
        "sixgr.link.runPRACHDetection", detectionThreshold, ...
        "Slot", carrierSlot, ...
        "RuntimeObjectType", "PRACHDetector", ...
        "RuntimeObjectPath", "detArgs.DetectionThreshold", ...
        "ApplicationScope", "prach_detection_trial");
    if ~isempty(preambleIndex)
        sixgr.config.publishConfigApplicationEvidence("record", ...
            "random_access.preamble_index", "Random_Access_PRACH", "phy.prach.preambleIndex", ...
            "sixgr.link.runPRACHDetection", preambleIndex, ...
            "Slot", carrierSlot, ...
            "RuntimeObjectType", "PRACHDetector", ...
            "RuntimeObjectPath", "detArgs.CandidatePreambles", ...
            "ApplicationScope", "prach_detection_trial");
    end
    tDetect = tic;
    detArgs = {"Occasion", occasion};
    if ~isempty(detectionThreshold)
        detArgs = [detArgs {"DetectionThresholdMode", "fixed", "DetectionThreshold", detectionThreshold}]; %#ok<AGROW>
    end
    if ~isempty(preambleIndex)
        detArgs = [detArgs {"CandidatePreambles", preambleIndex}]; %#ok<AGROW>
    end
    rx = sixgr.rach.PRACHDetector(rxWave, prachCfg, detArgs{:});
    rxNoise = sixgr.rach.PRACHDetector(noiseOnlyWave, prachCfg, detArgs{:});
    out.ComputeLatency_ms = toc(tDetect) * 1e3;
    out.AirInterfaceObservation_ms = localWaveformDurationMs(tx, cfg);
    [out.AccessDelay_ms, out.ProcedureDelay_ms, out.RAResponseWindow_slots, ...
        out.ContentionResolutionTimer_slots, out.SlotDuration_ms] = localRACHProcedureDelayMs(cfg, tx);
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.Detected = logical(rx.Detected);
    out.DetectionMetric = double(rx.PeakMetric);
    out.CorrelationPeak = double(rx.PeakMetric);
    out.DetectionThreshold = double(sixgr.util.structGet(rx, "Threshold", detectionThreshold));
    out.DetectionThresholdMode = char(string(sixgr.util.structGet(rx, "ThresholdMode", "")));
    out.NoiseOnlyDetectionMetric = double(sixgr.util.structGet(rxNoise, "PeakMetric", NaN));
    out.DetectorNoiseFloor = localEstimateWaveformPower(noiseOnlyWave);
    out.PreambleIndex = rx.DetectedPreambleIndex;
    out.DetectedPreambleIndex = localScalarOrNaN(rx.DetectedPreambleIndex);
    out.PreambleIndexFromPeak = localScalarOrNaN(sixgr.util.structGet(rx, "PreambleIndexFromPeak", NaN));
    out.TimingOffset_samples = localScalarOrNaN(rx.TimingOffsetSamples);
    out.TimingAdvance_samples = out.TimingOffset_samples;
    out.TimingAdvance_us = localSamplesToMicroseconds(out.TimingOffset_samples, tx.SampleRate_Hz);
    out.FalseAlarmFlag = double(logical(sixgr.util.structGet(rxNoise, "Detected", false)));
    out.FalseAlarm = logical(out.FalseAlarmFlag);
    out.MissedDetection = ~logical(out.Detected);

    if out.Detected
        out.Ok = true;
        out.BLER = 0;
        out.Notes = "DetectedIdx=" + string(localScalarOrEmpty(rx.DetectedPreambleIndex)) + ...
            "; carrier_slot=" + string(carrierSlot);
    else
        out.Ok = true;
        out.BLER = 1;
        out.Notes = "Not detected: PRACH detect did not trigger for carrier slot " + string(carrierSlot) + ".";
    end
catch ME
    out.Ok = false;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runPRACHDetection failed: " + string(ME.message));
    end
end
end

function [y, replay, noiseOnlyWave] = localApplyPRACHChannelAndNoise(x, cfg, tx, snr_dB)
txInfo = struct("OFDM", sixgr.util.structGet(tx, "OFDMInfo", struct()));
state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
sampleRateHz = double(sixgr.util.structGet(state, "SampleRate_Hz", localResolveSampleRate(tx, txInfo)));
y = x;
replay = struct( ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "InjectedNoiseVariance", NaN, ...
    "NoiseVarianceSource", "", ...
    "ChannelModelApplied", string(sixgr.util.structGet(cfg, "channel.model", "AWGN")), ...
    "ChannelFadingApplied", false);

if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    replay.ChannelFadingApplied = true;
    try
        reset(state.Obj);
    catch
    end
    xIn = x;
    padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
    trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
    if padSamples > 0
        xIn = [x; zeros(padSamples, size(x, 2), "like", x)];
    end
    try
        yRaw = state.Obj(xIn);
    catch
        [yRaw, ~] = state.Obj(xIn);
    end
    if trimSamples > 0 && size(yRaw, 1) >= (trimSamples + size(x, 1))
        y = yRaw(1+trimSamples:trimSamples+size(x, 1), :);
    else
        y = yRaw;
        if size(y, 1) > size(x, 1)
            y = y(1:size(x, 1), :);
        elseif size(y, 1) < size(x, 1)
            y(end+1:size(x, 1), :) = cast(0, "like", y); %#ok<AGROW>
        end
    end
end

cfgReplay = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz);
fields = fieldnames(impairmentReplay);
for ii = 1:numel(fields)
    replay.(fields{ii}) = impairmentReplay.(fields{ii});
end
replay.ChannelModelApplied = string(sixgr.util.structGet(cfg, "channel.model", replay.ChannelModelApplied));
replay.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false)) || ...
    logical(sixgr.util.structGet(state, "UseFading", false));
desiredWaveform = y;
[y, nVar] = localAddAwgnFromReplay(y, replay, desiredWaveform);
replay.InjectedNoiseVariance = double(nVar);
if isfinite(nVar) && nVar > 0
    replay.NoiseVarianceSource = "prach_replay_reference_waveform_awgn";
end
noiseOnlyWave = localNoiseOnlyWaveformLike(y, nVar);
end

function [y, nVar] = localAddAwgnFromReplay(x, replay, referenceWaveform)
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localResolveThermalNoiseVariance(replay, referenceWaveform);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
    y = x;
    nVar = NaN;
    return;
end
appliedSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
nVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, appliedSNR_dB);
if isfinite(nVar) && nVar >= 0
    if nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
    else
        y = x;
    end
    return;
end
[y, nVar] = sixgr.util.addAwgnComplex(x, appliedSNR_dB);
end

function nVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, snr_dB)
nVar = NaN;
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB)) || isempty(referenceWaveform)
    return;
end
refPower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
nVar = refPower / max(10.^(snr_dB / 10), eps);
end

function nVar = localResolveThermalNoiseVariance(replay, referenceWaveform)
nVar = NaN;
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
if ~(isfinite(thermalNoisePower_dBm) && isfinite(servingRxPower_dBm))
    return;
end
refPower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
relativeNoise_dB = thermalNoisePower_dBm - servingRxPower_dBm;
nVar = refPower * 10.^(relativeNoise_dB / 10);
end

function noiseOnlyWave = localNoiseOnlyWaveformLike(referenceWaveform, nVar)
noiseOnlyWave = zeros(size(referenceWaveform), "like", referenceWaveform);
if isfinite(double(nVar)) && double(nVar) > 0
    n = sqrt(double(nVar) / 2) .* ...
        (randn(size(referenceWaveform), "like", real(referenceWaveform)) + ...
        1i * randn(size(referenceWaveform), "like", real(referenceWaveform)));
    noiseOnlyWave = cast(n, "like", referenceWaveform);
end
end

function us = localSamplesToMicroseconds(samples, sampleRateHz)
us = NaN;
samples = double(samples);
sampleRateHz = double(sampleRateHz);
if isfinite(samples) && isfinite(sampleRateHz) && sampleRateHz > 0
    us = samples / sampleRateHz * 1e6;
end
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(fs)
    fs = sixgr.util.structGet(tx, "SampleRate_Hz", []);
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
fs = double(fs);
if ~(isfinite(fs) && fs > 0)
    fs = 30.72e6;
end
end

function s = localScalarOrEmpty(x)
if isempty(x)
    s = "[]";
    return;
end
if isscalar(x)
    s = string(x);
else
    s = "[" + strjoin(string(x(:).'), ",") + "]";
end
end

function v = localScalarOrNaN(x)
if isempty(x)
    v = NaN;
    return;
end

x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = x(1);
end
end

function p = localEstimateWaveformPower(x)
try
    vals = abs(x(:)).^2;
    p = mean(double(vals), "omitnan");
catch
    p = NaN;
end
end

function durMs = localWaveformDurationMs(tx, cfg)
durMs = NaN;
wave = sixgr.util.structGet(tx, "Waveform", []);
if isempty(wave)
    return;
end
sampleRateHz = sixgr.util.structGet(tx, "SampleRate_Hz", []);
if isempty(sampleRateHz)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            sampleRateHz = [];
        end
    end
end
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
sampleRateHz = double(sampleRateHz);
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    return;
end
durMs = 1e3 * (size(wave, 1) / sampleRateHz);
end

function [accessDelayMs, procedureDelayMs, raWindowSlots, crTimerSlots, slotDurationMs] = localRACHProcedureDelayMs(cfg, tx)
scsKHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.subcarrierSpacing_kHz", NaN)));
if ~(isfinite(scsKHz) && scsKHz > 0)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            scsKHz = double(carrier.SubcarrierSpacing);
        catch
            scsKHz = NaN;
        end
    end
end
if ~(isfinite(scsKHz) && scsKHz > 0)
    scsKHz = 15;
end
mu = max(0, round(log2(max(scsKHz, 15) / 15)));
slotsPerMs = 2^mu;
slotDurationMs = 1 / max(slotsPerMs, eps);
raWindowSlots = double(sixgr.util.structGet(cfg, "rrc.rach.raResponseWindow_slots", NaN));
if ~isfinite(raWindowSlots)
    raWindowMs = double(sixgr.util.structGet(cfg, "rrc.rach.raResponseWindow_ms", 10));
    raWindowSlots = max(1, round(raWindowMs * slotsPerMs));
end
crTimerSlots = double(sixgr.util.structGet(cfg, "rrc.rach.contentionResolutionTimer_slots", NaN));
if ~isfinite(crTimerSlots)
    crTimerMs = double(sixgr.util.structGet(cfg, "rrc.rach.contentionResolutionTimer_ms", 64));
    crTimerSlots = max(1, round(crTimerMs * slotsPerMs));
end
accessDelayMs = (raWindowSlots + crTimerSlots) * slotDurationMs;
procedureDelayMs = accessDelayMs;
end

function threshold = localResolveDetectionThreshold(cfg, explicitThreshold)
if ~isempty(explicitThreshold)
    threshold = double(explicitThreshold);
    return;
end
threshold = sixgr.util.structGet(cfg, "random_access.detection_threshold", []);
if isempty(threshold)
    threshold = sixgr.util.structGet(cfg, "phy.prach.detectionThreshold", []);
end
if isempty(threshold)
    threshold = [];
else
    threshold = double(threshold);
end
end

function carrierSlot = localResolveCarrierSlot(cfg, canonicalSlot)
if isfinite(canonicalSlot)
    carrierSlot = max(0, round(double(canonicalSlot)) - 1);
    return;
end
configured = sixgr.util.structGet(cfg, "phy.prach.nPrachSlot", []);
if ~isempty(configured) && isfinite(double(configured))
    carrierSlot = max(0, round(double(configured)));
    return;
end
carrierSlot = localFindFirstActiveCarrierSlot(cfg);
end

function carrierSlot = localFindFirstActiveCarrierSlot(cfg)
carrierSlot = 0;
try
    prachCfg = sixgr.rach.PRACHConfig(cfg);
    carrierSlot = double(prachCfg.FirstActiveOccasion.SlotIndex0);
catch
end
end

function occasion = localResolveOccasion(prachCfg, carrierSlot)
occasion = struct();
maxOccasions = max(double(prachCfg.NumPRACHOccasions), double(prachCfg.NumSlots) * max(double(prachCfg.ToolboxPRACH.NumTimeOccasions), 1));
for occIdx = 1:max(1, round(maxOccasions))
    try
        candidate = sixgr.rach.mapPRACHToOccasion(prachCfg, "OccasionIndex", occIdx);
    catch
        continue;
    end
    if double(candidate.SlotIndex0) == double(carrierSlot)
        occasion = candidate;
        return;
    end
end
end
