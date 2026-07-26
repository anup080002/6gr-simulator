function tests = testMIMOPhase07ImpactAnalysis
%TESTMIMOPHASE07IMPACTANALYSIS Dedicated Phase-07 impact acceptance.
tests = functiontests(localfunctions);
end

function setupOnce(~)
setup6GRSimToolkit("Verbose",false);
end

function testExecutedImpactContract(testCase)
root=fileparts(fileparts(mfilename("fullpath")));
outputDir=fullfile(root,"artifacts","mimo_csi_beamforming_impact");
summary=sixgr.phy.mimo.runMIMOCSIBeamformingImpactAnalysis( ...
    ExperimentMatrix=fullfile(root,"tests","vectors","mimo", ...
        "mimo_impact_experiment_matrix.csv"), ...
    OutputDir=outputDir,SeedList=[11 23 47 89 131 197], ...
    ConfidenceLevel=.95,Strict=true);

verifyTrue(testCase,summary.Passed);
verifyEqual(testCase,summary.ExperimentCount,768);
verifyEqual(testCase,summary.PairCount,384);
verifyEqual(testCase,summary.RuleCount,96);
verifyEqual(testCase,summary.IncompleteCount,0);
verifyEqual(testCase,summary.CSVCount,16);
verifyEqual(testCase,summary.PNGCount,30);
verifyFalse(testCase,summary.TruthQualified);
verifyEqual(testCase,summary.ExecutionBackend, ...
    "production_sample_domain_mimo_components");
verifyEqual(testCase,summary.ApproximationMode, ...
    "component_campaign_not_nr_waveform_truth");

raw=localReadStrings(fullfile(outputDir,"mimo_impact_raw_trials.csv"));
verifyEqual(testCase,height(raw),768);
verifyTrue(testCase,all(str2double(raw.TrialsRepresented)==2000));
verifyTrue(testCase,all(lower(raw.TruthQualified)=="false"));
verifyTrue(testCase,all(raw.ExecutionBackend== ...
    "production_sample_domain_mimo_components"));

operating=localReadStrings(fullfile(outputDir, ...
    "mimo_impact_operating_points.csv"));
verifyEqual(testCase,height(operating),768);
verifyFalse(testCase,any(lower(operating.Incomplete)=="true"));

rules=localReadStrings(fullfile(outputDir, ...
    "mimo_impact_rule_evaluation.csv"));
verifyEqual(testCase,height(rules),96);
verifyTrue(testCase,all(lower(rules.Passed)=="true"));
end

function value=localReadStrings(path)
options=detectImportOptions(path,FileType="text",Delimiter=",", ...
    VariableNamingRule="preserve");
options=setvartype(options,options.VariableNames,"string");
value=readtable(path,options);
end
