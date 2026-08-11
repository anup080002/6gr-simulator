function lla = ecef2llaSafe(ecefM, earthRadiusM)
%ECEF2LLASAFE Toolbox-independent spherical-Earth ECEF to LLA conversion.

r = sqrt(sum(ecefM.^2, 2));
lla = struct("Latitude_rad", asin(ecefM(:,3) ./ r), ...
    "Longitude_rad", atan2(ecefM(:,2), ecefM(:,1)), ...
    "Altitude_m", r - earthRadiusM);
end
