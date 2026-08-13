function exportRasterAtomic(figureHandle,filePath,resolutionDPI)
%EXPORTRASTERATOMIC Render locally, validate, then publish a raster image.
%
% MATLAB graphics export can block when it renders directly into a folder
% managed by a filesystem synchronization provider.  Keep renderer I/O in
% the local temporary directory and publish the completed bitmap through a
% same-directory staging file.  This also prevents readers from observing a
% partially written image.

arguments
    figureHandle (1,1)
    filePath (1,1) string
    resolutionDPI (1,1) double {mustBeFinite,mustBePositive}
end

if ~isgraphics(figureHandle,"figure")
    error("sixgr:visual:InvalidFigureHandle", ...
        "Raster export requires a valid MATLAB figure handle.");
end

[destinationFolder,~,extension] = fileparts(filePath);
extension = lower(string(extension));
if ~ismember(extension,[".png",".jpg",".jpeg"])
    error("sixgr:visual:UnsupportedRasterFormat", ...
        "Raster export supports PNG and JPEG only, not '%s'.",extension);
end
sixgr.util.ensureFolder(char(destinationFolder));

token = string(char(java.util.UUID.randomUUID()));
localPath = string(fullfile(tempdir,"sixgr-raster-"+token+extension));
stagingPath = string(fullfile(destinationFolder, ...
    ".sixgr-raster-"+token+extension));
cleanup = onCleanup(@() localCleanup([localPath;stagingPath])); %#ok<NASGU>

try
    exportgraphics(figureHandle,char(localPath),"Resolution",resolutionDPI);
catch exportError
    try
        if extension == ".png"
            device = "-dpng";
        else
            device = "-djpeg";
        end
        print(figureHandle,char(localPath),char(device), ...
            "-r"+string(round(resolutionDPI)));
    catch printError
        combined = addCause(printError,exportError);
        error("sixgr:visual:RasterRenderFailed", ...
            "Unable to render raster image '%s': %s",filePath,combined.message);
    end
end

localValidateBitmap(localPath);
localCopyWithRetry(localPath,stagingPath);
localMoveWithRetry(stagingPath,filePath);
localValidateBitmap(filePath);
end

function localValidateBitmap(path)
if exist(path,"file") ~= 2
    error("sixgr:visual:RasterRenderMissing", ...
        "Raster renderer did not create '%s'.",path);
end
info = dir(path);
if isempty(info) || info.bytes == 0
    error("sixgr:visual:RasterRenderEmpty", ...
        "Raster renderer created an empty image '%s'.",path);
end
try
    metadata = imfinfo(path);
catch cause
    error("sixgr:visual:RasterRenderInvalid", ...
        "Raster renderer created an unreadable image '%s': %s", ...
        path,cause.message);
end
if isempty(metadata) || metadata(1).Width < 1 || metadata(1).Height < 1
    error("sixgr:visual:RasterRenderInvalid", ...
        "Raster image '%s' has invalid dimensions.",path);
end
end

function localCopyWithRetry(source,destination)
lastMessage = "";
for attempt = 1:5
    [ok,message] = copyfile(char(source),char(destination),"f");
    if ok
        return;
    end
    lastMessage = string(message);
    pause(0.10*attempt);
end
error("sixgr:visual:RasterStageFailed", ...
    "Unable to stage raster '%s': %s",destination,lastMessage);
end

function localMoveWithRetry(source,destination)
lastMessage = "";
for attempt = 1:5
    [ok,message] = movefile(char(source),char(destination),"f");
    if ok
        return;
    end
    lastMessage = string(message);
    pause(0.10*attempt);
end
error("sixgr:visual:RasterPublishFailed", ...
    "Unable to publish raster '%s': %s",destination,lastMessage);
end

function localCleanup(paths)
for path = paths(:).'
    if exist(path,"file") == 2
        delete(path);
    end
end
end
