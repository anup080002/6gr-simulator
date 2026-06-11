function decision = resolveMCSIndexFromProfile(modulation, targetCodeRate, varargin)
%RESOLVEMCSINDEXFROMPROFILE Resolve a standardized NR MCS row without proxy math.
%
% This helper is intentionally table-driven: it either maps a valid CQI via
% TS 38.214 CQI/MCS tables, or matches an explicit modulation/code-rate
% request to the nearest valid row in the configured MCS table. It does not
% synthesize an "approximate" MCS when the required evidence is missing.

opt = struct( ...
    "MCSTable", "qam64_table1", ...
    "CQI", NaN, ...
    "CQITable", "", ...
    "Strict", false);
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:link:MCSProfileBadNV", ...
            "resolveMCSIndexFromProfile name-value inputs must be pairs.");
    end
    for i = 1:2:numel(varargin)
        key = char(string(varargin{i}));
        if isfield(opt, key)
            opt.(key) = varargin{i+1};
        else
            error("sixgr:link:MCSProfileUnknownOption", ...
                "Unknown MCS profile option '%s'.", key);
        end
    end
end

mcsTable = char(lower(strtrim(string(opt.MCSTable))));
if strlength(string(mcsTable)) == 0
    mcsTable = char(localDefaultMCSTable(modulation));
end
cqiTable = string(opt.CQITable);
if strlength(strtrim(cqiTable)) == 0
    cqiTable = localDefaultCQITable(mcsTable);
end

emptyProfile = sixgr.link.resolveMCSProfile(mcsTable, -1);
decision = struct( ...
    "Valid", false, ...
    "MCSIndex", NaN, ...
    "MCSProfile", emptyProfile, ...
    "MCSTable", char(mcsTable), ...
    "CQITable", char(cqiTable), ...
    "Source", "unavailable", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "mcs_resolution_input_unavailable");

cqi = sixgr.l2.mac.SchedulerBase.sanitizeCQI(opt.CQI, NaN);
if isfinite(cqi) && cqi >= 1
    amc = sixgr.link.resolveMCSFromCQI(cqi, mcsTable, cqiTable);
    if isfield(amc, "Valid") && logical(amc.Valid)
        decision.Valid = true;
        decision.MCSIndex = double(amc.MCSIndex);
        decision.MCSProfile = amc.MCSProfile;
        decision.Source = "cqi_table_measured_feedback";
        decision.ValueRole = "scheduled_from_cqi_feedback";
        decision.ValueStatus = "OK";
        decision.NAReason = "";
        return;
    end
    decision.NAReason = "cqi_profile_has_no_valid_mcs_row";
end

modStr = upper(strtrim(string(modulation)));
tcr = double(targetCodeRate);
if ~(strlength(modStr) > 0 && isscalar(tcr) && isfinite(tcr) && tcr > 0)
    localFailIfStrict(opt.Strict, decision.NAReason);
    return;
end

targetQm = sixgr.l2.mac.SchedulerBase.modOrder(modStr);
targetSE = double(targetQm) * double(tcr);
bestIdx = NaN;
bestScore = inf;
bestProfile = emptyProfile;
for idx = 0:31
    profile = sixgr.link.resolveMCSProfile(mcsTable, idx);
    if ~profile.Valid
        continue;
    end
    if profile.Qm ~= targetQm
        continue;
    end
    score = abs(double(profile.SpectralEfficiency) - targetSE);
    if score < bestScore - 1e-9 || ...
            (abs(score - bestScore) <= 1e-9 && ...
            abs(double(profile.TargetCodeRate) - tcr) < ...
            abs(double(bestProfile.TargetCodeRate) - tcr))
        bestScore = score;
        bestIdx = idx;
        bestProfile = profile;
    end
end

if isnan(bestIdx) || ~bestProfile.Valid
    decision.NAReason = "configured_modulation_code_rate_not_supported_by_mcs_table";
    localFailIfStrict(opt.Strict, decision.NAReason);
    return;
end

decision.Valid = true;
decision.MCSIndex = double(bestIdx);
decision.MCSProfile = bestProfile;
decision.Source = "mcs_table_nearest_configured_profile";
decision.ValueRole = "scheduled_from_explicit_modulation_code_rate";
decision.ValueStatus = "OK";
decision.NAReason = "";
end

function localFailIfStrict(strictMode, reason)
if logical(strictMode)
    error("sixgr:link:MCSResolutionUnavailable", ...
        "Unable to resolve a standards-table MCS index: %s.", string(reason));
end
end

function tableName = localDefaultMCSTable(modulationToken)
qm = sixgr.l2.mac.SchedulerBase.modOrder(modulationToken);
if qm >= 8
    tableName = "qam256_table2";
else
    tableName = "qam64_table1";
end
end

function tableName = localDefaultCQITable(mcsTable)
token = lower(string(mcsTable));
if contains(token, "256") || contains(token, "table2")
    tableName = "table2";
else
    tableName = "table1";
end
end
