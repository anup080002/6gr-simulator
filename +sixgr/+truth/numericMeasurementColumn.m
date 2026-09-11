function values=numericMeasurementColumn(raw,field)
%NUMERICMEASUREMENTCOLUMN Decode scalar CSV measurements without inventing data.
% Empty optional cells remain NaN. Text is parsed as numbers, never character
% codes. Nonempty malformed tokens/vectors fail rather than disappearing from
% a measurement aggregate. This does not validate a metric's physical range.
if nargin<2, field="measurement"; end
if isnumeric(raw) || islogical(raw)
    assert(isreal(raw) && (isvector(raw) || isempty(raw)), ...
        'sixgr:truth:InvalidNumericMeasurementColumn','%s requires one real scalar per row.',field);
    values=double(raw(:));
    return;
end
if ischar(raw), raw=string(raw); end
assert(iscell(raw) || isstring(raw), ...
    'sixgr:truth:InvalidNumericMeasurementColumn','Unsupported measurement representation for %s.',field);
values=nan(numel(raw),1);
for k=1:numel(raw)
    if iscell(raw), value=raw{k}; else, value=raw(k); end
    if isempty(value), continue; end
    if isnumeric(value) || islogical(value)
        valid=isreal(value) && isscalar(value);
        if valid, values(k)=double(value); end
    elseif ischar(value) || isstring(value)
        token=strtrim(string(value));
        valid=isscalar(token);
        if valid && (ismissing(token) || strlength(token)==0), continue; end
        if valid
            if localExplicitMissingToken(token)
                continue;
            end
            number=str2double(token);
            valid=isreal(number) && (~isnan(number) || strcmpi(token,"NaN"));
            if valid, values(k)=number; end
        end
    else
        valid=false;
    end
    assert(valid,'sixgr:truth:InvalidNumericMeasurementColumn', ...
        '%s row %d must be numeric or explicitly missing; do not hide invalid evidence.',field,k);
end
end

function tf=localExplicitMissingToken(token)
% These values are canonical schema-preservation sentinels emitted by the
% active runtime. They mean that no numeric observation exists; they are not
% measurements and therefore decode to NaN for numeric aggregation. Keep the
% allow-list synchronized with canonicalizeLLSLiveSignalChainTable rather
% than accepting arbitrary prose as missing evidence.
normalized=lower(strtrim(string(token)));
prefixes=["not_recorded_by_active_", "not_emitted_by_active_", ...
    "field_not_emitted_by_active_", "not_applicable_for_active_"];
tf=isscalar(normalized) && (normalized=="not_applicable" || ...
    any(startsWith(normalized,prefixes)));
end
