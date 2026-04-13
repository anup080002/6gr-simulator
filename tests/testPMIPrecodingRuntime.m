function ok = testPMIPrecodingRuntime()
%TESTPMIPRECODINGRUNTIME Verify configured PMI drives actual DL precoding.

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
cfg = sixgr.util.structSet(cfg, "phy.pdsch.numPorts", 4);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.PMI", 0);
cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo");
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", "type1");

[tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg);
assert(logical(txInfo.Precoding.Active), "Configured PMI must activate actual DL precoding.");
assert(string(txInfo.Precoding.Source) == "pmi-codebook", "PMI-driven precoding must be labeled honestly.");
assert(txInfo.Precoding.NumLayers == 2, "Unexpected layer count in PMI-driven precoding.");
assert(txInfo.Precoding.NumPorts == 4, "Unexpected port count in PMI-driven precoding.");

rx = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV);

assert(rx.Ok, "PMI-driven wideband precoding must decode successfully.");
assert(isequal(int8(rx.TransportBlock(:)), int8(tx.TransportBlock(:))), ...
    "PMI-driven precoding changed the recovered transport block.");

ok = true;
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPDSCHPrecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2;
end
