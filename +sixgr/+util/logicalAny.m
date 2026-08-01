function tf = logicalAny(value)
%LOGICALANY Reduce explicit scalar/vector flag evidence to one boolean.

if isempty(value)
    tf = false;
elseif islogical(value)
    tf = any(value(:));
elseif isnumeric(value)
    numeric = double(value(:));
    tf = any(isfinite(numeric) & numeric ~= 0);
elseif ischar(value) || isstring(value) || iscategorical(value)
    token = lower(strtrim(string(value(:))));
    tf = any(ismember(token,["true","1","yes","on","pass","passed","retransmission","retx"]));
elseif iscell(value)
    tf = any(cellfun(@sixgr.util.logicalAny,value(:)));
else
    tf = false;
end
tf = logical(tf);
end
