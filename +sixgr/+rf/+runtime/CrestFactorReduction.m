classdef CrestFactorReduction
%CRESTFACTORREDUCTION Bounded iterative magnitude clipping with evidence.

    methods(Static)
        function [y,evidence]=apply(x,targetPAPR_dB,iterations)
            if isempty(x)||any(~isfinite(x(:)))||~isfinite(targetPAPR_dB)|| ...
                    targetPAPR_dB<0||iterations<1||iterations~=round(iterations)
                error("RF:UnsupportedCombination","CFR configuration is invalid.");
            end
            y=x;
            before=sixgr.rf.runtime.CrestFactorReduction.papr(x);
            for k=1:iterations
                rmsValue=sqrt(mean(abs(double(y(:))).^2));
                limit=rmsValue*10^(targetPAPR_dB/20);
                magnitude=abs(y);
                mask=magnitude>limit;
                y(mask)=limit.*y(mask)./magnitude(mask);
            end
            evidence=struct("PAPRBefore_dB",before, ...
                "PAPRAfter_dB",sixgr.rf.runtime.CrestFactorReduction.papr(y), ...
                "TargetPAPR_dB",targetPAPR_dB,"Iterations",iterations);
        end
    end

    methods(Static,Access=private)
        function value=papr(x)
            p=abs(double(x(:))).^2;
            value=10*log10(max(p)/max(mean(p),realmin));
        end
    end
end
