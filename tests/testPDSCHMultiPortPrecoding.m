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
cfg.phy.nTxAnt = 4;
cfg.channel.nTxAnt = 4;

W = [ ...
    1  0; ...
    0  1; ...
    1  1; ...
    1 -1];

[tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, "PrecodingMatrix", W);
portContract = txInfo.ResourceGridPortContract;
assert(logical(txInfo.Precoding.Active), "Multi-layer DL path must enable explicit precoding.");
assert(string(txInfo.Precoding.Mode) == "explicit-wideband", "Unexpected explicit precoding mode.");
assert(string(txInfo.Precoding.Source) == "explicit-matrix", "Explicit matrix source was not recorded.");
assert(txInfo.Precoding.NumLayers == 2, "Unexpected layer count in precoding info.");
assert(txInfo.Precoding.NumPorts == 4, "Unexpected antenna-port count in precoding info.");
assert(size(tx.Grid, 3) >= 4, ...
    "Precoded PDSCH grid must expose at least the four antenna ports used by explicit PDSCH precoding.");
assert(size(tx.PDSCHAntennaIndices, 2) == 4, "Precoded PDSCH indices must be antenna-oriented.");
assert(size(tx.DMRSAntennaIndices, 2) == 4, "Precoded DMRS indices must be antenna-oriented.");
assert(portContract.PDSCHAntennaPortCount == 4 && portContract.DMRSAntennaPortCount == 4, ...
    "Port contract must report the true PDSCH and DM-RS antenna-port counts.");
assert(logical(portContract.PrecodingPortAlignmentOk) && logical(portContract.PDSCHDMRSPortAlignmentOk), ...
    "Port contract must confirm truthful precoding and DM-RS alignment.");
assert(logical(portContract.ResourceSelectiveChannelEstimateRequired), ...
    "Multi-port DL mapping must require resource-selective channel estimation.");
assert(portContract.GridNumPages >= portContract.PrimarySignalPortCount, ...
    "Full transmit-grid page count must never under-report the primary signal ports.");

portSym = nrPDSCH(tx.Carrier, tx.PDSCH, {tx.Codeword});
[expAntSym, expAntInd] = nrPDSCHPrecode(tx.Carrier, portSym, tx.PDSCHIndices, txInfo.Precoding.MatrixNR);
assert(isequal(tx.PDSCHAntennaIndices, expAntInd), ...
    "PDSCH antenna indices do not match the explicit precoding stage.");
assert(max(abs(tx.PDSCHAntennaSymbols(:) - expAntSym(:))) < 1e-10, ...
    "PDSCH antenna symbols do not match the explicit precoding stage.");

cfgReserved = cfg;
cfgReserved.phy.csirs.enable = true;
cfgReserved.phy.csirs.nPorts = 1;
cfgReserved.phy.csirs.rowNumber = 2;
cfgReserved.phy.csirs.rbOffset = 0;
cfgReserved.phy.csirs.numRB = 7;
cfgReserved.phy.csirs.symbolLocations = 5;
cfgReserved.phy.csirs.subcarrierLocations = 0;
[txReserved, ~] = sixgr.phy.dl.PDSCH_Tx(cfgReserved, "PrecodingMatrix", W);
assert(size(txReserved.PDSCHSymbols, 1) == size(txReserved.PDSCHIndices, 1), ...
    "Reserved-resource PDSCH rate matching must generate one symbol per scheduled data RE.");
assert(size(txReserved.PDSCHAntennaSymbols, 1) == size(txReserved.PDSCHAntennaIndices, 1), ...
    "Reserved-resource PDSCH precoding must preserve symbol/index size equality.");
assert(numel(txReserved.Codeword) == double(txReserved.G), ...
    "Reserved-resource PDSCH codeword length must use the exact nrPDSCHIndices data-bit budget.");

[rx, info] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
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
assert(strcmp(string(info.ChannelEstimation.EngineUsed), "nrChannelEstimate") && ...
    ~logical(info.ChannelEstimation.ScalarFastPathUsed), ...
    "Explicitly precoded multi-port PDSCH must stay on resource-selective channel estimation.");

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
