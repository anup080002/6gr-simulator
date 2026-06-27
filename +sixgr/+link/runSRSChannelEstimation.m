function out = runSRSChannelEstimation(cfg, varargin)
%RUNSRSCHANNELESTIMATION SRS Tx/Rx channel-estimation smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 20), @(x) isnumeric(x) && isscalar(x));
p.addParameter("ChannelState", [], @(x) isempty(x) || isstruct(x));
p.addParameter("TrialIndex", 1, @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);
trialIdx = max(1, round(double(p.Results.TrialIndex)));

out = struct();
out.Ok = false;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.NMSE_dB = NaN;
out.InterpolationLoss_dB = NaN;
out.MismatchSensitivity_dB = NaN;
out.QCLAccuracy = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = 0;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.TrackingFailure = 1;
out.NoiseVariance = NaN;
out.NoiseVarStatus = "";
out.NoiseVarSource = "";
out.NoiseVarReason = "";
out.NoiseVarStrictFailure = false;
out.ChannelEstimateUsable = false;
out.ConfiguredSNR_dB = double(snr_dB);
out.AppliedAWGNSNR_dB = NaN;
out.NoiseOperatingMode = "";
out.NoisePowerSource = "";
out.ThermalNoisePower_dBm = NaN;
out.ServingRxPower_dBm = NaN;
out.ServingRxPowerSource = "";
out.AppliedLargeScaleGain_dB = NaN;
out.AppliedLargeScaleLoss_dB = NaN;
out.AppliedBasePathloss_dB = NaN;
out.AppliedPathloss_dB = NaN;
out.AppliedShadowFading_dB = NaN;
out.AppliedO2I_dB = NaN;
out.AppliedLargeScaleGainSource = "";
out.InjectedCFO_Hz = NaN;
out.InjectedTimingOffset_samples = NaN;
out.ChannelModelApplied = "";
out.ChannelFadingApplied = false;
out.MeasurementAttempted = false;
out.MeasurementUsable = false;
out.FailureReason = "";
out.InjectedDoppler_Hz = NaN;
out.EstimatedDopplerHz = NaN;
out.DopplerError_Hz = NaN;
out.DopplerEstimateCRLB_Hz = NaN;
out.EstimatedRI = NaN;
out.EstimatedTPMI = NaN;
out.RankEstimate = NaN;
out.RIEstimate = NaN;
out.TPMIEstimate = NaN;
out.SINR_dB = NaN;
out.SINRSource = "";
out.SINRValueStatus = "";
out.CQI = NaN;
out.CQISource = "";
out.CQIValueStatus = "";
out.MCSIndex = NaN;
out.Modulation = "";
out.TargetCodeRate = NaN;
out.RISource = "";
out.TPMISource = "";
out.TPMICandidateCount = NaN;
out.TPMIMutualInformation = NaN;
out.SRSConditionNumber_dB = NaN;
out.SRSOccupiedPRBCount = NaN;
out.SRSCarrierPRBCount = NaN;
out.SRSBandwidthFraction = NaN;
out.SRSFrequencyPRBStart = NaN;
out.SRSFrequencyPRBEnd = NaN;
out.SRSBandwidthCoverageStatus = "";
out.ChannelState = p.Results.ChannelState;

if ~logical(sixgr.util.structGet(cfg, "phy.srs.enable", true))
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.srs.enable=true for SRS coverage.");
    out.Skipped = true;
    out.Ok = false;
    out.Notes = "Skipped: cfg.phy.srs.enable=false";
    out.FailureReason = "srs_disabled_fail_closed";
    return;
end

if exist("nrSRS", "file") ~= 2 || exist("nrSRSIndices", "file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrSRS/nrSRSIndices for SRS coverage.");
    out.Skipped = true;
    out.Ok = false;
    out.Notes = "Skipped: nrSRS APIs unavailable.";
    out.FailureReason = "srs_toolbox_unavailable_fail_closed";
    return;
