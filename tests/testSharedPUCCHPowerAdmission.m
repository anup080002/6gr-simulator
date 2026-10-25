function ok=testSharedPUCCHPowerAdmission()
% Declared received-reference/connected boundaries; actual public preparation
% and typed receiver binding, with no RF/channel execution or UCI reception.
% Mixed HARQ/CSI reducer inputs below are explicitly declared scheduled work,
% not decoded DCI or PDSCH outcomes. Actual receive-only completion is separate.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
% This test deliberately exercises finite-age research admission, not the
% selected scenario's retained-filter lifecycle (covered separately).
s=s.toStruct();
assert(string(s.rf_frontend.ul_power_control.pathloss_reference_lifetime)=="retained_filtered_reference");
s.rf_frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
folder=fullfile(pwd,'results','validation','shared_pucch_power_admission',char(java.util.UUID.randomUUID()));
mkdir(folder); cfg=sixgr.lls6g.buildInternalConfig(s,folder); cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),0);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,1,0);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,cfg.run.totalSlots,0);
state.CurrentServingIdx(:)=1;
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
decoded=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),decoded);
common=installed.UECommonCellConfiguration;
common.ServingCell=1; common.AvailableSlot=1; common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
state.UECommonCellConfigurationByUE={common};
fresh=publish(state,1,1); groups=0;
for condition=["missing","missing_sib1","future_sib1","future_rsrp","wrong_beam","stale"]
    v=fresh; target=5;
    switch condition
        case "missing", v=state;
        case "missing_sib1", v.UECommonCellConfigurationByUE={struct()};
        case "future_sib1", v.UECommonCellConfigurationByUE{1}.AvailableSlot=6;
        case "future_rsrp", v.ReferenceSignalMeasurementTable.AvailableSlot(:)=6;
        case "wrong_beam", v.ReferenceSignalMeasurementTable.ResourceId(:)=1;
        case "stale", target=25;
    end
    v.CurrentSlot=target;
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
    original=v; random=rng;
    [admit,bound,row]=sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bound,1,target);
    assert(~admit && ~row.PreparationAdmitted && row.MeasuredPowerReferenceRequired && ...
        row.Action=="defer_PUCCH_unavailable_measured_power_reference" && ...
        row.PowerReferenceRS=="SSB-0" && row.DecisionSlot==target && ...
        isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB) && ...
        isequaln(v,original) && isequal(random,rng));
    if condition=="stale", assert(row.PowerReferenceStatus=="stale"); end
end
groups=groups+1;
v=fresh; v.CurrentSlot=25; v=publish(v,24,24);
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
[admit,rebound,row]=sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bound,1,25);
assert(admit && row.PowerReferenceProducerSlot==24 && row.PowerReferenceAvailableSlot==24 && ...
    row.MaximumPowerReferenceAgeSlots==20 && ...
    rebound.lls6g.userContext.RuntimeServingPathloss_dB==common.SSPBCHBlockPower_dBm+90);
v.RuntimeViewMode="future_ul_grant_planning"; v.PlanningDecisionSlot=23;
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
[admit,~,row]=sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bound,1,25);
assert(~admit && row.DecisionSlot==23 && row.PUCCHResourceSlot==25);
groups=groups+1;

v=state; [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
bad=bound; bad.lls6g.userContext.RuntimeServingCell=2;
reject(@()sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bad,1,1),'sixgr:truth:PUCCHPowerAdmissionIdentity');
bad=bound; bad.lls6g.userContext.RuntimeCurrentDirection='DL';
reject(@()sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bad,1,1),'sixgr:truth:PUCCHPowerAdmissionIdentity');
bad=bound; bad.validation.pucch_resources.power_control.require_measured_reference_rs='1';
reject(@()sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bad,1,1),'sixgr:truth:PUCCHPowerAdmissionConfiguration');
bad=bound; bad.validation.pucch_resources.spatial_relations.reference_signal_type='CSI-RS';
reject(@()sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bad,1,1),'sixgr:truth:PUCCHPowerAdmissionConfiguration');
bad=bound; bad.validation.pucch_resources.power_control.pathloss_reference_rs_id=99;
reject(@()sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bad,1,1),'sixgr:truth:PUCCHPowerAdmissionConfiguration');
bad=bound; bad.validation.pucch_resources.power_control.require_measured_reference_rs=false;
[admit,~,row]=sixgr.truth.resolveSharedPUCCHPowerAdmission(v,bad,1,1);
assert(admit && ~row.MeasuredPowerReferenceRequired);
groups=groups+1;

