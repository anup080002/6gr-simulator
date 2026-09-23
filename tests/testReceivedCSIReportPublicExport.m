function ok = testReceivedCSIReportPublicExport()
% Declared export fixtures; these are not physical receiver qualification.
setup6GRSimToolkit('Verbose',false);
contract = sixgr.truth.llsOutputContract();
meta = struct('logical_run_id',"received_csi_export_fixture",'run_id',17);
base = struct('table_cqi_pmi_ri',table(1,15,4,999, ...
    'VariableNames',{'ue_id','wideband_cqi','ri','pmi'}), ...
    'table_mcs_tbs_evolution',table(1,15,28, ...
    'VariableNames',{'UEId','CQI','CQIDerivedMCS'}));
out = sixgr.truth.buildLLSPublicOutputTables(base,contract,meta);
assert(isempty(out.csi_report_table),'Scheduler rows must not become CSI reports.');
rx = struct2table(struct('SourceSignal',"received_CSI_UCI",'Direction',"DL", ...
    'ReportIdentity',"declared_receiver_report",'CSIUCIDecodeOk',1, ...
    'CSIUCICRCPass',1,'CSIUCITransport',"pucch_independently_received", ...
    'DeliveryStatus',"delivered_to_runtime_scheduler", ...
    'CSIReportConfigID',"csi-report-2",'CSIConfigurationEpoch',1, ...
    'UEIndex',1,'RNTI',320,'SourceSlot',34,'DueSlot',39,'DeliveredSlot',39, ...
    'CQI',15,'RI',2,'PMI',30,'CRI',0, ...
    'RawCQIDerivedMCS',28,'RawCQIDerivedModulation',"64QAM", ...
    'SINR_dB',123,'UEReferenceRecordJSON','{"RI":4,"PMI":999,"SINR_dB":321}', ...
    'SubbandCQI',"15 14",'SubbandPMI',"30 17"));
out = sixgr.truth.buildLLSPublicOutputTables(base,contract,meta,rx);
t = out.csi_report_table;
assert(height(t)==1 && t.CQI==15 && t.RI==2 && t.PMI==30 && t.CRI==0);
assert(t.CQIDerivedMCS==28 && t.CQIDerivedModulation=="64QAM");
assert(t.SourceSlot==34 && t.DueSlot==39 && t.DeliveredSlot==39 && t.Slot==39);
assert(t.ReportIdentity==rx.ReportIdentity && t.CSIReportConfigID=="csi-report-2");
assert(t.CSIUCITransport==rx.CSIUCITransport && t.RNTI==320);
assert(isnan(t.EffectiveSINR_dB) && t.CalibrationProfile=="");
assert(t.source_artifact_ref=="control/csv/received_csi_reports.csv");
assert(t.runtime_evidence=="independently_received_csi_uci");
poisoned = rx;
poisoned.UEReferenceRecordJSON = "poisoned_reference_payload";
poisoned.SINR_dB(:) = -123;
other = sixgr.truth.buildLLSPublicOutputTables(struct(),contract,meta,poisoned);
assert(isequaln(t,other.csi_report_table));
for decode = [0 NaN]
    failed = rx;
    failed.CSIUCIDecodeOk(:) = decode;
    failed.CSIUCICRCPass(:) = 0;
    failed.DeliveryStatus(:) = "decode_failed";
    out = sixgr.truth.buildLLSPublicOutputTables(base,contract,meta,failed);
    f = out.csi_report_table;
    assert(height(f)==1 && all(isnan(f{1,{'CQI','PMI','RI','CRI','CQIDerivedMCS'}})));
    assert(f.SubbandCQIVector=="" && f.SubbandPMIVector=="" && f.CQIDerivedModulation=="");
    assert(f.ReportIdentity==rx.ReportIdentity && f.DeliveryStatus=="decode_failed");
end
for source = ["CSI-RS","SRS","scheduler_observation"]
    bad = rx;
    bad.SourceSignal(:) = source;
    localReject(base,contract,meta,bad);
end
bad = rx;
bad.Direction(:) = "UL";
localReject(base,contract,meta,bad);
bad = removevars(rx,'CSIUCIDecodeOk');
localReject(base,contract,meta,bad);
unknownMapping = removevars(rx,{'RawCQIDerivedMCS','RawCQIDerivedModulation'});
out = sixgr.truth.buildLLSPublicOutputTables(base,contract,meta,unknownMapping);
assert(isnan(out.csi_report_table.CQIDerivedMCS) && out.csi_report_table.CQIDerivedModulation=="");
fprintf('RECEIVED_CSI_PUBLIC_EXPORT_AUTHORITY_PASS\n');
ok = true;
end

function localReject(base,contract,meta,bad)
try
    sixgr.truth.buildLLSPublicOutputTables(base,contract,meta,bad);
catch err
    assert(strcmp(err.identifier,'sixgr:report:CSIReportReceiverAuthority'));
    return;
end
error('test:ExpectedRejection','Non-receiver CSI source was accepted.');
end
