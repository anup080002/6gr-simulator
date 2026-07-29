function tests = testFullStackQualificationContract
%TESTFULLSTACKQUALIFICATIONCONTRACT Focused Phase-18 orchestration contracts.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
path = fullfile(root,"simulator","configs","scenarios", ...
    "lls_webgui_full_stack_sinr_geometry_qualification.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(path);
profile = sixgr.integration.qualification. ...
    FullStackQualificationProfile.load(scfg);
testCase.TestData.Root = root;
testCase.TestData.Scenario = scfg;
testCase.TestData.Profile = profile;
end

function testScenarioSchemaAndExactSemanticMapping(testCase)
scfg = testCase.TestData.Scenario;
verifyEqual(testCase,string(scfg.get("scenario.runner_profile")), ...
    "full_stack_qualification");
verifyEqual(testCase,string(scfg.get("qualification.suite.preset")), ...
    "comprehensive_smoke");
verifyEqual(testCase,reshape(double(scfg.get( ...
    "qualification.main_fixed_sinr_sweep.snr_db")),1,[]), ...
    [-8 -4 0 4 10]);
verifyEqual(testCase,double(scfg.get( ...
    "qualification.carrier.active_bwp_nrb")),24);
verifyEqual(testCase,string(scfg.get( ...
    "qualification.network_probes.nlos_o2i_blockage.channel_profile")), ...
    "CDL-C");
end

function testPackCountsAndSelectedPresetArtifactCounts(testCase)
profile = testCase.TestData.Profile;
verifyEqual(testCase,height(profile.Subcases),31);
verifyEqual(testCase,height(profile.Components),163);
verifyEqual(testCase,height(profile.ValueChecks),107);
verifyEqual(testCase,height(profile.NegativeCases),77);
verifyEqual(testCase,height(profile.AcceptanceRules),387);
verifyEqual(testCase,height(profile.WebGUIPages),13);
verifyEqual(testCase,height(profile.SelectedArtifactRegistry),746);
verifyEqual(testCase,nnz(profile.SelectedArtifactRegistry.ArtifactType=="CSV"),447);
verifyEqual(testCase,nnz(profile.SelectedArtifactRegistry.ArtifactType=="PNG"),299);
end

function testOrderedSubcaseRegistry(testCase)
registry = sixgr.integration.qualification. ...
    FullStackSubcaseRegistry.load(testCase.TestData.Profile);
verifyEqual(testCase,string({registry.SubcaseID})', ...
    "SC-"+compose("%02d",(0:30)'));
verifyTrue(testCase,all([registry.Mandatory]));
groups = arrayfun(@(item)sixgr.integration.qualification. ...
    ComponentExecutionAdapter.groupFor(item.SubcaseID),registry);
verifyEqual(testCase,groups(1),"PREFLIGHT");
verifyEqual(testCase,groups(end),"REGRESSION");
end

function testCanonicalImplementationRegistryIsSourceHashBound(testCase)
[registry,digest] = sixgr.integration.qualification. ...
    CanonicalComponentRegistry.build(testCase.TestData.Profile);
verifyEqual(testCase,height(registry),163);
verifyEqual(testCase,strlength(digest),64);
verifyTrue(testCase,all(registry.SourcePresent));
verifyTrue(testCase,all(strlength(registry.SourceSHA256)==64));
verifyTrue(testCase,all(registry.Status=="PASS"));
end

function testResolvedAndExecutedYAMLHashesAreExact(testCase)
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@()rmdir(root,"s")); %#ok<NASGU>
scfg = testCase.TestData.Scenario;
cfg = sixgr.lls6g.buildInternalConfig(scfg,root);
ctx = sixgr.integration.qualification.FullStackRunContext.create( ...
    cfg,scfg,root,testCase.TestData.Profile);
verifyEqual(testCase,ctx.ResolvedYAMLSHA256,ctx.ExecutedYAMLSHA256);
verifyEqual(testCase,strlength(ctx.ResolvedYAMLSHA256),64);
verifyTrue(testCase,all(ctx.ConfigBinding.Status=="PASS"));
verifyNotEqual(testCase,ctx.ToolboxVersion,"unavailable");
end

function testArtifactAuditFailsClosedWithoutRuntimeEvidence(testCase)
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@()rmdir(root,"s")); %#ok<NASGU>
ctx = localMinimalContext(root,testCase.TestData.Profile);
audit = sixgr.integration.qualification.ArtifactCompletenessEngine.run(ctx);
verifyFalse(testCase,audit.Passed);
verifyEqual(testCase,height(audit.Combined),746);
verifyGreaterThan(testCase,nnz(audit.Combined.Status=="FAIL"),700);
verifyEqual(testCase,sum(audit.Completeness.PresentCSV),0);
verifyEqual(testCase,sum(audit.Completeness.PresentPNG),0);
verifyTrue(testCase,isfile(fullfile(ctx.CSVDir, ...
    "full_stack_artifact_manifest.csv")));
end

function testRunArtifactIndexFindsUniqueAndDuplicateNames(testCase)
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@()rmdir(root,"s")); %#ok<NASGU>
mkdir(fullfile(root,"a"));
mkdir(fullfile(root,"b"));
writelines("one",fullfile(root,"a","unique.csv"));
writelines("left",fullfile(root,"a","duplicate.csv"));
writelines("right",fullfile(root,"b","duplicate.csv"));
index = sixgr.integration.qualification.RunArtifactIndex.build(root);
[path,uniquePath] = sixgr.integration.qualification. ...
    RunArtifactIndex.findUnique(index,"unique.csv");
verifyTrue(testCase,uniquePath);
verifyTrue(testCase,endsWith(path,fullfile("a","unique.csv")));
[path,uniquePath] = sixgr.integration.qualification. ...
    RunArtifactIndex.findUnique(index,"duplicate.csv");
verifyFalse(testCase,uniquePath);
verifyEqual(testCase,path,"");
end

function testRegressionSummaryStartsFailClosed(testCase)
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@()rmdir(root,"s")); %#ok<NASGU>
ctx = localMinimalContext(root,testCase.TestData.Profile);
T = sixgr.integration.qualification.FullStackRegressionRunner.pending(ctx);
verifyEqual(testCase,height(T),10);
verifyTrue(testCase,all(string(T.Status)=="FAIL"));
verifyTrue(testCase,all(T.BlockedTests==1));
end

function ctx = localMinimalContext(root,profile)
reports = fullfile(root,"reports");
csvDir = fullfile(reports,"csv");
sixgr.util.ensureFolder(csvDir);
ctx = struct("RunID","FULLSTACK-FAIL-CLOSED-TEST", ...
    "RunFolder",root,"ReportsDir",reports,"CSVDir",csvDir, ...
    "WebGUILaunched",false,"ResolvedYAMLSHA256",repmat("a",1,64), ...
    "ExecutedYAMLSHA256",repmat("a",1,64),"Profile",profile);
end
