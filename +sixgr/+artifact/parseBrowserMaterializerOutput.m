function result = parseBrowserMaterializerOutput(status, raw)
%PARSEBROWSERMATERIALIZEROUTPUT Keep coverage and diagnostics on CLI failure.
% The strict publisher writes one JSON object followed by human-readable
% failure details. Decode the balanced object, not the trailing diagnostic.
% Exit status and the complete output remain authoritative and unchanged.
text = strtrim(string(raw));
result = struct("Status", double(status), "CreatedCount", 0, ...
    "MissingTableCount", NaN, "MissingChartCount", NaN, ...
    "PayloadText", text);
if ~isscalar(text)
    return;
end
chars = char(text);
starts = strfind(chars, '{');
if isempty(starts)
    return;
end
first = starts(1);
depth = 0; quoted = false; escaped = false;
for k = first:numel(chars)
    c = chars(k);
    if quoted
        if escaped
            escaped = false;
        elseif c == char(92)
            escaped = true;
        elseif c == '"'
            quoted = false;
        end
    elseif c == '"'
        quoted = true;
    elseif c == '{'
        depth = depth + 1;
    elseif c == '}'
        depth = depth - 1;
        if depth == 0
            try
                payload = jsondecode(chars(first:k));
            catch
                return;
            end
            if ~(isstruct(payload) && isscalar(payload))
                return;
            end
            result.CreatedCount = localCount(payload, 'created_count', 0);
            result.MissingTableCount = localCount(payload, 'tables_missing', NaN);
            result.MissingChartCount = localCount(payload, 'charts_missing', NaN);
            return;
        end
    end
end
end

function value = localCount(payload, field, default)
value = default;
if ~isfield(payload, field)
    return;
end
candidate = payload.(field);
% Null, strings, arrays, negative counts and fractional counts cannot prove
% coverage. In particular a malformed zero must never become a PASS.
if isnumeric(candidate) && isscalar(candidate) && isreal(candidate) && ...
        isfinite(candidate) && candidate >= 0 && candidate == fix(candidate)
    value = double(candidate);
end
end
