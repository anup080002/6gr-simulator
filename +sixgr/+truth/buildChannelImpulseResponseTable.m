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
    [txRuntime, txMeta, rxRuntime, rxMeta, numTxAnt, numRxAnt] = ...
        localRuntimeAntennaEndpoints(cfg, direction);
    ch = sixgr.channel.ChannelFactory.create(cfg, ...
        "SampleRate", fsHz, ...
        "NumTxAnt", numTxAnt, ...
        "NumRxAnt", numRxAnt, ...
        "LinkDirection", char(direction), ...
        "TransmitAntennaRuntime", txRuntime, ...
        "ReceiveAntennaRuntime", rxRuntime, ...
        "TransmitAntennaMeta", txMeta, ...
        "ReceiveAntennaMeta", rxMeta);
catch
    return;
end
if ~(isstruct(ch) && isfield(ch, "Object") && ~isempty(ch.Object))
    return;
end

chObj = ch.Object;
releaseCleanup = onCleanup(@() localReleaseChannelObject(chObj)); %#ok<NASGU>
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

azimuthDepartureDeg = localNumericRowVector(sixgr.util.structGet(chInfo, "AnglesAoD", []));
azimuthArrivalDeg = localNumericRowVector(sixgr.util.structGet(chInfo, "AnglesAoA", []));
zenithDepartureDeg = localNumericRowVector(sixgr.util.structGet(chInfo, "AnglesZoD", []));
zenithArrivalDeg = localNumericRowVector(sixgr.util.structGet(chInfo, "AnglesZoA", []));

n = min(numel(pathDelays), numel(pathGains));
if n <= 0
    return;
end
pathDelays = pathDelays(1:n);
pathGains = pathGains(1:n);
azimuthDepartureDeg = localAlignedNumericVector(azimuthDepartureDeg, n);
azimuthArrivalDeg = localAlignedNumericVector(azimuthArrivalDeg, n);
zenithDepartureDeg = localAlignedNumericVector(zenithDepartureDeg, n);
zenithArrivalDeg = localAlignedNumericVector(zenithArrivalDeg, n);
valid = isfinite(pathDelays) & isfinite(pathGains);
pathDelays = pathDelays(valid);
pathGains = pathGains(valid);
azimuthDepartureDeg = azimuthDepartureDeg(valid);
azimuthArrivalDeg = azimuthArrivalDeg(valid);
zenithDepartureDeg = zenithDepartureDeg(valid);
zenithArrivalDeg = zenithArrivalDeg(valid);
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
txOrientation = localOrientationRow(sixgr.util.structGet(ch.Meta, ...
    "TransmitArrayOrientation_deg", [NaN NaN NaN]));
rxOrientation = localOrientationRow(sixgr.util.structGet(ch.Meta, ...
    "ReceiveArrayOrientation_deg", [NaN NaN NaN]));
angleStatus = repmat("not_applicable_to_channel_profile", n, 1);
finiteAngles = isfinite(azimuthDepartureDeg) & isfinite(azimuthArrivalDeg) & ...
    isfinite(zenithDepartureDeg) & isfinite(zenithArrivalDeg);
angleStatus(finiteAngles) = "available_from_runtime_channel_info";

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
    azimuthDepartureDeg(:), ...
    azimuthArrivalDeg(:), ...
    zenithDepartureDeg(:), ...
    zenithArrivalDeg(:), ...
    repmat(txOrientation(1), n, 1), ...
    repmat(txOrientation(2), n, 1), ...
    repmat(txOrientation(3), n, 1), ...
    repmat(rxOrientation(1), n, 1), ...
    repmat(rxOrientation(2), n, 1), ...
    repmat(rxOrientation(3), n, 1), ...
    repmat("3gpp_tr38901_global_coordinate_system", n, 1), ...
    angleStatus, ...
    repmat("available", n, 1), ...
    repmat("sixgr.channel.ChannelFactory.info.runtime_nr_channel_path_delay_gain_angles", n, 1), ...
    'VariableNames', localChannelImpulseResponseVariableNames());
end

