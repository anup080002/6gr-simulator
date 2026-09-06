function ok=testTRSReceiveCompletion()
% Complete the canonical TRS receiver without repeating TX/RF/channel execution.
setup6GRSimToolkit("Verbose",false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs", ...
    "scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
[baseline,r]=sixgr.link.runTRSTracking(cfg,"SNR_dB",12);
assert(~baseline.Crash && ~baseline.Skipped,"%s",baseline.FailureReason);
assert(baseline.DetectionAttempted && baseline.RuntimeStageCount==5);
x=r.Observation.readComplete();
p=r.Prepared;
origin=r.Observation.StartSample;
buffer=sixgr.phy.waveform.WaveformObservationBuffer( ...
    origin,origin+p.NumSamples,p.SampleRateHz,size(x,2));
split=floor(size(x,1)/2);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(1:split,:),origin),p.SampleRateHz);
localExpectError(@()sixgr.link.completeTRSReception(p,buffer,r.Replay,r.ChannelState), ...
    "WAVEFORM:IncompleteObservation");
buffer.append(sixgr.phy.waveform.WaveformChunk(x(split+1:end,:),origin+split),p.SampleRateHz);
profile clear;
profile on;
cleanup=onCleanup(@()profile('off')); %#ok<NASGU>
completed=sixgr.link.completeTRSReception(p,buffer,r.Replay,r.ChannelState);
profile off;
stats=profile('info');
assert(isequaln(rmfield(baseline,"ComputeLatency_ms"), ...
    rmfield(completed,"ComputeLatency_ms")),"Receive-only output changed measured evidence.");
names=string({stats.FunctionTable.FunctionName});
for forbidden=["generateTRSWaveform","prepareTRSTransmission", ...
        "applyRFImpairmentChain","applyRuntimeFadingChannel", ...
        "applyRuntimeChannelState","initWaveformTruthChannelState", ...
        "advanceRuntimeChannelState","applyCompositeReceiverFrontEnd"]
    assert(~any(contains(names,forbidden)),"Completion executed %s.",forbidden);
end
for required=["estimateTRSTiming","detectTRSResources","estimateTRSChannel","scoreTRSDetection"]
    assert(any(contains(names,required)),"Completion omitted %s.",required);
end
bad=p;
bad.NumSamples=p.NumSamples+1;
localExpectError(@()sixgr.link.completeTRSReception(bad,buffer,r.Replay,r.ChannelState), ...
    "sixgr:link:TRSObservationLayoutMismatch");
badReplay=r.Replay;
badReplay.RuntimeChannelStartSample=origin+1;
localExpectError(@()sixgr.link.completeTRSReception(p,buffer,badReplay,r.ChannelState), ...
    "sixgr:link:TRSObservationOriginMismatch");
fprintf('TRS_RECEIVE_COMPLETION_PASS: %d actual RX samples; identical receiver evidence.\n',size(x,1));
ok=true;
end

function localExpectError(f,identifier)
try
    f();
catch ME
    assert(string(ME.identifier)==identifier,"Expected %s; got %s: %s", ...
        identifier,ME.identifier,ME.message);
    return;
end
error("TEST:MissingError","Expected %s.",identifier);
end
