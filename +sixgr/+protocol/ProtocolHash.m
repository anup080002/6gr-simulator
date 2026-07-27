classdef ProtocolHash
    %PROTOCOLHASH Deterministic SHA-256 helpers for protocol evidence.

    methods (Static)
        function value = bytes(data)
            if isstring(data) || ischar(data)
                data = uint8(unicode2native(char(string(data)), "UTF-8"));
            elseif ~isa(data, "uint8")
                data = uint8(data);
            end
            digest = java.security.MessageDigest.getInstance("SHA-256");
            digest.update(typecast(data(:), "int8"));
            value = lower(string(reshape(dec2hex( ...
                typecast(digest.digest(), "uint8"), 2).', 1, [])));
        end

        function value = file(path)
            path = string(path);
            if ~isfile(path)
                error("sixgr:protocol:MissingHashSource", ...
                    "SHA-256 source file does not exist: %s.", path);
            end
            stream = java.io.FileInputStream(java.io.File(char(path)));
            cleanup = onCleanup(@() stream.close()); %#ok<NASGU>
            digest = java.security.MessageDigest.getInstance("SHA-256");
            % Use a Java ByteBuffer so FileChannel mutates the buffer by
            % reference. Passing a MATLAB numeric array to read(buffer)
            % hashes zeros because MATLAB arrays are copied into Java.
            channel = stream.getChannel();
            buffer = java.nio.ByteBuffer.allocate(1024 * 1024);
            while channel.read(buffer) > 0
                buffer.flip();
                digest.update(buffer);
                buffer.clear();
            end
            value = lower(string(reshape(dec2hex( ...
                typecast(digest.digest(), "uint8"), 2).', 1, [])));
        end
    end
end
