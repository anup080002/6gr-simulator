function writeUnavailablePlotCard(filePath, plotTitle, message)
%WRITEUNAVAILABLEPLOTCARD Write an explicit unavailable PNG card.

filePath = sixgr.visual.unavailableArtifactPath(filePath);
outputFolder = fileparts(char(filePath));
sixgr.util.ensureFolder(outputFolder);
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

% Render beside the destination and publish with a replace operation.  A
% browser or OneDrive indexer can briefly hold an existing PNG open on
% Windows; printing directly to that path then fails before MATLAB has a
% complete replacement artifact.
temporaryToken = char(java.util.UUID.randomUUID());
temporaryPath = string(fullfile(outputFolder, ...
    "u" + string(temporaryToken(1:8)) + ".png"));
temporaryCleanup = onCleanup(@() localDeleteIfPresent(temporaryPath)); %#ok<NASGU>
try
    exportgraphics(fig, char(temporaryPath), "Resolution", 160);
catch
    print(fig, char(temporaryPath), "-dpng", "-r160");
end
localPublishWithRetry(temporaryPath, filePath);
end

function localPublishWithRetry(sourcePath, destinationPath)
lastMessage = "";
for attempt = 1:5
    [ok, message] = movefile(char(sourcePath), char(destinationPath), "f");
    if ok
        return;
    end
    lastMessage = string(message);
    if attempt < 5
        pause(0.10 * attempt);
    end
end
error("sixgr:visual:ArtifactPublishFailed", ...
    "Unable to publish unavailable plot card '%s': %s", ...
    char(destinationPath), char(lastMessage));
end

function localDeleteIfPresent(pathValue)
if isfile(pathValue)
    delete(pathValue);
end
end
