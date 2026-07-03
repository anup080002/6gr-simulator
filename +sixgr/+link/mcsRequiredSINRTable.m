function [reqSINR_dB, info] = mcsRequiredSINRTable(mcsTable, cqiTable, direction, varargin)
%MCSREQUIREDSINRTABLE Derive required SINR per MCS index from CQI thresholds.
%
% REQSINR_DB(i+1) is the required SINR for MCS index i. The table is derived
% from the same CQI operating points used by resolveWidebandCQI and the
% configured CQI->MCS mapping, so OLLA and CQI selection share one threshold
% source.

if nargin < 1 || isempty(mcsTable)
    mcsTable = "qam64_table1";
end
if nargin < 2 || isempty(cqiTable)
    cqiTable = "table1";
end
if nargin < 3 || isempty(direction)
    direction = "DL";
end

ip = inputParser;
ip.addParameter("Config", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("TargetBLER", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
cfg = ip.Results.Config;
if isempty(cfg)
    cfg = struct();
end

mcsTable = char(string(mcsTable));
cqiTable = char(string(cqiTable));
direction = upper(string(direction));

[cqiReq_dB, cqiInfo] = localResolveCQIOperatingPoints(cfg, direction, cqiTable, ip.Results.TargetBLER);
maxMCS = localMaxValidMCS(mcsTable);
reqSINR_dB = nan(1, maxMCS + 1);
info = struct( ...
    "Source", char(string(sixgr.util.structGet(cqiInfo, "Source", ""))), ...
    "ValueRole", "mcs_required_sinr_derived_from_cqi_operating_points", ...
    "CQIThresholdSource", char(string(sixgr.util.structGet(cqiInfo, "Source", ""))), ...
    "CQIThresholdValueRole", char(string(sixgr.util.structGet(cqiInfo, "ValueRole", ""))), ...
    "MCSTable", char(mcsTable), ...
    "CQITable", char(cqiTable), ...
    "Direction", char(direction));

if maxMCS < 0 || isempty(cqiReq_dB)
    return;
end

anchorMCS = nan(15, 1);
anchorSINR = nan(15, 1);
for cqi = 1:min(15, numel(cqiReq_dB))
    decision = sixgr.link.resolveMCSFromCQI(cqi, mcsTable, cqiTable);
    if ~logical(sixgr.util.structGet(decision, "Valid", false))
        continue;
    end
    idx = round(double(decision.MCSIndex));
    if idx < 0 || idx > maxMCS
        continue;
    end
    anchorMCS(cqi) = idx;
    anchorSINR(cqi) = double(cqiReq_dB(cqi));
    if ~isfinite(reqSINR_dB(idx + 1))
        reqSINR_dB(idx + 1) = double(cqiReq_dB(cqi));
    else
        reqSINR_dB(idx + 1) = min(reqSINR_dB(idx + 1), double(cqiReq_dB(cqi)));
    end
end

validAnchors = isfinite(anchorMCS) & isfinite(anchorSINR);
if nnz(validAnchors) < 2
    return;
end
[anchorMCS, order] = sort(anchorMCS(validAnchors), "ascend");
anchorSINR = anchorSINR(validAnchors);
anchorSINR = anchorSINR(order);
[anchorMCS, uniqueIdx] = unique(anchorMCS, "stable");
anchorSINR = anchorSINR(uniqueIdx);

for idx = 0:maxMCS
    if isfinite(reqSINR_dB(idx + 1))
        continue;
    end
    profile = sixgr.link.resolveMCSProfile(mcsTable, idx);
    if ~logical(sixgr.util.structGet(profile, "Valid", false))
        continue;
    end
    if idx < min(anchorMCS) || idx > max(anchorMCS)
        continue;
    end
    reqSINR_dB(idx + 1) = interp1(anchorMCS, anchorSINR, double(idx), "linear");
end

finiteMask = isfinite(reqSINR_dB);
if any(finiteMask)
    reqSINR_dB(finiteMask) = cummax(reqSINR_dB(finiteMask));
end
end

function [cqiReq_dB, info] = localResolveCQIOperatingPoints(cfg, direction, cqiTable, targetBLER)
modeToken = localResolveCQIMode(cfg, direction);
if modeToken == "effective_sinr_bler_lut"
    sinrEvidence = struct( ...
        "WidebandSINR_dB", 0, ...
        "SINRSource", "scheduler_runtime_csi", ...
        "SINRValueRole", "scheduling_quality", ...
        "SINRValueStatus", "OK");
    feedback = sixgr.link.resolveWidebandCQI(sinrEvidence, cfg, direction);
    cqiReq_dB = double(sixgr.util.structGet(feedback, "CQIOperatingPointSINR_dB", []));
    if numel(cqiReq_dB) == 15 && all(isfinite(cqiReq_dB))
        info = struct( ...
            "Source", char(string(sixgr.util.structGet(feedback, "BLERLUTSource", ""))), ...
            "ValueRole", char(string(sixgr.util.structGet(feedback, "BLERLUTValueRole", ""))));
        return;
    end
end
[cqiReq_dB, info] = sixgr.link.cqiRequiredSINRTable(cqiTable, cfg, direction, ...
    "TargetBLER", targetBLER);
end

function modeToken = localResolveCQIMode(cfg, direction)
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.sinrToCQIMode"
        "phy.csi.ulSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
else
    candidates = [ ...
        "phy.pdsch.sinrToCQIMode"
        "phy.csi.dlSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
end
raw = "";
for i = 1:numel(candidates)
    raw = string(sixgr.util.structGet(cfg, candidates(i), ""));
    if strlength(strtrim(raw)) > 0
        break;
    end
end
raw = lower(strtrim(raw));
if any(raw == ["effective_sinr_bler_lut", "eesm_bler_lut", "miesm_bler_lut", "effective_sinr"])
    modeToken = "effective_sinr_bler_lut";
else
    modeToken = "threshold_table";
end
end

function maxMCS = localMaxValidMCS(mcsTable)
maxMCS = -1;
for idx = 0:31
    profile = sixgr.link.resolveMCSProfile(mcsTable, idx);
    if logical(sixgr.util.structGet(profile, "Valid", false))
        maxMCS = idx;
    end
end
end
