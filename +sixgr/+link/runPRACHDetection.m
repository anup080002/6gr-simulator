function out = runPRACHDetection(cfg, varargin)
%RUNPRACHDETECTION PRACH Tx/Rx detection KPI case.

sixgr.runtime.RuntimeCallLedger.record("sixgr.link.runPRACHDetection", ...
    "PRACH", "UL", struct("Stage","TX_RX_TRIAL"));

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 12), @(x) isnumeric(x) && isscalar(x));
p.addParameter("DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));
p.addParameter("CanonicalSlot", NaN, @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.addParameter("PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
p.parse(varargin{:});
log = p.Results.Logger;
[snr_dB, snrSource] = localResolveFinitePRACHReceiverSNR(cfg, double(p.Results.SNR_dB));
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
out.RxAntennaCount = NaN;
out.PDPAverageNoiseFloor = NaN;
out.PeakToThresholdRatio = NaN;
out.PeakToNoiseRatio = NaN;
out.PeakToNoiseRatio_dB = NaN;
out.CandidateCount = NaN;
out.CandidatesAboveThreshold = NaN;
out.TargetFalseAlarmProbability = NaN;
out.ThresholdBackgroundComponent = NaN;
out.ThresholdGlobalPeakComponent = NaN;
out.PeakGuardFactor = NaN;
out.DetectorPeakLagSamples = NaN;
out.MissedDetection = false;
out.FalseAlarm = false;
out.NoiseFalseAlarm = false;
out.CollisionFalseAlarm = NaN;
out.FalseAlarmClassification = "";
out.FalseAlarmCandidateScope = "";
out.FalseAlarmCandidateCount = NaN;
out.CollisionFalseAlarmClassification = "not_measured_without_collision_occasion";
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
out.TAOutOfRangeFlag = false;
out.TAOutOfRangeReason = "";
out.TAMaxValid_samples = NaN;
out.TAMaxValid_us = NaN;
out.ComputeLatency_ms = NaN;
out.AccessDelay_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.RAResponseWindow_slots = NaN;
out.ContentionResolutionTimer_slots = NaN;
out.PRACHSubcarrierSpacing_kHz = NaN;
out.SlotDuration_ms = NaN;
out.FalseAlarmFlag = 0;
out.NoiseFalseAlarmFlag = 0;
out.CollisionFalseAlarmFlag = NaN;
out.FalseAlarmProbability = NaN;
out.NoiseVariance = NaN;
out.NoiseVarStatus = "NOT_AVAILABLE";
out.NoiseVarSource = "";
out.NoiseVarReason = "";
out.ConfiguredSNR_dB = double(snr_dB);
out.AppliedAWGNSNR_dB = NaN;
out.AppliedAWGNSNRSource = char(snrSource);
out.SNRValueRole = "prach_receiver_esn0_detection_axis";
out.DesiredSignalPowerBeforeNoise = NaN;
out.CompositeSignalPowerBeforeNoise = NaN;
out.AppliedNoiseSNR_dB = NaN;
out.PRACHSNRCalibrationStatus = "";
out.PRACHSNRCalibrationSource = "";
out.PRACHSNRCalibrationError_dB = NaN;
out.PRACHNoiseReferencePower = NaN;
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
out.CorrelationTraceTable = table();

configuredPRACH = logical(sixgr.util.structGet(cfg, "phy.prach.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "prach", configuredPRACH, ...
    "runPRACHDetection");
if ~configuredPRACH
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
    [rxWave, replay, noiseOnlyWave] = localApplyPRACHChannelAndNoise(tx.Waveform, cfg, tx, snr_dB, snrSource);
    out.NoiseVariance = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
    out.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
    out.AppliedAWGNSNRSource = char(string(sixgr.util.structGet(replay, "AppliedAWGNSNRSource", "")));
    out.SNRValueRole = char(string(sixgr.util.structGet(replay, "SNRValueRole", out.SNRValueRole)));
    out.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "DesiredSignalPowerBeforeNoise", NaN));
    out.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "CompositeSignalPowerBeforeNoise", NaN));
    out.AppliedNoiseSNR_dB = double(sixgr.util.structGet(replay, "AppliedNoiseSNR_dB", NaN));
    out.PRACHSNRCalibrationStatus = char(string(sixgr.util.structGet(replay, "PRACHSNRCalibrationStatus", "")));
    out.PRACHSNRCalibrationSource = char(string(sixgr.util.structGet(replay, "PRACHSNRCalibrationSource", "")));
    out.PRACHSNRCalibrationError_dB = double(sixgr.util.structGet(replay, "PRACHSNRCalibrationError_dB", NaN));
    out.PRACHNoiseReferencePower = double(sixgr.util.structGet(replay, "PRACHNoiseReferencePower", NaN));
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
    faArgs = {"Occasion", occasion};
    if ~isempty(detectionThreshold)
        faArgs = [faArgs {"DetectionThresholdMode", "fixed", "DetectionThreshold", detectionThreshold}]; %#ok<AGROW>
    end
    [faScope, faCandidates] = localResolveFalseAlarmCandidateSet(cfg, preambleIndex);
    if ~isempty(faCandidates)
        faArgs = [faArgs {"CandidatePreambles", faCandidates}]; %#ok<AGROW>
    end
    rx = sixgr.rach.PRACHDetector(rxWave, prachCfg, detArgs{:});
    rxNoise = sixgr.rach.PRACHDetector(noiseOnlyWave, prachCfg, detArgs{:});
    rxNoPreambleOccasion = sixgr.rach.PRACHDetector(noiseOnlyWave, prachCfg, faArgs{:});
    out.ComputeLatency_ms = toc(tDetect) * 1e3;
    out.AirInterfaceObservation_ms = localWaveformDurationMs(tx, cfg);
    [out.AccessDelay_ms, out.ProcedureDelay_ms, out.RAResponseWindow_slots, ...
        out.ContentionResolutionTimer_slots, out.SlotDuration_ms, out.PRACHSubcarrierSpacing_kHz] = localRACHProcedureDelayMs(cfg, tx);
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
    out.RxAntennaCount = double(sixgr.util.structGet(rx, "RxAntennaCount", NaN));
    out.PDPAverageNoiseFloor = double(sixgr.util.structGet(rx, "PDPNoiseFloor", NaN));
    out.PeakToThresholdRatio = double(sixgr.util.structGet(rx, "PeakToThresholdRatio", NaN));
    out.PeakToNoiseRatio = double(sixgr.util.structGet(rx, "PeakToNoiseRatio", NaN));
    out.PeakToNoiseRatio_dB = double(sixgr.util.structGet(rx, "PeakToNoiseRatio_dB", NaN));
    out.CandidateCount = double(sixgr.util.structGet(rx, "CandidateCount", NaN));
    out.CandidatesAboveThreshold = double(sixgr.util.structGet(rx, "CandidatesAboveThreshold", NaN));
    out.TargetFalseAlarmProbability = double(sixgr.util.structGet(rx, "TargetFalseAlarmProbability", NaN));
    out.ThresholdBackgroundComponent = double(sixgr.util.structGet(rx, "ThresholdBackgroundComponent", NaN));
    out.ThresholdGlobalPeakComponent = double(sixgr.util.structGet(rx, "ThresholdGlobalPeakComponent", NaN));
    out.PeakGuardFactor = double(sixgr.util.structGet(rx, "PeakGuardFactor", NaN));
    out.DetectorPeakLagSamples = double(sixgr.util.structGet(rx, "PeakLagSamples", NaN));
    out.PreambleIndex = rx.DetectedPreambleIndex;
    out.DetectedPreambleIndex = localScalarOrNaN(rx.DetectedPreambleIndex);
    out.PreambleIndexFromPeak = localScalarOrNaN(sixgr.util.structGet(rx, "PreambleIndexFromPeak", NaN));
    out.TimingOffset_samples = localScalarOrNaN(rx.TimingOffsetSamples);
    out.TimingAdvance_samples = out.TimingOffset_samples;
    out.TimingAdvance_us = localSamplesToMicroseconds(out.TimingOffset_samples, tx.SampleRate_Hz);
    out = localValidatePRACHTimingAdvanceRange(out, cfg, tx.SampleRate_Hz);
    out.NoiseFalseAlarmFlag = double(logical(sixgr.util.structGet(rxNoise, "Detected", false)));
    out.NoiseFalseAlarm = logical(out.NoiseFalseAlarmFlag);
    out.FalseAlarmFlag = double(logical(sixgr.util.structGet(rxNoPreambleOccasion, "Detected", false)));
    out.FalseAlarm = logical(out.FalseAlarmFlag);
    out.FalseAlarmCandidateScope = char(faScope);
    out.FalseAlarmCandidateCount = double(numel(faCandidates));
    out.FalseAlarmProbability = double(out.FalseAlarmFlag);
    if faScope == "all_preambles"
        out.FalseAlarmClassification = "ts38321_no_preamble_transmitted_any_preamble_detected";
    else
    out.FalseAlarmClassification = "ts38321_no_preamble_transmitted_requested_preamble_detected";
    end
    out.MissedDetection = ~logical(out.Detected);
    out.CorrelationTraceTable = localBuildCorrelationTraceTable(cfg, prachCfg, tx, rx, out, snr_dB);

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

