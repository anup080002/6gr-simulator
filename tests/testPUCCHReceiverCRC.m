function ok=testPUCCHReceiverCRC()
% Detected desired and wrong-RNTI waveforms; CRC is not replaced by DTX.
setup6GRSimToolkit('Verbose',false);
bits=int8(mod((1:32).',2));
configured=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,bits,'RNTI',321);
context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb_crc_observation", ...
    'ConfigurationEpoch',1,'Sequence1Length',32,'Sequence2Length',0, ...
    'HARQACKBits',32,'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',"gnb_crc_observation",'ResourceID',configured.Assignment.Resource.ID, ...
    'RNTI',321,'AbsoluteSlot0',0,'Source',"declared_gNB_CRC_component", ...
    'TimingSource',"received_PUCCH_DMRS"),configured.RRCContext,context);
for rnti=[321 322]
    txFixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,bits,'RNTI',rnti);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(txFixture.Carrier,txFixture.Assignment,txFixture.Report);
    [waveform,~]=sixgr.link.addRuntimeComplexNoise(tx.Waveform,1e-8,18000+rnti,0,struct());
    rx=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,configured.Carrier,assignment,context, ...
        'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
        'ChannelProfile','AWGN','DetectionThreshold',0.2);
    assert(rx.CRCApplicable && numel(rx.CodeBlockCRCError)==1 && ...
        ~rx.DTX && rx.ReceiverUsable && rx.ReceiverOnlyAssignment && ~rx.OraclePayloadBitsUsed);
    assert(rx.CRCPassed==(rnti==321) && rx.CodeBlockCRCError==(rnti~=321));
    if rnti==321, assert(isequal(rx.DecodedSequence1,bits)); end
end
fprintf('PUCCH_RECEIVER_CRC_PASS desired=pass wrong_RNTI=CRC_fail both_waveforms_detected\n');
ok=true;
end
