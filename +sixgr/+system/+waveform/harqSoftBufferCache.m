function varargout=harqSoftBufferCache(action,key,value)
% Shared storage boundary so the owning runtime can release discarded TBs.
persistent buffers
if isempty(buffers), buffers=containers.Map('KeyType','char','ValueType','any'); end
if nargin<2, key=""; end
key=char(string(key));
switch lower(string(action))
    case "get"
        if isKey(buffers,key), varargout={true,buffers(key)};
        else, varargout={false,[]}; end
    case "set"
        buffers(key)=value;
    case "clear"
        if isKey(buffers,key), remove(buffers,key); end
    case "reset"
        remove(buffers,keys(buffers));
    otherwise
        error('sixgr:system:WaveformReplay:BadHARQSoftBufferAction','Unknown HARQ cache action.');
end
end