function T = localBuildCorrelationTraceTable(cfg, prachCfg, tx, rx, out, snr_dB)
trace = sixgr.util.structGet(rx, "CorrelationTrace", struct());
lags = double(sixgr.util.structGet(trace, "LagSamples", zeros(0, 1)));
corrAbs = double(sixgr.util.structGet(trace, "CorrelationAbs", zeros(0, 1)));
lags = lags(:);
corrAbs = corrAbs(:);
n = min(numel(lags), numel(corrAbs));
if n == 0
    T = table();
    return;
end
lags = lags(1:n);
corrAbs = corrAbs(1:n);
valid = isfinite(lags) & isfinite(corrAbs);
lags = lags(valid);
corrAbs = corrAbs(valid);
n = numel(lags);
if n == 0
    T = table();
    return;
end
sampleRateHz = double(sixgr.util.structGet(tx, "SampleRate_Hz", ...
    sixgr.util.structGet(prachCfg, "SampleRate_Hz", 30.72e6)));
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = 30.72e6;
end
preambleIndex = double(sixgr.util.structGet(trace, "PreambleIndex", ...
    sixgr.util.structGet(out, "PreambleIndexFromPeak", NaN)));
rootSequenceIndex = double(sixgr.util.structGet(prachCfg, "SequenceIndex", ...
    sixgr.util.structGet(out, "PRACHRootSequenceIndex", NaN)));
