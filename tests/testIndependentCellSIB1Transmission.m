function ok=testIndependentCellSIB1Transmission()
% Actual cell-common SI on shared RF/channel clock with zero UE observers.
% Two registered links do not imply either UE acquired or decoded anything.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
folder=fullfile(pwd,'results','validation','independent_cell_sib1',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('INDEPENDENT_CELL_SIB1_EVIDENCE %s\n',folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
cfg.phy.sib1.transmissionScope="selected_ssb_occasion"; cfg.phy.ssb.runtimeSSBIndex=0;
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),10);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,cfg});
beforeAcquisition=state.CellAcquisitionState;
[~,~,association]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5,'SSBIndex',0);
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
occasions=plan.sib1TransmissionOccasions(0,40);
assert(~isempty(occasions)); slot=occasions.AbsoluteSlot(1);
prepared=sixgr.link.prepareSIB1Transmission(cfg,association,'AbsoluteSlot',slot);
original=prepared.TransmitSamples;
component=stream.queueSIB1Transmission(1,prepared);
assert(isempty(stream.SIB1Transmissions) && numel(stream.Pending)==1 && ...
    stream.Pending.Kind=="CellSIB1TX" && stream.Pending.UE==0, ...
    'Preparation is not a transmission or a UE receive window.');
assert(stream.queueSIB1Transmission(1,prepared)==component && numel(stream.Pending)==1);
bad=prepared; bad.TransmitSamples(1)=bad.TransmitSamples(1)+1;
reject(@()stream.queueSIB1Transmission(1,bad),'sixgr:truth:InconsistentCellSIB1');
reject(@()stream.queueSIB1Transmission(99,prepared),'sixgr:truth:UnknownSIB1Transmitter');
bad=prepared; bad.TransmitStartSample=bad.TransmitStartSample+1;
reject(@()stream.queueSIB1Transmission(1,bad),'sixgr:truth:SharedSIB1PreparationAuthority');
bad=prepared; bad.Tx.SSBEmissionIncluded=true;
reject(@()stream.queueSIB1Transmission(1,bad),'sixgr:truth:SharedSIB1PreparationAuthority');
received=struct([]);
for current=1:slot+1
    state.CurrentSlot=current;
    [state,completed]=stream.advanceSlot(state,cfg);
    for item=completed
        assert(item.Kind=="CellSIB1TX",'No receiver has been armed in this fixture.');
        received=item;
    end
end
assert(isscalar(received) && numel(stream.SIB1Transmissions)==1 && isempty(stream.Pending));
assertSIB1TransmissionCompletion(stream,received);
record=stream.SIB1Transmissions;
assert(isequal(record.PDSCHDataREIndicesZeroBased,prepared.Tx.PDSCHTx.ResourcePlan.DataIndices) && ...
    isequal(record.PDSCHDMRSREIndicesZeroBased,prepared.Tx.PDSCHTx.DMRSIndices) && ...
    isequal(record.PDCCHDataIndicesOneBased,prepared.Tx.PDCCHTx.PDCCHInd) && ...
    isequal(record.PDCCHDMRSIndicesOneBased,prepared.Tx.PDCCHTx.DMRSInd));
observation=received.Planes.Observation;
assert(record.ComponentID==component && record.AbsoluteSlot==slot && ...
    record.CommittedAtSample==prepared.TransmitEndSampleExclusive && ...
    record.TransmitSampleSHA256==observation.sampleHash() && ...
    record.PreparedSampleSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(original) && ...
    any(observation.readComplete()~=0,'all') && ...
    isequaln(state.CellAcquisitionState,beforeAcquisition));
observed=sixgr.truth.buildObservedBroadcastREAllocation(prepared,observation,1);
assert(~isempty(observed) && all(observed.rnti==65535) && ...
    all(observed.associated_ssb_index0==0) && all(isnan(observed.ssb_index0)) && ...
    all(observed.authority=="executed_si_only_tx_grid_and_committed_waveform_interval"));
sixgr.util.csvWriteTable(fullfile(folder,'executed_si_resources.csv'),observed,'PreserveSchema',true);
save(fullfile(folder,'original_si_transmission.mat'),'cfg','prepared','record','observation','-v7.3');
assert(isequal(prepared.TransmitSamples,original));
% Real queue mutations must not turn a completed aggregate TX observation
% into evidence that the original SI component physically executed.
for mutation=["cancel","replace"]
    % Each physical execution owns its own immutable output directory.
    % Do not disable the recorder or overwrite the original positive IQ.
    negativeFolder=fullfile(folder,"negative_"+mutation);
    assert(~isfolder(negativeFolder),'Never reuse independent execution evidence.');
    negativeCfg=sixgr.lls6g.buildInternalConfig(scenario,negativeFolder);
    negativeCfg.run.rootRunFolder=char(negativeFolder);
    negativeCfg.phy.sib1.transmissionScope="selected_ssb_occasion";
    negativeCfg.phy.ssb.runtimeSSBIndex=0;
    negativeState=sixgr.truth.CoupledTruthRuntime.initialize(negativeCfg,negativeFolder,multi,struct(),10);
    negativeState.CurrentSlot=1; negativeState.CurrentServingIdx(:)=1;
    [negativeState,negativeStream]=sixgr.truth.CoupledWaveformStream.initialize( ...
        negativeState,negativeCfg,{negativeCfg,negativeCfg});
    negativeComponent=negativeStream.queueSIB1Transmission(1,prepared);
    if mutation=="cancel"
        negativeStream.Events.cancelUnemittedComponent("gnb_1",negativeComponent);
    else
        replacement=original; replacement(1)=replacement(1)+1;
        negativeStream.Events.replaceUnemittedComponent("gnb_1",negativeComponent, ...
            sixgr.phy.waveform.WaveformChunk(replacement,prepared.TransmitStartSample));
    end
    for current=1:slot
        negativeState.CurrentSlot=current;
        [negativeState,~]=negativeStream.advanceSlot(negativeState,negativeCfg);
    end
    negativeState.CurrentSlot=slot+1;
    reject(@()negativeStream.advanceSlot(negativeState,negativeCfg), ...
        'sixgr:truth:SIB1TransmissionCompletionMismatch');
    assert(isempty(negativeStream.SIB1Transmissions), ...
        'Cancelled/replaced SI must never be committed as original transmission.');
end
fprintf('INDEPENDENT_CELL_SIB1_PASS slot0=%d ue_observers=0 physical_tx=1 folder=%s\n',slot,folder);
ok=true;
end

function reject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s',identifier,cause.identifier); return;
end
error('test:MissingSIB1Rejection','Expected %s',identifier);
end
