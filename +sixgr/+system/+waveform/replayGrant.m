function replay = replayGrant(cfgIn, direction, grant, payloadIn, snr_dB, varargin)
%REPLAYGRANT Replay one system grant through waveform PHY TX/channel/RX.

ip = inputParser;
ip.addParameter("InputFormat", "bits", @(x)ischar(x)||isstring(x));
ip.addParameter("StrictMode", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("CompactPHYIO", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("FastAWGNPath", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("AdaptiveLDPC", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("LDPCMaxIterations", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("UseGPU", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

if nargin < 4
    payloadIn = [];
end

dir = upper(string(direction));
replay = struct( ...
    "Ok", false, ...
    "BLER", 1.0, ...
    "Notes", "", ...
    "UsedFading", false, ...
    "FastAWGNPath", false, ...
    "ChannelModel", localResolveChannelToken(cfgIn), ...
    "ExecutionBackend", "WAVEFORM_GRANT_REPLAY", ...
    "PHYMode", "CRC_WAVEFORM_REPLAY", ...
    "TransportBlockSize", NaN, ...
    "CRCPass", NaN, ...
    "CRCError", NaN, ...
    "BitErrors", NaN, ...
    "BitsCompared", NaN, ...
    "RawBER", NaN, ...
    "DecoderIterations", NaN, ...
    "EffectiveTxAntennas", NaN, ...
    "EffectiveRxAntennas", NaN, ...
    "ReceiverHestSINR_dB", NaN, ...
    "ReceiverHestSINRSource", "unavailable_waveform_replay_not_executed", ...
    "ReceiverHestSINRValueRole", "unavailable", ...
    "ReceiverHestSINRValueStatus", "unavailable", ...
    "ReceiverHestSINRNAReason", "waveform_replay_not_executed", ...
    "PostEqSINR_dB", NaN, ...
    "PostEqSINRSource", "unavailable_waveform_replay_not_executed", ...
    "PostEqSINRValueRole", "unavailable", ...
    "PostEqSINRValueStatus", "unavailable", ...
    "PostEqSINRNAReason", "waveform_replay_not_executed", ...
    "PostEqSINRPerLayer_dB", NaN, ...
    "TimingEstimateUsed", false, ...
    "RawTimingEstimate_samples", NaN, ...
    "AppliedTimingCorrection_samples", NaN, ...
    "TimingEstimateApplicationPolicy", "unavailable", ...
    "TimingEstimateStatus", "missing", ...
    "TimingEstimateWasClipped", false, ...
    "TimingEstimateAvailability", "missing", ...
    "TimingErrorDefinition", "not_available_without_timing_estimate", ...
    "TimingValueStatus", "NOT_AVAILABLE", ...
    "InjectedCFO_Hz", NaN, ...
    "TrueCFO_Hz", NaN, ...
    "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "ResidualCFO_PostCorrection_Hz", NaN, ...
    "CFOError_Hz", NaN, ...
    "EstimatedCFO_Hz", NaN, ...
    "CFOEstimateAvailable", false, ...
    "CFOEstimateAvailability", "missing", ...
    "ReceiverTrackingCorrectionSource", "", ...
    "ReceiverTrackingCorrectionStatus", "", ...
    "ReceiverTrackingCorrectionNAReason", "", ...
    "CFOErrorDefinition", "not_available_without_cfo_estimate", ...
    "CFOValueStatus", "NOT_AVAILABLE", ...
    "InjectedTimingOffset_samples", NaN, ...
    "TrueTimingOffset_samples", NaN, ...
    "EstimatedTimingOffset_PreCorrection_samples", NaN, ...
    "TimingError_samples", NaN, ...
    "AppliedPathloss_dB", NaN, ...
    "AppliedShadowFading_dB", NaN, ...
    "AppliedLargeScaleGain_dB", NaN, ...
    "AppliedO2I_dB", NaN, ...
    "ServingRxPower_dBm", NaN, ...
    "ThermalNoisePower_dBm", NaN, ...
    "NoisePowerSource", "unavailable", ...
    "PhaseNoiseConfigured", false, ...
    "PhaseNoiseApplied", false, ...
    "PhaseNoiseRMS_rad", NaN, ...
    "IQImbalanceConfigured", false, ...
    "IQImbalanceApplied", false, ...
    "IQImbalanceImageRejection_dB", NaN, ...
    "IQImbalanceMeasurementStatus", "not_measured", ...
    "ChannelEstimateAvailable", false, ...
    "EqualizationAvailable", false, ...
    "DecodeAttempted", false, ...
    "DecodeAvailable", false, ...
    "LLRAvailable", false, ...
    "LLRFinite", false, ...
    "DecoderTruthProxySINR_dB", NaN, ...
    "DecoderTruthProxySINRSource", "unavailable_equalizer_evm_not_computed", ...
    "DecoderTruthProxySINRValueRole", "unavailable", ...
    "DecoderTruthProxySINRValueStatus", "unavailable", ...
    "DecoderTruthProxySINRNAReason", "waveform_replay_not_executed", ...
    "PrecoderSource", "unavailable_waveform_replay_not_executed", ...
    "RequestedPrecoderSource", "unavailable_waveform_replay_not_executed", ...
    "AppliedPrecoderSource", "unavailable_waveform_replay_not_executed", ...
    "RequestedPrecoderPMI", NaN, ...
    "PrecodingMode", "unavailable", ...
    "PrecodingApplicationStage", "unavailable", ...
    "PrecodingActive", false, ...
    "ExplicitBeamWeightsApplied", false, ...
    "TransformPrecodingApplied", false, ...
    "BeamformingApplied", false, ...
    "AppliedBeamIndexSet", "", ...
    "AppliedPrecoderPMI", NaN, ...
    "AppliedPrecoderValueRole", "unavailable", ...
    "AppliedPrecoderValueStatus", "unavailable", ...
    "AppliedPrecoderNAReason", "waveform_replay_not_executed", ...
    "ExplicitPrecoderReplayStatus", "not_materialized", ...
    "ExplicitPrecoderReplayBlocker", "waveform_replay_not_executed", ...
    "AppliedPrecoderPMIType", "", ...
    "AppliedPrecoderCodebookMode", "", ...
    "PrecodingNumPorts", NaN, ...
    "PrecodingNumLayers", NaN, ...
    "PrecodingMatrixRows", NaN, ...
    "PrecodingMatrixCols", NaN);

try
    cfgReplay = localBuildReplayConfig(cfgIn, dir, grant);
    replay.ChannelModel = localResolveChannelToken(cfgReplay);
    replay.EffectiveTxAntennas = double(sixgr.util.structGet(cfgReplay, "channel.nTxAnt", NaN));
    replay.EffectiveRxAntennas = double(sixgr.util.structGet(cfgReplay, "channel.nRxAnt", NaN));

    if dir == "UL"
        tmpl = localResolveReplayTemplate(cfgReplay, "UL", grant, isempty(payloadIn));
        [tx, txInfo, txTemplateReused] = localResolveReplayTx(cfgReplay, "UL", tmpl, payloadIn, opt);
        replay.TransportBlockSize = double(tx.TransportBlockSize);
        chState = localInitChannelState(cfgReplay, tx, txInfo);
        [rxWave, nVar, chState] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);
        fastAWGNPath = logical(opt.FastAWGNPath) && localAllowsFastAWGN(cfgReplay, grant, chState);
        [rx, rxInfo] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgReplay, ...
            "Carrier", tx.Carrier, ...
            "PUSCH", tx.PUSCH, ...
            "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "NoiseVar", nVar, ...
            "NoiseVarDomain", "time", ...
            "MaxIterations", localLDPCMaxIterations(snr_dB, cfgReplay, opt), ...
            "CompactOutput", logical(opt.CompactPHYIO), ...
            "FastAWGNPath", fastAWGNPath, ...
            "SkipTimingEstimate", localShouldSkipTimingEstimate(cfgReplay));
    else
        tmpl = localResolveReplayTemplate(cfgReplay, "DL", grant, isempty(payloadIn));
        [tx, txInfo, txTemplateReused] = localResolveReplayTx(cfgReplay, "DL", tmpl, payloadIn, opt);
        replay.TransportBlockSize = double(tx.TransportBlockSize);
        chState = localInitChannelState(cfgReplay, tx, txInfo);
        [rxWave, nVar, chState] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);
        fastAWGNPath = logical(opt.FastAWGNPath) && localAllowsFastAWGN(cfgReplay, grant, chState);
        [rx, rxInfo] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgReplay, ...
            "Carrier", tx.Carrier, ...
            "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "NoiseVar", nVar, ...
            "NoiseVarDomain", "time", ...
            "MaxIterations", localLDPCMaxIterations(snr_dB, cfgReplay, opt), ...
            "CompactOutput", logical(opt.CompactPHYIO), ...
            "FastAWGNPath", fastAWGNPath, ...
            "SkipTimingEstimate", localShouldSkipTimingEstimate(cfgReplay));
    end

    [crcKnown, crcPass] = localMeasuredCRCPass(rx);
    replay.Ok = logical(crcKnown && crcPass);
    replay.CRCPass = localMeasuredCRCValue(crcKnown, crcPass);
    replay.CRCError = localMeasuredCRCValue(crcKnown, ~crcPass);
    replay.BLER = localBLERFromMeasuredCRC(crcKnown, crcPass);
    replay.UsedFading = logical(sixgr.util.structGet(chState, "UseFading", false));
    replay.FastAWGNPath = logical(fastAWGNPath);
    replay.WaveformReplayReused = logical(txTemplateReused);
    replay = localAttachWaveformEvidence(replay, dir, tx, txInfo, rx, rxInfo);
    replay = localAttachImpairmentEvidence(replay, chState);
    replay.DecoderIterations = double(sixgr.util.structGet(rx, "DecoderIterations", NaN));
    if ~isfinite(replay.DecoderIterations) && isfield(rx, "ActiveIterations") && ~isempty(rx.ActiveIterations)
        replay.DecoderIterations = mean(double(rx.ActiveIterations(:)), "omitnan");
    end

    grantBits = double(sixgr.util.structGet(grant, "TBSBits", NaN));
    if isfinite(grantBits) && grantBits > 0 && isfinite(replay.TransportBlockSize) && ...
            round(grantBits) ~= round(replay.TransportBlockSize)
        msg = "Grant TBSBits=" + string(round(grantBits)) + ...
            " differs from waveform replay transport block size=" + string(round(replay.TransportBlockSize));
        if logical(opt.StrictMode)
            error("sixgr:system:WaveformReplay:TBSMismatch", "%s", char(msg));
        end
        replay.Notes = msg;
    end
    replay.PHYDecisionRole = "measured";
    replay.PHYDecisionStatus = "OK";
    replay.PHYDecisionSource = "sixgr.system.waveform.replayGrant";
    replay.PHYDecisionReason = "waveform_replay_executed";
    replay.WaveformReplayExecuted = true;
    replay.WaveformReplayReused = logical(sixgr.util.structGet(replay, "WaveformReplayReused", false));
catch ME
    if strcmp(string(ME.identifier), "sixgr:system:WaveformReplay:MissingExactNRE")
        replay = localMarkReplayUnavailable(replay, ...
            "waveform_replay_no_exact_data_re_budget", ...
            "waveform_replay_failed: " + string(ME.message));
        return;
    end
    if logical(opt.StrictMode)
        rethrow(ME);
    end
    replay = localMarkReplayUnavailable(replay, ...
        "waveform_replay_failed", ...
        "waveform_replay_failed: " + string(ME.message));
end
end

function replay = localMarkReplayUnavailable(replay, reason, note)
replay.Ok = false;
replay.BLER = NaN;
replay.Notes = string(note);
replay.PHYDecisionRole = "unavailable";
replay.PHYDecisionStatus = "NOT_AVAILABLE";
replay.PHYDecisionSource = "sixgr.system.waveform.replayGrant";
replay.PHYDecisionReason = string(reason);
replay.WaveformReplayExecuted = false;
replay.WaveformReplayReused = false;
end

function [known, pass] = localMeasuredCRCPass(rx)
known = false;
pass = false;
if isstruct(rx) && isfield(rx, "CRCError")
    crcErr = rx.CRCError;
    if (islogical(crcErr) || isnumeric(crcErr)) && isscalar(crcErr)
        known = true;
        pass = ~logical(crcErr);
        return;
    end
end
if isstruct(rx) && isfield(rx, "CRCPass")
    crcPass = rx.CRCPass;
    if (islogical(crcPass) || isnumeric(crcPass)) && isscalar(crcPass)
        known = true;
        pass = logical(crcPass);
    end
end
end

function bler = localBLERFromMeasuredCRC(known, pass)
if ~logical(known)
    bler = NaN;
else
    bler = double(~logical(pass));
end
end

function value = localMeasuredCRCValue(known, tf)
if ~logical(known)
    value = NaN;
else
    value = double(logical(tf));
end
end

function [bitErrors, bitsCompared, rawBER] = localMeasuredTransportBlockBER(tx, rx)
bitErrors = NaN;
bitsCompared = NaN;
rawBER = NaN;
txBits = sixgr.util.structGet(tx, "TransportBlock", []);
rxBits = sixgr.util.structGet(rx, "TransportBlock", []);
if isempty(txBits) || isempty(rxBits)
    return;
end
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
bitsCompared = double(max(numel(txBits), numel(rxBits)));
if ~(isfinite(bitsCompared) && bitsCompared > 0)
    bitsCompared = NaN;
    return;
end
commonBits = min(numel(txBits), numel(rxBits));
bitErrors = double(sum(txBits(1:commonBits) ~= rxBits(1:commonBits))) + ...
    abs(double(numel(txBits)) - double(numel(rxBits)));
rawBER = bitErrors / bitsCompared;
end

function tf = localShouldSkipTimingEstimate(cfg)
tf = logical(sixgr.util.structGet(cfg, "phy.rx.useIdealTimingSync", false));
end

function [tx, txInfo, reused] = localResolveReplayTx(cfgReplay, dir, tmpl, payloadIn, opt)
reused = false;

if ~isempty(payloadIn)
    tbBits = localNormalizeTransportBits(payloadIn, double(tmpl.TransportBlockSize), opt.InputFormat);
    [tx, txInfo] = localBuildReplayTx(cfgReplay, dir, tmpl, tbBits, opt);
    return;
end

tmpl = localNormalizePayloadlessReplayTemplate(dir, tmpl);
tbBits = localPayloadlessTransportBits(double(tmpl.TransportBlockSize));
cacheKey = localReplayTxCacheKey(dir, tmpl);
[hit, cached] = localReplayTxTemplateCache("get", cacheKey);
if hit
    tx = cached.Tx;
    txInfo = cached.Info;
    reused = true;
    return;
end

[tx, txInfo] = localBuildReplayTx(cfgReplay, dir, tmpl, tbBits, opt);
localReplayTxTemplateCache("set", cacheKey, struct("Tx", tx, "Info", txInfo));
end

function tmpl = localResolveReplayTemplate(cfgReplay, dir, grant, allowCache)
if nargin < 4
    allowCache = false;
end

if allowCache
    cacheKey = localReplayTemplateCacheKey(cfgReplay, dir, grant);
    [hit, cached] = localReplayGrantTemplateCache("get", cacheKey);
    if hit
        tmpl = cached;
        return;
    end
end

if strcmpi(char(string(dir)), "UL")
    [tmpl, ~] = localBuildGrantAlignedPUSCHTx(cfgReplay, grant);
else
    [tmpl, ~] = localBuildGrantAlignedPDSCHTx(cfgReplay, grant);
end

if allowCache
    localReplayGrantTemplateCache("set", cacheKey, tmpl);
end
end

function tmpl = localNormalizePayloadlessReplayTemplate(dir, tmpl)
fieldName = "PDSCH";
if strcmpi(char(string(dir)), "UL")
    fieldName = "PUSCH";
end
if ~isfield(tmpl, fieldName)
    return;
end
channelCfg = tmpl.(fieldName);
channelCfg = localNormalizePayloadlessChannelIdentity(channelCfg);
tmpl.(fieldName) = channelCfg;
end

function channelCfg = localNormalizePayloadlessChannelIdentity(channelCfg)
if isempty(channelCfg) || ~isobject(channelCfg)
    return;
end
identityFields = {
    "RNTI", 1; ...
    "NID", 1; ...
    "NIDNSCID", 1; ...
    "NSCID", 0; ...
    "NRSID", 1; ...
    "DMRSNID", 1 ...
    };
for i = 1:size(identityFields, 1)
    name = char(identityFields{i, 1});
    value = identityFields{i, 2};
    if isprop(channelCfg, name)
        try
            channelCfg.(name) = value;
        catch
            % Keep runtime object value if the property is read-only in this release.
        end
    end
end
end

function [tx, txInfo] = localBuildReplayTx(cfgReplay, dir, tmpl, tbBits, opt)
if dir == "UL"
    [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfgReplay, ...
        "Carrier", tmpl.Carrier, ...
        "PUSCH", tmpl.PUSCH, ...
        "TransportBlockBits", tbBits, ...
        "RV", tmpl.RV, ...
        "TargetCodeRate", tmpl.TargetCodeRate, ...
        "XOverhead", double(sixgr.util.structGet(tmpl, "XOverhead", ...
            sixgr.util.structGet(cfgReplay, "phy.pusch.xOverhead", 0))), ...
        "CompactOutput", logical(opt.CompactPHYIO));
else
    [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfgReplay, ...
        "Carrier", tmpl.Carrier, ...
        "PDSCH", tmpl.PDSCH, ...
        "TransportBlockBits", tbBits, ...
        "RV", tmpl.RV, ...
        "TargetCodeRate", tmpl.TargetCodeRate, ...
        "XOverhead", double(sixgr.util.structGet(tmpl, "XOverhead", ...
            sixgr.phy.dl.resolvePDSCHXOverhead(cfgReplay, localObjectValue(tmpl.PDSCH, "SymbolAllocation", [0 14])))), ...
        "CompactOutput", logical(opt.CompactPHYIO));
end
end

function bits = localPayloadlessTransportBits(expectedBits)
expectedBits = max(0, round(double(expectedBits)));
bits = int8(zeros(expectedBits, 1));
end

function replay = localAttachWaveformEvidence(replay, dir, tx, txInfo, rx, rxInfo)
replay.ReceiverHestSINR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
replay.ReceiverHestSINRSource = string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", "unavailable_receiver_hest_reference_measurement"));
replay.ReceiverHestSINRValueRole = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueRole", "unavailable"));
replay.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueStatus", "unavailable"));
replay.ReceiverHestSINRNAReason = string(sixgr.util.structGet(rx, "ReceiverHestSINRNAReason", "receiver_hest_sinr_not_exported_by_replay_rx"));
replay.PostEqSINR_dB = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
replay.PostEqSINRSource = string(sixgr.util.structGet(rx, "PostEqSINRSource", "post_equalization_sinr_from_equalizer_channel_estimate"));
replay.PostEqSINRValueRole = string(sixgr.util.structGet(rx, "PostEqSINRValueRole", "measured_post_equalization_scheduling_input"));
replay.PostEqSINRValueStatus = string(sixgr.util.structGet(rx, "PostEqSINRValueStatus", localValueStatus(replay.PostEqSINR_dB)));
replay.PostEqSINRNAReason = string(sixgr.util.structGet(rx, "PostEqSINRNAReason", ""));
replay.PostEqSINRPerLayer_dB = sixgr.util.structGet(rx, "PostEqSINRPerLayer_dB", NaN);
replay.TimingEstimateUsed = logical(sixgr.util.structGet(rx, "TimingEstimateUsed", false));
replay.RawTimingEstimate_samples = double(sixgr.util.structGet(rx, "RawTimingEstimate_samples", ...
    sixgr.util.structGet(rx, "TimingOffset", NaN)));
replay.AppliedTimingCorrection_samples = double(sixgr.util.structGet(rx, "AppliedTimingCorrection_samples", NaN));
replay.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(rx, "TimingEstimateApplicationPolicy", ""));
replay.TimingEstimateStatus = string(sixgr.util.structGet(rx, "TimingEstimateStatus", localTimingStatus(replay.TimingEstimateUsed)));
replay.TimingEstimateWasClipped = logical(sixgr.util.structGet(rx, "TimingEstimateWasClipped", false));
replay.TimingEstimateAvailability = localAvailability(replay.TimingEstimateUsed);
replay.TimingErrorDefinition = localTimingErrorDefinition(replay.TimingEstimateUsed);
replay.TimingValueStatus = "NOT_AVAILABLE";
replay.EstimatedCFO_Hz = double(sixgr.util.structGet(rx, "EstimatedCFO_Hz", NaN));
replay.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(rx, "EstimatedCFO_PreCorrection_Hz", replay.EstimatedCFO_Hz));
replay.CFOEstimateAvailable = logical(sixgr.util.structGet(rx, "CFOEstimateAvailable", isfinite(replay.EstimatedCFO_Hz)));
replay.CFOEstimateAvailability = localAvailability(replay.CFOEstimateAvailable);
replay.ReceiverTrackingCorrectionSource = string(sixgr.util.structGet(rx, "ReceiverTrackingCorrectionSource", ""));
replay.ReceiverTrackingCorrectionStatus = string(sixgr.util.structGet(rx, "ReceiverTrackingCorrectionStatus", ""));
replay.ReceiverTrackingCorrectionNAReason = string(sixgr.util.structGet(rx, "ReceiverTrackingCorrectionNAReason", ""));
replay.CFOErrorDefinition = localCFOErrorDefinition(replay.CFOEstimateAvailable);
replay.CFOValueStatus = localValueStatus(replay.EstimatedCFO_Hz);
replay.ChannelEstimateAvailable = logical(sixgr.util.structGet(rx, "ChannelEstimateAvailable", false));
replay.EqualizationAvailable = logical(sixgr.util.structGet(rx, "EqualizationAvailable", false));
replay.DecodeAttempted = logical(sixgr.util.structGet(rx, "DecodeAttempted", false));
if dir == "UL"
    replay.DecodeAvailable = logical(sixgr.util.structGet(rx, "ULSCHDecodeAvailable", false));