restrictedSetType = string(sixgr.util.structGet(prachCfg, "RestrictedSet", ...
    sixgr.util.structGet(cfg, "phy.prach.restrictedSet", "UnrestrictedSet")));
ncs = double(sixgr.util.structGet(prachCfg, "ZCZNCS", NaN));
zcz = double(sixgr.util.structGet(prachCfg, "ZeroCorrelationZone", ...
    sixgr.util.structGet(out, "PRACHZeroCorrelationZone", NaN)));
threshold = double(sixgr.util.structGet(trace, "Threshold", ...
    sixgr.util.structGet(out, "DetectionThreshold", NaN)));
noiseFloor = double(sixgr.util.structGet(trace, "NoiseFloor", ...
    sixgr.util.structGet(out, "PDPAverageNoiseFloor", ...
    sixgr.util.structGet(out, "DetectorNoiseFloor", NaN))));
peakLagSamples = double(sixgr.util.structGet(trace, "PeakLagSamples", ...
    sixgr.util.structGet(out, "TimingOffset_samples", NaN)));
peakToThreshold = double(sixgr.util.structGet(out, "PeakToThresholdRatio", NaN));
peakToNoise = double(sixgr.util.structGet(out, "PeakToNoiseRatio", NaN));
peakToNoiseDb = double(sixgr.util.structGet(out, "PeakToNoiseRatio_dB", NaN));
candidateCount = double(sixgr.util.structGet(out, "CandidateCount", NaN));
candidateAboveThreshold = double(sixgr.util.structGet(out, "CandidatesAboveThreshold", NaN));
targetPfa = double(sixgr.util.structGet(out, "TargetFalseAlarmProbability", NaN));
thresholdBackground = double(sixgr.util.structGet(out, "ThresholdBackgroundComponent", NaN));
thresholdGlobalPeak = double(sixgr.util.structGet(out, "ThresholdGlobalPeakComponent", NaN));
taSamples = double(sixgr.util.structGet(out, "TimingAdvance_samples", NaN));
cfoHz = double(sixgr.util.structGet(out, "InjectedCFO_Hz", NaN));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
seed = round(double(sixgr.util.structGet(prachCfg, "Seed", sixgr.util.structGet(cfg, "run.seed", 1))));
detectionResult = "not_detected";
if logical(sixgr.util.structGet(out, "FalseAlarm", false))
    detectionResult = "false_alarm";
