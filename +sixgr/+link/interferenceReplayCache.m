function varargout = interferenceReplayCache(action, varargin)
%INTERFERENCEREPLAYCACHE Process-local store for coupled waveform interferer state.

persistent cacheMap
if isempty(cacheMap)
    cacheMap = containers.Map("KeyType", "char", "ValueType", "any");
end

action = lower(strtrim(string(action)));
switch action
    case "put"
        key = char(string(varargin{1}));
        payload = varargin{2};
        cacheMap(key) = payload;
        if nargout >= 1
            varargout{1} = key;
        end
    case "get"
        key = char(string(varargin{1}));
        hit = isKey(cacheMap, key);
        payload = struct();
        if hit
            payload = cacheMap(key);
        end
        if nargout >= 1
            varargout{1} = hit;
        end
        if nargout >= 2
            varargout{2} = payload;
        end
    case "remove"
        key = char(string(varargin{1}));
        if isKey(cacheMap, key)
            remove(cacheMap, key);
        end
    case "clear"
        cacheMap = containers.Map("KeyType", "char", "ValueType", "any");
    otherwise
        error("sixgr:link:interferenceReplayCache:UnknownAction", ...
            "Unsupported interference replay cache action '%s'.", char(action));
end
end
