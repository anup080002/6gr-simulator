function geometry = buildScenarioGeometry(cfg)
%BUILDSCENARIOGEOMETRY Deterministic strict mini geometry evidence.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

runId = string(sixgr.util.structGet(cfg, "channel_rf.runId", "channel_rf_strict"));
scenarioName = string(sixgr.util.structGet(cfg, "scenario.id", ...
    sixgr.util.structGet(cfg, "meta.scenarioID", "lls_channel_rf_strict_mini_anchor")));
isd = double(sixgr.util.structGet(cfg, "scenario.layout.interSiteDistance_m", ...
    sixgr.util.structGet(cfg, "deployment_topology.inter_site_distance_m", 500)));
bsHeight = double(sixgr.util.structGet(cfg, "scenario.bs.height_m", 24));
ueHeight = double(sixgr.util.structGet(cfg, "scenario.ue.height_m", 1.5));
sectorAz = double(sixgr.util.structGet(cfg, "scenario.sectorization.azimOffsets_deg", [0 120 240]));
if isempty(sectorAz)
    sectorAz = [0 120 240];
end
sectorAz = sectorAz(:).';
sitePos = [0 0 bsHeight; isd 0 bsHeight];
uePos = [0.35 * isd 80 ueHeight; 0.72 * isd -65 ueHeight];
ueSpeedKmph = double(sixgr.util.structGet(cfg, "scenario.mobility.speed_kmh", ...
    sixgr.util.structGet(cfg, "channel.mobility_kmph", [30 30])));
if isscalar(ueSpeedKmph)
    ueSpeedKmph = repmat(ueSpeedKmph, 1, size(uePos, 1));
end
ueHeadingDeg = [35; 215];

siteRows = repmat(struct("RunId","", "ScenarioName","", "SiteId",NaN, ...
    "X_m",NaN, "Y_m",NaN, "Z_m",NaN, "HeightBSm",NaN, "Status",""), 0, 1);
for i = 1:size(sitePos, 1)
    siteRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "SiteId", i, "X_m", sitePos(i, 1), "Y_m", sitePos(i, 2), ...
        "Z_m", sitePos(i, 3), "HeightBSm", bsHeight, "Status", "configured_geometry");
end

sectorRows = repmat(struct("RunId","", "ScenarioName","", "SiteId",NaN, ...
    "SectorId",NaN, "CellId",NaN, "SectorBoresightAzDeg",NaN, ...
    "SectorDowntiltDeg",NaN, "TxPositionXYZm","", "Status",""), 0, 1);
cellId = 0;
for s = 1:size(sitePos, 1)
    for a = 1:numel(sectorAz)
        cellId = cellId + 1;
        sectorRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
            "SiteId", s, "SectorId", a, "CellId", cellId, ...
            "SectorBoresightAzDeg", sectorAz(a), "SectorDowntiltDeg", ...
            double(sixgr.util.structGet(cfg, "scenario.bs.downtilt_deg", 6)), ...
            "TxPositionXYZm", localVec(sitePos(s, :)), "Status", "configured_geometry");
    end
end

ueRows = repmat(struct("RunId","", "ScenarioName","", "UEId",NaN, ...
    "X_m",NaN, "Y_m",NaN, "Z_m",NaN, "HeightUEm",NaN, "UESpeedKmph",NaN, ...
    "UEHeadingDeg",NaN, "UEVelocityXYZmps","", "O2IState",false, ...
    "IndoorDistance2Dm",NaN, "Status",""), 0, 1);
for u = 1:size(uePos, 1)
    speedMps = ueSpeedKmph(min(u, numel(ueSpeedKmph))) / 3.6;
    headingRad = ueHeadingDeg(u) * pi / 180;
    velocity = [speedMps * cos(headingRad), speedMps * sin(headingRad), 0];
    ueRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "UEId", u, "X_m", uePos(u, 1), "Y_m", uePos(u, 2), "Z_m", uePos(u, 3), ...
        "HeightUEm", ueHeight, "UESpeedKmph", ueSpeedKmph(min(u, numel(ueSpeedKmph))), ...
        "UEHeadingDeg", ueHeadingDeg(u), "UEVelocityXYZmps", localVec(velocity), ...
        "O2IState", u == 2, "IndoorDistance2Dm", localTernaryDouble(u == 2, 12, 0), ...
        "Status", "configured_geometry");
end

linkRows = repmat(struct("RunId","", "ScenarioName","", "LinkId","", ...
    "CellId",NaN, "SiteId",NaN, "SectorId",NaN, "UEId",NaN, "Direction","", ...
    "SitePositionXYZm","", "UEPositionXYZm","", "Distance2Dm",NaN, ...
    "Distance3Dm",NaN, "HeightBSm",NaN, "HeightUEm",NaN, "LOSState",false, ...
    "LOSProbability",NaN, "O2IState",false, "IndoorDistance2Dm",NaN, ...
    "Status",""), 0, 1);
servedPairs = [1 1 1; 2 2 2];
for i = 1:size(servedPairs, 1)
    siteId = servedPairs(i, 1);
    sectorId = servedPairs(i, 2);
    ueId = servedPairs(i, 3);
    cellId = (siteId - 1) * numel(sectorAz) + sectorId;
    tx = sitePos(siteId, :);
    rx = uePos(ueId, :);
    d2d = hypot(tx(1) - rx(1), tx(2) - rx(2));
    d3d = sqrt(sum((tx - rx).^2));
    losProbability = min(1, max(0.05, exp(-d2d / 500)));
    los = d2d < 300;
    linkRows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "LinkId", "L" + string(i), "CellId", cellId, "SiteId", siteId, ...
        "SectorId", sectorId, "UEId", ueId, "Direction", "downlink", ...
        "SitePositionXYZm", localVec(tx), "UEPositionXYZm", localVec(rx), ...
        "Distance2Dm", d2d, "Distance3Dm", d3d, "HeightBSm", bsHeight, ...
        "HeightUEm", ueHeight, "LOSState", los, "LOSProbability", losProbability, ...
        "O2IState", ueRows(ueId).O2IState, ...
        "IndoorDistance2Dm", ueRows(ueId).IndoorDistance2Dm, ...
        "Status", "configured_geometry");
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

function y = localTernaryDouble(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
