function tableToken = resolveConfiguredMCSTable(cfg, direction)
%RESOLVECONFIGUREDMCSTABLE Resolve the explicit MCS table for DL or UL runtime use.

if nargin < 2 || strlength(string(direction)) == 0
    direction = "DL";
end

dir = upper(string(direction));
if dir == "UL"
    tableToken = string(sixgr.util.structGet(cfg, "phy.pusch.mcsTable", []));
else
    tableToken = string(sixgr.util.structGet(cfg, "phy.pdsch.mcsTable", []));
end

tableToken = lower(strtrim(tableToken));
if strlength(tableToken) == 0
    error("sixgr:link:MissingMCSTableConfig", ...
        "Missing explicit MCS table config for direction '%s'.", dir);
end
end
