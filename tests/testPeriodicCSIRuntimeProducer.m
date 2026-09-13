function ok=testPeriodicCSIRuntimeProducer()
% Normal slot-entry producer with declared receiver inputs, no RF claim.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmpi(which('sixgr.truth.CoupledTruthRuntime'), ...
    fullfile(root,'+sixgr','+truth','CoupledTruthRuntime.m')));
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),58);
state.CurrentServingIdx(:)=1;
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,2,58,12);
assert(isempty(state.PendingCSITable),'No measurement means no invented CSI payload.');
assert(height(state.CSIReportObligationTable)==11 && all(state.CSIReportObligationTable.ULResourceAvailable));
measurement=table(1,true,true,true,true,true,true,10,1,0,0,0,18.5, ...
    "declared_received_CSI_calendar_fixture", ...
    'VariableNames',{'Slot','Transmitted','Observed','Consumed', ...
    'ResourceExtractionAvailable','ChannelEstimateAvailable','CSIMeasurementAvailable', ...
    'CQI','RI','PMI','CRI','LI','SINR_dB','MeasurementSource'});
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,measurement);
state.CSIFeedbackSlots=90; % Deliberate competing AMC delay, not report timing.
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,5,58,12);
report=state.PendingCSITable;
assert(height(report)==1 && report.DueSlot==9 && report.SourceSlot==1 && report.CQI==10);
assert(report.CSIReferenceSlot==4 && startsWith(string(report.ReportIdentity),"periodic_csi_"));
assert(report.SourceSignal=="CSI-RS" && isnan(report.CRCPass));
assert(isempty(state.PUCCHGrantTraceTable),'This slot-only producer test must not claim RF grants or reception.');
unchanged=sixgr.truth.CoupledTruthRuntime.refreshPeriodicCSIReportsRuntime(state);
assert(isequaln(unchanged.PendingCSITable,state.PendingCSITable),'A slot callback cannot duplicate a report.');
% A new eligible measurement refreshes the payload, not the receiver's
% configuration/occasion identity. No PDSCH or source-slot period is involved.
newer=measurement; newer.Slot=3; newer.CQI=11;
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,newer);
state=sixgr.truth.CoupledTruthRuntime.refreshPeriodicCSIReportsRuntime(state);
assert(height(state.PendingCSITable)==1 && state.PendingCSITable.SourceSlot==3 && ...
    state.PendingCSITable.CQI==11 && state.PendingCSITable.ReportIdentity==report.ReportIdentity);
% The reference resource for report slot 9 remains special DL/UL slot 4. A later
% measurement must not leak into this earlier reporting reference.
tooNew=measurement; tooNew.Slot=8; tooNew.CQI=12;
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,8,58,12);
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,tooNew);
state=sixgr.truth.CoupledTruthRuntime.refreshPeriodicCSIReportsRuntime(state);
assert(height(state.PendingCSITable)==1 && state.PendingCSITable.SourceSlot==3 && state.PendingCSITable.CQI==11);
% Retain this unexecuted component obligation as censored, not decoded.
% The next report is generated with no additional PDSCH execution.
state.PendingCSITable.RightCensored(:)=true;
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,10,58,12);
assert(height(state.PendingCSITable)==2 && state.PendingCSITable.DueSlot(end)==14 && ...
    state.PendingCSITable.SourceSlot(end)==8 && state.PendingCSITable.CQI(end)==12);
assert(~state.PendingCSITable.CSIUCIDecodeOk(end) && ~state.PendingCSITable.Processed(end));
% Gap exclusion applies to the reference resource, never by moving UL CSI
% to an arbitrary adjacent slot. Historical unavailable report slots stay.
gapped=cfg; gapped.phy.rsla.measurement_gaps=struct( ...
    'enabled',true,'period_slots',10,'offset_slots',3,'length_slots',1);
assert(sixgr.truth.periodicCSIReferenceSlot(gapped,9)==3);
assert(sixgr.truth.isCSIReportingMeasurementGap(gapped,4) && ...
    ~sixgr.truth.isCSIReportingMeasurementGap(gapped,3));
invalid=state; invalid.CfgMobility.phy.csi.reportOffsetSlots=1;
invalid.PendingCSITable=invalid.PendingCSITable([],:);
invalid.CSIReportObligationTable=table();
invalid=sixgr.truth.CoupledTruthRuntime.refreshPeriodicCSIReportsRuntime(invalid);
assert(isempty(invalid.PendingCSITable) && height(invalid.CSIReportObligationTable)==12 && ...
    ~any(invalid.CSIReportObligationTable.ULResourceAvailable));
logsRoot=fullfile(root,'logs'); if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot); mkdir(folder);
writetable(state.PendingCSITable,fullfile(folder,'queued_periodic_CSI.csv'));
writetable(state.CSIReportObligationTable,fullfile(folder,'configured_CSI_obligations.csv'));
roundtrip=readtable(fullfile(folder,'queued_periodic_CSI.csv'),'TextType','string');
assert(isequal(roundtrip.DueSlot,[9;14]) && isequal(roundtrip.SourceSlot,[3;8]));
save(fullfile(folder,'periodic_producer.mat'),'cfg','measurement','newer','tooNew','report','roundtrip');
fprintf('PERIODIC_CSI_RUNTIME_PRODUCER_PASS report_slots=9,14 sources=3,8 AMC_delay_ignored=90 PDSCH_executions=0 CSI_RF_executions=0 folder=%s\n',folder);
ok=true;
end
