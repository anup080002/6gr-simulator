function ok=testWaveformReceiveDispatcher()
setup6GRSimToolkit("Verbose",false);
chunk=@(x,start) sixgr.phy.waveform.WaveformChunk(x,start);
d=sixgr.phy.waveform.WaveformReceiveDispatcher(1000,2,100);
d.register("future",112,114);
d.register("a",101,106);
d.register("b",104,110);
x=complex(reshape(1:28,14,2),-reshape(1:28,14,2));
assert(isempty(d.dispatch(chunk(x(1:4,:),100),1000)));
localError(@() d.register("late",103,108),"WAVEFORM:LateObservation");
localError(@() d.register("a",104,108),"WAVEFORM:DuplicateObservation");
localError(@() d.dispatch(chunk(x(5:8,:),105),1000),"WAVEFORM:ObservationDiscontinuity");
localError(@() d.dispatch(chunk(x(5:8,:),104),2000),"WAVEFORM:ObservationSampleRateMismatch");
localError(@() d.dispatch(chunk(x(5:8,1),104),1000),"WAVEFORM:InvalidObservationSamples");
localError(@() d.dispatch(chunk(single(x(5:8,:)),104),1000),"WAVEFORM:ObservationPrecisionMismatch");
assert(d.NextSampleIndex==104,"Invalid chunks must not advance any receive window.");
c=d.dispatch(chunk(x(5:8,:),104),1000);
assert(numel(c)==1 && c.ID=="a" && c.CompletionSample==106 && c.ReceivedThroughSample==108);
assert(isequal(c.Observation.readComplete(),x(2:6,:)));
c=d.dispatch(chunk(x(9:14,:),108),1000);
assert(numel(c)==2 && c(1).ID=="b" && c(2).ID=="future");
assert(isequal(c(1).Observation.readComplete(),x(5:10,:)));
assert(isequal(c(2).Observation.readComplete(),x(13:14,:)));
assert(isempty(d.dispatch(chunk(x(1:2,:),114),1000)),"Completed observations cannot be emitted again.");
localError(@() d.register("a",116,120),"WAVEFORM:DuplicateObservation");
fprintf('WAVEFORM_RECEIVE_DISPATCHER_PASS\n');
ok=true;
end

function localError(action,identifier)
try
    action();
catch exception
    assert(string(exception.identifier)==identifier,"Unexpected error: %s",exception.message);
    return;
end
error("test:MissingExpectedError","Expected rejection %s.",identifier);
end
