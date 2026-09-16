function ok=testPUCCHCSIWholeReportSelection()
% Actual configured planning and waveform/receiver component, not a full run.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_tdd_connected_feedback_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
ue.ConfigurationEpoch=rrc.ConfigurationEpoch;
frame=struct('K1',4,'K1Source',"decoded_dci",'PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'FirstCCE',0,'NumCCE',8, ...
    'PRIProvenance',"declared_component_DCI",'SlotSymbolOwnership',"UUUUUUUUUUUUUU");
harq=int8([1;0;1;0]);
base=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,harq,int8(ones(7,1)),int8([]),frame);
assert(base.Plan.Resource.Data.NumPRBs==1); % A=11 fits one PRB when no omission.
for lengths={[7 9 1],[7 5 1]}
    sizes=lengths{1}; data=base.RequestedReport.Data;
    reports=repmat(struct('ReportID',0,'Priority',0,'Part1Bits',int8([]),'Part2Bits',int8([])),1,3);
    for k=1:3
        reports(k).ReportID=10*k; reports(k).Priority=k;
        reports(k).Part1Bits=int8(mod((1:sizes(k)).',2));
    end
    data.CSIReports=reports([3 1 2]); % Input order is not priority order.
    requested=sixgr.phy.pucch.UCIReport(data);
    plan=sixgr.phy.pucch.PUCCHResourcePlan(requested,ue,rrc,frame,"combined_uci");
    expectedIDs=10; csiCount=7;
    if sizes(2)==5, expectedIDs=[10 20]; csiCount=12; end
    assert(isequal(plan.Data.CSISelection.TransmittedReportIDs,expectedIDs));
    assert(plan.Resource.Data.NumPRBs==2 && plan.Data.ResourceSetID==base.Plan.Data.ResourceSetID);
    assert(plan.Data.AllocationBudget.Procedure=="dynamic_harq_csi_omission");
    assert(plan.RequestedReportDigest==requested.Digest && plan.ReportDigest~=requested.Digest);
    planned=struct('Plan',plan,'Report',plan.TransmittedReport);
    bound=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned);
    assert(bound.Assignment.PowerControlState.Data.MRB==2);
    carrier=sixgr.phy.grid.makeCarrier(cfg); carrier.NSlot=4; carrier.NFrame=0;
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,bound.Assignment,bound.Report);
    assert(tx.Coding.Plan.A==4+csiCount && tx.Coding.Plan.E==64);
    expectedCRC=0; if csiCount==12, expectedCRC=6; end
    assert(tx.Coding.Plan.TotalCRCBits==expectedCRC);
    reject(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,bound.Assignment,requested), ...
        'sixgr:phy:pucch:PlannedReportMismatch');
    context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"declared_gNB_subset", ...
        'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',4+csiCount, ...
        'Sequence2Length',0,'HARQACKBits',4,'SRBits',0,'CSIPart1Bits',csiCount, ...
        'CSIPart2Bits',0,'PriorityIndex',0));
    rxAssignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct('ObservationID',context.ReportID, ...
        'ResourceID',10,'RNTI',1,'AbsoluteSlot0',4,'Source',"declared_gNB_component_hypothesis", ...
        'TimingSource',"declared_slot",'ResourceSelectionProcedure',"dynamic_harq_csi_omission"),rrc,context);
    assert(rxAssignment.Resource.Digest==bound.Assignment.Resource.Digest);
    rx=sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform,carrier,rxAssignment,context, ...
        'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate','ChannelProfile','AWGN', ...
        'DetectionThreshold',sixgr.phy.pucch.resolveDetectionThreshold(bound.Assignment));
    assert(rx.ReceiverOnlyAssignment && ~rx.OraclePayloadBitsUsed && rx.ReceiverUsable && ~rx.DTX);
    assert(isequal(rx.DecodedFields.HARQACK,harq));
    wanted=reports(1).Part1Bits;
    if csiCount==12, wanted=[wanted;reports(2).Part1Bits]; end
    assert(isequal(rx.DecodedFields.CSIPart1,wanted));
end
% Normal builder/materializer also returns the selected report when all CSI
% is omitted, retaining four HARQ bits rather than silently dropping HARQ.
allOmitted=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,harq,int8(ones(20,1)),int8([]),frame);
bound=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,allOmitted);
assert(isempty(bound.Report.Data.CSIReports) && bound.ReceiverContext.HARQACKBits==4 && ...
    bound.ReceiverContext.CSIPart1Bits==0 && allOmitted.Plan.Resource.Data.NumPRBs==2);
assert(isequal(allOmitted.Plan.Data.CSISelection.OmittedReportIDs,1));
assert(~isempty(allOmitted.RequestedReport.Data.CSIReports));
% Unsupported short-resource transition stays explicit, not made legal by padding.
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,int8(1),int8(ones(24,1)),int8([]),frame), ...
    'sixgr:phy:pucch:CSIOmissionShortPayloadProcedureRequired');
bad=requested.Data; bad.CSIReports(1).ReportID=bad.CSIReports(2).ReportID;
reject(@()sixgr.phy.pucch.PUCCHResourcePlan(sixgr.phy.pucch.UCIReport(bad),ue,rrc,frame,"combined_uci"), ...
    'sixgr:phy:pucch:DuplicateCSIReportIdentity');
ok=true;
fprintf('PUCCH_WHOLE_CSI_SELECTION_PASS priority_prefix=1 no_truncation=1 CRC_recomputed=1 selected_power=1 independent_component_RX=1 integrated=0 short_transition_pending=1\n');
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
