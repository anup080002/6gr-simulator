function out = runPUCCHWaveformTrial(cfg, varargin)
%RUNPUCCHWAVEFORMTRIAL Execute one waveform-backed PUCCH UCI trial.
% Keep this file ASCII-only.

p = inputParser;
p.FunctionName = "sixgr.link.runPUCCHWaveformTrial";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "ExpectedUCIBits", int8(1), @(x) isnumeric(x) || islogical(x));
addParameter(p, "SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", NaN), @(x) isnumeric(x) && isscalar(x));
addParameter(p, "Format", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
addParameter(p, "RNTI", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
addParameter(p, "InterferenceBundle", struct([]), @(x) isstruct(x));
addParameter(p, "ChannelState", [], @(x) isempty(x) || isstruct(x));
addParameter(p, "TrialIndex", 1, @(x) isnumeric(x) && isscalar(x));
parse(p, cfg, varargin{:});
opt = p.Results;
trialIdx = max(1, round(double(opt.TrialIndex)));

expectedBits = int8(logical(opt.ExpectedUCIBits(:)));
if isempty(expectedBits)
    expectedBits = int8(1);
end

out = struct( ...
    "Ok", false, ...
    "Skipped", false, ...
    "Crash", false, ...
    "Status", "FAIL", ...
    "ExpectedBits", expectedBits, ...
    "DecodedBits", int8([]), ...
    "AckObserved", false, ...
    "UCIContentMatch", false, ...
    "CRCApplicable", false, ...
    "CRCOutcome", "not_applicable", ...
    "DetectionOutcome", "unavailable", ...
    "BitsCompared", 0, ...
    "BitErrors", NaN, ...
    "DetectionMetric", NaN, ...
    "DetectionThreshold", NaN, ...
    "DetectionMetricStatus", "", ...
    "DetectorPeakMetric", NaN, ...
    "DetectorNoiseFloor", NaN, ...
    "DTXFlag", false, ...
    "DTXReason", "", ...
    "ComputeLatency_ms", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "AirInterfaceTTI_ms", NaN, ...
    "AirInterfaceObservation_ms", NaN, ...
    "ProcedureDelay_ms", 0, ...
    "NoiseVariance", NaN, ...
    "NoiseVarStatus", "", ...
    "NoiseVarSource", "", ...
    "NoiseVarReason", "", ...
    "NoiseVarStrictFailure", false, ...
    "ReceiverUsable", false, ...
    "DetectionAttempted", false, ...
    "DetectionUsable", false, ...
    "FailureReason", "", ...
    "ConfiguredSNR_dB", double(opt.SNR_dB), ...
    "AppliedAWGNSNR_dB", NaN, ...
    "DesiredSignalPowerBeforeNoise", NaN, ...
    "CompositeSignalPowerBeforeNoise", NaN, ...
    "AppliedNoiseSNR_dB", NaN, ...
    "NoiseVarianceSource", "", ...
    "NoiseOperatingMode", "", ...
    "NoisePowerSource", "", ...
    "ThermalNoisePower_dBm", NaN, ...
    "ServingRxPower_dBm", NaN, ...
    "ServingRxPowerSource", "", ...
    "ReceiverHestSINR_dB", NaN, ...
    "ReceiverHestSINRSource", "", ...
    "ReceiverHestSINRValueRole", "", ...
    "ReceiverHestSINRValueStatus", "", ...
    "ReceiverHestSINRNAReason", "", ...
    "SINRValueRole", "", ...
    "SINRSource", "", ...
    "SINRValueStatus", "", ...
    "SINRValueDefinition", "", ...
    "MeasuredTrialSINR_dB", NaN, ...
    "MeasuredTrialSINRSource", "", ...
    "MeasuredTrialSINRValueRole", "", ...
    "MeasuredTrialSINRValueStatus", "", ...
    "MeasuredTrialSINRNAReason", "", ...
    "EstimatedWidebandSINR_dB", NaN, ...
    "WidebandCQI", NaN, ...
    "RankIndicator", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "ChannelGain_dB", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "NumRxAntennas", NaN, ...
    "NumTxPorts", NaN, ...
    "RequestedFormat", NaN, ...
    "ResolvedFormat", NaN, ...
    "FormatAdapted", false, ...
    "FormatAdaptationReason", "", ...
    "ControlResourceValidity", false, ...
    "CrashSource", "", ...
    "CrashMessage", "", ...
    "ChannelModel", "", ...
    "DopplerHz", NaN, ...
    "TimingEstimateUsed", false, ...
    "UseIdealTimingSync", false, ...
    "InterferenceMode", "none", ...
    "InterferenceContributorCount", 0, ...
    "InterferenceAggregatedRxPower_dBm", NaN, ...
    "InterferencePowerSource", "", ...
    "FullInterfererChannelTruthUsed", false, ...
    "Replay", struct(), ...
    "Tx", struct(), ...
    "TxInfo", struct(), ...
    "ChannelState", opt.ChannelState, ...
    "Rx", struct(), ...
    "RxInfo", struct(), ...
    "Notes", "");

if ~logical(sixgr.util.structGet(cfg, "phy.pucch.enable", true))
    out.Skipped = true;
    out.Ok = false;
    out.Status = "SKIP";
    out.Notes = "Skipped: cfg.phy.pucch.enable=false";
    return;
end

fmt = sixgr.util.structGet(cfg, "phy.pucch.format", 2);
if ~isempty(opt.Format)
    fmt = double(opt.Format);
end
requestedFormat = double(fmt);
resolvedFormat = localResolveCompatiblePUCCHFormat(requestedFormat, numel(expectedBits));
cfgResolved = sixgr.util.structSet(cfg, "phy.pucch.format", resolvedFormat);
previewInterference = localPreviewInterferenceMetadata(opt.InterferenceBundle);
out.RequestedFormat = requestedFormat;
out.ResolvedFormat = resolvedFormat;
out.FormatAdapted = requestedFormat ~= resolvedFormat;
out.FormatAdaptationReason = ternaryFormatReason(requestedFormat, resolvedFormat, numel(expectedBits));
out.ControlResourceValidity = true;
out.ChannelModel = char(localResolveTrialChannelModel(cfgResolved));
out.DopplerHz = double(localResolveDopplerHz(cfgResolved));
out.InterferenceMode = char(string(sixgr.util.structGet(previewInterference, "InterferenceMode", "none")));
out.InterferenceContributorCount = double(sixgr.util.structGet(previewInterference, "InterferenceContributorCount", 0));
out.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet(previewInterference, "FullInterfererChannelTruthUsed", false));

try
    txArgs = {"Format", resolvedFormat};
    if ~isempty(opt.RNTI)
        txArgs = [txArgs {"RNTI", double(opt.RNTI)}]; %#ok<AGROW>
    end
    [tx, txInfo] = sixgr.phy.ul.PUCCH_Tx(cfgResolved, expectedBits, txArgs{:});
    rng(localTrialSeed(cfgResolved, trialIdx), "twister");
    chState = opt.ChannelState;
    if ~(isstruct(chState) && logical(sixgr.util.structGet(chState, "Initialized", false)))
        chState = localInitULChannelState(cfgResolved, tx, txInfo, trialIdx);
    end
    [rxWave, replay] = localApplyULChannelAndNoise(tx.Waveform, double(opt.SNR_dB), chState, cfgResolved, tx, txInfo, opt.InterferenceBundle);
    out.ChannelState = chState;

    tDecode = tic;
    strictNoiseVarianceRequired = ~localThermalNoiseSINRUnavailable(replay);
    [rx, rxInfo] = sixgr.phy.ul.PUCCH_Rx(rxWave, cfgResolved, ...
        "Carrier", tx.Carrier, ...
        "PUCCH", tx.PUCCH, ...
        "Format", resolvedFormat, ...
        "NumUCIBits", numel(expectedBits), ...
        "ExpectedUCIBits", expectedBits, ...
        "NoiseVar", sixgr.util.structGet(replay, "InjectedNoiseVariance", []), ...
        "StrictNoiseVarianceRequired", strictNoiseVarianceRequired);
    decodeLatency_ms = toc(tDecode) * 1e3;

    out.NoiseVariance = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
    out.NoiseVarStatus = char(string(sixgr.util.structGet(rx, "NoiseVarStatus", "")));
    out.NoiseVarSource = char(string(sixgr.util.structGet(rx, "NoiseVarSource", "")));
    out.NoiseVarReason = char(string(sixgr.util.structGet(rx, "NoiseVarReason", "")));
    out.NoiseVarStrictFailure = logical(sixgr.util.structGet(rx, "NoiseVarStrictFailure", false));
    out.ReceiverUsable = logical(sixgr.util.structGet(rx, "ReceiverUsable", false));
    out.DetectionAttempted = logical(sixgr.util.structGet(rx, "DetectionAttempted", false));
    out.DetectionUsable = logical(sixgr.util.structGet(rx, "DetectionUsable", false));
    out.FailureReason = char(string(sixgr.util.structGet(rx, "FailureReason", "")));
    out.DetectionThreshold = double(sixgr.util.structGet(rx, "DetectionThreshold", NaN));
    out.DetectionMetricStatus = char(string(sixgr.util.structGet(rx, "DetectionMetricStatus", "")));
    out.DetectorPeakMetric = double(sixgr.util.structGet(rx, "DetectorPeakMetric", NaN));
    out.DetectorNoiseFloor = double(sixgr.util.structGet(rx, "DetectorNoiseFloor", NaN));
    out.DTXFlag = logical(sixgr.util.structGet(rx, "DTXFlag", false));
    out.DTXReason = char(string(sixgr.util.structGet(rx, "DTXReason", "")));
    out.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", opt.SNR_dB));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
    out.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "DesiredSignalPowerBeforeNoise", NaN));
    out.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "CompositeSignalPowerBeforeNoise", NaN));
    out.AppliedNoiseSNR_dB = double(sixgr.util.structGet(replay, "AppliedNoiseSNR_dB", NaN));
    out.NoiseVarianceSource = char(string(sixgr.util.structGet(replay, "NoiseVarianceSource", "")));
    out.NoiseOperatingMode = char(string(sixgr.util.structGet(replay, "NoiseOperatingMode", "")));
    out.NoisePowerSource = char(string(sixgr.util.structGet(replay, "NoisePowerSource", "")));
    out.ThermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
    out.ServingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
    out.ServingRxPowerSource = char(string(sixgr.util.structGet(replay, "ServingRxPowerSource", "")));
    out.AirInterfaceTTI_ms = localAirInterfaceTTI(tx, txInfo);
    out.AirInterfaceObservation_ms = out.AirInterfaceTTI_ms;
    out.ProcedureDelay_ms = 0;
    out.TimingEstimateUsed = logical(sixgr.util.structGet(replay, "TimingEstimateUsed", false));
    out.UseIdealTimingSync = logical(sixgr.util.structGet(replay, "UseIdealTimingSync", false));
    out.InterferenceMode = char(string(sixgr.util.structGet(replay, "InterferenceMode", "none")));
    out.InterferenceContributorCount = double(sixgr.util.structGet(replay, "InterferenceContributorCount", 0));
    out.InterferenceAggregatedRxPower_dBm = double(sixgr.util.structGet(replay, "InterferenceAggregatedRxPower_dBm", NaN));
    out.InterferencePowerSource = char(string(sixgr.util.structGet(replay, "InterferencePowerSource", "")));
    out.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet(replay, "FullInterfererChannelTruthUsed", false));
    out.Replay = replay;
    out.Tx = tx;
    out.TxInfo = txInfo;
    out.Rx = rx;
    out.RxInfo = rxInfo;

    if ~logical(out.DetectionUsable)
        out.Ok = false;
        out.Status = "NA";
        out.UCIContentMatch = false;
        out.BitsCompared = 0;
        out.BitErrors = NaN;
        out.DetectionMetric = double(sixgr.util.structGet(rx, "DetectorPeakMetric", localResolveDetectionMetric(rx)));
        out.ComputeLatency_ms = double(decodeLatency_ms);
        out.DecodeLatency_ms = double(decodeLatency_ms);
        out.ReceiverHestSINR_dB = NaN;
        out.ReceiverHestSINRSource = "";
        out.ReceiverHestSINRValueRole = "unavailable";
        out.ReceiverHestSINRValueStatus = "unavailable";
        out.ReceiverHestSINRNAReason = char(string(out.FailureReason));
        out.MeasuredTrialSINR_dB = NaN;
        out.MeasuredTrialSINRSource = "";
        out.MeasuredTrialSINRValueRole = "unavailable";
        out.MeasuredTrialSINRValueStatus = "unavailable";
        out.MeasuredTrialSINRNAReason = char(string(out.FailureReason));
        out.SINRValueRole = "unavailable";
        out.SINRSource = "";
        out.SINRValueStatus = "unavailable";
        out.SINRValueDefinition = "no_control_sinr_observation_available_in_active_runtime";
        out.CRCOutcome = "not_applicable";
        out.DetectionOutcome = "unavailable";
        out.Notes = "Waveform-backed PUCCH detection unavailable: " + string(out.FailureReason);
        return;
    end

    decodedBits = localNormalizeUCIBits(sixgr.util.structGet(rx, "UCIBits", int8([])));
    [bitErrors, bitsCompared] = localBitErrors(expectedBits, decodedBits);
    detMetric = localResolveDetectionMetric(rx);
    ok = logical(sixgr.util.structGet(rx, "Ok", false)) && bitErrors == 0 && bitsCompared == numel(expectedBits);

    out.Ok = logical(ok);
    out.Status = ternaryStatus(ok);
    out.ExpectedBits = expectedBits;
    out.DecodedBits = decodedBits;
    out.AckObserved = localFirstLogical(decodedBits, false);
    out.UCIContentMatch = logical(bitErrors == 0 && bitsCompared == numel(expectedBits));
    out.CRCApplicable = false;
    out.CRCOutcome = "not_applicable";
    out.DetectionOutcome = localResolvePUCCHDetectionOutcome(out.DetectionUsable, out.UCIContentMatch);
    out.BitsCompared = double(bitsCompared);
    out.BitErrors = double(bitErrors);
    out.DetectionMetric = double(detMetric);
    out.ComputeLatency_ms = double(decodeLatency_ms);
    out.DecodeLatency_ms = double(decodeLatency_ms);
    measurement = localMeasurePUCCHLinkState(cfgResolved, rx, rxInfo);
    out.ReceiverHestSINR_dB = double(sixgr.util.structGet(measurement, "SINR_dB", NaN));
    out.ReceiverHestSINRSource = char(string(sixgr.util.structGet(measurement, "SINRSource", "")));
    out.ReceiverHestSINRValueRole = char(string(sixgr.util.structGet(measurement, "SINRValueRole", "")));
    out.ReceiverHestSINRValueStatus = char(string(sixgr.util.structGet(measurement, "SINRValueStatus", "")));
    out.ReceiverHestSINRNAReason = char(string(sixgr.util.structGet(measurement, "SINRNAReason", "")));
    receiverStatus = strtrim(string(out.ReceiverHestSINRValueStatus));
    receiverRole = strtrim(string(out.ReceiverHestSINRValueRole));
    receiverSource = strtrim(string(out.ReceiverHestSINRSource));
    unanchoredThermalSINR = localThermalNoiseSINRUnavailable(replay);
    receiverUsesFallbackEstimate = contains(lower(receiverSource), "fallback") || ...
        contains(lower(receiverRole), "fallback") || contains(lower(receiverStatus), "fallback") || ...
        unanchoredThermalSINR;
    if receiverUsesFallbackEstimate
        out.ReceiverHestSINR_dB = NaN;
        out.ReceiverHestSINRSource = "";
        out.ReceiverHestSINRValueRole = "unavailable";
        out.ReceiverHestSINRValueStatus = "unavailable";
        if unanchoredThermalSINR
            out.ReceiverHestSINRNAReason = "thermal_noise_sinr_unavailable_without_runtime_rx_power_or_pathloss";
        else
            out.ReceiverHestSINRNAReason = "control_reference_signal_sinr_not_available_from_receiver_evidence";
        end
        receiverStatus = "unavailable";
        receiverRole = "unavailable";
        receiverSource = "";
    end
    out.MeasuredTrialSINR_dB = NaN;
    out.MeasuredTrialSINRSource = "";
    out.MeasuredTrialSINRValueRole = "unavailable";
    out.MeasuredTrialSINRValueStatus = "unavailable";
    out.MeasuredTrialSINRNAReason = "pucch_has_no_data_post_equalization_sinr_measurement";
    if isfinite(double(out.ReceiverHestSINR_dB))
        out.SINRValueRole = char(receiverRole);
        out.SINRSource = char(receiverSource);
        out.SINRValueStatus = char(receiverStatus);
        out.SINRValueDefinition = "diagnostic_receiver_hest_sinr_from_control_reference_signal_observation_not_scheduling_input";
    else
        out.SINRValueRole = "unavailable";
        out.SINRSource = char(receiverSource);
        out.SINRValueStatus = char(receiverStatus);
        out.SINRValueDefinition = "no_control_sinr_observation_available_in_active_runtime";
    end
    out.EstimatedWidebandSINR_dB = NaN;
    out.WidebandCQI = NaN;
    if unanchoredThermalSINR
        out.EstimatedWidebandSINR_dB = NaN;
        out.WidebandCQI = NaN;
    end
    out.RankIndicator = double(sixgr.util.structGet(measurement, "RI", NaN));
    out.PMI = double(sixgr.util.structGet(measurement, "PMI", NaN));
    out.CRI = double(sixgr.util.structGet(measurement, "CRI", NaN));
    out.ChannelGain_dB = double(sixgr.util.structGet(measurement, "ChannelGain_dB", NaN));
    out.ConditionNumber_dB = double(sixgr.util.structGet(measurement, "ConditionNumber_dB", NaN));
    out.NumRxAntennas = double(sixgr.util.structGet(measurement, "NumRxAnt", NaN));
    out.NumTxPorts = double(sixgr.util.structGet(measurement, "NumTxPorts", NaN));
    out.Notes = "Waveform-backed PUCCH HARQ/feedback trial using active uplink PHY primitives." + ...
        ternaryFormatNote(requestedFormat, resolvedFormat);