end

try
    tStart = tic;
    [tx, info] = sixgr.phy.ul.SRS_Tx(cfg);
    out.SRSOccupiedPRBCount = double(sixgr.util.structGet(tx, "SRSOccupiedPRBCount", NaN));
    out.SRSCarrierPRBCount = double(sixgr.util.structGet(tx, "SRSCarrierPRBCount", NaN));
    out.SRSBandwidthFraction = double(sixgr.util.structGet(tx, "SRSBandwidthFraction", NaN));
    out.SRSFrequencyPRBStart = double(sixgr.util.structGet(tx, "SRSFrequencyPRBStart", NaN));
    out.SRSFrequencyPRBEnd = double(sixgr.util.structGet(tx, "SRSFrequencyPRBEnd", NaN));
    out.SRSBandwidthCoverageStatus = char(string(sixgr.util.structGet(tx, "SRSBandwidthCoverageStatus", "")));
    sampleRateHz = localResolveSampleRate(info, tx, cfg);
    injectedDopplerHz = localResolveInjectedDopplerHz(cfg);
    rng(localTrialSeed(cfg, trialIdx), "twister");
    [rxWave, injectedNoiseVariance, replay, txWaveForReference, chState] = ...
        localApplySRSChannelAndNoise(tx.Waveform, cfg, tx, info, sampleRateHz, injectedDopplerHz, snr_dB, p.Results.ChannelState, trialIdx);
    out.ChannelState = chState;
    out.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
    out.NoiseOperatingMode = char(string(sixgr.util.structGet(replay, "NoiseOperatingMode", "")));
    out.NoisePowerSource = char(string(sixgr.util.structGet(replay, "NoisePowerSource", "")));
    out.ThermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
    out.ServingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
    out.ServingRxPowerSource = char(string(sixgr.util.structGet(replay, "ServingRxPowerSource", "")));
    out.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
    out.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
    out.AppliedBasePathloss_dB = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
    out.AppliedPathloss_dB = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
    out.AppliedShadowFading_dB = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
    out.AppliedO2I_dB = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
    out.AppliedLargeScaleGainSource = char(string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", "")));
    out.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
    out.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN));
    out.ChannelModelApplied = char(string(sixgr.util.structGet(replay, "ChannelModelApplied", "")));
    out.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
    strictNoiseVarianceRequired = ~localThermalNoiseSINRUnavailable(replay);
    noiseVarArgs = {};
    if isnumeric(injectedNoiseVariance) && isscalar(injectedNoiseVariance) && ...
            isfinite(double(injectedNoiseVariance)) && double(injectedNoiseVariance) >= 0
        noiseVarArgs = {"NoiseVar", double(injectedNoiseVariance)};
    end
    [rx, ~] = sixgr.phy.ul.SRS_Rx(rxWave, cfg, ...
        "Carrier", tx.Carrier, ...
        "SRS", tx.SRS, ...
        noiseVarArgs{:}, ...
        "StrictNoiseVarianceRequired", strictNoiseVarianceRequired);
    out.NoiseVariance = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
    out.NoiseVarStatus = char(string(sixgr.util.structGet(rx, "NoiseVarStatus", "")));
    out.NoiseVarSource = char(string(sixgr.util.structGet(rx, "NoiseVarSource", "")));
    out.NoiseVarReason = char(string(sixgr.util.structGet(rx, "NoiseVarReason", "")));
    out.NoiseVarStrictFailure = logical(sixgr.util.structGet(rx, "NoiseVarStrictFailure", false));
    out.MeasurementAttempted = logical(sixgr.util.structGet(rx, "MeasurementAttempted", false));
    out.MeasurementUsable = logical(sixgr.util.structGet(rx, "MeasurementUsable", false));
    out.FailureReason = char(string(sixgr.util.structGet(rx, "FailureReason", "")));

    if isempty(rx.Hest)
        out.Ok = false;
        out.Notes = "SRS channel estimate is empty.";
        return;
    end
    out.ChannelEstimateUsable = true;

    hEst = localSRSLSEstimate(rx.Hest, rx.RxGrid, tx.SRSIndices, tx.SRSSymbols);
    [hTrue, symTimes_s, symIdx] = localReferencePilotChannel(tx.Carrier, tx.SRSIndices, tx.SRS, sampleRateHz, injectedDopplerHz);
    nmse = localNormalizedMSE(hEst, hTrue);
    estimatedDopplerHz = localEstimateDopplerHz(hEst, symTimes_s);
    out.DopplerEstimateCRLB_Hz = localDopplerCRLBHz(hEst, symTimes_s, rx.NoiseVar);

    out.NMSE_dB = 10*log10(max(nmse, eps));
    out.InterpolationLoss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue);
    out.MismatchSensitivity_dB = localStaticMismatchSensitivity(hTrue);
    out.QCLAccuracy = localReferenceCorrelation(hEst, hTrue);
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = 0;
    out.AirInterfaceObservation_ms = 1e3 * (size(txWaveForReference, 1) / max(sampleRateHz, eps));
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.TrackingFailure = 0;
    out.InjectedDoppler_Hz = injectedDopplerHz;
    out.EstimatedDopplerHz = estimatedDopplerHz;
    if isfinite(out.EstimatedDopplerHz) && isfinite(out.InjectedDoppler_Hz)
        out.DopplerError_Hz = out.EstimatedDopplerHz - out.InjectedDoppler_Hz;
    end
    srsULCSI = sixgr.phy.ul.estimateSRSRITPMI(rx.Hest, rx.NoiseVar, cfg);
    out.EstimatedRI = double(sixgr.util.structGet(srsULCSI, "RI", NaN));
    out.EstimatedTPMI = double(sixgr.util.structGet(srsULCSI, "TPMI", NaN));
    out.RankEstimate = out.EstimatedRI;
    out.RIEstimate = out.EstimatedRI;
    out.TPMIEstimate = out.EstimatedTPMI;
    out.RISource = char(string(sixgr.util.structGet(srsULCSI, "RISource", "")));
    out.TPMISource = char(string(sixgr.util.structGet(srsULCSI, "TPMISource", "")));
    out.TPMICandidateCount = double(sixgr.util.structGet(srsULCSI, "TPMICandidateCount", NaN));
    out.TPMIMutualInformation = double(sixgr.util.structGet(srsULCSI, "TPMIMutualInformation", NaN));
    out.SRSConditionNumber_dB = double(sixgr.util.structGet(srsULCSI, "ConditionNumber_dB", NaN));
    linkState = sixgr.phy.ul.measureULLinkState(rx.Hest, rx.NoiseVar, cfg, ...
        "ReceivedGrid", rx.RxGrid, ...
        "ReferenceIndices", tx.SRSIndices, ...
        "ReferenceSymbols", tx.SRSSymbols);
    out.SINR_dB = double(sixgr.util.structGet(linkState, "SINR_dB", NaN));
    out.SINRSource = char(string(sixgr.util.structGet(linkState, "SINRSource", "")));
    out.SINRValueStatus = char(string(sixgr.util.structGet(linkState, "SINRValueStatus", "")));
    if localThermalNoiseSINRUnavailable(replay)
        out.SINR_dB = NaN;
        out.SINRSource = "ul_srs_sinr_unavailable_without_runtime_rx_power_or_pathloss";
        out.SINRValueStatus = "unavailable";
        out.CQI = NaN;
        out.CQISource = "";
        out.CQIValueStatus = "unavailable";
    else
        rawCQI = double(sixgr.util.structGet(linkState, "CQI", NaN));
        if isfinite(rawCQI)
            out.CQI = double(max(0, min(15, round(rawCQI))));
        else
            out.CQI = NaN;
        end
        out.CQISource = char(string(sixgr.util.structGet(linkState, "CQISource", "")));
        out.CQIValueStatus = char(string(sixgr.util.structGet(linkState, "CQIValueStatus", "")));
    end
    if isfinite(out.CQI) && out.CQI >= 0
        [modStr, targetCodeRate, mcsIndex] = sixgr.link.amcFromCQI(out.CQI, "", NaN, cfg, "UL");
        out.MCSIndex = double(mcsIndex);
        out.Modulation = char(string(modStr));
        out.TargetCodeRate = double(targetCodeRate);
    end
    out.Ok = true;
    out.MeasurementAttempted = true;
    out.MeasurementUsable = isfinite(out.SINR_dB) && strcmpi(string(out.SINRValueStatus), "OK");
    if logical(out.MeasurementUsable)
        out.Notes = "SRS NMSE=" + string(round(out.NMSE_dB,2)) + ...
            " dB, injected Doppler=" + string(round(injectedDopplerHz, 3)) + " Hz" + ...
            ", CQI=" + string(out.CQI) + ", MCS=" + string(out.MCSIndex);
    else
        out.Notes = "SRS channel estimate available; SINR/CQI unavailable from receiver noise evidence: " + ...
            string(out.NoiseVarReason);
    end
