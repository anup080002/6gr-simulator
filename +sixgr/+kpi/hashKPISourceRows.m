function hash = hashKPISourceRows(T)
%HASHKPISOURCEROWS Stable SHA-256 hash for KPI source rows.

if ~(istable(T) && ~isempty(T))
    hash = "empty";
    return;
end

vars = string(T.Properties.VariableNames);
parts = strings(0, 1);
parts(end+1, 1) = strjoin(vars, "|");
for r = 1:height(T)
    rowParts = strings(1, numel(vars));
    for c = 1:numel(vars)
        v = T.(vars(c));
        rowParts(c) = localValueToString(v(r, :));
    end
    parts(end+1, 1) = strjoin(rowParts, "|"); %#ok<AGROW>
end
hash = localSHA256(strjoin(parts, newline));
end

function s = localValueToString(v)
if iscell(v)
    v = v{1};
end
if isstring(v) || ischar(v)
    s = string(v);
elseif islogical(v)
    s = string(double(v));
elseif isnumeric(v)
    nums = double(v(:)).';
    s = strjoin(compose("%.17g", nums), ",");
elseif isdatetime(v)
    s = string(v);
else
    try
        s = jsonencode(v);
    catch
        s = string(v);
    end
end
end

function h = localSHA256(text)
try
    md = java.security.MessageDigest.getInstance("SHA-256");
    bytes = uint8(char(string(text)));
    md.update(bytes);
    digest = typecast(md.digest(), "uint8");
    h = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
catch
    error("sixgr:kpi:SourceHashUnavailable", ...
        "Strict KPI source-row hashing requires Java SHA-256 support.");
end
end
