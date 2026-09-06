function ok = testTRSResultDelivery()
% Scheduling fixture only: these prescribed values are not PHY evidence.
setup6GRSimToolkit('Verbose',false);
assert(nargin('sixgr.truth.runWaveformLinkBundle')==3); % Parse the production adapter.
source = fileread(which('sixgr.truth.runWaveformLinkBundle'));
assert(contains(source,'state = localDeliverCoupledTRSResults(state);'));
assert(contains(source,'state = sixgr.truth.TRSResultDelivery.enqueue('));
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
multi = struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
base = sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),12);
base.CurrentSlot = 3;
base.CurrentFrame = 1;
base.CurrentServingIdx(:) = 1;
fs = 7.68e6;
row = localRow(fs,61440);
re = table([2;7],'VariableNames',{'AbsoluteSlot'});
state = sixgr.truth.TRSResultDelivery.enqueue(base,1,1,row,cfg,re);
assert(isequaln(state.TRSValidityStateByCell,base.TRSValidityStateByCell));
assert(isequaln(state.ReferenceSignalMeasurementTable,base.ReferenceSignalMeasurementTable));
assert(isequaln(state.ControlTrials.TRS,base.ControlTrials.TRS));
assert(isequaln(state.ObservedREAllocationTable,base.ObservedREAllocationTable));
localError(@()sixgr.truth.TRSResultDelivery.enqueue(state,1,1,row,cfg,re), ...
    'sixgr:truth:DuplicatePendingTRS');
localError(@()sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,row), ...
    'sixgr:truth:TRSResultBeforeDelivery');
for slot = 3:8
    state.CurrentSlot = slot;
    [state,ready] = sixgr.truth.TRSResultDelivery.takeAvailable(state);
    assert(isempty(ready));
    assert(isequaln(state.ReceiverTrackingStateByCell,base.ReceiverTrackingStateByCell));
    assert(isequaln(state.ControlTrials.TRS,base.ControlTrials.TRS));
end
state.CurrentSlot = 9; % 8 ms: both configured resources have been received.
[state,ready] = sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(numel(ready)==1 && isempty(state.PendingTRSResults));
assert(isequaln(ready.Trial(:,row.Properties.VariableNames),row));
assert(isequaln(ready.ObservedRE,re));
assert(ready.Trial.Slot==3 && ready.Trial.ObservationDeliverySlot==9);
delivered = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,ready.Trial);
assert(delivered.TrackingEligibilityByCell(1));
assert(delivered.LastSuccessfulTRSSlotByCell(1)==9);
assert(delivered.ReceiverTrackingStateByCell(1).LastUpdateSlot==9);
assert(delivered.ReceiverTrackingStateByCell(1).TRSTrackingUpdateTime_s==0.008);
assert(strcmp(delivered.ReceiverTrackingStateByCell(1).MeasurementSFNSlot,'frame=1,slot=3'));
assert(delivered.ReferenceSignalMeasurementTable.ProducerSlot(end)==3);
assert(delivered.ReferenceSignalMeasurementTable.AvailableSlot(end)==9);
assert(delivered.ReceiverTrackingTraceTable.Slot(end)==9);
assert(delivered.ReceiverTrackingTraceTable.TRSTrackingUpdateTime_s(end)==0.008);
[~,again] = sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(isempty(again));
early = state; early.CurrentSlot = 8;
localError(@()sixgr.truth.CoupledTruthRuntime.applyTRSTrial(early,1,ready.Trial), ...
    'sixgr:truth:TRSResultBeforeDelivery');
% Do not round a receive window ending one sample after a slot boundary.
late = sixgr.truth.TRSResultDelivery.enqueue(base,1,1,localRow(fs,61441),cfg,re);
late.CurrentSlot = 9;
[late,notYet] = sixgr.truth.TRSResultDelivery.takeAvailable(late);
assert(isempty(notYet));
late.CurrentSlot = 10;
[~,due] = sixgr.truth.TRSResultDelivery.takeAvailable(late);
assert(numel(due)==1 && due.Trial.ObservationDeliverySlot==10);
bad = row; bad.ObservationCompletionTime_s = 0;
localError(@()sixgr.truth.TRSResultDelivery.enqueue(base,1,1,bad,cfg,re), ...
    'sixgr:truth:InvalidTRSObservationClock');
