function amc = resolveMCSFromCQI(cqiIn, mcsTable, cqiTable)
%RESOLVEMCSFROMCQI Resolve a CQI row into a provisional NR MCS profile.

if nargin < 2 || isempty(mcsTable)
    mcsTable = "qam64_table1";
end
if nargin < 3 || isempty(cqiTable)
    cqiTable = localInferCQITable(mcsTable);
end

tableToken = lower(strtrim(string(mcsTable)));
cqiProfile = sixgr.link.resolveCQIProfile(cqiTable, cqiIn);
emptyMCS = sixgr.link.resolveMCSProfile(tableToken, -1);

amc = struct( ...
    "Valid", false, ...
    "MCSTable", char(tableToken), ...
    "CQITable", char(cqiProfile.Table), ...
    "MCSIndex", NaN, ...
    "CQIProfile", cqiProfile, ...
    "MCSProfile", emptyMCS);

if ~(cqiProfile.Valid && cqiProfile.CQI >= 1)
    return;
end

bestProfile = emptyMCS;
bestIndex = NaN;
bestSE = -inf;
for idx = 0:31
    profile = sixgr.link.resolveMCSProfile(tableToken, idx);
    if ~profile.Valid || profile.Qm > cqiProfile.Qm + 1e-9
        continue;
    end
    if profile.SpectralEfficiency <= cqiProfile.SpectralEfficiency + 1e-9
        if profile.SpectralEfficiency > bestSE + 1e-9 || ...
                (abs(profile.SpectralEfficiency - bestSE) <= 1e-9 && (isnan(bestIndex) || idx > bestIndex))
            bestSE = profile.SpectralEfficiency;
            bestProfile = profile;
            bestIndex = idx;
        end
    end
end

if isnan(bestIndex)
    for idx = 0:31
        profile = sixgr.link.resolveMCSProfile(tableToken, idx);
        if profile.Valid && profile.Qm <= cqiProfile.Qm + 1e-9
            bestProfile = profile;
            bestIndex = idx;
            break;
        end
    end
end

if isnan(bestIndex) || ~bestProfile.Valid
    return;
end

amc.Valid = true;
amc.MCSIndex = double(bestIndex);
amc.MCSProfile = bestProfile;
end

function cqiTable = localInferCQITable(mcsTable)
token = lower(strtrim(string(mcsTable)));
if contains(token, "256") || contains(token, "table2")
    cqiTable = "table2";
else
    cqiTable = "table1";
end
end
