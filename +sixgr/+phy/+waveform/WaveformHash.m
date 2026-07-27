classdef WaveformHash
    %WAVEFORMHASH Stable SHA-256 helpers for waveform provenance.

    methods (Static)
        function digest = bytes(value)
            if isstring(value) || ischar(value)
                value = uint8(unicode2native(char(value),"UTF-8"));
            else
                value = uint8(value(:));
            end
            md = javaMethod("getInstance","java.security.MessageDigest","SHA-256");
            md.update(value);
            digest = lower(string(reshape(dec2hex(typecast(md.digest(),"uint8"),2).',1,[])));
        end

        function digest = file(path)
            path = char(string(path));
            if ~isfile(path)
                error("WAVEFORM:ArtifactMissing","Cannot hash missing file %s.",path);
            end
            fileObject = javaObject("java.io.File",path);
            inputStream = javaObject("java.io.FileInputStream",fileObject);
            channel = inputStream.getChannel();
            cleanup = onCleanup(@() channel.close());
            md = javaMethod("getInstance","java.security.MessageDigest","SHA-256");
            buffer = javaMethod("allocate","java.nio.ByteBuffer",1024*1024);
            while channel.read(buffer) > 0
                buffer.flip();
                md.update(buffer);
                buffer.clear();
            end
            clear cleanup
            digest = lower(string(reshape(dec2hex(typecast(md.digest(),"uint8"),2).',1,[])));
        end

        function digest = numeric(value)
            value = value(:);
            realValue = real(double(value));
            imaginaryValue = imag(double(value));
            countBytes = typecast(uint64(numel(value)),"uint8");
            realBytes = typecast(realValue,"uint8");
            imaginaryBytes = typecast(imaginaryValue,"uint8");
            payload = [countBytes(:); realBytes(:); imaginaryBytes(:)];
            digest = sixgr.phy.waveform.WaveformHash.bytes(payload);
        end
    end
end
