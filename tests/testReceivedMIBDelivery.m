function ok=testReceivedMIBDelivery(state,item,context,recovery,post,folder)
% Reuse the actual shared two-UE/eight-candidate receive test. One separately
% labelled erased-SI negative executes an additional receiver. State transitions are
% explicitly reducer-boundary inputs; this is not the full access campaign.
if nargin==0
    ok=testCellCommonSIB1Broadcast(true); return;
end
owner=state.SharedWaveformStream; ue=double(item.UE);
beforeRNG=rng; beforeClock=owner.Events.NextSampleIndex;
originalHash=post.sampleHash(); originalRecovery=recovery;
dl=recovery.ReceivedDLTimingReference;
binding=sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,item,context,dl,post);
assert(~binding.Delivered && binding.ContextSHA256==context.SHA256 && ...
    binding.DecoderInputSHA256==originalHash && binding.UEIndex==ue && ...
    binding.GenerationID==binding.BindingSHA256);
sixgr.truth.ReceivedMIBDelivery.validate(binding,false);
reject(@()sixgr.truth.ReceivedMIBDelivery.validate(binding,true),'sixgr:truth:ReceivedMIBNotDelivered');

% Actual received candidates remain private until the capture end. No
% guessed SIB1 success/SSB timing or artificially advanced physical clock.
row=table(double(item.Context.Slot),binding.CaptureStartSample,binding.CaptureEndSampleExclusive, ...
    binding.SampleRateHz,binding.CaptureEndSampleExclusive/binding.SampleRateHz, ...
    "complete_contiguous_received_sample_buffer", ...
    'VariableNames',{'Slot','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','ObservationCompletionTime_s','ObservationCoverageSource'});
