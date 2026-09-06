function ok = testSSBSharedReceivedBurst()
% Four candidate receivers must observe one generated and impaired burst.
setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));
s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, "simulator", ...
    "configs", "scenarios", "lls_causal_access_to_data_wiring_tdd.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(s, fullfile(tempdir, ...
    "sixgr_ssb_shared_received_burst"));
indices = double(cfg.phy.ssb.activeCandidateIndices0Based(:).');
assert(numel(indices) > 1, "The regression must exercise a multi-beam burst.");

profile clear;
profile on;
cleanupProfile = onCleanup(@() profile('off')); %#ok<NASGU>
out = sixgr.link.runCellSearch_MIB_SIB1(cfg, "NumSubframes", 5, ...
    "SSBIndex", indices(1), "CandidateSSBIndices", indices, ...
    "UseRuntimeChannel", true, "RuntimeSlot", 0, "WriteArtifacts", false);
profile off;
stats = profile('info');
assert(~out.Crash, "Shared burst receiver crashed: %s", out.FailureReason);
assert(isequal(out.CandidateSSBIndices, indices) && ...
    numel(out.CandidateResults) == numel(indices));
localAssertCalls(stats, "generateSSB_MIB_SIB1_Waveform", 1);
localAssertCalls(stats, "applyWaveformTruthImpairments", 1);
localAssertCalls(stats, "recoverSIB1FromWaveform", numel(indices));

first = out.CandidateResults{1};
assert(~first.RuntimeChannelReplay.CFOCorrectionApplied && ...
    isnan(first.RuntimeChannelReplay.EstimatedCFO_PreCorrection_Hz));
assert(first.TrueCFO_Hz==first.RuntimeChannelReplay.InjectedCFO_Hz && ...
    first.CFOError_Hz==first.FreqOffsetEstimate_Hz-first.TrueCFO_Hz);
assert(first.EstimatedCFO_PreCorrection_Hz==first.FreqOffsetEstimate_Hz && ...
    string(first.CFOEstimateSource)=="SSB_Rx_pss_cp_synchronization_on_received_samples");
assert(first.RuntimeChannelStateUsed && first.PBCH.Ok, ...
    "The first candidate must traverse fading and actual BCH decoding.");
actualRx=first.RuntimeChannelReplay.ReceiverInputWaveform;
assert(first.RuntimeChannelReplay.InjectedNoiseVariance>0 && ...
    norm(actualRx-first.RuntimeChannelReplay.CorrectedWaveform,'fro')>0, ...
    "The actual decoder input must retain the noise added after synchronization-stage snapshots.");
for k = 1:numel(indices)
    candidate = out.CandidateResults{k};
    assert(isequaln(candidate.RuntimeChannelReplay, first.RuntimeChannelReplay), ...
        "All candidate measurements must share exact RX samples and channel/noise evidence.");
    assert(candidate.RuntimeDLChannelState.CurrentSampleIndex == ...
        first.RuntimeDLChannelState.CurrentSampleIndex, ...
        "Candidate decoding must not advance the shared channel again.");
    assert(candidate.DetectionAttempted && candidate.DecodeAttempted, ...
        "Each requested candidate must execute its real receiver.");
    if candidate.PBCH.Ok
        assert(candidate.SSBIndex == indices(k), ...
            "A successful candidate must recover its own SSB identity.");
    end
    fprintf('Candidate %d: BCH=%d SIB1=%d SS-RSRP=%g dBm\n', ...
        indices(k), candidate.PBCH.Ok, candidate.Ok, candidate.SS_RSRP_dBm);
end

% A single-candidate call with the same seed must have exactly the same
% observation and candidate result; requesting more receivers cannot alter TX.
single = sixgr.link.runCellSearch_MIB_SIB1(cfg, "NumSubframes", 5, ...
    "SSBIndex", indices(1), "UseRuntimeChannel", true, ...
    "RuntimeSlot", 0, "WriteArtifacts", false);
assert(isequaln(single.RuntimeChannelReplay, first.RuntimeChannelReplay));
assert(isequaln(single.PBCH, first.PBCH));
assert(single.Ok == first.Ok);
% Reassemble the exact noisy receiver input in partial chunks. The canonical
% decoder must reject the incomplete observation, then match array decoding.
start=first.RuntimeChannelReplay.RuntimeChannelStartSample;
fs=first.RuntimeChannelReplay.SampleRate_Hz;
observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    start,start+size(actualRx,1),fs,size(actualRx,2));
prepared=sixgr.link.prepareCellSearchBroadcast(cfg,true);
completionOptions=struct("UseRuntimeChannel",true,"RuntimeSlot",0, ...
    "CandidateSSBIndices",indices,"SSBIndex",indices(1), ...
    "WriteArtifacts",false,"RunFolder","","RunId","buffer_completion_test");
