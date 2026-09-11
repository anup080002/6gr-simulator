function ok=testPUSCHReceivedCSI2Length()
% Actual UCI codec/multiplexing with noiseless LLR fixtures. No RF claim.
setup6GRSimToolkit('Verbose',false);
p=nrPUSCHConfig('PRBSet',0:5,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
cases=0;
for mode=[1 2]
 for rank=[1 2]
  for tbs=[0 512]
    request=struct('ReportConfigID',"received_csi_size_fixture",'Epoch',0, ...
        'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',2, ...
        'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',mode, ...
        'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',4, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    layout=sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,prod(layout.Dimensions)-1);
    values.RI=rank; values.CRI=3; values.CQI_CW0=11; values.LI=rank-1;
    config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    report=config.build(values);
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
    info=nrULSCHInfo(p,.3,tbs,0,numel(report.Part1Bits),numel(report.Part2Bits));
    data=int8(mod((0:double(info.GULSCH)-1).',2));
    encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(p,.3,tbs,data,payload,4);
    llr=100*(1-2*double(encoded.Codewords{1}));
    % Deliberately wrong TX reference values AND Part-2 length. The receiver
    % is allowed to compare these, never use them to size its demapper.
    poisoned=sixgr.phy.ul.pusch.PUSCHUCIPayload('CSIPart1',1-report.Part1Bits, ...
        'CSIPart2',int8(1),'UCIOnly',tbs==0);
    request.Rank=3-rank;
    receiver=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    actual=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex(p,.3,tbs,llr,poisoned,4,receiver);
    assert(actual.CSIPart1DecodedBeforePart2 && ...
        actual.CSI2LengthAuthority=="received_csi_part1_and_active_report_configuration");
    assert(actual.ResolvedCSI2BitCount==numel(report.Part2Bits));
    assert(isequal(actual.DecodedCSIPart1,report.Part1Bits) && ...
        isequal(actual.DecodedCSIPart2,report.Part2Bits));
    assert(~actual.CSI1ContentMatch && ~actual.CSI2ContentMatch, ...
        'TX diagnostic mismatch must remain visible while received decoding is correct.');
    assert(isequal(int8(actual.ULSCHLLR{1}<0),data));
    decoded=receiver.decode(actual.DecodedCSIPart1,actual.DecodedCSIPart2);
    assert(decoded.RI==rank && decoded.PMI==prod(layout.Dimensions)-1);
    cases=cases+1;
  end
 end
end
% A configured single-port report has no Part 2, including UCI-only.
request.Ports=1; request.Rank=1; request.MaxRank=1;
config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
report=config.build(struct('CRI',2,'CQI_CW0',9));
for tbs=[0 512]
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('CSIPart1',report.Part1Bits);
    info=nrULSCHInfo(p,.3,tbs,0,numel(report.Part1Bits),0);
    data=int8(mod((0:double(info.GULSCH)-1).',2));
    encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(p,.3,tbs,data,payload,4);
    poisoned=sixgr.phy.ul.pusch.PUSCHUCIPayload('CSIPart1',1-report.Part1Bits,'CSIPart2',int8(1));
    actual=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex( ...
        p,.3,tbs,100*(1-2*double(encoded.Codewords{1})),poisoned,4,config);
    assert(actual.ResolvedCSI2BitCount==0 && isempty(actual.DecodedCSIPart2));
    assert(isequal(actual.DecodedCSIPart1,report.Part1Bits));
    assert(isequal(int8(actual.ULSCHLLR{1}<0),data));
    cases=cases+1;
end
% Excluding rank two removes the RI bit, not a receiver-side rank clamp.
request.Ports=2; request.Rank=2; request.MaxRank=2;
config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
report=config.build(struct('CRI',2,'RI',2,'CQI_CW0',9,'PMI',1,'LI',1));
payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
info=nrULSCHInfo(p,.3,512,0,numel(report.Part1Bits),numel(report.Part2Bits));
encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
    p,.3,512,zeros(info.GULSCH,1,'int8'),payload,4);
request.MaxRank=1;
rejected=false;
try
    sixgr.phy.mimo.CSIReportConfiguration(request,0);
catch err
    assert(strcmp(err.identifier,'sixgr:mimo:InvalidRI')); rejected=true;
end
assert(rejected,'An excluded RI must not produce a report configuration.');
ok=true; fprintf('PUSCH_RECEIVED_CSI2_SIZE_PASS cases=%d plus excluded RI rejection\n',cases);
end
