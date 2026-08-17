function audit = auditRunArtifacts(runFolder, varargin)
%AUDITRUNARTIFACTS Recursively audit CSV and image artifacts for a run.
%
%   audit = sixgr.validation.auditRunArtifacts(runFolder) scans every CSV,
%   PNG, JPG, JPEG, and legacy SVG files under the run folder, overlays required
%   run-class-specific artifacts, and writes:
%     reports/csv/all_csv_artifact_audit.csv
%     reports/csv/all_image_artifact_audit.csv
%     reports/csv/artifact_issue_registry.csv
%     reports/json/artifact_audit_summary.json

p = inputParser;
p.addParameter("RequiredCSV", strings(0, 1), @(x)isstring(x) || ischar(x) || iscellstr(x));
p.addParameter("RequiredImages", strings(0, 1), @(x)isstring(x) || ischar(x) || iscellstr(x));
p.addParameter("Strict", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("MaxPreviewRows", 5, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.addParameter("FailOnEmptyRequiredCSV", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FailOnBlankRequiredImage", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FailOnUnmanifestedImages", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("WriteOutputs", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

rootRunFolder = localResolveRootRunFolder(runFolder);
if exist(rootRunFolder, "dir") ~= 7
    error("sixgr:validation:auditRunArtifacts:RunFolderMissing", ...
        "Run folder does not exist: %s", rootRunFolder);
end

layout = sixgr.report.resultLayout(rootRunFolder);
reportJSONDir = fullfile(layout.ReportDir, "json");
cfgInfo = localReadOptionalJSON(fullfile(layout.MetaDir, "scenario_config_resolved.json"));
runClassInfo = localReadOptionalTable(fullfile(layout.ReportCSVDir, "run_classification.csv"));
runClass = localResolveRunClass(cfgInfo.Data, runClassInfo.Table);
req = localResolveRequirements(runClass, opt);
specCatalog = localArtifactSpecCatalog();
lineageMap = localBuildPlotLineageMap(rootRunFolder, layout.ReportCSVDir);

csvFiles = localListRelativeFiles(rootRunFolder, ["*.csv"]);
imageFiles = localListRelativeFiles(rootRunFolder, ["*.png", "*.jpg", "*.jpeg", "*.svg"]);
csvTargets = unique([csvFiles(:); req.RequiredCSV(:)], "stable");
imageTargets = unique([imageFiles(:); req.RequiredImages(:)], "stable");

csvRows = repmat(localEmptyCSVRow(), 0, 1);
for i = 1:numel(csvTargets)
    relPath = string(csvTargets(i));
    csvRows(end + 1, 1) = localAuditCSV(rootRunFolder, relPath, ...
        any(strcmp(req.RequiredCSV, relPath)), specCatalog, opt); %#ok<AGROW>
end

imageRows = repmat(localEmptyImageRow(), 0, 1);
for i = 1:numel(imageTargets)
    relPath = string(imageTargets(i));
    imageRows(end + 1, 1) = localAuditImage(rootRunFolder, relPath, ...
        any(strcmp(req.RequiredImages, relPath)), lineageMap, opt); %#ok<AGROW>
end

csvAuditTable = localRowsToTable(csvRows, localEmptyCSVRow());
imageAuditTable = localRowsToTable(imageRows, localEmptyImageRow());
issueRegistry = localBuildIssueRegistry(csvAuditTable, imageAuditTable);

csvFailMask = string(csvAuditTable.status) == "fail";
csvWarnMask = string(csvAuditTable.status) == "warn";
imageFailMask = string(imageAuditTable.status) == "fail";
imageWarnMask = string(imageAuditTable.status) == "warn";

audit = struct();
audit.RootRunFolder = string(rootRunFolder);
audit.RunClass = string(runClass);
audit.RequiredCSV = req.RequiredCSV;
audit.RequiredImages = req.RequiredImages;
audit.Ok = ~any(csvFailMask) && ~any(imageFailMask);
audit.Status = localTernary(audit.Ok, "pass", "fail");
audit.CSVCount = height(csvAuditTable);
audit.ImageCount = height(imageAuditTable);
audit.CSVFailureCount = double(nnz(csvFailMask));
audit.CSVWarningCount = double(nnz(csvWarnMask));
audit.ImageFailureCount = double(nnz(imageFailMask));
audit.ImageWarningCount = double(nnz(imageWarnMask));
audit.FailureCount = audit.CSVFailureCount + audit.ImageFailureCount;
audit.WarningCount = audit.CSVWarningCount + audit.ImageWarningCount;
audit.FailureCodes = unique([string(csvAuditTable.failure_code(csvFailMask)); string(imageAuditTable.failure_code(imageFailMask))], "stable");
audit.WarningCodes = unique([string(csvAuditTable.failure_code(csvWarnMask)); string(imageAuditTable.failure_code(imageWarnMask))], "stable");
audit.CSVAuditTable = csvAuditTable;
audit.ImageAuditTable = imageAuditTable;
audit.IssueRegistry = issueRegistry;
audit.Options = opt;

if logical(opt.WriteOutputs)
    sixgr.util.ensureFolder(layout.ReportCSVDir);
    sixgr.util.ensureFolder(reportJSONDir);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "all_csv_artifact_audit.csv"), csvAuditTable);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "all_image_artifact_audit.csv"), imageAuditTable);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "artifact_issue_registry.csv"), issueRegistry);
    jsonAudit = audit;
    jsonAudit.CSVAuditTable = table2struct(csvAuditTable);
    jsonAudit.ImageAuditTable = table2struct(imageAuditTable);
    jsonAudit.IssueRegistry = table2struct(issueRegistry);
    sixgr.util.jsonWrite(fullfile(reportJSONDir, "artifact_audit_summary.json"), jsonAudit);
