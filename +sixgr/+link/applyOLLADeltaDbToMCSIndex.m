function [adjustedIdx, detail] = applyOLLADeltaDbToMCSIndex(baseIdx, deltaDb, mcsTable, cqiTable, direction, varargin)
%APPLYOLLADELTADBTOMCSINDEX Apply OLLA's dB-domain margin to an MCS index.
%
% deltaDb accumulates negative on NACK (more margin required, lower MCS)
% and positive on ACK (less margin required, higher MCS), matching the
% scheduler OLLA sign convention. The dB margin is converted through the
% MCS table's required-SINR spacing; it is never added directly to the
% ordinal MCS row number.

ip = inputParser;
ip.addParameter("Config", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("TargetBLER", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
cfg = ip.Results.Config;
if isempty(cfg)
    cfg = struct();
end

[reqSINR_dB, tableInfo] = sixgr.link.mcsRequiredSINRTable(mcsTable, cqiTable, direction, ...
    "Config", cfg, ...
    "TargetBLER", ip.Results.TargetBLER);

detail = struct( ...
    "BaseMCSIndex", NaN, ...
    "AdjustedMCSIndex", NaN, ...
    "DeltaDb", double(deltaDb), ...
    "BaseRequiredSINR_dB", NaN, ...
    "TargetRequiredSINR_dB", NaN, ...
    "ThresholdSource", char(string(sixgr.util.structGet(tableInfo, "Source", ""))), ...
    "ThresholdValueRole", char(string(sixgr.util.structGet(tableInfo, "ValueRole", ""))));

finiteReq = isfinite(reqSINR_dB);
if ~any(finiteReq)
    error("sixgr:link:OLLA:MissingMCSRequiredSINR", ...
        "Cannot apply OLLA dB margin because no finite required-SINR table exists for MCS table %s / CQI table %s.", ...
        char(string(mcsTable)), char(string(cqiTable)));
end

validIndices = find(finiteReq) - 1;
baseIdx = round(double(baseIdx));
if ~(isscalar(baseIdx) && isfinite(baseIdx))
    baseIdx = min(validIndices);
end
baseIdx = max(min(validIndices), min(max(validIndices), baseIdx));
if ~isfinite(reqSINR_dB(baseIdx + 1))
    [~, nearest] = min(abs(validIndices - baseIdx));
    baseIdx = validIndices(nearest);
end

baseReqSINR = double(reqSINR_dB(baseIdx + 1));
targetReqSINR = baseReqSINR + double(deltaDb);
eligible = find(finiteReq & reqSINR_dB <= targetReqSINR + 1e-12);
if isempty(eligible)
    adjustedIdx = min(validIndices);
else
    adjustedIdx = max(eligible) - 1;
end
adjustedIdx = max(min(validIndices), min(max(validIndices), round(double(adjustedIdx))));

detail.BaseMCSIndex = double(baseIdx);
detail.AdjustedMCSIndex = double(adjustedIdx);
detail.BaseRequiredSINR_dB = double(baseReqSINR);
detail.TargetRequiredSINR_dB = double(targetReqSINR);
end
