function ok = testPDSCHMultiPortPrecoding()
%TESTPDSCHMULTIPORTPRECODING Regression checks for explicit DL precoding.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.carrier.NSizeGrid = 18;
cfg.phy.pdsch.prbSet = 0:7;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = 'QPSK';
cfg.phy.pdsch.codeRate = 0.35;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.enablePTRS = false;

W = [ ...
    1  0; ...
    0  1; ...
    1  1; ...
    1 -1];

[tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, "PrecodingMatrix", W);
assert(logical(txInfo.Precoding.Active), "Multi-layer DL path must enable explicit precoding.");
assert(string(txInfo.Precoding.Mode) == "explicit-wideband", "Unexpected explicit precoding mode.");
assert(string(txInfo.Precoding.Source) == "explicit-matrix", "Explicit matrix source was not recorded.");
assert(txInfo.Precoding.NumLayers == 2, "Unexpected layer count in precoding info.");
assert(txInfo.Precoding.NumPorts == 4, "Unexpected antenna-port count in precoding info.");
assert(size(tx.Grid, 3) == 4, "Precoded PDSCH grid must expose four antenna ports.");
assert(size(tx.PDSCHAntennaIndices, 2) == 4, "Precoded PDSCH indices must be antenna-oriented.");
assert(size(tx.DMRSAntennaIndices, 2) == 4, "Precoded DMRS indices must be antenna-oriented.");

portSym = nrPDSCH(tx.Carrier, tx.PDSCH, {tx.Codeword});
[expAntSym, expAntInd] = nrPDSCHPrecode(tx.Carrier, portSym, tx.PDSCHIndices, txInfo.Precoding.MatrixNR);
assert(isequal(tx.PDSCHAntennaIndices, expAntInd), ...
    "PDSCH antenna indices do not match the explicit precoding stage.");
assert(max(abs(tx.PDSCHAntennaSymbols(:) - expAntSym(:))) < 1e-10, ...
    "PDSCH antenna symbols do not match the explicit precoding stage.");

rx = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "PrecodingMatrix", W);

assert(rx.Ok, "Explicitly precoded multi-port PDSCH must decode successfully.");
assert(isequal(int8(rx.TransportBlock(:)), int8(tx.TransportBlock(:))), ...
    "Explicitly precoded multi-port PDSCH changed the recovered transport block.");

cfgGuard = cfg;
cfgGuard.phy.pdsch.nLayers = 5;
cfgGuard.phy.pdsch.numLayers = 5;
try
    sixgr.phy.dl.PDSCH_Tx(cfgGuard, "PrecodingMatrix", eye(5));
    error("testPDSCHMultiPortPrecoding:MissingGuard", ...
        "Expected the single-codeword guard for NumLayers > 4.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported"), ...
        "Unexpected guard failure for unsupported multi-codeword PDSCH: %s", ME.identifier);
end

ok = true;
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPDSCHPrecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2;
end
