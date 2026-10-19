function mask=measurementValuePresent(col)
% Availability is a real value, never a producer's missing-data sentinel.
if isnumeric(col) || islogical(col)
    mask=all(isfinite(double(col)),2); return;
end
try, value=lower(strtrim(string(col))); catch, mask=false(size(col,1),1); return; end
mask=~ismissing(value) & ~ismember(value,["","nan","<missing>","missing","unavailable", ...
    "not_available","not_applicable","none_recorded"]);
for prefix=["not_recorded_","not_emitted_","field_not_emitted_","not_applicable_","unavailable_"]
    mask=mask & ~startsWith(value,prefix);
end
mask=all(mask,2);
end
