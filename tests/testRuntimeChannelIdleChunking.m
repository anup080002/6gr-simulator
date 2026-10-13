function ok=testRuntimeChannelIdleChunking()
% Actual fading objects: bounded idle calls must equal monolithic silence.
% This is a numerical channel/clock regression, not a decoded BLER result.
assert(exist('nrCDLChannel','class')==8 && exist('nrTDLChannel','class')==8);
fs=122.88e6; idle=2053; cap=257; cases=0;
for profile=["TDL-C","CDL-C"]
    if startsWith(profile,'CDL')
        channel=nrCDLChannel('DelayProfile',char(profile),'DelaySpread',100e-9, ...
            'MaximumDopplerShift',37,'SampleRate',fs,'SampleDensity',Inf, ...
            'RandomStream','mt19937ar with seed','Seed',8137);
        channel.TransmitAntennaArray.Size=[1 2 1 1 1];
        channel.ReceiveAntennaArray.Size=[1 2 1 1 1];
    else
        channel=nrTDLChannel('DelayProfile',char(profile),'DelaySpread',100e-9, ...
            'MaximumDopplerShift',37,'SampleRate',fs, ...
            'NumTransmitAntennas',2,'NumReceiveAntennas',2, ...
            'RandomStream','mt19937ar with seed','Seed',8137);
    end
    reference=clone(channel);
    state=struct('ContractVersion',"runtime_channel_state_v1", ...
        'Materialized',true,'UseFading',true,'Obj',channel,'NumTxAnt',2, ...
        'SampleRate_Hz',fs,'CurrentSampleIndex',0,'TotalObjectInputSamples',0, ...
        'TotalIdleAdvancedSamples',0,'ElementExpansionChunkSamples',cap);
    prefix=reshape(exp(1i*(1:256)/13),128,2);
    channel(prefix); reference(prefix);
    state.CurrentSampleIndex=128; state.TotalObjectInputSamples=128;
    state=sixgr.channel.ChannelFactory.advanceRuntimeChannelState(state,idle,2,prefix);
    reference(complex(zeros(idle,2)));
    suffix=reshape(exp(1i*(1:512)/7),256,2);
    observed=channel(suffix); expected=reference(suffix);
    assert(norm(observed-expected,'fro')<1e-11*max(norm(expected,'fro'),realmin), ...
        'Bounded idle consumption changed actual fading/filter history.');
    assert(state.CurrentSampleIndex==128+idle && ...
        state.TotalObjectInputSamples==128+idle && ...
        state.TotalIdleAdvancedSamples==idle && state.LastIdleAdvancedSamples==idle && ...
        state.LastIdlePhysicalChunkCount==ceil(idle/cap) && ...
        state.LastIdlePhysicalMaxChunkSamples==cap && ...
        state.CurrentTime_s==(128+idle)/fs);
    cases=cases+1;
end
% Finite-snapshot CDL must not silently change its channel sampling model.
channel=nrCDLChannel('SampleDensity',64);
state.Obj=channel;
try
    sixgr.channel.ChannelFactory.advanceRuntimeChannelState(state,idle,2,[]);
catch failure
    assert(strcmp(failure.identifier,'ChannelFactory:ContinuousCDLRequiresPerSampleFading'));
    ok=true;
    fprintf('PASS testRuntimeChannelIdleChunking: %d actual profiles, same waveform/clock, bounded calls.\n',cases);
    return;
end
error('test:FiniteSnapshotIdlePartitionAccepted','Finite CDL snapshot semantics must not change silently.');
end
