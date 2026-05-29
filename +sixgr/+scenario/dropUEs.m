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
minInterUEDistance_m = localResolveMinimumInterUEDistance(cfg, prof);
spacingStatus = "not_requested";
if isfinite(minInterUEDistance_m) && minInterUEDistance_m > 0 && K > 1
    [xy, servingRef, headingSeedDeg, spacingStatus] = localEnforceMinimumInterUEDistance( ...
        xy, servingRef, headingSeedDeg, layout, prof, W, H, minInterUEDistance_m);
end

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
ue.min_inter_ue_distance_m = repmat(double(minInterUEDistance_m), K, 1);
ue.min_inter_ue_distance_status = repmat(string(spacingStatus), K, 1);

end

% ---------------- Local helpers ----------------

function minDistance_m = localResolveMinimumInterUEDistance(cfg, prof)
minDistance_m = double(sixgr.util.structGet(cfg, "scenario.ue.minInterUEDistance_m", ...
    sixgr.util.structGet(cfg, "scenario.ue.distribution.minInterUEDistance_m", ...
    sixgr.util.structGet(prof, "ue.minInterUEDistance_m", 0))));
if isempty(minDistance_m) || ~isscalar(minDistance_m) || ~isfinite(minDistance_m)
    minDistance_m = 0;
end
minDistance_m = max(0, double(minDistance_m));
end

function [xy, servingRef, headingSeedDeg, status] = localEnforceMinimumInterUEDistance(xy, servingRef, headingSeedDeg, layout, prof, W, H, minDistance_m)
K = size(xy, 1);
if K <= 1
    status = "single_ue";
    return;
end
maxAttempts = max(2000, 80 * K);
for u = 1:K
    candidate = xy(u, :);
    candidateServing = servingRef(u);
    candidateHeading = headingSeedDeg(u);
    accepted = localCandidateSpacingOK(candidate, xy(1:u-1, :), minDistance_m);
    attempt = 0;
    while ~accepted && attempt < maxAttempts
        attempt = attempt + 1;
        [candidate, candidateServing, candidateHeading] = localGenerateDropCandidate(layout, prof, W, H, candidateServing);
        accepted = localCandidateSpacingOK(candidate, xy(1:u-1, :), minDistance_m);
    end
    if ~accepted
        error("sixgr:scenario:MinimumInterUEDistanceUnfillable", ...
            "Unable to place UE %d with min_inter_ue_distance_m=%.3f after %d attempts. Increase area/ISD or reduce UE count/distance.", ...
            u, double(minDistance_m), maxAttempts);
    end
    xy(u, :) = candidate;
    servingRef(u) = candidateServing;
    headingSeedDeg(u) = candidateHeading;
end
status = "enforced_by_rejection_drop";
end

function ok = localCandidateSpacingOK(candidate, previousXY, minDistance_m)
if isempty(previousXY)
    ok = true;
    return;
end
dx = previousXY(:, 1) - double(candidate(1));
dy = previousXY(:, 2) - double(candidate(2));
d = sqrt(dx.^2 + dy.^2);
ok = all(d >= double(minDistance_m) - 1e-9);
end

function [candidate, servingCell, headingDeg] = localGenerateDropCandidate(layout, prof, W, H, preferredServingCell)
bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
bsAz = double(sixgr.util.structGet(layout, "bs.azim_deg", zeros(size(bsPos,1),1)));
nCells = size(bsPos, 1);
if isempty(bsPos) || isempty(bsAz) || nCells < 1
    candidate = [(rand - 0.5) * W, (rand - 0.5) * H];
    servingCell = 1;
    headingDeg = rand * 360;
    return;
end

switch localResolveDropMode(prof)
    case "pathloss_based_association_drop"
        candidate = [(rand - 0.5) * W, (rand - 0.5) * H];
        servingCell = localAssignByNearestCell(candidate, layout, nCells);
        dx = candidate(1) - bsPos(servingCell,1);
        dy = candidate(2) - bsPos(servingCell,2);
        if abs(dx) < eps && abs(dy) < eps
            headingDeg = rand * 360;
        else
            headingDeg = mod(atan2d(-dy, -dx) + 25 * randn(), 360);
        end
    otherwise
        sectorSpanDeg = localResolveSectorSpan(layout, prof);
        radiusMax_m = localResolveSectorRadius(layout, prof, W, H);
        radiusMin_m = min(40, max(5, 0.08 * radiusMax_m));
        servingCell = max(1, min(nCells, round(double(preferredServingCell))));
        az = double(bsAz(servingCell));
        theta = az + (rand - 0.5) * sectorSpanDeg;
        rho = sqrt(radiusMin_m^2 + rand * (radiusMax_m^2 - radiusMin_m^2));
        candidate = [bsPos(servingCell,1) + rho * cosd(theta), bsPos(servingCell,2) + rho * sind(theta)];
        candidate(1) = min(max(candidate(1), -0.5 * W), 0.5 * W);
        candidate(2) = min(max(candidate(2), -0.5 * H), 0.5 * H);
        headingDeg = mod(theta + 180 + 25 * randn(), 360);
end
end

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
            theta = az + (rand - 0.5) * sectorSpanDeg;
            rho = sqrt(radiusMin_m^2 + rand * (radiusMax_m^2 - radiusMin_m^2));
            xy(u,1) = bsPos(c,1) + rho * cosd(theta);
            xy(u,2) = bsPos(c,2) + rho * sind(theta);
            headingSeedDeg(u) = mod(theta + 180 + 25 * randn(), 360);
        end
        xy(:,1) = min(max(xy(:,1), -0.5 * W), 0.5 * W);
        xy(:,2) = min(max(xy(:,2), -0.5 * H), 0.5 * H);
end
end

function servingRef = localAssignByNearestCell(xy, layout, nCells)
wrapMode = string(sixgr.util.structGet(layout, "wraparoundMode", ""));
if strlength(strtrim(wrapMode)) == 0
    if contains(lower(string(sixgr.util.structGet(layout, "layoutType", ""))), "hex")
        wrapMode = "hex_lattice_min_image";
    else
        wrapMode = "rectangular_torus";
    end
end
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
    method = "equal_sector_uniform_area_annulus_reference";
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
    radiusMax_m = isd_m / sqrt(3);
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
