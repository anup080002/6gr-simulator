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

artifacts = struct('csv',{{}},'mat',{{}},'fig',{{}},'json',{{}});

sixgr.util.ensureFolder(fullfile(runFolder, "csv"));
sixgr.util.ensureFolder(fullfile(runFolder, "mat"));
sixgr.util.ensureFolder(fullfile(runFolder, "image"));

if opt.SaveCSV
    fileSuffix = localNormalizeFileSuffix(opt.FileSuffix);
    csvFile = fullfile(runFolder, "csv", localAppendFileSuffix("link_kpis.csv", fileSuffix));
    sixgr.util.csvWriteTable(csvFile, kpiTable);
    artifacts.csv{end+1} = csvFile;

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
        "StrictMode", localStrictMode(details), ...
        "MeasurementWindowSec", localMeasurementWindowSec(details, rawKPI), ...
        "WarmupDurationSec", localWarmupDurationSec(details), ...
        "EffectiveBandwidthHz", localEffectiveBandwidthHz(details));
    kpiLineage = localBuildKPILineageTable(kpiRecon.ReconstructionSummary);

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
        "kpi_tb_delivery_ledger_ul.csv", kpiRecon.TBDeliveryLedgerUL;
        "kpi_tb_delivery_ledger_dl.csv", kpiRecon.TBDeliveryLedgerDL;
        "kpi_packet_sdu_delivery_ledger_ul.csv", kpiRecon.PacketSDUDeliveryLedgerUL;
        "kpi_packet_sdu_delivery_ledger_dl.csv", kpiRecon.PacketSDUDeliveryLedgerDL;
        "kpi_application_packet_delivery_ledger_ul.csv", kpiRecon.ApplicationPacketDeliveryLedgerUL;
        "kpi_application_packet_delivery_ledger_dl.csv", kpiRecon.ApplicationPacketDeliveryLedgerDL;
        "kpi_direction_isolation_audit.csv", kpiRecon.DirectionIsolationAudit;
        "kpi_legacy_alias_map.csv", kpiRecon.LegacyAliasMap;
        "kpi_known_bug_regression.csv", kpiRecon.KnownBugRegression;
        "kpi_unit_conversion_audit.csv", kpiRecon.UnitConversionAudit;
        "kpi_duration_source_audit.csv", kpiRecon.DurationSourceAudit;
        "kpi_objective_binding.csv", kpiRecon.ObjectiveBinding;
        "kpi_lineage_table.csv", kpiLineage
        };
    for ki = 1:size(kpiSidecars, 1)
        sidecarPath = fullfile(reportCSVDir, kpiSidecars{ki, 1});
        sixgr.util.csvWriteTable(sidecarPath, kpiSidecars{ki, 2});
        artifacts.csv{end+1} = sidecarPath; %#ok<AGROW>
    end
    reportJSONDir = localKPIReportJSONDir(reportCSVDir);
    sixgr.util.ensureFolder(reportJSONDir);
    gatePath = fullfile(reportJSONDir, "kpi_consistency_gate.json");
    sixgr.util.jsonWrite(gatePath, localBuildKPIConsistencyGate(kpiRecon, kpiLineage));
    artifacts.json{end+1} = gatePath;

    mimoArtifacts = sixgr.mimo.exportMIMOEvidenceArtifacts(localRunRootFolder(runFolder), ...
        localConfig(details), rawKPI, ...
        "RunId", localRunId(details), ...
        "ScenarioName", localScenarioName(details), ...
        "StrictMode", localStrictMode(details));
    if isstruct(mimoArtifacts)
        for mi = 1:numel(mimoArtifacts.csv)
            artifacts.csv{end+1} = mimoArtifacts.csv{mi}; %#ok<AGROW>
        end
    end

    pdschArtifacts = sixgr.truth.exportPDSCHObjectiveArtifacts(localRunRootFolder(runFolder), ...
        localConfig(details), rawKPI.DL, ...
        "RunId", localRunId(details), ...
        "ScenarioName", localScenarioName(details), ...
        "StrictMode", localStrictMode(details), ...
        "SourceTable", rawKPI.Paths.DL);
    if isstruct(pdschArtifacts)
        for pi = 1:numel(pdschArtifacts.csv)
            artifacts.csv{end+1} = pdschArtifacts.csv{pi}; %#ok<AGROW>
        end
        if isfield(pdschArtifacts, "json")
            for pi = 1:numel(pdschArtifacts.json)
                artifacts.json{end+1} = pdschArtifacts.json{pi}; %#ok<AGROW>
            end
        end
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

