function artifacts=exportPDCCHChannelEstimates(runFolder,T,renderImages)
%EXPORTPDCCHCHANNELESTIMATES All retained candidate REs, labelled previews.
% Each preview is one actual occasion; never average different SNRs, UEs,
% slots, candidates or ports to synthesize a channel response.
artifacts=struct('CSVPath',"",'ImagePaths',strings(0,1),'Rows',height(T));
if isempty(T), return; end
required=["SubcarrierIndex0","SymbolIndex0","RxPortIndex0","ReferencePortIndex0", ...
    "HReal","HImag","Magnitude","Phase_rad","ReceiverAccepted","CandidateIndex", ...
    "ChannelEstimateSource","ChannelEstimateMethod","AbsoluteSlot0", ...
    "UEIndex","ServingCell","SNR_dB","ObservationStartSample","ObservationEndSampleExclusive","GrantDirection"];
assert(all(ismember(required,string(T.Properties.VariableNames))), ...
    'sixgr:report:IncompletePDCCHChannelEvidence','Missing receiver capture identity.');
h=complex(double(T.HReal),double(T.HImag));
assert(all(isfinite(h)) && all(abs(abs(h)-double(T.Magnitude))<=1e-12*max(1,abs(h))) && ...
    all(abs(angle(exp(1i*(angle(h)-double(T.Phase_rad)))))<1e-12), ...
    'sixgr:report:InvalidPDCCHChannelEvidence','Magnitude/phase must derive from retained complex estimates.');
layout=sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);
path=fullfile(layout.ControlCSVDir,'pdcch_channel_estimates.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
artifacts.CSVPath=string(path);
if ~renderImages, return; end
sixgr.util.ensureFolder(layout.ControlImageDir);
scopeFields={'SNR_dB','UEIndex','ServingCell','GrantDirection'};
scopes=unique(T(:,scopeFields),'rows','stable');
lineage=cell(height(scopes),1);
for k=1:height(scopes)
    selected=T.SNR_dB==scopes.SNR_dB(k) & T.UEIndex==scopes.UEIndex(k) & ...
        T.ServingCell==scopes.ServingCell(k) & string(T.GrantDirection)==string(scopes.GrantDirection(k));
    t=T(selected,:);
    % This bounded preview is explicitly the latest retained observation.
    % The CSV above contains every retained observation, including failures.
    start=max(t.ObservationStartSample);
    t=t(t.ObservationStartSample==start,:);
    stop=max(t.ObservationEndSampleExclusive);
    t=t(t.ObservationEndSampleExclusive==stop,:);
    assert(numel(unique(t.CandidateIndex))==1 && numel(unique(t.AbsoluteSlot0))==1, ...
        'sixgr:report:AmbiguousPDCCHChannelPreview','Do not mix receiver hypotheses in one preview.');
    ports=unique(t(:,{'RxPortIndex0','ReferencePortIndex0'}),'rows','stable');
    fig=figure('Visible','off','Color','white','Position',[50 50 1300 max(650,300*height(ports))]);
    cleanup=onCleanup(@()close(fig));
    tiled=tiledlayout(fig,height(ports),2,'TileSpacing','compact');
    for p=1:height(ports)
        pt=t(t.RxPortIndex0==ports.RxPortIndex0(p) & t.ReferencePortIndex0==ports.ReferencePortIndex0(p),:);
        for column=1:2
            ax=nexttile(tiled); hold(ax,'on');
            for symbol=reshape(unique(pt.SymbolIndex0),1,[])
                st=sortrows(pt(pt.SymbolIndex0==symbol,:),'SubcarrierIndex0');
                if column==1, y=st.Magnitude; else, y=st.Phase_rad; end
                plot(ax,st.SubcarrierIndex0,y,'.-','DisplayName',"symbol "+string(symbol));
            end
            xlabel(ax,'Subcarrier index (zero-based)');
            if column==1, ylabel(ax,'|Hest|'); else, ylabel(ax,'Phase (rad)'); end
            title(ax,sprintf('RX dimension %d / reference-port dimension %d', ...
                ports.RxPortIndex0(p),ports.ReferencePortIndex0(p)),'Interpreter','none');
            set(ax,'Color','white','XColor','black','YColor','black'); grid(ax,'on');
            legend(ax,'Location','best','TextColor','black','Color','white');
        end
    end
    title(tiled,sprintf('PDCCH measured Hest: %g dB configured, UE %g, slot0 %g, accepted=%d\nLatest retained occasion preview; all occasions in CSV', ...
        scopes.SNR_dB(k),scopes.UEIndex(k),t.AbsoluteSlot0(1),all(t.ReceiverAccepted)), ...
        'Interpreter','none','Color','black');
    token=replace(string(scopes.SNR_dB(k)),["-","."],["m","p"]);
    filename="pdcch_channel_estimate_snr_"+token+"_ue_"+string(scopes.UEIndex(k))+ ...
        "_cell_"+string(scopes.ServingCell(k))+"_"+lower(string(scopes.GrantDirection(k)))+".png";
    imagePath=fullfile(layout.ControlImageDir,filename);
    sixgr.util.exportFigureArtifact(fig,imagePath,'Resolution',120);
    artifacts.ImagePaths(end+1,1)=string(imagePath); %#ok<AGROW>
    lineage{k}=table(filename,string(path),scopes.SNR_dB(k),scopes.UEIndex(k), ...
        scopes.ServingCell(k),string(scopes.GrantDirection(k)),t.AbsoluteSlot0(1), ...
        start,stop,t.CandidateIndex(1),height(t),"latest_retained_observation_no_averaging", ...
        'VariableNames',{'ImageFile','SourceCSV','SNR_dB','UEIndex','ServingCell', ...
        'GrantDirection','AbsoluteSlot0','ObservationStartSample','ObservationEndSampleExclusive','CandidateIndex', ...
        'SourceRows','SelectionRule'});
    clear cleanup;
end
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir,'pdcch_channel_estimate_plot_lineage.csv'), ...
    vertcat(lineage{:}),'PreserveSchema',true);
end
