function [center, halfWidth, low, high] = wilsonBinomialCI(k, n, confidenceLevel)
%WILSONBINOMIALCI Wilson confidence interval for a binomial proportion.

if nargin < 3 || isempty(confidenceLevel)
    confidenceLevel = 0.95;
end

center = NaN;
halfWidth = NaN;
low = NaN;
high = NaN;

k = double(k);
n = double(n);
confidenceLevel = double(confidenceLevel);
if ~(isscalar(k) && isscalar(n) && isfinite(k) && isfinite(n) ...
        && n > 0 && k >= 0 && isscalar(confidenceLevel) ...
        && isfinite(confidenceLevel) && confidenceLevel > 0 ...
        && confidenceLevel < 1)
    return;
end

k = min(max(k, 0), n);
p = k / n;
z = sqrt(2) * erfinv(confidenceLevel);
denom = 1 + z^2 / n;
center = (p + z^2 / (2 * n)) / denom;
halfWidth = z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom;
low = max(0, center - halfWidth);
high = min(1, center + halfWidth);
center = min(max(center, 0), 1);
halfWidth = max(0, min(1, halfWidth));
end