function reportCSVDir = localKPIReportCSVDir(runFolder)
runFolder = char(string(runFolder));
[parent, leaf] = fileparts(runFolder);
if strcmpi(leaf, "air_interface") && strlength(string(parent)) > 0
    reportCSVDir = fullfile(parent, "reports", "csv");
else
    reportCSVDir = fullfile(runFolder, "reports", "csv");
end
end

function reportJSONDir = localKPIReportJSONDir(reportCSVDir)
[reportDir, leaf] = fileparts(char(string(reportCSVDir)));
if strcmpi(leaf, "csv") && strlength(string(reportDir)) > 0
    reportJSONDir = fullfile(reportDir, "json");
else
    reportJSONDir = fullfile(char(string(reportCSVDir)), "json");
end
end

function T = localBuildKPILineageTable(recon)
if ~(istable(recon) && ~isempty(recon))
    T = table();
    return;
end
n = height(recon);
rows = table();
rows.RunId = localColumnOrDefault(recon, "RunId", strings(n, 1));
rows.ScenarioName = localColumnOrDefault(recon, "ScenarioName", strings(n, 1));
rows.KPIName = localColumnOrDefault(recon, "KPIName", strings(n, 1));
rows.Direction = localColumnOrDefault(recon, "Direction", strings(n, 1));
rows.FormulaId = localColumnOrDefault(recon, "FormulaId", strings(n, 1));
rows.FormulaVersion = localColumnOrDefault(recon, "FormulaVersion", strings(n, 1));
rows.Value = localColumnOrDefault(recon, "Value", nan(n, 1));
rows.NumeratorValue = localColumnOrDefault(recon, "NumeratorValue", nan(n, 1));
rows.DenominatorValue = localColumnOrDefault(recon, "DenominatorValue", nan(n, 1));
rows.AggregationDurationSec = localColumnOrDefault(recon, "AggregationDurationSec", nan(n, 1));
rows.DurationSource = localColumnOrDefault(recon, "DurationSource", strings(n, 1));
rows.RadioDurationOk = isfinite(double(rows.AggregationDurationSec)) & double(rows.AggregationDurationSec) > 0 & ...
    ~contains(lower(string(rows.DurationSource)), "unavailable") & ...
    ~contains(lower(string(rows.DurationSource)), "wall");
rows.SourceTablePaths = localColumnOrDefault(recon, "SourceTablePaths", strings(n, 1));
rows.SourceRowCount = localColumnOrDefault(recon, "SourceRowCount", zeros(n, 1));
rows.EligibleRowCount = localColumnOrDefault(recon, "EligibleRowCount", zeros(n, 1));
rows.SourceRowsHash = localColumnOrDefault(recon, "SourceRowsHash", strings(n, 1));
rows.ProxyRowsExcluded = localColumnOrDefault(recon, "ProxyRowsExcluded", zeros(n, 1));
rows.SkippedRowsExcluded = localColumnOrDefault(recon, "SkippedRowsExcluded", zeros(n, 1));
rows.HARQDeduplicationApplied = localColumnOrDefault(recon, "HARQDeduplicationApplied", false(n, 1));
rows.DuplicateDeliveryCount = localColumnOrDefault(recon, "DuplicateDeliveryCount", zeros(n, 1));
rows.ReconstructionPass = localColumnOrDefault(recon, "ReconciliationPass", false(n, 1));
rows.StrictOk = localColumnOrDefault(recon, "StrictOk", false(n, 1));
rows.Status = localColumnOrDefault(recon, "Status", strings(n, 1));
rows.FailureReason = localColumnOrDefault(recon, "FailureReason", strings(n, 1));
T = rows;
end

function gate = localBuildKPIConsistencyGate(kpiRecon, kpiLineage)
durationAudit = sixgr.util.structGet(kpiRecon, "DurationSourceAudit", table());
durationPass = true;
if istable(durationAudit) && ~isempty(durationAudit) && ismember("Pass", string(durationAudit.Properties.VariableNames))
    durationPass = all(logical(durationAudit.Pass));
end
lineageDurationOk = true;
if istable(kpiLineage) && ~isempty(kpiLineage) && ismember("RadioDurationOk", string(kpiLineage.Properties.VariableNames))
    lineageDurationOk = all(logical(kpiLineage.RadioDurationOk));
