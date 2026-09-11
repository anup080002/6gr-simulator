function ok=testPUSCHReceivedCSIWaveform()
% OFDM/DM-RS/LDPC/CSI round trip on an explicitly authored AWGN component.
% This is not a fading, access, scheduler, or link-adaptation qualification.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(3821208,'twister');
cfg=sixgr.config.defaultConfig();
cfg.channel.model="AWGN"; cfg.channel.awgnOnly=true;
cfg.phy.nTxAnt=1; cfg.phy.nRxAnt=1;
cfg.channel.nTxAnt=1; cfg.channel.nRxAnt=1;
cfg.scenario.ue.nTxAnt=1; cfg.antenna.ue.numElements=1;
cfg.phy.carrier.NSizeGrid=12; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.pusch.prbSet=0:5; cfg.phy.pusch.symbolAllocation=[0 14];
cfg.phy.pusch.modulation="QPSK"; cfg.phy.pusch.codeRate=.3;
cfg.phy.pusch.mcsIndex=4; cfg.phy.pusch.numLayers=1; cfg.phy.pusch.nLayers=1;
cfg.phy.pusch.numAntennaPorts=1; cfg.phy.pusch.numPorts=1;
cfg.phy.pusch.transmissionScheme="nonCodebook";
cfg.phy.pusch.transformPrecoding=false; cfg.phy.pusch.enablePTRS=false;
cfg.phy.pusch.equalizer="MMSE";
cfg.phy.pusch.dmrs.typeAPosition=2; cfg.phy.pusch.dmrs.configurationType=1;
cfg.phy.pusch.dmrs.additionalPosition=1; cfg.phy.pusch.dmrs.maxLength=1;
cfg.phy.pusch.dmrs.numCDMGroupsWithoutData=2;
cfg.phy.channelEstimation.method="LS";
request=struct('ReportConfigID',"received_csi_waveform_fixture",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',2,'MaxRank',2, ...
    'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',2, ...
    'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',4, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
reportCfg=sixgr.phy.mimo.CSIReportConfiguration(request,0);
[~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,5);
values.RI=2; values.CRI=2; values.CQI_CW0=11; values.LI=1;
report=reportCfg.build(values);
payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0]), ...
    'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
tx=sixgr.phy.ul.PUSCH_Tx(cfg,'UCIPayload',payload,'InitialIMCSPerCodeword',4);
% The DL CSI rank need not equal the number of layers on its UL transport.
request.Rank=1; cfg.phy.csi.reportConfiguration=request;
cfg.phy.csi.reportConfigurationEpoch=0;
poison=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([0;1]), ...
    'CSIPart1',1-report.Part1Bits,'CSIPart2',int8(1));
noiseVariance=1e-7;
received=tx.Waveform+sqrt(noiseVariance/2)*(randn(size(tx.Waveform))+1i*randn(size(tx.Waveform)));
for explicitLayout=[false true]
    args={};
    if explicitLayout, args={'CodingLayout',tx.CodingLayout}; end
    rx=sixgr.phy.ul.PUSCH_Rx(received,cfg,'Carrier',tx.Carrier,'PUSCH',tx.PUSCH, ...
        'TransportBlockSize',tx.TransportBlockSize,'TargetCodeRate',tx.TargetCodeRate, ...
        'RV',tx.RV,'ExpectedUCIPayload',poison,'InitialIMCSPerCodeword',4, ...
        'NoiseVar',noiseVariance,'NoiseVarDomain','time',args{:});
    assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,tx.TransportBlock));
    assert(isequal(rx.DecodedHARQACKBits,payload.HARQACK) && ~rx.HARQACKContentMatch);
    assert(isequal(rx.DecodedCSIPart1Bits,report.Part1Bits) && ...
        isequal(rx.DecodedCSIPart2Bits,report.Part2Bits));
    assert(rx.CSI1BitCount==numel(report.Part1Bits) && rx.CSI2BitCount==numel(report.Part2Bits));
    e=rx.UCIReceiverEvidence;
    assert(e.CSIPart1DecodedBeforePart2 && ...
        e.CSI2LengthAuthority=="received_csi_part1_and_active_report_configuration");
    assert(e.ResolvedCSI2BitCount==rx.CSI2BitCount);
    assert(rx.CodingLayout.RateMatchedBitCount==tx.CodingLayout.RateMatchedBitCount);
    assert(~rx.CSI1ContentMatch && ~rx.CSI2ContentMatch);
    assert(~e.CSI1.CRCApplicable && isnan(e.CSI1.CRCPass));
end
ok=true; fprintf('PUSCH_RECEIVED_CSI_WAVEFORM_PASS: actual OFDM/DMRS/LDPC/UCI, two layout contracts.\n');
end
