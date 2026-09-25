function ok=testWaveformUnemittedCancellation()
% Exact sample arithmetic; no channel/receiver or simulated SRS success.
c=sixgr.phy.waveform.WaveformStreamComposer(1000,2,0);
srs=complex(zeros(12,2)); srs(9:12,:)=repmat([1 2],4,1);
other=complex(repmat([3 4],12,1));
c.enqueue('srs',sixgr.phy.waveform.WaveformChunk(srs,0),1000);
c.enqueue('other',sixgr.phy.waveform.WaveformChunk(other,0),1000);
prefix=c.readThrough(8); hash=prefix.SHA256;
r=c.cancelUnemittedComponent('srs');
assert(r.ConsumedPrefixSamples==8 && r.EmittedNonzeroSamples==0 && ~r.PreviouslyConsumedSamplesChanged);
tail=c.readThrough(12);
assert(isequal([prefix.Samples;tail.Samples],other) && prefix.SHA256==hash);
reject(@()c.enqueue('srs',sixgr.phy.waveform.WaveformChunk(srs,12),1000),'WAVEFORM:DuplicateComponent');
d=sixgr.phy.waveform.WaveformStreamComposer(1000,2,0);
d.enqueue('srs',sixgr.phy.waveform.WaveformChunk(srs,0),1000);
first=d.readThrough(9);
reject(@()d.cancelUnemittedComponent('srs'),'WAVEFORM:CannotCancelEmittedComponent');
last=d.readThrough(12);
assert(isequal([first.Samples;last.Samples],srs));
events=sixgr.phy.waveform.WaveformEventRuntime(1000,0,@notExecuted,struct());
events.addTransmitter('ue_1',2,'double');
events.enqueue('ue_1','srs',sixgr.phy.waveform.WaveformChunk(srs,0));
receipt=events.cancelUnemittedComponent('ue_1','srs');
assert(receipt.TransmitterID=="ue_1" && receipt.CancelledAtSample==0);
events.enqueue('ue_1','second',sixgr.phy.waveform.WaveformChunk(srs,0));
events.commitTransmissionsThrough('ue_1',1);
reject(@()events.cancelUnemittedComponent('ue_1','second'),'WAVEFORM:CommittedTransmission');
fprintf('WAVEFORM_UNEMITTED_CANCELLATION_PASS prefix_unchanged=1 other_component_unchanged=1 emitted_rejection=1\n');
ok=true;
end
function varargout=notExecuted(varargin) %#ok<INUSD,STOUT>
error('test:UnexpectedPhysicalExecution','This is a schedule-mutation guard, not a receiver trial.');
end
function reject(f,id)
try, f(); catch e, assert(strcmp(e.identifier,id),'Expected %s, got %s.',id,e.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
