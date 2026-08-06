function result = evaluateBinomialStopping(eventCount, trialCount, targetProbability, varargin)
%EVALUATEBINOMIALSTOPPING Fail-closed qualification of a binomial metric.
%
% The two decision bounds use exact one-sided Clopper-Pearson intervals.
% Alpha is divided across both decision directions and all configured
% interim looks, so repeatedly checking the campaign cannot silently turn a
% nominal fixed-sample interval into a fail-open sequential test.

p = inputParser;
p.FunctionName = "sixgr.stats.evaluateBinomialStopping";
addRequired(p, "eventCount", @localNonnegativeInteger);
addRequired(p, "trialCount", @localPositiveInteger);
addRequired(p, "targetProbability", @localOpenProbability);
addParameter(p, "ConfidenceLevel", [], @localOpenProbability);
addParameter(p, "MinimumTrials", [], @localPositiveInteger);
addParameter(p, "MaximumTrials", [], @localPositiveInteger);
addParameter(p, "MinimumEvents", [], @localNonnegativeInteger);
addParameter(p, "CIWidthTarget", [], @localPositiveFinite);
addParameter(p, "LookIndex", [], @localPositiveInteger);
addParameter(p, "PlannedLooks", [], @localPositiveInteger);
addParameter(p, "FinalLook", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, "MetricName", "binomial_event_probability", @(x) ischar(x) || isstring(x));
parse(p, eventCount, trialCount, targetProbability, varargin{:});
o = p.Results;

requiredNames = ["ConfidenceLevel","MinimumTrials","MaximumTrials", ...
    "MinimumEvents","CIWidthTarget","LookIndex","PlannedLooks"];
for ii = 1:numel(requiredNames)
    if isempty(o.(requiredNames(ii)))
        error("sixgr:stats:MissingStoppingParameter", ...
            "Binomial stopping requires explicit %s.", requiredNames(ii));
    end
end

k = double(eventCount);
n = double(trialCount);
target = double(targetProbability);
confidence = double(o.ConfidenceLevel);
minimumTrials = double(o.MinimumTrials);
maximumTrials = double(o.MaximumTrials);
minimumEvents = double(o.MinimumEvents);
lookIndex = double(o.LookIndex);
plannedLooks = double(o.PlannedLooks);
widthTarget = double(o.CIWidthTarget);
if k > n
    error("sixgr:validation:InvalidBinomialCounts", ...
        "Binomial counts require integer 0 <= EventCount <= TrialCount.");
end
if minimumTrials > maximumTrials
    error("sixgr:stats:InvalidStoppingDesign", ...
        "MinimumTrials must not exceed MaximumTrials.");
end
if n > maximumTrials
    error("sixgr:stats:TrialBudgetExceeded", ...
        "TrialCount %d exceeds the configured MaximumTrials %d.", n, maximumTrials);
end
if lookIndex > plannedLooks
    error("sixgr:stats:LookBudgetExceeded", ...
        "LookIndex %d exceeds PlannedLooks %d.", lookIndex, plannedLooks);
end

familyAlpha = 1-confidence;
directionalAlpha = familyAlpha/(2*plannedLooks);
effectiveConfidence = 1-directionalAlpha;
designId = "planned_look_bonferroni_two_direction";
upper = sixgr.validation.BinomialIntervalEngine.exactUpper( ...
    k,n,effectiveConfidence,"LookIndex",lookIndex, ...
    "AlphaSpent",directionalAlpha,"DesignID",designId);
lower = sixgr.validation.BinomialIntervalEngine.exactLower( ...
    k,n,effectiveConfidence,"LookIndex",lookIndex, ...
    "AlphaSpent",directionalAlpha,"DesignID",designId);

ciLower = double(lower.Lower);
ciUpper = double(upper.Upper);
ciWidth = ciUpper-ciLower;
enoughTrials = n >= minimumTrials;
enoughEvents = k >= minimumEvents;
narrowEnough = ciWidth <= widthTarget;
passBound = ciUpper <= target;
failBound = ciLower > target;

qualification = "NOT_EVALUATED";
qualified = false;
continueSampling = true;
stoppingReason = "minimum_trial_count_not_reached";
if enoughTrials && enoughEvents && narrowEnough && passBound
    qualification = "PASS";
    qualified = true;
    continueSampling = false;
    stoppingReason = "exact_upper_bound_at_or_below_target";
elseif enoughTrials && narrowEnough && failBound
    qualification = "FAIL";
    qualified = true;
    continueSampling = false;
    stoppingReason = "exact_lower_bound_above_target";
elseif ~enoughEvents
    stoppingReason = "minimum_event_count_not_reached";
elseif ~narrowEnough
    stoppingReason = "confidence_interval_width_not_reached";
elseif enoughTrials
    stoppingReason = "confidence_bounds_overlap_target";
end

finalLook = logical(o.FinalLook) || n >= maximumTrials || lookIndex >= plannedLooks;
if finalLook && continueSampling
    continueSampling = false;
    if n >= maximumTrials
        stoppingReason = "maximum_trial_count_reached_without_qualification";
    elseif lookIndex >= plannedLooks
        stoppingReason = "planned_look_budget_reached_without_qualification";
    else
        stoppingReason = "caller_declared_final_look_without_qualification";
    end
end

result = struct( ...
    "MetricName", string(o.MetricName), ...
    "EvidenceUnit", "independent_binomial_decision", ...
    "EventCount", k, ...
    "TrialCount", n, ...
    "Estimate", k/n, ...
    "TargetProbability", target, ...
    "CILower", ciLower, ...
    "CIUpper", ciUpper, ...
    "CIWidth", ciWidth, ...
    "CIWidthTarget", widthTarget, ...
    "ConfidenceLevel", confidence, ...
    "EffectiveDirectionalConfidenceLevel", effectiveConfidence, ...
    "FamilyAlpha", familyAlpha, ...
    "AlphaSpentThisLook", 2*directionalAlpha, ...
    "IntervalMethod", "CLOPPER_PEARSON_EXACT_ONE_SIDED_BOUNDS", ...
    "SequentialDesign", designId, ...
    "LookIndex", lookIndex, ...
    "PlannedLooks", plannedLooks, ...
    "MinimumTrials", minimumTrials, ...
    "MaximumTrials", maximumTrials, ...
    "MinimumEvents", minimumEvents, ...
    "MinimumTrialsReached", enoughTrials, ...
    "MinimumEventsReached", enoughEvents, ...
    "CIWidthReached", narrowEnough, ...
    "PointEstimatePass", (k/n) <= target, ...
    "Qualification", qualification, ...
    "StatisticallyQualified", qualified, ...
    "ContinueSampling", continueSampling, ...
    "StoppingReason", stoppingReason);
end

function tf = localNonnegativeInteger(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x == fix(x);
end

function tf = localPositiveInteger(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == fix(x);
end

function tf = localOpenProbability(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x < 1;
end

function tf = localPositiveFinite(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end
