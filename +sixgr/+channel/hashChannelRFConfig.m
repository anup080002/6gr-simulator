function hash = hashChannelRFConfig(value)
%HASHCHANNELRFCONFIG Deterministic SHA-256 hash for Channel/RF evidence.

try
    payload = jsonencode(localSanitize(value));
catch
    payload = char(string(class(value)) + ":" + string(numel(value)));
end
hash = localSHA256(uint8(unicode2native(char(payload), "UTF-8")));
end

function out = localSanitize(value)
if istable(value)
    out = table2struct(value);
elseif isstruct(value)
    out = value;
elseif isnumeric(value) || islogical(value)
    out = value;
elseif isstring(value) || ischar(value)
    out = char(string(value));
else
    out = char(string(class(value)));
end
end

function hash = localSHA256(bytes)
md = java.security.MessageDigest.getInstance("SHA-256");
md.update(bytes(:));
raw = typecast(md.digest(), "uint8");
hash = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
end
