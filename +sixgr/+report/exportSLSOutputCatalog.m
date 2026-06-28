function out = exportSLSOutputCatalog(runFolder, cfg, results, runtimeSummary, environmentSummary)
%EXPORTSLSOUTPUTCATALOG Write a provenance-preserving SLS output bundle.
%
% The catalog is a derived, analysis-friendly view of the system-level run:
%   <runFolder>/
%     manifests/
%     summaries/
%     raw/
%     tables/
%     traces/
%     maps/
%     plots/
%     comparisons/
%     debug/

arguments
    runFolder {mustBeTextScalar}
    cfg struct
    results struct
    runtimeSummary struct
    environmentSummary struct
end

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
localEnsureCatalogDirs(layout);

persistCSV = logical(sixgr.util.structGet(cfg, "outputs.saveCSV", true));
persistMAT = logical(sixgr.util.structGet(cfg, "outputs.saveMAT", true));
persistFigures = localResolveSaveFigures(cfg);

scenarioID = localResolveScenarioID(cfg, runFolder);
[codeVersion, codeDetail] = localDetectCodeVersion();
manifest = localBuildSystemManifest(runFolder, cfg, results, runtimeSummary, environmentSummary, ...
    scenarioID, codeVersion, codeDetail, persistCSV, persistMAT, persistFigures);
defaultCfg = sixgr.config.defaultConfig();

inventory = repmat(struct( ...
    "Category", "", ...
    "ArtifactType", "", ...
    "RelativePath", "", ...
    "SourcePath", "", ...
    "Notes", ""), 0, 1);

artifacts = struct();

artifacts.SystemRunManifest = fullfile(layout.ManifestsDir, "system_run_manifest.json");
sixgr.util.jsonWrite(artifacts.SystemRunManifest, manifest);
inventory = localRecord(inventory, "manifests", "json", artifacts.SystemRunManifest, "", "System-level run manifest");

artifacts.ResolvedConfigJSON = fullfile(layout.ManifestsDir, "resolved_config.json");
sixgr.util.jsonWrite(artifacts.ResolvedConfigJSON, cfg);
inventory = localRecord(inventory, "manifests", "json", artifacts.ResolvedConfigJSON, "", "Resolved system-level config snapshot");

artifacts.ResolvedConfigYAML = fullfile(layout.ManifestsDir, "resolved_config.yaml");
sixgr.lls6g.config.writeYAML(artifacts.ResolvedConfigYAML, cfg);
inventory = localRecord(inventory, "manifests", "yaml", artifacts.ResolvedConfigYAML, "", "Resolved system-level config snapshot (YAML)");

artifacts.RuntimeSummaryJSON = fullfile(layout.ManifestsDir, "runtime_summary.json");
sixgr.util.jsonWrite(artifacts.RuntimeSummaryJSON, runtimeSummary);
inventory = localRecord(inventory, "manifests", "json", artifacts.RuntimeSummaryJSON, "", "Runtime summary");

artifacts.EnvironmentJSON = fullfile(layout.ManifestsDir, "environment.json");
sixgr.util.jsonWrite(artifacts.EnvironmentJSON, environmentSummary);
inventory = localRecord(inventory, "manifests", "json", artifacts.EnvironmentJSON, "", "Environment summary");

assumptionReport = localBuildAssumptionReport(cfg, defaultCfg, results, scenarioID);
artifacts.AssumptionReportYAML = fullfile(layout.ManifestsDir, "assumption_report.yaml");
sixgr.lls6g.config.writeYAML(artifacts.AssumptionReportYAML, assumptionReport);
inventory = localRecord(inventory, "manifests", "yaml", artifacts.AssumptionReportYAML, "", "Assumption report");

if persistCSV
    inventory = localWriteTableArtifact(inventory, fullfile(layout.SummariesDir, "system_kpi_summary.csv"), ...
        sixgr.util.structGet(results, "KPITable", table()), "", "summaries", "csv", "Primary system KPI summary");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.SummariesDir, "system_ue_summary.csv"), ...
        localGetNestedTable(results, "Details", "UESummary"), "", "summaries", "csv", "Per-UE summary");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.SummariesDir, "system_algo_processing.csv"), ...
        localGetNestedTable(results, "Details", "AlgoProcessing"), "", "summaries", "csv", "Algorithm processing counters");

    inventory = localWriteTableArtifact(inventory, fullfile(layout.TablesDir, "system_kpis.csv"), ...
        sixgr.util.structGet(results, "KPITable", table()), fullfile(runFolder, "csv", "system_kpis.csv"), ...
        "tables", "csv", "System KPI table");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TablesDir, "system_ue_summary.csv"), ...
        localGetNestedTable(results, "Details", "UESummary"), fullfile(runFolder, "csv", "system_ue_summary.csv"), ...
        "tables", "csv", "System UE summary table");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TablesDir, "system_algo_processing.csv"), ...
        localGetNestedTable(results, "Details", "AlgoProcessing"), fullfile(runFolder, "csv", "system_algo_processing.csv"), ...
        "tables", "csv", "System algorithm processing table");

    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_time_series.csv"), ...
        localGetNestedTable(results, "Details", "TimeSeries"), fullfile(runFolder, "csv", "system_time_series.csv"), ...
        "traces", "csv", "System time-series trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_mobility_control_series.csv"), ...
        localGetNestedTable(results, "Details", "MobilityControlSeries"), fullfile(runFolder, "csv", "system_mobility_control_series.csv"), ...
        "traces", "csv", "Mobility/measurement/beam/handover control loop trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_handover_events.csv"), ...
        localGetNestedTable(results, "Details", "HandoverEvents"), fullfile(runFolder, "csv", "system_handover_events.csv"), ...
        "traces", "csv", "Handover event trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_beam_events.csv"), ...
        localGetNestedTable(results, "Details", "BeamEvents"), fullfile(runFolder, "csv", "system_beam_events.csv"), ...
        "traces", "csv", "Beam-management event trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_scheduler_grants.csv"), ...
        localGetNestedTable(results, "Details", "SchedulerGrants"), fullfile(runFolder, "csv", "system_scheduler_grants.csv"), ...
        "traces", "csv", "Per-grant scheduler trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_harq_processes.csv"), ...
        localGetNestedTable(results, "Details", "HARQProcesses"), fullfile(runFolder, "csv", "system_harq_processes.csv"), ...
        "traces", "csv", "HARQ process trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_cell_load.csv"), ...
        localGetNestedTable(results, "Details", "CellLoad"), fullfile(runFolder, "csv", "system_cell_load.csv"), ...
        "traces", "csv", "Per-cell load trace");
    inventory = localWriteTableArtifact(inventory, fullfile(layout.TracesDir, "system_interference_detail.csv"), ...
        localGetNestedTable(results, "Details", "InterferenceDetail"), fullfile(runFolder, "csv", "system_interference_detail.csv"), ...
        "traces", "csv", "Per-UE interference detail trace");

    topoT = localBuildTopologySnapshot(results);
    inventory = localWriteTableArtifact(inventory, fullfile(layout.MapsDir, "system_topology_snapshot.csv"), topoT, "", ...
        "maps", "csv", "Serving topology snapshot with BS/UE positions");

    comparisonT = table("single_run", false, "No comparator configured for this SLS run.", ...
        'VariableNames', {'ComparisonScope','ComparatorAvailable','Reason'});
    inventory = localWriteTableArtifact(inventory, fullfile(layout.ComparisonsDir, "comparison_manifest.csv"), comparisonT, "", ...
        "comparisons", "csv", "Comparison availability manifest");
end

[inventory, geometryArtifacts] = localExportGeometryDeploymentArtifacts(inventory, layout, cfg, results);
artifacts.GeometryDeployment = geometryArtifacts;

if persistMAT
    srcMat = fullfile(runFolder, "mat", "system_results.mat");
    if exist(srcMat, "file") == 2
        dstMat = fullfile(layout.RawDir, "system_results.mat");
        localCopyFile(srcMat, dstMat);
        inventory = localRecord(inventory, "raw", "mat", dstMat, srcMat, "Raw MAT payload");
    end
end

srcReplay = fullfile(runFolder, "run_replay_system.m");
if exist(srcReplay, "file") == 2
    dstReplay = fullfile(layout.RawDir, "run_replay_system.m");
    localCopyFile(srcReplay, dstReplay);
    inventory = localRecord(inventory, "raw", "m", dstReplay, srcReplay, "Replay script");
