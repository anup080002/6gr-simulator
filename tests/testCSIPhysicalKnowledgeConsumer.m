function ok=testCSIPhysicalKnowledgeConsumer(outputRoot)
% Actual physical-owner clock with declared CSI boundary fixtures. This test
% does not transmit or measure CSI-RS and is not integrated CSI qualification.
setup6GRSimToolkit('Verbose',false);
if nargin<1
    logsRoot=fullfile(pwd,'logs');
    if ~isfolder(logsRoot), mkdir(logsRoot); end
    outputRoot=tempname(logsRoot);
end
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier evidence.');
mkdir(outputRoot);
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_pucch_gnb_receive_only_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,cfg.channel.snr_dB);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
assert(owner.Events.NextSampleIndex==0);
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
slotEnd=sixgr.phy.frame.slotStartSample(carrier,1,fs);
row=table(1,true,true,true,true,true,true,"declared_CSI_boundary_not_RF_measurement",1, ...
    'VariableNames',{'Slot','Transmitted','Observed','Consumed','ResourceExtractionAvailable', ...
    'ChannelEstimateAvailable','CSIMeasurementAvailable','MeasurementSource','ObservationDeliverySlot'});
row.ObservationStartSample=0; row.ObservationEndSampleExclusive=1;
row.ResultAvailableAtSample=2; row.ObservationSampleRateHz=fs;
row.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
row.DeliverySlotStartSample=0; row.DeliverySlotEndSampleExclusive=slotEnd;
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
% Complete declared SSB input for the installed preconnection RSRP filter.
% These values exercise mixed clock schemas, not an SSB RF measurement.
ssbRow=struct('Slot',1,'ServingCell',1,'ReferenceSignalId',0,'SS_RSRP_dBm',-80);
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,ssbRow,'ProducerSlot',1,'AvailableSlot',1, ...
    'Valid',true,'MeasurementSource','declared_slot_only_schema_fixture');
before=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state,'CSI-RS','UE',1,1,inf);
assert(~before.Usable && before.KnownAtSample==0 && before.NextAvailableSample==2);
ssb=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state,'SSB','UE',1,1,inf);
assert(ssb.Usable && isnan(ssb.ResultAvailableAtSample));
state.CurrentCanonicalSlot=1; state.LastTrafficFrameApplied=0;
plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,5);
assert(plan.PlanningDecisionSample==0 && plan.PlanningDecisionSampleRateHz==fs && ...
    plan.PlanningDecisionClockEpoch==owner.Physical.ConfigurationEpoch);
% Advance the actual configured physical owner with no queued transmitter
% contribution. No sample-clock value is assigned by the test.
[state,~]=owner.advanceSlot(state,cfg,@noEvents);
assert(owner.Events.NextSampleIndex==slotEnd);
state.CurrentSlot=2; state.CurrentCanonicalSlot=2;
live=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state,'CSI-RS','UE',1,2,inf);
frozen=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(plan,'CSI-RS','UE',1,5,inf);
assert(live.Usable && live.KnownAtSample==slotEnd && live.ResultAvailableAtSample==2);
assert(~frozen.Usable && frozen.KnownAtSample==0, ...
    'Advancing the shared handle cannot reveal later knowledge to an older planning view.');
bad=plan; bad.PlanningDecisionSample=slotEnd+1;
reject(@()sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(bad,'CSI-RS','UE',1,5,inf), ...
    'sixgr:truth:MeasurementPlanningClockMismatch');
save(fullfile(outputRoot,'clock_consumer_results.mat'),'cfg','row','before','ssb','live','frozen');
fprintf('CSI_PHYSICAL_KNOWLEDGE_CONSUMER_PASS published_and_consumed=1 physical_clock_advanced=%g frozen_planning_clock=0 CSI_RF_executions=0\n',slotEnd);
ok=true;
end
function state=noEvents(state,events,owner) %#ok<INUSD>
assert(isempty(events),'test:UnexpectedEvents','No CSI transmitter or receiver event is declared in this clock unit test.');
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
