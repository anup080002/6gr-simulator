function assertBufferedPriorULTiming(reference,cfg)
% Alignment-only boundary fixture. The reference is an actual received
% pilot; the deterministic target buffer is NOT a PUCCH/decoder result.
assert(isa(reference,'sixgr.phy.sync.ReceivedULTimingReference'));
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=reference.SampleRateHz;
sourceSlot=sixgr.phy.frame.slotIndexFromStartSample(carrier,reference.NominalStartSample,fs);
assert(sixgr.phy.frame.slotStartSample(carrier,sourceSlot,fs)==reference.NominalStartSample);
slot=sourceSlot+1;
nominal=sixgr.phy.frame.slotStartSample(carrier,slot,fs);
count=sixgr.phy.frame.slotStartSample(carrier,slot+1,fs)-nominal;
arrival=nominal+reference.ArrivalOffsetFromNominalSamples;
first=min([reference.AvailableAtSample-1 nominal arrival]);
last=max(arrival+count,reference.AvailableAtSample);
buffer=makeBuffer(first,last,fs);
reject(@()reference.alignObservation(cfg,buffer,slot),'FutureULTimingReference');
[samples,evidence]=reference.alignCompletedObservation(cfg,buffer,slot);
raw=buffer.readComplete(); offset=arrival-first;
assert(isequal(samples,raw(offset+(1:count),:)) && ...
    reference.AvailableAtSample>buffer.StartSample && ...
    reference.AvailableAtSample<=buffer.EndSampleExclusive && ...
    ~evidence.OracleTimingUsed && ~evidence.ReceiverZeroPaddingUsed);
assert(evidence.TimingSource=="prior_received_UL_pilot_constant_phase_prediction" && ...
    isnan(evidence.TimingOffsetSamples),'A prior pilot must not become a current timing measurement.');
assert(evidence.ReferenceAvailableDuringBuffer && ...
    evidence.ReceiverTimingAvailableAtSample==reference.AvailableAtSample);
assert(evidence.ReferenceAgeSlots==1 && ...
    evidence.ReferenceSourceAbsoluteSlot0==sourceSlot && evidence.TargetAbsoluteSlot0==slot);
% Selection and reception must agree about the completion deadline.
state=struct('ReceivedULTimingReferences',{{reference}});
assert(isempty(sixgr.truth.selectReceivedULTimingReference(state,1,first)));
assert(isequaln(reference,sixgr.truth.selectReceivedULTimingReference(state,1,last,nominal)));
early=makeBuffer(first-1,reference.AvailableAtSample-1,fs);
reject(@()reference.alignCompletedObservation(cfg,early,slot),'FutureULTimingReference');
if sourceSlot>0
    reject(@()reference.alignCompletedObservation(cfg,buffer,sourceSlot-1),'FutureULTimingReference');
end
stale=cfg; stale.phy.synchronization.maxReceivedULTimingAgeSlots=0;
reject(@()reference.alignCompletedObservation(stale,buffer,slot),'StaleULTimingReference');
wrong=cfg; wrong.phy.pusch.RNTI=cfg.phy.pusch.RNTI+1;
reject(@()reference.alignCompletedObservation(wrong,buffer,slot),'ULTimingReferenceIdentityMismatch');
fprintf('BUFFERED_PRIOR_UL_TIMING_PASS source_slot0=%d target_slot0=%d available=%d buffer=[%d,%d) alignment_fixture_not_UCI_decode=1\n', ...
    sourceSlot,slot,reference.AvailableAtSample,first,last);
end

function b=makeBuffer(first,last,fs)
b=sixgr.phy.waveform.WaveformObservationBuffer(first,last,fs,1);
% Deliberately nonphysical deterministic values check exact sample indexing.
x=complex((1:last-first)',-(1:last-first)');
b.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end

function reject(fn,suffix)
try, fn(); catch err
    assert(strcmp(err.identifier,['sixgr:phy:sync:' suffix]),'%s',err.message); return;
end
error('test:ExpectedTimingRejection','Expected %s.',suffix);
end
