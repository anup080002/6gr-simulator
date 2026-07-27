classdef WaveformChunk
    %WAVEFORMCHUNK Immutable sample block with absolute indices.
    properties (SetAccess=immutable)
        Samples
        StartSample double
        EndSample double
        SHA256 string
    end
    methods
        function obj=WaveformChunk(samples,startSample)
            obj.Samples=samples;
            obj.StartSample=double(startSample);
            obj.EndSample=obj.StartSample+size(samples,1)-1;
            obj.SHA256=sixgr.phy.waveform.WaveformHash.numeric(samples);
        end
    end
end
