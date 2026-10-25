function ok=testSharedMsg1TransmissionCompletion()
% Native Msg1/shared TX and actual silent RAR monitoring. Initial DL clock
% is explicitly DECLARED, not BCH evidence. No cell PRACH RX/response runs.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','msg1_tx_completion',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('MSG1_TX_COMPLETION_EVIDENCE %s\n',folder);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,folder); cfg.run.rootRunFolder=folder;
cfg.outputs.continuousRawIQCaptureEnabled=false;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),cfg.channel.snr_dB);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[uc,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
fs=owner.SampleRateHz;
uc.SharedULTimingContext=struct('DLReference',struct( ...
    'Source',"received_SSB_timing_and_decoded_BCH",'SampleRateHz',fs, ...
    'DLPhaseOffsetSamples',0,'AvailableAtSample',0, ...
    'TestScope',"declared_receiver_clock_not_BCH_evidence"), ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(struct( ...
        'Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false, ...
        'TimingAdvanceOffset',""),"FR1"));
[prepared,cp]=sixgr.phy.ra.runFourStepRA(uc,'WriteArtifacts',false, ...
    'RunId',"actual_msg1_tx_completion",'UEId',1,'AttemptId',1, ...
    'PreamblePowerRampingCounter',1,'RuntimeIntegrationMode','shared_physical_waveform_stream', ...
    'UseRuntimeChannel',true,'RequireRuntimeStageWaveforms',true, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage', ...
    'InitialDLChannelState',owner.directionalChannelState(1,"DL"), ...
    'InitialULChannelState',owner.directionalChannelState(1,"UL"));
p=prepared.PreparedTransmission; original=cp;
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
activeEnd=double(cp.RAConfig.PRACHActiveEndTicksExclusive/int64(tc));
bufferEnd=sixgr.phy.ra.preparedStageTransmitStartSample(p)+p.SampleCount;
assert(activeEnd<bufferEnd,'Native zero padding must distinguish active from full-buffer completion.');
retry=sixgr.mac.ra.RARetryState(4181);
retry=retry.prepare("declared_initial_SSB_reference",int64(0),false,false);
retry=retry.arm(cp.RAConfig); state.RARetryByUE={retry};
state.PendingRAAttempts={struct('Config',uc,'Continuation',cp,'Received',[])};
state.TestOriginalCheckpoint=cp; state.TestTXItem=struct(); state.TestTXCallbackSample=NaN;
state.TestExpiredResult=struct(); state.TestRARCount=0; access=state.AccessState;
badCP=cp; badCP.RAConfig.PRACHActiveEndTicksExclusive=cp.RAConfig.PRACHActiveEndTicksExclusive-int64(tc);
reject(@()owner.queueMsg1Transmission(1,p,badCP),'sixgr:truth:Msg1TransmissionContract');
owner.armRARWindow(1,cp.RAConfig);
id=owner.queueMsg1Transmission(1,p,cp);
assert(~owner.hasPending("RA",1) && owner.hasPending("Msg1TX",1));
reject(@()owner.queueMsg1Transmission(1,p,cp),'sixgr:truth:DuplicateMsg1Transmission');
pending=owner.Pending(string({owner.Pending.Kind})=="Msg1TX");
reject(@()action(uc,cp,owner,pending),'sixgr:truth:Msg1TransmissionContract');
assert(isequaln(state.PendingRAAttempts{1}.Continuation,original) && ...
    state.RARetryByUE{1}.CurrentTransmissionEndTicks==int64(-1));
expiry=double(cp.RAConfig.RARMonitoringWindow.ExpiryTicksExclusive/int64(tc));
assert(expiry/fs<0.1,'Keep this component test below100ms.');
while owner.Events.NextSampleIndex<expiry
    [state,~]=owner.advanceSlot(state,cfg,@complete);
    state.CurrentSlot=state.CurrentSlot+1;
end
r=state.TestExpiredResult;
assert(state.TestTXCallbackSample==activeEnd && state.TestTXCallbackSample<bufferEnd && ...
    state.TestRARCount==numel(cp.RAConfig.RARMonitoringWindow.MonitoringSlots));
assert(isempty(r.ArtifactTables.msg1_prach_detection) && isempty(r.ArtifactTables.msg1_detected_candidates) && ...
    r.RARWindowExpired && r.ExpiredRARReceiver.Status=="expired" && isempty(r.RuntimeStageRows), ...
    'Silence/expiry cannot fabricate a Msg1 detection or paired receiver-stage row.');
assert(state.RARetryByUE{1}.TransmissionCounter==2 && ...
    state.RARetryByUE{1}.PreviousTransmissionEndTicks==cp.RAConfig.PRACHActiveEndTicksExclusive && ...
    isequaln(state.AccessState,access));
item=state.TestTXItem; proof=sixgr.truth.validateMsg1TransmissionCompletion(owner,item,original);
assert(proof.ComponentID==id && proof.PhysicalTransmissionVerified && ~proof.ReceiverExecutionClaimed);
reject(@()sixgr.truth.completeSharedMsg1Transmission(state,item),'sixgr:truth:DuplicateMsg1Transmission');
reject(@()owner.queueMsg1Transmission(1,p,cp),'sixgr:truth:DuplicateMsg1Transmission');
bad=item; bad.UE=2;
reject(@()action(uc,cp,owner,bad),'sixgr:truth:Msg1TransmissionContract');
bad=item; bad.Context.PhysicalConfigurationEpoch=bad.Context.PhysicalConfigurationEpoch+1;
reject(@()action(uc,cp,owner,bad),'sixgr:truth:Msg1TransmissionContract');
bad=item; bad.Context.RAConfig.AttemptId=2;
reject(@()action(uc,cp,owner,bad),'sixgr:truth:Msg1TransmissionContract');
badCP=cp; badCP.RAConfig.PreambleIndex=mod(cp.RAConfig.PreambleIndex+1,64);
reject(@()action(uc,badCP,owner,item),'sixgr:truth:Msg1TransmissionCheckpointMismatch');
badCP=cp; badCP.RAConfig.RARMonitoringWindow.ExpiryTicksExclusive=cp.RAConfig.RARMonitoringWindow.ExpiryTicksExclusive+int64(1);
reject(@()action(uc,badCP,owner,item),'sixgr:truth:Msg1TransmissionCheckpointMismatch');
bad=item; o=item.Planes.Observation;
replacement=sixgr.phy.waveform.WaveformObservationBuffer(o.StartSample,o.EndSampleExclusive,fs,o.NumReceiveAntennas);
replacement.append(sixgr.phy.waveform.WaveformChunk(complex(zeros(o.EndSampleExclusive-o.StartSample,o.NumReceiveAntennas)),o.StartSample),fs);
bad.Planes.Observation=replacement;
reject(@()action(uc,cp,owner,bad),'sixgr:truth:Msg1TransmissionContract');
save(fullfile(folder,'original_msg1_tx_receipt.mat'),'proof','original','activeEnd','bufferEnd','id');
ok=true; fprintf('SHARED_MSG1_TX_COMPLETION_PASS native_MSG1_TX=1 cell_PRACH_RX=0 actual_silent_RAR_windows=%d main_activation=0\n',state.TestRARCount);
end

function state=complete(state,items)
for item=items
    if item.Kind=="Msg1TX"
        assert(isempty(fieldnames(state.TestTXItem)));
        state=sixgr.truth.completeSharedMsg1Transmission(state,item);
        state.TestTXItem=item; state.TestTXCallbackSample=state.SharedWaveformStream.Events.NextSampleIndex;
        cp=state.PendingRAAttempts{1}.Continuation; original=state.TestOriginalCheckpoint;
        assert(cp.NextStage==2 && cp.ResumePhase=="decoded" && ...
            isequaln(cp.RAConfig,original.RAConfig) && isequaln(cp.Msg1Tx,original.Msg1Tx) && ...
            isequaln(cp.RARReceiver,original.RARReceiver) && isempty(fieldnames(cp.Detection)) && ...
            isempty(fieldnames(cp.TimingAdvance)) && isempty(cp.Result.RuntimeStageRows) && ...
            ~isfield(sixgr.util.structGet(cp.Result,'ArtifactTables',struct()),'msg1_prach_detection') && ...
            isempty(state.PendingRAAttempts{1}.Received));
    elseif item.Kind=="RAR"
        a=state.PendingRAAttempts{1}; cp=a.Continuation;
        assert(cp.NextStage==2 && ~isempty(fieldnames(state.TestTXItem)));
        streams=struct('RARPhysicalExecution',struct('Planes',item.Planes));
        [~,next]=sixgr.phy.ra.runFourStepRA(a.Config,'Continuation',cp, ...
            'RuntimeStageWaveforms',streams,'StageAction','receive_rar_observation', ...
            'RARObservationSlot',item.Context.AbsoluteSlot);
        assert(next.NextStage==2 && next.RARReceiver.Status=="waiting" && ...
            isempty(fieldnames(next.Detection)) && isempty(fieldnames(next.TimingAdvance)));
        a.Continuation=next; state.PendingRAAttempts{1}=a; state.TestRARCount=state.TestRARCount+1;
    elseif item.Kind=="RARExpiry"
        a=state.PendingRAAttempts{1};
        [r,~]=sixgr.phy.ra.runFourStepRA(a.Config,'Continuation',a.Continuation, ...
            'StageAction','expire_rar_window','EventTicks',item.Context.ExpiryTicks);
        [retry,~]=state.RARetryByUE{1}.responseExpired(r.ExpiredRARReceiver,item.Context.ExpiryTicks);
        state.RARetryByUE{1}=retry; state.TestExpiredResult=r;
    end
end
end
function action(cfg,cp,owner,item)
[~,~]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',cp,'StageAction','complete_msg1_transmission', ...
    'Msg1TransmissionOwner',owner,'Msg1TransmissionCompletion',item);
end
function reject(fn,id)
try
    fn();
catch cause
    assert(string(cause.identifier)==id,'Unexpected %s (wanted %s): %s',cause.identifier,id,cause.message);
    return;
end
error('test:MissingExpectedFailure','Expected %s.',id);
end
