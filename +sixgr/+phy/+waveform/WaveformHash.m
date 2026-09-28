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
            sixgr.phy.waveform.WaveformHash.updateDigest(md,value);
            digest = sixgr.phy.waveform.WaveformHash.finishDigest(md);
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
            % Preserve the historical hash byte stream exactly:
            %   uint64 element count, all real double bytes, all imaginary
            %   double bytes.  Feed bounded pieces to Java instead of
            %   materializing a second waveform-sized byte array or passing
            %   an array larger than the Java bridge limit.  This is
            %   required for long 100 MHz element-domain observations.
            value = value(:);
            countBytes = typecast(uint64(numel(value)),"uint8");
            md = javaMethod("getInstance","java.security.MessageDigest","SHA-256");
            sixgr.phy.waveform.WaveformHash.updateDigest(md,countBytes);
            elementsPerChunk = 262144; % 2 MiB after conversion to double bytes.
            count = numel(value);
            for first = 1:elementsPerChunk:count
                last = min(count,first+elementsPerChunk-1);
                bytes = typecast(real(double(value(first:last))),"uint8");
                sixgr.phy.waveform.WaveformHash.updateDigest(md,bytes);
            end
            for first = 1:elementsPerChunk:count
                last = min(count,first+elementsPerChunk-1);
                bytes = typecast(imag(double(value(first:last))),"uint8");
                sixgr.phy.waveform.WaveformHash.updateDigest(md,bytes);
            end
            digest = sixgr.phy.waveform.WaveformHash.finishDigest(md);
        end
    end

    methods (Static, Access=private)
        function updateDigest(md,value)
            value = uint8(value(:));
            bytesPerChunk = 8*1024*1024;
            for first = 1:bytesPerChunk:numel(value)
                last = min(numel(value),first+bytesPerChunk-1);
                md.update(value(first:last));
            end
        end

        function digest = finishDigest(md)
            digest = lower(string(reshape( ...
                dec2hex(typecast(md.digest(),"uint8"),2).',1,[])));
        end
    end
end
