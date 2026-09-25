function ok=testPDCCHArtifactSourceBinding(retainedFolder)
% Test values/identity, not just PNG size or a minimum point count.
arguments
    retainedFolder (1,1) string = ""
end
root=fileparts(fileparts(mfilename('fullpath')));
out=fullfile(root,'results','lls','pdcch_artifact_repair', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(out);
t=table([3;8;12;19],[0;2;1;3],[4;5;7;8],[1;1;2;2], ...
    repmat("SSB",4,1),'VariableNames', ...
    {'AbsoluteSlot','TCIStateID','BeamID','QCLSourceID','QCLSourceType'});
name="pdcch_beam_monitoring_timeline.png";
source="pdcch_beam_monitoring.csv";
fig=figure('Visible','off'); c=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig);
sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{t});
for field=["TCIStateID","BeamID","QCLSourceID"]
    label=field;
    if field=="QCLSourceID", label=field+" / SSB"; end
    h=findobj(ax,'DisplayName',label);
    assert(numel(h)==1 && isequal(h.XData(:),t.AbsoluteSlot) && isequal(h.YData(:),t.(field)));
end
% Same row count, different source values: a count-only sine generator fails.
t.TCIStateID(2)=6; cla(ax);
sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{t});
h=findobj(ax,'DisplayName','TCIStateID'); assert(h.YData(2)==6);
localReject(@()sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{removevars(t,'BeamID')}), ...
    'sixgr:phy:pdcch:missing_plot_evidence');
bad=t; bad.TCIStateID(2)=NaN;
localReject(@()sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{bad}), ...
    'sixgr:phy:pdcch:invalid_plot_evidence');
localReject(@()sixgr.phy.pdcch.plotArtifactEvidence(ax,"unbound_physical_plot.png",source,{t}), ...
    'sixgr:phy:pdcch:missing_plot_binding');
contract=readtable(fullfile(root,'tests','vectors','pdcch','desired_pdcch_image_contract.csv'), ...
    'TextType','string','VariableNamingRule','preserve');
row=table2struct(contract(contract.ImageFile==name,:));
writetable(t,fullfile(out,source));
audit=sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure(out,row);
assert(audit.SeriesCount==3 && audit.FinitePointCount==12);
row.MinFinitePointCount=13;
localReject(@()sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure(out,row), ...
    'sixgr:phy:pdcch:incomplete_figure_semantics');
writetable(struct2table(audit),fullfile(out,'focused_plot_audit.csv'));
localMeasurementProducers(out,ax,contract);
fprintf('PDCCH_ARTIFACT_SOURCE_BINDING_PASS output=%s\n',out);
if strlength(retainedFolder)>0
    % Reanalysis is opt-in and isolated. Preserve original CSVs/PNGs/manifests.
    replay=fullfile(out,'retained_reanalysis'); mkdir(replay);
    names=strings(height(contract),1); status=names; details=names;
    for k=1:height(contract)
        names(k)=contract.ImageFile(k);
        try
            sources=split(contract.SourceCSV(k),'|');
            for s=reshape(sources,1,[])
                copyfile(fullfile(retainedFolder,s),fullfile(replay,s));
            end
            a=sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure(replay,table2struct(contract(k,:)));
            status(k)="RENDERED_FROM_RETAINED_CSV";
            details(k)=string(a.FinitePointCount)+" plotted points; not new PHY execution";
        catch ex
            status(k)="UNAVAILABLE";
            details(k)=string(ex.identifier)+": "+string(ex.message);
        end
        fprintf('PDCCH_REANALYSIS %s %s %s\n',names(k),status(k),details(k));
    end
    writetable(table(names,status,details,'VariableNames',{'ImageFile','Status','Detail'}), ...
        fullfile(replay,'reanalysis_status.csv'));
