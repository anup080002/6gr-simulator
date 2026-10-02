function out = pairedDropBootstrap(dropKPI, targetComparator, opts)
%PAIREDDROPBOOTSTRAP Bootstrap paired comparator differences over drops.
%
% DROP KPI must contain exactly one scalar KPI for S0 and the requested
% target comparator per independent PairKey.  Slots, UEs and TBs must be
% aggregated before calling this function; duplicate rows fail closed.

arguments
    dropKPI table
    targetComparator (1,1) string
    opts.BaselineComparator (1,1) string = "S0"
    opts.NumResamples (1,1) double {mustBeInteger,mustBePositive} = 10000
    opts.ConfidenceLevel (1,1) double {mustBeGreaterThan(opts.ConfidenceLevel,0),mustBeLessThan(opts.ConfidenceLevel,1)} = 0.95
    opts.Seed (1,1) double {mustBeInteger,mustBePositive} = 1032001
end

required = ["PairKey","ComparatorID","KPIValue"];
if any(~ismember(required, string(dropKPI.Properties.VariableNames)))
    error("sixgr:ran1ai1032:PairedBootstrapSchema", ...
        "Drop-level bootstrap requires PairKey, ComparatorID and KPIValue.");
end
baseline = opts.BaselineComparator;
target = targetComparator;
if target == baseline
    error("sixgr:ran1ai1032:PairedBootstrapSameComparator", ...
        "Target and baseline comparators must differ.");
end
rows = ismember(string(dropKPI.ComparatorID), [baseline,target]);
T = dropKPI(rows, :);
pairKeys = unique(string(T.PairKey), "stable");
if numel(pairKeys) < 2
    error("sixgr:ran1ai1032:PairedBootstrapTooFewDrops", ...
        "At least two independent paired drops are required.");
end

difference = NaN(numel(pairKeys), 1);
baselineValue = NaN(numel(pairKeys), 1);
targetValue = NaN(numel(pairKeys), 1);
for i = 1:numel(pairKeys)
    pairRows = string(T.PairKey) == pairKeys(i);
    b = double(T.KPIValue(pairRows & string(T.ComparatorID) == baseline));
    t = double(T.KPIValue(pairRows & string(T.ComparatorID) == target));
    if numel(b) ~= 1 || numel(t) ~= 1 || ~isfinite(b) || ~isfinite(t)
        error("sixgr:ran1ai1032:PairedBootstrapNotDropLevel", ...
            "Pair %s must contain one finite drop aggregate for each comparator.", pairKeys(i));
    end
    baselineValue(i) = b;
    targetValue(i) = t;
    difference(i) = t - b;
end

stream = RandStream("mt19937ar", "Seed", opts.Seed);
n = numel(difference);
means = zeros(opts.NumResamples, 1);
for r = 1:opts.NumResamples
    indices = randi(stream, n, n, 1);
    means(r) = mean(difference(indices));
end
alpha = 1 - opts.ConfidenceLevel;
ci = localQuantile(means, [alpha/2, 1-alpha/2]);
paired = table(pairKeys, baselineValue, targetValue, difference, ...
    'VariableNames', {'PairKey','BaselineValue','TargetValue','Difference'});
out = struct("BaselineComparator", baseline, "TargetComparator", target, ...
    "IndependentDropCount", n, "MeanDifference", mean(difference), ...
    "MedianDifference", median(difference), "ConfidenceLevel", ...
    opts.ConfidenceLevel, "CILower", ci(1), "CIUpper", ci(2), ...
    "NumResamples", opts.NumResamples, "BootstrapUnit", ...
    "independent_paired_drop", "PairedDropTable", paired, "Status", "PASS");
end

function q = localQuantile(values, probabilities)
values = sort(double(values(:)));
n = numel(values);
q = zeros(size(probabilities));
for i = 1:numel(probabilities)
    position = 1 + (n - 1) * probabilities(i);
    lowerIndex = floor(position);
    upperIndex = ceil(position);
    fraction = position - lowerIndex;
    q(i) = values(lowerIndex) + fraction * ...
        (values(upperIndex) - values(lowerIndex));
end
end
