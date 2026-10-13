function [rendered,summary] = exportConstellationGroups(T,pathOut)
% One joint raster for every captured direction/SNR/modulation/MCS/layer.
% T is the same canonical sample table persisted in the report CSV.
[groups,summary]=sixgr.report.groupConstellationPlotSamples(T);
rendered=false;
if isempty(groups), return; end
nCols=min(3,numel(groups)); nRows=ceil(numel(groups)/nCols);
fig=figure('Visible','off','Color','w','Units','pixels', ...
    'Position',[50 50 420*nCols 390*nRows+60]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
tl=tiledlayout(fig,nRows,nCols,'Padding','loose','TileSpacing','loose');
title(tl,'Equalized constellations — all captured groups','Interpreter','none');
for k=1:numel(groups)
    G=groups{k}; s=summary(k,:); ax=nexttile(tl); hold(ax,'on');
    scatter(ax,double(G.equalized_i),double(G.equalized_q),8,'filled', ...
        'MarkerFaceAlpha',0.35,'DisplayName','Equalized capture');
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
    label=[string(sprintf('%s | %s | layer %g | MCS %g', ...
        s.Direction,s.Modulation,s.Layer,s.MCS)); ...
        string(sprintf('Configured SNR %g dB | N=%d',s.ConfiguredSNR_dB,s.CapturedSampleCount)); ...
        string(sprintf('Capture EVM %.3g%% (%.3g dB)',s.CaptureEVM_pct,s.CaptureEVM_dB))];
    if ismember('ue_id',names)
        label(1)=label(1)+" | UE "+string(G.ue_id(1));
    end
    title(ax,label,'Interpreter','none','FontSize',9);
    xlabel(ax,'I'); ylabel(ax,'Q'); axis(ax,'equal'); grid(ax,'on');
    legend(ax,'Location','southoutside','NumColumns',2,'FontSize',8);
end
sixgr.util.exportFigureArtifact(fig,pathOut,'Resolution',160);
rendered=true;
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