catch ME
    out.Crash = true;
    out.Ok = false;
    out.Status = "CRASH";
    out.CrashSource = string(ME.identifier);
    out.CrashMessage = string(ME.message);
    out.Notes = string(ME.message);
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

function fmt = localResolveCompatiblePUCCHFormat(requestedFormat, numBits)
fmt = double(requestedFormat);
numBits = max(0, round(double(numBits)));
if ~(isfinite(fmt) && any(fmt == [0 1 2 3 4]))
    if numBits <= 2
        fmt = 1;
    else
        fmt = 2;
    end
    return;
end
if numBits <= 2 && any(fmt == [2 3 4])
    fmt = 1;
elseif numBits > 2 && any(fmt == [0 1])
    fmt = 2;
end
end

function note = ternaryFormatNote(requestedFormat, resolvedFormat)
if isfinite(double(requestedFormat)) && isfinite(double(resolvedFormat)) && double(requestedFormat) ~= double(resolvedFormat)
    note = " Requested format " + string(requestedFormat) + " was adapted to " + string(resolvedFormat) + ...
        " to match the active UCI payload size.";
else
    note = "";
end
end

function reason = ternaryFormatReason(requestedFormat, resolvedFormat, numBits)
if ~(isfinite(double(requestedFormat)) && isfinite(double(resolvedFormat))) || double(requestedFormat) == double(resolvedFormat)
    reason = "";
    return;
