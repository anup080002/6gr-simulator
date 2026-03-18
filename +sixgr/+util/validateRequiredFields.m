function validateRequiredFields(s, requiredPaths, context)
%VALIDATEREQUIREDFIELDS Error if any required nested fields are missing.
%
%   sixgr.util.validateRequiredFields(cfg, ["run.mode","phy.carrier.NSizeGrid"], "cfg")

if nargin < 3 || isempty(context)
    context = "struct";
end

if ischar(requiredPaths)
    requiredPaths = string(requiredPaths);
elseif iscell(requiredPaths)
    requiredPaths = string(requiredPaths);
else
    requiredPaths = string(requiredPaths);
end

missing = strings(0,1);
for i = 1:numel(requiredPaths)
    p = requiredPaths(i);
    v = sixgr.util.structGet(s, p, []);
    if isempty(v) && ~localHasField(s, p)
        missing(end+1,1) = p; %#ok<AGROW>
    end
end

if ~isempty(missing)
    error("sixgr:util:validateRequiredFields:Missing", ...
        "%s missing required fields: %s", context, strjoin(missing, ", "));
end

end

function tf = localHasField(s, path)
tf = true;
parts = strsplit(char(path), ".");
cur = s;
for i = 1:numel(parts)
    k = parts{i};
    if ~(builtin("isstruct", cur) && isscalar(cur) && isfield(cur, k))
        tf = false;
        return;
    end
    cur = cur.(k);
end
end
