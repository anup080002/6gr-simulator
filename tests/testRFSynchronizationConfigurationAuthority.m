function ok=testRFSynchronizationConfigurationAuthority()
% Report-only numerical fixtures: never waveform qualification evidence.
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_result_richness.yaml');
source=scfg.toStruct();
root=fullfile(pwd,'results','lls','rf_sync_configuration', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
runtime=sixgr.lls6g.buildInternalConfig(scfg,root);
assert(runtime.phy.impairments.cfoHz==40 && ...
    runtime.phy.impairments.timingOffsetSamples==16);
T=table([40;40],[40;40],[0;0],[16;16],[16;16],[0;0], ...
    'VariableNames',{'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz', ...
    'ResidualCFO_PostCorrection_Hz','InjectedTimingOffset_samples', ...
    'EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples'});
raw=struct('DL',T,'UL',T);
for representation=["source","runtime"]
    if representation=="source", cfg=source; else, cfg=runtime; end
    a=sixgr.analytics.writeRFInterferenceReconciliation(cfg, ...
        fullfile(root,representation),raw,struct(),struct());
    assert(all(a.Tables.CFO.ConfiguredCFO_Hz==40) && ...
        all(a.Tables.CFO.CFOEstimationRequired) && ...
        all(a.Tables.CFO.CfoConfiguredAppliedOk));
    assert(all(a.Tables.Timing.ConfiguredTimingOffset_samples==16) && ...
        all(a.Tables.Timing.TimingOffsetConfiguredAppliedOk));
end
% Explicit disabled stages are zero injections even when a saved request
% retains a nonzero setting for the next enabled experiment.
disabled=source;
disabled.impairments.cfo_enabled=false;
disabled.impairments.timing_offset_enabled=false;
identity=T; identity{:,:}=0;
identity.EstimatedCFO_PreCorrection_Hz(:)=NaN;
identity.ResidualCFO_PostCorrection_Hz(:)=NaN;
a=sixgr.analytics.writeRFInterferenceReconciliation(disabled, ...
    fullfile(root,'disabled'),struct('DL',identity,'UL',identity),struct(),struct());
assert(all(a.Tables.CFO.ConfiguredCFO_Hz==0) && ...
    ~any(a.Tables.CFO.CFOEstimationRequired) && all(a.Tables.CFO.CfoConfiguredAppliedOk));
assert(all(a.Tables.Timing.ConfiguredTimingOffset_samples==0));
% Missing or mismatched observations cannot disappear from the population.
for variant=["missing_injection","missing_estimator","missing_residual", ...
        "wrong_injection","large_residual"]
    bad=T;
    switch variant
        case "missing_injection"
            bad.InjectedCFO_Hz(2)=NaN; bad.InjectedTimingOffset_samples(2)=NaN;
        case "missing_estimator"
            bad.EstimatedCFO_PreCorrection_Hz(2)=NaN;
            bad.EstimatedTimingOffset_PreCorrection_samples(2)=NaN;
        case "missing_residual"
            bad.ResidualCFO_PostCorrection_Hz(2)=NaN;
            bad.ResidualTimingError_PostCorrection_samples(2)=NaN;
        case "wrong_injection"
            bad.InjectedCFO_Hz(2)=80; bad.InjectedTimingOffset_samples(2)=32;
        case "large_residual"
            bad.ResidualCFO_PostCorrection_Hz(2)=4;
            bad.ResidualTimingError_PostCorrection_samples(2)=4;
    end
    a=sixgr.analytics.writeRFInterferenceReconciliation(runtime, ...
        fullfile(root,variant),struct('DL',bad,'UL',bad),struct(),struct());
    assert(~any(a.Tables.CFO.CfoConfiguredAppliedOk) && ...
        ~any(a.Tables.Timing.TimingOffsetConfiguredAppliedOk), ...
        'Incomplete/failed synchronization evidence was accepted: %s.',variant);
end
fprintf('RF_SYNC_CONFIGURATION_NUMERICAL_FIXTURES=%s\n',root);
ok=true;
end
