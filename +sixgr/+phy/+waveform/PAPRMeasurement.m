classdef PAPRMeasurement
    %PAPRMEASUREMENT Oversampled PAPR and empirical CCDF evidence.
    methods (Static)
        function rows=measure(samples,factors,varargin)
            ip=inputParser;
            ip.addParameter("ReferenceDomain","useful_samples",@(x)ischar(x)||isstring(x));
            ip.addParameter("PayloadID","PAYLOAD",@(x)ischar(x)||isstring(x));
            ip.parse(varargin{:});
            factors=double(factors(:));
            papr=zeros(numel(factors),1);
            for i=1:numel(factors)
                factor=factors(i);
                if factor<1||factor~=fix(factor)
                    error("WAVEFORM:PAPRInsufficientOversampling","Oversampling factor is invalid.");
                end
                x=samples;
                if factor>1,x=interpft(samples,size(samples,1)*factor,1);end
                power=abs(double(x(:))).^2;
                papr(i)=10*log10(max(power)/max(mean(power),eps));
            end
            rows=table(factors,papr, ...
                repmat(string(ip.Results.ReferenceDomain),numel(factors),1), ...
                repmat(string(ip.Results.PayloadID),numel(factors),1), ...
                'VariableNames',{'OversamplingFactor','PAPR_dB','ReferenceDomain','PayloadID'});
        end
        function row=ccdf(values,threshold,confidence)
            if nargin<3,confidence=.95;end
            n=numel(values);k=sum(values>threshold);p=k/max(n,1);
            z=-sqrt(2)*erfcinv(2*(1-(1-confidence)/2));
            den=1+z^2/n;
            center=(p+z^2/(2*n))/den;
            half=z*sqrt(p*(1-p)/n+z^2/(4*n^2))/den;
            row=struct("Threshold_dB",threshold,"Exceedances",k, ...
                "Trials",n,"CCDF",p,"LowerCI",max(0,center-half), ...
                "UpperCI",min(1,center+half));
        end
    end
end
