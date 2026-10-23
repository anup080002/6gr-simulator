function ok=testCheckpointExecutionHorizon()
% Real H4 config and production clock/termination helpers; no claim that a
% 60-slot physical scenario or its final plotted artifacts executed here.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.meta.configHash=s.ConfigHash;
original=cfg; saved=s.toStruct();
meta=struct('CompletedSlot',45,'ConfigHash',s.ConfigHash, ...
    'StateSHA256',string(repmat('b',1,64)));
h=sixgr.runtime.CheckpointExecutionHorizon.fromRequest(saved,meta,60, ...
    "component_request_not_a_run",string(repmat('c',1,64)));
beforeRNG=rng;
bounded=sixgr.runtime.CheckpointExecutionHorizon.apply(cfg,h);
assert(isequaln(beforeRNG,rng) && isequaln(saved,s.toStruct()));
assert(bounded.run.totalSlots==60 && bounded.run.numTTI==60 && ...
    bounded.run.numFrames==3 && bounded.run.totalTime_ms==30 && ...
    bounded.run.measurementSlots==60 && bounded.run.measurementTime_ms==30 && ...
    bounded.system.simDuration_s==.03 && bounded.system.measurementTime_s==.03);
for name=string(fieldnames(original)).'
    if any(name==["run","system"]), continue; end
    assert(isequaln(original.(name),bounded.(name)), ...
        'test:BoundedPhysicsChanged','Horizon projection changed %s.',name);
end
assert(isequaln(bounded.run.runtimeCheckpointScenario,original.run.runtimeCheckpointScenario));
assert(bounded.meta.configHash==s.ConfigHash && ...
    bounded.run.runtimeCheckpointScenario.run_control.total_slots==100);
assert(bounded.outputs.saveCSV && bounded.outputs.savePNG && ...
    bounded.outputs.saveRawWaveforms && ~bounded.outputs.emitPlaceholderArtifacts);
assert(sixgr.artifact.liveCSVPlotDue(bounded,60,60));
planCfg=bounded; planCfg.prach_lls.NumSlots=100;
[planned,checks]=sixgr.truth.buildPlannedREAllocation(planCfg,'TargetChannels',"PRACH");
assert(all(checks.resolved(checks.enabled)) && any(string(planned.channel)=="PRACH"));
slots=double(planned.absolute_slot); slots=slots(isfinite(slots));
assert(~isempty(slots)&&all(slots<60), ...
    'Standalone PRACH duration must not expand the bounded connected-run plan.');
restored=struct('SNRGrid',40,'FramesPerPoint',100,'CompletedSlot',45, ...
    'FrameLocal',45,'SweepIndex',1);
sixgr.runtime.CheckpointExecutionHorizon.assertResume(restored,bounded,60,40);
queued=restored; queued.PendingULGrants=struct('Slot',60);
sixgr.runtime.CheckpointExecutionHorizon.assertResume(queued,bounded,60,40);
queued.PendingULGrants.Slot=65;
reject(@()sixgr.runtime.CheckpointExecutionHorizon.assertResume(queued,bounded,60,40), ...
    'sixgr:checkpoint:HorizonCutsFrozenGrant');
reject(@()sixgr.runtime.CheckpointExecutionHorizon.assertResume(restored,original,60,40), ...
    'sixgr:checkpoint:HorizonMismatch');
reject(@()sixgr.runtime.CheckpointExecutionHorizon.assertResume(restored,bounded,60,[30;40]), ...
    'sixgr:checkpoint:HorizonMismatch');
bad=restored; bad.FramesPerPoint=99;
reject(@()sixgr.runtime.CheckpointExecutionHorizon.assertResume(bad,bounded,60,40), ...
    'sixgr:checkpoint:HorizonMismatch');
badcfg=cfg; badcfg.meta.configHash='wrong';
reject(@()sixgr.runtime.CheckpointExecutionHorizon.apply(badcfg,h), ...
    'sixgr:checkpoint:HorizonIdentityMismatch');
