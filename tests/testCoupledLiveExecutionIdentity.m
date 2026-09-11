function ok=testCoupledLiveExecutionIdentity()
% Explicit metadata fixture, not PHY qualification or a measured radio run.
setup6GRSimToolkit('Verbose',false);
for profile=["lls_causal_access_to_data_wiring_tdd.yaml","lls_causal_access_to_data_wiring.yaml"]
    root=tempname; mkdir(root);
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',profile));
    cfg=sixgr.lls6g.buildInternalConfig(s,root);
    cfg.run.runTag="metadata_fixture_run";
    cfg.run.executionID="metadata_fixture_execution";
    cfg.run.scenarioID="metadata_fixture_scenario";
    cfg.meta.configHash=string(repmat('a',1,64));
    row=table(1,1,"metadata_fixture_only",'VariableNames',{'Slot','UEIndex','Source'});
    for signal=["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSI-RS","TRS"]
        bound=sixgr.truth.bindCoupledExecutionIdentity(row,cfg,signal);
        assert(bound.RunID==cfg.run.runTag && bound.ExecutionID==cfg.run.executionID);
        assert(isequaln(bound(:,row.Properties.VariableNames),row));
        assert(isequaln(bound,sixgr.truth.bindCoupledExecutionIdentity(bound,cfg,signal)));
        if any(signal==["DL","UL"])
            csvPath=fullfile(root,signal+"_live_identity_fixture.csv");
            sixgr.util.csvWriteTable(csvPath,bound,'PreserveSchema',true);
            persisted=sixgr.util.csvReadTable(csvPath,'TextType','string');
            assert(persisted.RunID==cfg.run.runTag && ...
                persisted.ExecutionID==cfg.run.executionID && ...
                persisted.Source==row.Source);
        end
        bad=bound; bad.ExecutionID="another_execution";
        localMustFail(@() sixgr.truth.bindCoupledExecutionIdentity(bad,cfg,signal));
    end
    legacy=row; legacy.RunID=NaN;
    repaired=sixgr.truth.bindCoupledExecutionIdentity(legacy,cfg,"PBCH");
    assert(repaired.RunID==cfg.run.runTag);
    database=row; database.DatabaseRunID=42;
    preserved=sixgr.truth.bindCoupledExecutionIdentity(database,cfg,"SRS");
    assert(preserved.DatabaseRunID==42 && preserved.RunID==cfg.run.runTag);
    database.RunID=42;
    localMustFail(@() sixgr.truth.bindCoupledExecutionIdentity(database,cfg,"SRS"));
    assert(isequaln(row,sixgr.truth.bindCoupledExecutionIdentity(row,struct(),"SRS")));

    % Exercise the real live writer, before bundle terminal identity binding.
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',8101, ...
        'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),1);
    state.ControlTrials.PBCH=row;
    state.ControlTrials.SRS=row;
    state.ControlTrials.TRS=row;
    state=sixgr.truth.CoupledTruthRuntime.writeTables(state,root);
    for signal=["pbch","srs","trs"]
        T=readtable(fullfile(root,'air_interface','csv',signal+"_trials.csv"), ...
            'TextType','string','VariableNamingRule','preserve', ...
            'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0);
        assert(T.RunID==cfg.run.runTag && T.ExecutionID==cfg.run.executionID);
        assert(T.ConfigHash==cfg.meta.configHash && T.ScenarioID==cfg.run.scenarioID);
    end
    state.ControlTrials.PBCH.ExecutionID="another_execution";
    localMustFail(@() sixgr.truth.CoupledTruthRuntime.writeTables(state,root));
end
ok=true;
fprintf('PASS testCoupledLiveExecutionIdentity\n');
end

function localMustFail(fn)
try
    fn();
catch ME
    assert(string(ME.identifier)=="sixgr:truth:CoupledControlIdentityMismatch",'%s: %s',ME.identifier,ME.message);
    return;
end
error('testCoupledLiveExecutionIdentity:ExpectedFailure','Identity conflict was not rejected.');
end
