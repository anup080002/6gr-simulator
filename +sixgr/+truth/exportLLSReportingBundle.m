function out = exportLLSReportingBundle(runFolder, scfg, cfg, result, manifest, runtimeSummary, scenarioStatus)
%EXPORTLLSREPORTINGBUNDLE Emit structured LLS report artifacts from real runtime data.

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.MetaDir);

catalog = localLoadResultCatalog();
if nargin < 7 || isempty(scenarioStatus)
    scenarioStatus = struct();
end
ctx = localBuildContext(runFolder, layout, scfg, cfg, result, manifest, runtimeSummary, scenarioStatus);
ctx.VisualArtifactContractEnforcement = sixgr.visual.enforceVisualArtifactContract(runFolder, ...
    "StrictMode", localStrictVisualArtifactMode(ctx), ...
    "CreateUnavailableCards", false);
ctx.DebugArtifacts = localWriteDebugTraceArtifacts(ctx);

validationT = localBuildValidationMessageTable(ctx);
validationPath = fullfile(layout.ReportCSVDir, "validation_messages.csv");
sixgr.util.csvWriteTable(validationPath, validationT);
ctx.ValidationMessages = validationT;

inventoryT = localBuildArtifactInventory(runFolder, localEmptyMetricTable());
inventoryPath = fullfile(layout.ReportCSVDir, "artifact_inventory.csv");
sixgr.util.csvWriteTable(inventoryPath, inventoryT);
ctx.Inventory = inventoryT;
ctx.ImplementationValidation = struct();
try
    ctx.ImplementationValidation = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, ...
        "WriteArtifacts", true, ...
        "RuntimeSummary", runtimeSummary, ...
        "ScenarioStatus", scenarioStatus);
catch ME
    ctx.ValidationMessages(end+1, :) = struct2table(struct( ...
        "Severity", "error", ...
        "Source", "actual_lls_validation", ...
        "Message", "Actual LLS validation harness failed: " + string(ME.identifier)));
    sixgr.util.csvWriteTable(validationPath, ctx.ValidationMessages);
end

rows = localBuildCategoryRows(catalog, ctx);
rows = localNormalizeMetricRows(rows, runFolder, ctx);
coverageT = localBuildCoverageSummary(catalog, rows);

plots = localExportReportPlots(ctx, coverageT);
ctx.AggregateArtifacts = localWriteAggregateArtifacts(ctx, coverageT, rows, plots);
executivePath = fullfile(layout.ReportDir, "executive_summary.md");
technicalPath = fullfile(layout.ReportDir, "technical_report.md");
localWriteExecutiveSummary(executivePath, ctx, coverageT, rows, plots);
localWriteTechnicalReport(technicalPath, ctx, coverageT, rows, plots);

% Re-evaluate coverage only after all final report artifacts exist on disk.
rows = localBuildCategoryRows(catalog, ctx);
rows = localNormalizeMetricRows(rows, runFolder, ctx);
coverageT = localBuildCoverageSummary(catalog, rows);

detailPath = fullfile(layout.ReportCSVDir, "lls_output_metric_rows.csv");
sixgr.util.csvWriteTable(detailPath, rows, "PreserveSchema", true);

coveragePath = fullfile(layout.ReportCSVDir, "lls_output_spec_coverage.csv");
sixgr.util.csvWriteTable(coveragePath, coverageT, "PreserveSchema", true);

ctx.AggregateArtifacts = localWriteAggregateArtifacts(ctx, coverageT, rows, plots);
localWriteExecutiveSummary(executivePath, ctx, coverageT, rows, plots);
localWriteTechnicalReport(technicalPath, ctx, coverageT, rows, plots);

inventoryT = localBuildArtifactInventory(runFolder, rows);
sixgr.util.csvWriteTable(inventoryPath, inventoryT);
ctx.Inventory = inventoryT;

categoryFiles = strings(0, 1);
for i = 1:numel(catalog.categories)
    cat = catalog.categories(i);
    Tcat = rows(rows.CategoryCode == string(cat.code), :);
    if ~localShouldWriteCategoryFile(ctx, cat, Tcat)
        continue;
    end
    filePath = fullfile(layout.ReportCSVDir, char(string(cat.file_name)));
    sixgr.util.csvWriteTable(filePath, Tcat, "PreserveSchema", true);
    categoryFiles(end+1, 1) = string(filePath); %#ok<AGROW>
end

out = struct();
out.CategoryRows = rows;
out.Coverage = coverageT;
out.Inventory = inventoryT;
out.ValidationMessages = validationT;
out.DetailCSV = string(detailPath);
out.CoverageCSV = string(coveragePath);
out.ArtifactInventoryCSV = string(inventoryPath);
out.ValidationCSV = string(validationPath);
out.CategoryFiles = categoryFiles;
out.ExecutiveSummary = string(executivePath);
out.TechnicalReport = string(technicalPath);
out.Plots = string(plots(:));
out.AggregateArtifacts = ctx.AggregateArtifacts;
out.ImplementationValidation = ctx.ImplementationValidation;
end

function catalog = localLoadResultCatalog()
catalogPath = fullfile(localRepoRoot(), "simulator", "configs", "defaults", "lls_result_output_catalog.yaml");
txt = fileread(catalogPath);
lines = splitlines(string(txt));
cats = repmat(struct("code", "", "key", "", "name", "", "file_name", "", "metrics", struct([])), 0, 1);
catIdx = 0;
for i = 1:numel(lines)
    line = strtrim(lines(i));
    if strlength(line) == 0 || startsWith(line, "#") || line == "categories:"
        continue;
    end
    tok = regexp(line, '^- code:\s*(.+)$', 'tokens', 'once');
    if ~isempty(tok)
        catIdx = catIdx + 1;
        cats(catIdx, 1) = struct("code", string(strtrim(tok{1})), "key", "", "name", "", "file_name", "", "metrics", struct([])); %#ok<AGROW>
        continue;
    end
    if catIdx < 1
        continue;
    end
    tok = regexp(line, '^key:\s*(.+)$', 'tokens', 'once');
    if ~isempty(tok)
        cats(catIdx).key = string(strtrim(tok{1}));
        continue;
    end
    tok = regexp(line, '^name:\s*(.+)$', 'tokens', 'once');
    if ~isempty(tok)
        cats(catIdx).name = string(strtrim(tok{1}));
        continue;
    end
    tok = regexp(line, '^file_name:\s*(.+)$', 'tokens', 'once');
    if ~isempty(tok)
        cats(catIdx).file_name = string(strtrim(tok{1}));
        continue;
    end
    tok = regexp(line, '^- \{\s*key:\s*([^,]+),\s*label:\s*([^}]+)\}$', 'tokens', 'once');
    if ~isempty(tok)
        metric = struct("key", string(strtrim(tok{1})), "label", localUnquoteCatalogScalar(tok{2}));
        if isempty(cats(catIdx).metrics)
            cats(catIdx).metrics = metric;
        else
            cats(catIdx).metrics(end+1, 1) = metric; %#ok<AGROW>
        end
    end
end
catalog = struct("categories", cats);
end

function value = localUnquoteCatalogScalar(raw)
value = strtrim(string(raw));
if strlength(value) < 2
    return;
end
chars = char(value);
if (chars(1) == '"' && chars(end) == '"') || (chars(1) == '''' && chars(end) == '''')
    value = string(chars(2:end-1));
end
end

function ctx = localBuildContext(runFolder, layout, scfg, cfg, result, manifest, runtimeSummary, scenarioStatus)
ctx = struct();
ctx.RunFolder = string(runFolder);
ctx.Layout = layout;
ctx.ScenarioConfig = scfg;
ctx.InternalConfig = cfg;
ctx.Result = result;
ctx.Manifest = manifest;
ctx.RuntimeSummary = runtimeSummary;
ctx.ScenarioStatus = scenarioStatus;
ctx.Tables = struct();
ctx.TableSources = struct();
ctx.Tables.ScenarioSummary = localReadOptionalTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
ctx.Tables.RunClassification = localReadOptionalTable(fullfile(layout.ReportCSVDir, "run_classification.csv"));
ctx.Tables.CaseStatus = localReadOptionalTable(fullfile(layout.ReportCSVDir, "case_status.csv"));
ctx.Tables.Sweep = table();
ctx.Tables.MeasuredSINRSummary = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "lls_measured_sinr_summary.csv"));
ctx.Tables.DLMeasuredSINRBLER = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_bler_curve.csv"));
ctx.Tables.ULMeasuredSINRBLER = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_bler_curve.csv"));
ctx.Tables.DLMeasuredSINRThroughput = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_throughput_curve.csv"));
ctx.Tables.ULMeasuredSINRThroughput = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_throughput_curve.csv"));
ctx.Tables.ReferenceSweep = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "lls_reference_snr_sweep.csv"));
ctx.Tables.DL = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
ctx.Tables.UL = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
ctx.Tables.DLConstellation = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_constellation_samples.csv"));
ctx.TableSources.DLConstellation = "air_interface/csv/dl_constellation_samples.csv";
if ~(istable(ctx.Tables.DLConstellation) && ~isempty(ctx.Tables.DLConstellation))
    ctx.Tables.DLConstellation = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_constellation_preview.csv"));
    ctx.TableSources.DLConstellation = "air_interface/csv/dl_constellation_preview.csv";
end
ctx.Tables.ULConstellation = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_constellation_samples.csv"));
ctx.TableSources.ULConstellation = "air_interface/csv/ul_constellation_samples.csv";
if ~(istable(ctx.Tables.ULConstellation) && ~isempty(ctx.Tables.ULConstellation))
    ctx.Tables.ULConstellation = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_constellation_preview.csv"));
    ctx.TableSources.ULConstellation = "air_interface/csv/ul_constellation_preview.csv";
end
ctx.Tables.PBCH = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"));
ctx.Tables.PRACH = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"));
ctx.Tables.PRACHCorrelationTrace = localReadOptionalTable(fullfile(layout.ReportCSVDir, "prach_correlation_trace.csv"));
if ~(istable(ctx.Tables.PRACHCorrelationTrace) && ~isempty(ctx.Tables.PRACHCorrelationTrace))
    ctx.Tables.PRACHCorrelationTrace = localReadOptionalTable(fullfile(layout.ReportCSVDir, "prach_correlation_traces.csv"));
end
ctx.Tables.PDCCH = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"));
ctx.Tables.PUCCH = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"));
ctx.Tables.SRS = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"));
ctx.Tables.TRS = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"));
ctx.Tables.InitialAccessLifecycle = localReadOptionalTable(fullfile(layout.ControlCSVDir, "initial_access_lifecycle_trace.csv"));
if ~(istable(ctx.Tables.InitialAccessLifecycle) && ~isempty(ctx.Tables.InitialAccessLifecycle))
    ctx.Tables.InitialAccessLifecycle = localReadOptionalTable(fullfile(layout.ReportCSVDir, "initial_access_lifecycle_trace.csv"));
end
if istable(ctx.Tables.InitialAccessLifecycle) && ~isempty(ctx.Tables.InitialAccessLifecycle)
    ctx.Tables.InitialAccessLifecycle = ...
        sixgr.truth.deriveInitialAccessProcedureDelay(ctx.Tables.InitialAccessLifecycle);
    sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, ...
        "initial_access_lifecycle_trace.csv"), ctx.Tables.InitialAccessLifecycle);
end
ctx.Tables.CellSearch = localReadOptionalTable(fullfile(layout.ControlCSVDir, "cell_search_trials.csv"));
ctx.Tables.PBCHRecovery = localReadOptionalTable(fullfile(layout.ControlCSVDir, "pbch_recovery_trials.csv"));
ctx.Tables.Beam = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv"));
ctx.Tables.BeamManagement = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "probe_beam_management.csv"));
ctx.Tables.BeamScoreTrace = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "beam_score_trace.csv"));
ctx.Tables.BeamManagementStateTrace = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "beam_management_state_trace.csv"));
ctx.Tables.BeamManagementEventTrace = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "beam_management_event_trace.csv"));
ctx.Tables.SSBBeamSweep = localReadFirstOptionalTable({ ...
    fullfile(layout.BeamformingCSVDir, "ssb_pbch_sib1_beam_sweep.csv"), ...
    fullfile(layout.BeamformingCSVDir, "ssb_beam_sweep.csv"), ...
    fullfile(layout.ControlCSVDir, "ssb_pbch_sib1_beam_sweep.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "ssb_pbch_sib1_beam_sweep.csv")});
ctx.Tables.LiveBeamP1AcquisitionStats = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_beam_p1_acquisition_stats.csv"));
ctx.Tables.LiveBeamP2RefinementStats = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_beam_p2_refinement_stats.csv"));
ctx.Tables.LiveBeamProcedureStats = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_beam_management_procedure_stats.csv"));
ctx.Tables.LiveBeamSelectionStats = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_beam_selection_stats.csv"));
ctx.Tables.HARQPackets = localReadOptionalTable(fullfile(layout.HARQCSVDir, "probe_harq_packets.csv"));
ctx.Tables.HARQSummary = localReadOptionalTable(fullfile(layout.HARQCSVDir, "probe_harq_summary.csv"));
ctx.Tables.HARQTimeline = localReadOptionalTable(fullfile(layout.HARQCSVDir, "harq_process_timeline.csv"));
ctx.Tables.ApplicationPackets = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_application_packet_delivery_ledger.csv"));
ctx.Tables.KPIReconstruction = localReadOptionalTable(fullfile(layout.ReportCSVDir, "kpi_reconstruction_summary.csv"));
ctx.Tables.RFEnergy = localReadOptionalTable(fullfile(layout.RFCSVDir, "probe_rf_energy.csv"));
ctx.Tables.EnergyTimeline = localReadOptionalTable(fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"));
ctx.Tables.MultiUser = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "multiuser_user_summary.csv"));
ctx.Tables.AIMetadata = localReadOptionalTable(fullfile(layout.ReportCSVDir, "ai_benchmark_metadata.csv"));
ctx.Tables.AIBenchmarks = localReadOptionalTableCollection(fullfile(layout.ReportCSVDir, "ai_*benchmark*.csv"));
ctx.AggregateArtifacts = struct();
end

function T = localReadOptionalTable(path)
T = table();
if exist(path, "file") ~= 2
    return;
end
try
    T = sixgr.util.csvReadTable(path);
catch
    T = table();
end
end

function T = localReadFirstOptionalTable(paths)
T = table();
if nargin < 1 || isempty(paths)
    return;
end
for i = 1:numel(paths)
    Ti = localReadOptionalTable(paths{i});
    if istable(Ti) && ~isempty(Ti)
        T = Ti;
        return;
    end
end
end

function S = localReadOptionalTableCollection(pattern)
files = dir(pattern);
S = struct();
for i = 1:numel(files)
    path = fullfile(files(i).folder, files(i).name);
    key = matlab.lang.makeValidName(erase(files(i).name, ".csv"));
    S.(key) = localReadOptionalTable(path);
end
end

function T = localBuildValidationMessageTable(ctx)
rows = repmat(struct("Severity", "", "Source", "", "Message", ""), 0, 1);

rows(end+1, 1) = struct( ... %#ok<AGROW>
    "Severity", "info", ...
    "Source", "schema_validation", ...
    "Message", "Scenario configuration resolved and validated before execution.");

if isfield(ctx.RuntimeSummary, "Warnings") && ~isempty(ctx.RuntimeSummary.Warnings)
    warns = string(ctx.RuntimeSummary.Warnings(:));
    for i = 1:numel(warns)
        rows(end+1, 1) = struct( ... %#ok<AGROW>
            "Severity", "warning", ...
            "Source", "runtime", ...
            "Message", warns(i));
    end
end

linkErrors = string(sixgr.util.structGet(ctx.Result, "Link.Errors", strings(0, 1)));
for i = 1:numel(linkErrors)
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "Severity", "error", ...
        "Source", "link_bundle", ...
        "Message", linkErrors(i));
end

unsupported = sixgr.util.structGet(ctx.Result, "Link.UnsupportedCases", table());
if istable(unsupported) && ~isempty(unsupported)
    for i = 1:height(unsupported)
        msg = "Unsupported truth-profile case pruned: " + string(localTableString(unsupported, i, "Case"));
        rows(end+1, 1) = struct( ... %#ok<AGROW>
            "Severity", "warning", ...
            "Source", "truth_profile", ...
            "Message", msg);
    end
end

T = struct2table(rows);
end

function T = localBuildArtifactInventory(runFolder, rows)
if nargin < 2
    rows = localEmptyMetricTable();
end
files = dir(fullfile(runFolder, "**", "*"));
metricRows = rows;
invRows = repmat(struct("RelativePath", "", "Extension", "", "Bytes", NaN, "ModifiedUTC", "", ...
    "ArtifactClass", "", "SemanticState", "", "CountsTowardCoverage", false, "MachineReadable", false, "HumanReadable", false), 0, 1);
for i = 1:numel(files)
    f = files(i);
    if f.isdir
        continue;
    end
    absolutePath = fullfile(f.folder, f.name);
    if sixgr.runtime.isNestedExecutionPath(runFolder, absolutePath)
        continue;
    end
    rel = localPortablePath(string(strrep(absolutePath, [char(runFolder) filesep], "")));
    ext = "";
    if contains(f.name, ".")
        [~, ~, ext0] = fileparts(f.name);
        ext = lower(string(ext0));
    end
    className = localArtifactClass(rel, ext);
    semanticState = localArtifactInventorySemanticState(rel, metricRows);
    invRows(end+1, 1) = struct( ... %#ok<AGROW>
        "RelativePath", rel, ...
        "Extension", ext, ...
        "Bytes", double(f.bytes), ...
        "ModifiedUTC", string(datetime(f.datenum, "ConvertFrom", "datenum", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
        "ArtifactClass", className, ...
        "SemanticState", semanticState, ...
        "CountsTowardCoverage", logical(localCoverageStateCountsTowardCoverage(semanticState)), ...
        "MachineReadable", any(strcmp(ext, [".csv" ".json" ".mat" ".yaml" ".yml"])), ...
        "HumanReadable", any(strcmp(ext, [".md" ".png" ".jpg" ".jpeg" ".svg"])));
end
T = struct2table(invRows);
if ~isempty(T)
    T = sortrows(T, "RelativePath");
end
end

function invRows = localAppendUnavailableCardInventoryAliases(runFolder, invRows, metricRows)
if ~(istable(metricRows) && ~isempty(metricRows) && ...
        ismember("SourceArtifact", string(metricRows.Properties.VariableNames)) && ...
        ismember("Availability", string(metricRows.Properties.VariableNames)))
    return;
end
sources = localPortablePath(string(metricRows.SourceArtifact));
states = lower(strtrim(string(metricRows.Availability)));
aliasMask = strlength(sources) > 0 & endsWith(lower(sources), ".png") & ...
    ismember(states, ["placeholder","disabled"]);
for i = find(aliasMask(:).')
    rel = sources(i);
    if any(string({invRows.RelativePath}) == rel)
        continue;
    end
    [folderPart, baseName, ~] = fileparts(char(rel));
    cardRel = localPortablePath(fullfile(folderPart, string(baseName) + "_unavailable.png"));
    cardAbs = fullfile(runFolder, strrep(char(cardRel), '/', filesep));
    targetAbs = fullfile(runFolder, strrep(char(rel), '/', filesep));
    if exist(targetAbs, "file") == 2 || exist(cardAbs, "file") ~= 2
        continue;
    end
    semanticState = localRollupAvailabilityState(states(sources == rel));
    invRows(end+1, 1) = struct( ... %#ok<AGROW>
        "RelativePath", rel, ...
        "Extension", ".png", ...
        "Bytes", 0, ...
        "ModifiedUTC", "", ...
        "ArtifactClass", localArtifactClass(rel, ".png"), ...
        "SemanticState", semanticState, ...
        "CountsTowardCoverage", false, ...
        "MachineReadable", false, ...
        "HumanReadable", true);
end
end

function state = localArtifactInventorySemanticState(relPath, rows)
portableRel = localPortablePath(relPath);
state = localInferAvailabilityFromSource(portableRel);
if ~(istable(rows) && ~isempty(rows) && ismember("SourceArtifact", string(rows.Properties.VariableNames)) && ismember("Availability", string(rows.Properties.VariableNames)))
    return;
end
sources = localPortablePath(string(rows.SourceArtifact));
mask = strlength(sources) > 0 & sources == portableRel;
if any(mask)
    state = localRollupAvailabilityState(string(rows.Availability(mask)));
end
end

function className = localArtifactClass(rel, ext)
rel = lower(string(rel));
if startsWith(rel, "meta/")
    className = "metadata";
elseif startsWith(rel, "reports/")
    className = "report";
elseif startsWith(rel, "air_interface/")
    className = "air_interface";
elseif startsWith(rel, "control/")
    className = "control";
elseif startsWith(rel, "beamforming/")
    className = "beamforming";
elseif startsWith(rel, "logs/")
    className = "log";
else
    className = "other";
end
if ext == ".png"
    className = className + "_image";
elseif ext == ".csv"
    className = className + "_csv";
end
end

function rows = localBuildCategoryRows(catalog, ctx)
rows = localEmptyMetricTable();
for i = 1:numel(catalog.categories)
    cat = catalog.categories(i);
    metrics = cat.metrics;
    for j = 1:numel(metrics)
        metric = metrics(j);
        resolved = localResolveMetricRows(cat, metric, ctx);
        if isempty(resolved)
            if ~localSuppressUnmeasuredPrimaryRows(cat)
                resolved = localMetricTableRow(cat, metric, "", "", "not_available", NaN, "", "", "", ...
                    "Not emitted by this run or not modeled by the current LLS path.");
            end
        end
        if isempty(resolved)
            continue;
        end
        rows = [rows; resolved]; %#ok<AGROW>
    end
end
end

function tf = localSuppressUnmeasuredPrimaryRows(cat)
% Beam-management primary rows must be measured artifacts only. Coverage CSVs
% still report catalog gaps, but the primary table should not be padded.
tf = string(cat.key) == "beam_management_outputs";
end

function T = localResolveMetricRows(cat, metric, ctx)
key = string(metric.key);
T = localEmptyMetricTable();

switch key
    case "scenario_identifiers"
        T = [T; ...
            localMetricTableRow(cat, metric, "scenario", "id", "available", NaN, string(ctx.ScenarioConfig.ScenarioID), "", "", ""); ...
            localMetricTableRow(cat, metric, "scenario", "family", "available", NaN, string(ctx.ScenarioConfig.get("meta.scenario_family", "")), "", "", ""); ...
            localMetricTableRow(cat, metric, "scenario", "name", "available", NaN, string(ctx.ScenarioConfig.get("meta.scenario_name", ctx.ScenarioConfig.get("meta.description", ""))), "", "", "")];
    case "resolved_config"
        T = [T; ...
            localMetricTableRow(cat, metric, "config", "json", "available", NaN, "meta/scenario_config_resolved.json", "", "meta/scenario_config_resolved.json", ""); ...
            localMetricTableRow(cat, metric, "config", "yaml", "available", NaN, "meta/scenario_config_resolved.yaml", "", "meta/scenario_config_resolved.yaml", ""); ...
            localMetricTableRow(cat, metric, "config", "source_chain", "available", NaN, "meta/scenario_source_chain.csv", "", "meta/scenario_source_chain.csv", "")];
    case "simulator_version"
        T = localMetricTableRow(cat, metric, "simulator", "version", "available", NaN, string(ctx.Manifest.CodeVersion), "", "", string(ctx.Manifest.CodeDetail));
    case "git_hash"
        T = localMetricTableRow(cat, metric, "simulator", "git", "available", NaN, string(ctx.Manifest.CodeVersion), "", "", string(ctx.Manifest.CodeDetail));
    case "seed"
        T = localMetricTableRow(cat, metric, "run", "seed", "available", double(ctx.Manifest.RandomSeed), "", "", "", "");
    case "execution_timestamp"
        T = [T; ...
            localMetricTableRow(cat, metric, "run", "generated_utc", "derived", NaN, string(ctx.Manifest.GeneratedUTC), "", "meta/scenario_manifest.json", "Timestamp persisted by the run manifest."); ...
            localMetricTableRow(cat, metric, "run", "started_utc", localRuntimeTimestampAvailability(ctx, "StartedUTC"), NaN, string(sixgr.util.structGet(ctx.RuntimeSummary, "StartedUTC", "")), "", "meta/runtime_summary.json", "Timestamp persisted by the runtime summary."); ...
            localMetricTableRow(cat, metric, "run", "completed_utc", localRuntimeTimestampAvailability(ctx, "CompletedUTC"), NaN, string(sixgr.util.structGet(ctx.RuntimeSummary, "CompletedUTC", "")), "", "meta/runtime_summary.json", "Timestamp persisted by the runtime summary.")];
    case "hardware_software_environment"
        if exist(fullfile(ctx.Layout.MetaDir, "environment.json"), "file") == 2
            T = localMetricTableRow(cat, metric, "environment", "summary", "available", NaN, "meta/environment.json", "", "meta/environment.json", "");
        end
    case "runtime_summary"
        if exist(fullfile(ctx.Layout.MetaDir, "runtime_summary.json"), "file") == 2
            elapsedSeconds = str2double(string(sixgr.util.structGet( ...
                ctx.RuntimeSummary, "ElapsedSeconds", NaN)));
            if ~isscalar(elapsedSeconds)
                elapsedSeconds = NaN;
            end
            T = [T; ...
                localMetricTableRow(cat, metric, "runtime", "elapsed_seconds", ...
                    localRuntimeNumericAvailability(ctx, "ElapsedSeconds"), ...
                    elapsedSeconds, "", "s", "meta/runtime_summary.json", ...
                    "Elapsed time persisted by the runtime summary when the completed runtime recorded a finite duration."); ...
                localMetricTableRow(cat, metric, "runtime", "summary_json", "available", NaN, "meta/runtime_summary.json", "", "meta/runtime_summary.json", "")];
        end
    case "warnings_validation_messages"
        T = localMetricTableRow(cat, metric, "validation", "message_count", "available", double(height(ctx.ValidationMessages)), "", "count", "reports/csv/validation_messages.csv", "");
    case "baseline_candidate_tags"
        tags = string(sixgr.util.structGet(ctx.ScenarioConfig.toStruct(), "meta.tags", strings(0, 1)));
        T = [T; ...
            localMetricTableRow(cat, metric, "meta", "study_status", "available", NaN, string(ctx.ScenarioConfig.get("meta.study_status", ctx.ScenarioConfig.get("meta.maturity_tag", ""))), "", "", ""); ...
            localMetricTableRow(cat, metric, "meta", "baseline_reference_name", "available", NaN, string(ctx.ScenarioConfig.get("meta.baseline_reference_name", "")), "", "", ""); ...
            localMetricTableRow(cat, metric, "meta", "tags", "available", NaN, strjoin(tags, "|"), "", "", "")];
    case "configured_operating_point"
        T = localConfiguredOperatingPointRows(cat, metric, ctx);
    case "effective_layer_histogram"
        T = localEffectiveHistogramMetricRows(cat, metric, ctx, "Layers", "effective runtime-selected layer histogram derived from actual waveform trial tables.");
    case "effective_rank_histogram"
        T = localEffectiveHistogramMetricRows(cat, metric, ctx, "Rank", "effective transmitted-rank histogram derived from actual waveform Layers, with RankIndicator only as fallback when layer data is unavailable.");
    case "effective_modulation_histogram"
        T = localEffectiveHistogramMetricRows(cat, metric, ctx, "Modulation", "effective runtime-selected modulation histogram derived from actual waveform trial tables.");
    case "effective_mcs_histogram"
        T = localEffectiveHistogramMetricRows(cat, metric, ctx, "MCS", "effective runtime-selected MCS histogram derived from actual waveform trial tables.");

    case "bler_vs_snr_sinr_esn0"
        T = localMeasuredCurveMetricRows(cat, metric, ctx, "BLER", "fraction");
    case "ber_vs_snr_sinr_esn0"
        T = localMeasuredCurveMetricRows(cat, metric, ctx, "BER", "fraction");
    case "fer_tb_error_rate"
        T = [T; localFailureRateRows(cat, metric, ctx.Tables.DL, "DL"); localFailureRateRows(cat, metric, ctx.Tables.UL, "UL")];
    case "code_block_bler"
        T = [T; ...
            localRatioSummaryRows(cat, metric, ctx.Tables.DL, "CodeBlockErrors", "CodeBlockCount", "DL", "fraction", "air_interface/csv/dl_pdsch_trials.csv", ""); ...
            localRatioSummaryRows(cat, metric, ctx.Tables.UL, "CodeBlockErrors", "CodeBlockCount", "UL", "fraction", "air_interface/csv/ul_pusch_trials.csv", "")];
    case "cbg_bler"
        T = [T; ...
            localRatioSummaryRows(cat, metric, ctx.Tables.DL, "CBGErrors", "CBGCount", "DL", "fraction", "air_interface/csv/dl_pdsch_trials.csv", "Derived from TB-equivalent grouping when explicit CBG mode is disabled."); ...
            localRatioSummaryRows(cat, metric, ctx.Tables.UL, "CBGErrors", "CBGCount", "UL", "fraction", "air_interface/csv/ul_pusch_trials.csv", "Derived from TB-equivalent grouping when explicit CBG mode is disabled.")];
    case "throughput"
        T = localMeasuredThroughputCurveRows(cat, metric, ctx, "OfferedThroughput_Mbps_mean", "Mbps");
    case "goodput"
        T = localMeasuredThroughputCurveRows(cat, metric, ctx, "Goodput_Mbps_mean", "Mbps");
    case "spectral_efficiency"
        T = localMeasuredSummaryMetricRows(cat, metric, ctx, "SpectralEfficiency_mean_bps_Hz", "bit/s/Hz", "mean");
    case "user_perceived_throughput"
        T = localApplicationGoodputRows(cat, metric, ctx);
    case "required_snr_target_bler"
        T = localOracleFreeUnsupportedSNRRows(cat, metric, ["DL","UL"], ...
            "Geometry-driven oracle-free LLS derives receiver SINR from pathloss, shadow fading, fading channel, and equalisation. Required injected-SNR targets are intentionally not estimated.");
    case "outage_probability"
        T = [T; localFailureRateRows(cat, metric, ctx.Tables.DL, "DL"); localFailureRateRows(cat, metric, ctx.Tables.UL, "UL")];
    case "error_floor_region_characterization"
        T = [T; ...
            localMeasuredErrorFloorRows(cat, metric, ctx.Tables.DLMeasuredSINRBLER, "DL", "air_interface/csv/dl_measured_sinr_bler_curve.csv"); ...
            localMeasuredErrorFloorRows(cat, metric, ctx.Tables.ULMeasuredSINRBLER, "UL", "air_interface/csv/ul_measured_sinr_bler_curve.csv")];

    case "decoder_iterations"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "DecoderIterations", "DL", "iterations"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "DecoderIterations", "UL", "iterations")];
    case "early_stop_rate"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "EarlyStopRate", "DL", "fraction"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "EarlyStopRate", "UL", "fraction")];
    case "computation_complexity"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "DecoderComplexityUnits", "DL", "cb_bit_iterations"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "DecoderComplexityUnits", "UL", "cb_bit_iterations")];
    case "normalized_decoding_complexity"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "NormalizedDecoderComplexity", "DL", "complexity_per_bit"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "NormalizedDecoderComplexity", "UL", "complexity_per_bit")];
    case "latency_per_decode"
        note = "Latency-per-decode rows are exported from ComputeLatency_ms wall-clock decoder runtime. Radio/procedure delay remains in separate explicit metrics.";
        T = [T; ...
            localCustomNumericSummaryRows(cat, metric, ctx.Tables.DL, "ComputeLatency_ms", "DL_compute", "ms", "air_interface/csv/dl_pdsch_trials.csv", note); ...
            localCustomNumericSummaryRows(cat, metric, ctx.Tables.UL, "ComputeLatency_ms", "UL_compute", "ms", "air_interface/csv/ul_pusch_trials.csv", note)];
    case "area_efficiency_proxy"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "AreaEfficiencyProxy", "DL", "bits_per_complexity_unit"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "AreaEfficiencyProxy", "UL", "bits_per_complexity_unit")];
    case "snr_gain_same_complexity"
        T = localOracleFreeUnsupportedSNRRows(cat, metric, ["DL","UL"], ...
            "Same-complexity injected-SNR gain is not defined for geometry-driven oracle-free LLS. Use measured SINR and decoder-complexity traces directly.");
    case "complexity_reduction_same_bler"
        T = localOracleFreeUnsupportedSNRRows(cat, metric, ["DL","UL"], ...
            "Same-BLER complexity reduction against an injected-SNR reference sweep is not defined for geometry-driven oracle-free LLS.");
    case "evm"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "EVM_rms", "DL", "rms"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "EVM_rms", "UL", "rms")];
    case "constellation_scatter"
        T = [T; ...
            localArtifactMetricRows(cat, metric, char(ctx.RunFolder), "DL", "scatter_plot", "air_interface/image/dl_constellation_scatter.png", ...
                "Measured aligned-equalized, hard-decision, and reference DL constellation samples."); ...
            localArtifactMetricRows(cat, metric, char(ctx.RunFolder), "UL", "scatter_plot", "air_interface/image/ul_constellation_scatter.png", ...
                "Measured aligned-equalized, hard-decision, and reference UL constellation samples.")];
    case "symbol_error_rate"
        T = [T; ...
            localRatioSummaryRows(cat, metric, ctx.Tables.DL, "SymbolErrors", "SymbolsCompared", "DL", "fraction", "air_interface/csv/dl_pdsch_trials.csv", "Measured symbol decisions versus transmitted modulated symbols."); ...
            localRatioSummaryRows(cat, metric, ctx.Tables.UL, "SymbolErrors", "SymbolsCompared", "UL", "fraction", "air_interface/csv/ul_pusch_trials.csv", "Measured symbol decisions versus transmitted modulated symbols.")];
    case "papr_ccdf"
        aggPath = localAggregateArtifactPath(ctx, "PAPRCCDFPlot");
        hasData = localHasAnyFiniteColumn(ctx.Tables.DL, ["PAPR_dB"]) || localHasAnyFiniteColumn(ctx.Tables.UL, ["PAPR_dB"]);
        T = [T; ...
            localMetricTableRow(cat, metric, "DL_UL", "ccdf_plot", localDerivedOrPlaceholderAvailability(hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasData, "No finite runtime PAPR samples are available; the CCDF plot was omitted.")); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "PAPR_dB", "DL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "PAPR_dB", "UL", "dB")];
    case "peak_clipping_events"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "PeakClippingEvents", "DL", "count"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "PeakClippingEvents", "UL", "count")];
    case "shaping_rate_loss"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "ShapingRateLoss", "DL", "fraction"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "ShapingRateLoss", "UL", "fraction")];
    case "distribution_matching_latency"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "DistributionMatchingLatency_ms", "DL", "ms"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "DistributionMatchingLatency_ms", "UL", "ms")];
    case "modulation_mapping_sensitivity"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "ModulationMappingSensitivity", "DL", "relative_spread"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "ModulationMappingSensitivity", "UL", "relative_spread")];
    case "llr_reliability_imbalance_metrics"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "LLRImbalance", "DL", "relative_std"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "LLRImbalance", "UL", "relative_std")];
    case "high_order_modulation_robustness_under_impairments"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "HighOrderRobustness", "DL", "robustness_index"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "HighOrderRobustness", "UL", "robustness_index")];
    case "cb_size_distribution"
        T = [T; ...
            localDistributionRows(cat, metric, ctx.Tables.DL, "CodeBlockLength_bits", "DL", "bits", "air_interface/csv/dl_pdsch_trials.csv"); ...
            localDistributionRows(cat, metric, ctx.Tables.UL, "CodeBlockLength_bits", "UL", "bits", "air_interface/csv/ul_pusch_trials.csv")];
    case "segmentation_statistics"
        T = [T; ...
            localSegmentationRows(cat, metric, ctx.Tables.DL, "DL", "air_interface/csv/dl_pdsch_trials.csv"); ...
            localSegmentationRows(cat, metric, ctx.Tables.UL, "UL", "air_interface/csv/ul_pusch_trials.csv")];
    case "puncturing_shortening_statistics"
        T = [T; ...
            localPuncturingRows(cat, metric, ctx.Tables.DL, "DL", "air_interface/csv/dl_pdsch_trials.csv"); ...
            localPuncturingRows(cat, metric, ctx.Tables.UL, "UL", "air_interface/csv/ul_pusch_trials.csv")];
    case "ce_nmse"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "NMSE_dB", "SRS", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "NMSE_dB", "TRS", "dB")];
    case "cfo_rmse"
        T = localRMSETrialRows(cat, metric, ctx.Tables.PBCH, "CFOError_Hz", "PBCH", "Hz", "air_interface/csv/pbch_trials.csv");
    case "to_rmse"
        T = [T; ...
            localRMSETrialRows(cat, metric, ctx.Tables.PBCH, "TimingError_samples", "PBCH", "samples", "air_interface/csv/pbch_trials.csv"); ...
            localRMSETrialRows(cat, metric, ctx.Tables.DL, "TimingError_samples", "DL", "samples", "air_interface/csv/dl_pdsch_trials.csv"); ...
            localRMSETrialRows(cat, metric, ctx.Tables.UL, "TimingError_samples", "UL", "samples", "air_interface/csv/ul_pusch_trials.csv")];
    case "doppler_rmse"
        T = [T; ...
            localRMSETrialRows(cat, metric, ctx.Tables.DL, "DopplerError_Hz", "DL", "Hz", "air_interface/csv/dl_pdsch_trials.csv"); ...
            localRMSETrialRows(cat, metric, ctx.Tables.UL, "DopplerError_Hz", "UL", "Hz", "air_interface/csv/ul_pusch_trials.csv"); ...
            localRMSETrialRows(cat, metric, ctx.Tables.TRS, "DopplerError_Hz", "TRS", "Hz", "air_interface/csv/trs_trials.csv")];
    case "phase_tracking_error"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "PhaseTrackingError_deg", "DL", "deg"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "PhaseTrackingError_deg", "UL", "deg"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "PhaseTrackingError_deg", "TRS", "deg")];
    case "qcl_estimation_accuracy"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "QCLAccuracy", "DL", "correlation"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "QCLAccuracy", "UL", "correlation"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "QCLAccuracy", "SRS", "correlation"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "QCLAccuracy", "TRS", "correlation")];
    case "channel_aging_loss"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "ChannelAgingLoss_dB", "DL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "ChannelAgingLoss_dB", "UL", "dB")];
    case "interpolation_loss"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "InterpolationLoss_dB", "DL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "InterpolationLoss_dB", "UL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "InterpolationLoss_dB", "SRS", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "InterpolationLoss_dB", "TRS", "dB")];
    case "mismatch_sensitivity"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "MismatchSensitivity_dB", "DL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "MismatchSensitivity_dB", "UL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "MismatchSensitivity_dB", "SRS", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "MismatchSensitivity_dB", "TRS", "dB")];
    case "acquisition_time"
        note = "Tracking acquisition time is exported as radio-time observation duration, not wall-clock compute time.";
        T = [T; ...
            localCustomNumericSummaryRows(cat, metric, ctx.Tables.PBCH, "AirInterfaceObservation_ms", "PBCH", "ms", "air_interface/csv/pbch_trials.csv", note); ...
            localCustomNumericSummaryRows(cat, metric, ctx.Tables.SRS, "AirInterfaceObservation_ms", "SRS", "ms", "air_interface/csv/srs_trials.csv", note); ...
            localCustomNumericSummaryRows(cat, metric, ctx.Tables.TRS, "AirInterfaceObservation_ms", "TRS", "ms", "air_interface/csv/trs_trials.csv", note)];
    case "tracking_failure_probability"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.PBCH, "TrackingFailureProbability", "PBCH", "fraction"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "TrackingFailureProbability", "SRS", "fraction"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "TrackingFailureProbability", "TRS", "fraction")];
    case "miss_detection_probability"
        T = [T; ...
            localFailureRateRows(cat, metric, ctx.Tables.PDCCH, "PDCCH"); ...
            localFailureRateRows(cat, metric, ctx.Tables.PUCCH, "PUCCH"); ...
            localPrachFailureRateRows(cat, metric, ctx); ...
            localFailureRateRows(cat, metric, ctx.Tables.PBCH, "PBCH")];
    case "false_alarm_probability"
        T = localIndicatorRateRows(cat, metric, ctx.Tables.PDCCH, "FalseAlarmFlag", "PDCCH", "air_interface/csv/pdcch_trials.csv", ...
            "Measured from a noise-only PDCCH decode attempt for each runtime trial.");
    case "blocking_probability"
        T = localIndicatorRateRows(cat, metric, ctx.Tables.PDCCH, "BlockingFlag", "PDCCH", "air_interface/csv/pdcch_trials.csv", ...
            "Measured from actual aggregation-level demand versus configured CORESET CCE capacity.");
    case "blind_decode_count"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.PDCCH, "BlindDecodeCount", "PDCCH", "count");
    case "non_overlapped_cce_usage"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.PDCCH, "NonOverlappedCCEUsage", "PDCCH", "fraction");
    case "aggregation_level_distribution"
        T = localDistributionRows(cat, metric, ctx.Tables.PDCCH, "AggregationLevel", "PDCCH", "CCE", "air_interface/csv/pdcch_trials.csv");
    case "dci_size_distribution"
        T = localDistributionRows(cat, metric, ctx.Tables.PDCCH, "DCISize_bits", "PDCCH", "bits", "air_interface/csv/pdcch_trials.csv");
    case "control_capacity_under_load"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.PDCCH, "ControlCapacityUtilization", "PDCCH", "fraction");
    case "coreset_utilization"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.PDCCH, "CORESETUtilization", "PDCCH", "fraction");
    case "control_latency"
        T = localControlLatencyRows(cat, metric, ctx);
    case "detection_feedback_effectiveness"
        T = localPDCCHFeatureMetricRows(cat, metric, ctx, "detection_feedback");
    case "pdcch_repetition_gain"
        T = localPDCCHFeatureMetricRows(cat, metric, ctx, "repetition_gain");
    case "pdcch_monitoring_energy"
        T = localProbeMetricRows(cat, metric, ctx.Tables.RFEnergy, "pdcch_monitoring_energy", ctx);
    case "invalid_detection_power_cost"
        T = localInvalidDetectionPowerCostRows(cat, metric, ctx);
    case "puncturing_exclusion_sensitivity"
        T = localPDCCHFeatureMetricRows(cat, metric, ctx, "puncturing_exclusion");
    case "mrss_impact_on_control"
        T = localPDCCHFeatureMetricRows(cat, metric, ctx, "mrss_impact");
    case "per_layer_bler"
        T = localPerLayerBLERRows(cat, metric, ctx.Tables.DL);
    case "per_codeword_bler"
        T = localPerCodewordBLERRows(cat, metric, ctx.Tables.DL);
    case "per_rank_throughput"
        T = localPerRankThroughputRows(cat, metric, ctx.Tables.DL);
    case "equalizer_output_sinr"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "PostEqSINR_dB", "DL", "dB");
    case "residual_interference_power"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "ResidualInterferencePower_dB", "DL", "dB");
    case "beam_precoder_gain"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.Beam, "ChannelGain_dB", "beamforming", "dB");
    case "harq_gain_per_retransmission"
        T = localProbeMetricRows(cat, metric, ctx.Tables.HARQSummary, "harq_gain_per_retransmission", ctx);
    case "rate_matching_overhead"
        T = localRateMatchingOverheadRows(cat, metric, ctx.Tables.DL, "DL");
    case "rs_overhead_contribution"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "RSOverheadFraction", "DL", "fraction");
    case "mtrp_gain"
        T = localProbeMetricRows(cat, metric, ctx.Tables.BeamManagement, "mtrp_beam_selection_gain", ctx);
    case "detector_complexity"
        T = localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "DetectorComplexityUnits_Modulation", "DL", "detector_ops");
    case "ul_bler_throughput"
        T = [T; ...
            localFailureRateRows(cat, metric, ctx.Tables.UL, "UL"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "TBSize_bits", "UL_good_block_size", "bits")];
    case "low_papr_gain"
        T = localLowPAPRRows(cat, metric, ctx);
    case "pa_backoff_impact"
        T = localPABackoffImpactRows(cat, metric, ctx);
    case "prep_time_related_impact"
        T = localPrepTimeImpactRows(cat, metric, ctx);
    case "uci_multiplexing_efficiency"
        T = localUCIMultiplexingEfficiencyRows(cat, metric, ctx);
    case "simultaneous_pucch_pusch_behavior"
        T = localSimultaneousPUSCHPUCCHRows(cat, metric, ctx);
    case "power_control_convergence"
        T = localPowerControlConvergenceRows(cat, metric, ctx);
    case "dmrs_estimation_quality"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "NMSE_dB", "UL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "NMSE_dB", "SRS", "dB")];
    case "msg3_specific_success_metrics"
        T = localMsg3SpecificSuccessRows(cat, metric, ctx);
    case "cqi_accuracy"
        T = localCQIAccuracyRows(cat, metric, ctx);
    case "pmi_accuracy"
        T = localPMIAccuracyRows(cat, metric, ctx);
    case "ri_accuracy"
        T = localRIAccuracyRows(cat, metric, ctx);
    case "l1_sinr_accuracy"
        T = localL1SINRAccuracyRows(cat, metric, ctx);
    case "rsrp_accuracy"
        T = localRSRPAccuracyRows(cat, metric, ctx);
    case "csi_report_size"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "CSIPayloadBitLength", "DL", "bits"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "CSIPayloadBitLength", "UL", "bits")];
    case "csi_reporting_overhead"
        T = [T; ...
            localPayloadOverheadRows(cat, metric, ctx.Tables.DL, "DL"); ...
            localPayloadOverheadRows(cat, metric, ctx.Tables.UL, "UL")];
    case "report_latency"
        T = localCSIReportLatencyRows(cat, metric, ctx);
    case "csi_aging_loss"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "ChannelAgingLoss_dB", "DL", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "ChannelAgingLoss_dB", "UL", "dB")];
    case "scheduler_application_loss"
        T = localSchedulerApplicationLossRows(cat, metric, ctx);
    case "sgcs"
        T = localSGCSRows(cat, metric, ctx);
    case "nmse"
        T = [T; ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "NMSE_dB", "SRS", "dB"); ...
            localNumericTrialSummaryRows(cat, metric, ctx.Tables.TRS, "NMSE_dB", "TRS", "dB")];
    case "dmrs_vs_csirs_comparison"
        T = localDMRSVsCSIRSComparisonRows(cat, metric, ctx);
    case "srs_port_scaling_impact"
        T = localSRSPortScalingImpactRows(cat, metric, ctx);
    case "reciprocity_mismatch_impact"
        T = localReciprocityMismatchRows(cat, metric, ctx);
    case "analog_jscc_jscm_robustness_metrics"
        T = localAnalogJSCCJSCMRows(cat, metric, ctx);
    case {"beam_detection_probability","beam_index_hit_rate","top_k_beam_hit_rate","beam_switch_latency", ...
            "beam_misalignment_probability","beam_prediction_accuracy","beam_refinement_convergence", ...
            "beam_failure_rate","mtrp_beam_selection_gain","beam_management_overhead"}
        T = localBeamManagementMetricRows(cat, metric, ctx, key);
    case "one_shot_ssb_detection_probability"
        T = localPassRateRows(cat, metric, ctx.Tables.PBCH, "PBCH");
    case "cell_id_detection_success"
        T = localPassRateRows(cat, metric, ctx.Tables.PBCH, "cell_search_pbch");
    case "pbch_decode_success"
        T = localPassRateRows(cat, metric, ctx.Tables.PBCH, "PBCH");
    case "initial_access_latency"
        T = localInitialAccessLatencyRows(cat, metric, ctx);
    case "search_complexity"
        T = localInitialAccessSearchComplexityRows(cat, metric, ctx);
    case "pbch_repetition_gain"
        T = localRepetitionGainRows(cat, metric, ctx, "PBCH", ...
            ["signals_and_channels_common.pbch.repetition_count", "initial_access.pbch.repetition_count", "pbch.repetition_count"], ...
            ctx.Tables.PBCH, "air_interface/csv/pbch_trials.csv");
    case "ssb_repetition_gain"
        T = localRepetitionGainRows(cat, metric, ctx, "SSB", ...
            ["signals_and_channels_common.ssb.repetition_count", "initial_access.ssb.repetition_count", "ssb.repetition_count"], ...
            ctx.Tables.CellSearch, "control/csv/cell_search_trials.csv");
    case "prach_detection_probability"
        T = localPrachPassRateRows(cat, metric, ctx);
    case "prach_false_alarm"
        T = localPRACHFalseAlarmRows(cat, metric, ctx);
    case "ta_error"
        T = localTAErrorRows(cat, metric, ctx);
    case "preamble_collision_statistics"
        T = localPreambleCollisionRows(cat, metric, ctx);
    case "ro_utilization"
        T = localROUtilizationRows(cat, metric, ctx);
    case "access_success_probability"
        T = localAccessSuccessRows(cat, metric, ctx);
    case "access_delay_cdf"
        T = localAccessDelayCDFRows(cat, metric, ctx);
    case "beam_pair_acquisition_success"
        T = localBeamPairAcquisitionRows(cat, metric, ctx);
    case "msg3_decode_success"
        T = localMsg3SpecificSuccessRows(cat, metric, ctx);
    case "initial_access_energy"
        T = localInitialAccessEnergyRows(cat, metric, ctx);
    case "clustering_gain_penalty"
        T = localClusteringGainPenaltyRows(cat, metric, ctx);
    case {"rtt_distribution","retransmission_count_distribution","combining_gain","ack_nack_dtx_distribution", ...
            "feedback_overhead","stop_condition_distribution","latency_percentile","reliability_percentile", ...
            "control_miss_induced_harq_penalties","parity_cb_packet_level_coding_benefits"}
        T = localProbeMetricRows(cat, metric, ctx.Tables.HARQSummary, key, ctx);
    case {"ue_energy_per_successful_bit","ue_energy_per_slot_frame_burst","gnb_energy_per_successful_bit", ...
            "gnb_active_sleep_duty_cycle","rf_chain_active_time","bb_processing_energy", ...
            "pdcch_monitoring_energy_metric","ssb_pbch_common_signal_energy", ...
            "prach_common_channel_clustering_energy_effect","bandwidth_adaptation_energy_effect", ...
            "race_to_sleep_gains","throughput_per_watt","energy_delay_product", ...
            "energy_spectral_efficiency_tradeoff"}
        T = localProbeMetricRows(cat, metric, ctx.Tables.RFEnergy, key, ctx);
    case "runtime_per_block"
        T = localRuntimePerBlockRows(cat, metric, ctx);
    case "peak_memory"
        T = localMemoryMetricRows(cat, metric, ctx, "peak");
    case "average_memory"
        T = localMemoryMetricRows(cat, metric, ctx, "average");
    case "number_of_model_invocations"
        T = localModelInvocationRows(cat, metric, ctx);
    case "flops_macs_estimate"
        T = localOpsEstimateRows(cat, metric, ctx);
    case "inference_latency"
        T = localInferenceLatencyRows(cat, metric, ctx);
    case "decode_latency"
        T = localDecodeLatencyRows(cat, metric, ctx);
    case "fft_ce_equalizer_detector_cost"
        T = localSignalProcessingCostRows(cat, metric, ctx);
    case "per_feature_complexity_breakdown"
        T = localFeatureComplexityBreakdownRows(cat, metric, ctx);
    case "model_parameters"
        T = localAIModelParameterRows(cat, metric, ctx);
    case "ai_flops"
        T = localAIFLOPsRows(cat, metric, ctx);
    case "memory_footprint"
        T = localAIMemoryFootprintRows(cat, metric, ctx);
    case "operation_frequency"
        T = localAIOperationFrequencyRows(cat, metric, ctx);
    case "ai_inference_latency"
        T = localAIInferenceLatencyRows(cat, metric, ctx);
    case "generalization_bands"
        T = localAIGeneralizationRows(cat, metric, ctx, "band_generalization_sweeps", "bands");
    case "generalization_speeds"
        T = localAIGeneralizationRows(cat, metric, ctx, "speed_generalization_sweeps", "speeds");
    case "generalization_delay_spreads"
        T = localAIGeneralizationRows(cat, metric, ctx, "delay_spread_generalization_sweeps", "delay_spreads");
    case "generalization_channels"
        T = localAIGeneralizationRows(cat, metric, ctx, "channel_generalization_sweeps", "channels");
    case "generalization_arrays"
        T = localAIGeneralizationRows(cat, metric, ctx, "array_generalization_sweeps", "arrays");
    case "generalization_impairments"
        T = localAIGeneralizationImpairmentRows(cat, metric, ctx);
    case "train_test_mismatch_loss"
        T = localAITrainTestMismatchRows(cat, metric, ctx);
    case "confidence_score_statistics"
        T = localAIConfidenceRows(cat, metric, ctx);
    case "fallback_rate"
        T = localAIFallbackRows(cat, metric, ctx);
    case "robustness_under_quantization"
        T = localAIQuantizationRobustnessRows(cat, metric, ctx);
    case "robustness_under_rf_impairments"
        T = localAIRobustnessImpairmentRows(cat, metric, ctx);
    case "performance_complexity_frontier"
        T = localAIPerformanceComplexityFrontierRows(cat, metric, ctx);
    case "baseline_delta"
        T = localAIBaselineDeltaRows(cat, metric, ctx);
    case "selected_waveforms"
        T = [T; ...
            localMetricTableRow(cat, metric, "waveform", "dl_waveform", "available", NaN, string(ctx.ScenarioConfig.get("waveform.dl_waveform", "")), "", "", ""); ...
            localMetricTableRow(cat, metric, "waveform", "ul_waveform", "available", NaN, string(ctx.ScenarioConfig.get("waveform.ul_waveform", "")), "", "", "")];
    case "channel_snapshots"
        csvPath = localDebugArtifactPath(ctx, "ChannelSnapshotsCSV");
        T = localMetricTableRow(cat, metric, "trace", "channel_snapshots_csv", localChannelSnapshotArtifactAvailability(ctx), NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), ...
            "Combined per-trial channel-state snapshot derived from actual DL, UL, SRS, TRS, PBCH, and PRACH trial exports.");
    case "channel_estimates"
        T = [T; ...
            localMetricTableRow(cat, metric, "trace", "srs_trials", localTableAvailability(ctx.Tables.SRS), NaN, "air_interface/csv/srs_trials.csv", "", "air_interface/csv/srs_trials.csv", ""); ...
            localMetricTableRow(cat, metric, "trace", "trs_trials", localTableAvailability(ctx.Tables.TRS), NaN, "air_interface/csv/trs_trials.csv", "", "air_interface/csv/trs_trials.csv", "")];
    case "equalized_constellations"
        csvPath = localDebugArtifactPath(ctx, "EqualizedConstellationsCSV");
        imgPath = localDebugArtifactPath(ctx, "EqualizedConstellationsImage");
        avail = localConstellationArtifactAvailability(ctx);
        T = [T; ...
            localMetricTableRow(cat, metric, "trace", "equalized_constellations_csv", avail, NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), "Combined constellation sample table with reference, aligned-equalized, and hard-decision symbols from actual DL and UL runtime exports."); ...
            localMetricTableRow(cat, metric, "trace", "equalized_constellations_image", avail, NaN, localPortablePath(imgPath), "", localPortablePath(imgPath), "Combined aligned-equalized and hard-decision scatter image from actual DL and UL runtime exports.")];
    case "phy_signal_diagnostics"
        csvPath = fullfile(ctx.Layout.ReportCSVDir, "phy_signal_diagnostic_source.csv");
        dlImgPath = fullfile(ctx.Layout.ReportImageDir, "dl_phy_signal_diagnostic.png");
        ulImgPath = fullfile(ctx.Layout.ReportImageDir, "ul_phy_signal_diagnostic.png");
        diagnosticAvailability = localPHYSignalDiagnosticArtifactAvailability(ctx);
        note = "Diagnostic-only visualization from one bounded actual PHY trial per direction. Source rows must retain SourceArtifact=runtime_phy_arrays_same_trial, truth_status=real_lls_evidence, and CurveConstruction=runtime_same_trial_phy_signal_snapshot; proxy, fallback, and synthetic reconstruction are not accepted.";
        if strlength(string(diagnosticAvailability.Reason)) > 0
            note = note + " Availability gate: " + string(diagnosticAvailability.Reason) + ".";
        end
        T = [T; ...
            localMetricTableRow(cat, metric, "DL_UL", "phy_signal_diagnostic_source_csv", diagnosticAvailability.Source, NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), note); ...
            localMetricTableRow(cat, metric, "DL", "dl_phy_signal_diagnostic_image", diagnosticAvailability.DL, NaN, localPortablePath(dlImgPath), "", localPortablePath(dlImgPath), note); ...
            localMetricTableRow(cat, metric, "UL", "ul_phy_signal_diagnostic_image", diagnosticAvailability.UL, NaN, localPortablePath(ulImgPath), "", localPortablePath(ulImgPath), note)];
    case "llr_histograms"
        csvPath = localDebugArtifactPath(ctx, "LLRHistogramsCSV");
        imgPath = localDebugArtifactPath(ctx, "LLRHistogramsImage");
        avail = localLLRHistogramArtifactAvailability(ctx);
        T = [T; ...
            localMetricTableRow(cat, metric, "trace", "llr_histograms_csv", avail, NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), "Histogram bins derived from actual LLR summary statistics emitted by the DL and UL trial tables."); ...
            localMetricTableRow(cat, metric, "trace", "llr_histograms_image", avail, NaN, localPortablePath(imgPath), "", localPortablePath(imgPath), "Histogram plot derived from actual LLR summary statistics emitted by the DL and UL trial tables.")];
    case "cfo_to_tracking_traces"
        csvPath = localDebugArtifactPath(ctx, "CFOToTrackingCSV");
        imgPath = localDebugArtifactPath(ctx, "CFOToTrackingImage");
        avail = localTrackingTraceArtifactAvailability(ctx);
        T = [T; ...
            localMetricTableRow(cat, metric, "trace", "tracking_traces_csv", avail, NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), "Per-trial CFO, TO, Doppler, and phase-tracking trace table from actual link and RS runtime exports."); ...
            localMetricTableRow(cat, metric, "trace", "tracking_traces_image", avail, NaN, localPortablePath(imgPath), "", localPortablePath(imgPath), "Per-trial CFO, TO, Doppler, and phase-tracking plot from actual link and RS runtime exports.")];
    case "harq_process_timelines"
        T = localMetricTableRow(cat, metric, "trace", "harq_timeline", localTableAvailability(ctx.Tables.HARQTimeline), NaN, "harq/csv/harq_process_timeline.csv", "", "harq/csv/harq_process_timeline.csv", "");
    case "dci_candidate_traces"
        T = localMetricTableRow(cat, metric, "trace", "pdcch_trials", localTableAvailability(ctx.Tables.PDCCH), NaN, "air_interface/csv/pdcch_trials.csv", "", "air_interface/csv/pdcch_trials.csv", "");
    case "prach_correlation_traces"
        csvPath = localDebugArtifactPath(ctx, "PRACHCorrelationCSV");
        imgPath = localDebugArtifactPath(ctx, "PRACHCorrelationImage");
        T = localPrachCorrelationMetricRows(cat, metric, ctx, csvPath, imgPath);
    case "beam_score_traces"
        T = [T; ...
            localMetricTableRow(cat, metric, "trace", "beam_score_trace", localTableAvailability(ctx.Tables.BeamScoreTrace), NaN, "beamforming/csv/beam_score_trace.csv", "", "beamforming/csv/beam_score_trace.csv", ""); ...
            localMetricTableRow(cat, metric, "trace", "beam_management_state_trace", localTableAvailability(ctx.Tables.BeamManagementStateTrace), NaN, "beamforming/csv/beam_management_state_trace.csv", "", "beamforming/csv/beam_management_state_trace.csv", "Runtime beam state machine trace emitted from actual slot-ordered beam observations."); ...
            localMetricTableRow(cat, metric, "trace", "beam_management_event_trace", localTableAvailability(ctx.Tables.BeamManagementEventTrace), NaN, "beamforming/csv/beam_management_event_trace.csv", "", "beamforming/csv/beam_management_event_trace.csv", "Runtime beam event trace emitted from actual slot-ordered beam observations.")];
    case "ai_confidence_traces"
        csvPath = localDebugArtifactPath(ctx, "AIConfidenceCSV");
        imgPath = localDebugArtifactPath(ctx, "AIConfidenceImage");
        avail = localAIConfidenceTraceAvailability(ctx);
        note = "AI confidence trace is emitted from actual benchmark/runtime metadata when AI/ML is active. Production truth profiles may suppress disabled-AI audit artifacts instead of emitting empty traces.";
        T = [T; ...
            localMetricTableRow(cat, metric, "trace", "ai_confidence_csv", avail, NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), note); ...
            localMetricTableRow(cat, metric, "trace", "ai_confidence_image", avail, NaN, localPortablePath(imgPath), "", localPortablePath(imgPath), note)];
    case "energy_timeline_traces"
        T = localMetricTableRow(cat, metric, "trace", "energy_timeline", localTableAvailability(ctx.Tables.EnergyTimeline), NaN, "rf/csv/energy_timeline_trace.csv", "", "rf/csv/energy_timeline_trace.csv", "");
    case "per_scenario_summary_tables"
        aggPath = localAggregateArtifactPath(ctx, "PerScenarioSummaryTable");
        T = localMetricTableRow(cat, metric, "report", "summary_table", localFileAvailability(aggPath), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), "");
    case "per_sweep_comparison_tables"
        T = localOracleFreeUnsupportedSNRRows(cat, metric, "report", ...
            "Injected-SNR sweep comparison tables are suppressed in oracle-free geometry-driven LLS. Use air_interface/csv/lls_measured_sinr_summary.csv and measured SINR curve CSVs instead.");
    case "baseline_candidate_delta_tables"
        aggPath = localAggregateArtifactPath(ctx, "BaselineCandidateDeltaTable");
        hasComparator = strlength(string(ctx.ScenarioConfig.get("meta.baseline_reference_name", ""))) > 0;
        T = localMetricTableRow(cat, metric, "report", "delta_table", localDerivedOrPlaceholderAvailability(hasComparator), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasComparator, "No paired baseline comparator artifacts were materialized for this run; the delta table is unavailable."));
    case "waterfall_bar_charts_gains_losses"
        aggPath = localAggregateArtifactPath(ctx, "WaterfallChart");
        hasData = localMeasuredSummaryHasAnyKPI(ctx);
        T = localMetricTableRow(cat, metric, "report", "chart", localDerivedOrPlaceholderAvailability(hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasData, "No key-KPI aggregate data are available; the chart is omitted."));
    case "curves_bler_vs_snr"
        hasData = localMeasuredCurveHasAnyKPI(ctx, "BLER");
        contractPath = "analytics/image/contract__error-reliability-analytics__bler-vs-sinr.png";
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, contractPath, "", contractPath, localAggregateAvailabilityNote(hasData, "No measured SINR BLER curve data are available for contract rendering."));
    case "curves_throughput_vs_snr"
        hasData = localMeasuredCurveHasAnyKPI(ctx, "Goodput_Mbps_mean");
        contractPath = "analytics/image/contract__throughput-goodput-spectral-efficiency-analytics__throughput-vs-sinr.png";
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, contractPath, "", contractPath, localAggregateAvailabilityNote(hasData, "No measured SINR throughput curve data are available for contract rendering."));
    case "curves_nmse_vs_snr"
        hasData = exist(fullfile(ctx.Layout.ReportCSVDir, "nmse_vs_measured_sinr.csv"), "file") == 2;
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, "reports/image/nmse_vs_measured_sinr.png", "", "reports/image/nmse_vs_measured_sinr.png", localAggregateAvailabilityNote(hasData, "No NMSE measured-SINR data are available; the plot is omitted."));
    case "curves_papr_ccdf"
        aggPath = localAggregateArtifactPath(ctx, "PAPRCCDFPlot");
        hasData = localHasAnyFiniteColumn(ctx.Tables.DL, ["PAPR_dB"]) || localHasAnyFiniteColumn(ctx.Tables.UL, ["PAPR_dB"]);
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasData, "No PAPR samples are available; the plot is omitted."));
    case "curves_latency_cdf"
        aggPath = localAggregateArtifactPath(ctx, "LatencyCDFPlot");
        hasData = localHasLatencySemanticData(ctx);
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasData, "No compute, radio-time, or procedure-delay samples are available; the plot is omitted."));
    case "curves_access_delay_cdf"
        aggPath = localAggregateArtifactPath(ctx, "AccessDelayCDFPlot");
        hasData = localHasAnyFiniteColumn(ctx.Tables.InitialAccessLifecycle, ["AccessDelay_ms","ProcedureDelay_ms"]) || ...
            localHasAnyFiniteColumn(ctx.Tables.PRACH, ["AccessDelay_ms","ProcedureDelay_ms"]) || ...
            localHasAnyFiniteColumn(ctx.Tables.PBCH, ["ProcedureDelay_ms"]) || ...
            localHasAnyFiniteColumn(ctx.Tables.PBCHRecovery, ["ProcedureDelay_ms"]) || ...
            localHasAnyFiniteColumn(ctx.Tables.CellSearch, ["ProcedureDelay_ms"]);
        if hasData
            note = "";
        elseif localShouldEmitPlaceholderArtifacts(ctx)
            note = "No true initial-access procedure-delay samples are available in this LLS scope; the plot is omitted.";
        else
            note = "No true initial-access procedure-delay samples are available in this LLS scope, so the plot is intentionally omitted in this production truth profile.";
        end
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrSuppressedPlaceholderAvailability(ctx, hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), note);
    case "curves_energy_vs_throughput"
        aggPath = localAggregateArtifactPath(ctx, "EnergyVsThroughputPlot");
        hasData = localHasAnyFiniteColumn(ctx.Tables.ScenarioSummary, ["Throughput_Mbps","EnergyPerBit_J"]) || ...
            localHasAnyFiniteColumn(ctx.Tables.CaseStatus, ["Throughput_Mbps","EnergyPerBit_J"]) || ...
            (localHasAnyFiniteColumn(ctx.Tables.Sweep, ["DL_Throughput_Mbps","UL_Throughput_Mbps"]) && ...
            localHasAnyFiniteColumn(ctx.Tables.RFEnergy, ["Value"]));
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasData, "No joint energy/throughput samples are available; the plot is omitted."));
    case "curves_complexity_vs_gain"
        aggPath = localAggregateArtifactPath(ctx, "ComplexityVsGainPlot");
        hasData = localHasAnyFiniteColumn(ctx.Tables.DL, ["DecoderIterations","PostEqSINR_dB"]) || localHasAnyFiniteColumn(ctx.Tables.UL, ["DecoderIterations","PostEqSINR_dB"]);
        T = localMetricTableRow(cat, metric, "report", "plot", localDerivedOrPlaceholderAvailability(hasData), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), localAggregateAvailabilityNote(hasData, "No complexity/gain sample pairs are available; the plot is omitted."));
    case "heatmaps_band_feature_kpi"
        aggPath = localAggregateArtifactPath(ctx, "BandFeatureKPIHeatmap");
        T = localMetricTableRow(cat, metric, "report", "heatmap", localFileAvailability(aggPath), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), "Single-run band/feature/KPI snapshot heatmap built from actual current-run KPIs.");
    case "heatmaps_impairment_kpi"
        aggPath = localAggregateArtifactPath(ctx, "ImpairmentKPIHeatmap");
        T = localMetricTableRow(cat, metric, "report", "heatmap", localFileAvailability(aggPath), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), "Single-run impairment/KPI snapshot heatmap built from actual current-run tracking, BLER, and energy measurements.");
    case "heatmaps_beam_rank_trp_kpi"
        aggPath = localAggregateArtifactPath(ctx, "BeamRankTRPKPIHeatmap");
        T = localMetricTableRow(cat, metric, "report", "heatmap", localFileAvailability(aggPath), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), "Single-run beam/rank/TRP snapshot heatmap built from actual beam-management and throughput measurements.");
    case "automatic_markdown_summary"
        aggPath = localAggregateArtifactPath(ctx, "AutomaticMarkdownSummary");
        T = localMetricTableRow(cat, metric, "report", "markdown_summary", localFileAvailability(aggPath), NaN, localPortablePath(aggPath), "", localPortablePath(aggPath), "");
    case "executive_one_page_summary"
        T = localMetricTableRow(cat, metric, "report", "executive_summary", localFileAvailability(fullfile(ctx.Layout.ReportDir, "executive_summary.md")), NaN, "reports/executive_summary.md", "", "reports/executive_summary.md", "");
    case "detailed_technical_report"
        T = localMetricTableRow(cat, metric, "report", "technical_report", localFileAvailability(fullfile(ctx.Layout.ReportDir, "technical_report.md")), NaN, "reports/technical_report.md", "", "reports/technical_report.md", "");
end
end

function T = localSweepMetricRows(cat, metric, sweepT, cols, entities, unit)
T = localEmptyMetricTable();
if ~(istable(sweepT) && ~isempty(sweepT) && ismember("SNR_dB", string(sweepT.Properties.VariableNames)))
    return;
end
for i = 1:numel(cols)
    col = string(cols(i));
    if ~ismember(col, string(sweepT.Properties.VariableNames))
        continue;
    end
    x = double(sweepT.(col));
    x = x(isfinite(x));
    if isempty(x)
        continue;
    end
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, entities(i), "min", "available", min(x), "", unit, "air_interface/csv/lls_snr_sweep.csv", ""); ...
        localMetricTableRow(cat, metric, entities(i), "mean", "available", mean(x, "omitnan"), "", unit, "air_interface/csv/lls_snr_sweep.csv", ""); ...
        localMetricTableRow(cat, metric, entities(i), "max", "available", max(x), "", unit, "air_interface/csv/lls_snr_sweep.csv", "")];
end
end

function T = localSweepMetricRowsPreferred(cat, metric, sweepT, colCandidates, entities, unit)
T = localEmptyMetricTable();
if ~(istable(sweepT) && ~isempty(sweepT))
    return;
end
vars = string(sweepT.Properties.VariableNames);
for i = 1:size(colCandidates, 1)
    candidates = string(colCandidates(i, :));
    col = "";
    for j = 1:numel(candidates)
        if strlength(candidates(j)) > 0 && ismember(candidates(j), vars)
            col = candidates(j);
            break;
        end
    end
    if strlength(col) == 0
        warning("sixgr:output:SweepColumnNotFound", ...
            "No throughput/goodput column found in sweep table. Available columns: %s", ...
            strjoin(vars, ", "));
        continue;
    end
    x = double(sweepT.(col));
    x = x(isfinite(x));
    if isempty(x)
        continue;
    end
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, entities(i), "min", "available", min(x), "", unit, "air_interface/csv/lls_snr_sweep.csv", ""); ...
        localMetricTableRow(cat, metric, entities(i), "mean", "available", mean(x, "omitnan"), "", unit, "air_interface/csv/lls_snr_sweep.csv", ""); ...
        localMetricTableRow(cat, metric, entities(i), "max", "available", max(x), "", unit, "air_interface/csv/lls_snr_sweep.csv", "")];
end
end

function T = localFailureRateRows(cat, metric, trialT, entity)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("Status", string(trialT.Properties.VariableNames)))
    return;
end
status = upper(strtrim(string(trialT.Status)));
validMask = localObservedStatusMask(status);
if ~any(validMask)
    return;
end
failMask = status(validMask) == "FAIL" | status(validMask) == "CRASH";
T = [T; ...
    localMetricTableRow(cat, metric, entity, "rate", "available", mean(failMask), "", "fraction", localDefaultSource(entity), ""); ...
    localMetricTableRow(cat, metric, entity, "count", "available", sum(failMask), "", "count", localDefaultSource(entity), "")];
end

function T = localPassRateRows(cat, metric, trialT, entity)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("Status", string(trialT.Properties.VariableNames)))
    return;
end
status = upper(strtrim(string(trialT.Status)));
validMask = localObservedStatusMask(status);
if ~any(validMask)
    return;
end
passMask = status(validMask) == "PASS";
T = [T; ...
    localMetricTableRow(cat, metric, entity, "rate", "available", mean(passMask), "", "fraction", localDefaultSource(entity), ""); ...
    localMetricTableRow(cat, metric, entity, "count", "available", sum(passMask), "", "count", localDefaultSource(entity), "")];
end

function T = localPrachFailureRateRows(cat, metric, ctx)
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "PRACH", "miss_detection", "air_interface/csv/prach_trials.csv", ...
        "PRACH_Detection was pruned from the active truth profile, so PRACH miss-detection coverage is not supported in this run.");
    return;
end
T = localFailureRateRows(cat, metric, ctx.Tables.PRACH, "PRACH");
end

function T = localPrachPassRateRows(cat, metric, ctx)
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "PRACH", "detection_probability", "air_interface/csv/prach_trials.csv", ...
        "PRACH_Detection was pruned from the active truth profile, so PRACH detection probability is not supported in this run.");
    return;
end
T = localPassRateRows(cat, metric, ctx.Tables.PRACH, "PRACH");
end

function T = localPrachCorrelationMetricRows(cat, metric, ctx, csvPath, imgPath)
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = [ ...
        localTruthPrunedMetricRows(cat, metric, "trace", "prach_correlation_csv", localPortablePath(csvPath), ...
            "PRACH_Detection was pruned from the active truth profile, so PRACH correlation traces are not supported in this run."); ...
        localTruthPrunedMetricRows(cat, metric, "trace", "prach_correlation_image", localPortablePath(imgPath), ...
            "PRACH_Detection was pruned from the active truth profile, so PRACH correlation plots are not supported in this run.")];
    return;
end
hasTrace = istable(ctx.Tables.PRACHCorrelationTrace) && ~isempty(ctx.Tables.PRACHCorrelationTrace) && ...
    all(ismember(["lag_samples","correlation_abs","truth_status"], string(ctx.Tables.PRACHCorrelationTrace.Properties.VariableNames))) && ...
    any(string(ctx.Tables.PRACHCorrelationTrace.truth_status) == "real_lls_evidence") && ...
    localHasAnyFiniteColumn(ctx.Tables.PRACHCorrelationTrace, "correlation_abs");
avail = localDerivedOrPlaceholderAvailability(hasTrace);
note = localAggregateAvailabilityNote(hasTrace, ...
    "No lag-domain PRACH correlation samples were emitted by the current LLS path; unavailable debug artifacts may still exist.");
T = [ ...
    localMetricTableRow(cat, metric, "trace", "prach_correlation_csv", avail, NaN, localPortablePath(csvPath), "", localPortablePath(csvPath), note); ...
    localMetricTableRow(cat, metric, "trace", "prach_correlation_image", avail, NaN, localPortablePath(imgPath), "", localPortablePath(imgPath), note)];
end

function T = localNumericTrialSummaryRows(cat, metric, trialT, varName, entity, unit)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember(varName, string(trialT.Properties.VariableNames)))
    return;
end
x = double(trialT.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
T = [T; ...
    localMetricTableRow(cat, metric, entity, "mean", "available", mean(x, "omitnan"), "", unit, localDefaultSource(entity), ""); ...
    localMetricTableRow(cat, metric, entity, "p95", "available", prctile(x, 95), "", unit, localDefaultSource(entity), ""); ...
    localMetricTableRow(cat, metric, entity, "max", "available", max(x), "", unit, localDefaultSource(entity), "")];
end

function T = localRMSETrialRows(cat, metric, trialT, varName, entity, unit, source)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember(varName, string(trialT.Properties.VariableNames)))
    return;
end
x = double(trialT.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
rmse = sqrt(mean(x.^2, "omitnan"));
T = [T; ...
    localMetricTableRow(cat, metric, entity, "rmse", "available", rmse, "", unit, source, ""); ...
    localMetricTableRow(cat, metric, entity, "mean_abs", "available", mean(abs(x), "omitnan"), "", unit, source, ""); ...
    localMetricTableRow(cat, metric, entity, "max_abs", "available", max(abs(x)), "", unit, source, "")];
end

function T = localArtifactMetricRows(cat, metric, runDir, entity, stat, relPath, notes)
availability = localFileAvailability(fullfile(runDir, strrep(relPath, "/", filesep)));
T = localMetricTableRow(cat, metric, entity, stat, availability, NaN, relPath, "", relPath, string(notes));
end

function T = localRatioSummaryRows(cat, metric, trialT, numVar, denVar, entity, unit, source, notes)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && all(ismember([numVar, denVar], string(trialT.Properties.VariableNames))))
    return;
end
num = double(trialT.(numVar));
den = double(trialT.(denVar));
mask = isfinite(num) & isfinite(den) & den >= 0;
if ~any(mask)
    return;
end
num = num(mask);
den = den(mask);
ratio = NaN;
if sum(den) > 0
    ratio = sum(num) / sum(den);
end
T = [T; ...
    localMetricTableRow(cat, metric, entity, "rate", "available", ratio, "", unit, source, notes); ...
    localMetricTableRow(cat, metric, entity, "numerator_sum", "available", sum(num), "", "count", source, notes); ...
    localMetricTableRow(cat, metric, entity, "denominator_sum", "available", sum(den), "", "count", source, notes)];
end

function T = localIndicatorRateRows(cat, metric, trialT, varName, entity, source, notes)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember(varName, string(trialT.Properties.VariableNames)))
    return;
end
x = double(trialT.(varName));
mask = isfinite(x);
if ~any(mask)
    return;
end
x = x(mask) ~= 0;
T = [T; ...
    localMetricTableRow(cat, metric, entity, "rate", "available", mean(x), "", "fraction", source, notes); ...
    localMetricTableRow(cat, metric, entity, "count", "available", sum(x), "", "count", source, notes); ...
    localMetricTableRow(cat, metric, entity, "sample_count", "available", numel(x), "", "count", source, notes)];
end

function T = localPerLayerBLERRows(cat, metric, trialT)
T = localEmptyMetricTable();
requiredVars = ["Layers","Status"];
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(requiredVars, string(trialT.Properties.VariableNames))))
    return;
end
layers = double(trialT.Layers);
status = upper(strtrim(string(trialT.Status)));
failMask = status == "FAIL" | status == "CRASH";
valid = isfinite(layers) & layers >= 1;
if ~any(valid)
    return;
end
maxLayers = max(layers(valid));
for idx = 1:maxLayers
    mask = valid & layers >= idx;
    if ~any(mask)
        continue;
    end
    note = "Current LLS runtime exports aggregate TB outcome rows; PDSCH PHY supports one codeword for ranks 1-4 and two codewords for ranks 5-8, while per-layer BLER is attributed to each active layer in the configured layer map.";
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "layer_" + string(idx), "rate", "available", mean(failMask(mask)), "", "fraction", "air_interface/csv/dl_pdsch_trials.csv", note); ...
        localMetricTableRow(cat, metric, "layer_" + string(idx), "sample_count", "available", sum(mask), "", "count", "air_interface/csv/dl_pdsch_trials.csv", note)];
end
end

function T = localPerCodewordBLERRows(cat, metric, trialT)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("Status", string(trialT.Properties.VariableNames)))
    return;
end
status = upper(strtrim(string(trialT.Status)));
failMask = status == "FAIL" | status == "CRASH";
note = "PHY PDSCH TX/RX supports one codeword for ranks 1-4 and two codewords for ranks 5-8; this aggregate trial table exposes TB status, so codeword_1 mirrors TB failure rate unless codeword-specific rows are present.";
T = [T; ...
    localMetricTableRow(cat, metric, "codeword_1", "rate", "available", mean(failMask), "", "fraction", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "codeword_1", "sample_count", "available", numel(failMask), "", "count", "air_interface/csv/dl_pdsch_trials.csv", note)];
end

function T = localRateMatchingOverheadRows(cat, metric, trialT, entity)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
vars = string(trialT.Properties.VariableNames);
if all(ismember(["RateMatchedBits","RateMatchPunctureBits","RateMatchRepetitionBits"], vars))
    rm = double(trialT.RateMatchedBits);
    punct = double(trialT.RateMatchPunctureBits);
    rep = double(trialT.RateMatchRepetitionBits);
    mask = isfinite(rm) & isfinite(punct) & isfinite(rep) & rm > 0;
    if any(mask)
        overhead = (punct(mask) + rep(mask)) ./ rm(mask);
        note = "Measured from actual rate-matching puncture and repetition bit counts.";
        T = [T; ...
            localMetricTableRow(cat, metric, entity, "mean_ratio", "available", mean(overhead, "omitnan"), "", "fraction", localDefaultSource(entity), note); ...
            localMetricTableRow(cat, metric, entity, "p95_ratio", "available", prctile(overhead, 95), "", "fraction", localDefaultSource(entity), note)];
    end
end
end

function T = localPDCCHFeatureMetricRows(cat, metric, ctx, mode)
T = localEmptyMetricTable();
source = "meta/scenario_config_resolved.yaml";
switch string(mode)
    case "detection_feedback"
        policy = lower(strtrim(string(ctx.ScenarioConfig.get("control.pdcch_detection_feedback_policy", ""))));
        enabled = ~(policy == "" || any(policy == ["disabled","none","off"])) || ...
            logical(ctx.ScenarioConfig.get("control.detection_feedback_enabled", false)) || ...
            logical(ctx.ScenarioConfig.get("harq.detection_feedback_interaction_enabled", false));
        if ~enabled
            T = localMetricTableRow(cat, metric, "PDCCH", "effectiveness_fraction", localFeatureAvailability(enabled), 0, "", "fraction", source, ...
                "Detection feedback is disabled by scenario configuration, so effectiveness is zero by construction.");
            return;
        end
        status = upper(strtrim(string(localColumnOrEmpty(ctx.Tables.PDCCH, "Status"))));
        if isempty(status)
            return;
        end
        passRate = mean(status == "PASS");
        T = [T; ...
            localMetricTableRow(cat, metric, "PDCCH", "effectiveness_fraction", "available", passRate, "", "fraction", localDefaultSource("PDCCH"), ...
                "Measured as successful PDCCH decode rate while detection feedback is enabled."); ...
            localMetricTableRow(cat, metric, "PDCCH", "sample_count", "available", numel(status), "", "count", localDefaultSource("PDCCH"), ...
                "Measured over executed PDCCH trials while detection feedback is enabled.")];
    case "repetition_gain"
        enabled = logical(ctx.ScenarioConfig.get("control.repetition_enabled", false));
        repCount = double(ctx.ScenarioConfig.get("signals_and_channels_common.sib1_related_pdcch.repetition_count", 1));
        repCount = max(repCount, 1);
        gain_dB = 0;
        note = "PDCCH repetition is disabled by scenario configuration, so repetition gain is zero by construction.";
        if enabled
            gain_dB = 10 * log10(repCount);
            note = "Config-derived repetition combining gain proxy from the enabled repetition count.";
        end
        T = localMetricTableRow(cat, metric, "PDCCH", "gain_dB", localFeatureAvailability(enabled), gain_dB, "", "dB", source, note);
    case "puncturing_exclusion"
        stressMode = lower(strtrim(string(ctx.ScenarioConfig.get("control.stress_mode", "none"))));
        puncturing = lower(strtrim(string(ctx.ScenarioConfig.get("resource_grid.puncturing_policy", "none"))));
        exclusion = lower(strtrim(string(ctx.ScenarioConfig.get("resource_grid.exclusion_mask", "none"))));
        enabled = ~(puncturing == "none" && exclusion == "none" && stressMode ~= "puncturing");
        if ~enabled
            T = localMetricTableRow(cat, metric, "PDCCH", "penalty_fraction", localFeatureAvailability(enabled), 0, "", "fraction", source, ...
                "No puncturing or exclusion constraints are enabled in this scenario.");
            return;
        end
        status = upper(strtrim(string(localColumnOrEmpty(ctx.Tables.PDCCH, "Status"))));
        if isempty(status)
            return;
        end
        failRate = mean(status == "FAIL" | status == "CRASH");
        T = [T; ...
            localMetricTableRow(cat, metric, "PDCCH", "penalty_fraction", "available", failRate, "", "fraction", localDefaultSource("PDCCH"), ...
                "Measured control failure rate under active puncturing or exclusion constraints."); ...
            localMetricTableRow(cat, metric, "PDCCH", "sample_count", "available", numel(status), "", "count", localDefaultSource("PDCCH"), ...
                "Measured over executed PDCCH trials under active puncturing or exclusion constraints.")];
    case "mrss_impact"
        mrssFlag = logical(ctx.ScenarioConfig.get("control.mrss_tolerant_enabled", false));
        mrssPolicy = lower(strtrim(string(ctx.ScenarioConfig.get("resource_grid.mrss_constraints", "none"))));
        enabled = mrssFlag || mrssPolicy ~= "none";
        if ~enabled
            T = localMetricTableRow(cat, metric, "PDCCH", "impact_fraction", localFeatureAvailability(enabled), 0, "", "fraction", source, ...
                "MRSS constraints are disabled by scenario configuration, so control impact is zero by construction.");
            return;
        end
        status = upper(strtrim(string(localColumnOrEmpty(ctx.Tables.PDCCH, "Status"))));
        if isempty(status)
            return;
        end
        failRate = mean(status == "FAIL" | status == "CRASH");
        T = [T; ...
            localMetricTableRow(cat, metric, "PDCCH", "impact_fraction", "available", failRate, "", "fraction", localDefaultSource("PDCCH"), ...
                "Measured control failure rate under active MRSS constraints."); ...
            localMetricTableRow(cat, metric, "PDCCH", "sample_count", "available", numel(status), "", "count", localDefaultSource("PDCCH"), ...
                "Measured over executed PDCCH trials under active MRSS constraints.")];
end
end

function T = localInvalidDetectionPowerCostRows(cat, metric, ctx)
T = localEmptyMetricTable();
if ~(istable(ctx.Tables.PDCCH) && ~isempty(ctx.Tables.PDCCH) && ismember("FalseAlarmFlag", string(ctx.Tables.PDCCH.Properties.VariableNames)))
    return;
end
falseAlarm = double(ctx.Tables.PDCCH.FalseAlarmFlag);
falseAlarm = falseAlarm(isfinite(falseAlarm));
if isempty(falseAlarm)
    return;
end
falseAlarmRate = mean(falseAlarm ~= 0);
monitorEnergy = localProbeMetricScalar(ctx.Tables.RFEnergy, "pdcch_monitoring_energy");
if ~isfinite(monitorEnergy)
    monitorEnergy = 0;
end
cost = falseAlarmRate * monitorEnergy;
T = [T; ...
    localMetricTableRow(cat, metric, "PDCCH", "mean_cost", "available", cost, "", "J", "air_interface/csv/pdcch_trials.csv", ...
        "Measured from the product of false-alarm probability and UE PDCCH monitoring energy."); ...
    localMetricTableRow(cat, metric, "PDCCH", "false_alarm_rate", "available", falseAlarmRate, "", "fraction", "air_interface/csv/pdcch_trials.csv", ...
        "Measured from noise-only PDCCH decode attempts.")];
end

function value = localProbeMetricScalar(probeT, metricKey)
value = NaN;
requiredVars = ["MetricKey","Value"];
if ~(istable(probeT) && ~isempty(probeT) && all(ismember(requiredVars, string(probeT.Properties.VariableNames))))
    return;
end
mask = string(probeT.MetricKey) == string(metricKey);
if ~any(mask)
    return;
end
x = double(probeT.Value(mask));
x = x(isfinite(x));
if isempty(x)
    return;
end
value = mean(x, "omitnan");
end

function value = localColumnOrEmpty(T, varName)
value = strings(0, 1);
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
value = T.(varName);
end

function logicalPath = localReportChartCSVLogicalPath(fileName)
logicalPath = "reports/csv/" + replace(string(fileName), ".png", ".csv");
end

function T = localTrialThroughputRows(cat, metric, trialT, entity, unit, notes)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
vars = string(trialT.Properties.VariableNames);
bitVar = "";
sourcePath = localDefaultSource(entity);
if ismember("GoodBits", vars) || ismember("Goodput_Mbps", vars)
    bitVar = "GoodBits";
elseif ismember("OfferedBits", vars) || ismember("OfferedThroughput_Mbps", vars)
    bitVar = "OfferedBits";
end
if strlength(bitVar) == 0
    return;
end
samples = localSlotAggregatedBitRateSamples(trialT, bitVar);
if isempty(samples)
    return;
end
T = [T; ...
    localMetricTableRow(cat, metric, entity, "mean", "available", mean(samples, "omitnan"), "", unit, sourcePath, ""); ...
    localMetricTableRow(cat, metric, entity, "p95", "available", prctile(samples, 95), "", unit, sourcePath, ""); ...
    localMetricTableRow(cat, metric, entity, "max", "available", max(samples), "", unit, sourcePath, "")];
if ~isempty(T)
    T.Notes(:) = string(notes);
end
end

function T = localApplicationGoodputRows(cat, metric, ctx)
% Report application goodput only when the strict KPI reconstruction is
% backed by application packets that completed SDAP/PDCP/RLC/MAC and the
% same PDSCH/PUSCH waveform.  PHY/TB goodput is deliberately not accepted
% as a substitute for application-layer delivery.
T = localEmptyMetricTable();
ledger = ctx.Tables.ApplicationPackets;
recon = ctx.Tables.KPIReconstruction;
requiredLedger = ["Direction","DeliverySuccess","SameWaveformProtocolComplete"];
requiredRecon = ["KPIName","Value","StrictOk","SchemaValid","FormulaExecuted", ...
    "ReconciliationPass","SourceRowCount"];
if ~(istable(ledger) && ~isempty(ledger) && all(ismember(requiredLedger, string(ledger.Properties.VariableNames))))
    return;
end
if ~(istable(recon) && ~isempty(recon) && all(ismember(requiredRecon, string(recon.Properties.VariableNames))))
    return;
end

ledgerDirection = upper(strtrim(string(ledger.Direction)));
for direction = ["DL","UL"]
    kpiName = direction + "_Application_Goodput_Mbps";
    ridx = find(string(recon.KPIName) == kpiName);
    if numel(ridx) ~= 1
        continue;
    end
    ridx = ridx(1);
    strictOk = localTableLogicalAtRow(recon, ridx, "StrictOk") && ...
        localTableLogicalAtRow(recon, ridx, "SchemaValid") && ...
        localTableLogicalAtRow(recon, ridx, "FormulaExecuted") && ...
        localTableLogicalAtRow(recon, ridx, "ReconciliationPass");
    value = localTableNumericAtRow(recon, ridx, "Value");
    sourceRows = localTableNumericAtRow(recon, ridx, "SourceRowCount");
    lidx = find(ledgerDirection == direction);
    if ~strictOk || ~isfinite(value) || value < 0 || ~isfinite(sourceRows) || ...
            sourceRows <= 0 || isempty(lidx)
        continue;
    end
    delivered = false(numel(lidx), 1);
    protocolComplete = false(numel(lidx), 1);
    for i = 1:numel(lidx)
        delivered(i) = localTableLogicalAtRow(ledger, lidx(i), "DeliverySuccess");
        protocolComplete(i) = localTableLogicalAtRow(ledger, lidx(i), "SameWaveformProtocolComplete");
    end
    if any(delivered & ~protocolComplete) || ~any(delivered & protocolComplete)
        continue;
    end
    note = "Strict application goodput reconstructed from unique delivered application packets whose SDAP/PDCP/RLC/MAC payload completed on the same decoded PDSCH/PUSCH waveform; no PHY-goodput proxy is used. Source packet ledger: packet_flow/csv/live_application_packet_delivery_ledger.csv.";
    T = [T; localMetricTableRow(cat, metric, direction, "measurement_window", ...
        "derived", value, "", "Mbps", "reports/csv/kpi_reconstruction_summary.csv", note)]; %#ok<AGROW>
end
end

function samples = localSlotAggregatedBitRateSamples(trialT, bitVar)
samples = NaN(0, 1);
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
bitValues = localResolvedTrialBitsForReporting(trialT, bitVar);
if isempty(bitValues)
    return;
end
slotDurDefault_s = localTrialDefaultDurationSeconds(trialT);
slotDurByRow_s = localTrialDurationsSecondsForReporting(trialT, slotDurDefault_s);
slotKeys = localTrialSlotKeysForReporting(trialT);
if numel(slotKeys) ~= numel(bitValues)
    slotKeys = strings(numel(bitValues), 1);
end
slotKeys = string(slotKeys(:));
if all(strlength(strtrim(slotKeys)) == 0)
    slotKeys = "row_" + string((1:numel(bitValues)).');
end
[uniqueKeys, ~, groupIdx] = unique(slotKeys, "stable");
if isempty(uniqueKeys)
    return;
end
bitSums = accumarray(groupIdx, bitValues, [numel(uniqueKeys) 1], @localNaNSumCompatForReporting, NaN);
slotDurByGroup_s = accumarray(groupIdx, slotDurByRow_s, [numel(uniqueKeys) 1], @(x) localRepresentativePositiveDurationForReporting(x, slotDurDefault_s), NaN);
samples = (bitSums ./ max(slotDurByGroup_s, eps)) / 1e6;
samples = samples(isfinite(samples));
end

function total = localNaNSumCompatForReporting(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    total = 0;
    return;
end
total = sum(x);
end

function bitValues = localResolvedTrialBitsForReporting(trialT, bitVar)
bitValues = NaN(0, 1);
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
vars = string(trialT.Properties.VariableNames);
bitVar = string(bitVar);
if ismember(bitVar, vars)
    bitValues = double(trialT.(bitVar));
    bitValues(~isfinite(bitValues)) = NaN;
else
    bitValues = NaN(height(trialT), 1);
end
if bitVar == "GoodBits" && all(~isfinite(bitValues))
    if ismember("TBSize_bits", vars)
        bitTotals = double(trialT.TBSize_bits);
        bitTotals(~isfinite(bitTotals)) = 0;
        passMask = false(height(trialT), 1);
        if ismember("Status", vars)
            passMask = upper(strtrim(string(trialT.Status))) == "PASS";
        elseif ismember("CRCPass", vars)
            passMask = logical(trialT.CRCPass);
        end
        bitValues = zeros(size(bitTotals));
        bitValues(passMask) = bitTotals(passMask);
    end
elseif bitVar == "OfferedBits" && all(~isfinite(bitValues)) && ismember("TBSize_bits", vars)
    bitTotals = double(trialT.TBSize_bits);
    bitTotals(~isfinite(bitTotals)) = NaN;
    bitValues = bitTotals;
end
end

function slotDur_s = localTrialDefaultDurationSeconds(trialT)
slotDur_s = 0.5e-3;
if ~(istable(trialT) && ~isempty(trialT) && ismember("AirInterfaceTTI_ms", string(trialT.Properties.VariableNames)))
    return;
end
tti_ms = double(trialT.AirInterfaceTTI_ms);
tti_ms = tti_ms(isfinite(tti_ms) & tti_ms > 0);
if ~isempty(tti_ms)
    slotDur_s = median(tti_ms, "omitnan") / 1000;
end
end

function durations_s = localTrialDurationsSecondsForReporting(trialT, fallback_s)
durations_s = repmat(double(fallback_s), height(trialT), 1);
if ~(istable(trialT) && ~isempty(trialT) && ismember("AirInterfaceTTI_ms", string(trialT.Properties.VariableNames)))
    return;
end
tti_ms = double(trialT.AirInterfaceTTI_ms);
validMask = isfinite(tti_ms) & tti_ms > 0;
durations_s(validMask) = tti_ms(validMask) / 1000;
end

function slotKeys = localTrialSlotKeysForReporting(trialT)
slotKeys = strings(0, 1);
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
vars = string(trialT.Properties.VariableNames);
if all(ismember(["Frame","Slot"], vars))
    slotKeys = "frame_" + string(round(double(trialT.Frame))) + "_slot_" + string(round(double(trialT.Slot)));
elseif all(ismember(["SFN","Slot"], vars))
    slotKeys = "sfn_" + string(round(double(trialT.SFN))) + "_slot_" + string(round(double(trialT.Slot)));
elseif ismember("CanonicalSlot", vars)
    slotKeys = "canonical_slot_" + string(round(double(trialT.CanonicalSlot)));
elseif ismember("Slot", vars)
    slotKeys = "slot_" + string(round(double(trialT.Slot)));
else
    slotKeys = strings(height(trialT), 1);
end
end

function duration_s = localRepresentativePositiveDurationForReporting(x, fallback_s)
duration_s = double(fallback_s);
x = double(x(:));
x = x(isfinite(x) & x > 0);
if ~isempty(x)
    duration_s = max(x);
end
if ~(isfinite(duration_s) && duration_s > 0)
    duration_s = double(fallback_s);
end
end

function T = localSpectralEfficiencyRows(cat, metric, sweepT, colName, entity, bwHz)
T = localEmptyMetricTable();
if ~(isfinite(bwHz) && bwHz > 0 && istable(sweepT) && ~isempty(sweepT))
    return;
end
colName = localFirstPresentColumn(sweepT, colName);
if strlength(colName) == 0
    return;
end
x = double(sweepT.(colName));
x = x(isfinite(x));
if isempty(x)
    return;
end
eta = (x * 1e6) / bwHz;
T = [T; ...
    localMetricTableRow(cat, metric, entity, "mean", "available", mean(eta, "omitnan"), "", "bit/s/Hz", "air_interface/csv/lls_snr_sweep.csv", ""); ...
    localMetricTableRow(cat, metric, entity, "max", "available", max(eta), "", "bit/s/Hz", "air_interface/csv/lls_snr_sweep.csv", "")];
end

function T = localPreferredRequiredSNRRows(cat, metric, ctx, blerCol, entity)
sourcePath = "air_interface/csv/lls_snr_sweep.csv";
notePrefix = "Derived from the primary adaptive sweep.";
sweepT = ctx.Tables.Sweep;
if istable(ctx.Tables.ReferenceSweep) && ~isempty(ctx.Tables.ReferenceSweep) && ...
        all(ismember(["SNR_dB", blerCol], string(ctx.Tables.ReferenceSweep.Properties.VariableNames)))
    x = double(ctx.Tables.ReferenceSweep.(blerCol));
    if sum(isfinite(x)) >= 2
        sweepT = ctx.Tables.ReferenceSweep;
        sourcePath = "air_interface/csv/lls_reference_snr_sweep.csv";
        notePrefix = "Derived from the fixed-reference sweep generated from the same waveform truth path.";
    end
end
T = localRequiredSNRRows(cat, metric, sweepT, blerCol, entity, sourcePath, notePrefix);
end

function T = localRequiredSNRRows(cat, metric, sweepT, blerCol, entity, sourcePath, notePrefix)
T = localEmptyMetricTable();
targets = [0.1 0.01 0.001 0.0001];
labels = ["10pct" "1pct" "0_1pct" "0_01pct"];
if nargin < 6 || strlength(string(sourcePath)) == 0
    sourcePath = "air_interface/csv/lls_snr_sweep.csv";
end
if nargin < 7
    notePrefix = "";
end
if ~(istable(sweepT) && ~isempty(sweepT) && all(ismember(["SNR_dB", blerCol], string(sweepT.Properties.VariableNames))))
    return;
end
snr = double(sweepT.SNR_dB);
bler = double(sweepT.(blerCol));
trialCounts = localSweepTrialCounts(sweepT, blerCol);
mask = isfinite(snr) & isfinite(bler);
snr = snr(mask);
bler = bler(mask);
if ~isempty(trialCounts)
    trialCounts = trialCounts(mask);
else
    trialCounts = nan(size(snr));
end
[snr, order] = sort(snr);
bler = bler(order);
trialCounts = trialCounts(order);
trialCountText = localSweepCountNote(sweepT, blerCol);
for i = 1:numel(targets)
    [snrReq, methodTag, reasonTag] = localEstimateRequiredSNRMeasuredOrFit(snr, bler, targets(i));
    if isfinite(snrReq)
        [ciLow, ciHigh, nNear] = localRequiredSNRCI95(snr, bler, trialCounts, targets(i));
        ciNote = localRequiredSNRCINote(ciLow, ciHigh, nNear);
        note = strtrim(notePrefix + " " + localRequiredSNRMethodNote(methodTag, targets(i), trialCountText) + " " + ciNote);
        T = [T; localMetricTableRow(cat, metric, entity, labels(i), "available", snrReq, "", "dB", sourcePath, note)]; %#ok<AGROW>
        if isfinite(ciLow)
            T = [T; localMetricTableRow(cat, metric, entity, labels(i) + "_ci95_low", "available", ciLow, "", "dB", sourcePath, note)]; %#ok<AGROW>
        end
        if isfinite(ciHigh)
            T = [T; localMetricTableRow(cat, metric, entity, labels(i) + "_ci95_high", "available", ciHigh, "", "dB", sourcePath, note)]; %#ok<AGROW>
        end
        if isfinite(nNear)
            if nNear >= 30
                availability = "available";
                trialNote = "";
            else
                availability = "derived";
                trialNote = "Required SNR estimate uses fewer than 30 trials near the target; CI may be wide.";
            end
            T = [T; localMetricTableRow(cat, metric, entity, labels(i) + "_num_trials_near_target", availability, nNear, "", "count", sourcePath, trialNote)]; %#ok<AGROW>
            if nNear < 30
                warning("sixgr:output:RequiredSNRLowConfidence", ...
                    "Required SNR at BLER=%.4f estimated from only %d trials near target; CI may be wide.", ...
                    targets(i), round(double(nNear)));
            end
        end
    else
        note = strtrim(notePrefix + " " + localRequiredSNRUnavailableNote(reasonTag, targets(i), trialCountText));
        T = [T; localMetricTableRow(cat, metric, entity, labels(i), "not_available", NaN, string(reasonTag), "dB", sourcePath, note)]; %#ok<AGROW>
    end
end
end

function snrReq = localEstimateRequiredSNR(snr, bler, target)
snrReq = NaN;
if all(bler > target) || all(bler < target)
    return;
end
for i = 1:numel(snr)-1
    b0 = bler(i);
    b1 = bler(i+1);
    if (b0 - target) * (b1 - target) > 0
        continue;
    end
    if abs(b1 - b0) < eps
        snrReq = snr(i);
        return;
    end
    t = (target - b0) / (b1 - b0);
    snrReq = snr(i) + t * (snr(i+1) - snr(i));
    return;
end
end

function [snrReq, methodTag, reasonTag] = localEstimateRequiredSNRMeasuredOrFit(snr, bler, target)
snr = double(snr(:));
bler = double(bler(:));
mask = isfinite(snr) & isfinite(bler);
snr = snr(mask);
bler = bler(mask);
reasonTag = "";
if numel(snr) < 2 || numel(unique(snr)) < 2
    snrReq = NaN;
    methodTag = "unavailable";
    reasonTag = "not_enough_data_insufficient_points";
    return;
end
[snr, uniqIdx] = unique(snr, "stable");
bler = bler(uniqIdx);
eqMask = abs(bler - target) <= eps(max(target, 1e-9));
if any(eqMask)
    snrReq = snr(find(eqMask, 1, "first"));
    methodTag = "exact_measured";
    return;
end
if ~(any(bler < target) && any(bler > target))
    snrReq = NaN;
    methodTag = "unavailable";
    reasonTag = "not_enough_data_no_target_crossing";
    return;
end
snrReq = localEstimateRequiredSNR(snr, bler, target);
if isfinite(snrReq)
    methodTag = "interpolated";
    return;
end
methodTag = "unavailable";
reasonTag = "not_enough_data_no_bracketing_segment";
end

function [ciLow, ciHigh, nNear] = localRequiredSNRCI95(snr, bler, trialCounts, target)
ciLow = NaN;
ciHigh = NaN;
nNear = localTrialsNearTarget(snr, bler, trialCounts, target);
trialCounts = double(trialCounts(:));
if numel(trialCounts) ~= numel(bler) || ~any(isfinite(trialCounts) & trialCounts > 0)
    return;
end
blerLow = nan(size(bler));
blerHigh = nan(size(bler));
for i = 1:numel(bler)
    nTotal = round(double(trialCounts(i)));
    if ~(isfinite(nTotal) && nTotal > 0 && isfinite(double(bler(i))))
        continue;
    end
    nFail = round(max(0, min(1, double(bler(i)))) * nTotal);
    [blerLow(i), blerHigh(i)] = localBLERConfidenceInterval(nFail, nTotal, 0.05);
end
ciFromLow = localEstimateRequiredSNR(snr, blerLow, target);
ciFromHigh = localEstimateRequiredSNR(snr, blerHigh, target);
finiteVals = [ciFromLow, ciFromHigh];
finiteVals = finiteVals(isfinite(finiteVals));
if isempty(finiteVals)
    return;
end
ciLow = min(finiteVals);
ciHigh = max(finiteVals);
end

function [blerLow, blerHigh] = localBLERConfidenceInterval(nFail, nTotal, alpha)
if nargin < 3 || ~(isfinite(alpha) && alpha > 0 && alpha < 1)
    alpha = 0.05;
end
nFail = max(0, min(round(double(nFail)), round(double(nTotal))));
nTotal = max(0, round(double(nTotal)));
if nTotal <= 0
    blerLow = 0;
    blerHigh = 1;
    return;
end
try
    if nFail == 0
        blerLow = 0;
    else
        blerLow = betainv(alpha / 2, nFail, nTotal - nFail + 1);
    end
    if nFail == nTotal
        blerHigh = 1;
    else
        blerHigh = betainv(1 - alpha / 2, nFail + 1, nTotal - nFail);
    end
catch
    interval = sixgr.validation.BinomialIntervalEngine.wilson( ...
        nFail,nTotal,1-alpha);
    blerLow = interval.Lower;
    blerHigh = interval.Upper;
end
blerLow = max(0, min(1, double(blerLow)));
blerHigh = max(0, min(1, double(blerHigh)));
end

function nNear = localTrialsNearTarget(snr, bler, trialCounts, target)
nNear = NaN;
trialCounts = double(trialCounts(:));
if numel(trialCounts) ~= numel(bler)
    return;
end
mask = isfinite(snr) & isfinite(bler) & isfinite(trialCounts) & trialCounts > 0;
if ~any(mask)
    return;
end
exactMask = mask & abs(bler - target) <= eps(max(target, 1e-9));
if any(exactMask)
    nNear = trialCounts(find(exactMask, 1, "first"));
    return;
end
for i = 1:(numel(bler) - 1)
    if ~(mask(i) && mask(i + 1))
        continue;
    end
    if (bler(i) - target) * (bler(i + 1) - target) <= 0
        nNear = min(trialCounts(i), trialCounts(i + 1));
        return;
    end
end
[~, idx] = min(abs(bler(mask) - target));
vals = trialCounts(mask);
nNear = vals(idx);
end

function snrReq = localEstimateRequiredSNRByLogFit(snr, bler, target)
snrReq = NaN;
mask = isfinite(snr) & isfinite(bler) & bler > 0;
snr = snr(mask);
bler = bler(mask);
if numel(unique(snr)) < 2
    return;
end
y = log10(max(bler, 1e-6));
p = polyfit(snr(:), y(:), 1);
if ~(numel(p) == 2 && isfinite(p(1)) && isfinite(p(2)) && p(1) < 0)
    return;
end
snrReq = (log10(target) - p(2)) / p(1);
if ~isfinite(snrReq)
    snrReq = NaN;
end
end

function note = localRequiredSNRMethodNote(methodTag, target, trialCountText)
if nargin < 3
    trialCountText = "";
end
switch string(methodTag)
    case "exact_measured"
        note = "Measured BLER hit the target directly at BLER=" + string(target) + "." + trialCountText;
    case "interpolated"
        note = "Measured BLER sweep crossed the target and the required SNR was obtained by linear interpolation at BLER=" + string(target) + "." + trialCountText;
    otherwise
        note = "";
end
end

function note = localRequiredSNRCINote(ciLow, ciHigh, nNear)
note = "";
parts = strings(0, 1);
if isfinite(ciLow) && isfinite(ciHigh)
    parts(end + 1, 1) = "CI95=[" + string(round(ciLow, 3)) + "," + string(round(ciHigh, 3)) + "] dB.";
end
if isfinite(nNear)
    parts(end + 1, 1) = "Trials near target=" + string(round(nNear)) + ".";
end
if ~isempty(parts)
    note = strjoin(parts, " ");
end
end

function note = localRequiredSNRUnavailableNote(reasonTag, target, trialCountText)
if nargin < 3
    trialCountText = "";
end
switch string(reasonTag)
    case "not_enough_data_insufficient_points"
        note = "not_enough_data: fewer than two usable SNR sweep points were available for BLER=" + string(target) + "." + trialCountText;
    case "not_enough_data_no_target_crossing"
        note = "not_enough_data: measured BLER never bracketed the target within the available sweep points for BLER=" + string(target) + "." + trialCountText;
    case "not_enough_data_no_bracketing_segment"
        note = "not_enough_data: a stable adjacent bracketing segment for BLER=" + string(target) + " could not be identified from the measured sweep." + trialCountText;
    otherwise
        note = "not_enough_data: the required SNR could not be estimated for BLER=" + string(target) + "." + trialCountText;
end
end

function txt = localSweepCountNote(sweepT, metricCol)
txt = "";
countCol = localSweepTrialCountColumn(metricCol);
if strlength(countCol) == 0 || ~ismember(countCol, string(sweepT.Properties.VariableNames))
    return;
end
counts = double(sweepT.(countCol));
counts = counts(isfinite(counts) & counts > 0);
if isempty(counts)
    return;
end
if all(abs(counts - counts(1)) < eps)
    txt = " Sample count per SNR: n=" + string(round(counts(1)));
else
    txt = " Sample count per SNR: n=" + string(round(min(counts))) + "-" + string(round(max(counts)));
end
end

function counts = localSweepTrialCounts(sweepT, metricCol)
counts = [];
countCol = localSweepTrialCountColumn(metricCol);
if strlength(countCol) == 0 || ~(istable(sweepT) && ismember(countCol, string(sweepT.Properties.VariableNames)))
    return;
end
counts = double(sweepT.(countCol));
counts = counts(:);
end

function countCol = localSweepTrialCountColumn(metricCol)
metricCol = string(metricCol);
parts = split(metricCol, "_");
if isempty(parts) || strlength(parts(1)) == 0
    countCol = "";
else
    countCol = parts(1) + "_TrialCount";
end
end

function T = localSNRGainSameComplexityRows(cat, metric, ctx, entity, complexityCol)
T = localEmptyMetricTable();
[adaptSNR, adaptComplexity, refSNR, refComplexity] = localComplexityComparisonCurves(ctx, entity, complexityCol);
labels = ["low_reference" "median_reference" "high_reference"];
sourcePath = "air_interface/csv/lls_reference_snr_sweep.csv|air_interface/csv/lls_snr_sweep.csv";
if numel(adaptSNR) < 2 || numel(refSNR) < 2
    T = localUnavailableComparisonRows(cat, metric, entity, labels, sourcePath, ...
        "no_valid_comparator", "no_valid_comparator: both the adaptive and fixed-reference sweeps need at least two usable complexity points.");
    return;
end
overlapLo = max(min(adaptComplexity), min(refComplexity));
overlapHi = min(max(adaptComplexity), max(refComplexity));
if ~(isfinite(overlapLo) && isfinite(overlapHi) && overlapHi > overlapLo)
    T = localUnavailableComparisonRows(cat, metric, entity, labels, sourcePath, ...
        "no_valid_comparator", "no_valid_comparator: the adaptive and fixed-reference sweeps do not share an overlapping decoder-complexity range.");
    return;
end
targets = [overlapLo; median([overlapLo; overlapHi], "omitnan"); overlapHi];
for i = 1:numel(labels)
    target = targets(min(i, numel(targets)));
    [snrAdaptive, methodAdaptive, reasonAdaptive] = localEstimateSNRForCeilingTarget(adaptSNR, adaptComplexity, target);
    [snrReference, methodReference, reasonReference] = localEstimateSNRForCeilingTarget(refSNR, refComplexity, target);
    if ~(isfinite(snrAdaptive) && isfinite(snrReference))
        reason = strjoin(unique([string(reasonAdaptive), string(reasonReference)]), "|");
        note = "not_enough_data: the adaptive and fixed-reference sweeps could not both bracket the same decoder-complexity level of " + string(target) + ".";
        T = [T; localMetricTableRow(cat, metric, entity, labels(i), "not_available", NaN, reason, "dB", sourcePath, note)]; %#ok<AGROW>
        continue;
    end
    gain = snrReference - snrAdaptive;
    note = "Positive values mean the adaptive primary sweep reached the same decoder-complexity level with lower required SNR than the fixed-reference sweep. Adaptive method=" + string(methodAdaptive) + ", reference method=" + string(methodReference) + ".";
    T = [T; localMetricTableRow(cat, metric, entity, labels(i), "available", gain, "", "dB", sourcePath, note)]; %#ok<AGROW>
end
end

function T = localComplexityReductionSameBLERRows(cat, metric, ctx, entity, blerCol, complexityCol)
T = localEmptyMetricTable();
[adaptSNR, adaptBLER, refSNR, refBLER] = localComparisonSweepCurves(ctx, blerCol);
[~, adaptComplexity, ~, refComplexity] = localComplexityComparisonCurves(ctx, entity, complexityCol);
targets = [0.1 0.01 0.001 0.0001];
labels = ["10pct" "1pct" "0_1pct" "0_01pct"];
sourcePath = "air_interface/csv/lls_reference_snr_sweep.csv|air_interface/csv/lls_snr_sweep.csv";
if numel(adaptSNR) < 2 || numel(refSNR) < 2 || numel(adaptComplexity) < 2 || numel(refComplexity) < 2
    T = localUnavailableComparisonRows(cat, metric, entity, labels, sourcePath, ...
        "no_valid_comparator", "no_valid_comparator: both the adaptive and fixed-reference sweeps need usable BLER and complexity curves.");
    return;
end
for i = 1:numel(targets)
    [snrAdaptive, methodAdaptive, reasonAdaptive] = localEstimateRequiredSNRMeasuredOrFit(adaptSNR, adaptBLER, targets(i));
    [snrReference, methodReference, reasonReference] = localEstimateRequiredSNRMeasuredOrFit(refSNR, refBLER, targets(i));
    if ~(isfinite(snrAdaptive) && isfinite(snrReference))
        reason = strjoin(unique([string(reasonAdaptive), string(reasonReference)]), "|");
        note = "not_enough_data: the adaptive and fixed-reference sweeps could not both estimate a required SNR at BLER=" + string(targets(i)) + ".";
        T = [T; localMetricTableRow(cat, metric, entity, labels(i), "not_available", NaN, reason, "fraction", sourcePath, note)]; %#ok<AGROW>
        continue;
    end
    compAdaptive = localEstimateMetricAtSNR(adaptSNR, adaptComplexity, snrAdaptive);
    compReference = localEstimateMetricAtSNR(refSNR, refComplexity, snrReference);
    if ~(isfinite(compAdaptive) && isfinite(compReference) && compReference > 0)
        note = "not_enough_data: decoder-complexity values could not be interpolated at the measured BLER target operating points.";
        T = [T; localMetricTableRow(cat, metric, entity, labels(i), "not_available", NaN, "not_enough_data_metric_lookup", "fraction", sourcePath, note)]; %#ok<AGROW>
        continue;
    end
    reduction = (compReference - compAdaptive) / compReference;
    note = "Positive values mean the adaptive primary sweep required less decoder complexity than the fixed-reference sweep at the same BLER target. Adaptive SNR method=" + string(methodAdaptive) + ", reference SNR method=" + string(methodReference) + ".";
    T = [T; localMetricTableRow(cat, metric, entity, labels(i), "available", reduction, "", "fraction", sourcePath, note)]; %#ok<AGROW>
end
end

function [adaptSNR, adaptMetric, refSNR, refMetric] = localComplexityComparisonCurves(ctx, ~, metricCol)
[adaptSNR, adaptMetric] = localSweepFiniteXY(ctx.Tables.Sweep, metricCol);
[refSNR, refMetric] = localSweepFiniteXY(ctx.Tables.ReferenceSweep, metricCol);
end

function [adaptSNR, adaptMetric, refSNR, refMetric] = localComparisonSweepCurves(ctx, metricCol)
[adaptSNR, adaptMetric] = localSweepFiniteXY(ctx.Tables.Sweep, metricCol);
[refSNR, refMetric] = localSweepFiniteXY(ctx.Tables.ReferenceSweep, metricCol);
end

function [x, y] = localSweepFiniteXY(T, varName)
x = [];
y = [];
if ~(istable(T) && ~isempty(T) && all(ismember(["SNR_dB", varName], string(T.Properties.VariableNames))))
    return;
end
x = double(T.SNR_dB);
y = double(T.(varName));
mask = isfinite(x) & isfinite(y);
x = x(mask);
y = y(mask);
[x, order] = sort(x);
y = y(order);
end

function value = localEstimateSNRForMetricTarget(snr, metricVals, target)
value = NaN;
if numel(snr) < 2 || numel(metricVals) < 2
    return;
end
[snr, order] = sort(snr(:));
metricVals = metricVals(order);
for i = 1:numel(snr)-1
    v0 = metricVals(i);
    v1 = metricVals(i+1);
    if (v0 - target) * (v1 - target) > 0
        continue;
    end
    if abs(v1 - v0) < eps
        value = snr(i);
        return;
    end
    t = (target - v0) / (v1 - v0);
    value = snr(i) + t * (snr(i+1) - snr(i));
    return;
end
if numel(unique(snr)) < 2
    return;
end
p = polyfit(snr, metricVals, 1);
if ~(numel(p) == 2 && isfinite(p(1)) && abs(p(1)) > eps)
    return;
end
value = (target - p(2)) / p(1);
end

function [value, methodTag, reasonTag] = localEstimateSNRForCeilingTarget(snr, metricVals, target)
value = NaN;
methodTag = "unavailable";
reasonTag = "";
if numel(snr) < 2 || numel(metricVals) < 2
    reasonTag = "not_enough_data_insufficient_points";
    return;
end
[snr, order] = sort(snr(:));
metricVals = metricVals(order);
mask = isfinite(snr) & isfinite(metricVals);
snr = snr(mask);
metricVals = metricVals(mask);
if numel(snr) < 2 || numel(unique(snr)) < 2
    reasonTag = "not_enough_data_insufficient_points";
    return;
end
eqMask = abs(metricVals - target) <= eps(max(abs(target), 1));
if any(eqMask)
    value = snr(find(eqMask, 1, "first"));
    methodTag = "exact_measured";
    return;
end
if target < min(metricVals) || target > max(metricVals)
    reasonTag = "no_valid_comparator";
    return;
end
for i = 1:numel(snr)-1
    v0 = metricVals(i);
    v1 = metricVals(i+1);
    if (v0 - target) * (v1 - target) > 0
        continue;
    end
    if abs(v1 - v0) < eps
        value = snr(i);
        methodTag = "interpolated";
        return;
    end
    t = (target - v0) / (v1 - v0);
    value = snr(i) + t * (snr(i+1) - snr(i));
    methodTag = "interpolated";
    return;
end
reasonTag = "not_enough_data_no_same_complexity_crossing";
end

function value = localEstimateMetricAtSNR(snr, metricVals, snrTarget)
value = NaN;
if numel(snr) < 2 || numel(metricVals) < 2 || ~isfinite(snrTarget)
    return;
end
[snr, order] = sort(snr(:));
metricVals = metricVals(order);
if snrTarget <= snr(1)
    value = metricVals(1);
    return;
end
if snrTarget >= snr(end)
    value = metricVals(end);
    return;
end
for i = 1:numel(snr)-1
    if snrTarget < snr(i) || snrTarget > snr(i+1)
        continue;
    end
    if abs(snr(i+1) - snr(i)) < eps
        value = metricVals(i);
        return;
    end
    t = (snrTarget - snr(i)) / (snr(i+1) - snr(i));
    value = metricVals(i) + t * (metricVals(i+1) - metricVals(i));
    return;
end
end

function vals = localUniqueMonotone(vals)
vals = unique(double(vals(:)), "stable");
vals = vals(isfinite(vals));
end

function T = localUnavailableComparisonRows(cat, metric, entity, labels, sourcePath, reasonCode, noteText)
T = localEmptyMetricTable();
for i = 1:numel(labels)
    T = [T; localMetricTableRow(cat, metric, entity, labels(i), "not_available", NaN, string(reasonCode), "", sourcePath, string(noteText))]; %#ok<AGROW>
end
end

function T = localErrorFloorRows(cat, metric, sweepT, blerCol, entity)
T = localEmptyMetricTable();
if ~(istable(sweepT) && ~isempty(sweepT) && all(ismember(["SNR_dB", blerCol], string(sweepT.Properties.VariableNames))))
    return;
end
snr = double(sweepT.SNR_dB);
bler = double(sweepT.(blerCol));
mask = isfinite(snr) & isfinite(bler);
if ~any(mask)
    return;
end
snr = snr(mask);
bler = bler(mask);
[snr, idx] = sort(snr);
bler = bler(idx);
tail = bler(snr >= max(snr) - 1e-9);
if isempty(tail)
    tail = bler(end);
end
desc = "no_error_floor_observed";
if any(tail > 1e-3)
    desc = "possible_error_floor_above_1e-3";
elseif any(tail > 1e-4)
    desc = "possible_error_floor_above_1e-4";
end
T = localMetricTableRow(cat, metric, entity, "assessment", "available", NaN, desc, "bler", "air_interface/csv/lls_snr_sweep.csv", "");
end

function T = localDistributionRows(cat, metric, trialT, varName, entity, unit, source)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember(varName, string(trialT.Properties.VariableNames)))
    return;
end
x = double(trialT.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
T = [T; ...
    localMetricTableRow(cat, metric, entity, "mean", "available", mean(x, "omitnan"), "", unit, source, ""); ...
    localMetricTableRow(cat, metric, entity, "p50", "available", prctile(x, 50), "", unit, source, ""); ...
    localMetricTableRow(cat, metric, entity, "max", "available", max(x), "", unit, source, "")];
u = unique(x(:));
if numel(u) <= 12
    for i = 1:numel(u)
        label = "count_at_" + string(matlab.lang.makeValidName(sprintf("%.0f", u(i))));
        T = [T; localMetricTableRow(cat, metric, entity, label, "available", sum(x == u(i)), "", "count", source, "")]; %#ok<AGROW>
    end
end
end

function T = localSegmentationRows(cat, metric, trialT, entity, source)
T = localEmptyMetricTable();
req = ["SegmentationOccurred","NumCodeBlocks","SegmentationPaddingBits"];
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(req, string(trialT.Properties.VariableNames))))
    return;
end
seg = double(trialT.SegmentationOccurred);
numCb = double(trialT.NumCodeBlocks);
pad = double(trialT.SegmentationPaddingBits);
seg = seg(isfinite(seg));
numCb = numCb(isfinite(numCb));
pad = pad(isfinite(pad));
if ~isempty(seg)
    T = [T; localMetricTableRow(cat, metric, entity, "segmentation_rate", "available", mean(seg > 0), "", "fraction", source, "")]; %#ok<AGROW>
end
if ~isempty(numCb)
    T = [T; localMetricTableRow(cat, metric, entity, "mean_num_codeblocks", "available", mean(numCb, "omitnan"), "", "count", source, "")]; %#ok<AGROW>
end
if ~isempty(pad)
    T = [T; localMetricTableRow(cat, metric, entity, "mean_padding_bits", "available", mean(pad, "omitnan"), "", "bits", source, "Segmentation padding is emitted as a transport-block segmentation statistic.")]; %#ok<AGROW>
end
end

function T = localPuncturingRows(cat, metric, trialT, entity, source)
T = localEmptyMetricTable();
req = ["RateMatchPunctureBits","RateMatchRepetitionBits","SegmentationPaddingBits"];
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(req, string(trialT.Properties.VariableNames))))
    return;
end
puncture = double(trialT.RateMatchPunctureBits);
repeat = double(trialT.RateMatchRepetitionBits);
padding = double(trialT.SegmentationPaddingBits);
puncture = puncture(isfinite(puncture));
repeat = repeat(isfinite(repeat));
padding = padding(isfinite(padding));
if ~isempty(puncture)
    T = [T; ...
        localMetricTableRow(cat, metric, entity, "mean_puncture_bits", "available", mean(puncture, "omitnan"), "", "bits", source, ""); ...
        localMetricTableRow(cat, metric, entity, "max_puncture_bits", "available", max(puncture), "", "bits", source, "")]; %#ok<AGROW>
end
if ~isempty(repeat)
    T = [T; ...
        localMetricTableRow(cat, metric, entity, "mean_repetition_bits", "available", mean(repeat, "omitnan"), "", "bits", source, ""); ...
        localMetricTableRow(cat, metric, entity, "max_repetition_bits", "available", max(repeat), "", "bits", source, "")]; %#ok<AGROW>
end
if ~isempty(padding)
    T = [T; localMetricTableRow(cat, metric, entity, "segmentation_padding_bits", "available", mean(padding, "omitnan"), "", "bits", source, "Exported as shortening/padding proxy because explicit shortening state is not emitted separately.")]; %#ok<AGROW>
end
end

function T = localPerRankThroughputRows(cat, metric, trialT)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(["Layers","Status","TBSize_bits"], string(trialT.Properties.VariableNames))))
    return;
end
layers = double(trialT.Layers);
status = upper(strtrim(string(trialT.Status)));
bits = double(trialT.TBSize_bits);
vals = unique(layers(isfinite(layers)));
for i = 1:numel(vals)
    v = vals(i);
    mask = layers == v;
    goodBits = sum(bits(mask & status == "PASS"), "omitnan");
    T = [T; localMetricTableRow(cat, metric, "rank_" + string(v), "good_bits", "available", goodBits, "", "bits", "air_interface/csv/dl_pdsch_trials.csv", "")]; %#ok<AGROW>
end
end

function T = localPayloadOverheadRows(cat, metric, trialT, entity)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(["CSIPayloadBitLength","TBSize_bits"], string(trialT.Properties.VariableNames))))
    return;
end
x = double(trialT.CSIPayloadBitLength);
y = double(trialT.TBSize_bits);
mask = isfinite(x) & isfinite(y) & y > 0;
if ~any(mask)
    return;
end
ratio = x(mask) ./ y(mask);
T = [T; ...
    localMetricTableRow(cat, metric, entity, "mean_ratio", "available", mean(ratio, "omitnan"), "", "fraction", localDefaultSource(entity), ""); ...
    localMetricTableRow(cat, metric, entity, "max_ratio", "available", max(ratio), "", "fraction", localDefaultSource(entity), "")];
end

function T = localLowPAPRRows(cat, metric, ctx)
T = localEmptyMetricTable();
papr = localFiniteColumn(ctx.Tables.UL, "PAPR_dB");
enabled = localConfigFlag(ctx, ["waveform.low_papr_mode", "pusch.low_papr_mode"], false) || ...
    localConfigNonBaseline(ctx, ["pucch.low_papr_policy"]) || ...
    localConfigFlag(ctx, ["modulation.pi2_bpsk_enabled"], false);
note = "Reported as observed UL PAPR under the configured low-PAPR mode. Lower observed PAPR implies higher low-PAPR gain relative to a comparator campaign.";
if isempty(papr)
    papr = NaN;
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "UL", "feature_enabled", "config_only", double(enabled), "", "bool", "meta/scenario_config_resolved.json", localConfigEnabledNote(enabled, note)); ...
    localMetricTableRow(cat, metric, "UL", "mean_papr_db", "available", mean(papr, "omitnan"), "", "dB", localDefaultSource("UL"), localConfigEnabledNote(enabled, note)); ...
    localMetricTableRow(cat, metric, "UL", "p95_papr_db", "available", prctile(papr(isfinite(papr)), 95), "", "dB", localDefaultSource("UL"), localConfigEnabledNote(enabled, note))];
end

function T = localPABackoffImpactRows(cat, metric, ctx)
T = localEmptyMetricTable();
backoff = localConfigNumber(ctx, ["power_and_rf_frontend.power_backoff_db", "rf.pa.backoff_dB"], 0);
note = "Configured PA backoff is exported directly, alongside observed UL goodput efficiency from the actual waveform run.";
T = [T; localMetricTableRow(cat, metric, "UL", "configured_backoff_db", "config_only", backoff, "", "dB", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
T = [T; localRatioSummaryRows(cat, metric, ctx.Tables.UL, "GoodBits", "OfferedBits", "UL_goodput_efficiency", "fraction", localDefaultSource("UL"), note)]; %#ok<AGROW>
end

function T = localPrepTimeImpactRows(cat, metric, ctx)
T = localEmptyMetricTable();
policy = localConfigString(ctx, ["pusch.prep_time_model"], "baseline");
note = "Prep-time impact is exported through the configured prep-time policy and the observed UL compute-latency cost in the waveform loop. No separate radio/procedure delay is modeled here.";
T = [T; localMetricTableRow(cat, metric, "UL", "policy", "config_only", NaN, policy, "", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
T = [T; localCustomNumericSummaryRows(cat, metric, ctx.Tables.UL, "ComputeLatency_ms", "UL_compute", "ms", "air_interface/csv/ul_pusch_trials.csv", note)]; %#ok<AGROW>
if ~isempty(T)
    T.Notes(:) = note;
end
end

function T = localUCIMultiplexingEfficiencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
policy = localConfigString(ctx, ["pusch.uci_multiplexing_mode", "pucch.multiplexing_policy"], "baseline");
note = "Computed as correctly detected UCI bits over compared UCI bits from actual PUCCH observations; CRC pass is ignored when CRC is not applicable.";
T = [T; localMetricTableRow(cat, metric, "UCI", "policy", "config_only", NaN, policy, "", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
if ~(istable(ctx.Tables.PUCCH) && ~isempty(ctx.Tables.PUCCH) && ismember("BitsCompared", string(ctx.Tables.PUCCH.Properties.VariableNames)))
    return;
end
bits = double(ctx.Tables.PUCCH.BitsCompared);
success = localPUCCHSuccessVector(ctx.Tables.PUCCH);
mask = isfinite(bits) & isfinite(success) & bits >= 0;
if ~any(mask)
    return;
end
bits = bits(mask);
good = bits .* success(mask);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "UCI", "success_ratio", "available", sum(good) / max(sum(bits), eps), "", "fraction", "air_interface/csv/pucch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "UCI", "successful_bits", "available", sum(good), "", "bits", "air_interface/csv/pucch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "UCI", "transmitted_bits", "available", sum(bits), "", "bits", "air_interface/csv/pucch_trials.csv", note)];
end

function success = localPUCCHSuccessVector(T)
n = height(T);
success = nan(n, 1);
if ismember("UCIContentMatch", string(T.Properties.VariableNames))
    success = double(logical(T.UCIContentMatch));
    return;
end
if ismember("CRCOutcome", string(T.Properties.VariableNames))
    crcOutcome = lower(strtrim(string(T.CRCOutcome)));
    success(strcmp(crcOutcome, "pass")) = 1;
    success(strcmp(crcOutcome, "fail")) = 0;
    return;
end
if ismember("CRCPass", string(T.Properties.VariableNames))
    success = double(T.CRCPass);
    if ismember("CRCApplicable", string(T.Properties.VariableNames))
        success(~logical(T.CRCApplicable)) = NaN;
    end
end
end

function T = localSimultaneousPUSCHPUCCHRows(cat, metric, ctx)
T = localEmptyMetricTable();
policy = localConfigString(ctx, ["pucch.simultaneous_pucch_pusch_policy", "pusch.simultaneous_pusch_pucch_policy"], "baseline");
note = "Simultaneous behavior is measured from overlapping Frame/Slot observations between the actual PUSCH and PUCCH trial tables.";
T = [T; localMetricTableRow(cat, metric, "UL_control", "policy", "config_only", NaN, policy, "", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
if ~(istable(ctx.Tables.UL) && istable(ctx.Tables.PUCCH) && ~isempty(ctx.Tables.UL) && ~isempty(ctx.Tables.PUCCH) && ...
        all(ismember(["Frame","Slot","Status"], string(ctx.Tables.UL.Properties.VariableNames))) && ...
        all(ismember(["Frame","Slot","Status"], string(ctx.Tables.PUCCH.Properties.VariableNames))))
    return;
end
ulKeys = string(ctx.Tables.UL.Frame) + "_" + string(ctx.Tables.UL.Slot);
pucchKeys = string(ctx.Tables.PUCCH.Frame) + "_" + string(ctx.Tables.PUCCH.Slot);
overlapKeys = intersect(unique(ulKeys), unique(pucchKeys), "stable");
overlapCount = numel(overlapKeys);
overlapRate = overlapCount / max(numel(unique(pucchKeys)), 1);
successVals = NaN(overlapCount, 1);
ulStatus = upper(strtrim(string(ctx.Tables.UL.Status)));
pucchStatus = upper(strtrim(string(ctx.Tables.PUCCH.Status)));
for i = 1:overlapCount
    k = overlapKeys(i);
    ulPass = any(ulStatus(ulKeys == k) == "PASS");
    pucchPass = any(pucchStatus(pucchKeys == k) == "PASS");
    successVals(i) = double(ulPass && pucchPass);
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "UL_control", "overlap_count", "available", overlapCount, "", "count", "air_interface/csv/pucch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "UL_control", "overlap_rate", "available", overlapRate, "", "fraction", "air_interface/csv/pucch_trials.csv", note)];
if overlapCount > 0
    T = [T; localMetricTableRow(cat, metric, "UL_control", "overlap_success_rate", "available", mean(successVals, "omitnan"), "", "fraction", "air_interface/csv/pucch_trials.csv", note)]; %#ok<AGROW>
else
    T = [T; localMetricTableRow(cat, metric, "UL_control", "overlap_success_rate", "available", 0, "", "fraction", "air_interface/csv/pucch_trials.csv", note + " No overlapping slots were scheduled in this scenario.")]; %#ok<AGROW>
end
end

function T = localPowerControlConvergenceRows(cat, metric, ctx)
T = localEmptyMetricTable();
policy = localPowerControlPolicy(ctx);
note = "Power-control convergence is summarized from actual UL SINR stability under the configured power-control policy.";
T = [T; localMetricTableRow(cat, metric, "UL", "policy", "config_only", NaN, policy, "", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
    sinr = localFiniteColumn(ctx.Tables.UL, "PostEqSINR_dB");
if isempty(sinr)
    return;
end
step = abs(diff(sinr(:)));
if isempty(step)
    step = 0;
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "UL", "sinr_std_db", "available", std(sinr, 0, "omitnan"), "", "dB", localDefaultSource("UL"), note); ...
    localMetricTableRow(cat, metric, "UL", "mean_step_delta_db", "available", mean(step, "omitnan"), "", "dB", localDefaultSource("UL"), note)];
end

function policy = localPowerControlPolicy(ctx)
enabled = localConfigFlag(ctx, ["pusch.power_control.enabled"], false);
if ~enabled
    policy = "disabled";
    return;
end
openLoop = localConfigFlag(ctx, ["pusch.power_control.open_loop_enabled"], false);
closedLoop = localConfigFlag(ctx, ["pusch.power_control.closed_loop_enabled"], false);
if openLoop && closedLoop
    policy = "open_loop_plus_closed_loop";
elseif openLoop
    policy = "open_loop";
elseif closedLoop
    policy = "closed_loop";
else
    policy = "enabled_without_loop_selection";
end
end

function T = localMsg3SpecificSuccessRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "Msg3", "success_rate", "air_interface/csv/prach_trials.csv", ...
        "Msg3 success cannot be claimed when PRACH_Detection is pruned from the active truth profile.");
    return;
end
enabled = localConfigFlag(ctx, ["random_access.msg3_enabled", "pusch.msg3_flag"], false);
alignment = localConfigString(ctx, ["random_access.msg3_waveform_alignment"], "inherit_ul_waveform");
note = "Msg3 success is exported from the actual UL/PUSCH and PRACH execution path when Msg3 support is enabled.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "Msg3", "enabled_flag", "config_only", double(enabled), "", "bool", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, "Msg3", "waveform_alignment", "config_only", NaN, alignment, "", "meta/scenario_config_resolved.json", note)];
if ~enabled
    T = [T; localMetricTableRow(cat, metric, "Msg3", "success_rate", "disabled", NaN, "", "fraction", "", note + " Feature is disabled in this scenario; no success observation is claimed.")]; %#ok<AGROW>
    return;
end
ulPass = localPassRateScalar(ctx.Tables.UL);
prachPass = localPassRateScalar(ctx.Tables.PRACH);
if ~isfinite(ulPass) || ~isfinite(prachPass)
    T = [T; localMetricTableRow(cat, metric, "Msg3", "success_rate", "not_available", NaN, "", "fraction", "", note + " Both UL transport and PRACH runtime outcomes are required.")]; %#ok<AGROW>
    return;
end
successRate = ulPass;
successRate = min(successRate, prachPass);
T = [T; localMetricTableRow(cat, metric, "Msg3", "success_rate", "available", successRate, "", "fraction", "air_interface/csv/ul_pusch_trials.csv", note)]; %#ok<AGROW>
end

function T = localInitialAccessLatencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Initial-access latency is reported only from complete slot-coupled SSB/PBCH/PRACH/PDCCH/Msg3/Msg4 lifecycle samples. Wall-clock PBCH/PRACH runtime is exported separately as compute latency and is not reused here.";
[samples, sourceRel] = localInitialAccessProcedureDelaySamples(ctx);
if ~isempty(samples)
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "initial_access", "mean", "available", mean(samples, "omitnan"), "", "ms", sourceRel, note); ...
        localMetricTableRow(cat, metric, "initial_access", "p50", "available", prctile(samples, 50), "", "ms", sourceRel, note); ...
        localMetricTableRow(cat, metric, "initial_access", "p95", "available", prctile(samples, 95), "", "ms", sourceRel, note); ...
        localMetricTableRow(cat, metric, "initial_access", "sample_count", "available", numel(samples), "", "count", sourceRel, note)];
    return;
end
if isempty(T)
    T = localUnavailableMetricRows(cat, metric, "initial_access", "procedure_delay", "air_interface/csv/prach_trials.csv", ...
        "No complete slot-coupled SSB/PBCH/PRACH/PDCCH/Msg3/Msg4 lifecycle sample is available in this run.");
end
end

function T = localControlLatencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Control latency is exported as radio-time control opportunity duration when available. Wall-clock PDCCH decode runtime is exported separately as compute latency.";
T = localCustomNumericSummaryRows(cat, metric, ctx.Tables.PDCCH, "ProcedureDelay_ms", "PDCCH_procedure", "ms", "air_interface/csv/pdcch_trials.csv", note);
if isempty(T)
    T = localCustomNumericSummaryRows(cat, metric, ctx.Tables.PDCCH, "AirInterfaceTTI_ms", "PDCCH_radio_tti", "ms", "air_interface/csv/pdcch_trials.csv", note);
end
if isempty(T)
    T = localUnavailableMetricRows(cat, metric, "PDCCH", "radio_latency", "air_interface/csv/pdcch_trials.csv", ...
        "No explicit control procedure delay is modeled by the current waveform LLS path.");
end
end

function T = localInitialAccessSearchComplexityRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Search complexity is exported as the number of actual cell-search and PBCH-recovery trials observed in the initial-access execution path.";
if istable(ctx.Tables.CellSearch) && ~isempty(ctx.Tables.CellSearch)
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "cell_search", "trial_count", "available", double(height(ctx.Tables.CellSearch)), "", "count", "control/csv/cell_search_trials.csv", note)];
end
if istable(ctx.Tables.PBCHRecovery) && ~isempty(ctx.Tables.PBCHRecovery)
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "pbch_recovery", "trial_count", "available", double(height(ctx.Tables.PBCHRecovery)), "", "count", "control/csv/pbch_recovery_trials.csv", note)];
end
if isempty(T) && istable(ctx.Tables.PBCH) && ~isempty(ctx.Tables.PBCH)
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "initial_access", "trial_count", "available", double(height(ctx.Tables.PBCH)), "", "count", "air_interface/csv/pbch_trials.csv", note)];
end
end

function T = localRepetitionGainRows(cat, metric, ctx, entity, repetitionPaths, passT, sourcePath)
T = localEmptyMetricTable();
count = max(1, round(localConfigNumber(ctx, repetitionPaths, 1)));
gain = 10 * log10(count);
note = string(entity) + " repetition gain is exported as the configuration-derived combining ceiling for the executed scenario. A paired comparator campaign is required to measure empirical gain.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, entity, "repetition_count", "config_only", count, "", "count", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, entity, "theoretical_combining_gain_db", "config_only", gain, "", "dB", "meta/scenario_config_resolved.json", note)];
passRate = localPassRateScalar(passT);
if isfinite(passRate)
    T = [T; localMetricTableRow(cat, metric, entity, "observed_success_rate", "available", passRate, "", "fraction", sourcePath, note)]; %#ok<AGROW>
end
end

function T = localPRACHFalseAlarmRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "PRACH", "false_alarm", "air_interface/csv/prach_trials.csv", ...
        "PRACH false-alarm reporting is not supported when PRACH_Detection is pruned from the active truth profile.");
    return;
end
if ~(istable(ctx.Tables.PRACH) && ~isempty(ctx.Tables.PRACH))
    T = localUnavailableMetricRows(cat, metric, "PRACH", "false_alarm", "air_interface/csv/prach_trials.csv", ...
        "No observed PRACH trials were emitted by this run.");
    return;
end
note = "PRACH false alarm is exported from explicit false-alarm flags when present; otherwise the executed targeted-access trials observed zero false alarms.";
falseAlarm = localFiniteColumn(ctx.Tables.PRACH, "FalseAlarmFlag");
if isempty(falseAlarm)
    falseAlarm = zeros(height(ctx.Tables.PRACH), 1);
end
rate = mean(falseAlarm ~= 0, "omitnan");
count = sum(falseAlarm ~= 0, "omitnan");
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "PRACH", "rate", "available", rate, "", "fraction", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "count", "available", count, "", "count", "air_interface/csv/prach_trials.csv", note)];
end

function T = localTAErrorRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "PRACH", "timing_advance_error", "air_interface/csv/prach_trials.csv", ...
        "TA-error reporting is not supported when PRACH_Detection is pruned from the active truth profile.");
    return;
end
if ~(istable(ctx.Tables.PRACH) && ~isempty(ctx.Tables.PRACH))
    T = localUnavailableMetricRows(cat, metric, "PRACH", "timing_advance_error", "air_interface/csv/prach_trials.csv", ...
        "No observed PRACH timing samples were emitted by this run.");
    return;
end
note = "TA error is exported from PRACH timing-error samples when present. If the scenario executes with nominal zero timing offset and no separate TA-estimator residual is emitted, the exported residual is zero.";
err = abs(localFiniteColumn(ctx.Tables.PRACH, "TimingError_samples"));
if isempty(err)
    trueOffset = localFiniteColumn(ctx.Tables.PRACH, "TrueTimingOffset_samples");
    if ~isempty(trueOffset)
        err = zeros(size(trueOffset));
    else
        return;
    end
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "PRACH", "mean", "available", mean(err, "omitnan"), "", "samples", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "p95", "available", prctile(err, 95), "", "samples", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "max", "available", max(err), "", "samples", "air_interface/csv/prach_trials.csv", note)];
end

function T = localPreambleCollisionRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "PRACH", "collision_statistics", "air_interface/csv/prach_trials.csv", ...
        "Preamble-collision reporting is not supported when PRACH_Detection is pruned from the active truth profile.");
    return;
end
if ~(istable(ctx.Tables.PRACH) && ~isempty(ctx.Tables.PRACH))
    T = localUnavailableMetricRows(cat, metric, "PRACH", "collision_statistics", "air_interface/csv/prach_trials.csv", ...
        "No observed PRACH trials were emitted by this run.");
    return;
end
trials = max(height(ctx.Tables.PRACH), 1);
numUEs = localConfigNumber(ctx, ["random_access.num_ues_per_ro", "deployment_topology.num_ues", "scenario.ue.nUE"], 1);
collisionFlags = localFiniteColumn(ctx.Tables.PRACH, "CollisionFlag");
activeUECount = localFiniteColumn(ctx.Tables.PRACH, "ActiveUECount");
if isempty(activeUECount)
    activeUECount = repmat(double(numUEs), trials, 1);
end
if isempty(collisionFlags)
    collisionFlags = double(activeUECount > 1);
end
collisionCount = sum(collisionFlags ~= 0, "omitnan");
collisionRate = mean(collisionFlags ~= 0, "omitnan");
if ~isfinite(collisionRate)
    collisionRate = 0;
end
note = "Preamble-collision statistics are derived from observed multi-UE PRACH random-access occasions when the runtime exports collision flags or active-UE counts.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "PRACH", "collision_count", "available", collisionCount, "", "count", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "collision_rate", "available", collisionRate, "", "fraction", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "configured_ues", "available", max(activeUECount, [], "omitnan"), "", "count", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "trial_count", "available", trials, "", "count", "air_interface/csv/prach_trials.csv", note)];
end

function T = localROUtilizationRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "PRACH", "ro_utilization", "air_interface/csv/prach_trials.csv", ...
        "Random-access occasion utilization is not supported when PRACH_Detection is pruned from the active truth profile.");
    return;
end
if ~(istable(ctx.Tables.PRACH) && ~isempty(ctx.Tables.PRACH))
    return;
end
trialCount = double(height(ctx.Tables.PRACH));
note = "RO utilization is exported from the executed PRACH loop. In the current waveform LLS path, each PRACH trial corresponds to one occupied random-access occasion.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "PRACH", "occupied_ro_count", "available", trialCount, "", "count", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "observed_ro_count", "available", trialCount, "", "count", "air_interface/csv/prach_trials.csv", note); ...
    localMetricTableRow(cat, metric, "PRACH", "utilization_rate", "available", 1, "", "fraction", "air_interface/csv/prach_trials.csv", note)];
end

function T = localAccessSuccessRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "initial_access", "success_rate", "air_interface/csv/prach_trials.csv", ...
        "Initial-access success cannot be claimed when PRACH_Detection is pruned from the active truth profile.");
    return;
end
pbchPass = localPassRateScalar(ctx.Tables.PBCH);
prachPass = localPassRateScalar(ctx.Tables.PRACH);
beamHit = localProbeMetricScalar(ctx.Tables.BeamManagement, "beam_index_hit_rate");
if ~isfinite(prachPass)
    T = localUnavailableMetricRows(cat, metric, "initial_access", "success_rate", "air_interface/csv/prach_trials.csv", ...
        "Initial-access success requires observed PRACH trials, but none were emitted by this run.");
    return;
end
rates = [pbchPass, prachPass, beamHit];
rates = rates(isfinite(rates));
if isempty(rates)
    return;
end
successRate = min(rates);
note = "Access success probability is exported conservatively as the minimum of the actual PBCH, PRACH, and beam-pair success rates available in this LLS run.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "initial_access", "success_rate", "available", successRate, "", "fraction", "air_interface/csv/pbch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "initial_access", "pbch_success_rate", "available", pbchPass, "", "fraction", "air_interface/csv/pbch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "initial_access", "prach_success_rate", "available", prachPass, "", "fraction", "air_interface/csv/prach_trials.csv", note)];
if isfinite(beamHit)
    T = [T; localMetricTableRow(cat, metric, "initial_access", "beam_pair_success_rate", "available", beamHit, "", "fraction", "beamforming/csv/probe_beam_management.csv", note)]; %#ok<AGROW>
end
end

function T = localAccessDelayCDFRows(cat, metric, ctx)
T = localEmptyMetricTable();
if localTruthCasePruned(ctx, "PRACH_Detection")
    T = localTruthPrunedMetricRows(cat, metric, "initial_access", "cdf", "air_interface/csv/prach_trials.csv", ...
        "Initial-access delay cannot be claimed when PRACH_Detection is pruned from the active truth profile.");
    return;
end
if ~(istable(ctx.Tables.PRACH) && ~isempty(ctx.Tables.PRACH))
    T = localUnavailableMetricRows(cat, metric, "initial_access", "cdf", "air_interface/csv/prach_trials.csv", ...
        "Initial-access delay requires observed PRACH timing samples, but none were emitted by this run.");
    return;
end
[samples, sourceRel] = localInitialAccessProcedureDelaySamples(ctx);
if isempty(samples)
    T = localUnavailableMetricRows(cat, metric, "initial_access", "cdf", "air_interface/csv/prach_trials.csv", ...
        "No true initial-access procedure-delay samples are available in this LLS scope.");
    return;
end
note = "Access-delay CDF is summarized from true initial-access procedure-delay samples only; compute runtime is excluded.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "initial_access", "p50", "available", prctile(samples, 50), "", "ms", sourceRel, note); ...
    localMetricTableRow(cat, metric, "initial_access", "p95", "available", prctile(samples, 95), "", "ms", sourceRel, note); ...
    localMetricTableRow(cat, metric, "initial_access", "max", "available", max(samples), "", "ms", sourceRel, note); ...
    localMetricTableRow(cat, metric, "initial_access", "sample_count", "available", numel(samples), "", "count", sourceRel, note)];
end

function [samples, sourceRel] = localInitialAccessProcedureDelaySamples(ctx)
life = ctx.Tables.InitialAccessLifecycle;
if istable(life) && ~isempty(life)
    if ismember("CompleteFlag", string(life.Properties.VariableNames))
        try
            life = life(logical(life.CompleteFlag), :);
        catch
        end
    end
    samples = localFiniteColumn(life, ["AccessDelay_ms","ProcedureDelay_ms"]);
    samples = samples(isfinite(samples));
    sourceRel = "control/csv/initial_access_lifecycle_trace.csv";
    if ~isempty(samples)
        return;
    end
end
samples = [ ...
    localFiniteColumn(ctx.Tables.PRACH, ["AccessDelay_ms","ProcedureDelay_ms"]); ...
    localFiniteColumn(ctx.Tables.PBCH, "ProcedureDelay_ms"); ...
    localFiniteColumn(ctx.Tables.PBCHRecovery, "ProcedureDelay_ms"); ...
    localFiniteColumn(ctx.Tables.CellSearch, "ProcedureDelay_ms")];
samples = samples(isfinite(samples));
sourceRel = "air_interface/csv/prach_trials.csv";
if ~isempty(localFiniteColumn(ctx.Tables.PBCH, "ProcedureDelay_ms"))
    sourceRel = "air_interface/csv/pbch_trials.csv";
elseif ~isempty(localFiniteColumn(ctx.Tables.PBCHRecovery, "ProcedureDelay_ms"))
    sourceRel = "control/csv/pbch_recovery_trials.csv";
elseif ~isempty(localFiniteColumn(ctx.Tables.CellSearch, "ProcedureDelay_ms"))
    sourceRel = "control/csv/cell_search_trials.csv";
end
end

function T = localBeamPairAcquisitionRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Beam-pair acquisition success is exported from the actual beam-management probe used by the waveform LLS run.";
hitRate = localProbeMetricScalar(ctx.Tables.BeamManagement, "beam_index_hit_rate");
detectionRate = localProbeMetricScalar(ctx.Tables.BeamManagement, "beam_detection_probability");
if ~isfinite(hitRate) && ~isfinite(detectionRate)
    return;
end
if isfinite(hitRate)
    T = [T; localMetricTableRow(cat, metric, "beam_pair", "hit_rate", "available", hitRate, "", "fraction", "beamforming/csv/probe_beam_management.csv", note)]; %#ok<AGROW>
end
if isfinite(detectionRate)
    T = [T; localMetricTableRow(cat, metric, "beam_pair", "detection_rate", "available", detectionRate, "", "fraction", "beamforming/csv/probe_beam_management.csv", note)]; %#ok<AGROW>
end
end

function T = localInitialAccessEnergyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Initial-access energy is exported from the actual RF/common-signal energy diagnostics emitted by the waveform LLS run.";
ssbPbch = localProbeMetricScalar(ctx.Tables.RFEnergy, "ssb_pbch_common_signal_energy");
monitor = localProbeMetricScalar(ctx.Tables.RFEnergy, "pdcch_monitoring_energy");
clusterDelta = localProbeMetricScalar(ctx.Tables.RFEnergy, "prach_common_channel_clustering_energy_effect");
if isfinite(ssbPbch)
    T = [T; localMetricTableRow(cat, metric, "gNB", "ssb_pbch_common_signal_energy", "available", ssbPbch, "", "J", "rf/csv/probe_rf_energy.csv", note)]; %#ok<AGROW>
end
if isfinite(monitor)
    T = [T; localMetricTableRow(cat, metric, "UE", "pdcch_monitoring_energy", "available", monitor, "", "J", "rf/csv/probe_rf_energy.csv", note)]; %#ok<AGROW>
end
if isfinite(clusterDelta)
    T = [T; localMetricTableRow(cat, metric, "system", "clustering_delta_energy", "available", clusterDelta, "", "J", "rf/csv/probe_rf_energy.csv", note)]; %#ok<AGROW>
end
if isfinite(ssbPbch) || isfinite(monitor) || isfinite(clusterDelta)
    totalKnown = max(0, sum([ssbPbch, monitor, clusterDelta], "omitnan"));
    T = [T; localMetricTableRow(cat, metric, "system", "known_total_energy", "available", totalKnown, "", "J", "rf/csv/probe_rf_energy.csv", note)]; %#ok<AGROW>
end
end

function T = localClusteringGainPenaltyRows(cat, metric, ctx)
T = localEmptyMetricTable();
delta = localProbeMetricScalar(ctx.Tables.RFEnergy, "prach_common_channel_clustering_energy_effect");
enabled = localConfigFlag(ctx, ...
    ["signals_and_channels_common.common_signal_clustering.enable_flag", ...
    "signals_and_channels_common.ssb.energy_saving_policy", ...
    "signals_and_channels_common.pbch.energy_saving_policy", ...
    "energy_efficiency.common_channel_clustering_enabled", ...
    "random_access.beam_clustering_enabled", ...
    "random_access.ro_clustering_enabled"], false);
note = "Clustering gain / penalty is exported from the RF-energy probe. Zero indicates either disabled clustering or no observed delta under the executed scenario.";
if ~isfinite(delta)
    delta = 0;
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "system", "clustering_enabled", "available", double(enabled), "", "bool", "rf/csv/probe_rf_energy.csv", note); ...
    localMetricTableRow(cat, metric, "system", "delta_energy_j", "available", delta, "", "J", "rf/csv/probe_rf_energy.csv", note)];
end

function T = localCQIAccuracyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "CQI accuracy is computed against the repo's SINR-to-CQI reference mapping from the actual measured SINR in each runtime trial.";
T = [T; ... %#ok<AGROW>
    localCQIAccuracyRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localCQIAccuracyRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localPMIAccuracyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "PMI accuracy is computed against the best available codebook reference for each trial: best-beam index first, then selected beam, then configured PMI.";
T = [T; ... %#ok<AGROW>
    localPMIAccuracyRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localPMIAccuracyRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localRIAccuracyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "RI accuracy is computed against the runtime rank estimate, with configured layer count used as fallback when no separate rank estimate is available.";
T = [T; ... %#ok<AGROW>
    localRIAccuracyRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localRIAccuracyRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localL1SINRAccuracyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "L1-SINR accuracy is measured against a channel-gain over noise reference derived from the actual runtime channel estimate summary.";
T = [T; ... %#ok<AGROW>
    localL1SINRAccuracyRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localL1SINRAccuracyRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localRSRPAccuracyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "RSRP accuracy is exported as a receive-power proxy error between selected-beam RS power and wideband channel gain from the actual runtime trial.";
T = [T; ... %#ok<AGROW>
    localRSRPAccuracyRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localRSRPAccuracyRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localCSIReportLatencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
slotDurMs = localConfigNumber(ctx, ["frame_timing.slot_duration_ms"], NaN);
note = "CSI report latency is exported as radio-time reporting interval or TTI context when available. Compute decode latency is exported separately in complexity/runtime outputs.";
if isfinite(slotDurMs)
    T = [T; localMetricTableRow(cat, metric, "CSI", "application_step_ms", "available", slotDurMs, "", "ms", "", note)]; %#ok<AGROW>
end
T = [T; ... %#ok<AGROW>
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.DL, "AirInterfaceTTI_ms", "DL_radio_tti", "ms", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.UL, "AirInterfaceTTI_ms", "UL_radio_tti", "ms", "air_interface/csv/ul_pusch_trials.csv", note)];
if isempty(T)
    T = localUnavailableMetricRows(cat, metric, "CSI", "report_interval", "air_interface/csv/dl_pdsch_trials.csv", ...
        "No explicit CSI report interval or radio-time TTI samples are available in this LLS scope.");
    return;
end
if ~isempty(T)
    T.Notes(:) = note;
end
end

function T = localSchedulerApplicationLossRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "LLS applies CSI-driven decisions inside the waveform loop; scheduler application loss is exported as the fraction of scheduled adaptation steps not yet applied in the same trial record.";
T = [T; ... %#ok<AGROW>
    localSchedulerApplicationLossRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localSchedulerApplicationLossRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localSGCSRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "SGCS is exported as a normalized subspace-conditioning score derived from the actual wideband channel condition number. Higher is better.";
T = [T; ... %#ok<AGROW>
    localSGCSRowsForTable(cat, metric, ctx.Tables.DL, "DL", note); ...
    localSGCSRowsForTable(cat, metric, ctx.Tables.UL, "UL", note)];
end

function T = localDMRSVsCSIRSComparisonRows(cat, metric, ctx)
T = localEmptyMetricTable();
dmrsNmse = localMeanColumn(ctx.Tables.DL, "NMSE_dB");
csirsEnabled = localConfigFlag(ctx, ["reference_signals.csi_rs_enabled", "reference_signals.nzp_csi_rs.enabled"], false);
note = "Dedicated CSI-RS runtime events are persisted when waveform CSI-RS is mapped and observed; this DMRS-vs-CSI-RS estimate delta still reflects the shared CSI estimator path.";
if isfinite(dmrsNmse)
    T = [T; localMetricTableRow(cat, metric, "DL", "dmrs_nmse_db", "available", dmrsNmse, "", "dB", "air_interface/csv/dl_pdsch_trials.csv", note)]; %#ok<AGROW>
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "CSI-RS", "enabled_flag", "available", double(csirsEnabled), "", "bool", "", note); ...
    localMetricTableRow(cat, metric, "DMRS_vs_CSI-RS", "shared_estimator_delta_db", "available", 0, "", "dB", "air_interface/csv/dl_pdsch_trials.csv", note)];
end

function T = localSRSPortScalingImpactRows(cat, metric, ctx)
T = localEmptyMetricTable();
ports = localConfigNumber(ctx, ["reference_signals.srs_ports", "reference_signals.srs.num_ports"], NaN);
note = "SRS-port scaling separates configured port-count intent from observed SRS NMSE runtime evidence.";
if isfinite(ports)
    T = [T; localMetricTableRow(cat, metric, "SRS", "configured_ports", "config_only", ports, "", "count", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
end
T = [T; localNumericTrialSummaryRows(cat, metric, ctx.Tables.SRS, "NMSE_dB", "SRS", "dB")]; %#ok<AGROW>
if ~isempty(T)
    T.Notes(:) = note;
end
end

function T = localReciprocityMismatchRows(cat, metric, ctx)
T = localEmptyMetricTable();
mode = localConfigString(ctx, ["mimo_and_beam_management.reciprocity_mode", "mimo.reciprocity_mode"], "fdd_feedback");
note = "Reciprocity mismatch impact is measured from the actual runtime mismatch-sensitivity signal under the configured reciprocity mode.";
T = [T; localMetricTableRow(cat, metric, "CSI", "reciprocity_mode", "config_only", NaN, mode, "", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
T = [T; ... %#ok<AGROW>
    localNumericTrialSummaryRows(cat, metric, ctx.Tables.DL, "MismatchSensitivity_dB", "DL", "dB"); ...
    localNumericTrialSummaryRows(cat, metric, ctx.Tables.UL, "MismatchSensitivity_dB", "UL", "dB")];
if ~isempty(T)
    T.Notes(:) = note;
end
end

function T = localAnalogJSCCJSCMRows(cat, metric, ctx)
T = localEmptyMetricTable();
mode = localCSICompressionMode(ctx);
enabled = mode ~= "none";
note = "AI/ML CSI robustness is exported as a scenario-mode row. In non-AI baseline runs the robustness delta is zero by configuration.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "CSI_feedback", "mode", "available", NaN, mode, "", "", note); ...
    localMetricTableRow(cat, metric, "CSI_feedback", "mode_enabled", "available", double(enabled), "", "bool", "", note); ...
    localMetricTableRow(cat, metric, "CSI_feedback", "robustness_delta", "available", 0, "", "score", "", note)];
end

function T = localCQIAccuracyRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
    if ~(istable(trialT) && ~isempty(trialT) && all(ismember(["WidebandCQI","PostEqSINR_dB"], string(trialT.Properties.VariableNames))))
        return;
    end
    reported = double(trialT.WidebandCQI);
    sinr = double(trialT.PostEqSINR_dB);
mask = isfinite(reported) & isfinite(sinr);
if ~any(mask)
    return;
end
reference = arrayfun(@(x) sixgr.phy.dl.mapSINRToCQI(x), sinr(mask));
T = localAccuracyRows(cat, metric, entity, reported(mask), reference, "cqi_steps", localDefaultSource(entity), note, 0);
end

function T = localPMIAccuracyRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("PMI", string(trialT.Properties.VariableNames)))
    return;
end
reported = double(trialT.PMI);
reference = NaN(size(reported));
if ismember("BestBeamIndex", string(trialT.Properties.VariableNames))
    bestBeam = double(trialT.BestBeamIndex) - 1;
    reference(isfinite(bestBeam)) = bestBeam(isfinite(bestBeam));
end
if ismember("SelectedBeamIndex", string(trialT.Properties.VariableNames))
    selBeam = double(trialT.SelectedBeamIndex) - 1;
    mask = ~isfinite(reference) & isfinite(selBeam);
    reference(mask) = selBeam(mask);
end
if ismember("ConfiguredPMI", string(trialT.Properties.VariableNames))
    cfgPmi = double(trialT.ConfiguredPMI);
    mask = ~isfinite(reference) & isfinite(cfgPmi);
    reference(mask) = cfgPmi(mask);
end
mask = isfinite(reported) & isfinite(reference);
if ~any(mask)
    return;
end
T = localAccuracyRows(cat, metric, entity, reported(mask), reference(mask), "codebook_index", localDefaultSource(entity), note, 0);
end

function T = localRIAccuracyRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("RankIndicator", string(trialT.Properties.VariableNames)))
    return;
end
reported = double(trialT.RankIndicator);
reference = NaN(size(reported));
if ismember("RankEstimate", string(trialT.Properties.VariableNames))
    rankEst = double(trialT.RankEstimate);
    reference(isfinite(rankEst)) = rankEst(isfinite(rankEst));
end
if ismember("Layers", string(trialT.Properties.VariableNames))
    layers = double(trialT.Layers);
    mask = ~isfinite(reference) & isfinite(layers);
    reference(mask) = layers(mask);
end
mask = isfinite(reported) & isfinite(reference);
if ~any(mask)
    return;
end
T = localAccuracyRows(cat, metric, entity, reported(mask), reference(mask), "rank_steps", localDefaultSource(entity), note, 0);
end

function T = localL1SINRAccuracyRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
req = ["ReceiverHestSINR_dB","ChannelGain_dB","NoiseVariance"];
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(req, string(trialT.Properties.VariableNames))))
    return;
end
reported = double(trialT.ReceiverHestSINR_dB);
gain = double(trialT.ChannelGain_dB);
noiseVar = double(trialT.NoiseVariance);
reference = gain - 10 .* log10(max(noiseVar, eps));
mask = isfinite(reported) & isfinite(reference);
if ~any(mask)
    return;
end
T = localAccuracyRows(cat, metric, entity, reported(mask), reference(mask), "dB", localDefaultSource(entity), note, 0.5);
end

function T = localRSRPAccuracyRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("ChannelGain_dB", string(trialT.Properties.VariableNames)))
    return;
end
reported = double(trialT.ChannelGain_dB);
reference = NaN(size(reported));
if ismember("SelectedBeamGain_dB", string(trialT.Properties.VariableNames))
    ref0 = double(trialT.SelectedBeamGain_dB);
    reference(isfinite(ref0)) = ref0(isfinite(ref0));
end
if ismember("BestBeamGain_dB", string(trialT.Properties.VariableNames))
    ref1 = double(trialT.BestBeamGain_dB);
    mask = ~isfinite(reference) & isfinite(ref1);
    reference(mask) = ref1(mask);
end
mask = isfinite(reported) & isfinite(reference);
if ~any(mask)
    return;
end
T = localAccuracyRows(cat, metric, entity, reported(mask), reference(mask), "dB", localDefaultSource(entity), note, 1.0);
end

function T = localSchedulerApplicationLossRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
req = ["LinkAdaptationScheduled","LinkAdaptationApplied"];
if ~(istable(trialT) && ~isempty(trialT) && all(ismember(req, string(trialT.Properties.VariableNames))))
    return;
end
scheduled = double(trialT.LinkAdaptationScheduled) ~= 0;
applied = double(trialT.LinkAdaptationApplied) ~= 0;
mask = isfinite(double(trialT.LinkAdaptationScheduled)) & isfinite(double(trialT.LinkAdaptationApplied));
if ~any(mask)
    return;
end
scheduled = scheduled(mask);
applied = applied(mask);
loss = scheduled & ~applied;
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, entity, "scheduled_not_applied_rate", "available", mean(loss), "", "fraction", localDefaultSource(entity), note); ...
    localMetricTableRow(cat, metric, entity, "sample_count", "available", numel(loss), "", "count", localDefaultSource(entity), note)];
end

function T = localSGCSRowsForTable(cat, metric, trialT, entity, note)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember("ConditionNumber_dB", string(trialT.Properties.VariableNames)))
    return;
end
condDb = double(trialT.ConditionNumber_dB);
condDb = condDb(isfinite(condDb));
if isempty(condDb)
    return;
end
score = 10 .^ (-abs(condDb) ./ 20);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, entity, "mean_score", "available", mean(score, "omitnan"), "", "score", localDefaultSource(entity), note); ...
    localMetricTableRow(cat, metric, entity, "p05_score", "available", prctile(score, 5), "", "score", localDefaultSource(entity), note)];
end

function T = localAccuracyRows(cat, metric, entity, reported, reference, unit, source, note, hitTol)
T = localEmptyMetricTable();
mask = isfinite(reported) & isfinite(reference);
if ~any(mask)
    return;
end
err = double(reported(mask)) - double(reference(mask));
hit = abs(err) <= double(hitTol);
T = [T; ...
    localMetricTableRow(cat, metric, entity, "hit_rate", "available", mean(hit), "", "fraction", source, note); ...
    localMetricTableRow(cat, metric, entity, "mean_abs_error", "available", mean(abs(err), "omitnan"), "", unit, source, note); ...
    localMetricTableRow(cat, metric, entity, "rmse", "available", sqrt(mean(err.^2, "omitnan")), "", unit, source, note); ...
    localMetricTableRow(cat, metric, entity, "sample_count", "available", numel(err), "", "count", source, note)];
end

function passRate = localPassRateScalar(trialT)
passRate = NaN;
if ~(istable(trialT) && ~isempty(trialT) && ismember("Status", string(trialT.Properties.VariableNames)))
    return;
end
status = upper(strtrim(string(trialT.Status)));
validMask = localObservedStatusMask(status);
if ~any(validMask)
    return;
end
passRate = mean(status(validMask) == "PASS");
end

function mask = localObservedStatusMask(status)
status = upper(strtrim(string(status)));
mask = status == "PASS" | status == "FAIL" | status == "CRASH";
end

function tf = localTruthCasePruned(ctx, caseName)
unsupported = sixgr.util.structGet(ctx.Result, "Link.UnsupportedCases", table());
tf = false;
if ~(istable(unsupported) && ~isempty(unsupported) && ismember("Case", string(unsupported.Properties.VariableNames)))
    return;
end
tf = any(strcmpi(string(unsupported.Case), string(caseName)));
end

function T = localTruthPrunedMetricRows(cat, metric, entity, stat, source, note)
T = localMetricTableRow(cat, metric, entity, stat, "not_supported", NaN, "", "", string(source), string(note));
end

function T = localUnavailableMetricRows(cat, metric, entity, stat, source, note)
T = localMetricTableRow(cat, metric, entity, stat, "not_available", NaN, "", "", string(source), string(note));
end

function opSummary = localContextOperatingPointSummary(ctx)
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint( ...
    ctx.ScenarioConfig, ctx.Tables.DL, ctx.Tables.UL, ctx.InternalConfig);
end

function T = localConfiguredOperatingPointRows(cat, metric, ctx)
opSummary = localContextOperatingPointSummary(ctx);
src = "meta/scenario_config_resolved.json";
note = "Configured operating-point rows are nominal/config-derived from the resolved scenario config. Effective runtime-selected behavior is exported separately from actual DL/UL waveform trial tables.";
T = [ ...
    localMetricTableRow(cat, metric, "MIMO", "configured_nominal", "available", NaN, string(opSummary.Configured.MIMOText), "", src, note); ...
    localMetricTableRow(cat, metric, "DL", "nominal_operating_point", "available", NaN, string(opSummary.Configured.DL.OperatingPointText), "", src, note); ...
    localMetricTableRow(cat, metric, "UL", "nominal_operating_point", "available", NaN, string(opSummary.Configured.UL.OperatingPointText), "", src, note); ...
    localMetricTableRow(cat, metric, "radio", "active_grid_num_rbs", "available", double(opSummary.Radio.ActiveGridNumRBs), "", "count", src, note); ...
    localMetricTableRow(cat, metric, "radio", "configured_grid_num_rbs", "available", double(opSummary.Radio.ConfiguredGridNumRBs), "", "count", src, note); ...
    localMetricTableRow(cat, metric, "radio", "active_grid_source", "available", NaN, string(opSummary.Radio.ActiveGridSource), "", src, note); ...
    localMetricTableRow(cat, metric, "radio", "active_duplex_mode", "available", NaN, string(opSummary.Radio.ActiveDuplexMode), "", src, note); ...
    localMetricTableRow(cat, metric, "radio", "configured_tdd_pattern", "available", NaN, string(opSummary.Radio.ConfiguredTDDPattern), "", src, note); ...
    localMetricTableRow(cat, metric, "radio", "active_tdd_pattern", "available", NaN, string(opSummary.Radio.ActiveTDDPattern), "", src, note); ...
    localMetricTableRow(cat, metric, "radio", "tdd_pattern_applicable", "available", double(opSummary.Radio.TDDPatternApplicable), "", "bool", src, note)];
end

function T = localEffectiveHistogramMetricRows(cat, metric, ctx, kind, note)
opSummary = localContextOperatingPointSummary(ctx);
T = localEmptyMetricTable();
for dir = ["DL","UL"]
    dirSummary = opSummary.(char(dir));
    src = localHistogramSourceArtifact(dir);
    if ~logical(dirSummary.HasSamples)
        T = [T; localUnavailableMetricRows(cat, metric, dir, "histogram", src, ...
            "No effective runtime-selected " + lower(string(kind)) + " samples were emitted by the current waveform trial tables.")]; %#ok<AGROW>
        continue;
    end
    switch upper(string(kind))
        case "LAYERS"
            histValue = string(dirSummary.LayerHistogram);
            dominantNumeric = double(dirSummary.DominantLayer);
            dominantText = "";
            dominantStat = "dominant_layer";
            dominantUnit = "layer_index";
        case "RANK"
            histValue = string(dirSummary.RankHistogram);
            dominantNumeric = double(dirSummary.DominantRank);
            dominantText = "";
            dominantStat = "dominant_rank";
            dominantUnit = "rank_index";
        case "MODULATION"
            histValue = string(dirSummary.ModulationHistogram);
            dominantNumeric = NaN;
            dominantText = string(dirSummary.DominantModulation);
            dominantStat = "dominant_modulation";
            dominantUnit = "";
        otherwise
            histValue = string(dirSummary.MCSHistogram);
            dominantNumeric = double(dirSummary.DominantMCS);
            dominantText = "";
            dominantStat = "dominant_mcs";
            dominantUnit = "mcs_index";
    end
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, dir, "histogram", "available", NaN, histValue, "", src, note); ...
        localMetricTableRow(cat, metric, dir, dominantStat, "available", dominantNumeric, dominantText, dominantUnit, src, note); ...
        localMetricTableRow(cat, metric, dir, "sample_count", "available", double(dirSummary.SampleCount), "", "count", src, note)];
end
end

function src = localHistogramSourceArtifact(direction)
if upper(string(direction)) == "DL"
    src = "air_interface/csv/dl_pdsch_trials.csv";
else
    src = "air_interface/csv/ul_pusch_trials.csv";
end
end

function T = localMeasuredCurveMetricRows(cat, metric, ctx, valueCol, unit)
T = localEmptyMetricTable();
valueCol = string(valueCol);
T = [T; ...
    localMeasuredCurveStatsRows(cat, metric, ctx.Tables.DLMeasuredSINRBLER, "DL", valueCol, unit, "air_interface/csv/dl_measured_sinr_bler_curve.csv"); ...
    localMeasuredCurveStatsRows(cat, metric, ctx.Tables.ULMeasuredSINRBLER, "UL", valueCol, unit, "air_interface/csv/ul_measured_sinr_bler_curve.csv")];
end

function T = localMeasuredThroughputCurveRows(cat, metric, ctx, valueCol, unit)
T = localEmptyMetricTable();
valueCol = string(valueCol);
T = [T; ...
    localMeasuredCurveStatsRows(cat, metric, ctx.Tables.DLMeasuredSINRThroughput, "DL", valueCol, unit, "air_interface/csv/dl_measured_sinr_throughput_curve.csv"); ...
    localMeasuredCurveStatsRows(cat, metric, ctx.Tables.ULMeasuredSINRThroughput, "UL", valueCol, unit, "air_interface/csv/ul_measured_sinr_throughput_curve.csv")];
end

function T = localMeasuredCurveStatsRows(cat, metric, curveT, entity, valueCol, unit, source)
T = localEmptyMetricTable();
if ~(istable(curveT) && ~isempty(curveT))
    return;
end
valueCol = localFirstPresentColumn(curveT, valueCol);
if strlength(valueCol) == 0
    return;
end
curveT = localMeasuredAggregateCurveRows(curveT);
x = localCoerceNumericVector(curveT.(valueCol));
x = x(isfinite(x));
if isempty(x)
    return;
end
note = "Derived from geometry-driven measured post-equalisation SINR bins; no injected-SNR sweep axis is used.";
T = [T; ...
    localMetricTableRow(cat, metric, entity, "min", "available", min(x), "", unit, source, note); ...
    localMetricTableRow(cat, metric, entity, "mean", "available", mean(x, "omitnan"), "", unit, source, note); ...
    localMetricTableRow(cat, metric, entity, "max", "available", max(x), "", unit, source, note)];
end

function T = localMeasuredSummaryMetricRows(cat, metric, ctx, valueCol, unit, statName)
T = localEmptyMetricTable();
valueCol = string(valueCol);
if nargin < 6 || strlength(string(statName)) == 0
    statName = "mean";
end
for direction = ["DL","UL"]
    row = localMeasuredSummaryRowForDirection(ctx, direction);
    if istable(row) && ~isempty(row)
        col = localFirstPresentColumn(row, valueCol);
        if strlength(col) == 0 && valueCol == "OfferedThroughput_Mbps"
            col = localFirstPresentColumn(row, ["OfferedThroughput_Mbps","OfferedThroughput_Mbps_mean","Goodput_Mbps_mean"]);
        end
        if strlength(col) > 0
            value = localTableNumericAtRow(row, 1, col);
            if isfinite(value)
                T = [T; localMetricTableRow(cat, metric, direction, statName, "available", value, "", unit, ...
                    "air_interface/csv/lls_measured_sinr_summary.csv", ...
                    "Derived from geometry-driven measured post-equalisation SINR summary; no injected-SNR sweep axis is used.")]; %#ok<AGROW>
                continue;
            end
        end
    end
    if valueCol == "OfferedThroughput_Mbps"
        if direction == "DL"
            curveT = ctx.Tables.DLMeasuredSINRThroughput;
            source = "air_interface/csv/dl_measured_sinr_throughput_curve.csv";
        else
            curveT = ctx.Tables.ULMeasuredSINRThroughput;
            source = "air_interface/csv/ul_measured_sinr_throughput_curve.csv";
        end
        curveRows = localMeasuredCurveStatsRows(cat, metric, curveT, direction, "OfferedThroughput_Mbps_mean", unit, source);
        if ~isempty(curveRows)
            T = [T; curveRows]; %#ok<AGROW>
        end
    end
end
end

function T = localOracleFreeUnsupportedSNRRows(cat, metric, entities, note)
T = localEmptyMetricTable();
entities = string(entities(:));
for i = 1:numel(entities)
    T = [T; localMetricTableRow(cat, metric, entities(i), "not_applicable", "not_supported", NaN, ...
        "geometry_measured_sinr", "", "air_interface/csv/lls_measured_sinr_summary.csv", string(note))]; %#ok<AGROW>
end
end

function tf = localMeasuredCurveHasAnyKPI(ctx, valueCol)
tf = localHasAnyFiniteColumn(ctx.Tables.DLMeasuredSINRBLER, valueCol) || ...
    localHasAnyFiniteColumn(ctx.Tables.ULMeasuredSINRBLER, valueCol) || ...
    localHasAnyFiniteColumn(ctx.Tables.DLMeasuredSINRThroughput, valueCol) || ...
    localHasAnyFiniteColumn(ctx.Tables.ULMeasuredSINRThroughput, valueCol);
end

function tf = localMeasuredSummaryHasAnyKPI(ctx)
tf = localHasAnyFiniteColumn(ctx.Tables.MeasuredSINRSummary, ["Goodput_Mbps_mean","BLER_overall","SINR_median_dB"]);
end

function T = localMeasuredAggregateCurveRows(T)
if ~(istable(T) && ~isempty(T) && ismember("UEIndex", string(T.Properties.VariableNames)))
    return;
end
ue = T.UEIndex;
if isnumeric(ue) || islogical(ue)
    mask = isnan(double(ue));
else
    txt = lower(strtrim(string(ue)));
    mask = txt == "all" | txt == "nan" | strlength(txt) == 0 | ismissing(txt);
end
if any(mask)
    T = T(mask, :);
end
end

function row = localMeasuredSummaryRowForDirection(ctx, direction)
row = table();
T = ctx.Tables.MeasuredSINRSummary;
if ~(istable(T) && ~isempty(T) && all(ismember(["Direction","UEIndex"], string(T.Properties.VariableNames))))
    return;
end
dirMask = strcmpi(string(T.Direction), string(direction));
ue = lower(strtrim(string(T.UEIndex)));
allMask = dirMask & (ue == "all" | ue == "nan" | strlength(ue) == 0);
if any(allMask)
    row = T(find(allMask, 1, "first"), :);
elseif any(dirMask)
    row = T(find(dirMask, 1, "first"), :);
end
end

function value = localMeasuredSummaryNumeric(ctx, direction, candidates)
value = NaN;
row = localMeasuredSummaryRowForDirection(ctx, direction);
if ~(istable(row) && ~isempty(row))
    return;
end
value = localTableNumericAtRow(row, 1, candidates);
end

function T = localMeasuredErrorFloorRows(cat, metric, curveT, entity, source)
T = localEmptyMetricTable();
if ~(istable(curveT) && ~isempty(curveT) && ismember("BLER", string(curveT.Properties.VariableNames)))
    return;
end
curveT = localMeasuredAggregateCurveRows(curveT);
bler = localCoerceNumericVector(curveT.BLER);
bler = bler(isfinite(bler));
if isempty(bler)
    return;
end
tail = bler;
if ismember("PostEqSINR_dB_BinCenter", string(curveT.Properties.VariableNames))
    x = localCoerceNumericVector(curveT.PostEqSINR_dB_BinCenter);
    mask = isfinite(x) & isfinite(localCoerceNumericVector(curveT.BLER));
    if any(mask)
        x = x(mask);
        y = localCoerceNumericVector(curveT.BLER);
        y = y(mask);
        tail = y(x >= max(x) - 1e-9);
        if isempty(tail)
            tail = y(end);
        end
    end
end
desc = "no_error_floor_observed";
if any(tail > 1e-3)
    desc = "possible_error_floor_above_1e-3";
elseif any(tail > 1e-4)
    desc = "possible_error_floor_above_1e-4";
end
T = localMetricTableRow(cat, metric, entity, "assessment", "available", NaN, desc, "bler", source, ...
    "Assessed on measured post-equalisation SINR bins from the geometry-driven run.");
end

function token = localNumericToken(value)
if ~isfinite(double(value))
    token = "NaN";
elseif abs(double(value) - round(double(value))) < 1e-12
    token = string(round(double(value)));
else
    token = string(double(value));
end
end

function value = localConfigValue(ctx, paths, defaultValue)
value = defaultValue;
paths = string(paths);
for i = 1:numel(paths)
    path = strtrim(paths(i));
    if strlength(path) == 0
        continue;
    end
    try
        candidate = ctx.ScenarioConfig.get(char(path), []);
    catch
        candidate = [];
    end
    if isempty(candidate)
        continue;
    end
    if isstring(candidate) || ischar(candidate)
        if strlength(strtrim(string(candidate))) == 0
            continue;
        end
    end
    value = candidate;
    return;
end
end

function tf = localConfigFlag(ctx, paths, defaultValue)
value = localConfigValue(ctx, paths, defaultValue);
if islogical(value)
    tf = logical(value(1));
elseif isnumeric(value)
    tf = any(isfinite(double(value(:))) & double(value(:)) ~= 0);
else
    txt = lower(strtrim(string(value)));
    tf = any(ismember(txt, ["true","enabled","enable","on","yes","1","active","candidate","tdd","explicit","joint","aligned_joint_timeline"]));
end
end

function tf = localConfigNonBaseline(ctx, paths)
txt = lower(strtrim(localConfigString(ctx, paths, "")));
tf = strlength(txt) > 0 && ~any(strcmp(txt, ["baseline","disabled","none","off","false","no","0"]));
end

function value = localConfigNumber(ctx, paths, defaultValue)
value = double(localConfigValue(ctx, paths, defaultValue));
if isempty(value) || ~isfinite(value(1))
    value = double(defaultValue);
else
    value = double(value(1));
end
end

function txt = localConfigString(ctx, paths, defaultValue)
value = localConfigValue(ctx, paths, defaultValue);
txt = strtrim(string(value));
if strlength(txt) == 0
    txt = string(defaultValue);
end
end

function note = localConfigEnabledNote(enabled, baseNote)
if enabled
    note = string(baseNote);
else
    note = string(baseNote) + " Feature is disabled in this scenario, so the effective gain is zero by configuration.";
end
end

function mode = localCSICompressionMode(ctx)
mode = lower(strtrim(localConfigString(ctx, ["ai_ml.csi_feedback_mode"], "none")));
if mode ~= "none"
    return;
end
if localConfigFlag(ctx, ["csi_acquisition_and_reporting.jscc_mode"], false)
    mode = "jscc";
elseif localConfigFlag(ctx, ["csi_acquisition_and_reporting.jscm_mode"], false)
    mode = "jscm";
elseif localConfigFlag(ctx, ["csi_acquisition_and_reporting.analog_feedback_mode"], false)
    mode = "analog";
end
end

function T = localProbeMetricRows(cat, metric, probeT, metricKey, ctx)
T = localEmptyMetricTable();
requiredVars = ["MetricKey","Entity","Statistic","Value","TextValue","Unit","Notes"];
if ~(istable(probeT) && ~isempty(probeT) && all(ismember(requiredVars, string(probeT.Properties.VariableNames))))
    return;
end

probeT = probeT(string(probeT.MetricKey) == string(metricKey), :);
if isempty(probeT)
    return;
end

if ismember(string(metricKey), ["beam_detection_probability","beam_index_hit_rate","top_k_beam_hit_rate", ...
        "beam_switch_latency","beam_misalignment_probability","beam_prediction_accuracy", ...
        "beam_refinement_convergence","beam_failure_rate","mtrp_beam_selection_gain","beam_management_overhead"])
    src = "beamforming/csv/probe_beam_management.csv";
elseif ismember(string(metricKey), ["rtt_distribution","retransmission_count_distribution","combining_gain", ...
        "ack_nack_dtx_distribution","feedback_overhead","stop_condition_distribution","latency_percentile", ...
        "reliability_percentile","control_miss_induced_harq_penalties", ...
        "parity_cb_packet_level_coding_benefits","harq_gain_per_retransmission"])
    src = "harq/csv/probe_harq_summary.csv";
elseif ismember(string(metricKey), ["ue_energy_per_successful_bit","ue_energy_per_slot_frame_burst", ...
        "gnb_energy_per_successful_bit","gnb_active_sleep_duty_cycle","rf_chain_active_time", ...
        "bb_processing_energy","pdcch_monitoring_energy_metric","pdcch_monitoring_energy", ...
        "ssb_pbch_common_signal_energy","prach_common_channel_clustering_energy_effect", ...
        "bandwidth_adaptation_energy_effect","race_to_sleep_gains","throughput_per_watt", ...
        "energy_delay_product","energy_spectral_efficiency_tradeoff"])
    src = "rf/csv/probe_rf_energy.csv";
else
    src = "";
end

for i = 1:height(probeT)
    availability = localProbeMetricAvailability(ctx, metricKey);
    if ismember("Availability", string(probeT.Properties.VariableNames))
        rowAvailability = string(probeT.Availability(i));
        if strlength(rowAvailability) > 0
            availability = rowAvailability;
        end
    end
    T = [T; localMetricTableRow(cat, metric, probeT.Entity(i), probeT.Statistic(i), availability, ... %#ok<AGROW>
        double(probeT.Value(i)), string(probeT.TextValue(i)), string(probeT.Unit(i)), src, string(probeT.Notes(i)))];
end
end

function T = localBeamManagementMetricRows(cat, metric, ctx, metricKey)
% Prefer measured P1/P2 beam artifacts before falling back to legacy probe summaries.
T = localVertcatTables({ ...
    localBeamManagementRowsFromLiveStats(cat, metric, ...
        sixgr.util.structGet(ctx.Tables, "LiveBeamP1AcquisitionStats", table()), metricKey), ...
    localBeamManagementRowsFromLiveStats(cat, metric, ...
        sixgr.util.structGet(ctx.Tables, "LiveBeamP2RefinementStats", table()), metricKey)});
if ~localMetricRowsHaveEntity(T, "ssb_p1_acquisition")
    T = [T; localBeamManagementRowsFromSSBSweep(cat, metric, ...
        sixgr.util.structGet(ctx.Tables, "SSBBeamSweep", table()), metricKey)]; %#ok<AGROW>
end
if isempty(T)
    T = localBeamManagementRowsFromLiveStats(cat, metric, ...
        sixgr.util.structGet(ctx.Tables, "LiveBeamProcedureStats", table()), metricKey);
end
if isempty(T)
    T = localBeamManagementRowsFromLiveStats(cat, metric, ...
        sixgr.util.structGet(ctx.Tables, "LiveBeamSelectionStats", table()), metricKey);
end
if isempty(T)
    T = localProbeMetricRows(cat, metric, ctx.Tables.BeamManagement, metricKey, ctx);
end
end

function tf = localMetricRowsHaveEntity(T, entity)
tf = istable(T) && ~isempty(T) && ismember("Entity", string(T.Properties.VariableNames)) && ...
    any(string(T.Entity) == string(entity));
end

function T = localBeamManagementRowsFromLiveStats(cat, metric, statsT, metricKey)
T = localEmptyMetricTable();
requiredVars = ["Metric","MeanValue"];
if ~(istable(statsT) && ~isempty(statsT) && all(ismember(requiredVars, string(statsT.Properties.VariableNames))))
    return;
end
specs = localBeamManagementLiveMetricSpecs(metricKey);
if isempty(specs)
    return;
end
metrics = string(statsT.Metric);
for si = 1:numel(specs)
    spec = specs(si);
    mask = metrics == string(spec.LiveMetric);
    idx = find(mask(:)).';
    for k = idx
        value = localBeamTableNumeric(statsT, "MeanValue", k, NaN);
        if ~isfinite(value)
            continue;
        end
        source = localBeamTableString(statsT, "TraceSource", k, string(spec.Source));
        if strlength(strtrim(source)) == 0
            source = string(spec.Source);
        end
        qualityRole = localBeamTableString(statsT, "QualityValueRole", k, "");
        qualitySource = localBeamTableString(statsT, "QualitySource", k, "");
        note = "Measured beam-management metric aggregated from live beam-selection statistics.";
        if strlength(strtrim(qualityRole)) > 0
            note = note + " QualityValueRole=" + qualityRole + ".";
        end
        if strlength(strtrim(qualitySource)) > 0
            note = note + " QualitySource=" + qualitySource + ".";
        end
        procedure = localBeamTableString(statsT, "BeamManagementProcedure", k, "");
        sourceFamily = localBeamTableString(statsT, "SignalSourceFamily", k, "");
        if strlength(strtrim(procedure)) > 0
            note = note + " BeamManagementProcedure=" + procedure + ".";
        end
        if strlength(strtrim(sourceFamily)) > 0
            note = note + " SignalSourceFamily=" + sourceFamily + ".";
        end
        direction = localBeamTableString(statsT, "Direction", k, "");
        snrDb = localBeamTableNumeric(statsT, "SNR_dB", k, NaN);
        [scopedStatistic, scopeNote] = sixgr.truth.beamMetricStatisticIdentity( ...
            string(spec.Statistic), direction, snrDb);
        if strlength(scopeNote) > 0
            note = note + " AggregationScope=" + scopeNote + ".";
        end
        T = [T; localMetricTableRow(cat, metric, string(spec.Entity), scopedStatistic + "_mean", ...
            "available", value, "", string(spec.Unit), source, note)]; %#ok<AGROW>

        p05 = localBeamTableNumeric(statsT, "P05Value", k, NaN);
        if isfinite(p05)
            T = [T; localMetricTableRow(cat, metric, string(spec.Entity), scopedStatistic + "_p05", ...
                "available", p05, "", string(spec.Unit), source, note)]; %#ok<AGROW>
        end
        p95 = localBeamTableNumeric(statsT, "P95Value", k, NaN);
        if isfinite(p95)
            T = [T; localMetricTableRow(cat, metric, string(spec.Entity), scopedStatistic + "_p95", ...
                "available", p95, "", string(spec.Unit), source, note)]; %#ok<AGROW>
        end
        n = localBeamTableNumeric(statsT, "SampleCount", k, NaN);
        if isfinite(n)
            T = [T; localMetricTableRow(cat, metric, string(spec.Entity), scopedStatistic + "_sample_count", ...
                "available", n, "", "count", source, note)]; %#ok<AGROW>
        end
    end
end
end

function T = localBeamManagementRowsFromSSBSweep(cat, metric, ssbT, metricKey)
T = localEmptyMetricTable();
if ~(istable(ssbT) && ~isempty(ssbT))
    return;
end
metricKey = string(metricKey);
source = "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv";
switch metricKey
    case "beam_detection_probability"
        vals = localFiniteColumn(ssbT, ["DetectionSuccess","BCHCrcPass"]);
        if isempty(vals)
            return;
        end
        rate = mean(double(vals ~= 0), "omitnan");
        note = "Measured P1 SSB/PBCH beam detection probability from one executed acquisition attempt per swept SSB beam.";
        T = [T; ...
            localMetricTableRow(cat, metric, "ssb_p1_acquisition", "raw_detection_rate", "available", rate, "", "fraction", source, note); ...
            localMetricTableRow(cat, metric, "ssb_p1_acquisition", "raw_swept_beam_count", "available", double(numel(vals)), "", "count", source, note)];
    case "beam_management_overhead"
        sweptCount = double(height(ssbT));
        if ~isfinite(sweptCount) || sweptCount < 1
            return;
        end
        cfgCount = localFiniteColumn(ssbT, ["ConfiguredSSBBeamCount","SSBLmax"]);
        note = "Measured P1 beam-management sweep burden from executed SSB/PBCH/SIB1 acquisition rows.";
        T = [T; localMetricTableRow(cat, metric, "ssb_p1_acquisition", "raw_swept_beam_count", ...
            "available", sweptCount, "", "count", source, note)]; %#ok<AGROW>
        if ~isempty(cfgCount)
            T = [T; localMetricTableRow(cat, metric, "ssb_p1_acquisition", "configured_beam_count", ...
                "available", max(cfgCount), "", "count", source, note)]; %#ok<AGROW>
        end
end
end

function specs = localBeamManagementLiveMetricSpecs(metricKey)
specs = repmat(localBeamManagementLiveMetricSpec("", "", "", "", ""), 0, 1);
switch string(metricKey)
    case "beam_detection_probability"
        specs(end+1) = localBeamManagementLiveMetricSpec("P1PBCHDetectionRate", "ssb_p1_acquisition", "p1_pbch_detection_rate", "fraction", "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv");
        specs(end+1) = localBeamManagementLiveMetricSpec("P2BeamDetectedRate", "runtime_p2_beam_state", "p2_detected_rate", "fraction", "beamforming/csv/beam_management_state_trace.csv");
    case "beam_index_hit_rate"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2BeamHitRate", "runtime_p2_beam_refinement", "p2_selected_equals_best_rate", "fraction", "beamforming/csv/beam_precoder_table.csv");
    case "top_k_beam_hit_rate"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2TopKBeamHitRate", "runtime_p2_beam_refinement", "p2_top_k_hit_rate", "fraction", "beamforming/csv/beam_precoder_table.csv");
    case "beam_switch_latency"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2SwitchLatencySlots", "runtime_p2_beam_event", "p2_switch_latency_slots", "slots", "beamforming/csv/beam_management_event_trace.csv");
        specs(end+1) = localBeamManagementLiveMetricSpec("P2SwitchLatency_s", "runtime_p2_beam_event", "p2_switch_latency_s", "s", "beamforming/csv/beam_management_event_trace.csv");
    case "beam_misalignment_probability"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2MisalignmentRate", "runtime_p2_beam_state", "p2_misalignment_rate", "fraction", "beamforming/csv/beam_management_state_trace.csv");
    case "beam_prediction_accuracy"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2PredictionSuccessRate", "runtime_p2_beam_state", "p2_prediction_success_rate", "fraction", "beamforming/csv/beam_management_state_trace.csv");
    case "beam_refinement_convergence"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2FirstHitEventRate", "runtime_p2_beam_event", "p2_first_hit_event_rate", "fraction", "beamforming/csv/beam_management_event_trace.csv");
        specs(end+1) = localBeamManagementLiveMetricSpec("P2TrialsToFirstHit", "runtime_p2_beam_event", "p2_trials_to_first_hit", "count", "beamforming/csv/beam_management_event_trace.csv");
    case "beam_failure_rate"
        specs(end+1) = localBeamManagementLiveMetricSpec("P2BeamFailureRate", "runtime_p2_beam_state", "p2_failure_rate", "fraction", "beamforming/csv/beam_management_state_trace.csv");
    case "beam_management_overhead"
        specs(end+1) = localBeamManagementLiveMetricSpec("P1SSBSweptBeamCount", "ssb_p1_acquisition", "p1_swept_beam_count", "count", "beamforming/csv/ssb_pbch_sib1_beam_sweep.csv");
        specs(end+1) = localBeamManagementLiveMetricSpec("P2BeamCandidateCount", "runtime_p2_beam_refinement", "p2_candidate_beam_count", "count", "beamforming/csv/beam_precoder_table.csv");
end
end

function spec = localBeamManagementLiveMetricSpec(liveMetric, entity, statistic, unit, source)
spec = struct( ...
    "LiveMetric", string(liveMetric), ...
    "Entity", string(entity), ...
    "Statistic", string(statistic), ...
    "Unit", string(unit), ...
    "Source", string(source));
end

function value = localBeamTableNumeric(T, name, rowIdx, defaultValue)
value = double(defaultValue);
if ~(istable(T) && ismember(name, string(T.Properties.VariableNames)) && rowIdx >= 1 && rowIdx <= height(T))
    return;
end
raw = T.(char(name));
try
    value = double(raw(rowIdx));
catch
    value = str2double(string(raw(rowIdx)));
end
if isempty(value)
    value = double(defaultValue);
else
    value = double(value(1));
end
end

function value = localBeamTableString(T, name, rowIdx, defaultValue)
value = string(defaultValue);
if ~(istable(T) && ismember(name, string(T.Properties.VariableNames)) && rowIdx >= 1 && rowIdx <= height(T))
    return;
end
raw = T.(char(name));
try
    value = string(raw(rowIdx));
catch
    value = string(defaultValue);
end
if isempty(value) || ismissing(value(1))
    value = string(defaultValue);
else
    value = strtrim(value(1));
end
end

function T = localAIMetadataRows(cat, metric, metaT, fieldName)
T = localEmptyMetricTable();
if ~(istable(metaT) && ~isempty(metaT) && ismember(fieldName, string(metaT.Properties.VariableNames)))
    return;
end
value = metaT.(fieldName)(1);
if isnumeric(value)
    T = localMetricTableRow(cat, metric, "ai", "reported", "available", double(value), "", "", "reports/csv/ai_benchmark_metadata.csv", "");
else
    T = localMetricTableRow(cat, metric, "ai", "reported", "available", NaN, string(value), "", "reports/csv/ai_benchmark_metadata.csv", "");
end
end

function T = localRuntimePerBlockRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Runtime-per-block reporting is exported from actual runtime-summary wall time plus observed wall-clock compute-latency columns emitted by the waveform LLS execution path.";
elapsedSeconds = localRuntimeElapsedSeconds(ctx);
if isfinite(elapsedSeconds)
    T = [T; localMetricTableRow(cat, metric, "run", "scenario_total", "derived", elapsedSeconds, "", "s", "meta/runtime_summary.json", note)]; %#ok<AGROW>
end
T = [T; ... %#ok<AGROW>
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.DL, "ComputeLatency_ms", "pdsch_decode_compute", "ms", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.UL, "ComputeLatency_ms", "pusch_decode_compute", "ms", "air_interface/csv/ul_pusch_trials.csv", note); ...
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.PDCCH, "ComputeLatency_ms", "pdcch_control_compute", "ms", "air_interface/csv/pdcch_trials.csv", note); ...
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.PBCH, "ComputeLatency_ms", "pbch_initial_access_compute", "ms", "air_interface/csv/pbch_trials.csv", note); ...
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.CellSearch, "ComputeLatency_ms", "cell_search_compute", "ms", "control/csv/cell_search_trials.csv", note)];
end

function T = localMemoryMetricRows(cat, metric, ctx, mode)
T = localEmptyMetricTable();
[~, tableBytes] = localPopulatedTableBytes(ctx.Tables, "tables");
tableMB = double(tableBytes) ./ (1024 ^ 2);
processMB = localProcessMemorySnapshotMB();
note = "Memory reporting is exported as an honest exporter-time resident-memory view over actual loaded LLS artifacts. Full in-run peak profiling is not instrumented in the current waveform path.";
switch string(mode)
    case "peak"
        if isfinite(processMB)
            T = [T; localMetricTableRow(cat, metric, "exporter", "process_snapshot_mb", "available", processMB, "", "MB", "meta/runtime_summary.json", note)]; %#ok<AGROW>
        end
        if ~isempty(tableMB)
            T = [T; ... %#ok<AGROW>
                localMetricTableRow(cat, metric, "loaded_tables", "max_resident_table_mb", "available", max(tableMB), "", "MB", "reports/csv/lls_output_metric_rows.csv", note); ...
                localMetricTableRow(cat, metric, "loaded_tables", "total_resident_tables_mb", "available", sum(tableMB, "omitnan"), "", "MB", "reports/csv/lls_output_metric_rows.csv", note)];
        end
    otherwise
        if ~isempty(tableMB)
            T = [T; ... %#ok<AGROW>
                localMetricTableRow(cat, metric, "loaded_tables", "mean_resident_table_mb", "available", mean(tableMB, "omitnan"), "", "MB", "reports/csv/lls_output_metric_rows.csv", note); ...
                localMetricTableRow(cat, metric, "loaded_tables", "median_resident_table_mb", "available", median(tableMB, "omitnan"), "", "MB", "reports/csv/lls_output_metric_rows.csv", note)];
        end
        if isfinite(processMB)
            T = [T; localMetricTableRow(cat, metric, "exporter", "process_snapshot_mb", "available", processMB, "", "MB", "meta/runtime_summary.json", note)]; %#ok<AGROW>
        end
end
end

function T = localModelInvocationRows(cat, metric, ctx)
T = localEmptyMetricTable();
aiEnabled = localAIEnabled(ctx);
count = localAIBenchmarkInvocationCount(ctx.Tables.AIBenchmarks);
src = "reports/csv/ai_benchmark_metadata.csv";
note = "Model invocation count is emitted from actual AI benchmark rows when present, otherwise from the resolved AI configuration for this run.";
if ~isfinite(count)
    if aiEnabled
        count = max(1, round(localConfigNumber(ctx, ["ai_ml.benchmark_observations"], 1)));
        src = "meta/scenario_config_resolved.json";
        note = note + " No dedicated AI benchmark artifact was emitted, so the configured benchmark-observation count is exported.";
    else
        count = 0;
        src = "meta/scenario_config_resolved.json";
        note = note + " AI/ML is disabled in this scenario, so the effective model invocation count is zero.";
    end
end
T = [T; localMetricTableRow(cat, metric, "ai_ml", "count", "available", double(count), "", "count", src, note)]; %#ok<AGROW>
elapsedSeconds = localRuntimeElapsedSeconds(ctx);
if isfinite(elapsedSeconds) && elapsedSeconds > 0
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "effective_rate_hz", "derived", double(count) / elapsedSeconds, "", "invocations_per_s", src, note)]; %#ok<AGROW>
end
end

function T = localOpsEstimateRows(cat, metric, ctx)
T = localEmptyMetricTable();
costs = localComplexityCostComponents(ctx);
note = "FLOPs / MACs estimates are exported from actual decoder and detector complexity counters plus FFT/channel-estimation/equalization estimates derived from observed RE counts and the resolved FFT/grid configuration.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "signal_processing", "fft_ops", "available", costs.FFTOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "signal_processing", "channel_estimation_ops", "available", costs.CEOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "signal_processing", "equalizer_ops", "available", costs.EqualizerOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "signal_processing", "detector_ops", "available", costs.DetectorOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "signal_processing", "decoder_ops", "available", costs.DecoderOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "signal_processing", "total_estimated_ops", "available", costs.TotalOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note)];
end

function T = localInferenceLatencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Inference latency is promoted only when the active AI path emits measured runtime latency telemetry. Configured latency budgets remain config_only and do not count as measured AI execution evidence.";
benchVal = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredInferenceLatency_us","ObservedInferenceLatency_us","RuntimeMeasuredInferenceLatency_us","InferenceLatency_us"]);
metaVal = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredInferenceLatency_us","ObservedInferenceLatency_us","RuntimeMeasuredInferenceLatency_us","InferenceLatency_us","InferenceLatency"]);
latencyVal = benchVal;
latencySrc = "reports/csv/ai_channel_estimation_benchmark.csv";
if ~isfinite(double(latencyVal))
    latencyVal = metaVal;
    latencySrc = "reports/csv/ai_benchmark_metadata.csv";
end
if isfinite(double(latencyVal))
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "reported_us", "available", double(latencyVal), "", "us", latencySrc, note)]; %#ok<AGROW>
    return;
end
latBudget = localConfigNumber(ctx, ["ai_ml.latency_budget_us", "ai_ml.runtime_budget_us"], 0);
aiAvail = localAIConfigAvailability(ctx);
T = [T; localMetricTableRow(cat, metric, "ai_ml", "configured_budget_us", aiAvail, latBudget, "", "us", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
if ~localAIEnabled(ctx)
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "effective_us", aiAvail, 0, "", "us", "meta/scenario_config_resolved.json", note + " AI/ML is disabled in this scenario, so effective inference latency is zero.")]; %#ok<AGROW>
end
end

function T = localDecodeLatencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Decode latency is exported from ComputeLatency_ms wall-clock decoder runtime. Radio/procedure delay stays in separate explicit metrics.";
T = [T; ... %#ok<AGROW>
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.DL, "ComputeLatency_ms", "DL_compute", "ms", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localCustomNumericSummaryRows(cat, metric, ctx.Tables.UL, "ComputeLatency_ms", "UL_compute", "ms", "air_interface/csv/ul_pusch_trials.csv", note)];
end

function T = localSignalProcessingCostRows(cat, metric, ctx)
T = localEmptyMetricTable();
costs = localComplexityCostComponents(ctx);
note = "Signal-processing cost rows are exported from observed trial complexity counters plus FFT/channel-estimation/equalizer estimates derived from actual grid occupancy.";
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "fft", "estimated_ops", "available", costs.FFTOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "channel_estimation", "estimated_ops", "available", costs.CEOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "equalizer", "estimated_ops", "available", costs.EqualizerOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note); ...
    localMetricTableRow(cat, metric, "detector", "estimated_ops", "available", costs.DetectorOps, "", "estimated_ops", "air_interface/csv/dl_pdsch_trials.csv", note)];
end

function T = localFeatureComplexityBreakdownRows(cat, metric, ctx)
T = localEmptyMetricTable();
costs = localComplexityCostComponents(ctx);
featureNames = ["waveform_fft","channel_estimation","equalization","detection","decoding","control","beam_management","harq","ai_ml"];
featureVals = [costs.FFTOps, costs.CEOps, costs.EqualizerOps, costs.DetectorOps, costs.DecoderOps, costs.ControlOps, costs.BeamOps, costs.HARQOps, costs.AIOps];
total = sum(featureVals, "omitnan");
note = "Per-feature complexity breakdown is emitted from actual waveform counters and scenario-aware AI configuration. Fractions are normalized by the total estimated complexity of the current run.";
for i = 1:numel(featureNames)
    T = [T; localMetricTableRow(cat, metric, featureNames(i), "estimated_ops", "available", featureVals(i), "", "estimated_ops", "reports/csv/lls_output_metric_rows.csv", note)]; %#ok<AGROW>
    frac = 0;
    if isfinite(total) && total > 0
        frac = featureVals(i) / total;
    end
    T = [T; localMetricTableRow(cat, metric, featureNames(i), "fraction_of_total", "available", frac, "", "fraction", "reports/csv/lls_output_metric_rows.csv", note)]; %#ok<AGROW>
end
end

function T = localCustomNumericSummaryRows(cat, metric, trialT, varName, entity, unit, source, notes)
T = localEmptyMetricTable();
if ~(istable(trialT) && ~isempty(trialT) && ismember(varName, string(trialT.Properties.VariableNames)))
    return;
end
x = localFiniteColumn(trialT, varName);
if isempty(x)
    return;
end
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, entity, "mean", "available", mean(x, "omitnan"), "", unit, source, notes); ...
    localMetricTableRow(cat, metric, entity, "p95", "available", prctile(x, 95), "", unit, source, notes); ...
    localMetricTableRow(cat, metric, entity, "max", "available", max(x), "", unit, source, notes)];
end

function costs = localComplexityCostComponents(ctx)
costs = struct("FFTOps", 0, "CEOps", 0, "EqualizerOps", 0, "DetectorOps", 0, ...
    "DecoderOps", 0, "ControlOps", 0, "BeamOps", 0, "HARQOps", 0, "AIOps", 0, "TotalOps", 0);

detectorDL = localFiniteColumn(ctx.Tables.DL, "DetectorComplexityUnits_Modulation");
detectorUL = localFiniteColumn(ctx.Tables.UL, "DetectorComplexityUnits_Modulation");
decoderDL = localFiniteColumn(ctx.Tables.DL, "DecoderComplexityUnits");
decoderUL = localFiniteColumn(ctx.Tables.UL, "DecoderComplexityUnits");
dataRE = [localFiniteColumn(ctx.Tables.DL, "DataRECount"); localFiniteColumn(ctx.Tables.UL, "DataRECount")];
dmrsRE = [localFiniteColumn(ctx.Tables.DL, "DMRSRECount"); localFiniteColumn(ctx.Tables.UL, "DMRSRECount")];
ptrsRE = [localFiniteColumn(ctx.Tables.DL, "PTRSRECount"); localFiniteColumn(ctx.Tables.UL, "PTRSRECount")];
numRx = [localFiniteColumn(ctx.Tables.DL, "NumRxAntennas"); localFiniteColumn(ctx.Tables.UL, "NumRxAntennas")];
numPorts = [localFiniteColumn(ctx.Tables.DL, "NumTxPorts"); localFiniteColumn(ctx.Tables.UL, "NumTxPorts")];

costs.DetectorOps = sum(detectorDL, "omitnan") + sum(detectorUL, "omitnan");
costs.DecoderOps = sum(decoderDL, "omitnan") + sum(decoderUL, "omitnan");

nfft = max(localConfigNumber(ctx, ["global_radio_scope.fft_size", "waveform.fft_size"], 1024), 2);
nrb = max(localConfigNumber(ctx, ["resource_grid.num_rbs", "frequency.n_size_grid"], 1), 1);
activeSubcarriers = max(12 * nrb, 1);
rxFactor = max(1, round(localFiniteMeanOrDefault(numRx, localConfigNumber(ctx, ["antenna_and_array.ue_num_antenna_elements", "mimo.n_rx_ant"], 1))));
portFactor = max(1, round(localFiniteMeanOrDefault(numPorts, localConfigNumber(ctx, ["antenna_and_array.bs_num_txrus", "mimo.n_tx_ant"], 1))));
totalREPerAntenna = (sum(dataRE, "omitnan") + sum(dmrsRE, "omitnan") + sum(ptrsRE, "omitnan")) / max(rxFactor, 1);
observedSymbols = totalREPerAntenna / activeSubcarriers;

costs.FFTOps = observedSymbols * rxFactor * nfft * log2(nfft);
costs.CEOps = (sum(dmrsRE, "omitnan") + sum(ptrsRE, "omitnan")) / max(rxFactor, 1) * portFactor;
costs.EqualizerOps = sum(dataRE, "omitnan") / max(rxFactor, 1) * rxFactor * portFactor;

blindDecodeCount = localFiniteColumn(ctx.Tables.PDCCH, "BlindDecodeCount");
dciSizeBits = localFiniteColumn(ctx.Tables.PDCCH, "DCISize_bits");
aggLevel = localFiniteColumn(ctx.Tables.PDCCH, "AggregationLevel");
if ~isempty(blindDecodeCount)
    if isempty(dciSizeBits)
        dciSizeBits = 64 * ones(size(blindDecodeCount));
    end
    if isempty(aggLevel)
        aggLevel = ones(size(blindDecodeCount));
    end
    n = min([numel(blindDecodeCount), numel(dciSizeBits), numel(aggLevel)]);
    costs.ControlOps = sum(blindDecodeCount(1:n) .* max(dciSizeBits(1:n), 1) .* max(aggLevel(1:n), 1), "omitnan");
end

beamCandidates = localFiniteColumn(ctx.Tables.BeamManagement, "BeamCandidateCount");
if isempty(beamCandidates)
    beamCandidates = localFiniteColumn(ctx.Tables.BeamScoreTrace, "BeamCandidateCount");
end
if ~isempty(beamCandidates)
    costs.BeamOps = sum(max(beamCandidates, 1), "omitnan");
else
    costs.BeamOps = double(height(ctx.Tables.BeamScoreTrace));
end

retxCounts = localFiniteColumn(ctx.Tables.HARQPackets, "RetransmissionCount");
tbBits = localFiniteColumn(ctx.Tables.HARQPackets, "TBSize_bits");
if isempty(tbBits)
    tbBits = ones(size(retxCounts));
end
if ~isempty(retxCounts)
    n = min(numel(retxCounts), numel(tbBits));
    costs.HARQOps = sum((retxCounts(1:n) + 1) .* max(tbBits(1:n), 1), "omitnan");
end

if localAIEnabled(ctx)
    costs.AIOps = max(localConfigNumber(ctx, ["ai_ml.flops_budget"], 0), 0);
else
    costs.AIOps = 0;
end

costs.TotalOps = costs.FFTOps + costs.CEOps + costs.EqualizerOps + costs.DetectorOps + ...
    costs.DecoderOps + costs.ControlOps + costs.BeamOps + costs.HARQOps + costs.AIOps;
end

function T = localAIModelParameterRows(cat, metric, ctx)
T = localEmptyMetricTable();
value = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredParameterCount","ObservedParameterCount","RuntimeModelParameterCount","LoadedParameterCount"]);
src = "reports/csv/ai_channel_estimation_benchmark.csv";
note = "Model parameter count is promoted only when the runtime AI path emits model-load telemetry. Descriptor-side parameter counts remain config_only because they are not measured inference metadata.";
avail = "available";
if ~(isnumeric(value) && isfinite(double(value)))
    value = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredParameterCount","ObservedParameterCount","RuntimeModelParameterCount","LoadedParameterCount"]);
    src = "reports/csv/ai_benchmark_metadata.csv";
end
if ~(isnumeric(value) && isfinite(double(value)))
    value = localAIMetadataValue(ctx.Tables.AIMetadata, ["ParameterCount","ModelParameters"]);
    src = "reports/csv/ai_benchmark_metadata.csv";
    avail = localAIConfigAvailability(ctx);
end
if ~(isnumeric(value) && isfinite(double(value)))
    value = localConfigNumber(ctx, ["ai_ml.parameter_count_budget"], 0);
    src = "meta/scenario_config_resolved.json";
    avail = localAIConfigAvailability(ctx);
end
T = [T; localMetricTableRow(cat, metric, "ai_ml", "parameter_count", avail, double(value), "", "parameters", src, note)]; %#ok<AGROW>
end

function T = localAIFLOPsRows(cat, metric, ctx)
T = localEmptyMetricTable();
value = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredFLOPs","ObservedFLOPs","RuntimeModelFLOPs","RuntimeMeasuredFLOPs"]);
src = "reports/csv/ai_channel_estimation_benchmark.csv";
note = "AI FLOPs are promoted only when the runtime AI path emits measured execution-cost metadata. Configured FLOPs budgets remain config_only.";
avail = "available";
if ~(isnumeric(value) && isfinite(double(value)))
    value = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredFLOPs","ObservedFLOPs","RuntimeModelFLOPs","RuntimeMeasuredFLOPs"]);
    src = "reports/csv/ai_benchmark_metadata.csv";
end
if ~(isnumeric(value) && isfinite(double(value)))
    value = localAIMetadataValue(ctx.Tables.AIMetadata, ["FLOPs","FLOPsBudget"]);
    src = "reports/csv/ai_benchmark_metadata.csv";
    avail = localAIConfigAvailability(ctx);
end
if ~(isnumeric(value) && isfinite(double(value)))
    value = localConfigNumber(ctx, ["ai_ml.flops_budget"], 0);
    src = "meta/scenario_config_resolved.json";
    avail = localAIConfigAvailability(ctx);
end
T = [T; localMetricTableRow(cat, metric, "ai_ml", "flops", avail, double(value), "", "flops", src, note)]; %#ok<AGROW>
end

function T = localAIMemoryFootprintRows(cat, metric, ctx)
T = localEmptyMetricTable();
value = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredMemoryFootprint","ObservedMemoryFootprint","RuntimePeakMemoryBytes","RuntimeMemoryBytes"]);
src = "reports/csv/ai_channel_estimation_benchmark.csv";
note = "AI memory footprint is promoted only when the runtime AI path emits measured memory telemetry. Configured memory budgets remain config_only.";
avail = "available";
if ~(isnumeric(value) && isfinite(double(value)))
    value = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredMemoryFootprint","ObservedMemoryFootprint","RuntimePeakMemoryBytes","RuntimeMemoryBytes"]);
    src = "reports/csv/ai_benchmark_metadata.csv";
end
if ~(isnumeric(value) && isfinite(double(value)))
    value = localAIMetadataValue(ctx.Tables.AIMetadata, ["MemoryFootprint","MemoryBudget"]);
    src = "reports/csv/ai_benchmark_metadata.csv";
    avail = localAIConfigAvailability(ctx);
end
if ~(isnumeric(value) && isfinite(double(value)))
    value = localConfigNumber(ctx, ["ai_ml.memory_budget"], 0);
    src = "meta/scenario_config_resolved.json";
    avail = localAIConfigAvailability(ctx);
end
T = [T; localMetricTableRow(cat, metric, "ai_ml", "memory_budget", avail, double(value), "", "configured_units", src, note)]; %#ok<AGROW>
end

function T = localAIOperationFrequencyRows(cat, metric, ctx)
T = localEmptyMetricTable();
src = "meta/scenario_config_resolved.json";
note = "AI operation frequency is exported from actual benchmark metadata when available, otherwise from the resolved inference-frequency policy and effective invocation rate for the run.";
aiAvail = localAIConfigAvailability(ctx);
metaVal = localAIMetadataValue(ctx.Tables.AIMetadata, ["OperationFrequency"]);
if ~(isnumeric(metaVal) && isfinite(double(metaVal)))
    txt = localConfigTextValue(metaVal);
    if strlength(txt) > 0 && txt ~= "NaN"
        T = [T; localMetricTableRow(cat, metric, "ai_ml", "reported_mode", "available", NaN, txt, "", "reports/csv/ai_benchmark_metadata.csv", note)]; %#ok<AGROW>
    end
end
if isempty(T)
    freqMode = localConfigString(ctx, ["ai_ml.inference_frequency"], "slot");
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "configured_mode", aiAvail, NaN, freqMode, "", src, note)]; %#ok<AGROW>
end
count = localAIBenchmarkInvocationCount(ctx.Tables.AIBenchmarks);
if ~isfinite(count)
    if localAIEnabled(ctx)
        count = max(1, round(localConfigNumber(ctx, ["ai_ml.benchmark_observations"], 1)));
    else
        count = 0;
    end
end
elapsedSeconds = localRuntimeElapsedSeconds(ctx);
if isfinite(elapsedSeconds) && elapsedSeconds > 0
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "effective_rate_hz", aiAvail, double(count) / elapsedSeconds, "", "invocations_per_s", src, note)]; %#ok<AGROW>
end
end

function T = localAIInferenceLatencyRows(cat, metric, ctx)
T = localInferenceLatencyRows(cat, metric, ctx);
end

function T = localAIGeneralizationRows(cat, metric, ctx, fieldName, entity)
T = localEmptyMetricTable();
path = "ai_ml." + string(fieldName);
enabled = localConfigFlag(ctx, path + ".enabled", false);
cfgText = localConfigTextValue(localConfigValue(ctx, path, struct("enabled", enabled)));
note = "AI generalization coverage is exported from the resolved config for the current scenario.";
aiAvail = localAIConfigAvailability(ctx);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, entity, "enabled_flag", aiAvail, double(enabled), cfgText, "flag", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, entity, "configured_scope", aiAvail, NaN, cfgText, "", "meta/scenario_config_resolved.json", note)];
end

function T = localAIGeneralizationImpairmentRows(cat, metric, ctx)
T = localEmptyMetricTable();
mode = localConfigString(ctx, ["ai_ml.robustness_to_impairments"], "baseline");
enabled = ~any(strcmpi(strtrim(mode), ["baseline","none","disabled","off"]));
note = "AI impairment generalization coverage is exported from the resolved robustness-to-impairments setting for the scenario.";
aiAvail = localAIConfigAvailability(ctx);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "impairments", "enabled_flag", aiAvail, double(enabled), mode, "flag", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, "impairments", "configured_mode", aiAvail, NaN, mode, "", "meta/scenario_config_resolved.json", note)];
end

function T = localAITrainTestMismatchRows(cat, metric, ctx)
T = localEmptyMetricTable();
trainScope = localConfigString(ctx, ["ai_ml.training_dataset_scope"], "lab_default");
testScope = localConfigString(ctx, ["ai_ml.test_dataset_scope"], "lab_default");
mismatch = double(trainScope ~= testScope);
note = "Train/test mismatch loss is exported as a scenario-level dataset-scope mismatch proxy when no dedicated AI benchmark delta table is present.";
aiAvail = localAIConfigAvailability(ctx);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "ai_ml", "scope_mismatch_flag", aiAvail, mismatch, trainScope + "->" + testScope, "flag", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, "ai_ml", "training_scope", aiAvail, NaN, trainScope, "", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, "ai_ml", "test_scope", aiAvail, NaN, testScope, "", "meta/scenario_config_resolved.json", note)];
end

function T = localAIConfidenceRows(cat, metric, ctx)
T = localEmptyMetricTable();
benchVal = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredConfidenceScore","ObservedConfidenceScore","RuntimeMeasuredConfidenceScore","ConfidenceScore"]);
metaVal = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredConfidenceScore","ObservedConfidenceScore","RuntimeMeasuredConfidenceScore","ConfidenceScore","ConfidenceMetric"]);
note = "AI confidence statistics are promoted only when runtime confidence telemetry is emitted by the active AI path. Static descriptor confidence settings remain config_only.";
if isnumeric(benchVal) && isfinite(double(benchVal))
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "reported_confidence", "available", double(benchVal), "", "score", "reports/csv/ai_channel_estimation_benchmark.csv", note)]; %#ok<AGROW>
elseif isnumeric(metaVal) && isfinite(double(metaVal))
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "reported_confidence", "available", double(metaVal), "", "score", "reports/csv/ai_benchmark_metadata.csv", note)]; %#ok<AGROW>
elseif ~isnumeric(metaVal)
    txt = localConfigTextValue(metaVal);
    if strlength(txt) > 0 && txt ~= "[]"
        T = [T; localMetricTableRow(cat, metric, "ai_ml", "reported_metric", localAIConfigAvailability(ctx), NaN, txt, "", "reports/csv/ai_benchmark_metadata.csv", note)]; %#ok<AGROW>
    end
end
if isempty(T)
    metricName = localConfigString(ctx, ["ai_ml.confidence_metric"], "none");
    enabled = ~any(strcmpi(strtrim(metricName), ["none","disabled","off"]));
    aiAvail = localAIConfigAvailability(ctx);
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "ai_ml", "configured_enabled_flag", aiAvail, double(enabled), metricName, "flag", "meta/scenario_config_resolved.json", note); ...
        localMetricTableRow(cat, metric, "ai_ml", "configured_metric", aiAvail, NaN, metricName, "", "meta/scenario_config_resolved.json", note)];
end
end

function T = localAIFallbackRows(cat, metric, ctx)
T = localEmptyMetricTable();
benchVal = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredFallbackRate","ObservedFallbackRate","RuntimeFallbackRate","FallbackRate"]);
metaVal = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredFallbackRate","ObservedFallbackRate","RuntimeFallbackRate","FallbackRate"]);
note = "Fallback rate is promoted only when the active AI path emits measured fallback telemetry. Fallback configuration flags remain config_only.";
if isnumeric(benchVal) && isfinite(double(benchVal))
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "observed_rate", "available", double(benchVal), "", "fraction", "reports/csv/ai_channel_estimation_benchmark.csv", note)]; %#ok<AGROW>
    return;
end
if isnumeric(metaVal) && isfinite(double(metaVal))
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "observed_rate", "available", double(metaVal), "", "fraction", "reports/csv/ai_benchmark_metadata.csv", note)]; %#ok<AGROW>
    return;
end
enabled = localConfigFlag(ctx, ["ai_ml.fallback_enabled"], false);
if ~localAIEnabled(ctx)
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "observed_rate", localAIConfigAvailability(ctx), 0, "", "fraction", "meta/scenario_config_resolved.json", note + " AI/ML is disabled in this scenario, so fallback rate is zero.")]; %#ok<AGROW>
else
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "ai_ml", "configured_enabled_flag", localAIConfigAvailability(ctx), double(enabled), "", "flag", "meta/scenario_config_resolved.json", note); ...
        localMetricTableRow(cat, metric, "ai_ml", "configured_mode", localAIConfigAvailability(ctx), NaN, string(enabled), "", "meta/scenario_config_resolved.json", note)];
end
end

function T = localAIQuantizationRobustnessRows(cat, metric, ctx)
T = localEmptyMetricTable();
quantMode = localConfigString(ctx, ["ai_ml.quantization", "ai_ml.quantization_mode"], "fp32");
isQuantized = ~any(strcmpi(strtrim(quantMode), ["fp32","none","disabled","off","full_precision"]));
note = "Quantization robustness is exported from the resolved AI quantization mode for the executed scenario.";
aiAvail = localAIConfigAvailability(ctx);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "ai_ml", "quantized_flag", aiAvail, double(isQuantized), quantMode, "flag", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, "ai_ml", "configured_mode", aiAvail, NaN, quantMode, "", "meta/scenario_config_resolved.json", note)];
end

function T = localAIRobustnessImpairmentRows(cat, metric, ctx)
T = localEmptyMetricTable();
mode = localConfigString(ctx, ["ai_ml.robustness_to_impairments"], "baseline");
enabledCount = 0;
enabledCount = enabledCount + double(localConfigNonBaseline(ctx, ["power_and_rf_frontend.iq_imbalance", "impairments.iq_imbalance"]));
enabledCount = enabledCount + double(localConfigNonBaseline(ctx, ["power_and_rf_frontend.dc_offset", "impairments.dc_offset"]));
enabledCount = enabledCount + double(localConfigNonBaseline(ctx, ["power_and_rf_frontend.lo_phase_noise_model", "impairments.phase_noise"]));
enabledCount = enabledCount + double(localConfigNonBaseline(ctx, ["power_and_rf_frontend.cfo_model", "impairments.cfo"]) && ...
    ~strcmpi(strtrim(localConfigString(ctx, ["power_and_rf_frontend.cfo_model", "impairments.cfo"], "none")), "constant_zero"));
enabledCount = enabledCount + double(localConfigNonBaseline(ctx, ["power_and_rf_frontend.drift_rate_model", "impairments.drift_rate"]));
enabledCount = enabledCount + double(localConfigNonBaseline(ctx, ["power_and_rf_frontend.pa_nonlinearity_model", "impairments.pa_nonlinearity"]));
note = "RF-impairment robustness is exported from the resolved AI robustness mode plus the number of active RF impairment families configured in the scenario.";
aiAvail = localAIConfigAvailability(ctx);
T = [T; ... %#ok<AGROW>
    localMetricTableRow(cat, metric, "ai_ml", "active_impairment_family_count", aiAvail, enabledCount, mode, "count", "meta/scenario_config_resolved.json", note); ...
    localMetricTableRow(cat, metric, "ai_ml", "configured_mode", aiAvail, NaN, mode, "", "meta/scenario_config_resolved.json", note)];
end

function T = localAIPerformanceComplexityFrontierRows(cat, metric, ctx)
T = localEmptyMetricTable();
note = "Performance-complexity frontier is exported from actual AI baseline delta and FLOPs when available, otherwise from the resolved AI enable state. Disabled scenarios export zero frontier gain.";
delta = localAIMetadataValue(ctx.Tables.AIMetadata, ["BaselineDelta"]);
flops = localAIMetadataValue(ctx.Tables.AIMetadata, ["FLOPs","FLOPsBudget"]);
if isnumeric(delta) && isfinite(double(delta)) && isnumeric(flops) && isfinite(double(flops)) && double(flops) > 0
    frontier = double(delta) / double(flops);
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "delta_per_flop", "available", frontier, "", "delta_per_flop", "reports/csv/ai_benchmark_metadata.csv", note)]; %#ok<AGROW>
    return;
end
if localAIEnabled(ctx)
    flopsBudget = max(localConfigNumber(ctx, ["ai_ml.flops_budget"], 1), 1);
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "ai_ml", "delta_per_flop", "available", 0, "", "delta_per_flop", "meta/scenario_config_resolved.json", note + " No measured AI-vs-baseline delta table was emitted in this run."); ...
        localMetricTableRow(cat, metric, "ai_ml", "configured_flops_budget", "available", flopsBudget, "", "flops", "meta/scenario_config_resolved.json", note)];
else
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "delta_per_flop", localAIConfigAvailability(ctx), 0, "", "delta_per_flop", "meta/scenario_config_resolved.json", note)]; %#ok<AGROW>
end
end

function T = localAIBaselineDeltaRows(cat, metric, ctx)
T = localEmptyMetricTable();
delta = localAIMetadataValue(ctx.Tables.AIMetadata, ["BaselineDelta"]);
note = "Baseline delta is exported from actual AI benchmark metadata when available, otherwise from the resolved baseline pairing and scenario enable state.";
if isnumeric(delta) && isfinite(double(delta))
    T = [T; localMetricTableRow(cat, metric, "ai_ml", "reported_delta", "available", double(delta), "", "delta", "reports/csv/ai_benchmark_metadata.csv", note)]; %#ok<AGROW>
    return;
end
baselineName = localConfigString(ctx, ["ai_ml.baseline_pairing", "meta.baseline_reference_name"], "non_ai_baseline");
if localAIEnabled(ctx)
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "ai_ml", "configured_baseline", "available", NaN, baselineName, "", "meta/scenario_config_resolved.json", note); ...
        localMetricTableRow(cat, metric, "ai_ml", "reported_delta", "available", 0, "", "delta", "meta/scenario_config_resolved.json", note + " No measured AI-vs-baseline delta table was emitted in this run.")];
else
    T = [T; ... %#ok<AGROW>
        localMetricTableRow(cat, metric, "ai_ml", "configured_baseline", localAIConfigAvailability(ctx), NaN, baselineName, "", "meta/scenario_config_resolved.json", note); ...
        localMetricTableRow(cat, metric, "ai_ml", "reported_delta", localAIConfigAvailability(ctx), 0, "", "delta", "meta/scenario_config_resolved.json", note + " AI/ML is disabled in this scenario, so baseline delta is zero by configuration.")];
end
end

function value = localAIMetadataValue(metaT, fieldNames)
value = NaN;
if ~(istable(metaT) && ~isempty(metaT))
    return;
end
fieldNames = string(fieldNames);
vars = string(metaT.Properties.VariableNames);
for i = 1:numel(fieldNames)
    idx = find(vars == fieldNames(i), 1, "first");
    if isempty(idx)
        continue;
    end
    candidate = metaT.(vars(idx));
    if iscell(candidate)
        candidate = candidate{1};
    elseif numel(candidate) >= 1
        candidate = candidate(1);
    end
    value = candidate;
    return;
end
end

function value = localAIBenchmarkNumericValue(S, fieldNames)
value = NaN;
if ~(isstruct(S) && ~isempty(fieldnames(S)))
    return;
end
fieldNames = string(fieldNames);
names = fieldnames(S);
for i = 1:numel(fieldNames)
    for j = 1:numel(names)
        T = S.(names{j});
        if ~(istable(T) && ~isempty(T))
            continue;
        end
        vars = string(T.Properties.VariableNames);
        idx = find(vars == fieldNames(i), 1, "first");
        if isempty(idx)
            continue;
        end
        candidate = T.(vars(idx));
        if ~(isnumeric(candidate) || islogical(candidate))
            continue;
        end
        candidate = double(candidate(:));
        candidate = candidate(isfinite(candidate));
        if isempty(candidate)
            continue;
        end
        value = mean(candidate, "omitnan");
        return;
    end
end
end

function txt = localConfigTextValue(value)
try
    if isstring(value) || ischar(value)
        txt = strtrim(string(value));
    elseif isnumeric(value) || islogical(value)
        if isscalar(value)
            txt = string(value);
        else
            txt = string(jsonencode(value));
        end
    elseif isstruct(value) || iscell(value)
        txt = string(jsonencode(value));
    else
        txt = string(value);
    end
catch
    txt = string(value);
end
if strlength(txt) == 0
    txt = "";
end
end

function tf = localAIEnabled(ctx)
tf = localConfigFlag(ctx, ["ai_ml.enabled"], false);
if tf
    return;
end
mode = lower(strtrim(localConfigString(ctx, ["ai_ml.mode"], "disabled")));
modelFamily = lower(strtrim(localConfigString(ctx, ["ai_ml.model_family"], "none")));
modelName = lower(strtrim(localConfigString(ctx, ["ai_ml.model_name"], "none")));
tf = ~any(strcmp(mode, ["disabled","none","off","false",""])) && ...
    (~strcmp(modelFamily, "none") || ~strcmp(modelName, "none"));
end

function [names, bytes] = localPopulatedTableBytes(value, prefix)
names = strings(0, 1);
bytes = zeros(0, 1);
if nargin < 2
    prefix = "";
end
if istable(value)
    if ~isempty(value)
        names = string(prefix);
        bytes = localValueBytes(value);
    end
    return;
end
if ~isstruct(value)
    return;
end
fields = fieldnames(value);
for i = 1:numel(fields)
    childPrefix = string(fields{i});
    if strlength(string(prefix)) > 0
        childPrefix = string(prefix) + "." + childPrefix;
    end
    [childNames, childBytes] = localPopulatedTableBytes(value.(fields{i}), childPrefix);
    if ~isempty(childNames)
        names = [names; childNames]; %#ok<AGROW>
        bytes = [bytes; childBytes]; %#ok<AGROW>
    end
end
end

function bytes = localValueBytes(value)
try
    if istable(value)
        bytes = 0;
        vars = string(value.Properties.VariableNames);
        for i = 1:numel(vars)
            col = value.(vars(i));
            try
                s = whos("col");
                bytes = bytes + double(s.bytes);
            catch
                bytes = bytes + double(numel(col)) * 8;
            end
        end
        return;
    end
    if isnumeric(value) || islogical(value)
        bytes = double(numel(value)) * 8;
    elseif isstring(value) || iscellstr(value)
        bytes = double(numel(string(value))) * 32;
    else
        s = whos("value");
        bytes = double(s.bytes);
    end
catch
    bytes = 0;
end
end

function mb = localProcessMemorySnapshotMB()
mb = NaN;
try
    [userView, ~] = memory();
    if isstruct(userView) && isfield(userView, "MemUsedMATLAB")
        mb = double(userView.MemUsedMATLAB) ./ (1024 ^ 2);
    end
catch
    mb = NaN;
end
end

function meanValue = localFiniteMeanOrDefault(x, defaultValue)
x = double(x);
x = x(isfinite(x));
if isempty(x)
    meanValue = double(defaultValue);
else
    meanValue = mean(x, "omitnan");
end
end

function n = localAIBenchmarkInvocationCount(S)
n = NaN;
if ~(isstruct(S) && ~isempty(fieldnames(S)))
    return;
end
names = fieldnames(S);
count = 0;
for i = 1:numel(names)
    T = S.(names{i});
    if istable(T)
        count = count + height(T);
    end
end
n = double(count);
end

function T = localBuildCoverageSummary(catalog, rows)
entryRows = repmat(struct("CategoryCode", "", "CategoryKey", "", "CategoryName", "", ...
    "MetricKey", "", "MetricName", "", "Availability", "", "CountsTowardCoverage", false, "CoveredRowCount", NaN, ...
    "ObservedRowCount", NaN, "DerivedRowCount", NaN, "ConfigOnlyRowCount", NaN, ...
    "DisabledRowCount", NaN, "PlaceholderRowCount", NaN, "NotSupportedRowCount", NaN, ...
    "NotAvailableRowCount", NaN, "NotExercisedRowCount", NaN, ...
    "SourceArtifacts", "", "Notes", ""), 0, 1);
for i = 1:numel(catalog.categories)
    cat = catalog.categories(i);
    metrics = cat.metrics;
    for j = 1:numel(metrics)
        metric = metrics(j);
        mask = rows.CategoryCode == string(cat.code) & rows.MetricKey == string(metric.key);
        Tm = rows(mask, :);
        avail = "not_available";
        countsTowardCoverage = false;
        source = "";
        notes = "";
        observedCount = 0;
        derivedCount = 0;
        configOnlyCount = 0;
        disabledCount = 0;
        placeholderCount = 0;
        notSupportedCount = 0;
        notAvailableCount = 0;
        notExercisedCount = 0;
        coveredRowCount = 0;
        if ~isempty(Tm)
            states = lower(strtrim(string(Tm.Availability)));
            observedCount = sum(states == "observed");
            derivedCount = sum(states == "derived");
            configOnlyCount = sum(states == "config_only");
            disabledCount = sum(states == "disabled");
            placeholderCount = sum(states == "placeholder");
            notSupportedCount = sum(states == "not_supported");
            notAvailableCount = sum(states == "not_available");
            notExercisedCount = sum(states == "not_exercised");
            coveredMask = localCoverageStateCountsTowardCoverage(states);
            coveredRowCount = sum(coveredMask);
            countsTowardCoverage = any(coveredMask);
            avail = localRollupAvailabilityState(states);
            source = strjoin(unique(string(Tm.SourceArtifact(strlength(string(Tm.SourceArtifact)) > 0))), "|");
            notes = strjoin(unique(string(Tm.Notes(strlength(string(Tm.Notes)) > 0))), " | ");
        end
        entryRows(end+1, 1) = struct( ... %#ok<AGROW>
            "CategoryCode", string(cat.code), ...
            "CategoryKey", string(cat.key), ...
            "CategoryName", string(cat.name), ...
            "MetricKey", string(metric.key), ...
            "MetricName", string(metric.label), ...
            "Availability", avail, ...
            "CountsTowardCoverage", logical(countsTowardCoverage), ...
            "CoveredRowCount", double(coveredRowCount), ...
            "ObservedRowCount", double(observedCount), ...
            "DerivedRowCount", double(derivedCount), ...
            "ConfigOnlyRowCount", double(configOnlyCount), ...
            "DisabledRowCount", double(disabledCount), ...
            "PlaceholderRowCount", double(placeholderCount), ...
            "NotSupportedRowCount", double(notSupportedCount), ...
            "NotAvailableRowCount", double(notAvailableCount), ...
            "NotExercisedRowCount", double(notExercisedCount), ...
            "SourceArtifacts", source, ...
            "Notes", notes);
    end
end
T = struct2table(entryRows);
end

function rows = localNormalizeMetricRows(rows, runFolder, ctx)
if ~(istable(rows) && ~isempty(rows))
    return;
end
if nargin < 3
    ctx = struct();
end
if ismember("SourceArtifact", string(rows.Properties.VariableNames))
    rows.SourceArtifact = localNormalizeMetricPathColumn(rows.SourceArtifact, runFolder);
end
if ismember("ValueText", string(rows.Properties.VariableNames))
    rows.ValueText = localNormalizeMetricPathColumn(rows.ValueText, runFolder);
end
if ismember("Availability", string(rows.Properties.VariableNames))
    states = lower(strtrim(string(rows.Availability)));
    if ~localShouldEmitPlaceholderArtifacts(ctx)
        states(states == "placeholder") = "not_available";
    end
    if ~localConfigFlag(ctx, ["output.emit_disabled_audit_artifacts"], true)
        states(states == "disabled") = "not_supported";
    end
    if ismember("SourceArtifact", string(rows.Properties.VariableNames))
        sources = strtrim(string(rows.SourceArtifact));
        for i = 1:height(rows)
            if ~(states(i) == "observed" || states(i) == "derived")
                continue;
            end
            sourceExists = false;
            if strlength(sources(i)) > 0 && ~ismissing(sources(i))
                candidate = fullfile(runFolder, char(replace(sources(i), "/", filesep)));
                sourceExists = exist(candidate, "file") == 2;
            end
            if sourceExists
                continue;
            end
            priorState = states(i);
            states(i) = "not_available";
            reason = "Runtime coverage suppressed: " + priorState + ...
                " metric source is missing from the finalized run tree (" + ...
                localMissingMetricSourceText(sources(i)) + ").";
            if ismember("Notes", string(rows.Properties.VariableNames))
                note = strtrim(string(rows.Notes(i)));
                if strlength(note) > 0
                    rows.Notes(i) = note + " " + reason;
                else
                    rows.Notes(i) = reason;
                end
            end
        end
    end
    rows.Availability = states;
    if ismember("CountsTowardCoverage", string(rows.Properties.VariableNames))
        rows.CountsTowardCoverage = localCoverageStateCountsTowardCoverage(states);
    end
end
end

function out = localMissingMetricSourceText(source)
source = strtrim(string(source));
if strlength(source) == 0 || ismissing(source)
    out = "source_not_declared";
else
    out = source;
end
end

function values = localNormalizeMetricPathColumn(values, runFolder)
values = string(values);
for i = 1:numel(values)
    values(i) = localRelativeToRunFolder(values(i), runFolder);
end
end

function plots = localExportReportPlots(ctx, coverageT)
plots = strings(0, 1);
if ~localCanRenderReportFigures(ctx)
    return;
end
sixgr.util.ensureFolder(ctx.Layout.ReportImageDir);
try
    measuredPlots = sixgr.analytics.generateMeasuredSINRPlots(ctx.RunFolder);
    plots = [plots; string(measuredPlots.Plots(:))]; %#ok<AGROW>
catch
end
if localConfigFlag(ctx, ["output.enable_measured_posteq_sinr_bins_diagnostic_plot", ...
        "output.enable_measured_sinr_bin_diagnostic_plots", ...
        "reporting.enable_measured_posteq_sinr_bins_diagnostic_plot"], false) || ...
        localHasMeasuredPostEqSINRDiagnosticEvidence(ctx)
    plots(end+1, 1) = localPlotMeasuredPostEqSINRBinsDiagnostic(ctx, ctx.Layout.ReportImageDir); %#ok<AGROW>
end
plots(end+1, 1) = localPlotTrialMetricRelationship(ctx, ctx.Layout.ReportImageDir, ctx.Tables.DL, ctx.Tables.UL, ...
    "PostEqSINR_dB", "BLER", "bler_vs_sinr.png", "BLER vs Post-Eq SINR", "Post-equalization SINR (dB)", "BLER", false, false); %#ok<AGROW>
plots(end+1, 1) = localPlotTrialMetricRelationship(ctx, ctx.Layout.ReportImageDir, ctx.Tables.DL, ctx.Tables.UL, ...
    "PostEqSINR_dB", "BER", "ber_vs_sinr.png", "BER vs Post-Eq SINR", "Post-equalization SINR (dB)", "BER", false, false); %#ok<AGROW>
plots(end+1, 1) = localPlotTrialMetricRelationship(ctx, ctx.Layout.ReportImageDir, ctx.Tables.DL, ctx.Tables.UL, ...
    "BLER", "BER", "ber_vs_bler.png", "BER vs BLER", "BLER", "BER", false, false); %#ok<AGROW>
plots(end+1, 1) = localPlotTrialMetricRelationship(ctx, ctx.Layout.ReportImageDir, ctx.Tables.DL, ctx.Tables.UL, ...
    "DerivedEcNo_dB", "BER", "ber_vs_ecno.png", "BER vs Derived Ec/No", "Derived Ec/No (dB)", "BER", false, false); %#ok<AGROW>
plots(end+1, 1) = localPlotTrialMetricRelationship(ctx, ctx.Layout.ReportImageDir, ctx.Tables.DL, ctx.Tables.UL, ...
    "DerivedEcNo_dB", "BLER", "bler_vs_ecno.png", "BLER vs Derived Ec/No", "Derived Ec/No (dB)", "BLER", false, false); %#ok<AGROW>
plots(end+1, 1) = localPlotControlPassRates(ctx.Layout.ReportImageDir, ctx); %#ok<AGROW>
plots(end+1, 1) = localPlotCoverageAvailability(ctx.Layout.ReportImageDir, coverageT, ctx); %#ok<AGROW>
plots = plots(strlength(plots) > 0);
end

function tf = localCanRenderReportFigures(ctx)
% The post-run contract materializer is the sole raster authority whenever
% enabled.  The report bundle must still persist every source CSV, but must
% not produce legacy MATLAB PNGs or unavailable/reason-card images that can
% be mistaken for runtime charts on a future run.
contractRasterAuthority = logical(ctx.ScenarioConfig.get( ...
    "output.artifact_contract_engine.enabled", false));
tf = usejava("jvm") && ~contractRasterAuthority;
end

function tf = localHasMeasuredPostEqSINRDiagnosticEvidence(ctx)
tf = localTableHasFiniteColumn(ctx.Tables.DL, ["PostEqSINR_dB","PostEqWidebandSINR_dB","MeasuredTrialSINR_dB"]) || ...
    localTableHasFiniteColumn(ctx.Tables.UL, ["PostEqSINR_dB","PostEqWidebandSINR_dB","MeasuredTrialSINR_dB"]);
end

function tf = localTableHasFiniteColumn(T, varNames)
tf = false;
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
varNames = string(varNames);
for i = 1:numel(varNames)
    if ~ismember(varNames(i), vars)
        continue;
    end
    values = localCoerceNumericVector(T.(varNames(i)));
    if any(isfinite(values))
        tf = true;
        return;
    end
end
end

function pathOut = localPlotControlledSNRSweep(ctx, imgDir, fileName, plotTitle, yLabel, metricKind)
normalPath = string(fullfile(imgDir, fileName));
unavailablePath = sixgr.visual.unavailableArtifactPath(normalPath);
pathOut = unavailablePath;
[ok, reason] = localControlledSNRSweepStatus(ctx.Tables.Sweep, metricKind);
if ~ok
    localExportPlaceholderFigure(normalPath, plotTitle, ...
        "Controlled SNR sweep unavailable: " + reason + ".");
    return;
end

sweepT = ctx.Tables.Sweep;
chartT = localControlledSNRSweepChartTable(sweepT, metricKind);
status = sixgr.visual.validatePlotData("relation", chartT.SNR_dB, chartT.MetricValue, ...
    "MinimumRows", 3, "MinimumUniqueX", 3, "MinimumUniqueY", 1);
if status.PlotRenderStatus ~= "rendered"
    localExportPlaceholderFigure(normalPath, plotTitle, ...
        "Controlled SNR sweep unavailable: " + string(status.PlotSuppressionReason) + ".");
    return;
end

sixgr.visual.writeChartSourceCsv(char(ctx.RunFolder), localReportChartCSVLogicalPath(fileName), chartT);
sixgr.util.ensureFolder(imgDir);
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
series = unique(string(chartT.SeriesLabel), "stable");
colorOrder = get(ax, "ColorOrder");
made = false;
for i = 1:numel(series)
    mask = string(chartT.SeriesLabel) == series(i);
    x = double(chartT.SNR_dB(mask));
    y = double(chartT.MetricValue(mask));
    finiteMask = isfinite(x) & isfinite(y);
    if ~any(finiteMask)
        continue;
    end
    seriesColor = colorOrder(1 + mod(i - 1, size(colorOrder, 1)), :);
    if strcmpi(string(metricKind), "bler") && all(ismember(["CILow","CIHigh"], string(chartT.Properties.VariableNames)))
        lo = double(chartT.CILow(mask));
        hi = double(chartT.CIHigh(mask));
        ciMask = finiteMask & isfinite(lo) & isfinite(hi);
        if any(ciMask)
            localPlotDiscreteSweepSeries(ax, x(ciMask), y(ciMask), seriesColor, char(series(i)));
            errorbar(ax, x(ciMask), y(ciMask), max(y(ciMask) - lo(ciMask), 0), max(hi(ciMask) - y(ciMask), 0), ...
                "LineStyle", "none", "LineWidth", 1.2, "CapSize", 4, "Marker", "none", ...
                "HandleVisibility", "off", "Color", seriesColor);
            made = true;
        end
        plainMask = finiteMask & ~ciMask;
        if any(plainMask)
            localPlotDiscreteSweepSeries(ax, x(plainMask), y(plainMask), seriesColor, char(series(i)));
            made = true;
        end
    else
        localPlotDiscreteSweepSeries(ax, x(finiteMask), y(finiteMask), seriesColor, char(series(i)));
        made = true;
    end
end
if ~made
    localExportPlaceholderFigure(normalPath, plotTitle, "Controlled SNR sweep unavailable: no finite plotted series.");
    return;
end
grid(ax, "on");
xlabel(ax, "Controlled SNR (dB)");
ylabel(ax, yLabel);
title(ax, plotTitle);
legend(ax, "Location", "best");
snr = double(chartT.SNR_dB);
snr = snr(isfinite(snr));
if ~isempty(snr)
    if min(snr) < max(snr)
        xlim(ax, [min(snr), max(snr)]);
    else
        xlim(ax, [min(snr) - 0.5, max(snr) + 0.5]);
    end
    xticks(ax, localSweepTickValues(min(snr), max(snr)));
end
pathOut = normalPath;
sixgr.util.exportFigureArtifact(fig, normalPath, "Resolution", 160);
end

function [ok, reason] = localControlledSNRSweepStatus(sweepT, metricKind)
ok = false;
reason = "";
if ~(istable(sweepT) && ~isempty(sweepT))
    reason = "air_interface/csv/lls_snr_sweep.csv is missing or empty";
    return;
end
vars = string(sweepT.Properties.VariableNames);
required = localControlledSNRSweepColumns();
missing = required(~ismember(required, vars));
if ~isempty(missing)
    reason = "missing required controlled-sweep columns: " + strjoin(missing, "|");
    return;
end
snr = localCoerceNumericVector(sweepT.snr_db);
if nnz(isfinite(snr)) < 3 || numel(unique(snr(isfinite(snr)))) < 3
    reason = "insufficient controlled SNR points";
    return;
end
metricKind = lower(string(metricKind));
if metricKind == "bler"
    y = localCoerceNumericVector(sweepT.bler);
elseif metricKind == "throughput"
    y = localCoerceNumericVector(sweepT.throughput_mbps);
else
    reason = "unknown controlled SNR metric";
    return;
end
if nnz(isfinite(snr) & isfinite(y)) < 3
    reason = "insufficient finite controlled-sweep metric rows";
    return;
end
nTB = localCoerceNumericVector(sweepT.n_tb);
if ~any(isfinite(nTB) & nTB > 0)
    reason = "no transport-block evidence in controlled sweep";
    return;
end
truthStatus = lower(strtrim(string(sweepT.truth_status)));
truthStatus = truthStatus(strlength(truthStatus) > 0 & truthStatus ~= "<missing>");
allowed = ["real_lls_evidence","runtime_measured","truth","controlled_snr_sweep_truth"];
if isempty(truthStatus) || any(~ismember(truthStatus, allowed))
    reason = "truth_status is absent or not controlled-sweep truth";
    return;
end
ok = true;
end

function cols = localControlledSNRSweepColumns()
cols = ["direction", "snr_db", "noise_variance", "n_tb", "n_crc_fail", "bler", "bler_ci_low", ...
    "bler_ci_high", "n_bits", "n_bit_errors", "ber", "throughput_mbps", "goodput_mbps", ...
    "mcs_index", "mcs_table", "cqi_table", "modulation_order", "code_rate", "tbs", ...
    "n_layers", "rv_sequence", "harq_enabled", "channel_model", "seed", "truth_status"];
end

function chartT = localControlledSNRSweepChartTable(sweepT, metricKind)
metricKind = lower(string(metricKind));
rows = repmat(struct("Direction", "", "SNR_dB", NaN, "MetricValue", NaN, "SeriesLabel", "", ...
    "SourceColumn", "", "CILow", NaN, "CIHigh", NaN, "TruthStatus", "", "SourceCSV", "air_interface/csv/lls_snr_sweep.csv"), 0, 1);
directions = unique(string(sweepT.direction), "stable");
for d = 1:numel(directions)
    direction = string(directions(d));
    dMask = string(sweepT.direction) == direction;
    if metricKind == "bler"
        y = localCoerceNumericVector(sweepT.bler);
        lo = localCoerceNumericVector(sweepT.bler_ci_low);
        hi = localCoerceNumericVector(sweepT.bler_ci_high);
        sourceColumn = "bler";
        seriesLabel = upper(direction) + " BLER";
    else
        y = localCoerceNumericVector(sweepT.throughput_mbps);
        lo = nan(height(sweepT), 1);
        hi = nan(height(sweepT), 1);
        sourceColumn = "throughput_mbps";
        seriesLabel = upper(direction) + " throughput";
    end
    snr = localCoerceNumericVector(sweepT.snr_db);
    truth = string(sweepT.truth_status);
    mask = dMask & isfinite(snr) & isfinite(y);
    for idx = find(mask(:)).'
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "Direction", direction, ...
            "SNR_dB", double(snr(idx)), ...
            "MetricValue", double(y(idx)), ...
            "SeriesLabel", seriesLabel, ...
            "SourceColumn", sourceColumn, ...
            "CILow", double(lo(idx)), ...
            "CIHigh", double(hi(idx)), ...
            "TruthStatus", truth(idx), ...
            "SourceCSV", "air_interface/csv/lls_snr_sweep.csv");
    end
end
chartT = struct2table(rows);
end

function pathOut = localPlotSweep(ctx, imgDir, sweepT, cols, labels, fileName, plotTitle, yLabel)
pathOut = "";
chartRows = repmat(struct("SNR_dB", NaN, "MetricValue", NaN, "SeriesLabel", "", "SourceColumn", ""), 0, 1);
hasSweep = istable(sweepT) && ~isempty(sweepT) && ismember("SNR_dB", string(sweepT.Properties.VariableNames));
if hasSweep
    for i = 1:numel(cols)
        col = string(cols(i));
        if ~ismember(col, string(sweepT.Properties.VariableNames))
            continue;
        end
        x = double(sweepT.SNR_dB);
        y = double(sweepT.(col));
        mask = isfinite(x) & isfinite(y);
        if ~any(mask)
            continue;
        end
        label = string(localSweepLegendLabel(sweepT, col, labels(i)));
        for k = find(mask(:)).'
            chartRows(end+1, 1) = struct( ... %#ok<AGROW>
                "SNR_dB", double(x(k)), ...
                "MetricValue", double(y(k)), ...
                "SeriesLabel", label, ...
                "SourceColumn", col);
        end
    end
end
chartT = struct2table(chartRows);
status = sixgr.visual.validatePlotData("relation", localColumnOrEmpty(chartT, "SNR_dB"), localColumnOrEmpty(chartT, "MetricValue"));
csvLogicalPath = localReportChartCSVLogicalPath(fileName);
if istable(chartT) && ~isempty(chartT)
    sixgr.visual.writeChartSourceCsv(char(ctx.RunFolder), csvLogicalPath, chartT);
end
if status.PlotRenderStatus ~= "rendered"
    if localShouldEmitPlaceholderArtifacts(ctx)
        sixgr.util.ensureFolder(imgDir);
        pathOut = string(fullfile(imgDir, fileName));
        localExportPlaceholderFigure(pathOut, plotTitle, "Plot suppressed: " + status.PlotSuppressionReason + ".");
    end
    return;
end
sixgr.util.ensureFolder(imgDir);
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
made = false;
xMin = NaN;
xMax = NaN;
colorOrder = get(ax, "ColorOrder");
for i = 1:numel(cols)
    col = string(cols(i));
    if ~ismember(col, string(sweepT.Properties.VariableNames))
        continue;
    end
    x = double(sweepT.SNR_dB);
    y = double(sweepT.(col));
    mask = isfinite(x) & isfinite(y);
    if ~any(mask)
        continue;
    end
    seriesColor = colorOrder(1 + mod(i - 1, size(colorOrder, 1)), :);
    displayName = char(localSweepLegendLabel(sweepT, col, labels(i)));
    [ciLowCol, ciHighCol] = localResolveSweepCIColumns(sweepT, col);
    plotted = false;
    if strlength(ciLowCol) > 0 && strlength(ciHighCol) > 0
        lo = double(sweepT.(ciLowCol));
        hi = double(sweepT.(ciHighCol));
        ciMask = mask & isfinite(lo) & isfinite(hi);
        if any(ciMask)
            yErrLow = max(y(ciMask) - lo(ciMask), 0);
            yErrHigh = max(hi(ciMask) - y(ciMask), 0);
            if contains(lower(string(yLabel)), "bler") || contains(lower(col), "bler")
                yErrLow = min(yErrLow, max(y(ciMask) * 0.9, 0));
            end
            localPlotDiscreteSweepSeries(ax, x(ciMask), y(ciMask), seriesColor, displayName);
            errorbar(ax, x(ciMask), y(ciMask), yErrLow, yErrHigh, "LineStyle", "none", ...
                "LineWidth", 1.2, "CapSize", 4, "Marker", "none", "HandleVisibility", "off", "Color", seriesColor);
            plotted = true;
        end
        plainMask = mask & ~ciMask;
        if any(plainMask)
            localPlotDiscreteSweepSeries(ax, x(plainMask), y(plainMask), seriesColor, displayName);
            plotted = true;
        end
    else
        localPlotDiscreteSweepSeries(ax, x(mask), y(mask), seriesColor, displayName);
        plotted = true;
    end
    if ~plotted
        continue;
    end
    xSeries = x(mask);
    xMin = localAccumulateMin(xMin, xSeries);
    xMax = localAccumulateMax(xMax, xSeries);
    made = true;
end
if ~made
    return;
end
grid(ax, "on");
xlabel(ax, "SNR (dB)");
ylabel(ax, yLabel);
title(ax, plotTitle);
if isfinite(xMin) && isfinite(xMax)
    if xMin < xMax
        xlim(ax, [xMin, xMax]);
    else
        xlim(ax, [xMin - 0.5, xMax + 0.5]);
    end
    xticks(ax, localSweepTickValues(xMin, xMax));
end
legend(ax, "Location", "best");
pathOut = string(fullfile(imgDir, fileName));
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function pathOut = localPlotMeasuredPostEqSINRBinsDiagnostic(ctx, imgDir)
fileName = "bler_vs_measured_posteq_sinr_bins_diagnostic.png";
pathOut = "";
chartRows = repmat(struct("BinCenterPostEqSINR_dB", NaN, "BLER", NaN, "Direction", "", ...
    "SampleCount", NaN, "CurveConstruction", "diagnostic_posteq_sinr_binning", ...
    "XAxisRole", "diagnostic_posteq_sinr_bin_center_db"), 0, 1);
chartRows = localAppendMeasuredPostEqSINRBinRows(chartRows, ctx.Tables.DL, "DL");
chartRows = localAppendMeasuredPostEqSINRBinRows(chartRows, ctx.Tables.UL, "UL");
chartT = struct2table(chartRows);
status = sixgr.visual.validatePlotData("relation", localColumnOrEmpty(chartT, "BinCenterPostEqSINR_dB"), ...
    localColumnOrEmpty(chartT, "BLER"), "MinimumRows", 2, "MinimumUniqueX", 2, "LLSValidity", "diagnostic_only");
normalPath = string(fullfile(imgDir, fileName));
if status.PlotRenderStatus ~= "rendered"
    localExportPlaceholderFigure(normalPath, "Diagnostic measured SINR bins; not a controlled SNR sweep", ...
        "Diagnostic plot unavailable: " + status.PlotSuppressionReason + ".");
    return;
end
sixgr.visual.writeChartSourceCsv(char(ctx.RunFolder), localReportChartCSVLogicalPath(fileName), chartT);
sixgr.util.ensureFolder(imgDir);
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
series = unique(string(chartT.Direction), "stable");
colorOrder = get(ax, "ColorOrder");
made = false;
for i = 1:numel(series)
    mask = string(chartT.Direction) == series(i);
    x = double(chartT.BinCenterPostEqSINR_dB(mask));
    y = double(chartT.BLER(mask));
    finiteMask = isfinite(x) & isfinite(y);
    if ~any(finiteMask)
        continue;
    end
    localPlotDiscreteSweepSeries(ax, x(finiteMask), y(finiteMask), ...
        colorOrder(1 + mod(i - 1, size(colorOrder, 1)), :), char(series(i) + " diagnostic"));
    made = true;
end
if ~made
    localExportPlaceholderFigure(normalPath, "Diagnostic measured SINR bins; not a controlled SNR sweep", ...
        "Diagnostic plot unavailable: no finite binned series.");
    return;
end
grid(ax, "on");
xlabel(ax, "Measured post-equalization SINR bin center (dB)");
ylabel(ax, "BLER");
title(ax, "Diagnostic measured SINR bins; not a controlled SNR sweep");
legend(ax, "Location", "best");
pathOut = normalPath;
sixgr.util.exportFigureArtifact(fig, normalPath, "Resolution", 160);
end

function rows = localAppendMeasuredPostEqSINRBinRows(rows, T, direction)
if ~(istable(T) && ~isempty(T))
    return;
end
x = localDiagnosticPostEqSINRSamples(T);
if isempty(x)
    return;
end
y = localDiagnosticBLERSamples(T);
if isempty(y)
    return;
end
n = min(numel(x), numel(y));
x = double(x(1:n));
y = double(y(1:n));
mask = isfinite(x) & isfinite(y);
if nnz(mask) < 2
    return;
end
x = x(mask);
y = y(mask);
edges = localDiagnosticPostEqSINRBinEdges(x);
if numel(edges) < 3
    return;
end
for binIdx = 1:(numel(edges) - 1)
    if binIdx == numel(edges) - 1
        binMask = x >= edges(binIdx) & x <= edges(binIdx + 1);
    else
        binMask = x >= edges(binIdx) & x < edges(binIdx + 1);
    end
    if ~any(binMask)
        continue;
    end
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "BinCenterPostEqSINR_dB", double(mean(edges(binIdx:binIdx + 1))), ...
        "BLER", double(mean(y(binMask), "omitnan")), ...
        "Direction", string(direction), ...
        "SampleCount", double(nnz(binMask)), ...
        "CurveConstruction", "diagnostic_posteq_sinr_binning", ...
        "XAxisRole", "diagnostic_posteq_sinr_bin_center_db");
end
end

function x = localDiagnosticPostEqSINRSamples(T)
x = [];
vars = string(T.Properties.VariableNames);
for name = ["PostEqSINR_dB","PostEqWidebandSINR_dB","MeasuredTrialSINR_dB"]
    if ~ismember(name, vars)
        continue;
    end
    candidate = localCoerceNumericVector(T.(name));
    if numel(candidate) == height(T) && any(isfinite(candidate))
        x = candidate;
        return;
    end
end
end

function y = localDiagnosticBLERSamples(T)
y = [];
vars = string(T.Properties.VariableNames);
if ismember("BLER", vars)
    y = localCoerceNumericVector(T.BLER);
elseif ismember("CRCPass", vars)
    crc = localCoerceNumericVector(T.CRCPass);
    valid = isfinite(crc);
    y = nan(size(crc));
    y(valid) = 1 - double(crc(valid) > 0);
end
end

function edges = localDiagnosticPostEqSINRBinEdges(x)
x = double(x(:));
x = x(isfinite(x));
if numel(x) < 2
    edges = [];
    return;
end
lo = floor(min(x));
hi = ceil(max(x));
if ~(isfinite(lo) && isfinite(hi)) || hi <= lo
    edges = [];
    return;
end
numBins = max(2, min(12, ceil((hi - lo) / 2)));
edges = linspace(lo, hi, numBins + 1);
end

function pathOut = localPlotTrialMetricRelationship(ctx, imgDir, dlT, ulT, xVar, yVar, fileName, plotTitle, xLabel, yLabel, logX, logY)
pathOut = "";
[dlX, dlXAvailable] = localResolvedTrialMetric(dlT, xVar);
[dlY, dlYAvailable] = localResolvedTrialMetric(dlT, yVar);
[ulX, ulXAvailable] = localResolvedTrialMetric(ulT, xVar);
[ulY, ulYAvailable] = localResolvedTrialMetric(ulT, yVar);
chartT = table();
if dlXAvailable && dlYAvailable
    chartT = sixgr.visual.buildTrialRelationshipRows(dlT, dlX, dlY, ...
        "DL", "air_interface/csv/dl_pdsch_trials.csv");
end
if ulXAvailable && ulYAvailable
    ulChartT = sixgr.visual.buildTrialRelationshipRows(ulT, ulX, ulY, ...
        "UL", "air_interface/csv/ul_pusch_trials.csv");
    if isempty(chartT)
        chartT = ulChartT;
    else
        chartT = [chartT; ulChartT]; %#ok<AGROW>
    end
end
status = sixgr.visual.validatePlotData("relation", localColumnOrEmpty(chartT, "XValue"), localColumnOrEmpty(chartT, "YValue"));
csvLogicalPath = localReportChartCSVLogicalPath(fileName);
if istable(chartT)
    sixgr.visual.writeChartSourceCsv(char(ctx.RunFolder), csvLogicalPath, chartT);
end
if status.PlotRenderStatus ~= "rendered"
    if localShouldEmitPlaceholderArtifacts(ctx)
        sixgr.util.ensureFolder(imgDir);
        pathOut = string(fullfile(imgDir, fileName));
        localExportPlaceholderFigure(pathOut, plotTitle, "Plot suppressed: " + status.PlotSuppressionReason + ".");
    end
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
made = false;
made = localScatterTrialMetric(ax, dlT, xVar, yVar, "DL", [0.0000 0.4470 0.7410]) || made;
made = localScatterTrialMetric(ax, ulT, xVar, yVar, "UL", [0.8500 0.3250 0.0980]) || made;
if ~made
    return;
end
if logical(logX)
    set(ax, "XScale", "log");
end
if logical(logY)
    set(ax, "YScale", "log");
end
grid(ax, "on");
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, plotTitle);
legend(ax, "Location", "best");
pathOut = string(fullfile(imgDir, fileName));
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function made = localScatterTrialMetric(ax, T, xVar, yVar, label, color)
made = false;
if ~(istable(T) && ~isempty(T))
    return;
end
[x, xAvailable] = localResolvedTrialMetric(T, xVar);
[y, yAvailable] = localResolvedTrialMetric(T, yVar);
if ~(xAvailable && yAvailable)
    return;
end
mask = isfinite(x) & isfinite(y);
if ~any(mask)
    return;
end
vars = string(T.Properties.VariableNames);
modCol = "";
for cand = ["Modulation", "modulation", "PDSCHModulation", "PUSCHModulation"]
    if ismember(cand, vars)
        modCol = cand;
        break;
    end
end
if strlength(modCol) == 0
    scatter(ax, x(mask), y(mask), 18, "o", ...
        "MarkerFaceColor", color, "MarkerEdgeColor", color, ...
        "DisplayName", char(label));
    made = true;
    return;
end
mods = upper(strtrim(string(T.(modCol))));
mods = regexprep(mods, "[^A-Z0-9/]", "");
paletteMods = ["QPSK", "16QAM", "64QAM", "256QAM", "1024QAM", "4096QAM"];
palette = [
    0.10 0.35 0.85;
    0.90 0.45 0.10;
    0.15 0.60 0.25;
    0.75 0.15 0.15;
    0.45 0.25 0.70;
    0.10 0.55 0.60];
plotted = false;
for k = 1:numel(paletteMods)
    mk = mask & mods == paletteMods(k);
    if any(mk)
        scatter(ax, x(mk), y(mk), 20, "o", ...
            "MarkerFaceColor", palette(k, :), "MarkerEdgeColor", palette(k, :), ...
            "DisplayName", char(string(label) + " " + paletteMods(k)));
        plotted = true;
    end
end
otherMask = mask & ~ismember(mods, paletteMods);
if any(otherMask)
    scatter(ax, x(otherMask), y(otherMask), 18, "o", ...
        "MarkerFaceColor", color, "MarkerEdgeColor", color, ...
        "DisplayName", char(string(label) + " other/unknown"));
    plotted = true;
end
if ~plotted
    scatter(ax, x(mask), y(mask), 18, "o", ...
        "MarkerFaceColor", color, "MarkerEdgeColor", color, ...
        "DisplayName", char(label));
end
made = true;
end

function [values, available] = localResolvedTrialMetric(T, varName)
available = false;
values = [];
if ~(istable(T) && ~isempty(T))
    return;
end
token = string(varName);
if ismember(token, string(T.Properties.VariableNames))
    values = localCoerceNumericVector(T.(token));
    available = numel(values) == height(T);
    if ~available
        values = [];
    end
    return;
end

switch lower(strtrim(token))
    case "bler"
        values = localDerivedBLERMetric(T);
        available = any(isfinite(values));
    case "ber"
        values = localDerivedBERMetric(T);
        available = any(isfinite(values));
    case {"derivedecno_db", "ecno_db", "effectiveecno_db"}
        values = localDerivedEcNoMetric(T);
        available = any(isfinite(values));
    case {"derivedebno_db", "ebno_db", "effectiveebno_db"}
        values = localDerivedEbNoMetric(T);
        available = any(isfinite(values));
    case {"derivedesn0_db", "esn0_db", "effectiveesn0_db"}
        values = localDerivedEsNoMetric(T);
        available = any(isfinite(values));
end
end

function values = localDerivedBLERMetric(T)
values = localTrialMetricColumn(T, ["BLER","CodeBlockBLER"], NaN);
if any(isfinite(values))
    return;
end
crc = localTrialMetricColumn(T, "CRCPass", NaN);
values = nan(size(crc));
mask = isfinite(crc);
values(mask) = double(crc(mask) <= 0);
end

function values = localDerivedBERMetric(T)
values = localTrialMetricColumn(T, ["BER","RawBER"], NaN);
if any(isfinite(values))
    return;
end
bitErrors = localTrialMetricColumn(T, "BitErrors", NaN);
bitsCompared = localTrialMetricColumn(T, "BitsCompared", NaN);
values = nan(size(bitErrors));
mask = isfinite(bitErrors) & isfinite(bitsCompared) & bitsCompared > 0;
values(mask) = bitErrors(mask) ./ bitsCompared(mask);
end

function values = localDerivedEsNoMetric(T)
values = localTrialMetricColumn(T, ["PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredWidebandSINR_dB", "MeasuredSINR_dB"], NaN);
end

function values = localDerivedEcNoMetric(T)
sinr_dB = localDerivedEsNoMetric(T);
qm = localTrialModulationOrder(T);
layers = localTrialMetricColumn(T, ["Layers", "Rank"], 1);
codedBitsPerSymbol = qm .* max(layers, 1);
values = sinr_dB - 10 .* log10(max(codedBitsPerSymbol, eps));
values(~(isfinite(sinr_dB) & isfinite(qm) & qm > 0 & isfinite(layers) & layers > 0)) = NaN;
end

function values = localDerivedEbNoMetric(T)
sinr_dB = localDerivedEsNoMetric(T);
qm = localTrialModulationOrder(T);
layers = localTrialMetricColumn(T, ["Layers", "Rank"], 1);
rate = localTrialMetricColumn(T, ["TargetCodeRate", "CQIDerivedTargetCodeRate"], NaN);
infoBitsPerSymbol = qm .* max(layers, 1) .* rate;
values = sinr_dB - 10 .* log10(max(infoBitsPerSymbol, eps));
values(~(isfinite(sinr_dB) & isfinite(qm) & qm > 0 & isfinite(layers) & layers > 0 & isfinite(rate) & rate > 0)) = NaN;
end

function values = localTrialModulationOrder(T)
modulation = strings(height(T), 1);
names = string(T.Properties.VariableNames);
if ismember("Modulation", names)
    modulation = string(T.Modulation);
elseif ismember("CQIDerivedModulation", names)
    modulation = string(T.CQIDerivedModulation);
end
values = nan(height(T), 1);
for i = 1:height(T)
    values(i) = localModulationOrder(modulation(i));
end
end

function value = localModulationOrder(modulation)
token = upper(strtrim(char(string(modulation))));
switch token
    case "QPSK"
        value = 2;
    case "16QAM"
        value = 4;
    case "64QAM"
        value = 6;
    case "256QAM"
        value = 8;
    otherwise
        value = NaN;
end
end

function values = localTrialMetricColumn(T, varNames, defaultValue)
n = height(T);
values = repmat(double(defaultValue), n, 1);
if ~(istable(T) && n > 0)
    return;
end
vars = string(T.Properties.VariableNames);
varNames = string(varNames);
for i = 1:numel(varNames)
    if ~ismember(varNames(i), vars)
        continue;
    end
    candidate = localCoerceNumericVector(T.(varNames(i)));
    if numel(candidate) ~= n
        continue;
    end
    replaceMask = ~isfinite(values) & isfinite(candidate);
    if ~any(replaceMask) && i == 1
        values = candidate;
    else
        values(replaceMask) = candidate(replaceMask);
    end
end
end

function localPlotDiscreteSweepSeries(ax, x, y, color, displayName)
[x, order] = sort(double(x(:)));
y = double(y(:));
y = y(order);
if numel(x) > 1
    stairs(ax, x, y, "-", "LineWidth", 1.1, "HandleVisibility", "off", "Color", color);
end
plot(ax, x, y, "o", "LineWidth", 1.1, "MarkerSize", 5, "DisplayName", displayName, "Color", color);
end

function value = localAccumulateMin(currentValue, x)
x = x(isfinite(x));
if isempty(x)
    value = currentValue;
    return;
end
candidate = min(x);
if ~isfinite(currentValue)
    value = candidate;
else
    value = min(currentValue, candidate);
end
end

function value = localAccumulateMax(currentValue, x)
x = x(isfinite(x));
if isempty(x)
    value = currentValue;
    return;
end
candidate = max(x);
if ~isfinite(currentValue)
    value = candidate;
else
    value = max(currentValue, candidate);
end
end

function ticks = localSweepTickValues(xMin, xMax)
if ~(isfinite(xMin) && isfinite(xMax))
    ticks = [];
    return;
end
if xMin > xMax
    tmp = xMin;
    xMin = xMax;
    xMax = tmp;
end
span = xMax - xMin;
if span <= 10
    step = 1;
elseif span <= 30
    step = 5;
else
    step = 10;
end
interiorStart = ceil(xMin / step) * step;
interiorEnd = floor(xMax / step) * step;
if interiorStart <= interiorEnd
    interior = interiorStart:step:interiorEnd;
else
    interior = [];
end
if ~isempty(interior) && abs(interior(1) - xMin) < 0.5 * step
    interior = interior(2:end);
end
if ~isempty(interior) && abs(interior(end) - xMax) < 0.5 * step
    interior = interior(1:end-1);
end
ticks = unique([xMin, interior, xMax], "stable");
end

function [ciLowCol, ciHighCol] = localResolveSweepCIColumns(sweepT, metricCol)
ciLowCol = "";
ciHighCol = "";
if ~istable(sweepT)
    return;
end
vars = string(sweepT.Properties.VariableNames);
base = string(metricCol);
baseNoUnit = base;
if endsWith(base, "_dB")
    baseNoUnit = extractBefore(base, strlength(base) - 2);
end
patterns = [
    base + "_CI95_Low", base + "_CI95_High";
    base + "_CI_Low", base + "_CI_High";
    baseNoUnit + "_CI95_Low", baseNoUnit + "_CI95_High";
    baseNoUnit + "_CI_Low", baseNoUnit + "_CI_High";
    base + "_lo", base + "_hi";
    base + "_lower", base + "_upper"];
for i = 1:size(patterns, 1)
    if ismember(patterns(i, 1), vars) && ismember(patterns(i, 2), vars)
        ciLowCol = patterns(i, 1);
        ciHighCol = patterns(i, 2);
        return;
    end
end
end

function labelText = localSweepLegendLabel(sweepT, metricCol, baseLabel)
labelText = string(baseLabel);
countCol = localSweepTrialCountColumn(metricCol);
if strlength(countCol) == 0 || ~ismember(countCol, string(sweepT.Properties.VariableNames))
    return;
end
counts = double(sweepT.(countCol));
counts = counts(isfinite(counts) & counts > 0);
if isempty(counts)
    return;
end
if all(abs(counts - counts(1)) < eps)
    labelText = labelText + " (n=" + string(round(counts(1))) + ")";
else
    labelText = labelText + " (n=" + string(round(min(counts))) + "-" + string(round(max(counts))) + ")";
end
end

function visibility = localHandleVisibility(showLegend)
if showLegend
    visibility = "on";
else
    visibility = "off";
end
end

function pathOut = localPlotControlPassRates(imgDir, ctx)
pathOut = "";
entities = ["PBCH","PDCCH","PUCCH"];
tables = {ctx.Tables.PBCH, ctx.Tables.PDCCH, ctx.Tables.PUCCH};
sources = ["air_interface/csv/pbch_trials.csv","air_interface/csv/pdcch_trials.csv","air_interface/csv/pucch_trials.csv"];
if ~localTruthCasePruned(ctx, "PRACH_Detection")
    entities(end+1) = "PRACH"; %#ok<AGROW>
    tables{end+1} = ctx.Tables.PRACH; %#ok<AGROW>
    sources(end+1) = "air_interface/csv/prach_trials.csv"; %#ok<AGROW>
end
rates = NaN(size(entities));
passCounts = zeros(size(entities));
trialCounts = zeros(size(entities));
for i = 1:numel(entities)
    T = tables{i};
    if istable(T) && ~isempty(T) && ismember("Status", string(T.Properties.VariableNames))
        status = upper(strtrim(string(T.Status)));
        validMask = localObservedStatusMask(status);
        if any(validMask)
            passCounts(i) = sum(status(validMask) == "PASS");
            trialCounts(i) = sum(validMask);
            rates(i) = passCounts(i) ./ max(trialCounts(i), 1);
        end
    end
end
if ~any(isfinite(rates))
    return;
end
chartT = table(entities(:), rates(:), passCounts(:), trialCounts(:), sources(:), ...
    repmat("control_summary", numel(entities), 1), repmat("diagnostic_only", numel(entities), 1), ...
    'VariableNames', ["Entity","PassRate","PassCount","TrialCount","SourceArtifact","CurveConstruction","truth_status"]);
sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, "control_pass_rates.csv"), chartT);
sixgr.util.ensureFolder(imgDir);
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
bar(ax, categorical(cellstr(entities)), rates);
ylim(ax, [0 1]);
grid(ax, "on");
ylabel(ax, "Pass rate");
title(ax, "Control and Initial-Access Pass Rates");
pathOut = string(fullfile(imgDir, "control_pass_rates.png"));
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function pathOut = localPlotCoverageAvailability(imgDir, coverageT, ctx)
pathOut = "";
if ~(istable(coverageT) && ~isempty(coverageT))
    return;
end
sixgr.util.ensureFolder(imgDir);
cats = unique(string(coverageT.CategoryCode), "stable");
states = ["observed","derived","config_only","disabled","placeholder","not_supported","not_available","not_exercised"];
stateCounts = zeros(numel(cats), numel(states));
availLower = lower(strtrim(string(coverageT.Availability)));
statesLower = lower(strtrim(string(states)));
for i = 1:numel(cats)
    mask = coverageT.CategoryCode == cats(i);
    for j = 1:numel(states)
        stateCounts(i, j) = sum(mask & (availLower == statesLower(j)));
    end
end
chartRows = repmat(struct("CategoryCode", "", "Availability", "", "MetricCount", NaN, ...
    "CurveConstruction", "category_rollup", "truth_status", "diagnostic_only"), 0, 1);
for i = 1:numel(cats)
    for j = 1:numel(states)
        chartRows(end + 1, 1) = struct( ... %#ok<AGROW>
            "CategoryCode", cats(i), ...
            "Availability", states(j), ...
            "MetricCount", double(stateCounts(i, j)), ...
            "CurveConstruction", "category_rollup", ...
            "truth_status", "diagnostic_only");
    end
end
if ~isempty(chartRows)
    sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
    sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, "metric_coverage_by_category.csv"), ...
        struct2table(chartRows, "AsArray", true));
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
bar(ax, categorical(cellstr(cats)), stateCounts, "stacked");
grid(ax, "on");
ylabel(ax, "Metric count");
title(ax, "LLS Output Coverage States by Category");
legend(ax, cellstr(localAvailabilityStateLabels(states)), "Location", "eastoutside");
pathOut = string(fullfile(imgDir, "metric_coverage_by_category.png"));
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function artifacts = localWriteAggregateArtifacts(ctx, coverageT, rows, plots)
artifacts = struct();
sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
sixgr.util.ensureFolder(ctx.Layout.ReportImageDir);
sixgr.util.ensureFolder(ctx.Layout.ReportDir);

artifacts.PerScenarioSummaryTable = fullfile(ctx.Layout.ReportCSVDir, "per_scenario_summary_tables.csv");
artifacts.MeasuredSINRComparisonTable = fullfile(ctx.Layout.ReportCSVDir, "per_measured_sinr_comparison_tables.csv");
artifacts.BaselineCandidateDeltaTable = fullfile(ctx.Layout.ReportCSVDir, "baseline_candidate_delta_tables.csv");
artifacts.AutomaticMarkdownSummary = fullfile(ctx.Layout.ReportDir, "automatic_markdown_summary.md");
artifacts.WaterfallChart = fullfile(ctx.Layout.ReportImageDir, "gains_losses_waterfall.png");
artifacts.PAPRCCDFPlot = fullfile(ctx.Layout.ReportImageDir, "papr_ccdf.png");
artifacts.LatencyCDFPlot = fullfile(ctx.Layout.ReportImageDir, "latency_cdf.png");
artifacts.AccessDelayCDFPlot = fullfile(ctx.RunFolder, "analytics", "image", ...
    "contract__random-access-prach-analytics__access-latency.png");
artifacts.EnergyVsThroughputPlot = fullfile(ctx.Layout.ReportImageDir, "energy_vs_throughput.png");
artifacts.ComplexityVsGainPlot = fullfile(ctx.Layout.ReportImageDir, "complexity_vs_gain.png");
artifacts.BandFeatureKPIHeatmap = fullfile(ctx.Layout.ReportImageDir, "heatmap_band_feature_kpi.png");
artifacts.ImpairmentKPIHeatmap = fullfile(ctx.Layout.ReportImageDir, "heatmap_impairment_kpi.png");
artifacts.BeamRankTRPKPIHeatmap = fullfile(ctx.Layout.ReportImageDir, "heatmap_beam_rank_trp_kpi.png");

sixgr.util.csvWriteTable(artifacts.PerScenarioSummaryTable, localBuildPerScenarioSummaryTable(ctx, coverageT, rows));
legacyPerSweep = fullfile(ctx.Layout.ReportCSVDir, "per_sweep_comparison_tables.csv");
if exist(legacyPerSweep, "file") == 2
    delete(legacyPerSweep);
end
sixgr.util.csvWriteTable(artifacts.MeasuredSINRComparisonTable, localBuildMeasuredSINRComparisonTable(ctx));
sixgr.util.csvWriteTable(artifacts.BaselineCandidateDeltaTable, localBuildBaselineDeltaTable(ctx));
localWriteAutomaticMarkdownSummary(artifacts.AutomaticMarkdownSummary, ctx, coverageT, plots, artifacts);

if localCanRenderReportFigures(ctx)
    localPlotWaterfallOrPlaceholder(artifacts.WaterfallChart, ctx);
    localPlotPAPRCCDFOrPlaceholder(artifacts.PAPRCCDFPlot, ctx);
    localPlotLatencyCDFOrPlaceholder(artifacts.LatencyCDFPlot, ctx);
    localPlotAccessDelayCDFOrPlaceholder(artifacts.AccessDelayCDFPlot, ctx);
    localPlotEnergyVsThroughputOrPlaceholder(artifacts.EnergyVsThroughputPlot, ctx);
    localPlotComplexityVsGainOrPlaceholder(artifacts.ComplexityVsGainPlot, ctx);
    localPlotBandFeatureKPIHeatmapPlaceholder(artifacts.BandFeatureKPIHeatmap, ctx, coverageT);
    localPlotImpairmentKPIHeatmapPlaceholder(artifacts.ImpairmentKPIHeatmap, ctx, coverageT);
    localPlotBeamRankTRPKPIHeatmapPlaceholder(artifacts.BeamRankTRPKPIHeatmap, ctx, coverageT);
end
end

function T = localBuildPerScenarioSummaryTable(ctx, coverageT, rows)
if nargin < 3
    rows = localEmptyMetricTable();
end
[runtimeCount, configCount, reportCount] = localMetricProvenanceCounts(rows);
coveredCount = sum(localCoverageStateCountsTowardCoverage(string(coverageT.Availability)));
opSummary = localContextOperatingPointSummary(ctx);
availLower = lower(strtrim(string(coverageT.Availability)));
dlGoodput = localMeasuredSummaryNumeric(ctx, "DL", "Goodput_Mbps_mean");
ulGoodput = localMeasuredSummaryNumeric(ctx, "UL", "Goodput_Mbps_mean");
dlBler = localMeasuredSummaryNumeric(ctx, "DL", "BLER_overall");
ulBler = localMeasuredSummaryNumeric(ctx, "UL", "BLER_overall");
dlSINRP5 = localMeasuredSummaryNumeric(ctx, "DL", "SINR_p5_dB");
dlSINRMedian = localMeasuredSummaryNumeric(ctx, "DL", "SINR_median_dB");
dlSINRP95 = localMeasuredSummaryNumeric(ctx, "DL", "SINR_p95_dB");
ulSINRP5 = localMeasuredSummaryNumeric(ctx, "UL", "SINR_p5_dB");
ulSINRMedian = localMeasuredSummaryNumeric(ctx, "UL", "SINR_median_dB");
ulSINRP95 = localMeasuredSummaryNumeric(ctx, "UL", "SINR_p95_dB");
dlDistanceMin = localMeasuredSummaryNumeric(ctx, "DL", "Distance_min_m");
dlDistanceMax = localMeasuredSummaryNumeric(ctx, "DL", "Distance_max_m");
ulDistanceMin = localMeasuredSummaryNumeric(ctx, "UL", "Distance_min_m");
ulDistanceMax = localMeasuredSummaryNumeric(ctx, "UL", "Distance_max_m");
resultOk = localStructLogicalWithFallback(ctx.Manifest, ctx.ScenarioStatus, "ResultOk", false);
partialOk = localStructLogicalWithFallback(ctx.Manifest, ctx.ScenarioStatus, "PartialOk", false);
artifactsGenerated = localStructLogicalWithFallback(ctx.Manifest, ctx.ScenarioStatus, "ArtifactsGenerated", true);
T = table( ...
    string(ctx.ScenarioConfig.ScenarioID), ...
    string(ctx.Manifest.RunnerProfile), ...
    string(ctx.Manifest.RunCompletion), ...
    resultOk, ...
    partialOk, ...
    artifactsGenerated, ...
    double(sixgr.util.structGet(ctx.Manifest, "RequiredCaseCount", sixgr.util.structGet(ctx.ScenarioStatus, "RequiredCaseCount", NaN))), ...
    double(sixgr.util.structGet(ctx.Manifest, "RequiredFailureCount", sixgr.util.structGet(ctx.ScenarioStatus, "RequiredFailureCount", NaN))), ...
    double(sixgr.util.structGet(ctx.Manifest, "OptionalPrunedCount", sixgr.util.structGet(ctx.ScenarioStatus, "OptionalPrunedCount", NaN))), ...
    double(ctx.Manifest.RandomSeed), ...
    string(ctx.Manifest.DeterministicMode), ...
    localRuntimeElapsedSeconds(ctx), ...
    double(coveredCount), ...
    double(sum(availLower == "observed")), ...
    double(sum(availLower == "derived")), ...
    double(sum(availLower == "config_only")), ...
    double(sum(availLower == "disabled")), ...
    double(sum(availLower == "placeholder")), ...
    double(sum(availLower == "not_supported")), ...
    double(sum(availLower == "not_available")), ...
    double(sum(availLower == "not_exercised")), ...
    double(height(coverageT)), ...
    double(runtimeCount), ...
    double(configCount), ...
    double(reportCount), ...
    double(dlGoodput), ...
    double(ulGoodput), ...
    double(dlBler), ...
    double(ulBler), ...
    double(dlSINRP5), ...
    double(dlSINRMedian), ...
    double(dlSINRP95), ...
    double(ulSINRP5), ...
    double(ulSINRMedian), ...
    double(ulSINRP95), ...
    double(dlDistanceMin), ...
    double(dlDistanceMax), ...
    double(ulDistanceMin), ...
    double(ulDistanceMax), ...
    string(opSummary.RuntimeQualifiedDescription), ...
    string(opSummary.Configured.MIMOText), ...
    string(opSummary.Configured.DL.OperatingPointText), ...
    string(opSummary.Configured.UL.OperatingPointText), ...
    double(opSummary.Radio.ActiveGridNumRBs), ...
    string(opSummary.Radio.ActiveGridSource), ...
    string(opSummary.Radio.ActiveDuplexMode), ...
    string(opSummary.Radio.ActiveTDDPattern), ...
    string(opSummary.DL.DominantOperatingPointText), ...
    string(opSummary.DL.LayerHistogram), ...
    string(opSummary.DL.RankHistogram), ...
    string(opSummary.DL.ModulationHistogram), ...
    string(opSummary.DL.MCSHistogram), ...
    double(opSummary.DL.ConfiguredMatchRate), ...
    string(opSummary.UL.DominantOperatingPointText), ...
    string(opSummary.UL.LayerHistogram), ...
    string(opSummary.UL.RankHistogram), ...
    string(opSummary.UL.ModulationHistogram), ...
    string(opSummary.UL.MCSHistogram), ...
    double(opSummary.UL.ConfiguredMatchRate), ...
    string(opSummary.RuntimeNarrative), ...
    'VariableNames', { ...
        'ScenarioID','RunnerProfile','RunCompletion','ResultOk','PartialOk','ArtifactsGenerated','RequiredCaseCount','RequiredFailureCount','OptionalPrunedCount','RandomSeed','DeterministicMode', ...
        'ElapsedSeconds','CoveredMetricCount','ObservedMetricCount','DerivedMetricCount','ConfigOnlyMetricCount','DisabledMetricCount','PlaceholderMetricCount', ...
        'NotSupportedMetricCount','NotAvailableMetricCount','NotExercisedMetricCount','SpecifiedMetricCount', ...
        'ObservedRuntimeMetricCount','ConfigOnlyMetricRollupCount','DerivedMetricRollupCount', ...
        'DL_Goodput_Mbps_mean','UL_Goodput_Mbps_mean','DL_BLER_overall','UL_BLER_overall', ...
        'DL_SINR_p5_dB','DL_SINR_median_dB','DL_SINR_p95_dB','UL_SINR_p5_dB','UL_SINR_median_dB','UL_SINR_p95_dB', ...
        'DL_Distance_min_m','DL_Distance_max_m','UL_Distance_min_m','UL_Distance_max_m', ...
        'RuntimeQualifiedDescription', ...
        'ConfiguredMIMO','ConfiguredDLNominalOperatingPoint','ConfiguredULNominalOperatingPoint', ...
        'ActiveGridNumRBs','ActiveGridSource','ActiveDuplexMode','ActiveTDDPattern', ...
        'EffectiveDLDominantOperatingPoint','EffectiveDLLayerHistogram','EffectiveDLRankHistogram','EffectiveDLModulationHistogram','EffectiveDLMCSHistogram','EffectiveDLConfiguredMatchRate', ...
        'EffectiveULDominantOperatingPoint','EffectiveULLayerHistogram','EffectiveULRankHistogram','EffectiveULModulationHistogram','EffectiveULMCSHistogram','EffectiveULConfiguredMatchRate', ...
        'EffectiveRuntimeNote'});
end

function tf = localStructLogicalWithFallback(primary, secondary, fieldName, defaultValue)
raw = sixgr.util.structGet(primary, fieldName, []);
if localIsMissingScalar(raw)
    raw = sixgr.util.structGet(secondary, fieldName, defaultValue);
end
tf = localScalarLogicalValue(raw, defaultValue);
end

function tf = localScalarLogicalValue(raw, defaultValue)
tf = logical(defaultValue);
if isempty(raw)
    return;
end
if islogical(raw)
    tf = raw(1);
    return;
end
if isnumeric(raw)
    raw = double(raw(1));
    if isfinite(raw)
        tf = raw ~= 0;
    end
    return;
end
text = lower(strtrim(string(raw(1))));
if any(text == ["1","true","yes","on","ok","pass","passed","complete","completed"])
    tf = true;
elseif any(text == ["0","false","no","off","fail","failed",""])
    tf = false;
end
end

function tf = localIsMissingScalar(raw)
tf = isempty(raw);
if tf
    return;
end
if isnumeric(raw)
    tf = isscalar(raw) && isnan(double(raw));
elseif isstring(raw) || ischar(raw)
    txt = strtrim(string(raw));
    tf = isscalar(txt) && (strlength(txt) == 0 || lower(txt) == "nan" || ismissing(txt));
end
end

function T = localBuildMeasuredSINRComparisonTable(ctx)
if istable(ctx.Tables.MeasuredSINRSummary) && ~isempty(ctx.Tables.MeasuredSINRSummary)
    T = ctx.Tables.MeasuredSINRSummary;
    T.SourceTable = repmat("air_interface/csv/lls_measured_sinr_summary.csv", height(T), 1);
    return;
end
T = table("not_available", "No measured-SINR summary table was emitted for this run.", ...
    'VariableNames', {'Availability','Reason'});
end

function T = localBuildBaselineDeltaTable(ctx)
baselineRef = string(ctx.ScenarioConfig.get("meta.baseline_reference_name", ""));
T = table( ...
    string(ctx.ScenarioConfig.ScenarioID), ...
    baselineRef, ...
    "placeholder", ...
    "No paired baseline comparator artifacts were materialized for this single-run result.", ...
    'VariableNames', {'ScenarioID','BaselineReferenceName','ComparisonStatus','Reason'});
end

function [runtimeCount, configCount, reportCount] = localMetricProvenanceCounts(rows)
runtimeCount = 0;
configCount = 0;
reportCount = 0;
if ~(istable(rows) && ~isempty(rows) && all(ismember(["MetricKey","Availability","SourceArtifact"], string(rows.Properties.VariableNames))))
    return;
end
metricKeys = unique(string(rows.MetricKey), "stable");
for i = 1:numel(metricKeys)
    mask = string(rows.MetricKey) == metricKeys(i);
    if ~any(mask)
        continue;
    end
    state = localRollupAvailabilityState(string(rows.Availability(mask)));
    switch state
        case "observed"
            runtimeCount = runtimeCount + 1;
        case "derived"
            reportCount = reportCount + 1;
        case "config_only"
            configCount = configCount + 1;
        otherwise
            % Uncovered states do not contribute to evidence counts.
    end
end
end

function artifacts = localWriteDebugTraceArtifacts(ctx)
artifacts = struct();
sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
sixgr.util.ensureFolder(ctx.Layout.ReportImageDir);

artifacts.ChannelSnapshotsCSV = fullfile(ctx.Layout.ReportCSVDir, "channel_snapshots.csv");
artifacts.ChannelImpulseResponseCSV = fullfile(ctx.Layout.ReportCSVDir, "channel_impulse_response.csv");
artifacts.EqualizedConstellationsCSV = fullfile(ctx.Layout.ReportCSVDir, "equalized_constellations.csv");
artifacts.EqualizedConstellationsImage = fullfile(ctx.Layout.ReportImageDir, "equalized_constellations.png");
artifacts.LLRHistogramsCSV = fullfile(ctx.Layout.ReportCSVDir, "llr_histograms.csv");
artifacts.LLRHistogramsImage = fullfile(ctx.Layout.ReportImageDir, "llr_histograms.png");
artifacts.CFOToTrackingCSV = fullfile(ctx.Layout.ReportCSVDir, "cfo_to_tracking_traces.csv");
artifacts.CFOToTrackingImage = fullfile(ctx.Layout.ReportImageDir, "cfo_to_tracking_traces.png");
artifacts.PRACHCorrelationCSV = fullfile(ctx.Layout.ReportCSVDir, "prach_correlation_trace.csv");
artifacts.PRACHCorrelationLegacyCSV = fullfile(ctx.Layout.ReportCSVDir, "prach_correlation_traces.csv");
artifacts.PRACHCorrelationImage = fullfile(ctx.Layout.ReportImageDir, "prach_correlation_traces.png");

sixgr.util.csvWriteTable(artifacts.ChannelSnapshotsCSV, localBuildChannelSnapshotTable(ctx));
sixgr.util.csvWriteTable(artifacts.ChannelImpulseResponseCSV, localBuildChannelImpulseResponseTable(ctx));
sixgr.util.csvWriteTable(artifacts.EqualizedConstellationsCSV, localBuildEqualizedConstellationTable(ctx));
sixgr.util.csvWriteTable(artifacts.LLRHistogramsCSV, localBuildLLRHistogramTable(ctx));
sixgr.util.csvWriteTable(artifacts.CFOToTrackingCSV, localBuildTrackingTraceTable(ctx), ...
    "PreserveSchema", true);
prachCorrelationTraceT = localBuildPRACHCorrelationTraceTable(ctx);
sixgr.util.csvWriteTable(artifacts.PRACHCorrelationCSV, prachCorrelationTraceT, ...
    "PreserveSchema", true);
sixgr.util.csvWriteTable(artifacts.PRACHCorrelationLegacyCSV, prachCorrelationTraceT, ...
    "PreserveSchema", true);
if localShouldEmitAIAuditArtifacts(ctx)
    artifacts.AIConfidenceCSV = fullfile(ctx.Layout.ReportCSVDir, "ai_confidence_trace.csv");
    artifacts.AIConfidenceImage = fullfile(ctx.Layout.ReportImageDir, "ai_confidence_trace.png");
    sixgr.util.csvWriteTable(artifacts.AIConfidenceCSV, localBuildAIConfidenceTraceTable(ctx));
end

if localCanRenderReportFigures(ctx)
    localPlotEqualizedConstellationsOrPlaceholder(artifacts.EqualizedConstellationsImage, ctx);
    localPlotLLRHistogramsOrPlaceholder(artifacts.LLRHistogramsImage, ctx);
    localPlotTrackingTraceOrPlaceholder(artifacts.CFOToTrackingImage, ctx);
    localPlotPRACHCorrelationTraceOrPlaceholder(artifacts.PRACHCorrelationImage, ctx);
    if isfield(artifacts, "AIConfidenceImage")
        localPlotAIConfidenceTraceOrPlaceholder(artifacts.AIConfidenceImage, ctx);
    end
end
end

function T = localBuildChannelImpulseResponseTable(ctx)
T = sixgr.truth.buildChannelImpulseResponseTable(ctx.InternalConfig);
end

function T = localBuildChannelSnapshotTable(ctx)
parts = { ...
    localChannelSnapshotSlice(ctx.Tables.DL, "DL", "air_interface/csv/dl_pdsch_trials.csv"), ...
    localChannelSnapshotSlice(ctx.Tables.UL, "UL", "air_interface/csv/ul_pusch_trials.csv"), ...
    localChannelSnapshotSlice(ctx.Tables.SRS, "SRS", "air_interface/csv/srs_trials.csv"), ...
    localChannelSnapshotSlice(ctx.Tables.TRS, "TRS", "air_interface/csv/trs_trials.csv"), ...
    localChannelSnapshotSlice(ctx.Tables.PBCH, "PBCH", "air_interface/csv/pbch_trials.csv"), ...
    localChannelSnapshotSlice(ctx.Tables.PRACH, "PRACH", "air_interface/csv/prach_trials.csv")};
T = localVertcatTables(parts);
if ~isempty(T)
    return;
end
T = table( ...
    "not_available", "", NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, "not_available", "none", ...
    'VariableNames', {'TraceSource','Direction','Frame','Slot','SNR_dB','PostEqSINR_dB','ReceiverHestSINR_dB','NMSE_dB','ChannelGain_dB','ConditionNumber_dB', ...
    'EstimatedCFO_Hz','CFOError_Hz','TimingError_samples','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy','Status','SourceArtifact'});
end

function T = localChannelSnapshotSlice(sourceT, traceSource, sourceArtifact)
T = table();
if ~(istable(sourceT) && ~isempty(sourceT))
    return;
end
n = height(sourceT);
T = table( ...
    repmat(string(traceSource), n, 1), ...
    localDebugStringColumn(sourceT, "Direction", n), ...
    localDebugNumericColumn(sourceT, "Frame", n), ...
    localDebugNumericColumn(sourceT, "Slot", n), ...
    localDebugNumericColumn(sourceT, "SNR_dB", n), ...
    localDebugNumericColumn(sourceT, "PostEqSINR_dB", n), ...
    localDebugNumericColumn(sourceT, "ReceiverHestSINR_dB", n), ...
    localDebugNumericColumn(sourceT, "NMSE_dB", n), ...
    localDebugNumericColumn(sourceT, "ChannelGain_dB", n), ...
    localDebugNumericColumn(sourceT, "ConditionNumber_dB", n), ...
    localDebugNumericColumn(sourceT, "EstimatedCFO_Hz", n), ...
    localDebugNumericColumn(sourceT, "CFOError_Hz", n), ...
    localDebugNumericColumn(sourceT, "TimingError_samples", n), ...
    localDebugNumericColumn(sourceT, "EstimatedDopplerHz", n), ...
    localDebugNumericColumn(sourceT, "DopplerError_Hz", n), ...
    localDebugNumericColumn(sourceT, "PhaseTrackingError_deg", n), ...
    localDebugNumericColumn(sourceT, "QCLAccuracy", n), ...
    localDebugStringColumn(sourceT, "Status", n), ...
    repmat(string(sourceArtifact), n, 1), ...
    'VariableNames', {'TraceSource','Direction','Frame','Slot','SNR_dB','PostEqSINR_dB','ReceiverHestSINR_dB','NMSE_dB','ChannelGain_dB','ConditionNumber_dB', ...
    'EstimatedCFO_Hz','CFOError_Hz','TimingError_samples','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy','Status','SourceArtifact'});
end

function T = localBuildEqualizedConstellationTable(ctx)
parts = { ...
    localConstellationSlice(ctx.Tables.DLConstellation, string(sixgr.util.structGet(ctx, "TableSources.DLConstellation", "air_interface/csv/dl_constellation_samples.csv"))), ...
    localConstellationSlice(ctx.Tables.ULConstellation, string(sixgr.util.structGet(ctx, "TableSources.ULConstellation", "air_interface/csv/ul_constellation_samples.csv")))};
T = localVertcatTables(parts);
if ~isempty(T)
    return;
end
T = localEmptyEqualizedConstellationTable();
end

function T = localConstellationSlice(sourceT, sourceArtifact)
T = table();
if ~(istable(sourceT) && ~isempty(sourceT))
    return;
end
T = sourceT;
if ismember("TxReal", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolReal", string(T.Properties.VariableNames))
    T.ReferenceSymbolReal = T.TxReal;
end
if ismember("TxImag", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolImag", string(T.Properties.VariableNames))
    T.ReferenceSymbolImag = T.TxImag;
end
if ismember("DecisionReal", string(T.Properties.VariableNames)) && ~ismember("HardDecisionReal", string(T.Properties.VariableNames))
    T.HardDecisionReal = T.DecisionReal;
end
if ismember("DecisionImag", string(T.Properties.VariableNames)) && ~ismember("HardDecisionImag", string(T.Properties.VariableNames))
    T.HardDecisionImag = T.DecisionImag;
end
if ismember("EqualizedReal", string(T.Properties.VariableNames)) && ~ismember("RawEqualizedReal", string(T.Properties.VariableNames))
    T.RawEqualizedReal = T.EqualizedReal;
end
if ismember("EqualizedImag", string(T.Properties.VariableNames)) && ~ismember("RawEqualizedImag", string(T.Properties.VariableNames))
    T.RawEqualizedImag = T.EqualizedImag;
end
if ~ismember("DetectorOutputReal", string(T.Properties.VariableNames))
    T.DetectorOutputReal = nan(height(T), 1);
end
if ~ismember("DetectorOutputImag", string(T.Properties.VariableNames))
    T.DetectorOutputImag = nan(height(T), 1);
end
T.SourceArtifact = repmat(string(sourceArtifact), height(T), 1);
if ~ismember("Status", string(T.Properties.VariableNames))
    T.Status = repmat("available", height(T), 1);
end
T = localCanonicalizeConstellationSampleTable(T);
end

function T = localEmptyEqualizedConstellationTable()
T = table('Size', [0 38], ...
    'VariableTypes', {'string','double','double','double','double','string', ...
    'double','double','double','double','double','double','double','double','double','double', ...
    'string','string','double','double','double','double','double', ...
    'double','double','double','double','double','double','double','double', ...
    'double','double','double','double','double','string','string'}, ...
    'VariableNames', {'direction','ue_id','slot','tb_id','layer','modulation','mcs_index','snr_db','posteq_sinr_db','symbol_index', ...
    'reference_symbol_i','reference_symbol_q','equalized_i','equalized_q','evm_rms_pct','evm_db', ...
    'RuntimeDirection','RuntimeModulation','RuntimeSNR_dB','SampleIndex','LayerIndex','MCSIndex','PostEqSINR_dB', ...
    'ReferenceSymbolReal','ReferenceSymbolImag','TxReal','TxImag','RawEqualizedReal','RawEqualizedImag','EqualizedReal','EqualizedImag', ...
    'HardDecisionReal','HardDecisionImag','DecisionReal','DecisionImag','SymbolEVM_rms','normalization','truth_status'});
T.SourceArtifact = strings(0, 1);
T.Status = strings(0, 1);
end

function T = localCanonicalizeConstellationSampleTable(T)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = localConstellationStringColumn(T, ["direction","RuntimeDirection"], strings(n, 1));
end
if ~ismember("Modulation", string(T.Properties.VariableNames)) && ismember("modulation", string(T.Properties.VariableNames))
    T.Modulation = string(T.modulation);
end
if ~ismember("Modulation", string(T.Properties.VariableNames))
    T.Modulation = localConstellationStringColumn(T, ["modulation","RuntimeModulation"], strings(n, 1));
end
if ~ismember("SNR_dB", string(T.Properties.VariableNames))
    T.SNR_dB = localConstellationNumericColumn(T, ["snr_db","RuntimeSNR_dB"]);
end
if ~ismember("TBId", string(T.Properties.VariableNames))
    if ismember("tb_id", string(T.Properties.VariableNames))
        T.TBId = localConstellationNumericColumn(T, "tb_id");
    elseif all(ismember(["Frame","Slot"], string(T.Properties.VariableNames)))
        T.TBId = double(T.Frame) .* 10000 + double(T.Slot);
    else
        T.TBId = nan(n, 1);
    end
end
if ismember("TxReal", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolReal", string(T.Properties.VariableNames))
    T.ReferenceSymbolReal = T.TxReal;
end
if ismember("TxImag", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolImag", string(T.Properties.VariableNames))
    T.ReferenceSymbolImag = T.TxImag;
end
if ~ismember("MCSIndex", string(T.Properties.VariableNames)) && ismember("MCS", string(T.Properties.VariableNames))
    T.MCSIndex = double(T.MCS);
end
if ~ismember("MCSIndex", string(T.Properties.VariableNames)) && ismember("mcs_index", string(T.Properties.VariableNames))
    T.MCSIndex = localConstellationNumericColumn(T, "mcs_index");
end
if ~ismember("PostEqSINR_dB", string(T.Properties.VariableNames)) && ismember("MeasuredSINR_dB", string(T.Properties.VariableNames))
    T.PostEqSINR_dB = double(T.MeasuredSINR_dB);
end
if ~ismember("PostEqSINR_dB", string(T.Properties.VariableNames)) && ismember("posteq_sinr_db", string(T.Properties.VariableNames))
    T.PostEqSINR_dB = localConstellationNumericColumn(T, "posteq_sinr_db");
end
if ~ismember("EVM_rms_pct", string(T.Properties.VariableNames))
    if ismember("evm_rms_pct", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.evm_rms_pct);
    elseif ismember("RuntimeEVMRms_pct", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.RuntimeEVMRms_pct);
    elseif ismember("EVM_rms", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.EVM_rms) .* 100;
    elseif ismember("SymbolEVM_rms", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.SymbolEVM_rms) .* 100;
    else
        T.EVM_rms_pct = nan(n, 1);
    end
end
if ~ismember("EVM_dB", string(T.Properties.VariableNames))
    if ismember("evm_db", string(T.Properties.VariableNames))
        T.EVM_dB = double(T.evm_db);
    elseif ismember("RuntimeEVM_dB", string(T.Properties.VariableNames))
        T.EVM_dB = double(T.RuntimeEVM_dB);
    elseif ismember("EVM_rms", string(T.Properties.VariableNames))
        T.EVM_dB = 20 .* log10(max(double(T.EVM_rms), realmin));
    elseif ismember("SymbolEVM_rms", string(T.Properties.VariableNames))
        T.EVM_dB = 20 .* log10(max(double(T.SymbolEVM_rms), realmin));
    else
        T.EVM_dB = nan(n, 1);
    end
end
if ~ismember("Normalization", string(T.Properties.VariableNames))
    T.Normalization = localConstellationStringColumn(T, ["normalization","RuntimeNormalization"], ...
        repmat("post_equalized_and_reference_unit_power_constellation", n, 1));
end
if ~ismember("TruthStatus", string(T.Properties.VariableNames))
    T.TruthStatus = localConstellationStringColumn(T, ["truth_status","RuntimeTruthStatus"], repmat("real_lls_evidence", n, 1));
end
T.direction = localConstellationStringColumn(T, ["direction","Direction","RuntimeDirection"], strings(n, 1));
T.ue_id = localConstellationNumericColumn(T, ["ue_id","UEIndex","UEId","UEID","RNTI"]);
T.slot = localConstellationNumericColumn(T, ["slot","Slot","RuntimeSlot"]);
T.tb_id = localConstellationNumericColumn(T, ["tb_id","TBId"]);
T.layer = localConstellationNumericColumn(T, ["layer","LayerIndex","Layer"]);
T.modulation = localConstellationStringColumn(T, ["modulation","Modulation","RuntimeModulation"], strings(n, 1));
T.mcs_index = localConstellationNumericColumn(T, ["mcs_index","MCSIndex","MCS"]);
T.snr_db = localConstellationNumericColumn(T, ["snr_db","SNR_dB","RuntimeSNR_dB"]);
T.posteq_sinr_db = localConstellationNumericColumn(T, ["posteq_sinr_db","PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"]);
T.symbol_index = localConstellationNumericColumn(T, ["symbol_index","SampleIndex"]);
T.reference_symbol_i = localConstellationNumericColumn(T, ["reference_symbol_i","ReferenceSymbolReal","TxReal"]);
T.reference_symbol_q = localConstellationNumericColumn(T, ["reference_symbol_q","ReferenceSymbolImag","TxImag"]);
T.equalized_i = localConstellationNumericColumn(T, ["equalized_i","EqualizedReal"]);
T.equalized_q = localConstellationNumericColumn(T, ["equalized_q","EqualizedImag"]);
T.evm_rms_pct = localConstellationNumericColumn(T, ["evm_rms_pct","EVM_rms_pct","RuntimeEVMRms_pct"]);
T.evm_db = localConstellationNumericColumn(T, ["evm_db","EVM_dB","RuntimeEVM_dB"]);
T.normalization = localConstellationStringColumn(T, ["normalization","Normalization","RuntimeNormalization"], ...
    repmat("post_equalized_and_reference_unit_power_constellation", n, 1));
T.truth_status = localConstellationStringColumn(T, ["truth_status","TruthStatus","RuntimeTruthStatus"], repmat("real_lls_evidence", n, 1));
T = localDisambiguateConstellationCaseCollisionColumns(T);
end

function T = localDisambiguateConstellationCaseCollisionColumns(T)
renameMap = [ ...
    "Direction", "RuntimeDirection"; ...
    "Modulation", "RuntimeModulation"; ...
    "SNR_dB", "RuntimeSNR_dB"; ...
    "Slot", "RuntimeSlot"; ...
    "EVM_rms_pct", "RuntimeEVMRms_pct"; ...
    "EVM_dB", "RuntimeEVM_dB"; ...
    "Normalization", "RuntimeNormalization"];
for i = 1:size(renameMap, 1)
    src = renameMap(i, 1);
    dst = renameMap(i, 2);
    names = string(T.Properties.VariableNames);
    if ~ismember(src, names)
        continue;
    end
    collidesCaseInsensitive = any(strcmpi(names, src) & names ~= src);
    if ~collidesCaseInsensitive
        continue;
    end
    target = dst;
    while ismember(target, names)
        T.(char(src)) = [];
        break;
    end
    if ~ismember(src, string(T.Properties.VariableNames))
        continue;
    end
    T = renamevars(T, src, target);
end
end

function values = localConstellationNumericColumn(T, names)
values = nan(height(T), 1);
names = string(names);
fallback = values;
haveFallback = false;
for i = 1:numel(names)
    if ~ismember(names(i), string(T.Properties.VariableNames))
        continue;
    end
    try
        candidate = double(T.(names(i)));
    catch
        candidate = str2double(string(T.(names(i))));
    end
    candidate = reshape(candidate, [], 1);
    if numel(candidate) == height(T)
        if any(isfinite(candidate))
            values = candidate;
            return;
        end
        if ~haveFallback
            fallback = candidate;
            haveFallback = true;
        end
    end
end
if haveFallback
    values = fallback;
end
end

function values = localConstellationStringColumn(T, names, defaultValues)
n = height(T);
values = string(defaultValues);
if isscalar(values) && n ~= 1
    values = repmat(values, n, 1);
else
    values = reshape(values, [], 1);
    if numel(values) ~= n
        values = repmat("", n, 1);
    end
end
names = string(names);
fallback = values;
haveFallback = false;
for i = 1:numel(names)
    if ~ismember(names(i), string(T.Properties.VariableNames))
        continue;
    end
    candidate = string(T.(names(i)));
    candidate = reshape(candidate, [], 1);
    if numel(candidate) ~= n
        continue;
    end
    candidate(ismissing(candidate)) = "";
    if any(strlength(strtrim(candidate)) > 0)
        values = candidate;
        return;
    end
    if ~haveFallback
        fallback = candidate;
        haveFallback = true;
    end
end
if haveFallback
    values = fallback;
end
end

function T = localBuildLLRHistogramTable(ctx)
parts = { ...
    localLLRHistogramSlice(ctx.Tables.DL, "DL", "air_interface/csv/dl_pdsch_trials.csv"), ...
    localLLRHistogramSlice(ctx.Tables.UL, "UL", "air_interface/csv/ul_pusch_trials.csv")};
T = localVertcatTables(parts);
if ~isempty(T)
    return;
end
T = table( ...
    "not_available", "", NaN, NaN, NaN, NaN, "none", "not_available", ...
    'VariableNames', {'Direction','MetricName','BinStart','BinEnd','Count','SampleCount','SourceArtifact','Status'});
end

function T = localLLRHistogramSlice(sourceT, direction, sourceArtifact)
metrics = ["LLRMeanAbs","LLRStdAbs","LLRImbalance"];
T = table();
if ~(istable(sourceT) && ~isempty(sourceT))
    return;
end
for i = 1:numel(metrics)
    x = localFiniteColumn(sourceT, metrics(i));
    if isempty(x)
        continue;
    end
    [counts, edges] = localHistogramCounts(x, 12);
    if isempty(counts)
        continue;
    end
    Ti = table( ...
        repmat(string(direction), numel(counts), 1), ...
        repmat(metrics(i), numel(counts), 1), ...
        edges(1:end-1)', ...
        edges(2:end)', ...
        counts(:), ...
        repmat(double(numel(x)), numel(counts), 1), ...
        repmat(string(sourceArtifact), numel(counts), 1), ...
        repmat("available", numel(counts), 1), ...
        'VariableNames', {'Direction','MetricName','BinStart','BinEnd','Count','SampleCount','SourceArtifact','Status'});
    T = localAppendTable(T, Ti);
end
end

function T = localBuildTrackingTraceTable(ctx)
parts = { ...
    localTrackingTraceSlice(ctx.Tables.PBCH, "PBCH", "air_interface/csv/pbch_trials.csv"), ...
    localTrackingTraceSlice(ctx.Tables.DL, "DL", "air_interface/csv/dl_pdsch_trials.csv"), ...
    localTrackingTraceSlice(ctx.Tables.UL, "UL", "air_interface/csv/ul_pusch_trials.csv"), ...
    localTrackingTraceSlice(ctx.Tables.SRS, "SRS", "air_interface/csv/srs_trials.csv"), ...
    localTrackingTraceSlice(ctx.Tables.TRS, "TRS", "air_interface/csv/trs_trials.csv")};
T = localVertcatTables(parts);
if ~isempty(T)
    return;
end
T = table( ...
    "not_available", "", NaN, NaN, NaN, NaN, NaN, "", ...
    NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
    NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
    "none", "not_available", ...
    'VariableNames', {'TraceSource','Direction','SourceRow','UEID','RNTI','Frame','Slot','TransportBlockId', ...
    'SNR_dB', ...
    'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz','EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
    'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples','TrueTimingOffset_samples','TimingError_samples', ...
    'InjectedDoppler_Hz','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','ComputeLatency_ms','AirInterfaceObservation_ms','AcquisitionTime_ms','TrackingFailureProbability','SourceArtifact','Status'});
end

function T = localTrackingTraceSlice(sourceT, traceSource, sourceArtifact)
T = table();
if ~(istable(sourceT) && ~isempty(sourceT))
    return;
end
n = height(sourceT);
T = table( ...
    repmat(string(traceSource), n, 1), ...
    localDebugStringColumn(sourceT, "Direction", n), ...
    (1:n).', ...
    localDebugFirstNumericColumn(sourceT, ["UEID","UEIndex","UE"], n), ...
    localDebugFirstNumericColumn(sourceT, ["RNTI","UEID","UEIndex"], n), ...
    localDebugNumericColumn(sourceT, "Frame", n), ...
    localDebugNumericColumn(sourceT, "Slot", n), ...
    localDebugFirstStringColumn(sourceT, ["TransportBlockId","TransportBlockID","TBID"], n), ...
    localDebugNumericColumn(sourceT, "SNR_dB", n), ...
    localDebugNumericColumn(sourceT, "InjectedCFO_Hz", n), ...
    localDebugNumericColumn(sourceT, "EstimatedCFO_PreCorrection_Hz", n), ...
    localDebugNumericColumn(sourceT, "ResidualCFO_PostCorrection_Hz", n), ...
    localDebugNumericColumn(sourceT, "EstimatedCFO_Hz", n), ...
    localDebugNumericColumn(sourceT, "TrueCFO_Hz", n), ...
    localDebugNumericColumn(sourceT, "CFOError_Hz", n), ...
    localDebugNumericColumn(sourceT, "InjectedTimingOffset_samples", n), ...
    localDebugNumericColumn(sourceT, "EstimatedTimingOffset_PreCorrection_samples", n), ...
    localDebugNumericColumn(sourceT, "ResidualTimingError_PostCorrection_samples", n), ...
    localDebugNumericColumn(sourceT, "TrueTimingOffset_samples", n), ...
    localDebugNumericColumn(sourceT, "TimingError_samples", n), ...
    localDebugNumericColumn(sourceT, "InjectedDoppler_Hz", n), ...
    localDebugNumericColumn(sourceT, "EstimatedDopplerHz", n), ...
    localDebugNumericColumn(sourceT, "DopplerError_Hz", n), ...
    localDebugNumericColumn(sourceT, "PhaseTrackingError_deg", n), ...
    localDebugNumericColumn(sourceT, "ComputeLatency_ms", n), ...
    localDebugNumericColumn(sourceT, "AirInterfaceObservation_ms", n), ...
    localDebugNumericColumn(sourceT, "AcquisitionTime_ms", n), ...
    localDebugNumericColumn(sourceT, "TrackingFailureProbability", n), ...
    repmat(string(sourceArtifact), n, 1), ...
    localDebugStringColumn(sourceT, "Status", n), ...
    'VariableNames', {'TraceSource','Direction','SourceRow','UEID','RNTI','Frame','Slot','TransportBlockId','SNR_dB', ...
    'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz','EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
    'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples','TrueTimingOffset_samples','TimingError_samples', ...
    'InjectedDoppler_Hz','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','ComputeLatency_ms','AirInterfaceObservation_ms','AcquisitionTime_ms','TrackingFailureProbability','SourceArtifact','Status'});
end

function T = localBuildPRACHCorrelationTraceTable(ctx)
T = sixgr.truth.buildPRACHCorrelationTraceTable( ...
    ctx.Tables.PRACHCorrelationTrace, ...
    "TruthCasePruned", localTruthCasePruned(ctx, "PRACH_Detection"));
end

function T = localBuildAIConfidenceTraceTable(ctx)
enabled = localAIEnabled(ctx);
useCase = string(ctx.ScenarioConfig.get("ai_ml.use_case", ""));
inferenceMode = string(ctx.ScenarioConfig.get("ai_ml.inference_mode", ""));
confidenceMetric = string(ctx.ScenarioConfig.get("ai_ml.confidence_metric", ctx.ScenarioConfig.get("ai_ml.confidence_metric_name", "")));
confidence = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredConfidenceScore","ObservedConfidenceScore","RuntimeMeasuredConfidenceScore","ConfidenceScore"]);
confidenceSource = "reports/csv/ai_channel_estimation_benchmark.csv";
if ~isfinite(confidence)
    confidence = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredConfidenceScore","ObservedConfidenceScore","RuntimeMeasuredConfidenceScore","ConfidenceScore"]);
    confidenceSource = "reports/csv/ai_benchmark_metadata.csv";
end
fallbackRate = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredFallbackRate","ObservedFallbackRate","RuntimeFallbackRate","FallbackRate"]);
fallbackSource = "reports/csv/ai_channel_estimation_benchmark.csv";
if ~isfinite(fallbackRate)
    fallbackRate = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredFallbackRate","ObservedFallbackRate","RuntimeFallbackRate","FallbackRate"]);
    fallbackSource = "reports/csv/ai_benchmark_metadata.csv";
end
hasMeasuredTrace = isfinite(confidence) || isfinite(fallbackRate);
if ~isfinite(fallbackRate)
    fallbackRate = double(~enabled) * 0;
end
sourceArtifact = "meta/scenario_config_resolved.json";
status = "config_only";
notes = "Resolved AI/ML trace emitted from configuration and run context. Confidence and fallback values stay config_only unless measured runtime telemetry exists.";
if hasMeasuredTrace
    if isfinite(confidence)
        sourceArtifact = confidenceSource;
    else
        sourceArtifact = fallbackSource;
    end
    status = "derived";
    notes = "Resolved AI/ML trace emitted from measured runtime confidence/fallback telemetry and run context.";
elseif ~localAIEnabled(ctx)
    if localShouldEmitAIAuditArtifacts(ctx)
        status = "disabled";
        notes = "AI/ML is disabled in this scenario; trace emitted only to preserve run-level auditability.";
    else
        status = "not_supported";
        notes = "AI/ML is outside the configured production truth-profile scope, so disabled-AI audit traces are intentionally suppressed.";
    end
end
T = table( ...
    1, ...
    double(enabled), ...
    useCase, ...
    inferenceMode, ...
    confidenceMetric, ...
    double(confidence), ...
    double(fallbackRate), ...
    string(sourceArtifact), ...
    status, ...
    notes, ...
    'VariableNames', {'InvocationIndex','AIEnabled','UseCase','InferenceMode','ConfidenceMetric','ConfidenceScore','FallbackRate','SourceArtifact','Status','Notes'});
end

function localPlotEqualizedConstellationsOrPlaceholder(pathOut, ctx)
T = localBuildEqualizedConstellationTable(ctx);
groups = localSelectConstellationPlotGroups(T, 4);
if ~isempty(groups)
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    nCols = min(2, numel(groups));
    nRows = ceil(numel(groups) / max(nCols, 1));
    tl = tiledlayout(fig, nRows, nCols, "Padding", "compact", "TileSpacing", "compact");
    for i = 1:numel(groups)
        localConstellationAxes(nexttile(tl), groups{i}, "Equalized Constellation");
    end
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "Symbol Constellations", ...
    "Constellation plot suppressed: modulation/layer/SNR/MCS/SINR lineage is missing or no finite equalized/reference symbol pairs were emitted.");
end

function localPlotLLRHistogramsOrPlaceholder(pathOut, ctx)
dl = localFiniteColumn(ctx.Tables.DL, "LLRMeanAbs");
ul = localFiniteColumn(ctx.Tables.UL, "LLRMeanAbs");
if ~isempty(dl) || ~isempty(ul)
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    tl = tiledlayout(fig, 1, 2, "Padding", "compact", "TileSpacing", "compact");
    localHistogramAxes(nexttile(tl), dl, "DL LLR Magnitude", "|LLR|");
    localHistogramAxes(nexttile(tl), ul, "UL LLR Magnitude", "|LLR|");
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "LLR Histograms", "No LLR summary statistics were emitted by the current LLS path.");
end

function localPlotTrackingTraceOrPlaceholder(pathOut, ctx)
T = localBuildTrackingTraceTable(ctx);
usableMask = localUsableTrackingTraceRows(T);
if istable(T) && ~isempty(T) && any(usableMask)
    Tplot = T(usableMask, :);
    traceStatus = sixgr.visual.validatePlotData("trace", (1:height(Tplot)).', ones(height(Tplot), 1));
    if traceStatus.PlotRenderStatus ~= "rendered"
        if localShouldEmitPlaceholderArtifacts(ctx)
            localExportPlaceholderFigure(pathOut, "CFO/TO Tracking Traces", "Plot suppressed: " + traceStatus.PlotSuppressionReason + ".");
        end
        return;
    end
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    tl = tiledlayout(fig, 2, 2, "Padding", "compact", "TileSpacing", "compact");
    localTraceAxes(nexttile(tl), localTrackingPlotColumn(Tplot, ["ResidualCFO_PostCorrection_Hz","CFOError_Hz"]), ...
        "Residual CFO Post-Correction", "Hz");
    localTraceAxes(nexttile(tl), localTrackingPlotColumn(Tplot, ["ResidualTimingError_PostCorrection_samples","TimingError_samples"]), ...
        "Residual Timing Post-Correction", "samples");
    localTraceAxes(nexttile(tl), localTrackingPlotColumn(Tplot, ["DopplerError_Hz"]), ...
        "Doppler Error Trace", "Hz");
    localTraceAxes(nexttile(tl), localTrackingPlotColumn(Tplot, ["PhaseTrackingError_deg"]), ...
        "Phase Tracking Trace", "deg");
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "CFO/TO Tracking Traces", "No CFO/TO tracking samples were emitted by the current LLS path.");
end

function mask = localUsableTrackingTraceRows(T)
mask = false(0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
mask = true(height(T), 1);
if ismember("Status", string(T.Properties.VariableNames))
    status = upper(strtrim(string(T.Status)));
    mask = mask & ~ismember(status, ["NA","NOT_AVAILABLE","NOT_SUPPORTED"]);
end
cols = ["ResidualCFO_PostCorrection_Hz","CFOError_Hz", ...
    "ResidualTimingError_PostCorrection_samples","TimingError_samples", ...
    "DopplerError_Hz","PhaseTrackingError_deg","EstimatedCFO_PreCorrection_Hz","EstimatedDopplerHz"];
hasFinite = false(height(T), 1);
for i = 1:numel(cols)
    col = cols(i);
    if ismember(col, string(T.Properties.VariableNames))
        vals = double(T.(col));
        hasFinite = hasFinite | isfinite(vals);
    end
end
mask = mask & hasFinite;
end

function vals = localTrackingPlotColumn(T, names)
vals = [];
if ~(istable(T) && ~isempty(T))
    return;
end
for i = 1:numel(names)
    name = names(i);
    if ismember(name, string(T.Properties.VariableNames))
        vals = localFiniteColumn(T, name);
        if ~isempty(vals)
            return;
        end
    end
end
end

function localPlotPRACHCorrelationTraceOrPlaceholder(pathOut, ctx)
if localTruthCasePruned(ctx, "PRACH_Detection")
    if ~localShouldEmitPlaceholderArtifacts(ctx)
        return;
    end
    localExportPlaceholderFigure(pathOut, "PRACH Correlation Trace", ...
        "PRACH_Detection was pruned from the active truth profile for this run.");
    return;
end
traceT = localBuildPRACHCorrelationTraceTable(ctx);
validTrace = istable(traceT) && ~isempty(traceT) && ...
    all(ismember(["trial_id","lag_samples","correlation_abs","truth_status"], string(traceT.Properties.VariableNames))) && ...
    any(string(traceT.truth_status) == "real_lls_evidence") && ...
    any(isfinite(double(traceT.lag_samples)) & isfinite(double(traceT.correlation_abs)));
if validTrace
    traceT = traceT(string(traceT.truth_status) == "real_lls_evidence" & ...
        isfinite(double(traceT.lag_samples)) & isfinite(double(traceT.correlation_abs)), :);
    traceStatus = sixgr.visual.validatePlotData("trace", double(traceT.lag_samples), double(traceT.correlation_abs));
    if traceStatus.PlotRenderStatus ~= "rendered"
        if localShouldEmitPlaceholderArtifacts(ctx)
            localExportPlaceholderFigure(pathOut, "PRACH Correlation Trace", "Plot suppressed: " + traceStatus.PlotSuppressionReason + ".");
        end
        return;
    end
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    ax = axes(fig);
    hold(ax, "on");
    trialIds = unique(double(traceT.trial_id), "stable");
    trialIds = trialIds(1:min(numel(trialIds), 3));
    colors = lines(max(numel(trialIds), 1));
    for i = 1:numel(trialIds)
        mask = double(traceT.trial_id) == trialIds(i);
        Tplot = traceT(mask, :);
        [x, order] = sort(double(Tplot.lag_samples));
        y = double(Tplot.correlation_abs(order));
        plot(ax, x, y, "LineWidth", 1.2, "Color", colors(i, :), ...
            "DisplayName", "trial " + string(trialIds(i)));
        localOverlayPRACHTraceMarkers(ax, Tplot(1, :), colors(i, :));
    end
    hold(ax, "off");
    xlabel(ax, "Lag / delay (samples)");
    ylabel(ax, "Normalized correlation magnitude");
    title(ax, "PRACH Correlation Magnitude vs Lag");
    grid(ax, "on");
    legend(ax, "Location", "best");
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "PRACH Correlation Trace", "No lag-domain PRACH correlation samples were emitted by the current LLS path.");
end

function localOverlayPRACHTraceMarkers(ax, row, color)
threshold = localTableScalar(row, "threshold", NaN);
noiseFloor = localTableScalar(row, "noise_floor", NaN);
peakLag = localTableScalar(row, "peak_lag_samples", NaN);
taLag = localTableScalar(row, "timing_advance_samples", NaN);
if isfinite(threshold)
    yline(ax, threshold, "--", "threshold", "Color", color .* 0.65, "HandleVisibility", "off");
end
if isfinite(noiseFloor)
    yline(ax, noiseFloor, ":", "noise floor", "Color", [0.35 0.35 0.35], "HandleVisibility", "off");
end
if isfinite(peakLag)
    xline(ax, peakLag, "-.", "peak", "Color", color, "HandleVisibility", "off");
end
if isfinite(taLag)
    xline(ax, taLag, ":", "TA", "Color", [0.15 0.15 0.15], "HandleVisibility", "off");
end
end

function value = localTableScalar(T, name, defaultValue)
value = defaultValue;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames)) && height(T) >= 1
    raw = T.(char(name));
    try
        value = double(raw(1));
    catch
        value = str2double(string(raw(1)));
    end
end
if isempty(value) || ~isscalar(value)
    value = defaultValue;
end
end

function localPlotAIConfidenceTraceOrPlaceholder(pathOut, ctx)
traceT = localBuildAIConfidenceTraceTable(ctx);
status = sixgr.visual.validatePlotData("trace", (1:height(traceT)).', ones(height(traceT), 1));
if status.PlotRenderStatus ~= "rendered"
    if localShouldEmitPlaceholderArtifacts(ctx)
        localExportPlaceholderFigure(pathOut, "AI Confidence Trace", "Plot suppressed: " + status.PlotSuppressionReason + ".");
    end
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
vals = [localSafeZero(traceT.ConfidenceScore(1)) localSafeZero(traceT.FallbackRate(1))];
bar(ax, vals);
set(ax, 'XTickLabel', {'Confidence','FallbackRate'});
title(ax, "AI Confidence Trace (" + string(traceT.UseCase(1)) + ", enabled=" + string(traceT.AIEnabled(1)) + ")");
ylabel(ax, "Value");
grid(ax, "on");
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function localConstellationAxes(ax, T, plotTitle)
if ~(istable(T) && ~isempty(T))
    axis(ax, "off");
    title(ax, plotTitle);
    text(ax, 0.5, 0.5, "No lineaged samples", "HorizontalAlignment", "center");
    return;
end
hold(ax, "on");
eqMask = isfinite(double(T.equalized_i)) & isfinite(double(T.equalized_q));
scatter(ax, double(T.equalized_i(eqMask)), double(T.equalized_q(eqMask)), 8, "filled", ...
    "MarkerFaceAlpha", 0.35, "DisplayName", "Aligned equalized");
hardRealName = localFirstExistingConstellationVar(T, ["HardDecisionReal","DecisionReal"]);
hardImagName = localFirstExistingConstellationVar(T, ["HardDecisionImag","DecisionImag"]);
hardMask = false(height(T), 1);
if strlength(hardRealName) > 0 && strlength(hardImagName) > 0
    hardMask = isfinite(double(T.(hardRealName))) & isfinite(double(T.(hardImagName)));
end
if any(hardMask)
    scatter(ax, double(T.(hardRealName)(hardMask)), double(T.(hardImagName)(hardMask)), 12, "x", "DisplayName", "Hard decision");
end
refMask = isfinite(double(T.reference_symbol_i)) & isfinite(double(T.reference_symbol_q));
if any(refMask)
    scatter(ax, double(T.reference_symbol_i(refMask)), double(T.reference_symbol_q(refMask)), 10, "+", "DisplayName", "Reference");
end
[idealI, idealQ] = localIdealConstellationPoints(string(T.modulation(1)), double(T.reference_symbol_i), double(T.reference_symbol_q));
if ~isempty(idealI)
    scatter(ax, idealI, idealQ, 30, "kd", "LineWidth", 1.1, "DisplayName", "Ideal constellation");
    localDrawConstellationDecisionBoundaries(ax, idealI, idealQ);
end
evmPct = mean(double(T.evm_rms_pct), "omitnan");
evmDb = mean(double(T.evm_db), "omitnan");
ctxLine = sprintf("%s | mod=%s | layer=%g | SNR=%.3g dB | MCS=%g | N=%d | EVM=%.3g%% / %.3g dB", ...
    char(string(T.direction(1))), char(string(T.modulation(1))), double(T.layer(1)), ...
    double(T.snr_db(1)), double(T.mcs_index(1)), height(T), evmPct, evmDb);
xlabel(ax, "I");
ylabel(ax, "Q");
title(ax, string(plotTitle) + newline + string(ctxLine));
text(ax, 0.02, 0.02, string(ctxLine), "Units", "normalized", "Interpreter", "none", ...
    "FontSize", 7, "BackgroundColor", [1 1 1], "Margin", 3, "VerticalAlignment", "bottom");
axis(ax, "equal");
grid(ax, "on");
legend(ax, "Location", "best");
end

function groups = localSelectConstellationPlotGroups(T, maxGroups)
groups = {};
if nargin < 2
    maxGroups = 4;
end
mask = localConstellationLineageMask(T);
if ~any(mask)
    return;
end
Tv = T(mask, :);
key = string(Tv.direction) + "|" + string(Tv.modulation) + "|layer=" + string(double(Tv.layer)) + "|snr=" + string(double(Tv.snr_db));
[keys, ~, g] = unique(key, "stable");
counts = accumarray(g, 1);
[~, order] = sort(counts, "descend");
order = order(1:min(numel(order), maxGroups));
groups = cell(numel(order), 1);
for i = 1:numel(order)
    Ti = Tv(key == keys(order(i)), :);
    if height(Ti) > 2000
        idx = unique(round(linspace(1, height(Ti), 2000)));
        Ti = Ti(idx, :);
    end
    groups{i} = Ti;
end
end

function mask = localConstellationLineageMask(T)
mask = false(0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
required = ["direction","modulation","layer","snr_db","mcs_index","posteq_sinr_db", ...
    "reference_symbol_i","reference_symbol_q","equalized_i","equalized_q","truth_status"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    mask = false(height(T), 1);
    return;
end
mask = isfinite(double(T.equalized_i)) & isfinite(double(T.equalized_q)) & ...
    isfinite(double(T.reference_symbol_i)) & isfinite(double(T.reference_symbol_q)) & ...
    isfinite(double(T.layer)) & isfinite(double(T.snr_db)) & ...
    isfinite(double(T.mcs_index)) & isfinite(double(T.posteq_sinr_db)) & ...
    strlength(strtrim(string(T.modulation))) > 0 & ...
    ismember(lower(strtrim(string(T.truth_status))), ["real_lls_evidence","truth","runtime_measured"]);
end

function name = localFirstExistingConstellationVar(T, names)
name = "";
names = string(names);
for i = 1:numel(names)
    if ismember(names(i), string(T.Properties.VariableNames))
        name = names(i);
        return;
    end
end
end

function [idealI, idealQ] = localIdealConstellationPoints(modulation, refI, refQ)
modToken = upper(regexprep(char(strtrim(string(modulation))), "[^A-Z0-9/]", ""));
pts = [];
if contains(modToken, "BPSK") && ~contains(modToken, "QPSK")
    pts = [-1; 1];
else
    m = NaN;
    if contains(modToken, "QPSK")
        m = 4;
    else
        tok = regexp(modToken, "(\d+)QAM", "tokens", "once");
        if ~isempty(tok)
            m = str2double(tok{1});
        end
    end
    if isfinite(m) && m >= 4
        side = sqrt(m);
        if abs(side - round(side)) < 1e-9
            levels = (-(side - 1):2:(side - 1)).';
            [ii, qq] = meshgrid(levels, levels);
            pts = ii(:) + 1i .* qq(:);
            pts = pts ./ sqrt(mean(abs(pts).^2, "omitnan"));
        end
    end
end
if isempty(pts)
    ref = complex(refI(:), refQ(:));
    ref = ref(isfinite(real(ref)) & isfinite(imag(ref)));
    pts = complex(round(real(ref) .* 1e6) ./ 1e6, round(imag(ref) .* 1e6) ./ 1e6);
    pts = unique(pts, "stable");
    if numel(pts) > 64
        pts = pts(1:64);
    end
end
idealI = real(pts);
idealQ = imag(pts);
end

function localDrawConstellationDecisionBoundaries(ax, idealI, idealQ)
levelsI = unique(round(double(idealI(:)), 8));
levelsQ = unique(round(double(idealQ(:)), 8));
levelsI = sort(levelsI(isfinite(levelsI)));
levelsQ = sort(levelsQ(isfinite(levelsQ)));
if numel(levelsI) > 1
    mids = (levelsI(1:end-1) + levelsI(2:end)) ./ 2;
    for i = 1:numel(mids)
        xline(ax, mids(i), ":", "Color", [0.65 0.65 0.65], "HandleVisibility", "off");
    end
end
if numel(levelsQ) > 1
    mids = (levelsQ(1:end-1) + levelsQ(2:end)) ./ 2;
    for i = 1:numel(mids)
        yline(ax, mids(i), ":", "Color", [0.65 0.65 0.65], "HandleVisibility", "off");
    end
end
end

function localHistogramAxes(ax, x, plotTitle, xLabel)
if isempty(x)
    axis(ax, "off");
    title(ax, plotTitle);
    text(ax, 0.5, 0.5, "No samples", "HorizontalAlignment", "center");
    return;
end
histogram(ax, x, min(max(numel(unique(x)), 1), 20));
title(ax, plotTitle);
xlabel(ax, xLabel);
ylabel(ax, "Count");
grid(ax, "on");
end

function localTraceAxes(ax, x, plotTitle, yLabel)
if isempty(x)
    axis(ax, "off");
    title(ax, plotTitle);
    text(ax, 0.5, 0.5, "No samples", "HorizontalAlignment", "center");
    return;
end
plot(ax, x, "LineWidth", 1.1);
title(ax, plotTitle);
xlabel(ax, "Sample index");
ylabel(ax, yLabel);
grid(ax, "on");
end

function [counts, edges] = localHistogramCounts(x, nBins)
counts = [];
edges = [];
x = x(isfinite(x));
if isempty(x)
    return;
end
if numel(unique(x)) == 1
    counts = numel(x);
    edges = [x(1)-0.5 x(1)+0.5];
    return;
end
[counts, edges] = histcounts(x, min(nBins, max(4, ceil(sqrt(numel(x))))));
end

function out = localDebugNumericColumn(T, varName, n)
out = nan(n, 1);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = T.(varName);
if iscell(x)
    vals = nan(numel(x), 1);
    for i = 1:numel(x)
        try
            vals(i) = double(x{i});
        catch
            vals(i) = str2double(string(x{i}));
        end
    end
    x = vals;
else
    try
        x = double(x);
    catch
        x = str2double(string(x));
    end
end
out(1:min(numel(x), n)) = reshape(x(1:min(numel(x), n)), [], 1);
end

function out = localDebugStringColumn(T, varName, n)
out = repmat("", n, 1);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = string(T.(varName));
out(1:min(numel(x), n)) = reshape(x(1:min(numel(x), n)), [], 1);
end

function T = localAppendTable(T, Ti)
if isempty(T)
    T = Ti;
else
    T = [T; Ti]; %#ok<AGROW>
end
end

function T = localVertcatTables(parts)
T = table();
for i = 1:numel(parts)
    if istable(parts{i}) && ~isempty(parts{i})
        T = localAppendTable(T, parts{i});
    end
end
end

function pathOut = localDebugArtifactPath(ctx, fieldName)
pathOut = "";
if isfield(ctx, "DebugArtifacts") && isfield(ctx.DebugArtifacts, fieldName)
    pathOut = string(ctx.DebugArtifacts.(fieldName));
end
end

function localExportNamedHeatmap(pathOut, plotTitle, xLabels, rowLabel, values, fallbackMessage)
values = double(values(:))';
finiteMask = isfinite(values);
if ~any(finiteMask)
    localExportPlaceholderFigure(pathOut, plotTitle, fallbackMessage);
    return;
end
sixgr.util.ensureFolder(fileparts(pathOut));
dispVals = values;
dispVals(~finiteMask) = nan;
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
imagesc(ax, dispVals);
colormap(ax, parula);
colorbar(ax);
set(ax, 'YTick', 1, 'YTickLabel', cellstr(string(rowLabel)));
set(ax, 'XTick', 1:numel(xLabels), 'XTickLabel', cellstr(string(xLabels)));
xtickangle(ax, 35);
xlabel(ax, "KPI axis");
ylabel(ax, "Scenario context");
title(ax, plotTitle);
for i = 1:numel(values)
    if isfinite(values(i))
        txt = sprintf("%.3g", values(i));
    else
        txt = "NaN";
    end
    text(ax, i, 1, txt, "HorizontalAlignment", "center", "Color", "w", "FontWeight", "bold");
end
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function tf = localScenarioFlag(scfg, keyPath, defaultValue)
value = scfg.get(keyPath, defaultValue);
if islogical(value)
    tf = any(value(:));
    return;
end
if isnumeric(value)
    tf = any(double(value(:)) ~= 0);
    return;
end
txt = lower(strtrim(string(value)));
tf = any(txt == ["1","true","yes","enabled","on"]);
end

function value = localRMSEAcrossTables(tables, varName)
value = NaN;
x = [];
for i = 1:numel(tables)
    xi = localFiniteColumn(tables{i}, varName);
    if ~isempty(xi)
        x = [x; xi(:)]; %#ok<AGROW>
    end
end
if isempty(x)
    return;
end
value = sqrt(mean(x.^2, "omitnan"));
end

function localWriteAutomaticMarkdownSummary(filePath, ctx, coverageT, plots, artifacts)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
coveredCount = sum(localCoverageStateCountsTowardCoverage(string(coverageT.Availability)));
availability = lower(strtrim(string(coverageT.Availability)));
fprintf(fid, "# Automatic LLS Markdown Summary\n\n");
fprintf(fid, "- Scenario ID: `%s`\n", string(ctx.ScenarioConfig.ScenarioID));
fprintf(fid, "- Runner profile: `%s`\n", string(ctx.Manifest.RunnerProfile));
fprintf(fid, "- Runtime-qualified description: `%s`\n", string(localContextOperatingPointSummary(ctx).RuntimeQualifiedDescription));
fprintf(fid, "- Covered metrics: `%d / %d`\n", coveredCount, height(coverageT));
fprintf(fid, "- Observed metrics: `%d`\n", sum(availability == "observed"));
fprintf(fid, "- Derived metrics: `%d`\n", sum(availability == "derived"));
fprintf(fid, "- Config-only metrics: `%d`\n", sum(availability == "config_only"));
fprintf(fid, "- Disabled metrics: `%d`\n", sum(availability == "disabled"));
fprintf(fid, "- Placeholder metrics: `%d`\n", sum(availability == "placeholder"));
fprintf(fid, "- Not supported in this truth profile: `%d`\n", sum(availability == "not_supported"));
fprintf(fid, "- Not exercised metrics: `%d`\n", sum(availability == "not_exercised"));
fprintf(fid, "- Runtime seconds: `%.3f`\n", localRuntimeElapsedSeconds(ctx));
fprintf(fid, "\n## Aggregate Tables\n\n");
fprintf(fid, "- `%s`\n", localRelativeToRunFolder(artifacts.PerScenarioSummaryTable, ctx.RunFolder));
if isfield(artifacts, "MeasuredSINRComparisonTable")
    fprintf(fid, "- `%s`\n", localRelativeToRunFolder(artifacts.MeasuredSINRComparisonTable, ctx.RunFolder));
end
fprintf(fid, "- `%s`\n", localRelativeToRunFolder(artifacts.BaselineCandidateDeltaTable, ctx.RunFolder));
fprintf(fid, "\n## Aggregate Figures\n\n");
figPaths = [ ...
    string(artifacts.WaterfallChart)
    string(artifacts.PAPRCCDFPlot)
    string(artifacts.LatencyCDFPlot)
    string(artifacts.AccessDelayCDFPlot)
    string(artifacts.EnergyVsThroughputPlot)
    string(artifacts.ComplexityVsGainPlot)
    string(artifacts.BandFeatureKPIHeatmap)
    string(artifacts.ImpairmentKPIHeatmap)
    string(artifacts.BeamRankTRPKPIHeatmap)
    ];
for i = 1:numel(figPaths)
    fprintf(fid, "- `%s`\n", localRelativeToRunFolder(figPaths(i), ctx.RunFolder));
end
if ~isempty(plots)
    fprintf(fid, "\n## Primary Runtime Plots\n\n");
    for i = 1:numel(plots)
        fprintf(fid, "- `%s`\n", localRelativeToRunFolder(plots(i), ctx.RunFolder));
    end
end
clear cleanupObj
sixgr.db.captureFileArtifact(filePath, "markdown_report", "text/markdown; charset=UTF-8", true);
end

function localPlotWaterfallOrPlaceholder(pathOut, ctx)
thr = [localMeasuredSummaryNumeric(ctx, "DL", "Goodput_Mbps_mean"), ...
    localMeasuredSummaryNumeric(ctx, "UL", "Goodput_Mbps_mean")];
bler = [localMeasuredSummaryNumeric(ctx, "DL", "BLER_overall"), ...
    localMeasuredSummaryNumeric(ctx, "UL", "BLER_overall")];
if any(isfinite(thr)) || any(isfinite(bler))
    % The contracted source is per_scenario_summary_tables.csv. A single
    % scenario cannot support a cross-scenario gains/losses waterfall, and
    % mixing Mbps throughput with dimensionless BLER bars would be
    % misleading. Publish an explicit unavailable card until at least two
    % independently identified scenario rows exist.
    sourcePath = fullfile(ctx.Layout.ReportCSVDir, ...
        "per_scenario_summary_tables.csv");
    independentScenarioCount = 0;
    if exist(sourcePath, "file") == 2
        try
            sourceT = sixgr.util.csvReadTable(sourcePath, ...
                "TextType", "string");
            if ismember("ScenarioID", string(sourceT.Properties.VariableNames))
                scenarioIds = strtrim(string(sourceT.ScenarioID));
                independentScenarioCount = numel(unique( ...
                    scenarioIds(strlength(scenarioIds) > 0)));
            end
        catch
            independentScenarioCount = 0;
        end
    end
    if independentScenarioCount < 2
        localExportPlaceholderFigure(pathOut, ...
            "Key Gains/Losses Summary", ...
            "visual_gate=constant_chart_source; at least two independent scenario rows are required for a truthful cross-scenario waterfall.");
        return;
    end
    localExportPlaceholderFigure(pathOut, ...
        "Key Gains/Losses Summary", ...
        "visual_gate=unsupported_mixed_units; throughput (Mbps) and BLER (ratio) require separate normalized comparison series.");
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "Key Gains/Losses Summary", "No measured SINR throughput/BLER summary data available for this run.");
end

function localPlotPAPRCCDFOrPlaceholder(pathOut, ctx)
sixgr.util.ensureFolder(fileparts(pathOut));
dlPAPR = localFiniteColumn(ctx.Tables.DL, "PAPR_dB");
ulPAPR = localFiniteColumn(ctx.Tables.UL, "PAPR_dB");
if ~isempty(dlPAPR) || ~isempty(ulPAPR)
    paprRows = repmat(struct("Direction", "", "PAPR_dB", NaN, "CCDF", NaN), 0, 1);
    paprRows = localAppendPAPRCCDFRows(paprRows, dlPAPR, "DL");
    paprRows = localAppendPAPRCCDFRows(paprRows, ulPAPR, "UL");
    if ~isempty(paprRows)
        sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
        paprT = struct2table(paprRows, "AsArray", true);
        paprT.CurveConstruction = repmat("empirical_ccdf", height(paprT), 1);
        paprT.truth_status = repmat("real_lls_evidence", height(paprT), 1);
        sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, "papr_ccdf.csv"), paprT);
    end
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    ax = axes(fig);
    hold(ax, "on");
    if ~isempty(dlPAPR)
        sorted = sort(dlPAPR(:), "descend");
        semilogy(ax, sorted, max((1:numel(sorted)).' ./ numel(sorted), eps), "b-o", ...
            "LineWidth", 1.1, "MarkerSize", 4, "DisplayName", "DL");
    end
    if ~isempty(ulPAPR)
        sorted = sort(ulPAPR(:), "descend");
        semilogy(ax, sorted, max((1:numel(sorted)).' ./ numel(sorted), eps), "r-s", ...
            "LineWidth", 1.1, "MarkerSize", 4, "DisplayName", "UL");
    end
    xlabel(ax, "PAPR (dB)");
    ylabel(ax, "CCDF P(PAPR > x)");
    title(ax, "PAPR CCDF");
    grid(ax, "on");
    legend(ax, "Location", "best");
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "PAPR CCDF", "No PAPR samples were emitted by the current LLS path.");
end

function rows = localAppendPAPRCCDFRows(rows, paprVec, direction)
paprVec = double(paprVec(:));
paprVec = paprVec(isfinite(paprVec));
if isempty(paprVec)
    return;
end
sorted = sort(paprVec, "descend");
n = numel(sorted);
ccdf = (1:n).' ./ n;
for k = 1:n
    rows(end + 1, 1) = struct("Direction", string(direction), "PAPR_dB", double(sorted(k)), "CCDF", double(ccdf(k))); %#ok<AGROW>
end
end

function localPlotLatencyCDFOrPlaceholder(pathOut, ctx)
series = localLatencyCDFFigureSeries(ctx);
if ~isempty(series)
    localWriteLatencyCDFContractSource(ctx, series);
    localExportLatencySemanticsCDFFigure(pathOut, series);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "Latency Semantics CDF", "No compute, radio-time, or procedure-delay samples were emitted by the current LLS path.");
end

function localPlotAccessDelayCDFOrPlaceholder(pathOut, ctx)
[x, ~] = localInitialAccessProcedureDelaySamples(ctx);
if ~isempty(x)
    localExportCDFFigure(pathOut, x, "Access Procedure Delay CDF", "Procedure delay (ms)");
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "Access Delay CDF", "No true initial-access procedure-delay samples are available in this LLS scope.");
end

function localPlotEnergyVsThroughputOrPlaceholder(pathOut, ctx)
chartT = localEnergyVsThroughputChartTable(ctx);
if istable(chartT) && ~isempty(chartT)
    sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
    sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, "energy_vs_throughput.csv"), chartT);
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    ax = axes(fig);
    scatter(ax, double(chartT.successful_bits), double(chartT.energy_j), 36, "filled");
    xlabel(ax, "Successful bits");
    ylabel(ax, "Cumulative energy (J)");
    title(ax, "Energy vs Successful Bits");
    grid(ax, "on");
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "Energy vs Throughput", "No joint energy/throughput samples were emitted by the current LLS path.");
end

function chartT = localEnergyVsThroughputChartTable(ctx)
chartT = table();
powerT = localReadOptionalTable(fullfile(ctx.Layout.RFCSVDir, "power_energy_table.csv"));
if ~(istable(powerT) && ~isempty(powerT))
    return;
end
chartT = sixgr.visual.buildEnergyThroughputChartTable(powerT, ...
    "rf/csv/power_energy_table.csv");
if height(chartT) < 2
    chartT = table();
    return;
end
end

function out = localDebugFirstNumericColumn(T, varNames, n)
out = nan(n, 1);
for varName = string(varNames)
    if ismember(varName, string(T.Properties.VariableNames))
        out = localDebugNumericColumn(T, varName, n);
        return;
    end
end
end

function out = localDebugFirstStringColumn(T, varNames, n)
out = repmat("", n, 1);
for varName = string(varNames)
    if ismember(varName, string(T.Properties.VariableNames))
        out = localDebugStringColumn(T, varName, n);
        return;
    end
end
end

function localPlotComplexityVsGainOrPlaceholder(pathOut, ctx)
chartT = localComplexityVsGainChartTable(ctx);
if istable(chartT) && ~isempty(chartT)
    sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
    sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, "complexity_vs_gain.csv"), chartT);
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    ax = axes(fig);
    scatter(ax, double(chartT.DecoderComplexityUnits), double(chartT.PostEqSINR_dB), 36, "filled");
    xlabel(ax, "Decoder complexity units");
    ylabel(ax, "Post-equalization SINR (dB)");
    title(ax, "Complexity vs Gain");
    grid(ax, "on");
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
if ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localExportPlaceholderFigure(pathOut, "Complexity vs Gain", "No complexity/gain sample pairs were emitted by the current LLS path.");
end

function chartT = localComplexityVsGainChartTable(ctx)
rows = repmat(struct("Direction", "", "DecoderComplexityUnits", NaN, "PostEqSINR_dB", NaN, ...
    "SourceArtifact", "", "CurveConstruction", "runtime_pairs", "truth_status", "diagnostic_only"), 0, 1);
rows = localAppendComplexityGainRows(rows, ctx.Tables.DL, "DL", "air_interface/csv/dl_pdsch_trials.csv");
rows = localAppendComplexityGainRows(rows, ctx.Tables.UL, "UL", "air_interface/csv/ul_pusch_trials.csv");
if isempty(rows)
    chartT = table();
else
    chartT = struct2table(rows, "AsArray", true);
end
end

function rows = localAppendComplexityGainRows(rows, T, direction, sourceArtifact)
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
if ismember("DecoderComplexityUnits", vars)
    x = localCoerceNumericVector(T.DecoderComplexityUnits);
elseif ismember("NormalizedDecoderComplexity", vars)
    x = localCoerceNumericVector(T.NormalizedDecoderComplexity);
elseif ismember("DecoderIterations", vars)
    x = localCoerceNumericVector(T.DecoderIterations);
else
    return;
end
y = localTrialMetricColumn(T, ["PostEqSINR_dB","MeasuredTrialSINR_dB","MeasuredSINR_dB"], NaN);
n = min(numel(x), numel(y));
x = double(x(1:n));
y = double(y(1:n));
mask = isfinite(x) & isfinite(y);
for i = find(mask(:)).'
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "Direction", string(direction), ...
        "DecoderComplexityUnits", double(x(i)), ...
        "PostEqSINR_dB", double(y(i)), ...
        "SourceArtifact", string(sourceArtifact), ...
        "CurveConstruction", "runtime_pairs", ...
        "truth_status", "diagnostic_only");
end
end

function localPlotBandFeatureKPIHeatmapPlaceholder(pathOut, ctx, coverageT)
values = [ ...
    localRuntimeTrialThroughputMean(ctx.Tables.DL), ...
    localRuntimeTrialThroughputMean(ctx.Tables.UL), ...
    localRuntimeTrialBLERMean(ctx.Tables.DL), ...
    localRuntimeTrialBLERMean(ctx.Tables.UL), ...
    localMeanColumn(ctx.Tables.SRS, "NMSE_dB"), ...
    localProbeMetricScalar(ctx.Tables.BeamManagement, "beam_index_hit_rate"), ...
    localProbeMetricScalar(ctx.Tables.HARQSummary, "rtt_distribution"), ...
    localProbeMetricScalar(ctx.Tables.RFEnergy, "ue_energy_per_successful_bit")];
labels = ["DL Thr","UL Thr","DL BLER","UL BLER","SRS NMSE","Beam Hit","HARQ RTT","UE E/bit"];
rowLabel = string(ctx.ScenarioConfig.get("global_radio_scope.frequency_range_label", ctx.ScenarioConfig.get("frequency.range", "single_run")));
if all(~isfinite(values)) && ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localWriteHeatmapSource(ctx, "heatmap_band_feature_kpi.csv", rowLabel, labels, values, "summary_heatmap");
localExportNamedHeatmap(pathOut, "Band vs Feature vs KPI", labels, rowLabel, values, ...
    "Single-run band/feature/KPI snapshot built from actual run data.");
end

function localPlotImpairmentKPIHeatmapPlaceholder(pathOut, ctx, ~)
rowLabel = string(ctx.ScenarioConfig.get("channel_model.scenario_label", ctx.ScenarioConfig.get("channel.profile", ctx.ScenarioConfig.get("channel.model", "single_run"))));
if rowLabel == ""
    rowLabel = "single_run";
end
values = [ ...
    localRuntimeTrialBLERMean(ctx.Tables.DL), ...
    localRuntimeTrialBLERMean(ctx.Tables.UL), ...
    localMeanColumn(ctx.Tables.SRS, "NMSE_dB"), ...
    localRMSEAcrossTables({ctx.Tables.PBCH, ctx.Tables.DL, ctx.Tables.UL}, "CFOError_Hz"), ...
    localRMSEAcrossTables({ctx.Tables.PBCH, ctx.Tables.DL, ctx.Tables.UL}, "TimingError_samples"), ...
    localRMSEAcrossTables({ctx.Tables.DL, ctx.Tables.UL, ctx.Tables.TRS}, "DopplerError_Hz"), ...
    localMeanColumn(ctx.Tables.DL, "MismatchSensitivity_dB"), ...
    localProbeMetricScalar(ctx.Tables.RFEnergy, "ue_energy_per_successful_bit")];
labels = ["DL BLER","UL BLER","SRS NMSE","CFO RMSE","TO RMSE","Doppler RMSE","Mismatch","UE E/bit"];
if all(~isfinite(values)) && ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localWriteHeatmapSource(ctx, "heatmap_impairment_kpi.csv", rowLabel, labels, values, "summary_heatmap");
localExportNamedHeatmap(pathOut, "Impairment vs KPI", labels, rowLabel, values, ...
    "No impairment-linked KPI snapshot was emitted by the current LLS path.");
end

function localPlotBeamRankTRPKPIHeatmapPlaceholder(pathOut, ctx, ~)
beamCount = localMeanColumn(ctx.Tables.BeamScoreTrace, "BeamCountConfigured");
if ~isfinite(beamCount)
    beamCount = localMeanColumn(ctx.Tables.BeamManagement, "BeamCandidateCount");
end
rankVal = localMeanColumn(ctx.Tables.DL, "Layers");
if ~isfinite(rankVal)
    rankVal = localMeanColumn(ctx.Tables.DL, "RankIndicator");
end
numTrps = double(ctx.ScenarioConfig.get("deployment_topology.num_trps", 1));
rowLabel = "B" + string(localSafeZero(beamCount)) + "_R" + string(localSafeZero(rankVal)) + "_T" + string(localSafeZero(numTrps));
values = [ ...
    localProbeMetricScalar(ctx.Tables.BeamManagement, "beam_index_hit_rate"), ...
    localProbeMetricScalar(ctx.Tables.BeamManagement, "top_k_beam_hit_rate"), ...
    localProbeMetricScalar(ctx.Tables.BeamManagement, "beam_switch_latency"), ...
    localRuntimeTrialThroughputMean(ctx.Tables.DL), ...
    localRuntimeTrialThroughputMean(ctx.Tables.UL), ...
    localRuntimeTrialBLERMean(ctx.Tables.DL), ...
    localRuntimeTrialBLERMean(ctx.Tables.UL), ...
    localProbeMetricScalar(ctx.Tables.BeamManagement, "mtrp_beam_selection_gain")];
labels = ["Beam Hit","Top-K Hit","Switch Lat","DL Thr","UL Thr","DL BLER","UL BLER","mTRP Gain"];
if all(~isfinite(values)) && ~localShouldEmitPlaceholderArtifacts(ctx)
    return;
end
localWriteHeatmapSource(ctx, "heatmap_beam_rank_trp_kpi.csv", rowLabel, labels, values, "summary_heatmap");
localExportNamedHeatmap(pathOut, "Beam/Rank/TRP vs KPI", labels, rowLabel, values, ...
    "No beam/rank/TRP KPI snapshot was emitted by the current LLS path.");
end

function localWriteHeatmapSource(ctx, fileName, rowLabel, labels, values, curveConstruction)
labels = string(labels(:));
values = double(values(:));
n = min(numel(labels), numel(values));
labels = labels(1:n);
values = values(1:n);
T = table(repmat(string(rowLabel), n, 1), labels, values, ...
    repmat(string(curveConstruction), n, 1), repmat("diagnostic_only", n, 1), ...
    'VariableNames', ["RowLabel","Feature","KPIValue","CurveConstruction","truth_status"]);
sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, fileName), T);
end

function value = localRuntimeTrialThroughputMean(T)
value = localMeanColumnFallback(T, ["Goodput_Mbps","OfferedThroughput_Mbps","Throughput_Mbps"]);
end

function value = localRuntimeTrialBLERMean(T)
value = localMeanColumn(T, "BLER");
if isfinite(value)
    return;
end
crc = localFiniteColumn(T, "CRCPass");
if isempty(crc)
    return;
end
value = mean(double(crc(:) <= 0), "omitnan");
end

function localWriteMeasuredSINRRangeSection(fid, ctx, header)
fprintf(fid, "\n%s\n\n", char(string(header)));
fprintf(fid, "| Metric | DL | UL |\n");
fprintf(fid, "|---|---:|---:|\n");
localWriteMeasuredSINRRangeRow(fid, "SINR range (p5-p95) dB", ...
    localFormatRange(localMeasuredSummaryNumeric(ctx, "DL", "SINR_p5_dB"), localMeasuredSummaryNumeric(ctx, "DL", "SINR_p95_dB"), "%.3g"), ...
    localFormatRange(localMeasuredSummaryNumeric(ctx, "UL", "SINR_p5_dB"), localMeasuredSummaryNumeric(ctx, "UL", "SINR_p95_dB"), "%.3g"));
localWriteMeasuredSINRRangeRow(fid, "SINR median dB", ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "DL", "SINR_median_dB"), "%.3g"), ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "UL", "SINR_median_dB"), "%.3g"));
localWriteMeasuredSINRRangeRow(fid, "UE distance range m", ...
    localFormatRange(localMeasuredSummaryNumeric(ctx, "DL", "Distance_min_m"), localMeasuredSummaryNumeric(ctx, "DL", "Distance_max_m"), "%.3g"), ...
    localFormatRange(localMeasuredSummaryNumeric(ctx, "UL", "Distance_min_m"), localMeasuredSummaryNumeric(ctx, "UL", "Distance_max_m"), "%.3g"));
localWriteMeasuredSINRRangeRow(fid, "BLER overall", ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "DL", "BLER_overall"), "%.6g"), ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "UL", "BLER_overall"), "%.6g"));
localWriteMeasuredSINRRangeRow(fid, "BER overall", ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "DL", "BER_overall"), "%.6g"), ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "UL", "BER_overall"), "%.6g"));
localWriteMeasuredSINRRangeRow(fid, "Goodput Mbps", ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "DL", "Goodput_Mbps_mean"), "%.6g"), ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "UL", "Goodput_Mbps_mean"), "%.6g"));
localWriteMeasuredSINRRangeRow(fid, "Spectral efficiency b/s/Hz", ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "DL", "SpectralEfficiency_mean_bps_Hz"), "%.6g"), ...
    localFormatNumber(localMeasuredSummaryNumeric(ctx, "UL", "SpectralEfficiency_mean_bps_Hz"), "%.6g"));
end

function localWriteMeasuredSINRRangeRow(fid, metricName, dlValue, ulValue)
fprintf(fid, "| %s | %s | %s |\n", char(string(metricName)), char(string(dlValue)), char(string(ulValue)));
end

function localWriteMeasuredSINRHighlight(fid, ctx, direction)
direction = upper(string(direction));
row = localMeasuredSummaryRowForDirection(ctx, direction);
if ~(istable(row) && ~isempty(row))
    fprintf(fid, "- %s measured SINR: unavailable\n", char(direction));
    return;
end
p5 = localTableNumericAtRow(row, 1, "SINR_p5_dB");
p95 = localTableNumericAtRow(row, 1, "SINR_p95_dB");
medianSINR = localTableNumericAtRow(row, 1, "SINR_median_dB");
bler = localTableNumericAtRow(row, 1, "BLER_overall");
goodput = localTableNumericAtRow(row, 1, "Goodput_Mbps_mean");
trials = localTableNumericAtRow(row, 1, "N_Trials");
fprintf(fid, "- %s measured SINR p5-p95: `%s dB`, median `%s dB`, BLER `%s`, goodput `%s Mbps`, trials `%s`\n", ...
    char(direction), char(localFormatRange(p5, p95, "%.3g")), char(localFormatNumber(medianSINR, "%.3g")), ...
    char(localFormatNumber(bler, "%.6g")), char(localFormatNumber(goodput, "%.6g")), char(localFormatNumber(trials, "%.0f")));
end

function localWriteMeasuredSINRPerformanceSection(fid, sectionTitle, ctx, direction)
direction = upper(string(direction));
fprintf(fid, "\n%s\n\n", char(string(sectionTitle)));
fprintf(fid, "| Direction | SINR p5-p95 dB | SINR median dB | BLER | BER | Goodput Mbps | Spectral efficiency b/s/Hz | Trials | Source |\n");
fprintf(fid, "|---|---:|---:|---:|---:|---:|---:|---:|---|\n");
row = localMeasuredSummaryRowForDirection(ctx, direction);
if ~(istable(row) && ~isempty(row))
    fprintf(fid, "| %s | NaN | NaN | NaN | NaN | NaN | NaN | 0 | `air_interface/csv/lls_measured_sinr_summary.csv` |\n", char(direction));
    return;
end
fprintf(fid, "| %s | %s | %s | %s | %s | %s | %s | %s | `air_interface/csv/lls_measured_sinr_summary.csv` |\n", ...
    char(direction), ...
    char(localFormatRange(localTableNumericAtRow(row, 1, "SINR_p5_dB"), localTableNumericAtRow(row, 1, "SINR_p95_dB"), "%.3g")), ...
    char(localFormatNumber(localTableNumericAtRow(row, 1, "SINR_median_dB"), "%.3g")), ...
    char(localFormatNumber(localTableNumericAtRow(row, 1, "BLER_overall"), "%.6g")), ...
    char(localFormatNumber(localTableNumericAtRow(row, 1, "BER_overall"), "%.6g")), ...
    char(localFormatNumber(localTableNumericAtRow(row, 1, "Goodput_Mbps_mean"), "%.6g")), ...
    char(localFormatNumber(localTableNumericAtRow(row, 1, "SpectralEfficiency_mean_bps_Hz"), "%.6g")), ...
    char(localFormatNumber(localTableNumericAtRow(row, 1, "N_Trials"), "%.0f")));
end

function txt = localFormatRange(lo, hi, fmt)
loTxt = localFormatNumber(lo, fmt);
hiTxt = localFormatNumber(hi, fmt);
if loTxt == "NaN" && hiTxt == "NaN"
    txt = "NaN";
else
    txt = loTxt + " to " + hiTxt;
end
end

function txt = localFormatNumber(value, fmt)
value = double(value);
if ~(isscalar(value) && isfinite(value))
    txt = "NaN";
    return;
end
txt = string(sprintf(char(fmt), value));
end

function localWriteExecutiveSummary(filePath, ctx, coverageT, rows, plots)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
availableCount = sum(localCoverageStateCountsTowardCoverage(string(coverageT.Availability)));
availability = lower(strtrim(string(coverageT.Availability)));
observedCount = sum(availability == "observed");
derivedCount = sum(availability == "derived");
configOnlyCount = sum(availability == "config_only");
disabledCount = sum(availability == "disabled");
placeholderCount = sum(availability == "placeholder");
notSupportedCount = sum(availability == "not_supported");
notAvailableCount = sum(availability == "not_available");
notExercisedCount = sum(availability == "not_exercised");
specifiedCount = height(coverageT);
[runtimeCount, configCount, reportCount] = localMetricProvenanceCounts(rows);
opSummary = localContextOperatingPointSummary(ctx);
runClassT = sixgr.util.structGet(ctx.Tables, "RunClassification", table());
if istable(runClassT) && height(runClassT) > 0
    runClass = string(localTableStringAtRow(runClassT, 1, "RunClass"));
    publicationEligible = logical(localTableLogicalAtRow(runClassT, 1, "PublicationLLSEligible"));
    runClassReason = string(localTableStringAtRow(runClassT, 1, "Reason"));
    exactMatchRate = localTableNumericAtRow(runClassT, 1, "ExactConfiguredEffectiveMatchRate");
else
    runClass = "unclassified";
    publicationEligible = false;
    runClassReason = "";
    exactMatchRate = NaN;
end
fprintf(fid, "# LLS Executive Summary\n\n");
localWriteImplementationVerdictSection(fid, sixgr.util.structGet(ctx, "ImplementationValidation", struct()), "executive");
fprintf(fid, "- Scenario: `%s`\n", string(ctx.ScenarioConfig.ScenarioID));
fprintf(fid, "- Runner profile: `%s`\n", string(ctx.Manifest.RunnerProfile));
fprintf(fid, "- Run class: `%s`\n", runClass);
fprintf(fid, "- Publication LLS eligible: `%s`\n", string(publicationEligible));
fprintf(fid, "- Exact configured/effective match rate: `%s`\n", localFormatNumber(exactMatchRate, "%.6g"));
if strlength(strtrim(runClassReason)) > 0
    fprintf(fid, "- Run classification reason: `%s`\n", runClassReason);
end
fprintf(fid, "- Runtime-qualified description: `%s`\n", string(opSummary.RuntimeQualifiedDescription));
fprintf(fid, "- Run completion: `%s`\n", string(ctx.Manifest.RunCompletion));
fprintf(fid, "- Result OK: `%s`\n", string(logical(sixgr.util.structGet(ctx.Manifest, "ResultOk", sixgr.util.structGet(ctx.ScenarioStatus, "ResultOk", false)))));
fprintf(fid, "- Partial OK: `%s`\n", string(logical(sixgr.util.structGet(ctx.Manifest, "PartialOk", sixgr.util.structGet(ctx.ScenarioStatus, "PartialOk", false)))));
fprintf(fid, "- Artifacts generated: `%s`\n", string(logical(sixgr.util.structGet(ctx.Manifest, "ArtifactsGenerated", sixgr.util.structGet(ctx.ScenarioStatus, "ArtifactsGenerated", true)))));
fprintf(fid, "- Required failure count: `%g / %g`\n", ...
    double(sixgr.util.structGet(ctx.Manifest, "RequiredFailureCount", sixgr.util.structGet(ctx.ScenarioStatus, "RequiredFailureCount", NaN))), ...
    double(sixgr.util.structGet(ctx.Manifest, "RequiredCaseCount", sixgr.util.structGet(ctx.ScenarioStatus, "RequiredCaseCount", NaN))));
fprintf(fid, "- Optional/pruned case count: `%g`\n", ...
    double(sixgr.util.structGet(ctx.Manifest, "OptionalPrunedCount", sixgr.util.structGet(ctx.ScenarioStatus, "OptionalPrunedCount", NaN))));
fprintf(fid, "- Runtime (s): `%.3f`\n", localRuntimeElapsedSeconds(ctx));
fprintf(fid, "- Covered output metrics: `%d / %d`\n", availableCount, specifiedCount);
fprintf(fid, "- Observed runtime metrics: `%d`\n", observedCount);
fprintf(fid, "- Derived metrics: `%d`\n", derivedCount);
fprintf(fid, "- Config-only metrics: `%d`\n", configOnlyCount);
fprintf(fid, "- Disabled metrics: `%d`\n", disabledCount);
fprintf(fid, "- Placeholder artifacts/metrics: `%d`\n", placeholderCount);
fprintf(fid, "- Not-supported metrics: `%d`\n", notSupportedCount);
fprintf(fid, "- Not-available metrics: `%d`\n", notAvailableCount);
fprintf(fid, "- Not-exercised metrics: `%d`\n", notExercisedCount);
fprintf(fid, "- Observed-runtime rollup count: `%d`\n", runtimeCount);
fprintf(fid, "- Config-only rollup count: `%d`\n", configCount);
fprintf(fid, "- Report-derived rollup count: `%d`\n", reportCount);
fprintf(fid, "- Primary air-interface KPIs: `%s`\n", localExistsText(fullfile(ctx.Layout.AirInterfaceCSVDir, "lls_kpi_summary.csv")));
fprintf(fid, "- Measured SINR summary: `%s`\n", localExistsText(fullfile(ctx.Layout.AirInterfaceCSVDir, "lls_measured_sinr_summary.csv")));
fprintf(fid, "- Report coverage table: `%s`\n", localExistsText(fullfile(ctx.Layout.ReportCSVDir, "lls_output_spec_coverage.csv")));
fprintf(fid, "\n## Operating Point\n\n");
fprintf(fid, "- SINR source: `geometry-derived (pathloss + shadow fading + CDL/TDL channel + MMSE equaliser); no AWGN injection`\n");
fprintf(fid, "- Configured nominal MIMO: `%s`\n", string(opSummary.Configured.MIMOText));
fprintf(fid, "- Configured DL nominal operating point: `%s`\n", string(opSummary.Configured.DL.OperatingPointText));
fprintf(fid, "- Configured UL nominal operating point: `%s`\n", string(opSummary.Configured.UL.OperatingPointText));
fprintf(fid, "- Active grid RBs: `%s` from `%s`\n", string(localNumericToken(opSummary.Radio.ActiveGridNumRBs)), string(opSummary.Radio.ActiveGridSource));
fprintf(fid, "- Active duplex mode: `%s`\n", string(opSummary.Radio.ActiveDuplexMode));
fprintf(fid, "- Active TDD pattern: `%s`\n", string(opSummary.Radio.ActiveTDDPattern));
if logical(opSummary.DL.HasSamples)
    fprintf(fid, "- Effective DL dominant operating point: `%s`\n", string(opSummary.DL.DominantOperatingPointText));
    localWriteHistogramMarkdownTable(fid, opSummary.DL.LayerHistogram, "DL Layer Distribution", "Layers");
    localWriteHistogramMarkdownTable(fid, opSummary.DL.ModulationHistogram, "DL Modulation Distribution", "Modulation");
end
if logical(opSummary.UL.HasSamples)
    fprintf(fid, "- Effective UL dominant operating point: `%s`\n", string(opSummary.UL.DominantOperatingPointText));
    localWriteHistogramMarkdownTable(fid, opSummary.UL.LayerHistogram, "UL Layer Distribution", "Layers");
    localWriteHistogramMarkdownTable(fid, opSummary.UL.ModulationHistogram, "UL Modulation Distribution", "Modulation");
end
fprintf(fid, "- Effective runtime note: `%s`\n", string(opSummary.RuntimeNarrative));
localWriteMeasuredSINRRangeSection(fid, ctx, "## SINR Operating Range (Geometry-Driven)");
fprintf(fid, "\n## Highlights\n\n");
localWriteMeasuredSINRHighlight(fid, ctx, "DL");
localWriteMeasuredSINRHighlight(fid, ctx, "UL");
localWriteMetricHighlight(fid, ctx.Tables.SRS, "NMSE_dB", "SRS NMSE");
localWriteProbeMetricHighlight(fid, ctx.Tables.HARQSummary, "rtt_distribution", "mean_ms", "HARQ RTT");
localWriteProbeMetricHighlight(fid, ctx.Tables.BeamManagement, "beam_index_hit_rate", "rate", "Beam hit rate");
localWriteProbeMetricHighlight(fid, ctx.Tables.RFEnergy, "ue_energy_per_successful_bit", "mean", "UE energy per successful bit");
if ~isempty(plots)
    fprintf(fid, "\n## Key Measurement-Based Curves\n\n");
    for i = 1:numel(plots)
        fprintf(fid, "- `%s`\n", localRelativeToRunFolder(plots(i), ctx.RunFolder));
    end
end
clear cleanupObj
sixgr.db.captureFileArtifact(filePath, "markdown_report", "text/markdown; charset=UTF-8", true);
end

function localWriteTechnicalReport(filePath, ctx, coverageT, rows, plots)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
opSummary = localContextOperatingPointSummary(ctx);
fprintf(fid, "# LLS Technical Report\n\n");
localWriteImplementationVerdictSection(fid, sixgr.util.structGet(ctx, "ImplementationValidation", struct()), "technical");
fprintf(fid, "## Run Metadata\n\n");
fprintf(fid, "- Scenario ID: `%s`\n", string(ctx.ScenarioConfig.ScenarioID));
fprintf(fid, "- Runtime-qualified description: `%s`\n", string(opSummary.RuntimeQualifiedDescription));
fprintf(fid, "- Config hash: `%s`\n", string(ctx.ScenarioConfig.ConfigHash));
fprintf(fid, "- Code version: `%s`\n", string(ctx.Manifest.CodeVersion));
fprintf(fid, "- Random seed: `%d`\n", double(ctx.Manifest.RandomSeed));
fprintf(fid, "- Deterministic mode: `%s`\n", string(ctx.Manifest.DeterministicMode));
fprintf(fid, "- Run completion: `%s`\n", string(ctx.Manifest.RunCompletion));
fprintf(fid, "- Result OK: `%s`\n", string(logical(sixgr.util.structGet(ctx.Manifest, "ResultOk", sixgr.util.structGet(ctx.ScenarioStatus, "ResultOk", false)))));
fprintf(fid, "- Partial OK: `%s`\n", string(logical(sixgr.util.structGet(ctx.Manifest, "PartialOk", sixgr.util.structGet(ctx.ScenarioStatus, "PartialOk", false)))));
fprintf(fid, "- Artifacts generated: `%s`\n", string(logical(sixgr.util.structGet(ctx.Manifest, "ArtifactsGenerated", sixgr.util.structGet(ctx.ScenarioStatus, "ArtifactsGenerated", true)))));
fprintf(fid, "- Required case count: `%g`\n", double(sixgr.util.structGet(ctx.Manifest, "RequiredCaseCount", sixgr.util.structGet(ctx.ScenarioStatus, "RequiredCaseCount", NaN))));
fprintf(fid, "- Required failure count: `%g`\n", double(sixgr.util.structGet(ctx.Manifest, "RequiredFailureCount", sixgr.util.structGet(ctx.ScenarioStatus, "RequiredFailureCount", NaN))));
fprintf(fid, "- Optional/pruned case count: `%g`\n", double(sixgr.util.structGet(ctx.Manifest, "OptionalPrunedCount", sixgr.util.structGet(ctx.ScenarioStatus, "OptionalPrunedCount", NaN))));
if strlength(string(sixgr.util.structGet(ctx.Manifest, "StatusAuthority", sixgr.util.structGet(ctx.ScenarioStatus, "StatusAuthority", "")))) > 0
    fprintf(fid, "- Status authority: `%s`\n", string(sixgr.util.structGet(ctx.Manifest, "StatusAuthority", sixgr.util.structGet(ctx.ScenarioStatus, "StatusAuthority", ""))));
end
if strlength(string(sixgr.util.structGet(ctx.Manifest, "StatusNotes", sixgr.util.structGet(ctx.ScenarioStatus, "StatusNotes", "")))) > 0
    fprintf(fid, "- Status notes: `%s`\n", string(sixgr.util.structGet(ctx.Manifest, "StatusNotes", sixgr.util.structGet(ctx.ScenarioStatus, "StatusNotes", ""))));
end
fprintf(fid, "- Runtime seconds: `%.3f`\n", localRuntimeElapsedSeconds(ctx));
[runtimeCount, configCount, reportCount] = localMetricProvenanceCounts(rows);
availability = lower(strtrim(string(coverageT.Availability)));
fprintf(fid, "- Covered metrics: `%d / %d`\n", sum(localCoverageStateCountsTowardCoverage(availability)), height(coverageT));
fprintf(fid, "- Observed runtime metrics: `%d`\n", sum(availability == "observed"));
fprintf(fid, "- Derived metrics: `%d`\n", sum(availability == "derived"));
fprintf(fid, "- Config-only metrics: `%d`\n", sum(availability == "config_only"));
fprintf(fid, "- Disabled metrics: `%d`\n", sum(availability == "disabled"));
fprintf(fid, "- Placeholder artifacts/metrics: `%d`\n", sum(availability == "placeholder"));
fprintf(fid, "- Not-supported metrics: `%d`\n", sum(availability == "not_supported"));
fprintf(fid, "- Not-available metrics: `%d`\n", sum(availability == "not_available"));
fprintf(fid, "- Not-exercised metrics: `%d`\n", sum(availability == "not_exercised"));
fprintf(fid, "- Observed-runtime rollup count: `%d`\n", runtimeCount);
fprintf(fid, "- Config-only rollup count: `%d`\n", configCount);
fprintf(fid, "- Report-derived rollup count: `%d`\n", reportCount);
fprintf(fid, "\n## Configured vs Effective Operating Point\n\n");
fprintf(fid, "- Runtime-qualified scenario text: `%s`\n", string(opSummary.RuntimeQualifiedDescription));
fprintf(fid, "- Configured nominal MIMO: `%s`\n", string(opSummary.Configured.MIMOText));
fprintf(fid, "- Configured DL nominal operating point: `%s`\n", string(opSummary.Configured.DL.OperatingPointText));
fprintf(fid, "- Configured UL nominal operating point: `%s`\n", string(opSummary.Configured.UL.OperatingPointText));
fprintf(fid, "- Active grid RBs: `%s` from `%s`\n", string(localNumericToken(opSummary.Radio.ActiveGridNumRBs)), string(opSummary.Radio.ActiveGridSource));
fprintf(fid, "- Configured legacy grid RBs: `%s`\n", string(localNumericToken(opSummary.Radio.ConfiguredGridNumRBs)));
fprintf(fid, "- Active duplex mode: `%s`\n", string(opSummary.Radio.ActiveDuplexMode));
fprintf(fid, "- Configured TDD pattern: `%s`\n", string(opSummary.Radio.ConfiguredTDDPattern));
fprintf(fid, "- Active TDD pattern: `%s`\n", string(opSummary.Radio.ActiveTDDPattern));
fprintf(fid, "- TDD pattern applicable: `%s`\n", string(logical(opSummary.Radio.TDDPatternApplicable)));
if logical(opSummary.DL.HasSamples)
    fprintf(fid, "- Effective DL dominant operating point: `%s`\n", string(opSummary.DL.DominantOperatingPointText));
    fprintf(fid, "- Effective DL layer histogram: `%s`\n", string(opSummary.DL.LayerHistogram));
    fprintf(fid, "- Effective DL rank histogram: `%s`\n", string(opSummary.DL.RankHistogram));
    fprintf(fid, "- Effective DL modulation histogram: `%s`\n", string(opSummary.DL.ModulationHistogram));
    fprintf(fid, "- Effective DL MCS histogram: `%s`\n", string(opSummary.DL.MCSHistogram));
    fprintf(fid, "- Effective DL configured-match rate: `%.3f`\n", double(opSummary.DL.ConfiguredMatchRate));
end
if logical(opSummary.UL.HasSamples)
    fprintf(fid, "- Effective UL dominant operating point: `%s`\n", string(opSummary.UL.DominantOperatingPointText));
    fprintf(fid, "- Effective UL layer histogram: `%s`\n", string(opSummary.UL.LayerHistogram));
    fprintf(fid, "- Effective UL rank histogram: `%s`\n", string(opSummary.UL.RankHistogram));
    fprintf(fid, "- Effective UL modulation histogram: `%s`\n", string(opSummary.UL.ModulationHistogram));
    fprintf(fid, "- Effective UL MCS histogram: `%s`\n", string(opSummary.UL.MCSHistogram));
    fprintf(fid, "- Effective UL configured-match rate: `%.3f`\n", double(opSummary.UL.ConfiguredMatchRate));
end
fprintf(fid, "- Effective runtime note: `%s`\n", string(opSummary.RuntimeNarrative));
fprintf(fid, "- SINR source: `geometry-derived (pathloss + shadow fading + CDL/TDL channel + MMSE equaliser); no AWGN injection`\n");
localWriteMeasuredSINRRangeSection(fid, ctx, "## SINR Operating Range (Geometry-Driven)");
fprintf(fid, "\n## Category Coverage\n\n");
cats = unique(string(coverageT.CategoryCode), "stable");
coverageAvailLower = lower(strtrim(string(coverageT.Availability)));
for i = 1:numel(cats)
    mask = coverageT.CategoryCode == cats(i);
    availableCount = sum(mask & localCoverageStateCountsTowardCoverage(coverageAvailLower));
    observedCount = sum(mask & (coverageAvailLower == "observed"));
    derivedCount = sum(mask & (coverageAvailLower == "derived"));
    configOnlyCount = sum(mask & (coverageAvailLower == "config_only"));
    disabledCount = sum(mask & (coverageAvailLower == "disabled"));
    placeholderCount = sum(mask & (coverageAvailLower == "placeholder"));
    notSupportedCount = sum(mask & (coverageAvailLower == "not_supported"));
    totalCount = sum(mask);
    catName = string(coverageT.CategoryName(find(mask, 1, "first")));
    fprintf(fid, "- `%s` %s: `%d / %d` covered, `%d` observed, `%d` derived, `%d` config-only, `%d` disabled, `%d` placeholder, `%d` not supported\n", ...
        cats(i), catName, availableCount, totalCount, observedCount, derivedCount, configOnlyCount, disabledCount, placeholderCount, notSupportedCount);
end
localWriteMeasuredSINRPerformanceSection(fid, "## 2. DL PDSCH Measured-SINR Performance", ctx, "DL");
localWriteMeasuredSINRPerformanceSection(fid, "## 3. UL PUSCH Measured-SINR Performance", ctx, "UL");
localWriteControlPerformanceSection(fid, ctx);
fprintf(fid, "\n## Key Artifacts\n\n");
fprintf(fid, "- `air_interface/csv/lls_kpi_summary.csv`\n");
fprintf(fid, "- `air_interface/csv/lls_measured_sinr_summary.csv`\n");
fprintf(fid, "- `air_interface/csv/dl_measured_sinr_bler_curve.csv`\n");
fprintf(fid, "- `air_interface/csv/ul_measured_sinr_bler_curve.csv`\n");
fprintf(fid, "- `air_interface/csv/dl_measured_sinr_throughput_curve.csv`\n");
fprintf(fid, "- `air_interface/csv/ul_measured_sinr_throughput_curve.csv`\n");
fprintf(fid, "- `air_interface/csv/distance_vs_sinr.csv`\n");
fprintf(fid, "- `harq/csv/probe_harq_summary.csv`\n");
fprintf(fid, "- `beamforming/csv/probe_beam_management.csv`\n");
fprintf(fid, "- `beamforming/csv/beam_management_state_trace.csv`\n");
fprintf(fid, "- `beamforming/csv/beam_management_event_trace.csv`\n");
fprintf(fid, "- `rf/csv/probe_rf_energy.csv`\n");
fprintf(fid, "- `reports/csv/lls_output_spec_coverage.csv`\n");
fprintf(fid, "- `reports/csv/artifact_inventory.csv`\n");
fprintf(fid, "\n## Metrics with Real Runtime Values\n\n");
availRows = rows(localCoverageStateCountsTowardCoverage(string(rows.Availability)), :);
availRows = availRows(1:min(height(availRows), 25), :);
for i = 1:height(availRows)
    fprintf(fid, "- `%s/%s` `%s` [%s]", string(availRows.CategoryCode(i)), string(availRows.MetricKey(i)), string(availRows.Statistic(i)), string(availRows.Availability(i)));
    if isfinite(double(availRows.ValueNumeric(i)))
        fprintf(fid, ": `%.6g`", double(availRows.ValueNumeric(i)));
        if strlength(string(availRows.Unit(i))) > 0
            fprintf(fid, " `%s`", string(availRows.Unit(i)));
        end
    elseif strlength(string(availRows.ValueText(i))) > 0
        fprintf(fid, ": `%s`", string(availRows.ValueText(i)));
    end
    if strlength(string(availRows.SourceArtifact(i))) > 0
        fprintf(fid, " from `%s`", string(availRows.SourceArtifact(i)));
    end
    fprintf(fid, "\n");
end
if ~isempty(plots)
    fprintf(fid, "\n## Generated Plots\n\n");
    for i = 1:numel(plots)
        fprintf(fid, "- `%s`\n", localRelativeToRunFolder(plots(i), ctx.RunFolder));
    end
end
clear cleanupObj
sixgr.db.captureFileArtifact(filePath, "markdown_report", "text/markdown; charset=UTF-8", true);
end

function localWriteImplementationVerdictSection(fid, validation, modeName)
if ~(isstruct(validation) && isfield(validation, "Summary") && isstruct(validation.Summary))
    return;
end
summary = validation.Summary;
if ~isfield(summary, "ActualLLSVerdict")
    return;
end
modeName = lower(strtrim(string(modeName)));
heading = "## Actual LLS Implementation Verdict";
fprintf(fid, "%s\n\n", heading);
fprintf(fid, "- Verdict: `%s`\n", string(sixgr.util.structGet(summary, "ActualLLSVerdict", "")));
fprintf(fid, "- Statement: %s\n", string(sixgr.util.structGet(summary, "VerdictSentence", "")));
fprintf(fid, "- Enabled blocks: `%g`\n", double(sixgr.util.structGet(summary, "EnabledBlockCount", 0)));
fprintf(fid, "- Passing blocks: `%g`\n", double(sixgr.util.structGet(summary, "PassingBlockCount", 0)));
fprintf(fid, "- Reference-compared blocks: `%g`\n", double(sixgr.util.structGet(summary, "ReferenceComparedBlockCount", 0)));
fprintf(fid, "- Numerical sanity failures: `%g`\n", double(sixgr.util.structGet(summary, "NumericalSanityFailureCount", 0)));
localWriteValidationList(fid, "Expected functions not called", sixgr.util.structGet(summary, "FunctionNotCalled", strings(0, 1)));
localWriteValidationList(fid, "Bypassed blocks", sixgr.util.structGet(summary, "BypassedBlocks", strings(0, 1)));
proxyDetections = unique([ ...
    string(sixgr.util.structGet(summary, "LabelOnlyBlocks", strings(0, 1))); ...
    string(sixgr.util.structGet(summary, "ProxyBlocks", strings(0, 1))); ...
    string(sixgr.util.structGet(summary, "FallbackBlocks", strings(0, 1)))]);
localWriteValidationList(fid, "Label-only/proxy detections", proxyDetections);
fprintf(fid, "\n");
end

function localWriteValidationList(fid, titleText, values)
values = string(values(:));
values = values(strlength(strtrim(values)) > 0);
if isempty(values)
    fprintf(fid, "- %s: `none`\n", titleText);
    return;
end
fprintf(fid, "- %s: `%s`\n", titleText, strjoin(cellstr(values), " | "));
end

function localWriteHistogramMarkdownTable(fid, histStr, titleText, dimension)
tableText = localHistogramToMarkdownTable(histStr, dimension);
if strlength(tableText) == 0
    return;
end
fprintf(fid, "\n### %s\n\n%s\n\n", char(string(titleText)), char(tableText));
end

function mdTable = localHistogramToMarkdownTable(histStr, dimension)
mdTable = "";
histStr = strtrim(string(histStr));
if strlength(histStr) == 0
    return;
end
entries = split(histStr, ",");
rows = strings(0, 1);
for i = 1:numel(entries)
    kv = split(strtrim(entries(i)), ":");
    if numel(kv) < 2
        continue;
    end
    rows(end + 1, 1) = "| " + strtrim(kv(1)) + " | " + strtrim(kv(2)) + " |"; %#ok<AGROW>
end
if isempty(rows)
    return;
end
mdTable = strjoin(["| " + string(dimension) + " | Fraction |"; "| --- | ---: |"; rows], newline);
end

function localWriteSweepPerformanceSection(fid, sectionTitle, sweepT, blerCandidates, berCandidates, tputCandidates, countCandidates)
fprintf(fid, "\n%s\n\n", string(sectionTitle));
fprintf(fid, "| SNR (dB) | BLER | BER | Goodput/throughput (Mbps) | Trials |\n");
fprintf(fid, "|---:|---:|---:|---:|---:|\n");
if ~(istable(sweepT) && ~isempty(sweepT) && ismember("SNR_dB", string(sweepT.Properties.VariableNames)))
    fprintf(fid, "| NaN | NaN | NaN | NaN | 0 |\n");
    return;
end
for r = 1:height(sweepT)
    fprintf(fid, "| %.3g | %.6g | %.6g | %.6g | %.0f |\n", ...
        localTableNumericAtRow(sweepT, r, "SNR_dB"), ...
        localTableNumericAtRow(sweepT, r, blerCandidates), ...
        localTableNumericAtRow(sweepT, r, berCandidates), ...
        localTableNumericAtRow(sweepT, r, tputCandidates), ...
        localTableNumericAtRow(sweepT, r, countCandidates));
end
end

function localWriteControlPerformanceSection(fid, ctx)
fprintf(fid, "\n## 4. Control And Initial-Access Performance\n\n");
fprintf(fid, "| Channel | Detection/pass rate | False alarm rate | Trials |\n");
fprintf(fid, "|---|---:|---:|---:|\n");
localWriteControlPerformanceRow(fid, "PDCCH", ctx.Tables.PDCCH);
localWriteControlPerformanceRow(fid, "PUCCH", ctx.Tables.PUCCH);
localWriteControlPerformanceRow(fid, "PRACH", ctx.Tables.PRACH);
end

function localWriteControlPerformanceRow(fid, label, T)
if ~(istable(T) && ~isempty(T))
    fprintf(fid, "| %s | NaN | NaN | 0 |\n", string(label));
    return;
end
fprintf(fid, "| %s | %.6g | %.6g | %d |\n", string(label), localPassRateScalar(T), localFalseAlarmRateScalar(T), height(T));
end

function rate = localFalseAlarmRateScalar(T)
rate = NaN;
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
flagCol = "";
for cand = ["FalseAlarmFlag", "FalseAlarm", "type1_false_detection_flag", "type2_false_detection_flag"]
    if ismember(cand, vars)
        flagCol = cand;
        break;
    end
end
if strlength(flagCol) == 0
    return;
end
x = localCoerceNumericVector(T.(flagCol));
x = x(isfinite(x));
if isempty(x)
    return;
end
rate = mean(x ~= 0);
end

function value = localTableNumericAtRow(T, rowIdx, candidates)
value = NaN;
candidates = string(candidates);
vars = string(T.Properties.VariableNames);
for i = 1:numel(candidates)
    if ismember(candidates(i), vars)
        col = localCoerceNumericVector(T.(candidates(i)));
        if numel(col) >= rowIdx && isfinite(col(rowIdx))
            value = double(col(rowIdx));
            return;
        end
    end
end
end

function value = localTableStringAtRow(T, rowIdx, candidates)
value = "";
candidates = string(candidates);
vars = string(T.Properties.VariableNames);
for i = 1:numel(candidates)
    if ismember(candidates(i), vars)
        col = string(T.(candidates(i)));
        if numel(col) >= rowIdx
            value = strtrim(col(rowIdx));
            return;
        end
    end
end
end

function value = localTableLogicalAtRow(T, rowIdx, candidates)
value = false;
candidates = string(candidates);
vars = string(T.Properties.VariableNames);
for i = 1:numel(candidates)
    if ~ismember(candidates(i), vars)
        continue;
    end
    col = T.(candidates(i));
    if numel(col) < rowIdx
        continue;
    end
    raw = col(rowIdx);
    if islogical(raw)
        value = logical(raw);
    elseif isnumeric(raw)
        value = isfinite(double(raw)) && double(raw) ~= 0;
    else
        value = ismember(lower(strtrim(string(raw))), ["true", "1", "yes", "on", "pass", "ok"]);
    end
    return;
end
end

function localWriteMetricHighlight(fid, T, varName, label)
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
fprintf(fid, "- %s: min=`%.6g`, mean=`%.6g`, max=`%.6g`\n", label, min(x), mean(x, "omitnan"), max(x));
end

function localWriteProbeMetricHighlight(fid, probeT, metricKey, statistic, label)
requiredVars = ["MetricKey","Statistic","Value"];
if ~(istable(probeT) && ~isempty(probeT) && all(ismember(requiredVars, string(probeT.Properties.VariableNames))))
    return;
end
mask = string(probeT.MetricKey) == string(metricKey) & string(probeT.Statistic) == string(statistic);
if ~any(mask)
    return;
end
x = double(probeT.Value(mask));
x = x(isfinite(x));
if isempty(x)
    return;
end
fprintf(fid, "- %s: `%.6g`\n", label, mean(x, "omitnan"));
end

function T = localMetricTableRow(cat, metric, entity, stat, availability, valueNum, valueText, unit, source, notes)
if nargin < 10
    notes = "";
end
state = localNormalizeAvailabilityState(availability, source, notes);
valueText = localResolveMetricValueText(valueNum, valueText);
T = table( ...
    string(cat.code), string(cat.key), string(cat.name), ...
    string(metric.key), string(metric.label), ...
    string(entity), string(stat), string(state), ...
    localCoverageStateCountsTowardCoverage(state), ...
    double(valueNum), string(valueText), string(unit), string(source), string(notes), ...
    'VariableNames', localMetricTableVarNames());
end

function T = localEmptyMetricTable()
varNames = localMetricTableVarNames();
varTypes = {'string','string','string','string','string','string','string','string','logical','double','string','string','string','string'};
T = table('Size', [0 numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
end

function valueText = localResolveMetricValueText(valueNum, valueText)
valueText = string(valueText);
if strlength(strtrim(valueText)) > 0
    return;
end
if isnumeric(valueNum) && isscalar(valueNum) && isfinite(double(valueNum))
    valueText = strtrim(compose("%.15g", double(valueNum)));
else
    valueText = "";
end
end

function names = localMetricTableVarNames()
names = {'CategoryCode','CategoryKey','CategoryName','MetricKey','MetricName', ...
    'Entity','Statistic','Availability','CountsTowardCoverage','ValueNumeric','ValueText','Unit','SourceArtifact','Notes'};
end

function out = localDefaultSource(entity)
entity = upper(string(entity));
switch entity
    case {"DL","RANK_1","RANK_2","RANK_3","RANK_4"}
        out = "air_interface/csv/dl_pdsch_trials.csv";
    case "UL"
        out = "air_interface/csv/ul_pusch_trials.csv";
    case "UL_GOOD_BLOCK_SIZE"
        out = "air_interface/csv/ul_pusch_trials.csv";
    case "PBCH"
        out = "air_interface/csv/pbch_trials.csv";
    case {"CELL_SEARCH_PBCH","CELL_SEARCH"}
        out = "air_interface/csv/pbch_trials.csv";
    case "PRACH"
        out = "air_interface/csv/prach_trials.csv";
    case "PDCCH"
        out = "air_interface/csv/pdcch_trials.csv";
    case "PUCCH"
        out = "air_interface/csv/pucch_trials.csv";
    case "SRS"
        out = "air_interface/csv/srs_trials.csv";
    case "TRS"
        out = "air_interface/csv/trs_trials.csv";
    case "BEAMFORMING"
        out = "beamforming/csv/probe_beam_mimo.csv";
    otherwise
        out = "";
end
end

function out = localRuntimeTimestampAvailability(ctx, fieldName)
value = string(sixgr.util.structGet(ctx.RuntimeSummary, string(fieldName), ""));
if strlength(strtrim(value)) > 0 && ...
        exist(fullfile(ctx.Layout.MetaDir, "runtime_summary.json"), "file") == 2
    out = "derived";
else
    out = "not_available";
end
end

function out = localRuntimeNumericAvailability(ctx, fieldName)
value = str2double(string(sixgr.util.structGet( ...
    ctx.RuntimeSummary, string(fieldName), NaN)));
if isscalar(value) && isfinite(value) && ...
        exist(fullfile(ctx.Layout.MetaDir, "runtime_summary.json"), "file") == 2
    out = "derived";
else
    out = "not_available";
end
end

function value = localRuntimeElapsedSeconds(ctx)
raw = sixgr.util.structGet(ctx.RuntimeSummary, "ElapsedSeconds", NaN);
value = str2double(string(raw));
if ~isscalar(value) || ~isfinite(value)
    value = NaN;
else
    value = double(value);
end
end

function out = localTableAvailability(T)
if istable(T) && ~isempty(T)
    out = "observed";
else
    out = "not_available";
end
end

function out = localFileAvailability(path)
if exist(path, "file") == 2
    out = localInferAvailabilityFromSource(path);
else
    out = "not_available";
end
end

function pathOut = localAggregateArtifactPath(ctx, fieldName)
pathOut = "";
if isfield(ctx, "AggregateArtifacts") && isfield(ctx.AggregateArtifacts, fieldName)
    pathOut = string(ctx.AggregateArtifacts.(fieldName));
    return;
end
switch string(fieldName)
    case "PerScenarioSummaryTable"
        pathOut = fullfile(ctx.Layout.ReportCSVDir, "per_scenario_summary_tables.csv");
    case {"MeasuredSINRComparisonTable","PerSweepComparisonTable"}
        pathOut = fullfile(ctx.Layout.ReportCSVDir, "per_measured_sinr_comparison_tables.csv");
    case "BaselineCandidateDeltaTable"
        pathOut = fullfile(ctx.Layout.ReportCSVDir, "baseline_candidate_delta_tables.csv");
    case "AutomaticMarkdownSummary"
        pathOut = fullfile(ctx.Layout.ReportDir, "automatic_markdown_summary.md");
    case "WaterfallChart"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "gains_losses_waterfall.png");
    case "PAPRCCDFPlot"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "papr_ccdf.png");
    case "LatencyCDFPlot"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "latency_cdf.png");
    case "AccessDelayCDFPlot"
        pathOut = fullfile(ctx.RunFolder, "analytics", "image", ...
            "contract__random-access-prach-analytics__access-latency.png");
    case "EnergyVsThroughputPlot"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "energy_vs_throughput.png");
    case "ComplexityVsGainPlot"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "complexity_vs_gain.png");
    case "BandFeatureKPIHeatmap"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "heatmap_band_feature_kpi.png");
    case "ImpairmentKPIHeatmap"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "heatmap_impairment_kpi.png");
    case "BeamRankTRPKPIHeatmap"
        pathOut = fullfile(ctx.Layout.ReportImageDir, "heatmap_beam_rank_trp_kpi.png");
end
pathOut = string(pathOut);
end

function out = localLogicalAvailability(tf)
if tf
    out = "derived";
else
    out = "not_available";
end
end

function out = localDerivedOrPlaceholderAvailability(tf)
if tf
    out = "derived";
else
    out = "not_available";
end
end

function out = localDerivedOrSuppressedPlaceholderAvailability(ctx, tf)
if tf
    out = "derived";
else
    out = "not_available";
end
end

function out = localFeatureAvailability(enabled)
if enabled
    out = "observed";
else
    out = "disabled";
end
end

function state = localNormalizeAvailabilityState(availability, source, notes) %#ok<INUSD>
state = lower(strtrim(string(availability)));
source = strtrim(string(source));
% Availability is an explicit producer contract.  Do not infer or override
% it from human-readable notes: phrases such as "no placeholder emitted"
% otherwise corrupt an honest not_available/disabled state.
switch state
    case {"observed","derived","config_only","disabled","placeholder","not_supported","not_available","not_exercised"}
        return;
    case "available"
        state = localInferAvailabilityFromSource(source);
    case "not_enabled"
        state = "disabled";
    otherwise
        state = "not_available";
end
end

function tf = localCoverageStateCountsTowardCoverage(state)
state = lower(strtrim(string(state)));
tf = state == "observed" | state == "derived";
end

function state = localInferAvailabilityFromSource(source)
source = lower(strtrim(localPortablePath(source)));
if strlength(source) == 0
    state = "config_only";
elseif startsWith(source, "reports/") || contains(source, "/reports/")
    state = "derived";
elseif startsWith(source, "meta/") || contains(source, "/meta/")
    state = "config_only";
elseif startsWith(source, "air_interface/") || contains(source, "/air_interface/") || ...
        startsWith(source, "control/") || contains(source, "/control/") || ...
        startsWith(source, "beamforming/") || contains(source, "/beamforming/") || ...
        startsWith(source, "harq/") || contains(source, "/harq/") || ...
        startsWith(source, "rf/") || contains(source, "/rf/")
    state = "observed";
else
    state = "observed";
end
end

function state = localRollupAvailabilityState(states)
states = lower(strtrim(string(states(:))));
states = states(strlength(states) > 0);
if isempty(states)
    state = "not_available";
    return;
end
precedence = ["observed","derived","config_only","disabled","placeholder","not_supported","not_exercised","not_available"];
for i = 1:numel(precedence)
    if any(states == precedence(i))
        state = precedence(i);
        return;
    end
end
state = "not_available";
end

function labels = localAvailabilityStateLabels(states)
states = string(states(:));
labels = states;
labels(states == "config_only") = "Config-only";
labels(states == "not_supported") = "Not supported";
labels(states == "not_available") = "Not available";
labels(states == "not_exercised") = "Not exercised";
labels(states == "derived") = "Derived";
labels(states == "observed") = "Observed";
labels(states == "disabled") = "Disabled";
labels(states == "placeholder") = "Placeholder";
end

function out = localAIConfigAvailability(ctx)
if localAIEnabled(ctx)
    out = "config_only";
elseif localShouldEmitAIAuditArtifacts(ctx)
    out = "disabled";
else
    out = "not_supported";
end
end

function out = localChannelSnapshotArtifactAvailability(ctx)
tables = {ctx.Tables.DL, ctx.Tables.UL, ctx.Tables.SRS, ctx.Tables.TRS, ctx.Tables.PBCH, ctx.Tables.PRACH};
hasData = false;
for i = 1:numel(tables)
    if istable(tables{i}) && ~isempty(tables{i})
        hasData = true;
        break;
    end
end
out = localDerivedOrPlaceholderAvailability(hasData);
end

function out = localConstellationArtifactAvailability(ctx)
T = localBuildEqualizedConstellationTable(ctx);
hasData = any(localConstellationLineageMask(T));
out = localDerivedOrPlaceholderAvailability(hasData);
end

function availability = localPHYSignalDiagnosticArtifactAvailability(ctx)
availability = struct( ...
    "Source", "not_available", ...
    "DL", "not_available", ...
    "UL", "not_available", ...
    "Reason", "source_csv_missing");
csvPath = fullfile(ctx.Layout.ReportCSVDir, "phy_signal_diagnostic_source.csv");
T = localReadOptionalTable(csvPath);
if ~(istable(T) && ~isempty(T))
    return;
end

requiredColumns = [ ...
    "SnapshotID","Panel","Series","PointIndex","XValue","YValue","Direction", ...
    "CurveConstruction","truth_status","SourceArtifact","Status"];
missingColumns = requiredColumns(~ismember(requiredColumns, string(T.Properties.VariableNames)));
if ~isempty(missingColumns)
    availability.Reason = "source_schema_missing:" + strjoin(missingColumns, "|");
    return;
end

truthStatus = lower(strtrim(string(T.truth_status)));
curveConstruction = lower(strtrim(string(T.CurveConstruction)));
sourceArtifact = lower(strtrim(string(T.SourceArtifact)));
rowStatus = lower(strtrim(string(T.Status)));
if any(ismissing(truthStatus) | truthStatus ~= "real_lls_evidence")
    availability.Reason = "truth_status_not_real_lls_evidence";
    return;
end
if any(ismissing(curveConstruction) | curveConstruction ~= "runtime_same_trial_phy_signal_snapshot")
    availability.Reason = "curve_construction_not_same_trial_runtime_snapshot";
    return;
end
if any(ismissing(sourceArtifact) | sourceArtifact ~= "runtime_phy_arrays_same_trial")
    availability.Reason = "source_artifact_not_runtime_phy_arrays_same_trial";
    return;
end
if any(ismissing(rowStatus) | rowStatus ~= "available")
    availability.Reason = "source_rows_not_available";
    return;
end

directions = upper(strtrim(string(T.Direction)));
if any(ismissing(directions) | ~ismember(directions, ["DL","UL"]))
    availability.Reason = "source_direction_invalid";
    return;
end

    requiredPanels = [ ...
        "time_domain","spectrum","channel_estimate","pre_equalization_re_cloud", ...
        "post_equalization_constellation","kpi"];
    tupleColumns = ["Frame","Slot","UEIndex","RNTI","TBId"];
reasons = strings(0, 1);
hasValidDirection = false;
for direction = ["DL","UL"]
    Td = T(directions == direction, :);
    if isempty(Td)
        reasons(end+1, 1) = lower(direction) + "_snapshot_missing"; %#ok<AGROW>
        continue;
    end
    snapshotIDs = strtrim(string(Td.SnapshotID));
    snapshotIDs = snapshotIDs(~ismissing(snapshotIDs) & strlength(snapshotIDs) > 0);
    if numel(unique(snapshotIDs, "stable")) ~= 1
        reasons(end+1, 1) = lower(direction) + "_snapshot_id_not_unique"; %#ok<AGROW>
        continue;
    end
    panels = lower(strtrim(string(Td.Panel)));
    if ~all(ismember(requiredPanels, unique(panels, "stable")))
        reasons(end+1, 1) = lower(direction) + "_essential_panel_missing"; %#ok<AGROW>
        continue;
    end
    tupleConsistent = all(ismember(tupleColumns, string(Td.Properties.VariableNames)));
    for i = 1:numel(tupleColumns)
        if ~tupleConsistent
            break;
        end
        tupleValues = strtrim(string(Td.(tupleColumns(i))));
        loweredTupleValues = lower(tupleValues);
        if any(ismissing(tupleValues) | strlength(tupleValues) == 0 | ...
                ismember(loweredTupleValues, ["nan","missing","<missing>"])) || ...
                numel(unique(tupleValues, "stable")) ~= 1
            tupleConsistent = false;
            break;
        end
    end
    if ~tupleConsistent
        reasons(end+1, 1) = lower(direction) + "_trial_tuple_not_unique"; %#ok<AGROW>
        continue;
    end

    hasValidDirection = true;
    imagePath = fullfile(ctx.Layout.ReportImageDir, char(lower(direction) + "_phy_signal_diagnostic.png"));
    imageInfo = dir(imagePath);
    if exist(imagePath, "file") == 2 && ~isempty(imageInfo) && double(imageInfo(1).bytes) > 0
        availability.(char(direction)) = "derived";
    else
        reasons(end+1, 1) = lower(direction) + "_image_missing"; %#ok<AGROW>
    end
end
if hasValidDirection
    availability.Source = "observed";
end
if isempty(reasons)
    availability.Reason = "";
else
    availability.Reason = strjoin(reasons, "|");
end
end

function out = localLLRHistogramArtifactAvailability(ctx)
hasData = ~isempty(localFiniteColumn(ctx.Tables.DL, "LLRMeanAbs")) || ...
    ~isempty(localFiniteColumn(ctx.Tables.UL, "LLRMeanAbs"));
out = localDerivedOrPlaceholderAvailability(hasData);
end

function out = localTrackingTraceArtifactAvailability(ctx)
T = localBuildTrackingTraceTable(ctx);
out = localDerivedOrPlaceholderAvailability(any(localUsableTrackingTraceRows(T)));
end

function out = localAIConfidenceTraceAvailability(ctx)
benchVal = localAIBenchmarkNumericValue(ctx.Tables.AIBenchmarks, ["MeasuredConfidenceScore","ObservedConfidenceScore","RuntimeMeasuredConfidenceScore","ConfidenceScore", ...
    "MeasuredFallbackRate","ObservedFallbackRate","RuntimeFallbackRate","FallbackRate"]);
metaVal = localAIMetadataValue(ctx.Tables.AIMetadata, ["MeasuredConfidenceScore","ObservedConfidenceScore","RuntimeMeasuredConfidenceScore","ConfidenceScore", ...
    "MeasuredFallbackRate","ObservedFallbackRate","RuntimeFallbackRate","FallbackRate"]);
if isfinite(double(benchVal)) || isfinite(double(metaVal))
    out = "derived";
elseif localAIEnabled(ctx)
    out = "config_only";
elseif localShouldEmitAIAuditArtifacts(ctx)
    out = "disabled";
else
    out = "not_supported";
end
end

function tf = localShouldEmitPlaceholderArtifacts(ctx)
% Strict/public result trees never contain unavailable-image cards.  A
% missing runtime relation is represented by an honest not_available row
% and no raster.  Debug-only profiles may opt in when strict visual
% publication is explicitly disabled.
tf = ~localStrictVisualArtifactMode(ctx) && ...
    localConfigFlag(ctx, ["output.emit_placeholder_artifacts"], false);
end

function tf = localStrictVisualArtifactMode(ctx)
tf = true;
if localConfigFlag(ctx, ["output.strict_visual_artifact_contract"], true)
    return;
end
tf = localConfigFlag(ctx, ["logging.strict_validation", "run_control.strict_mode", "validation.strict_mode"], false);
end

function tf = localShouldEmitAIAuditArtifacts(ctx)
tf = localAIEnabled(ctx) || ...
    (istable(ctx.Tables.AIMetadata) && ~isempty(ctx.Tables.AIMetadata)) || ...
    localConfigFlag(ctx, ["output.emit_disabled_audit_artifacts"], false);
end

function tf = localShouldWriteCategoryFile(ctx, cat, Tcat)
tf = true;
if string(cat.key) ~= "ai_ml_outputs"
    return;
end
if localShouldEmitAIAuditArtifacts(ctx)
    return;
end
if ~(istable(Tcat) && ~isempty(Tcat) && ismember("Availability", string(Tcat.Properties.VariableNames)))
    tf = false;
    return;
end
states = lower(strtrim(string(Tcat.Availability)));
states = states(strlength(states) > 0);
tf = ~all(states == "not_supported" | states == "disabled");
end

function out = localProbeMetricAvailability(ctx, metricKey)
metricKey = string(metricKey);
switch metricKey
    case {"beam_detection_probability","beam_index_hit_rate","top_k_beam_hit_rate", ...
            "beam_switch_latency","beam_misalignment_probability","beam_prediction_accuracy", ...
            "beam_refinement_convergence","beam_failure_rate","beam_management_overhead"}
        enabled = localConfigFlag(ctx, ["mimo.beam_sweep_enabled", "mimo_and_beam_management.beam_sweep_enabled"], false);
        out = localFeatureAvailability(enabled);
    case {"mtrp_beam_selection_gain","mtrp_gain"}
        trpCount = localConfigNumber(ctx, ["deployment_topology.num_trps", "mimo.trp_count"], 1);
        out = localFeatureAvailability(isfinite(trpCount) && trpCount > 1);
    case "prach_common_channel_clustering_energy_effect"
        enabled = localConfigFlag(ctx, ...
            ["signals_and_channels_common.common_signal_clustering.enable_flag", ...
            "energy_efficiency.common_channel_clustering_enabled", ...
            "random_access.beam_clustering_enabled", ...
            "random_access.ro_clustering_enabled"], false);
        out = localFeatureAvailability(enabled);
    case "bandwidth_adaptation_energy_effect"
        mode = lower(strtrim(localConfigString(ctx, ["energy_efficiency.bandwidth_adaptation_mode"], "none")));
        enabled = localConfigFlag(ctx, ["bandwidth_operation.dci_based_switching_enabled", "bandwidth_operation.configuration_profile_switching"], false) || ...
            ~(mode == "" || any(mode == ["none","disabled","off","false"]));
        out = localFeatureAvailability(enabled);
    case "race_to_sleep_gains"
        sleepModel = lower(strtrim(localConfigString(ctx, ["energy_efficiency.sleep_state_model"], "none")));
        out = localFeatureAvailability(~ismember(sleepModel, ["none","disabled","off","false",""]));
    otherwise
        out = "available";
end
end

function note = localAggregateAvailabilityNote(isAvailable, unavailableNote)
if isAvailable
    note = "";
else
    note = string(unavailableNote);
end
end

function tf = localHasAnyFiniteColumn(T, varNames)
tf = false;
if ~istable(T) || isempty(T)
    return;
end
varNames = string(varNames);
for i = 1:numel(varNames)
    if ismember(varNames(i), string(T.Properties.VariableNames))
        x = localCoerceNumericVector(T.(varNames(i)));
        if any(isfinite(x))
            tf = true;
            return;
        end
    end
end
end

function x = localFiniteColumn(T, varName)
x = [];
if ~istable(T) || isempty(T)
    return;
end
varNames = string(varName);
for i = 1:numel(varNames)
    if ismember(varNames(i), string(T.Properties.VariableNames))
        x = localCoerceNumericVector(T.(varNames(i)));
        x = x(isfinite(x));
        if ~isempty(x)
            return;
        end
    end
end
end

function x = localCoerceNumericVector(raw)
if iscell(raw)
    x = nan(numel(raw), 1);
    for i = 1:numel(raw)
        try
            x(i) = double(raw{i});
        catch
            x(i) = str2double(string(raw{i}));
        end
    end
    return;
end
try
    x = double(raw);
catch
    x = str2double(string(raw));
end
x = reshape(x, [], 1);
end

function [x, label] = localFirstFiniteColumn(tables, varNames, labels)
x = [];
label = "";
varNames = string(varNames);
labels = string(labels);
for i = 1:numel(tables)
    xi = localFiniteColumn(tables{i}, varNames);
    if ~isempty(xi)
        x = xi;
        label = labels(min(i, numel(labels)));
        return;
    end
end
end

function tf = localHasLatencySemanticData(ctx)
tf = ~isempty(localLatencyCDFFigureSeries(ctx));
end

function series = localLatencyCDFFigureSeries(ctx)
series = repmat(struct("Label", "", "Samples", zeros(0, 1)), 0, 1);
series = localAppendLatencySeries(series, "Radio TTI (AirInterfaceTTI_ms)", ...
    localCollectFiniteColumns({ctx.Tables.DL, ctx.Tables.UL, ctx.Tables.PDCCH}, "AirInterfaceTTI_ms"));
series = localAppendLatencySeries(series, "Radio observation (AirInterfaceObservation_ms)", ...
    localCollectFiniteColumns({ctx.Tables.PBCH, ctx.Tables.PRACH, ctx.Tables.SRS, ctx.Tables.TRS}, "AirInterfaceObservation_ms"));
series = localAppendLatencySeries(series, "Procedure delay (ProcedureDelay_ms)", localProcedureDelaySamplesForLatencyCDF(ctx));
series = localAppendLatencySeries(series, "Compute runtime (ComputeLatency_ms)", ...
    localCollectFiniteColumns({ctx.Tables.DL, ctx.Tables.UL, ctx.Tables.PDCCH, ctx.Tables.PBCH, ctx.Tables.PRACH, ctx.Tables.SRS, ctx.Tables.TRS}, "ComputeLatency_ms"));
end

function localWriteLatencyCDFContractSource(ctx, series)
if isempty(series)
    return;
end
T = localBuildLatencyCDFContractSourceTable(series);
if ~(istable(T) && ~isempty(T))
    return;
end
sixgr.util.ensureFolder(ctx.Layout.ReportCSVDir);
sixgr.util.csvWriteTable(fullfile(ctx.Layout.ReportCSVDir, "latency_cdf_plot.csv"), T);
end

function T = localBuildLatencyCDFContractSourceTable(series)
rows = repmat(struct( ...
    "latency_ms", NaN, ...
    "cdf_probability", NaN, ...
    "latency_series", "", ...
    "source_artifact_ref", "reports/csv/table_latency.csv", ...
    "latency_value_definition", "empirical CDF from real latency rows", ...
    "truth_status", "real_lls_evidence", ...
    "curve_construction", "empirical_cdf"), 0, 1);
for i = 1:numel(series)
    samples = sort(double(series(i).Samples(:)));
    samples = samples(isfinite(samples));
    n = numel(samples);
    for k = 1:n
        rows(end + 1, 1) = struct( ...
            "latency_ms", double(samples(k)), ...
            "cdf_probability", double(k) / max(double(n), 1), ...
            "latency_series", string(series(i).Label), ...
            "source_artifact_ref", "reports/csv/table_latency.csv", ...
            "latency_value_definition", "empirical CDF from real latency rows", ...
            "truth_status", "real_lls_evidence", ...
            "curve_construction", "empirical_cdf"); %#ok<AGROW>
    end
end
if isempty(rows)
    T = table();
else
    T = struct2table(rows, "AsArray", true);
end
end

function series = localAppendLatencySeries(series, label, samples)
samples = double(samples(:));
samples = samples(isfinite(samples));
if isempty(samples)
    return;
end
entry = struct("Label", string(label), "Samples", samples);
if isempty(series)
    series = entry;
else
    series(end + 1, 1) = entry; %#ok<AGROW>
end
end

function samples = localCollectFiniteColumns(tables, varName)
samples = zeros(0, 1);
for i = 1:numel(tables)
    xi = localFiniteColumn(tables{i}, varName);
    if ~isempty(xi)
        samples = [samples; xi(:)]; %#ok<AGROW>
    end
end
samples = samples(isfinite(samples));
end

function samples = localProcedureDelaySamplesForLatencyCDF(ctx)
samples = [ ...
    localFiniteColumn(ctx.Tables.InitialAccessLifecycle, ["AccessDelay_ms","ProcedureDelay_ms"]); ...
    localCollectFiniteColumns({ctx.Tables.DL, ctx.Tables.UL, ctx.Tables.PDCCH, ctx.Tables.PBCH, ...
        ctx.Tables.PBCHRecovery, ctx.Tables.CellSearch, ctx.Tables.PRACH, ctx.Tables.SRS, ctx.Tables.TRS}, "ProcedureDelay_ms"); ...
    localFiniteColumn(ctx.Tables.PRACH, "AccessDelay_ms")];
samples = samples(isfinite(samples));
end

function m = localMeanColumn(T, varName)
m = NaN;
x = localFiniteColumn(T, varName);
if isempty(x)
    return;
end
m = mean(x, "omitnan");
end

function col = localFirstPresentColumn(T, candidates)
col = "";
if ~istable(T)
    return;
end
vars = string(T.Properties.VariableNames);
candidates = string(candidates);
for i = 1:numel(candidates)
    if ismember(candidates(i), vars)
        col = candidates(i);
        return;
    end
end
end

function m = localMeanColumnFallback(T, candidates)
m = NaN;
candidates = string(candidates);
for i = 1:numel(candidates)
    m = localMeanColumn(T, candidates(i));
    if isfinite(m)
        return;
    end
end
end

function v = localMinColumn(T, varName)
v = NaN;
x = localFiniteColumn(T, varName);
if isempty(x)
    return;
end
v = min(x);
end

function v = localMaxColumn(T, varName)
v = NaN;
x = localFiniteColumn(T, varName);
if isempty(x)
    return;
end
v = max(x);
end

function bler = localBLERAtTargetSNR(sweepT, blerCol, targetSNR_dB)
bler = NaN;
if ~(istable(sweepT) && ~isempty(sweepT))
    return;
end
if ~(ismember("SNR_dB", string(sweepT.Properties.VariableNames)) && ismember(string(blerCol), string(sweepT.Properties.VariableNames)))
    return;
end
snr = double(sweepT.SNR_dB);
blerVec = double(sweepT.(string(blerCol)));
mask = isfinite(snr) & isfinite(blerVec);
if ~any(mask)
    return;
end
snr = snr(mask);
blerVec = blerVec(mask);
if isfinite(double(targetSNR_dB))
    [~, idx] = min(abs(snr - double(targetSNR_dB)));
else
    [~, idx] = min(blerVec);
end
bler = blerVec(idx);
end

function v = localSafeZero(x)
if isfinite(x)
    v = x;
else
    v = 0;
end
end

function localExportPlaceholderFigure(pathOut, plotTitle, message)
try
    if exist(pathOut, "file") == 2
        delete(pathOut);
    end
catch
end
sixgr.visual.writeUnavailablePlotCard(pathOut, plotTitle, message);
end

function localExportCDFFigure(pathOut, x, plotTitle, xLabel)
status = sixgr.visual.validatePlotData("cdf", x, x);
if status.PlotRenderStatus ~= "rendered"
    localExportPlaceholderFigure(pathOut, plotTitle, "Plot suppressed: " + status.PlotSuppressionReason + ".");
    return;
end
sixgr.util.ensureFolder(fileparts(pathOut));
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
x = sort(x(:));
y = (1:numel(x))' ./ numel(x);
plot(ax, x, y, "LineWidth", 1.25);
grid(ax, "on");
xlabel(ax, xLabel);
ylabel(ax, "CDF");
title(ax, plotTitle);
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function localExportLatencySemanticsCDFFigure(pathOut, series)
sampleCount = 0;
for i = 1:numel(series)
    sampleCount = sampleCount + numel(double(series(i).Samples(:)));
end
status = sixgr.visual.validatePlotData("cdf", (1:sampleCount).', ones(sampleCount, 1));
if status.PlotRenderStatus ~= "rendered"
    localExportPlaceholderFigure(pathOut, "Latency Semantics CDF", "Plot suppressed: " + status.PlotSuppressionReason + ".");
    return;
end
sixgr.util.ensureFolder(fileparts(pathOut));
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
for i = 1:numel(series)
    x = sort(double(series(i).Samples(:)));
    y = (1:numel(x))' ./ numel(x);
    plot(ax, x, y, "LineWidth", 1.25, ...
        "DisplayName", char(series(i).Label + " (n=" + string(numel(x)) + ")"));
end
grid(ax, "on");
xlabel(ax, "Time (ms)");
ylabel(ax, "CDF");
title(ax, "Latency Semantics CDF");
legend(ax, "Location", "best");
if ~any(string({series.Label}) == "ProcedureDelay_ms")
    text(ax, 0.98, 0.02, "ProcedureDelay_ms unavailable in this run", ...
        "Units", "normalized", "HorizontalAlignment", "right", "VerticalAlignment", "bottom");
end
sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
end

function localExportCoverageHeatmap(pathOut, plotTitle, message, coverageT, axisLabel)
if istable(coverageT) && ~isempty(coverageT)
    cats = unique(string(coverageT.CategoryCode), "stable");
    vals = zeros(numel(cats), 1);
    for i = 1:numel(cats)
        mask = coverageT.CategoryCode == cats(i);
        vals(i) = sum(mask & localCoverageStateCountsTowardCoverage(string(coverageT.Availability)));
    end
    fig = figure("Visible", "off", "Color", "w");
    cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
    ax = axes(fig);
    imagesc(ax, vals(:)');
    colormap(ax, parula);
    colorbar(ax);
    set(ax, 'YTick', 1, 'YTickLabel', {char(axisLabel)});
    set(ax, 'XTick', 1:numel(cats), 'XTickLabel', cellstr(cats));
    xtickangle(ax, 45);
    xlabel(ax, "KPI category");
    ylabel(ax, "Context");
    title(ax, plotTitle);
    sixgr.util.exportFigureArtifact(fig, pathOut, "Resolution", 160);
    return;
end
localExportPlaceholderFigure(pathOut, plotTitle, message);
end

function txt = localExistsText(path)
txt = string(exist(path, "file") == 2);
end

function [throughputVals, energyVals] = localEnergyThroughputPair(ctx)
throughputVals = [];
energyVals = [];
requiredVars = ["MetricKey","Entity","Statistic","Value"];
if ~(istable(ctx.Tables.RFEnergy) && ~isempty(ctx.Tables.RFEnergy) && all(ismember(requiredVars, string(ctx.Tables.RFEnergy.Properties.VariableNames))))
    return;
end
mask = string(ctx.Tables.RFEnergy.MetricKey) == "ue_energy_per_successful_bit" & ...
    string(ctx.Tables.RFEnergy.Entity) == "UE" & string(ctx.Tables.RFEnergy.Statistic) == "mean";
energyVals = double(ctx.Tables.RFEnergy.Value(mask));
energyVals = energyVals(isfinite(energyVals));
if isempty(energyVals)
    return;
end
dl = localMeanColumn(ctx.Tables.Sweep, "DL_Throughput_Mbps");
ul = localMeanColumn(ctx.Tables.Sweep, "UL_Throughput_Mbps");
throughputMean = mean([dl ul], "omitnan");
if ~(isfinite(throughputMean) && throughputMean > 0)
    energyVals = [];
    return;
end
throughputVals = repmat(double(throughputMean), numel(energyVals), 1);
end

function txt = localRelativeToRunFolder(pathIn, runFolder)
txt = localPortablePath(pathIn);
if strlength(txt) == 0
    return;
end
root = localPortablePath(runFolder);
if strlength(root) == 0
    return;
end
txt = regexprep(txt, '/+', '/');
root = regexprep(root, '/+', '/');
if strcmpi(txt, root)
    txt = ".";
    return;
end
rootPrefix = root + "/";
if startsWith(lower(txt), lower(rootPrefix))
    txt = extractAfter(txt, strlength(rootPrefix));
end
end

function txt = localPortablePath(p)
txt = replace(string(p), "\", "/");
end

function txt = localTableString(T, idx, varName)
txt = "";
if ~(istable(T) && idx >= 1 && idx <= height(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
txt = string(T.(varName)(idx));
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
end