end
if double(numBits) <= 2 && any(double(requestedFormat) == [2 3 4]) && double(resolvedFormat) == 1
    reason = "uci_payload_size_demoted_to_short_format";
elseif double(numBits) > 2 && any(double(requestedFormat) == [0 1]) && double(resolvedFormat) == 2
    reason = "uci_payload_size_promoted_to_long_format";
else
    reason = "runtime_format_compatibility_adjustment";
end
end

function preview = localPreviewInterferenceMetadata(bundle)
preview = struct( ...
    "InterferenceMode", "none", ...
    "InterferenceContributorCount", 0, ...
    "FullInterfererChannelTruthUsed", false);
if ~(isstruct(bundle) && ~isempty(bundle))
    return;
end
preview.InterferenceContributorCount = double(numel(bundle));
modeTokens = strings(0, 1);
for idx = 1:numel(bundle)
    modeTokens(end+1, 1) = string(sixgr.util.structGet(bundle(idx), "InterferenceMode", "")); %#ok<AGROW>
end
modeTokens = upper(strtrim(modeTokens));
modeTokens = modeTokens(strlength(modeTokens) > 0);
if isempty(modeTokens)
    preview.InterferenceMode = "interference_bundle_present_mode_unspecified";
elseif numel(unique(modeTokens)) == 1
    preview.InterferenceMode = char(lower(modeTokens(1)));
