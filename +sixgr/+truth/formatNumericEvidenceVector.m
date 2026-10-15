function token = formatNumericEvidenceVector(values)
%FORMATNUMERICEVIDENCEVECTOR Retain positional identity and double precision.
% Missing layer/candidate values must not shift the positions that follow.
if ischar(values) || isstring(values)
    token = string(values);
    assert(isscalar(token), 'sixgr:truth:InvalidNumericEvidenceVector', ...
        'An already serialized evidence vector must be one text scalar.');
    return;
end
assert((isnumeric(values) || islogical(values)) && isreal(values) && ...
    (isvector(values) || isempty(values)), ...
    'sixgr:truth:InvalidNumericEvidenceVector', ...
    'Evidence must be a real vector; do not silently flatten matrices.');
values = double(values(:).');
parts = strings(1,numel(values));
for k = 1:numel(values)
    parts(k) = string(sprintf('%.17g',values(k)));
end
token = join(parts,'|');
if isempty(values), token = ""; end
end
