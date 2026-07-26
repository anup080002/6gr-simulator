classdef FriisNoiseFigureSpec
%FRIISNOISEFIGURESPEC Pure-math Friis cascade reference.
    methods(Static)
        function result=cascade(gains_dB,noiseFigures_dB,bandwidthHz,temperatureK)
            gains=10.^(double(gains_dB(:))/10);
            factors=10.^(double(noiseFigures_dB(:))/10);
            if numel(gains)~=numel(factors)||isempty(gains)|| ...
                    any(~isfinite([gains;factors]))||any(gains<=0)|| ...
                    any(factors<1)||bandwidthHz<=0||temperatureK<=0
                error("RFOracle:NoiseFigureInvalid", ...
                    "Friis reference inputs are invalid.");
            end
            total=factors(1);
            cumulative=1;
            for k=2:numel(factors)
                cumulative=cumulative*gains(k-1);
                total=total+(factors(k)-1)/cumulative;
            end
            nf=10*log10(total);
            noise=-174+10*log10(bandwidthHz)+nf+ ...
                10*log10(temperatureK/290);
            result=struct("CascadeNF_dB",nf,"NoisePower_dBm",noise);
        end
    end
end