function T = localEmptyChannelImpulseResponseTable()
T = table( ...
    strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), false(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', localChannelImpulseResponseVariableNames());
end

function names = localChannelImpulseResponseVariableNames()
names = {'Direction','ResponseType','TapIndex','TapDelay_s','PathDelay_s','TapPower_dB','PathPower_dB', ...
    'TapLinearPower','NormalizedTapPower','DelaySpread_s','ChannelModel','DelayProfile','ChannelObjectClass', ...
    'NormalizePathGains','ChannelFilterDelay_samples','MaximumChannelDelay_samples','SampleRate_Hz', ...
    'AzimuthDeparture_deg','AzimuthArrival_deg','ZenithDeparture_deg','ZenithArrival_deg', ...
    'TxArrayOrientationAzimuth_deg','TxArrayOrientationDowntilt_deg','TxArrayOrientationSlant_deg', ...
    'RxArrayOrientationAzimuth_deg','RxArrayOrientationDowntilt_deg','RxArrayOrientationSlant_deg', ...
    'AngleCoordinateFrame','AngleStatus','Status','Source'};
end

function [txRuntime, txMeta, rxRuntime, rxMeta, numTxAnt, numRxAnt] = ...
        localRuntimeAntennaEndpoints(cfg, direction)
if direction == "UL"
    txRole = "ue";
    rxRole = "bs";
    signal = "pusch";
    txPorts = double(sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", ...
        sixgr.util.structGet(cfg, "phy.pusch.numPorts", 1)));
    rxPorts = double(sixgr.util.structGet(cfg, "antenna.bs.numRxRFChains", 1));
    txRF = double(sixgr.util.structGet(cfg, "antenna.ue.numTxRFChains", txPorts));
    rxRF = double(sixgr.util.structGet(cfg, "antenna.bs.numRxRFChains", rxPorts));
else
    txRole = "bs";
    rxRole = "ue";
    signal = "pdsch";
    txPorts = double(sixgr.util.structGet(cfg, "phy.pdsch.numPorts", 1));
    rxPorts = double(sixgr.util.structGet(cfg, "antenna.ue.numRxRFChains", 1));
    txRF = double(sixgr.util.structGet(cfg, "antenna.bs.numTxRFChains", txPorts));
    rxRF = double(sixgr.util.structGet(cfg, "antenna.ue.numRxRFChains", rxPorts));
end
txRuntime = sixgr.rf.AntennaArrayFactory.build(cfg, txRole, ...
    "signal", signal, "numPorts", txPorts, "numRFChains", txRF);
rxRuntime = sixgr.rf.AntennaArrayFactory.build(cfg, rxRole, ...
    "signal", signal, "numPorts", rxPorts, "numRFChains", rxRF);
txMeta = localRuntimeAntennaMeta(txRuntime, upper(txRole));
rxMeta = localRuntimeAntennaMeta(rxRuntime, upper(rxRole));
numTxAnt = double(txRuntime.NumWaveformColumns);
numRxAnt = double(rxRuntime.NumWaveformColumns);
end

function meta = localRuntimeAntennaMeta(arr, role)
meta = struct( ...
    "NodeType", char(role), "NodeIndex", 1, ...
    "NumRows", double(arr.Size(1)), "NumCols", double(arr.Size(2)), ...
    "NumPolarizations", double(arr.NPol), ...
    "PanelRows", double(arr.PanelRows), "PanelCols", double(arr.PanelCols), ...
    "NumElements", double(arr.NumElements), "NumPorts", double(arr.NumPorts), ...
    "NumWaveformColumns", double(arr.NumWaveformColumns), ...
    "NumRFChains", double(arr.NumRFChains), ...
    "WaveformDomain", string(arr.WaveformDomain), ...
    "PortCountSource", string(arr.PortCountSource), ...
    "SpacingH_lambda", double(arr.ElementSpacing_lambda(1)), ...
    "SpacingV_lambda", double(arr.ElementSpacing_lambda(2)), ...
    "Azimuth_deg", 0, "Heading_deg", 0, "Tilt_deg", 0, ...
    "BoresightAzimuth_deg", double(arr.BoresightAzElSlant_deg(1)), ...
    "BoresightElevation_deg", double(arr.BoresightAzElSlant_deg(2)), ...
    "BoresightSlant_deg", double(arr.BoresightAzElSlant_deg(3)), ...
    "HasPhasedArrayObject", logical(arr.HasPhased));
end

function values = localAlignedNumericVector(values, count)
if isempty(values)
    values = nan(1, count);
elseif numel(values) < count
    values = [values(:).' nan(1, count - numel(values))];
else
    values = values(1:count);
end
end

function orientation = localOrientationRow(value)
orientation = double(value(:).');
if numel(orientation) < 3
    orientation(end+1:3) = NaN;
else
    orientation = orientation(1:3);
end
end

function localReleaseChannelObject(obj)
try
    release(obj);
catch
end
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
