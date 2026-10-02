function topology = buildHexWraparoundTopology(numSites, sectorsPerSite, interSiteDistance_m)
%BUILDHEXWRAPAROUNDTOPOLOGY Build a finite hex cluster and its periodic lattice.
%
% The finite cluster contains complete rings around the origin. Periodic
% images are separated by a cluster-reuse lattice, not by the primitive
% one-site lattice. For the mandatory seven-site deployment, the reuse
% vectors therefore have length sqrt(7)*ISD. This prevents distinct sites
% in the simulated cluster from collapsing onto one another under
% wrap-around.

arguments
    numSites (1,1) double {mustBeInteger,mustBePositive}
    sectorsPerSite (1,1) double {mustBeInteger,mustBePositive}
    interSiteDistance_m (1,1) double {mustBeFinite,mustBePositive}
end

ringCount = (-3 + sqrt(12 * numSites - 3)) / 6;
if abs(ringCount - round(ringCount)) > 1e-12
    error("sixgr:ran1ai1032:IncompleteHexRing", ...
        "Hex wrap-around requires a complete centered cluster with numSites=1+3R(R+1); observed %d sites.", ...
        numSites);
end
ringCount = round(ringCount);

[axialQ, axialR] = localCenteredCluster(ringCount);
[reuseI, reuseJ] = localReuseParameters(numSites);

primitiveA = interSiteDistance_m .* [1, 0];
primitiveB = interSiteDistance_m .* [0.5, sqrt(3) / 2];
translation1 = reuseI .* primitiveA + reuseJ .* primitiveB;
translation2 = -reuseJ .* primitiveA + ...
    (reuseI + reuseJ) .* primitiveB;
translationVectors_m = [translation1; translation2];

siteX_m = interSiteDistance_m .* (axialQ + 0.5 .* axialR);
siteY_m = interSiteDistance_m .* (sqrt(3) / 2) .* axialR;
siteID = (1:numSites).';
siteTable = table(siteID, axialQ, axialR, siteX_m, siteY_m, ...
    'VariableNames', {'SiteID','AxialQ','AxialR','SiteX_m','SiteY_m'});

cellCount = numSites * sectorsPerSite;
cellID = (1:cellCount).';
cellSiteID = repelem(siteID, sectorsPerSite);
sectorID = repmat((1:sectorsPerSite).', numSites, 1);
sectorAzimuth_deg = (sectorID - 1) .* (360 / sectorsPerSite);
cellX_m = repelem(siteX_m, sectorsPerSite);
cellY_m = repelem(siteY_m, sectorsPerSite);
cellTable = table(cellID, cellSiteID, sectorID, sectorAzimuth_deg, ...
    cellX_m, cellY_m, 'VariableNames', {'CellID','SiteID','SectorID', ...
    'SectorAzimuth_deg','SiteX_m','SiteY_m'});

topology = struct();
topology.NumSites = numSites;
topology.SectorsPerSite = sectorsPerSite;
topology.NumCells = cellCount;
topology.InterSiteDistance_m = interSiteDistance_m;
topology.RingCount = ringCount;
topology.SiteTable = siteTable;
topology.CellTable = cellTable;
topology.PrimitiveSiteLattice_m = [primitiveA; primitiveB];
topology.ClusterReuseParameters = [reuseI reuseJ];
topology.TranslationVectors_m = translationVectors_m;
topology.WraparoundMode = "finite_hex_cluster_minimum_image";
topology.GeometrySource = "sixgr_native_axial_hex_cluster";
topology.ReferenceUse = "external_implementations_used_for_method_review_only";
end

function [q, r] = localCenteredCluster(ringCount)
q = zeros(0,1);
r = zeros(0,1);
for qValue = -ringCount:ringCount
    rMin = max(-ringCount, -qValue - ringCount);
    rMax = min(ringCount, -qValue + ringCount);
    for rValue = rMin:rMax
        q(end+1,1) = qValue; %#ok<AGROW>
        r(end+1,1) = rValue; %#ok<AGROW>
    end
end

% Put the origin first; retain a deterministic angular/radial order after it.
radius = max(abs([q r -q-r]), [], 2);
angle = atan2((sqrt(3) / 2) .* r, q + 0.5 .* r);
[~, order] = sortrows([radius angle q r], [1 2 3 4]);
q = q(order);
r = r(order);
end

function [reuseI, reuseJ] = localReuseParameters(numSites)
reuseI = NaN;
reuseJ = NaN;
for i = 1:ceil(sqrt(numSites)) + 1
    for j = 0:i
        if i^2 + i*j + j^2 == numSites
            reuseI = i;
            reuseJ = j;
            return;
        end
    end
end
error("sixgr:ran1ai1032:UnsupportedHexClusterReuse", ...
    "No integral hex-cluster reuse basis exists for %d sites.", numSites);
end