else
    preview.InterferenceMode = "mixed_requested_interference_modes";
end
preview.FullInterfererChannelTruthUsed = any(strcmpi(modeTokens, "FULL_PER_LINK_CHANNEL_WAVEFORM_SUM"));
end

function outcome = localResolvePUCCHDetectionOutcome(detectionUsable, contentMatch)
if ~logical(detectionUsable)
    outcome = "unavailable";
elseif logical(contentMatch)
    outcome = "detected";
else
    outcome = "missed";
end
end

function state = localInitULChannelState(cfg, tx, txInfo, trialIdx)
if nargin < 4
    trialIdx = 1;
end
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0, "ChannelSeed", localTrialSeed(cfg, trialIdx));

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
    return;
end

cfgCh = cfg;
dopp = localResolveDopplerHz(cfgCh);
cfgCh.channel.doppler_Hz = max(0, dopp);

if startsWith(modelRaw, "TDL")
    cfgCh.channel.model = "TDL";
    if modelRaw ~= "TDL"
        cfgCh.channel.tdlProfile = char(modelRaw);
    end
elseif startsWith(modelRaw, "CDL")
    cfgCh.channel.model = "CDL";
    if modelRaw ~= "CDL"
        cfgCh.channel.cdlProfile = char(modelRaw);
    end