end

srcLog = fullfile(runFolder, "logs", "run.log");
if exist(srcLog, "file") == 2
    dstLog = fullfile(layout.DebugDir, "system_run.log");
    localCopyFile(srcLog, dstLog);
    inventory = localRecord(inventory, "debug", "log", dstLog, srcLog, "System runner log");
end

if persistFigures
    figFiles = dir(fullfile(runFolder, "image", "*.png"));
    for i = 1:numel(figFiles)
        srcFig = fullfile(figFiles(i).folder, figFiles(i).name);
        dstFig = fullfile(layout.PlotsDir, figFiles(i).name);
        localCopyFile(srcFig, dstFig);
        inventory = localRecord(inventory, "plots", "png", dstFig, srcFig, "System-level plot");
    end
end

artifacts.SystemRunSummaryMD = fullfile(layout.SummariesDir, "system_run_summary.md");
localWriteSummaryMarkdown(artifacts.SystemRunSummaryMD, manifest, results, layout, runFolder);
inventory = localRecord(inventory, "summaries", "md", artifacts.SystemRunSummaryMD, "", "Human-readable SLS summary");

inventoryT = localInventoryTable(inventory);
artifacts.InventoryCSV = fullfile(layout.DebugDir, "output_catalog_inventory.csv");
sixgr.util.csvWriteTable(artifacts.InventoryCSV, inventoryT);

crossCheck = localBuildCrossCheckReport(cfg, defaultCfg, results, inventoryT, layout, persistCSV, persistMAT, persistFigures);
artifacts.CrossCheckReportJSON = fullfile(layout.ManifestsDir, "cross_check_report.json");
sixgr.util.jsonWrite(artifacts.CrossCheckReportJSON, crossCheck);
inventory = localRecord(inventory, "manifests", "json", artifacts.CrossCheckReportJSON, "", "Cross-check report (JSON)");

artifacts.CrossCheckReportMD = fullfile(layout.ManifestsDir, "cross_check_report.md");
localWriteCrossCheckMarkdown(artifacts.CrossCheckReportMD, crossCheck);
inventory = localRecord(inventory, "manifests", "md", artifacts.CrossCheckReportMD, "", "Cross-check report (Markdown)");

inventoryT = localInventoryTable(inventory);
sixgr.util.csvWriteTable(artifacts.InventoryCSV, inventoryT);

gitInfo = localDetectGitState();
configHash = localComputeStableHash(cfg);
modelHash = localComputeStableHash(localBuildModelHashInput(cfg, results));
resultHash = localComputeStableHash(localBuildResultHashInput(results, inventoryT, crossCheck));
mandatoryManifest = localBuildMandatoryRunManifest(runFolder, cfg, results, runtimeSummary, ...
    environmentSummary, scenarioID, gitInfo, configHash, modelHash, resultHash);

artifacts.RunManifestYAML = fullfile(layout.ManifestsDir, "run_manifest.yaml");
sixgr.lls6g.config.writeYAML(artifacts.RunManifestYAML, mandatoryManifest);
inventory = localRecord(inventory, "manifests", "yaml", artifacts.RunManifestYAML, "", "Mandatory run manifest");

manifest.MandatoryRunManifestPath = localPortablePath(artifacts.RunManifestYAML);
manifest.ConfigHash = char(string(configHash));
manifest.ModelHash = char(string(modelHash));
manifest.ResultHash = char(string(resultHash));
manifest.GitCommit = char(string(gitInfo.commit));
manifest.Branch = char(string(gitInfo.branch));
manifest.DirtyRepoFlag = logical(gitInfo.dirty);
manifest.SimulatorVersion = char(string(gitInfo.describe));
manifest.AssumptionReportPath = localPortablePath(artifacts.AssumptionReportYAML);
manifest.CrossCheckReportJSONPath = localPortablePath(artifacts.CrossCheckReportJSON);
manifest.CrossCheckReportMDPath = localPortablePath(artifacts.CrossCheckReportMD);
sixgr.util.jsonWrite(artifacts.SystemRunManifest, manifest);

inventoryT = localInventoryTable(inventory);
sixgr.util.csvWriteTable(artifacts.InventoryCSV, inventoryT);

out = struct();
out.Root = runFolder;
out.CatalogVersion = "1.0";
out.ScenarioID = char(string(scenarioID));
out.Manifest = manifest;
out.MandatoryRunManifest = mandatoryManifest;
out.AssumptionReport = assumptionReport;
out.CrossCheckReport = crossCheck;
out.Artifacts = artifacts;
out.Inventory = inventoryT;
end

function localEnsureCatalogDirs(layout)
dirs = { ...
    layout.ManifestsDir, layout.SummariesDir, layout.RawDir, layout.TablesDir, ...
    layout.TracesDir, layout.MapsDir, layout.PlotsDir, layout.ComparisonsDir, ...
    layout.DebugDir};
for i = 1:numel(dirs)
    sixgr.util.ensureFolder(dirs{i});
end
end

function inventory = localWriteTableArtifact(inventory, dst, T, src, category, artifactType, notes)
if ~(istable(T) && ~isempty(T))
    return;
end
sixgr.util.csvWriteTable(dst, T);
inventory = localRecord(inventory, category, artifactType, dst, src, notes);
end

function localCopyFile(src, dst)
sixgr.util.ensureDir(dst);
if exist(dst, "file") == 2
    delete(dst);
end
copyfile(src, dst);
end

function T = localGetNestedTable(results, parentField, childField)
T = table();
if ~isstruct(results) || ~isfield(results, parentField)
    return;
end
parent = results.(parentField);
if ~isstruct(parent) || ~isfield(parent, childField)
    return;
end
value = parent.(childField);
if istable(value)
    T = value;
end
end

function T = localBuildTopologySnapshot(results)
T = table();
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
ue = sixgr.util.structGet(details, "UEFinal", struct());
servingCell = sixgr.util.structGet(details, "ServingCell", []);

rows = repmat(struct( ...
    "NodeType", "", ...
    "NodeID", NaN, ...
    "CellID", NaN, ...
    "X_m", NaN, ...
    "Y_m", NaN, ...
    "ServingCell", NaN), 0, 1);

bsPos = sixgr.util.structGet(layout, "bs.pos_m", []);
if ~isempty(bsPos)
    nBS = size(bsPos, 1);
    for i = 1:nBS
        rows(end+1,1) = struct("NodeType", "BS", "NodeID", double(i), "CellID", double(i), ... %#ok<AGROW>
            "X_m", double(bsPos(i,1)), "Y_m", double(bsPos(i,2)), "ServingCell", double(i));
    end
end

uePos = sixgr.util.structGet(ue, "pos_m", []);
if ~isempty(uePos)
    nUE = size(uePos, 1);
    finalServing = NaN(nUE,1);
    if ~isempty(servingCell)
        finalServing = double(servingCell(end,:)).';
    end
    for i = 1:nUE
        rows(end+1,1) = struct("NodeType", "UE", "NodeID", double(i), "CellID", NaN, ... %#ok<AGROW>
            "X_m", double(uePos(i,1)), "Y_m", double(uePos(i,2)), "ServingCell", double(finalServing(i)));
    end
end

if ~isempty(rows)
    T = struct2table(rows);
end
end

function [inventory, artifacts] = localExportGeometryDeploymentArtifacts(inventory, layout, cfg, results)
artifacts = struct();

siteT = localBuildSiteTable(cfg, results);
artifacts.SitesCSV = fullfile(layout.TablesDir, "sites.csv");
sixgr.util.csvWriteTable(artifacts.SitesCSV, siteT);
inventory = localRecord(inventory, "tables", "csv", artifacts.SitesCSV, "", "Site geometry table");

sectorT = localBuildSectorTable(cfg, results);
artifacts.SectorsCSV = fullfile(layout.TablesDir, "sectors.csv");
sixgr.util.csvWriteTable(artifacts.SectorsCSV, sectorT);
inventory = localRecord(inventory, "tables", "csv", artifacts.SectorsCSV, "", "Sector geometry table");

trpT = localBuildTRPTable(cfg, results);
artifacts.TRPsCSV = fullfile(layout.TablesDir, "trps.csv");
sixgr.util.csvWriteTable(artifacts.TRPsCSV, trpT);
inventory = localRecord(inventory, "tables", "csv", artifacts.TRPsCSV, "", "TRP geometry table");

