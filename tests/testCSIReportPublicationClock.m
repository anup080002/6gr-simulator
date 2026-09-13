function ok=testCSIReportPublicationClock()
% Actual shared clock, declared CSI receiver rows; no CSI RF qualification.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmpi(which('sixgr.truth.CoupledTruthRuntime'), ...
    fullfile(root,'+sixgr','+truth','CoupledTruthRuntime.m')));
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,12);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[state,~]=owner.advanceSlot(state,cfg,@noEvents);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,2,10,12);
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
now=owner.Events.NextSampleIndex;
row=table(1,1,1,true,true,true,true,true,true,10,1,0,0,0,18.5, ...
    "declared_received_CSI_report_clock_fixture", ...
    'VariableNames',{'Slot','UEIndex','ServingCell','Transmitted','Observed', ...
    'Consumed','ResourceExtractionAvailable','ChannelEstimateAvailable', ...
    'CSIMeasurementAvailable','CQI','RI','PMI','CRI','LI','SINR_dB','MeasurementSource'});
row.ObservationDeliverySlot=2;
row.ObservationStartSample=0; row.ObservationEndSampleExclusive=now;
row.ResultAvailableAtSample=now; row.ObservationSampleRateHz=fs;
row.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
row.DeliverySlotStartSample=now;
row.DeliverySlotEndSampleExclusive=sixgr.phy.frame.slotStartSample(carrier,2,fs);
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
before=state.ReferenceSignalMeasurementTable;
dmrs=table(1,7,1,0,true, ...
    'VariableNames',{'Slot','WidebandCQI','RIEstimate','PMI','CRCPass'});
state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',dmrs,cfg,row);
assert(isequaln(before,state.ReferenceSignalMeasurementTable), ...
    'test:CSIReportRepublishedMeasurement', ...
    'Queuing CSI must not duplicate or retime already published receiver evidence.');
report=state.PendingCSITable(end,:);
assert(report.CQI==row.CQI && report.SourceSlot==row.Slot && report.DueSlot>2);
assert(report.MeasurementAvailableSlot==2 && report.MeasurementAvailableAtSample==now && ...
    report.MeasurementClockEpoch==owner.Physical.ConfigurationEpoch && ...
    string(report.MeasurementClockDomain)=="shared_receiver_sample_clock/v1");
available=sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime( ...
    state,'CSI-RS','UE',1,2,inf);
assert(available.Usable && available.ResultAvailableAtSample==now);
assert(owner.Events.NextSampleIndex==now,'Report queuing must not execute another physical clock.');
% A report producer must not consume a future completion merely because
% the measurement row was retained in a ledger ahead of its availability.
future=row; future.ResultAvailableAtSample=now+1;
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',dmrs,cfg,future),'sixgr:truth:CSIReportMeasurementNotAvailable');
bad=row; bad.Consumed=NaN;
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',dmrs,cfg,bad),'sixgr:truth:InvalidCSIRSProducerFlag');
bad=row; bad.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch+1;
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',dmrs,cfg,bad),'sixgr:truth:CSIReportMeasurementClockMismatch');
bad=row; bad.CQI=11;
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',dmrs,cfg,bad),'sixgr:truth:UnpublishedCSIReportMeasurement');
unpublished=state; unpublished.ReferenceSignalMeasurementTable.TargetId(:)=2;
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    unpublished,1,'DL',dmrs,cfg,row),'sixgr:truth:UnpublishedCSIReportMeasurement');
logsRoot=fullfile(root,'logs'); if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot); mkdir(folder);
writetable(before,fullfile(folder,'published_measurement.csv'));
writetable(report,fullfile(folder,'queued_report.csv'));
roundtrip=readtable(fullfile(folder,'queued_report.csv'),'TextType','string');
assert(roundtrip.MeasurementAvailableSlot==2 && roundtrip.MeasurementAvailableAtSample==now && ...
    roundtrip.MeasurementClockEpoch==owner.Physical.ConfigurationEpoch && ...
    roundtrip.MeasurementClockDomain=="shared_receiver_sample_clock/v1" && ...
    roundtrip.DueSlot==report.DueSlot && roundtrip.CQI==report.CQI);
save(fullfile(folder,'CSI_report_clock.mat'),'cfg','row','report','before','available');
fprintf('CSI_REPORT_PUBLICATION_CLOCK_PASS actual_clock=%g publication_rows=%d report_due=%g CSI_RF_executions=0 folder=%s\n', ...
    now,height(before),report.DueSlot,folder);
ok=true;
end
function state=noEvents(state,events,owner) %#ok<INUSD>
assert(isempty(events));
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
