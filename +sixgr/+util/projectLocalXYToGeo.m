function [lat_deg, lon_deg] = projectLocalXYToGeo(x_m, y_m, anchorLat_deg, anchorLon_deg)
%PROJECTLOCALXYTOGEO Project local east/north meter offsets onto geodetic latitude/longitude.
%
% Local simulator geometry is maintained in Cartesian meters. For browser and
% DB exports we anchor that geometry onto a reference latitude/longitude using
% a forward geodesic on a spherical Earth, which is materially more accurate
% than a flat meters-per-degree approximation once the layout spans hundreds
% of meters or more.

arguments
    x_m
    y_m
    anchorLat_deg (1,1) double = 19.122164
    anchorLon_deg (1,1) double = 72.999217
end

radius_m = 6378137.0;
x = double(x_m);
y = double(y_m);
lat0 = deg2rad(double(anchorLat_deg));
lon0 = deg2rad(double(anchorLon_deg));

distance_m = hypot(x, y);
bearing_rad = atan2(x, y); % local x=east, y=north
angularDistance = distance_m ./ radius_m;

lat2 = asin( ...
    sin(lat0) .* cos(angularDistance) + ...
    cos(lat0) .* sin(angularDistance) .* cos(bearing_rad));
lon2 = lon0 + atan2( ...
    sin(bearing_rad) .* sin(angularDistance) .* cos(lat0), ...
    cos(angularDistance) - sin(lat0) .* sin(lat2));

lat_deg = rad2deg(lat2);
lon_deg = rad2deg(lon2);

stationaryMask = distance_m <= eps;
if any(stationaryMask(:))
    lat_deg(stationaryMask) = double(anchorLat_deg);
    lon_deg(stationaryMask) = double(anchorLon_deg);
end
end