else
    replay.DecodeAvailable = logical(sixgr.util.structGet(rx, "DLSCHDecodeAvailable", false));
end
replay.LLRAvailable = logical(sixgr.util.structGet(rx, "LLRAvailable", false));
replay.LLRFinite = logical(sixgr.util.structGet(rx, "LLRFinite", false));
[bitErrors, bitsCompared, rawBER] = localMeasuredTransportBlockBER(tx, rx);
replay.BitErrors = double(bitErrors);
replay.BitsCompared = double(bitsCompared);
replay.RawBER = double(rawBER);

[decoderSINR, decoderMeta] = localDecoderTruthProxySINR(tx, rx, dir);
replay.DecoderTruthProxySINR_dB = double(decoderSINR);
replay.DecoderTruthProxySINRSource = string(sixgr.util.structGet(decoderMeta, "Source", "unavailable_equalizer_evm_not_computed"));
replay.DecoderTruthProxySINRValueRole = string(sixgr.util.structGet(decoderMeta, "ValueRole", "unavailable"));
replay.DecoderTruthProxySINRValueStatus = string(sixgr.util.structGet(decoderMeta, "ValueStatus", "unavailable"));
replay.DecoderTruthProxySINRNAReason = string(sixgr.util.structGet(decoderMeta, "NAReason", "equalizer_evm_metric_unavailable"));