elseif logical(sixgr.util.structGet(out, "Detected", false))
    detectionResult = "detected";
elseif logical(sixgr.util.structGet(out, "MissedDetection", false))
    detectionResult = "missed_detection";
end
truthStatus = string(sixgr.util.structGet(trace, "TraceStatus", "real_lls_evidence"));
if strlength(truthStatus) == 0
    truthStatus = "real_lls_evidence";
end
lagUs = lags ./ sampleRateHz .* 1e6;
T = table( ...
    repmat(double(seed), n, 1), ...
    repmat(double(preambleIndex), n, 1), ...
    repmat(double(rootSequenceIndex), n, 1), ...
    repmat(restrictedSetType, n, 1), ...
    repmat(double(ncs), n, 1), ...
    repmat(double(zcz), n, 1), ...
    double(lags), ...
    double(lagUs), ...
    double(corrAbs), ...
    repmat(double(threshold), n, 1), ...
    repmat(double(noiseFloor), n, 1), ...
    repmat(double(peakToThreshold), n, 1), ...
    repmat(double(peakToNoise), n, 1), ...
    repmat(double(peakToNoiseDb), n, 1), ...
    repmat(double(candidateCount), n, 1), ...
    repmat(double(candidateAboveThreshold), n, 1), ...
    repmat(double(targetPfa), n, 1), ...
    repmat(double(thresholdBackground), n, 1), ...
    repmat(double(thresholdGlobalPeak), n, 1), ...
    repmat(double(peakLagSamples), n, 1), ...
    repmat(double(taSamples), n, 1), ...
    repmat(detectionResult, n, 1), ...
    repmat(logical(sixgr.util.structGet(out, "FalseAlarm", false)), n, 1), ...
    repmat(logical(sixgr.util.structGet(out, "MissedDetection", false)), n, 1), ...
    repmat(double(snr_dB), n, 1), ...
    repmat(double(cfoHz), n, 1), ...
    repmat(double(seed), n, 1), ...
    repmat(truthStatus, n, 1), ...
    'VariableNames', localPRACHCorrelationTraceVariableNames());
end

function names = localPRACHCorrelationTraceVariableNames()
names = {'trial_id','preamble_index','root_sequence_index','restricted_set_type','n_cs', ...
    'zero_correlation_zone_config','lag_samples','lag_us','correlation_abs','threshold', ...
    'noise_floor','peak_to_threshold_ratio','peak_to_noise_ratio','peak_to_noise_ratio_db', ...
    'candidate_count','candidates_above_threshold','target_false_alarm_probability', ...
    'threshold_background_component','threshold_global_peak_component', ...
    'peak_lag_samples','timing_advance_samples','detection_result', ...
    'false_alarm','missed_detection','snr_db','cfo_hz','seed','truth_status'};
end

function [scope, candidates] = localResolveFalseAlarmCandidateSet(cfg, preambleIndex)
scope = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.prach.falseAlarmCandidateScope", ...
    sixgr.util.structGet(cfg, "random_access.false_alarm_candidate_scope", "")))));
