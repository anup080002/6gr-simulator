function T = buildChannelImpulseResponseTable(cfg, varargin)
%BUILDCHANNELIMPULSERESPONSETABLE Export configured fading-channel taps.
% The rows are derived from the actual ChannelFactory channel object metadata.
% AWGN or unavailable channel-object paths return an empty table rather than a
% synthetic impulse response.

p = inputParser;
p.FunctionName = "sixgr.truth.buildChannelImpulseResponseTable";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Directions", ["DL","UL"], @(x) ischar(x) || isstring(x) || iscellstr(x));
addParameter(p, "SampleRate_Hz", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
parse(p, cfg, varargin{:});
opt = p.Results;

directions = string(opt.Directions);
directions = directions(:);
directions = directions(strlength(strtrim(directions)) > 0);
if isempty(directions)
    directions = ["DL"; "UL"];
end

parts = cell(numel(directions), 1);
for i = 1:numel(directions)
    parts{i} = localChannelImpulseResponseSlice(cfg, upper(strtrim(directions(i))), opt.SampleRate_Hz);
end

T = localVertcatTables(parts);
if isempty(T)
    T = localEmptyChannelImpulseResponseTable();
end
end

function T = localChannelImpulseResponseSlice(cfg, direction, sampleRateHz)
T = localEmptyChannelImpulseResponseTable();
if isempty(sampleRateHz)
    fsHz = localResolveChannelImpulseSampleRateHz(cfg);
else
    fsHz = double(sampleRateHz);
end
if ~(isscalar(fsHz) && isfinite(fsHz) && fsHz > 0)
    fsHz = localResolveChannelImpulseSampleRateHz(cfg);
end

try
    ch = sixgr.channel.ChannelFactory.create(cfg, ...
        "SampleRate", fsHz, ...
        "NumTxAnt", 1, ...
        "NumRxAnt", 1, ...
        "LinkDirection", char(direction));
catch
    return;
end
if ~(isstruct(ch) && isfield(ch, "Object") && ~isempty(ch.Object))
    return;
end

chObj = ch.Object;
try
    chInfo = info(chObj);
catch
    chInfo = struct();
end

pathDelays = localNumericRowVector(sixgr.util.structGet(chInfo, "PathDelays", []));
if isempty(pathDelays)
    try
        pathDelays = localNumericRowVector(chObj.PathDelays);
    catch
        pathDelays = [];
    end
end

pathGains = localNumericRowVector(sixgr.util.structGet(chInfo, "AveragePathGains", []));
if isempty(pathGains)
    try
        pathGains = localNumericRowVector(chObj.AveragePathGains);
    catch
        pathGains = [];
    end
end

n = min(numel(pathDelays), numel(pathGains));
if n <= 0
    return;
end
pathDelays = pathDelays(1:n);
pathGains = pathGains(1:n);
valid = isfinite(pathDelays) & isfinite(pathGains);
pathDelays = pathDelays(valid);
pathGains = pathGains(valid);
n = numel(pathDelays);
if n <= 0
    return;
end

linearPower = 10 .^ (pathGains ./ 10);
powerDenom = sum(linearPower);
if isfinite(powerDenom) && powerDenom > 0
    normalizedPower = linearPower ./ powerDenom;
else
    normalizedPower = nan(size(linearPower));
end

delaySpread = double(sixgr.util.structGet(cfg, "channel.delaySpread_s", ...
    sixgr.util.structGet(cfg, "channel.fading.delaySpread_s", NaN)));
model = string(sixgr.util.structGet(ch.Meta, "Model", sixgr.util.structGet(cfg, "channel.model", "")));
delayProfile = localResolveChannelImpulseDelayProfile(cfg, chObj);
className = string(class(chObj));
normalizePathGains = localObjectLogicalProperty(chObj, "NormalizePathGains", false);
filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", NaN));
maxDelay = double(sixgr.util.structGet(chInfo, "MaximumChannelDelay", NaN));

T = table( ...
    repmat(string(direction), n, 1), ...
    repmat("model_average_power_delay_profile", n, 1), ...
    (1:n)', ...
    pathDelays(:), ...
    pathDelays(:), ...
    pathGains(:), ...
    pathGains(:), ...
    linearPower(:), ...
    normalizedPower(:), ...
    repmat(delaySpread, n, 1), ...
    repmat(model, n, 1), ...
    repmat(delayProfile, n, 1), ...
    repmat(className, n, 1), ...
    repmat(logical(normalizePathGains), n, 1), ...
    repmat(filterDelay, n, 1), ...
    repmat(maxDelay, n, 1), ...
    repmat(fsHz, n, 1), ...
    repmat("available", n, 1), ...
    repmat("sixgr.channel.ChannelFactory.info.PathDelays.AveragePathGains", n, 1), ...
    'VariableNames', localChannelImpulseResponseVariableNames());
end

function T = localEmptyChannelImpulseResponseTable()
T = table( ...
    strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), false(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', localChannelImpulseResponseVariableNames());
end

function names = localChannelImpulseResponseVariableNames()
names = {'Direction','ResponseType','TapIndex','TapDelay_s','PathDelay_s','TapPower_dB','PathPower_dB', ...
    'TapLinearPower','NormalizedTapPower','DelaySpread_s','ChannelModel','DelayProfile','ChannelObjectClass', ...
    'NormalizePathGains','ChannelFilterDelay_samples','MaximumChannelDelay_samples','SampleRate_Hz','Status','Source'};
end

function fsHz = localResolveChannelImpulseSampleRateHz(cfg)
candidates = ["phy.sampleRate_Hz","phy.sampleRate","phy.SampleRate","phy.carrier.SampleRate", ...
    "phy.carrier.SampleRate_Hz","waveform.sampleRate_Hz","waveform.sampleRate","run.sampleRate_Hz"];
fsHz = NaN;
for i = 1:numel(candidates)
    value = sixgr.util.structGet(cfg, candidates(i), NaN);
    try
        value = double(value);
    catch
        value = str2double(string(value));
    end
    if isscalar(value) && isfinite(value) && value > 0
        fsHz = value;
        return;
    end
end

try
    carrier = nrCarrierConfig;
    nSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
    scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
        sixgr.util.structGet(cfg, "phy.scs_kHz", NaN)));
    if isfinite(nSizeGrid) && nSizeGrid > 0
        carrier.NSizeGrid = nSizeGrid;
    end
    if isfinite(scs) && scs > 0
        carrier.SubcarrierSpacing = scs;
    end
    ofdmInfo = nrOFDMInfo(carrier);
    fsHz = double(ofdmInfo.SampleRate);
