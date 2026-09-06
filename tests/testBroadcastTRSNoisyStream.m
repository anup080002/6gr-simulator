function [ok,evidence] = testBroadcastTRSNoisyStream(trsRuntimeSlot,includePDCCH)
% Actual composed TDD samples, noisy CDL stream and completed receivers.
% This is not qualification of the main slot scheduler or full RF chain.
setup6GRSimToolkit('Verbose',false);
if nargin < 1, trsRuntimeSlot = 3; end
if nargin < 2, includePDCCH = false; end
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
root = tempname;
cfg = sixgr.lls6g.buildInternalConfig(s,root);
multi = struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime = sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),1);
runtime.CurrentSlot = 1;
runtime.CurrentServingIdx(:) = 1;
[cfg,~] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
trs = sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',trsRuntimeSlot);
assert(trs.Tx.FirstSlot0Based==trsRuntimeSlot-1);
prototype = sixgr.link.runCellSearch_MIB_SIB1(cfg, 'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',0);
assert(prototype.Status=="prepared_not_received");
broadcast = prototype.PreparedBroadcast;
tx = trs.Tx;
tx.Waveform = trs.TransmitSamples;
truth = sixgr.link.initWaveformTruthChannelState(trs.ReceiverConfig,tx,trs.TxInfo);
[xTRS,~] = sixgr.channel.projectRuntimeTransmitSamples(truth.RuntimeChannelState,trs.TransmitSamples);
fs = trs.SampleRateHz;
assert(fs==broadcast.SampleRateHz && cfg.phy.carrier.SubcarrierSpacing==15);
firstTRS = round(trs.Tx.FirstSlot0Based*fs*1e-3);
stop = max(broadcast.NumSamples,firstTRS+trs.NumSamples);
if includePDCCH
    cfgP = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,trsRuntimeSlot);
    cfgP = sixgr.util.structSet(cfgP,'lls6g.userContext.RuntimeSlotStartTime_s',firstTRS/fs);
    cfgP = sixgr.util.structSet(cfgP,'lls6g.userContext.RuntimeSignalFamily','PDCCH');
    cfgP = sixgr.util.structSet(cfgP,'phy.runtimeSignalFamily','PDCCH');
    bits = int8(mod((0:cfgP.phy.pdcch.configuredPayloadBits-1).',2));
    pdcch = sixgr.link.preparePDCCHTransmission(cfgP,'DCIBits',bits,'RNTI',1);
    assert(pdcch.SampleRateHz==fs && pdcch.RuntimeStartSample==firstTRS);
    [powerPDCCH,powerContext] = sixgr.rf.applyPowerContext( ...
        pdcch.TransmitSamples,cfgP,'DL',pdcch.TxInfo);
    assert(~powerContext.PAApplied, ...
        'This shared-stream test uses the authored PA-disabled profile, not per-component PA processing.');
    [physicalPDCCH,~] = sixgr.channel.projectRuntimeTransmitSamples(truth.RuntimeChannelState,powerPDCCH);
    stop = max(stop,firstTRS+pdcch.NumSamples);
end
composer = sixgr.phy.waveform.WaveformStreamComposer(fs,size(xTRS,2),0);
composer.enqueue('ssb',sixgr.phy.waveform.WaveformChunk(broadcast.TransmitSamples,0),fs);
composer.enqueue('trs',sixgr.phy.waveform.WaveformChunk(xTRS,firstTRS),fs);
if includePDCCH
    composer.enqueue('pdcch',sixgr.phy.waveform.WaveformChunk(physicalPDCCH,firstTRS),fs);
end
wholeTX = complex(zeros(stop,size(xTRS,2)));
wholeTX(1:broadcast.NumSamples,:) = broadcast.TransmitSamples;
wholeTX(firstTRS+(1:trs.NumSamples),:) = wholeTX(firstTRS+(1:trs.NumSamples),:)+xTRS;
if includePDCCH
    wholeTX(firstTRS+(1:pdcch.NumSamples),:) = wholeTX(firstTRS+(1:pdcch.NumSamples),:)+physicalPDCCH;
end
% Test-only independent clone for whole-vs-chunk comparison. Production
% sample execution below uses one retained fading object without replay.
referenceState = truth;
referenceState.RuntimeChannelState = sixgr.channel.ChannelFactory.forkRuntimeChannelState(truth.RuntimeChannelState);
[reference,wholeReplay,referenceState] = sixgr.link.applyWaveformTruthImpairments( ...
    wholeTX,12,referenceState,trs.ReceiverConfig,tx,trs.TxInfo, ...
    'InputSampleDomain','materialized_channel_ports');
receiver = sixgr.phy.waveform.WaveformReceiveDispatcher(fs,size(reference,2),0);
receiver.register('ssb',0,broadcast.NumSamples);
receiver.register('trs',firstTRS,firstTRS+trs.NumSamples);
if includePDCCH
    receiver.register('pdcch',firstTRS,firstTRS+pdcch.NumSamples);
end
received = zeros(size(reference),'like',reference);
first = 0;
ids = strings(0,1);
observations = struct();
intervals = zeros(0,2);
for last = unique([1 13:round(fs*1e-3):stop stop])
    chunk = composer.readThrough(last);
    [y,replay,truth] = sixgr.link.applyWaveformTruthImpairments( ...
        chunk.Samples,12,truth,trs.ReceiverConfig,tx,trs.TxInfo, ...
        'InputSampleDomain','materialized_channel_ports');
    assert(replay.RuntimeChannelStartSample==first && replay.RuntimeChannelEndSample==last);
    assert(replay.RuntimeChannelInputAlreadyProjected && ~replay.RuntimeChannelElementExpansionApplied);
    assert(~replay.RuntimeChannelAlignmentLookaheadExecutedOnFork);
    assert(replay.InjectedNoiseVariance==wholeReplay.InjectedNoiseVariance);
    intervals(end+1,:) = [first last]; %#ok<AGROW>
    if first==0, firstReplay=replay; end
    received(first+1:last,:) = y;
    completed = receiver.dispatch(sixgr.phy.waveform.WaveformChunk(y,first),fs);
    for k = 1:numel(completed)
        item = completed(k);
        assert(~any(ids==item.ID) && item.CompletionSample<=last);
        ids(end+1,1) = item.ID; %#ok<AGROW>
        a = item.Observation.StartSample;
        b = item.Observation.EndSampleExclusive;
        assert(isequal(item.Observation.readComplete(),received(a+1:b,:)));
        observations.(item.ID) = item.Observation;
    end
    first = last;
end
assert(norm(received-reference,'fro')<=1e-12*max(norm(reference,'fro'),realmin));
assert(isequaln(truth.ReceiverNoiseState,referenceState.ReceiverNoiseState));
assert(truth.RuntimeChannelState.CurrentSampleIndex==stop);
expectedIDs = ["ssb";"trs"];
if includePDCCH, expectedIDs(end+1,1)="pdcch"; end
assert(isequal(sort(ids),sort(expectedIDs)));
assert(norm(reference-wholeReplay.RawWaveform,'fro')>0);
% Each capture is a real subinterval of the same contiguous noisy stream.
% Copy only invariant channel/noise fields, never first-chunk power metrics
% and present them as measurements of a whole multi-slot observation.
baseReplay = struct();
for field = ["RuntimeChannelStateUsed","RuntimeChannelLinkKey", ...
        "RuntimeChannelSeed","InjectedNoiseVariance","InjectedTimingOffset_samples", ...
        "InjectedCFO_Hz","AppliedAWGNSNR_dB","ChannelFadingApplied"]
    baseReplay.(field) = firstReplay.(field);
end
assert(intervals(1,1)==0 && intervals(end,2)==stop && ...
    all(intervals(2:end,1)==intervals(1:end-1,2)));
baseReplay.ReceiveStreamChunkIntervals = intervals;
ssbReplay = baseReplay;
ssbReplay.RuntimeChannelStartSample = observations.ssb.StartSample;
ssbReplay.RuntimeChannelEndSample = observations.ssb.EndSampleExclusive;
prototype.RuntimeChannelReplay = ssbReplay;
prototype.RuntimeDLChannelState = truth.RuntimeChannelState;
prototype.RuntimeChannelStateUsed = true;
prototype.PowerContext = broadcast.PowerContext;
options = struct('UseRuntimeChannel',true,'RuntimeSlot',0, ...
    'CandidateSSBIndices',cfg.phy.ssb.activeCandidateIndices0Based, ...
    'SSBIndex',[],'WriteArtifacts',false,'RunFolder','','RunId','shared_noisy_stream');
clockBefore = truth.RuntimeChannelState.CurrentSampleIndex;
bch = sixgr.link.completeCellSearchBroadcast(broadcast,observations.ssb,prototype,options,tic);
for k = 1:numel(bch.CandidateResults)
    candidate = bch.CandidateResults{k};
    assert(candidate.Ok && candidate.PBCH.Ok, ...
        'Shared noisy stream SSB/SIB1 candidate failed: %s',candidate.FailureReason);
end
trsReplay = baseReplay;
trsReplay.RuntimeChannelStartSample = observations.trs.StartSample;
trsReplay.RuntimeChannelEndSample = observations.trs.EndSampleExclusive;
tracked = sixgr.link.completeTRSReception(trs,observations.trs,trsReplay,truth.RuntimeChannelState);
assert(tracked.Ok && tracked.StrictOk && ~tracked.Crash, ...
    'Shared noisy stream TRS receiver failed: %s',tracked.FailureReason);
assert(isfinite(tracked.MeasuredTrialSINR_dB) && isfinite(tracked.NMSE_dB));
evidence = struct('TRS',tracked,'Runtime',runtime,'Config',cfg, ...
    'SourceSlot',trsRuntimeSlot,'SampleRateHz',fs);
if includePDCCH
    [control,controlInfo] = sixgr.link.completePDCCHReception(pdcch,observations.pdcch, ...
        'NoiseVariance',firstReplay.InjectedNoiseVariance);
    assert(control.Ok && isequal(control.DCIBits,bits), ...
        'PDCCH did not recover the actual DCI payload from the shared noisy CDL stream.');
    assert(controlInfo.ObservationStartSample==firstTRS);
    assert(controlInfo.ListLength==cfgP.phy.pdcch.listLength);
    evidence.PDCCH = control;
    evidence.PDCCHInfo = controlInfo;
    disp('PDCCH_SSB_TRS_SHARED_RECEIVER_PASS');
end
assert(truth.RuntimeChannelState.CurrentSampleIndex==clockBefore, ...
    'Completing received observations must not propagate their channel again.');
stale = truth;
stale.WaveformImpairmentNextSample = stop-1;
probe = complex(ones(7,size(xTRS,2)));
caught = false;
try
    sixgr.link.applyWaveformTruthImpairments(probe,12,stale,trs.ReceiverConfig,tx,trs.TxInfo, ...
        'InputSampleDomain','materialized_channel_ports');
catch cause
    caught = strcmp(cause.identifier,'sixgr:link:ImpairmentClockDiscontinuity');
end
assert(caught, 'A stale receiver clock must fail before channel mutation.');
% Compare subsequent actual output, not just value-struct counters: a failed
% call must not have mutated the shared fading handle behind those counters.
[after,~,truth] = sixgr.link.applyWaveformTruthImpairments(probe,12,truth, ...
    trs.ReceiverConfig,tx,trs.TxInfo,'InputSampleDomain','materialized_channel_ports');
[expectedAfter,~,referenceState] = sixgr.link.applyWaveformTruthImpairments(probe,12,referenceState, ...
    trs.ReceiverConfig,tx,trs.TxInfo,'InputSampleDomain','materialized_channel_ports');
assert(norm(after-expectedAfter,'fro')<=1e-12*max(norm(expectedAfter,'fro'),realmin));
ok = true;
disp('BROADCAST_TRS_NOISY_STREAM_PASS');
end
