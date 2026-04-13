function exportFigureArtifact(figHandle, filePath, varargin)
%EXPORTFIGUREARTIFACT Export a figure to the active sink or the filesystem.

filePath = char(string(filePath));

if sixgr.db.isArtifactStoreActive()
    tmpPath = char(string(tempname) + ".png");
    cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>
    exportgraphics(figHandle, tmpPath, varargin{:});
    sixgr.db.captureFileArtifact(tmpPath, "image_png", "image/png", true, filePath);
    return;
end

sixgr.util.ensureDir(filePath);
exportgraphics(figHandle, filePath, varargin{:});
end

function localDeleteIfExists(filePath)
try
    if exist(filePath, "file") == 2
        warnState = warning("off", "all");
        cleanupWarn = onCleanup(@() warning(warnState)); %#ok<NASGU>
        delete(filePath);
    end
catch
end
end
