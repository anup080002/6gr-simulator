function ok=testPUCCHShortSRContract()
% Actual short-SR waveform semantics and absence accounting, not qualification.
setup6GRSimToolkit('Verbose',false);
for format=[0 1]
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,int8(0));
    data=f.Report.Data;
    data.HARQACKReport=struct('Bits',int8([]));
    for sr=int8([0 1])
        data.SchedulingRequestReports=struct('Bits',sr);
        report=sixgr.phy.pucch.UCIReport(data);
        % Independent declaration: no fromReport/expected bit values at RX.
        context=sixgr.phy.pucch.UCIReportContext(struct( ...
            'ReportID',report.ReportID,'ConfigurationEpoch',f.RRCContext.ConfigurationEpoch, ...
            'Sequence1Length',1,'Sequence2Length',0,'HARQACKBits',0, ...
            'SRBits',1,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
        identity=struct('ObservationID',"short_sr",'ResourceID',f.Assignment.Resource.ID, ...
            'RNTI',f.Assignment.Data.RNTI,'AbsoluteSlot0',0, ...
            'Source',"installed_SR_resource_component",'TimingSource',"declared_slot");
        assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(identity,f.RRCContext,context);
        txAssignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI( ...
            report,f.UEContext,f.FrameState);
        tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,txAssignment,report);
        assert(tx.TransmissionPresent==logical(sr) && tx.Power.TransmissionPresent==logical(sr));
        if sr==0
            assert(~any(tx.Waveform(:)) && isempty(tx.PUCCHIndices) && isempty(tx.DMRSIndices));
            assert(isempty(tx.Ownership.Table) && tx.Ownership.DataRECount==0 && tx.Ownership.DMRSRECount==0);
            assert(isnan(tx.Power.AppliedPowerdBm) && isnan(tx.Power.PowerError_dB));
            assert(tx.Power.MeasuredWaveformPowerdBm==-Inf);
        else
            if format==0, reference=nrPUCCH(f.Carrier,tx.PUCCH,{int8([]),int8(1)});
            else, reference=nrPUCCH(f.Carrier,tx.PUCCH,int8(0)); end
            assert(max(abs(tx.Grid(tx.PUCCHIndices)-reference))<1e-12);
            assert(~isempty(tx.Ownership.Table) && isfinite(tx.Power.AppliedPowerdBm));
        end
        threshold=sixgr.phy.pucch.resolveDetectionThreshold(f.Assignment);
        args={'NoiseVariance',0,'NoiseVarianceMode','provided'};
        if format==0, args={'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation'}; end
        rx=sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform,f.Carrier,assignment,context, ...
            args{:},'DetectionThreshold',threshold);
        assert(rx.ReceiverOnlyAssignment && ~rx.OraclePayloadBitsUsed);
        assert(rx.DTX==~logical(sr));
        if sr==1, assert(isequal(rx.DecodedFields.SR,int8(1)) && isempty(rx.DecodedFields.HARQACK));
        else, assert(isempty(rx.DecodedSequence1)); end
    end
end
% Two HARQ bits plus SR stay on set 0; SR is not a third HARQ bit.
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,int8([0;1]));
data=f.Report.Data; data.SchedulingRequestReports=struct('Bits',int8(1));
report=sixgr.phy.pucch.UCIReport(data);
rrcData=f.RRCContext.Data; rrcData.ResourceSets.MaxPayloadBits=2;
rrc=sixgr.phy.pucch.PUCCHRRCContext(rrcData);
plan=sixgr.phy.pucch.PUCCHResourcePlan(report,f.UEContext.Data,rrc,f.FrameState,"component");
assert(plan.Format==0 && plan.Data.ResourceSetID==0);
% Illegal schemas still fail; no general relaxation from <=2 to <=3 bits.
validContext=sixgr.phy.pucch.UCIReportContext.fromReport(report);
reject(@()sixgr.phy.pucch.PUCCHFormatValidator.validateResource( ...
    plan.Resource.Data,4,validContext),'sixgr:phy:pucch:InvalidFormatPayload');
bad=validContext.Data;
bad.HARQACKBits=3; bad.SRBits=0;
reject(@()sixgr.phy.pucch.PUCCHFormatValidator.validateResource( ...
    plan.Resource.Data,3,sixgr.phy.pucch.UCIReportContext(bad)), ...
    'sixgr:phy:pucch:InvalidFormatPayload');
bad.HARQACKBits=2; bad.SRBits=1;
resource=plan.Resource.Data; resource.Format=1; resource.NumSymbols=4; resource.StartSymbol=10;
reject(@()sixgr.phy.pucch.PUCCHFormatValidator.validateResource( ...
    resource,3,sixgr.phy.pucch.UCIReportContext(bad)), ...
    'sixgr:phy:pucch:UnresolvedFormat1SRResource');
reject(@()sixgr.phy.pucch.PUCCHGridMapper.map(f.Carrier,f.Assignment,complex(zeros(0,1))), ...
    'sixgr:phy:pucch:UCILengthMismatch');
for value={NaN,Inf,-1,2,0.5,[],[0 1]}
    badReport=report.Data; badReport.SchedulingRequestReports=struct('Value',value{1});
    reject(@()sixgr.phy.pucch.UCIReportSerializer.serialize( ...
        sixgr.phy.pucch.UCIReport(badReport)),'sixgr:phy:pucch:InvalidUCIBit');
end
ok=true;
fprintf('PUCCH_SHORT_SR_CONTRACT_PASS format0_and_1_SR_only=1 absence_ownership_power=1 independent_RX=1 unresolved_format1_overlap_rejected=1\n');
end

function reject(fn,id)
try
    fn();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error: %s',err.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