prec = sixgr.util.structGet(txInfo, "Precoding", struct());
if ~(isstruct(prec) && ~isempty(fieldnames(prec)))
    prec = sixgr.util.structGet(rxInfo, "Precoding", struct());
end
if ~(isstruct(prec) && ~isempty(fieldnames(prec)))
    prec = sixgr.util.structGet(tx, "PrecodeInfo", struct());
end
if ~(isstruct(prec) && ~isempty(fieldnames(prec)))
    replay.ExplicitPrecoderReplayStatus = "not_materialized";
    replay.ExplicitPrecoderReplayBlocker = "waveform_replay_precoder_metadata_missing";
    return;
end

precSource = string(sixgr.util.structGet(prec, "Source", ""));
if strlength(strtrim(precSource)) == 0 || strcmpi(char(precSource), "none")
    precSource = "waveform_replay_direct_mapping_no_explicit_beam_weights";
end
precMode = string(sixgr.util.structGet(prec, "Mode", "runtime_precoding_state"));
replay.PrecoderSource = precSource;
replay.RequestedPrecoderSource = precSource;
replay.AppliedPrecoderSource = precSource;
replay.RequestedPrecoderPMI = double(sixgr.util.structGet(prec, "PMI", NaN));
replay.PrecodingMode = precMode;
replay.PrecodingApplicationStage = string(sixgr.util.structGet(prec, "ApplicationStage", "waveform_replay_runtime"));
replay.PrecodingActive = logical(sixgr.util.structGet(prec, "Active", false));
replay.ExplicitBeamWeightsApplied = logical(sixgr.util.structGet(prec, "ExplicitBeamWeightsApplied", ...
    replay.PrecodingActive && dir == "DL" && contains(lower(precMode), "explicit")));
