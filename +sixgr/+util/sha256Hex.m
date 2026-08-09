function hex = sha256Hex(data)
%SHA256HEX Return a real SHA-256 hex digest for byte-like data.

bytes = localBytes(data);
digest = [];

if usejava("jvm")
    try
        md = javaMethod("getInstance", "java.security.MessageDigest", "SHA-256");
        % Java byte[] is signed.  A direct MATLAB uint8 conversion fails
        % for source evidence containing octets above 127 on newer MATLAB
        % releases.  Preserve all bits and pass the corresponding int8
        % representation to MessageDigest.
        javaBytes = typecast(uint8(bytes(:)), "int8");
        md.update(javaBytes);
        digest = typecast(int8(md.digest()), "uint8");
    catch
        digest = [];
    end
end

if isempty(digest) && ispc
    try
        alg = System.Security.Cryptography.SHA256.Create();
        digest = uint8(alg.ComputeHash(bytes(:).'));
    catch
        digest = [];
    end
end

if isempty(digest)
    error("sixgr:util:SHA256Unavailable", ...
        "Real SHA-256 hashing requires Java or Windows .NET cryptography support.");
end

hex = lower(string(reshape(dec2hex(uint8(digest), 2).', 1, [])));
end

function bytes = localBytes(data)
if isempty(data)
    bytes = uint8([]);
elseif isstring(data)
    bytes = uint8(unicode2native(char(strjoin(data(:), newline)), "UTF-8"));
elseif ischar(data)
    bytes = uint8(unicode2native(data, "UTF-8"));
elseif isnumeric(data) || islogical(data)
    bytes = uint8(data(:));
else
    try
        bytes = uint8(unicode2native(char(jsonencode(data)), "UTF-8"));
    catch
        bytes = uint8(unicode2native(char(string(data)), "UTF-8"));
    end
end
end
