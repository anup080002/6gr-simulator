function ok=testLLSDerivedBeamExecutionIdentity()
% Metadata-only fixture for raw-memory -> derived-summary provenance.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.run.runTag="derived_beam_identity_fixture";
cfg.run.executionID="derived_beam_execution_fixture";
cfg.run.scenarioID="derived_beam_scenario_fixture";
cfg.meta.configHash=string(repmat('b',1,64));
pbch=table([1;1],[1;1],[0;1],[-80;-70],[12;12], ...
    'VariableNames',{'UEIndex','Slot','SSBIndex','SS_RSRP_dBm','ConfiguredSNR_dB'});
pbch.Source=repmat("metadata_fixture_not_runtime_phy",2,1);
reference=sixgr.truth.bindCoupledExecutionIdentity(pbch,cfg,"PBCH");
root=tempname;
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.BeamformingCSVDir);
stale=table("stale_run","stale_execution",1,7.5, ...
    'VariableNames',{'RunID','ExecutionID','SelectedBeamIndex','SelectedBeamGain_dB'});
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, ...
    'probe_beam_mimo.csv'),stale);
artifacts=sixgr.truth.exportLLSLiveDerivedTables(cfg,root, ...
    struct('PBCH',pbch),struct(),struct(),struct());
derived=readtable(artifacts.BeamP1AcquisitionStatsPath,'Delimiter',',', ...
    'TextType','string','VariableNamingRule','preserve','NumHeaderLines',0);
assert(~isempty(derived) && all(derived.RunID==reference.RunID(1)) && ...
    all(derived.ExecutionID==reference.ExecutionID(1)), ...
    'test:DerivedBeamIdentityMissing', ...
    'Derived summaries must retain the same lifecycle identity as live primary rows.');
assert(all(contains(derived.IdentityScope,"RunID")) && ...
    all(contains(derived.IdentityScope,"ExecutionID")));
p2=readtable(artifacts.BeamP2RefinementStatsPath,'Delimiter',',', ...
    'TextType','string','VariableNamingRule','preserve','NumHeaderLines',0);
assert(~any(string(p2.TraceSource)=="beamforming/csv/probe_beam_mimo.csv"), ...
    'test:StaleAuxiliaryBeamPromoted', ...
    'A beam artifact from another execution was promoted into this run.');
bad=reference; bad.ExecutionID(:)="different_observed_execution";
try
    sixgr.truth.exportLLSLiveDerivedTables(cfg,tempname, ...
        struct('PBCH',bad),struct(),struct(),struct());
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:CoupledControlIdentityMismatch'));
    ok=true;
    fprintf('LLS_DERIVED_BEAM_EXECUTION_IDENTITY_PASS: lifecycle binding and conflict rejection.\n');
    return;
end
error('test:MissingIdentityConflict','Conflicting observed identity was silently accepted.');
end