catch ME
    out.Ok = false;
    out.TrackingFailure = 1;
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runSRSChannelEstimation failed: " + string(ME.message));
    end
end
end

function tf = localThermalNoiseSINRUnavailable(replay)
noiseMode = lower(strtrim(string(sixgr.util.structGet(replay, "NoiseOperatingMode", ""))));
if noiseMode ~= "receiver_noise_figure_thermal_noise"
    tf = false;
    return;
end
servingSource = lower(strtrim(string(sixgr.util.structGet(replay, "ServingRxPowerSource", ""))));
noiseSource = lower(strtrim(string(sixgr.util.structGet(replay, "NoisePowerSource", ""))));
tf = servingSource == "unavailable_missing_pathloss_or_runtime_rx_power" || ...
    noiseSource == "thermal_noise_unavailable_missing_pathloss_or_runtime_rx_power";
end

function [y, nVar, replay, referenceWaveform, state] = localApplySRSChannelAndNoise(x, cfg, tx, info, sampleRateHz, injectedDopplerHz, snr_dB, state, trialIdx)
if nargin < 8
    state = [];
end
if nargin < 9
    trialIdx = 1;
end
txInfo = struct("OFDM", sixgr.util.structGet(info, "OFDMInfo", struct()));
if ~(isstruct(state) && logical(sixgr.util.structGet(state, "Initialized", false)))
    state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
    state.ChannelSeed = localTrialSeed(cfg, trialIdx);
