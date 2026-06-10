function tableToken = resolveConfiguredCQITable(cfg, direction)
%RESOLVECONFIGUREDCQITABLE Resolve the explicit CQI table for DL or UL runtime use.

if nargin < 2 || strlength(string(direction)) == 0
    direction = "DL";
end

dir = upper(string(direction));
if dir == "UL"
    candidatePaths = [ ...
        "phy.pusch.cqiTable"
        "phy.csi.ulCQITable"
        "phy.csi.cqiTable"];
else
    candidatePaths = [ ...
        "phy.pdsch.cqiTable"
        "phy.csi.dlCQITable"
        "phy.csi.cqiTable"];
end

rawToken = "";
for i = 1:numel(candidatePaths)
    candidateValue = sixgr.util.structGet(cfg, candidatePaths(i), []);
    candidateText = localScalarToken(candidateValue);
    if strlength(strtrim(candidateText)) > 0
        rawToken = candidateText;
        break;
    end
end

if strlength(strtrim(rawToken)) == 0
    rawToken = localInferCQITableFromConfiguredMCS(cfg, dir);
end

if strlength(strtrim(rawToken)) == 0
    error("sixgr:link:MissingCQITableConfig", ...
        "Missing CQI table config for direction '%s'. Configure phy.csi.*CQITable or a matching MCS/maxModulation table.", dir);
end

tableToken = string(sixgr.link.resolveCQIProfile(rawToken, 1).Table);
if ~ismember(lower(strtrim(tableToken)), ["table1","table2"])
    error("sixgr:link:InvalidCQITableConfig", ...
        "Unsupported CQI table '%s' for direction '%s'.", rawToken, dir);
end

function tableToken = localInferCQITableFromConfiguredMCS(cfg, direction)
if upper(string(direction)) == "UL"
    rawMCS = localScalarToken(sixgr.util.structGet(cfg, "phy.pusch.mcsTable", []));
    rawMod = localScalarToken(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.pusch.maxModulation", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.modulation", [])));
else
    rawMCS = localScalarToken(sixgr.util.structGet(cfg, "phy.pdsch.mcsTable", []));
    rawMod = localScalarToken(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.pdsch.maxModulation", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.modulation", [])));
end
token = lower(strtrim(rawMCS));
if contains(token, "256") || contains(token, "table2")
    tableToken = "table2";
    return;
end
if contains(token, "64") || contains(token, "table1")
    tableToken = "table1";
    return;
end
modToken = upper(strrep(strtrim(rawMod), " ", ""));
if any(modToken == ["256QAM","1024QAM","4096QAM"])
    tableToken = "table2";
elseif strlength(modToken) > 0
    tableToken = "table1";
else
    tableToken = "";
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for i = 1:numel(varargin)
    candidate = varargin{i};
    if isempty(candidate)
        continue;
    end
    if isstring(candidate)
        candidate = candidate(strlength(strtrim(candidate)) > 0);
        if isempty(candidate)
            continue;
        end
        value = candidate(1);
        return;
    elseif ischar(candidate)
        if strlength(strtrim(string(candidate))) == 0
            continue;
        end
        value = candidate;
        return;
    else
        value = candidate;
        return;
    end
end
end
end

function token = localScalarToken(rawValue)
token = "";
if isempty(rawValue)
    return;
end
if isstring(rawValue)
    rawValue = rawValue(:);
    rawValue = rawValue(strlength(strtrim(rawValue)) > 0);
    if isempty(rawValue)
        return;
    end
    token = string(rawValue(1));
    return;
end
if iscell(rawValue)
    rawValue = rawValue(:);
    rawValue = rawValue(~cellfun(@isempty, rawValue));
    if isempty(rawValue)
        return;
    end
    token = localScalarToken(rawValue{1});
    return;
end
if ischar(rawValue)
    token = string(rawValue);
    return;
end
if isnumeric(rawValue) || islogical(rawValue)
    if isscalar(rawValue) && isfinite(double(rawValue))
        token = string(rawValue);
    end
    return;
end
try
    token = string(rawValue);
    token = token(1);
catch
    token = "";
end
end
