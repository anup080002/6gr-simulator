classdef RappSalehSpec
%RAPPSALEHSPEC Pure-math memoryless PA references.
    methods(Static)
        function output=rapp(input,saturation,smoothness)
            if saturation<=0||smoothness<=0|| ...
                    any(~isfinite([input(:);saturation;smoothness]))
                error("RFOracle:PAInvalid","Rapp reference inputs are invalid.");
            end
            output=input./(1+(abs(input)./saturation).^(2*smoothness)).^ ...
                (1/(2*smoothness));
        end
        function output=saleh(input,alphaAM,betaAM,alphaPM,betaPM)
            values=[input(:);alphaAM;betaAM;alphaPM;betaPM];
            if any(~isfinite(values))||betaAM<0||betaPM<0
                error("RFOracle:PAInvalid","Saleh reference inputs are invalid.");
            end
            amplitude=abs(input);
            am=alphaAM.*amplitude./(1+betaAM.*amplitude.^2);
            pm=alphaPM.*amplitude.^2./(1+betaPM.*amplitude.^2);
            output=am.*exp(1j*(angle(input)+pm));
        end
    end
end