cut=floor(size(actualRx,1)/2);
observation.append(sixgr.phy.waveform.WaveformChunk(actualRx(1:cut,:),start),fs);
try
    sixgr.link.completeCellSearchBroadcast(prepared,observation,first, ...
        completionOptions,tic);
    error('test:PrematureCompletion','Incomplete reception produced a completed broadcast result.');
catch exception
    assert(string(exception.identifier)=="WAVEFORM:IncompleteObservation");
end
try
    sixgr.phy.broadcast.recoverSIB1FromWaveform(observation,cfg);
    error('test:PrematureAcquisition','An incomplete observation reached the decoder.');
catch exception
    assert(string(exception.identifier)=="WAVEFORM:IncompleteObservation");
end
observation.append(sixgr.phy.waveform.WaveformChunk(actualRx(cut+1:end,:),start+cut),fs);
receiverCfg=sixgr.util.structSet(cfg,"lls6g.runtimePowerContext",first.PowerContext);
buffered=sixgr.phy.broadcast.recoverSIB1FromWaveform(observation,receiverCfg, ...
    "CandidateSSBIndex",indices(1));
direct=sixgr.phy.broadcast.recoverSIB1FromWaveform(actualRx,receiverCfg, ...
    "CandidateSSBIndex",indices(1));
assert(isequaln(buffered,direct) && buffered.BCHCrcPass, ...
    "Buffering must preserve actual receiver results exactly.");
% Completion must use received samples only, never regenerate or re-channel
% the prepared broadcast. Compare all decoder results, not only CRC flags.
profile clear;
profile on;
completed=sixgr.link.completeCellSearchBroadcast(prepared,observation,first, ...
    completionOptions,tic);
profile off;
completionStats=profile('info');
completionNames=string({completionStats.FunctionTable.FunctionName});
assert(~any(contains(completionNames,"generateSSB_MIB_SIB1_Waveform") | ...
    contains(completionNames,"applyWaveformTruthImpairments") | ...
    contains(completionNames,"initWaveformTruthChannelState") | ...
    contains(completionNames,"applyRuntimeChannelState") | ...
    contains(completionNames,"advanceRuntimeChannelState")));
localAssertCalls(completionStats,"recoverSIB1FromWaveform",numel(indices));
for k=1:numel(indices)
    assert(isequaln(completed.CandidateResults{k}.PBCH,out.CandidateResults{k}.PBCH));
    assert(isequaln(completed.CandidateResults{k}.SIB1,out.CandidateResults{k}.SIB1));
    assert(completed.CandidateResults{k}.RuntimeDLChannelState.CurrentSampleIndex == ...
        first.RuntimeDLChannelState.CurrentSampleIndex);
end
assert(completed.ObservationStartSample==start && ...
    completed.ObservationEndSampleExclusive==start+size(actualRx,1));
assert(completed.ObservationCompletionTime_s==(start+size(actualRx,1))/fs);
assert(completed.AirInterfaceObservation_ms==1e3*size(actualRx,1)/fs);
badLayout=prepared;
badLayout.NumSamples=prepared.NumSamples+1;
localAssertCompletionError(badLayout,observation,first,completionOptions, ...
    "sixgr:link:BroadcastObservationLayoutMismatch");
wrongOrigin=completionOptions;
wrongOrigin.RuntimeSlot=1;
localAssertCompletionError(prepared,observation,first,wrongOrigin, ...
    "sixgr:link:BroadcastObservationOriginMismatch");
% The actual decoded candidate rows remain private until the canonical
% runtime reaches the complete capture boundary. Copy measured values, do
% not regenerate metrics or infer timing from a configured capture length.
deliveryRows=cell(numel(indices),1);
for k=1:numel(indices)
    candidate=completed.CandidateResults{k};
    deliveryRows{k}=table(1,candidate.SSBIndex,candidate.SS_RSRP_dBm, ...
        candidate.SS_SINR_dB,logical(candidate.PBCH.Ok), ...
        candidate.ObservationStartSample,candidate.ObservationEndSampleExclusive, ...
        candidate.ObservationSampleRateHz,candidate.ObservationCompletionTime_s, ...
        string(candidate.ObservationCoverageSource), ...
        'VariableNames',{'Slot','SSBIndex','SS_RSRP_dBm','SS_SINR_dB','CRCPass', ...
        'ObservationStartSample','ObservationEndSampleExclusive', ...
        'ObservationSampleRateHz','ObservationCompletionTime_s','ObservationCoverageSource'});
