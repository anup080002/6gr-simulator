function ue = dropUEs(cfg, layout, scenarioName)
%SIXGR.SCENARIO.DROPUES Drop UEs in the scenario and assign indoor/speed profiles.
%
%   ue = sixgr.scenario.dropUEs(cfg, layout)
%   ue = sixgr.scenario.dropUEs(cfg, layout, scenarioName)
%
% Returns ue struct:
%   ue.K
%   ue.id
%   ue.pos_m         [K x 3]
%   ue.indoor        [K x 1] logical
%   ue.speed_kmh     [K x 1]
%   ue.heading_deg   [K x 1]
%
% This function is deterministic under cfg.run.seed (via rngInit).
%
% Fixes earlier config mismatches by supporting both:
%   cfg.scenario.ue.distribution.indoorFraction
%   cfg.scenario.ue.distribution.speeds_kmh
%
% See also: sixgr.scenario.generateLayout

arguments
    cfg struct
    layout struct
    scenarioName {mustBeTextScalar} = ""
end

prof = sixgr.scenario.ScenarioFactory.getProfile(cfg, scenarioName);

K = prof.ue.count;
W = prof.area_m(1);
H = prof.area_m(2);

[xy, servingRef, headingSeedDeg] = localResolveDropPositions(layout, prof, K, W, H);

% Heights
z = prof.ue.height_m * ones(K,1);

% Indoor/outdoor
indoorFrac = double(sixgr.util.structGet(prof, "ue.distribution.indoorFraction", 0.2));
indoor = rand(K,1) < indoorFrac;

% Speed distribution (km/h)
speeds = double(sixgr.util.structGet(prof, "ue.distribution.speeds_kmh", [3 30 120]));
p = localResolveSpeedWeights(prof, speeds);

speedIdx = localDiscreteSample(p, K);
speedKmh = speeds(speedIdx).';

% Heading (deg)
headingDeg = mod(double(headingSeedDeg(:)) + 20 .* randn(K,1), 360);

ue = struct();
ue.profileName = prof.name;
ue.K = K;
ue.id = (1:K).';
ue.pos_m = [xy z];
ue.indoor = indoor;
ue.speed_kmh = speedKmh;
ue.heading_deg = headingDeg;
ue.drop_cell_id = servingRef(:);
ue.drop_mode = repmat(string(localResolveDropMode(prof)), K, 1);
ue.drop_reference_cell_id = servingRef(:);
ue.serving_selection_method = repmat(string(localResolveServingSelectionMethod(prof)), K, 1);

end

% ---------------- Local helpers ----------------

function [xy, servingRef, headingSeedDeg] = localResolveDropPositions(layout, prof, K, W, H)
xy = zeros(K, 2);
servingRef = ones(K, 1);
headingSeedDeg = rand(K, 1) * 360;

bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
bsAz = double(sixgr.util.structGet(layout, "bs.azim_deg", zeros(size(bsPos,1),1)));
if isempty(bsPos) || isempty(bsAz) || size(bsPos,1) < 1
    xy = [ (rand(K,1)-0.5)*W, (rand(K,1)-0.5)*H ];
    return;
end

