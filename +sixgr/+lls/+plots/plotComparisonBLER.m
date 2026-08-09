function path = plotComparisonBLER(summaryA,summaryB,outputFolder)
%PLOTCOMPARISONBLER Plot paired waveform BLER curves without inventing zeros.

path = fullfile(outputFolder,"paired_bler_comparison.png");
fig = figure("Visible","off","Color","white","Position",[100 100 960 620]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
yA = summaryA.BLER;
yB = summaryB.BLER;
yA(summaryA.NumBlockErrors == 0) = ...
    summaryA.BLERUpperCI(summaryA.NumBlockErrors == 0);
yB(summaryB.NumBlockErrors == 0) = ...
    summaryB.BLERUpperCI(summaryB.NumBlockErrors == 0);
semilogy(ax,summaryA.SNRdB,yA,"o-","LineWidth",1.8,"DisplayName","Baseline A");
hold(ax,"on");
semilogy(ax,summaryB.SNRdB,yB,"s-","LineWidth",1.8,"DisplayName","Candidate B");
grid(ax,"on");
xlabel(ax,"Configured E_s/N_0 (dB)");
ylabel(ax,"Transport-block error rate / zero-error upper limit");
title(ax,"Paired waveform-truth A/B comparison");
set(ax,"Color","white","XColor",[0.1 0.1 0.1],"YColor",[0.1 0.1 0.1], ...
    "GridColor",[0.55 0.55 0.55],"MinorGridColor",[0.75 0.75 0.75]);
ax.Title.Color = [0.1 0.1 0.1];
ax.XLabel.Color = [0.1 0.1 0.1];
ax.YLabel.Color = [0.1 0.1 0.1];
ylim(ax,[max(1e-6,min([yA(yA>0);yB(yB>0)])/2) 1]);
legend(ax,"Location","southwest","Color","white","TextColor",[0.1 0.1 0.1]);
exportgraphics(fig,path,"Resolution",160);
end
