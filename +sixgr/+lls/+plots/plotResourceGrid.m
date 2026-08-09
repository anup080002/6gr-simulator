function path = plotResourceGrid(diagnostic, outputFolder, link)
%PLOTRESOURCEGRID Plot actual mapped data/DM-RS/PT-RS RE classes as PNG.

if nargin < 3
    link = "PUSCH";
end
link = upper(string(link));

tx = diagnostic.Tx;
mask = zeros(size(tx.Grid,1), size(tx.Grid,2));
indices = sixgr.util.structGet(tx, "ResourceAccounting.Indices", struct());
if ~isempty(fieldnames(indices))
    dataIndices = sixgr.util.structGet(indices, "DataLinear", []);
    dmrsIndices = sixgr.util.structGet(indices, "DMRSLinear", []);
    ptrsIndices = sixgr.util.structGet(indices, "PTRSLinear", []);
    reservedIndices = sixgr.util.structGet(indices, "ReservedLinear", []);
else
    dataIndices = sixgr.util.structGet(tx, link + "Indices", []);
    dmrsIndices = sixgr.util.structGet(tx, "DMRSIndices", []);
    ptrsIndices = sixgr.util.structGet(tx, "PTRSIndices", []);
    reservedIndices = [];
end
mask(localBaseIndices(dataIndices, size(mask))) = 1;
mask(localBaseIndices(dmrsIndices, size(mask))) = 2;
mask(localBaseIndices(ptrsIndices, size(mask))) = 3;
mask(localBaseIndices(reservedIndices, size(mask))) = 4;
path = fullfile(outputFolder, lower(char(link)) + "_resource_grid.png");
fig = figure("Visible", "off", "Color", "white", "Position", [100 100 1100 620]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
imagesc(ax, 0:size(mask,2)-1, 0:size(mask,1)-1, mask);
axis xy;
xlabel("OFDM symbol (zero based)");
ylabel("Active subcarrier (zero based)");
title("Executed " + link + " resource grid: unused / data / DM-RS / PT-RS / reserved");
colormap([0.94 0.95 0.95; 0.10 0.48 0.72; 0.12 0.67 0.45; 0.65 0.31 0.78; 0.95 0.55 0.18]);
clim(ax, [-0.5 4.5]);
cb = colorbar;
cb.Ticks = 0:4;
cb.TickLabels = {"unused","data","DM-RS","PT-RS","reserved"};
cb.Color = [0.1 0.1 0.1];
set(ax, "Color", "white", "XColor", [0.1 0.1 0.1], "YColor", [0.1 0.1 0.1]);
ax.Title.Color = [0.1 0.1 0.1];
ax.XLabel.Color = [0.1 0.1 0.1];
ax.YLabel.Color = [0.1 0.1 0.1];
exportgraphics(fig, path, "Resolution", 160);
end

function idx = localBaseIndices(linear, gridSize)
linear = double(linear(:));
if isempty(linear)
    idx = zeros(0,1);
    return;
end
plane = prod(gridSize);
idx = mod(linear-1, plane)+1;
idx = unique(idx);
end
