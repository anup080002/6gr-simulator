function ok=testConfiguredCombinedPUCCHReception(outputRoot)
% Actual encoded/decoded combined PUCCH component waveforms. Scheduling and
% CSI/HARQ/SR values are declared test inputs, not connected-runtime evidence.
setup6GRSimToolkit('Verbose',false);
if nargin<1
    logsRoot=fullfile(pwd,'logs');
    if ~isfolder(logsRoot), mkdir(logsRoot); end
    outputRoot=tempname(logsRoot);
end
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier captures.');
mkdir(outputRoot);
request=struct('ReportConfigID',"installed_wideband_test",'Epoch',1, ...
    'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',1,'AllowedRanks',[1 2], ...
    'MaxRank',2,'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',4, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUCCH");
installed=sixgr.phy.mimo.CSIReportConfiguration(request,1);
obligation=struct('ObservationID',"gnb_combined_capture",'ConfigurationEpoch',1, ...
    'HARQBitCount',2,'SRBitCount',1,'PriorityIndex',0, ...
    'CSIReportConfigID',installed.ReportConfigID,'CSIConfigurationEpoch',1);
context=sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,installed);
% Construct the receiver before any payload. This context stays byte-identical
% across different HARQ/SR values and the transmitter's rank choice.
digest=context.Digest;
fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(zeros(context.Sequence1Length,1)), ...
    'SimultaneousHARQACKCSI',true);
rxAssignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',obligation.ObservationID,'ResourceID',fixture.Assignment.Resource.ID, ...
    'RNTI',fixture.Report.Data.RNTI,'AbsoluteSlot0',0, ...
    'Source',"declared_gNB_component_obligation_and_installed_RRC", ...
    'TimingSource',"received_PUCCH_DMRS", ...
    'ResourceSelectionProcedure',"dynamic_harq_csi"),fixture.RRCContext,context);
audit=table();
for rank=1:2
    txRequest=request; txRequest.Rank=rank;
    txConfig=sixgr.phy.mimo.CSIReportConfiguration(txRequest,1);
    values=struct('CRI',2,'RI',rank,'CQI_CW0',9,'PMI',0);
    if rank==1, values.PMI=3; end
    csi=txConfig.build(values);
    harq=int8([rank-1;2-rank]); sr=int8(rank-1);
    d=fixture.Report.Data; d.ReportID="ue_report_"+rank;
    d.HARQACKReport=struct('Bits',harq);
    d.SchedulingRequestReports=struct('Bits',sr);
    d.CSIReports=struct('Part1Bits',csi.Part1Bits,'Part2Bits',csi.Part2Bits,'Priority',0,'ReportID',1);
    report=sixgr.phy.pucch.UCIReport(d);
    plan=sixgr.phy.pucch.PUCCHResourcePlan(report,fixture.UEContext.Data, ...
        fixture.RRCContext,fixture.FrameState,"declared_component_dynamic_harq");
    power=fixture.UEContext.Data.PowerControlState.Data;
    power.MRB=plan.Resource.Data.NumPRBs;
    assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromResourcePlan(plan, ...
        sixgr.phy.pucch.PUCCHPowerControlState(power),fixture.UEContext.Data.SpatialRelationState);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(fixture.Carrier,assignment,report);
    [waveform,~]=sixgr.link.addRuntimeComplexNoise(tx.Waveform,1e-8,91+rank,0,struct());
    rx=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,fixture.Carrier,rxAssignment,context, ...
        'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
        'ChannelProfile','AWGN','DetectionThreshold',0.2);
    assert(rx.ReceiverOnlyAssignment && ~rx.OraclePayloadBitsUsed && rx.ReceiverUsable && ~rx.DTX && rx.CRCPassed);
    assert(isequal(rx.DecodedFields.HARQACK,harq) && isequal(rx.DecodedFields.SR,sr));
    decoded=installed.decode(rx.DecodedFields.CSIPart1,rx.DecodedFields.CSIPart2);
    assert(decoded.RI==rank && decoded.CRI==2 && decoded.CQI_CW0==9 && decoded.PMI==values.PMI);
    [llr,likelihood]=sixgr.phy.pucch.demapFormat2EqualizerOutput( ...
        fixture.Carrier,rxAssignment.Resource.toolboxConfig(),rx.EqualizerInfo.EqualizerResult);
    corrected=sixgr.phy.pucch.UCIDecoder.decode(llr,context.Sequence1Length+context.Sequence2Length);
    assert(isequal(corrected.Bits,[harq;sr;csi.Part1Bits;csi.Part2Bits]) && ...
        corrected.CRCPassed && corrected.CRCApplicable==rx.CRCApplicable && ...
        ~likelihood.TransmittedBitsUsed && ~likelihood.SignalPresenceDecisionMade);
    assert(context.Digest==digest && ...
        sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,txConfig).Digest==digest);
    save(fullfile(outputRoot,sprintf('combined_rank_%d.mat',rank)), ...
        'request','obligation','context','rxAssignment','report','tx','waveform','rx','decoded', ...
        'llr','likelihood','corrected');
    row=table(rank,string(context.Digest),string(rx.AssignmentDigest),true, ...
        "declared_obligation_actual_PUCCH_component_not_integrated", ...
        'VariableNames',{'TransmittedRI','ReceiverContextDigest','ReceiverAssignmentDigest','BitsRecovered','EvidenceClass'});
    audit=[audit;row]; %#ok<AGROW>