replay.TransformPrecodingApplied = logical(sixgr.util.structGet(prec, "TransformPrecodingApplied", ...
    contains(lower(precMode), "transform")));
replay.BeamformingApplied = logical(sixgr.util.structGet(prec, "BeamformingApplied", replay.PrecodingActive));
replay.AppliedBeamIndexSet = localNumericSetToken(sixgr.util.structGet(prec, "BeamIndices", []));
replay.AppliedPrecoderPMI = double(sixgr.util.structGet(prec, "PMI", NaN));
replay.AppliedPrecoderValueRole = "applied";
replay.AppliedPrecoderValueStatus = "OK";
replay.AppliedPrecoderNAReason = "";
replay.ExplicitPrecoderReplayStatus = "materialized";
replay.ExplicitPrecoderReplayBlocker = "";
replay.AppliedPrecoderPMIType = string(sixgr.util.structGet(prec, "PMIType", ""));
replay.AppliedPrecoderCodebookMode = string(sixgr.util.structGet(prec, "CodebookMode", ""));
replay.PrecodingNumPorts = double(sixgr.util.structGet(prec, "NumPorts", NaN));
replay.PrecodingNumLayers = double(sixgr.util.structGet(prec, "NumLayers", NaN));
replay.PrecodingMatrixRows = double(sixgr.util.structGet(prec, "MatrixRows", NaN));
replay.PrecodingMatrixCols = double(sixgr.util.structGet(prec, "MatrixCols", NaN));
end

function replay = localAttachImpairmentEvidence(replay, chState)
imp = struct();
if isstruct(chState)
    imp = sixgr.util.structGet(chState, "ImpairmentReplay", struct());
end
if ~(isstruct(imp) && ~isempty(fieldnames(imp)))
    return;
end

replay.InjectedCFO_Hz = double(sixgr.util.structGet(imp, "InjectedCFO_Hz", NaN));
replay.TrueCFO_Hz = replay.InjectedCFO_Hz;
replay.InjectedTimingOffset_samples = double(sixgr.util.structGet(imp, "InjectedTimingOffset_samples", NaN));
replay.TrueTimingOffset_samples = replay.InjectedTimingOffset_samples;
replay.EstimatedTimingOffset_PreCorrection_samples = replay.RawTimingEstimate_samples;
if isfinite(replay.TrueTimingOffset_samples) && isfinite(replay.EstimatedTimingOffset_PreCorrection_samples)
    replay.TimingError_samples = replay.TrueTimingOffset_samples - replay.EstimatedTimingOffset_PreCorrection_samples;
end
if isfinite(replay.TrueCFO_Hz) && isfinite(replay.EstimatedCFO_PreCorrection_Hz)
    replay.CFOError_Hz = replay.TrueCFO_Hz - replay.EstimatedCFO_PreCorrection_Hz;
    replay.ResidualCFO_PostCorrection_Hz = replay.CFOError_Hz;
end

replay.AppliedPathloss_dB = double(sixgr.util.structGet(imp, "AppliedPathloss_dB", NaN));
replay.AppliedShadowFading_dB = double(sixgr.util.structGet(imp, "AppliedShadowFading_dB", NaN));
replay.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(imp, "AppliedLargeScaleGain_dB", NaN));
replay.AppliedO2I_dB = double(sixgr.util.structGet(imp, "AppliedO2I_dB", NaN));
replay.ServingRxPower_dBm = double(sixgr.util.structGet(imp, "ServingRxPower_dBm", NaN));
replay.ThermalNoisePower_dBm = double(sixgr.util.structGet(imp, "ThermalNoisePower_dBm", NaN));
replay.NoisePowerSource = string(sixgr.util.structGet(imp, "NoisePowerSource", ""));