end

if logical(opt.Strict) && ~audit.Ok
    error("sixgr:validation:auditRunArtifacts:AuditFailed", ...
        "Artifact audit failed with %d failure row(s): %s", ...
        audit.FailureCount, strjoin(audit.FailureCodes, ", "));
end
end

function req = localResolveRequirements(runClass, opt)
req = struct();
req.RunClass = string(runClass);
req.RequiredCSV = unique([localDefaultRequiredCSV(runClass); localNormalizeRequiredList(opt.RequiredCSV)], "stable");
req.RequiredImages = unique([localDefaultRequiredImages(runClass); localNormalizeRequiredList(opt.RequiredImages)], "stable");
end

function paths = localDefaultRequiredCSV(runClass)
runClass = lower(strtrim(string(runClass)));
switch runClass
    case "fixed_snr_sweep_lls"
        paths = [
            "reports/csv/run_classification.csv"
            "air_interface/csv/lls_fixed_link_campaign.csv"
            "air_interface/csv/fixed_link_campaign_task_plan.csv"
            "air_interface/csv/dl_fixed_link_campaign_trials.csv"
            "air_interface/csv/ul_fixed_link_campaign_trials.csv"
            "reports/csv/dl_fixed_snr_bler_curve.csv"
            "reports/csv/ul_fixed_snr_bler_curve.csv"
            "reports/csv/fixed_snr_sweep_audit.csv"
            ];
    case "ue_placement_geometry_lls"
        paths = [
            "reports/csv/run_classification.csv"
            "geometry/csv/topology_nodes.csv"
            "geometry/csv/ue_initial_positions.csv"
            "geometry/csv/trajectory_geometry.csv"
            "mobility/csv/doppler_reconciliation.csv"
            "reports/csv/geometry_runtime_audit.csv"
            ];
    otherwise
        paths = strings(0, 1);
end
end

function paths = localDefaultRequiredImages(runClass)
runClass = lower(strtrim(string(runClass)));
switch runClass
    case "fixed_snr_sweep_lls"
        paths = [
            "reports/image/dl_bler_vs_snr.png"
            "reports/image/ul_bler_vs_snr.png"
            "reports/image/dl_ber_vs_snr.png"
            "reports/image/ul_ber_vs_snr.png"
            "reports/image/measured_sinr_vs_configured_snr.png"
            ];
    case "ue_placement_geometry_lls"
        paths = [
            "geometry/image/topology_map.png"
            "geometry/image/ue_trajectory_xy.png"
            "mobility/image/doppler_vs_slot.png"
            "reports/image/measured_sinr_vs_slot.png"
            ];
    otherwise
        paths = strings(0, 1);
end
end

