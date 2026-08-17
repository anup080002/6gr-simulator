function writeUnavailablePlotCard(filePath, plotTitle, message)
%WRITEUNAVAILABLEPLOTCARD Suppress unavailable visuals without fake raster evidence.
%
% Kept as a compatibility entry point for existing callers.  An unavailable
% measurement is represented by plot_manifest/plot_suppression CSV rows, not
% by a PNG containing prose.  Delete both possible raster names so a stale
% image from an earlier finalization cannot be mistaken for current evidence.
% plotTitle and message intentionally remain accepted for API compatibility;
% their values are persisted by the caller's suppression-status table.
normalPath = string(filePath);
unavailablePath = sixgr.visual.unavailableArtifactPath(normalPath);
if endsWith(lower(normalPath), "_unavailable.png")
    unavailablePath = normalPath;
    [folder, name] = fileparts(char(normalPath));
    name = regexprep(name, "_unavailable$", "");
    normalPath = string(fullfile(folder, name + ".png"));
end
localDeleteIfPresent(normalPath);
localDeleteIfPresent(unavailablePath);
end

function localDeleteIfPresent(pathValue)
if isfile(pathValue)
    delete(pathValue);
end
end
