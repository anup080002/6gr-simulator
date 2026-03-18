function s = structSet(s, path, value)
%STRUCTSET Safe nested set, creating intermediate structs.
%
%   cfg = sixgr.util.structSet(cfg,"phy.carrier.NSizeGrid",66)

if ~(builtin("isstruct", s) && isscalar(s))
    s = struct();
end

if isstring(path), path = char(path); end
if ~ischar(path) || isempty(path)
    error("sixgr:util:structSet:BadPath","path must be a non-empty char/string.");
end

parts = strsplit(path, ".");
s = localSet(s, parts, value);

end

function out = localSet(in, parts, value)
out = in;
k = parts{1};

if numel(parts) == 1
    out.(k) = value;
    return;
end

if ~isfield(out, k) || ~(builtin("isstruct", out.(k)) && isscalar(out.(k)))
    out.(k) = struct();
end

out.(k) = localSet(out.(k), parts(2:end), value);

end
