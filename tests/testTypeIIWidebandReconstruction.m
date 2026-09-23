function ok=testTypeIIWidebandReconstruction()
% Normative algebra and independent toolbox comparisons on analytic H.
% This does not qualify CSI Part 1/2 wire coding or an integrated scenario.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
rng(38214223,'twister');
request=localRequest(2,1,1,2,4);
c=struct('Q1',0,'Q2',0,'BeamGroupIndex',0, ...
    'StrongestCoefficientIndices',0,'WidebandAmplitudeIndices',[7;0;0;0], ...
    'PhaseIndices',zeros(4,1));
[W,info]=sixgr.phy.mimo.TypeIICodebook.matrix(request,c);
assert(norm(W-[1;1;0;0]/sqrt(2))<1e-14 && ~info.WireLayoutQualified);
% Exercise every normative amplitude against a directly constructed vector.
for k=0:7
    c.WidebandAmplitudeIndices=[7;k;0;0];
    p=sqrt([0 1/64 1/32 1/16 1/8 1/4 1/2 1]); p=p(k+1);
    expected=[1+p;1-p;0;0]/sqrt(2*(1+p^2));
    W=sixgr.phy.mimo.TypeIICodebook.matrix(request,c);
    assert(norm(W-expected)<1e-14);
end
% Beam groups must obey the normative combinatorial index, not an arbitrary
% nchoosek ordering. Check all groups for L=2,3,4 on an eight-port panel.
for L=2:4
    request=localRequest(2,2,1,L,8);
    for group=0:nchoosek(4,L)-1
        c=localComponents(L,1,8); c.BeamGroupIndex=group;
        [~,info]=sixgr.phy.mimo.TypeIICodebook.matrix(request,c);
        recovered=0;
        for b=1:L
            x=4-1-info.BeamIndices(b); y=L-b+1;
            if x>=y, recovered=recovered+nchoosek(x,y); end
        end
        assert(recovered==group);
    end
end
% Malformed components and unsupported requests cannot silently select a
% smaller rank, default beam, invented coefficient or Type-I substitute.
request=localRequest(2,1,1,2,4); c=localComponents(2,1,4);
bad=c; bad.Q1=4; localReject(request,bad,'sixgr:mimo:InvalidPMI');
bad=c; bad.BeamGroupIndex=1; localReject(request,bad,'sixgr:mimo:InvalidPMI');
bad=c; bad.WidebandAmplitudeIndices(1)=6;
localReject(request,bad,'sixgr:mimo:InvalidTypeIICoefficients');
bad=c; bad.PhaseIndices(1)=1;
localReject(request,bad,'sixgr:mimo:InvalidTypeIICoefficients');
bad=c; bad.WidebandAmplitudeIndices(2)=0; bad.PhaseIndices(2)=1;
localReject(request,bad,'sixgr:mimo:InvalidTypeIICoefficients');
bad=c; bad.PhaseIndices(2)=NaN; localReject(request,bad,'sixgr:mimo:InvalidPMI');
for field=["Rank","NumberOfBeams","PhaseAlphabetSize"]
    bad=request; bad.(field)=3;
    localReject(bad,c,'sixgr:mimo:UnsupportedTypeIIProfile');
end
bad=request; bad.FrequencyGranularity="subband";
localReject(bad,c,'sixgr:mimo:UnsupportedTypeIIProfile');
bad=request; bad.CodebookSubsetRestriction=[1 0];
localReject(bad,c,'sixgr:mimo:UnsupportedTypeIIProfile');

assert(string(version('-release'))=="2026a",'Toolbox comparison is release-pinned.');
carrier=nrCarrierConfig('NSizeGrid',4,'SubcarrierSpacing',15);
cases=0; maxDifference=0;
for tuple=[2 1 2; 2 2 2; 2 2 3; 4 1 4].'
    n1=tuple(1); n2=tuple(2); L=tuple(3); ports=2*n1*n2;
    if ports==4, row=4; locations=0; else, row=7; locations=[0 2]; end
    csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',row,'Density','one', ...
        'SymbolLocations',3,'SubcarrierLocations',locations,'NumRB',4);
    measuredH=randn(2,ports)+1i*randn(2,ports);
    H=repmat(reshape(measuredH,1,1,2,ports),48,14,1,1);
    for rank=1:2
        for alphabet=[4 8]
            request=localRequest(n1,n2,rank,L,alphabet);
            reference=nrCSIReportConfig('NSizeBWP',4,'CodebookType','type2', ...
                'PanelDimensions',[1 n1 n2],'NumberOfBeams',L, ...
                'PhaseAlphabetSize',alphabet,'PMIFormatIndicator','wideband');
            [pmi,referenceInfo]=nr5g.internal.nrPMIReport(carrier,csirs,reference,rank,H,.1);
            components=sixgr.phy.mimo.TypeIICodebook.fromToolboxPMI(request,pmi);
            [W,info]=sixgr.phy.mimo.TypeIICodebook.matrix(request,components);
            difference=norm(W-referenceInfo.W,'fro');
            % R2026a uses rounded .1768/.3536/.7071 amplitude values.
            % The normalized-vector perturbation bound is 2*||delta||/||a||;
            % strongest coefficient is exactly one, so ||a||>=1.
            exact=sqrt([0 1/64 1/32 1/16 1/8 1/4 1/2 1]);
            rounded=[0 .125 .1768 .25 .3536 .5 .7071 1];
            bound=2*sqrt(2*L-1)*max(abs(exact-rounded))+1e-12;
            assert(difference<=bound,'Type-II reconstruction differs beyond known toolbox amplitude rounding: %.12g > %.12g.',difference,bound);
            assert(abs(sum(abs(W(:)).^2)-1)<1e-12);
            assert(all(abs(sum(abs(W).^2,1)-1/rank)<1e-12));
            assert(all(info.NonzeroCoefficientCount>=1));
            maxDifference=max(maxDifference,difference); cases=cases+1;
        end
    end
end
fprintf('TYPEII_WIDEBAND_RECONSTRUCTION_PASS toolbox_cases=%d max_matrix_difference=%.12g wire_qualified=0\n',cases,maxDifference);
ok=true;
end

function request=localRequest(n1,n2,rank,L,alphabet)
request=struct('CodebookType',"typeII",'FrequencyGranularity',"wideband", ...
    'Ports',2*n1*n2,'N1',n1,'N2',n2,'O1',4,'O2',1+3*(n2>1), ...
    'Rank',rank,'NumberOfBeams',L,'PhaseAlphabetSize',alphabet);
end

function c=localComponents(L,rank,alphabet)
c=struct('Q1',0,'Q2',0,'BeamGroupIndex',0, ...
    'StrongestCoefficientIndices',zeros(1,rank), ...
    'WidebandAmplitudeIndices',randi([1 7],2*L,rank), ...
    'PhaseIndices',randi([0 alphabet-1],2*L,rank));
c.WidebandAmplitudeIndices(1,:)=7; c.PhaseIndices(1,:)=0;
end

function localReject(request,components,identifier)
try
    sixgr.phy.mimo.TypeIICodebook.matrix(request,components);
catch ex
    assert(string(ex.identifier)==identifier,'Expected %s, got %s: %s',identifier,ex.identifier,ex.message);
    return;
end
error('test:ExpectedFailure','Malformed Type-II inputs were accepted.');
end