function specs = localArtifactSpecCatalog()
specs = repmat(struct("RelativePath", "", "ColumnGroups", {{}}, "DisplayGroups", strings(0, 1)), 0, 1);
specs(end + 1, 1) = localSpec("reports/csv/run_classification.csv", {["RunClass"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("air_interface/csv/lls_fixed_link_campaign.csv", {["SNR_dB","ConfiguredSNR_dB"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("air_interface/csv/fixed_link_campaign_task_plan.csv", {["TaskKind"], ["PointIndex"], ["PointValue","ConfiguredSNR_dB","SNR_dB"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("air_interface/csv/dl_fixed_link_campaign_trials.csv", {["Direction"], ["SNR_dB","AppliedAWGNSNR_dB","ConfiguredSNR_dB"], ["Status"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("air_interface/csv/ul_fixed_link_campaign_trials.csv", {["Direction"], ["SNR_dB","AppliedAWGNSNR_dB","ConfiguredSNR_dB"], ["Status"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("reports/csv/dl_fixed_snr_bler_curve.csv", {["Direction"], ["ConfiguredSNR_dB","SNR_dB"], ["BLER"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("reports/csv/ul_fixed_snr_bler_curve.csv", {["Direction"], ["ConfiguredSNR_dB","SNR_dB"], ["BLER"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("reports/csv/dl_fixed_snr_ber_curve.csv", {["Direction"], ["ConfiguredSNR_dB","SNR_dB"], ["BER"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("reports/csv/ul_fixed_snr_ber_curve.csv", {["Direction"], ["ConfiguredSNR_dB","SNR_dB"], ["BER"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("reports/csv/fixed_snr_sweep_audit.csv", {["CheckName"], ["Status"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("geometry/csv/topology_nodes.csv", {["NodeClass"], ["X_m"], ["Y_m"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("geometry/csv/ue_initial_positions.csv", {["UeId","UEID"], ["X_m"], ["Y_m"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("geometry/csv/trajectory_geometry.csv", {["UeId","UEID"], ["CanonicalSlot"], ["X_m"], ["Y_m"], ["Distance3D_m"], ["AppliedDopplerHz"], ["PropagationDelay_s"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("mobility/csv/doppler_reconciliation.csv", {["UeId","UEID","UEId"], ["CanonicalSlot","Slot"], ["AppliedDopplerHz","ObservedDopplerHz","Doppler_Hz"]}); %#ok<AGROW>
specs(end + 1, 1) = localSpec("reports/csv/geometry_runtime_audit.csv", {["CheckName"], ["Status"]}); %#ok<AGROW>
end

function spec = localSpec(relPath, columnGroups)
displayGroups = strings(0, 1);
for i = 1:numel(columnGroups)
    displayGroups(end + 1, 1) = strjoin(string(columnGroups{i}), "|"); %#ok<AGROW>
end
spec = struct( ...
    "RelativePath", localNormalizeRelativePath(relPath), ...
    "ColumnGroups", {columnGroups}, ...
    "DisplayGroups", displayGroups);
end

function row = localAuditCSV(rootRunFolder, relPath, required, specCatalog, opt)
spec = localLookupSpec(specCatalog, relPath);
row = localEmptyCSVRow();
row.path = string(fullfile(rootRunFolder, strrep(char(relPath), "/", filesep)));
row.relative_path = string(relPath);
row.bytes = 0;
row.sha256 = "";
row.readable_by_readtable = false;
row.row_count = 0;
row.column_count = 0;
row.column_names_json = "[]";
row.numeric_column_count = 0;
row.finite_numeric_count = 0;
row.missing_numeric_count = 0;
row.all_blank_columns_json = "[]";
row.has_required_columns = ~spec.Matched;
row.status = "pass";
row.failure_code = "";
row.first_issue = "";
row.required = logical(required);
row.artifact_spec = string(spec.RelativePath);
row.required_columns_json = localJSONString(spec.DisplayGroups);

if exist(row.path, "file") ~= 2
    row.status = localTernary(required, "fail", "warn");
    row.failure_code = localTernary(required, "required_csv_missing", "csv_missing");
    row.first_issue = "artifact_missing";
    return;
end

fileInfo = dir(char(row.path));
if ~isempty(fileInfo)
    row.bytes = double(fileInfo(1).bytes);
end
row.sha256 = localFileSHA256(row.path);

[T, readable, reason] = localReadCSVTable(row.path);
row.readable_by_readtable = logical(readable);
if ~row.readable_by_readtable
    row.status = localTernary(required, "fail", "warn");
    row.failure_code = localTernary(required, "required_csv_unreadable", "csv_unreadable");
    row.first_issue = string(reason);
    return;
end

row.row_count = double(height(T));
row.column_count = double(width(T));
row.column_names_json = localJSONString(string(T.Properties.VariableNames));

[numericColumnCount, finiteNumericCount, missingNumericCount, blankColumns] = localTableStats(T);
row.numeric_column_count = double(numericColumnCount);
row.finite_numeric_count = double(finiteNumericCount);
row.missing_numeric_count = double(missingNumericCount);
row.all_blank_columns_json = localJSONString(blankColumns);
if spec.Matched
    row.has_required_columns = localHasRequiredColumns(T, spec.ColumnGroups);
else
    row.has_required_columns = true;
end

if required && row.row_count == 0 && logical(opt.FailOnEmptyRequiredCSV)
    row.status = "fail";
    row.failure_code = "required_csv_empty";
    row.first_issue = "required_csv_has_zero_rows";
    return;
end
if required && ~row.has_required_columns
    row.status = "fail";
    row.failure_code = "required_columns_missing";
    row.first_issue = "required_column_group_missing";
    return;
end
if ~required && row.row_count == 0
    row.status = "warn";
    row.failure_code = "csv_empty";
    row.first_issue = "csv_has_zero_rows";
    return;
end
if spec.Matched && ~row.has_required_columns
    row.status = "warn";
    row.failure_code = "required_columns_missing";
    row.first_issue = "required_column_group_missing";
    return;
end
blankColumns = string(blankColumns(:));
if ~isempty(blankColumns)
    row.status = "warn";
    row.failure_code = "blank_columns_present";
    row.first_issue = "all_blank_columns_detected";
end
end

function row = localAuditImage(rootRunFolder, relPath, required, lineageMap, opt)
row = localEmptyImageRow();
row.path = string(fullfile(rootRunFolder, strrep(char(relPath), "/", filesep)));
row.relative_path = string(relPath);
row.bytes = 0;
row.sha256 = "";
row.format = "";
row.width_px = NaN;
row.height_px = NaN;
row.readable = false;
row.color_or_grayscale = "";
row.estimated_unique_color_count = NaN;
row.pixel_std = NaN;
row.blank_or_low_information = false;
row.source_csv = localLineageLookup(lineageMap, relPath);
row.source_csv_exists = false;
row.status = "pass";
row.failure_code = "";
row.first_issue = "";
row.required = logical(required);

if strlength(row.source_csv) > 0 && row.source_csv ~= "__manifested_without_source__"
    row.source_csv_exists = localSourceCSVExists(rootRunFolder, row.source_csv);
end

if exist(row.path, "file") ~= 2
    row.status = localTernary(required, "fail", "warn");
    row.failure_code = localTernary(required, "required_image_missing", "image_missing");
    row.first_issue = "artifact_missing";
    return;
end

fileInfo = dir(char(row.path));
if ~isempty(fileInfo)
    row.bytes = double(fileInfo(1).bytes);
end
row.sha256 = localFileSHA256(row.path);

[~, ~, ext] = fileparts(char(row.path));
ext = lower(string(ext));
if ext == ".svg"
    row.status = "fail";
    row.failure_code = "vector_visual_format_forbidden";
    row.first_issue = "Persisted visual artifacts must use PNG or JPEG; SVG is read-only legacy input.";
    return;
end
if any(ext == [".png", ".jpg", ".jpeg"])
    [imageInfo, reason] = localAnalyzeRasterImage(row.path);
else
    [imageInfo, reason] = localAnalyzeSVG(row.path);
end

row.format = string(imageInfo.Format);
row.width_px = double(imageInfo.Width);
row.height_px = double(imageInfo.Height);
row.readable = logical(imageInfo.Readable);
row.color_or_grayscale = string(imageInfo.ColorMode);
row.estimated_unique_color_count = double(imageInfo.UniqueColors);
row.pixel_std = double(imageInfo.PixelStd);
row.blank_or_low_information = logical(imageInfo.LowInformation);

if ~row.readable
    row.status = localTernary(required, "fail", "warn");
    row.failure_code = localTernary(required, "required_image_unreadable", "image_unreadable");
    row.first_issue = string(reason);
    return;
end
if logical(opt.FailOnUnmanifestedImages) && strlength(row.source_csv) == 0
    row.status = "fail";
    row.failure_code = "unmanifested_visual_artifact";
    row.first_issue = "Every persisted PNG or JPEG requires exact source lineage.";
    return;
end
if row.source_csv == "__manifested_without_source__"
    row.status = "fail";
    row.failure_code = "manifest_source_csv_missing";
    row.first_issue = "The visual manifest row does not identify its source CSV.";
    return;
end
if row.blank_or_low_information && required && logical(opt.FailOnBlankRequiredImage)
    row.status = "fail";
    row.failure_code = "required_image_blank_or_low_information";
    row.first_issue = string(reason);
    return;
end
if row.blank_or_low_information
    row.status = "warn";
    row.failure_code = "image_low_information";
    row.first_issue = string(reason);
    return;
end
if strlength(row.source_csv) > 0 && ~row.source_csv_exists
    row.status = "warn";
    row.failure_code = "source_csv_missing";
    row.first_issue = "lineage_source_csv_not_found";
end
end

function [T, readable, reason] = localReadCSVTable(pathValue)
T = table();
readable = false;
reason = "";
try
    T = readtable(char(pathValue), "VariableNamingRule", "preserve", "TextType", "string");
    readable = true;
    return;
catch ME
    reason = string(ME.identifier) + ":" + string(ME.message);
end
try
    opts = detectImportOptions(char(pathValue), "Delimiter", ",");
    opts.VariableNamingRule = "preserve";
    T = readtable(char(pathValue), opts);
    readable = true;
    reason = "";
catch ME
    reason = string(ME.identifier) + ":" + string(ME.message);
end
end

function [numericColumnCount, finiteNumericCount, missingNumericCount, blankColumns] = localTableStats(T)
numericColumnCount = 0;
finiteNumericCount = 0;
missingNumericCount = 0;
blankColumns = strings(0, 1);
if ~(istable(T) && width(T) > 0)
    return;
end
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    name = names(i);
    raw = T.(T.Properties.VariableNames{i});
    if isnumeric(raw) || islogical(raw)
        values = double(raw(:));
        numericColumnCount = numericColumnCount + 1;
        finiteNumericCount = finiteNumericCount + nnz(isfinite(values));
        missingNumericCount = missingNumericCount + nnz(isnan(values));
        if isempty(values) || all(~isfinite(values))
            blankColumns(end + 1, 1) = name; %#ok<AGROW>
        end
    else
        txt = strtrim(string(raw(:)));
        if isempty(txt) || all(ismissing(txt) | strlength(txt) == 0)
            blankColumns(end + 1, 1) = name; %#ok<AGROW>
        end
    end
end
end

function tf = localHasRequiredColumns(T, columnGroups)
tf = true;
for i = 1:numel(columnGroups)
    candidates = string(columnGroups{i});
    if ~any(ismember(lower(string(T.Properties.VariableNames)), lower(candidates)))
        tf = false;
        return;
    end
end
end

function spec = localLookupSpec(specCatalog, relPath)
spec = struct("Matched", false, "RelativePath", "", "ColumnGroups", {{}}, "DisplayGroups", strings(0, 1));
relPath = localNormalizeRelativePath(relPath);
for i = 1:numel(specCatalog)
    if strcmp(specCatalog(i).RelativePath, relPath)
        spec = specCatalog(i);
        spec.Matched = true;
        return;
    end
end
end

function [info, reason] = localAnalyzeRasterImage(pathValue)
info = struct( ...
    "Format", "", ...
    "Width", NaN, ...
    "Height", NaN, ...
    "Readable", false, ...
    "ColorMode", "", ...
    "UniqueColors", NaN, ...
    "PixelStd", NaN, ...
    "LowInformation", true);
reason = "";
try
    meta = imfinfo(char(pathValue));
    img = imread(char(pathValue));
    info.Format = string(meta.Format);
    info.Width = double(meta.Width);
    info.Height = double(meta.Height);
    info.Readable = true;
    if ndims(img) >= 3 && size(img, 3) >= 3
        info.ColorMode = "color";
        pixels = reshape(img, [], size(img, 3));
        sample = localSampleRows(double(pixels), 50000);
        info.UniqueColors = double(size(unique(sample, "rows"), 1));
        gray = mean(sample, 2);
    else
        info.ColorMode = "grayscale";
        values = double(img(:));
        sample = localSampleRows(values, 50000);
        info.UniqueColors = double(numel(unique(sample)));
        gray = sample;
    end
    info.PixelStd = double(std(double(gray(:)), 0));
    info.LowInformation = localRasterLowInformation(info.UniqueColors, info.PixelStd, info.Width, info.Height);
    if info.LowInformation
        reason = "blank_or_low_information_raster";
    end
catch ME
    reason = string(ME.identifier) + ":" + string(ME.message);
end
end

function [info, reason] = localAnalyzeSVG(pathValue)
info = struct( ...
    "Format", "SVG", ...
    "Width", NaN, ...
    "Height", NaN, ...
    "Readable", false, ...
    "ColorMode", "vector", ...
    "UniqueColors", NaN, ...
    "PixelStd", NaN, ...
    "LowInformation", true);
reason = "";
try
    txt = string(fileread(char(pathValue)));
catch ME
    reason = string(ME.identifier) + ":" + string(ME.message);
    return;
end
txtTrim = strtrim(txt);
if strlength(txtTrim) == 0
    reason = "svg_empty";
    return;
end
if ~contains(lower(txt), "<svg")
    reason = "svg_tag_missing";
    return;
end
info.Readable = true;
info.Width = localSVGDimension(txt, "width");
info.Height = localSVGDimension(txt, "height");
if ~isfinite(info.Width) || ~isfinite(info.Height)
    [vbWidth, vbHeight] = localSVGViewBoxDimensions(txt);
    if ~isfinite(info.Width)
        info.Width = vbWidth;
    end
    if ~isfinite(info.Height)
        info.Height = vbHeight;
    end
end
graphicCount = localSVGGraphicElementCount(txt);
byteCount = strlength(txt);
info.LowInformation = graphicCount <= 0 || byteCount < 256;
if info.LowInformation
    if graphicCount <= 0
        reason = "svg_missing_graphical_elements";
    else
        reason = "svg_low_information";
    end
else
    reason = "";
end
end

function tf = localRasterLowInformation(uniqueColors, pixelStd, widthPx, heightPx)
tf = false;
if ~isfinite(widthPx) || ~isfinite(heightPx) || widthPx <= 0 || heightPx <= 0
    tf = true;
    return;
end
if ~isfinite(uniqueColors) || uniqueColors <= 1
    tf = true;
    return;
end
if isfinite(pixelStd) && uniqueColors <= 4 && pixelStd < 0.5
    tf = true;
end
end

function count = localSVGGraphicElementCount(txt)
matches = regexp(char(txt), '<(path|line|polyline|circle|rect|image|text)\b', "ignorecase");
count = double(numel(matches));
end

function value = localSVGDimension(txt, attrName)
value = NaN;
expr = attrName + '="([^"]+)"';
tokens = regexp(char(txt), char(expr), "tokens", "once", "ignorecase");
if isempty(tokens)
    return;
end
value = localParseLeadingNumeric(tokens{1});
end

function [widthValue, heightValue] = localSVGViewBoxDimensions(txt)
widthValue = NaN;
heightValue = NaN;
tokens = regexp(char(txt), 'viewBox="([^"]+)"', "tokens", "once", "ignorecase");
if isempty(tokens)
    return;
end
parts = regexp(strtrim(tokens{1}), '\s+', "split");
if numel(parts) >= 4
    widthValue = str2double(parts{3});
    heightValue = str2double(parts{4});
end
end

function value = localParseLeadingNumeric(token)
value = NaN;
match = regexp(char(string(token)), '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', "match", "once");
if ~isempty(match)
    value = str2double(match);
end
end

function sample = localSampleRows(values, maxRows)
if isempty(values)
    sample = values;
    return;
end
n = size(values, 1);
if n <= maxRows
    sample = values;
    return;
end
idx = unique(round(linspace(1, n, maxRows)));
sample = values(idx, :);
end

function lineageMap = localBuildPlotLineageMap(rootRunFolder, reportCSVDir)
lineageMap = containers.Map("KeyType", "char", "ValueType", "char");
files = [dir(fullfile(rootRunFolder, "**", "*plot_lineage.csv")); ...
    dir(fullfile(reportCSVDir, "plot_manifest.csv"))];
if ~isempty(files)
    [~, uniqueIndex] = unique(string(fullfile({files.folder}, {files.name})), "stable");
    files = files(uniqueIndex);
end
for i = 1:numel(files)
    pathValue = fullfile(files(i).folder, files(i).name);
    if sixgr.runtime.isNestedExecutionPath(rootRunFolder, pathValue)
        continue;
    end
    try
        T = readtable(pathValue, "VariableNamingRule", "preserve", "TextType", "string");
    catch
        continue;
    end
    if ~(istable(T) && height(T) > 0)
        continue;
    end
    plotColumn = localFirstColumn(T, ["PlotFile", "ImagePath", "ArtifactPath"]);
    sourceColumn = localFirstColumn(T, ["SourceCSV", "source_csv"]);
    if strlength(plotColumn) == 0
        continue;
    end
    plotFiles = strtrim(string(T.(plotColumn)));
    if strlength(sourceColumn) == 0
        sourceCSVs = repmat("__manifested_without_source__", height(T), 1);
    else
        sourceCSVs = strtrim(string(T.(sourceColumn)));
        sourceCSVs(strlength(sourceCSVs) == 0) = "__manifested_without_source__";
    end
    for k = 1:height(T)
        plotRel = localManifestArtifactPath(plotFiles(k), rootRunFolder);
        sourceRel = localManifestSourceSpec(sourceCSVs(k), rootRunFolder);
        if strlength(plotRel) == 0
            continue;
        end
        if ~isKey(lineageMap, char(plotRel))
            lineageMap(char(plotRel)) = char(sourceRel);
        end
        plotAbs = localNormalizeRelativePath(localRelativePath(fullfile(rootRunFolder, strrep(char(plotRel), "/", filesep)), rootRunFolder));
        if ~isKey(lineageMap, char(plotAbs))
            lineageMap(char(plotAbs)) = char(sourceRel);
    end
end
end
lineageMap = localAddArtifactGenerationLineage(lineageMap, rootRunFolder);
lineageMap = localAddComponentMirrorLineage(lineageMap, rootRunFolder);
end

function lineageMap = localAddArtifactGenerationLineage(lineageMap, rootRunFolder)
resultsPath = fullfile(rootRunFolder, "artifact_generation", ...
    "artifact_generation_results.csv");
if ~isfile(resultsPath)
    return;
end
try
    T = readtable(resultsPath, "VariableNamingRule", "preserve", ...
        "TextType", "string");
catch
    return;
end
required = ["Domain","Component","Profile","ArtifactType", ...
    "Status","OutputRelativePath","SHA256","SourceSHA256"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    return;
end
types = upper(strtrim(string(T.ArtifactType)));
statuses = upper(strtrim(string(T.Status)));
for idx = find(types == "PNG" & statuses == "PASS").'
    sameContract = string(T.Domain) == string(T.Domain(idx)) & ...
        string(T.Component) == string(T.Component(idx)) & ...
        string(T.Profile) == string(T.Profile(idx)) & ...
        types == "CSV" & statuses == "PASS";
    candidates = find(sameContract);
    if numel(candidates) ~= 1
        continue;
    end
    imageRel = localNormalizeRelativePath(string(T.OutputRelativePath(idx)));
    sourceRel = localNormalizeRelativePath(string(T.OutputRelativePath(candidates)));
    imagePath = fullfile(rootRunFolder, strrep(char(imageRel), "/", filesep));
    sourcePath = fullfile(rootRunFolder, strrep(char(sourceRel), "/", filesep));
    if ~isfile(imagePath) || ~isfile(sourcePath)
        continue;
    end
    if ~strcmpi(localFileSHA256(imagePath), string(T.SHA256(idx))) || ...
            ~strcmpi(localFileSHA256(sourcePath), ...
            string(T.SourceSHA256(idx)))
        continue;
    end
    lineageMap(char(imageRel)) = char(sourceRel);
end
end

function lineageMap = localAddComponentMirrorLineage(lineageMap, rootRunFolder)
manifestPath = fullfile(rootRunFolder, "reports", "csv", ...
    "component_artifact_publication_manifest.csv");
if ~isfile(manifestPath)
    return;
end
try
    T = readtable(manifestPath, "VariableNamingRule", "preserve", ...
        "TextType", "string");
catch
    return;
end
required = ["ArtifactType","CanonicalRelativePath", ...
    "PublishedRelativePath","CanonicalSHA256","PublishedSHA256", ...
    "MirrorOnly","CanonicalAuthorityRetained", ...
    "SourceTruthClassification","PublishStatus"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    return;
end
for idx = 1:height(T)
    if lower(strtrim(string(T.ArtifactType(idx)))) ~= "image" || ...
            ~localLogicalScalar(T.MirrorOnly(idx)) || ...
            ~localLogicalScalar(T.CanonicalAuthorityRetained(idx)) || ...
            lower(strtrim(string(T.SourceTruthClassification(idx)))) ~= ...
            "byte_identical_canonical_mirror" || ...
            upper(strtrim(string(T.PublishStatus(idx)))) ~= ...
            "PUBLISHED_HASH_VERIFIED"
        continue;
    end
    canonicalRel = localNormalizeRelativePath( ...
        string(T.CanonicalRelativePath(idx)));
    publishedRel = localNormalizeRelativePath( ...
        string(T.PublishedRelativePath(idx)));
    if ~isKey(lineageMap, char(canonicalRel))
        continue;
    end
    canonicalPath = fullfile(rootRunFolder, ...
        strrep(char(canonicalRel), "/", filesep));
    publishedPath = fullfile(rootRunFolder, ...
        strrep(char(publishedRel), "/", filesep));
    if ~isfile(canonicalPath) || ~isfile(publishedPath)
        continue;
    end
    canonicalHash = localFileSHA256(canonicalPath);
    publishedHash = localFileSHA256(publishedPath);
    if ~strcmpi(canonicalHash, publishedHash) || ...
            ~strcmpi(canonicalHash, string(T.CanonicalSHA256(idx))) || ...
            ~strcmpi(publishedHash, string(T.PublishedSHA256(idx)))
        continue;
    end
    lineageMap(char(publishedRel)) = lineageMap(char(canonicalRel));
end
end

function value = localLogicalScalar(raw)
if islogical(raw)
    value = logical(raw);
elseif isnumeric(raw)
    value = raw ~= 0;
else
    value = any(lower(strtrim(string(raw))) == ["true","1","yes"]);
end
end

function name = localFirstColumn(T, candidates)
name = "";
names = string(T.Properties.VariableNames);
for candidate = string(candidates(:)).'
    idx = find(strcmpi(names, candidate), 1, "first");
    if ~isempty(idx)
        name = names(idx);
        return;
    end
end
end

function rel = localManifestArtifactPath(pathValue, rootRunFolder)
pathValue = string(pathValue);
if isfile(char(pathValue)) || localLooksAbsolute(pathValue)
    rel = localRelativePath(pathValue, rootRunFolder);
else
    rel = pathValue;
end
rel = localNormalizeRelativePath(rel);
end

function sourceSpec = localManifestSourceSpec(value, rootRunFolder)
value = strtrim(string(value));
if value == "__manifested_without_source__"
    sourceSpec = value;
    return;
end
parts = split(value, "|");
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
for i = 1:numel(parts)
    parts(i) = localManifestArtifactPath(parts(i), rootRunFolder);
end
sourceSpec = strjoin(parts, "|");
end

function tf = localLooksAbsolute(pathValue)
pathValue = char(string(pathValue));
tf = ~isempty(regexp(pathValue, '^[A-Za-z]:[\\/]', 'once')) || ...
    startsWith(string(pathValue), "\\\\") || startsWith(string(pathValue), "/");
end

function tf = localSourceCSVExists(rootRunFolder, sourceSpec)
parts = split(string(sourceSpec), "|");
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
tf = ~isempty(parts);
for i = 1:numel(parts)
    rel = localNormalizeRelativePath(parts(i));
    pathValue = fullfile(rootRunFolder, strrep(char(rel), "/", filesep));
    tf = tf && exist(pathValue, "file") == 2;
end
end

function sourceCSV = localLineageLookup(lineageMap, relPath)
sourceCSV = "";
relPath = localNormalizeRelativePath(relPath);
if isKey(lineageMap, char(relPath))
    sourceCSV = string(lineageMap(char(relPath)));
end
end

function issueTable = localBuildIssueRegistry(csvAuditTable, imageAuditTable)
rows = repmat(localEmptyIssueRow(), 0, 1);
for i = 1:height(csvAuditTable)
    status = string(csvAuditTable.status(i));
    if status == "pass"
        continue;
    end
    row = localEmptyIssueRow();
    row.artifact_type = "csv";
    row.relative_path = string(csvAuditTable.relative_path(i));
    row.status = status;
    row.failure_code = string(csvAuditTable.failure_code(i));
    row.first_issue = string(csvAuditTable.first_issue(i));
    row.required = logical(csvAuditTable.required(i));
    rows(end + 1, 1) = row; %#ok<AGROW>
end
for i = 1:height(imageAuditTable)
    status = string(imageAuditTable.status(i));
    if status == "pass"
        continue;
    end
    row = localEmptyIssueRow();
    row.artifact_type = "image";
    row.relative_path = string(imageAuditTable.relative_path(i));
    row.status = status;
    row.failure_code = string(imageAuditTable.failure_code(i));
    row.first_issue = string(imageAuditTable.first_issue(i));
    row.required = logical(imageAuditTable.required(i));
    rows(end + 1, 1) = row; %#ok<AGROW>
end
issueTable = localRowsToTable(rows, localEmptyIssueRow());
end

function row = localEmptyCSVRow()
row = struct( ...
    "path", "", ...
    "relative_path", "", ...
    "bytes", 0, ...
    "sha256", "", ...
    "readable_by_readtable", false, ...
    "row_count", 0, ...
    "column_count", 0, ...
    "column_names_json", "[]", ...
    "numeric_column_count", 0, ...
    "finite_numeric_count", 0, ...
    "missing_numeric_count", 0, ...
    "all_blank_columns_json", "[]", ...
    "has_required_columns", true, ...
    "status", "", ...
    "failure_code", "", ...
    "first_issue", "", ...
    "required", false, ...
    "artifact_spec", "", ...
    "required_columns_json", "[]");
end

function row = localEmptyImageRow()
row = struct( ...
    "path", "", ...
    "relative_path", "", ...
    "bytes", 0, ...
    "sha256", "", ...
    "format", "", ...
    "width_px", NaN, ...
    "height_px", NaN, ...
    "readable", false, ...
    "color_or_grayscale", "", ...
    "estimated_unique_color_count", NaN, ...
    "pixel_std", NaN, ...
    "blank_or_low_information", false, ...
    "source_csv", "", ...
    "source_csv_exists", false, ...
    "status", "", ...
    "failure_code", "", ...
    "first_issue", "", ...
    "required", false);
end

function row = localEmptyIssueRow()
row = struct( ...
    "artifact_type", "", ...
    "relative_path", "", ...
    "status", "", ...
    "failure_code", "", ...
    "first_issue", "", ...
    "required", false);
end

function T = localRowsToTable(rows, prototype)
if isempty(rows)
    T = struct2table(repmat(prototype, 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
end
end

function tf = localHasColumn(T, name)
tf = istable(T) && any(strcmpi(string(T.Properties.VariableNames), string(name)));
end

function paths = localNormalizeRequiredList(values)
values = string(values(:));
values = strtrim(values);
values = values(strlength(values) > 0);
for i = 1:numel(values)
    values(i) = localNormalizeRelativePath(values(i));
end
paths = unique(values, "stable");
end

function relPaths = localListRelativeFiles(rootRunFolder, patterns)
relPaths = strings(0, 1);
for i = 1:numel(patterns)
    files = dir(fullfile(rootRunFolder, "**", char(patterns(i))));
    files = files(~[files.isdir]);
    for k = 1:numel(files)
        absolutePath = fullfile(files(k).folder, files(k).name);
        if sixgr.runtime.isNestedExecutionPath(rootRunFolder, absolutePath)
            continue;
        end
        rel = localRelativePath(absolutePath, rootRunFolder);
        relPaths(end + 1, 1) = localNormalizeRelativePath(rel); %#ok<AGROW>
    end
end
relPaths = unique(relPaths, "stable");
end

function value = localResolveRunClass(cfg, runClassTable)
value = "";
if istable(runClassTable) && height(runClassTable) > 0 && localHasColumn(runClassTable, "RunClass")
    value = strtrim(string(runClassTable.RunClass(1)));
end
if strlength(value) == 0
    value = localFirstTextValue([
        localGetText(cfg, "validation.run_class", "")
        localGetText(cfg, "validation.RunClass", "")
        localGetText(cfg, "scenario.run_class", "")
        localGetText(cfg, "canonical_control.validation.run_class", "")
        ]);
end
if strlength(value) == 0
    value = "unknown";
end
end

function out = localReadOptionalJSON(pathValue)
out = struct("Present", false, "Readable", false, "Data", struct());
if exist(pathValue, "file") ~= 2
    return;
end
out.Present = true;
try
    out.Data = sixgr.util.jsonRead(pathValue);
    out.Readable = true;
catch
    out.Data = struct();
end
end

function out = localReadOptionalTable(pathValue)
out = struct("Present", false, "Readable", false, "Table", table());
if exist(pathValue, "file") ~= 2
    return;
end
out.Present = true;
try
    out.Table = readtable(pathValue, "VariableNamingRule", "preserve", "TextType", "string");
    out.Readable = true;
catch
    out.Table = table();
end
end

function rootRunFolder = localResolveRootRunFolder(runFolder)
rootRunFolder = char(string(runFolder));
if strlength(string(rootRunFolder)) == 0
    rootRunFolder = pwd;
    return;
end
while true
    [parentPath, leaf] = fileparts(rootRunFolder);
    leaf = lower(string(leaf));
    if any(leaf == ["geometry", "mobility", "reports", "air_interface", "meta"])
        rootRunFolder = parentPath;
    else
        break;
    end
end
end

function rel = localRelativePath(pathValue, rootRunFolder)
pathValue = string(pathValue);
rootRunFolder = string(rootRunFolder);
prefix = rootRunFolder + filesep;
if startsWith(pathValue, prefix, "IgnoreCase", true)
    rel = extractAfter(pathValue, strlength(prefix));
else
    rel = pathValue;
end
end

function rel = localNormalizeRelativePath(pathValue)
rel = string(pathValue);
rel = replace(rel, "\", "/");
while startsWith(rel, "./") || startsWith(rel, ".\")
    rel = extractAfter(rel, 2);
end
end

function hash = localFileSHA256(pathValue)
hash = "";
if exist(char(pathValue), "file") ~= 2
    return;
end
fid = fopen(char(pathValue), "r");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, "*uint8");
hash = string(sixgr.util.sha256Hex(uint8(bytes(:))));
end

function text = localJSONString(values)
values = string(values(:));
if isempty(values)
    text = "[]";
else
    text = string(jsonencode(cellstr(values)));
end
end

function value = localFirstTextValue(values)
values = string(values(:));
mask = ~ismissing(values) & strlength(strtrim(values)) > 0;
if any(mask)
    value = values(find(mask, 1, "first"));
else
    value = "";
end
end

function text = localGetText(cfg, pathValue, defaultValue)
value = defaultValue;
try
    value = sixgr.util.structGet(cfg, pathValue, defaultValue);
catch
    value = defaultValue;
end
text = strtrim(string(value));
if strlength(text) == 0
    text = string(defaultValue);
end
end

function out = localTernary(cond, a, b)
if logical(cond)
    out = a;
else
    out = b;
end
end
