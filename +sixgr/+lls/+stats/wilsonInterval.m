function [lower, upper] = wilsonInterval(errors, trials, confidenceLevel)
%WILSONINTERVAL Wilson score interval for a binomial proportion.

arguments
    errors (1,1) double {mustBeNonnegative,mustBeInteger}
    trials (1,1) double {mustBePositive,mustBeInteger}
    confidenceLevel (1,1) double {mustBeGreaterThan(confidenceLevel,0),mustBeLessThan(confidenceLevel,1)} = 0.95
end
if errors > trials
    error("sixgr:lls:InvalidBinomialCounts", "Errors cannot exceed trials.");
end
p = errors / trials;
z = sqrt(2) * erfcinv(1-confidenceLevel);
denominator = 1 + z^2/trials;
center = (p + z^2/(2*trials)) / denominator;
halfWidth = z * sqrt(p*(1-p)/trials + z^2/(4*trials^2)) / denominator;
lower = max(0, center-halfWidth);
upper = min(1, center+halfWidth);
end
