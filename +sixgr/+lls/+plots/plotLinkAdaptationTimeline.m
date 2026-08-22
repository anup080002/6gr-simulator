function path = plotLinkAdaptationTimeline(trialCSVPath, outputFolder, link)
%PLOTLINKADAPTATIONTIMELINE Render causal CQI/ILLA/OLLA evidence from CSV.

arguments
    trialCSVPath (1,1) string
    outputFolder (1,1) string
    link (1,1) string = "PDSCH"
end

if exist(trialCSVPath,"file") ~= 2
    error("sixgr:lls:MissingLinkAdaptationCSV", ...
        "Persisted link-adaptation trial CSV is missing: %s",trialCSVPath);
end
T = readtable(trialCSVPath,"VariableNamingRule","preserve","TextType","string");
required = ["TrialIndex","PostEqSINRdB","LinkAdaptationEffectiveSINRdB", ...
    "LinkAdaptationSelectedCQI","MCSIndex","CRCError", ...
    "OLLAOffsetDbApplied","OLLAFeedbackACK", ...
    "LinkAdaptationForcedWaveformProbe"];
if isempty(T) || ~all(ismember(required,string(T.Properties.VariableNames)))
    error("sixgr:lls:InvalidLinkAdaptationCSV", ...
        "Persisted link-adaptation CSV lacks required runtime columns.");
end

% TrialIndex intentionally restarts at one for every independently seeded
% SNR point.  Use persisted row order on the horizontal axis so a
% multi-point diagnostic cannot draw unrelated trials on top of each other.
x = (1:height(T)).';
postEq = double(T.PostEqSINRdB);
effective = double(T.LinkAdaptationEffectiveSINRdB);
cqi = double(T.LinkAdaptationSelectedCQI);
mcs = double(T.MCSIndex);
olla = double(T.OLLAOffsetDbApplied);
ollaFeedbackACK = double(T.OLLAFeedbackACK);
probe = logical(T.LinkAdaptationForcedWaveformProbe);

path = fullfile(outputFolder,"link_adaptation_cqi_mcs_olla_timeline.png");
fig = figure("Visible","off","Color","white","Position",[100 100 1200 900]);
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,3,1,"TileSpacing","compact","Padding","compact");
title(layout,upper(link) + " causal CQI / ILLA / OLLA runtime evidence", ...
    "Color",[0.08 0.12 0.2],"FontWeight","bold");

ax1 = nexttile(layout);
plot(ax1,x,postEq,"o-","LineWidth",1.5,"DisplayName","receiver post-EQ SINR");
hold(ax1,"on");
plot(ax1,x,effective,"s--","LineWidth",1.3,"DisplayName","OLLA-adjusted CQI input");
localProbeMarkers(ax1,x,postEq,probe);
localPointBoundaries(ax1,T,x);
ylabel(ax1,"SINR (dB)");
title(ax1,"Measured receiver feedback and OLLA-adjusted inner-loop input");
legend(ax1,"Location","best");
localAxes(ax1);

ax2 = nexttile(layout);
yyaxis(ax2,"left");
hCQI = plot(ax2,x,cqi,"o-","LineWidth",1.5,"DisplayName","selected CQI");
ylabel(ax2,"CQI index (0–15)");
ylim(ax2,[-0.5 15.5]);
yyaxis(ax2,"right");
hMCS = stairs(ax2,x,mcs,"s-","LineWidth",1.5,"DisplayName","executed MCS");
ylabel(ax2,"MCS index");
title(ax2,"Inner-loop CQI-to-MCS decision from delayed receiver feedback");
localPointBoundaries(ax2,T,x);
localAxes(ax2);
if any(probe)
    hold(ax2,"on");
    hProbe = scatter(ax2,x(probe),mcs(probe),70,[0.85 0.18 0.16],"filled", ...
        "DisplayName","diagnostic probe—not scheduler eligible");
    legend(ax2,[hCQI hMCS hProbe],"Location","best");
else
    legend(ax2,[hCQI hMCS],"Location","best");
end

ax3 = nexttile(layout);
stairs(ax3,x,olla,"o-","LineWidth",1.5,"DisplayName","OLLA offset");
hold(ax3,"on");
ackRows = isfinite(ollaFeedbackACK) & ollaFeedbackACK == 1;
nackRows = isfinite(ollaFeedbackACK) & ollaFeedbackACK == 0;
scatter(ax3,x(ackRows),olla(ackRows),36,[0.08 0.55 0.35],"filled", ...
    "DisplayName","decoded ACK");
scatter(ax3,x(nackRows),olla(nackRows),55,[0.85 0.18 0.16],"x", ...
    "LineWidth",1.8,"DisplayName","decoded NACK");
xlabel(ax3,"Persisted runtime row (SNR points and local TB trials in order)");
ylabel(ax3,"OLLA offset (dB)");
title(ax3,"Outer-loop state applied when delayed decoded ACK/NACK arrives");
localPointBoundaries(ax3,T,x);
legend(ax3,"Location","best");
localAxes(ax3);

exportgraphics(fig,path,"Resolution",160);
end

function localPointBoundaries(ax,T,x)
if ~ismember("SNRIndex",string(T.Properties.VariableNames)) || height(T) < 1
    return;
end
snrIndex = double(T.SNRIndex);
starts = [1;find(diff(snrIndex) ~= 0)+1];
for k = 2:numel(starts)
    xline(ax,x(starts(k))-0.5,":","Color",[0.35 0.4 0.5], ...
        "HandleVisibility","off");
end
if ismember("TargetSNRdB",string(T.Properties.VariableNames))
    yLimits = ylim(ax);
    for k = 1:numel(starts)
        text(ax,x(starts(k)),yLimits(2), ...
            compose("  SNR %.1f dB",double(T.TargetSNRdB(starts(k)))), ...
            "VerticalAlignment","top","Color",[0.25 0.3 0.4], ...
            "FontSize",8,"Clipping","on");
    end
end
end

function localProbeMarkers(ax,x,y,probe)
if any(probe)
    scatter(ax,x(probe),y(probe),70,[0.85 0.18 0.16],"filled", ...
        "DisplayName","diagnostic CQI-0 waveform probe");
end
end

function localAxes(ax)
grid(ax,"on");
set(ax,"Color","white","XColor",[0.1 0.1 0.1],"YColor",[0.1 0.1 0.1], ...
    "GridColor",[0.65 0.68 0.72],"MinorGridColor",[0.8 0.82 0.85]);
ax.Title.Color = [0.08 0.12 0.2];
end
