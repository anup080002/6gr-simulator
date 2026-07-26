function [lower, upper] = computePairedBootstrapCI(differences, confidence, replicates, seed)
%COMPUTEPAIREDBOOTSTRAPCI Deterministic paired mean bootstrap interval.
values = double(differences(:));
values = values(isfinite(values));
if isempty(values)
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "Paired bootstrap requires finite differences.");
end
replicates = double(replicates);
if ~(isscalar(replicates) && replicates >= 50 && replicates == fix(replicates))
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "Bootstrap replicate count must be an integer of at least 50.");
end
state = rng;
cleanup = onCleanup(@() rng(state));
rng(double(seed), "twister");
n = numel(values);
means = zeros(replicates, 1);
for index = 1:replicates
    means(index) = mean(values(randi(n, n, 1)));
end
alpha = (1 - double(confidence)) / 2;
means = sort(means);
lower = means(max(1, ceil(alpha * replicates)));
upper = means(min(replicates, floor((1 - alpha) * replicates)));
clear cleanup
end
