function layout = generateLayout(cfg, scenarioName)
%SIXGR.SCENARIO.GENERATELAYOUT Generate BS/TRxP layout for a scenario profile.
%
%   layout = sixgr.scenario.generateLayout(cfg)
%   layout = sixgr.scenario.generateLayout(cfg, scenarioName)
%
% Output layout struct contains:
%   layout.profileName
%   layout.area_m              [W H]
%   layout.wraparoundEnabled
%   layout.sites.pos_m         [nSites x 3]
%   layout.bs.pos_m            [nTRxP x 3]
%   layout.bs.siteId           [nTRxP x 1]
%   layout.bs.sectorId         [nTRxP x 1]
%   layout.bs.azim_deg         [nTRxP x 1]
%   layout.bs.txPower_dBm      [nTRxP x 1]
%
% Notes:
% - Coordinates are local Cartesian meters with origin at (0,0).
% - For macro scenarios, a hex lattice is used with nSites up to 19 by default.
% - For indoor, a rectangular grid is used.
%
% See also: sixgr.scenario.dropUEs, sixgr.scenario.wraparoundDistance

arguments
    cfg struct
    scenarioName {mustBeTextScalar} = ""
end

prof = sixgr.scenario.ScenarioFactory.getProfile(cfg, scenarioName);

layout = struct();
layout.profileName = prof.name;
layout.layoutType = prof.layoutType;
layout.area_m = prof.area_m;
layout.wraparoundEnabled = prof.wraparoundEnabled;
layout.isd_m = prof.isd_m;
layout.nSites = prof.nSites;
layout.nSectors = prof.nSectors;
layout.nTRxP = prof.nTRxP;

bsH = prof.bs.height_m;

switch lower(string(prof.layoutType))
    case {"hex","hex_grid","hexgrid"}
        siteXY = localHexSites(prof.nSites, prof.isd_m);
    case {"indoor_grid","grid","rect"}
        siteXY = localIndoorGridSites(prof.nSites, prof.isd_m, prof.area_m);
    otherwise
        error("sixgr:scenario:UnknownLayout", "Unknown layoutType: %s", prof.layoutType);
end

nSites = size(siteXY,1);
sitePos = [siteXY, bsH * ones(nSites,1)];
layout.sites = struct();
layout.sites.pos_m = sitePos;
layout.sites.id = (1:nSites).';

% Sectorization: create TRxP per sector (co-located at site)
azOff = double(prof.sectorization.azimOffsets_deg(:).');
if numel(azOff) < prof.nSectors
    % Repeat if insufficient offsets
    azOff = repmat(azOff, 1, ceil(prof.nSectors/numel(azOff)));
end
azOff = azOff(1:prof.nSectors);

nTRxP = nSites * prof.nSectors;
bsPos = zeros(nTRxP,3);
siteId = zeros(nTRxP,1);
sectorId = zeros(nTRxP,1);
azimDeg = zeros(nTRxP,1);
txP = prof.bs.txPower_dBm * ones(nTRxP,1);

k = 0;
for s = 1:nSites
    for sec = 1:prof.nSectors
        k = k + 1;
        bsPos(k,:) = sitePos(s,:);
        siteId(k) = s;
        sectorId(k) = sec;
        azimDeg(k) = mod(azOff(sec), 360);
    end
end

layout.bs = struct();
layout.bs.pos_m = bsPos;
layout.bs.siteId = siteId;
layout.bs.sectorId = sectorId;
layout.bs.azim_deg = azimDeg;
layout.bs.height_m = bsH;
layout.bs.txPower_dBm = txP;

end

% ---------------- Local helpers ----------------

function siteXY = localHexSites(nSites, isd_m)
% Generate an arbitrary-size hex lattice centered at origin.

nSites = double(nSites);
isd_m = double(isd_m);

if nSites <= 0
    siteXY = zeros(0,2);
    return;
end

axial = zeros(nSites, 2);
axial(1,:) = [0 0];
count = 1;
ring = 1;
dirs = [0 -1; -1 0; -1 1; 0 1; 1 0; 1 -1];
while count < nSites
    q = ring;
    r = 0;
    for side = 1:6
        for step = 1:ring
            count = count + 1;
            axial(count,:) = [q r];
            if count >= nSites
                break;
            end
            q = q + dirs(side,1);
            r = r + dirs(side,2);
        end
        if count >= nSites
            break;
        end
    end
    ring = ring + 1;
end

q = axial(:,1);
r = axial(:,2);

% Convert axial to Cartesian (neighbor distance = isd_m)
x = isd_m * (q + 0.5*r);
y = isd_m * (sqrt(3)/2) * r;

siteXY = [x y];
end

function siteXY = localIndoorGridSites(nSites, isd_m, area_m)
% Place TRxPs on an indoor rectangular grid and center it at origin.
nSites = double(nSites);
isd_m = double(isd_m);
W = double(area_m(1));
H = double(area_m(2));

if nSites <= 0
    siteXY = zeros(0,2);
    return;
end

% Heuristic grid dims: try to keep aspect ratio similar to W/H.
targetRatio = max(W,eps) / max(H,eps);
nx = max(1, round(sqrt(nSites*targetRatio)));
ny = max(1, ceil(nSites / nx));
nx = max(1, nx);
ny = max(1, ny);

% Grid spacing: prefer isd_m but shrink if it doesn't fit.
maxDx = (nx-1) * isd_m;
maxDy = (ny-1) * isd_m;
sx = isd_m;
sy = isd_m;
if maxDx > W*0.9 && nx>1
    sx = (W*0.9) / (nx-1);
end
if maxDy > H*0.9 && ny>1
    sy = (H*0.9) / (ny-1);
end

xv = linspace(-W*0.45, W*0.45, nx);
yv = linspace(-H*0.45, H*0.45, ny);
[X,Y] = meshgrid(xv, yv);
pts = [X(:) Y(:)];
siteXY = pts(1:nSites, :);

end