end
% The common configured constructor must preserve the existing HARQ-only schema.
harqOnly=obligation; harqOnly.SRBitCount=0;
harqOnly.CSIReportConfigID=""; harqOnly.CSIConfigurationEpoch=NaN;
h=sixgr.truth.buildConfiguredPUCCHReceiveContext(harqOnly);
legacy=sixgr.phy.pucch.UCIReportContext(struct( ...
    'ReportID',string(harqOnly.ObservationID),'ConfigurationEpoch',harqOnly.ConfigurationEpoch, ...
    'Sequence1Length',2,'Sequence2Length',0,'HARQACKBits',2, ...
    'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
assert(isequal(h.Data,legacy.Data) && h.Digest==legacy.Digest);
for name=["ConfigurationEpoch","HARQBitCount","SRBitCount","PriorityIndex"]
    bad=obligation; bad.(name)=0.5;
    reject(@()sixgr.truth.buildConfiguredPUCCHReceiveContext(bad,installed), ...
        'sixgr:truth:InvalidPUCCHReceiveObligation');
end
bad=harqOnly; bad.HARQBitCount=0;
reject(@()sixgr.truth.buildConfiguredPUCCHReceiveContext(bad), ...
    'sixgr:truth:EmptyPUCCHReceiveObligation');
bad=obligation; bad.ExpectedBits=int8([1;0]);
reject(@()sixgr.truth.buildConfiguredPUCCHReceiveContext(bad,installed),'sixgr:truth:InvalidPUCCHReceiveObligation');
bad=obligation; bad.CSIConfigurationEpoch=2;
reject(@()sixgr.truth.buildConfiguredPUCCHReceiveContext(bad,installed),'sixgr:truth:CSIReceiveConfigurationMismatch');
reject(@()sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,[]),'sixgr:truth:MissingInstalledCSIReceiveConfiguration');
reject(@()sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,installed.forTransport('PUSCH')), ...
    'sixgr:truth:CSIReceiveConfigurationMismatch');
writetable(audit,fullfile(outputRoot,'combined_receiver_context_audit.csv'));
fprintf('CONFIGURED_COMBINED_PUCCH_RX_PASS waveforms=2 ranks=1,2 constant_receiver_schema=1 HARQ_SR_CSI_bits_exact=1 integrated=0\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
