function ok = testRAN1AI1032PairedDropPlan()
%TESTRAN1AI1032PAIREDDROPPLAN Paired drops must freeze all stochastic inputs.

setup6GRSimToolkit("Verbose", false);
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
cfg = sixgr.studies.ran1ai1032.loadStudyConfig(fullfile(repoRoot, ...
    "configs", "tdoc", "ai_10_3_2_modulation", "study.yaml"));
out = sixgr.studies.ran1ai1032.buildPairedDropPlan(cfg);
T = out.Plan;

expectedPairs = 2 * 2 * 3 * 30;
assert(out.Status == "PASS" && out.PairCount == expectedPairs && ...
    height(T) == expectedPairs * 6, ...
    "Plan must contain all UMa/UMi, population, load, drop and comparator rows.");
assert(out.SeedValidation.Status == "PASS" && ...
    height(out.SeedLedger) == expectedPairs * 6, ...
    "Every independent pair/component must have a collision-free seed.");

first = T.PairKey == T.PairKey(1);
seedColumns = ["GeometrySeed","ShadowSeed","TrafficSeed", ...
    "AntennaOrientationSeed","SchedulerSeed","PropagationSeed"];
for name = seedColumns
    assert(numel(unique(T.(name)(first))) == 1, ...
        "Every stochastic stream must be frozen across S0--S5.");
end
assert(isequal(sort(T.ComparatorID(first)), sort(["S0";"S1";"S2";"S3";"S4";"S5"])) && ...
    numel(unique(T.ArrivalStreamID(first))) == 1, ...
    "Every pair must contain S0--S5 and one frozen traffic ledger identity.");

keys = unique(T.PairKey, "stable");
kpi = table(strings(0,1), strings(0,1), zeros(0,1), ...
    'VariableNames', {'PairKey','ComparatorID','KPIValue'});
for i = 1:30
    kpi(end+1,:) = {keys(i), "S0", i}; %#ok<AGROW>
    kpi(end+1,:) = {keys(i), "S1", i + 2}; %#ok<AGROW>
end
boot = sixgr.studies.ran1ai1032.pairedDropBootstrap(kpi, "S1", ...
    "NumResamples", 1000, "Seed", 91);
assert(boot.IndependentDropCount == 30 && boot.MeanDifference == 2 && ...
    boot.CILower == 2 && boot.CIUpper == 2 && ...
    boot.BootstrapUnit == "independent_paired_drop", ...
    "Paired bootstrap must resample independent drop differences.");

duplicate = [kpi; kpi(1,:)];
threw = false;
try
    sixgr.studies.ran1ai1032.pairedDropBootstrap(duplicate, "S1", ...
        "NumResamples", 10);
catch ME
    threw = ME.identifier == "sixgr:ran1ai1032:PairedBootstrapNotDropLevel";
end
assert(threw, "Slot/UE/TB duplicates must not be accepted as independent drops.");
ok = true;
end
