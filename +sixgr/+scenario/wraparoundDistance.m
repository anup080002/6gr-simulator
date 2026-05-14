function [dist_m, dxy_m] = wraparoundDistance(uePos_m, bsPos_m, area_m, varargin)
%SIXGR.SCENARIO.WRAPAROUNDDISTANCE Wrap-around distance with explicit geometry mode.
%
%   dist_m = sixgr.scenario.wraparoundDistance(uePos_m, bsPos_m, area_m)
%   dist_m = sixgr.scenario.wraparoundDistance(..., "Mode", mode)
%   dist_m = sixgr.scenario.wraparoundDistance(..., "Mode", "hex_lattice_min_image", "ISD_m", isd_m)
%
% Modes:
%   rectangular_torus     legacy rectangular wrap-around on [W H]
%   hex_lattice_min_image nearest-image search using the hex lattice basis
%   disabled              no wrap-around; plain Euclidean distance

ip = inputParser;
ip.addParameter("Mode", "rectangular_torus", @(x) ischar(x) || isstring(x));
ip.addParameter("ISD_m", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

validateattributes(uePos_m, {'double'}, {'2d', 'nonempty'}, mfilename, 'uePos_m', 1);
validateattributes(bsPos_m, {'double'}, {'2d', 'nonempty'}, mfilename, 'bsPos_m', 2);
validateattributes(area_m, {'double'}, {'vector', 'numel', 2}, mfilename, 'area_m', 3);

W = area_m(1);
H = area_m(2);
if W <= 0 || H <= 0
    error("sixgr:scenario:BadArea", "area_m must be positive [W H].");
end

ueXY = double(uePos_m(:,1:2));
bsXY = double(bsPos_m(:,1:2));
K = size(ueXY,1);
N = size(bsXY,1);

mode = lower(strtrim(string(opt.Mode)));
switch mode
    case {"", "rectangular", "rectangular_torus", "legacy_rectangular_torus"}
        dx = ueXY(:,1) - bsXY(:,1).';
        dy = ueXY(:,2) - bsXY(:,2).';
        dx = dx - W * round(dx / W);
        dy = dy - H * round(dy / H);
    case {"disabled", "none", "off"}
        dx = ueXY(:,1) - bsXY(:,1).';
        dy = ueXY(:,2) - bsXY(:,2).';
    case {"hex_lattice_min_image", "hex", "hex_grid"}
        isd_m = double(opt.ISD_m);
        if ~(isfinite(isd_m) && isd_m > 0)
            error("sixgr:scenario:BadHexISD", ...
                "Hex wrap-around requires a positive ISD_m.");
        end
        [dx, dy] = localHexNearestImage(ueXY, bsXY, isd_m, K, N);
    otherwise
        error("sixgr:scenario:UnknownWraparoundMode", ...
            "Unknown wrap-around mode: %s", mode);
end

dist_m = sqrt(dx.^2 + dy.^2);
if nargout > 1
    dxy_m = zeros(K, N, 2);
    dxy_m(:,:,1) = dx;
    dxy_m(:,:,2) = dy;
end
end

function [bestDx, bestDy] = localHexNearestImage(ueXY, bsXY, isd_m, K, N)
a = [isd_m, 0];
b = [0.5 * isd_m, (sqrt(3) / 2) * isd_m];

bestDist2 = inf(K, N);
bestDx = zeros(K, N);
bestDy = zeros(K, N);

for ia = -1:1
    for ib = -1:1
        shift = ia * a + ib * b;
        dx = ueXY(:,1) - (bsXY(:,1).' + shift(1));
        dy = ueXY(:,2) - (bsXY(:,2).' + shift(2));
        candDist2 = dx.^2 + dy.^2;
        betterMask = candDist2 < bestDist2;
        bestDist2(betterMask) = candDist2(betterMask);
        bestDx(betterMask) = dx(betterMask);
        bestDy(betterMask) = dy(betterMask);
    end
end
end
