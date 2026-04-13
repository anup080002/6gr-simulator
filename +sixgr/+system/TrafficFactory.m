classdef TrafficFactory
% sixgr.system.TrafficFactory
% Flow-aware traffic generation for system and E2E simulations.
%
% Supports:
%   - Model families: fullBuffer, xr, genai, mmtc, mixed, traceReplay
%   - Transport: UDP/TCP (or mixed via per-flow setting)
%   - Direction: DL / UL / BIDIR
%   - QoS hints: 5QI/QFI + packet delay budget (PDB)
%
% Output fields:
%   traffic.OfferedBitsDL  [NumTTI x NumUE]
%   traffic.OfferedBitsUL  [NumTTI x NumUE]
%   traffic.OfferedBits    [NumTTI x NumUE]  (DL+UL for backward compatibility)
%   traffic.FlowTable      table with configured QoS flows

    methods(Static)
        function traffic = generate(cfg, nUE, nTTI, tti_s)
            model = lower(strtrim(string(sixgr.util.structGet(cfg, "traffic.model", "fullBuffer"))));
            if any(model == ["tracereplay","trace_replay","trace"])
                traffic = localGenerateTraceReplayTraffic(cfg, nUE, nTTI, tti_s);
                return;
            end
            baseBits = localBaseModelBits(cfg, char(model), nUE, nTTI, tti_s);

            [flows, flowTable] = localResolveFlows(cfg, model, tti_s, baseBits, nUE);
            if isempty(flows)
                if logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false))
                    error("sixgr:traffic:MissingResolvedFlowOwnership", ...
                        "Strict LLS traffic generation requires explicit traffic.flows or buildInternalConfig-derived traffic.flows with traffic.flowSource/traffic.flowDerivationMode labels.");
                end
                flows = localDefaultFlow(cfg, model, tti_s, baseBits);
                flowTable = localFlowTable(flows);
            end
            flowTable = localAnnotateFlowTable(flowTable);
            [transportSemanticClass, transportTruthLabel, transportApproxReason] = localSummarizeFlowTransportSemantics(flowTable);

            offeredDL = zeros(nTTI, nUE);
            offeredUL = zeros(nTTI, nUE);
            for i = 1:numel(flows)
                f = flows(i);
                [fDL, fUL] = localGenerateFlowBits(cfg, f, nUE, nTTI, tti_s, baseBits, numel(flows));
                offeredDL = offeredDL + fDL;
                offeredUL = offeredUL + fUL;
            end

            offeredDL = max(0, round(offeredDL));
            offeredUL = max(0, round(offeredUL));
            offered = offeredDL + offeredUL;

            protList = upper(string(flowTable.Protocol));
            protList = protList(strlength(protList) > 0);
            if isempty(protList)
                transport = upper(string(sixgr.util.structGet(cfg, "traffic.transport", "UDP")));
            else
                u = unique(protList);
                if numel(u) == 1
                    transport = u(1);
                else
                    transport = "MIXED";
                end
            end

            dirList = upper(string(flowTable.Direction));
            dirList = dirList(strlength(dirList) > 0);
            if isempty(dirList)
                flowDir = upper(string(sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR")));
            else
                if all(dirList == "DL")
                    flowDir = "DL";
                elseif all(dirList == "UL")
                    flowDir = "UL";
                else
                    flowDir = "BIDIR";
                end
            end

            pdbVals = double(flowTable.PacketDelayBudget_ms);
            pdbVals = pdbVals(isfinite(pdbVals) & pdbVals > 0);
            if isempty(pdbVals)
                pdbMs = double(sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", ...
                    sixgr.util.structGet(cfg, "traffic.qos.latencyBudget_ms", 50)));
            else
                pdbMs = min(pdbVals);
            end

            traffic = struct();
            traffic.Model = string(model);
            traffic.Transport = upper(string(transport));
            traffic.FlowDirection = upper(string(flowDir));
            traffic.PacketDelayBudget_ms = double(pdbMs);
            traffic.OfferedBits = offered;
            traffic.OfferedBitsDL = offeredDL;
            traffic.OfferedBitsUL = offeredUL;
            traffic.MeanBitsPerUEPerTTI = mean(offered, 1);
            traffic.FlowTable = flowTable;
            traffic.FlowCount = height(flowTable);
            traffic.ModelSource = "profile_generator";
            traffic.Deterministic = false;
            traffic.ProxyShapingUsed = any(string(flowTable.TransportTruthLabel) == "proxy_transport_not_full_tcp_truth");
            traffic.TransportSemanticClass = string(transportSemanticClass);
            traffic.TransportTruthLabel = string(transportTruthLabel);
            traffic.TransportApproximationReason = string(transportApproxReason);
        end
    end
end

function baseBits = localBaseModelBits(cfg, model, nUE, nTTI, tti_s)
switch model
    case {"xr","traffic_xr","extendedreality"}
        baseBits = sixgr.system.Traffic_XR(cfg, nUE, nTTI, tti_s);
    case {"genai","traffic_genai","ai"}
        baseBits = sixgr.system.Traffic_GenAI(cfg, nUE, nTTI, tti_s);
    case {"mmtc","traffic_mmtc","iot"}
        baseBits = sixgr.system.Traffic_mMTC(cfg, nUE, nTTI, tti_s);
    case {"mixed"}
        baseBits = sixgr.system.Traffic_XR(cfg, nUE, nTTI, tti_s) ...
            + sixgr.system.Traffic_GenAI(cfg, nUE, nTTI, tti_s) ...
            + sixgr.system.Traffic_mMTC(cfg, nUE, nTTI, tti_s);
    otherwise
        bitsPerTTI = double(sixgr.util.structGet(cfg, "traffic.fullBufferBitsPerTTI", 1e5));
        baseBits = bitsPerTTI * ones(nTTI, nUE);
end
baseBits = max(0, double(baseBits));
end

function traffic = localGenerateTraceReplayTraffic(cfg, nUE, nTTI, tti_s)
[traceSpec, sourceLabel] = localLoadTraceReplaySpec(cfg);

offeredDL = localNormalizeTraceMatrix(sixgr.util.structGet(traceSpec, "offeredBitsDL", []), nTTI, nUE, "traffic.trace.offeredBitsDL");
offeredUL = localNormalizeTraceMatrix(sixgr.util.structGet(traceSpec, "offeredBitsUL", []), nTTI, nUE, "traffic.trace.offeredBitsUL");
offered = offeredDL + offeredUL;

transport = upper(string(sixgr.util.structGet(traceSpec, "transport", "")));
if strlength(transport) == 0
    transport = upper(string(sixgr.util.structGet(cfg, "traffic.transport", "UDP")));
end
flowDir = upper(string(sixgr.util.structGet(traceSpec, "flowDirection", "")));
if strlength(flowDir) == 0
    flowDir = upper(string(sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR")));
end
pdbMs = double(sixgr.util.structGet(traceSpec, "packetDelayBudget_ms", NaN));
if ~(isscalar(pdbMs) && isfinite(pdbMs) && pdbMs > 0)
    pdbMs = double(sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", 50));
end
if ~(isscalar(pdbMs) && isfinite(pdbMs) && pdbMs > 0)
    pdbMs = 50;
end

flowTable = sixgr.util.structGet(traceSpec, "flowTable", table());
if ~(istable(flowTable) && ~isempty(flowTable))
    rateMbps = mean(offered(:), "omitnan") / max(tti_s, eps) / 1e6;
    flowTable = table("traceReplay", 9, 9, string(transport), string(flowDir), pdbMs, ...
        double(sixgr.util.structGet(cfg, "traffic.packetSize_bytes", 1200)), ...
        double(sixgr.util.structGet(cfg, "traffic.packetInterval_ms", 10)), ...
        double(rateMbps), 1.0, "trace", ...
        'VariableNames', {'Name','QFI','FiveQI','Protocol','Direction', ...
                          'PacketDelayBudget_ms','PacketSize_bytes','PacketInterval_ms', ...
                          'Rate_Mbps','Weight','Burstiness'});
    flowTable.Protocol = upper(string(flowTable.Protocol));
    flowTable.Direction = upper(string(flowTable.Direction));
    flowTable = localAnnotateFlowTable(flowTable);
end

traffic = struct();
traffic.Model = "traceReplay";
traffic.Transport = upper(string(transport));
traffic.FlowDirection = upper(string(flowDir));
traffic.PacketDelayBudget_ms = double(pdbMs);
traffic.OfferedBits = offered;
traffic.OfferedBitsDL = offeredDL;
traffic.OfferedBitsUL = offeredUL;
traffic.MeanBitsPerUEPerTTI = mean(offered, 1);
traffic.FlowTable = flowTable;
traffic.FlowCount = height(flowTable);
traffic.ModelSource = string(sourceLabel);
traffic.Deterministic = true;
traffic.ProxyShapingUsed = false;
[transportSemanticClass, transportTruthLabel, transportApproxReason] = localSummarizeFlowTransportSemantics(flowTable);
traffic.TransportSemanticClass = string(transportSemanticClass);
traffic.TransportTruthLabel = string(transportTruthLabel);
traffic.TransportApproximationReason = string(transportApproxReason);
end

function [flows, flowTable] = localResolveFlows(cfg, model, tti_s, baseBits, nUE)
flows = struct([]);
flowTable = localFlowTable(flows);

raw = sixgr.util.structGet(cfg, "traffic.flows", []);
if isempty(raw)
    return;
end

if isstruct(raw)
    if isscalar(raw)
        raw = raw(:);
    end
elseif iscell(raw)
    try
        raw = [raw{:}];
    catch
        raw = struct([]);
    end
else
    raw = struct([]);
end

if isempty(raw)
    return;
end

flows = repmat(localFlowTemplate(), numel(raw), 1);
defaultRateMbps = mean(baseBits(:), "omitnan") / max(tti_s, eps) / 1e6;
if ~(isfinite(defaultRateMbps) && defaultRateMbps > 0)
    defaultRateMbps = 50;
end

for i = 1:numel(raw)
    r = raw(i);
    f = localFlowTemplate();
    f.Name = string(localGetField(r, "name", "flow" + string(i)));
    f.QFI = double(localGetField(r, "qfi", sixgr.util.structGet(cfg, "traffic.qos.default5QI", 9)));
    f.FiveQI = double(localGetField(r, "fiveQi", localGetField(r, "5qi", f.QFI)));
    f.Protocol = upper(string(localGetField(r, "protocol", sixgr.util.structGet(cfg, "traffic.transport", "UDP"))));
    f.Direction = upper(string(localGetField(r, "direction", sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR"))));
    f.PacketDelayBudget_ms = double(localGetField(r, "packetDelayBudget_ms", ...
        localGetField(r, "latencyBudget_ms", sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", 50))));
    f.PacketSize_bytes = double(localGetField(r, "packetSize_bytes", sixgr.util.structGet(cfg, "traffic.packetSize_bytes", 1200)));
    f.PacketInterval_ms = double(localGetField(r, "packetInterval_ms", sixgr.util.structGet(cfg, "traffic.packetInterval_ms", 10)));
    f.Rate_Mbps = double(localGetField(r, "rate_Mbps", sixgr.util.structGet(cfg, "traffic.targetRate_Mbps", defaultRateMbps)));
    f.Weight = double(localGetField(r, "weight", 1.0));
    f.JitterPct = double(localGetField(r, "jitterPct", sixgr.util.structGet(cfg, "traffic.jitterPct", 0.1)));
    f.Burstiness = lower(string(localGetField(r, "burstiness", "medium")));
    f.ServiceProfile = string(localGetField(r, "service_profile", ""));
    f.UEClass = string(localGetField(r, "ue_class", ""));
    f.UECount = double(localGetField(r, "ue_count", NaN));
    flows(i) = f;
end

flows = localAssignFlowUserMasks(flows, nUE);

flowTable = localFlowTable(flows);
end

function f = localDefaultFlow(cfg, model, tti_s, baseBits)
f = localFlowTemplate();
f.Name = string(model);
f.QFI = double(sixgr.util.structGet(cfg, "traffic.qos.default5QI", 9));
f.FiveQI = f.QFI;
f.Protocol = upper(string(sixgr.util.structGet(cfg, "traffic.transport", "UDP")));
f.Direction = upper(string(sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR")));
f.PacketDelayBudget_ms = double(sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", ...
    sixgr.util.structGet(cfg, "traffic.qos.latencyBudget_ms", 50)));
f.PacketSize_bytes = double(sixgr.util.structGet(cfg, "traffic.packetSize_bytes", 1200));
f.PacketInterval_ms = double(sixgr.util.structGet(cfg, "traffic.packetInterval_ms", 10));
f.Rate_Mbps = double(sixgr.util.structGet(cfg, "traffic.targetRate_Mbps", ...
    mean(baseBits(:), "omitnan") / max(tti_s, eps) / 1e6));
if ~(isfinite(f.Rate_Mbps) && f.Rate_Mbps > 0)
    f.Rate_Mbps = 50;
end
f.Weight = 1.0;
f.JitterPct = double(sixgr.util.structGet(cfg, "traffic.jitterPct", 0.1));
f.Burstiness = "medium";
f.ServiceProfile = string(model);
f.UEClass = "";
f.UECount = NaN;
f.UserMask = true(1, size(baseBits, 2));
end

function [traceSpec, sourceLabel] = localLoadTraceReplaySpec(cfg)
traceSpec = sixgr.util.structGet(cfg, "traffic.trace", struct());
if ~(isstruct(traceSpec) && isscalar(traceSpec))
    traceSpec = struct();
end

sourceLabel = "traceReplay_inline";
traceFile = char(string(sixgr.util.structGet(traceSpec, "file", "")));
if strlength(string(traceFile)) == 0
    traceFile = char(string(sixgr.util.structGet(traceSpec, "path", "")));
end
if strlength(string(traceFile)) == 0
    if isempty(sixgr.util.structGet(traceSpec, "offeredBitsDL", [])) && isempty(sixgr.util.structGet(traceSpec, "offeredBitsUL", []))
        error("sixgr:traffic:MissingTraceReplaySpec", ...
            "traffic.model='traceReplay' requires traffic.trace.offeredBitsDL/UL or traffic.trace.file.");
    end
    return;
end

if exist(traceFile, "file") ~= 2
    error("sixgr:traffic:MissingTraceReplayFile", ...
        "Trace replay file does not exist: %s", traceFile);
end

[~, ~, ext] = fileparts(traceFile);
ext = lower(string(ext));
if ext == ".json"
    traceSpec = jsondecode(fileread(traceFile));
    sourceLabel = "traceReplay_json";
elseif ext == ".csv"
    T = readtable(traceFile, "VariableNamingRule", "preserve");
    traceSpec = localTraceSpecFromCSV(T);
    sourceLabel = "traceReplay_csv";
else
    error("sixgr:traffic:UnsupportedTraceReplayFile", ...
        "Unsupported trace replay file type: %s", traceFile);
end
end

function traceSpec = localTraceSpecFromCSV(T)
if ~(istable(T) && ~isempty(T))
    error("sixgr:traffic:BadTraceReplayCSV", "Trace replay CSV is empty.");
end
required = ["Slot","UE","DLBits","ULBits"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    error("sixgr:traffic:BadTraceReplayCSV", ...
        "Trace replay CSV must contain columns: %s", strjoin(cellstr(required), ", "));
end

slots = double(T.Slot);
ues = double(T.UE);
if any(~isfinite(slots)) || any(~isfinite(ues))
    error("sixgr:traffic:BadTraceReplayCSV", "Trace replay CSV Slot/UE columns must be finite.");
end
nTTI = max(1, round(max(slots)));
nUE = max(1, round(max(ues)));
offeredDL = zeros(nTTI, nUE);
offeredUL = zeros(nTTI, nUE);
for i = 1:height(T)
    s = round(double(T.Slot(i)));
    u = round(double(T.UE(i)));
    if s < 1 || u < 1
        error("sixgr:traffic:BadTraceReplayCSV", "Trace replay CSV Slot/UE indices must be one-based positive integers.");
    end
    offeredDL(s, u) = double(T.DLBits(i));
    offeredUL(s, u) = double(T.ULBits(i));
end

traceSpec = struct();
traceSpec.offeredBitsDL = offeredDL;
traceSpec.offeredBitsUL = offeredUL;
end

function M = localNormalizeTraceMatrix(raw, nTTI, nUE, label)
if isempty(raw)
    M = zeros(nTTI, nUE);
    return;
end
M = double(raw);
sz = size(M);
if isscalar(M)
    M = repmat(M, nTTI, nUE);
elseif isequal(sz, [nTTI, nUE])
    % keep shape
elseif isequal(sz, [nTTI, 1])
    M = repmat(M, 1, nUE);
elseif isequal(sz, [1, nUE])
    M = repmat(M, nTTI, 1);
else
    error("sixgr:traffic:BadTraceReplayShape", ...
        "%s must be scalar, [NumTTI x NumUE], [NumTTI x 1], or [1 x NumUE].", label);
end
M = max(0, round(M));
end

function [fDL, fUL] = localGenerateFlowBits(cfg, flow, nUE, nTTI, tti_s, baseBits, nFlows)
mask = true(1, nUE);
if isfield(flow, "UserMask") && ~isempty(flow.UserMask)
    rawMask = logical(flow.UserMask(:).');
    mask = false(1, nUE);
    mask(1:min(nUE, numel(rawMask))) = rawMask(1:min(nUE, numel(rawMask)));
end

% Construct a per-flow source process first.
if isfinite(flow.Rate_Mbps) && flow.Rate_Mbps > 0
    meanBits = flow.Rate_Mbps * 1e6 * tti_s;
    src = meanBits * ones(nTTI, nUE);
else
    src = baseBits / max(nFlows, 1);
end

% Packetized option if rate is not explicitly provided.
if ~(isfinite(flow.Rate_Mbps) && flow.Rate_Mbps > 0)
    pktBits = max(8, 8 * round(max(flow.PacketSize_bytes, 1)));
    intTti = max(1, round((max(flow.PacketInterval_ms, 1) * 1e-3) / max(tti_s, eps)));
    src = zeros(nTTI, nUE);
    for t = 1:nTTI
        if mod(t - 1, intTti) == 0
            src(t, :) = pktBits;
        end
    end
end

% Apply any explicit UE ownership mask before temporal shaping so flow
% periodicity is assigned across the users that actually own this flow.
src(:, ~mask) = 0;

burstiness = lower(strtrim(string(flow.Burstiness)));
if any(burstiness == ["periodic","steady"])
    intTti = max(1, round((max(flow.PacketInterval_ms, tti_s * 1e3) * 1e-3) / max(tti_s, eps)));
    periodicSrc = zeros(nTTI, nUE);
    ownedIdx = find(mask);
    for localUserIdx = 1:numel(ownedIdx)
        u = ownedIdx(localUserIdx);
        offset = mod(localUserIdx - 1, intTti);
        activeSlots = (offset + 1):intTti:nTTI;
        if isempty(activeSlots)
            continue;
        end
        periodicSrc(activeSlots, u) = src(activeSlots, u) * intTti;
    end
    src = periodicSrc;
end

% Burstiness shaping.
switch burstiness
    case {"saturation","fullbuffer","full_buffer"}
        pOn = 1.0;
    case {"periodic","steady"}
        pOn = 1.0;
    case {"bursty","burst"}
        pOn = 0.35;
    case "high"
        pOn = 0.35;
    case "low"
        pOn = 0.9;
    otherwise
        pOn = 0.65;
end
if pOn < 1.0
    onMask = rand(nTTI, nUE) < pOn;
    src = src .* onMask;
end

% Jitter.
j = min(max(flow.JitterPct, 0), 0.95);
src = src .* (1 + j * (2 * rand(nTTI, nUE) - 1));
src = max(src, 0);

% Transport-level shaping.
proto = upper(strtrim(string(flow.Protocol)));
if proto == "TCP"
    src = localApplyTCPShaping(cfg, src);
end

% Weight.
src = max(0, src * max(flow.Weight, 0));

% Direction split.
dir = upper(strtrim(string(flow.Direction)));
[dlRatio, ulRatio] = localDirectionRatios(cfg, dir);
fDL = src * dlRatio;
fUL = src * ulRatio;
end

function src = localApplyTCPShaping(cfg, src)
% Simple congestion-window-like shaping (simulation proxy).
if logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false))
    error("sixgr:traffic:ProxyTransportForbidden", ...
        "TCP proxy shaping is forbidden under the no-proxy truth contract. Use traffic.model='traceReplay' with explicit trace traffic.");
end
[nTTI, nUE] = size(src);
initCwnd = max(1, round(double(sixgr.util.structGet(cfg, "traffic.tcp.initCwnd_packets", 10))));
lossProb = min(max(double(sixgr.util.structGet(cfg, "traffic.tcp.lossProb", 0.01)), 0), 0.5);
backoff = min(max(double(sixgr.util.structGet(cfg, "traffic.tcp.lossBackoff", 0.5)), 0.1), 0.95);
maxCwnd = max(initCwnd, round(double(sixgr.util.structGet(cfg, "traffic.tcp.maxCwnd_packets", 256))));
minFloor = min(max(double(sixgr.util.structGet(cfg, "traffic.tcp.minRateFloor", 0.2)), 0.01), 1.0);

cwnd = initCwnd * ones(1, nUE);
for t = 1:nTTI
    scale = max(minFloor, min(1, cwnd / max(initCwnd, 1)));
    src(t, :) = src(t, :) .* scale;

    loss = rand(1, nUE) < lossProb;
    cwnd(loss) = max(1, floor(cwnd(loss) * backoff));
    cwnd(~loss) = min(maxCwnd, cwnd(~loss) + max(1 ./ max(cwnd(~loss), 1), 0.25));
end
end

function [dlRatio, ulRatio] = localDirectionRatios(cfg, dir)
dlCfg = double(sixgr.util.structGet(cfg, "traffic.dlRatio", 0.8));
ulCfg = double(sixgr.util.structGet(cfg, "traffic.ulRatio", 0.2));
s = max(dlCfg + ulCfg, eps);
dlCfg = dlCfg / s;
ulCfg = ulCfg / s;

switch upper(char(dir))
    case "DL"
        dlRatio = 1.0; ulRatio = 0.0;
    case "UL"
        dlRatio = 0.0; ulRatio = 1.0;
    otherwise
        dlRatio = dlCfg;
        ulRatio = ulCfg;
end
end

function T = localFlowTable(flows)
if isempty(flows)
    T = table(string.empty(0,1), zeros(0,1), zeros(0,1), string.empty(0,1), string.empty(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), string.empty(0,1), ...
        string.empty(0,1), string.empty(0,1), zeros(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), ...
        'VariableNames', {'Name','QFI','FiveQI','Protocol','Direction', ...
                          'PacketDelayBudget_ms','PacketSize_bytes','PacketInterval_ms', ...
                          'Rate_Mbps','Weight','Burstiness','ServiceProfile','UEClass','UECount', ...
                          'TransportSemanticClass','TransportTruthLabel','TransportApproximationReason'});
    return;
end

T = table(string({flows.Name}.'), [flows.QFI].', [flows.FiveQI].', ...
    string({flows.Protocol}.'), string({flows.Direction}.'), ...
    [flows.PacketDelayBudget_ms].', [flows.PacketSize_bytes].', [flows.PacketInterval_ms].', ...
    [flows.Rate_Mbps].', [flows.Weight].', string({flows.Burstiness}.'), ...
    string({flows.ServiceProfile}.'), string({flows.UEClass}.'), [flows.UECount].', ...
    strings(numel(flows),1), strings(numel(flows),1), strings(numel(flows),1), ...
    'VariableNames', {'Name','QFI','FiveQI','Protocol','Direction', ...
                      'PacketDelayBudget_ms','PacketSize_bytes','PacketInterval_ms', ...
                      'Rate_Mbps','Weight','Burstiness','ServiceProfile','UEClass','UECount', ...
                      'TransportSemanticClass','TransportTruthLabel','TransportApproximationReason'});
T = localAnnotateFlowTable(T);
end

function f = localFlowTemplate()
f = struct();
f.Name = "";
f.QFI = 9;
f.FiveQI = 9;
f.Protocol = "UDP";
f.Direction = "BIDIR";
f.PacketDelayBudget_ms = 50;
f.PacketSize_bytes = 1200;
f.PacketInterval_ms = 10;
f.Rate_Mbps = 50;
f.Weight = 1.0;
f.JitterPct = 0.1;
f.Burstiness = "medium";
f.ServiceProfile = "";
f.UEClass = "";
f.UECount = NaN;
f.UserMask = true(1, 0);
end

function T = localAnnotateFlowTable(T)
if ~(istable(T) && all(ismember(["Protocol","ServiceProfile"], string(T.Properties.VariableNames))))
    return;
end
n = height(T);
semanticClass = strings(n,1);
truthLabel = strings(n,1);
approxReason = strings(n,1);
for i = 1:n
    [semanticClass(i), truthLabel(i), approxReason(i)] = localResolveTransportSemantics( ...
        string(T.Protocol(i)), string(T.ServiceProfile(i)));
end
T.TransportSemanticClass = semanticClass;
T.TransportTruthLabel = truthLabel;
T.TransportApproximationReason = approxReason;
end

function [semanticClass, truthLabel, approxReason] = localResolveTransportSemantics(protocol, serviceProfile)
protocol = upper(strtrim(string(protocol)));
serviceProfile = upper(strtrim(string(serviceProfile)));

semanticClass = "configured_transport_semantics_unspecified";
truthLabel = "transport_semantics_unspecified";
approxReason = "";

if serviceProfile == "FTP3_LIKE" && protocol == "UDP"
    semanticClass = "ftp3_like_udp_offered_load_approximation";
    truthLabel = "approximate_not_truthful_tcp";
    approxReason = "ftp3_like_profile_uses_udp_offered_load_without_tcp_connection_state_ack_retransmission_or_ftp_session_semantics";
    return;
end

if protocol == "TCP"
    semanticClass = "tcp_proxy_congestion_window_shaping";
    truthLabel = "proxy_transport_not_full_tcp_truth";
    approxReason = "tcp_mode_uses_simple_cwnd_loss_shaping_proxy_and_not_a_full_tcp_or_ftp_session_model";
    return;
end

if protocol == "UDP"
    semanticClass = "configured_udp_datagram_transport";
    truthLabel = "configured_udp_transport";
    approxReason = "";
    return;
end
end

function [semanticClass, truthLabel, approxReason] = localSummarizeFlowTransportSemantics(T)
if ~(istable(T) && ~isempty(T) && ismember("TransportTruthLabel", string(T.Properties.VariableNames)))
    semanticClass = "";
    truthLabel = "";
    approxReason = "";
    return;
end

labels = string(T.TransportTruthLabel);
classes = string(T.TransportSemanticClass);
reasons = string(T.TransportApproximationReason);
labels = labels(strlength(strtrim(labels)) > 0);
classes = classes(strlength(strtrim(classes)) > 0);
reasons = unique(reasons(strlength(strtrim(reasons)) > 0), "stable");

if any(labels == "approximate_not_truthful_tcp")
    semanticClass = "contains_ftp3_like_udp_offered_load_approximation";
    truthLabel = "contains_approximate_transport_semantics";
elseif any(labels == "proxy_transport_not_full_tcp_truth")
    semanticClass = "contains_tcp_proxy_transport_semantics";
    truthLabel = "contains_proxy_transport_semantics";
elseif numel(unique(labels, "stable")) == 1
    truthLabel = labels(1);
    if isempty(classes)
        semanticClass = "";
    elseif numel(unique(classes, "stable")) == 1
        semanticClass = classes(1);
    else
        semanticClass = "mixed_configured_transport_semantics";
    end
else
    semanticClass = "mixed_transport_semantics";
    truthLabel = "mixed_transport_truth_labels";
end

approxReason = strjoin(cellstr(reasons), "; ");
end

function flows = localAssignFlowUserMasks(flows, nUE)
if isempty(flows)
    return;
end
nUE = max(1, round(double(nUE)));
explicit = false(numel(flows), 1);
for i = 1:numel(flows)
    count = double(flows(i).UECount);
    explicit(i) = isfinite(count) && count > 0;
    flows(i).UserMask = false(1, nUE);
end
if ~any(explicit)
    for i = 1:numel(flows)
        flows(i).UserMask = true(1, nUE);
        flows(i).UECount = nUE;
    end
    return;
end

remaining = true(1, nUE);
for i = 1:numel(flows)
    if ~explicit(i)
        continue;
    end
    count = min(sum(remaining), max(0, round(double(flows(i).UECount))));
    if count <= 0
        flows(i).UECount = 0;
        continue;
    end
    idx = find(remaining, count, "first");
    flows(i).UserMask(idx) = true;
    remaining(idx) = false;
    flows(i).UECount = count;
end

unspecified = find(~explicit);
if isempty(unspecified)
    if any(remaining)
        lastExplicit = find(explicit, 1, "last");
        flows(lastExplicit).UserMask(remaining) = true;
        flows(lastExplicit).UECount = sum(flows(lastExplicit).UserMask);
    end
    return;
end

remainingIdx = find(remaining);
if isempty(remainingIdx)
    for i = unspecified(:).'
        flows(i).UECount = 0;
    end
    return;
end

baseCount = floor(numel(remainingIdx) / numel(unspecified));
extra = mod(numel(remainingIdx), numel(unspecified));
cursor = 1;
for k = 1:numel(unspecified)
    i = unspecified(k);
    count = baseCount + double(k <= extra);
    if count <= 0
        flows(i).UECount = 0;
        continue;
    end
    idx = remainingIdx(cursor:(cursor + count - 1));
    flows(i).UserMask(idx) = true;
    flows(i).UECount = count;
    cursor = cursor + count;
end
end

function v = localGetField(s, name, def)
if isfield(s, name)
    v = s.(name);
else
    v = def;
end
end
