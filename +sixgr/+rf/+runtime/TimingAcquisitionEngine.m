classdef TimingAcquisitionEngine
%TIMINGACQUISITIONENGINE Reference-correlation timing estimator.

    methods(Static)
        function estimate=estimate(received,reference,varargin)
            p=inputParser;
            p.addParameter("MinimumPeakMetric",0.05);
            p.addParameter("AmbiguityRatio",1.01);
            p.parse(varargin{:});
            rx=double(received(:));
            ref=double(reference(:));
            if isempty(rx)||isempty(ref)||any(~isfinite(rx))|| ...
                    any(~isfinite(ref))||sum(abs(rx).^2)<=eps|| ...
                    sum(abs(ref).^2)<=eps
                error("RF:TimingAcquisitionFailed", ...
                    "Timing acquisition requires finite signal and reference energy.");
            end
            correlation=conv(rx,flipud(conj(ref)));
            magnitude=abs(correlation);
            [peak,index]=max(magnitude);
            normalizedPeak=peak/sqrt(sum(abs(rx).^2)*sum(abs(ref).^2));
            sorted=sort(magnitude,"descend");
            ambiguity=Inf;
            if numel(sorted)>1 && sorted(2)>0
                ambiguity=sorted(1)/sorted(2);
            end
            if normalizedPeak<double(p.Results.MinimumPeakMetric)
                error("RF:TimingAcquisitionFailed", ...
                    "No timing peak passed the declared metric.");
            end
            if ambiguity<double(p.Results.AmbiguityRatio)
                error("RF:TimingAcquisitionFailed", ...
                    "Timing peak is ambiguous.");
            end
            fractional=0;
            if index>1 && index<numel(magnitude)
                ym=magnitude(index-1); y0=magnitude(index); yp=magnitude(index+1);
                denominator=ym-2*y0+yp;
                if abs(denominator)>eps
                    fractional=0.5*(ym-yp)/denominator;
                end
            end
            lag=(index-numel(ref))+fractional;
            if numel(rx)==numel(ref)
                candidates=lag+linspace(-0.6,0.6,121);
                scores=zeros(size(candidates));
                for candidateIndex=1:numel(candidates)
                    hypothesis=sixgr.util.applyFractionalSampleDelay( ...
                        ref,candidates(candidateIndex));
                    scores(candidateIndex)=abs(hypothesis'*rx)/ ...
                        max(norm(hypothesis)*norm(rx),realmin);
                end
                [~,best]=max(scores);
                lag=candidates(best);
                normalizedPeak=scores(best);
            end
            estimate=struct("EstimatedTiming_samples",lag, ...
                "PeakMetric",normalizedPeak,"PeakRatio",ambiguity, ...
                "FalseLock",false,"Source","reference_correlation_parabolic_peak");
        end
    end
end
