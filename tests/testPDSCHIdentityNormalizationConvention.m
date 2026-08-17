function ok = testPDSCHIdentityNormalizationConvention()
%TESTPDSCHIDENTITYNORMALIZATIONCONVENTION Generated identity obeys YAML power policy.

setup6GRSimToolkit("Verbose", false);
pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:3;
pdsch.SymbolAllocation = [2 10];
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 2;
pdsch.DMRS.DMRSPortSet = [0 1];

cfg = sixgr.config.defaultConfig();
cfg.mimo.strict = false;
cfg.phy.mimo.strict = false;
cfg.phy.canonicalGrant.enabled = false;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.nPorts = 2;
cfg.phy.pdsch.precoding.matrix = [];
cfg.phy.pdsch.precodingMatrix = [];
cfg.phy.pdsch.W = [];
cfg.phy.pdsch.precoding.normalizationConvention = "unit_frobenius";
cfg.phy.pdsch.precoderNormalizationConvention = "unit_frobenius";

unitTotal = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg);
assert(abs(norm(unitTotal.MatrixPorts, "fro")^2 - 1) < 1e-12 && ...
    string(unitTotal.NormalizationConvention) == "unit_frobenius", ...
    "A generated rank-2 identity must allocate unit total transmit power across layers.");

cfg.phy.pdsch.precoding.normalizationConvention = "semi_unitary";
cfg.phy.pdsch.precoderNormalizationConvention = "semi_unitary";
semiUnitary = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg);
assert(norm(semiUnitary.MatrixPorts' * semiUnitary.MatrixPorts - eye(2), "fro") < 1e-12, ...
    "A generated semi-unitary identity must preserve one unit-power column per layer.");

ok = true;
end
