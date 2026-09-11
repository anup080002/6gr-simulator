function [ok,evidence] = testBroadcastTRSNoisyStream(trsRuntimeSlot,includePDCCH)
% Actual composed TDD samples, noisy CDL stream and completed receivers.
% This is not qualification of the main slot scheduler or full RF chain.
setup6GRSimToolkit('Verbose',false);
if nargin < 1, trsRuntimeSlot = []; end
if nargin < 2, includePDCCH = false; end
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
root = tempname;
cfg = sixgr.lls6g.buildInternalConfig(s,root);
if isempty(trsRuntimeSlot)
    trsRuntimeSlot = double(cfg.phy.trs.slotNumbers(1)) + 1;
end
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
[basis,~]=sixgr.channel.projectRuntimeTransmitSamples(truth.RuntimeChannelState, ...
    eye(size(trs.TransmitSamples,2),'like',trs.TransmitSamples));
trs.TransmitProjectionMatrix=basis.';
trs.TransmitStartSample=firstTRS;
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
processorState=struct('Truth',truth,'Config',trs.ReceiverConfig,'Tx',tx, ...
    'TxInfo',trs.TxInfo,'Received',zeros(size(reference),'like',reference));
stream=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@localPhysicalInterval,processorState);
stream.addTransmitter('gnb',size(xTRS,2),'double');
stream.addReceiver('ue_pre_rf',size(reference,2));
stream.enqueue('gnb','ssb',sixgr.phy.waveform.WaveformChunk(broadcast.TransmitSamples,0));
stream.enqueue('gnb','trs',sixgr.phy.waveform.WaveformChunk(xTRS,firstTRS));
stream.observe('ue_pre_rf','ssb',0,broadcast.NumSamples);
horizons=sixgr.phy.frame.ssbObservationHorizons(cfg,fs);
prefixIDs="ssb_occasion_"+string(horizons.SSBIndex);
prefixResults=cell(height(horizons),1);
assert(all(horizons.ObservationEndSampleExclusive<broadcast.NumSamples), ...
    'This fixture must prove SSB availability before complete SIB1/burst reception.');
for k=1:height(horizons)
    stream.observe('ue_pre_rf',prefixIDs(k),0,horizons.ObservationEndSampleExclusive(k));
end
stream.observe('ue_pre_rf','trs',firstTRS,firstTRS+trs.NumSamples);
if includePDCCH
    stream.enqueue('gnb','pdcch',sixgr.phy.waveform.WaveformChunk(physicalPDCCH,firstTRS));
    stream.observe('ue_pre_rf','pdcch',firstTRS,firstTRS+pdcch.MinimumReceiveSamples);
end
% This diagnostic's entire TX schedule is known. A scheduler must instead
% commit only intervals for which all causal contributors are available.
stream.commitTransmissionsThrough('gnb',stop);
ids = strings(0,1);
observations = struct();
intervals = zeros(0,2);
options = struct('UseRuntimeChannel',true,'RuntimeSlot',0, ...
    'CandidateSSBIndices',cfg.phy.ssb.activeCandidateIndices0Based, ...
    'SSBIndex',[],'WriteArtifacts',false,'RunFolder','','RunId','shared_noisy_stream');