catch
    fsHz = 30.72e6;
end
if ~(isfinite(fsHz) && fsHz > 0)
    fsHz = 30.72e6;
end
end

function delayProfile = localResolveChannelImpulseDelayProfile(cfg, chObj)
delayProfile = string(sixgr.util.structGet(cfg, "channel.delayProfile", ...
    sixgr.util.structGet(cfg, "channel.cdlProfile", ...
    sixgr.util.structGet(cfg, "channel.tdlProfile", ...
    sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
if strlength(strtrim(delayProfile)) > 0
    return;
end
try
    delayProfile = string(chObj.DelayProfile);
catch
    delayProfile = "";
end
end

function out = localObjectLogicalProperty(obj, propName, defaultValue)
out = logical(defaultValue);
try
    out = logical(obj.(propName));
catch
end
end

function x = localNumericRowVector(value)
if isempty(value)
    x = [];
    return;
end
try
    x = double(value(:)).';
catch
    x = str2double(string(value(:))).';
end
end

function T = localVertcatTables(parts)
T = table();
if isempty(parts)
    return;
end
for i = 1:numel(parts)
    part = parts{i};
    if ~(istable(part) && ~isempty(part))
        continue;
    end
    if isempty(T)
        T = part;
    else
        T = [T; part]; %#ok<AGROW>
    end
end
end
