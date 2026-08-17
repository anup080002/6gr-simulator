function out = exportLiveGeometryArtifacts(layout, scfg, cfg)
%EXPORTLIVEGEOMETRYARTIFACTS Publish configured live topology consistently.
%
% The live WebGUI geometry tables are deterministic projections of the
% resolved scenario layout and UE drop.  They are configuration-derived
% evidence, not measured propagation truth, and are published under both
% the canonical live-table names and the legacy compatibility names.

backend = lower(strtrim(string(localScenarioGet(scfg, ...
    "output.backend", sixgr.util.structGet(cfg, "outputs.storageBackend", "filesystem")))));
if ~ismember(backend, ["filesystem","mysql_web"])
    error("sixgr:truth:UnsupportedLiveGeometryBackend", ...
        "Live geometry export does not support output backend '%s'.", backend);
end
out = struct("Enabled", true, "Written", false, "OutputBackend", backend, ...
    "Paths", strings(0, 1), "EvidenceClass", "CONFIGURED_GEOMETRY_PROJECTION");

rngState = rng; %#ok<RNGR>
cleanupRng = onCleanup(@() rng(rngState)); %#ok<NASGU>
seed = double(sixgr.util.structGet(cfg, "run.seed", ...
    sixgr.util.structGet(cfg, "run.randomSeed", 1)));
rng(seed, "twister");

try
    scenarioId = string(localScenarioGet(scfg, "meta.scenario_id", ...
        sixgr.util.structGet(cfg, "meta.scenarioID", "")));
    scenarioName = string(sixgr.util.structGet(cfg, "scenario.name", scenarioId));
    scenarioLayout = sixgr.scenario.generateLayout(cfg, scenarioName);
    ue = sixgr.scenario.dropUEs(cfg, scenarioLayout, scenarioName);
    [siteT, sectorT, trpT, ueT] = localBuildProjectedGeometryTables(scenarioLayout, ue);
catch cause
    failure = MException("sixgr:truth:LiveGeometryExportFailed", ...
        "Unable to derive live geometry from the resolved scenario: %s", cause.message);
    failure = addCause(failure, cause);
    throwAsCaller(failure);
end

names = ["sites.csv","sectors.csv","trps.csv","ues.csv", ...
    "live_site_table.csv","live_sector_table.csv", ...
    "live_trp_table.csv","live_ue_table.csv"];
tables = {siteT, sectorT, trpT, ueT, siteT, sectorT, trpT, ueT};
paths = strings(numel(names), 1);
for index = 1:numel(names)
    paths(index) = string(fullfile(layout.ReportCSVDir, names(index)));
    sixgr.util.csvWriteTable(paths(index), tables{index});
end
out.Written = true;
out.Paths = paths;
out.SiteCount = height(siteT);
out.SectorCount = height(sectorT);
out.TRPCount = height(trpT);
out.UECount = height(ueT);
end

function [siteT, sectorT, trpT, ueT] = localBuildProjectedGeometryTables(layoutStruct, ue)
anchorLat = 19.122164;
anchorLon = 72.999217;
anchorLabel = "Reliance Corporate Park, Ghansoli, Navi Mumbai";
coordMode = "configured_local_xy_projected_to_default_map_anchor";

