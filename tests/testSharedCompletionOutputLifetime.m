function ok=testSharedCompletionOutputLifetime()
% Actual shared sample clock; declared payloads test memory ownership only.
% No access, data decode, throughput or full H4 memory qualification claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
prior=rng; restore=onCleanup(@()rng(prior)); %#ok<NASGU>
states=cell(1,2); returned=struct([]);
for keep=0:1
    rng(double(cfg.run.seed),'twister');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
    state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
    state.LifetimeKeepReturned=logical(keep);
    state.LifetimeSamples=[]; state.LifetimePayloadHashes=strings(0,1);
    state.LifetimeRetainedCounts=[];
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
    for k=1:3
        % A sizeable immutable context makes accidental slot-wide retention
        % observable without manufacturing a received waveform or channel.
        payload=complex(ones(256,4)*k,-ones(256,4)*k);
        owner.queueULDataPreparation(1,64*k,struct('LifetimePayload',payload));
    end
    if keep
        [state,returned]=sixgr.truth.advanceSharedSlotWithULGrants( ...
            state,cfg,struct([]),struct([]),@receive);
    else
        state=sixgr.truth.advanceSharedSlotWithULGrants( ...
            state,cfg,struct([]),struct([]),@receive);
    end
    assert(isequal(state.LifetimeSamples,[64,128,192]) && ...
        isempty(owner.Pending) && isempty(owner.DataTransmissions));
    states{keep+1}=state;
end
assert(isequal(states{1}.LifetimeRetainedCounts,[1 1 1]), ...
    'test:UnusedCompletedObservationsRetained', ...
    'State-only callbacks must not retain already delivered observations until slot end.');
assert(isequal(states{2}.LifetimeRetainedCounts,[1 2 3]) && numel(returned)==3, ...
    'Explicitly requested completed observations must remain available.');
assert(isequal(states{1}.LifetimePayloadHashes,states{2}.LifetimePayloadHashes));
for k=1:numel(returned)
    assert(sixgr.phy.waveform.WaveformHash.numeric(returned(k).Context.LifetimePayload)== ...
        states{1}.LifetimePayloadHashes(k));
end
assert(states{1}.SharedWaveformStream.Events.NextSampleIndex== ...
    states{2}.SharedWaveformStream.Events.NextSampleIndex && ...
    isequaln(states{1}.SharedWaveformStream.Events.ExecutionTrace, ...
             states{2}.SharedWaveformStream.Events.ExecutionTrace), ...
    'Output retention must not change channel/RF/noise execution or its clock.');
fprintf('SHARED_COMPLETION_LIFETIME_PASS state_only_counts=[1 1 1] returned_counts=[1 2 3] exact_callbacks=3\n');
ok=true;
end

function state=receive(state,items)
assert(isscalar(items) && items.Kind=="PrepareULData");
% White-box lifetime check on the real production callback caller. This
% does not alter production state or fabricate a PHY measurement.
state.LifetimeRetainedCounts(end+1)=evalin('caller','numel(completed)');
state.LifetimeSamples(end+1)=state.SharedWaveformStream.Events.NextSampleIndex;
state.LifetimePayloadHashes(end+1,1)= ...
    sixgr.phy.waveform.WaveformHash.numeric(items.Context.LifetimePayload);
end
