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
parse(p, cfg, varargin{:});
opt = p.Results;

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
    "BitsCompared", 0, ...
    "BitErrors", NaN, ...
    "DetectionMetric", NaN, ...
    "ComputeLatency_ms", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "AirInterfaceTTI_ms", NaN, ...
    "NoiseVariance", NaN, ...
    "ConfiguredSNR_dB", double(opt.SNR_dB), ...
    "AppliedAWGNSNR_dB", NaN, ...
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
    chState = localInitULChannelState(cfgResolved, tx, txInfo);
    [rxWave, replay] = localApplyULChannelAndNoise(tx.Waveform, double(opt.SNR_dB), chState, cfgResolved, tx, txInfo, opt.InterferenceBundle);

    tDecode = tic;
    [rx, rxInfo] = sixgr.phy.ul.PUCCH_Rx(rxWave, cfgResolved, ...
        "Carrier", tx.Carrier, ...
        "PUCCH", tx.PUCCH, ...
        "Format", resolvedFormat, ...
        "NumUCIBits", numel(expectedBits), ...
        "ExpectedUCIBits", expectedBits, ...
        "NoiseVar", sixgr.util.structGet(replay, "InjectedNoiseVariance", []));
    decodeLatency_ms = toc(tDecode) * 1e3;

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
    out.BitsCompared = double(bitsCompared);
    out.BitErrors = double(bitErrors);
    out.DetectionMetric = double(detMetric);
    out.ComputeLatency_ms = double(decodeLatency_ms);
    out.DecodeLatency_ms = double(decodeLatency_ms);
    out.AirInterfaceTTI_ms = localAirInterfaceTTI(tx, txInfo);
    out.NoiseVariance = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
    out.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", opt.SNR_dB));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
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

function state = localInitULChannelState(cfg, tx, txInfo)
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0);

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
    "Seed", sixgr.util.structGet(cfg, "run.seed", 1));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
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
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "InterferenceMode", "none", ...
    "InterferenceContributorCount", 0, ...
    "InterferenceAggregatedRxPower_dBm", NaN, ...
    "InterferencePowerSource", "", ...
    "FullInterfererChannelTruthUsed", false);

if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
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

sampleRateHz = localResolveSampleRate(tx, txInfo);
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfg, sampleRateHz);
impairFields = fieldnames(impairmentReplay);
for fi = 1:numel(impairFields)
    replay.(impairFields{fi}) = impairmentReplay.(impairFields{fi});
end
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
desiredWaveform = y;
[interferenceWaveform, interferenceMeta] = sixgr.link.synthesizeInterferenceWaveform("UL", desiredWaveform, replay, interferenceBundle);
if ~isempty(interferenceWaveform)
    y = y + cast(interferenceWaveform, "like", y);
end
replay.InterferenceMode = char(string(sixgr.util.structGet(interferenceMeta, "InterferenceMode", replay.InterferenceMode)));
replay.InterferenceContributorCount = double(sixgr.util.structGet(interferenceMeta, "Contributors", 0));
replay.InterferenceAggregatedRxPower_dBm = double(sixgr.util.structGet(interferenceMeta, "AggregatedRxPower_dBm", NaN));
replay.InterferencePowerSource = char(string(sixgr.util.structGet(interferenceMeta, "PowerSource", "")));
replay.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet(interferenceMeta, "FullPerLinkChannelTruthUsed", false));
if strlength(strtrim(string(replay.InterferencePowerSource))) == 0 && replay.InterferenceContributorCount > 0
    replay.InterferencePowerSource = "sample_domain_interference_sum";
end
[y, replay.InjectedNoiseVariance] = localAddAwgn(y, replay, desiredWaveform);
end

function [y, nVar] = localAddAwgn(x, replay, referenceWaveform)
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "configured_snr_anchor_after_large_scale_gain"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localResolveThermalNoiseVariance(replay, referenceWaveform);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
end
[y, nVar] = sixgr.util.addAwgnComplex(x, double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN)));
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
