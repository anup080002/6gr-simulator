function ok = testMultiUETRSReceiverOwnership()
% Prescribed delivery/ownership fixture, not physical TRS qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),20);
state.CurrentSlot=3; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
fs=7.68e6;
first=localRow(1,fs,61440,251,2);
second=localRow(2,fs,61441,-73,9);
state=sixgr.truth.TRSResultDelivery.enqueue(state,1,1,first,cfg,table());
state=sixgr.truth.TRSResultDelivery.enqueue(state,1,2,second,cfg,table());
assert(numel(state.PendingTRSResults)==2,'Independent UE observations must coexist.');
localError(@()sixgr.truth.TRSResultDelivery.enqueue(state,1,1,first,cfg,table()), ...
    'sixgr:truth:DuplicatePendingTRS');
state.CurrentSlot=8;
[state,ready]=sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(isempty(ready));
state.CurrentSlot=9;
[state,ready]=sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(isscalar(ready) && ready.UEIndex==1);
wrongCell=ready.Trial; wrongCell.ServingCell=2;
localError(@()sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,wrongCell), ...
    'sixgr:truth:TRSMeasurementCellMismatch');
state=sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,ready.Trial);
one=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,1,1);
two=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,2,1);
assert(one.TRSProcessed && one.TrackingEligibility && one.TRSEstimatedCFO_Hz==251);
assert(~two.TRSProcessed && ~two.TrackingEligibility && isnan(two.TRSEstimatedCFO_Hz), ...
    'UE 2 must not inherit UE 1 tracking or scheduler eligibility.');
state.CurrentSlot=10;
[state,ready]=sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(isscalar(ready) && ready.UEIndex==2 && isempty(state.PendingTRSResults));
state=sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,ready.Trial);
one=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,1,1);
two=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,2,1);
assert(one.TRSEstimatedCFO_Hz==251 && one.TRSTimingEstimate_samples==2);
assert(two.TRSEstimatedCFO_Hz==-73 && two.TRSTimingEstimate_samples==9);
assert(one.LastSuccessfulTRSSlot==9 && two.LastSuccessfulTRSSlot==10);
for ue=1:2
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,ue,'DL');
    expected=[251 -73];
    assert(bound.lls6g.userContext.RuntimeTRSEstimatedCFO_Hz==expected(ue));
end
assert(isequal(state.ReceiverTrackingTraceTable.UEIndex,[1;2]));
measurements=state.ReferenceSignalMeasurementTable;
assert(all(string(measurements.TargetType)=="UE") && ...
    isequal(double(measurements.TargetId),[1;2]),'Reference measurements need receiver ownership.');
artifacts=sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(state);
tracking=artifacts.ReceiverTrackingStateTable;
for ue=1:2
    actual=tracking(tracking.UEIndex==ue & tracking.ServingCell==1,:);
    expected=[251 -73];
    assert(height(actual)==1 && actual.EstimatedCFO_Hz==expected(ue), ...
        'Tracking export must preserve distinct receiver estimates.');
end
% A new unusable observation invalidates its own live tracking object. An
% older fresh success cannot resurrect the now-cleared timing/CFO fields.
failed=localRow(1,fs,69120,999,99); failed.Slot=9;
failed.Status="FAIL"; failed.DetectionSuccess=false;
failureState=sixgr.truth.TRSResultDelivery.enqueue(state,1,1,failed,cfg,table());
[failureState,failedReady]=sixgr.truth.TRSResultDelivery.takeAvailable(failureState);
assert(isscalar(failedReady));
failureState=sixgr.truth.CoupledTruthRuntime.applyTRSTrial(failureState,1,failedReady.Trial);
bad=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(failureState,cfg,1,1);
other=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(failureState,cfg,2,1);
assert(~bad.TrackingEligibility && bad.TRSValidityState=="failed" && ...
    ~bad.TRSCFOEstimateAvailable && isnan(bad.TRSEstimatedCFO_Hz), ...
    'test:FailedTRSResurrected','Freshness must not resurrect an unusable receiver observation.');
assert(other.TrackingEligibility && other.TRSEstimatedCFO_Hz==-73, ...
    'A failed UE 1 observation must not invalidate UE 2.');
noOwner=rmfield(table2struct(failedReady.Trial),'UEIndex');
localError(@()sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,struct2table(noOwner)), ...
    'sixgr:truth:MissingTRSReceiverOwner');
state.ControlGating.TRSMaxAgeSlots=1;
state.CurrentSlot=11;
state=sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
one=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,1,1);
two=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,2,1);
assert(~one.TrackingEligibility && one.TRSValidityState=="stale");
assert(two.TrackingEligibility && two.TRSValidityState=="valid");
ok=true;
disp('MULTI_UE_TRS_RECEIVER_OWNERSHIP_PASS');
end

function row=localRow(ue,fs,last,cfo,timing)
row=struct2table(struct('Frame',1,'Slot',3,'UEIndex',ue,'ServingCell',1, ...
    'Status',"PASS",'EstimatedDopplerHz',0,'NMSE_dB',-18, ...
    'DetectionMetric',0.99,'DetectionAttempted',true,'DetectionSuccess',true, ...
    'TimingTrackingAttempted',true,'TRSTimingEstimateUsable',true, ...
    'TRSTimingEstimateAvailable',true,'EstimatedTimingOffset_samples',timing, ...
    'FrequencyTrackingAttempted',true,'TRSCFOEstimateUsable',true, ...
    'TRSCFOEstimateAvailable',true,'EstimatedCFO_Hz',cfo, ...
    'EstimatedCommonFrequency_Hz',cfo,'EstimatedOscillatorCFO_Hz',NaN, ...
    'FrequencyEstimateDomain',"received_TRS_common_phase_frequency", ...
    'ChannelEstimationAttempted',true, ...
    'TRSChannelEstimateAvailable',true,'TRSRuntimeEvidenceUsable',true, ...
    'StrictOk',true,'UsedOracleFields',"", ...
    'ObservationStartSample',15360,'ObservationEndSampleExclusive',last, ...
    'ObservationSampleRateHz',fs,'ObservationCompletionTime_s',last/fs, ...
    'ObservationCoverageSource',"complete_contiguous_received_sample_buffer"));
end

function localError(f,identifier)
try, f(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s.',identifier,cause.identifier);
    return;
end
error('TEST:MissingError','Expected %s.',identifier);
end
