function path = plotLinkAdaptationOperatingPoints(summaryCSVPath,outputFolder,link)
%PLOTLINKADAPTATIONOPERATINGPOINTS Plot runtime CQI/ILLA/OLLA reductions.

arguments
    summaryCSVPath (1,1) string
    outputFolder (1,1) string
    link (1,1) string = "PDSCH"
end
if exist(summaryCSVPath,"file") ~= 2
    error("sixgr:lls:MissingLinkAdaptationSummaryCSV", ...
        "Persisted link-adaptation operating-point CSV is missing: %s", ...
        summaryCSVPath);
end
T = readtable(summaryCSVPath,"VariableNamingRule","preserve","TextType","string");
required = ["SNRdB","PostDelayBLER","PostDelayBLERLowerCI", ...
    "PostDelayBLERUpperCI","TargetBLER","MinimumCQI","MeanCQI", ...
    "MaximumCQI","MinimumMCSIndex","MeanMCSIndex","MaximumMCSIndex", ...
    "OLLAFinalOffsetDb","OLLAUpdateCount","RuntimeTrials", ...
    "ExecutionBackend","ApproximationMode"];
if isempty(T) || ~all(ismember(required,string(T.Properties.VariableNames)))
    error("sixgr:lls:InvalidLinkAdaptationSummaryCSV", ...
        "Persisted link-adaptation summary lacks required runtime columns.");
end
if any(T.ExecutionBackend ~= "waveform_truth") || any(T.ApproximationMode ~= "none")
    error("sixgr:lls:NonTruthLinkAdaptationPlotInput", ...
        "Link-adaptation plots accept waveform-truth runtime reductions only.");
end

[snr,order] = sort(double(T.SNRdB));
T = T(order,:);
bler = double(T.PostDelayBLER);
lower = double(T.PostDelayBLERLowerCI);
upperCI = double(T.PostDelayBLERUpperCI);
target = double(T.TargetBLER);

path = fullfile(outputFolder,"link_adaptation_operating_points.png");
fig = figure("Visible","off","Color","white","Position",[100 100 1200 850]);
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
title(layout,upper(link) + " causal link-adaptation operating points", ...
    "Color",[0.08 0.12 0.2],"FontWeight","bold");

ax1 = nexttile(layout);
errorbar(ax1,snr,bler,bler-lower,upperCI-bler,"o-","LineWidth",1.5, ...
    "MarkerFaceColor",[0.05 0.47 0.44],"DisplayName","decoded TB BLER");
hold(ax1,"on");
plot(ax1,snr,target,"r--","LineWidth",1.2,"DisplayName","OLLA target BLER");
xlabel(ax1,"Applied AWGN Es/N0 (dB)"); ylabel(ax1,"Post-delay BLER");
ylim(ax1,[0 1]); title(ax1,"Decoded CRC reliability with Wilson intervals");
legend(ax1,"Location","best"); localAxes(ax1);

ax2 = nexttile(layout);
errorbar(ax2,snr,double(T.MeanCQI), ...
    double(T.MeanCQI)-double(T.MinimumCQI), ...
    double(T.MaximumCQI)-double(T.MeanCQI), ...
    "o-","LineWidth",1.5,"MarkerFaceColor",[0.2 0.45 0.8]);
xlabel(ax2,"Applied AWGN Es/N0 (dB)"); ylabel(ax2,"CQI index");
ylim(ax2,[-0.5 15.5]); title(ax2,"Delayed receiver CQI: mean and observed range");
localAxes(ax2);

ax3 = nexttile(layout);
errorbar(ax3,snr,double(T.MeanMCSIndex), ...
    double(T.MeanMCSIndex)-double(T.MinimumMCSIndex), ...
    double(T.MaximumMCSIndex)-double(T.MeanMCSIndex), ...
    "o-","LineWidth",1.5,"MarkerFaceColor",[0.55 0.3 0.75]);
xlabel(ax3,"Applied AWGN Es/N0 (dB)"); ylabel(ax3,"Executed MCS index");
title(ax3,"Inner-loop selected MCS: mean and observed range");
localAxes(ax3);

ax4 = nexttile(layout);
yyaxis(ax4,"left");
plot(ax4,snr,double(T.OLLAFinalOffsetDb),"o-","LineWidth",1.5, ...
    "DisplayName","final OLLA offset");
ylabel(ax4,"Final OLLA offset (dB)");
yyaxis(ax4,"right");
plot(ax4,snr,double(T.OLLAUpdateCount),"s--","LineWidth",1.5, ...
    "DisplayName","decoded feedback updates");
ylabel(ax4,"OLLA updates"); xlabel(ax4,"Applied AWGN Es/N0 (dB)");
title(ax4,"Outer-loop state from delayed decoded ACK/NACK");
localAxes(ax4);

exportgraphics(fig,path,"Resolution",160);
end

function localAxes(ax)
grid(ax,"on");
set(ax,"Color","white","XColor",[0.1 0.1 0.1],"YColor",[0.1 0.1 0.1], ...
    "GridColor",[0.65 0.68 0.72],"MinorGridColor",[0.8 0.82 0.85]);
ax.Title.Color = [0.08 0.12 0.2];
end
