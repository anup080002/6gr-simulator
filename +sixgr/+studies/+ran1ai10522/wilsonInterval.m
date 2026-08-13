function [lower,upper]=wilsonInterval(errors,trials,confidence)
%WILSONINTERVAL Two-sided Wilson score interval for a binomial error rate.
arguments
    errors (1,1) double {mustBeInteger,mustBeNonnegative}
    trials (1,1) double {mustBeInteger,mustBePositive}
    confidence (1,1) double {mustBeGreaterThan(confidence,0),mustBeLessThan(confidence,1)}
end
if errors>trials
    error("sixgr:ran1ai10522:InvalidBinomialCounts", ...
        "Error count cannot exceed the trial count.");
end
p=errors/trials; alpha=(1-confidence)/2;
z=sqrt(2)*erfcinv(2*alpha);
den=1+z^2/trials;
center=(p+z^2/(2*trials))/den;
half=z*sqrt(p*(1-p)/trials+z^2/(4*trials^2))/den;
lower=max(0,center-half); upper=min(1,center+half);
end