if strlength(scope) == 0
    scope = lower(strtrim(string(sixgr.util.structGet(cfg, "prach_lls.FalseAlarmCandidateScope", ""))));
end
if strlength(scope) == 0
    scope = "requested_preamble";
end
if any(scope == ["all", "all_preambles", "occasion", "occasion_all_preambles"])
    scope = "all_preambles";
    candidates = 0:63;
    return;
end
scope = "requested_preamble";
if isempty(preambleIndex)
    scope = "all_preambles";
    candidates = 0:63;
    return;
end
candidates = unique(round(double(preambleIndex(:).')));
candidates = candidates(candidates >= 0 & candidates <= 63);
if isempty(candidates)
    scope = "all_preambles";
    candidates = 0:63;
end
end

function [snr_dB, source] = localResolveFinitePRACHReceiverSNR(cfg, requestedSNR_dB)
snr_dB = double(requestedSNR_dB);
source = "input_SNR_dB";
if isscalar(snr_dB) && (isfinite(snr_dB) || isinf(snr_dB))
    return;
end

paths = [ ...
    "phy.prach.receiverEsN0_dB"; ...
    "phy.prach.receiver_esn0_db"; ...
    "phy.prach.snr_dB"; ...
    "random_access.receiverEsN0_dB"; ...
    "random_access.receiver_esn0_db"; ...
    "random_access.prach_receiver_esn0_db"; ...
    "random_access.snr_dB"; ...
    "random_access.snr_db"; ...
    "validation.random_access_evidence.receiver_esn0_db"; ...
    "channel.snr_dB"; ...
    "simulation.snr_db"];
for i = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(i), []);
    vals = double(raw(:));
    vals = vals(isfinite(vals) | isinf(vals));
    if ~isempty(vals)
        snr_dB = double(vals(1));
        source = "configured_" + paths(i);
        return;
    end
end

sweepPaths = ["random_access.snr_sweep_db","random_access.snrSweepDb","validation.prach.snr_sweep_db"];
for i = 1:numel(sweepPaths)
    raw = sixgr.util.structGet(cfg, sweepPaths(i), []);
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        snr_dB = double(max(vals));
        source = "configured_" + sweepPaths(i) + "_max";
        return;
    end
end
source = "unresolved_nonfinite_prach_receiver_esn0";
end

function [y, replay, noiseOnlyWave] = localApplyPRACHChannelAndNoise(x, cfg, tx, snr_dB, snrSource)
if nargin < 5
    snrSource = "prach_receiver_esn0_detection_axis";
end
cfg = localWithPRACHULRuntimeDirection(cfg);
txInfo = struct("OFDM", sixgr.util.structGet(tx, "OFDMInfo", struct()));
state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
sampleRateHz = double(sixgr.util.structGet(state, "SampleRate_Hz", localResolveSampleRate(tx, txInfo)));
y = x;
replay = struct( ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNRSource", char(string(snrSource)), ...
    "SNRValueRole", "prach_receiver_esn0_detection_axis_not_data_channel_sinr", ...
    "InjectedNoiseVariance", NaN, ...
    "NoiseVarianceSource", "", ...
    "DesiredSignalPowerBeforeNoise", NaN, ...
    "CompositeSignalPowerBeforeNoise", NaN, ...
    "AppliedNoiseSNR_dB", NaN, ...
    "PRACHSNRCalibrationStatus", "pending_noise_application", ...
    "PRACHSNRCalibrationSource", "reference_waveform_power_before_awgn", ...
    "PRACHSNRCalibrationError_dB", NaN, ...
    "PRACHNoiseReferencePower", NaN, ...
    "ChannelModelApplied", string(sixgr.util.structGet(cfg, "channel.model", "AWGN")), ...
    "ChannelFadingApplied", false, ...
    "NoiseOperatingMode", "prach_receiver_esn0_awgn", ...
    "AppliedLargeScaleGain_dB", NaN, ...
    "AppliedLargeScaleLoss_dB", NaN, ...
    "AppliedBasePathloss_dB", NaN, ...
    "AppliedPathloss_dB", NaN, ...
    "AppliedShadowFading_dB", NaN, ...
    "AppliedO2I_dB", NaN, ...
    "AppliedLargeScaleGainSource", "not_applied_prach_receiver_esn0_axis", ...
    "ServingRSRP_dBm", NaN, ...
    "ServingRSRPSource", "not_applicable_prach_receiver_esn0_axis", ...
    "LargeScaleSINR_dB", NaN, ...
    "LargeScaleSINRSource", "not_applicable_prach_receiver_esn0_axis", ...
    "InjectedCFO_Hz", localResolveInjectedCFOHz(cfg), ...
    "InjectedTimingOffset_samples", localResolveInjectedTimingOffsetSamples(cfg), ...
    "InjectedCarrierPhaseOffset_deg", localResolveInjectedCarrierPhaseOffsetDeg(cfg), ...
    "CarrierPhaseOffsetApplied", false);

[y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state); %#ok<ASGLU>
chFields = fieldnames(channelReplay);
for chIdx = 1:numel(chFields)
    replay.(chFields{chIdx}) = channelReplay.(chFields{chIdx});
end

[y, replay] = localApplyPRACHSampleImpairments(y, replay, sampleRateHz, cfg);
desiredWaveform = y;
[y, nVar] = localAddAwgnFromReplay(y, replay, desiredWaveform);
replay.InjectedNoiseVariance = double(nVar);
desiredPower = localEstimateWaveformPower(desiredWaveform);
replay.DesiredSignalPowerBeforeNoise = double(desiredPower);
replay.CompositeSignalPowerBeforeNoise = double(desiredPower);
replay.PRACHNoiseReferencePower = double(desiredPower);
if isfinite(desiredPower) && desiredPower >= 0 && isfinite(nVar) && nVar > 0
    replay.AppliedNoiseSNR_dB = 10 * log10(max(desiredPower, eps) / double(nVar));
    replay.PRACHSNRCalibrationError_dB = double(replay.AppliedNoiseSNR_dB) - double(replay.AppliedAWGNSNR_dB);
    if abs(double(replay.PRACHSNRCalibrationError_dB)) <= 0.1
        replay.PRACHSNRCalibrationStatus = "calibrated_to_reference_waveform_power";
    else
        replay.PRACHSNRCalibrationStatus = "mismatch_between_requested_esn0_and_injected_noise";
    end
elseif isfinite(nVar) && nVar == 0
    replay.AppliedNoiseSNR_dB = Inf;
    replay.PRACHSNRCalibrationStatus = "noise_free_reference_trial";
else
    replay.PRACHSNRCalibrationStatus = "unavailable_noise_variance_not_resolved";
end
if isfinite(nVar) && nVar > 0
    replay.NoiseVarianceSource = "prach_receiver_input_esn0_awgn";
end
noiseOnlyWave = localNoiseOnlyWaveformLike(y, nVar);
end

function cfgOut = localWithPRACHULRuntimeDirection(cfg)
cfgOut = cfg;
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeCurrentDirection", "UL");
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.Direction", "UL");
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeSignalFamily", "PRACH");
cfgOut = sixgr.util.structSet(cfgOut, "phy.runtimeSignalFamily", "PRACH");
cfgOut = sixgr.util.structSet(cfgOut, "channel.linkDirection", "UL");
end

function [y, replay] = localApplyPRACHSampleImpairments(y, replay, sampleRateHz, cfg)
% PRACH detection curves use receiver Es/N0, so only sample-domain RF
% impairments are applied here. Large-scale loss and data-channel AWGN replay
% are intentionally excluded from the PRACH SNR axis.
iqGain_dB = double(sixgr.util.structGet(cfg, "phy.impairments.iqGainImbalance_dB", ...
    sixgr.util.structGet(cfg, "impairments.iq_gain_imbalance_db", 0)));
iqPhase_deg = double(sixgr.util.structGet(cfg, "phy.impairments.iqPhaseImbalance_deg", ...
    sixgr.util.structGet(cfg, "impairments.iq_phase_imbalance_deg", 0)));
if ~isfinite(iqGain_dB)
    iqGain_dB = 0;
end
if ~isfinite(iqPhase_deg)
    iqPhase_deg = 0;
end
replay.ConfiguredIQGainImbalance_dB = iqGain_dB;
replay.ConfiguredIQPhaseImbalance_deg = iqPhase_deg;
replay.IQImbalanceApplied = false;
if abs(iqGain_dB) > 1e-12 || abs(iqPhase_deg) > 1e-12
    y = localApplyIQImbalance(y, iqGain_dB, iqPhase_deg);
    replay.IQImbalanceApplied = true;
end

timingOffset = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", 0));
if isfinite(timingOffset) && abs(timingOffset) > 1e-12
    y = sixgr.util.applyFractionalSampleDelay(y, timingOffset);
end

cfoHz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", 0));
if isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(cfoHz) && cfoHz ~= 0
    n = (0:size(y, 1)-1).';
    rot = exp(1j * 2 * pi * (cfoHz / sampleRateHz) * n);
    y = y .* cast(rot, "like", y);
end

phaseOffsetDeg = double(sixgr.util.structGet(replay, "InjectedCarrierPhaseOffset_deg", 0));
if isfinite(phaseOffsetDeg) && abs(phaseOffsetDeg) > 1e-12
    y = y .* cast(exp(1j * phaseOffsetDeg * pi / 180), "like", y);
    replay.CarrierPhaseOffsetApplied = true;
end
end

function y = localApplyIQImbalance(x, gainImbalance_dB, phaseImbalance_deg)
gainLin = 10.^(double(gainImbalance_dB) / 20);
phaseRad = double(phaseImbalance_deg) * pi / 180;
iPart = real(x) .* gainLin;
qPart = imag(x) ./ max(gainLin, eps);
qRot = qPart .* cos(phaseRad) + iPart .* sin(phaseRad);
y = complex(iPart, qRot);
if ~isa(y, class(x))
    y = cast(y, "like", x);
end
end

function [y, nVar] = localAddAwgnFromReplay(x, replay, referenceWaveform)
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

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0)));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", ...
    sixgr.util.structGet(cfg, "impairments.to.value_samples", NaN))));