else
    cfgCh.channel.model = char(modelRaw);
end

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(tx.Waveform, 2));
numRx = localResolveULNumRxAnt(cfg, numTx);

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", state.ChannelSeed);
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    localResetChannelOnce(state.Obj, state.ChannelSeed);
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
end
end

function [y, replay] = localApplyULChannelAndNoise(x, snr_dB, state, cfg, tx, txInfo, interferenceBundle)
y = x;
replay = struct( ...
    "RawWaveform", x, ...
    "CorrectedWaveform", x, ...
    "InjectedNoiseVariance", NaN, ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", NaN, ...
    "InterferenceMode", "none", ...
    "InterferenceContributorCount", 0, ...
    "InterferenceAggregatedRxPower_dBm", NaN, ...
    "InterferencePowerSource", "", ...
    "FullInterfererChannelTruthUsed", false);

if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
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

sampleRateHz = localResolveSampleRate(tx, txInfo);
cfgReplay = localPrepareControlReplayCfg(cfg, snr_dB);
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz);
impairFields = fieldnames(impairmentReplay);
for fi = 1:numel(impairFields)
    replay.(impairFields{fi}) = impairmentReplay.(impairFields{fi});
end
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
desiredWaveform = y;
[interferenceWaveform, interferenceMeta] = sixgr.link.synthesizeInterferenceWaveform("UL", desiredWaveform, replay, interferenceBundle);
interferenceWaveformVariance = NaN;
if ~isempty(interferenceWaveform)
    interferenceWaveformVariance = mean(abs(double(interferenceWaveform(:))).^2, "omitnan");
    y = y + cast(interferenceWaveform, "like", y);
