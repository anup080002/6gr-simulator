function tests = testFrameGridImpactAnalysis
%TESTFRAMEGRIDIMPACTANALYSIS Dedicated 12-work-item impact checks.
tests = functiontests(localfunctions);
end

function testFrozenImpactPackAndSourceLineage(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(root, "tests", "vectors", "frame_grid");
cfg = sixgr.lls6g.config.readConfigFile(fullfile(root, "simulator", ...
    "configs", "validation", "frame_grid_impact.yaml"));
[tables, evidence, records] = ...
    sixgr.phy.frame.analysis.FrameGridImpactEvidenceBuilder.build( ...
        fullfile(vectorRoot, "frame_impact_experiment_matrix.csv"), ...
        fullfile(vectorRoot, "frame_impact_acceptance_rules.csv"), ...
        vectorRoot, fullfile(root, "artifacts", "frame_grid_phase"), ...
        cfg, "TEST", 0);
verifyEqual(testCase, evidence.ExperimentCount, 36);
verifyEqual(testCase, evidence.FamilyCount, 12);
verifyEqual(testCase, evidence.RuleCount, 24);
verifyTrue(testCase, evidence.HardRulesPassed);
verifyFalse(testCase, evidence.TruthQualified);
verifyTrue(testCase, all([records.SourceRowsPass]));
verifyEqual(testCase, numel(fieldnames(tables)), 15);
end

function testProductionResolversRemainAuthoritative(testCase)
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    30, "normal", "generic_waveform_test", "FR1");
verifyEqual(testCase, numerology.Mu, 1);
verifyEqual(testCase, numerology.SlotsPerFrame, 20);
carrier = sixgr.phy.frame.CarrierGridConfig.resolve( ...
    "Role", "gNB_carrier_transmission_bandwidth", ...
    "FrequencyRange", "FR1", "CenterFrequencyHz", 4.0e9, ...
    "ChannelBandwidthMHz", 10, "SubcarrierSpacingKHz", 15);
verifyEqual(testCase, carrier.NSizeGrid, 52);
end

function testTruthRelabelIsRejected(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(root, "tests", "vectors", "frame_grid");
bad = fullfile(tempdir, "frame_grid_impact_truth_relabel.yaml");
cleanup = onCleanup(@() localDelete(bad)); %#ok<NASGU>
copyfile(fullfile(root, "simulator", "configs", "validation", ...
    "frame_grid_impact.yaml"), bad);
text = replace(fileread(bad), "truth_qualified: false", ...
    "truth_qualified: true");
fid = fopen(bad, "w");
fileCleanup = onCleanup(@() fclose(fid));
fwrite(fid, text, "char");
clear fileCleanup
call = @() sixgr.phy.frame.analysis.runFrameGridImpactValidation( ...
    VectorRoot=vectorRoot, ...
    BaseArtifactDir=fullfile(root, "artifacts", "frame_grid_phase"), ...
    OutputDir=fullfile(tempdir, "unused_frame_grid_impact"), ...
    Strict=true, StudyConfig=bad);
verifyError(testCase, call, "sixgr:frame:ImpactTruthRelabelForbidden");
end

function localDelete(path)
if isfile(path)
    delete(path);
end
end
