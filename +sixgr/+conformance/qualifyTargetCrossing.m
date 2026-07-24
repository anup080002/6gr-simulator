function [crossing, info] = qualifyTargetCrossing( ...
        snr, metric, simultaneousLower, simultaneousUpper, denominator, ...
        confidenceMethod, confidenceQualificationEligible, requirement, ...
        requiredSNR_dB, tolerance_dB, confidenceLevel)
%QUALIFYTARGETCROSSING Qualify a fixed-sample SNR-at-target bracket.
%
%   The symmetric SNR diagnostic is a project regression check, not a 3GPP
%   conformance rule. Its acceptance region is fixed before sampling at
%
%       [requiredSNR_dB - tolerance_dB, requiredSNR_dB + tolerance_dB].
%
%   At the low-SNR endpoint the directional confidence bound must establish
%   failure of the target, while at the high-SNR endpoint the opposite bound
%   must establish attainment of the target. SIMULTANEOUSLOWER and
%   SIMULTANEOUSUPPER are the endpoints of a two-sided CONFIDENCELEVEL
%   interval. Each endpoint is therefore a one-sided bound at
%   1-(1-CONFIDENCELEVEL)/2, and Bonferroni gives at least
%   CONFIDENCELEVEL joint coverage for these two prespecified comparisons.
%
%   This is a fixed-sample rule. It does not inspect interim confidence
%   intervals and does not use metric-interval half-width as an SNR
%   precision surrogate. The width of the prespecified SNR bracket is the
%   relevant precision for the project +/- tolerance diagnostic.

narginchk(11, 11);
[snr, metric, simultaneousLower, simultaneousUpper, denominator, ...
    confidenceMethod] = localValidateVectors( ...
    snr, metric, simultaneousLower, simultaneousUpper, denominator, ...
    confidenceMethod);

confidenceQualificationEligible = ...
    localLogicalScalar(confidenceQualificationEligible, ...
    "confidenceQualificationEligible");
requiredSNR_dB = localFiniteScalar(requiredSNR_dB, "requiredSNR_dB");
tolerance_dB = localPositiveFiniteScalar(tolerance_dB, "tolerance_dB");
confidenceLevel = localProbability(confidenceLevel, "confidenceLevel");
[target, comparator, metricName] = localValidateRequirement(requirement);

[snr, order] = sort(snr);
metric = metric(order);
simultaneousLower = simultaneousLower(order);
simultaneousUpper = simultaneousUpper(order);
denominator = denominator(order);
confidenceMethod = confidenceMethod(order);
if any(diff(snr) <= 0)
    error("sixgr:conformance:DuplicateCrossingSNR", ...
        "Crossing qualification requires unique SNR samples.");
end

prespecifiedBracket = requiredSNR_dB + [-tolerance_dB, tolerance_dB];
lowerIndex = localFindSNRIndex(snr, prespecifiedBracket(1));
upperIndex = localFindSNRIndex(snr, prespecifiedBracket(2));
if isempty(lowerIndex) || isempty(upperIndex)
    error("sixgr:conformance:ProjectToleranceEndpointsMissing", ...
        ["The fixed-sample project gate requires simulations at both " ...
        "prespecified tolerance endpoints %.12g dB and %.12g dB."], ...
        prespecifiedBracket(1), prespecifiedBracket(2));
end

[globalCrossing, pointEstimateBracket, monotoneMetric] = ...
    localPointEstimateCrossing(snr, metric, denominator, target, comparator);
[endpointCrossing, endpointStraddles] = localEndpointCrossing( ...
    snr([lowerIndex, upperIndex]), ...
    metric([lowerIndex, upperIndex]), ...
    denominator([lowerIndex, upperIndex]), target, comparator);
if endpointStraddles
    crossing = endpointCrossing;
    interpolationBracket = "prespecified_tolerance_endpoints";
else
    crossing = globalCrossing;
    interpolationBracket = "monotone_point_estimate_neighbor_pair";
end

