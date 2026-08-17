function ok = testCSIRSMultiResourceYAMLAuthority()
%TESTCSIRSMULTIRESOURCEYAMLAUTHORITY Reload and preserve the full CSI-RS set.

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@()rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

assert(double(sixgr.util.structGet(cfg, "phy.csirs.nPorts", NaN)) == 4, ...
    "The YAML-owned four-port CSI-RS configuration was not materialized.");
assert(double(sixgr.util.structGet(cfg, "phy.csirs.numResources", NaN)) == 8, ...
    "All eight YAML-owned CSI-RS resources must survive config resolution.");
resourceIDs = double(sixgr.util.structGet(cfg, "phy.csirs.resourceIDs", []));
assert(isequal(resourceIDs(:).', 0:7), ...
    "CSI-RS resource identities must remain exact and ordered.");
rowNumbers = double(sixgr.util.structGet(cfg, "phy.csirs.rowNumbers", []));
assert(isequal(rowNumbers(:).', repmat(3, 1, 8)), ...
    "CSI-RS row numbers must come from YAML without a runtime replacement.");
symbolLocations = double(sixgr.util.structGet(cfg, "phy.csirs.symbolLocationsByResource", []));
assert(isequal(symbolLocations(:).', ...
    [10 10 10 10 11 11 11 11]), ...
    "CSI-RS symbol locations must come from YAML without a runtime replacement.");
W = sixgr.util.structGet(cfg, "phy.csirs.precoderMatrices", []);
assert(isequal(size(W), [64 4 8]), ...
    "The YAML-owned CSI-RS codebook must materialize as 64-by-4-by-8.");
for k = 1:size(W, 3)
    gram = W(:,:,k)' * W(:,:,k);
    assert(norm(gram - eye(4), 'fro') < 1e-12, ...
        "CSI-RS resource %d does not have unit-norm orthogonal logical ports.", k - 1);
end

ok = true;
end
