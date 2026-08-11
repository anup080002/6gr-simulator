function sample = sampleUniformReferenceArea(centerECEFM, earthRadiusM, areaRadiusM, sampleCount, seed)
%SAMPLEUNIFORMREFERENCEAREA Uniform-in-surface-area spherical-cap samples.

arguments
    centerECEFM (1,3) double
    earthRadiusM (1,1) double {mustBePositive,mustBeFinite}
    areaRadiusM (1,1) double {mustBeNonnegative,mustBeFinite}
    sampleCount (1,1) double {mustBeInteger,mustBePositive}
    seed (1,1) double {mustBeInteger,mustBeNonnegative}
end
if abs(norm(centerECEFM) - earthRadiusM) > max(1e-6 * earthRadiusM, 1e-3)
    error("sixgr:ntn:resilientsync:ReferenceCenterOffSurface", ...
        "Reference-area center must lie on the configured spherical Earth.");
end
stream = RandStream("mt19937ar", "Seed", seed);
u = rand(stream, sampleCount, 1);
v = rand(stream, sampleCount, 1);
radialDistanceM = areaRadiusM .* sqrt(u);
azimuthRad = 2*pi .* v;
centralAngle = radialDistanceM ./ earthRadiusM;
r0 = centerECEFM ./ earthRadiusM;
axisCandidate = [0,0,1];
if abs(dot(r0, axisCandidate)) > 0.99
    axisCandidate = [0,1,0];
end
east = cross(axisCandidate, r0); east = east ./ norm(east);
north = cross(r0, east); north = north ./ norm(north);
tangent = cos(azimuthRad) .* east + sin(azimuthRad) .* north;
positions = earthRadiusM .* (cos(centralAngle) .* r0 + sin(centralAngle) .* tangent);
sample = struct("PositionECEF_m", positions, ...
    "SurfaceRadius_m", radialDistanceM, "Azimuth_rad", azimuthRad, ...
    "Distribution", "uniform_in_area", "Seed", seed);
end
