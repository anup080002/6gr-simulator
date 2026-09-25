function ok=testReceivedSameSlotTimingReplay(capturePath)
% Actual slot-35 SRS samples from the failed -10 dB run; timing-only replay.
% No PUCCH payload or new successful reception is manufactured here.
assert(nargin==1 && isfile(capturePath));
digest=sixgr.phy.waveform.WaveformHash.file(capturePath);
x=load(capturePath,'capture'); c=x.capture; p=c.Prepared;
cfg=p.ReceiverConfig; fs=c.SampleRateHz;
buffer=sixgr.phy.waveform.WaveformObservationBuffer(c.RXStartSample,c.RXEndSampleExclusive, ...
    fs,size(c.RXAfterDigitalGainCompensation,2));
buffer.append(sixgr.phy.waveform.WaveformChunk(c.RXAfterDigitalGainCompensation,c.RXStartSample),fs);
reference=sixgr.truth.retainReceivedSRSTimingReference(p,buffer,c.ReceivedResult);
assert(isa(reference,'sixgr.phy.sync.ReceivedULTimingReference'));
carrier=sixgr.phy.grid.makeCarrier(cfg);
slot0=round(reference.NominalStartSample/(fs*1e-3*15/carrier.SubcarrierSpacing));
reject(@()reference.alignObservation(cfg,buffer,slot0),'sixgr:phy:sync:FutureULTimingReference');
[samples,evidence]=reference.alignCompletedObservation(cfg,buffer,slot0);
assert(evidence.ReferenceAgeSlots==0 && evidence.ReferenceAvailableAtSample==buffer.EndSampleExclusive);
offset=c.ReceivedResult.ReceiveTiming.AppliedTimingCorrectionSamples;
count=c.ReceivedResult.ReceiveTiming.DemodulatedSampleCount;
assert(isequal(samples,c.RXAfterDigitalGainCompensation(offset+(1:count),:)));
assert(~evidence.OracleTimingUsed && ~evidence.ReceiverZeroPaddingUsed);
early=sixgr.phy.waveform.WaveformObservationBuffer(c.RXStartSample,c.RXEndSampleExclusive-1,fs,buffer.NumReceiveAntennas);
early.append(sixgr.phy.waveform.WaveformChunk(c.RXAfterDigitalGainCompensation(1:end-1,:),c.RXStartSample),fs);
reject(@()reference.alignCompletedObservation(cfg,early,slot0),'sixgr:phy:sync:FutureULTimingReference');
bad=cfg; bad.phy.pusch.RNTI=cfg.phy.pusch.RNTI+1;
reject(@()reference.alignCompletedObservation(bad,buffer,slot0),'sixgr:phy:sync:ULTimingReferenceIdentityMismatch');
state=struct('NumUsers',1); state=sixgr.truth.storeReceivedULTimingReference(state,1,reference);
assert(isempty(sixgr.truth.selectReceivedULTimingReference(state,1,buffer.StartSample)));
assert(isempty(sixgr.truth.selectReceivedULTimingReference(state,1,buffer.EndSampleExclusive,reference.NominalStartSample-1)));
assert(isequaln(reference,sixgr.truth.selectReceivedULTimingReference(state,1,buffer.EndSampleExclusive,reference.NominalStartSample)));
assert(digest==sixgr.phy.waveform.WaveformHash.file(capturePath));
fprintf('RECEIVED_SAME_SLOT_TIMING_REPLAY_PASS slot=%g offset=%g source_unchanged=1 no_PUCCH_success_claim=1\n',slot0+1,offset);
ok=true;
end
function reject(f,id)
try, f(); catch e, assert(strcmp(e.identifier,id),'Expected %s, got %s.',id,e.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