if ~isfinite(timingOffset)
    distance_m = double(sixgr.util.structGet(cfg, "channel.propagationDistance_m", ...
        sixgr.util.structGet(cfg, "channel.distance_m", NaN)));
    sampleRateHz = double(sixgr.util.structGet(cfg, "global_radio_scope.sample_rate_hz", ...
        sixgr.util.structGet(cfg, "phy.carrier.SampleRate", 122.88e6)));
    if isfinite(distance_m) && distance_m >= 0 && isfinite(sampleRateHz) && sampleRateHz > 0
        timingOffset = (double(distance_m) ./ 299792458) .* double(sampleRateHz);
    end
end
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function out = localValidatePRACHTimingAdvanceRange(out, cfg, sampleRateHz)
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = double(sixgr.util.structGet(cfg, "global_radio_scope.sample_rate_hz", ...
        sixgr.util.structGet(cfg, "phy.carrier.SampleRate", 122.88e6)));
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = 122.88e6;
end
maxTA_us = localPRACHMaxTimingAdvanceUs(cfg);
maxTA_samp = double(maxTA_us) * 1e-6 * double(sampleRateHz);
out.TAMaxValid_us = double(maxTA_us);
out.TAMaxValid_samples = double(maxTA_samp);
timingOffset = double(sixgr.util.structGet(out, "TimingOffset_samples", NaN));
if isfinite(timingOffset) && timingOffset > maxTA_samp
    out.TAOutOfRangeFlag = true;
    out.TAOutOfRangeReason = sprintf( ...
        "TimingOffset_samples=%.1f exceeds maxTA_samp=%.1f (%.1f us); check geometry units and PRACH reference slot.", ...
        timingOffset, maxTA_samp, maxTA_us);
