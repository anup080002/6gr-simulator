function ok = testRAN1AI1032HexTopology()
%TESTRAN1AI1032HEXTOPOLOGY Guard the mandatory 7-site/21-cell geometry.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.studies.ran1ai1032.loadStudyConfig();

deployment = cfg.sls.deployments;
assert(numel(deployment) == 2, ...
    "The SLS study must explicitly configure UMa and UMi deployment geometry.");
for k = 1:numel(deployment)
    topology = sixgr.studies.ran1ai1032.buildHexWraparoundTopology( ...
        cfg.sls.sites, cfg.sls.sectors_per_site, ...
        deployment(k).inter_site_distance_m);
    evidence = sixgr.studies.ran1ai1032.validateSLSHexTopology(topology);
    assert(all(evidence.Status == "PASS"));
    assert(topology.NumSites == 7 && topology.NumCells == 21);
    assert(isequal(topology.ClusterReuseParameters, [2 1]), ...
        "Seven-site wrap-around requires the integral reuse pair [2 1].");

    % Independent exhaustive image enumeration: do not reuse production
    % nearest-lattice centering logic in this reference calculation.
    siteXY = [topology.SiteTable.SiteX_m topology.SiteTable.SiteY_m];
    probe = [0.371 -0.283] .* topology.InterSiteDistance_m;
    actual = sixgr.studies.ran1ai1032.hexClusterMinImageDistance( ...
        probe, siteXY, topology.TranslationVectors_m);
    expected = localBruteForceMinImage(probe, siteXY, ...
        topology.TranslationVectors_m, 5);
    assert(max(abs(actual-expected), [], "all") < ...
        1e-11*topology.InterSiteDistance_m, ...
        "Native minimum-image distances disagree with independent exhaustive images.");

    % A primitive one-site translation is intentionally not periodic for
    % the seven-site cluster; neighboring sites must remain distinct.
    origin = find(topology.SiteTable.AxialQ == 0 & ...
        topology.SiteTable.AxialR == 0, 1, "first");
    neighbor = find(topology.SiteTable.AxialQ == 1 & ...
        topology.SiteTable.AxialR == 0, 1, "first");
    neighborDistance = sixgr.studies.ran1ai1032.hexClusterMinImageDistance( ...
        siteXY(origin,:), siteXY(neighbor,:), topology.TranslationVectors_m);
    assert(abs(neighborDistance - topology.InterSiteDistance_m) < ...
        1e-11*topology.InterSiteDistance_m, ...
        "One-site lattice spacing must not be mistaken for a cluster period.");

    % Exercise the actual runtime geometry path with explicit finite-cluster
    % vectors, not only the study helper.
    runtimeLayout = struct();
    runtimeLayout.bs.pos_m = [siteXY, 25*ones(size(siteXY,1),1)];
    runtimeLayout.area_m = [4 4] .* topology.InterSiteDistance_m;
    runtimeLayout.isd_m = topology.InterSiteDistance_m;
    runtimeLayout.wraparoundEnabled = true;
    runtimeLayout.wraparoundMode = "hex_cluster_min_image";
    runtimeLayout.TranslationVectors_m = topology.TranslationVectors_m;
    [runtimeDistance, runtimeDelta] = sixgr.system.GeometryEngine.distanceAndDelta( ...
        [siteXY(origin,:) 1.5], runtimeLayout);
    assert(abs(runtimeDistance(neighbor) - topology.InterSiteDistance_m) < ...
        1e-11*topology.InterSiteDistance_m && ...
        all(isfinite(runtimeDelta), "all"), ...
        "GeometryEngine must use the explicit finite-cluster minimum image.");
    assert(all(runtimeDistance(~(1:numel(runtimeDistance) == origin)) > ...
        1e-11*topology.InterSiteDistance_m), ...
        "GeometryEngine must not collapse a distinct seven-site representative.");

    % Verify config -> ScenarioFactory -> layout propagation of the same
    % explicit basis used by the runtime geometry engine.
    cfgLayout = sixgr.config.defaultConfig();
    if isfield(cfgLayout.scenario, "profiles")
        cfgLayout.scenario = rmfield(cfgLayout.scenario, "profiles");
    end
    cfgLayout.scenario.name = char(deployment(k).id);
    cfgLayout.scenario.profileName = char(deployment(k).id);
    cfgLayout.scenario.geometry = struct( ...
        "area_m", runtimeLayout.area_m, ...
        "wraparound", true, ...
        "wraparoundMode", "hex_cluster_min_image", ...
        "wraparoundTranslationVectors_m", topology.TranslationVectors_m);
    cfgLayout.scenario.layout = struct( ...
        "nSites", 7, "nSectorsPerSite", 3, ...
        "interSiteDistance_m", topology.InterSiteDistance_m);
    cfgLayout = sixgr.config.normalizeConfig(cfgLayout);
    generatedLayout = sixgr.scenario.generateLayout(cfgLayout);
    assert(generatedLayout.nSites == 7 && generatedLayout.nTRxP == 21 && ...
        isequal(generatedLayout.TranslationVectors_m, topology.TranslationVectors_m), ...
        "Explicit finite-cluster vectors must survive config-to-layout resolution.");
    generatedDistance = sixgr.system.GeometryEngine.distanceAndDelta( ...
        [generatedLayout.sites.pos_m(origin,1:2) 1.5], generatedLayout);
    distinctSiteCells = generatedLayout.bs.siteId ~= origin;
    assert(all(generatedDistance(distinctSiteCells) > ...
        1e-11*topology.InterSiteDistance_m), ...
        "Generated runtime layout must not collapse distinct sites.");
end

bad = sixgr.studies.ran1ai1032.buildHexWraparoundTopology(7, 3, 500);
bad.TranslationVectors_m = bad.PrimitiveSiteLattice_m;
localAssertError(@() sixgr.studies.ran1ai1032.validateSLSHexTopology(bad), ...
    "sixgr:ran1ai1032:HexTopologyConformanceFailed");
localAssertError(@() sixgr.scenario.wraparoundDistance([0 0], [1 0], ...
    [10 10], "Mode", "hex_cluster_min_image"), ...
    "sixgr:scenario:MissingClusterTranslationVectors");

ok = true;
fprintf("RAN1_AI_1032_HEX_TOPOLOGY_PASS deployments=%d sites=7 cells=21\n", ...
    numel(deployment));
end

function distance = localBruteForceMinImage(point, sites, basis, radius)
distance = inf(1, size(sites,1));
for i = -radius:radius
    for j = -radius:radius
        shift = [i j] * basis;
        candidate = vecnorm(point - (sites + shift), 2, 2).';
        distance = min(distance, candidate);
    end
end
end

function localAssertError(fcn, expectedID)
caught = false;
try
    fcn();
catch err
    caught = strcmp(err.identifier, expectedID);
end
assert(caught, "Expected error %s.", expectedID);
end
