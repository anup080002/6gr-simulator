function tests=testQualificationFinalizationIdempotence
tests=functiontests(localfunctions);
end

function testCompletedStageResumeDoesNotRewriteLedger(testCase)
[source,recovery,cleanup]=localFixture(); %#ok<ASGLU>
stage="F01_DOMAIN_EXPORTS_DISCOVERED";
sixgr.integration.qualification.resumeFinalize( ...
    SourceRunRoot=source,RecoveryRunRoot=recovery, ...
    StopAfterStage=stage);
path=fullfile(recovery,"reports","csv", ...
    "finalization_stage_ledger.csv");
before=sixgr.integration.qualification.ArtifactResolver.fileHash(path);
out=sixgr.integration.qualification.resumeFinalize( ...
    SourceRunRoot=source,RecoveryRunRoot=recovery, ...
    StopAfterStage=stage);
after=sixgr.integration.qualification.ArtifactResolver.fileHash(path);
verifyTrue(testCase,out.ResumedExistingFinalization);
verifyEqual(testCase,after,before);
end

function [source,recovery,cleanup]=localFixture()
root=string(tempname);mkdir(root);
source=fullfile(root,"source");recovery=fullfile(root,"recovery");
mkdir(fullfile(source,"reports","config"));
repositoryRoot=fileparts(fileparts(mfilename("fullpath")));
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    repositoryRoot,"simulator","configs","scenarios", ...
    "lls_webgui_full_stack_sinr_geometry_qualification.yaml"));
resolved=scenario.toStruct();
if isfield(resolved,"inherits"),resolved=rmfield(resolved,"inherits");end
sixgr.lls6g.config.writeYAML(fullfile(source,"reports","config", ...
    "executed_scenario.yaml"),resolved);
cleanup=onCleanup(@()rmdir(root,"s"));
end
