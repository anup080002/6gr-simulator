function ok=testTypeIIReceivedCSIReport()
% Typed report + independent PUSCH demultiplexer, noiseless coded LLRs.
% This is not a channel-estimation or full scenario qualification.
setup6GRSimToolkit('Verbose',false);
pusch=nrPUSCHConfig('PRBSet',0:5,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
cases=0;
for L=2:4
 for rank=1:2
  for sparse=[true false]
    request=struct('ReportConfigID',"typeII_received_report",'Epoch',0, ...
        'CodebookType',"typeII",'Ports',8,'Rank',rank,'MaxRank',2,'AllowedRanks',[1 2], ...
        'N1',2,'N2',2,'O1',4,'O2',4,'NumberOfBeams',L,'PhaseAlphabetSize',4, ...
        'ReportQuantity',"cri-ri-li-pmi-cqi",'NumCSIResources',3, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    amplitude=ones(2*L,rank); phase=ones(2*L,rank);
    amplitude(1,:)=7; phase(1,:)=0;
    if sparse, amplitude(2:end,1)=0; phase(2:end,1)=0; end
    components=struct('Q1',1,'Q2',2,'BeamGroupIndex',0, ...
        'StrongestCoefficientIndices',zeros(1,rank), ...
        'WidebandAmplitudeIndices',amplitude,'PhaseIndices',phase);
    tx=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    values=struct('RI',rank,'CRI',2,'CQI_CW0',11,'LI',rank-1,'PMIComponents',components);
    report=tx.build(values);
    % Independently concatenate CRI=10, RI, CQI=1011 and count indicators.
    width=ceil(log2(2*L-1)); counts=sum(amplitude>0,1);
    words=[dec2bin(2,2) dec2bin(rank-1,1) '1011' dec2bin(counts(1)-1,width)];
    second=0; if rank==2, second=counts(2)-1; end
    words=[words dec2bin(second,width)];
    assert(isequal(report.Part1Bits,int8((words-'0').')));
    % Stale bootstrap RI and coefficients must not size the received report.
    request.Rank=3-rank; request.NonzeroCoefficientCount=ones(1,3-rank);
    receiver=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    [part1,resolved]=receiver.decodePart1(report.Part1Bits);
    assert(part1.RI==rank && isequal(part1.NonzeroCoefficientCount,counts));
    assert(resolved.part2BitCount()==numel(report.Part2Bits));
    decoded=receiver.decode(report.Part1Bits.',report.Part2Bits.');
    assert(isequal(decoded.PMIComponents,components) && decoded.CRI==2 && decoded.LI==rank-1);
    assert(norm(decoded.Precoder_W-sixgr.phy.mimo.TypeIICodebook.matrix( ...
        setfield(request,'Rank',rank),components),'fro')<1e-14); %#ok<SFLD>
    packed=sixgr.phy.dl.packCSIFeedbackPayload( ...
        struct('TypedReport',report,'CSIReportConfiguration',receiver),struct('Strict',true));
    assert(packed.BitExactSupported && packed.SeparateEncoding && ...
        packed.WireFormatQualification=="qualified_typeII_wideband_pusch_codec_only");
    assert(ismember(numel(report.Part2Bits),receiver.part2BitCountCandidates()));
    obligation=struct('ObservationID',"declared_typeII_capture",'ConfigurationEpoch',0, ...
        'AssignmentDigest',"declared_ul_assignment",'HARQMappingDigest',"", ...
        'HARQACKBitCount',0,'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',request.ReportConfigID,'CSIConfigurationEpoch',0);
    context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(obligation);
    for tbs=[0 512]
        payload=sixgr.phy.ul.pusch.PUSCHUCIPayload( ...
            'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
        info=nrULSCHInfo(pusch,.3,tbs,0,numel(report.Part1Bits),numel(report.Part2Bits));
        data=int8(mod((0:double(info.GULSCH)-1).',2));
        encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(pusch,.3,tbs,data,payload,4);
        actual=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive( ...
            pusch,.3,tbs,100*(1-2*double(encoded.Codewords{1})),context,4,receiver);
        assert(actual.CSIPart1DecodedBeforePart2 && ...
            actual.CSI2LengthAuthority=="received_csi_part1_and_active_report_configuration");
        assert(isequal(actual.DecodedCSIPart1,report.Part1Bits) && ...
            isequal(actual.DecodedCSIPart2,report.Part2Bits));
        assert(isequal(int8(actual.ULSCHLLR{1}<0),data));
        cases=cases+1;
        if L==3 && rank==1 && sparse && tbs==512
            % Coded but semantically invalid count fields are failed CSI,
            % not a receiver crash or permission to erase invariant HARQ.
            for inactive=[false true]
                badFirst=report.Part1Bits;
                reason="sixgr:mimo:InvalidTypeIINonzeroCounts";
                if inactive
                    badFirst(end)=1; reason="sixgr:mimo:InvalidTypeIIInactiveCount";
                else
                    offset=sum(tx.Part1Widths(1:3)); badFirst(offset+(1:width))=1;
                end
                ack=int8([1;0;1;0;1]);
                badPayload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',ack, ...
                    'CSIPart1',badFirst,'CSIPart2',report.Part2Bits);
                badInfo=nrULSCHInfo(pusch,.3,tbs,5,numel(badFirst),numel(report.Part2Bits));
                badEncoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
                    pusch,.3,tbs,zeros(badInfo.GULSCH,1,'int8'),badPayload,4);
                badObligation=obligation; badObligation.HARQACKBitCount=5;
                badObligation.HARQMappingDigest="declared_five_assignments";
                partial=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive(pusch,.3,tbs, ...
                    100*(1-2*double(badEncoded.Codewords{1})), ...
                    sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(badObligation),4,receiver);
                assert(partial.PartialReception && ~partial.CSIPart1Usable && ...
                    partial.CSIRejectionIdentifier==reason && isequal(partial.DecodedHARQACK,ack));
            end
        end
    end
  end
 end
end
request.Rank=1; request=rmfield(request,'NonzeroCoefficientCount');
unresolved=sixgr.phy.mimo.CSIReportConfiguration(request,0);
localReject(@()unresolved.part2BitCount(),'sixgr:mimo:UnresolvedCSIPart2Length');
localReject(@()unresolved.forTransport('PUCCH'),'sixgr:mimo:UnsupportedCSIReportLayout');
request.UCIChannel="PUCCH";
localReject(@()sixgr.phy.mimo.CSIReportConfiguration(request,0),'sixgr:mimo:UnsupportedCSIReportLayout');
fprintf('TYPEII_RECEIVED_REPORT_PASS pusch_codec_cases=%d no_transmitter_receive_reference=1\n',cases);
ok=true;
end

function localReject(action,id)
try, action(); catch ex
    assert(string(ex.identifier)==id,'Expected %s, got %s: %s',id,ex.identifier,ex.message); return;
end
error('test:ExpectedFailure','Invalid CSI report was accepted.');
end
