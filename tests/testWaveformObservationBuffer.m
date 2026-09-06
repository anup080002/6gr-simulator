function ok=testWaveformObservationBuffer()
% A decoder cannot consume samples that have not arrived.
setup6GRSimToolkit("Verbose",false);
chunk=@(x,start) sixgr.phy.waveform.WaveformChunk(x,start);
b=sixgr.phy.waveform.WaveformObservationBuffer(100,110,1000,2);
assert(~b.isComplete());
localError(@() b.readComplete(),"WAVEFORM:IncompleteObservation");
localError(@() sixgr.phy.broadcast.recoverSIB1FromWaveform(b,struct()), ...
    "WAVEFORM:IncompleteObservation");
x=complex(reshape(1:20,10,2),-reshape(1:20,10,2));
b.append(chunk(x(1:3,:),100),1000);
localError(@() b.append(chunk(x(4:5,:),104),1000),"WAVEFORM:ObservationDiscontinuity");
localError(@() b.append(chunk(x(1:3,:),100),1000),"WAVEFORM:ObservationDiscontinuity");
localError(@() b.append(chunk(x,103),1000),"WAVEFORM:ObservationOverrun");
localError(@() b.append(chunk(x(4:5,:),103),2000),"WAVEFORM:ObservationSampleRateMismatch");
localError(@() b.append(chunk(x(4:5,1),103),1000),"WAVEFORM:InvalidObservationSamples");
assert(b.ReceivedThroughSample==103 && ~b.isComplete());
b.append(chunk(x(4:10,:),103),1000);
assert(b.isComplete() && isequal(b.readComplete(),x));
assert(isequal(b.readComplete(),x),"Multiple receivers must see the same immutable samples.");
fprintf('WAVEFORM_OBSERVATION_BUFFER_PASS: partial reads and missing/overlapping samples rejected.\n');
ok=true;
end

function localError(action,identifier)
try
    action();
catch exception
    assert(string(exception.identifier)==identifier, ...
        "Expected %s, received %s.",identifier,string(exception.identifier));
    return;
end
error("test:MissingExpectedError","Expected rejection %s.",identifier);
end
