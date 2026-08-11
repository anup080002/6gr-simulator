function ecefM = lla2ecefSafe(latitudeRad, longitudeRad, altitudeM, earthRadiusM)
%LLA2ECEFSAFE Toolbox-independent spherical-Earth LLA to ECEF conversion.

r = earthRadiusM + altitudeM;
ecefM = [r .* cos(latitudeRad) .* cos(longitudeRad), ...
    r .* cos(latitudeRad) .* sin(longitudeRad), r .* sin(latitudeRad)];
end
