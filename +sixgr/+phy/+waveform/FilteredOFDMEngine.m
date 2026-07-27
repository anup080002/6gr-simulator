classdef FilteredOFDMEngine
    %FILTEREDOFDMENGINE Explicit stateful FIR research waveform engine.
    methods (Static)
        function [output,state,metadata]=process(input,coefficients,state)
            coefficients=double(coefficients(:));
            if isempty(coefficients)||any(~isfinite(coefficients))
                error("WAVEFORM:UnsupportedResearchCandidate","FIR coefficients are invalid.");
            end
            if nargin<3||isempty(state),state=complex(zeros(numel(coefficients)-1,size(input,2)));end
            [output,state]=filter(coefficients,1,input,state,1);
            metadata=struct("GroupDelaySamples",(numel(coefficients)-1)/2, ...
                "CoefficientSHA256",sixgr.phy.waveform.WaveformHash.numeric(coefficients), ...
                "NormativeClaimAllowed",false);
        end
    end
end
