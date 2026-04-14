function varargout = schedulerCache(action, kind, key, varargin)
% sixgr.l2.mac.schedulerCache
% Shared cache helper for scheduler hot paths.

persistent tbsCache nreCache

if nargin < 3
    error('sixgr:schedulerCache:InvalidInput', ...
        'action, kind, and key are required.');
end

action = lower(char(string(action)));
kind = upper(char(string(kind)));
key = char(string(key));

switch kind
    case 'TBS'
        if isempty(tbsCache)
            tbsCache = containers.Map('KeyType','char','ValueType','any');
        end
        map = tbsCache;
    case 'NRE'
        if isempty(nreCache)
            nreCache = containers.Map('KeyType','char','ValueType','double');
        end
        map = nreCache;
    otherwise
        error('sixgr:schedulerCache:UnknownKind', ...
            'Unknown scheduler cache kind ''%s''.', kind);
end

switch action
    case 'get'
        hit = isKey(map, key);
        if hit
            value = map(key);
        else
            value = [];
        end
        varargout = {hit, value};
    case 'set'
        if isempty(varargin)
            error('sixgr:schedulerCache:MissingValue', ...
                'schedulerCache set requires a value.');
        end
        map(key) = varargin{1};
        switch kind
            case 'TBS'
                tbsCache = map;
            case 'NRE'
                nreCache = map;
        end
        if nargout > 0
            varargout = {true};
        end
    case 'reset'
        switch kind
            case 'TBS'
                tbsCache = containers.Map('KeyType','char','ValueType','any');
            case 'NRE'
                nreCache = containers.Map('KeyType','char','ValueType','double');
        end
        if nargout > 0
            varargout = {true};
        end
    otherwise
        error('sixgr:schedulerCache:UnknownAction', ...
            'Unknown scheduler cache action ''%s''.', action);
end
end
