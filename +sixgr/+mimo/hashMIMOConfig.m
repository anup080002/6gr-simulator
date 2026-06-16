function hash = hashMIMOConfig(value)
%HASHMIMOCONFIG Stable SHA-256 hash for MIMO config/evidence metadata.

try
    txt = jsonencode(localSanitize(value));
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(uint8(unicode2native(char(txt), "UTF-8")));
    digest = typecast(md.digest(), "uint8");
    hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
catch ME
    error("sixgr:mimo:HashUnavailable", "Unable to hash MIMO config/evidence: %s", ME.message);
end
end

function out = localSanitize(in)
if istable(in)
    out = table2struct(in);
elseif isstruct(in)
    out = in;
    f = fieldnames(out);
    for i = 1:numel(f)
        out.(f{i}) = localSanitize(out.(f{i}));
    end
elseif isstring(in)
    out = cellstr(in);
elseif iscell(in)
    out = cellfun(@localSanitize, in, "UniformOutput", false);
elseif isnumeric(in) || islogical(in) || ischar(in)
    out = in;
else
    out = string(in);
end
end
