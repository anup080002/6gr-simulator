classdef DigitalUpconverter
    %DIGITALUPCONVERTER Phase-continuous complex NCO.
    methods (Static)
        function [output,state,metadata]=process(input,frequencyHz,sampleRateHz,state)
            if nargin<4 || isempty(state)
                state=sixgr.phy.waveform.OFDMStreamState(sampleRateHz,0);
            end
            if abs(double(frequencyHz))>=double(sampleRateHz)/2
                error("WAVEFORM:CarrierFrequencyOverlap", ...
                    "Digital frequency shift must lie strictly inside Nyquist.");
            end
            start=state.NextSampleIndex;
            index=start+(0:size(input,1)-1).';
            phase=state.NCOPhase_rad+2*pi*double(frequencyHz)*(0:size(input,1)-1).'/double(sampleRateHz);
            output=input.*exp(1j*phase);
            nextPhase=state.NCOPhase_rad+2*pi*double(frequencyHz)*size(input,1)/double(sampleRateHz);
            state.advance(size(input,1),sampleRateHz,nextPhase);
            metadata=struct("StartSample",start,"EndSample",state.NextSampleIndex-1, ...
                "FrequencyOffset_Hz",double(frequencyHz), ...
                "InitialPhase_rad",phase(1),"FinalStatePhase_rad",state.NCOPhase_rad, ...
                "SampleIndices",index);
        end
    end
end
