function trace = resolveInterferencePrecodingTrace(replay)
%RESOLVEINTERFERENCEPRECODINGTRACE Normalize measured interferer metadata.
% Shared-slot synthesis may expose either an already-aggregated scalar or
% one count/token per physical contributor. Canonical trial rows require
% one scalar count and one deterministic token set. Invalid evidence is
% rejected instead of truncated or replaced with a display fallback.

trace = struct( ...
    "InterfererBeamformingAppliedCount", localCount(replay, ...
        "InterfererBeamformingAppliedCount"), ...
    "InterfererExplicitBeamWeightCount", localCount(replay, ...
        "InterfererExplicitBeamWeightCount"), ...
    "InterfererTransformPrecodingCount", localCount(replay, ...
        "InterfererTransformPrecodingCount"), ...
    "InterfererPrecoderSourceSet", localTokenSet(replay, ...
        "InterfererPrecoderSourceSet"), ...
    "InterfererPrecodingModeSet", localTokenSet(replay, ...
        "InterfererPrecodingModeSet"), ...
    "InterfererBeamIndexSetSummary", localTokenSet(replay, ...
        "InterfererBeamIndexSetSummary"));
end

function count = localCount(replay, fieldName)
value = sixgr.util.structGet(replay, fieldName, 0);
if isempty(value)
    count = 0;
    return;
end
if ~(isnumeric(value) || islogical(value))
    error("sixgr:link:InvalidInterferenceCountEvidence", ...
        "Runtime field %s must contain numeric contributor counts.", fieldName);
end
values = double(value(:));
if any(~isfinite(values)) || any(values < 0) || any(values ~= round(values))
    error("sixgr:link:InvalidInterferenceCountEvidence", ...
        "Runtime field %s contains a nonfinite, negative, or noninteger contributor count.", ...
        fieldName);
end
count = sum(values);
end

function token = localTokenSet(replay, fieldName)
values = string(sixgr.util.structGet(replay, fieldName, ""));
values = strip(values(~ismissing(values)));
values = values(strlength(values) > 0);
if isempty(values)
    token = "";
    return;
end

parts = strings(0, 1);
for value = reshape(values, 1, [])
    splitValues = strip(split(value, "|"));
    splitValues = splitValues(strlength(splitValues) > 0);
    parts = [parts; splitValues(:)]; %#ok<AGROW>
end
token = join(unique(parts, "stable"), "|");
end
