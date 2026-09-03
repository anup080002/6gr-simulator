function ok = testCSIRSMultiResourceYAMLAuthority()
%TESTCSIRSMULTIRESOURCEYAMLAUTHORITY Reload and preserve the full CSI-RS set.

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@()rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

assert(double(sixgr.util.structGet(cfg, "phy.csirs.nPorts", NaN)) == 2, ...
    "The YAML-owned two-port CSI-RS configuration was not materialized.");
assert(double(sixgr.util.structGet(cfg, "phy.csirs.numResources", NaN)) == 8, ...
    "All eight YAML-owned CSI-RS resources must survive config resolution.");
resourceIDs = double(sixgr.util.structGet(cfg, "phy.csirs.resourceIDs", []));
assert(isequal(resourceIDs(:).', 0:7), ...
    "CSI-RS resource identities must remain exact and ordered.");
rowNumbers = double(sixgr.util.structGet(cfg, "phy.csirs.rowNumbers", []));
assert(isequal(rowNumbers(:).', repmat(3, 1, 8)), ...
    ["Two-port CSI-RS must preserve YAML Row 3 from TS 38.211 " ...
     "Table 7.4.1.5.3-1 without a runtime replacement."]);
symbolLocations = double(sixgr.util.structGet(cfg, "phy.csirs.symbolLocationsByResource", []));
assert(isequal(symbolLocations(:).', ...
    [9 9 9 10 10 10 11 11]), ...
    "CSI-RS symbol locations must come from YAML without a runtime replacement.");
subcarrierLocations = double(sixgr.util.structGet(cfg, ...
    "phy.csirs.subcarrierLocationsByResource", []));
assert(isequal(subcarrierLocations(:).', [0 4 8 0 4 8 0 4]), ...
    ["Two-port Row-3 CSI-RS resources must retain disjoint YAML k0 " ...
     "placements without a runtime replacement."]);
W = sixgr.util.structGet(cfg, "phy.csirs.precoderMatrices", []);
assert(isequal(size(W), [64 2 8]), ...
    "The YAML-owned CSI-RS codebook must materialize as 64-by-2-by-8.");
for k = 1:size(W, 3)
    gram = W(:,:,k)' * W(:,:,k);
    assert(norm(gram - eye(2), 'fro') < 1e-12, ...
        "CSI-RS resource %d does not have unit-norm orthogonal logical ports.", k - 1);
end

% A one-resource YAML set must consume the same per-resource placement
% fields.  This guards against silently using the nrCSIRSConfig symbol-0
% default when numResources happens to equal one.
carrier = nrCarrierConfig;
carrier.NSizeGrid = 24;
carrier.SubcarrierSpacing = 30;
single = struct();
single.phy.csirs.enable = true;
single.phy.csirs.numResources = 1;
single.phy.csirs.nPorts = 4;
single.phy.csirs.resourceIDs = 7;
single.phy.csirs.rowNumbers = 4;
single.phy.csirs.symbolLocationsByResource = 9;
single.phy.csirs.subcarrierLocationsByResource = 0;
single.phy.csirs.rbOffsetsByResource = 0;
single.phy.csirs.numRBsByResource = 24;
[indices, ~, info] = sixgr.phy.refsig.csirs(carrier, single, ...
    "IndexBase", "1based");
[~, symbolIndex, portIndex] = ind2sub( ...
    [12 * carrier.NSizeGrid carrier.SymbolsPerSlot 4], ...
    double(indices(:)));
assert(all((symbolIndex - 1) == 9, "all"), ...
    "Single-resource CSI-RS indices did not preserve YAML symbol location 9.");
assert(isequal(unique(double(portIndex(:))).', 1:4), ...
    "Single-resource CSI-RS did not materialize all four configured ports.");
assert(isequal(double(info.SymbolLocations(:).'), 9), ...
    "Single-resource CSI-RS did not preserve YAML symbol location 9.");

ok = true;
end
