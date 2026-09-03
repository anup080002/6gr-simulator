function out = verifyContractPlotLineageSources(runFolder)
%VERIFYCONTRACTPLOTLINEAGESOURCES Verify exact persisted chart source bytes.

arguments
    runFolder (1,1) string
end

lineagePath = fullfile(runFolder, "reports", "csv", ...
    "contract_plot_lineage.csv");
rows = repmat(localEmptyRow(), 0, 1);
if exist(lineagePath, "file") ~= 2
    rows(end+1, 1) = localFailureRow("", "", "", "", ...
        "contract_plot_lineage_missing"); %#ok<AGROW>
    out = localBuildOutput(rows, lineagePath);
    return;
end

try
    lineage = readtable(lineagePath, "Delimiter", ",", ...
        "VariableNamingRule", "preserve", "TextType", "string");
catch ME
    rows(end+1, 1) = localFailureRow("", "", "", "", ...
        "contract_plot_lineage_unreadable:" + string(ME.identifier)); %#ok<AGROW>
    out = localBuildOutput(rows, lineagePath);
    return;
end

requiredColumns = ["PlotId","ImagePath","SourceCSV","SourceCSV_SHA256"];
if ~all(ismember(requiredColumns, string(lineage.Properties.VariableNames)))
    rows(end+1, 1) = localFailureRow("", "", "", "", ...
        "contract_plot_lineage_schema_invalid"); %#ok<AGROW>
    out = localBuildOutput(rows, lineagePath);
    return;
end
if isempty(lineage)
    if ~localRasterOutputEnabled(runFolder)
        % A YAML-disabled raster campaign has no scientific images to bind.
        % The header-only lineage receipt is therefore a truthful,
        % configuration-driven not-applicable result rather than missing
        % evidence.  Raster-enabled runs continue to fail closed below.
        out = localBuildOutput(rows, lineagePath, true);
    else
        rows(end+1, 1) = localFailureRow("", "", "", "", ...
            "contract_plot_lineage_empty_for_enabled_rasters"); %#ok<AGROW>
        out = localBuildOutput(rows, lineagePath);
    end
    return;
end

for rowIndex = 1:height(lineage)
    plotId = string(lineage.PlotId(rowIndex));
    imagePath = string(lineage.ImagePath(rowIndex));
    sourcePaths = split(string(lineage.SourceCSV(rowIndex)), "|");
    expectedHashes = lower(split(string( ...
        lineage.SourceCSV_SHA256(rowIndex)), "|"));
    sourcePaths = strtrim(sourcePaths(:));
    expectedHashes = strtrim(expectedHashes(:));
    if isempty(sourcePaths) || any(strlength(sourcePaths) == 0) || ...
            numel(sourcePaths) ~= numel(expectedHashes)
        rows(end+1, 1) = localFailureRow(plotId, imagePath, ...
            string(lineage.SourceCSV(rowIndex)), ...
            string(lineage.SourceCSV_SHA256(rowIndex)), ...
            "source_path_hash_cardinality_mismatch"); %#ok<AGROW>
        continue;
    end
    for sourceIndex = 1:numel(sourcePaths)
        relativePath = localPortableRelativePath(sourcePaths(sourceIndex));
        absolutePath = fullfile(runFolder, strrep(char(relativePath), ...
            "/", filesep));
        actualHash = "";
        failure = "";
        if exist(absolutePath, "file") ~= 2
            failure = "source_csv_missing";
        else
            actualHash = localFileSHA256(absolutePath);
            if strlength(expectedHashes(sourceIndex)) ~= 64
                failure = "source_hash_invalid";
            elseif actualHash ~= expectedHashes(sourceIndex)
                failure = "source_hash_mismatch";
            end
        end
        row = localEmptyRow();
        row.PlotId = plotId;
        row.ImagePath = imagePath;
        row.SourceCSV = relativePath;
        row.ExpectedSHA256 = expectedHashes(sourceIndex);
        row.ActualSHA256 = actualHash;
        row.SourceExists = exist(absolutePath, "file") == 2;
        row.HashMatches = strlength(failure) == 0;
        row.FailureCode = failure;
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
out = localBuildOutput(rows, lineagePath);
end

function out = localBuildOutput(rows, lineagePath, emptyIsPolicyDisabled)
if nargin < 3
    emptyIsPolicyDisabled = false;
end
if isempty(rows)
    details = struct2table(localEmptyRow());
    details(1, :) = [];
else
    details = struct2table(rows, "AsArray", true);
end
out = struct( ...
    "Ok", (logical(emptyIsPolicyDisabled) && isempty(details)) || ...
        (~isempty(details) && all(details.HashMatches)), ...
    "Applicable", ~logical(emptyIsPolicyDisabled), ...
    "Status", localStatus(emptyIsPolicyDisabled, details), ...
    "LineagePath", string(lineagePath), ...
    "SourceCount", double(height(details)), ...
    "FailureCount", double(sum(~details.HashMatches)), ...
    "Details", details);
end

function value = localStatus(emptyIsPolicyDisabled, details)
if logical(emptyIsPolicyDisabled) && isempty(details)
    value = "policy_disabled_by_resolved_yaml";
elseif isempty(details)
    value = "missing";
elseif all(details.HashMatches)
    value = "pass";
else
    value = "fail";
end
end

function enabled = localRasterOutputEnabled(runFolder)
% Missing or unreadable authority fails closed as raster-enabled.
enabled = true;
configPath = fullfile(runFolder, "meta", "scenario_config_resolved.json");
if exist(configPath, "file") ~= 2
    return;
end
try
    cfg = jsondecode(fileread(configPath));
    raw = sixgr.util.structGet(cfg, "output.save_figures", true);
    if islogical(raw) || isnumeric(raw)
        enabled = logical(raw(1));
        return;
    end
    token = lower(strtrim(string(raw)));
    if any(token == ["false","0","no","off","disabled"])
        enabled = false;
    elseif any(token == ["true","1","yes","on","enabled"])
        enabled = true;
    end
catch
    enabled = true;
end
end

function row = localFailureRow(plotId, imagePath, sourceCSV, expected, code)
row = localEmptyRow();
row.PlotId = string(plotId);
row.ImagePath = string(imagePath);
row.SourceCSV = string(sourceCSV);
row.ExpectedSHA256 = string(expected);
row.SourceExists = false;
row.HashMatches = false;
row.FailureCode = string(code);
end

function row = localEmptyRow()
row = struct( ...
    "PlotId", "", ...
    "ImagePath", "", ...
    "SourceCSV", "", ...
    "ExpectedSHA256", "", ...
    "ActualSHA256", "", ...
    "SourceExists", false, ...
    "HashMatches", false, ...
    "FailureCode", "");
end

function value = localFileSHA256(pathValue)
fid = fopen(pathValue, "rb");
if fid < 0
    value = "";
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
value = lower(string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"))));
end

function value = localPortableRelativePath(value)
value = replace(strtrim(string(value)), "\", "/");
while startsWith(value, "./")
    value = extractAfter(value, 2);
end
end
