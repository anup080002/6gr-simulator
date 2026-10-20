function ok=testSharedArrivalTimingReference()
% Explicit clock/operator unit fixture, not measured PHY qualification.
post=sixgr.phy.waveform.WaveformObservationBuffer(1000,1100,122.88e6,1);
post.append(sixgr.phy.waveform.WaveformChunk(complex(ones(100,1)),1000),122.88e6);
link=struct('TX',"ue",'RX',"gnb",'Replay',struct( ...
    'RuntimeChannelExpectedEarliestArrivalDelay_samples',7.5, ...
    'RuntimeChannelAppliedAlignmentTrimSamples',0,'RuntimeChannelFilterDelay_samples',7));
e=struct('TX',struct('ID',"ue",'Replay',struct('InjectedTimingOffset_samples',1)), ...
    'RX',struct('ID',"gnb",'Replay',struct('InjectedTimingOffset_samples',2)), ...
    'Links',link);
s=struct('StartSample',1000,'EndSampleExclusive',1100,'Execution',e);
planes=struct('ReceiverID',{"gnb:post_rf","ue:tx"},'Observation',{post,post},'Segments',{{s},{s}});
ref=sixgr.truth.sharedArrivalTimingReference(planes,1011);
assert(ref.ExpectedArrivalOffset_samples==21.5 && ref.ChannelFilterDelay_samples==7 && ...
    ~ref.ReceiverEstimatorInput && ref.AdditionalChannelExecutions==0);
% TA advances the actual TX clock; receiver pre-roll is not propagation.
advanced=sixgr.truth.sharedArrivalTimingReference(planes,1011-32);
assert(advanced.ExpectedArrivalOffset_samples==ref.ExpectedArrivalOffset_samples-32);
% Msg2/Msg4 use the actual queued DL timestamp, not the UL-only TA struct.
% The same resolver is used by the stream enqueue and post-receiver scoring.
for stage=["Msg2","Msg4"]
    prepared=struct('StageName',stage,'Direction',"DL", ...
        'StartTime_s',1011/post.SampleRateHz,'SampleRate_Hz',post.SampleRateHz, ...
        'AbsoluteSlot',999); % Deliberately unrelated diagnostic slot.
    assert(~isfield(prepared,'PhysicalTiming'));
    actual=sixgr.phy.ra.preparedStageTransmitStartSample(prepared);
    assert(actual==1011);
    scored=sixgr.truth.sharedArrivalTimingReference(planes,actual);
    assert(isequaln(scored,ref),'DL scoring must retain the executed TX clock.');
end
prepared.Direction="UL";
rejectClock(prepared,'sixgr:phy:ra:MissingSharedULTiming');
prepared.PhysicalTiming=struct('TransmitStartSample',1011);
assert(sixgr.phy.ra.preparedStageTransmitStartSample(prepared)==1011);
prepared.PhysicalTiming.TransmitStartSample=1011-32;
rejectClock(prepared,'sixgr:phy:ra:SharedTransmitClockMismatch');
prepared.StartTime_s=(1011-32)/post.SampleRateHz;
assert(sixgr.phy.ra.preparedStageTransmitStartSample(prepared)==1011-32);
prepared.Direction="DL";
prepared.StartTime_s=1011.25/post.SampleRateHz;
rejectClock(prepared,'sixgr:truth:SharedRAOriginOffClock');
prepared=rmfield(prepared,'StartTime_s');
rejectClock(prepared,'sixgr:phy:ra:MissingPreparedTransmitClock');
bad=planes; bad(1).Segments{1}.Execution.Links.Replay=rmfield(link.Replay, ...
    'RuntimeChannelExpectedEarliestArrivalDelay_samples');
reject(bad,'sixgr:truth:ArrivalTimingMissingExecution');
bad=planes; second=s; second.Execution.RX.Replay.InjectedTimingOffset_samples=3;
bad(1).Segments={s,second};
reject(bad,'sixgr:truth:TimeVaryingArrivalTiming');
ok=true; disp('SHARED_ARRIVAL_TIMING_REFERENCE_PASS');
end

function reject(planes,id)
try
    sixgr.truth.sharedArrivalTimingReference(planes,1011);
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier); return;
end
error('test:MissingError','Expected %s.',id);
end

function rejectClock(prepared,id)
try
    sixgr.phy.ra.preparedStageTransmitStartSample(prepared);
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier); return;
end
error('test:MissingError','Expected %s.',id);
end
