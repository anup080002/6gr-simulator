function ok=testCSIObservationPopulation()
% Pure declared metadata boundaries, NOT waveform or archive qualification.
setup6GRSimToolkit('Verbose',false);
[state,cfg,row,receipt]=fixture();
p=sixgr.truth.captureCSIObservationPopulation(state,cfg,6,0);
assert(p.Fields.RandomSeed==11 && p.Fields.ChannelSeed==22 && ...
    p.Fields.SweepPointIndex==3 && p.Fields.ConfiguredSNR_dB==0 && ...
    ~isfield(p.Fields,'NoiseSeed') && ~isfield(p.Fields,'NoiseStreamSeed'));
before=p;
% Later callback state must not replace the original queue population.
state.CurrentSweepPointIndex=9;
state.CurrentSNR_dB=99;
cfg.run.runTag="later_run"; cfg.meta.configHash="later_configuration";
out=sixgr.truth.bindCSIObservationPopulation(row,p,receipt,"declared_CSI_component");
assert(isequaln(p,before) && out.SweepPointIndex==3 && out.ConfiguredSNR_dB==0 && ...
    out.RunID=="declared_run" && out.RunTag=="declared_run" && ...
    out.ConfigHash=="declared_configuration" && out.NoiseStreamSeed==777 && ...
    out.CSIObservationPopulationSHA256==p.SHA256);
assert(isequaln(out,sixgr.truth.bindCSIObservationPopulation(out,p,receipt,"declared_CSI_component")));
% Public projection must preserve multiple populations without merging them
% or substituting the publication container's logical run ID for the source.
[secondState,secondCfg,secondRow,secondReceipt]=fixture();
secondState.CurrentSweepPointIndex=4;
secondPopulation=sixgr.truth.captureCSIObservationPopulation(secondState,secondCfg,6,-10);
second=sixgr.truth.bindCSIObservationPopulation(secondRow,secondPopulation,secondReceipt,"declared_CSI_component");
source=[out;second];
meta=struct('logical_run_id',"declared_publication_container",'run_id',1);
public=sixgr.truth.buildLLSPublicOutputTables(struct('csi_rs_table',source),sixgr.truth.llsOutputContract(),meta);
projected=public.csi_rs_runtime_event_table;
assert(height(projected)==2 && isequal(projected.SweepPointIndex,[3;4]) && ...
    isequal(projected.ConfiguredSNR_dB,[0;-10]) && ...
    isequal(projected.CSIObservationPopulationSHA256,source.CSIObservationPopulationSHA256) && ...
    all(projected.SourceRunID=="declared_run") && ...
    all(projected.RunId=="declared_publication_container") && isempty(public.csi_report_table));
later=sixgr.truth.captureCSIObservationPopulation(state,cfg,6,99);
assert(later.SHA256~=p.SHA256);
mustFail(@()sixgr.truth.bindCSIObservationPopulation(out,later,receipt,"declared_CSI_component"), ...
    'sixgr:truth:CSIObservationPopulationConflict');
bad=p; bad.Fields.SweepPointIndex=4;
mustFail(@()sixgr.truth.bindCSIObservationPopulation(row,bad,receipt,"declared_CSI_component"), ...
    'sixgr:truth:CSIObservationPopulationDigest');
badRow=row; badRow.ConfigHash="transplanted_configuration";
mustFail(@()sixgr.truth.bindCSIObservationPopulation(badRow,p,receipt,"declared_CSI_component"), ...
    'sixgr:truth:CSIObservationPopulationConflict');
for field=["Slot","ServingCell","SampleRateHz","PhysicalConfigurationEpoch","CommittedAtSample"]
    badReceipt=receipt; badReceipt.(field)=badReceipt.(field)+1;
    mustFail(@()sixgr.truth.bindCSIObservationPopulation(row,p,badReceipt,"declared_CSI_component"), ...
        'sixgr:truth:CSIObservationPopulationReceipt');
end
mustFail(@()sixgr.truth.bindCSIObservationPopulation(row,p,receipt,"other_component"), ...
    'sixgr:truth:CSIObservationPopulationReceipt');
