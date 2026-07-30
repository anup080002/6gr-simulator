function tests=testQualificationFinalizationResume
tests=functiontests(localfunctions);
end

function testInterruptedRecoveryResumesAtNextStage(testCase)
[source,recovery,cleanup]=localFixture(); %#ok<ASGLU>
first=sixgr.integration.qualification.resumeFinalize( ...
    SourceRunRoot=source,RecoveryRunRoot=recovery, ...
    StopAfterStage="F00_SOURCE_RUN_LOCKED");
verifyFalse(testCase,first.CompletedWithoutException);
second=sixgr.integration.qualification.resumeFinalize( ...
    SourceRunRoot=source,RecoveryRunRoot=recovery, ...
    StopAfterStage="F01_DOMAIN_EXPORTS_DISCOVERED");
verifyFalse(testCase,second.CompletedWithoutException);
ledger=readtable(fullfile(recovery,"reports","csv", ...
    "finalization_stage_ledger.csv"),"TextType","string");
verifyEqual(testCase,string(ledger.Status(1:2)),["COMPLETE";"COMPLETE"]);
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