replay.PhaseNoiseConfigured = logical(sixgr.util.structGet(imp, "PhaseNoiseConfigured", false));
replay.PhaseNoiseApplied = logical(sixgr.util.structGet(imp, "PhaseNoiseApplied", false));
replay.PhaseNoiseRMS_rad = double(sixgr.util.structGet(imp, "PhaseNoiseRMS_rad", NaN));
replay.IQImbalanceConfigured = logical(sixgr.util.structGet(imp, "IQImbalanceConfigured", false));
replay.IQImbalanceApplied = logical(sixgr.util.structGet(imp, "IQImbalanceApplied", false));
replay.IQImbalanceImageRejection_dB = double(sixgr.util.structGet(imp, "IQImbalanceImageRejection_dB", NaN));
replay.IQImbalanceMeasurementStatus = string(sixgr.util.structGet(imp, "IQImbalanceMeasurementStatus", ""));
end

function value = localAvailability(tf)
if logical(tf)
    value = "available";
else
    value = "missing";
end
end

function value = localValueStatus(x)
if any(isfinite(double(x(:))))
    value = "OK";
else
    value = "NOT_AVAILABLE";
end
end

function value = localTimingStatus(timingUsed)
if logical(timingUsed)
    value = "available_applied_signed_correction";
else
    value = "missing";
end
end

function value = localTimingErrorDefinition(timingUsed)
if logical(timingUsed)
    value = "not_available_without_injected_timing_reference";
else
    value = "not_available_without_timing_estimate";
end
end

function value = localCFOErrorDefinition(cfoAvailable)
if logical(cfoAvailable)
    value = "estimated_cfo_hz_no_injected_cfo_reference_in_replay";
else
    value = "not_available_without_cfo_estimate";
end
end

function [sinr_dB, meta] = localDecoderTruthProxySINR(tx, rx, dir)
meta = struct( ...
    "Source", "unavailable_equalizer_evm_not_computed", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "equalized_or_reference_symbols_missing");
sinr_dB = NaN;
eqSym = localEvidenceSymbols(rx, "EqualizedSymbolsForEvidence", "EqualizedSymbols");
if dir == "UL"
    refSym = localEvidenceSymbols(tx, "PUSCHSymbolsForEvidence", "PUSCHSymbols");
else
    refSym = localEvidenceSymbols(tx, "PDSCHSymbolsForEvidence", "PDSCHSymbols");
end
if isempty(eqSym) || isempty(refSym)
    return;
end
L = min(numel(eqSym), numel(refSym));
if L <= 0
    return;
end
eqSym = double(eqSym(1:L));
refSym = double(refSym(1:L));
valid = isfinite(real(eqSym)) & isfinite(imag(eqSym)) & isfinite(real(refSym)) & isfinite(imag(refSym));
if ~any(valid)
    meta.NAReason = "equalized_or_reference_symbols_nonfinite";
    return;
end
err = eqSym(valid) - refSym(valid);
pRef = mean(abs(refSym(valid)).^2, "omitnan");
if ~(isfinite(pRef) && pRef > 0)
    meta.NAReason = "reference_symbol_power_unavailable";
    return;
end
evm = sqrt(mean(abs(err).^2, "omitnan") / max(pRef, eps));
[sinr_dB, meta] = sixgr.link.deriveDecoderTruthProxySINR(struct("EVM_rms", evm));
if ~isfinite(sinr_dB)
    meta.NAReason = "equalizer_evm_sinr_unavailable";
end
end

function values = localEvidenceSymbols(s, preferredName, legacyName)
values = sixgr.util.structGet(s, preferredName, []);
if isempty(values)
    values = sixgr.util.structGet(s, legacyName, []);
end
if iscell(values) && ~isempty(values)
    values = values{1};
end
values = values(:);
end

function token = localNumericSetToken(values)
if isempty(values)
    token = "";
    return;
end
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
parts = strings(numel(values), 1);
for i = 1:numel(values)
    if abs(values(i) - round(values(i))) < 1e-9
        parts(i) = string(round(values(i)));
    else
        parts(i) = string(values(i));
    end
end
token = strjoin(parts, "|");
end

function cfgOut = localBuildReplayConfig(cfgIn, dir, grant)
cfgOut = cfgIn;
cfgOut.phy.rx.useFastChannelEstMex = false;

numLayers = max(1, round(double(sixgr.util.structGet(grant, "NumLayers", 1))));
txAnt = localEffectiveTxAntennas(cfgIn, dir, numLayers);
rxAnt = localEffectiveRxAntennas(cfgIn, dir, numLayers);
cfgOut.phy.nTxAnt = txAnt;
cfgOut.phy.nRxAnt = rxAnt;
cfgOut.channel.nTxAnt = txAnt;
cfgOut.channel.nRxAnt = rxAnt;

if dir == "UL"
    cfgOut.phy.pusch.numLayers = numLayers;
    cfgOut.phy.pusch.nLayers = numLayers;
else
    cfgOut.phy.pdsch.numLayers = numLayers;
    cfgOut.phy.pdsch.nLayers = numLayers;
end

cfgOut = localAlignReplayCarrierToGrant(cfgOut, grant);

modelRaw = upper(string(sixgr.util.structGet(cfgOut, "channel.model", "AWGN")));
if startsWith(modelRaw, "TDL")
    cfgOut.channel.model = "TDL";
    if modelRaw ~= "TDL"
        cfgOut.channel.tdlProfile = char(modelRaw);
    end
elseif startsWith(modelRaw, "CDL")
    cfgOut.channel.model = "CDL";
    if modelRaw ~= "CDL"
        cfgOut.channel.cdlProfile = char(modelRaw);
    end
else
    cfgOut.channel.model = char(modelRaw);
end
end

function cfgOut = localAlignReplayCarrierToGrant(cfgOut, grant)
requiredNSizeGrid = NaN;
prbOffset = 0;
useGrantLocalGrid = logical(sixgr.util.structGet(cfgOut, "system.waveform.useGrantLocalGrid", false));

prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
if ~isempty(prbSet)
    prbSet = unique(prbSet(isfinite(prbSet) & prbSet >= 0));
    if ~isempty(prbSet)
        if useGrantLocalGrid
            prbOffset = min(prbSet);
            requiredNSizeGrid = max(prbSet) - prbOffset + 1;
        else
            requiredNSizeGrid = max(prbSet) + 1;
        end
    end
end

if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    nprb = double(sixgr.util.structGet(grant, "NPRB", NaN));
    if isfinite(nprb) && nprb >= 1
        requiredNSizeGrid = round(nprb);
    end
end

if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    return;
end

currentNSizeGrid = double(sixgr.util.structGet(cfgOut, "phy.carrier.NSizeGrid", NaN));
if ~(isfinite(currentNSizeGrid) && currentNSizeGrid >= 1)
    currentNSizeGrid = requiredNSizeGrid;
end

if useGrantLocalGrid
    cfgOut.phy.carrier.NSizeGrid = max(1, round(requiredNSizeGrid));
    cfgOut.phy.carrier.NStartGrid = max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0))) + round(prbOffset));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", double(prbOffset));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "grant_allocation");