switch comparator
    case "less_than_or_equal"
        lowerEndpointSeparates = ...
            simultaneousLower(lowerIndex) > target;
        upperEndpointSeparates = ...
            simultaneousUpper(upperIndex) <= target;
        lowerEndpointDecision = "target_confidently_exceeded";
        upperEndpointDecision = "target_confidently_attained";
        monotonicityAssumption = ...
            "true_block_error_rate_nonincreasing_with_snr";
    case "greater_than_or_equal"
        lowerEndpointSeparates = ...
            simultaneousUpper(lowerIndex) < target;
        upperEndpointSeparates = ...
            simultaneousLower(upperIndex) >= target;
        lowerEndpointDecision = "target_confidently_not_attained";
        upperEndpointDecision = "target_confidently_attained";
        monotonicityAssumption = ...
            "true_throughput_fraction_nondecreasing_with_snr";
end

bracketSNR = snr([lowerIndex, upperIndex]);
bracketWidth = bracketSNR(2) - bracketSNR(1);
maximumBracketWidth = 2 .* tolerance_dB;
snrComparisonTolerance = localSNRTolerance( ...
    [snr; requiredSNR_dB; tolerance_dB]);
bracketWithinTolerance = ...
    bracketSNR(1) >= requiredSNR_dB - tolerance_dB - snrComparisonTolerance && ...
    bracketSNR(2) <= requiredSNR_dB + tolerance_dB + snrComparisonTolerance;
bracketPrecisionMet = logical( ...
    (bracketWidth <= maximumBracketWidth + snrComparisonTolerance) && ...
    logical(bracketWithinTolerance));

qualified = confidenceQualificationEligible && bracketPrecisionMet && ...
    lowerEndpointSeparates && upperEndpointSeparates && ...
    endpointStraddles && isfinite(crossing);
if ~confidenceQualificationEligible
    status = "prespecified_tolerance_bracket_smoke_confidence_unqualified";
elseif ~bracketPrecisionMet
    status = "prespecified_snr_bracket_precision_not_met";
elseif ~lowerEndpointSeparates
    status = "lower_tolerance_endpoint_not_confidence_separated";
elseif ~upperEndpointSeparates
    status = "upper_tolerance_endpoint_not_confidence_separated";
elseif ~endpointStraddles || ~isfinite(crossing)
    status = "crossing_interpolation_unavailable";
else
    status = "confidence_qualified_prespecified_tolerance_bracket";
end

selectedMethods = unique( ...
    confidenceMethod([lowerIndex, upperIndex]), "stable");
selectedMethods = selectedMethods(strlength(selectedMethods) > 0);
if isempty(selectedMethods)
    qualificationBounds = "unavailable";
else
    qualificationBounds = ...
        "simultaneous_directional_" + strjoin(selectedMethods, "+") + ...
        "_bonferroni_two_prespecified_endpoints";
end
if ~confidenceQualificationEligible
    qualificationBounds = qualificationBounds + "_descriptive_only";
end

