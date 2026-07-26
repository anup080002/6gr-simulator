classdef CFOAnalyticalSpec
%CFOANALYTICALSPEC Pure-math carrier-frequency-offset reference.
    methods(Static)
        function relativeHz=relative(txErrorHz,rxErrorHz,dopplerHz)
            values=double([txErrorHz rxErrorHz dopplerHz]);
            if any(~isfinite(values))
                error("RFOracle:CFOInvalid","CFO reference inputs must be finite.");
            end
            relativeHz=values(1)-values(2)+values(3);
        end
        function output=rotate(input,cfoHz,sampleRateHz,initialPhase)
            if any(~isfinite(input(:)))||~isfinite(cfoHz)|| ...
                    ~isfinite(sampleRateHz)||sampleRateHz<=0|| ...
                    ~isfinite(initialPhase)
                error("RFOracle:CFOInvalid","CFO reference inputs are invalid.");
            end
            n=(0:size(input,1)-1).';
            output=input.*cast(exp(1j*(initialPhase+ ...
                2*pi*cfoHz*n/sampleRateHz)),"like",input);
        end
    end
end
