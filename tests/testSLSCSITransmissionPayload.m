function ok=testSLSCSITransmissionPayload()
% Modeled CSI -> real typed serialization. Not a waveform receiver test.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run.executionID='csi_payload_causality';
cfg.system.linkAbstraction.dlFeedback.enabled=true;
cfg.system.linkAbstraction.dlFeedback.panel.Ports=2;
cfg.system.linkAbstraction.dlFeedback.maximumAgeSlots=12;
cfg.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_and_srs_and_csirs_and_pdcch';
cfg.phy.csirs.resourceIDs=[7 19];
cfg.phy.csi.cqiTable='table1'; cfg.phy.csi.allowUncalibratedBLERLUT=true;
cfg.phy.csi.reportConfigurationEpoch=0;
request=struct('ReportConfigID',"sls_transmission_fixture",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',1,'MaxRank',2, ...
    'AllowedRanks',[1 2],'ReportQuantity',"cri-RI-LI-PMI-CQI", ...
    'NumCSIResources',2,'FrequencyGranularity',"wideband",'UCIChannel',"PUCCH");
for transport=["PUCCH","PUSCH"]
    request.UCIChannel=transport; cfg.phy.csi.reportConfiguration=request;
    q=sixgr.system.abstraction.CausalDLCSIFeedback(cfg);
    o=struct('ObservationID',"early",'ExecutionID',string(cfg.run.executionID), ...
        'UEIndex',1,'ServingCell',1,'SourceAbsoluteSlot0',1,'ReportAbsoluteSlot0',9, ...
        'ReferenceAvailableAtSlot0',3,'AvailableAbsoluteSlot0',10, ...
        'CompletionAbsoluteSlot0',2,'CRI',0,'ReferenceResourceID',7, ...
        'ReferenceEmissionSHA256',string(repmat('a',1,64)), ...
        'ChannelEstimate',repmat(eye(2),1,1,4),'ExternalCovariance',eye(2), ...
        'TotalTransmitPower',100,'RFProfileID',"ideal", ...
        'SourceClassification',"modeled_csi_not_waveform_measurement");
    q.append(o,2);
    p=q.reportForTransmission(1,1,9,2); assert(~p.Available && isempty(p.Part1Bits));
    p=q.reportForTransmission(1,1,9,3); assert(p.Available && p.SelectedFeedback.RI==2);
    assert(isempty(q.select(1,1,3,4)),'UE payload readiness must not bypass gNB delivery time.');
    % A stronger beam captured in the future cannot affect this past report
    % query; a newer same-CRI measurement replaces its older observation.
    later=o; later.ObservationID="later_other_beam"; later.CRI=1; later.ReferenceResourceID=19;
    later.SourceAbsoluteSlot0=6; later.CompletionAbsoluteSlot0=7; later.ReferenceAvailableAtSlot0=8;
    later.TotalTransmitPower=200; q.append(later,7);
    past=q.reportForTransmission(1,1,9,3);
    assert(isequal(past.Part1Bits,p.Part1Bits) && past.SelectedFeedback.CRI==0);
    current=q.reportForTransmission(1,1,9,8); assert(current.SelectedFeedback.CRI==1);
    newer=later; newer.ObservationID="newer_same_beam"; newer.SourceAbsoluteSlot0=7;
    newer.CompletionAbsoluteSlot0=8; newer.ReferenceAvailableAtSlot0=9;
    newer.TotalTransmitPower=1e-3; q.append(newer,8);
    final=q.reportForTransmission(1,1,9,9); assert(final.SelectedFeedback.CRI==0);
    delivered=q.select(1,1,10,10);
    assert(delivered.ObservationID==final.SelectedFeedback.ObservationID);
    typedRequest=request; typedRequest.Rank=final.SelectedFeedback.RI;
    typed=sixgr.phy.mimo.CSIReportConfiguration(typedRequest,0);
    decoded=typed.decode(final.Part1Bits,final.Part2Bits);
    assert(decoded.CRI==final.SelectedFeedback.CRI && decoded.RI==final.SelectedFeedback.RI && ...
        decoded.PMI==final.SelectedFeedback.PMI && decoded.CQI_CW0==final.SelectedFeedback.CQI && ...
        decoded.LI==final.SelectedFeedback.LI && ~final.WaveformBacked && ~final.PhysicalDecodeQualified);
    if transport=="PUCCH", assert(isempty(final.Part2Bits)); else, assert(~isempty(final.Part2Bits)); end
    absent=q.reportForTransmission(1,2,9,9); assert(~absent.Available);
    absent=q.reportForTransmission(1,1,8,8); assert(~absent.Available);
    reject(@()q.reportForTransmission(1,1,9,10),'sixgr:abstraction:DLCSIReportClock');
end
fprintf('SLS_CSI_TRANSMISSION_PAYLOAD_PASS native_typed_parts=1 no_early_scheduler_delivery=1 modeled_only=1\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s',id);
end
