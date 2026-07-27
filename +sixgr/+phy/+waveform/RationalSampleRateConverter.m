classdef RationalSampleRateConverter
    %RATIONALSAMPLERATECONVERTER Exact-ratio state-explicit conversion.
    methods (Static)
        function [output,metadata]=convert(input,inputRate,outputRate)
            [p,q]=rat(double(outputRate)/double(inputRate),1e-12);
            if abs(p/q-double(outputRate)/double(inputRate))>1e-12 || ...
                    p>64 || q>64
                error("WAVEFORM:MultiNumerologyClockMismatch", ...
                    "Sample clocks do not have a supported exact rational ratio.");
            end
            if p==q
                output=input; backend="identity";
            elseif exist("resample","file")==2
                output=resample(input,p,q);backend="polyphase_resample";
            else
                error("WAVEFORM:MultiNumerologyClockMismatch", ...
                    "Exact rational conversion requires Signal Processing Toolbox.");
            end
            metadata=struct("P",p,"Q",q,"InputRate_Hz",double(inputRate), ...
                "OutputRate_Hz",double(outputRate),"Backend",backend);
        end
    end
end
