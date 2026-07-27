classdef FDSSStudyEngine
    %FDSSSTUDYENGINE Bounded frequency-domain spectral shaping definition.
    methods (Static)
        function [output,state]=apply(input,rolloff)
            m=size(input,1); n=(0:m-1).';
            weights=1-double(rolloff)*0.5*(1-cos(2*pi*(n+0.5)/m));
            [output,state]=sixgr.phy.waveform.FrequencyDomainShapingEngine.apply(input,weights);
            state.Engine="fdss_cosine_v1";
            state.Rolloff=double(rolloff);
        end
    end
end
