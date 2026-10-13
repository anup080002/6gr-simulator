function ok=testLLSBlockCoverageIsolation()
% Report-only fixtures: no PHY measurements or performance are claimed.
% SRS and TRS share a subsystem, but cannot borrow each other's call proof.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
ctx=llsImplementationHarnessFixture("partial_actual");
scenario=ctx.ScenarioConfig;
scenario.reference_signals.srs_enabled=true;
scenario.reference_signals.trs_enabled=true;
metadata=table("test_only_report_metadata_not_physical_execution", ...
    'VariableNames',{'RuntimeEvidenceStatus'});
sixgr.util.csvWriteTable(fullfile(ctx.Layout.AirInterfaceCSVDir,'srs_trials.csv'),metadata);
sixgr.util.csvWriteTable(fullfile(ctx.Layout.AirInterfaceCSVDir,'trs_trials.csv'),metadata);
profilePath=fullfile(ctx.Layout.ReportCSVDir,'runtime_function_profile.csv');
original=readtable(profilePath,'TextType','string','VariableNamingRule','preserve');
functions=["sixgr.link.runSRSChannelEstimation","sixgr.link.runTRSTracking"];
blocks=["SRS","TRS"];
for k=1:2
    profile=original([1:height(original),1],:);
    profile.FunctionName(end)=functions(k);
    profile.CompleteName(end)=functions(k);
    profile.NumCalls(end)=1;
    profile.TotalTime_s(end)=0.01;
    profile.SelfTimeApprox_s(end)=0.01;
    sixgr.util.csvWriteTable(profilePath,profile);
    out=sixgr.validation.LLSValidationHarness(ctx.RunFolder,scenario, ...
        ctx.InternalConfig,'WriteArtifacts',false);
    selected=out.ValidationMatrix(string(out.ValidationMatrix.BlockId)==blocks(k),:);
    other=out.ValidationMatrix(string(out.ValidationMatrix.BlockId)==blocks(3-k),:);
    assert(height(selected)==1 && height(other)==1 && selected.DUTFunctionActuallyCalled);
    assert(~other.DUTFunctionActuallyCalled && other.DUTCallCount==0, ...
        'testLLSBlockCoverageIsolation:CrossBlockCallEvidence', ...
        '%s must not borrow %s call evidence through a shared subsystem.',blocks(3-k),blocks(k));
    assert(~other.ImplementationPass && ~selected.ImplementationPass, ...
        'A profiler fixture without independent PHY/reference evidence cannot qualify either block.');
    assert(ismember('BlockId',out.RuntimeFunctionCoverage.Properties.VariableNames), ...
        'Coverage records need explicit block identity, not only subsystem identity.');
    coverage=out.RuntimeFunctionCoverage;
    assert(~any(coverage.ActuallyCalled(string(coverage.BlockId)==blocks(3-k))));
end
ok=true;
fprintf('LLS_BLOCK_COVERAGE_ISOLATION_PASS: report fixtures only, no physical qualification\n');
end