end
measuredRows=vertcat(deliveryRows{:});
clockState=struct("NumUsers",1,"CurrentSlot",1, ...
    "SlotDuration_s",sixgr.time.slotDurationSec(cfg));
clockState=sixgr.truth.BroadcastResultDelivery.enqueue( ...
    clockState,1,measuredRows,struct(),false);
due=ceil(measuredRows.ObservationCompletionTime_s(1)/clockState.SlotDuration_s)+1;
for slot=1:due-1
    clockState.CurrentSlot=slot;
    [clockState,early]=sixgr.truth.BroadcastResultDelivery.takeAvailable(clockState);
    assert(isempty(early));
end
clockState.CurrentSlot=due;
[~,delivered]=sixgr.truth.BroadcastResultDelivery.takeAvailable(clockState);
assert(numel(delivered)==1 && ...
    isequaln(delivered.Trial(:,measuredRows.Properties.VariableNames),measuredRows));
% A nonzero CFO applied to actual noisy received samples must be estimated
% by the receiver, and its audit reference must not be overwritten with zero.
% This is an explicit receiver test vector, not a new scenario operating point.
injected=7500;
shifted=actualRx.*exp(1j*2*pi*injected/fs*(0:size(actualRx,1)-1).');
shiftedBuffer=sixgr.phy.waveform.WaveformObservationBuffer( ...
    start,start+size(shifted,1),fs,size(shifted,2));
shiftedBuffer.append(sixgr.phy.waveform.WaveformChunk(shifted,start),fs);
cfoPrepared=prepared;
cfoPrepared.ReceiverConfig.phy.sync.freqSearchBW_Hz=15000;
cfoPrepared.ReceiverConfig.phy.sync.cfoHypothesesHz=[-15000 -7500 0 7500 15000];
cfoPrepared.ReceiverConfig.phy.sync.fineCFOEnabled=false;
cfoPrototype=first;
cfoPrototype.RuntimeChannelReplay.InjectedCFO_Hz=first.TrueCFO_Hz+injected;
cfoPrototype.RuntimeChannelReplay.ReceiverInputWaveform=shifted;
singleOptions=completionOptions;
singleOptions.CandidateSSBIndices=[];
withCFO=sixgr.link.completeCellSearchBroadcast( ...
    cfoPrepared,shiftedBuffer,cfoPrototype,singleOptions,tic);
assert(withCFO.PBCH.Ok && withCFO.Ok && withCFO.TrueCFO_Hz==injected, ...
    "Nonzero CFO: BCH=%d SIB1=%d true=%g estimated=%g status=%s reason=%s", ...
    withCFO.PBCH.Ok,withCFO.Ok,withCFO.TrueCFO_Hz, ...
    withCFO.EstimatedCFO_PreCorrection_Hz,withCFO.Status,withCFO.FailureReason);
assert(withCFO.EstimatedCFO_PreCorrection_Hz==injected && withCFO.CFOError_Hz==0);
assert(withCFO.SIB1CFOCorrectionApplied_Hz==withCFO.EstimatedCFO_PreCorrection_Hz && ...
    withCFO.SIB1CFOCorrectionSource=="received_ssb_pss_cp_frequency_estimate");
assert(isnan(withCFO.ResidualCFO_PostCorrection_Hz), ...
    "Known injection minus correction is an audit error, not a measured residual CFO.");
unknownPrototype=first;
unknownPrototype.RuntimeChannelReplay=rmfield( ...
    unknownPrototype.RuntimeChannelReplay,"InjectedCFO_Hz");
unknown=sixgr.link.completeCellSearchBroadcast( ...
    prepared,observation,unknownPrototype,singleOptions,tic);
assert(unknown.PBCH.Ok && isnan(unknown.TrueCFO_Hz) && isnan(unknown.CFOError_Hz));
fprintf('SSB_SHARED_RECEIVED_BURST_PASS: one TX/channel, %d receivers.\n', numel(indices));
ok = true;
end

function localAssertCompletionError(prepared,observation,prototype,options,identifier)
try
    sixgr.link.completeCellSearchBroadcast(prepared,observation,prototype,options,tic);
    error("test:MissingCompletionError","Expected completion to reject incompatible reception.");
catch exception
    assert(string(exception.identifier)==identifier, ...
        "Expected %s; got %s: %s",identifier,exception.identifier,exception.message);
end
end

function localAssertCalls(stats, functionSuffix, expected)
names = string({stats.FunctionTable.FunctionName});
matches = names == functionSuffix | endsWith(names, "." + functionSuffix);
assert(any(matches), "Profiler must observe production function %s.", functionSuffix);
assert(sum([stats.FunctionTable(matches).NumCalls]) == expected, ...
    "Production function %s must execute exactly %d times.", functionSuffix, expected);
end
