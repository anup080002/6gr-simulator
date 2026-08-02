function state = initWaveformTruthChannelState(cfg, tx, txInfo)
%INITWAVEFORMTRUTHCHANNELSTATE Prepare the authoritative waveform impairment state.

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(sixgr.util.structGet(tx, "Waveform", zeros(1, 1)), 2));
direction = localResolveDirection(cfg);
runtimeNumTx = localResolveRuntimeTxPortCapacity(cfg, direction, numTx);
numRx = localResolveRuntimeRxAntennaCount(cfg, direction, runtimeNumTx);
truthMode = sixgr.link.resolveTruthMode(cfg);

state = struct( ...
    "Initialized", true, ...
    "TruthMode", string(truthMode), ...
    "SampleRate_Hz", double(fs), ...
    "UseFading", false, ...
    "Obj", [], ...
    "RuntimeChannelState", sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), ...
    "RuntimeChannelStateUsed", false, ...
    "RuntimeChannelObjectSource", "", ...
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
    ueIdx = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", 1))));
    servingCell = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingCellIndex", ...
        sixgr.util.structGet(cfg, "lls6g.userContext.ServingCell", 1)))));
    runtimeState = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, direction, ...
        "UEIndex", ueIdx, "ServingCell", servingCell, ...
        "Seed", sixgr.util.structGet(cfg, "run.seed", NaN));
    [txRuntimeAntenna, txRuntimeMeta] = localRuntimeAntennaPair(cfg, direction, "tx", runtimeNumTx);
    [rxRuntimeAntenna, rxRuntimeMeta] = localRuntimeAntennaPair(cfg, direction, "rx", numRx);
    runtimeState = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        runtimeState, cfg, sixgr.util.structGet(tx, "Waveform", []), txInfo, ...
        "NumTxAnt", runtimeNumTx, "NumRxAnt", numRx, ...
        "TransmitAntennaRuntime", txRuntimeAntenna, ...
        "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
        "TransmitAntennaMeta", txRuntimeMeta, ...
        "ReceiveAntennaMeta", rxRuntimeMeta);
    state.RuntimeChannelState = runtimeState;
    state.RuntimeChannelStateUsed = true;
    state.RuntimeChannelObjectSource = "sixgr.channel.ChannelFactory.materializeRuntimeChannelState";
    state.UseFading = logical(sixgr.util.structGet(runtimeState, "UseFading", false));
    state.Obj = sixgr.util.structGet(runtimeState, "Obj", []);
    state.ChannelPadSamples = double(sixgr.util.structGet(runtimeState, "ChannelPadSamples", 0));
    state.ChannelTrimSamples = double(sixgr.util.structGet(runtimeState, "ChannelTrimSamples", 0));
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

function direction = localResolveDirection(cfg)
direction = upper(strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeCurrentDirection", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.Direction", "DL")))));
if direction ~= "UL"
    direction = "DL";
end
end

function numRx = localResolveRuntimeRxAntennaCount(cfg, direction, fallback)
if nargin < 3 || ~(isnumeric(fallback) && isscalar(fallback) && isfinite(fallback) && fallback >= 1)
    fallback = 1;
end
direction = upper(strtrim(string(direction)));
if direction == "UL"
    numRx = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", fallback));
    return;
end
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
numRx = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumPorts", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumPorts", []), ...
    sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", []), ...
    sixgr.util.structGet(cfg, "phy.nRxAnt", []), ...
    sixgr.util.structGet(cfg, "channel.nRxAnt", []), ...
    fallback);
numRx = max(1, round(double(numRx)));
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    vals = double(raw(:));
    vals = vals(isfinite(vals) & vals >= 1);
    if ~isempty(vals)
        value = double(vals(1));
        return;
    end
end
end

function numTx = localResolveRuntimeTxPortCapacity(cfg, direction, activePortCount)
activePortCount = max(1, round(double(activePortCount)));
direction = upper(strtrim(string(direction)));
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
if direction == "UL"
    numTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumLogicalPorts", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumLogicalPorts", []), ...
        sixgr.util.structGet(cfg, "phy.maxULLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.maxLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", []), ...
        activePortCount);
else
    numTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumLogicalPorts", []), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumLogicalPorts", []), ...
        sixgr.util.structGet(cfg, "phy.maxDLLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.dmrs.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.NumAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", []), ...
        activePortCount);
    if isfinite(numTx) && numTx > 32
        numTx = activePortCount;
    end
end
numTx = max(activePortCount, round(double(numTx)));
end

function [ant, meta] = localRuntimeAntennaPair(cfg, direction, endpoint, signalPortCount)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
role = localRuntimeRole(direction, endpoint);
if role == "BS"
    ant = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    meta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
else
    ant = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    meta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
end
[needsPortView, portViewSource] = localNeedsSignalPortView(cfg, direction, endpoint, signalPortCount);
if needsPortView
    [ant, meta] = sixgr.rf.AntennaArrayFactory.logicalPortView( ...
        ant, meta, signalPortCount, portViewSource);
end
end

function role = localRuntimeRole(direction, endpoint)
direction = upper(strtrim(string(direction)));
endpoint = lower(strtrim(string(endpoint)));
if direction == "UL"
    if endpoint == "tx"
        role = "UE";
    else
        role = "BS";
    end
else
    if endpoint == "tx"
        role = "BS";
    else
        role = "UE";
    end
end
end

function [tf, sourceToken] = localNeedsSignalPortView(cfg, direction, endpoint, signalPortCount)
tf = false;
sourceToken = "";
if ~(isnumeric(signalPortCount) && isscalar(signalPortCount) && isfinite(signalPortCount) && signalPortCount >= 1)
    return;
end
direction = upper(strtrim(string(direction)));
endpoint = lower(strtrim(string(endpoint)));
signalFamily = upper(strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeSignalFamily", ...
    sixgr.util.structGet(cfg, "phy.runtimeSignalFamily", "")))));
if direction == "DL" && endpoint == "tx"
    switch signalFamily
        case "PDCCH"
            tf = true;
            sourceToken = "pdcch_runtime_waveform_port_count";
        case "PDSCH"
            tf = true;
            sourceToken = "pdsch_runtime_waveform_port_count";
        case {"PBCH","SSB"}
            tf = true;
            sourceToken = "ssb_pbch_runtime_waveform_port_count";
        case {"TRS","CSI-RS","CSIRS"}
            tf = true;
            sourceToken = "dl_reference_signal_runtime_waveform_port_count";
    end
    if tf
        return;
    end
end
if ~(direction == "UL" && endpoint == "tx")
    return;
end
switch signalFamily
    case "PUSCH"
        tf = true;
        sourceToken = "pusch_runtime_waveform_port_count";
    case "PUCCH"
        tf = true;
        sourceToken = "pucch_runtime_waveform_port_count";
    case "PRACH"
        tf = true;
        sourceToken = "prach_runtime_waveform_port_count";
    case "SRS"
        tf = true;
        sourceToken = "srs_runtime_waveform_port_count";
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
losEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", false));
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
