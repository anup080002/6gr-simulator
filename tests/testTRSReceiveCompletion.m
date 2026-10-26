function ok=testTRSReceiveCompletion()
% Complete the canonical TRS receiver without repeating TX/RF/channel execution.
setup6GRSimToolkit("Verbose",false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs", ...
    "scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
[baseline,r]=sixgr.link.runTRSTracking(cfg,"SNR_dB",12);
assert(~baseline.Crash && ~baseline.Skipped,"%s",baseline.FailureReason);
assert(baseline.DetectionAttempted && baseline.RuntimeStageCount==5);
criteria=jsondecode(baseline.TRSQualificationCriteriaJSON);
assert(~criteria.StandardMandatedThresholds && criteria.RuntimeCoupled && ...
    ~criteria.TimingErrorGateApplied && ~criteria.FrequencyErrorGateApplied && ...
    criteria.ChannelNMSEThreshold_dB==baseline.ChannelNMSEThreshold_dB && ...
    baseline.StrictReceiverEvidenceOk==baseline.TRSRuntimeEvidenceUsable);
x=r.Observation.readComplete();
p=r.Prepared;
intervals=jsondecode(baseline.ResourceIntervalEvidence.ExecutedResourceIntervalsJSON);
mapped=baseline.ObservedREAllocationTable;
assert(numel(intervals)==size(unique([mapped.absolute_slot mapped.symbol_index],'rows'),1));
for k=1:numel(intervals)
    one=intervals(k);
    actual=mapped(mapped.absolute_slot==one.AbsoluteSlotIndex0 & ...
        mapped.symbol_index==one.SymbolIndex0,:);
    assert(~isempty(actual));
    expected=[];
    for j=1:height(actual)
        first=actual.subcarrier_start(j);
        last=first+actual.subcarrier_count(j)-1;
        expected=union(expected,floor(first/12):floor(last/12));
    end
    assert(isequal(reshape(one.PRBSet0Based,1,[]),reshape(expected,1,[])), ...
        'TRS interval PRBs must equal independently retained actual TX RE occupancy.');
end
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
% Shared receive replay does not duplicate the prepared TX normalization.
% Its absence must preserve the original power receipt and all RX values.
receivedReplay=rmfield(r.Replay,'PowerContext');
completed=sixgr.link.completeTRSReception(p,buffer,receivedReplay,r.ChannelState, ...
    'DesiredReferenceObservation',r.DesiredReferenceObservation, ...
    'RecordedReceiverTimingOffset_samples',r.RecordedReceiverTimingOffset_samples);
profile off;
stats=profile('info');
assert(isequaln(rmfield(baseline,"ComputeLatency_ms"), ...
    rmfield(completed,"ComputeLatency_ms")),"Receive-only output changed measured evidence.");
assert(completed.TransmitPowerEvidenceAvailable && ...
    startsWith(completed.TransmitPowerReferencePlane,"prepared_TRS_waveform_") && ...
    completed.PowerNormalizationPolicy==string(p.PowerContext.PowerNormalizationPolicy));
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
badReplay.PowerContext.OutputTotalPower_dBm=badReplay.PowerContext.OutputTotalPower_dBm+1;
localExpectError(@()sixgr.link.completeTRSReception(p,buffer,badReplay,r.ChannelState), ...
    "sixgr:link:ConflictingTRSPowerContext");
bad=p; bad=rmfield(bad,'PowerContext');
localExpectError(@()sixgr.link.completeTRSReception(bad,buffer,receivedReplay,r.ChannelState), ...
    "sixgr:link:MissingPreparedTRSPowerContext");
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