end
[y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state);
useFading = logical(sixgr.util.structGet(channelReplay, "ChannelFadingApplied", false));
if ~useFading
    y = localApplyTrackingDoppler(x, sampleRateHz, injectedDopplerHz);
end
referenceWaveform = y;

cfgReplay = localPrepareSRSReplayCfg(cfg, snr_dB);
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz);
replay = impairmentReplay;
chFields = fieldnames(channelReplay);
for chIdx = 1:numel(chFields)
    replay.(chFields{chIdx}) = channelReplay.(chFields{chIdx});
end
replay.ChannelModelApplied = char(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
replay.ChannelFadingApplied = logical(useFading);
desiredWaveform = y;
[y, nVar] = localAddAwgnFromReplay(y, replay, desiredWaveform);
replay.InjectedNoiseVariance = double(nVar);
if isfinite(nVar) && nVar > 0
    replay.NoiseVarianceSource = "srs_replay_reference_waveform_awgn";
end
end

function cfgOut = localPrepareSRSReplayCfg(cfg, snr_dB)
cfgOut = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
if localShouldUseStandaloneAWGN(cfgOut, snr_dB)
    cfgOut = sixgr.util.structSet(cfgOut, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
end
end

function tf = localShouldUseStandaloneAWGN(cfg, snr_dB)
if ~(isfinite(double(snr_dB)))
    tf = false;
    return;
end
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if ~(awgnOnly || model == "AWGN" || model == "NONE" || model == "OFF")
    tf = false;
    return;
end
noiseMode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ""))));
tf = strlength(noiseMode) == 0 || noiseMode == "receiver_noise_figure_thermal_noise";
end

