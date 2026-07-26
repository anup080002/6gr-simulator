function [response, state] = ArrayResponse(layout, nv, nh, ...
    spacingH_lambda, spacingV_lambda, azimuth_deg, elevation_deg, ...
    yaw_deg, pitch_deg, roll_deg)
%ARRAYRESPONSE Deterministic ULA/URA response with an explicit array pose.
%
% Horizontal elements are ordered along local +Y and vertical elements
% along local +Z. ElementIndex0 increments horizontally first.

arguments
    layout
    nv (1,1) double {mustBeInteger,mustBePositive}
    nh (1,1) double {mustBeInteger,mustBePositive}
    spacingH_lambda (1,1) double {mustBeFinite,mustBeNonnegative}
    spacingV_lambda (1,1) double {mustBeFinite,mustBeNonnegative}
    azimuth_deg (1,1) double {mustBeFinite}
    elevation_deg (1,1) double {mustBeFinite}
    yaw_deg (1,1) double {mustBeFinite} = 0
    pitch_deg (1,1) double {mustBeFinite} = 0
    roll_deg (1,1) double {mustBeFinite} = 0
end

layout = upper(strtrim(string(layout)));
if layout == "ULA"
    if nv ~= 1
        error("CHANNEL:InvalidAntennaArray", ...
            "ULA requires Nv=1.");
    end
elseif ~any(layout == ["URA","UPA"])
    error("CHANNEL:InvalidAntennaArray", ...
        "Array layout must be ULA or URA.");
end

horizontal = repmat((0:nh-1).', nv, 1);
vertical = kron((0:nv-1).', ones(nh, 1));
localPosition_lambda = [zeros(numel(horizontal),1), ...
    horizontal.*spacingH_lambda, vertical.*spacingV_lambda];

cy = cosd(yaw_deg); sy = sind(yaw_deg);
cp = cosd(pitch_deg); sp = sind(pitch_deg);
cr = cosd(roll_deg); sr = sind(roll_deg);
rz = [cy -sy 0; sy cy 0; 0 0 1];
ry = [cp 0 sp; 0 1 0; -sp 0 cp];
rx = [1 0 0; 0 cr -sr; 0 sr cr];
rotation = rz * ry * rx;
globalPosition_lambda = (rotation * localPosition_lambda.').';

direction = [cosd(elevation_deg).*cosd(azimuth_deg), ...
    cosd(elevation_deg).*sind(azimuth_deg), sind(elevation_deg)];
phase = 2 .* pi .* (globalPosition_lambda * direction.');
response = exp(1i .* phase);
state = struct( ...
    "ElementPosition_lambda", globalPosition_lambda, ...
    "RotationMatrix", rotation, ...
    "ArrayNorm", sqrt(numel(response)), ...
    "Normalization", "unit_magnitude_per_physical_element");
end
