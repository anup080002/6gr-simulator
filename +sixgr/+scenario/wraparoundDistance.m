function [dist_m, dxy_m] = wraparoundDistance(uePos_m, bsPos_m, area_m)
%SIXGR.SCENARIO.WRAPAROUNDDISTANCE Toroidal wrap-around distance (rectangular).
%
%   dist_m = sixgr.scenario.wraparoundDistance(uePos_m, bsPos_m, area_m)
%   [dist_m, dxy_m] = sixgr.scenario.wraparoundDistance(...)
%
% Inputs:
%   uePos_m : [K x 2] or [K x 3] UE positions (m)
%   bsPos_m : [N x 2] or [N x 3] BS/TRxP positions (m)
%   area_m  : [W H] rectangle size (m) for wrap-around
%
% Outputs:
%   dist_m  : [K x N] wrapped Euclidean distances (m)
%   dxy_m   : [K x N x 2] wrapped delta vectors (ue - bs) in x/y (m)
%
% Notes:
% - Wrap-around uses dx = dx - W*round(dx/W), same for dy.
% - This is used by system-level abstractions (pathloss, association).
%
% See also: pdist2

arguments
    uePos_m double
    bsPos_m double
    area_m (1,2) double
end

W = area_m(1);
H = area_m(2);
if W <= 0 || H <= 0
    error("sixgr:scenario:BadArea", "area_m must be positive [W H].");
end

ueXY = uePos_m(:,1:2);
bsXY = bsPos_m(:,1:2);

K = size(ueXY,1);
N = size(bsXY,1);

% Broadcast differences (KxN)
dx = ueXY(:,1) - bsXY(:,1).';
dy = ueXY(:,2) - bsXY(:,2).';

dx = dx - W * round(dx / W);
dy = dy - H * round(dy / H);

dist_m = sqrt(dx.^2 + dy.^2);

if nargout > 1
    dxy_m = zeros(K,N,2);
    dxy_m(:,:,1) = dx;
    dxy_m(:,:,2) = dy;
end
end