end
ok=true;
end
function localMeasurementProducers(out,ax,contract)
% Execute actual sequence measurements, not recreated historical metrics.
t=sixgr.phy.pdcch.buildDMRSArtifactEvidence("FOCUSED_COMPONENT");
for k=1:height(t)
    context=struct('NumerologyMu',t.NumerologyMu(k),'Slot',t.Slot(k), ...
        'Symbol',t.Symbol(k),'NID',t.NID(k),'CORESETRBs',t.CORESETRBs(k), ...
        'PrecoderGranularity',t.PrecoderGranularity(k),'AttemptedPRBs',0:t.CORESETRBs(k)-1);
    actual=sixgr.phy.pdcch.PDCCHDMRS.generate(context);
    e=sixgr.phy.pdcch.measureDMRSSequenceCorrelation(context,actual);
    assert(e.IndependentMismatchCount==0 && abs(e.MatchedReferenceCorrelation-1)<1e-12);
    assert(e.WrongNIDCorrelation<1 && e.WrongSymbolCorrelation<1);
    bad=actual; bad.SequenceSymbols(1)=-bad.SequenceSymbols(1);
    changed=sixgr.phy.pdcch.measureDMRSSequenceCorrelation(context,bad);
    assert(changed.IndependentMismatchCount==1 && changed.MatchedReferenceCorrelation<1);
    assert(e.MatchedReferenceCorrelation==t.MatchedReferenceCorrelation(k));
    assert(e.WrongNIDCorrelation==t.WrongNIDCorrelation(k));
    assert(e.WrongSymbolCorrelation==t.WrongSymbolCorrelation(k));
end
source="pdcch_dmrs_matrix.csv"; name="pdcch_dmrs_sequence_correlation.png";
writetable(t,fullfile(out,source)); cla(ax);
sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{t});
for field=["MatchedReferenceCorrelation","WrongNIDCorrelation","WrongSymbolCorrelation"]
    h=findobj(ax,'DisplayName',field+" (sequence component)");
    assert(isequal(h.XData(:),t.DMRSVectorIndex) && isequal(h.YData(:),t.(field)));
end
a=sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure(out, ...
    table2struct(contract(contract.ImageFile==name,:)));
assert(a.FinitePointCount==72);
t=sixgr.phy.pdcch.buildType0ArtifactEvidence("FOCUSED_COMPONENT");
assert(height(t)==48 && all(t.PDCCHSCSkHz==15) && all(t.MismatchCount==0));
% Table 13-11 index 1, odd SSB=1: M=1/2 does not mean half-slot spacing.
k=find(t.SearchSpaceZero==1 & t.SSBIndex==1);
assert(t.M(k)==0.5 && t.MonitoringSlots(k)=="0|20");
assert(t.MonitoringFirstSymbols(k)==join(repmat(string(t.CORESETSymbols(k)),1,2),'|'));
% Index 2: O=2, M=1, SSB=2 => n0=4, same parity again at 24.
k=find(t.SearchSpaceZero==2 & t.SSBIndex==2);
assert(t.MonitoringSlots(k)=="4|24");
source="pdcch_type0_css.csv"; name="pdcch_type0_css_timeline.png";
writetable(t,fullfile(out,source)); cla(ax);
sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{t});
lines=findobj(ax,'Type','line');
assert(numel(lines)==3 && sum(arrayfun(@(h)numel(h.XData),lines))==96);
for h=reshape(lines,1,[]), assert(all(h.XData==fix(h.XData))); end
bad=t; bad.MonitoringSlots(1)="0.5|20";
localReject(@()sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{bad}), ...
    'sixgr:phy:pdcch:invalid_plot_evidence');
sixgr.phy.pdcch.PDCCHArtifactExporter.writeSemanticFigure(out, ...
    table2struct(contract(contract.ImageFile==name,:)));
% A failed receiver trial is an observed outcome, not a missing identity.
t=table(["C-RNTI";"C-RNTI"],["C-RNTI";""],["1_0";"1_0"],[true;false], ...
    'VariableNames',{'RNTITypeTx','DecodedRNTIType','DCIFormatTx','Detected'});
cla(ax); source="pdcch_blind_trials.csv"; name="pdcch_rnti_confusion_matrix.png";
sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{t});
assert(any(string(ax.YTickLabel)=="Not detected"));
t.Detected(2)=true;
localReject(@()sixgr.phy.pdcch.plotArtifactEvidence(ax,name,source,{t}), ...
    'sixgr:phy:pdcch:missing_plot_evidence');
end
function localReject(f,id)
try, f(); catch ex, assert(strcmp(ex.identifier,id),'Unexpected error: %s',ex.message); return; end
error('test:PDCCHExpectedRejection','Expected %s',id);
end
