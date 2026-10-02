function out = buildPairedDropPlan(cfg)
%BUILDPAIREDDROPPLAN Build the immutable S0--S5 paired SLS experiment plan.
%
% One PairKey identifies one independent drop within a scenario,
% population and offered-load target.  Every comparator in that PairKey
% receives the same six stochastic streams.  Seeds differ across PairKeys,
% so confidence intervals can be formed over independent drops.

arguments
    cfg struct
end

sls = cfg.sls;
scenario = string(sls.scenarios(:));
population = string(sls.fwa_populations(:));
loadPercent = double(sls.target_resource_utilization_percent(:));
nDrop = double(sls.independent_paired_drops);
baseSeed = double(sls.pairing.base_seed);
comparator = string({sls.comparators.id}).';

if isempty(scenario) || isempty(population) || isempty(loadPercent) || ...
        nDrop < 30 || nDrop ~= fix(nDrop) || isempty(comparator)
    error("sixgr:ran1ai1032:InvalidPairedDropAxes", ...
        "Paired-drop scenarios, populations, loads, >=30 drops and comparators are required.");
end
if numel(unique(comparator)) ~= numel(comparator) || ...
        ~isequal(sort(comparator), sort(["S0";"S1";"S2";"S3";"S4";"S5"]))
    error("sixgr:ran1ai1032:InvalidComparatorSet", ...
        "The AI 10.3.2 paired plan requires exactly comparators S0--S5.");
end
if ~(isscalar(baseSeed) && isfinite(baseSeed) && baseSeed >= 1 && ...
        baseSeed == fix(baseSeed))
    error("sixgr:ran1ai1032:InvalidPairingSeed", ...
        "sls.pairing.base_seed must be a positive integer.");
end

nPair = numel(scenario) * numel(population) * numel(loadPercent) * nDrop;
nComparator = numel(comparator);
nRow = nPair * nComparator;
PairKey = strings(nRow, 1);
Scenario = strings(nRow, 1);
Population = strings(nRow, 1);
TargetRUPercent = zeros(nRow, 1);
IndependentDropID = strings(nRow, 1);
ComparatorID = strings(nRow, 1);
GeometrySeed = zeros(nRow, 1);
ShadowSeed = zeros(nRow, 1);
TrafficSeed = zeros(nRow, 1);
AntennaOrientationSeed = zeros(nRow, 1);
SchedulerSeed = zeros(nRow, 1);
PropagationSeed = zeros(nRow, 1);
ArrivalStreamID = strings(nRow, 1);
SeedBundleID = strings(nRow, 1);
MaxRank = zeros(nRow, 1);
Representation = strings(nRow, 1);

seedNames = ["geometry","shadow","traffic","antenna_orientation", ...
    "scheduler","propagation"];
ledgerRows = nPair * numel(seedNames);
CampaignID = repmat(string(cfg.study.id), ledgerRows, 1);
TaskID = strings(ledgerRows, 1);
LedgerDropID = strings(ledgerRows, 1);
Seed = zeros(ledgerRows, 1);
Substream = zeros(ledgerRows, 1);
Component = strings(ledgerRows, 1);

