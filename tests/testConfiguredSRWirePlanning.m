function ok=testConfiguredSRWirePlanning()
% Exact target planner plus declared multi-SR state algebra. No RF claim.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
calendar=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,4,4);
initial=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
originalDigest=initial.Digest;
states=sixgr.phy.pucch.SchedulingRequestState.atSlot(initial,3);
assert(initial.Digest==originalDigest && ~states.Data.PendingPositiveSR);
frame=struct('K1',1,'K1Source','declared_component_timing','PDSCHEndSlot',3, ...
    'TargetSlot',4,'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','declared_component_DCI', ...
    'FirstCCE',0,'NumCCE',4,'SlotSymbolOwnership','UUUUUUUUUUUUUU', ...
    'SchedulingRequestStates',states);
csi=sixgr.phy.mimo.CSIReportConfiguration(cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
bits=zeros(csi.part1BitCount(),1,'int8');
for harqCount=0:1
    planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,ones(harqCount,1,'int8'),bits,int8([]),frame);
    assert(planned.ReceiverContext.SRBits==1 && planned.ReceiverContext.Sequence1Length==numel(bits)+harqCount+1);
    assert(isequal(planned.Report.Data.SchedulingRequestReports.Bits,int8(0)));
    before=planned.Plan.Digest;
    again=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,ones(harqCount,1,'int8'),bits,int8([]),frame);
    assert(before==again.Plan.Digest && initial.Digest==originalDigest);
    obligation=struct('ObservationID',"independent_configured_count_component", ...
        'ConfigurationEpoch',cfg.validation.pucch_resources.configuration_epoch,'HARQBitCount',harqCount, ...
        'SRBitCount',ceil(log2(height(calendar)+1)),'PriorityIndex',0, ...
        'CSIReportConfigID',csi.ReportConfigID,'CSIConfigurationEpoch',csi.Epoch);
    rx=sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,csi);
    assert(rx.Sequence1Length==planned.ReceiverContext.Sequence1Length && rx.SRBits==1);
end
missing=rmfield(frame,'SchedulingRequestStates');
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,bits,int8([]),missing), ...
    'sixgr:truth:MissingSRProcedureState');
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
resource=rrc.resourceByID(sixgr.phy.pucch.resolveConfiguredCSIResourceID(rrc.Data.CSIResources));
for name=["ConfigurationEpoch","RNTI","ServingCell","ComponentCarrier","ActiveULBWP","UEIndex"]
    data=states.Data; data.(name)=data.(name)+1;
    bad=sixgr.phy.pucch.SchedulingRequestState(data);
    reject(@()sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,resource,0,bad), ...
        'sixgr:truth:SRProcedureConfigurationMismatch');
end
reject(@()sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,resource,0,initial), ...
    'sixgr:truth:StaleSRProcedureState');
reject(@()sixgr.phy.pucch.SchedulingRequestState.atSlot(states,2),'sixgr:truth:StaleSRProcedureState');
reject(@()sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,resource,0,[states states]), ...
    'sixgr:truth:InvalidSRProcedureIdentity');
% All-negative compact width and every positive ordinal for K=0..8.
cases=0;
for count=0:8
    rows=calendar(ones(count,1),:);
    rows.SRResourceConfigurationID=(count:-1:1).';
    rows.SchedulingRequestID=(count-1:-1:0).';
    rows.ObligationID="declared_SR_wire_algebra_"+rows.SRResourceConfigurationID;
    samples=cell(1,count);
    for k=1:count
        data=states.Data; data.SRResourceConfigurationID=rows.SRResourceConfigurationID(k);
        data.SchedulingRequestID=rows.SchedulingRequestID(k);
        samples{k}=sixgr.phy.pucch.SchedulingRequestState(data);
    end
    snapshots=[samples{:}];
    for selected=0:count
        positive=snapshots;
        if selected>0
            j=find(rows.SRResourceConfigurationID==selected);
            data=positive(j).Data; data.PendingPositiveSR=true;
            positive(j)=sixgr.phy.pucch.SchedulingRequestState(data);
        end
        [sr,overlap]=sixgr.truth.buildPUCCHSRWireIndicator(rows,4,resource,0,positive);
        width=ceil(log2(count+1)); assert(overlap.OpportunityCount==count);
        if count==0, assert(isempty(sr)); continue; end
        assert(numel(sr.Bits)==width && double(sr.Bits(:).')*2.^((width-1):-1:0).'==selected);
        cases=cases+1;
    end
    if count>1
        for j=1:count
            data=snapshots(j).Data; data.PendingPositiveSR=true;
            snapshots(j)=sixgr.phy.pucch.SchedulingRequestState(data);
        end
        reject(@()sixgr.truth.buildPUCCHSRWireIndicator(rows,4,resource,0,snapshots), ...
            'sixgr:truth:UnresolvedPositiveSRSelection');
        chosen=sixgr.truth.buildPUCCHSRWireIndicator(rows,4,resource,0,snapshots,count);
        assert(chosen.SelectedSRResourceConfigurationID==count);
    end
end
data=states.Data; data.PendingPositiveSR=true; data.ProhibitTimerActive=true;
prohibited=sixgr.phy.pucch.SchedulingRequestState(data);
sr=sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,resource,0,prohibited);
assert(sr.Bits==0);
reject(@()sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,resource,0,prohibited,1), ...
    'sixgr:truth:InvalidSRSelection');
% A union counts one occasion once; a gap between windows is not overlap.
o=sixgr.truth.resolveConfiguredSROverlap(calendar,4,[10 3;12 2],0);
assert(o.OpportunityCount==1);
o=sixgr.truth.resolveConfiguredSROverlap(calendar,4,[0 2;8 2],0);
assert(o.OpportunityCount==0);
short=rrc.resourceByID(0);
sr=sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,short,0,states);
assert(sr.Bits==0);
data=states.Data; data.PendingPositiveSR=true;
positive=sixgr.phy.pucch.SchedulingRequestState(data);
sr=sixgr.truth.buildPUCCHSRWireIndicator(calendar,4,short,0,positive);
assert(sr.Bits==1);
fprintf('CONFIGURED_SR_WIRE_PLANNING_PASS target_CSI_bits=%d target_combined_bits=%d algebra_cases=%d RF=0 MAC_lifecycle_qualified=0\n', ...
    numel(bits)+1,numel(bits)+2,cases);
ok=true;
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
