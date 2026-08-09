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
    encoded = strings(numel(v), 1);
    for i = 1:numel(v)
        encoded(i) = localValueToString(v{i});
    end
    s = "cell[" + strjoin(encoded, ",") + "]";
elseif isstring(v) || ischar(v) || iscategorical(v)
    values = string(v(:));
    encoded = strings(numel(values), 1);
    for i = 1:numel(values)
        encoded(i) = localFrameText(values(i));
    end
    s = string(class(v)) + "[" + strjoin(encoded, ",") + "]";
elseif islogical(v)
    s = "logical[" + strjoin(string(double(v(:).')), ",") + "]";
elseif isnumeric(v)
    nums = double(v(:)).';
    if isreal(nums)
        s = string(class(v)) + "[" + strjoin(compose("%.17g", nums), ",") + "]";
    else
        complexParts = compose("%.17g%+.17gi", real(nums), imag(nums));
        s = string(class(v)) + "[" + strjoin(complexParts, ",") + "]";
    end
elseif isdatetime(v) || isduration(v)
    values = string(v(:));
    encoded = strings(numel(values), 1);
    for i = 1:numel(values)
        encoded(i) = localFrameText(values(i));
    end
    s = string(class(v)) + "[" + strjoin(encoded, ",") + "]";
else
    try
        s = string(class(v)) + "[" + localFrameText(string(jsonencode(v))) + "]";
    catch
        s = string(class(v)) + "[" + localFrameText(string(v)) + "]";
    end
end
end

function framed = localFrameText(value)
value = string(value);
if ismissing(value)
    value = "<missing>";
end
if ~isscalar(value)
    error("sixgr:kpi:NonScalarTextHashToken", ...
        "KPI source-row hash serialization requires scalar text tokens.");
end
framed = string(strlength(value)) + ":" + value;
end

function h = localSHA256(text)
try
    h = sixgr.util.sha256Hex(uint8(unicode2native(char(string(text)), "UTF-8")));
catch cause
    failure = MException("sixgr:kpi:SourceHashUnavailable", ...
        "Strict KPI source-row hashing failed: %s", cause.message);
    failure = addCause(failure, cause);
    throwAsCaller(failure);
end
end
