classdef IQWidelyLinearSpec
%IQWIDELYLINEARSPEC Pure-math IQ alpha/beta reference.
    methods(Static)
        function result=coefficients(gainImbalance_dB,phaseImbalance_deg)
            if ~isfinite(gainImbalance_dB)||~isfinite(phaseImbalance_deg)
                error("RFOracle:IQInvalid","IQ reference inputs must be finite.");
            end
            gain=10^(double(gainImbalance_dB)/20);
            phase=double(phaseImbalance_deg)*pi/180;
            alpha=0.5*(1+gain*exp(-1j*phase));
            beta=0.5*(1-gain*exp(1j*phase));
            result=struct("Alpha",alpha,"Beta",beta, ...
                "IRR_dB",20*log10(abs(alpha)/max(abs(beta),realmin)));
        end
        function output=apply(input,alpha,beta,dcOffset)
            output=alpha.*input+beta.*conj(input)+dcOffset;
        end
    end
end
