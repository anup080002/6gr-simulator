function [calendar,contexts]=buildPeriodicCSIReportObligations(cfg,ue,firstSlot,lastSlot)
% Payload-free configured report obligations, NOT transmitted/received rows.
% This separates the report calendar from measurement availability. A row
% with unavailable UL symbols remains on its nominal slot; it is not moved.
% Independent HARQ/SR multiplexing and event-clock installation are separate.
arguments
    cfg (1,1) struct
    ue (1,1) struct
    firstSlot (1,1) double
    lastSlot (1,1) double
end
names=["UEID","RNTI","ServingCell","PUCCHCell","ComponentCarrier","ActiveULBWP"];
assert(all(isfield(ue,names)) && isempty(setdiff(string(fieldnames(ue)),names)), ...
    'sixgr:truth:InvalidCSIReportingIdentity','Only installed UE/cell/carrier/BWP identity belongs in a report obligation.');
for name=names
    x=ue.(name);
    assert(isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && x==fix(x) && x>=0 && x<=flintmax, ...
        'sixgr:truth:InvalidCSIReportingIdentity','Invalid configured identity field %s.',name);
end
assert(ue.UEID>=1 && ue.RNTI>=1 && ue.RNTI<=65535 && ue.ServingCell>=1 && ue.PUCCHCell>=1, ...
    'sixgr:truth:InvalidCSIReportingIdentity','UE, RNTI and serving/control cell identities must be positive.');
frameIdentity=sixgr.util.structGet(cfg,'phy.frame.DefaultIdentity',struct());
assert(isequal(ue.ComponentCarrier,sixgr.util.structGet(frameIdentity,'ScheduledCCID',NaN)) && ...
    isequal(ue.ActiveULBWP,sixgr.util.structGet(frameIdentity,'ULBWPID',NaN)), ...
    'sixgr:truth:CSIReportingCalendarBWPMismatch', ...
    'Resolve the report UL carrier/BWP before applying its slot period; do not attach another BWP identity to this calendar.');
enabled=sixgr.util.structGet(cfg,'phy.csi.reportCSI',[]);
assert(isscalar(enabled) && (islogical(enabled)||isnumeric(enabled)) && isreal(enabled) && enabled==1 && ...
    isequal(string(sixgr.util.structGet(cfg,'phy.csi.reportTrigger',"")),"periodic"), ...
    'sixgr:truth:PeriodicCSIConfigurationRequired','This calendar requires enabled periodic CSI, not an inferred dynamic activation.');
period=sixgr.util.structGet(cfg,'phy.csi.reportPeriodicitySlots',NaN);
offset=sixgr.util.structGet(cfg,'phy.csi.reportOffsetSlots',NaN);
sixgr.truth.periodicCSIReportSlotMask([firstSlot,lastSlot],period,offset);
assert(lastSlot>=firstSlot,'sixgr:truth:InvalidCSIReportSlot','The report calendar interval must be ordered.');
slots=(firstSlot:lastSlot).';
slots=slots(sixgr.truth.periodicCSIReportSlotMask(slots,period,offset));
request=sixgr.util.structGet(cfg,'phy.csi.reportConfiguration',struct());
epoch=sixgr.util.structGet(cfg,'phy.csi.reportConfigurationEpoch',NaN);
report=sixgr.phy.mimo.CSIReportConfiguration(request,epoch);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
ids=rrc.Data.CSIResources;
assert(isnumeric(ids) && isscalar(ids) && isfinite(ids) && ids>=0 && ids==fix(ids), ...
    'sixgr:truth:UnresolvedCSIReportingResource','This single-report/BWP calendar needs one installed CSI PUCCH resource; do not select the first of an unresolved list.');
resource=rrc.resourceByID(ids);
carrier=sixgr.phy.grid.makeCarrier(cfg);
identity=struct('UE',ue,'CSIReportConfigID',report.ReportConfigID, ...
    'CSIConfigurationEpoch',report.Epoch,'PUCCHConfigurationDigest',rrc.Digest, ...
    'ReportPeriodSlots',period,'ReportOffsetSlots',offset, ...
    'SubcarrierSpacing_kHz',carrier.SubcarrierSpacing,'CyclicPrefix',string(carrier.CyclicPrefix));
prefix="periodic_csi_"+sixgr.phy.pucch.PUCCHUtil.hash(identity);
row=struct('ObligationID',"",'UEIndex',ue.UEID,'RNTI',ue.RNTI,'ServingCell',ue.ServingCell, ...
    'ComponentCarrier',ue.ComponentCarrier,'ActiveULBWP',ue.ActiveULBWP, ...
    'CSIReportConfigID',report.ReportConfigID,'CSIConfigurationEpoch',report.Epoch, ...
    'PUCCHConfigurationEpoch',rrc.ConfigurationEpoch,'ReportSlot',NaN,'CSIReferenceSlot',NaN, ...
    'ReportPeriodSlots',period,'ReportOffsetSlots',offset, ...
    'ReportSubcarrierSpacing_kHz',carrier.SubcarrierSpacing,'PUCCHResourceID',resource.ID, ...
    'StartSymbol',resource.Data.StartSymbol,'NumSymbols',resource.Data.NumSymbols, ...
    'ULResourceAvailable',false,'ResourceBlocker',"",'ReceiverContextDigest',"", ...
    'EvidenceClass',"configured_report_obligation_not_RF_execution");
rows=repmat(row,numel(slots),1); contexts=cell(numel(slots),1);
for k=1:numel(slots)
    slot=slots(k); id=prefix+"_slot_"+slot;
    context=sixgr.truth.buildConfiguredPUCCHReceiveContext(struct( ...
        'ObservationID',id,'ConfigurationEpoch',rrc.ConfigurationEpoch, ...
        'HARQBitCount',0,'SRBitCount',0,'PriorityIndex',0, ...
        'CSIReportConfigID',report.ReportConfigID,'CSIConfigurationEpoch',report.Epoch),report);
    [~,allowUL,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    ul=partition.ULSymbolAllocation;
    fits=allowUL && resource.Data.StartSymbol>=ul(1) && ...
        resource.Data.StartSymbol+resource.Data.NumSymbols<=sum(ul);
    rows(k).ObligationID=id; rows(k).ReportSlot=slot;
    rows(k).CSIReferenceSlot=sixgr.truth.periodicCSIReferenceSlot(cfg,slot);
    rows(k).ULResourceAvailable=logical(fits);
    if ~fits, rows(k).ResourceBlocker="configured_CSI_symbols_not_UL_on_nominal_report_slot"; end
    if sixgr.truth.isCSIReportingMeasurementGap(cfg,slot)
        rows(k).ULResourceAvailable=false;
        rows(k).ResourceBlocker="configured_measurement_gap_on_nominal_report_slot";
    end
    rows(k).ReceiverContextDigest=context.Digest;
    contexts{k}=context;
end
calendar=struct2table(rows,'AsArray',true);
end
