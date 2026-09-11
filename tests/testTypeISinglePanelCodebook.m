function ok=testTypeISinglePanelCodebook()
% Independent implementation comparison on explicit analytic H fixtures.
% These are codebook/codec tests, NOT an over-the-air or main-run claim.
setup6GRSimToolkit('Verbose',false);
assert(string(version('-release'))=="2026a");
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
tuples=[2 1 4;2 2 7;4 1 7;3 2 10;6 1 10;4 2 12;8 1 12; ...
    4 3 14;6 2 14;12 1 14;4 4 17;8 2 17;16 1 17]; % Normative panel tuples and CSI-RS rows
matrixCount=0;
for tuple=tuples.'
    n1=tuple(1); n2=tuple(2); ports=2*n1*n2;
    csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',tuple(3), ...
        'Density','one','SymbolLocations',3,'SubcarrierLocations',[0 2 4], ...
        'NumRB',carrier.NSizeGrid);
    % Row-specific frequency-domain allocation, as configured by nrCSIRSConfig.
    if ports==4, csirs.SubcarrierLocations=0; end
    if ports==8, csirs.SubcarrierLocations=[0 2]; end
    if ismember(ports,[16 32]), csirs.SubcarrierLocations=[0 2 4 6]; end
    if ismember(ports,[24 32]), csirs.SymbolLocations=[3 9]; end
    assert(csirs.NumCSIRSPorts==ports);
    H=complex(zeros(12*carrier.NSizeGrid,carrier.SymbolsPerSlot,2,ports));
    for port=1:ports
        H(:,:,1,port)=exp(1i*.31*port)/sqrt(ports);
        H(:,:,2,port)=exp(-1i*.77*port)/sqrt(ports);
    end
    for mode=[1 2]
        for rank=[1 2]
            request=struct('ProfileID',"fr1_typeI_single_panel_strict", ...
                'Direction',"DL",'CodebookType',"typeI-SinglePanel", ...
                'Ports',ports,'Panels',1,'N1',n1,'N2',n2,'O1',4,'O2',1+3*(n2>1), ...
                'Rank',rank,'CodebookMode',mode,'MaxRank',2, ...
                'ReportConfigID',"codebook_fixture",'Epoch',0, ...
                'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',1, ...
                'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
            reference=nrCSIReportConfig('NSizeBWP',carrier.NSizeGrid, ...
                'CodebookType','type1SinglePanel','PanelDimensions',[1 n1 n2], ...
                'CodebookMode',mode,'PMIFormatIndicator','wideband');
            [~,referenceInfo]=nr5g.internal.nrPMIReport(carrier,csirs,reference,rank,H,.1);
            expected=reshape(referenceInfo.Codebook,ports,rank,[]);
            actual=sixgr.phy.mimo.CodebookEngine.enumerate(request);
            assert(isequal(size(actual.Matrices),size(expected)));
            assert(max(abs(actual.Matrices(:)-expected(:)))<1e-12, ...
                'Every candidate must match the independent R2026a matrix, not merely its power.');
            assert(all(abs(actual.FrobeniusPower-1)<1e-12));
            assert(all(actual.OrthogonalityError<1e-12));
            assert(isequal(actual.CandidateIndices,(0:size(expected,3)-1).'));
            matrixCount=matrixCount+size(expected,3);
            cfg=struct();
            cfg=sixgr.util.structSet(cfg,'phy.mimo',struct('strict',true, ...
                'profileID',request.ProfileID,'panels',1,'N1',n1,'N2',n2,'O1',4,'O2',request.O2));
            cfg=sixgr.util.structSet(cfg,'phy.csi.reportConfiguration',request);
            candidates=sixgr.phy.dl.pmiCodebookCandidates(cfg,rank,ports,'Mode','type1_su_mimo');
            assert(isequal(cat(3,candidates.W),actual.Matrices));
            chosen=actual.CandidateIndices(end);
            [W,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,chosen);
            values.RI=rank; values.CQI_CW0=11; values.CRI=0; values.LI=rank-1;
            tx=sixgr.phy.mimo.CSIReportConfiguration(request,0);
            payload=tx.build(values); received=tx.encodeDecodeNoNoise(payload);
            assert(received.CRCPassed && received.Part1BitErrors+received.Part2BitErrors==0);
            request.Rank=3-rank; % stale prior scalar rank at receiving end
            rx=sixgr.phy.mimo.CSIReportConfiguration(request,0);
            decoded=rx.decode(received.Part1.Bits,received.Part2.Bits);
            assert(decoded.PMI==chosen && decoded.RI==rank);
            request.Rank=decoded.RI;
            restored=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,decoded.PMI);
            assert(norm(W-restored,'fro')==0);
            localReject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,.5),'sixgr:mimo:InvalidPMI');
            bad=request; bad.O2=2;
            localReject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.layout(bad),'sixgr:mimo:UnsupportedAntennaTuple');
            missing=rmfield(values,'PMI_I11');
            localReject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.linearIndex(request,missing), ...
                'sixgr:mimo:MissingCSIReportMeasurement');
            % Restriction IDs remain in the original PMI domain.
            restricted=request;
            restricted.CodebookSubsetRestriction=ones(1,n1*4*n2*request.O2);
            restricted.CodebookSubsetRestriction(1)=0;
            subset=sixgr.phy.mimo.CodebookEngine.enumerate(restricted);
            assert(~any(subset.CandidateIndices==0) && subset.CandidateIndices(1)>0);
            localReject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(restricted,0),'sixgr:mimo:RestrictedPMI');
            fprintf('TYPEI_PANEL_PASS ports=%d N1=%d N2=%d mode=%d rank=%d matrices=%d\n', ...
                ports,n1,n2,mode,rank,size(expected,3));
        end
    end
end
ok=true; fprintf('TYPEI_SINGLE_PANEL_MATRIX_AND_RECEIVED_PMI_PASS matrices=%d\n',matrixCount);
end

function localReject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingError','Expected %s.',id);
end
