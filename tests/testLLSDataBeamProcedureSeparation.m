function ok=testLLSDataBeamProcedureSeparation()
% Bounded reporting-contract fixtures, not a physical beam qualification.
% A data precoder alone must not create P2 convergence/switch/recovery proof.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','lls','beam_procedure_export_fixture', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
cfg.run.runTag="beam_procedure_table_fixture";
cfg.run.executionID="beam_procedure_table_fixture_execution";
cfg.run.scenarioID="beam_procedure_table_fixture_scenario";
cfg.meta.configHash=string(repmat('c',1,64));
cfg.run.totalSlots=2;
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.BeamformingCSVDir);
raw=table([1;2],[1;1],[40;40],[3;5], ...
    repmat("authored_reporting_fixture_not_physical_run",2,1), ...
    'VariableNames',{'Slot','UEIndex','ConfiguredSNR_dB','SelectedBeamIndex','Source'});
raw=sixgr.truth.bindCoupledExecutionIdentity(raw,cfg,"DL");
raw.Frame=ones(height(raw),1);
precoder=raw;
precoder.Direction=repmat("DL",2,1);
precoder.BestBeamIndex=[3;6]; precoder.BeamHit=[1;0];
precoder.TopKBeamHit=[1;1]; precoder.BeamCandidateCount=[8;8];
precoder.PrecodingNumLayers=[1;2]; precoder.PrecodingNumPorts=[8;8];
precoderPath=fullfile(layout.BeamformingCSVDir,'beam_precoder_table.csv');
sixgr.util.csvWriteTable(precoderPath,precoder,'PreserveSchema',true);
hash=string(sixgr.util.sha256File(precoderPath));
stateBefore=rng;
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct('DL',raw));
assert(isequal(rng,stateBefore) && string(sixgr.util.sha256File(precoderPath))==hash);
assert(isempty(out.BeamP2RefinementStats), ...
    'Data-beam observations must not manufacture a refinement procedure.');
data=out.DataBeamSelectionStats;
assert(~isempty(data) && all(data.BeamManagementProcedure=="runtime_data_beam_selection"));
hits=data(data.Metric=="DataBeamHitRate",:);
assert(isequal(hits.MeanValue,[1;0]) && isequal(hits.Slot,[1;2]) && ...
    all(hits.SampleCount==1) && all(hits.RunID==cfg.run.runTag) && ...
    all(hits.ExecutionID==cfg.run.executionID), ...
    'Selection measurements, counts and identity must survive unchanged.');
assert(~any(startsWith(data.Metric,"P2")));

% An unrelated execution must not enter either procedure's primary summary.
stale=precoder; stale.ExecutionID(:)="different_execution";
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir,'probe_beam_mimo.csv'),stale);
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct('DL',raw));
assert(~any(contains(out.BeamSelectionStats.TraceSource,'probe_beam_mimo')));
assert(isempty(out.BeamP2RefinementStats));

% The complete report consumer must publish data hit-rate, not convergence.
manifest=struct('CodeVersion',"fixture",'CodeDetail',"fixture", ...
    'RandomSeed',1,'GeneratedUTC',"fixture",'RunnerProfile',"reporting_contract_fixture", ...
    'RunCompletion',"failed",'DeterministicMode',"fixture");
report=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
    manifest,struct('StartedUTC',"fixture",'ElapsedSeconds',1),struct());
rows=report.CategoryRows;
hits=rows(rows.MetricKey=="beam_index_hit_rate" & endsWith(rows.Statistic,"_mean"),:);
assert(height(hits)==2 && isequal(hits.ValueNumeric,[1;0]) && ...
    all(hits.Entity=="runtime_data_beam_selection") && ...
    all(contains(hits.Notes,'BeamManagementProcedure=runtime_data_beam_selection')));
assert(~any(rows.MetricKey=="beam_refinement_convergence" & ...
    isfinite(rows.ValueNumeric) & rows.CountsTowardCoverage), ...
    'A selected data beam cannot establish refinement convergence.');

% Real event fields remain reportable independently; no event is inferred
% from a precoder match or merely from entering a P2_REFINING state.
event=raw(2,:); event.FirstHitEventFlag=1; event.TrialsToFirstHit=3;
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, ...
    'beam_management_event_trace.csv'),event,'PreserveSchema',true);
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct('DL',raw));
p2=out.BeamP2RefinementStats;
assert(all(p2.SignalSourceFamily=="BEAM_EVENT_TRACE") && ...
    any(p2.Metric=="P2TrialsToFirstHit" & p2.MeanValue==3) && ...
    ~any(contains(p2.TraceSource,'beam_precoder_table')));
assert(string(sixgr.util.sha256File(precoderPath))==hash);
fprintf('LLS_DATA_BEAM_PROCEDURE_SEPARATION_PASS fixture_only=1 folder=%s\n',root);
ok=true;
end
