function ok=testSharedGrantPreparationClock()
% Metadata preparation must not acquire/advance the shared fading owner.
% Explicit component fixture, not decoded access or main-run qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),2);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
% Slots 0/1 carry SS/PBCH in this profile. Use the following DL occasion
% for data; preparing its metadata still must not move the physical clock.
[dl,preparedOccasion]=sixgr.truth.bindSharedDataOccasion(dl,3,1,owner.SampleRateHz);
reservation=sixgr.phy.frame.ssbPRBSymbolReservation(dl,sixgr.phy.grid.makeCarrier(dl),2);
assert(isempty(reservation.ReservedCarrierRE0),'The clock fixture must use an actual SSB-free occasion.');
state.CurrentSlot=3; state.CurrentCanonicalSlot=3;
grant=sixgr.link.resolveWaveformGrant(dl,'DL',2);
before=owner.directionalChannelState(1,'DL');
[state,context,~]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(state,dl,1,'DL',grant);
after=owner.directionalChannelState(1,'DL');
assert(owner.Events.NextSampleIndex==0 && isempty(owner.Pending) && isempty(owner.DataTransmissions));
assert(before.CurrentSampleIndex==after.CurrentSampleIndex && ...
    context.ChannelState.CurrentSampleIndex==before.CurrentSampleIndex);
expectedTime=preparedOccasion.StartSample/owner.SampleRateHz;
assert(context.ChannelState.TargetSlotStartTime_s==expectedTime);
assert(context.AbsoluteSampleTime_s==expectedTime && ~context.GrantSnapshot.GrantWorkerSafe);
[future,occasion]=sixgr.truth.bindSharedDataOccasion(dl,4,1,owner.SampleRateHz);
assert(future.lls6g.runtime.AbsoluteSlotIndexOneBased==4 && ...
    future.lls6g.userContext.RuntimeSlotStartTime_s==occasion.StartSample/owner.SampleRateHz && ...
    dl.lls6g.userContext.RuntimeSlotStartTime_s==expectedTime && ...
    owner.Events.NextSampleIndex==0 && isempty(owner.Pending));
% The timer is an available-knowledge decision, not a grant or waveform.
state.CurrentSlot=1; state.CurrentCanonicalSlot=1;
owner.queueULDataPreparation(1,64,struct('FixtureDecisionSample',64));
[state,~]=owner.advanceSlot(state,cfg,@localDecision);
assert(isequal(state.ObservedPreparationDecisionSamples,64));
assert(isempty(owner.DataTransmissions));
ok=true; disp('SHARED_GRANT_PREPARATION_CLOCK_PASS');
end

function state=localDecision(state,events)
for item=events
    assert(item.Kind=="PrepareULData" && isempty(item.Planes));
    assert(state.SharedWaveformStream.Events.NextSampleIndex==item.Context.FixtureDecisionSample);
    state.ObservedPreparationDecisionSamples=item.Context.FixtureDecisionSample;
end
end
