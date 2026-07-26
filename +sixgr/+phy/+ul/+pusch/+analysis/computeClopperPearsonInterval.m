function [lower, upper] = computeClopperPearsonInterval(errors, trials, confidence)
%COMPUTECLOPPERPEARSONINTERVAL Exact two-sided binomial interval.
errors = double(errors);
trials = double(trials);
alpha = 1 - double(confidence);
if ~(isscalar(errors) && isscalar(trials) && trials >= 1 && ...
        errors >= 0 && errors <= trials && alpha > 0 && alpha < 1)
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "Clopper-Pearson interval inputs are invalid.");
end
if errors == 0
    lower = 0;
else
    lower = betaincinv(alpha / 2, errors, trials - errors + 1);
end
if errors == trials
    upper = 1;
else
    upper = betaincinv(1 - alpha / 2, errors + 1, trials - errors);
end
end
