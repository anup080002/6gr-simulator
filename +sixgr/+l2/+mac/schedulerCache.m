function varargout = schedulerCache(action, kind, key, varargin)
% sixgr.l2.mac.schedulerCache
% Shared cache helper for scheduler hot paths.

persistent tbsCache nreCache tbsOrder nreOrder tbsLimit nreLimit

if nargin < 3
    error('sixgr:schedulerCache:InvalidInput', ...
        'action, kind, and key are required.');
end

action = lower(char(string(action)));
kind = upper(char(string(kind)));
key = char(string(key));

if isempty(tbsLimit)
    tbsLimit = localCacheLimit("SIXGR_SCHEDULER_TBS_CACHE_MAX", 4096);
end
if isempty(nreLimit)
    nreLimit = localCacheLimit("SIXGR_SCHEDULER_NRE_CACHE_MAX", 2048);
end

switch kind
    case 'TBS'
        if isempty(tbsCache)
            tbsCache = containers.Map('KeyType','char','ValueType','any');
        end
        if isempty(tbsOrder)
            tbsOrder = {};
        end
        map = tbsCache;
        order = tbsOrder;
        maxEntries = tbsLimit;
    case 'NRE'
        if isempty(nreCache)
            nreCache = containers.Map('KeyType','char','ValueType','double');
        end
        if isempty(nreOrder)
            nreOrder = {};
        end
        map = nreCache;
        order = nreOrder;
        maxEntries = nreLimit;
    otherwise
        error('sixgr:schedulerCache:UnknownKind', ...
            'Unknown scheduler cache kind ''%s''.', kind);
end

switch action
    case 'get'
        hit = isKey(map, key);
        if hit
            value = map(key);
            order = localTouchOrder(order, key);
            switch kind
                case 'TBS'
                    tbsOrder = order;
                case 'NRE'
                    nreOrder = order;
            end
        else
            value = [];
        end
        varargout = {hit, value};
    case 'set'
        if isempty(varargin)
            error('sixgr:schedulerCache:MissingValue', ...
                'schedulerCache set requires a value.');
        end
        [map, order] = localSetBounded(map, order, key, varargin{1}, maxEntries);
        switch kind
            case 'TBS'
                tbsCache = map;
                tbsOrder = order;
            case 'NRE'
                nreCache = map;
                nreOrder = order;
        end
        if nargout > 0
            varargout = {true};
        end
    case 'reset'
        switch kind
            case 'TBS'
                tbsCache = containers.Map('KeyType','char','ValueType','any');
                tbsOrder = {};
            case 'NRE'
                nreCache = containers.Map('KeyType','char','ValueType','double');
                nreOrder = {};
        end
        if nargout > 0
            varargout = {true};
        end
    otherwise
        error('sixgr:schedulerCache:UnknownAction', ...
            'Unknown scheduler cache action ''%s''.', action);
end
end

function limit = localCacheLimit(envName, defaultValue)
raw = str2double(getenv(char(envName)));
if isfinite(raw) && raw >= 32
    limit = round(raw);
else
    limit = defaultValue;
end
end

function [map, order] = localSetBounded(map, order, key, value, maxEntries)
order = localTouchOrder(order, key);
map(key) = value;
while map.Count > maxEntries
    if isempty(order)
        allKeys = keys(map);
        order = allKeys(:).';
    end
    evictKey = order{1};
    order(1) = [];
    if isKey(map, evictKey)
        remove(map, evictKey);
    end
end
end

function order = localTouchOrder(order, key)
if isempty(order)
    order = {key};
    return;
end
matches = strcmp(order, key);
order(matches) = [];
order{end + 1} = key;
end
