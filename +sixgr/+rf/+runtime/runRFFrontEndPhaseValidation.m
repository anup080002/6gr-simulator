function summary=runRFFrontEndPhaseValidation(varargin)
%RUNRFFRONTENDPHASEVALIDATION Execute Phase-11 RF production validation.

p=inputParser;
p.addParameter("VectorRoot",fullfile(pwd,"tests","vectors","rf"), ...
    @(v)ischar(v)||isstring(v));
p.addParameter("OutputDir",fullfile(pwd,"artifacts","rf_frontend_phase"), ...
    @(v)ischar(v)||isstring(v));
p.addParameter("SeedList",[11 23 47 89],@isnumeric);
p.addParameter("ConfidenceLevel",0.95,@(v)isnumeric(v)&&isscalar(v));
p.addParameter("Strict",true,@(v)islogical(v)||(isnumeric(v)&&isscalar(v)));
p.parse(varargin{:});
opt=p.Results;
vectorRoot=string(opt.VectorRoot);
outputDir=string(opt.OutputDir);

profile=sixgr.rf.runtime.RFSpecificationProfile.resolve( ...
    "rf_impaired_research");
if logical(opt.Strict) && profile.ClaimClass~="RESEARCH"
    error("RF:UnsupportedProfile","RF phase runner claim boundary changed.");
end

testFile=fullfile(pwd,"tests","testRFFrontEndPhase11.m");
testResults=runtests(testFile);
executed=numel(testResults);
passed=nnz([testResults.Passed]);
failed=nnz([testResults.Failed]);
incomplete=nnz([testResults.Incomplete]);

evidence=sixgr.rf.runtime.RFPhaseEvidenceBuilder.build( ...
    vectorRoot,double(opt.SeedList),double(opt.ConfidenceLevel));
testSummary=table("RF_FRONTEND_PHASE11",executed,passed,failed,0,0, ...
    incomplete,localPass(failed==0&&incomplete==0), ...
    'VariableNames',{'Suite','Executed','Passed','Failed','Skipped', ...
    'Blocked','IncompletePoints','Status'});
evidence.rf_test_summary=testSummary;
exportSummary=sixgr.rf.runtime.RFArtifactExporter.exportBase( ...
    evidence,vectorRoot,outputDir);
summary=struct( ...
    "Passed",logical(exportSummary.Passed&&failed==0&&incomplete==0), ...
    "Profile",profile,"Strict",logical(opt.Strict), ...
    "TestResults",testResults,"TestSummary",testSummary, ...
    "Artifacts",exportSummary,"OutputDir",outputDir, ...
    "ClaimRestriction","NO_RF_DEVICE_CONFORMANCE_OR_CERTIFICATION");
end

function value=localPass(condition)
if condition, value="PASS"; else, value="FAIL"; end
end
