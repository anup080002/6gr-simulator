function ok=testReceivedDAIHoleNativePUSCH(outputRoot)
% Progressive component checkpoint, NOT shared multiassignment qualification.
% Original retained DL events + actual decoded UL DCI -> native PUSCH RX.
% CSI values and identity channel are explicitly declared component inputs.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot)); mkdir(outputRoot);
controlRoot=fullfile(outputRoot,'original_control');
assert(testReceivedULTotalDAICodebook(controlRoot));
cfg=sixgr.config.defaultConfig(); cfg.run.useMex=false;
cfg.phy.pusch.mcsTable='qam64_table1'; cfg.phy.pusch.transformPrecoding=false;
cfg.phy.nTxAnt=1; cfg.phy.nRxAnt=1; cfg.channel.nTxAnt=1; cfg.channel.nRxAnt=1;
cfg.phy.pusch.numLayers=1; cfg.phy.pusch.nLayers=1;
c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',30);
p=nrPUSCHConfig('PRBSet',0:11,'NumLayers',1,'Modulation','QPSK');
p.DMRS.DMRSPortSet=0;
[~,grid]=nrPUSCHIndices(c,p); tbs=nrTBS('QPSK',1,12,grid.NREPerPRB,.3,0);
bits=int8(mod((0:tbs-1).',2));
request=struct('ReportConfigID',"declared_DAI_checkpoint_CSI",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',1,'MaxRank',2, ...
    'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
    'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',3, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH",'ConfiguredUCIChannel',"PUSCH");
schema=sixgr.phy.mimo.CSIReportConfiguration(request,0);
[~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
values.RI=1; values.CRI=2; values.CQI_CW0=9; report=schema.build(values);
cases=0;
for k=1:4
    path=fullfile(controlRoot,sprintf('received_ul_dai_%d_2.mat',k));
    originalSHA=sixgr.util.sha256File(path); original=load(path);
    book=original.book; e=original.event.Data;
    holes=find(book.SourceEventIndex==0);
    assert(~isempty(holes) && all(book.Bits(holes)==0) && numel(book.Events)==1);
    assert(book.Events(1).Digest==original.event.Digest);
    receive=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
        'ObservationID',"declared_receiver_schedule_case_"+k,'ConfigurationEpoch',e.ConfigurationEpoch, ...
        'AssignmentDigest',original.a.AssignmentDigest,'HARQMappingDigest',book.Digest, ...
        'HARQACKBitCount',numel(book.Bits),'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',request.ReportConfigID,'CSIConfigurationEpoch',0));
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',book, ...
        'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
    tx=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',c,'PUSCH',p,'TargetCodeRate',.3, ...
        'NumTxAnt',1,'UCIPayload',payload,'TransportBlockBits',bits, ...
        'TransportBlockSizeOverride',tbs,'RV',0,'ExecutionProfile','phy_calibration');
    rx=sixgr.phy.ul.PUSCH_Rx(tx.Waveform,cfg,'Carrier',c,'PUSCH',p, ...
        'TransportBlockSize',tbs,'TargetCodeRate',.3,'RV',0,'InitialIMCSPerCodeword',0, ...
        'UCIReceiveContext',receive,'UCIReportConfiguration',schema, ...
        'NoiseVar',1e-10,'NoiseVarDomain','grid','SkipTimingEstimate',true,'ExecutionProfile','phy_calibration');
    assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,bits));
    assert(isequal(rx.DecodedHARQACKBits,book.Bits) && all(rx.DecodedHARQACKBits(holes)==0));
    assert(isequal(rx.DecodedCSIPart1Bits,report.Part1Bits) && ...
        isequal(rx.DecodedCSIPart2Bits,report.Part2Bits) && ~rx.UCIReferenceScoringAvailable);
    assert(sixgr.util.sha256File(path)==originalSHA);
    save(fullfile(outputRoot,sprintf('native_gap_case_%d.mat',k)), ...
        'originalSHA','book','holes','receive','payload','tx','rx','report','-v7.3');
    cases=cases+1;
end
fprintf('RECEIVED_DAI_NATIVE_PUSCH_PASS cases=%d shared_multiassignment_qualified=0 CSI_measured=0\n',cases);
ok=true;
end
