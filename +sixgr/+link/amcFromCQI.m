function [modStr, targetCodeRate, mcsIndex] = amcFromCQI(cqiIn, modDefault, tcrDefault, cfg, direction)
%AMCFROMCQI Shared CQI-to-AMC mapping for scheduler and LLS closed loop.

if nargin < 2
    modDefault = "";
end
if nargin < 3
    tcrDefault = NaN;
end
if nargin < 4
    cfg = struct();
end
if nargin < 5 || isempty(direction)
    direction = "DL";
end

dir = upper(char(string(direction)));
cqiTable = localResolveCQITable(cfg, dir);
mcsTable = localResolveMCSTable(cfg, dir);
amc = sixgr.link.resolveMCSFromCQI(cqiIn, mcsTable, cqiTable);

if amc.Valid
    modStr = char(string(amc.MCSProfile.Modulation));
    targetCodeRate = double(amc.MCSProfile.TargetCodeRate);
    mcsIndex = double(amc.MCSIndex);
    return;
end

fallbackCQI = max(1, min(15, round(double(cqiIn))));
cqiProfile = sixgr.link.resolveCQIProfile(cqiTable, fallbackCQI);
if cqiProfile.Valid && cqiProfile.CQI >= 1
    modStr = char(string(cqiProfile.Modulation));
    targetCodeRate = double(cqiProfile.TargetCodeRate);
else
    modStr = char(string(modDefault));
    targetCodeRate = double(tcrDefault);
end

if strlength(string(modStr)) == 0
    modStr = "QPSK";
end
if ~(isfinite(targetCodeRate) && targetCodeRate > 0)
    targetCodeRate = 78 / 1024;
end
mcsIndex = sixgr.l2.mac.SchedulerBase.approxMCSIndex(modStr, targetCodeRate, fallbackCQI, char(mcsTable));
end

function tableToken = localResolveCQITable(cfg, direction)
tableToken = char(sixgr.link.resolveConfiguredCQITable(cfg, direction));
end

function tableToken = localResolveMCSTable(cfg, direction)
tableToken = char(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
end
