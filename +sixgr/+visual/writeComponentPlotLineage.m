function T = writeComponentPlotLineage(runFolder, lineagePath, plotIds, imagePaths, sourceCSVs, producerModule)
%WRITECOMPONENTPLOTLINEAGE Persist exact image-to-source lineage for component plots.

runFolder = char(string(runFolder));
lineagePath = char(string(lineagePath));
plotIds = string(plotIds(:));
imagePaths = string(imagePaths(:));
sourceCSVs = string(sourceCSVs(:));
producerModule = string(producerModule);

n = numel(plotIds);
if numel(imagePaths) ~= n || numel(sourceCSVs) ~= n
    error("sixgr:visual:ComponentPlotLineageSizeMismatch", ...
        "Plot ids, image paths, and source CSV specifications must have equal lengths.");
end
if ~localInsideRun(lineagePath, runFolder)
    error("sixgr:visual:ComponentPlotLineageOutsideRun", ...
        "Component plot lineage path must remain inside the run root: %s", lineagePath);
end

% Final artifact sanitization must not invalidate a hash written here.
% Normalize only the explicitly declared source CSVs before measuring their
% bytes.  This does not alter populated evidence values; it removes only
% structurally blank columns and applies the canonical live-table schema.
sourceSpecs = strings(n, 1);
sourcePaths = strings(0, 1);
for i = 1:n
    sourceSpecs(i) = localNormalizeSourceSpec(sourceCSVs(i), runFolder);
    sourcePaths = [sourcePaths; localAbsoluteSourcePaths(sourceSpecs(i), runFolder)]; %#ok<AGROW>
end
if ~isempty(sourcePaths)
    sixgr.truth.sanitizeLLSArtifactCSVs(runFolder, ...
        "OnlyPaths", unique(sourcePaths, "stable"));
end

rows = repmat(localEmptyRow(), n, 1);
for i = 1:n
    imagePath = char(imagePaths(i));
    sourceSpec = sourceSpecs(i);
    imageRelative = localRelativePath(imagePath, runFolder);
    imageExists = exist(imagePath, "file") == 2;
    [sourceExists, sourceHashes] = localSourceEvidence(sourceSpec, runFolder);
    [widthPx, heightPx, mimeType] = localImageInfo(imagePath);
    imageHash = localFileSHA256(imagePath);
    failureReason = "";
    status = "pass";
    if ~imageExists
        status = "fail";
        failureReason = "image_missing";
    elseif strlength(sourceSpec) == 0
        status = "fail";
        failureReason = "source_csv_missing_from_lineage";
    elseif ~sourceExists
        status = "fail";
        failureReason = "source_csv_file_missing";
    elseif ~any(mimeType == ["image/png", "image/jpeg"])
        status = "fail";
        failureReason = "unsupported_persisted_visual_format";
    end
    rows(i) = struct( ...
        "PlotId", plotIds(i), ...
        "ImagePath", imageRelative, ...
        "SourceCSV", sourceSpec, ...
        "SourceCSV_SHA256", sourceHashes, ...
        "ImageSHA256", imageHash, ...
        "Width", widthPx, ...
        "Height", heightPx, ...
        "MimeType", mimeType, ...
        "ImageExists", imageExists, ...
        "SourceExists", sourceExists, ...
        "ProducerModule", producerModule, ...
        "Status", status, ...
        "FailureReason", failureReason);
end
T = struct2table(rows, "AsArray", true);
sixgr.util.csvWriteTable(lineagePath, T);
end

function paths = localAbsoluteSourcePaths(sourceSpec, runFolder)
parts = split(string(sourceSpec), "|");
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
paths = strings(numel(parts), 1);
for i = 1:numel(parts)
    paths(i) = string(fullfile(runFolder, ...
        strrep(char(parts(i)), "/", filesep)));
end
end

function row = localEmptyRow()
row = struct( ...
    "PlotId", "", ...
    "ImagePath", "", ...
    "SourceCSV", "", ...
    "SourceCSV_SHA256", "", ...
    "ImageSHA256", "", ...
    "Width", NaN, ...
    "Height", NaN, ...
    "MimeType", "", ...
    "ImageExists", false, ...
    "SourceExists", false, ...
    "ProducerModule", "", ...
    "Status", "not_evaluated", ...
    "FailureReason", "");
end

function sourceSpec = localNormalizeSourceSpec(value, runFolder)
parts = split(strtrim(string(value)), "|");
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
for i = 1:numel(parts)
    pathValue = char(parts(i));
    if localLooksAbsolute(pathValue)
        if ~localInsideRun(pathValue, runFolder)
            error("sixgr:visual:ComponentPlotSourceOutsideRun", ...
                "Component plot source must remain inside the run root: %s", pathValue);
        end
        parts(i) = localRelativePath(pathValue, runFolder);
    else
        parts(i) = localPortable(parts(i));
    end
end
sourceSpec = strjoin(parts, "|");
end

function [existsOk, hashes] = localSourceEvidence(sourceSpec, runFolder)
parts = split(string(sourceSpec), "|");
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
existsOk = ~isempty(parts);
hashValues = strings(numel(parts), 1);
for i = 1:numel(parts)
    pathValue = fullfile(runFolder, strrep(char(parts(i)), "/", filesep));
    existsOk = existsOk && exist(pathValue, "file") == 2;
    hashValues(i) = localFileSHA256(pathValue);
end
hashes = strjoin(hashValues, "|");
end

function [widthPx, heightPx, mimeType] = localImageInfo(pathValue)
widthPx = NaN;
heightPx = NaN;
mimeType = "";
if exist(pathValue, "file") ~= 2
    return;
end
[~, ~, ext] = fileparts(pathValue);
switch lower(string(ext))
    case ".png"
        mimeType = "image/png";
    case {".jpg", ".jpeg"}
        mimeType = "image/jpeg";
    otherwise
        mimeType = "application/octet-stream";
end
try
    info = imfinfo(pathValue);
    widthPx = double(info.Width);
    heightPx = double(info.Height);
catch
end
end

function hash = localFileSHA256(pathValue)
hash = "";
if exist(pathValue, "file") ~= 2
    return;
end
fid = fopen(pathValue, "r");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, "*uint8");
hash = string(sixgr.util.sha256Hex(uint8(bytes(:))));
end

function tf = localInsideRun(pathValue, runFolder)
pathValue = localCanonical(pathValue);
runFolder = localCanonical(runFolder);
tf = strcmpi(pathValue, runFolder) || startsWith(pathValue, runFolder + filesep, "IgnoreCase", true);
end

function value = localCanonical(pathValue)
value = string(char(java.io.File(char(string(pathValue))).getCanonicalPath()));
end

function rel = localRelativePath(pathValue, runFolder)
pathValue = localCanonical(pathValue);
runFolder = localCanonical(runFolder);
if strcmpi(pathValue, runFolder)
    rel = "";
else
    rel = extractAfter(pathValue, strlength(runFolder) + 1);
end
rel = localPortable(rel);
end

function tf = localLooksAbsolute(pathValue)
pathValue = char(string(pathValue));
tf = ~isempty(regexp(pathValue, '^[A-Za-z]:[\\/]', 'once')) || ...
    startsWith(string(pathValue), "\\\\") || startsWith(string(pathValue), "/");
end

function value = localPortable(pathValue)
value = replace(string(pathValue), "\", "/");
while startsWith(value, "./")
    value = extractAfter(value, 2);
end
end
