classdef QuantizerSpec
%QUANTIZERSPEC Pure-math signed-midtread quantizer reference.
    methods(Static)
        function [output,code,clipped]=signedMidtread(input,bits,fullScale)
            if bits~=round(bits)||bits<2||bits>24||fullScale<=0|| ...
                    any(~isfinite([input(:);bits;fullScale]))
                error("RFOracle:QuantizerInvalid", ...
                    "Quantizer reference inputs are invalid.");
            end
            maxCode=2^(bits-1)-1;
            clipped=abs(input)>=fullScale;
            limited=min(max(input,-fullScale),fullScale);
            code=round(limited/fullScale*maxCode);
            code=min(max(code,-maxCode),maxCode);
            output=code/maxCode*fullScale;
        end
    end
end
