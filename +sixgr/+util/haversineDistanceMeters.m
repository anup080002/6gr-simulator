function distance_m = haversineDistanceMeters(lat1_deg, lon1_deg, lat2_deg, lon2_deg)
%HAVERSINEDISTANCEMETERS Great-circle distance between latitude/longitude pairs.

arguments
    lat1_deg
    lon1_deg
    lat2_deg
    lon2_deg
end

radius_m = 6378137.0;
lat1 = deg2rad(double(lat1_deg));
lon1 = deg2rad(double(lon1_deg));
lat2 = deg2rad(double(lat2_deg));
lon2 = deg2rad(double(lon2_deg));

dLat = lat2 - lat1;
dLon = lon2 - lon1;
a = sin(dLat ./ 2).^2 + cos(lat1) .* cos(lat2) .* sin(dLon ./ 2).^2;
c = 2 .* atan2(sqrt(max(a, 0)), sqrt(max(1 - a, 0)));
distance_m = radius_m .* c;
end