pending=sixgr.truth.BroadcastResultDelivery.enqueue(state,ue,row,recovery,false,binding);
[waiting,notReady]=sixgr.truth.BroadcastResultDelivery.takeAvailable(pending);
assert(isempty(notReady) && sixgr.truth.BroadcastResultDelivery.hasPending(waiting,ue));
% This boundary is the next scheduler slot; the physical stream has already
% completed it, and no native state is advanced by the delivery reducers.
delivered=pending;
delivered.CurrentSlot=round(beforeClock/(owner.SampleRateHz*state.SlotDuration_s))+1;
delivered.CellAcquisitionState(ue)="acquired";
delivered.LastSuccessfulPBCHSlotByUE(ue)=delivered.CurrentSlot;
[delivered,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(delivered);
assert(isscalar(ready) && isequaln(ready.MIBBinding,binding));
[delivered,installed,status]=sixgr.truth.ReceivedMIBDelivery.deliver(delivered,ready.MIBBinding);
assert(installed && status=="delivered_original_received_MIB");
[available,status,current]=sixgr.truth.ReceivedMIBDelivery.current(delivered,ue);
assert(available && status=="current_delivered_received_MIB" && ...
    current.DeliveredAvailableSample==beforeClock && current.DeliverySlot==delivered.CurrentSlot && ...
    current.ContextSHA256==context.SHA256 && isequaln(current.ReceivedDLTimingReference,dl));
[again,installed,status]=sixgr.truth.ReceivedMIBDelivery.deliver(delivered,binding);
assert(installed && status=="already_delivered_original_context" && ...
    isequaln(again.ReceivedMIBByUE,delivered.ReceivedMIBByUE));

% Operational installation is received-tree authority, not an offline TX
% equality check. Every positive decoder flag/tree/hash remains original.
receivedOnly=recovery; receivedOnly.SIB1TreeEqual=false;
if isfield(receivedOnly,'SIB1TxTree'), receivedOnly=rmfield(receivedOnly,'SIB1TxTree'); end
receivedOnly.SIB1PayloadHashTx="deliberately_not_receiver_authority";
installedState=sixgr.truth.installReceivedSIB1Recovery(delivered,ue,receivedOnly,delivered.CurrentSlot,current);
common=installedState.UECommonCellConfigurationByUE{ue};
assert(common.Source=="decoded_sib1" && common.TreeHash==recovery.SIB1RxTreeHash && ...
    isequaln(common.ReceivedDLTimingReference,dl) && ...
    installedState.DecodedSIB1RecoveryByUE{ue}.ReceivedMIBGenerationID==current.GenerationID);
receiverCfg=item.Context.Prepared.ReceiverConfig;
assert(testReceivedCommonMIBRACHAuthority("combined",receiverCfg, ...
    installedState.DecodedSIB1RecoveryByUE{ue},current));
bad=receivedOnly; bad.DLSCHCrcPass=false;
unchanged=sixgr.truth.installReceivedSIB1Recovery(delivered,ue,bad,delivered.CurrentSlot,current);
assert(isequaln(unchanged,delivered));
bad=receivedOnly; bad.SIB1RxTreeHash="changed";
reject(@()sixgr.truth.installReceivedSIB1Recovery(delivered,ue,bad,delivered.CurrentSlot,current), ...
    'sixgr:truth:InvalidReceivedSIB1Identity');

for kind=["lost","later_acquisition","cell","configuration","physical_epoch"]
    changed=delivered;
    switch kind
        case "lost", changed.CellAcquisitionState(ue)="searching";
        case "later_acquisition", changed.LastSuccessfulPBCHSlotByUE(ue)=delivered.CurrentSlot+1;
        case "cell", changed.CurrentServingIdx(ue)=state.CurrentServingIdx(ue)+1;
        case "configuration", changed.CfgMobility.initial_access.configuration_epoch= ...
                changed.CfgMobility.initial_access.configuration_epoch+1;
        case "physical_epoch"
            % Corrupt the retained receipt, not the actual physical owner.
            changed.ReceivedMIBByUE{ue}.PhysicalConfigurationEpoch=current.PhysicalConfigurationEpoch+1;
            reject(@()sixgr.truth.ReceivedMIBDelivery.current(changed,ue), ...
                'sixgr:truth:InvalidReceivedMIBDelivery'); continue;
    end
    [valid,~,~]=sixgr.truth.ReceivedMIBDelivery.current(changed,ue); assert(~valid);
end
other=3-ue;
[valid,~,~]=sixgr.truth.ReceivedMIBDelivery.current(delivered,other); assert(~valid);
bad=item; bad.UE=other;
reject(@()sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,bad,context,dl,post), ...
    'sixgr:truth:BroadcastCompletedCaptureMismatch');
bad=item; bad.Context.Prepared.ReceiverConfig.initial_access.configuration_epoch= ...
    bad.Context.Prepared.ReceiverConfig.initial_access.configuration_epoch+1;
reject(@()owner.validateCompletedBroadcastObservation(bad), ...
    'sixgr:truth:BroadcastCompletedCaptureMismatch');
bad=dl; bad.AvailableAtSample=bad.AvailableAtSample+1;
reject(@()sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,item,context,bad,post), ...
    'sixgr:truth:ReceivedMIBTimingMismatch');
badBinding=binding; badBinding.ContextSHA256="changed";
reject(@()sixgr.truth.BroadcastResultDelivery.enqueue(state,ue,row,recovery,false,badBinding), ...
    'sixgr:truth:InvalidReceivedMIBDelivery');
badBinding=binding; badBinding.Delivered=0;
reject(@()sixgr.truth.ReceivedMIBDelivery.validate(badBinding,false), ...
    'sixgr:truth:InvalidReceivedMIBDelivery');