sitePos = localPositionMatrix(sixgr.util.structGet(layoutStruct, "sites.pos_m", zeros(0,3)), "sites.pos_m");
siteId = double(sixgr.util.structGet(layoutStruct, "sites.id", (1:size(sitePos,1)).'));
[siteLat, siteLon] = sixgr.util.projectLocalXYToGeo(sitePos(:,1), sitePos(:,2), anchorLat, anchorLon);
siteT = table(siteId(:), sitePos(:,1), sitePos(:,2), sitePos(:,3), siteLat(:), siteLon(:), ...
    repmat(string(coordMode), numel(siteId), 1), repmat(string(anchorLabel), numel(siteId), 1), ...
    'VariableNames', {'SiteID','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

bsPos = localPositionMatrix(sixgr.util.structGet(layoutStruct, "bs.pos_m", zeros(0,3)), "bs.pos_m");
siteRef = double(sixgr.util.structGet(layoutStruct, "bs.siteId", nan(size(bsPos,1),1)));
sectorId = double(sixgr.util.structGet(layoutStruct, "bs.sectorId", (1:size(bsPos,1)).'));
cellId = double(sixgr.util.structGet(layoutStruct, "bs.cellId", ...
    (siteRef(:) - 1) .* max(1, double(sixgr.util.structGet(layoutStruct, "nSectors", 1))) + sectorId(:)));
pci = double(sixgr.util.structGet(layoutStruct, "bs.pci", cellId(:)));
nCellId = double(sixgr.util.structGet(layoutStruct, "bs.nCellId", cellId(:)));
az = double(sixgr.util.structGet(layoutStruct, "bs.azim_deg", nan(size(bsPos,1),1)));
txP = double(sixgr.util.structGet(layoutStruct, "bs.txPower_dBm", nan(size(bsPos,1),1)));
[bsLat, bsLon] = sixgr.util.projectLocalXYToGeo(bsPos(:,1), bsPos(:,2), anchorLat, anchorLon);
sectorT = table(siteRef(:), sectorId(:), cellId(:), pci(:), nCellId(:), az(:), ...
    bsPos(:,1), bsPos(:,2), bsPos(:,3), bsLat(:), bsLon(:), ...
    repmat(string(coordMode), numel(sectorId), 1), repmat(string(anchorLabel), numel(sectorId), 1), ...
    'VariableNames', {'SiteID','SectorID','CellID','PCI','NCellID','Azimuth_deg','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

trpId = (1:size(bsPos,1)).';
trpT = table(trpId(:), siteRef(:), sectorId(:), cellId(:), pci(:), nCellId(:), az(:), txP(:), ...
    bsPos(:,1), bsPos(:,2), bsPos(:,3), bsLat(:), bsLon(:), ...
    repmat(string(coordMode), numel(trpId), 1), repmat(string(anchorLabel), numel(trpId), 1), ...
    'VariableNames', {'TRPID','SiteID','SectorID','CellID','PCI','NCellID','Azimuth_deg','TxPower_dBm','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

uePos = localPositionMatrix(sixgr.util.structGet(ue, "pos_m", zeros(0,3)), "ue.pos_m");
ueId = double(sixgr.util.structGet(ue, "id", (1:size(uePos,1)).'));
ueIndoor = logical(sixgr.util.structGet(ue, "indoor", false(size(uePos,1),1)));
ueSpeed = double(sixgr.util.structGet(ue, "speed_kmh", nan(size(uePos,1),1)));
ueHeading = double(sixgr.util.structGet(ue, "heading_deg", nan(size(uePos,1),1)));
servingCellId = double(sixgr.util.structGet(ue, "drop_cell_id", nan(size(uePos,1),1)));
[ueLat, ueLon] = sixgr.util.projectLocalXYToGeo(uePos(:,1), uePos(:,2), anchorLat, anchorLon);
ueT = table(ueId(:), uePos(:,1), uePos(:,2), uePos(:,3), ueLat(:), ueLon(:), ...
    ueIndoor(:), ueSpeed(:), ueHeading(:), servingCellId(:), ...
    repmat(string(coordMode), numel(ueId), 1), repmat(string(anchorLabel), numel(ueId), 1), ...
    'VariableNames', {'UEID','X_m','Y_m','Z_m','Lat','Lon','Indoor','Speed_kmh','Heading_deg','ServingCellID','CoordinateMode','MapAnchorLabel'});
end

function positions = localPositionMatrix(raw, fieldName)
positions = double(raw);
if isempty(positions)
    positions = zeros(0, 3);
elseif ~(ismatrix(positions) && size(positions, 2) == 3 && all(isfinite(positions), "all"))
    error("sixgr:truth:InvalidLiveGeometryPositions", ...
        "%s must be a finite N-by-3 matrix.", fieldName);
end
end

function value = localScenarioGet(scfg, path, defaultValue)
value = defaultValue;
if isobject(scfg) && ismethod(scfg, "get")
    value = scfg.get(path, defaultValue);
elseif isstruct(scfg)
    value = sixgr.util.structGet(scfg, path, defaultValue);
end
end
