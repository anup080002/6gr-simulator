function state = initWaveformTruthChannelState(cfg, tx, txInfo)
%INITWAVEFORMTRUTHCHANNELSTATE Prepare the authoritative waveform impairment state.

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(sixgr.util.structGet(tx, "Waveform", zeros(1, 1)), 2));
numRx = max(1, double(sixgr.util.structGet(cfg, "phy.nRxAnt", numTx)));
truthMode = sixgr.link.resolveTruthMode(cfg);

state = struct( ...
    "Initialized", true, ...
    "TruthMode", string(truthMode), ...
    "SampleRate_Hz", double(fs), ...
    "UseFading", false, ...
    "Obj", [], ...
    "ChannelPadSamples", 0, ...
    "ChannelTrimSamples", 0, ...
    "LargeScaleGain_dB", 0, ...
    "Pathloss_dB", NaN, ...
    "ShadowFading_dB", NaN, ...
    "O2ILoss_dB", NaN, ...
    "LOS", NaN, ...
    "InterferenceSIR_dB", NaN, ...
    "InterferenceVariance", NaN);

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if ~(awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF")
    cfgCh = cfg;
    dopp = double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
        sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
        sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0))));
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

[gain_dB, pathloss_dB, shadow_dB, o2i_dB, losVal] = localResolveLargeScaleGain(cfg);
if isfinite(gain_dB)
    state.LargeScaleGain_dB = double(gain_dB);
end
state.Pathloss_dB = double(pathloss_dB);
state.ShadowFading_dB = double(shadow_dB);
state.O2ILoss_dB = double(o2i_dB);
state.LOS = double(losVal);

sir_dB = double(sixgr.util.structGet(cfg, "channel.interferenceSIR_dB", ...
    sixgr.util.structGet(cfg, "channel.interferenceMargin_dB", NaN)));
if isfinite(sir_dB)
    state.InterferenceSIR_dB = sir_dB;
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
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function [gain_dB, pathloss_dB, shadow_dB, o2i_dB, losVal] = localResolveLargeScaleGain(cfg)
gain_dB = 0;
pathloss_dB = NaN;
shadow_dB = NaN;
o2i_dB = NaN;
losVal = NaN;

explicitGain = double(sixgr.util.structGet(cfg, "channel.largeScaleGain_dB", NaN));
if isfinite(explicitGain)
    gain_dB = explicitGain;
    pathloss_dB = -explicitGain;
    return;
end

explicitPathloss = double(sixgr.util.structGet(cfg, "channel.pathloss_dB", NaN));
if isfinite(explicitPathloss)
    gain_dB = -explicitPathloss;
    pathloss_dB = explicitPathloss;
    return;
end

pathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false));
shadowEnabled = logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", false));
losEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", true));
modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
needsLargeScale = pathlossEnabled || shadowEnabled || any(modelRaw == ["TR38901", "TR38.901", "TR38_901", "ABG", "RAYTRACING", "RT"]);
if ~needsLargeScale
    return;
end

scenarioName = string(sixgr.util.structGet(cfg, "channel.propagationScenario", ...
    sixgr.util.structGet(cfg, "run.scenario", ...
    sixgr.util.structGet(cfg, "scenario.profileName", "UMa"))));
fc_Hz = double(sixgr.util.structGet(cfg, "phy.fc_Hz", sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9)));
seed = double(sixgr.util.structGet(cfg, "run.seed", 1));

[txPos_m, rxPos_m, indoorRx, indoorDistance_m] = localResolveSingleLinkGeometry(cfg);
if any(modelRaw == ["RAYTRACING", "RT"])
    plModel = sixgr.channel.RayTracingAdapter(cfg, "Scenario", scenarioName, "Fc_Hz", fc_Hz);
    [pl_dB, det] = plModel.pathloss(txPos_m, rxPos_m);
    pl_dB = double(pl_dB);
    los = NaN;
    ex = struct("shadow_dB", NaN, "o2i_dB", NaN);
    if isstruct(det) && isfield(det, "pl_dB")
        pl_dB = double(det.pl_dB);
    end
else
    plModel = sixgr.channel.TR38901Plus(cfg, "Scenario", scenarioName, "Fc_Hz", fc_Hz, "Seed", seed);
    [pl_dB, los, ex] = plModel.pathloss(txPos_m, rxPos_m, ...
        "Scenario", scenarioName, ...
        "IndoorRx", indoorRx, ...
        "IndoorDistance_m", indoorDistance_m, ...
        "PathlossEnabled", pathlossEnabled, ...
        "ShadowFadingEnabled", shadowEnabled, ...
        "LOSEnabled", losEnabled);
end

pl_dB = double(pl_dB);
if isempty(pl_dB)
    return;
end
pathloss_dB = double(pl_dB(1));
gain_dB = -double(pathloss_dB);
if isstruct(ex)
    shadow_dB = double(sixgr.util.structGet(ex, "shadow_dB", NaN));
    if numel(shadow_dB) >= 1
        shadow_dB = double(shadow_dB(1));
    end
    o2i_dB = double(sixgr.util.structGet(ex, "o2i_dB", NaN));
    if numel(o2i_dB) >= 1
        o2i_dB = double(o2i_dB(1));
    end
end
if exist("los", "var") && ~isempty(los)
    losVal = double(los(1));
end
end

function [txPos_m, rxPos_m, indoorRx, indoorDistance_m] = localResolveSingleLinkGeometry(cfg)
bsDefault = [0; 0; 25];
ueIdx = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", 1))));
ueDefault = [100 + 10 * (ueIdx - 1); 0; 1.5];

txPos_m = localResolvePosition(cfg, ...
    ["scenario.bs.position_m","scenario.bs.pos_m","scenario.base_station.position_m"], ...
    bsDefault);
rxPos_m = localResolvePosition(cfg, ...
    ["lls6g.userContext.Position_m","scenario.ue.position_m","scenario.ue.pos_m"], ...
    ueDefault);
indoorRx = logical(sixgr.util.structGet(cfg, "lls6g.userContext.Indoor", ...
    sixgr.util.structGet(cfg, "scenario.ue.indoor", false)));
indoorDistance_m = double(sixgr.util.structGet(cfg, "channel.o2i.indoorDistance_m", 10));
if ~(isfinite(indoorDistance_m) && indoorDistance_m >= 0)
    indoorDistance_m = 10;
end
end

function pos = localResolvePosition(cfg, candidates, fallback)
pos = [];
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(cfg, char(candidates(i)), []);
    pos = localAsPositionColumn(raw);
    if ~isempty(pos)
        return;
    end
end
pos = localAsPositionColumn(fallback);
end

function pos = localAsPositionColumn(raw)
pos = [];
if isempty(raw)
    return;
end
if iscell(raw)
    try
        raw = cell2mat(raw);
    catch
        return;
    end
end
raw = double(raw);
if isequal(size(raw), [1 3])
    pos = raw(:);
elseif isequal(size(raw), [3 1])
    pos = raw;
elseif ndims(raw) == 2 && size(raw, 2) == 3 && size(raw, 1) >= 1
    pos = raw(1, :).';
elseif ndims(raw) == 2 && size(raw, 1) == 3 && size(raw, 2) >= 1
    pos = raw(:, 1);
end
if isempty(pos) || numel(pos) ~= 3 || any(~isfinite(pos))
    pos = [];
end
end