function seed = localTrialSeed(cfg, trialIdx)
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
if ~isfinite(seedBase)
    seedBase = 1;
end
seed = mod(round(seedBase) + max(1, round(double(trialIdx))) - 1, 2^31 - 2) + 1;
end

function localResetChannelOnce(chObj, seed)
if isempty(chObj)
    return;
end
try
    if isprop(chObj, "Seed")
        chObj.Seed = double(seed);
    end
catch
end
try
    reset(chObj);
catch
end
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

function sampleRateHz = localResolveSampleRate(info, tx, cfg)
sampleRateHz = sixgr.util.structGet(info, "OFDMInfo.SampleRate", []);
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
if isempty(sampleRateHz)
    try
        nrInfo = nrOFDMInfo(tx.Carrier);
        sampleRateHz = double(sixgr.util.structGet(nrInfo, "SampleRate", []));
    catch
        sampleRateHz = [];
    end
end
if isempty(sampleRateHz)
    error("sixgr:link:SRSChannelEstimationSampleRateMissing", ...
        "SRS tracking requires a known OFDM sample rate.");
end
sampleRateHz = double(sampleRateHz);
end

function dopplerHz = localResolveInjectedDopplerHz(cfg)
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
if ~isfinite(dopplerHz)
    dopplerHz = 0;
end
end

function y = localApplyTrackingDoppler(x, sampleRateHz, dopplerHz)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(dopplerHz) && dopplerHz ~= 0)
    return;
end
n = (0:size(y, 1)-1).';
h = exp(1j * 2 * pi * (dopplerHz / sampleRateHz) * n);
y = y .* h;
end

function hEst = localSRSLSEstimate(Hest, rxGrid, srsInd, srsSym)
hEst = [];
if isempty(srsInd) || isempty(srsSym)
    return;
end
pilotHest = localPilotChannelEstimateSlice(Hest, srsInd);
if ~isempty(pilotHest)
    hEst = pilotHest(:);
    return;
end
if isempty(rxGrid)
    return;
end
try
    pilotObs = nrExtractResources(srsInd, rxGrid);
catch
    if ndims(rxGrid) >= 3
        pilotObs = rxGrid(:, :, 1);
        pilotObs = pilotObs(srsInd);
    else
        pilotObs = rxGrid(srsInd);
    end
end
pilotObs = localCollapsePilotObservations(pilotObs);
srsSym = srsSym(:);
N = min(numel(pilotObs), numel(srsSym));
if N == 0
    return;
end
pilotObs = pilotObs(1:N);
srsSym = srsSym(1:N);
den = srsSym;
den(abs(den) < eps) = 1;
hEst = pilotObs ./ den;
end

function pilotH = localPilotChannelEstimateSlice(H, pilotInd)
pilotH = [];
if isempty(H) || isempty(pilotInd)
    return;
end
sz = size(H);
if numel(sz) < 2
    return;
end
K = sz(1);
L = sz(2);
Nr = 1;
Np = 1;
if numel(sz) >= 3
    Nr = sz(3);
end
if numel(sz) >= 4
    Np = sz(4);
end
flatDim = max(K * L, 1);
ind = double(pilotInd(:));
ind = ind(isfinite(ind) & ind >= 1);
if isempty(ind)
    return;
end
try
    pDim = max(1, ceil(max(ind) / flatDim));
    [k, l, p] = ind2sub([K, L, pDim], ind);
catch
    return;
