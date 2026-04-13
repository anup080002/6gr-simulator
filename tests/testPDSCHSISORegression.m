function ok = testPDSCHSISORegression()
%TESTPDSCHSISOREGRESSION Keep the 1x1 PDSCH path on the legacy fast map.

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
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = 'QPSK';
cfg.phy.pdsch.codeRate = 0.3;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.enablePTRS = false;

[tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg);
assert(~logical(txInfo.Precoding.Active), "SISO path must bypass explicit precoding.");
assert(string(txInfo.Precoding.Mode) == "siso-bypass", "Unexpected SISO precoding mode.");
assert(size(tx.Grid, 3) == 1, "SISO grid must remain single-port.");

txDataSym = nrPDSCH(tx.Carrier, tx.PDSCH, {tx.Codeword});
gridDataSym = tx.Grid(tx.PDSCHIndices);
assert(max(abs(gridDataSym(:) - txDataSym(:))) < 1e-10, ...
    "SISO PDSCH symbols no longer map directly to the resource grid.");

rx = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV);

assert(rx.Ok, "SISO PDSCH round-trip must decode successfully.");
assert(isequal(int8(rx.TransportBlock(:)), int8(tx.TransportBlock(:))), ...
    "SISO PDSCH round-trip changed the recovered transport block.");
ok = true;
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPDSCHPrecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2;
end
