classdef FrequencyDomainShapingEngine
    %FREQUENCYDOMAINSHAPINGENGINE Versioned invertible spectral taper study.
    methods (Static)
        function [output,state]=apply(input,weights)
            weights=double(weights(:));
            if numel(weights)~=size(input,1)||any(~isfinite(weights))||any(weights<=0)
                error("WAVEFORM:UnsupportedResearchCandidate","Shaping weights must be finite and invertible.");
            end
            output=input.*weights;
            state=struct("Weights",weights,"Digest", ...
                sixgr.phy.waveform.WaveformHash.numeric(weights), ...
                "NormativeClaimAllowed",false);
        end
        function output=invert(input,state)
            output=input./state.Weights;
        end
    end
end
