function geometry = buildScenarioGeometry(cfg)
%BUILDSCENARIOGEOMETRY Deterministic strict mini geometry evidence.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

runId = string(sixgr.util.structGet(cfg, "channel_rf.runId", "channel_rf_strict"));
scenarioName = string(sixgr.util.structGet(cfg, "scenario.id", ...
    sixgr.util.structGet(cfg, "meta.scenarioID", "lls_channel_rf_strict_mini_anchor")));
% Use the same configured topology and UE-drop factories as the production
% system chain.  This function is an evidence adapter; it must not invent a
% second two-site/two-UE mini topology or its own LOS proxy.
rngState = rng;
rngCleanup = onCleanup(@() rng(rngState)); %#ok<NASGU>
seed = double(sixgr.util.structGet(cfg, "run.seed", ...
    sixgr.util.structGet(cfg, "run.randomSeed", 1)));
if ~(isscalar(seed) && isfinite(seed) && seed == fix(seed))
    error("sixgr:channel:GeometrySeedRequired", ...
        "Configured geometry evidence requires one finite integer run seed.");
end
rng(seed, "twister");
% Direct channel/geometry validators may receive the normalized public
% topology aliases without the internal ScenarioFactory mirrors. Project
% those authored values explicitly; never fall back to a second topology.
cfg = localProjectTopologyAliases(cfg);
layout = sixgr.scenario.generateLayout(cfg);
ue = sixgr.scenario.dropUEs(cfg, layout);

sitePos = double(sixgr.util.structGet(layout, "sites.pos_m", zeros(0, 3)));
siteIds = double(sixgr.util.structGet(layout, "sites.id", ...
    (1:size(sitePos, 1)).'));
bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0, 3)));
bsSiteIds = double(sixgr.util.structGet(layout, "bs.siteId", zeros(0, 1)));
sectorIds = double(sixgr.util.structGet(layout, "bs.sectorId", zeros(0, 1)));
cellIds = double(sixgr.util.structGet(layout, "bs.cellId", zeros(0, 1)));
sectorAz = double(sixgr.util.structGet(layout, "bs.azim_deg", zeros(0, 1)));
uePos = double(sixgr.util.structGet(ue, "pos_m", zeros(0, 3)));
ueIds = double(sixgr.util.structGet(ue, "id", (1:size(uePos, 1)).'));
ueSpeedKmph = double(sixgr.util.structGet(ue, "speed_kmh", zeros(size(uePos, 1), 1)));
ueHeadingDeg = double(sixgr.util.structGet(ue, "heading_deg", zeros(size(uePos, 1), 1)));
ueIndoor = logical(sixgr.util.structGet(ue, "indoor", false(size(uePos, 1), 1)));
servingCellIds = double(sixgr.util.structGet(ue, "drop_cell_id", ones(size(uePos, 1), 1)));
if isempty(sitePos) || isempty(bsPos) || isempty(uePos)
    error("sixgr:channel:ConfiguredGeometryEmpty", ...
        "The production topology/UE-drop factories returned empty configured geometry.");
end

siteRows = repmat(struct("RunId","", "ScenarioName","", "SiteId",NaN, ...
    "X_m",NaN, "Y_m",NaN, "Z_m",NaN, "HeightBSm",NaN, "Status",""), 0, 1);
for i = 1:size(sitePos, 1)
    siteRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "SiteId", siteIds(i), "X_m", sitePos(i, 1), "Y_m", sitePos(i, 2), ...
        "Z_m", sitePos(i, 3), "HeightBSm", sitePos(i, 3), "Status", "configured_geometry");
end

sectorRows = repmat(struct("RunId","", "ScenarioName","", "SiteId",NaN, ...
    "SectorId",NaN, "CellId",NaN, "SectorBoresightAzDeg",NaN, ...
    "SectorDowntiltDeg",NaN, "TxPositionXYZm","", "Status",""), 0, 1);
for b = 1:size(bsPos, 1)
    sectorRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "SiteId", bsSiteIds(b), "SectorId", sectorIds(b), "CellId", cellIds(b), ...
        "SectorBoresightAzDeg", sectorAz(b), "SectorDowntiltDeg", ...
        double(sixgr.util.structGet(cfg, "scenario.bs.downtilt_deg", 0)), ...
        "TxPositionXYZm", localVec(bsPos(b, :)), "Status", "configured_geometry");
end

ueRows = repmat(struct("RunId","", "ScenarioName","", "UEId",NaN, ...
    "X_m",NaN, "Y_m",NaN, "Z_m",NaN, "HeightUEm",NaN, "UESpeedKmph",NaN, ...
    "UEHeadingDeg",NaN, "UEVelocityXYZmps","", "O2IState",false, ...
    "IndoorDistance2Dm",NaN, "Status",""), 0, 1);
for u = 1:size(uePos, 1)
    speedMps = ueSpeedKmph(u) / 3.6;
    headingRad = ueHeadingDeg(u) * pi / 180;
    velocity = [speedMps * cos(headingRad), speedMps * sin(headingRad), 0];
    ueRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "UEId", ueIds(u), "X_m", uePos(u, 1), "Y_m", uePos(u, 2), "Z_m", uePos(u, 3), ...
        "HeightUEm", uePos(u, 3), "UESpeedKmph", ueSpeedKmph(u), ...
        "UEHeadingDeg", ueHeadingDeg(u), "UEVelocityXYZmps", localVec(velocity), ...
        "O2IState", ueIndoor(u), "IndoorDistance2Dm", ...
        localIndoorDistance(cfg, ueIndoor(u)), ...
        "Status", "configured_geometry");