% Future checkpoints retain the original science and explicit shorter bound.
next=restored; next.ExecutionHorizon=h; next.FramesPerPoint=60;
next.CompletedSlot=58; next.FrameLocal=58;
meta.CompletedSlot=58;
again=sixgr.runtime.CheckpointExecutionHorizon.fromRequest(saved,meta,60,"next",h.RequestSHA256);
nextcfg=sixgr.runtime.CheckpointExecutionHorizon.apply(cfg,again);
sixgr.runtime.CheckpointExecutionHorizon.assertResume(next,nextcfg,60,40);
extension=again; extension.FinishAfterSlot=70;
extended=sixgr.runtime.CheckpointExecutionHorizon.apply(cfg,extension);
reject(@()sixgr.runtime.CheckpointExecutionHorizon.assertResume(next,extended,70,40), ...
    'sixgr:checkpoint:HorizonExtension');
% Live completion is a 60-slot counter; original planned 100 remains explicit.
state=struct('CurrentSlot',60,'CompletedCanonicalSlots',60, ...
    'CanonicalSlotsPerSweepPoint',60,'SlotsPerFrame',20,'SymbolsPerSlot',14, ...
    'ExecutionHorizon',h);
progress=sixgr.truth.resolveRuntimeClockProgress(state);
assert(progress.TotalSlots==60 && progress.RunCompletion==1 && ...
    progress.OriginalConfiguredSlots==100 && progress.CompletedSymbols==840);
% Publication recovery uses the same executed denominator, never the saved
% scenario horizon. Mismatching or one-sided receipts are rejected.
root=string(tempname); mkdir(fullfile(root,'meta'));
lineage=struct('ExecutionHorizon',h,'CanonicalConfigHash',s.ConfigHash, ...
    'ContinuationRequestSHA256',h.RequestSHA256,'StateSHA256',h.CheckpointStateSHA256);
sixgr.util.jsonWrite(fullfile(root,'meta','checkpoint_resume.json'),lineage);
reject(@()sixgr.runtime.CheckpointExecutionHorizon.restorePublished(cfg,root), ...
    'sixgr:checkpoint:HorizonPublicationIdentity');
sixgr.util.jsonWrite(fullfile(root,'meta','continuation_execution_horizon.json'),h);
published=sixgr.runtime.CheckpointExecutionHorizon.restorePublished(cfg,root);
assert(published.run.totalSlots==60 && published.system.simDuration_s==.03);
% The geometry audit consumes saved configuration (100), not internal cfg.
% Bind its coverage check to the explicit limit without rewriting that file.
configPath=fullfile(root,'meta','scenario_config_resolved.json');
sixgr.util.jsonWrite(configPath,saved);
configBytes=fileread(configPath);
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_identity.json'), ...
    struct('ConfigHash',s.ConfigHash,'ResolvedJSONSHA256',sixgr.util.sha256File(configPath)));
audit=sixgr.validation.auditGeometryScenarioRun(root,'WriteOutputs',false);
assert(audit.ExpectedSlots==60 && ~audit.Ok && isequal(fileread(configPath),configBytes), ...
    'Horizon accounting must not turn absent geometry measurements into a PASS.');
corrupt=h; corrupt.FinishAfterSlot=59;
sixgr.util.jsonWrite(fullfile(root,'meta','continuation_execution_horizon.json'),corrupt);
reject(@()sixgr.runtime.CheckpointExecutionHorizon.restorePublished(cfg,root), ...
    'sixgr:checkpoint:HorizonPublicationIdentity');
% Reject multicase limits instead of misinterpreting per-point versus
% campaign-contiguous slot indices.
multi=saved; multi.sweeps_and_matrix.snr_sweep.enabled=true;
multi.sweeps_and_matrix.snr_sweep.values_db=[30 40];
reject(@()sixgr.runtime.CheckpointExecutionHorizon.fromRequest(multi,meta,60,"bad","x"), ...
    'sixgr:checkpoint:UnsupportedBoundedHorizon');
assert(isequaln(original,cfg));
ok=true; disp('CHECKPOINT_EXECUTION_HORIZON_PASS original=100 executed_limit=60 physics_unchanged=1');
end

function reject(call,id)
try
    call();
catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
