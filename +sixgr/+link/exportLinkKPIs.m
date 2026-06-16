function artifacts = exportLinkKPIs(runFolder, kpiTable, details, varargin)
%EXPORTLINKKPIS Unified link-level CSV/MAT/FIG export.

if nargin >= 3 && istable(runFolder) && (ischar(details) || (isstring(details) && isscalar(details)))
    legacyKpiTable = runFolder;
    legacyDetails = kpiTable;
    runFolder = details;
    kpiTable = legacyKpiTable;
    details = legacyDetails;
end
runFolder = char(string(runFolder));

p = inputParser;
p.addParameter("SaveCSV", true, @(x) islogical(x) && isscalar(x));
p.addParameter("SaveMAT", true, @(x) islogical(x) && isscalar(x));
p.addParameter("SaveFigures", false, @(x) islogical(x) && isscalar(x));
p.addParameter("SavePNG", true, @(x) islogical(x) && isscalar(x));
p.addParameter("FigurePrefix", "Link", @(x) ischar(x) || isstring(x));
p.addParameter("PlotVisible", false, @(x) islogical(x) && isscalar(x));
p.addParameter("FigureResolution", 140, @(x) isnumeric(x) && isscalar(x) && x >= 72);
p.addParameter("FileSuffix", "", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

if nargin < 3 || isempty(details)
    details = struct();
end

artifacts = struct('csv',{{}},'mat',{{}},'fig',{{}});

sixgr.util.ensureFolder(fullfile(runFolder, "csv"));
sixgr.util.ensureFolder(fullfile(runFolder, "mat"));
sixgr.util.ensureFolder(fullfile(runFolder, "image"));

if opt.SaveCSV
    fileSuffix = localNormalizeFileSuffix(opt.FileSuffix);
    csvFile = fullfile(runFolder, "csv", localAppendFileSuffix("link_kpis.csv", fileSuffix));
    sixgr.util.csvWriteTable(csvFile, kpiTable);
    artifacts.csv{end+1} = csvFile;

    sweep = sixgr.util.structGet(details, "SNRSweep", table());
    sweepFile = fullfile(runFolder, "csv", localAppendFileSuffix("lls_snr_sweep.csv", fileSuffix));
    if istable(sweep)
        if isempty(sweep) || height(sweep) == 0
            sweep = localEmptySweepStatusTable();
        end
        sweep = localPreserveExistingTableColumns(sweepFile, sweep);
        sixgr.util.csvWriteTable(sweepFile, sweep);
        artifacts.csv{end+1} = sweepFile;
    end

    paprT = sixgr.util.structGet(details, "PAPRCCDF", table());
    if istable(paprT) && ~isempty(paprT)
        paprFile = fullfile(runFolder, "csv", localAppendFileSuffix("papr_ccdf.csv", fileSuffix));
        sixgr.util.csvWriteTable(paprFile, paprT);
        artifacts.csv{end+1} = paprFile;
    end

    rawKPI = sixgr.kpi.loadDirectionRawTables(details, "RunFolder", runFolder);
    kpiRecon = sixgr.kpi.reconstructLLSKPISummaryFromRaw(rawKPI, ...
        "RunId", localRunId(details), ...
        "ScenarioName", localScenarioName(details), ...
        "SourcePaths", rawKPI.Paths, ...
        "StrictMode", localStrictMode(details));

    reportCSVDir = localKPIReportCSVDir(runFolder);
    sixgr.util.ensureFolder(reportCSVDir);
    kpiSidecars = {
        "kpi_formula_registry.csv", kpiRecon.FormulaRegistry;
        "kpi_source_table_manifest.csv", kpiRecon.SourceManifest;
        "kpi_raw_table_schema_audit.csv", kpiRecon.SchemaAudit;
        "kpi_reconstruction_summary.csv", kpiRecon.ReconstructionSummary;
        "kpi_row_contributions_ul.csv", kpiRecon.RowContributionsUL;
        "kpi_row_contributions_dl.csv", kpiRecon.RowContributionsDL;
        "kpi_harq_delivery_trace_ul.csv", kpiRecon.HARQDeliveryTraceUL;
        "kpi_harq_delivery_trace_dl.csv", kpiRecon.HARQDeliveryTraceDL;
        "kpi_direction_isolation_audit.csv", kpiRecon.DirectionIsolationAudit;
        "kpi_legacy_alias_map.csv", kpiRecon.LegacyAliasMap;
        "kpi_known_bug_regression.csv", kpiRecon.KnownBugRegression;
        "kpi_unit_conversion_audit.csv", kpiRecon.UnitConversionAudit;
        "kpi_duration_source_audit.csv", kpiRecon.DurationSourceAudit;
        "kpi_objective_binding.csv", kpiRecon.ObjectiveBinding
        };
    for ki = 1:size(kpiSidecars, 1)
        sidecarPath = fullfile(reportCSVDir, kpiSidecars{ki, 1});
        sixgr.util.csvWriteTable(sidecarPath, kpiSidecars{ki, 2});
        artifacts.csv{end+1} = sidecarPath; %#ok<AGROW>
    end

    % Backward-compatible campaign alias with compact scalar content. The
    % values are generated from raw direction-filtered trial rows only.
    csvSummary = fullfile(runFolder, "csv", localAppendFileSuffix("lls_kpi_summary.csv", fileSuffix));
    sixgr.util.csvWriteTable(csvSummary, kpiRecon.SummaryAliases);
    artifacts.csv{end+1} = csvSummary;

    unitFile = fullfile(runFolder, "csv", localAppendFileSuffix("metric_unit_catalog.csv", fileSuffix));
    unitCatalog = sixgr.truth.buildMetricUnitCatalogue(runFolder);
    sixgr.util.csvWriteTable(unitFile, unitCatalog);
    artifacts.csv{end+1} = unitFile;
end

if opt.SaveMAT
    fileSuffix = localNormalizeFileSuffix(opt.FileSuffix);
    matFile = fullfile(runFolder, "mat", localAppendFileSuffix("link_results.mat", fileSuffix));
    payload = struct();
    payload.kpiTable = kpiTable;
    payload.details = details;
    sixgr.util.matSave(matFile, payload);
    artifacts.mat{end+1} = matFile;
end

if opt.SaveFigures
    try
        resStruct = struct();
        resStruct.KPIs = struct();
        resStruct.KPIs.LinkKPI = kpiTable;
        figPrefix = string(opt.FigurePrefix) + localNormalizeFileSuffix(opt.FileSuffix);
        sweep = sixgr.util.structGet(details, "SNRSweep", table());
        if istable(sweep) && ~isempty(sweep)
            resStruct.KPIs.LinkSNRSweep = sweep;
        end
        paprCCDF = sixgr.util.structGet(details, "PAPRCCDF", table());
        if istable(paprCCDF) && ~isempty(paprCCDF)
            resStruct.KPIs.PAPRCCDF = paprCCDF;
        end

        figs = sixgr.visual.PlotLinkKPIs(resStruct, ...
            "FigurePrefix", char(figPrefix), ...
            "MakeInvisible", ~logical(opt.PlotVisible));
        fNames = fieldnames(figs);
        for i = 1:numel(fNames)
            n = fNames{i};
            if startsWith(n, "_")
                continue;
            end
            f = figs.(n);
            if isempty(f) || ~ishghandle(f)
                continue;
            end
            if opt.SavePNG
                fp = fullfile(runFolder, "image", lower(figPrefix) + "_" + lower(string(n)) + ".png");
                sixgr.util.exportFigureArtifact(f, fp, "Resolution", round(double(opt.FigureResolution)));
                artifacts.fig{end+1} = char(fp); %#ok<AGROW>
            end
            try
                if ~logical(opt.PlotVisible)
                    close(f);
                end
            catch
            end
        end
    catch
        % Keep data export successful even if plotting fails.
    end
end
end

function T = localPreserveExistingTableColumns(csvFile, T)
% Keep richer runner-owned measured columns when this generic exporter
% refreshes the same artifact later in the bundle pipeline.
if ~(istable(T) && isfile(csvFile))
    return;
end
try
    existing = readtable(csvFile, "VariableNamingRule", "preserve");
catch
    return;
end
if ~(istable(existing) && height(existing) == height(T))
    return;
end

existingVars = string(existing.Properties.VariableNames);
newVars = string(T.Properties.VariableNames);
merged = existing;
for i = 1:numel(newVars)
    varName = char(newVars(i));
    merged.(varName) = T.(varName);
end

missingExisting = setdiff(existingVars, newVars, "stable");
if ~isempty(missingExisting) || width(existing) > width(T)
    T = merged;
end
end

function suffix = localNormalizeFileSuffix(in)
suffix = strtrim(string(in));
if strlength(suffix) == 0
    suffix = "";
    return;
end
if ~startsWith(suffix, "_")
    suffix = "_" + suffix;
end
end

function out = localAppendFileSuffix(fileName, suffix)
fileName = string(fileName);
suffix = string(suffix);
if strlength(suffix) == 0
    out = char(fileName);
    return;
end
[folder, stem, ext] = fileparts(char(fileName));
outName = string(stem) + suffix + string(ext);
if strlength(string(folder)) > 0
    out = char(fullfile(folder, char(outName)));
else
    out = char(outName);
end
end

function T = localEmptySweepStatusTable()
T = table( ...
    string("skipped_single_point_run"), ...
    NaN, NaN, NaN, NaN, NaN, ...
    'VariableNames', {'Status','SNR_dB','DL_BLER','UL_BLER','DL_Throughput_Mbps','UL_Throughput_Mbps'});
end

function reportCSVDir = localKPIReportCSVDir(runFolder)
runFolder = char(string(runFolder));
[parent, leaf] = fileparts(runFolder);
if strcmpi(leaf, "air_interface") && strlength(string(parent)) > 0
    reportCSVDir = fullfile(parent, "reports", "csv");
else
    reportCSVDir = fullfile(runFolder, "reports", "csv");
end
end

function runId = localRunId(details)
runId = string(sixgr.util.structGet(details, "RunId", ...
    sixgr.util.structGet(details, "run_id", "")));
end

function scenarioName = localScenarioName(details)
scenarioName = string(sixgr.util.structGet(details, "ScenarioName", ...
    sixgr.util.structGet(details, "scenario_name", "")));
end

function tf = localStrictMode(details)
tf = false;
cfg = sixgr.util.structGet(details, "Config", struct());
if isstruct(cfg)
    tf = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
        logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
end
end
