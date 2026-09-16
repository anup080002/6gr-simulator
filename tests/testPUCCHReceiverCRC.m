function ok=testPUCCHReceiverCRC()
% Detected desired and wrong-RNTI waveforms; CRC is not replaced by DTX.
setup6GRSimToolkit('Verbose',false);
bits=int8(mod((1:32).',2));
configured=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,bits,'RNTI',321);
% Declare the gNB procedure independently of TX payloads. Configured CSI
% occupies all four installed PRBs; dynamic HARQ selects two at rate 0.80.
% The former fixture transmitted CSI but declared HARQ at RX (E=128 vs 64).
for procedure=["configured_csi","dynamic_harq"]
    isHARQ=procedure=="dynamic_harq";
    expectedPRBs=4-2*double(isHARQ);
    context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb_crc_observation", ...
        'ConfigurationEpoch',1,'Sequence1Length',32,'Sequence2Length',0, ...
        'HARQACKBits',32*double(isHARQ),'SRBits',0, ...
        'CSIPart1Bits',32*double(~isHARQ),'CSIPart2Bits',0,'PriorityIndex',0));
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
        'ObservationID',"gnb_crc_observation",'ResourceID',12, ...
        'RNTI',321,'AbsoluteSlot0',0,'Source',"declared_gNB_CRC_component", ...
        'TimingSource',"received_PUCCH_DMRS", ...
        'ResourceSelectionProcedure',procedure),configured.RRCContext,context);
    assert(assignment.Resource.Data.NumPRBs==expectedPRBs);
    assert(assignment.Data.AllocationBudget.CapacityBits==32*expectedPRBs);
    for rnti=[321 322]
        txFixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,bits,'RNTI',rnti);
        if isHARQ
            state=txFixture.Report.Data;
            state.HARQACKReport=struct('Bits',bits);
            state.CSIReports=struct([]);
            report=sixgr.phy.pucch.UCIReport(state);
            plan=sixgr.phy.pucch.PUCCHResourcePlan(report,txFixture.UEContext.Data, ...
                txFixture.RRCContext,txFixture.FrameState,"dynamic_harq");
            power=txFixture.Assignment.PowerControlState.Data;
            % Bind the existing power formula to the actual allocation;
            % do not retain the four-PRB MRB after selecting two PRBs.
            power.MRB=plan.Resource.Data.NumPRBs;
            txFixture.Assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromResourcePlan( ...
                plan,sixgr.phy.pucch.PUCCHPowerControlState(power), ...
                txFixture.Assignment.SpatialRelationState);
            txFixture.Report=plan.TransmittedReport;
        end
        for field=["StartPRB","NumPRBs","StartSymbol","NumSymbols"]
            assert(txFixture.Assignment.Resource.Data.(field)==assignment.Resource.Data.(field));
        end
        tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(txFixture.Carrier,txFixture.Assignment,txFixture.Report);
        assert(tx.Coding.Plan.E==assignment.Data.AllocationBudget.CapacityBits);
        [waveform,~]=sixgr.link.addRuntimeComplexNoise(tx.Waveform,1e-8,18000+rnti,0,struct());
        rx=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,configured.Carrier,assignment,context, ...
            'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
            'ChannelProfile','AWGN','DetectionThreshold',0.2);
        assert(rx.CRCApplicable && numel(rx.CodeBlockCRCError)==1 && ...
            ~rx.DTX && rx.ReceiverUsable && rx.ReceiverOnlyAssignment && ~rx.OraclePayloadBitsUsed);
        assert(rx.CRCPassed==(rnti==321) && rx.CodeBlockCRCError==(rnti~=321));
        if rnti==321, assert(isequal(rx.DecodedSequence1,bits)); end
        fprintf('PUCCH_RECEIVER_CRC_CASE procedure=%s rnti=%d prbs=%d E=%d crc_passed=%d\n', ...
            procedure,rnti,expectedPRBs,tx.Coding.Plan.E,rx.CRCPassed);
    end
end
fprintf('PUCCH_RECEIVER_CRC_PASS procedures=2 desired=pass wrong_RNTI=CRC_fail all_waveforms_detected\n');
ok=true;
end
