function ok=testNRMaxSEDecisionEvidence()
% Numerical selection-policy equivalence, not physical accuracy or BLER.
setup6GRSimToolkit('Verbose',false);
prior=rng; restore=onCleanup(@()rng(prior)); %#ok<NASGU>
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',5,'SubcarrierLocations',0,'NumRB',24);
report=nrCSIReportConfig('NSizeBWP',24,'CodebookType','type1SinglePanel', ...
    'PanelDimensions',[1 2 1],'CodebookMode',1, ...
    'CQIFormatIndicator','wideband','PMIFormatIndicator','wideband');
base=[1 .1 .04 .02;.03 .8 .1 .02;.02 .03 .5 .07;.01 .05 .03 .3];
H=repmat(reshape(complex(base),1,1,4,4),288,14,1,1);
cases=0;
for domain={1:4,[1 3],2}
    ranks=domain{1}; restriction=zeros(1,8); restriction(ranks)=1;
    report.RIRestriction=restriction;
    for disturbance={.01,.8,diag([.01 .02 .03 .04])}
        n=disturbance{1}; before=rng;
        [ri,e]=sixgr.phy.mimo.selectNRMaxSEWithEvidence(carrier,csirs,report,H,n,ranks);
        assert(isequal(before,rng));
        expected=nr5g.internal.nrRISelect(carrier,csirs,report,H,n,'MaxSE');
        assert(ri==expected && e.SelectedRank==ri && ...
            e.RankSearchCallCount==numel(ranks) && e.AdditionalRankSearches==0 && ...
            ~e.DecodedBLERAvailable && ~e.IndependentSelectionQualityVerified && ...
            ~e.StandardizedAccuracyQualified && ...
            e.ChannelSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(H));
        for k=1:numel(ranks)
            c=e.Candidates{k};
            [q,pm,ci,pi]=nr5g.internal.nrCQISelect(carrier,csirs,report,ranks(k),H,n);
            assert(isequaln(c.WidebandCQI,q(1,:)) && isequaln(c.RankSearchPMI,pm) && ...
                isequaln(c.ModelEstimatedTransportBLER,ci.TransportBLER(1,:)) && ...
                c.RankSearchPrecoderSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(pi.W));
            if any(q(1,:)==0)
                assert(c.Objective==0);
            else
                calculated=sum(c.CodewordLayerCounts.*(1-c.ModelEstimatedTransportBLER).*c.CQITableSpectralEfficiency);
                assert(abs(c.Objective-calculated)<=8*eps(max(1,abs(calculated))));
            end
            assert(isequaln(e.ObjectiveByRank(ranks(k)),c.Objective));
        end
        [best,selected]=max(e.ObjectiveByRank);
        assert(e.SelectedObjective==best && ri==selected);
        cases=cases+1;
    end
end
report.RIRestriction=[1 1 1 1 0 0 0 0];
[ri,e]=sixgr.phy.mimo.selectNRMaxSEWithEvidence(carrier,csirs,report,zeros(size(H)),1,1:4);
assert(ri==1 && all(e.ObjectiveByRank==0),'Preserve native zero-CQI first-rank tie.');
% Preserve the v167 positive table4 failure as an unsupported backend, not
% a repaired native feature. No replacement table or successful decision.
report.CQITable='table4-r17'; report.RIRestriction=[1 1 0 0 0 0 0 0];
blocked=false; before=rng;
try
    sixgr.phy.mimo.selectNRMaxSEWithEvidence(carrier,csirs,report,H,.01,[1 2]);
catch cause
    assert(strcmp(cause.identifier,'sixgr:mimo:NativeCQITableUnsupported'));
    blocked=true;
end
assert(blocked&&isequal(before,rng)&&string(report.CQITable)=="table4-r17");
for tableName=["table2","table3"]
    report.CQITable=tableName;
    [ri,e]=sixgr.phy.mimo.selectNRMaxSEWithEvidence(carrier,csirs,report,H,.01,[1 2]);
    expected=nr5g.internal.nrRISelect(carrier,csirs,report,H,.01,'MaxSE');
    assert(ri==expected&&string(e.Configuration.CQITable)==tableName);
    cases=cases+1;
end
% Original native restriction semantics include sorted/deduplicated and
% physically clipped ranks. Evidence retains the request separately.
report.CQITable='table1'; report.RIRestriction=[1 1 1 1 0 0 0 0];
[ri,e]=sixgr.phy.mimo.selectNRMaxSEWithEvidence(carrier,csirs,report,H(:,:,1:2,:),.01,[4 2 1 3 2]);
expected=nr5g.internal.nrRISelect(carrier,csirs,report,H(:,:,1:2,:),.01,'MaxSE');
assert(ri==expected && isequal(e.RankDomain,[1 2]) && ...
    isequal(e.RequestedRankDomain,[4 2 1 3 2]));
fprintf('MAXSE_ORIGINAL_DECISION_PASS cases=%d table4_explicitly_blocked=1 native_model_not_decoded_BLER=1\n',cases+2);
ok=true;
end
