function actualPath = writeFlowDiagramPNG(filePath, titleText, labels, ok)
%WRITEFLOWDIAGRAMPNG Render an informative flow diagram as a raster PNG.

% This helper is for explanatory pipeline figures.  It does not invent PHY
% measurements: every label and status must be supplied by the caller from
% its persisted execution result.

filePath = string(filePath);
[folder, name] = fileparts(char(filePath));
filePath = string(fullfile(folder, string(name) + ".png"));
labels = reshape(string(labels), 1, []);
if isempty(labels)
    labels = "No runtime stages supplied";
end

fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1120 430]);
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig, "Position", [0.04 0.12 0.92 0.74]);
hold(ax, "on");
axis(ax, [0 1 0 1]);
axis(ax, "off");

n = numel(labels);
gap = min(0.035, 0.16 / max(n - 1, 1));
boxWidth = min(0.21, (0.92 - gap * max(n - 1, 0)) / n);
totalWidth = n * boxWidth + max(n - 1, 0) * gap;
startX = (1 - totalWidth) / 2;
boxY = 0.34;
boxHeight = 0.32;
fillColor = [0.90 0.97 0.96];
edgeColor = [0.03 0.48 0.44];
for i = 1:n
    x = startX + (i - 1) * (boxWidth + gap);
    rectangle(ax, "Position", [x boxY boxWidth boxHeight], ...
        "Curvature", 0.10, "FaceColor", fillColor, "EdgeColor", edgeColor, "LineWidth", 1.5);
    text(ax, x + boxWidth / 2, boxY + boxHeight / 2, labels(i), ...
        "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
        "FontSize", 10, "FontWeight", "bold", "Interpreter", "none");
    if i < n
        arrowStart = x + boxWidth + 0.006;
        arrowLength = max(gap - 0.012, 0.008);
        quiver(ax, arrowStart, boxY + boxHeight / 2, arrowLength, 0, 0, ...
            "Color", [0.20 0.30 0.32], "LineWidth", 1.4, "MaxHeadSize", 0.8);
    end
end

title(ax, string(titleText), "FontSize", 16, "FontWeight", "bold", "Interpreter", "none");
if logical(ok)
    statusText = "STRICT STATUS: PASS";
    statusColor = [0.05 0.50 0.28];
else
    statusText = "STRICT STATUS: FAIL";
    statusColor = [0.72 0.16 0.13];
end
text(ax, 0.5, 0.12, statusText, "HorizontalAlignment", "center", ...
    "FontSize", 12, "FontWeight", "bold", "Color", statusColor, "Interpreter", "none");

actualPath = string(sixgr.util.exportFigureArtifact(fig, filePath, "Resolution", 170));
end