nCells = size(bsPos, 1);
switch localResolveDropMode(prof)
    case "pathloss_based_association_drop"
        xy = [ (rand(K,1)-0.5)*W, (rand(K,1)-0.5)*H ];
        servingRef = localAssignByNearestCell(xy, layout, nCells);
        for u = 1:K
            c = servingRef(u);
            dx = xy(u,1) - bsPos(c,1);
            dy = xy(u,2) - bsPos(c,2);
            if abs(dx) < eps && abs(dy) < eps
                headingSeedDeg(u) = rand * 360;
            else
                headingSeedDeg(u) = mod(atan2d(-dy, -dx) + 25 * randn(), 360);
            end
        end
    otherwise
        sectorSpanDeg = localResolveSectorSpan(layout, prof);
        radiusMax_m = localResolveSectorRadius(layout, prof, W, H);
        radiusMin_m = min(40, max(5, 0.08 * radiusMax_m));

        servingRef = repmat((1:nCells).', ceil(K / nCells), 1);
        servingRef = servingRef(1:K);
        servingRef = servingRef(randperm(K));

        for u = 1:K
            c = servingRef(u);
            az = double(bsAz(c));
            theta = az + (rand - 0.5) * 0.92 * sectorSpanDeg;
            rho = sqrt(rand) * (radiusMax_m - radiusMin_m) + radiusMin_m;
            xy(u,1) = bsPos(c,1) + rho * cosd(theta);
            xy(u,2) = bsPos(c,2) + rho * sind(theta);
            headingSeedDeg(u) = mod(theta + 180 + 25 * randn(), 360);
        end
        xy(:,1) = min(max(xy(:,1), -0.5 * W), 0.5 * W);
        xy(:,2) = min(max(xy(:,2), -0.5 * H), 0.5 * H);
end
end

function servingRef = localAssignByNearestCell(xy, layout, nCells)
wrapMode = string(sixgr.util.structGet(layout, "wraparoundMode", "rectangular_torus"));
wrapEnabled = logical(sixgr.util.structGet(layout, "wraparoundEnabled", false));
if wrapEnabled && wrapMode ~= "disabled"
    d = sixgr.scenario.wraparoundDistance(xy, layout.bs.pos_m, layout.area_m, ...
        "Mode", wrapMode, "ISD_m", double(sixgr.util.structGet(layout, "isd_m", NaN)));
else
    dx = xy(:,1) - layout.bs.pos_m(:,1).';
    dy = xy(:,2) - layout.bs.pos_m(:,2).';
    d = sqrt(dx.^2 + dy.^2);
end
[~, servingRef] = min(d, [], 2);
servingRef = min(max(round(double(servingRef)), 1), nCells);
end

function mode = localResolveDropMode(prof)
mode = lower(strtrim(string(sixgr.util.structGet(prof, "ue.dropMode", "legacy_equal_sector_drop"))));
if strlength(mode) == 0
    mode = "legacy_equal_sector_drop";
end
switch mode
    case {"legacy_equal_sector_drop", "legacy", "equal_sector"}
        mode = "legacy_equal_sector_drop";
    case {"pathloss_based_association_drop", "pathloss_based", "nearest_cell_after_drop"}
        mode = "pathloss_based_association_drop";
    otherwise
        error("sixgr:scenario:UnsupportedUEDropMode", ...
            "Unsupported UE drop mode: %s", mode);
end
end

function method = localResolveServingSelectionMethod(prof)
if localResolveDropMode(prof) == "pathloss_based_association_drop"
    method = "nearest_cell_distance_after_uniform_area_drop";
else
    method = "legacy_equal_sector_reference";
end
end

function p = localResolveSpeedWeights(prof, speeds)
p = double(sixgr.util.structGet(prof, "ue.distribution.speedWeights", ...
    sixgr.util.structGet(prof, "ue.distribution.speedProb", ones(1, numel(speeds)) / max(numel(speeds), 1))));
p = p(:).';
if isempty(speeds)
    p = 1;
    return;
end
if numel(p) ~= numel(speeds) || ~any(isfinite(p))
    p = ones(1, numel(speeds)) / numel(speeds);
else
    p(~isfinite(p) | p < 0) = 0;
    if sum(p) <= 0
        p = ones(1, numel(speeds)) / numel(speeds);
    else
        p = p / sum(p);
    end
end
end

function spanDeg = localResolveSectorSpan(layout, prof)
spanDeg = 360 / max(1, double(sixgr.util.structGet(prof, "nSectors", numel(sixgr.util.structGet(layout, "bs.azim_deg", 1)))));
if isfield(layout, "bs") && isfield(layout.bs, "siteId") && isfield(layout.bs, "sectorId")
    siteIds = double(layout.bs.siteId(:));
    if ~isempty(siteIds)
        firstSite = siteIds(1);
        nOnSite = nnz(siteIds == firstSite);
        if nOnSite >= 1
            spanDeg = 360 / double(nOnSite);
        end
    end
end
spanDeg = max(45, min(180, spanDeg));
end

function radiusMax_m = localResolveSectorRadius(layout, prof, W, H)
isd_m = double(sixgr.util.structGet(layout, "isd_m", sixgr.util.structGet(prof, "isd_m", NaN)));
if isfinite(isd_m) && isd_m > 0
    radiusMax_m = 0.42 * isd_m;
else
    radiusMax_m = 0.22 * min(double(W), double(H));
end
radiusMax_m = max(radiusMax_m, 25);
end

function idx = localDiscreteSample(p, N)
% Sample N iid indices from categorical distribution p (row vector).
cdf = cumsum(p(:));
r = rand(N,1);
idx = zeros(N,1);
for i = 1:N
    idx(i) = find(r(i) <= cdf, 1, "first");
end
end