else
    out.TAOutOfRangeFlag = false;
    out.TAOutOfRangeReason = "";
end
end

function maxTA_us = localPRACHMaxTimingAdvanceUs(cfg)
fmt = upper(strtrim(string(sixgr.util.structGet(cfg, "phy.prach.preambleFormat", ...
    sixgr.util.structGet(cfg, "random_access.prach_format", "0")))));
fmt = erase(fmt, "FORMAT");
switch fmt
    case "0"
        maxTA_us = 1.1 * 103.1;
    case {"1", "3"}
        maxTA_us = 1.1 * 684.4;
    case "2"
        maxTA_us = 1.1 * 203.1;
    otherwise
        maxTA_us = 1.1 * 103.1;
end
end

function phaseOffsetDeg = localResolveInjectedCarrierPhaseOffsetDeg(cfg)
phaseOffsetDeg = double(sixgr.util.structGet(cfg, "phy.impairments.carrierPhaseOffset_deg", ...
    sixgr.util.structGet(cfg, "impairments.carrier_phase_offset_deg", 0)));
if ~isfinite(phaseOffsetDeg)
    phaseOffsetDeg = 0;
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

function [accessDelayMs, procedureDelayMs, raWindowSlots, crTimerSlots, slotDurationMs, prachScsKHz] = localRACHProcedureDelayMs(cfg, tx)
prachScsKHz = double(sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", ...
    sixgr.util.structGet(cfg, "phy.prach.SubcarrierSpacing", NaN)));
