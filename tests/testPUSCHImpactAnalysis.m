function tests = testPUSCHImpactAnalysis
%TESTPUSCHIMPACTANALYSIS Dedicated PUSCH impact component checks.
tests = functiontests(localfunctions);
end

function testIntervalsAndMultiplicity(testCase)
[lo, hi] = sixgr.phy.ul.pusch.analysis.computeWilsonInterval( ...
    10, 100, 0.95);
verifyLessThanOrEqual(testCase, lo, 0.1);
verifyGreaterThanOrEqual(testCase, hi, 0.1);
[exactLo, exactHi] = ...
    sixgr.phy.ul.pusch.analysis.computeClopperPearsonInterval( ...
        10, 100, 0.95);
verifyLessThanOrEqual(testCase, exactLo, 0.1);
verifyGreaterThanOrEqual(testCase, exactHi, 0.1);
adjusted = sixgr.phy.ul.pusch.analysis.adjustPValuesHolm( ...
    [0.01; 0.04; 0.2]);
verifyGreaterThanOrEqual(testCase, adjusted, [0.01; 0.04; 0.2]);
verifyLessThanOrEqual(testCase, adjusted, ones(3, 1));
end

function testPairedStreamsAreStable(testCase)
row = table("EXP-1", "PAIR-1", "CELL-1", ...
    VariableNames=["ExperimentID","PairID","DesignCell"]);
first = sixgr.phy.ul.pusch.analysis.PairedRNGStreams.resolve( ...
    row, [11 23 47]);
second = sixgr.phy.ul.pusch.analysis.PairedRNGStreams.resolve( ...
    row, [11 23 47]);
verifyEqual(testCase, first, second);
verifyNotEqual(testCase, first.PayloadSeed, first.ChannelSeed);
end

function testRegisteredSmokeExperimentExecutes(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(root, "tests", "vectors", "pusch");
matrixPath = fullfile(vectorRoot, "pusch_impact_experiment_matrix.csv");
options = detectImportOptions(matrixPath, VariableNamingRule="preserve");
options = setvartype(options, options.VariableNames, "string");
matrix = readtable(matrixPath, options);
cfg = sixgr.lls6g.config.readConfigFile(fullfile(root, "simulator", ...
    "configs", "validation", "pusch_ulsch_impact.yaml"));
record = sixgr.phy.ul.pusch.analysis.PUSCHImpactExperimentExecutor.execute( ...
    matrix(1, :), cfg, [11 23 47 89]);
verifyTrue(testCase, record.CorrectnessGatePass);
verifyFalse(testCase, record.TruthQualified);
verifyEqual(testCase, record.ExperimentID, string(matrix.ExperimentID(1)));
verifyTrue(testCase, isfinite(record.MeasuredSINRdB));
verifyTrue(testCase, isfinite(record.ChannelEstimationNMSE));
end

function testTruthRelabelIsRejected(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(root, "tests", "vectors", "pusch");
bad = fullfile(tempdir, "pusch_impact_truth_relabel.yaml");
cleanup = onCleanup(@() localDelete(bad)); %#ok<NASGU>
copyfile(fullfile(root, "simulator", "configs", "validation", ...
    "pusch_ulsch_impact.yaml"), bad);
text = fileread(bad);
text = replace(text, "truth_qualified: false", ...
    "truth_qualified: true");
fid = fopen(bad, "w");
fileCleanup = onCleanup(@() fclose(fid));
fwrite(fid, text, "char");
clear fileCleanup
call = @() sixgr.phy.ul.pusch.analysis.runPUSCHImpactValidation( ...
    ExperimentMatrix=fullfile(vectorRoot, ...
        "pusch_impact_experiment_matrix.csv"), ...
    PairingContract=fullfile(vectorRoot, ...
        "pusch_impact_pairing_contract.csv"), ...
    AcceptanceRules=fullfile(vectorRoot, ...
        "pusch_impact_acceptance_rules.csv"), ...
    AnalyticalFloor=fullfile(vectorRoot, ...
        "expected_pusch_impact_analytical_floor.csv"), ...
    OutputDir=fullfile(tempdir, "unused_pusch_impact"), ...
    Tier="smoke", Strict=true, StudyConfig=bad);
verifyError(testCase, call, "sixgr:pusch:ImpactTruthRelabelForbidden");
end

function localDelete(path)
if isfile(path)
    delete(path);
end
end
