function statusOut = canonicalizeRuntimeStatusSnapshot(statusIn)
%CANONICALIZERUNTIMESTATUSSNAPSHOT Enforce a truthful one-row status schema.
%   Live runtime status is a single measured snapshot. Text values are
%   represented as scalar strings so an unavailable text value remains one
%   table row (""), rather than becoming a zero-row char array. Numeric and
%   logical fields must already be scalar measurements; vectors are rejected
%   because silently reducing them would change their producer semantics.

if ~(isstruct(statusIn) && isscalar(statusIn))
    error("sixgr:truth:RuntimeStatusMustBeScalarStruct", ...
        "Runtime status must be a scalar struct representing one snapshot.");
end

statusOut = statusIn;
names = fieldnames(statusIn);
for i = 1:numel(names)
    name = names{i};
    statusOut.(name) = localCanonicalValue(statusIn.(name), name);
end
end

function value = localCanonicalValue(raw, fieldName)
if ischar(raw)
    if isempty(raw)
        value = "";
        return;
    end
    if ~isrow(raw)
        localThrowNonScalar(fieldName, raw);
    end
    value = string(raw);
    return;
end

if isstring(raw)
    if isempty(raw)
        value = "";
        return;
    end
    if ~isscalar(raw)
        localThrowNonScalar(fieldName, raw);
    end
    if ismissing(raw)
        value = "";
    else
        value = raw;
    end
    return;
end

if iscell(raw)
    if ~isscalar(raw)
        localThrowNonScalar(fieldName, raw);
    end
    value = localCanonicalValue(raw{1}, fieldName);
    return;
end

if isnumeric(raw) || islogical(raw) || isdatetime(raw) || isduration(raw)
    if ~isscalar(raw)
        localThrowNonScalar(fieldName, raw);
    end
    value = raw;
    return;
end

if iscategorical(raw)
    if ~isscalar(raw)
        localThrowNonScalar(fieldName, raw);
    end
    value = string(raw);
    if ismissing(value)
        value = "";
    end
    return;
end

error("sixgr:truth:UnsupportedRuntimeStatusFieldType", ...
    "Runtime status field '%s' has unsupported type %s.", ...
    fieldName, class(raw));
end

function localThrowNonScalar(fieldName, raw)
dims = size(raw);
shape = strjoin(string(dims), "x");
message = sprintf([ ...
    'Runtime status field ''%s'' has shape %s. A live status file represents ' ...
    'one measured snapshot; reduce the value at its producer or encode an ' ...
    'explicit scalar token.'], fieldName, char(shape));
error("sixgr:truth:RuntimeStatusFieldNotScalar", "%s", message);
end
