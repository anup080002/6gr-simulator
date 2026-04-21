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
    error("sixgr:link:MissingCQITableConfig", ...
        "Missing explicit CQI table config for direction '%s'.", dir);
end

tableToken = string(sixgr.link.resolveCQIProfile(rawToken, 1).Table);
if ~ismember(lower(strtrim(tableToken)), ["table1","table2"])
    error("sixgr:link:InvalidCQITableConfig", ...
        "Unsupported CQI table '%s' for direction '%s'.", rawToken, dir);
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
