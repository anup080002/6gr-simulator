function ok=testLLSPhysicalFailureClassification()
% Retain actual objective failures without calling measured BLER a proxy.
setup6GRSimToolkit('Verbose',false);
ctx=llsRootGateFixture('pass');
path=fullfile(ctx.Layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv');
rows=sixgr.util.csvReadTable(path,'TextType','string');
rows.CRCPass(:)=false;
rows.BitErrors(:)=100;
sixgr.util.csvWriteTable(path,rows);
verdict=sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ...
    ctx.ScenarioConfig,ctx.InternalConfig);
assert(~verdict.Ok,'A measured CRC/BLER failure must still fail the run.');
failures=sixgr.util.csvReadTable(fullfile(ctx.Layout.ReportCSVDir, ...
    'truth_contract_failures.csv'),'TextType','string');
hit=failures.FailureCode=="dl_pdsch_objective_failed:dl_pdsch_bler_objective_failed";
assert(nnz(hit)==1 && failures.FailureCategory(hit)=="physical_performance" && ...
    failures.RequiredFailureCountContribution(hit)==1, ...
    'Keep the physical BLER failure and its contribution; only repair its category.');
assert(verdict.StrictProxyGuardFailureCount==0, ...
    'Measured CRC failures alone must not imply proxy PHY execution.');
runtimePath=fullfile(ctx.Layout.ReportCSVDir,'runtime_operating_mode.csv');
runtime=sixgr.util.csvReadTable(runtimePath,'TextType','string');
runtime.ProxyPHYActive(:)=1;
sixgr.util.csvWriteTable(runtimePath,runtime);
verdict=sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ...
    ctx.ScenarioConfig,ctx.InternalConfig);
failures=sixgr.util.csvReadTable(fullfile(ctx.Layout.ReportCSVDir, ...
    'truth_contract_failures.csv'),'TextType','string');
assert(~verdict.Ok && verdict.StrictProxyGuardFailureCount>0 && ...
    any(failures.FailureCategory=="proxy_or_fallback"), ...
    'The physical-performance category must not waive actual proxy execution.');
fprintf('LLS_PHYSICAL_FAILURE_CLASSIFICATION_PASS unchanged_failure_and_proxy_gates=1\n');
ok=true;
end
