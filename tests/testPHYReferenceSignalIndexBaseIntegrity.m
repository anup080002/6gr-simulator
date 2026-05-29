function ok = testPHYReferenceSignalIndexBaseIntegrity()
%TESTPHYREFERENCESIGNALINDEXBASEINTEGRITY Guard payload/RS index-base alignment.

setup6GRSimToolkit("Verbose", false);
cfg = localBaseCfg();

[txDL, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);
assert(isempty(intersect(txDL.PDSCHIndices(:), txDL.DMRSIndices(:))), ...
    "PDSCH data REs must not collide with PDSCH DM-RS REs.");
[rxDL, ~] = sixgr.phy.dl.PDSCH_Rx(txDL.Waveform, cfg, ...
    "Carrier", txDL.Carrier, ...
    "PDSCH", txDL.PDSCH, ...
    "PDSCHIndices", txDL.PDSCHIndices, ...
    "TransportBlockSize", txDL.TransportBlockSize, ...
    "TargetCodeRate", txDL.TargetCodeRate, ...
    "RV", txDL.RV, ...
    "NoiseVar", 0, ...
    "FastAWGNPath", true, ...
    "SkipTimingEstimate", true);
localAssertBitExact(txDL.TransportBlock, rxDL.TransportBlock, rxDL.Ok, "PDSCH");

[txUL, ~] = sixgr.phy.ul.PUSCH_Tx(cfg);
assert(isempty(intersect(txUL.PUSCHIndices(:), txUL.DMRSIndices(:))), ...
    "PUSCH data REs must not collide with PUSCH DM-RS REs.");
[rxUL, ~] = sixgr.phy.ul.PUSCH_Rx(txUL.Waveform, cfg, ...
    "Carrier", txUL.Carrier, ...
    "PUSCH", txUL.PUSCH, ...
    "PUSCHIndices", txUL.PUSCHIndices, ...
    "TransportBlockSize", txUL.TransportBlockSize, ...
    "TargetCodeRate", txUL.TargetCodeRate, ...
    "RV", txUL.RV, ...
    "NoiseVar", 1e-12, ...
    "ConfiguredNoiseVariance", 1e-12, ...
    "FastAWGNPath", true, ...
    "SkipTimingEstimate", true);
localAssertBitExact(txUL.TransportBlock, rxUL.TransportBlock, rxUL.Ok, "PUSCH");

ok = true;
end

function cfg = localBaseCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.tdlProfile = "";
cfg.channel.cdlProfile = "";
cfg.channel.fading.profile = "";
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.nTxAnt = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.phy.csirs.enable = false;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.PMI = NaN;
cfg.phy.pdsch.modulation = "256QAM";
cfg.phy.pdsch.codeRate = 0.75;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.PMI = NaN;
cfg.phy.pusch.tpmi = NaN;
cfg.phy.pusch.NumAntennaPorts = 1;
cfg.phy.pusch.numAntennaPorts = 1;
cfg.phy.pusch.modulation = "256QAM";
cfg.phy.pusch.codeRate = 0.75;
end

function localAssertBitExact(txBits, rxBits, okFlag, label)
assert(logical(okFlag), "%s CRC must pass in near-noiseless AWGN.", label);
assert(numel(txBits) == numel(rxBits), "%s recovered TB length must match transmit TB length.", label);
assert(all(int8(txBits(:)) == int8(rxBits(:))), "%s recovered TB must be bit-exact.", label);
end
