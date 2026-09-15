function ok=testSharedULGrantCalendarLifetime()
% Real shared event clock, resource-only calendar fixture. No fabricated
% DCI reception, transmitted PUSCH, ACK result or end-to-end acceptance.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),2);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
due=struct('Slot',1,'FixtureIdentity',"due",'EncodedPayloadIdentity',"immutable");
future=struct('Slot',2,'FixtureIdentity',"future");
owner.queueULDataPreparation(1,64,struct('FixtureDecisionSample',64));
[state,~]=sixgr.truth.advanceSharedSlotWithULGrants(state,cfg,future,due,@localObserve);
assert(state.CalendarObservedAtSample==64);
pending=state.SharedPendingULGrants;
assert(isequal([pending.Slot],[2,3]) && ...
    isequal(string({pending.FixtureIdentity}),["future","received_during_slot"]));
assert(isempty(owner.DataTransmissions),'A calendar fixture must not claim a PHY transmission.');
% Invalid partitions must fail before consuming any physical samples.
before=owner.Events.NextSampleIndex;
try
    sixgr.truth.advanceSharedSlotWithULGrants(state,cfg,due,due,@localObserve);
    error('test:ExpectedRejection','A due grant must not also be in the future calendar.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InvalidSharedULCalendarPartition'));
end
assert(owner.Events.NextSampleIndex==before);
ok=true; disp('SHARED_UL_GRANT_CALENDAR_LIFETIME_PASS');
end

function state=localObserve(state,events)
assert(isscalar(events) && events.Kind=="PrepareULData");
assert(state.SharedWaveformStream.Events.NextSampleIndex==64);
pending=state.SharedPendingULGrants;
hit=find(string({pending.FixtureIdentity})=="due");
assert(isscalar(hit),'The due grant must remain owned inside the physical callback.');
assert(pending(hit).EncodedPayloadIdentity=="immutable");
% A callback can admit a future grant; retirement must preserve this update.
added=pending(1); added.Slot=3; added.FixtureIdentity="received_during_slot";
pending(end+1)=added;
state.SharedPendingULGrants=pending;
state.CalendarObservedAtSample=state.SharedWaveformStream.Events.NextSampleIndex;
end
