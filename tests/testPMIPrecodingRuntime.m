function ok = testPMIPrecodingRuntime()
%TESTPMIPRECODINGRUNTIME Verify configured PMI drives actual waveform precoding.

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

cfgUL = sixgr.config.defaultConfig();
cfgUL.run.shortRun = true;
cfgUL.outputs.saveCSV = false;
cfgUL.outputs.saveMAT = false;
cfgUL.outputs.saveFigures = false;
cfgUL.phy.carrier.NSizeGrid = 18;
cfgUL.phy.pusch.prbSet = 0:7;
cfgUL.phy.pusch.symbolAllocation = [0 10];
cfgUL.phy.pusch.modulation = 'QPSK';
cfgUL.phy.pusch.codeRate = 0.35;
cfgUL.phy.pusch.transformPrecoding = false;
cfgUL.phy.pusch.nLayers = 2;
cfgUL.phy.pusch.numLayers = 2;
cfgUL.phy.nTxAnt = 4;
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.numPorts", 4);
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.PMI", 1);
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.TPMI", 1);

[txUL, txULInfo] = sixgr.phy.ul.PUSCH_Tx(cfgUL);
assert(logical(txULInfo.Precoding.Active), "Configured UL TPMI must activate native PUSCH codebook precoding.");
assert(string(txULInfo.Precoding.Source) == "ul_pusch_native_codebook_tpmi", ...
    "UL TPMI-driven precoding must be labeled as native PUSCH codebook application.");
assert(txULInfo.Precoding.PMI == 1, "UL applied precoder PMI must come from the runtime PUSCH TPMI.");
assert(txULInfo.Precoding.NumLayers == 2, "Unexpected UL layer count in PMI-driven precoding.");
assert(txULInfo.Precoding.NumPorts == 4, "Unexpected UL antenna-port count in PMI-driven precoding.");
assert(size(txUL.Grid, 3) == 4 && size(txUL.PUSCHIndices, 2) == 4, ...
    "PMI-driven UL PUSCH grid and indices must expose the runtime antenna-port mapping.");

rxUL = sixgr.phy.ul.PUSCH_Rx(txUL.Waveform, cfgUL, ...
    "Carrier", txUL.Carrier, ...
    "PUSCH", txUL.PUSCH, ...
    "PUSCHIndices", txUL.PUSCHIndices, ...
    "TransportBlockSize", txUL.TransportBlockSize, ...
    "TargetCodeRate", txUL.TargetCodeRate, ...
    "RV", txUL.RV);

assert(rxUL.Ok, "PMI-driven native-codebook PUSCH must decode successfully.");
assert(isequal(int8(rxUL.TransportBlock(:)), int8(txUL.TransportBlock(:))), ...
    "PMI-driven native-codebook PUSCH changed the recovered transport block.");

ok = true;
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPDSCHPrecode", "file") == 2 ...
    && exist("nrPUSCH", "file") == 2 ...
    && exist("nrPUSCHDecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2;
end