badRow=row; badRow.ResultAvailableAtSample=receipt.CommittedAtSample-1;
mustFail(@()sixgr.truth.bindCSIObservationPopulation(badRow,p,receipt,"declared_CSI_component"), ...
    'sixgr:truth:CSIObservationPopulationReceipt');
% Components may omit lifecycle. Neither folders nor noise seeds fill it.
cfg=struct(); state=rmfield(state,'CurrentSweepPointIndex');
missing=sixgr.truth.captureCSIObservationPopulation(state,cfg,6,0);
unbound=sixgr.truth.bindCSIObservationPopulation(row,missing,receipt,"declared_CSI_component");
assert(unbound.RunID=="" && unbound.RunFolder=="" && unbound.ExecutionID=="" && ...
    unbound.ConfigHash=="" && unbound.ScenarioID=="" && isnan(unbound.RandomSeed) && ...
    isnan(unbound.ChannelSeed) && isnan(unbound.SweepPointIndex) && unbound.NoiseStreamSeed==777);
badRow=row; badRow.RunID="late_invented_identity";
mustFail(@()sixgr.truth.bindCSIObservationPopulation(badRow,missing,receipt,"declared_CSI_component"), ...
    'sixgr:truth:CSIObservationPopulationConflict');
cfg=struct('run',struct('executionID',[],'seed',[]));
assert(isequaln(missing,sixgr.truth.captureCSIObservationPopulation(state,cfg,6,0)), ...
    'Empty component metadata must remain missing, not become an invented identity.');
% Clock portability is metadata-only here: never scale sample indices from
% a numerology label or assume every carrier has the n40 sample rate.
for fs=[7.68e6 30.72e6]
    [otherState,otherCfg,otherRow,otherReceipt]=fixture();
    otherState.SharedWaveformStream.SampleRateHz=fs;
    otherRow.ObservationSampleRateHz=fs; otherReceipt.SampleRateHz=fs;
    other=sixgr.truth.captureCSIObservationPopulation(otherState,otherCfg,6,0);
    bound=sixgr.truth.bindCSIObservationPopulation(otherRow,other,otherReceipt,"declared_CSI_component");
    assert(other.Queue.SampleRateHz==fs && bound.ObservationSampleRateHz==fs && ...
        other.Queue.QueuedAtSample==100 && bound.ResultAvailableAtSample==270);
end
fprintf('CSI_OBSERVATION_POPULATION_PASS immutable_queue=1 exact_receipt=1 missing_preserved=1 physical_qualification=0\n');
ok=true;
end

function [state,cfg,row,receipt]=fixture()
% Explicit value fixture; no physical owner or completed transmission claim.
state=struct('CurrentSweepPointIndex',3,'CurrentSNR_dB',42, ...
    'SharedWaveformStream',struct('Events',struct('NextSampleIndex',100), ...
    'Physical',struct('ConfigurationEpoch',7),'SampleRateHz',30.72e6));
cfg=struct('run',struct('rootRunFolder',"declared_root_not_an_inferred_ID", ...
    'runTag',"declared_run",'executionID',"declared_execution", ...
    'scenarioID',"declared_scenario",'seed',11), ...
    'meta',struct('configHash',"declared_configuration"),'channel',struct('seed',22));
row=table(6,1,30.72e6,7,"shared_receiver_sample_clock/v1",250,270,777, ...
    'VariableNames',{'Slot','CellID','ObservationSampleRateHz','MeasurementClockEpoch', ...
    'MeasurementClockDomain','ObservationEndSampleExclusive','ResultAvailableAtSample','NoiseStreamSeed'});
receipt=struct('ComponentID',"declared_CSI_component",'SignalFamily',"CSI-RS", ...
    'ServingCell',1,'Slot',6,'FirstActiveSample',150,'CommittedAtSample',200, ...
    'EndSampleExclusive',200,'SampleRateHz',30.72e6,'PhysicalConfigurationEpoch',7);
end

function mustFail(f,identifier)
try, f(); catch exception
    assert(strcmp(exception.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,exception.identifier,exception.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',identifier);
end