ueT = localBuildUETable(cfg, results);
artifacts.UEsCSV = fullfile(layout.TablesDir, "ues.csv");
sixgr.util.csvWriteTable(artifacts.UEsCSV, ueT);
inventory = localRecord(inventory, "tables", "csv", artifacts.UEsCSV, "", "UE inventory table");

trajT = localBuildUETrajectoryTrace(results);
artifacts.UETrajectoriesParquet = fullfile(layout.TracesDir, "ue_trajectories.parquet");
localWriteParquetTable(artifacts.UETrajectoriesParquet, trajT);
inventory = localRecord(inventory, "traces", "parquet", artifacts.UETrajectoriesParquet, "", "UE trajectory trace");

artifacts.SiteLayoutPNG = fullfile(layout.MapsDir, "site_layout.png");
localWriteGeometryFigure(artifacts.SiteLayoutPNG, @(ax) localPlotSiteLayout(ax, cfg, results));
inventory = localRecord(inventory, "maps", "png", artifacts.SiteLayoutPNG, "", "Site layout map");

artifacts.AttachmentMapPNG = fullfile(layout.MapsDir, "attachment_map.png");
localWriteGeometryFigure(artifacts.AttachmentMapPNG, @(ax) localPlotAttachmentMap(ax, results));
inventory = localRecord(inventory, "maps", "png", artifacts.AttachmentMapPNG, "", "Final attachment map");

artifacts.HandoverBoundariesPNG = fullfile(layout.MapsDir, "handover_boundaries.png");
localWriteGeometryFigure(artifacts.HandoverBoundariesPNG, @(ax) localPlotHandoverBoundaries(ax, results));
inventory = localRecord(inventory, "maps", "png", artifacts.HandoverBoundariesPNG, "", "Handover boundary map");

artifacts.ServingBeamMapPNG = fullfile(layout.MapsDir, "serving_beam_map.png");
localWriteGeometryFigure(artifacts.ServingBeamMapPNG, @(ax) localPlotServingBeamMap(ax, results));
inventory = localRecord(inventory, "maps", "png", artifacts.ServingBeamMapPNG, "", "Serving-beam map");
end

function T = localBuildSiteTable(cfg, results)
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
sitePos = double(sixgr.util.structGet(layout, "sites.pos_m", zeros(0,3)));
nSites = size(sitePos, 1);

site_id = (1:nSites).';
sector_id = nan(nSites, 1);
trp_id = nan(nSites, 1);
x_m = localColumnOrNaN(sitePos, 1);
y_m = localColumnOrNaN(sitePos, 2);
z_m = localColumnOrNaN(sitePos, 3);
layer_id = ones(nSites, 1);
carrier_id = ones(nSites, 1);
boresight_deg = nan(nSites, 1);
mechanical_tilt_deg = nan(nSites, 1);
electrical_tilt_deg = nan(nSites, 1);
max_tx_power_dbm = localSiteMaxPower(layout, nSites);
antenna_model_id = repmat(localResolveBSAntennaModelID(cfg), nSites, 1);
array_geometry_id = repmat(localResolveBSArrayGeometryID(cfg), nSites, 1);
indoor_outdoor = repmat(localResolveLayoutIndoorOutdoor(layout), nSites, 1);
sleep_capable_flag = repmat(localResolveSleepCapableFlag(cfg), nSites, 1);

T = table(site_id, sector_id, trp_id, x_m, y_m, z_m, layer_id, carrier_id, ...
    boresight_deg, mechanical_tilt_deg, electrical_tilt_deg, max_tx_power_dbm, ...
    antenna_model_id, array_geometry_id, indoor_outdoor, sleep_capable_flag);
T.SiteID = site_id;
T.X_m = x_m;
T.Y_m = y_m;
T.Z_m = z_m;
T.MaxTxPower_dBm = max_tx_power_dbm;
end