else
    cfgOut.phy.carrier.NSizeGrid = max(round(currentNSizeGrid), round(requiredNSizeGrid));
    cfgOut.phy.carrier.NStartGrid = max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0))));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", 0);
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "full_carrier");
end
end

function n = localEffectiveTxAntennas(cfg, dir, numLayers)
if dir == "UL"
    explicitUL = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "channel.ul.nTxAnt", []), ...
        sixgr.util.structGet(cfg, "phy.ul.nTxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", []));
    if isfinite(explicitUL) && explicitUL >= 1
        n = localApplyReplayAntennaCap(cfg, explicitUL, numLayers);
        return;
    end
end

explicit = double(sixgr.util.structGet(cfg, "channel.nTxAnt", ...
    sixgr.util.structGet(cfg, "phy.nTxAnt", NaN)));
if isfinite(explicit) && explicit >= 1
    n = localApplyReplayAntennaCap(cfg, explicit, numLayers);
    return;
end
if dir == "UL"
    ueTx = double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1));
    n = localApplyReplayAntennaCap(cfg, ueTx, numLayers);
else
    n = max(1, round(numLayers));
end
end

function n = localEffectiveRxAntennas(cfg, dir, numLayers)
if dir == "UL"
    explicitUL = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "channel.ul.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "phy.ul.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", []));
    if isfinite(explicitUL) && explicitUL >= 1
        n = localApplyReplayAntennaCap(cfg, explicitUL, numLayers);
        return;
    end
end

explicit = double(sixgr.util.structGet(cfg, "channel.nRxAnt", ...
    sixgr.util.structGet(cfg, "phy.nRxAnt", NaN)));
if isfinite(explicit) && explicit >= 1
    n = localApplyReplayAntennaCap(cfg, explicit, numLayers);
    return;
end
if dir == "UL"
    bsRx = double(sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", ...
        sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", 1)));
    n = localApplyReplayAntennaCap(cfg, bsRx, numLayers);
else
    ueRx = double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", 1));
    n = localApplyReplayAntennaCap(cfg, ueRx, numLayers);
end
end

function n = localApplyReplayAntennaCap(cfg, value, numLayers)
n = max(1, round(double(value)));
if logical(sixgr.util.structGet(cfg, "system.waveform.capReplayAntennasToLayers", false))
    n = max(1, min(n, max(1, round(double(numLayers)))));
end
end

function value = localFirstFiniteScalar(varargin)
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

function bits = localNormalizeTransportBits(payloadIn, expectedBits, inputFormat)
expectedBits = max(0, round(double(expectedBits)));
if expectedBits == 0
    bits = int8(zeros(0,1));
    return;
end

if isempty(payloadIn)
    bits = int8(randi([0 1], expectedBits, 1));
    return;
end

fmt = lower(char(string(inputFormat)));
if strcmp(fmt, "bytes")
    bits = sixgr.l2.mac.TBAssembler.bytesToBits(uint8(payloadIn(:)));
else
    bits = int8(payloadIn(:) ~= 0);
end

if numel(bits) < expectedBits
    bits(end+1:expectedBits,1) = 0;
elseif numel(bits) > expectedBits
    bits = bits(1:expectedBits);
end
bits = int8(bits(:));
end

function [tx0, grantUsed] = localBuildGrantAlignedPDSCHTx(cfgE, grant)
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet)
    cfgE = sixgr.util.structSet(cfgE, "phy.pdsch.prbSet", localReplayPRBSet(cfgE, grant));
end
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgE);
[~, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgE);
grantUsed = grant;
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet) && isprop(pdsch, "PRBSet")
    pdsch.PRBSet = localReplayPRBSet(cfgE, grant);
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation) && isprop(pdsch, "SymbolAllocation")
    sa = double(grant.SymbolAllocation(:).');
    if numel(sa) >= 2
        pdsch.SymbolAllocation = sa(1:2);
    end
end
if isfield(grant, "Modulation") && ~isempty(grant.Modulation) && isprop(pdsch, "Modulation")
    pdsch.Modulation = char(string(grant.Modulation));
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers) && isprop(pdsch, "NumLayers")
    pdsch.NumLayers = max(1, round(double(grant.NumLayers)));
end
rv = localGrantRV(grant);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", ...
    sixgr.util.structGet(cfgE, "phy.pdsch.codeRate", 0.5)));
xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfgE, localObjectValue(pdsch, "SymbolAllocation", [0 14]));
try
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
catch
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
end
tx0 = struct( ...
    "Carrier", carrier, ...
    "PDSCH", pdsch, ...
    "RV", rv, ...
    "TargetCodeRate", targetCodeRate, ...
    "XOverhead", double(xOverhead), ...
    "TransportBlockSize", localComputeTBSBitsFromAlloc(pdsch, pdschInfo, targetCodeRate, double(xOverhead)));
end

function prbSet = localReplayPRBSet(cfgE, grant)
prbSet = double(unique(grant.PRBSet(:).'));
offset = double(sixgr.util.structGet(cfgE, "system.waveform.replayPRBOffset", 0));
if isfinite(offset) && offset > 0
    prbSet = prbSet - offset;
end
prbSet = prbSet(isfinite(prbSet) & prbSet >= 0);
if isempty(prbSet)
    nGrid = max(1, round(double(sixgr.util.structGet(cfgE, "phy.carrier.NSizeGrid", 1))));
    prbSet = 0:(nGrid-1);
end
end

function [tx0, grantUsed] = localBuildGrantAlignedPUSCHTx(cfgE, grant)
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet)
    cfgE = sixgr.util.structSet(cfgE, "phy.pusch.prbSet", localReplayPRBSet(cfgE, grant));
end
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgE);
[~, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfgE);
grantUsed = grant;
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet) && isprop(pusch, "PRBSet")
    pusch.PRBSet = localReplayPRBSet(cfgE, grant);
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation) && isprop(pusch, "SymbolAllocation")
    sa = double(grant.SymbolAllocation(:).');
    if numel(sa) >= 2
        pusch.SymbolAllocation = sa(1:2);
    end
end
pusch = localNormalizeReplayPUSCHMapping(pusch);
if isfield(grant, "Modulation") && ~isempty(grant.Modulation) && isprop(pusch, "Modulation")
    pusch.Modulation = char(string(grant.Modulation));
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers) && isprop(pusch, "NumLayers")
    pusch.NumLayers = max(1, round(double(grant.NumLayers)));
end
rv = localGrantRV(grant);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", ...
    sixgr.util.structGet(cfgE, "phy.pusch.codeRate", 0.5)));
xOverhead = double(sixgr.util.structGet(cfgE, "phy.pusch.xOverhead", 0));
try
    [~, puschInfo] = nrPUSCHIndices(carrier, pusch, "IndexStyle", "index");
catch
    [~, puschInfo] = nrPUSCHIndices(carrier, pusch);
end
tx0 = struct( ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "RV", rv, ...
    "TargetCodeRate", targetCodeRate, ...
    "XOverhead", double(xOverhead), ...
    "TransportBlockSize", localComputeTBSBitsFromAlloc(pusch, puschInfo, targetCodeRate, double(xOverhead)));