end
replay.InterferenceWaveformVariance = double(interferenceWaveformVariance);
replay.InterferenceMode = char(string(sixgr.util.structGet(interferenceMeta, "InterferenceMode", replay.InterferenceMode)));
replay.InterferenceContributorCount = double(sixgr.util.structGet(interferenceMeta, "Contributors", 0));
replay.InterferenceAggregatedRxPower_dBm = double(sixgr.util.structGet(interferenceMeta, "AggregatedRxPower_dBm", NaN));
replay.InterferencePowerSource = char(string(sixgr.util.structGet(interferenceMeta, "PowerSource", "")));
replay.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet(interferenceMeta, "FullPerLinkChannelTruthUsed", false));
if strlength(strtrim(string(replay.InterferencePowerSource))) == 0 && replay.InterferenceContributorCount > 0
    replay.InterferencePowerSource = "sample_domain_interference_sum";
end
preNoiseWaveform = y;
[y, replay.InjectedNoiseVariance, replay.NoiseVarianceSource] = localAddAwgn(y, replay, desiredWaveform);
replay.DesiredSignalPowerBeforeNoise = localMeanSamplePower(desiredWaveform);
replay.CompositeSignalPowerBeforeNoise = localMeanSamplePower(preNoiseWaveform);
if isfinite(replay.DesiredSignalPowerBeforeNoise) && replay.DesiredSignalPowerBeforeNoise > 0 && ...
        isfinite(replay.InjectedNoiseVariance) && replay.InjectedNoiseVariance > 0
    replay.AppliedNoiseSNR_dB = 10 * log10(replay.DesiredSignalPowerBeforeNoise / replay.InjectedNoiseVariance);
