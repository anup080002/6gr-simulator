function actualPath = exportFigureArtifact(figHandle, filePath, varargin)
%EXPORTFIGUREARTIFACT Export a figure to the active sink or the filesystem.

filePath = char(string(filePath));
[exportArgs, logicalPath] = localParseOptions(filePath, varargin{:});
[~, ~, ext] = fileparts(filePath);
if strlength(string(ext)) == 0
    ext = ".png";
    filePath = char(string(filePath) + ".png");
end
% Runtime visual evidence is persisted as raster imagery.  Preserve support
% for legacy callers that still request an SVG name, but redirect the actual
% and logical artifacts to PNG instead of emitting a second vector copy.
if lower(string(ext)) == ".svg"
    ext = ".png";
    filePath = char(localPathWithExtension(filePath, ext));
    logicalPath = localPathWithExtension(logicalPath, ext);
end
gate = sixgr.visual.checkVisualArtifactRenderGate(filePath);
if isstruct(gate) && isfield(gate, "Matched") && logical(gate.Matched)
    if ~logical(gate.AllowRender)
        localDeleteIfExists(filePath);
        localDeleteIfExists(char(string(gate.UnavailablePath)));
        actualPath = '';
        return;
    elseif string(gate.VisualValidity) == "diagnostic_only"
        sixgr.visual.addDiagnosticWarningBanner(figHandle, gate.WarningBannerText);
    end
end

if sixgr.db.isArtifactStoreActive()
    tmpPath = char(string(tempname) + string(ext));
    cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>
    localExportGraphics(figHandle, tmpPath, string(ext), exportArgs{:});
    localRequireValidRaster(tmpPath, string(ext));
    [tmpPath, logicalPath, artifactKind, mimeType] = localNormalizeExportedVisualFile(tmpPath, logicalPath);
    sixgr.db.captureFileArtifact(tmpPath, artifactKind, mimeType, true, logicalPath);
    actualPath = char(logicalPath);
    return;
end

sixgr.util.ensureDir(filePath);
[targetFolder, ~, ~] = fileparts(filePath);
if isempty(targetFolder)
    targetFolder = pwd;
end
stagingPath = char(string(tempname(targetFolder)) + string(ext));
cleanupStage = onCleanup(@() localDeleteIfExists(stagingPath)); %#ok<NASGU>
localExportGraphics(figHandle, stagingPath, string(ext), exportArgs{:});
localRequireValidRaster(stagingPath, string(ext));
[moveOk, moveMessage] = movefile(stagingPath, filePath, "f");
if ~moveOk
    error("sixgr:visual:RasterPublishFailed", ...
        "Validated raster staging file could not be published to %s: %s", ...
        string(filePath), string(moveMessage));
end
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
if ~any(lower(string(ext)) == [".png", ".jpg", ".jpeg"])
    error("sixgr:visual:UnsupportedRasterFormat", ...
        "Figure artifacts must be persisted as PNG or JPEG, not %s.", string(ext));
end
resolution = 150;
if mod(numel(varargin), 2) ~= 0
    error("sixgr:visual:InvalidRasterExportOptions", ...
        "Raster export options must be supplied as name-value pairs.");
end
for optionIndex = 1:2:numel(varargin)
    optionName = lower(strtrim(string(varargin{optionIndex})));
    switch optionName
        case "resolution"
            resolution = double(varargin{optionIndex + 1});
        otherwise
            error("sixgr:visual:UnsupportedRasterExportOption", ...
                "The bounded raster backend does not support option '%s'.", ...
                char(optionName));
    end
end
if ~(isscalar(resolution) && isfinite(resolution) && ...
        resolution >= 72 && resolution <= 1200)
    error("sixgr:visual:InvalidRasterResolution", ...
        "Raster export resolution must be a finite scalar in [72, 1200] dpi.");
end

% exportgraphics relies on the WebWindow graphics handshake on Windows.
% Long LLS runs can complete every PHY trial and then hang indefinitely in
% that handshake while rendering the first post-run figure. The classic
% print pipeline is synchronous, headless-safe in MATLAB -batch, and emits
% the same required PNG/JPEG raster evidence without an SVG fallback.
switch lower(string(ext))
    case ".png"
        device = "-dpng";
    otherwise
        device = "-djpeg95";
end
% Some headless Windows graphics warnings are routed through an asynchronous
% console stream.  If the launching client has already closed that stream,
% warning() itself throws iolib:badbit before print can finish.  Suppress
% console warnings only for this bounded call and validate the raster bytes
% immediately afterwards; an absent or corrupt image still fails closed.
warningState = warning("off", "all");
cleanupWarning = onCleanup(@() warning(warningState)); %#ok<NASGU>
print(figHandle, filePath, char(device), ...
    sprintf("-r%d", round(resolution)));
end

function localRequireValidRaster(filePath, ext)
info = sixgr.visual.inspectVisualArtifactFile(filePath);
expectedMime = "image/png";
if any(lower(string(ext)) == [".jpg", ".jpeg"])
    expectedMime = "image/jpeg";
end
if ~logical(info.exists) || string(info.actual_mime_type) ~= expectedMime || ...
        ~logical(info.extension_mime_match) || double(info.byte_count) <= 0
    error("sixgr:visual:RasterExportInvalid", ...
        "Raster export %s is missing or invalid (expected=%s actual=%s bytes=%g status=%s).", ...
        string(filePath), expectedMime, string(info.actual_mime_type), ...
        double(info.byte_count), string(info.signature_status));
end
try
    imageInfo = imfinfo(filePath);
catch ME
    error("sixgr:visual:RasterExportUnreadable", ...
        "Raster export %s could not be decoded: %s", string(filePath), string(ME.message));
end
if isempty(imageInfo) || double(imageInfo(1).Width) <= 0 || double(imageInfo(1).Height) <= 0
    error("sixgr:visual:RasterExportEmptyDimensions", ...
        "Raster export %s has invalid pixel dimensions.", string(filePath));
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
