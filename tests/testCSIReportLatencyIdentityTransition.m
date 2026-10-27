function ok=testCSIReportLatencyIdentityTransition(retainedRun)
% Declared clock/received-installation boundary; optional original-run replay.
setup6GRSimToolkit('Verbose',false);
if nargin>0
    report=sixgr.util.csvReadTable(fullfile(retainedRun,'control','csv','received_csi_reports.csv'),'TextType','string');
    measurement=sixgr.util.csvReadTable(fullfile(retainedRun,'air_interface','csv','csi_rs_trials.csv'),'TextType','string');
    transition=sixgr.report.loadCSIIdentityTransitions(retainedRun);
    before={report,measurement};
    old=sixgr.report.collectCSIReportLatency(report,measurement);
    fresh=sixgr.report.collectCSIReportLatency(report,measurement,transition);
    assert(height(fresh)==1 && ~old.LatencyAvailable && fresh.LatencyAvailable && ...
        fresh.MeasurementSourceSlot==36 && fresh.DueSlot==49 && ...
        fresh.MeasurementOriginalRNTI==1 && fresh.RNTI==4660 && fresh.IdentityTransitionUsed && ...
        fresh.IdentityTransitionInstalledSlot==40 && isequaln(before,{report,measurement}));
    fprintf('RETAINED_CSI_TRANSITION_LATENCY_PASS measurement36_RNTI1 installation40 report49_RNTI4660 ms=%g\n', ...
        fresh.MeasurementEndToDelivery_ms);
    ok=true; return;
end
root=tempname; mkdir(root); mkdir(fullfile(root,'meta'));
identity=struct('RunID',"run",'ExecutionID',"execution",'ConfigHash',"config");
sixgr.util.jsonWrite(fullfile(root,'meta','execution_identity.json'),identity);
i=struct('UEIndex',1,'ServingCell',1,'RNTI',4660,'ConfiguredRNTI',1, ...
    'Msg4CanonicalSlot',38,'Source',"decoded_msg4_payload_after_contention_match", ...
    'EncodingProfile',"legacy_bounded_not_NR_MAC_RRC",'MACRRCStandardsQualified',false);
i.EvidenceSHA256=sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(i),'UTF-8')));
i.InstalledAtCanonicalSlot=40;
a=struct('UEIndex',1,'ServingCell',1,'FinalCRNTI',4660,'TemporaryCRNTI',4660, ...
    'FinalCRNTISource',i.Source,'FinalCRNTIEncodingProfile',i.EncodingProfile, ...
    'RASlotTimeBase',"absolute_zero_based",'Msg4ScheduledSlot',37,'RequireRRCSetupComplete',false);
for f=["RACompleted","RAPIDMatches","Msg2DCICrcPass","Msg2PDSCHCrcPass", ...
        "RARULGrantValid","Msg3PUSCHCrcPass","Msg4PDCCHCrcPass","Msg4PDSCHCrcPass","ContentionIdentityMatches"]
    a.(f)=1;
end
for f=string(fieldnames(identity)).', a.(f)=identity.(f); end
t=sixgr.report.loadCSIIdentityTransitions(root,struct2table(i),struct2table(a));
ue=struct('Direction',"DL",'UEIndex',1,'RNTI',4660,'ServingCell',1, ...
    'SourceSlot',36,'MeasurementAvailableSlot',37,'DueSlot',49,'CSIReferenceSlot',39, ...
    'SourceSignal',"CSI-RS",'ReportIdentity',"report49",'CSIReportConfigID',"report", ...
    'CSIConfigurationEpoch',0,'MeasurementAvailableAtSample',553268,'MeasurementClockEpoch',1, ...
    'CSIMeasurementID',"original36",'CSIMeasurementDigest',"original_digest", ...
    'MeasurementClockDomain',"shared_receiver_sample_clock/v1");
r=ue; r.SourceSlot=39; r.SourceSlotAuthority="configured_CSI_reference_resource_not_UE_measurement_slot";
r.UEReferenceRecordJSON=string(jsonencode(ue)); r.CSIUCIDecodeOk=true;
r.DeliveryStatus="delivered_to_runtime_scheduler";r.DeliveredSlot=49;r.CSIUCIChannel="PUCCH";
r.ObservationID="rx49";r.AvailableAtSample=752582;r.ReceiverClockEpoch=1;
r.ReceiverClockDomain="shared_receiver_sample_clock/v1";
r.ObservationStartSample=736572;r.ObservationEndSampleExclusive=752582;r.ObservationSampleRateHz=30720000;
m=struct('Slot',36,'UEIndex',1,'RNTI',1,'ServingCell',1,'CellID',1, ...
    'ObservationStartSample',537600,'ObservationEndSampleExclusive',553268, ...
    'ResultAvailableAtSample',553268,'ObservationSampleRateHz',30720000, ...
    'MeasurementClockEpoch',1,'MeasurementClockDomain',"shared_receiver_sample_clock/v1", ...
    'CSIReportConfigID',"report",'CSIConfigurationEpoch',0,'CSIMeasurementID',"original36", ...
    'CSIMeasurementDigest',"original_digest",'DeliverySlotStartSample',552960, ...
    'DeliverySlotEndSampleExclusive',568320);
for f=string(fieldnames(identity)).',r.(f)=identity.(f);m.(f)=identity.(f);end
r=struct2table(r);m=struct2table(m);before={r,m};
assert(~sixgr.report.collectCSIReportLatency(r,m).LatencyAvailable);
out=sixgr.report.collectCSIReportLatency(r,m,t);
assert(out.LatencyAvailable&&out.IdentityTransitionUsed&&out.MeasurementOriginalRNTI==1 && ...
    abs(out.MeasurementEndToDelivery_ms-(752582-553268)/30720)<1e-12&&isequaln(before,{r,m}));
bad=t;bad.ExecutionID="wrong";assert(~sixgr.report.collectCSIReportLatency(r,m,bad).LatencyAvailable);
bad=t;bad.InstalledAtCanonicalSlot=50;assert(~sixgr.report.collectCSIReportLatency(r,m,bad).LatencyAvailable);
bad=t;bad.ServingCell=2;assert(~sixgr.report.collectCSIReportLatency(r,m,bad).LatencyAvailable);
bad=a;bad.Msg4PDSCHCrcPass=0;
try
    sixgr.report.loadCSIIdentityTransitions(root,struct2table(i),struct2table(bad));
catch e
    assert(string(e.identifier)=="sixgr:report:CSIIdentityTransitionScope");ok=true;return;
end
error('sixgr:test:ExpectedRejection','Failed received Msg4 cannot install identity.');
end
