function ok = testPUSCHScramblingNIDFallback()
%TESTPUSCHSCRAMBLINGNIDFALLBACK Match nrPUSCH's empty-NID ownership.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if exist("nrPUSCH", "file") ~= 2 || exist("nrPUSCHScramble", "file") ~= 2
    warning("testPUSCHScramblingNIDFallback:Missing5G", ...
        "Skipping because required 5G Toolbox PUSCH APIs are unavailable.");
    ok = true;
    return;
end

cfg = localConfig();
carrier = nrCarrierConfig;
carrier.NCellID = 321;
carrier.NSizeGrid = 12;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";

pusch = nrPUSCHConfig;
pusch.NID = [];
pusch.RNTI = 77;
pusch.PRBSet = 0:5;
pusch.SymbolAllocation = [0 14];
pusch.MappingType = "A";
pusch.Modulation = "QPSK";
pusch.NumLayers = 1;
pusch.TransmissionScheme = "nonCodebook";
pusch.TransformPrecoding = false;
pusch.EnablePTRS = false;
pusch.DMRS.DMRSConfigurationType = 1;
pusch.DMRS.DMRSTypeAPosition = 2;
pusch.DMRS.DMRSAdditionalPosition = 1;
pusch.DMRS.DMRSLength = 1;
pusch.DMRS.NumCDMGroupsWithoutData = 2;

rng(38101, "twister");
[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "TargetCodeRate", 0.30, ...
    "RV", 0, ...
    "NumTxAnt", 1, ...
    "CompactOutput", false);
toolboxSymbols = nrPUSCH(carrier, pusch, tx.Codeword);

assert(isequal(size(tx.PUSCHPortSymbols), size(toolboxSymbols)), ...
    "PUSCH port-symbol evidence shape must match nrPUSCH.");
assert(max(abs(tx.PUSCHPortSymbols(:) - toolboxSymbols(:))) < 1e-12, ...
    ["When PUSCH.NID is empty, reconstructed layer/port symbols must use " ...
     "carrier.NCellID exactly as nrPUSCH does."]);

fprintf("PUSCHScramblingNIDFallback: empty PUSCH.NID inherited carrier.NCellID=%d.\n", ...
    carrier.NCellID);
ok = true;
end

function cfg = localConfig()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.run.useMex = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.antenna.ue.numElements = 1;
cfg.phy.pusch.transformPrecoding = false;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.pusch.transmissionScheme = "nonCodebook";
cfg.phy.channelEstimation.method = "LS";
end
