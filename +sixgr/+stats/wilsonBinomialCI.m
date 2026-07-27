function [center, halfWidth, low, high] = wilsonBinomialCI(k, n, confidenceLevel)
%WILSONBINOMIALCI Compatibility facade over the canonical interval engine.

if nargin < 3 || isempty(confidenceLevel)
    error("sixgr:validation:InvalidConfidenceLevel", ...
        "wilsonBinomialCI requires an explicit confidence level.");
end

interval = sixgr.validation.BinomialIntervalEngine.wilson( ...
    k,n,confidenceLevel);
center = interval.Center;
halfWidth = interval.HalfWidth;
low = interval.Lower;
high = interval.Upper;
end
