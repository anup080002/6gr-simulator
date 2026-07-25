function values = pdschVectorDecodeIntegers(text)
%PDSCHVECTORDECODEINTEGERS Decode pipe/range frozen-vector notation.

text = strtrim(string(text));
if ismissing(text) || strlength(text) == 0
    values = zeros(1, 0);
    return;
end
tokens = split(text, "|");
values = zeros(1, 0);
for i = 1:numel(tokens)
    token = strtrim(tokens(i));
    range = regexp(char(token), '^(-?\d+)-(-?\d+)$', ...
        'tokens', 'once');
    if ~isempty(range)
        first = str2double(range{1});
        last = str2double(range{2});
        values = [values first:last]; %#ok<AGROW>
    else
        value = str2double(token);
        if ~isfinite(value)
            error("sixgr:test:InvalidPDSCHVectorSet", ...
                "Malformed vector-set token '%s'.", tokens(i));
        end
        values(end + 1) = value; %#ok<AGROW>
    end
end
assert(all(isfinite(values)) && all(values == floor(values)), ...
    "Frozen PDSCH vector contains a noninteger set value.");
values = double(values(:).');
end
