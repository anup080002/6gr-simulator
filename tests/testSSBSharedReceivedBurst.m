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
cut=floor(size(actualRx,1)/2);
observation.append(sixgr.phy.waveform.WaveformChunk(actualRx(1:cut,:),start),fs);
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
fprintf('SSB_SHARED_RECEIVED_BURST_PASS: one TX/channel, %d receivers.\n', numel(indices));
ok = true;
end

function localAssertCalls(stats, functionSuffix, expected)
names = string({stats.FunctionTable.FunctionName});
matches = names == functionSuffix | endsWith(names, "." + functionSuffix);
assert(any(matches), "Profiler must observe production function %s.", functionSuffix);
assert(sum([stats.FunctionTable(matches).NumCalls]) == expected, ...
    "Production function %s must execute exactly %d times.", functionSuffix, expected);
end
