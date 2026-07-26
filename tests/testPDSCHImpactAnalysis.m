function tests = testPDSCHImpactAnalysis
%TESTPDSCHIMPACTANALYSIS Dedicated PDSCH impact evidence checks.
tests = functiontests(localfunctions);
end

function testFrozenImpactPackAndSourceLineage(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(root, "tests", "vectors", "pdsch");
cfg = sixgr.lls6g.config.readConfigFile(fullfile(root, "simulator", ...
    "configs", "validation", "pdsch_dlsch_impact.yaml"));
[tables, evidence, records] = ...
    sixgr.pdsch.analysis.PDSCHImpactEvidenceBuilder.build( ...
        fullfile(vectorRoot, "pdsch_impact_experiment_matrix.csv"), ...
        fullfile(vectorRoot, "pdsch_impact_acceptance_rules.csv"), ...
        vectorRoot, fullfile(root, "artifacts", "pdsch_dlsch_phase"), ...
        cfg, "TEST", 0);
verifyEqual(testCase, evidence.ExperimentCount, 36);
verifyEqual(testCase, evidence.FamilyCount, 12);
verifyEqual(testCase, evidence.RuleCount, 24);
verifyTrue(testCase, evidence.HardRulesPassed);
verifyFalse(testCase, evidence.TruthQualified);
verifyTrue(testCase, all([records.SourceRowsPass]));
verifyEqual(testCase, numel(fieldnames(tables)), 15);
end

function testProductionModulatorRemainsAuthoritative(testCase)
bits = int8([0; 0; 0; 1; 1; 0; 1; 1]);
symbols = sixgr.pdsch.PDSCHModulator(bits, "QPSK");
recovered = sixgr.pdsch.PDSCHModulator( ...
    symbols, "QPSK", "Operation", "hard-demap");
verifyEqual(testCase, int8(recovered), bits);
end

function testTruthRelabelIsRejected(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(root, "tests", "vectors", "pdsch");
bad = fullfile(tempdir, "pdsch_impact_truth_relabel.yaml");
cleanup = onCleanup(@() localDelete(bad)); %#ok<NASGU>
copyfile(fullfile(root, "simulator", "configs", "validation", ...
    "pdsch_dlsch_impact.yaml"), bad);
text = replace(fileread(bad), "truth_qualified: false", ...
    "truth_qualified: true");
fid = fopen(bad, "w");
fileCleanup = onCleanup(@() fclose(fid));
fwrite(fid, text, "char");
clear fileCleanup
call = @() sixgr.pdsch.analysis.runPDSCHImpactValidation( ...
    VectorRoot=vectorRoot, ...
    BaseArtifactDir=fullfile(root, "artifacts", "pdsch_dlsch_phase"), ...
    OutputDir=fullfile(tempdir, "unused_pdsch_impact"), ...
    Strict=true, StudyConfig=bad);
verifyError(testCase, call, "sixgr:pdsch:ImpactTruthRelabelForbidden");
end

function localDelete(path)
if isfile(path)
    delete(path);
end
end