pairOrdinal = 0;
row = 0;
ledgerRow = 0;
for s = 1:numel(scenario)
    for p = 1:numel(population)
        for l = 1:numel(loadPercent)
            for d = 1:nDrop
                pairOrdinal = pairOrdinal + 1;
                pairKey = localPairKey(scenario(s), population(p), ...
                    loadPercent(l), d);
                seedVector = baseSeed + (pairOrdinal - 1) * numel(seedNames) + ...
                    (1:numel(seedNames));
                if any(seedVector > (2^32 - 1))
                    error("sixgr:ran1ai1032:PairingSeedOverflow", ...
                        "Configured paired-drop seed sequence exceeds uint32 range.");
                end
                bundleID = "paired:" + pairKey + ":" + ...
                    join(string(seedVector), "-");
                arrivalID = "ftp3:paired:" + pairKey + ...
                    ":seed=" + string(seedVector(3));

                for k = 1:numel(seedNames)
                    ledgerRow = ledgerRow + 1;
                    TaskID(ledgerRow) = pairKey + ":" + seedNames(k);
                    LedgerDropID(ledgerRow) = pairKey;
                    Seed(ledgerRow) = seedVector(k);
                    % SeedLedger treats every component as an independent
                    % validation task, so its substream must also be
                    % globally unique. PairKey/SeedBundleID carry the
                    % shared-drop relationship across those tasks.
                    Substream(ledgerRow) = ledgerRow;
                    Component(ledgerRow) = seedNames(k);
                end

                for c = 1:nComparator
                    row = row + 1;
                    comp = sls.comparators(c);
                    PairKey(row) = pairKey;
                    Scenario(row) = scenario(s);
                    Population(row) = population(p);
                    TargetRUPercent(row) = loadPercent(l);
                    IndependentDropID(row) = compose("drop-%03d", d);
                    ComparatorID(row) = string(comp.id);
                    GeometrySeed(row) = seedVector(1);
                    ShadowSeed(row) = seedVector(2);
                    TrafficSeed(row) = seedVector(3);
                    AntennaOrientationSeed(row) = seedVector(4);
                    SchedulerSeed(row) = seedVector(5);
                    PropagationSeed(row) = seedVector(6);
                    ArrivalStreamID(row) = arrivalID;
                    SeedBundleID(row) = bundleID;
                    MaxRank(row) = double(comp.max_rank);
                    Representation(row) = string(comp.representation);
                end
            end
        end
    end
end

plan = table(PairKey, Scenario, Population, TargetRUPercent, ...
    IndependentDropID, ComparatorID, GeometrySeed, ShadowSeed, ...
    TrafficSeed, AntennaOrientationSeed, SchedulerSeed, PropagationSeed, ...
    ArrivalStreamID, SeedBundleID, MaxRank, Representation);
seedLedger = table(CampaignID, TaskID, LedgerDropID, Seed, Substream, ...
    Component, 'VariableNames', {'CampaignID','TaskID', ...
    'IndependentDropID','Seed','Substream','Component'});

validation = sixgr.validation.SeedLedger.validate(seedLedger(:, 1:5));
localValidatePairing(plan, comparator, nDrop);
out = struct("Plan", plan, "SeedLedger", seedLedger, ...
    "PairCount", nPair, "ComparatorCount", nComparator, ...
    "SeedValidation", validation, "Status", "PASS");
end

function key = localPairKey(scenario, population, loadPercent, drop)
scenario = regexprep(lower(strtrim(scenario)), "[^a-z0-9]+", "-");
population = regexprep(lower(strtrim(population)), "[^a-z0-9]+", "-");
key = scenario + ":" + population + ":ru" + ...
    compose("%03d", round(loadPercent)) + ":drop" + compose("%03d", drop);
end

function localValidatePairing(plan, expectedComparators, expectedDropCount)
seedColumns = ["GeometrySeed","ShadowSeed","TrafficSeed", ...
    "AntennaOrientationSeed","SchedulerSeed","PropagationSeed"];
pairKeys = unique(plan.PairKey, "stable");
for i = 1:numel(pairKeys)
    rows = plan.PairKey == pairKeys(i);
    if ~isequal(sort(plan.ComparatorID(rows)), sort(expectedComparators))
        error("sixgr:ran1ai1032:IncompleteComparatorPair", ...
            "Pair %s does not contain exactly S0--S5.", pairKeys(i));
    end
    for name = seedColumns
        if numel(unique(plan.(name)(rows))) ~= 1
            error("sixgr:ran1ai1032:UnpairedStochasticStream", ...
                "Pair %s changes %s across comparators.", pairKeys(i), name);
        end
    end
    if numel(unique(plan.ArrivalStreamID(rows))) ~= 1 || ...
            numel(unique(plan.SeedBundleID(rows))) ~= 1
        error("sixgr:ran1ai1032:UnpairedArrivalLedger", ...
            "Pair %s does not freeze traffic and seed-bundle identity.", pairKeys(i));
    end
end

groups = unique(plan(:, ["Scenario","Population","TargetRUPercent"]), "rows");
for i = 1:height(groups)
    rows = plan.Scenario == groups.Scenario(i) & ...
        plan.Population == groups.Population(i) & ...
        plan.TargetRUPercent == groups.TargetRUPercent(i);
    if numel(unique(plan.IndependentDropID(rows))) ~= expectedDropCount
        error("sixgr:ran1ai1032:InsufficientIndependentDrops", ...
            "Every scenario/population/load branch requires the configured independent-drop count.");
    end
end
end
