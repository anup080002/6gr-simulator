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
coordinates=["SubcarrierIndex0","SymbolIndex0","RxPortIndex0", ...
    "ReferencePortIndex0","AbsoluteSlot0","ObservationStartSample", ...
    "ObservationEndSampleExclusive","CandidateIndex"];
values=T{:,cellstr(coordinates)};
assert(isnumeric(values) && isreal(values) && ...
    all(isfinite(values) & values>=0 & values==fix(values),'all') && ...
    all(T.ObservationEndSampleExclusive>T.ObservationStartSample) && ...
    all(isfinite(T.SNR_dB)) && all(isfinite(T.UEIndex) & T.UEIndex>=1 & T.UEIndex==fix(T.UEIndex)) && ...
    all(isfinite(T.ServingCell) & T.ServingCell>=1 & T.ServingCell==fix(T.ServingCell)), ...
    'sixgr:report:IncompletePDCCHChannelEvidence','Invalid receiver capture coordinates or scope.');
if ismember('TrialIndex',T.Properties.VariableNames)
    assert(all(isfinite(T.TrialIndex) & T.TrialIndex>=1 & T.TrialIndex==fix(T.TrialIndex)), ...
        'sixgr:report:IncompletePDCCHChannelEvidence','Invalid independent trial identity.');
end
h=complex(double(T.HReal),double(T.HImag));
assert(all(isfinite(h)) && all(abs(abs(h)-double(T.Magnitude))<=1e-12*max(1,abs(h))) && ...
    all(abs(angle(exp(1i*(angle(h)-double(T.Phase_rad)))))<1e-12), ...
    'sixgr:report:InvalidPDCCHChannelEvidence','Magnitude/phase must derive from retained complex estimates.');
layout=sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);
path=fullfile(layout.ControlCSVDir,'pdcch_channel_estimates.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'RoundTripNumericText',true);
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
    trialIndex=NaN; % Shared captures need only their absolute receive clock.
    % Independent component captures can repeat the same physical local
    % clock. Keep their trial identity instead of joining their RE samples.
    if ismember('TrialIndex',t.Properties.VariableNames)
        trialIndex=max(t.TrialIndex);
        t=t(t.TrialIndex==trialIndex,:);
    end
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
        start,stop,t.CandidateIndex(1),trialIndex,height(t),"latest_retained_observation_no_averaging", ...
        'VariableNames',{'ImageFile','SourceCSV','SNR_dB','UEIndex','ServingCell', ...
        'GrantDirection','AbsoluteSlot0','ObservationStartSample','ObservationEndSampleExclusive','CandidateIndex','TrialIndex', ...
        'SourceRows','SelectionRule'});
    clear cleanup;
end
lineagePath=fullfile(layout.ControlCSVDir,'pdcch_channel_estimate_plot_lineage.csv');
context=vertcat(lineage{:});
% Retain the exact selection context above and the standard cryptographic
% lineage consumed by MATLAB/Python audits. A bare ImageFile is not enough.
bound=sixgr.visual.writeComponentPlotLineage(runFolder,lineagePath, ...
    erase(context.ImageFile,'.png'),artifacts.ImagePaths, ...
    repmat(string(path),height(context),1), ...
    'sixgr.report.exportPDCCHChannelEstimates','SourcesAlreadyFinalized',true);
for name=string(bound.Properties.VariableNames)
    context.(name)=bound.(name);
end
sixgr.util.csvWriteTable(lineagePath,context,'PreserveSchema',true);
end