info = struct( ...
    "Status", string(status), ...
    "TargetFraction", target, ...
    "MeasuredSNR_dB", double(crossing), ...
    "StatisticallyQualified", logical(qualified), ...
    "BracketIndices", double([lowerIndex, upperIndex]), ...
    "BracketSNR_dB", double(bracketSNR), ...
    "BracketWidth_dB", double(bracketWidth), ...
    "MaximumBracketWidth_dB", double(maximumBracketWidth), ...
    "BracketWithinTolerance", logical(bracketWithinTolerance), ...
    "BracketPrecisionTargetMet", logical(bracketPrecisionMet), ...
    "LowerEndpointConfidenceSeparates", ...
        logical(lowerEndpointSeparates), ...
    "UpperEndpointConfidenceSeparates", ...
        logical(upperEndpointSeparates), ...
    "ConfidenceSeparatedBracket", ...
        logical(lowerEndpointSeparates && upperEndpointSeparates), ...
    "LowerEndpointDecision", string(lowerEndpointDecision), ...
    "UpperEndpointDecision", string(upperEndpointDecision), ...
    "BracketMetricEstimate", ...
        double(metric([lowerIndex, upperIndex])), ...
    "BracketSimultaneousLower", ...
        double(simultaneousLower([lowerIndex, upperIndex])), ...
    "BracketSimultaneousUpper", ...
        double(simultaneousUpper([lowerIndex, upperIndex])), ...
    "PointEstimateBracketIndices", ...
        double(localBracketIndices(pointEstimateBracket)), ...
    "PointEstimateMonotoneMetric", double(monotoneMetric), ...
    "Interpolation", localInterpolationName(metricName), ...
    "InterpolationBracket", string(interpolationBracket), ...
    "QualificationBounds", string(qualificationBounds), ...
    "ConfidenceQualificationEligible", ...
        logical(confidenceQualificationEligible), ...
    "JointConfidenceLevel", double(confidenceLevel), ...
    "EndpointOneSidedConfidenceLevel", ...
        double(1 - (1 - confidenceLevel) ./ 2), ...
    "MultiplicityControl", ...
        "bonferroni_two_prespecified_tolerance_endpoints", ...
    "MetricIntervalHalfWidthUsedForQualification", false, ...
    "SNRBracketWidthUsedForQualification", true, ...
    "ZeroEventCrossingEstimate", "half_event_continuity_adjustment", ...
    "MonotonicityAssumption", string(monotonicityAssumption), ...
    "MonotonicEnvelopeApplied", true, ...
    "MonotonicEnvelopeAppliedToExploratoryEstimate", true, ...
    "Normative", false);
end

function [snr, metric, lower, upper, denominator, method] = ...
        localValidateVectors(snr, metric, lower, upper, denominator, method)
snr = double(snr(:));
metric = double(metric(:));
lower = double(lower(:));
upper = double(upper(:));
denominator = double(denominator(:));
method = string(method(:));
n = numel(snr);
if n < 2 || any([numel(metric), numel(lower), numel(upper), ...
        numel(denominator), numel(method)] ~= n)
    error("sixgr:conformance:InvalidCrossingVectors", ...
        "Crossing inputs must contain the same number of at least two points.");
end
if any(~isfinite(snr)) || any(~isfinite(metric)) || ...
        any(~isfinite(lower)) || any(~isfinite(upper)) || ...
        any(~isfinite(denominator) | denominator <= 0)
    error("sixgr:conformance:NonfiniteCrossingInput", ...
        "Crossing SNR, metric, bounds, and denominators must be finite.");
end
if any(strlength(method) == 0)
    error("sixgr:conformance:MissingCrossingConfidenceMethod", ...
        "Every crossing point must identify its confidence-bound method.");
end
boundTolerance = 64 .* eps(max(1, max(abs([metric; lower; upper]))));
if any(lower < -boundTolerance) || any(upper > 1 + boundTolerance) || ...
        any(lower > metric + boundTolerance) || ...
        any(metric > upper + boundTolerance)
    error("sixgr:conformance:InvalidCrossingConfidenceBounds", ...
        "Each confidence interval must contain its metric estimate in [0,1].");
end
end

function [target, comparator, metricName] = localValidateRequirement(requirement)
if ~(isstruct(requirement) && isscalar(requirement)) || ...
        ~all(isfield(requirement, ...
        ["target_fraction", "comparator", "metric"]))
    error("sixgr:conformance:InvalidCrossingRequirement", ...
        "Requirement must provide target_fraction, comparator, and metric.");
end
target = localProbability(requirement.target_fraction, ...
    "requirement.target_fraction");
comparator = string(requirement.comparator);
if ~isscalar(comparator) || ...
        ~any(comparator == ["less_than_or_equal", "greater_than_or_equal"])
    error("sixgr:conformance:InvalidCrossingComparator", ...
        "Unsupported crossing comparator '%s'.", comparator);
end
metricName = string(requirement.metric);
if ~isscalar(metricName) || ...
        ~any(metricName == ...
        ["block_error_rate", "fraction_of_maximum_throughput"])
    error("sixgr:conformance:InvalidCrossingMetric", ...
        "Unsupported crossing metric '%s'.", metricName);
end
end

