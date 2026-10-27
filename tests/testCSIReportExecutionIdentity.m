function ok=testCSIReportExecutionIdentity()
% Original producer lifecycle -> real queue/delivery reducers. No RF or
% decoded-CSI qualification: receiver rows below are declared component data.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.run.runTag='declared_csi_identity_run';
cfg.run.executionID='declared_csi_identity_execution';
cfg.run.scenarioID='declared_csi_identity_scenario';
cfg.meta.configHash=repmat('a',1,64);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',701, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),4);
state.CurrentServingIdx(:)=1;
state.BeamManagementRuntimeEnabled=false;
state.CSIFeedbackSlots=1;
state.CurrentSlot=10; state.CurrentCanonicalSlot=10;
row=table(10,9,1,0,true,'VariableNames', ...
    {'Slot','WidebandCQI','Layers','PMI','CRCPass'});
row.ULSpatialMeasurementEvidenceJSON=string(jsonencode(struct( ...
    'ChannelEstimateDomain',"pusch_dmrs_effective_layer_domain",'RI',1, ...
    'RISource',"ul_pusch_dmrs_effective_layer_rank_descriptor_not_srs_ri", ...
    'SRSRITPMIValid',false)));
original=row;
pending=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'UL',row,cfg,table());
assert(height(pending.PendingCSITable)==1 && ~pending.PendingCSITable.Processed(1));
assert(isnan(pending.PendingCSITable.DeliveredSlot(1)) && ...
    pending.PendingCSITable.DueSlot(1)==11 && isequaln(row,original));
checkIdentity(pending.PendingCSITable,cfg);
first=pending.PendingCSITable;

% A later append must have the same lifecycle before any exporter runs.
% The earlier pending record and its unavailable delivery time stay intact.
delivered=pending; delivered.CurrentSlot=12; delivered.CurrentCanonicalSlot=12;
row.Slot=11;
delivered=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    delivered,1,'UL',row,cfg,table());
assert(height(delivered.PendingCSITable)==2 && ...
    isequaln(delivered.PendingCSITable(1,first.Properties.VariableNames),first));
assert(delivered.PendingCSITable.Processed(2) && delivered.PendingCSITable.DeliveredSlot(2)==12);
checkIdentity(delivered.PendingCSITable,cfg);
path=string(tempname)+".csv";
sixgr.util.csvWriteTable(path,delivered.PendingCSITable,'PreserveSchema',true,'RoundTripNumericText',true);
roundtrip=sixgr.util.csvReadTable(path,'TextType','string');
checkIdentity(roundtrip,cfg);
assert(height(roundtrip)==2 && isnan(roundtrip.DeliveredSlot(1)) && roundtrip.DeliveredSlot(2)==12);

% Declared independently-decoded DL boundary: existing measured data/clock
% fields are not manufactured by binding lifecycle or by scheduler receipt.
report=table2struct(first);
report.Direction="DL"; report.SourceSignal="received_CSI_UCI";
report.CSIUCIDecodeOk=true; report.CSIUCITransport="declared_decoded_report_boundary";
report.CSIUCIChannel="PUCCH"; report.ReportIdentity="declared_received_csi_identity";
report.SourceSlot=10; report.DueSlot=11; report.DeliveredSlot=NaN;
report.RI=1; report.PMI=0; report.CRI=0;
report.SINR_dB=NaN; report.CRCPass=NaN;
report.SINRSource="not_reported_in_CSI_payload";
report.SINRValueRole="unavailable_not_a_received_SINR_measurement";
report.SINRValueStatus="NA_not_reported";
receiver=state; receiver.CurrentSlot=11; receiver.CurrentCanonicalSlot=11;
[~,received]=sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(receiver,report);
checkIdentity(struct2table(received,'AsArray',true),cfg);
assert(received.DeliveredSlot==11 && isnan(received.SINR_dB) && isnan(received.CRCPass));

for field=["ScenarioID","ConfigHash","RunID","ExecutionID"]
    wrong=row; wrong.(field)="different_original_identity";
    reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
        state,1,'UL',wrong,cfg,table()));
    wrongReport=report; wrongReport.(field)="different_original_identity";
    reject(@()sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(receiver,wrongReport));
end
wrongCfg=cfg; wrongCfg.run.executionID='other_execution';
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'UL',row,wrongCfg,table()));
partialCfg=struct('run',struct('runTag','other_partial_run'));
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'UL',row,partialCfg,table()));
wrongMeasurement=table("other_execution",'VariableNames',{'ExecutionID'});
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',row,cfg,wrongMeasurement));

% A low-level component has no complete runner lifecycle. It must stay
% unbound, even though it has finite authored quality and a source slot.
componentCfg=cfg; componentCfg.run.runTag=''; componentCfg.run.executionID='';
componentCfg.run.scenarioID=''; componentCfg.meta.configHash='';
component=state; component.CfgMobility=componentCfg;
component.PendingCSITable=first([],:);
component=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    component,1,'UL',original,componentCfg,table());
for field=["ScenarioID","ConfigHash","RunID","ExecutionID"]
    assert(strlength(string(component.PendingCSITable.(field)(1)))==0);
end
ok=true;
fprintf('CSI_REPORT_EXECUTION_IDENTITY_PASS pending_and_delivered=1 cross_run_rejected=1 RF_executions=0 csv=%s\n',path);
end

function checkIdentity(T,cfg)
assert(all(string(T.ScenarioID)==string(cfg.run.scenarioID)) && ...
    all(string(T.ConfigHash)==string(cfg.meta.configHash)) && ...
    all(string(T.RunID)==string(cfg.run.runTag)) && ...
    all(string(T.ExecutionID)==string(cfg.run.executionID)));
end

function reject(action)
try
    action();
catch cause
    assert(string(cause.identifier)=="sixgr:truth:CoupledControlIdentityMismatch", ...
        'Unexpected rejection %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingCSIExecutionGuard','Conflicting CSI execution identity was accepted.');
end
