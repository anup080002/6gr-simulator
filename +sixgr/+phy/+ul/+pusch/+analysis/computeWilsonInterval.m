function [lower, upper] = computeWilsonInterval(errors, trials, confidence)
%COMPUTEWILSONINTERVAL Wilson score interval for a binomial proportion.
errors = double(errors);
trials = double(trials);
confidence = double(confidence);
if ~(isscalar(errors) && isscalar(trials) && trials >= 1 && ...
        errors >= 0 && errors <= trials && ...
        confidence > 0 && confidence < 1)
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "Wilson interval inputs are invalid.");
end
z = -sqrt(2) * erfcinv(2 * (1 - (1 - confidence) / 2));
p = errors / trials;
denominator = 1 + z^2 / trials;
center = (p + z^2 / (2 * trials)) / denominator;
radius = z * sqrt(p * (1 - p) / trials + z^2 / (4 * trials^2)) ...
    / denominator;
lower = max(0, center - radius);
upper = min(1, center + radius);
end
