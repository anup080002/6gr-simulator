function actualPath = exportFigureArtifact(figHandle, filePath, varargin)
%EXPORTFIGUREARTIFACT Export a figure to the active sink or the filesystem.

filePath = char(string(filePath));
[exportArgs, logicalPath] = localParseOptions(filePath, varargin{:});
[~, ~, ext] = fileparts(filePath);
if strlength(string(ext)) == 0
    ext = ".png";
    filePath = char(string(filePath) + ".png");
end
gate = sixgr.visual.checkVisualArtifactRenderGate(filePath);
if isstruct(gate) && isfield(gate, "Matched") && logical(gate.Matched)
    if ~logical(gate.AllowRender)
        localDeleteIfExists(filePath);
        sixgr.visual.writeUnavailablePlotCard(string(gate.UnavailablePath), string(gate.PlotId), ...
            "Plot suppressed by visual artifact contract: " + string(gate.SuppressionReason));
        actualPath = char(string(gate.UnavailablePath));
        return;
    elseif string(gate.VisualValidity) == "diagnostic_only"
        sixgr.visual.addDiagnosticWarningBanner(figHandle, gate.WarningBannerText);
    end
end

if sixgr.db.isArtifactStoreActive()
    tmpPath = char(string(tempname) + string(ext));
    cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>
    localExportGraphics(figHandle, tmpPath, string(ext), exportArgs{:});
    [tmpPath, logicalPath, artifactKind, mimeType] = localNormalizeExportedVisualFile(tmpPath, logicalPath);
    sixgr.db.captureFileArtifact(tmpPath, artifactKind, mimeType, true, logicalPath);
    actualPath = char(logicalPath);
    return;
end

sixgr.util.ensureDir(filePath);
localExportGraphics(figHandle, filePath, string(ext), exportArgs{:});
[actualPath, ~, ~, ~] = localNormalizeExportedVisualFile(filePath, filePath);
end

function [exportArgs, logicalPath] = localParseOptions(defaultLogicalPath, varargin)
logicalPath = string(defaultLogicalPath);
exportArgs = {};
i = 1;
while i <= numel(varargin)
    if i < numel(varargin) && strcmpi(string(varargin{i}), "LogicalPath")
        logicalPath = string(varargin{i + 1});
        i = i + 2;
    else
        exportArgs(end + 1) = varargin(i); %#ok<AGROW>
        i = i + 1;
    end
end
end

function [filePath, logicalPath, artifactKind, mimeType] = localNormalizeExportedVisualFile(filePath, logicalPath)
info = sixgr.visual.inspectVisualArtifactFile(filePath);
mimeType = string(info.actual_mime_type);
if mimeType == "missing" || mimeType == "unknown"
    mimeType = string(info.declared_mime_type);
end
expectedExt = string(info.expected_extension);
if strlength(expectedExt) > 0
    filePath = localMoveToExtension(filePath, expectedExt);
    logicalPath = localPathWithExtension(logicalPath, expectedExt);
end
artifactKind = localImageArtifactKindFromMime(mimeType);
end

function artifactKind = localImageArtifactKindFromMime(mimeType)
switch lower(string(mimeType))
    case "image/svg+xml"
        artifactKind = "image_svg";
    case "image/jpeg"
        artifactKind = "image_jpeg";
    case "application/pdf"
        artifactKind = "document_pdf";
    otherwise
        artifactKind = "image_png";
end
end

function out = localMoveToExtension(filePath, ext)
filePath = string(filePath);
[folder, name, currentExt] = fileparts(char(filePath));
if lower(string(currentExt)) == lower(string(ext))
    out = char(filePath);
    return;
end
target = string(fullfile(folder, name + string(ext)));
if exist(target, "file") == 2
    localDeleteIfExists(target);
end
movefile(char(filePath), char(target), "f");
out = char(target);
end

function out = localPathWithExtension(filePath, ext)
[folder, name] = fileparts(char(string(filePath)));
out = string(fullfile(folder, name + string(ext)));
end

function localExportGraphics(figHandle, filePath, ext, varargin)
if lower(string(ext)) == ".svg"
    print(figHandle, char(filePath), "-dsvg");
else
    exportgraphics(figHandle, filePath, varargin{:});
end
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