end

linkRows = repmat(struct("RunId","", "ScenarioName","", "LinkId","", ...
    "CellId",NaN, "SiteId",NaN, "SectorId",NaN, "UEId",NaN, "Direction","", ...
    "SitePositionXYZm","", "UEPositionXYZm","", "Distance2Dm",NaN, ...
    "Distance3Dm",NaN, "HeightBSm",NaN, "HeightUEm",NaN, "LOSState",false, ...
    "LOSProbability",NaN, "O2IState",false, "IndoorDistance2Dm",NaN, ...
    "Status",""), 0, 1);
losEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", false));
profileName = string(sixgr.util.structGet(layout, "profileName", ...
    sixgr.util.structGet(cfg, "channel.propagationScenario", "")));
for u = 1:size(uePos, 1)
    servingCellId = servingCellIds(u);
    if isempty(find(cellIds == servingCellId, 1, "first"))
        error("sixgr:channel:ServingCellNotInConfiguredTopology", ...
            "UE %g references serving cell %g, absent from the configured topology.", ...
            ueIds(u), servingCellId);
    end
    % A strict channel/RF geometry campaign validates every configured
    % BS-to-UE propagation link, not only the initially selected serving
    % link.  Interference and O2I/pathloss evidence therefore retain their
    % actual candidate-cell geometry and never duplicate one serving row.
    for bsIndex = 1:size(bsPos, 1)
        cellId = cellIds(bsIndex);
        siteId = bsSiteIds(bsIndex);
        sectorId = sectorIds(bsIndex);
        tx = bsPos(bsIndex, :);
        rx = uePos(u, :);
        d2d = hypot(tx(1) - rx(1), tx(2) - rx(2));
        d3d = sqrt(sum((tx - rx).^2));
        [losProbability, losStatus] = sixgr.channel.LOSProbability( ...
            profileName, max(d2d, eps), "HUT_m", rx(3));
        if ~logical(losStatus.StrictSupported)
            error("sixgr:channel:UnsupportedLOSProbabilityScenario", ...
                "Configured scenario %s has no strict LOS-probability implementation.", ...
                profileName);
        end
        los = losEnabled;
        linkRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ... %#ok<AGROW>
            "LinkId", "L" + string(u) + "_C" + string(cellId), "CellId", cellId, "SiteId", siteId, ...
            "SectorId", sectorId, "UEId", ueIds(u), "Direction", "downlink", ...
            "SitePositionXYZm", localVec(tx), "UEPositionXYZm", localVec(rx), ...
            "Distance2Dm", d2d, "Distance3Dm", d3d, "HeightBSm", tx(3), ...
            "HeightUEm", rx(3), "LOSState", los, "LOSProbability", losProbability, ...
            "O2IState", ueRows(u).O2IState, ...
            "IndoorDistance2Dm", ueRows(u).IndoorDistance2Dm, ...
            "Status", "configured_geometry");
    end
end

geometry = struct();
geometry.SiteTable = struct2table(siteRows);
geometry.SectorTable = struct2table(sectorRows);
geometry.UETable = struct2table(ueRows);
geometry.LinkTable = struct2table(linkRows);
geometry.GeometryId = "geom_" + extractBefore(sixgr.channel.hashChannelRFConfig(linkRows), 13);
end

function txt = localVec(v)
txt = strjoin(string(double(v(:).')), " ");
end

function cfg = localProjectTopologyAliases(cfg)
aliases = {
    "scenario.layout.nSites", ["topology.num_sites", "deployment_topology.num_sites"]
    "scenario.layout.nSectorsPerSite", ["topology.num_sectors_per_site", "deployment_topology.num_sectors_per_site"]
    "scenario.layout.interSiteDistance_m", ["topology.inter_site_distance_m", "deployment_topology.inter_site_distance_m"]
    "scenario.ue.nUE", ["topology.num_ues", "deployment_topology.num_ues"]
    };
for row = 1:size(aliases, 1)
    target = aliases{row, 1};
    current = double(sixgr.util.structGet(cfg, target, NaN));
    if isscalar(current) && isfinite(current) && current >= 1
        continue;
    end
    candidates = string(aliases{row, 2});
    for source = candidates(:).'
        value = double(sixgr.util.structGet(cfg, source, NaN));
        if isscalar(value) && isfinite(value) && value >= 1
            cfg = sixgr.util.structSet(cfg, target, value);
            break;
        end
    end
end
end

function value = localIndoorDistance(cfg, isIndoor)
o2iEnabled = logical(sixgr.util.structGet(cfg, "channel.o2i.enabled", false));
if ~isIndoor || ~o2iEnabled
    value = 0;
    return;
end
value = double(sixgr.util.structGet(cfg, "channel.o2i.indoorDistance_m", NaN));
if ~(isscalar(value) && isfinite(value) && value >= 0)
    error("sixgr:channel:IndoorDistanceConfigurationRequired", ...
        char("An indoor UE with YAML-enabled O2I requires a finite nonnegative " + ...
        "channels.o2i_indoor_distance_m (or phase10_strict.o2i.indoor_distance_m)."));
end
end