% Same bounds and copied exact segment receipts cannot authenticate changed
% original samples. This must fail at the original owner's capture receipt,
% not merely because the preexisting MIB context has a different hash.
bad=item; k=find(endsWith(string({bad.Planes.ReceiverID}),':post_rf'));
raw=bad.Planes(k).Observation; x=raw.readComplete(); x(1,1)=x(1,1)+1;
replacement=sixgr.phy.waveform.WaveformObservationBuffer(raw.StartSample,raw.EndSampleExclusive,raw.SampleRateHz,size(x,2));
replacement.append(sixgr.phy.waveform.WaveformChunk(x,raw.StartSample),raw.SampleRateHz);
bad.Planes(k).Observation=replacement;
reject(@()owner.validateCompletedBroadcastObservation(bad),'sixgr:truth:BroadcastCompletedCaptureMismatch');
reject(@()sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,bad,context,dl,post), ...
    'sixgr:truth:BroadcastCompletedCaptureMismatch');

% Historical empty queues do not acquire a context simply through schema
% migration; the ordinary five-argument API still carries none.
legacy=state; legacy.PendingBroadcastResults=struct('UEIndex',{},'Trial',{}, ...
    'Recovery',{},'TrackingOnly',{},'CompletionTime_s',{});
legacy=sixgr.truth.BroadcastResultDelivery.enqueue(legacy,ue,row,recovery,false);
legacy.CurrentSlot=delivered.CurrentSlot;
[~,readyLegacy]=sixgr.truth.BroadcastResultDelivery.takeAvailable(legacy);
assert(isscalar(readyLegacy) && isempty(readyLegacy.MIBBinding));
if ue==1
    % Explicit sample-erasure experiment, NOT another original owner
    % observation. Preserve actually encoded BCH samples; erase only the
    % later SI region to exercise the original native decoder outcomes.
    p=item.Context.Prepared;
    si=sixgr.phy.broadcast.retainedSIB1Transmissions(p.Tx);
    cut=min([si.SIB1WaveformStartSample]);
    samples=post.readComplete();
    assert(cut>0 && cut<size(samples,1));
    samples(cut+1:end,:)=0;
    erased=sixgr.phy.waveform.WaveformObservationBuffer(post.StartSample,post.EndSampleExclusive, ...
        post.SampleRateHz,post.NumReceiveAntennas);
    erased.append(sixgr.phy.waveform.WaveformChunk(samples,post.StartSample),post.SampleRateHz);
    [noSI,prior]=sixgr.phy.broadcast.recoverSIB1FromWaveform(erased,p.ReceiverConfig, ...
        'CandidateSSBIndex',context.Data.SSBIndex);
    assert(noSI.BCHCRCValid && noSI.MIBDecoded && noSI.CandidateIdentityConsistent && ...
        noSI.SSBIdentityVerified && noSI.PBCHStrictReceiverEvidenceOk && ...
        isa(prior,'sixgr.phy.broadcast.ReceivedMIBContext') && ...
        prior.Data.OriginalStrictReceiverEvidenceOk && ~noSI.StrictOk && ...
        ~(noSI.DCICrcPass && noSI.DLSCHCrcPass), ...
        'Original accepted BCH must survive an actually failed later SI decoder.');
    % Never mislabel the erased experiment as the original shared capture.
    reject(@()sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,item,prior,dl,erased), ...
        'sixgr:truth:ReceivedMIBCaptureMismatch');
    save(fullfile(folder,'declared_SI_erasure_original_BCH.mat'),'noSI','prior','cut');
end
assert(isequaln(recovery,originalRecovery) && post.sampleHash()==originalHash && ...
    owner.Events.NextSampleIndex==beforeClock && isequal(beforeRNG,rng));
save(fullfile(folder,sprintf('ue_%d_original_MIB_delivery.mat',ue)), ...
    'binding','current','row','common','status');
fprintf('RECEIVED_MIB_DELIVERY_PASS UE=%d actual_shared_capture=1 candidate=%d additional_erased_SI_receiver_calls=%d generation_replacement_scope=pending_new_capture_test\n', ...
    ue,context.Data.SSBIndex,double(ue==1));
ok=true;
end

function reject(fn,id)
try, fn(); catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return;
end
error('test:ExpectedReceivedMIBRejection','Expected %s.',id);
end
