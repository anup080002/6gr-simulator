function [lower, upper, oneLower, oneUpper, method] = ...
        metricConfidenceBounds(metricName, eventCount, denominator, ...
        deliveredByTB, attemptsByTB, confidence, configuredMaxAttempts)
%METRICCONFIDENCEBOUNDS Confidence bounds using independent TB clusters.
%
%   BLER observations are one Bernoulli outcome per independently sampled
%   transport block and use exact Clopper-Pearson bounds.
%
%   HARQ throughput is the ratio
%
%       sum(TB delivered) / sum(HARQ transmissions).
%
%   Retransmissions are conditional observations from the same transport
%   block, so they are never treated as independent binomial trials. When
%   more than one HARQ transmission is configured, bounds use the
%   independent per-TB reward/attempt clusters. The configured maximum,
%   rather than the largest attempt count observed in the sample, defines
%   the bounded support used by the zero-variance Hoeffding fallback.

metricName = string(metricName);
confidence = double(confidence);
if ~(isscalar(confidence) && isfinite(confidence) && ...
        confidence > 0 && confidence < 1)
    error("sixgr:conformance:InvalidConfidenceLevel", ...
        "Confidence level must be a finite scalar in (0,1).");
end

if metricName == "block_error_rate"
    [lower, upper] = localBinomialInterval( ...
        eventCount, denominator, confidence);
    [oneLower, oneUpper] = localOneSidedBinomialBounds( ...
        eventCount, denominator, confidence);
    method = "clopper_pearson_independent_transport_blocks";
    return;
end
if metricName ~= "fraction_of_maximum_throughput"
    error("sixgr:conformance:UnsupportedRequirementMetric", ...
        "Unsupported FRC requirement metric '%s'.", metricName);
end

delivered = double(deliveredByTB(:));
attempts = double(attemptsByTB(:));
configuredMaxAttempts = double(configuredMaxAttempts);
if isempty(delivered) || numel(delivered) ~= numel(attempts) || ...
        any(~ismember(delivered, [0 1])) || ...
        any(~isfinite(attempts) | attempts < 1 | attempts ~= round(attempts))
    error("sixgr:conformance:InvalidThroughputConfidenceObservations", ...
        "Throughput confidence bounds require one delivery indicator and " + ...
        "one positive integer HARQ-attempt count per independent TB.");
end
if ~(isscalar(configuredMaxAttempts) && isfinite(configuredMaxAttempts) && ...
        configuredMaxAttempts >= 1 && ...
        configuredMaxAttempts == round(configuredMaxAttempts))
    error("sixgr:conformance:InvalidConfiguredHARQMaximum", ...
        "Configured maximum HARQ transmissions must be a positive integer.");
end
if any(attempts > configuredMaxAttempts)
    error("sixgr:conformance:HARQAttemptsExceedConfiguredMaximum", ...
        "An observed transport block used %d transmission(s), exceeding " + ...
        "the configured maximum of %d.", ...
        round(max(attempts)), round(configuredMaxAttempts));
end

% Clopper-Pearson is valid for throughput only when the experiment permits
% exactly one transmission per TB. Seeing only first-attempt successes in
% a short sample does not remove uncertainty about later retransmissions.
if configuredMaxAttempts == 1
    if any(attempts ~= 1)
        error("sixgr:conformance:SingleTransmissionHARQContractMismatch", ...
            "A one-transmission HARQ contract produced a non-unit attempt count.");
    end
    successes = sum(delivered);
    trials = numel(delivered);
    [lower, upper] = localBinomialInterval(successes, trials, confidence);
    [oneLower, oneUpper] = localOneSidedBinomialBounds( ...
        successes, trials, confidence);
    method = ...
        "clopper_pearson_single_transmission_independent_transport_blocks";
    return;
end

n = numel(delivered);
theta = sum(delivered) ./ sum(attempts);
influence = delivered - theta .* attempts;
meanAttempts = mean(attempts);
if n >= 2
    standardError = sqrt(var(influence, 0) ./ n) ./ meanAttempts;
else
    standardError = Inf;
end

if isfinite(standardError) && standardError > eps(max(1, abs(theta)))
    twoSidedCritical = sqrt(2) .* erfinv(confidence);
    oneSidedCritical = sqrt(2) .* erfinv(2 .* confidence - 1);
    lower = max(0, theta - twoSidedCritical .* standardError);
    upper = min(1, theta + twoSidedCritical .* standardError);
    oneLower = max(0, theta - oneSidedCritical .* standardError);
    oneUpper = min(1, theta + oneSidedCritical .* standardError);
    method = "independent_transport_block_cluster_ratio_delta_method";
    return;
end

% Zero empirical cluster variance can occur when a short run sees only
% first-attempt successes (or one other repeated outcome). A degenerate
% interval would make an unjustified certainty claim. Simultaneous
% Hoeffding bounds use the known [1, configuredMaxAttempts] attempt range.
alpha = 1 - confidence;
twoRadius = sqrt(log(4 ./ alpha) ./ (2 .* n));
oneRadius = sqrt(log(2 ./ alpha) ./ (2 .* n));
[lower, upper] = localRatioHoeffdingBounds( ...
    mean(delivered), meanAttempts, configuredMaxAttempts, twoRadius);
[oneLower, oneUpper] = localRatioHoeffdingBounds( ...
    mean(delivered), meanAttempts, configuredMaxAttempts, oneRadius);
method = ...
    "independent_transport_block_cluster_ratio_hoeffding_known_support";
end

function [lower, upper] = localRatioHoeffdingBounds( ...
        rewardMean, attemptMean, maxAttempts, radius)
rewardLower = max(0, rewardMean - radius);
rewardUpper = min(1, rewardMean + radius);
attemptRadius = (maxAttempts - 1) .* radius;
attemptLower = max(1, attemptMean - attemptRadius);
attemptUpper = min(maxAttempts, attemptMean + attemptRadius);
lower = max(0, rewardLower ./ attemptUpper);
upper = min(1, rewardUpper ./ attemptLower);
end

function [lower, upper] = localBinomialInterval(k, n, confidence)
[k, n] = localValidateBinomialCounts(k, n);
alpha = 1 - confidence;
if k == 0
    lower = 0;
else
    lower = betaincinv(alpha / 2, k, n - k + 1);
end
if k == n
    upper = 1;
else
    upper = betaincinv(1 - alpha / 2, k + 1, n - k);
end
end

function [lower, upper] = localOneSidedBinomialBounds(k, n, confidence)
[k, n] = localValidateBinomialCounts(k, n);
alpha = 1 - confidence;
if k == 0
    lower = 0;
else
    lower = betaincinv(alpha, k, n - k + 1);
end
if k == n
    upper = 1;
else
    upper = betaincinv(1 - alpha, k + 1, n - k);
end
end

function [k, n] = localValidateBinomialCounts(k, n)
k = double(k);
n = double(n);
if ~(isscalar(k) && isscalar(n) && isfinite(k) && isfinite(n) && ...
        n >= 1 && n == round(n) && k >= 0 && k <= n && k == round(k))
    error("sixgr:conformance:InvalidBinomialCounts", ...
        "Binomial event and trial counts must be integers with 0 <= k <= n.");
end
end
