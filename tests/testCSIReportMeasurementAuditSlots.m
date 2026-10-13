function ok = testCSIReportMeasurementAuditSlots()
% Audit-only slot semantics. No UE state is injected into a gNB receiver.
reference = struct('Direction',"DL",'UEIndex',1,'RNTI',7, ...
    'SourceSlot',18,'MeasurementAvailableSlot',19,'DueSlot',24, ...
    'CSIReferenceSlot',19,'SourceSignal',"CSI-RS", ...
    'ReportIdentity',"periodic_report_24",'CSIReportConfigID',"report-0", ...
    'CSIConfigurationEpoch',2,'CQI',15,'RI',2,'PMI',18);
received = rmfield(reference,{'MeasurementAvailableSlot','SourceSignal'});
received.SourceSlot = 19;
received.SourceSlotAuthority = "configured_CSI_reference_resource_not_UE_measurement_slot";
received.UEReferenceRecordJSON = string(jsonencode(reference));
T = struct2table(received); before = T;
[slots,authority] = sixgr.report.csiReportMeasurementAuditSlots(T);
assert(slots==18 && startsWith(authority,"posthoc_") && isequaln(T,before));
% A corrupted/wrong decoded CQI must remain independently observable. This
% function links identities, never copies or selects by reported CSI values.
poison = T; poison.CQI=1; poison.RI=1; poison.PMI=3;
assert(sixgr.report.csiReportMeasurementAuditSlots(poison)==18);
assert(poison.CQI==1 && poison.RI==1 && poison.PMI==3);
for field = ["UEIndex","RNTI","CSIReferenceSlot","DueSlot","CSIConfigurationEpoch"]
    wrong = reference; wrong.(field)=wrong.(field)+1;
    poison=T; poison.UEReferenceRecordJSON=string(jsonencode(wrong));
    assert(isnan(sixgr.report.csiReportMeasurementAuditSlots(poison)));
end
for field = ["Direction","ReportIdentity","CSIReportConfigID"]
    wrong = reference; wrong.(field)="different";
    poison=T; poison.UEReferenceRecordJSON=string(jsonencode(wrong));
    assert(isnan(sixgr.report.csiReportMeasurementAuditSlots(poison)));
end
for invalid = [NaN Inf 0 -1 18.5 25]
    wrong=reference; wrong.SourceSlot=invalid;
    poison=T; poison.UEReferenceRecordJSON=string(jsonencode(wrong));
    assert(isnan(sixgr.report.csiReportMeasurementAuditSlots(poison)));
end
poison=removevars(T,'UEReferenceRecordJSON');
assert(isnan(sixgr.report.csiReportMeasurementAuditSlots(poison)));
poison=T; poison.UEReferenceRecordJSON="malformed";
assert(isnan(sixgr.report.csiReportMeasurementAuditSlots(poison)));
legacy=T; legacy.SourceSlotAuthority=""; legacy.SourceSlot=18;
assert(sixgr.report.csiReportMeasurementAuditSlots(legacy)==18);
% Exercise the actual bundle reporter: configured reference 19, measured 18.
T.CRI=0; T.Processed=true; T.DeliveredSlot=24;
T.DeliveryStatus="delivered_to_runtime_scheduler";
measured=table(18,1,7,15,2,18,0,'VariableNames', ...
    {'Slot','UEIndex','RNTI','CQI','RI','PMI','CRI'});
bound=sixgr.report.bindCSIReportMeasurementAudit(measured,T,"DL");
assert(bound.ReportSourceSlot==19 && bound.ReportMeasurementSourceSlot==18);
assert(bound.ReportCSIExactMatch && bound.ReportProcessed);
assert(bound.ReportBindingStatus=="exact_measured_csi_report_bound");
% Same slot/user but another RNTI is not the same measurement identity.
wrongIdentity=measured; wrongIdentity.RNTI=8;
unbound=sixgr.report.bindCSIReportMeasurementAudit(wrongIdentity,T,"DL");
assert(isnan(unbound.ReportMeasurementSourceSlot) && ~unbound.ReportCSIExactMatch);
% Binding must expose actual decoded value errors, not select the UE values.
wrongValue=T; wrongValue.CQI=1;
bound=sixgr.report.bindCSIReportMeasurementAudit(measured,wrongValue,"DL");
assert(~bound.ReportCSIExactMatch && ...
    bound.ReportBindingStatus=="measured_csi_report_value_mismatch:CQI");
% UL reports must not be joined into the DL CSI-RS table.
wrongDirection=T; wrongDirection.Direction="UL";
unbound=sixgr.report.bindCSIReportMeasurementAudit(measured,wrongDirection,"DL");
assert(isnan(unbound.ReportMeasurementSourceSlot));
ok=true;
fprintf('CSI_REPORT_MEASUREMENT_AUDIT_PASS distinct_slots=1 identity_guards=1 decoded_values_unchanged=1\n');
end
