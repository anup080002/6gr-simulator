function path = plotBLER(summaryTable, outputFolder, link)
%PLOTBLER Save a raster-only BLER curve suitable for technical reports.

if nargin < 3
    link = "PUSCH";
end
link = upper(string(link));

path = fullfile(outputFolder, "bler_vs_snr.png");
fig = figure("Visible", "off", "Color", "white", "Position", [100 100 960 620]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
zeroError = summaryTable.NumBlockErrors == 0;
y = summaryTable.BLER;
% A zero observed error count has no positive ordinate on a logarithmic
% axis.  Plot its Wilson upper confidence limit explicitly; do not invent
% a nonzero empirical BLER.
y(zeroError) = summaryTable.BLERUpperCI(zeroError);
semilogy(ax, summaryTable.SNRdB, y, "o-", "LineWidth", 1.8, "MarkerSize", 7, ...
    "DisplayName", "empirical BLER / zero-error upper limit");
grid on;
xlabel("Configured E_s/N_0 (dB)");
ylabel("Transport-block error rate");
confidencePercent = 100*summaryTable.ConfidenceLevel(1);
title(compose("%s waveform BLER with %.3g%% Wilson confidence bounds", link, confidencePercent));
hold on;
if any(zeroError)
    semilogy(ax, summaryTable.SNRdB(zeroError), y(zeroError), "v", ...
        "LineStyle", "none", "MarkerSize", 9, "LineWidth", 1.5, ...
        "DisplayName", compose("zero errors: %.3g%% Wilson upper bound", confidencePercent));
end
for idx = 1:height(summaryTable)
    line([summaryTable.SNRdB(idx) summaryTable.SNRdB(idx)], ...
        [max(summaryTable.BLERLowerCI(idx), 1e-6) max(summaryTable.BLERUpperCI(idx), 1e-6)], ...
        "Color", [0.25 0.25 0.25], "LineWidth", 1, "HandleVisibility", "off");
end
ylim([max(1e-6, min(y(y>0))/2) 1]);
localLightAxes(ax);
legend(ax, "Location", "southwest", "TextColor", [0.1 0.1 0.1], "Color", "white");
exportgraphics(fig, path, "Resolution", 160);
end

function localLightAxes(ax)
set(ax, "Color", "white", "XColor", [0.1 0.1 0.1], "YColor", [0.1 0.1 0.1], ...
    "GridColor", [0.55 0.55 0.55], "MinorGridColor", [0.75 0.75 0.75]);
ax.Title.Color = [0.1 0.1 0.1];
ax.XLabel.Color = [0.1 0.1 0.1];
ax.YLabel.Color = [0.1 0.1 0.1];
end