bad = row; bad.ObservationEndSampleExclusive = NaN;
localError(@()sixgr.truth.TRSResultDelivery.enqueue(base,1,1,bad,cfg,re), ...
    'sixgr:truth:InvalidTRSObservationClock');
bad.RuntimeIntegrationMode = "coupled_slot_runtime";
localError(@()sixgr.truth.CoupledTruthRuntime.applyTRSTrial(base,1,bad), ...
    'sixgr:truth:MissingTRSObservationClock');
bad = row; bad.ObservationCoverageSource = "configured_duration_only";
localError(@()sixgr.truth.TRSResultDelivery.enqueue(base,1,1,bad,cfg,re), ...
    'sixgr:truth:InvalidTRSObservationClock');
bad = row; bad.ServingCell = 2;
localError(@()sixgr.truth.TRSResultDelivery.enqueue(base,1,1,bad,cfg,re), ...
    'sixgr:truth:TRSResultOwnerMismatch');
censored = sixgr.truth.TRSResultDelivery.censorAtSweepBoundary(late);
assert(isempty(censored.PendingTRSResults));
assert(numel(censored.CensoredTRSResults)==1);
assert(isequaln(censored.CensoredTRSResults{1}.Results.Trial,localRow(fs,61441)));
terminal = sixgr.truth.CoupledTruthRuntime.finalizeFiniteHorizonRuntime(late,9,'fixture_end');
assert(isempty(terminal.PendingTRSResults));
assert(terminal.CensoredTRSResults{1}.Reason=="terminal_horizon_before_trs_delivery:fixture_end");
assert(isequaln(terminal.ControlTrials.TRS,late.ControlTrials.TRS));
% A physically received failure must wait for its observation completion too.
failedRow = row; failedRow.Status = "FAIL"; failedRow.DetectionSuccess = false;
failed = sixgr.truth.TRSResultDelivery.enqueue(base,1,1,failedRow,cfg,re);
failed.CurrentSlot = 8;
[failed,noFailureYet] = sixgr.truth.TRSResultDelivery.takeAvailable(failed);
assert(isempty(noFailureYet) && failed.TRSFailureCountByCell(1)==base.TRSFailureCountByCell(1));
failed.CurrentSlot = 9;
[failed,failedReady] = sixgr.truth.TRSResultDelivery.takeAvailable(failed);
failed = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(failed,1,failedReady.Trial);
assert(~failed.TrackingEligibilityByCell(1));
assert(failed.TRSFailureCountByCell(1)==base.TRSFailureCountByCell(1)+1);
ok = true;
disp('TRS_RESULT_DELIVERY_PASS');
end

function row = localRow(fs,last)
row = struct2table(struct('Frame',1,'Slot',3,'UEIndex',1,'ServingCell',1, ...
    'Status',"PASS",'EstimatedDopplerHz',0,'NMSE_dB',-18, ...
    'DetectionMetric',0.99,'DetectionAttempted',true,'DetectionSuccess',true, ...
    'DetectionUsable',true,'TimingTrackingAttempted',true, ...
    'TRSTimingEstimateAvailable',true,'EstimatedTimingOffset_samples',0, ...
    'TRSTimingEstimateUsable',true,'FrequencyTrackingAttempted',true, ...
    'TRSCFOEstimateAvailable',true,'TRSCFOEstimateUsable',true, ...
    'EstimatedCFO_Hz',0,'ChannelEstimationAttempted',true, ...
    'TRSChannelEstimateAvailable',true,'TRSRuntimeEvidenceUsable',true, ...
    'StrictOk',true,'UsedOracleFields',"", ...
    'ObservationStartSample',15360,'ObservationEndSampleExclusive',last, ...
    'ObservationSampleRateHz',fs,'ObservationCompletionTime_s',last/fs, ...
    'ObservationCoverageSource',"complete_contiguous_received_sample_buffer"));
end
function localError(f,identifier)
try
    f();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message);
    return;
end
error('TEST:MissingError','Expected %s.',identifier);
end
