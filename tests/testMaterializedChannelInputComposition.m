function ok=testMaterializedChannelInputComposition()
% Real broadcast/TRS TX contributions share one physical fading clock.
setup6GRSimToolkit("Verbose",false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs", ...
    "scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
root=tempname;
cfg=sixgr.lls6g.buildInternalConfig(s,root);
multi=struct("Enabled",true,"NumUsers",1,"RNTIStart",1, ...
    "ExecutionModel","slot_coupled_truth");
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),1);
runtime.CurrentSlot=1;
runtime.CurrentServingIdx(:)=1;
[cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,"DL");
trs=sixgr.link.prepareTRSTransmission(cfg,12);
tx=trs.Tx;
tx.Waveform=trs.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(trs.ReceiverConfig,tx,trs.TxInfo);
state=truth.RuntimeChannelState;
assert(state.ElementExpansionApplied && state.CurrentSampleIndex==0);
before=state.CurrentSampleIndex;
beforeObjectSamples=state.TotalObjectInputSamples;
[xTRS,projection]=sixgr.channel.projectRuntimeTransmitSamples(state,trs.TransmitSamples);
assert(state.CurrentSampleIndex==before && state.TotalObjectInputSamples==beforeObjectSamples);
assert(projection.ElementExpansionApplied && projection.ChannelInputColumns==state.NumTxAnt);
expectedProjection=trs.TransmitSamples*cast(state.PortToElementMatrix,'like',trs.TransmitSamples).';
assert(isequal(xTRS,expectedProjection));
assert(abs(norm(xTRS,'fro')-norm(trs.TransmitSamples,'fro'))<1e-10*norm(xTRS,'fro'));
assert(strlength(projection.ProjectionMatrixSHA256)==64);
assert(projection.ProjectionMatrixSHA256==string(state.ElementExpansionMatrixSHA256));
broadcast=sixgr.link.prepareCellSearchBroadcast(cfg,true);
assert(broadcast.SampleRateHz==trs.SampleRateHz);
assert(size(broadcast.TransmitSamples,2)==state.NumTxAnt, ...
    "The broadcast producer must already expose its actual physical beam samples.");
fs=trs.SampleRateHz;
% This fixture uses the authored 15 kHz profile; general numerology/CP
% placement is independently covered by testTRSSlotTimeline.
assert(cfg.phy.carrier.SubcarrierSpacing==15);
trsStart=round(trs.Tx.FirstSlot0Based*fs*1e-3);
stop=max(broadcast.NumSamples,trsStart+trs.NumSamples);
source=sixgr.phy.waveform.WaveformStreamComposer(fs,state.NumTxAnt,0);
source.enqueue("broadcast",sixgr.phy.waveform.WaveformChunk(broadcast.TransmitSamples,0),fs);
source.enqueue("trs",sixgr.phy.waveform.WaveformChunk(xTRS,trsStart),fs);
expected=complex(zeros(stop,state.NumTxAnt));
expected(1:broadcast.NumSamples,:)=broadcast.TransmitSamples;
expected(trsStart+(1:trs.NumSamples),:)=expected(trsStart+(1:trs.NumSamples),:)+xTRS;
% Independent oracle clone only in the test. Production uses one object,
% never resets it, and returns each RX window only at its final sample.
oracle=sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
reference=oracle.Obj(expected);
receiver=sixgr.phy.waveform.WaveformReceiveDispatcher(fs,size(reference,2),0);
receiver.register("broadcast",0,broadcast.NumSamples);
receiver.register("trs",trsStart,trsStart+trs.NumSamples);
received=zeros(size(reference),'like',reference);
ids=strings(0,1);
first=0;
for last=unique([13:round(fs*1e-3):stop stop])
    chunk=source.readThrough(last);
    assert(isequal(chunk.Samples,expected(first+1:last,:)));
    [y,replay,truth]=sixgr.link.applyRuntimeFadingChannel(chunk.Samples,truth, ...
        "OutputSampleAlignment","continuous_raw_samples", ...
        "InputSampleDomain","materialized_channel_ports");
    assert(replay.RuntimeChannelInputAlreadyProjected && ~replay.RuntimeChannelElementExpansionApplied);
    assert(~replay.RuntimeChannelInputPaddedToMaterializedPorts);
    assert(replay.RuntimeChannelStartSample==first && replay.RuntimeChannelEndSample==last);
    assert(~replay.RuntimeChannelAlignmentLookaheadExecutedOnFork);
    received(first+1:last,:)=y;
    completed=receiver.dispatch(sixgr.phy.waveform.WaveformChunk(y,first),fs);
    for k=1:numel(completed)
        item=completed(k);
        assert(~any(ids==item.ID));
        ids(end+1,1)=item.ID; %#ok<AGROW>
        assert(item.CompletionSample<=last);
        a=item.Observation.StartSample;
        b=item.Observation.EndSampleExclusive;
        assert(isequal(item.Observation.readComplete(),received(a+1:b,:)));
    end
    first=last;
end
assert(norm(received-reference,'fro')<=1e-12*max(1,norm(reference,'fro')));
assert(truth.RuntimeChannelState.CurrentSampleIndex==stop);
assert(truth.RuntimeChannelState.TotalObjectInputSamples==beforeObjectSamples+stop);
assert(truth.RuntimeChannelState.ResetCount==state.ResetCount);
assert(isequal(sort(ids),sort(["broadcast";"trs"])));
localError(@()sixgr.link.applyRuntimeFadingChannel(xTRS(:,1),truth, ...
    "InputSampleDomain","materialized_channel_ports"), ...
    "ChannelFactory:ProjectedInputDimensionMismatch");
localError(@()sixgr.link.applyRuntimeFadingChannel(xTRS,struct(), ...
    "InputSampleDomain","materialized_channel_ports"), ...
    "ChannelFactory:UninitializedContinuousChannel");
localError(@()sixgr.link.applyRuntimeFadingChannel(xTRS,truth, ...
    "InputSampleDomain","unknown"),"ChannelFactory:InvalidInputSampleDomain");
assert(truth.RuntimeChannelState.CurrentSampleIndex==stop);
fprintf('MATERIALIZED_CHANNEL_INPUT_COMPOSITION_PASS: %d actual composite samples; one physical clock.\n',stop);
ok=true;
end

function localError(action,identifier)
try
    action();
catch ME
    assert(string(ME.identifier)==identifier,"Expected %s; got %s: %s",identifier,ME.identifier,ME.message);
    return;
end
error("TEST:MissingExpectedError","Expected %s.",identifier);
end
