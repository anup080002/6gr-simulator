function val = structGet(s, path, defaultVal)
%STRUCTGET Safe nested get with default.
%
%   v = sixgr.util.structGet(cfg,"phy.carrier.NSizeGrid",66)

if nargin < 3
    defaultVal = [];
end

if ~(builtin("isstruct", s) && isscalar(s))
    val = defaultVal;
    return;
end

if isstring(path), path = char(path); end
if ~ischar(path) || isempty(path)
    val = defaultVal;
    return;
end

% Fast path: single-level field access without tokenization.
if ~contains(path, '.')
    if isfield(s, path)
        val = s.(path);
    else
        val = defaultVal;
    end
    return;
end

parts = localCachedPathParts(path);
if isempty(parts)
    val = defaultVal;
    return;
end

cur = s;
for i = 1:numel(parts)
    key = parts{i};
    if ~(builtin("isstruct", cur) && isscalar(cur) && isfield(cur, key))
        val = defaultVal;
        return;
    end
    cur = cur.(key);
end

val = cur;

end

function parts = localCachedPathParts(path)
persistent partsCache cacheKeys maxCacheEntries
if isempty(partsCache)
    partsCache = containers.Map("KeyType", "char", "ValueType", "any");
    cacheKeys = strings(0,1);
    maxCacheEntries = 512;
end

if isKey(partsCache, path)
    parts = partsCache(path);
    return;
end

parts = localSplitPath(path);
if isempty(parts)
    return;
end

% Keep cache bounded to avoid unbounded memory growth across long campaigns.
if numel(cacheKeys) >= maxCacheEntries
    oldKey = char(cacheKeys(1));
    if isKey(partsCache, oldKey)
        remove(partsCache, oldKey);
    end
    cacheKeys(1) = [];
end
partsCache(path) = parts;
cacheKeys(end+1,1) = string(path);
end

function parts = localSplitPath(path)
dotIdx = find(path == '.');
if isempty(dotIdx)
    parts = {path};
    return;
end

n = numel(dotIdx) + 1;
parts = cell(1, n);
st = 1;
for i = 1:numel(dotIdx)
    en = dotIdx(i) - 1;
    if en < st
        parts = {};
        return;
    end
    parts{i} = path(st:en);
    st = dotIdx(i) + 1;
end

if st > numel(path)
    parts = {};
    return;
end
parts{n} = path(st:end);
end
