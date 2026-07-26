function [y, replay] = applyCompositeReceiverFrontEnd(x, cfg, sampleRateHz, replay, varargin)
%APPLYCOMPOSITERECEIVERFRONTEND Apply common Rx RF/ADC after waveform summation.
% Keep this file ASCII-only.

if nargin < 4 || ~isstruct(replay)
    replay = struct();
end
if nargin < 3 || ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    y = x;
    replay.CompositeReceiverFrontEndApplied = false;
    replay.CompositeReceiverFrontEndStatus = "not_applied_sample_rate_unavailable";
    return;
end

p = inputParser;
p.addParameter("Direction", "", @(v) ischar(v) || isstring(v));
p.addParameter("UseLegacyGlobalConfig", true, @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
p.addParameter("ApplyADC", true, @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
p.parse(varargin{:});
opt = p.Results;

direction = upper(strtrim(string(opt.Direction)));
if strlength(direction) == 0
    direction = upper(strtrim(string(sixgr.util.structGet(replay, "PowerContextDirection", ""))));
end
if strlength(direction) == 0
    userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
    direction = upper(strtrim(string(sixgr.util.structGet(userMeta, "RuntimeCurrentDirection", ...
        sixgr.util.structGet(userMeta, "Direction", "DL")))));
end
if direction ~= "UL"
    direction = "DL";
end

[cfgFE, autoAGC] = localEnsureCompositeReceiverAGC(cfg, logical(opt.ApplyADC));

rfOut = sixgr.rf.applyRFImpairmentChain(x, cfgFE, ...
    "SampleRateHz", double(sampleRateHz), ...
    "Direction", char(direction), ...
    "MeasurementPoint", "rx_composite_front_end", ...
    "Endpoint", "rx", ...
    "StrictMutationRequired", false, ...
    "UseLegacyGlobalConfig", logical(opt.UseLegacyGlobalConfig), ...
    "ApplyPA", false, ...
    "ApplyADC", logical(opt.ApplyADC));

y = cast(rfOut.Waveform, "like", x);
replay = localMergeRFReplay(replay, rfOut.Replay, rfOut.Row);
replay.CompositeReceiverFrontEndApplied = true;
replay.CompositeReceiverFrontEndStatus = "applied_after_channel_sum_and_noise";
replay.CompositeReceiverFrontEndOrder = "channel_per_link_large_scale_then_shared_slot_sum_then_noise_then_rx_rf_adc";
replay.CompositeReceiverAutoAGCEnabled = logical(autoAGC.Enabled);
replay.CompositeReceiverAutoAGCSource = char(string(autoAGC.Source));
replay.CompositeReceiverAutoAGCTargetRMS = double(autoAGC.TargetRMS);
replay.CompositeReceiverAutoAGCMaxGain_dB = double(autoAGC.MaxGain_dB);
end

function [cfgOut, autoAGC] = localEnsureCompositeReceiverAGC(cfgIn, applyADC)
cfgOut = cfgIn;
autoAGC = struct( ...
    "Enabled", false, ...
    "Source", "not_required", ...
    "TargetRMS", NaN, ...
    "MaxGain_dB", NaN);
if ~logical(applyADC) || ~localADCQuantizationEnabled(cfgIn)
    return;
end
if localHasPath(cfgIn, "rf.rx.agc.enable") || localHasPath(cfgIn, "rf.agc.enable") || ...
        localHasPath(cfgIn, "phy.impairments.agcEnabled")
    autoAGC.Source = "explicit_agc_configuration";
    return;
end
if localRFStrictProfileSelected(cfgIn)
    error("RF:ImplicitAGCForbidden", ...
        "Strict RF execution requires an explicit AGC profile when ADC quantization is enabled.");
end
autoAGC.Source = "agc_not_configured_identity";
end

function tf = localADCQuantizationEnabled(cfg)
bits = localFirstFinite( ...
    sixgr.util.structGet(cfg, "rf.adcBits", NaN), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationBits", NaN), ...
    NaN);
explicit = localHasPath(cfg, "rf.adcBits") || localHasPath(cfg, "phy.impairments.adcQuantizationBits") || ...
    localHasPath(cfg, "rf.adc.enable") || localHasPath(cfg, "phy.impairments.adcQuantizationEnabled");
if ~(explicit && isfinite(bits) && bits > 0 && bits < 32)
    tf = false;
    return;
end
enabled = localFirstLogical( ...
    sixgr.util.structGet(cfg, "rf.adc.enable", []), ...
    sixgr.util.structGet(cfg, "phy.impairments.adcQuantizationEnabled", []), ...
    true);
tf = logical(enabled);
end

function replay = localMergeRFReplay(replay, rfReplay, rfRow)
fields = fieldnames(rfReplay);
for i = 1:numel(fields)
    replay.(fields{i}) = rfReplay.(fields{i});
end
replay.RFImpairmentChainId = char(string(rfRow.RFImpairmentChainId));
replay.RFStrictOk = logical(rfRow.StrictOk);
replay.RFFailureReason = char(string(rfRow.FailureReason));
replay.EVMMeasuredDb = double(rfRow.EVMMeasuredDb);
replay.EVMMeasuredPercent = double(rfRow.EVMMeasuredPercent);
replay.RFExecutionStatus = "applied_ordered_composite_receiver_front_end";
if isfield(rfReplay, "InjectedCFO_Hz")
    replay.InjectedCFO_Hz = double(rfReplay.InjectedCFO_Hz);
end
if isfield(rfReplay, "InjectedTimingOffset_samples")
    replay.InjectedTimingOffset_samples = double(rfReplay.InjectedTimingOffset_samples);
end
if isfield(rfReplay, "TimingOffsetApplied")
    replay.TimingOffsetExecutionStatus = localConditionalString(logical(rfReplay.TimingOffsetApplied), ...
        "applied_fractional_sample_delay", "disabled_or_zero_identity");
end
if isfield(rfReplay, "CFOApplied")
    replay.CFOExecutionStatus = localConditionalString(logical(rfReplay.CFOApplied), ...
        "applied_cfo_rotation", "disabled_or_zero_identity");
end
if isfield(rfReplay, "PhaseNoiseApplied")
    replay.PhaseNoiseApplied = logical(rfReplay.PhaseNoiseApplied);
end
if isfield(rfReplay, "IQImbalanceApplied")
    replay.IQImbalanceApplied = logical(rfReplay.IQImbalanceApplied);
end
end

function value = localConditionalString(tf, whenTrue, whenFalse)
if tf
    value = string(whenTrue);
else
    value = string(whenFalse);
end
end

function value = localFirstFinite(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = double(raw(1));
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