function T = localBuildSectorTable(cfg, results)
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
siteId = double(sixgr.util.structGet(layout, "bs.siteId", nan(size(bsPos,1),1)));
sectorId = double(sixgr.util.structGet(layout, "bs.sectorId", (1:size(bsPos,1)).'));
cellId = double(sixgr.util.structGet(layout, "bs.cellId", ...
    (siteId(:) - 1) .* max(1, double(sixgr.util.structGet(layout, "nSectors", 1))) + sectorId(:)));
pci = double(sixgr.util.structGet(layout, "bs.pci", cellId(:)));
nCellId = double(sixgr.util.structGet(layout, "bs.nCellId", cellId(:)));
az = double(sixgr.util.structGet(layout, "bs.azim_deg", nan(size(bsPos,1),1)));
txP = double(sixgr.util.structGet(layout, "bs.txPower_dBm", nan(size(bsPos,1),1)));
n = size(bsPos, 1);

site_id = siteId(:);
sector_id = sectorId(:);
cell_id = cellId(:);
pci_id = pci(:);
n_cell_id = nCellId(:);
trp_id = (1:n).';
x_m = localColumnOrNaN(bsPos, 1);
y_m = localColumnOrNaN(bsPos, 2);
z_m = localColumnOrNaN(bsPos, 3);
layer_id = ones(n, 1);
carrier_id = ones(n, 1);
boresight_deg = az(:);
mechanical_tilt_deg = repmat(localResolveMechanicalTiltDeg(cfg), n, 1);
electrical_tilt_deg = repmat(localResolveElectricalTiltDeg(cfg), n, 1);
max_tx_power_dbm = txP(:);
antenna_model_id = repmat(localResolveBSAntennaModelID(cfg), n, 1);
array_geometry_id = repmat(localResolveBSArrayGeometryID(cfg), n, 1);
indoor_outdoor = repmat(localResolveLayoutIndoorOutdoor(layout), n, 1);
sleep_capable_flag = repmat(localResolveSleepCapableFlag(cfg), n, 1);

T = table(site_id, sector_id, cell_id, pci_id, n_cell_id, trp_id, x_m, y_m, z_m, layer_id, carrier_id, ...
    boresight_deg, mechanical_tilt_deg, electrical_tilt_deg, max_tx_power_dbm, ...
    antenna_model_id, array_geometry_id, indoor_outdoor, sleep_capable_flag);
T.SiteID = site_id;
T.SectorID = sector_id;
T.CellID = cell_id;
T.PCI = pci_id;
T.NCellID = n_cell_id;
T.TRPID = trp_id;
T.Azimuth_deg = boresight_deg;
T.X_m = x_m;
T.Y_m = y_m;
T.Z_m = z_m;
T.TxPower_dBm = max_tx_power_dbm;
end

function T = localBuildTRPTable(cfg, results)
T = localBuildSectorTable(cfg, results);
end

function T = localBuildUETable(cfg, results)
details = sixgr.util.structGet(results, "Details", struct());
ue0 = sixgr.util.structGet(details, "UEInitial", struct());
trafficClass = string(sixgr.util.structGet(details, "TrafficClass", strings(0,1)));

ue_id = double(sixgr.util.structGet(ue0, "id", zeros(0,1)));
pos0 = double(sixgr.util.structGet(ue0, "pos_m", zeros(numel(ue_id), 3)));
indoor = logical(sixgr.util.structGet(ue0, "indoor", false(numel(ue_id),1)));
speed_kmh = double(sixgr.util.structGet(ue0, "speed_kmh", zeros(numel(ue_id),1)));
heading = double(sixgr.util.structGet(ue0, "heading_deg", zeros(numel(ue_id),1)));
servingCell = double(sixgr.util.structGet(ue0, "drop_cell_id", nan(numel(ue_id),1)));
serving_cell_id = servingCell(:);
n = numel(ue_id);

if numel(trafficClass) ~= n
    trafficClass = repmat(string(sixgr.util.structGet(cfg, "traffic.model", "default")), n, 1);
end

ue_type = localResolveUEType(indoor, speed_kmh);
service_profile = trafficClass(:);
start_x_m = localColumnOrNaN(pos0, 1);
start_y_m = localColumnOrNaN(pos0, 2);
start_z_m = localColumnOrNaN(pos0, 3);
indoor_outdoor_state = localIndoorOutdoorState(indoor);
speed_profile = localResolveSpeedProfile(cfg, speed_kmh);
power_class_dbm = repmat(localResolveUEPowerClassDBm(cfg), n, 1);
antenna_model_id = repmat(localResolveUEAntennaModelID(cfg), n, 1);
ai_capability_class = repmat(localResolveAICapabilityClass(cfg), n, 1);
mobility_profile_id = repmat(localResolveMobilityProfileID(cfg), n, 1);

T = table(ue_id, ue_type, service_profile, start_x_m, start_y_m, start_z_m, ...
    indoor_outdoor_state, speed_profile, heading, serving_cell_id, power_class_dbm, antenna_model_id, ...
    ai_capability_class, mobility_profile_id);
T.UEID = ue_id;
T.X_m = start_x_m;
T.Y_m = start_y_m;
T.Z_m = start_z_m;
T.Indoor = indoor;
T.Speed_kmh = speed_kmh;
T.Heading_deg = heading;
T.ServingCellID = serving_cell_id;
end

function T = localBuildUETrajectoryTrace(results)
details = sixgr.util.structGet(results, "Details", struct());
posX = double(sixgr.util.structGet(details, "UEPosX_m", zeros(0,0)));
posY = double(sixgr.util.structGet(details, "UEPosY_m", zeros(size(posX))));
posZ = double(sixgr.util.structGet(details, "UEPosZ_m", zeros(size(posX))));
heading = double(sixgr.util.structGet(details, "UEHeading_deg", zeros(size(posX))));
servingCell = double(sixgr.util.structGet(details, "ServingCell", zeros(size(posX))));
servingBeam = double(sixgr.util.structGet(details, "ServingBeamIndex", zeros(size(posX))));
tti_s = double(sixgr.util.structGet(details, "TTI_s", 0));
ue0 = sixgr.util.structGet(details, "UEInitial", struct());
ue_id_list = double(sixgr.util.structGet(ue0, "id", (1:size(posX,2)).'));
speed_kmh_list = double(sixgr.util.structGet(ue0, "speed_kmh", zeros(numel(ue_id_list),1)));
indoor = logical(sixgr.util.structGet(ue0, "indoor", false(numel(ue_id_list),1)));

nTTI = size(posX, 1);
K = size(posX, 2);
if nTTI == 0 || K == 0
    T = table([], [], [], [], [], [], [], [], [], [], ...
        'VariableNames', {'t','ue_id','x_m','y_m','z_m','speed_kmh','heading_deg', ...
        'indoor_outdoor_state','serving_cell_id','serving_beam_id'});
    return;
end

t = repmat(((0:nTTI-1).' .* tti_s), K, 1);
ue_id = repelem(ue_id_list(:), nTTI, 1);
x_m = reshape(posX, [], 1);
y_m = reshape(posY, [], 1);
z_m = reshape(posZ, [], 1);
speed_kmh = repelem(speed_kmh_list(:), nTTI, 1);
heading_deg = reshape(heading, [], 1);
indoor_outdoor_state = repelem(localIndoorOutdoorState(indoor), nTTI, 1);
serving_cell_id = reshape(servingCell, [], 1);
serving_beam_id = reshape(servingBeam, [], 1);

T = table(t, ue_id, x_m, y_m, z_m, speed_kmh, heading_deg, indoor_outdoor_state, ...
    serving_cell_id, serving_beam_id);
end

function localWriteParquetTable(filePath, T)
sixgr.util.ensureFolder(fileparts(filePath));
parquetwrite(filePath, T);
end

function localWriteGeometryFigure(filePath, plotFn)
sixgr.util.ensureFolder(fileparts(filePath));
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig); %#ok<LAXES>
hold(ax, "on");
grid(ax, "on");
axis(ax, "equal");
plotFn(ax);
exportgraphics(fig, filePath, "Resolution", 140);
end

function localPlotSiteLayout(ax, cfg, results)
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
sitePos = double(sixgr.util.structGet(layout, "sites.pos_m", zeros(0,3)));
bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
az = double(sixgr.util.structGet(layout, "bs.azim_deg", nan(size(bsPos,1),1)));

if ~isempty(sitePos)
    scatter(ax, sitePos(:,1), sitePos(:,2), 70, "k", "filled", "DisplayName", "Sites");
end
if ~isempty(bsPos)
    scatter(ax, bsPos(:,1), bsPos(:,2), 36, "b", "filled", "DisplayName", "Sectors/TRPs");
    localPlotBoresightArrows(ax, bsPos(:,1:2), az, 40);
end

xlabel(ax, "x_m");
ylabel(ax, "y_m");
title(ax, sprintf("Site Layout | %s | %s", string(localResolveScenarioID(cfg, "")), string(localResolveLayoutIndoorOutdoor(layout))));
legend(ax, "Location", "best");
end

function localPlotAttachmentMap(ax, results)
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
ue = sixgr.util.structGet(details, "UEFinal", struct());
servingCell = double(sixgr.util.structGet(details, "ServingCell", zeros(0,0)));
sitePos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
uePos = double(sixgr.util.structGet(ue, "pos_m", zeros(0,3)));

if ~isempty(sitePos)
    scatter(ax, sitePos(:,1), sitePos(:,2), 60, "k", "^", "filled", "DisplayName", "Cells/TRPs");
end
if ~isempty(uePos)
    finalServing = ones(size(uePos,1),1);
    if ~isempty(servingCell)
        finalServing = double(servingCell(end,:)).';
    end
    scatter(ax, uePos(:,1), uePos(:,2), 20, finalServing, "filled", "DisplayName", "UE final attachment");
end

xlabel(ax, "x_m");
ylabel(ax, "y_m");
title(ax, "Attachment Map");
colorbar(ax);
end

function localPlotHandoverBoundaries(ax, results)
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
ue = sixgr.util.structGet(details, "UEFinal", struct());
ho = localGetNestedTable(results, "Details", "HandoverEvents");
bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
uePos = double(sixgr.util.structGet(ue, "pos_m", zeros(0,3)));

bsXYUnique = zeros(0,2);
if ~isempty(bsPos)
    bsXYUnique = unique(bsPos(:,1:2), "rows", "stable");
end
if size(bsXYUnique, 1) >= 3
    voronoi(ax, bsXYUnique(:,1), bsXYUnique(:,2), "k:");
end
if ~isempty(bsPos)
    scatter(ax, bsPos(:,1), bsPos(:,2), 60, "k", "^", "filled", "DisplayName", "Cells/TRPs");
end
if ~isempty(uePos)
    scatter(ax, uePos(:,1), uePos(:,2), 12, [0.7 0.7 0.7], "filled", "DisplayName", "UEs");
end
if istable(ho) && ~isempty(ho) && ~isempty(uePos)
    idx = unique(min(max(round(double(ho.UE)), 1), size(uePos,1)));
    scatter(ax, uePos(idx,1), uePos(idx,2), 28, "r", "filled", "DisplayName", "UEs with HO events");
end

xlabel(ax, "x_m");
ylabel(ax, "y_m");
title(ax, "Handover Boundaries");
legend(ax, "Location", "best");
end

function localPlotServingBeamMap(ax, results)
details = sixgr.util.structGet(results, "Details", struct());
layout = sixgr.util.structGet(details, "Layout", struct());
ue = sixgr.util.structGet(details, "UEFinal", struct());
beamHist = double(sixgr.util.structGet(details, "ServingBeamIndex", zeros(0,0)));
bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
az = double(sixgr.util.structGet(layout, "bs.azim_deg", nan(size(bsPos,1),1)));
uePos = double(sixgr.util.structGet(ue, "pos_m", zeros(0,3)));

if ~isempty(bsPos)
    scatter(ax, bsPos(:,1), bsPos(:,2), 60, "k", "^", "filled", "DisplayName", "Cells/TRPs");
    localPlotBoresightArrows(ax, bsPos(:,1:2), az, 35);
end
if ~isempty(uePos)
    finalBeam = ones(size(uePos,1),1);
    if ~isempty(beamHist)
        finalBeam = double(beamHist(end,:)).';
    end
    scatter(ax, uePos(:,1), uePos(:,2), 20, finalBeam, "filled", "DisplayName", "UE final serving beam");
end

xlabel(ax, "x_m");
ylabel(ax, "y_m");
title(ax, "Serving Beam Map");
colorbar(ax);
end

function localPlotBoresightArrows(ax, xy, az_deg, len_m)
if isempty(xy)
    return;
end
u = len_m .* cosd(az_deg(:));
v = len_m .* sind(az_deg(:));
quiver(ax, xy(:,1), xy(:,2), u, v, 0, "Color", [0.2 0.2 0.8], "LineWidth", 1.0, ...
    "MaxHeadSize", 0.8, "DisplayName", "Boresight");
end

function power = localSiteMaxPower(layout, nSites)
power = nan(nSites, 1);
bsSiteId = double(sixgr.util.structGet(layout, "bs.siteId", zeros(0,1)));
bsTxPower = double(sixgr.util.structGet(layout, "bs.txPower_dBm", zeros(0,1)));
for i = 1:nSites
    idx = bsSiteId == i;
    if any(idx)
        power(i) = max(bsTxPower(idx), [], "omitnan");
    end
end
end

function indoorOutdoor = localResolveLayoutIndoorOutdoor(layout)
layoutType = lower(string(sixgr.util.structGet(layout, "layoutType", "outdoor")));
if contains(layoutType, "indoor") || contains(layoutType, "inh")
    indoorOutdoor = "indoor";
else
    indoorOutdoor = "outdoor";
end
end

function tf = localResolveSleepCapableFlag(cfg)
tf = logical(sixgr.util.structGet(cfg, "system.sleep.enable", false));
end

function out = localResolveBSAntennaModelID(cfg)
out = string(sixgr.util.structGet(cfg, "scenario.bs.antennaModelID", ""));
if strlength(out) == 0
    out = "bs_default_panel";
end
end

function out = localResolveBSArrayGeometryID(cfg)
tx = double(sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", sixgr.util.structGet(cfg, "phy.nTxAnt", 1)));
rx = double(sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", sixgr.util.structGet(cfg, "phy.nRxAnt", 1)));
out = "bs_tx" + string(tx) + "_rx" + string(rx);
end

function out = localResolveUEAntennaModelID(cfg)
out = string(sixgr.util.structGet(cfg, "scenario.ue.antennaModelID", ""));
if strlength(out) == 0
    tx = double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1));
    rx = double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", 1));
    out = "ue_tx" + string(tx) + "_rx" + string(rx);
end
end

function out = localResolveUEType(indoor, speed_kmh)
n = numel(speed_kmh);
out = strings(n, 1);
for i = 1:n
    if indoor(i)
        out(i) = "indoor_ue";
    elseif speed_kmh(i) >= 60
        out(i) = "vehicular_ue";
    elseif speed_kmh(i) > 0
        out(i) = "pedestrian_ue";
    else
        out(i) = "stationary_ue";
    end
end
end

function out = localIndoorOutdoorState(indoor)
out = repmat("outdoor", numel(indoor), 1);
out(logical(indoor(:))) = "indoor";
end

function out = localResolveSpeedProfile(cfg, speed_kmh)
model = string(sixgr.util.structGet(cfg, "scenario.mobility.model", "randomWaypoint"));
out = model + "_" + string(round(speed_kmh(:), 3)) + "kmh";
end

function out = localResolveUEPowerClassDBm(cfg)
out = double(sixgr.util.structGet(cfg, "scenario.ue.txPower_dBm", 23));
end

function out = localResolveAICapabilityClass(cfg)
if logical(sixgr.util.structGet(cfg, "ai.enabled", false))
    out = "ai_capable";
else
    out = "non_ai";
end
end

function out = localResolveMobilityProfileID(cfg)
out = string(sixgr.util.structGet(cfg, "scenario.mobility.model", "randomWaypoint"));
end

function v = localResolveMechanicalTiltDeg(cfg)
v = double(sixgr.util.structGet(cfg, "scenario.bs.mechanicalTilt_deg", 0));
end

function v = localResolveElectricalTiltDeg(cfg)
v = double(sixgr.util.structGet(cfg, "scenario.bs.electricalTilt_deg", 0));
end

function col = localColumnOrNaN(M, idx)
if size(M, 2) >= idx
    col = double(M(:,idx));
else
    col = nan(size(M,1), 1);
end
end

function manifest = localBuildSystemManifest(runFolder, cfg, results, runtimeSummary, environmentSummary, ...
    scenarioID, codeVersion, codeDetail, persistCSV, persistMAT, persistFigures)
details = sixgr.util.structGet(results, "Details", struct());
manifest = struct();
manifest.GeneratedUTC = localUTCStamp();
manifest.RunFolder = char(string(runFolder));
manifest.ScenarioID = char(string(scenarioID));
manifest.RunMode = char(string(sixgr.util.structGet(cfg, "run.mode", "system")));
manifest.RandomSeed = double(sixgr.util.structGet(cfg, "run.seed", 1));
manifest.StrictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
manifest.ExecutionBackend = char(string(sixgr.util.structGet(details, "ExecutionBackend", "UNKNOWN")));
manifest.PHYMode = char(string(sixgr.util.structGet(details, "PHYMode", "UNKNOWN")));
manifest.WaveformBacked = logical(sixgr.util.structGet(details, "WaveformBacked", false));
manifest.WaveformPHYActive = logical(sixgr.util.structGet(details, "WaveformPHYActive", manifest.WaveformBacked));
manifest.ProxyPHYActive = logical(sixgr.util.structGet(details, "ProxyPHYActive", ~manifest.WaveformBacked));
manifest.FallbackUsed = logical(sixgr.util.structGet(details, "FallbackUsed", manifest.ProxyPHYActive));
manifest.NumCells = localPrimaryMetric(results, "NumCells");
manifest.NumUE = localPrimaryMetric(results, "NumUE");
manifest.SaveCSV = persistCSV;
manifest.SaveMAT = persistMAT;
manifest.SaveFigures = persistFigures;
manifest.CodeVersion = char(string(codeVersion));
manifest.CodeDetail = char(string(codeDetail));
manifest.StartedUTC = char(string(sixgr.util.structGet(runtimeSummary, "StartedUTC", "")));
manifest.CompletedUTC = char(string(sixgr.util.structGet(runtimeSummary, "CompletedUTC", "")));
manifest.ElapsedSeconds = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
manifest.WarningCount = double(sixgr.util.structGet(runtimeSummary, "WarningCount", 0));
manifest.ErrorCount = double(numel(sixgr.util.structGet(results, "Errors", strings(0,1))));
manifest.Environment = environmentSummary;
manifest.CatalogDirectories = struct( ...
    "manifests", "manifests", ...
    "summaries", "summaries", ...
    "raw", "raw", ...
    "tables", "tables", ...
    "traces", "traces", ...
    "maps", "maps", ...
    "plots", "plots", ...
    "comparisons", "comparisons", ...
    "debug", "debug");
end

function manifest = localBuildMandatoryRunManifest(runFolder, cfg, results, runtimeSummary, ...
    environmentSummary, scenarioID, gitInfo, configHash, modelHash, resultHash)
[campaignFolder, runLeaf] = fileparts(runFolder);
[~, campaignName] = fileparts(campaignFolder);
runID = char(string(scenarioID) + "_" + string(extractBefore(string(runtimeSummary.StartedUTC), "Z")) + "_" + string(runLeaf));
simTime = localResolveSimulationTime(results);
deps = localCollectDependencyVersions();
pyInfo = localDetectPythonVersion();
compilerInfo = localDetectCompilerVersions();
hostInfo = localDetectHostIdentity(environmentSummary);
baseSeed = double(sixgr.util.structGet(cfg, "run.seed", 1));

manifest = struct();
manifest.run_id = localSanitizeToken(runID, "system_run");
manifest.scenario_name = char(string(scenarioID));
manifest.campaign_name = char(string(campaignName));
manifest.timestamp_start_utc = char(string(runtimeSummary.StartedUTC));
manifest.timestamp_end_utc = char(string(runtimeSummary.CompletedUTC));
manifest.wall_clock_runtime_s = double(runtimeSummary.ElapsedSeconds);
manifest.simulation_time_s = double(simTime);
manifest.simulator_version = char(string(gitInfo.describe));
manifest.git_commit = char(string(gitInfo.commit));
manifest.branch = char(string(gitInfo.branch));
manifest.dirty_repo_flag = logical(gitInfo.dirty);
manifest.hostname = char(string(hostInfo.hostname));
manifest.container_id = char(string(hostInfo.container_id));
manifest.python = pyInfo;
manifest.compiler = compilerInfo;
manifest.dependency_versions = deps;
manifest.random_seeds = struct( ...
    "base_seed", baseSeed, ...
    "layout_drop_seed", baseSeed, ...
    "channel_model_seed", baseSeed + 17, ...
    "system_phy_seed", baseSeed + 31);
manifest.config_hash = char(string(configHash));
manifest.model_hash = char(string(modelHash));
manifest.result_hash = char(string(resultHash));
end

function scenarioID = localResolveScenarioID(cfg, runFolder)
scenarioID = string(sixgr.util.structGet(cfg, "meta.scenario_id", ""));
if strlength(scenarioID) == 0
    scenarioID = string(sixgr.util.structGet(cfg, "scenario.name", ""));
end
if strlength(scenarioID) == 0
    scenarioID = string(sixgr.util.structGet(cfg, "run.profile", ""));
end
if strlength(scenarioID) == 0
    [~, leaf] = fileparts(runFolder);
    scenarioID = string(leaf);
end
end

function tf = localResolveSaveFigures(cfg)
if isfield(cfg, "outputs") && isfield(cfg.outputs, "saveFigures")
    tf = logical(cfg.outputs.saveFigures);
elseif isfield(cfg, "outputs") && isfield(cfg.outputs, "saveFIG")
    tf = logical(cfg.outputs.saveFIG);
else
    tf = false;
end
end

function [codeVersion, detail] = localDetectCodeVersion()
repoRoot = localRepoRoot();
codeVersion = "unknown";
detail = "git_unavailable";
cmdHash = sprintf('git -C "%s" rev-parse --short HEAD', repoRoot);
[s1, out1] = system(cmdHash);
if s1 ~= 0
    return;
end
hash = strtrim(out1);
cmdBranch = sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot);
[~, out2] = system(cmdBranch);
branch = strtrim(out2);
codeVersion = "git:" + string(hash);
detail = "branch=" + string(branch) + "; hash=" + string(hash);
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(here)));
end

function txt = localUTCStamp()
dt = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd HH:mm:ss");
txt = char(replace(string(dt), " ", "T") + "Z");
end

function localWriteSummaryMarkdown(filePath, manifest, results, layout, runFolder)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# System-Level Run Summary\n\n");
fprintf(fid, "- Scenario ID: `%s`\n", string(manifest.ScenarioID));
fprintf(fid, "- Run folder: `%s`\n", string(manifest.RunFolder));
fprintf(fid, "- Execution backend: `%s`\n", string(manifest.ExecutionBackend));
fprintf(fid, "- PHY mode: `%s`\n", string(manifest.PHYMode));
fprintf(fid, "- Waveform-backed: `%s`\n", string(manifest.WaveformBacked));
fprintf(fid, "- Random seed: `%d`\n", double(manifest.RandomSeed));
fprintf(fid, "- Code version: `%s`\n", string(manifest.CodeVersion));
fprintf(fid, "- Elapsed seconds: `%.3f`\n", double(manifest.ElapsedSeconds));
fprintf(fid, "- Output catalog: `manifests/`, `summaries/`, `raw/`, `tables/`, `traces/`, `maps/`, `plots/`, `comparisons/`, `debug/`\n");
fprintf(fid, "\n## Primary Tables\n\n");
fprintf(fid, "- `tables/system_kpis.csv`\n");
fprintf(fid, "- `tables/system_ue_summary.csv`\n");
fprintf(fid, "- `traces/system_time_series.csv`\n");
fprintf(fid, "- `traces/system_scheduler_grants.csv`\n");
fprintf(fid, "- `traces/system_harq_processes.csv`\n");
fprintf(fid, "- `maps/system_topology_snapshot.csv`\n");
fprintf(fid, "\n## Existing Root Artifacts\n\n");
fprintf(fid, "- `%s`\n", localPortablePath(fullfile(runFolder, "csv", "system_kpis.csv")));
fprintf(fid, "- `%s`\n", localPortablePath(fullfile(runFolder, "mat", "system_results.mat")));
fprintf(fid, "- `%s`\n", localPortablePath(fullfile(runFolder, "image")));
if isfield(results, "Errors") && ~isempty(results.Errors)
    fprintf(fid, "\n## Runtime Notes\n\n");
    for i = 1:numel(results.Errors)
        fprintf(fid, "- `%s`\n", string(results.Errors(i)));
    end
end
fprintf(fid, "\n## Catalog Paths\n\n");
fprintf(fid, "- Manifests: `%s`\n", localPortablePath(layout.ManifestsDir));
fprintf(fid, "- Summaries: `%s`\n", localPortablePath(layout.SummariesDir));
fprintf(fid, "- Raw: `%s`\n", localPortablePath(layout.RawDir));
fprintf(fid, "- Tables: `%s`\n", localPortablePath(layout.TablesDir));
fprintf(fid, "- Traces: `%s`\n", localPortablePath(layout.TracesDir));
fprintf(fid, "- Maps: `%s`\n", localPortablePath(layout.MapsDir));
fprintf(fid, "- Plots: `%s`\n", localPortablePath(layout.PlotsDir));
fprintf(fid, "- Comparisons: `%s`\n", localPortablePath(layout.ComparisonsDir));
fprintf(fid, "- Debug: `%s`\n", localPortablePath(layout.DebugDir));
end

function report = localBuildAssumptionReport(cfg, defaultCfg, results, scenarioID)
specs = localAssumptionSpecs();
entries = cell(numel(specs), 1);
for i = 1:numel(specs)
    spec = specs(i);
    value = sixgr.util.structGet(cfg, spec.Path, []);
    defaultValue = sixgr.util.structGet(defaultCfg, spec.Path, []);
    sourceTag = localAssumptionSourceTag(value, defaultValue);
    classTag = localAssumptionClassification(spec.Path, sourceTag);
    entries{i} = struct( ...
        "parameter", spec.Path, ...
        "value", value, ...
        "units", spec.Units, ...
        "source_tag", sourceTag, ...
        "assumption_class", spec.AssumptionClass, ...
        "applicability", spec.Applicability, ...
        "baseline_status", classTag, ...
        "classification", classTag);
end

report = struct();
report.report_name = "assumption_report";
report.generated_utc = localUTCStamp();
report.scenario_name = char(string(scenarioID));
report.method = "important-parameter inventory with default-vs-override heuristic for legacy merged SLS config";
report.parameters = entries;
report.runtime_notes = struct( ...
    "execution_backend", char(string(sixgr.util.structGet(results, "Details.ExecutionBackend", ""))), ...
    "phy_mode", char(string(sixgr.util.structGet(results, "Details.PHYMode", ""))), ...
    "waveform_backed", logical(sixgr.util.structGet(results, "Details.WaveformBacked", false)), ...
    "waveform_phy_active", logical(sixgr.util.structGet(results, "Details.WaveformPHYActive", false)), ...
    "proxy_phy_active", logical(sixgr.util.structGet(results, "Details.ProxyPHYActive", true)), ...
    "fallback_used", logical(sixgr.util.structGet(results, "Details.FallbackUsed", true)));
end

function specs = localAssumptionSpecs()
specs = [ ...
    localAssumptionSpec("run.seed", "count", "execution_control", "always") ...
    localAssumptionSpec("run.shortRun", "boolean", "execution_control", "always") ...
    localAssumptionSpec("run.strictMode", "boolean", "execution_control", "always") ...
    localAssumptionSpec("outputs.saveCSV", "boolean", "artifact_policy", "always") ...
    localAssumptionSpec("outputs.saveMAT", "boolean", "artifact_policy", "always") ...
    localAssumptionSpec("outputs.saveFigures", "boolean", "artifact_policy", "always") ...
    localAssumptionSpec("system.phyBackend", "mode", "execution_model", "always") ...
    localAssumptionSpec("scenario.nUE", "count", "topology", "always") ...
    localAssumptionSpec("scenario.layout.nSites", "count", "topology", "always") ...
    localAssumptionSpec("scenario.layout.nSectorsPerSite", "count", "topology", "always") ...
    localAssumptionSpec("scenario.mobility.enable", "boolean", "mobility", "when system run enabled") ...
    localAssumptionSpec("scenario.mobility.model", "mode", "mobility", "when mobility enabled") ...
    localAssumptionSpec("scenario.mobility.speed_kmh", "km/h", "mobility", "when mobility enabled") ...
    localAssumptionSpec("channel.bandwidth_Hz", "Hz", "channel", "always") ...
    localAssumptionSpec("channel.fc_Hz", "Hz", "channel", "always") ...
    localAssumptionSpec("channel.model", "mode", "channel", "always") ...
    localAssumptionSpec("channel.awgnOnly", "boolean", "channel", "always") ...
    localAssumptionSpec("channel.dopplerHz", "Hz", "channel", "when fading enabled") ...
    localAssumptionSpec("phy.carrier.SubcarrierSpacing", "kHz", "waveform", "always") ...
    localAssumptionSpec("phy.duplex.mode", "mode", "waveform", "always") ...
    localAssumptionSpec("mac.scheduler.type", "mode", "scheduler", "always") ...
    localAssumptionSpec("system.ulSinrOffset_dB", "dB", "link_budget", "UL enabled") ...
    localAssumptionSpec("system.measurement.periodSlots", "slots", "measurement", "measurement enabled") ...
    localAssumptionSpec("system.beam.enable", "boolean", "beam_management", "beam management configured") ...
    localAssumptionSpec("system.beam.updatePeriod_slots", "slots", "beam_management", "beam management enabled") ...
    localAssumptionSpec("system.beam.numBeams", "count", "beam_management", "beam management enabled") ...
    localAssumptionSpec("system.beam.maxGain_dB", "dB", "beam_management", "beam management enabled") ...
    localAssumptionSpec("system.handover.enable", "boolean", "handover", "multi-cell") ...
    localAssumptionSpec("system.handover.a3Offset_dB", "dB", "handover", "handover enabled") ...
    localAssumptionSpec("system.handover.timeToTrigger_slots", "slots", "handover", "handover enabled") ...
    localAssumptionSpec("scenario.bs.noiseFigure_dB", "dB", "rf", "always") ...
    localAssumptionSpec("phy.pdsch.numLayers", "count", "mimo", "DL enabled") ...
    localAssumptionSpec("phy.pusch.numLayers", "count", "mimo", "UL enabled") ...
    ];
end

function spec = localAssumptionSpec(pathValue, units, assumptionClass, applicability)
spec = struct("Path", pathValue, "Units", units, ...
    "AssumptionClass", assumptionClass, "Applicability", applicability);
end

function sourceTag = localAssumptionSourceTag(value, defaultValue)
if isequaln(value, defaultValue)
    sourceTag = "resolved_matches_catalog_default";
else
    sourceTag = "resolved_override";
end
end

function classTag = localAssumptionClassification(pathValue, sourceTag)
pathValue = string(pathValue);
if sourceTag == "resolved_matches_catalog_default"
    classTag = "lab-default";
elseif startsWith(pathValue, "outputs.")
    classTag = "optional";
elseif any(pathValue == ["channel.bandwidth_Hz","channel.fc_Hz","phy.carrier.SubcarrierSpacing","phy.duplex.mode","channel.model"])
    classTag = "baseline";
else
    classTag = "agreed";
end
end

function report = localBuildCrossCheckReport(cfg, defaultCfg, results, inventoryT, layout, persistCSV, persistMAT, persistFigures)
implemented = { ...
    localFeatureRow("system_kpi_export", "tables/system_kpis.csv", "implemented"), ...
    localFeatureRow("system_time_series_trace", "traces/system_time_series.csv", "implemented"), ...
    localFeatureRow("scheduler_grant_trace", "traces/system_scheduler_grants.csv", "implemented"), ...
    localFeatureRow("harq_process_trace", "traces/system_harq_processes.csv", "implemented"), ...
    localFeatureRow("topology_snapshot", "maps/system_topology_snapshot.csv", "implemented"), ...
    localFeatureRow("runtime_and_environment_manifests", "manifests/run_manifest.yaml", "implemented") ...
    };

partial = { ...
    localFeatureRow("assumption_source_provenance", "manifests/assumption_report.yaml", ...
        "default-vs-override heuristic because direct SLS uses legacy merged config"), ...
    localFeatureRow("unused_config_field_audit", "manifests/cross_check_report.json", ...
        "namespace-level heuristic, not dynamic field-touch tracing"), ...
    localFeatureRow("comparison_outputs", "comparisons/comparison_manifest.csv", ...
        "single-run comparison manifest only unless an external comparator campaign is supplied") ...
    };

unsupported = { ...
    localFeatureRow("exact_field_level_config_source_chain", "", "not implemented for legacy direct SLS path"), ...
    localFeatureRow("built_in_multi_run_delta_tables", "", "not produced by single direct system run without comparator inputs") ...
    };

unusedFields = localUnusedConfigFieldSummary(cfg, defaultCfg);
hiddenConstants = localHiddenConstants();
missingOutputs = localMissingManifestOutputs(layout, persistCSV, persistMAT, persistFigures);
notApplicable = localNotApplicableOutputs(results, persistFigures);
nonBaseline = localNonBaselineAssumptions(cfg, defaultCfg);

report = struct();
report.generated_utc = localUTCStamp();
report.implemented_features = implemented;
report.partial_features = partial;
report.unsupported_features = unsupported;
report.unused_config_fields = unusedFields;
report.hidden_constants = hiddenConstants;
report.missing_outputs = missingOutputs;
report.non_baseline_assumptions_used = nonBaseline;
report.not_applicable_outputs = notApplicable;
report.output_inventory_path = localPortablePath(fullfile(layout.DebugDir, "output_catalog_inventory.csv"));
report.persist_flags = struct("save_csv", persistCSV, "save_mat", persistMAT, "save_figures", persistFigures);
report.inventory_summary = struct("artifact_count", height(inventoryT));
end

function row = localFeatureRow(name, evidence, status)
row = struct("name", name, "evidence", evidence, "status", status);
end

function unused = localUnusedConfigFieldSummary(cfg, ~)
topFields = string(fieldnames(cfg));
usedTop = ["run","outputs","scenario","system","mac","channel","phy","traffic","paths"];
unusedTop = topFields(~ismember(topFields, usedTop));
unused = cell(numel(unusedTop),1);
for i = 1:numel(unusedTop)
    unused{i} = struct("field", char(unusedTop(i)), "reason", "top-level namespace not consumed by direct SystemLevelRunner/exportSLSOutputCatalog path");
end
if isempty(unused)
    unused = {};
end
end

function items = localHiddenConstants()
items = { ...
    struct("name","channel_model_seed_offset","value",17,"units","seed_offset","source","SystemLevelRunner.m"), ...
    struct("name","system_phy_seed_offset","value",31,"units","seed_offset","source","SystemLevelRunner.m"), ...
    struct("name","zone_center_quantile","value",0.20,"units","fraction","source","SystemLevelRunner.m"), ...
    struct("name","zone_edge_quantile","value",0.80,"units","fraction","source","SystemLevelRunner.m"), ...
    struct("name","short_run_tti_cap","value",40,"units","TTI","source","SystemLevelRunner.m") ...
    };
end

function items = localMissingManifestOutputs(layout, persistCSV, persistMAT, persistFigures)
spec = { ...
    fullfile(layout.ManifestsDir, "run_manifest.yaml"), ...
    fullfile(layout.ManifestsDir, "resolved_config.yaml"), ...
    fullfile(layout.ManifestsDir, "assumption_report.yaml"), ...
    fullfile(layout.ManifestsDir, "cross_check_report.md"), ...
    fullfile(layout.ManifestsDir, "cross_check_report.json") ...
    };
if persistCSV
    spec{end+1} = fullfile(layout.TablesDir, "system_kpis.csv"); %#ok<AGROW>
end
if persistMAT
    spec{end+1} = fullfile(layout.RawDir, "system_results.mat"); %#ok<AGROW>
end
if persistFigures
    spec{end+1} = fullfile(layout.PlotsDir, "system_sinr_cdf.png"); %#ok<AGROW>
end
missing = {};
for i = 1:numel(spec)
    if exist(spec{i}, "file") ~= 2 && ~isfolder(spec{i})
        missing{end+1,1} = struct("path", localPortablePath(spec{i}), "reason", "required artifact not found on disk"); %#ok<AGROW>
    end
end
items = missing;
end

function items = localNotApplicableOutputs(results, persistFigures)
items = {};
if ~persistFigures
    items{end+1,1} = struct("output", "plots/*", "reason", "outputs.saveFigures=false"); %#ok<AGROW>
end
if isempty(localGetNestedTable(results, "Details", "BeamEvents"))
    items{end+1,1} = struct("output", "beam-event-derived comparison curves", "reason", "no beam-event rows in this run"); %#ok<AGROW>
end
items{end+1,1} = struct("output", "baseline_candidate_delta_tables", "reason", "single direct SLS run has no comparator"); %#ok<AGROW>
end

function items = localNonBaselineAssumptions(cfg, defaultCfg)
paths = ["system.phyBackend","mac.scheduler.type","system.beam.enable","system.handover.enable","scenario.mobility.enable"];
items = {};
for i = 1:numel(paths)
    value = sixgr.util.structGet(cfg, paths(i), []);
    defaultValue = sixgr.util.structGet(defaultCfg, paths(i), []);
    if ~isequaln(value, defaultValue)
        items{end+1,1} = struct("field", char(paths(i)), "value", value, "default_value", defaultValue); %#ok<AGROW>
    end
end
end

function localWriteCrossCheckMarkdown(filePath, report)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Cross-Check Report\n\n");
fprintf(fid, "Generated UTC: `%s`\n\n", string(report.generated_utc));
localWriteCrossCheckSection(fid, "Implemented Features", report.implemented_features);
localWriteCrossCheckSection(fid, "Partial Features", report.partial_features);
localWriteCrossCheckSection(fid, "Unsupported Features", report.unsupported_features);
localWriteCrossCheckSection(fid, "Unused Config Fields", report.unused_config_fields);
localWriteCrossCheckSection(fid, "Hidden Constants", report.hidden_constants);
localWriteCrossCheckSection(fid, "Missing Outputs", report.missing_outputs);
localWriteCrossCheckSection(fid, "Non-Baseline Assumptions Used", report.non_baseline_assumptions_used);
localWriteCrossCheckSection(fid, "Not-Applicable Outputs", report.not_applicable_outputs);
end

function localWriteCrossCheckSection(fid, titleText, items)
fprintf(fid, "## %s\n\n", titleText);
if isempty(items)
    fprintf(fid, "- none\n\n");
    return;
end
for i = 1:numel(items)
    item = items{i};
    try
        txt = jsonencode(item);
    catch
        txt = evalc("disp(item)");
    end
    fprintf(fid, "- `%s`\n", strtrim(txt));
end
fprintf(fid, "\n");
end

function gitInfo = localDetectGitState()
[codeVersion, detail] = localDetectCodeVersion();
gitInfo = struct();
gitInfo.describe = char(string(codeVersion));
gitInfo.commit = "";
gitInfo.branch = "";
gitInfo.dirty = false;
if startsWith(string(codeVersion), "git:")
    gitInfo.commit = char(extractAfter(string(codeVersion), "git:"));
end
detailStr = string(detail);
if contains(detailStr, "branch=")
    gitInfo.branch = char(extractBefore(extractAfter(detailStr, "branch="), ";"));
end
repoRoot = localRepoRoot();
cmdDirty = sprintf('git -C "%s" status --porcelain', repoRoot);
[s, out] = system(cmdDirty);
if s == 0
    gitInfo.dirty = strlength(strtrim(string(out))) > 0;
end
end

function deps = localCollectDependencyVersions()
try
    V = ver;
    deps = cell(numel(V),1);
    for i = 1:numel(V)
        deps{i} = struct("name", V(i).Name, "version", V(i).Version);
    end
catch
    deps = {struct("name","MATLAB","version",version)};
end
end

function pyInfo = localDetectPythonVersion()
pyInfo = struct("status", "not_available", "version", "", "executable", "");
try
    p = pyenv;
    pyInfo.status = "available";
    pyInfo.version = char(string(p.Version));
    pyInfo.executable = char(string(p.Executable));
catch
    try
        v = pyversion; %#ok<DUPF>
        pyInfo.status = "available";
        pyInfo.version = char(string(v.Version));
        pyInfo.executable = char(string(v.Executable));
    catch
    end
end
end

function compilerInfo = localDetectCompilerVersions()
compilerInfo = struct();
compilerInfo.c = localCompilerConfig("C");
compilerInfo.cpp = localCompilerConfig("C++");
end

function info = localCompilerConfig(lang)
info = struct("language", lang, "status", "not_available", "name", "", "version", "", "details", "");
try
    cfg = mex.getCompilerConfigurations(lang, "Selected");
    if ~isempty(cfg)
        cfg = cfg(1);
        info.status = "available";
        info.name = char(string(cfg.Name));
        info.version = char(string(cfg.Version));
        info.details = char(string(cfg.Details));
    end
catch
end
end

function hostInfo = localDetectHostIdentity(environmentSummary)
hostInfo = struct();
hostInfo.hostname = char(string(sixgr.util.structGet(environmentSummary, "Hostname", getenv("COMPUTERNAME"))));
containerID = getenv("CONTAINER_ID");
if strlength(string(containerID)) == 0
    containerID = getenv("HOSTNAME");
end
hostInfo.container_id = char(string(containerID));
end

function simTime = localResolveSimulationTime(results)
simTime = localPrimaryMetric(results, "SimDuration_s");
if ~isfinite(simTime)
    tti_s = double(sixgr.util.structGet(results, "Details.TTI_s", NaN));
    numTTI = localPrimaryMetric(results, "NumTTI");
    if isfinite(tti_s) && isfinite(numTTI)
        simTime = tti_s * numTTI;
    end
end
end

function in = localBuildModelHashInput(cfg, results)
in = struct();
in.run_mode = sixgr.util.structGet(cfg, "run.mode", "");
in.system = sixgr.util.structGet(cfg, "system", struct());
in.channel = sixgr.util.structGet(cfg, "channel", struct());
in.phy = sixgr.util.structGet(cfg, "phy", struct());
in.scenario = sixgr.util.structGet(cfg, "scenario", struct());
in.mac = sixgr.util.structGet(cfg, "mac", struct());
in.execution_backend = sixgr.util.structGet(results, "Details.ExecutionBackend", "");
in.phy_mode = sixgr.util.structGet(results, "Details.PHYMode", "");
in.waveform_phy_active = logical(sixgr.util.structGet(results, "Details.WaveformPHYActive", false));
in.proxy_phy_active = logical(sixgr.util.structGet(results, "Details.ProxyPHYActive", true));
in.fallback_used = logical(sixgr.util.structGet(results, "Details.FallbackUsed", true));
end

function in = localBuildResultHashInput(results, inventoryT, crossCheck)
in = struct();
in.kpi = sixgr.util.structGet(results, "KPITable", table());
in.ue_summary = localGetNestedTable(results, "Details", "UESummary");
in.time_series = localGetNestedTable(results, "Details", "TimeSeries");
in.scheduler_grants = localGetNestedTable(results, "Details", "SchedulerGrants");
in.harq_processes = localGetNestedTable(results, "Details", "HARQProcesses");
in.inventory = inventoryT;
in.cross_check = crossCheck;
end

function h = localComputeStableHash(data)
try
    txt = jsonencode(data);
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(uint8(txt));
    d = typecast(md.digest(), "uint8");
    h = lower(reshape(dec2hex(d, 2).', 1, []));
catch
    h = "fallback_" + string(sum(double(uint8(evalc("disp(data)")))));
end
h = char(string(h));
end

function token = localSanitizeToken(value, fallback)
token = string(value);
token = strtrim(token);
token = regexprep(token, "[^A-Za-z0-9._-]+", "_");
token = regexprep(token, "_{2,}", "_");
token = regexprep(token, "^_+|_+$", "");
if strlength(token) == 0
    token = string(fallback);
end
token = char(token);
end

function T = localInventoryTable(records)
if isempty(records)
    T = table(string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), ...
        'VariableNames', {'Category','ArtifactType','RelativePath','SourcePath','Notes'});
    return;
end
T = struct2table(records);
end

function p = localPortablePath(pIn)
p = string(pIn);
p = replace(p, "\", "/");
end

function inventory = localRecord(inventory, category, artifactType, pathValue, sourcePath, notes)
rec = struct();
rec.Category = string(category);
rec.ArtifactType = string(artifactType);
rec.RelativePath = string(localPortablePath(pathValue));
rec.SourcePath = string(localPortablePath(sourcePath));
rec.Notes = string(notes);
inventory(end+1,1) = rec; %#ok<AGROW>
end

function value = localPrimaryMetric(results, varName)
value = NaN;
K = sixgr.util.structGet(results, "KPITable", table());
if ~(istable(K) && ~isempty(K) && ismember(varName, string(K.Properties.VariableNames)))
    return;
end
value = double(K.(varName)(1));
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:report:exportSLSOutputCatalog:BadPath", ...
        "Path inputs must be char vectors or string scalars.");
end
end