end

function key = localReplayTxCacheKey(dir, tmpl)
signature = struct();
signature.Direction = upper(char(string(dir)));
signature.TransportBlockSize = double(sixgr.util.structGet(tmpl, "TransportBlockSize", NaN));
signature.RV = double(sixgr.util.structGet(tmpl, "RV", NaN));
signature.TargetCodeRate = round(double(sixgr.util.structGet(tmpl, "TargetCodeRate", NaN)) * 1e6) / 1e6;
signature.XOverhead = double(sixgr.util.structGet(tmpl, "XOverhead", NaN));
signature.Carrier = localObjectCacheStruct(sixgr.util.structGet(tmpl, "Carrier", []));
if strcmpi(signature.Direction, "UL")
    signature.Channel = localObjectCacheStruct(sixgr.util.structGet(tmpl, "PUSCH", []));
else
    signature.Channel = localObjectCacheStruct(sixgr.util.structGet(tmpl, "PDSCH", []));
end
try
    key = char(jsonencode(signature));
catch
    key = sprintf("%s|TBS=%g|RV=%g|Rate=%.6f", signature.Direction, ...
        signature.TransportBlockSize, signature.RV, signature.TargetCodeRate);
end
end

function key = localReplayTemplateCacheKey(cfgReplay, dir, grant)
signature = struct();
signature.Direction = upper(char(string(dir)));
signature.ChannelModel = char(string(localResolveChannelToken(cfgReplay)));
signature.TxAntennas = double(sixgr.util.structGet(cfgReplay, "channel.nTxAnt", NaN));
signature.RxAntennas = double(sixgr.util.structGet(cfgReplay, "channel.nRxAnt", NaN));
signature.NSizeGrid = double(sixgr.util.structGet(cfgReplay, "phy.carrier.NSizeGrid", NaN));
signature.NStartGrid = double(sixgr.util.structGet(cfgReplay, "phy.carrier.NStartGrid", NaN));
signature.SubcarrierSpacing = double(sixgr.util.structGet(cfgReplay, "phy.carrier.SubcarrierSpacing", NaN));
signature.PRBSet = double(localReplayPRBSet(cfgReplay, grant));
signature.SymbolAllocation = double(sixgr.util.structGet(grant, "SymbolAllocation", [0 14]));
signature.Modulation = char(string(sixgr.util.structGet(grant, "Modulation", "")));
signature.NumLayers = double(sixgr.util.structGet(grant, "NumLayers", NaN));
signature.RV = double(localGrantRV(grant));
signature.TargetCodeRate = round(double(sixgr.util.structGet(grant, "TargetCodeRate", NaN)) * 1e6) / 1e6;
try
    key = char(jsonencode(signature));
catch
    key = sprintf("%s|ch=%s|tx=%g|rx=%g|grid=%g|start=%g|layers=%g|rv=%g", ...
        signature.Direction, signature.ChannelModel, signature.TxAntennas, ...
        signature.RxAntennas, signature.NSizeGrid, signature.NStartGrid, ...
        signature.NumLayers, signature.RV);
end
end

function out = localObjectCacheStruct(value)
if isempty(value)
    out = struct();
    return;
end
try
    warnState = warning('off', 'MATLAB:structOnObject');
    cleanup = onCleanup(@() warning(warnState.state, 'MATLAB:structOnObject'));
    out = orderfields(struct(value));
    clear cleanup;
catch
    out = struct("StringValue", char(string(value)));
end
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    if isobject(obj) && isprop(obj, char(propName))
        value = obj.(char(propName));
    elseif isstruct(obj) && isfield(obj, char(propName))
        value = obj.(char(propName));
    end
catch
    value = defaultValue;
end
end

function varargout = localReplayGrantTemplateCache(action, key, value)
persistent cacheMap keyOrder
if isempty(cacheMap)
    cacheMap = containers.Map('KeyType','char','ValueType','any');
    keyOrder = strings(0,1);
end

switch lower(string(action))
    case "get"
        if isKey(cacheMap, char(key))
            varargout = {true, cacheMap(char(key))};
        else
            varargout = {false, struct()};
        end
    case "set"
        cacheMap(char(key)) = value;
        keyOrder(end+1,1) = string(key);
        maxEntries = 512;
        if numel(cacheMap) > maxEntries
            dropCount = max(1, floor(maxEntries / 4));
            keyOrder = localPruneReplayCache(cacheMap, keyOrder, dropCount);
        end
        varargout = {};
    case "reset"
        remove(cacheMap, keys(cacheMap));
        keyOrder = strings(0,1);
        varargout = {};
    otherwise
        error("sixgr:system:ReplayGrant:BadTemplateCacheAction", ...
            "Unknown replay template cache action '%s'.", char(string(action)));
end
end

function varargout = localReplayTxTemplateCache(action, key, value)
persistent cacheMap keyOrder
if isempty(cacheMap)
    cacheMap = containers.Map('KeyType','char','ValueType','any');
    keyOrder = strings(0,1);
end

switch lower(string(action))
    case "get"
        if isKey(cacheMap, char(key))
            varargout = {true, cacheMap(char(key))};
        else
            varargout = {false, struct()};
        end
    case "set"
        cacheMap(char(key)) = value;
        keyOrder(end+1,1) = string(key);
        maxEntries = 256;
        if numel(cacheMap) > maxEntries
            dropCount = max(1, floor(maxEntries / 4));
            keyOrder = localPruneReplayCache(cacheMap, keyOrder, dropCount);
        end
        varargout = {};
    case "reset"
        remove(cacheMap, keys(cacheMap));
        keyOrder = strings(0,1);
        varargout = {};
    otherwise
        error("sixgr:system:ReplayGrant:BadCacheAction", ...
            "Unknown replay TX cache action '%s'.", char(string(action)));
end
end

function keyOrder = localPruneReplayCache(cacheMap, keyOrder, dropCount)
if isempty(keyOrder) || numel(cacheMap) == 0
    keyOrder = strings(0,1);
    return;
end

dropCount = min(dropCount, numel(keyOrder));
dropKeys = unique(keyOrder(1:dropCount), 'stable');
for i = 1:numel(dropKeys)
    rawKey = char(dropKeys(i));
    if isKey(cacheMap, rawKey)
        remove(cacheMap, rawKey);
    end
end

liveKeys = string(keys(cacheMap));
if isempty(liveKeys)
    keyOrder = strings(0,1);
else
    keyOrder = liveKeys(:);
end
end

