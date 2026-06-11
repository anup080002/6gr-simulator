function writeUnavailablePlotCard(filePath, plotTitle, message)
%WRITEUNAVAILABLEPLOTCARD Write an explicit unavailable SVG card.

filePath = sixgr.visual.unavailableArtifactPath(filePath);
sixgr.util.ensureFolder(fileparts(char(filePath)));
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
axis(ax, "off");
text(ax, 0.5, 0.68, char(string(plotTitle)), ...
    "HorizontalAlignment", "center", "FontWeight", "bold", "FontSize", 12, "Interpreter", "none");
text(ax, 0.5, 0.50, "UNAVAILABLE", ...
    "HorizontalAlignment", "center", "FontWeight", "bold", "FontSize", 14, ...
    "Color", [0.55 0.20 0.05], "Interpreter", "none");
text(ax, 0.5, 0.34, char(string(message)), ...
    "HorizontalAlignment", "center", "FontSize", 10, "Interpreter", "none");
print(fig, char(filePath), "-dsvg");
end
