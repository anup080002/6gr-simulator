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
    rawToken = string(sixgr.util.structGet(cfg, candidatePaths(i), []));
    if strlength(strtrim(rawToken)) > 0
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