if ~(isfinite(prachScsKHz) && prachScsKHz > 0)
    prachScsKHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
        sixgr.util.structGet(cfg, "phy.carrier.subcarrierSpacing_kHz", NaN)));
end
if ~(isfinite(prachScsKHz) && prachScsKHz > 0)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            prachScsKHz = double(carrier.SubcarrierSpacing);
        catch
            prachScsKHz = NaN;
        end
    end
end
if ~(isfinite(prachScsKHz) && prachScsKHz > 0)
    error("sixgr:link:runPRACHDetection:MissingPRACHNumerology", ...
        "PRACH procedure timing requires an explicit PRACH or carrier SCS.");
end
dataScsKHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.subcarrierSpacing_kHz", prachScsKHz)));
if ~(isfinite(dataScsKHz) && dataScsKHz > 0)
    error("sixgr:link:runPRACHDetection:MissingDataNumerology", ...
        "RA response timing requires an explicit data-carrier SCS.");
end
prachNumerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    prachScsKHz, "normal", "generic_waveform_test", "");
dataNumerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    dataScsKHz, "normal", "generic_waveform_test", "");
slotsPerMsPrach = double(prachNumerology.SlotsPerSubframe);
slotsPerMsData = double(dataNumerology.SlotsPerSubframe);
slotDurationMs = double(prachNumerology.SlotDurationMilliseconds);
dataSlotDurationMs = double(dataNumerology.SlotDurationMilliseconds);
raWindowSlots = double(sixgr.util.structGet(cfg, "rrc.rach.raResponseWindow_slots", NaN));
if ~isfinite(raWindowSlots)
    raWindowMs = double(sixgr.util.structGet(cfg, "rrc.rach.raResponseWindow_ms", 10));
    raWindowSlots = max(1, round(raWindowMs * slotsPerMsData));
end
crTimerSlots = double(sixgr.util.structGet(cfg, "rrc.rach.contentionResolutionTimer_slots", NaN));
crTimerMs = double(sixgr.util.structGet(cfg, "rrc.rach.contentionResolutionTimer_ms", 64));
if ~isfinite(crTimerSlots)
    allowedMs = [8 16 24 32 40 48 56 64];
    if ~(isfinite(crTimerMs) && any(round(crTimerMs) == allowedMs))
        crTimerMs = 64;
    end
    crTimerSlots = max(1, round(crTimerMs * slotsPerMsPrach));
else
    crTimerMs = crTimerSlots * slotDurationMs;
end
accessDelayMs = raWindowSlots * dataSlotDurationMs + crTimerMs;
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
