function ok=testRuntimeChannelContinuousSamples()
% Continuous channel output equals the untrimmed persistent filter response.
setup6GRSimToolkit("Verbose",false);
root=fileparts(fileparts(mfilename("fullpath")));
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,"simulator", ...
    "configs","scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(tempdir,"sixgr_continuous_channel"));
assert(cfg.channel.perSampleFadingEnabled, ...
    "The scenario must explicitly authorize per-waveform-sample fading.");
tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,"SNRdB",Inf);
x=tx.Waveform;
info=struct("OFDM",struct("SampleRate",tx.SampleRateHz));
state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,"DL", ...
    "LinkKey","test_continuous_tdd_broadcast", "Seed",cfg.run.seed);
localError(@() sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    state,x,"OutputSampleAlignment","continuous_raw_samples"), ...
    "ChannelFactory:UninitializedContinuousChannel");
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    state,cfg,x,info,"NumTxAnt",size(x,2),"NumRxAnt",2);
assert(state.Initialized && state.UseFading && state.CurrentSampleIndex==0);
assert(isinf(state.Obj.SampleDensity), ...
    "The actual channel object must consume the YAML coefficient-sampling authority.");
snapshotCfg=cfg;
snapshotCfg.channel.perSampleFadingEnabled=false;
snapshot=sixgr.channel.ChannelFactory.createRuntimeChannelState(snapshotCfg,"DL", ...
    "LinkKey","test_continuous_reject_snapshot_sampling", "Seed",cfg.run.seed);
snapshot=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    snapshot,snapshotCfg,x,info,"NumTxAnt",size(x,2),"NumRxAnt",2);
localError(@() sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    snapshot,x,"OutputSampleAlignment","continuous_raw_samples"), ...
    "ChannelFactory:ContinuousCDLRequiresPerSampleFading");
% Forks here are independent test references, never production RX evidence.
direct=sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
directChunks=sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
whole=sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
fprintf('Continuous channel backend: %s; alignment trim=%g pad=%g.\n', ...
    class(state.Obj),state.ChannelTrimSamples,state.ChannelPadSamples);
expected=direct.Obj(x);
[one,replay,whole]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    whole,x,"OutputSampleAlignment","continuous_raw_samples");
assert(isequal(size(one),size(expected)));
assert(norm(one-expected,'fro')<=1e-12*max(1,norm(expected,'fro')));
assert(replay.RuntimeChannelOutputSampleAlignment=="continuous_raw_samples");
assert(~replay.RuntimeChannelAlignmentLookaheadExecutedOnFork && ...
    replay.RuntimeChannelAlignmentLookaheadSamples==0 && ...
    replay.RuntimeChannelAppliedAlignmentTrimSamples==0);

% Boundaries deliberately cut through OFDM symbols as well as slots.
ends=[13,4099,16384,size(x,1)];
first=0;
received=complex(zeros(size(one),'like',one));
for stop=ends
    [part,r,state]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
        state,x(first+1:stop,:),"OutputSampleAlignment","continuous_raw_samples");
    assert(r.RuntimeChannelStartSample==first && r.RuntimeChannelEndSample==stop);
    assert(r.RuntimeChannelObjectClockExact && ~r.RuntimeChannelAlignmentLookaheadExecutedOnFork);
    assert(r.RuntimeChannelAppliedAlignmentTrimSamples==0);
    assert(size(part,1)==stop-first);
    received(first+1:stop,:)=part;
    referencePart=directChunks.Obj(x(first+1:stop,:));
    fprintf('Samples [%d,%d): API-vs-object=%g; partition-vs-whole=%g.\n', ...
        first,stop,norm(part-referencePart,'fro'),norm(part-one(first+1:stop,:),'fro'));
    assert(norm(part-referencePart,'fro')<=1e-12*max(1,norm(referencePart,'fro')));
    first=stop;
end
relativeError=norm(received-one,'fro')/max(1,norm(one,'fro'));
assert(relativeError<=1e-12, ...
    "Chunk boundaries changed physical channel samples: relative error %g.",relativeError);
assert(state.CurrentSampleIndex==whole.CurrentSampleIndex && ...
    state.TotalObjectInputSamples==whole.TotalObjectInputSamples);
assert(state.ResetCount==whole.ResetCount, ...
    "Streaming must not reset or rewind the fading process.");
localError(@() sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    struct(),x,"OutputSampleAlignment","continuous_raw_samples"), ...
    "ChannelFactory:UninitializedContinuousChannel");
localError(@() sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    state,x,"OutputSampleAlignment","unknown"), ...
    "ChannelFactory:InvalidOutputSampleAlignment");
localError(@() sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    state,NaN(10,2),"OutputSampleAlignment","continuous_raw_samples"), ...
    "ChannelFactory:InvalidContinuousSamples");
fprintf('RUNTIME_CHANNEL_CONTINUOUS_SAMPLES_PASS: %d real TX samples, relative error %g.\n', ...
    size(x,1),relativeError);
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
