function path = plotThroughput(summaryTable, outputFolder, link)
%PLOTTHROUGHPUT Save successful-information-bit throughput as PNG.

if nargin < 3
    link = "PUSCH";
end
link = upper(string(link));

path = fullfile(outputFolder, "throughput_vs_snr.png");
fig = figure("Visible", "off", "Color", "white", "Position", [100 100 960 620]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
plot(ax, summaryTable.SNRdB, summaryTable.ThroughputBps/1e6, "s-", ...
    "LineWidth", 1.8, "MarkerSize", 7);
grid on;
xlabel("Configured E_s/N_0 (dB)");
ylabel("Successful information throughput (Mbit/s)");
title(link + " first-transmission throughput");
set(ax, "Color", "white", "XColor", [0.1 0.1 0.1], "YColor", [0.1 0.1 0.1], ...
    "GridColor", [0.55 0.55 0.55], "MinorGridColor", [0.75 0.75 0.75]);
ax.Title.Color = [0.1 0.1 0.1];
ax.XLabel.Color = [0.1 0.1 0.1];
ax.YLabel.Color = [0.1 0.1 0.1];
exportgraphics(fig, path, "Resolution", 160);
end
