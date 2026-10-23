function [rendered,summary,diagnostics,layout] = exportConstellationGroups(T,pathOut)
% One joint raster for every captured direction/SNR/modulation/MCS/layer.
% T is the same canonical sample table persisted in the report CSV.
[groups,summary,diagnostics]=sixgr.report.groupConstellationPlotSamples(T);
rendered=false; layout=table();
if isempty(groups), return; end
nCols=min(3,numel(groups)); nRows=ceil(numel(groups)/nCols);
labels=cell(numel(groups),1);
for k=1:numel(groups), labels{k}=localPanelLabels(summary(k,:),k); end
% Metadata is deliberately complete. Reserve space for it instead of
% allowing a long title to paint over the neighbouring cohort's title.
tileWidth=560;
tileHeight=max(430,240+14*max(cellfun(@numel,labels)));
fig=figure('Visible','off','Color','w','Units','pixels', ...
    'Position',[50 50 tileWidth*nCols tileHeight*nRows+60]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
tl=tiledlayout(fig,nRows,nCols,'Padding','loose','TileSpacing','loose');
title(tl,'Equalized constellations — all finite paired samples; source scopes kept separate','Interpreter','none');
axesHandles=gobjects(numel(groups),1); titleHandles=gobjects(numel(groups),1);
for k=1:numel(groups)
    G=groups{k}; s=summary(k,:); ax=nexttile(tl); hold(ax,'on');
    axesHandles(k)=ax;
    receiverLabel='Raw receiver equalized symbols';
    if startsWith(s.PlottedIQSource,"legacy_")
        receiverLabel='Legacy canonical equalized (not verified raw)';
    end
    scatter(ax,double(G.(s.PlottedRealColumn)),double(G.(s.PlottedImagColumn)),8,'filled', ...
        'MarkerFaceAlpha',0.35,'DisplayName',receiverLabel);
    names=string(G.Properties.VariableNames);
    for pair={ ["HardDecisionReal","HardDecisionImag"], ["DecisionReal","DecisionImag"] }
        fields=pair{1};
        if all(ismember(fields,names))
            finite=isfinite(double(G.(fields(1)))) & isfinite(double(G.(fields(2))));
            if any(finite)
                scatter(ax,double(G.(fields(1))(finite)),double(G.(fields(2))(finite)), ...
                    12,'x','DisplayName','Hard decision');
            end
            break;
        end
    end
    scatter(ax,double(G.reference_symbol_i),double(G.reference_symbol_q), ...
        10,'+','DisplayName','TX reference');
    ideal=localSquareAlphabet(s.Modulation);
    if ~isempty(ideal)
        scatter(ax,real(ideal),imag(ideal),24,'kd','LineWidth',0.8, ...
            'DisplayName','Unit-power alphabet');
        for axisName=["I","Q"]
            if axisName=="I", levels=unique(real(ideal)); else, levels=unique(imag(ideal)); end
            mids=(levels(1:end-1)+levels(2:end))/2;
            for v=mids.'
                if axisName=="I"
                    xline(ax,v,':','Color',[.7 .7 .7],'HandleVisibility','off');
                else
                    yline(ax,v,':','Color',[.7 .7 .7],'HandleVisibility','off');
                end
            end
        end
    end
    titleHandles(k)=title(ax,labels{k},'Interpreter','none','FontSize',9, ...
        'FontName',get(groot,'FixedWidthFontName'));
    xlabel(ax,'I'); ylabel(ax,'Q'); axis(ax,'equal'); grid(ax,'on');
    legend(ax,'Location','southoutside','NumColumns',2,'FontSize',8);
end
sixgr.util.exportFigureArtifact(fig,pathOut,'Resolution',160);
drawnow;
% Retain measured graphics geometry for regression checks. This is display
% metadata, not a measurement or a modification of the plotted population.
layout=table((1:numel(groups)).',ceil((1:numel(groups)).'/nCols), ...
    zeros(numel(groups),1),zeros(numel(groups),1), ...
    zeros(numel(groups),1),zeros(numel(groups),1), ...
    'VariableNames',{'GroupIndex','PanelRow','TitleLeftPixels','TitleRightPixels', ...
    'TitleBottomPixels','TitleTopPixels'});
for k=1:numel(groups)
    set(titleHandles(k),'Units','pixels');
    bounds=get(titleHandles(k),'Extent'); origin=getpixelposition(axesHandles(k),true);
    layout.TitleLeftPixels(k)=origin(1)+bounds(1);
    layout.TitleRightPixels(k)=layout.TitleLeftPixels(k)+bounds(3);
    layout.TitleBottomPixels(k)=origin(2)+bounds(2);
    layout.TitleTopPixels(k)=layout.TitleBottomPixels(k)+bounds(4);
end
rendered=true;
end

function lines=localPanelLabels(s,index)
% Wrap display text only. Full typed grouping identity remains in summary,
% and no identifiers, native positions or samples are changed/truncated.
text=["Group "+string(index)+" | plotted pairs "+string(s.CapturedSampleCount)+" / source rows "+string(s.SourceRowCount); ...
    "I/Q source: "+s.PlottedIQSource; ...
    "Capture scope: "+s.CaptureScope+" | coordinate domain: "+s.SymbolCoordinateDomain; ...
    string(sprintf('Plotted-pair EVM %.3g%% (%.3g dB)',s.CaptureEVM_pct,s.CaptureEVM_dB)); ...
    s.PopulationStatus+" | rejected rows: "+string(s.RejectedSampleCount); ...
    s.GroupLabel];
if strlength(s.RejectionReason)>0, text(end+1)=s.RejectionReason; end
lines=strings(0,1); width=54;
for row=reshape(text,1,[])
    chars=char(row);
    for first=1:width:numel(chars)
        lines(end+1,1)=string(chars(first:min(first+width-1,numel(chars)))); %#ok<AGROW>
    end
end
end

function points=localSquareAlphabet(modulation)
% Explicit unit-average-power alphabets only; no guessed alphabet for an
% unsupported modulation and no fitted gain/phase from the received cloud.
token=upper(strtrim(string(modulation))); points=[];
if token=="BPSK", points=[-1;1]; return; end
if token=="QPSK"
    order=4;
else
    part=regexp(char(token),'^(\d+)QAM$','tokens','once');
    if isempty(part), return; end
    order=str2double(part{1});
end
side=sqrt(order);
if ~isfinite(side) || side<2 || side~=fix(side), return; end
levels=(-(side-1):2:(side-1)).';
[i,q]=meshgrid(levels,levels);
points=complex(i(:),q(:)); points=points/sqrt(mean(abs(points).^2));
end
