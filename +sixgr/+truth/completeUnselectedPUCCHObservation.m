function state=completeUnselectedPUCCHObservation(state,item)
% Preserve actual unused receiver/TX audit captures. No PUCCH decoder ran,
% so no ACK/NACK/DTX, detector metric, BER or primary PUCCH trial is invented.
c=item.Context; selection=c.TransportSelection; owner=state.SharedWaveformStream;
assert(item.Kind=="PUCCHNotSelected" && ...
    selection.UEIndex==item.UE && selection.TargetSlot==c.Slot && ...
    numel(item.Planes)==3 && all(arrayfun(@(p)p.Observation.isComplete() && ...
    p.Observation.EndSampleExclusive<=owner.Events.NextSampleIndex,item.Planes)), ...
    'sixgr:truth:InvalidUnselectedPUCCHCompletion','Retain complete actual unselected capture planes.');
previous=sixgr.util.structGet(state,'SharedUnselectedPUCCHObservations',{});
assert(~any(cellfun(@(r)r.Context.TransportSelection.PUCCHObservationID==selection.PUCCHObservationID,previous)), ...
    'sixgr:truth:DuplicateUnselectedPUCCHCompletion','Retain this observation exactly once.');
names=string({item.Planes.ReceiverID}); post=find(endsWith(names,':post_rf')); tx=find(endsWith(names,':tx'));
assert(isscalar(post) && isscalar(tx),'sixgr:truth:InvalidUnselectedPUCCHCompletion','Keep unique physical receiver and TX audit planes.');
row=selection;
row.ObservationStartSample=item.Planes(post).Observation.StartSample;
row.ObservationEndSampleExclusive=item.Planes(post).Observation.EndSampleExclusive;
row.CaptureCompletedAtSample=owner.Events.NextSampleIndex;
row.SampleRateHz=owner.SampleRateHz;
producer=struct(); if isfield(c,'Prepared'), producer=c; end
identity=sixgr.truth.validateUnselectedPUCCHTransmission(state,selection,producer);
row.PUCCHTransmissionPrepared=~isempty(fieldnames(identity));
row.PUCCHTransmissionExecuted=row.PUCCHTransmissionPrepared;
row.PUCCHDecoderInvoked=false;
row.PUCCHFeedbackCommitted=false;
row.Disposition="gnb_scheduled_PUSCH_receiver_PUCCH_capture_unselected";
audit=sixgr.util.structGet(state,'SharedUnselectedPUCCHAuditTable',table());
audit=[audit;struct2table(row,'AsArray',true)];
state.SharedUnselectedPUCCHObservations=[previous,{item}];
state.SharedUnselectedPUCCHAuditTable=audit;
end