function tbsBits = localComputeTBSBitsFromAlloc(chCfg, chInfo, targetCodeRate, xOverhead)
nPRB = max(1, numel(chCfg.PRBSet));
[nrePerPRB, gBits] = localResolveDataNREPerPRB(chInfo, nPRB, chCfg.Modulation, chCfg.NumLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error("sixgr:system:WaveformReplay:MissingExactNRE", ...
        "Waveform replay could not derive an exact data RE budget for %s: PRBs=%d Modulation=%s Layers=%d G=%g.", ...
        class(chCfg), round(double(nPRB)), char(string(chCfg.Modulation)), ...
        round(double(chCfg.NumLayers)), double(gBits));
end
tbsBits = double(nrTBS(chCfg.Modulation, chCfg.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
tbsBits = max(24, round(tbsBits));
end

function [nrePerPRB, gBits] = localResolveDataNREPerPRB(chInfo, nPRB, modStr, nLayers)
nrePerPRB = NaN;
gBits = NaN;
qm = localQmFromModulation(modStr);
if isfield(chInfo, "G")
    gBits = double(chInfo.G);
    if isfinite(gBits)
        if gBits <= 0
            nrePerPRB = 0;
            return;
        end
        nrePerPRB = floor(double(gBits) / max(double(qm) * double(nLayers) * max(double(nPRB), 1), 1));
        if isfinite(nrePerPRB) && nrePerPRB > 0
            return;
        end
    end
end
if isfield(chInfo, "NRE")
    nrePerPRB = floor(double(chInfo.NRE) / max(double(nPRB), 1));
elseif isfield(chInfo, "NREPerPRB")
    nrePerPRB = double(chInfo.NREPerPRB);
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = NaN;
end
end

function qm = localQmFromModulation(modScheme)
switch upper(char(string(modScheme)))
    case {"PI/2-BPSK","BPSK"}
        qm = 1;
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    case "4096QAM"
        qm = 12;
    otherwise
        qm = 2;
end
end

function rv = localGrantRV(grant)
rv = double(sixgr.util.structGet(grant, "RV", NaN));
if ~(isscalar(rv) && isfinite(rv))
    harq = sixgr.util.structGet(grant, "HARQ", struct());
    rv = double(sixgr.util.structGet(harq, "RV", 0));
end
if ~(isscalar(rv) && isfinite(rv))
    rv = 0;
end
rv = max(0, min(3, round(rv)));
end

function pusch = localNormalizeReplayPUSCHMapping(pusch)
symAlloc = [0 14];
try
    if isprop(pusch, "SymbolAllocation") && ~isempty(pusch.SymbolAllocation)
        symAlloc = double(pusch.SymbolAllocation(:).');
    end
catch
end
startSym = 0;
if ~isempty(symAlloc)
    startSym = max(0, round(symAlloc(1)));
end

mapType = "A";
try
    if isprop(pusch, "MappingType") && ~isempty(pusch.MappingType)
        mapType = string(pusch.MappingType);
    end
catch
end
if startSym > 3 && upper(mapType) == "A"
    try
        if isprop(pusch, "MappingType")
            pusch.MappingType = 'B';
        end
    catch
    end
elseif strlength(mapType) == 0
    try
        if isprop(pusch, "MappingType")
            pusch.MappingType = 'A';
        end
    catch
    end
end
end

function state = localInitChannelState(cfg, tx, txInfo)
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0, ...
    "Cfg", cfg, "SampleRateHz", localResolveSampleRate(tx, txInfo), ...
    "ImpairmentReplay", struct());

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
    return;
end

cfgCh = cfg;
cfgCh.channel.doppler_Hz = max(0, double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0)))));

fs = double(state.SampleRateHz);
numTx = max(1, size(tx.Waveform, 2));
numRx = max(1, round(double(sixgr.util.structGet(cfgCh, "channel.nRxAnt", ...
    sixgr.util.structGet(cfgCh, "phy.nRxAnt", 1)))));

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", sixgr.util.structGet(cfgCh, "run.seed", 1));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
end
end

function [y, nVar, state] = localApplyChannelAndAwgn(x, snr_dB, state)
y = x;
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
        xIn = [x; zeros(padSamples, size(x,2), "like", x)];
    end
    try
        yRaw = state.Obj(xIn);
    catch
        [yRaw, ~] = state.Obj(xIn);
    end
    if trimSamples > 0 && size(yRaw,1) >= (trimSamples + size(x,1))
        y = yRaw(1+trimSamples:trimSamples+size(x,1), :);
    else
        y = yRaw;
        if size(y,1) > size(x,1)
            y = y(1:size(x,1), :);
        elseif size(y,1) < size(x,1)
            y(end+1:size(x,1), :) = cast(0, "like", y); %#ok<AGROW>
        end
    end
end
[y, state] = localApplyReplayImpairments(y, state);
[y, nVar] = localAddAwgn(y, snr_dB);
end

function [y, state] = localApplyReplayImpairments(x, state)
y = x;
if ~(isstruct(state) && isfield(state, "Cfg"))
    return;
end
sampleRateHz = double(sixgr.util.structGet(state, "SampleRateHz", NaN));
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = 0;
end
[y, imp] = sixgr.link.applyWaveformImpairments(x, state.Cfg, sampleRateHz);
state.ImpairmentReplay = imp;
end

function [y, nVar] = localAddAwgn(x, snr_dB)
snrLin = 10.^(double(snr_dB)/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

function tf = localAllowsFastAWGN(cfg, grant, chState)
if logical(sixgr.util.structGet(chState, "UseFading", false))
    tf = false;
    return;
end
channelToken = localResolveChannelToken(cfg);
numLayers = max(1, round(double(sixgr.util.structGet(grant, "NumLayers", 1))));
numTxAnt = max(1, round(double(sixgr.util.structGet(cfg, "channel.nTxAnt", 1))));
numRxAnt = max(1, round(double(sixgr.util.structGet(cfg, "channel.nRxAnt", 1))));
tf = any(strcmp(channelToken, ["AWGN","NONE","OFF"])) && numLayers <= 1 && numTxAnt <= 1 && numRxAnt <= 1;
end

function token = localResolveChannelToken(cfg)
paths = { ...
    "channel.tdlProfile", ...
    "channel.cdlProfile", ...
    "channel.delayProfile", ...
    "channel.fading.profile", ...
    "channel.model", ...
    "channel.fading.model" ...
    };
token = "AWGN";
for i = 1:numel(paths)
    raw = string(sixgr.util.structGet(cfg, paths{i}, ""));
    raw = upper(strtrim(raw));
    if startsWith(raw, "TDL") || startsWith(raw, "CDL")
        token = raw;
        return;
    end
    if strlength(raw) > 0 && token == "AWGN"
        token = raw;
    end
end
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

function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, fs)
padSamples = 0;
trimSamples = 0;
if isempty(chObj) || ~isfinite(double(fs)) || double(fs) <= 0
    return;
end
filterDelay = 0;
pathDelays = [];
try
    chInfo = info(chObj);
    filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", 0));
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
catch
end
if isempty(pathDelays)
    try
        pathDelays = double(chObj.PathDelays);
    catch
        pathDelays = [];
    end
end
maxPathDelay = 0;
if ~isempty(pathDelays)
    maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
end
% Keep enough waveform padding for the full channel memory, but only trim
% the implementation filter delay. The physical path delay must remain for
% timing and channel estimation to observe on fading grants.
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function maxIter = localLDPCMaxIterations(snr_dB, cfg, opt)
cfgMaxIter = sixgr.phy.phycode.resolveLDPCMaxIterations(cfg);
cfgMaxIter = max(1, cfgMaxIter);
hardMax = round(double(opt.LDPCMaxIterations));
if hardMax > 0
    maxIter = max(1, min(cfgMaxIter, hardMax));
    return;
end
% Truth replay must not silently reduce decoder iterations from SNR. A lower
% cap is allowed only through the explicit LDPCMaxIterations input above.
maxIter = cfgMaxIter;
maxIter = max(1, round(maxIter));
end
