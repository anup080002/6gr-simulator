function ok=testCSIReceivedRankAuthority()
% Codec/semantic fixtures, not channel-measured CSI or main-run evidence.
% Deliberately disagree with the receiver object's previous rank. The
% received Part 1 must determine Part 2 field widths and interpretation.
for ports=[2 4 8]
    for rank=[1 2]
        request=struct('ReportConfigID',"received-rank-fixture",'Epoch',0, ...
            'CodebookType',"typeI-SinglePanel",'Ports',ports,'Rank',rank, ...
            'MaxRank',2,'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',2, ...
            'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH", ...
            'N1',2,'N2',ports/4,'O1',4,'O2',1,'CodebookMode',1);
        if ports==8, request.O2=4; end % TS 38.214 2x2-panel oversampling
        tx=sixgr.phy.mimo.CSIReportConfiguration(request,0);
        values=struct('CRI',1,'RI',rank,'CQI_CW0',9,'LI',rank-1);
        if ports==2
            values.PMI=3-rank;
        else
            values.PMI_I11=3; values.PMI_I12=0; values.PMI_I13=1; values.PMI_I2=3-rank;
        end
        encoded=tx.build(values);
        % Actual UCI channel codec on declared noiseless LLRs. This does
        % not claim an RF waveform or an over-the-air CSI observation.
        received=tx.encodeDecodeNoNoise(encoded);
        assert(received.CRCPassed && received.Part1BitErrors==0 && received.Part2BitErrors==0);
        request.Rank=3-rank;
        rx=sixgr.phy.mimo.CSIReportConfiguration(request,0);
        [part1,resolved]=rx.decodePart1(received.Part1.Bits);
        assert(part1.RI==rank && resolved.Rank==rank && rx.Rank~=rank && ...
            resolved.part2BitCount()==numel(received.Part2.Bits));
        actual=rx.decode(received.Part1.Bits,received.Part2.Bits);
        assert(actual.RI==rank && actual.CRI==1 && actual.CQI_CW0==9 && actual.LI==rank-1);
        if ports==2
            assert(actual.PMI==values.PMI);
        else
            assert(actual.PMI_I11==values.PMI_I11 && actual.PMI_I2==values.PMI_I2);
            if rank==2, assert(actual.PMI_I13==values.PMI_I13); end
        end
        localReject(@()rx.decode(received.Part1.Bits,[received.Part2.Bits;int8(0)]), ...
            'sixgr:mimo:InvalidCSIPart2Length');
        fractional=double(received.Part1.Bits); fractional(1)=.1;
        localReject(@()rx.decode(fractional,received.Part2.Bits), ...
            'sixgr:mimo:CSIDeserializationMismatch');
        fractional=double(received.Part2.Bits); fractional(1)=.1;
        localReject(@()rx.decode(received.Part1.Bits,fractional), ...
            'sixgr:mimo:CSIDeserializationMismatch');
        if ports==2 && rank==2
            request.MaxRank=1; request.Rank=1;
            restricted=sixgr.phy.mimo.CSIReportConfiguration(request,0);
            localReject(@()restricted.decode(received.Part1.Bits,received.Part2.Bits), ...
                'sixgr:mimo:InvalidCSIPart1Length');
        end
    end
end
ok=true; disp('CSI_RECEIVED_RANK_AUTHORITY_PASS');
end

function localReject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingError','Expected %s.',id);
end
