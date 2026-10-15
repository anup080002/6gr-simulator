function ok=testLLSDirectionalLifecycleStatus()
% Authored export-contract fixture, not measured PHY performance.
setup6GRSimToolkit('Verbose',false);
for missingDirection=["UL","DL"]
    ctx=llsRootGateFixture("pass");
    dlPath=fullfile(ctx.Layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv');
    ulPath=fullfile(ctx.Layout.AirInterfaceCSVDir,'ul_pusch_trials.csv');
    dl=sixgr.util.csvReadTable(dlPath); ul=sixgr.util.csvReadTable(ulPath);
    if missingDirection=="UL"
        ul=ul([],:); sixgr.util.csvWriteTable(ulPath,ul,'PreserveSchema',true);
    else
        dl=dl([],:); sixgr.util.csvWriteTable(dlPath,dl,'PreserveSchema',true);
    end
    verdict=sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder,ctx.ScenarioConfig,ctx.InternalConfig);
    assert(~verdict.Ok && ~verdict.CheckDetails.RawLifecycle.RawLifecycleOk);
    assert(verdict.CheckDetails.RawLifecycle.DLRawLifecycleOk==(missingDirection=="UL") && ...
        verdict.CheckDetails.RawLifecycle.ULRawLifecycleOk==(missingDirection=="DL"));
    root=sixgr.truth.evaluateStrictAnchorStatus(ctx.RunFolder,ctx.ScenarioConfig, ...
        ctx.InternalConfig,verdict,dl,ul);
    rows=root.ConformanceMatrix.Rows;
    assert(rows.Pass(rows.Subsystem=="data_dl")== (missingDirection=="UL") && ...
        rows.Pass(rows.Subsystem=="data_ul")== (missingDirection=="DL"), ...
        'A missing direction must fail the run, not erase the other direction''s completed evidence.');
end
ok=true; fprintf('PASS testLLSDirectionalLifecycleStatus\n');
end