function [crossing, bracket, monotoneMetric] = ...
        localPointEstimateCrossing(snr, metric, denominator, target, comparator)
adjustedMetric = localAdjustZeroMetric(metric, denominator, comparator);
if comparator == "less_than_or_equal"
    monotoneMetric = cummin(adjustedMetric);
    y = log10(max(monotoneMetric, realmin("double")));
    targetY = log10(target);
    bracket = find(y(1:end-1) >= targetY & ...
        y(2:end) <= targetY, 1);
    if isempty(bracket)
        crossing = NaN;
    else
        crossing = localInterpolateCrossing( ...
            snr(bracket:bracket + 1), y(bracket:bracket + 1), targetY);
    end
else
    monotoneMetric = cummax(adjustedMetric);
    bracket = find(monotoneMetric(1:end-1) <= target & ...
        monotoneMetric(2:end) >= target, 1);
    if isempty(bracket)
        crossing = NaN;
    else
        crossing = localInterpolateCrossing( ...
            snr(bracket:bracket + 1), ...
            monotoneMetric(bracket:bracket + 1), target);
    end
end
end

function [crossing, straddles] = localEndpointCrossing( ...
        snr, metric, denominator, target, comparator)
metric = localAdjustZeroMetric(metric, denominator, comparator);
if comparator == "less_than_or_equal"
    straddles = metric(1) >= target && metric(2) <= target;
    y = log10(max(metric, realmin("double")));
    targetY = log10(target);
else
    straddles = metric(1) <= target && metric(2) >= target;
    y = metric;
    targetY = target;
end
if straddles
    crossing = localInterpolateCrossing(snr, y, targetY);
else
    crossing = NaN;
end
straddles = logical(straddles && isfinite(crossing));
end

function metric = localAdjustZeroMetric(metric, denominator, comparator)
metric = double(metric(:));
if comparator == "less_than_or_equal"
    zeroMask = metric == 0 & denominator > 0;
    metric(zeroMask) = 0.5 ./ denominator(zeroMask);
end
end

function crossing = localInterpolateCrossing(x, y, target)
x = double(x(:));
y = double(y(:));
if numel(x) ~= 2 || numel(y) ~= 2 || any(~isfinite([x; y])) || ...
        y(1) == y(2)
    crossing = NaN;
    return;
end
crossing = x(1) + ...
    (target - y(1)) .* (x(2) - x(1)) ./ (y(2) - y(1));
end

function indices = localBracketIndices(bracket)
if isempty(bracket)
    indices = [];
else
    indices = [bracket, bracket + 1];
end
end

function index = localFindSNRIndex(snr, expected)
tolerance = localSNRTolerance([snr; expected]);
index = find(abs(snr - expected) <= tolerance, 1);
end

function tolerance = localSNRTolerance(values)
scale = max(1, max(abs(double(values(:)))));
tolerance = max(1e-10, 64 .* eps(scale));
end

function value = localInterpolationName(metricName)
if metricName == "block_error_rate"
    value = "linear_in_log10_bler";
else
    value = "linear_in_throughput_fraction";
end
end

function value = localFiniteScalar(value, label)
value = double(value);
if ~(isscalar(value) && isfinite(value))
    error("sixgr:conformance:InvalidCrossingScalar", ...
        "%s must be a finite numeric scalar.", label);
end
end

function value = localPositiveFiniteScalar(value, label)
value = localFiniteScalar(value, label);
if value <= 0
    error("sixgr:conformance:InvalidCrossingScalar", ...
        "%s must be positive.", label);
end
end

function value = localProbability(value, label)
value = localFiniteScalar(value, label);
if value <= 0 || value >= 1
    error("sixgr:conformance:InvalidCrossingProbability", ...
        "%s must be in (0,1).", label);
end
end

function value = localLogicalScalar(value, label)
if ~((islogical(value) || isnumeric(value)) && isscalar(value) && ...
        isfinite(double(value)) && any(double(value) == [0, 1]))
    error("sixgr:conformance:InvalidCrossingLogical", ...
        "%s must be a logical scalar.", label);
end
value = logical(value);
end