else
    replay.AppliedNoiseSNR_dB = NaN;
end
end

function cfgOut = localPrepareControlReplayCfg(cfg, snr_dB)
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

function [y, nVar, source] = localAddAwgn(x, replay, referenceWaveform)
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    thermalNVar = localResolveThermalNoiseVariance(replay, referenceWaveform);
    [nVar, source] = localReceiverEffectiveNoiseVariance(thermalNVar, replay, "thermal_noise_plus_receiver_nf");
    if isfinite(thermalNVar) && thermalNVar > 0
        n = sqrt(thermalNVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
    y = x;
    return;
end
appliedSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
awgnNVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, appliedSNR_dB);
[nVar, source] = localReceiverEffectiveNoiseVariance(awgnNVar, replay, "standalone_awgn_snr_argument_post_channel_units");
if isfinite(awgnNVar) && awgnNVar >= 0
    if awgnNVar > 0
        n = sqrt(awgnNVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
    else
        y = x;
    end
    return;
end
[y, nVar] = sixgr.util.addAwgnComplex(x, appliedSNR_dB);
[nVar, source] = localReceiverEffectiveNoiseVariance(nVar, replay, "legacy_addAwgnComplex_last_resort");
end

function [effectiveNVar, source] = localReceiverEffectiveNoiseVariance(baseNVar, replay, baseSource)
effectiveNVar = double(baseNVar);
source = string(baseSource);
interferenceNVar = double(sixgr.util.structGet(replay, "InterferenceWaveformVariance", NaN));
if isfinite(interferenceNVar) && interferenceNVar > 0
    if isfinite(effectiveNVar) && effectiveNVar >= 0
        effectiveNVar = effectiveNVar + interferenceNVar;
    else
        effectiveNVar = interferenceNVar;
    end
    source = source + "_plus_full_waveform_interference_power";
end
end

function p = localMeanSamplePower(x)
p = NaN;
if isempty(x)
    return;
end
p = mean(abs(double(x(:))).^2, "omitnan");
end

function nVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, snr_dB)
nVar = NaN;
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB))
    return;
end
if isempty(referenceWaveform)
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
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
if ~(isfinite(servingRxPower_dBm) && isfinite(thermalNoisePower_dBm))
    return;
end
referencePower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(referencePower) && referencePower > 0)
    return;
end
signalMilliwatt = 10.^(servingRxPower_dBm / 10);
noiseMilliwatt = 10.^(thermalNoisePower_dBm / 10);
if ~(isfinite(signalMilliwatt) && signalMilliwatt > 0 && isfinite(noiseMilliwatt) && noiseMilliwatt >= 0)
    return;
end
nVar = referencePower * (noiseMilliwatt / signalMilliwatt);
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
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
if isempty(fs) || ~isfinite(double(fs)) || double(fs) <= 0
    fs = 30.72e6;
else
    fs = double(fs);
end
end

function numRx = localResolveULNumRxAnt(cfg, fallback)
candidates = [ ...
    sixgr.util.structGet(cfg, "channel.nRxAnt", NaN), ...
    sixgr.util.structGet(cfg, "phy.nRxAnt", NaN)];
candidates = double(candidates(:));
candidates = candidates(isfinite(candidates) & candidates >= 1);
if isempty(candidates)
    numRx = max(1, round(double(fallback)));
else
    numRx = max(1, round(candidates(1)));
end
end

function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, sampleRateHz)
padSamples = 0;
trimSamples = 0;
if isempty(chObj)
    return;