for requested = unique([1 13:round(fs*1e-3):stop stop])
  while stream.NextSampleIndex<requested
    event=stream.advanceUntilEvent(requested);
    first=event.StartSample; last=event.EndSampleExclusive;
    replay=event.Execution.Replay;
    truth=stream.ProcessorState.Truth;
    assert(replay.RuntimeChannelStartSample==first && replay.RuntimeChannelEndSample==last);
    assert(replay.RuntimeChannelInputAlreadyProjected && ~replay.RuntimeChannelElementExpansionApplied);
    assert(~replay.RuntimeChannelAlignmentLookaheadExecutedOnFork);
    assert(replay.InjectedNoiseVariance==wholeReplay.InjectedNoiseVariance);
    intervals(end+1,:) = [first last]; %#ok<AGROW>
    completed=event.Completed;
    for k = 1:numel(completed)
        item = completed(k);
        assert(~any(ids==item.ID) && item.Observation.EndSampleExclusive==last);
        ids(end+1,1) = item.ID; %#ok<AGROW>
        a = item.Observation.StartSample;
        b = item.Observation.EndSampleExclusive;
        assert(isequal(item.Observation.readComplete(),stream.ProcessorState.Received(a+1:b,:)));
        observations.(item.ID) = item.Observation;
        captureReplay=localObservationReplay(item);
        clockBefore=truth.RuntimeChannelState.CurrentSampleIndex;
        if any(item.ID==prefixIDs)
            index=find(item.ID==prefixIDs);
            assert(stream.NextSampleIndex==horizons.ObservationEndSampleExclusive(index));
            r=sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
                item.Observation,broadcast.ReceiverConfig,'RecoveryScope','SSB_MIB', ...
                'CandidateSSBIndex',horizons.SSBIndex(index));
            assert(r.SSBMIBComplete && r.BCHCrcPass && r.MIBDecoded && ...
                r.SSBIndex==horizons.SSBIndex(index),r.FailureReason);
            assert(~r.SIB1ReceptionAttempted && ~r.DLSCHCrcPass && ~r.StrictOk && ...
                r.Status=="SSB_MIB_COMPLETE_SIB1_NOT_ATTEMPTED");
            assert(isfinite(r.SS_RSRP_dBm) && isfinite(r.SS_SINR_dB));
            prefixResults{index}=r;
        end
        % Complete the real decoder at the event, before consuming any
        % later fading/noise samples. There is no future-result delivery.
        switch item.ID
            case "ssb"
                prototype.RuntimeChannelReplay=captureReplay;
                prototype.RuntimeDLChannelState=truth.RuntimeChannelState;
                prototype.RuntimeChannelStateUsed=true;
                prototype.PowerContext=broadcast.PowerContext;
                bch=sixgr.link.completeCellSearchBroadcast( ...
                    broadcast,item.Observation,prototype,options,tic);
                for j=1:numel(bch.CandidateResults)
                    candidate=bch.CandidateResults{j};
                    assert(candidate.Ok && candidate.PBCH.Ok, ...
                        'Shared noisy stream SSB/SIB1 candidate failed: %s',candidate.FailureReason);
                end
            case "trs"
                captures=cell(numel(item.Segments),1);
                for j=1:numel(item.Segments)
                    captures{j}=struct('LinkID',"gnb_to_ue",'TX',"gnb",'RX',"ue", ...
                        'Reference',item.Segments{j}.Execution.ChannelReference);
                end
                tracked=sixgr.link.completeTRSReception( ...
                    trs,item.Observation,captureReplay,truth.RuntimeChannelState, ...
                    'ScoringChannelReferences',captures);
                assert(tracked.Ok && tracked.StrictOk && ~tracked.Crash, ...
                    'Shared noisy stream TRS receiver failed: %s',tracked.FailureReason);
                assert(isnan(tracked.MeasuredTrialSINR_dB) && isfinite(tracked.NMSE_dB) && ...
                    tracked.NMSEScoringAvailable);
            case "pdcch"
                [control,controlInfo]=sixgr.link.completePDCCHReception(pdcch,item.Observation, ...
                    'NoiseVariance',captureReplay.InjectedNoiseVariance);
                assert(control.Ok && isequal(control.DCIBits,bits), ...
                    'PDCCH did not recover the actual DCI payload from the shared noisy CDL stream.');
                assert(controlInfo.ObservationStartSample==firstTRS);
                assert(controlInfo.ObservationEndSampleExclusive==firstTRS+pdcch.MinimumReceiveSamples && ...
                    controlInfo.ObservationEndSampleExclusive<firstTRS+pdcch.NumSamples && ...
                    ~controlInfo.ReceivePaddingApplied);
                assert(controlInfo.ListLength==cfgP.phy.pdcch.listLength);
        end
        assert(truth.RuntimeChannelState.CurrentSampleIndex==clockBefore, ...
            'Completing received observations must not propagate their channel again.');
    end
  end
