function token = serializeFiniteNumericIdentifierSet(values)
%SERIALIZEFINITENUMERICIDENTIFIERSET Serialize applicable numeric identities.
%   Non-finite values represent non-applicable identities and are omitted.
%   This is intentionally not a missing-value imputation path: no identifier
%   is invented when a row (for example CSI UCI) has no HARQ process.

if nargin < 1 || isempty(values)
    token = "";
    return;
end

if ~(isnumeric(values) || islogical(values))
    error("sixgr:truth:IdentifierSetType", ...
        "Identifier sets must be numeric or logical runtime identities.");
end

values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end

parts = strings(1, numel(values));
for idx = 1:numel(values)
    parts(idx) = string(sprintf("%.15g", values(idx)));
end
token = strjoin(parts, "|");
end
