function ok=testBroadcastResultDelivery()
% Scheduling fixture, not PHY-measurement or conformance evidence.
setup6GRSimToolkit("Verbose",false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs", ...
    "scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct("Enabled",true,"NumUsers",1,"RNTIStart",1, ...
    "ExecutionModel","slot_coupled_truth");
base=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),8);
base.CurrentSlot=1;
base.CurrentServingIdx(:)=1;
fs=7.68e6;
row=localRow(fs,38400);
recovery=struct("FixtureIdentity","receiver_recovery_payload");
state=sixgr.truth.BroadcastResultDelivery.enqueue(base,1,row,recovery,false);
assert(sixgr.truth.BroadcastResultDelivery.hasPending(state,1));
assert(isequaln(state.CellAcquisitionState,base.CellAcquisitionState));
assert(isequaln(state.ReferenceSignalMeasurementTable,base.ReferenceSignalMeasurementTable));
assert(isequaln(state.ControlTrials.PBCH,base.ControlTrials.PBCH));
localError(@()sixgr.truth.BroadcastResultDelivery.enqueue(state,1,row,recovery,false), ...
    "sixgr:truth:DuplicatePendingBroadcast");
localError(@()sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state,1,row), ...
    "sixgr:truth:BroadcastResultBeforeDelivery");
for slot=1:5
    state.CurrentSlot=slot;
    [state,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
    assert(isempty(ready) && sixgr.truth.BroadcastResultDelivery.hasPending(state,1));
    assert(isequaln(state.CellAcquisitionState,base.CellAcquisitionState));
end
state.CurrentSlot=6; % Slot six begins at 5 ms, the actual observation end.
[state,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
assert(numel(ready)==1 && ~sixgr.truth.BroadcastResultDelivery.hasPending(state,1));
assert(isequaln(ready.Recovery,recovery));
assert(ready.Trial.Slot==1 && ready.Trial.ObservationDeliverySlot==6);
assert(ready.Trial.ObservationDeliveryTime_s==38400/fs);
assert(isequaln(ready.Trial(:,row.Properties.VariableNames),row));
delivered=sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state,1,ready.Trial);
assert(delivered.CellAcquisitionState(1)=="acquired");
assert(delivered.LastSuccessfulPBCHSlotByUE(1)==6);
measurement=delivered.ReferenceSignalMeasurementTable(end,:);
assert(measurement.ProducerSlot==1 && measurement.AvailableSlot==6);
assert(all(delivered.InitialAccessLifecycleTraceTable.Slot==6));
[~,again]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
assert(isempty(again),"Delivery must be exactly once.");

% Neither rounding nor a slot label may make the next sample available.
oneSampleLater=localRow(fs,38401);
late=sixgr.truth.BroadcastResultDelivery.enqueue(base,1,oneSampleLater,recovery,false);
late.CurrentSlot=6;
[late,readyLate]=sixgr.truth.BroadcastResultDelivery.takeAvailable(late);
assert(isempty(readyLate));
late.CurrentSlot=7;
[~,readyLate]=sixgr.truth.BroadcastResultDelivery.takeAvailable(late);
assert(numel(readyLate)==1 && readyLate.Trial.ObservationDeliverySlot==7);

bad=row; bad.ObservationCompletionTime_s=0;
localError(@()sixgr.truth.BroadcastResultDelivery.enqueue(base,1,bad,recovery,false), ...
    "sixgr:truth:InvalidBroadcastObservationClock");
bad=row; bad.ObservationEndSampleExclusive=NaN;
localError(@()sixgr.truth.BroadcastResultDelivery.enqueue(base,1,bad,recovery,false), ...
    "sixgr:truth:InvalidBroadcastObservationClock");
bad=row; bad.ObservationCoverageSource="configured_duration_only";
localError(@()sixgr.truth.BroadcastResultDelivery.enqueue(base,1,bad,recovery,false), ...
    "sixgr:truth:InvalidBroadcastObservationClock");
bad=row; bad.Slot=2;
localError(@()sixgr.truth.BroadcastResultDelivery.enqueue(base,1,bad,recovery,false), ...
    "sixgr:truth:InvalidBroadcastObservationClock");
bad=removevars(row,"ObservationStartSample");
localError(@()sixgr.truth.BroadcastResultDelivery.enqueue(base,1,bad,recovery,false), ...
    "sixgr:truth:MissingBroadcastObservationClock");
early=state; early.CurrentSlot=5;
localError(@()sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(early,1,ready.Trial), ...
    "sixgr:truth:BroadcastResultBeforeDelivery");

% Tracking retains acquisition, and preserves source versus available slot.
tracking=sixgr.truth.BroadcastResultDelivery.enqueue(delivered,1,row,recovery,true);
[tracking,trackingReady]=sixgr.truth.BroadcastResultDelivery.takeAvailable(tracking);
assert(trackingReady.TrackingOnly);
tracking=sixgr.truth.CoupledTruthRuntime.applyServingSSBTrackingTrial( ...
    tracking,1,trackingReady.Trial);
assert(tracking.CellAcquisitionState(1)=="acquired");
assert(tracking.LastSuccessfulSSBTrackingSlotByUE(1)==6);
assert(tracking.ReferenceSignalMeasurementTable.AvailableSlot(end)==6);
censored=sixgr.truth.BroadcastResultDelivery.censorAtSweepBoundary(late);
assert(~sixgr.truth.BroadcastResultDelivery.hasPending(censored,1));
assert(numel(censored.CensoredBroadcastResults)==1);
assert(isequaln(censored.CensoredBroadcastResults{1}.Results.Trial,oneSampleLater));
fprintf('BROADCAST_RESULT_DELIVERY_PASS: source slot 1, delivery slot 6; no early acquisition or measurement.\n');
ok=true;
end

function row=localRow(fs,last)
row=struct2table(struct("Slot",1,"Status","PASS","CRCPass",true, ...
    "RNTI",1,"ServingCell",1,"SSBIndex",0,"ReferenceSignalId",0,"SS_RSRP_dBm",-95, ...
    "MeasuredReferenceSignalPathloss_dB",100, ...
    "PathlossReferenceRS","SSB-0", ...
    "MeasuredReferenceSignalPathlossSource","test_fixture_only", ...
    "ObservationStartSample",0,"ObservationEndSampleExclusive",last, ...
    "ObservationSampleRateHz",fs,"ObservationCompletionTime_s",last/fs, ...
    "ObservationCoverageSource","complete_contiguous_received_sample_buffer"));
end

function localError(action,identifier)
try
    action();
catch ME
    assert(string(ME.identifier)==identifier,"Expected %s, got %s: %s",identifier,ME.identifier,ME.message);
    return;
end
error("TEST:MissingExpectedError","Expected %s.",identifier);
end
