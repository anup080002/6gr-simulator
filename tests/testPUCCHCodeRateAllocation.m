function ok=testPUCCHCodeRateAllocation()
% Allocation math/public PHY references, not connected-run qualification.
setup6GRSimToolkit('Verbose',false);
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(mod((1:20).',2)));
% Declared non-interlaced format 2: 8 data RE/PRB/symbol, QPSK, 2 symbols.
assert(f.Assignment.Resource.Data.NumSymbols==2);
for row=[11 1;12 2;19 3;20 3].'
    [r,b]=f.Assignment.Resource.selectPRBAllocation(f.Carrier,row(1),0.35,"dynamic_harq");
    assert(r.Data.NumPRBs==row(2) && b.CapacityBits==32*row(2) && b.RateConstraintSatisfied);
    assert(r.Data.StartPRB==f.Assignment.Resource.Data.StartPRB);
end
[r,b]=f.Assignment.Resource.selectPRBAllocation(f.Carrier,11,0.35,"configured_csi");
assert(r.Digest==f.Assignment.Resource.Digest && b.SelectedNumPRBs==4 && ...
    b.Disposition=="configured_csi_resource");
d=f.Assignment.Resource.Data; d.NumPRBs=2;
limited=sixgr.phy.pucch.PUCCHResource(d);
[r,b]=limited.selectPRBAllocation(f.Carrier,20,0.35,"dynamic_harq");
assert(r.Data.NumPRBs==2 && ~b.RateConstraintSatisfied && ...
    b.InformationAndCRCRate==31/64 && ~b.RequiresCSISelection);
% Above the nominal rate is not itself an encoder-feasibility rejection.
payload=int8(mod((1:20).',2)); encoded=nrUCIEncode(payload,b.CapacityBits);
assert(numel(encoded)==64);
[r,b]=limited.selectPRBAllocation(f.Carrier,20,0.35,"dynamic_harq_csi");
assert(isempty(r) && isnan(b.SelectedNumPRBs) && b.RequiresCSISelection);
[r,b]=limited.selectPRBAllocation(f.Carrier,20,0.35,"configured_csi");
assert(isempty(r) && ~b.RequiresCSISelection && b.Disposition=="configured_csi_capacity_exceeded");
[r,b]=limited.selectPRBAllocation(f.Carrier,12,0.25,"dynamic_harq_csi");
assert(isempty(r) && b.TotalCRCBits==6 && b.CapacityBits==64);
% Intra-slot hopping retains the configured second-hop start after shrinking.
d=f.Assignment.Resource.Data; d.IntraSlotHopping=true; d.SecondHopStartPRB=14;
hopped=sixgr.phy.pucch.PUCCHResource(d);
[r,b]=hopped.selectPRBAllocation(f.Carrier,11,0.35,"dynamic_harq");
assert(r.Data.NumPRBs==1 && r.Data.SecondHopStartPRB==14 && b.CapacityBits==32);
% Format 3: four symbols/no hopping -> one DM-RS symbol, 72 coded bits/PRB.
f3=sixgr.phy.pucch.PUCCHFixtureFactory.connected(3,int8(mod((1:20).',2)));
d=f3.Assignment.Resource.Data; d.NumPRBs=8;
wide=sixgr.phy.pucch.PUCCHResource(d);
[r,b]=wide.selectPRBAllocation(f3.Carrier,150,0.35,"dynamic_harq");
assert(r.Data.NumPRBs==8 && b.CapacityBits==8*72 && b.TotalCRCBits==11);
% Seven PRBs would meet the raw inequality but are not a legal DFT width.
assert(150+11>6*72*0.35 && 150+11<=7*72*0.35);
% TS 38.213 9.2 uses 11 selection CRC bits for A>=360, not the
% actual two-block CRC total. This changes a physical allocation boundary.
segmentedData=f3.Assignment.Resource.Data;
segmentedData.NumPRBs=5; segmentedData.NumSymbols=14; segmentedData.StartSymbol=0;
segmented=sixgr.phy.pucch.PUCCHResource(segmentedData);
[r,b]=segmented.selectPRBAllocation(f3.Carrier,385,0.35,"dynamic_harq");
assert(r.Data.NumPRBs==4 && b.CapacityBits==1152 && b.TotalCRCBits==22 && ...
    b.AllocationCRCBits==11 && b.AllocationInputBits==396 && b.RateConstraintSatisfied);
assert(b.InformationAndCRCRate==396/1152 && b.ActualInformationAndCRCRate==407/1152);
assert(396<=0.35*1152 && 407>0.35*1152);
uci=int8(mod((1:385).',2)); cw=nrUCIEncode(uci,b.CapacityBits);
[decoded,crc]=nrUCIDecode(20*(1-2*double(cw)),numel(uci));
assert(isequal(decoded,uci) && ~any(crc));
d.NumPRBs=7; invalid=sixgr.phy.pucch.PUCCHResource(d);
reject(@()invalid.selectPRBAllocation(f3.Carrier,150,0.35,"dynamic_harq"), ...
    'sixgr:phy:pucch:InvalidPRBAllocation');
% Reject an invalid configured pool even when its first PRB could fit.
d=f.Assignment.Resource.Data; d.StartPRB=f.Carrier.NSizeGrid-1;
outside=sixgr.phy.pucch.PUCCHResource(d);
reject(@()outside.selectPRBAllocation(f.Carrier,11,0.35,"dynamic_harq"), ...
    'sixgr:phy:pucch:InvalidPRBAllocation');
for value={NaN,Inf,[],[0.25 0.35],0.3,true,0.35+1i}
    reject(@()limited.selectPRBAllocation(f.Carrier,12,value{1},"dynamic_harq"), ...
        'sixgr:phy:pucch:InvalidMaxCodeRate');
end
reject(@()limited.selectPRBAllocation(f.Carrier,12,0.35,"guess"), ...
    'sixgr:phy:pucch:InvalidAllocationProcedure');
reject(@()limited.selectPRBAllocation([],12,0.35,"dynamic_harq"), ...
    'sixgr:phy:pucch:MissingCarrierConfiguration');
% The same installed configuration drives normal TX planning and independent RX.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_tdd_connected_feedback_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
assert(rrc.maxCodeRate(2)==0.35);
frame=struct('K1',4,'K1Source',"decoded_dci",'PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'FirstCCE',0,'NumCCE',8, ...
    'PRIProvenance',"declared_component_DCI",'SlotSymbolOwnership',"UUUUUUUUUUUUUU");
for A=[11 12]
    context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb_"+A, ...
        'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',A,'Sequence2Length',0, ...
        'HARQACKBits',A,'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
    rx=sixgr.phy.pucch.PUCCHReceptionAssignment(struct('ObservationID',context.ReportID, ...
        'ResourceID',10,'RNTI',1,'AbsoluteSlot0',4,'Source',"declared_gNB", ...
        'TimingSource',"declared_component"),rrc,context);
    planned=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,int8(mod((1:A).',2)),frame);
    tx=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned);
    assert(rx.Resource.Digest==tx.Assignment.Resource.Digest && ...
        rx.Resource.Data.NumPRBs==A-10 && tx.Assignment.PowerControlState.Data.MRB==A-10);
    assert(isequal(rx.Data.AllocationBudget,tx.Assignment.Data.AllocationBudget));
    waveformCarrier=sixgr.phy.grid.makeCarrier(cfg);
    waveformCarrier.NSlot=4; waveformCarrier.NFrame=0;
    physical=sixgr.phy.pucch.PUCCHTransmitter.transmit(waveformCarrier,tx.Assignment,tx.Report);
    assert(physical.Coding.Plan.E==tx.Assignment.Data.AllocationBudget.CapacityBits && ...
        isequal(physical.PUCCH.PRBSet,tx.Assignment.Resource.Data.StartPRB+(0:A-11)) && ...
        numel(physical.PUCCHIndices)==16*(A-10));
    assert(tx.Assignment.Data.ReportDigest==planned.Report.Digest);
    if A==11, frozen=tx; end
end
% Same ID/epoch is insufficient: reject altered bits, lengths and bit owners
% before coding against a stale rate/power allocation. This is the retained
% 11 -> 12 counterexample (one PRB at 0.35 versus two with the added CRC).
for mutation=1:5
    changed=frozen.Report.Data;
    switch mutation
        case 1, changed.HARQACKReport.Bits(1)=1-changed.HARQACKReport.Bits(1);
        case 2, changed.HARQACKReport.Bits(end+1)=int8(1);
        case 3
            changed.SchedulingRequestReports=struct('Bits',changed.HARQACKReport.Bits(end));
            changed.HARQACKReport.Bits(end)=[];
        case 4, changed.RNTI=changed.RNTI+1;
        case 5, changed.TargetSlot=changed.TargetSlot+1;
    end
    changed=sixgr.phy.pucch.UCIReport(changed);
    assert(changed.ReportID==frozen.Report.ReportID && ...
        changed.ConfigurationEpoch==frozen.Report.ConfigurationEpoch);
    reject(@()sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
        waveformCarrier,frozen.Assignment,changed),'sixgr:phy:pucch:PlannedReportMismatch');
end
for invalid={[],"",missing,["a" "b"],17}
    data=frozen.Assignment.Data; data.ReportDigest=invalid{1};
    badAssignment=sixgr.phy.pucch.PUCCHTransmissionAssignment(data,frozen.Assignment.Resource, ...
        frozen.Assignment.PowerControlState,frozen.Assignment.SpatialRelationState);
    reject(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(waveformCarrier,badAssignment,frozen.Report), ...
        'sixgr:phy:pucch:PlannedReportMismatch');
end
data=rmfield(frozen.Assignment.Data,'ReportDigest');
for mode=1:3
    if mode==2, data.ConnectedModeEvidenceEligible=false; end
    if mode==3, data.AssignmentSource="calibration"; end
    unbound=sixgr.phy.pucch.PUCCHTransmissionAssignment(data,frozen.Assignment.Resource, ...
        frozen.Assignment.PowerControlState,frozen.Assignment.SpatialRelationState);
    reject(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(waveformCarrier,unbound,frozen.Report), ...
        'sixgr:phy:pucch:MissingPlannedReportBinding');
end
% The explicit calibration factory has no payload-derived allocation budget
% and stays ineligible as connected-mode evidence.
request=struct('AssignmentID',"calibration_binding_test",'ReportID',f.Report.ReportID, ...
    'RNTI',f.Report.Data.RNTI,'ConfigurationEpoch',f.Report.ConfigurationEpoch, ...
    'Resource',f.Assignment.Resource,'PowerControlState',f.Assignment.PowerControlState, ...
    'SpatialRelationState',f.Assignment.SpatialRelationState);
cal=sixgr.phy.pucch.PUCCHTransmissionAssignment.forCalibration(request,struct('AbsoluteSlot',1));
calTX=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,cal,f.Report);
assert(~calTX.ConnectedModeEvidenceEligible && ~isfield(cal.Data,'AllocationBudget'));
% CSI+SR without HARQ follows the installed CSI resource, not a decoded PRI.
d=planned.Report.Data; d.HARQACKReport=struct([]);
d.SchedulingRequestReports=struct('Bits',int8(1));
d.CSIReports=struct('Part1Bits',int8([1;0;1;0]),'Part2Bits',int8([]),'Priority',0,'ReportID',1);
report=sixgr.phy.pucch.UCIReport(d);
ueWithEpoch=ue; ueWithEpoch.ConfigurationEpoch=rrc.ConfigurationEpoch;
csiFrame=frame; csiFrame.DecodedPRI=7;
csiPlan=sixgr.phy.pucch.PUCCHResourcePlan(report,ueWithEpoch,rrc,csiFrame,"configured_csi_sr");
assert(csiPlan.Resource.ID==10 && csiPlan.Resource.Data.NumPRBs==2 && isnan(csiPlan.Data.PRIValue));
context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb_csi_sr", ...
    'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',5,'Sequence2Length',0, ...
    'HARQACKBits',0,'SRBits',1,'CSIPart1Bits',4,'CSIPart2Bits',0,'PriorityIndex',0));
rx=sixgr.phy.pucch.PUCCHReceptionAssignment(struct('ObservationID',context.ReportID, ...
    'ResourceID',10,'RNTI',1,'AbsoluteSlot0',4,'Source',"declared_gNB", ...
    'TimingSource',"declared_component"),rrc,context);
assert(rx.Resource.Digest==csiPlan.Resource.Digest && ...
    isequal(rx.Data.AllocationBudget,csiPlan.Data.AllocationBudget));
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,int8(ones(20,1)), ...
    int8([1;0;1;0]),int8([]),frame),'sixgr:phy:pucch:CSIResourceCapacityExceeded');
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,int8([1;0]), ...
    int8([1;0;1;0]),int8([1;0;1]),frame),'sixgr:phy:pucch:SeparateCSIPart2CodingRequired');
absent=cfg;
absent.validation.pucch_resources.format2=rmfield(absent.validation.pucch_resources.format2,'max_code_rate');
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(absent,ue,int8(ones(12,1)),frame), ...
    'sixgr:phy:pucch:MissingMaxCodeRate');
for value={[],NaN,0.3,[0.25 0.35]}
    bad=cfg; bad.validation.pucch_resources.format2.max_code_rate=value{1};
    reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(bad,ue), ...
        'sixgr:phy:pucch:InvalidMaxCodeRate');
end
carrier=sixgr.phy.grid.makeCarrier(cfg);
sixgr.phy.pucch.PUCCHResource.validateAllocationCarrier(tx.Assignment.Data.AllocationBudget,carrier);
carrier.NStartGrid=carrier.NStartGrid+1;
reject(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,tx.Assignment,tx.Report), ...
    'sixgr:phy:pucch:AllocationCarrierMismatch');
ok=true;
fprintf('PUCCH_CODE_RATE_ALLOCATION_PASS CRC_boundary=1 configured_CSI_preserved=1 HARQ_max_branch=1 CSI_omission_required=1 legal_DFT_width=1 TX_RX_power_binding=1 coupled_run=0\n');
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
