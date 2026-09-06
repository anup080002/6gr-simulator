function ok=testWaveformStreamComposition()
% Exact sample addition, bounded consumption, and immutable past samples.
setup6GRSimToolkit("Verbose",false);
chunk=@(x,start) sixgr.phy.waveform.WaveformChunk(x,start);
stream=sixgr.phy.waveform.WaveformStreamComposer(1000,2,0);
a=complex(reshape(1:16,8,2),reshape(17:32,8,2));
b=complex(ones(5,2),-2*ones(5,2));
stream.enqueue("a",chunk(a,0),1000);
stream.enqueue("b",chunk(b,3),1000);
expected=a;
expected(4:8,:)=expected(4:8,:)+b;
first=stream.readThrough(2);
middle=stream.readThrough(6);
last=stream.readThrough(8);
assert(isequal([first.Samples;middle.Samples;last.Samples],expected));
assert(first.StartSample==0 && first.EndSample==1 && ...
    middle.StartSample==2 && last.EndSample==7 && stream.NextSampleIndex==8);
localError(@() stream.enqueue("late",chunk(a,7),1000),"WAVEFORM:LateComponent");
localError(@() stream.enqueue("a",chunk(a,8),1000),"WAVEFORM:DuplicateComponent");
localError(@() stream.readThrough(7),"WAVEFORM:StreamTimeReversal");
localError(@() stream.enqueue("rate",chunk(a,8),2000),"WAVEFORM:SampleRateMismatch");
localError(@() stream.enqueue("ports",chunk(a(:,1),8),1000),"WAVEFORM:InvalidPhysicalSamples");
localError(@() stream.enqueue("precision",chunk(single(a),8),1000),"WAVEFORM:SamplePrecisionMismatch");
assert(stream.NextSampleIndex==8,"Rejected operations must not mutate the consumed boundary.");
stream.enqueue("future",chunk(b,10),1000);
gap=stream.readThrough(10);
assert(isequal(gap.Samples,complex(zeros(2,2))));
future=stream.readThrough(15);
assert(isequal(future.Samples,b));

% Exercise the production TDD broadcast, preserving its real SIB1 slot and
% all trailing observation samples. No receiver result is inferred here.
root=fileparts(fileparts(mfilename("fullpath")));
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,"simulator", ...
    "configs","scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(tempdir,"sixgr_broadcast_stream"));
tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,"SNRdB",Inf);
ports=size(tx.Waveform,2);
ssb=tx.SSBWaveform;
si=tx.SIB1Waveform;
ssb(:,end+1:ports)=0;
si(:,end+1:ports)=0;
reference=complex(zeros(size(tx.Waveform),'like',tx.Waveform));
reference(1:size(ssb,1),:)=ssb;
siRows=tx.SIB1WaveformStartSample+(1:size(si,1));
reference(siRows,:)=reference(siRows,:)+si;
assert(isequal(tx.Waveform,reference), ...
    "Production composition must preserve every SSB/SIB1 sample exactly.");
stream=sixgr.phy.waveform.WaveformStreamComposer(tx.SampleRateHz,ports,0);
stream.enqueue("SSB",chunk(ssb,0),tx.SampleRateHz);
stream.enqueue("SIB1",chunk(si,tx.SIB1WaveformStartSample),tx.SampleRateHz);
slotSamples=round(tx.SampleRateHz*sixgr.time.slotDurationSec(cfg));
assembled=complex(zeros(size(reference),'like',reference));
for start=0:slotSamples:size(reference,1)-1
    stop=min(start+slotSamples,size(reference,1));
    part=stream.readThrough(stop);
    assert(part.StartSample==start && part.EndSample==stop-1);
    assembled(start+1:stop,:)=part.Samples;
end
assert(isequal(assembled,reference), ...
    "Slot-window composition must equal the full generated physical waveform.");
fprintf('WAVEFORM_STREAM_COMPOSITION_PASS: %d samples, %d antennas, exact slot partition.\n', ...
    size(reference,1),ports);
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
