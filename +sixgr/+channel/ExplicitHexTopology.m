function topology = ExplicitHexTopology(interSiteDistance_m, sectorsPerSite)
%EXPLICITHEXTOPOLOGY Materialize the 19-site, two-ring hexagonal topology.

arguments
    interSiteDistance_m (1,1) double {mustBeFinite,mustBePositive}
    sectorsPerSite (1,1) double {mustBeInteger,mustBePositive}
end

coordinates = zeros(0,2);
for q = -2:2
    for r = -2:2
        if max(abs([q r q+r])) <= 2
            coordinates(end+1,:) = [q r]; %#ok<AGROW>
        end
    end
end
coordinates = sortrows(coordinates, [1 2]);
q = coordinates(:,1);
r = coordinates(:,2);
x = interSiteDistance_m .* (q + r ./ 2);
y = interSiteDistance_m .* (sqrt(3) ./ 2) .* r;
orientation = (0:sectorsPerSite-1) .* (360 ./ sectorsPerSite);

siteIndex = repelem((0:size(coordinates,1)-1).', sectorsPerSite);
sectorIndex = repmat((0:sectorsPerSite-1).', size(coordinates,1), 1);
topology = table( ...
    repelem(q, sectorsPerSite), repelem(r, sectorsPerSite), ...
    siteIndex, sectorIndex, repelem(x, sectorsPerSite), ...
    repelem(y, sectorsPerSite), repmat(orientation(:), size(coordinates,1), 1), ...
    'VariableNames', {'AxialQ','AxialR','CloneSiteIndex0','SectorIndex0', ...
    'SiteX_m','SiteY_m','SectorOrientation_deg'});
end
