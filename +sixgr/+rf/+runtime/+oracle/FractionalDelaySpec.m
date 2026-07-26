classdef FractionalDelaySpec
%FRACTIONALDELAYSPEC Windowed-sinc fractional-delay reference.
    methods(Static)
        function output=apply(input,delaySamples,halfLength)
            if nargin<3, halfLength=32; end
            if any(~isfinite(input(:)))||~isfinite(delaySamples)|| ...
                    halfLength<4||halfLength~=round(halfLength)
                error("RFOracle:FractionalDelayInvalid", ...
                    "Fractional-delay reference inputs are invalid.");
            end
            indices=(-halfLength:halfLength).';
            kernel=sinc(indices-delaySamples).* ...
                (0.54+0.46*cos(pi*indices/(halfLength+1)));
            kernel=kernel/sum(kernel);
            fullOutput=conv(double(input),kernel,"full");
            start=halfLength+1;
            output=fullOutput(start:start+size(input,1)-1,:);
            output=cast(output,"like",input);
        end
    end
end
