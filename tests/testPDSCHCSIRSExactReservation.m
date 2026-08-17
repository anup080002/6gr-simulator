function ok = testPDSCHCSIRSExactReservation()
%TESTPDSCHCSIRSEXACTRESERVATION CSI-RS uses exact RE ownership, not PRB erasure.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.pdsch.prbSet = 0;
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.dmrs.typeApos = 2;
cfg.phy.pdsch.dmrs.configType = 1;
cfg.phy.pdsch.dmrs.additionalPositions = 0;
cfg.phy.pdsch.dmrs.maxLength = 1;
cfg.phy.pdsch.dmrs.nPorts = 2;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.csirs.enable = true;
cfg.phy.csirs.nPorts = 4;
cfg.phy.csirs.numResources = 1;
cfg.phy.csirs.resourceID = 0;
cfg.phy.csirs.rowNumber = 4;
cfg.phy.csirs.symbolLocations = 3;
cfg.phy.csirs.subcarrierLocations = 0;
cfg.phy.csirs.rbOffset = 0;
cfg.phy.csirs.numRB = 24;

carrier = sixgr.phy.grid.makeCarrier(cfg);
[dataInd, ~, pdsch] = sixgr.phy.grid.allocREsPDSCH( ...
    carrier, cfg, "IndexBase", "0based", "PRBSet", 0, ...
    "SymbolAllocation", [2 12], "NumLayers", 2, ...
    "Modulation", "QPSK", "MappingType", "A");

assert(iscell(pdsch.ReservedPRB) && all(cellfun( ...
    @(x) isempty(x.PRBSet) && isempty(x.SymbolSet), pdsch.ReservedPRB)), ...
    "Sparse CSI-RS must not add a whole-PRB reservation.");
assert(~isempty(pdsch.ReservedRE), ...
    "An in-allocation CSI-RS resource must create exact ReservedRE entries.");
[csirsInd, ~] = sixgr.phy.refsig.csirs(carrier, cfg, "IndexBase", "0based");
plane = double(carrier.NSizeGrid) * 12 * double(carrier.SymbolsPerSlot);
expected = unique(mod(double(csirsInd(:)), plane), "sorted");
expected = expected(floor(mod(expected, 12 * double(carrier.NSizeGrid)) / 12) == 0);
assert(isequal(double(pdsch.ReservedRE(:)), expected(:)), ...
    "PDSCH ReservedRE must equal the exact CSI-RS base-plane RE set inside the grant.");

dmrsSub = nrPDSCHDMRSIndices(carrier, pdsch, ...
    "IndexStyle", "subscript", "IndexBase", "0based");
dmrsBase = unique(double(dmrsSub(:,1) + ...
    12 * double(carrier.NSizeGrid) * dmrsSub(:,2)));
dataBase = unique(mod(double(dataInd(:)), plane));
assert(~isempty(dmrsBase), "Exact CSI-RS reservation must preserve active PDSCH DM-RS.");
assert(isempty(intersect(dmrsBase, double(pdsch.ReservedRE(:)))) && ...
    isempty(intersect(dataBase, double(pdsch.ReservedRE(:)))), ...
    "PDSCH data/DM-RS and exact CSI-RS ownership must be disjoint.");

colliding = cfg;
colliding.phy.csirs.symbolLocations = 2;
try
    sixgr.phy.grid.allocREsPDSCH(carrier, colliding, ...
        "IndexBase", "0based", "PRBSet", 0, ...
        "SymbolAllocation", [2 12], "NumLayers", 2, ...
        "Modulation", "QPSK", "MappingType", "A");
    error("testPDSCHCSIRSExactReservation:MissingCollisionGuard", ...
        "A CSI-RS/PDSCH-DM-RS collision must fail closed.");
catch ME
    assert(strcmp(ME.identifier, ...
        "sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision"), ...
        "Unexpected CSI-RS/DM-RS collision failure: %s", ME.identifier);
end

ok = true;
end
