function childRunID = deriveChildRunID(parentRunID, relation, ordinal, label)
%DERIVECHILDRUNID Build a deterministic, unique nested-execution RunID.

% A nested waveform execution owns a distinct immutable identity while
% retaining its relationship to the parent matrix/repeat execution.  The
% ordinal prevents labels that normalize to the same token from colliding.

parentRunID = strtrim(string(parentRunID));
relation = strtrim(lower(string(relation)));
label = strtrim(lower(string(label)));
if ~isscalar(parentRunID) || strlength(parentRunID) == 0
    error("sixgr:runtime:ParentRunIdentityRequired", ...
        "A nested waveform execution requires a non-empty parent RunID.");
end
if ~isscalar(relation) || strlength(relation) == 0
    error("sixgr:runtime:ChildRunRelationRequired", ...
        "A nested waveform execution requires a non-empty relation token.");
end
if ~(isnumeric(ordinal) && isscalar(ordinal) && isfinite(ordinal) && ...
        ordinal >= 1 && ordinal == floor(ordinal))
    error("sixgr:runtime:ChildRunOrdinalInvalid", ...
        "A nested waveform execution ordinal must be a positive integer.");
end
if ~isscalar(label) || strlength(label) == 0
    error("sixgr:runtime:ChildRunLabelRequired", ...
        "A nested waveform execution requires a non-empty label.");
end

relation = localToken(relation, "child");
label = localToken(label, "point");
childRunID = parentRunID + "__" + relation + "_" + ...
    compose("%03d", double(ordinal)) + "_" + label;
end

function token = localToken(value, fallback)
token = lower(regexprep(strtrim(string(value)), '[^a-zA-Z0-9_-]+', '_'));
token = regexprep(token, '^_+|_+$', '');
if strlength(token) == 0
    token = string(fallback);
end
end
