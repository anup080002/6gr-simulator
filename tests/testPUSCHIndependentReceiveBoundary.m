function ok=testPUSCHIndependentReceiveBoundary(legacyReference)
% Real NR UCI codecs on deterministic LLR fixtures, not RF qualification.
if nargin<1, legacyReference=[]; end
setup6GRSimToolkit('Verbose',false);
decoder=@sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive;
scorer=@sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.score;
makeContext=@sixgr.phy.ul.pusch.PUSCHUCIReceiveContext;
p=nrPUSCHConfig('PRBSet',0:11,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK', ...
    'BetaOffsetACK',20,'BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
cases=0;
for count=[0 1 2 3 5 12 20]
    bits=int8(mod((1:count).',2));
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',bits);
    context=makeContext(localObligation(count));
    [llr,data]=localEncode(p,512,payload);
    rx=decoder(p,.3,512,llr,context,4);
    assert(isequal(rx.DecodedHARQACK,bits));
    assert(isequal(int8(rx.ULSCHLLR{1}<0),data));
    assert(~isfield(rx,'HARQACKContentMatch') && ~isfield(rx,'CSI1ContentMatch'), ...
        'Receiver output must not contain transmitter scoring.');
    good=scorer(rx,payload);
    assert(good.HARQACKContentMatch);
    before=rx;
    poisoned=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',ones(count+1,1,'int8'));
    bad=scorer(rx,poisoned);
    assert(~bad.HARQACKContentMatch && isequaln(rx,before), ...
        'Scoring a different value/length cannot mutate received fields or usability.');
    again=decoder(p,.3,512,llr,context,4);
    assert(isequaln(rx,again));
    if ~isempty(legacyReference)
        old=legacyReference(p,.3,512,llr,payload,4);
        compatibility=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex(p,.3,512,llr,payload,4);
        assert(isequaln(old,compatibility),'Legacy adapter must preserve baseline outputs.');
    end
    assert(rx.UCIReceiverEvidence.ReceiverContextDigest==context.Digest);
    assert(rx.UCIReceiverEvidence.HARQACK.InformationBitCount==count);
    if count>0, assert(rx.UCIReceiverEvidence.HARQACK.DecodeUsable); end
    localReject(@()decoder(p,.3,512,llr,payload,4), ...
        'sixgr:pusch:MissingUCIReceiveContext');
    cases=cases+1;
end

% Combined five-bit HARQ with CSI. Part-2 length follows received RI, even
% when the installed schema was constructed with the other allowed rank.
for rank=[1 2]
 for tbs=[0 512]
    request=struct('ReportConfigID',"gnb_installed_csi",'Epoch',3, ...
        'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',2, ...
        'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
        'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',4, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    layout=sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,prod(layout.Dimensions)-1);
    values.RI=rank; values.CRI=2; values.CQI_CW0=10; values.LI=rank-1;
    txConfig=sixgr.phy.mimo.CSIReportConfiguration(request,3);
    report=txConfig.build(values);
    ack=int8([1;0;1;0;0]);
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',ack, ...
        'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
    d=localObligation(5); d.CSIReportConfigID="gnb_installed_csi"; d.CSIConfigurationEpoch=3;
    context=makeContext(d);
    request.Rank=3-rank;
    installed=sixgr.phy.mimo.CSIReportConfiguration(request,3);
    budget=context.bitBudget(installed);
    assert(budget.OCSI2==0,'Part 2 must remain unresolved before receiving Part 1.');
    [llr,data]=localEncode(p,tbs,payload);
    rx=decoder(p,.3,tbs,llr,context,4,installed);
    assert(isequal(rx.DecodedHARQACK,ack) && isequal(rx.DecodedCSIPart1,report.Part1Bits) && ...
        isequal(rx.DecodedCSIPart2,report.Part2Bits));
    assert(rx.CSIPart1DecodedBeforePart2 && rx.ResolvedCSI2BitCount==numel(report.Part2Bits));
    assert(rx.CSI2LengthAuthority=="received_csi_part1_and_active_report_configuration");
    assert(isequal(int8(rx.ULSCHLLR{1}<0),data));
    if ~isempty(legacyReference)
        old=legacyReference(p,.3,tbs,llr,payload,4,installed);
        compatibility=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex(p,.3,tbs,llr,payload,4,installed);
        assert(isequaln(old,compatibility),'Combined CSI adapter must preserve baseline outputs.');
    end
    decoded=installed.decode(rx.DecodedCSIPart1,rx.DecodedCSIPart2);
    assert(decoded.RI==rank && decoded.CQI_CW0==10 && decoded.CRI==2);
    poison=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8(1), ...
        'CSIPart1',int8(1),'CSIPart2',int8(1));
    bad=scorer(rx,poison);
    assert(~bad.HARQACKContentMatch && ~bad.CSI1ContentMatch && ~bad.CSI2ContentMatch);
    localReject(@()context.bitBudget(), 'sixgr:pusch:MissingCSIReportConfiguration');
    localReject(@()context.bitBudget(installed.forTransport('PUCCH')), ...
        'sixgr:pusch:CSIReceiveConfigurationMismatch');
    request.ReportConfigID="different_installed_report";
    other=sixgr.phy.mimo.CSIReportConfiguration(request,3);
    localReject(@()context.bitBudget(other),'sixgr:pusch:CSIReceiveConfigurationMismatch');
    request.ReportConfigID="gnb_installed_csi"; request.Epoch=4;
    other=sixgr.phy.mimo.CSIReportConfiguration(request,4);
    localReject(@()context.bitBudget(other),'sixgr:pusch:CSIReceiveConfigurationMismatch');
    emptyContext=makeContext(localObligation(0));
    localReject(@()emptyContext.bitBudget(installed),'sixgr:pusch:CSIReceiveConfigurationMismatch');
    cases=cases+1;
 end
end

% A strict whitelist rejects even unfamiliar/nested oracle field names.
for name=["ExpectedUCIBits","TransmittedPayloadBits","UEState","Payload","SRBits","OCSI2"]
    bad=localObligation(2); bad.(name)=struct('Bits',int8([1;0]));
    localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
end
for value={-1,1.5,NaN,Inf,1i,[1 2],true,'2'}
    bad=localObligation(2); bad.HARQACKBitCount=value{1};
    localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
end
bad=localObligation(2); bad.HARQMappingDigest="";
localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
bad=localObligation(0); bad.HARQMappingDigest="invented_nonempty_mapping";
localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
bad=localObligation(2); bad.AssignmentDigest="";
localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
bad=localObligation(2); bad.ObservationID=missing;
localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
bad=localObligation(2); bad.CSIConfigurationEpoch=0;
localReject(@()makeContext(bad),'sixgr:pusch:InvalidUCIReceiveObligation');
fprintf('PUSCH_INDEPENDENT_RECEIVE_BOUNDARY_PASS codec_cases=%d plus malformed/oracle/CSI-binding rejection\n',cases);
ok=true;
end

function d=localObligation(count)
mapping=""; if count>0, mapping="literal_gnb_mapping_fixture"; end
d=struct('ObservationID',"literal_receive_occasion",'ConfigurationEpoch',0, ...
    'AssignmentDigest',"literal_scheduled_ul_assignment",'HARQMappingDigest',mapping, ...
    'HARQACKBitCount',count,'ConfiguredGrantUCIBitCount',0, ...
    'CSIReportConfigID',"",'CSIConfigurationEpoch',NaN);
end

function [llr,data]=localEncode(p,tbs,payload)
counts=payload.toStruct();
info=nrULSCHInfo(p,.3,tbs,counts.OACK,counts.OCSI1,counts.OCSI2+counts.OCGUCI);
data=int8(mod((0:double(info.GULSCH)-1).',2));
encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(p,.3,tbs,data,payload,4);
bits=encoded.Codewords{1};
bits(bits==-1)=1;
y=find(bits==-2); bits(y)=bits(y-1);
llr=100*(1-2*double(bits));
end

function localReject(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),'Expected %s, observed %s: %s',identifier,err.identifier,err.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection: %s',identifier);
end