end
N = numel(ind);
pilotH = complex(NaN(N, 1));
for i = 1:N
    portIdx = min(max(round(double(p(i))), 1), Np);
    if numel(sz) >= 4
        v = squeeze(H(k(i), l(i), :, portIdx));
    elseif numel(sz) == 3
        v = squeeze(H(k(i), l(i), :));
    else
        v = H(k(i), l(i));
    end
    if isempty(v)
        continue;
    end
    if Nr > 1 || numel(v) > 1
        pilotH(i) = mean(v(:), "omitnan");
    else
        pilotH(i) = v;
    end
end
mask = isfinite(real(pilotH)) & isfinite(imag(pilotH));
if ~any(mask)
    pilotH = [];
end
end

function obs = localCollapsePilotObservations(pilotObs)
if isempty(pilotObs)
    obs = [];
    return;
end
if isvector(pilotObs)
    obs = pilotObs(:);
    return;
end
obs = mean(pilotObs, 2, "omitnan");
obs = obs(:);
end

function [hTrue, symTimes_s, symIdx] = localReferencePilotChannel(carrier, pilotInd, srs, sampleRateHz, dopplerHz)
nPorts = max(1, round(double(sixgr.util.structGet(srs, "NumSRSPorts", 1))));
symIdx = localPilotSymbolIndices(carrier, pilotInd, nPorts);
symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz);
symTimes_s = symbolTimes(symIdx);
hTrue = exp(1j * 2 * pi * dopplerHz .* symTimes_s(:));
end

function symIdx = localPilotSymbolIndices(carrier, pilotInd, nPorts)
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
[~, symIdx, ~] = ind2sub([K, L, max(1, round(double(nPorts)))], double(pilotInd(:)));
symIdx = double(symIdx(:));
end

function symbolTimes_s = localSymbolCenterTimes(carrier, sampleRateHz)
L = double(carrier.SymbolsPerSlot);
symbolTimes_s = [];
try
    ofdmInfo = nrOFDMInfo(carrier);
    symbolLengths = double(sixgr.util.structGet(ofdmInfo, "SymbolLengths", []));
    if ~isempty(symbolLengths)
        symbolLengths = symbolLengths(:);
        if numel(symbolLengths) < L
            symbolLengths(end+1:L, 1) = symbolLengths(end);
        end
        symbolLengths = symbolLengths(1:L);
        symbolTimes_s = (cumsum(symbolLengths) - 0.5 * symbolLengths) / max(sampleRateHz, eps);
    end
