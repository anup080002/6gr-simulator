function value = sha256File(filePath)
%SHA256FILE Return the lowercase SHA-256 digest of one file byte stream.
%
% The implementation streams through Java FileChannel rather than loading
% large waveform/result artifacts into MATLAB memory.  ByteBuffer is used
% because passing a MATLAB numeric buffer into Java copies the array and can
% silently hash zeros instead of the bytes read from disk.

arguments
    filePath {mustBeTextScalar}
end

filePath = char(filePath);
if exist(filePath, "file") ~= 2
    error("sixgr:util:sha256File:MissingFile", ...
        "SHA-256 source file does not exist: %s.", filePath);
end

stream = java.io.FileInputStream(java.io.File(filePath));
cleanupStream = onCleanup(@() stream.close()); %#ok<NASGU>
channel = stream.getChannel();
digest = java.security.MessageDigest.getInstance("SHA-256");
buffer = java.nio.ByteBuffer.allocate(1024 * 1024);
while channel.read(buffer) > 0
    buffer.flip();
    digest.update(buffer);
    buffer.clear();
end
value = lower(string(reshape(dec2hex( ...
    typecast(digest.digest(), "uint8"), 2).', 1, [])));
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:util:sha256File:BadPath", ...
        "filePath must be a character vector or string scalar.");
end
end