end
filterDelay = double(sixgr.util.structGet(chObj, "ChannelFilterDelay", sixgr.util.structGet(chObj, "FilterDelay", 0)));
maxPathDelay = 0;
pathDelays = sixgr.util.structGet(chObj, "PathDelays", []);
if ~isempty(pathDelays)
    pathDelays = double(pathDelays(:));
    pathDelays = pathDelays(isfinite(pathDelays) & pathDelays >= 0);
    if ~isempty(pathDelays)
        maxPathDelay = max(pathDelays) * max(double(sampleRateHz), 0);
    end
end
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function [bitErrors, bitsCompared] = localBitErrors(expectedBits, decodedBits)
expectedBits = int8(expectedBits(:));
decodedBits = int8(decodedBits(:));
bitsCompared = min(numel(expectedBits), numel(decodedBits));
if bitsCompared < 1
    bitErrors = numel(expectedBits);
    bitsCompared = numel(expectedBits);
    return;
end
bitErrors = sum(expectedBits(1:bitsCompared) ~= decodedBits(1:bitsCompared));
bitErrors = bitErrors + abs(numel(expectedBits) - numel(decodedBits));
bitsCompared = max(bitsCompared, numel(expectedBits));
end

function metric = localResolveDetectionMetric(rx)
metric = NaN;
detMetric = sixgr.util.structGet(rx, "DetMetric", []);
if isempty(detMetric)
    return;
end
if isnumeric(detMetric) && ~isempty(detMetric)
    vals = double(detMetric(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        metric = mean(vals, "omitnan");
    end
end
end

function metrics = localMeasurePUCCHLinkState(cfg, rx, rxInfo)
metrics = struct();
Hest = sixgr.util.structGet(rx, "ChannelEstimate", []);
rxGrid = sixgr.util.structGet(rxInfo, "RxGrid", []);
pilotInd = sixgr.util.structGet(rxInfo, "DMRSIndices", []);
pilotSym = sixgr.util.structGet(rxInfo, "DMRSSymbols", []);
if isempty(Hest) || isempty(rxGrid) || isempty(pilotInd) || isempty(pilotSym)
    return;
end
try
    metrics = sixgr.phy.ul.measureULLinkState(Hest, ...
        double(sixgr.util.structGet(rx, "NoiseVar", NaN)), ...
        cfg, ...
        "ReceivedGrid", rxGrid, ...
        "ReferenceIndices", pilotInd, ...
        "ReferenceSymbols", pilotSym);
catch
    metrics = struct();
end
end

function value = localFirstLogical(vals, defaultValue)
if nargin < 2
    defaultValue = false;
end
if isempty(vals)
    value = logical(defaultValue);
else
    value = logical(vals(1));
end
end

function bits = localNormalizeUCIBits(rawBits)
bits = int8([]);
if isempty(rawBits)
    return;
end
if iscell(rawBits)
    if isempty(rawBits)
        return;
    end
    rawBits = rawBits{1};
end
if islogical(rawBits)
    bits = int8(rawBits(:));
elseif isnumeric(rawBits)
    bits = int8(logical(rawBits(:)));
end
end

function status = ternaryStatus(ok)
if ok
    status = "PASS";
else
    status = "FAIL";
end
end

function ttiMs = localAirInterfaceTTI(tx, txInfo)
sampleRate = sixgr.util.structGet(txInfo, "OFDM.SampleRate", NaN);
waveformLength = NaN;
if nargin >= 1 && isstruct(tx)
    txWave = sixgr.util.structGet(tx, "Waveform", []);
    if ~isempty(txWave)
        waveformLength = double(size(txWave, 1));
    end
end
ttiMs = NaN;
if isfinite(double(sampleRate)) && double(sampleRate) > 0 && isfinite(waveformLength) && waveformLength > 0
    ttiMs = 1e3 * waveformLength / double(sampleRate);
end
end

function model = localResolveTrialChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
if strlength(model) == 0 || model == "NONE" || model == "OFF"
    model = "AWGN";
    return;
end
if model == "TDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
elseif model == "CDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
end
end

function dopp = localResolveDopplerHz(cfg)
dopp = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", ...
    sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", NaN))));
if ~isfinite(dopp)
    dopp = NaN;
end
end
