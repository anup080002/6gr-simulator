classdef DigitalDownconverter
    %DIGITALDOWNCONVERTER Phase-continuous inverse NCO.
    methods (Static)
        function [output,state,metadata]=process(input,frequencyHz,sampleRateHz,state)
            [output,state,metadata]=sixgr.phy.waveform.DigitalUpconverter.process( ...
                input,-double(frequencyHz),sampleRateHz,state);
        end
    end
end
