function ok = testCompactPHYIOMeasuredTBCRC()
%TESTCOMPACTPHYIOMEASUREDTBCRC Keep compact PHY IO from dropping measured TB/CRC evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

if ~localHaveRequired5G()
    ok = true;
    return;
end

localAssertCompactPDSCH();
localAssertCompactPUSCH();

ok = true;
end

function localAssertCompactPDSCH()
cfg = localBaseCfg();
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.nPorts = 1;
cfg.phy.pdsch.dmrs.nPorts = 1;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.mcs = 1;
cfg.phy.csirs.enabled = false;
cfg.phy.csirs.nPorts = 1;

carrier = sixgr.phy.grid.makeCarrier(cfg);
pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:5;
pdsch.SymbolAllocation = [0 10];
pdsch.MappingType = "A";
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 1;
pdsch.RNTI = 1;
pdsch.NID = 1;
try
    pdsch.DMRS.DMRSPortSet = 0;
catch
end

[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
    "Carrier", carrier, ...
    "PDSCH", pdsch, ...
    "NumTxAnt", 1, ...
    "CompactOutput", true);
[rx, ~] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "NoiseVar", 1e-12, ...
    "NoiseVarDomain", "time", ...
    "CompactOutput", true, ...
    "FastAWGNPath", true, ...
    "SkipTimingEstimate", true);

localAssertCompactCRCAndBits(tx, rx, "DL PDSCH");
assert(logical(rx.StrictReceiverEvidenceOk) && logical(rx.DecodeUsable), ...
    "Compact DL PDSCH must keep enough measured evidence for strict receiver validation.");
end

function localAssertCompactPUSCH()
cfg = localBaseCfg();
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.numPorts = 1;
cfg.phy.pusch.nPorts = 1;
cfg.phy.pusch.dmrs.nPorts = 1;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.mcs = 1;
cfg.phy.pusch.transformPrecoding = false;

carrier = sixgr.phy.grid.makeCarrier(cfg);
pusch = nrPUSCHConfig;
pusch.PRBSet = 0:5;
pusch.SymbolAllocation = [0 10];
pusch.MappingType = "A";
pusch.Modulation = "QPSK";
pusch.NumLayers = 1;
pusch.RNTI = 1;
pusch.NID = 1;
try
    pusch.NumAntennaPorts = 1;
catch
end
try
    pusch.DMRS.DMRSPortSet = 0;
catch
end

[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "NumTxAnt", 1, ...
    "CompactOutput", true);
[rx, ~] = sixgr.phy.ul.PUSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PUSCH", tx.PUSCH, ...
    "PUSCHIndices", tx.PUSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "NoiseVar", 1e-12, ...
    "NoiseVarDomain", "time", ...
    "CompactOutput", true, ...
    "FastAWGNPath", true, ...
    "SkipTimingEstimate", true);

localAssertCompactCRCAndBits(tx, rx, "UL PUSCH");
assert(logical(rx.StrictReceiverEvidenceOk) && logical(rx.DecodeUsable), ...
    "Compact UL PUSCH must keep enough measured evidence for strict receiver validation.");
end

function cfg = localBaseCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.noProxyTruthContract = true;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 45;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.antenna.ue.numElements = 1;
cfg.antenna.bs.numElements = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.rx.useIdealTimingSync = true;
cfg.phy.channelEstimation.method = "LS";
end

function localAssertCompactCRCAndBits(tx, rx, label)
assert(isfield(tx, "TransportBlock") && isfield(rx, "TransportBlock"), ...
    "%s compact path must retain measured TX and RX transport blocks.", label);
assert(logical(rx.Ok) && logical(rx.CRCPass) && ~logical(rx.CRCError), ...
    "%s compact path must expose measured TB CRC pass.", label);
assert(numel(tx.TransportBlock) == numel(rx.TransportBlock) && ...
    all(int8(tx.TransportBlock(:)) == int8(rx.TransportBlock(:))), ...
    "%s compact path must recover a bit-exact transport block in near-noiseless AWGN.", label);
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPUSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPUSCHDecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2 ...
    && exist("nrOFDMDemodulate", "file") == 2;
end