end
gate = struct();
gate.KpiConsistencyOk = logical(sixgr.util.structGet(kpiRecon, "StrictOk", false));
gate.RadioDurationUnavailable = ~(durationPass && lineageDurationOk);
gate.LineageRows = double(height(kpiLineage));
gate.LineageRadioDurationOk = logical(lineageDurationOk);
gate.FormulaRegistryVersion = "kpi_registry_v1";
gate.ProducerModule = "sixgr.link.exportLinkKPIs";
end

function values = localColumnOrDefault(T, name, defaultValue)
values = defaultValue;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    values = T.(char(string(name)));
end
end

function rootFolder = localRunRootFolder(runFolder)
runFolder = char(string(runFolder));
[parent, leaf] = fileparts(runFolder);
if strcmpi(leaf, "air_interface") && strlength(string(parent)) > 0
    rootFolder = parent;
else
    rootFolder = runFolder;
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

function cfg = localConfig(details)
cfg = sixgr.util.structGet(details, "Config", struct());
end

function tf = localStrictMode(details)
tf = false;
cfg = sixgr.util.structGet(details, "Config", struct());
if isstruct(cfg)
    tf = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
        logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
end
end

function durationSec = localMeasurementWindowSec(details, rawKPI)
durationSec = NaN;
cfg = localConfig(details);
if isstruct(cfg)
    slotDur = localSlotDurationSec(cfg);
    totalSlots = double(sixgr.util.structGet(cfg, "run.totalSlots", ...
        sixgr.util.structGet(cfg, "run.numTTI", ...
        sixgr.util.structGet(cfg, "run.numFrames", NaN))));
    if isfinite(totalSlots) && totalSlots > 0 && isfinite(slotDur) && slotDur > 0
        durationSec = totalSlots * slotDur;
        return;
    end
    durationSec = double(sixgr.util.structGet(cfg, "run.measurementWindow_s", ...
        sixgr.util.structGet(cfg, "simulation.measurementWindow_s", NaN)));
    if isfinite(durationSec) && durationSec > 0
        return;
    end
end
durationSec = max(localRawWindow(rawKPI.DL), localRawWindow(rawKPI.UL));
if ~(isfinite(durationSec) && durationSec > 0)
    durationSec = NaN;
end
end

function warmupSec = localWarmupDurationSec(details)
warmupSec = 0;
cfg = localConfig(details);
if isstruct(cfg)
    warmupSec = double(sixgr.util.structGet(cfg, "run.warmupDuration_s", ...
        sixgr.util.structGet(cfg, "simulation.warmupDuration_s", 0)));
end
if ~(isfinite(warmupSec) && warmupSec >= 0)
    warmupSec = 0;
end
end

function bwHz = localEffectiveBandwidthHz(details)
bwHz = NaN;
cfg = localConfig(details);
if isstruct(cfg)
    bwHz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", ...
        sixgr.util.structGet(cfg, "phy.channelBandwidth_Hz", NaN)));
    if ~(isfinite(bwHz) && bwHz > 0)
        bwMHz = double(sixgr.util.structGet(cfg, "phy.channelBandwidth_MHz", NaN));
        if isfinite(bwMHz) && bwMHz > 0
            bwHz = bwMHz * 1e6;
        end
    end
end
end

function slotDur = localSlotDurationSec(cfg)
try
    slotDur = sixgr.time.slotDurationSec(cfg);
catch ME
    if any(string(ME.identifier) == [ ...
            "sixgr:time:MissingSCS", "sixgr:time:InvalidSCS"])
        slotDur = NaN;
    else
        rethrow(ME);
    end
end
end

function durationSec = localRawWindow(T)
durationSec = NaN;
if ~(istable(T) && ~isempty(T))
    return;
end
for name = ["MeasurementWindowSec","MeasurementWindow_s","ScenarioMeasurementWindowSec","ScenarioDurationSec","RunDurationSec"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localNumericColumn(T, name);
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            durationSec = max(vals);
            return;
        end
    end
end
for name = ["MeasurementWindow_ms","ScenarioDuration_ms","RunDuration_ms"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localNumericColumn(T, name);
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            durationSec = max(vals) / 1e3;
            return;
        end
    end
end
end

function vals = localNumericColumn(T, name)
try
    vals = double(T.(char(string(name))));
catch
    vals = str2double(string(T.(char(string(name)))));
end
vals = vals(:);
end
