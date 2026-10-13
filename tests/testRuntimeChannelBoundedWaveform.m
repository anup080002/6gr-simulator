function ok=testRuntimeChannelBoundedWaveform()
% Exact native sample partitioning, including standalone grant-aligned RA.
setup6GRSimToolkit('Verbose',false);
cfg=struct(); cfg.run.seed=913;
cfg.channel.model='CDL'; cfg.channel.cdlProfile='CDL-C';
cfg.channel.delaySpread_s=100e-9; cfg.channel.doppler_Hz=37;
cfg.channel.channelFiltering=true; cfg.channel.normalizePathGains=true;
cfg.channel.perSampleFadingEnabled=true;
cfg.channel.runtimeElementExpansionChunkSamples=257;
cfg.phy.fc_Hz=4e9; cfg.phy.carrier.NSizeGrid=273;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.duplex.mode='TDD';
fs=122.88e6; samples=2053;
x=reshape(exp(1i*(1:2*samples)/7),samples,2);
state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL', ...
    'LinkKey','bounded_grant_aligned_waveform','Seed',8173);
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,cfg,x, ...
    struct('OFDM',struct('SampleRate',fs)),'NumTxAnt',2,'NumRxAnt',2);
reference=clone(state.Obj);
for attempt=1:2
    [actual,replay,state]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(state,x);
    expectedRaw=reference(x);
    if state.ChannelPadSamples>0
        tail=clone(reference);
        expectedRaw=[expectedRaw;tail(complex(zeros(state.ChannelPadSamples,2)))]; %#ok<AGROW>
    end
    expected=expectedRaw(state.ChannelTrimSamples+(1:samples),:);
    assert(norm(actual-expected,'fro')<1e-11*max(norm(expected,'fro'),realmin), ...
        'Chunking must preserve the monolithic native waveform, including alignment tail.');
    assert(state.CurrentSampleIndex==attempt*samples && ...
        state.TotalObjectInputSamples==state.WarmupSamples+attempt*samples && ...
        state.ResetCount==1 && replay.RuntimeChannelObjectClockExact);
    if attempt==1
        assert(replay.ChannelPathGainsAvailable && ...
            replay.RuntimeChannelPathGainCaptureScope== ...
            "first_executed_sample_exact_bounded_diagnostic");
    else
        assert(~replay.ChannelPathGainsAvailable);
    end
end
ok=true;
fprintf('PASS testRuntimeChannelBoundedWaveform: 100-MHz clock, native CDL-C, exact samples/tail/clock.\n');
end