end
received=stream.ProcessorState.Received;
assert(norm(received-reference,'fro')<=1e-12*max(norm(reference,'fro'),realmin));
assert(isequaln(truth.ReceiverNoiseState,referenceState.ReceiverNoiseState));
assert(truth.RuntimeChannelState.CurrentSampleIndex==stop);
expectedIDs = ["ssb";"trs"];
expectedIDs=[expectedIDs;prefixIDs];
if includePDCCH, expectedIDs(end+1,1)="pdcch"; end
assert(isequal(sort(ids),sort(expectedIDs)));
assert(norm(reference-wholeReplay.RawWaveform,'fro')>0);
assert(intervals(1,1)==0 && intervals(end,2)==stop && ...
    all(intervals(2:end,1)==intervals(1:end-1,2)));
evidence = struct('TRS',tracked,'Runtime',runtime,'Config',cfg, ...
    'SourceSlot',trsRuntimeSlot,'PreparedTRS',trs,'SampleRateHz',fs,'ExecutionTrace',{stream.ExecutionTrace});
evidence.SSBObservationHorizons=horizons;
evidence.SSBOccasionResults=prefixResults;
assert(all(~cellfun(@isempty,prefixResults)));
disp('SSB_OCCASION_CAUSAL_RECEPTION_PASS: actual noisy CDL prefixes before full-burst/SIB1 completion.');
if includePDCCH
    evidence.PDCCH = control;
    evidence.PDCCHInfo = controlInfo;
    disp('PDCCH_SSB_TRS_SHARED_RECEIVER_PASS');
end
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

function [outputs,execution,state]=localPhysicalInterval(inputs,first,stop,state)
assert(numel(inputs)==1 && inputs.ID=="gnb");
[y,replay,state.Truth,reference]=sixgr.link.applyWaveformTruthImpairments( ...
    inputs.Chunk.Samples,12,state.Truth,state.Config,state.Tx,state.TxInfo, ...
    'InputSampleDomain','materialized_channel_ports','CaptureChannelReference',true);
state.Received(first+1:stop,:)=y;
outputs=struct('ID',"ue_pre_rf",'Chunk',sixgr.phy.waveform.WaveformChunk(y,first));
execution=struct('Source',"actual_continuous_CDL_and_thermal_noise_pre_RF", ...
    'ApproximationMode',"none",'StartSample',first,'EndSampleExclusive',stop, ...
    'Replay',replay,'ChannelReference',reference);
end

function replay=localObservationReplay(item)
% Retain invariant link/noise quantities only after checking every actual
% contributing interval; do not promote block power to whole-window power.
replay=struct();
for field=["RuntimeChannelStateUsed","RuntimeChannelLinkKey", ...
        "RuntimeChannelSeed","InjectedNoiseVariance","InjectedTimingOffset_samples", ...
        "InjectedCFO_Hz","AppliedAWGNSNR_dB","ChannelFadingApplied","AppliedLargeScaleGain_dB"]
    value=item.Segments{1}.Execution.Replay.(field);
    for k=2:numel(item.Segments)
        assert(isequaln(value,item.Segments{k}.Execution.Replay.(field)), ...
            'Receiver replay cannot flatten time-varying evidence for %s.',field);
    end
    replay.(field)=value;
end
intervals=zeros(numel(item.Segments),2);
for k=1:numel(item.Segments)
    intervals(k,:)=[item.Segments{k}.StartSample,item.Segments{k}.EndSampleExclusive];
end
replay.ReceiveStreamChunkIntervals=intervals;
replay.RuntimeChannelStartSample=item.Observation.StartSample;
replay.RuntimeChannelEndSample=item.Observation.EndSampleExclusive;
end