% Install a real shared owner at sample zero, but do not execute it. The
% connected/access/TAG boundary remains explicitly declared, not received.
state.AccessState(1)="succeeded"; state.LastSuccessfulPRACHSlotByUE(1)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
state.ConnectedULTimingByUE={struct('DLReference',struct( ...
    'Source',"received_SSB_timing_and_decoded_BCH",'NCellID',carrier.NCellID, ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',0,'AvailableAtSample',0), ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.03*fs))};
id=cfg.phy.frame.DefaultIdentity; rnti=sixgr.truth.CoupledRadioIdentity.resolve(state,1);
ue=struct('UEID',1,'RNTI',rnti,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
calendar=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,2,10);
calendar=calendar(calendar.ULResourceAvailable,:); assert(height(calendar)>=2);
slot=calendar.Slot(1);
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
bound=sixgr.phy.grid.applyRuntimeCarrierTimeline(bound,slot);
h=sixgr.truth.buildConfiguredPUCCHReception(state,bound,1,slot,"declared_SR_preparation");
assert(isempty(h.CSIReportConfiguration) && h.Context.SRBits==1);
sr=state.UEConfiguredSRProcedures{1,1}; assert(isscalar(sr));
d=sr.Data; d.PendingPositiveSR=false;
state.UEConfiguredSRProcedures{1,1}=sixgr.phy.pucch.SchedulingRequestState(d);
original=state; random=rng;
[prepared,admission]=sixgr.truth.prepareConfiguredSRTransmission(state,bound,h);
assert(isempty(prepared) && isempty(admission) && isequaln(state,original) && isequal(random,rng));
d.PendingPositiveSR=true; state.UEConfiguredSRProcedures{1,1}=sixgr.phy.pucch.SchedulingRequestState(d);
beforeSR=state.UEConfiguredSRProcedures; beforeControl=state.ControlTrials;
[prepared,admission]=sixgr.truth.prepareConfiguredSRTransmission(state,bound,h);
assert(isempty(prepared) && height(admission)==1 && ~admission.PreparationAdmitted && ...
    isequaln(beforeSR,state.UEConfiguredSRProcedures) && isequaln(beforeControl,state.ControlTrials));
key=occasion(slot,ue); arm(owner,bound,slot,key);
item=owner.Pending(end); item.Kind="PreparePUCCH";
h=sixgr.truth.buildConfiguredPUCCHReception(state,bound,1,slot,item.Context.ObservationID);
originalPlanes=owner.Pending(end).Planes; execution=owner.Events.ExecutionTrace;
random=rng; state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
assert(owner.Pending(end).Kind=="PUCCHReceiveOnly" && ...
    owner.Pending(end).Context.GNBReception.Context.Digest==h.Context.Digest && ...
    isequaln(owner.Pending(end).Planes,originalPlanes) && isempty(owner.PUCCHTransmissions) && ...
    owner.Events.NextSampleIndex==0 && isequaln(owner.Events.ExecutionTrace,execution) && ...
    isequaln(state.ControlTrials,beforeControl) && isequaln(state.UEConfiguredSRProcedures,beforeSR) && ...
    isequal(random,rng));
assert(height(state.SharedPUCCHPowerAdmissionTable)==1 && ...
    state.SharedPUCCHPowerAdmissionTable.PUCCHGrantIDsJSON=="[]");
groups=groups+1;

% Declared mixed HARQ+CSI reducer contract on a second real armed capture.
% Typed length/resource schema has no payload oracle. No scheduled DL TX or
% actual HARQ receiver completion is claimed by this reducer-only case.
slot=calendar.Slot(2); key=occasion(slot,ue);
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
bound=sixgr.phy.grid.applyRuntimeCarrierTimeline(bound,slot); arm(owner,bound,slot,key);
item=owner.Pending(end); item.Kind="PreparePUCCH"; obs=item.Context.ObservationID;
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bound,ue);
wire=sixgr.phy.mimo.CSIReportConfiguration(cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
context=sixgr.truth.buildConfiguredPUCCHReceiveContext(struct('ObservationID',obs, ...
    'ConfigurationEpoch',rrc.ConfigurationEpoch,'HARQBitCount',1,'SRBitCount',0, ...
    'PriorityIndex',0,'CSIReportConfigID',wire.ReportConfigID,'CSIConfigurationEpoch',wire.Epoch),wire);
resourceID=sixgr.phy.pucch.resolveConfiguredCSIResourceID(bound.validation.pucch_resources.csi_resource_ids);
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct('ObservationID',obs, ...
    'ResourceID',resourceID,'RNTI',rnti,'AbsoluteSlot0',slot-1, ...
    'Source',"declared_gNB_length_schema_reducer_fixture_not_received_DCI", ...
    'TimingSource',"received_PUCCH_DMRS",'ResourceSelectionProcedure',"dynamic_harq_csi"),rrc,context);
h=struct('SelectedTransport',"PUCCH",'Mapping',struct([]),'UEIndex',1,'TargetSlot',slot, ...
    'Assignment',assignment,'Context',context,'CSIReportConfiguration',wire);
grant=struct('PUCCHGrantId',"declared_HARQ",'UEIndex',1,'RNTI',rnti,'ServingCell',1, ...
    'BaseStationID',1,'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID, ...
    'Slot',slot,'ScheduledAbsoluteSlot',slot,'FeedbackForDirection',"DL", ...
    'GrantScheduledFlag',true,'GrantExecutedFlag',false,'MultiplexedOnPUSCH',false);
rows=struct2table([grant;grant]); rows.PUCCHGrantId(2)="PUCCH-CSI-declared_CSI";
state.PUCCHGrantTraceTable=rows;
state.PendingFeedbackTable=table("declared_HARQ",false,true, ...
    'VariableNames',{'PUCCHGrantId','Processed','Ack'});
state.PendingCSITable=table("declared_CSI",1,slot,false,"pucch",false,false,NaN,"0101", ...
    'VariableNames',{'ReportIdentity','UEIndex','DueSlot','Processed','CSIUCITransport', ...
    'UECSIPayloadRetired','CSIUCIDecodeOk','DeliveredSlot','CSIPart1BitsToken'});
[admit,bound,admission]=sixgr.truth.resolveSharedPUCCHPowerAdmission(state,bound,1,slot); assert(~admit);
snapshot=state; armed=owner.Pending; random=rng;
bad=admission; bad.PowerReferenceStatus="stale";
reject(@()sixgr.truth.CoupledTruthRuntime.deferSharedPUCCHPowerRuntime( ...
    state,item,bound,h,rows,bad),'sixgr:truth:PUCCHPowerAdmissionBinding');
badRows=rows; badRows.RNTI(1)=rnti+1;
reject(@()sixgr.truth.CoupledTruthRuntime.deferSharedPUCCHPowerRuntime( ...
    state,item,bound,h,badRows,admission),'sixgr:truth:PUCCHPowerAdmissionBinding');
assert(isequaln(owner.Pending,armed) && isequaln(state,snapshot) && isequal(random,rng));
state=sixgr.truth.CoupledTruthRuntime.deferSharedPUCCHPowerRuntime(state,item,bound,h,rows,admission);
assert(all(state.PUCCHGrantTraceTable.UETransmissionSuppressed) && ...
    ~any(state.PUCCHGrantTraceTable.GrantExecutedFlag) && ...
    all(state.PUCCHGrantTraceTable.PowerAdmissionObservationID==obs) && ...
    all(state.PendingFeedbackTable.Processed) && state.PendingFeedbackTable.Ack && ...
    state.PendingCSITable.Processed && ~state.PendingCSITable.UECSIPayloadRetired && ...
    ~state.PendingCSITable.CSIUCIDecodeOk && isnan(state.PendingCSITable.DeliveredSlot) && ...
    state.PendingCSITable.CSIPart1BitsToken=="0101" && ...
    owner.Pending(end).Context.GNBReception.Context.Digest==context.Digest && ...
    owner.Pending(end).Context.GNBReception.Assignment.Digest==assignment.Digest);
changed={'PUCCHGrantTraceTable','PendingFeedbackTable','PendingCSITable','SharedPUCCHPowerAdmissionTable'};
assert(isequaln(rmfield(state,changed),rmfield(snapshot,changed)) && ...
    isequaln(state.LatestDLFeedback,snapshot.LatestDLFeedback) && ...
    isequaln(owner.Events.ExecutionTrace,execution) && owner.Events.NextSampleIndex==0 && ...
    isempty(owner.PUCCHTransmissions) && isequal(random,rng));
% UE work is terminal, but without actual receiver evidence the independent
% physical grant disposition must remain unresolved, never successful.
disposition=sixgr.truth.classifyPUCCHGrantDisposition(state.PUCCHGrantTraceTable,table());
assert(disposition.UnresolvedCount==2 && disposition.StandaloneTrialCount==0 && ...
    disposition.ReceiverOnlyObservedCount==0);
groups=groups+1;
scope=struct('DeclaredAcquisitionAndReferenceInputs',true,'OriginalArmedCaptures',2, ...
    'RFExecutions',0,'ChannelExecutions',0,'PUCCHReceiverExecutions',0, ...
    'ActualHARQCompletionQualified',false,'FullScenarioQualified',false);
path=sixgr.truth.exportPUCCHPowerAdmissionDiagnostics(state,folder);
assert(isfile(path)); audit=state.SharedPUCCHPowerAdmissionTable;
save(fullfile(folder,'preparation_evidence.mat'),'scope','audit','cfg');
fprintf('SHARED_PUCCH_POWER_ADMISSION_PASS groups=%d original_armed=2 TX=0 RX=0 folder=%s\n',groups,folder);
ok=true;
end

function key=occasion(slot,ue)
row=struct('ScheduledAbsoluteSlot',slot,'FeedbackForDirection',"DL", ...
    'UEIndex',ue.UEID,'RNTI',ue.RNTI,'ServingCell',ue.ServingCell, ...
    'ComponentCarrier',ue.ComponentCarrier,'ActiveULBWP',ue.ActiveULBWP);
key=sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey(row);
end

function arm(owner,cfg,slot,key)
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
first=sixgr.phy.frame.slotStartSample(carrier,slot-1,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,slot,fs);
timing=sixgr.link.resolveConnectedULTransmissionTiming(cfg,first/fs,fs,stop-first);
owner.queuePUCCHPreparation(1,timing,cfg,struct('Slot',slot,'Key',key));
end

function state=publish(state,sourceSlot,availableSlot)
row=table(0,110,"SSB-0","declared_admission_diagnostic",1,-90,20, ...
    'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
    'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell', ...
    'SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,row,'ProducerSlot',sourceSlot,'AvailableSlot',availableSlot, ...
    'Valid',true,'Direction','DL','SourceSignal','SSB', ...
    'MeasurementSource','declared_admission_boundary_not_on_air');
end

function reject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:PUCCHAdmissionMissingGuard','Expected %s.',id);
end
