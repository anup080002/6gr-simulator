function ok=testPUCCHConfiguredSRResource()
% Installed SR resource/clock and actual short-SR waveforms, not MAC closure.
for format=[0 1]
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,int8(0));
    rrcData=f.RRCContext.Data;
    resource=rrcData.Resources; resource.ID=37; resource.StartPRB=7;
    rrcData.Resources=[rrcData.Resources resource];
    rrcData.SRResources=37;
    rrcData.SchedulingRequestResources=struct('scheduling_request_resource_id',1, ...
        'scheduling_request_id',2,'resource_id',37,'periodicity_slots',5, ...
        'offset_slots',0,'priority_index',1);
    ueData=f.UEContext.Data;
    ueData.RRCContext=sixgr.phy.pucch.PUCCHRRCContext(rrcData);
    ue=sixgr.phy.pucch.PUCCHUEContext(ueData);
    data=struct('SchedulingRequestID',2,'PeriodSlots',5,'OffsetSlots',0, ...
        'AbsoluteSlot',0,'PendingPositiveSR',true,'ProhibitTimerActive',false, ...
        'ResourceID',37,'Priority',1);
    frame=f.FrameState;
    % DCI fields cannot select or time a configured standalone SR.
    frame.DecodedPRI=999; frame.K1=-100; frame.PDSCHEndSlot=NaN;
    for positive=[false true]
        data.PendingPositiveSR=positive;
        sr=sixgr.phy.pucch.SchedulingRequestState(data);
        [assignment,report]=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromSR(sr,ue,frame);
        assert(assignment.Resource.ID==37 && assignment.Resource.Data.StartPRB==7);
        assert(isnan(assignment.Data.PRIValue) && isnan(assignment.Data.ResourceSetID));
        assert(assignment.Data.PRIProvenance=="configured_sr_resource");
        assert(assignment.Data.K1Source=="configured_sr_occasion" && assignment.DueSlot==1);
        assert(assignment.Data.SRResourceConfigurationID==1 && report.PriorityIndex==1);
        tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,assignment,report);
        assert(tx.TransmissionPresent==positive);
        context=sixgr.phy.pucch.UCIReportContext(struct( ...
            'ReportID',report.ReportID,'ConfigurationEpoch',1, ...
            'Sequence1Length',1,'Sequence2Length',0,'HARQACKBits',0, ...
            'SRBits',1,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',1));
        identity=struct('ObservationID',"configured_sr_component",'ResourceID',37, ...
            'RNTI',ue.Data.RNTI,'AbsoluteSlot0',0,'Source',"installed_SR_component", ...
            'TimingSource',"declared_slot");
        reception=sixgr.phy.pucch.PUCCHReceptionAssignment(identity,ue.Data.RRCContext,context);
        args={'NoiseVariance',0,'NoiseVarianceMode','provided'};
        if format==0, args={'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation'}; end
        rx=sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform,f.Carrier,reception,context, ...
            args{:},'DetectionThreshold',sixgr.phy.pucch.resolveDetectionThreshold(assignment));
        assert(rx.ReceiverOnlyAssignment && ~rx.OraclePayloadBitsUsed && rx.DTX==~positive);
        if positive
            if format==0, reference=nrPUCCH(f.Carrier,tx.PUCCH,{int8([]),int8(1)});
            else, reference=nrPUCCH(f.Carrier,tx.PUCCH,int8(0)); end
            assert(max(abs(tx.Grid(tx.PUCCHIndices)-reference))<1e-12);
            assert(isequal(rx.DecodedFields.SR,int8(1)));
        else
            assert(~any(tx.Waveform(:)) && isempty(tx.PUCCHIndices) && isempty(tx.DMRSIndices));
            assert(isempty(tx.Ownership.Table) && isnan(tx.Power.AppliedPowerdBm));
        end
    end
    for field=["SchedulingRequestID","ResourceID","PeriodSlots","OffsetSlots","Priority"]
        bad=data; bad.(field)=bad.(field)+1;
        expected='sixgr:phy:pucch:SRConfigurationMismatch';
        if field=="ResourceID", expected='sixgr:phy:pucch:UninstalledSRResource'; end
        reject(@()sixgr.phy.pucch.PUCCHTransmissionAssignment.fromSR( ...
            sixgr.phy.pucch.SchedulingRequestState(bad),ue,frame),expected);
    end
    bad=data; bad.AbsoluteSlot=1;
    reject(@()sixgr.phy.pucch.PUCCHTransmissionAssignment.fromSR( ...
        sixgr.phy.pucch.SchedulingRequestState(bad),ue,frame),'sixgr:phy:pucch:InvalidSROccasion');
    badFrame=frame; badFrame.TargetSlot=6;
    reject(@()sixgr.phy.pucch.PUCCHTransmissionAssignment.fromSR( ...
        sixgr.phy.pucch.SchedulingRequestState(data),ue,badFrame),'sixgr:phy:pucch:InvalidSROccasion');
    badFrame=frame; badFrame.SlotSymbolOwnership="DDDDDDDDDDDDDD";
    reject(@()sixgr.phy.pucch.PUCCHTransmissionAssignment.fromSR( ...
        sixgr.phy.pucch.SchedulingRequestState(data),ue,badFrame),'sixgr:phy:pucch:IllegalTDDResource');
end
for field=["PendingPositiveSR","ProhibitTimerActive"]
    for value={NaN,Inf,-1,2,0.5,[],[0 1],1i,"true"}
        bad=data; bad.(field)=value{1};
        reject(@()sixgr.phy.pucch.SchedulingRequestState(bad),'sixgr:phy:pucch:InvalidSRState');
    end
end
for field=["SchedulingRequestID","PeriodSlots","OffsetSlots","AbsoluteSlot"]
    for value={NaN,Inf,-1,0.5,[],[0 1],1i,"1"}
        bad=data; bad.(field)=value{1};
        reject(@()sixgr.phy.pucch.SchedulingRequestState(bad),'sixgr:phy:pucch:MissingSRConfiguration');
    end
end
ok=true;
fprintf('PUCCH_CONFIGURED_SR_RESOURCE_PASS distinct_SR_and_HARQ_resources=1 ignored_DCI_fields=1 positive_negative_actual_waveforms=1 malformed_state_rejection=1\n');
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Unexpected error %s, expected %s.',cause.identifier,id);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
