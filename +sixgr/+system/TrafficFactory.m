classdef TrafficFactory
% sixgr.system.TrafficFactory
% Flow-aware traffic generation for system and E2E simulations.
%
% Supports:
%   - Model families: fullBuffer, xr, genai, mmtc, mixed
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
            model = lower(char(string(sixgr.util.structGet(cfg, "traffic.model", "fullBuffer"))));
            baseBits = localBaseModelBits(cfg, model, nUE, nTTI, tti_s);

            [flows, flowTable] = localResolveFlows(cfg, model, tti_s, baseBits);
            if isempty(flows)
                flows = localDefaultFlow(cfg, model, tti_s, baseBits);
                flowTable = localFlowTable(flows);
            end

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

function [flows, flowTable] = localResolveFlows(cfg, model, tti_s, baseBits)
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
    flows(i) = f;
end

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
end

function [fDL, fUL] = localGenerateFlowBits(cfg, flow, nUE, nTTI, tti_s, baseBits, nFlows)
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

% Burstiness shaping.
switch lower(char(flow.Burstiness))
    case "high"
        pOn = 0.35;
    case "low"
        pOn = 0.9;
    otherwise
        pOn = 0.65;
end
onMask = rand(nTTI, nUE) < pOn;
src = src .* onMask;

% Jitter.
j = min(max(flow.JitterPct, 0), 0.95);
src = src .* (1 + j * (2 * rand(nTTI, nUE) - 1));
src = max(src, 0);

% Transport-level shaping.
proto = upper(char(flow.Protocol));
if strcmp(proto, "TCP")
    src = localApplyTCPShaping(cfg, src);
end

% Weight.
src = max(0, src * max(flow.Weight, 0));

% Direction split.
dir = upper(char(flow.Direction));
[dlRatio, ulRatio] = localDirectionRatios(cfg, dir);
fDL = src * dlRatio;
fUL = src * ulRatio;
end

function src = localApplyTCPShaping(cfg, src)
% Simple congestion-window-like shaping (simulation proxy).
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
        'VariableNames', {'Name','QFI','FiveQI','Protocol','Direction', ...
                          'PacketDelayBudget_ms','PacketSize_bytes','PacketInterval_ms', ...
                          'Rate_Mbps','Weight','Burstiness'});
    return;
end

T = table(string({flows.Name}.'), [flows.QFI].', [flows.FiveQI].', ...
    string({flows.Protocol}.'), string({flows.Direction}.'), ...
    [flows.PacketDelayBudget_ms].', [flows.PacketSize_bytes].', [flows.PacketInterval_ms].', ...
    [flows.Rate_Mbps].', [flows.Weight].', string({flows.Burstiness}.'), ...
    'VariableNames', {'Name','QFI','FiveQI','Protocol','Direction', ...
                      'PacketDelayBudget_ms','PacketSize_bytes','PacketInterval_ms', ...
                      'Rate_Mbps','Weight','Burstiness'});
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
end

function v = localGetField(s, name, def)
if isfield(s, name)
    v = s.(name);
else
    v = def;
end
end