catch
end
if isempty(symbolTimes_s)
    slotDur_s = 1e-3 / max(double(carrier.SubcarrierSpacing) / 15, eps);
    symDur_s = slotDur_s / max(L, 1);
    symbolTimes_s = ((0:L-1).' + 0.5) * symDur_s;
end
end

function nmse = localNormalizedMSE(hEst, hTrue)
hEst = hEst(:);
hTrue = hTrue(:);
N = min(numel(hEst), numel(hTrue));
if N == 0
    nmse = NaN;
    return;
end
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    nmse = NaN;
    return;
end
err = hEst(mask) - hTrue(mask);
hEst = hEst(mask);
hTrue = hTrue(mask);
alpha = (hTrue' * hEst) / max(hTrue' * hTrue, eps);
ref = alpha * hTrue;
err = hEst - ref;
den = mean(abs(ref).^2, "omitnan");
nmse = mean(abs(err).^2, "omitnan") / max(den, eps);
end

function qcl = localReferenceCorrelation(hEst, hTrue)
qcl = NaN;
hEst = hEst(:);
hTrue = hTrue(:);
N = min(numel(hEst), numel(hTrue));
if N == 0
    return;
end
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    return;
end
hEst = hEst(mask);
hTrue = hTrue(mask);
den = norm(hEst) * norm(hTrue);
if den <= 0
    return;
end
qcl = abs(hTrue' * hEst) / den;
end

function dopplerHz = localEstimateDopplerHz(hEst, symTimes_s)
dopplerHz = NaN;
hEst = hEst(:);
symTimes_s = double(symTimes_s(:));
N = min(numel(hEst), numel(symTimes_s));
if N == 0
    return;
end
hEst = hEst(1:N);
symTimes_s = symTimes_s(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(symTimes_s);
if nnz(mask) < 2
    dopplerHz = 0;
    return;
end
maxTime = max(symTimes_s(mask), [], "omitnan");
if isfinite(maxTime) && maxTime >= 1e-2
    error("sixgr:link:SRS:DopplerEstimateUnexpectedTimescale", ...
        "SRS symbol times appear to be in wrong units (max %.6g s). Expected less than 10 ms.", maxTime);
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    dopplerHz = 0;
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
phaseRange = max(phaseObs) - min(phaseObs);
if isfinite(phaseRange) && phaseRange > 0.9 * pi
    warning("sixgr:link:SRS:PhaseUnwrapRisk", ...
        "SRS phase range %.2f rad exceeds 90%% of pi; Doppler estimation may wrap.", phaseRange);
end
p = polyfit(uTimes(:), phaseObs(:), 1);
dopplerHz = p(1) / (2 * pi);
end

function crlbHz = localDopplerCRLBHz(hEst, symTimes_s, nVar)
crlbHz = NaN;
hEst = hEst(:);
symTimes_s = double(symTimes_s(:));
N = min(numel(hEst), numel(symTimes_s));
if N < 2
    return;
end
hEst = hEst(1:N);
symTimes_s = symTimes_s(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(symTimes_s);
if nnz(mask) < 2
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
if numel(hMean) < 2
    return;
end
snrLin = mean(abs(hMean).^2, "omitnan") / max(double(nVar), eps);
Lpilots = numel(hMean);
trep = mean(diff(uTimes), "omitnan");
if ~(isfinite(snrLin) && snrLin > 0 && isfinite(trep) && trep > 0 && Lpilots > 1)
    return;
end
crlbHz = sqrt(6 / (snrLin * Lpilots * (Lpilots^2 - 1) * (2 * pi * trep)^2));
end

function loss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue)
loss_dB = NaN;
symIdx = double(symIdx(:));
hEst = hEst(:);
hTrue = hTrue(:);
N = min([numel(symIdx), numel(hEst), numel(hTrue)]);
if N == 0
    return;
end
symIdx = symIdx(1:N);
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(symIdx) & isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if nnz(mask) < 3
    loss_dB = 0;
    return;
end
[uSym, ~, grp] = unique(symIdx(mask), "stable");
if numel(uSym) < 3
    loss_dB = 0;
    return;
end
hEstSym = accumarray(grp, hEst(mask), [], @localComplexMean);
hTrueSym = accumarray(grp, hTrue(mask), [], @localComplexMean);
coarseSel = 1:2:numel(uSym);
if numel(coarseSel) < 2
    loss_dB = 0;
    return;
end
hInterp = complex( ...
    interp1(double(uSym(coarseSel)), real(hEstSym(coarseSel)), double(uSym), "linear", "extrap"), ...
    interp1(double(uSym(coarseSel)), imag(hEstSym(coarseSel)), double(uSym), "linear", "extrap"));
nmse = localNormalizedMSE(hInterp, hTrueSym);
loss_dB = 10 * log10(max(nmse, eps));
end

function sens_dB = localStaticMismatchSensitivity(hTrue)
sens_dB = NaN;
hTrue = hTrue(:);
mask = isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    return;
end
hTrue = hTrue(mask);
hStatic = mean(hTrue, "omitnan");
nmse = mean(abs(hTrue - hStatic).^2, "omitnan") / max(mean(abs(hTrue).^2, "omitnan"), eps);
sens_dB = 10 * log10(max(nmse, eps));
end

function y = localComplexMean(x)
if isempty(x)
    y = complex(NaN);
else
    y = mean(x, "omitnan");
end
end
