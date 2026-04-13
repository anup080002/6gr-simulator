function ok = testChannelEstimationValidation()
%TESTCHANNELESTIMATIONVALIDATION Guard scalar shortcuts vs truth estimation.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

localTestAWGNFastPathAllowed();
localTestStrictTDLDisallowsScalarShortcut();
localTestTDLRequestedFastMexUsesSelectiveEstimator();

ok = true;
end

function localTestAWGNFastPathAllowed()
cfg = localBasicPDSCHCfg();
cfg.run.strictMode = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.model = "";
cfg.channel.fading.profile = "";
cfg.channel.awgnOnly = true;

[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);
[rx, info] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "FastAWGNPath", true);

assert(rx.Ok, "Explicit AWGN SISO smoke mode must allow the fast scalar shortcut.");
assert(isequal(int8(rx.TransportBlock(:)), int8(tx.TransportBlock(:))), ...
    "Fast AWGN shortcut changed the recovered PDSCH transport block.");
assert(strcmp(string(info.ChannelEstimation.EngineUsed), "unit-flat-shortcut"), ...
    "Fast AWGN shortcut should record the unit-flat estimator path.");
end

function localTestStrictTDLDisallowsScalarShortcut()
cfg = localBasicPUSCHCfg();
cfg.run.strictMode = true;
cfg.run.useMex = true;
cfg.phy.rx.useFastChannelEstMex = true;
cfg.channel.model = "TDL";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.fading.model = "TDL";
cfg.channel.fading.profile = "TDL-C";

[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg);
threw = false;
try
    sixgr.phy.ul.PUSCH_Rx(tx.Waveform, cfg, ...
        "Carrier", tx.Carrier, ...
        "PUSCH", tx.PUSCH, ...
        "PUSCHIndices", tx.PUSCHIndices, ...
        "TransportBlockSize", tx.TransportBlockSize, ...
        "TargetCodeRate", tx.TargetCodeRate, ...
        "RV", tx.RV);
catch ME
    threw = strcmp(ME.identifier, "sixgr:phy:channelEstimate:InvalidScalarFastPath");
    assert(contains(string(ME.message), "resource-selective estimator"), ...
        "Strict fading rejection should explain why scalar estimation is invalid.");
end
assert(threw, ...
    "Strict TDL/CDL truth validation must reject the scalar fast channel estimator.");
end

function localTestTDLRequestedFastMexUsesSelectiveEstimator()
cfg = localBasicPDSCHCfg();
cfg.run.useMex = true;
cfg.phy.rx.useFastChannelEstMex = true;
cfg.channel.model = "TDL";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.fading.model = "TDL";
cfg.channel.fading.profile = "TDL-C";

[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPDSCH(tx.Carrier, tx.PDSCH);
[rxGrid, ~] = sixgr.phy.waveform.ofdmDemodulate(tx.Carrier, tx.Waveform);
[Hest, ~, estInfo] = sixgr.phy.rx.channelEstimate(tx.Carrier, rxGrid, dmrsInd, dmrsSym, ...
    "UseFastMex", true, ...
    "StrictMode", false, ...
    "ChannelModel", "TDL-C", ...
    "ExpectedTxPorts", 1, ...
    "ContextLabel", "testChannelEstimationValidation");

assert(~isempty(Hest), "Selective truth estimation should still return a channel estimate.");
assert(strcmp(string(estInfo.EngineUsed), "nrChannelEstimate"), ...
    "Selective fading truth validation must stay on nrChannelEstimate when scalar MEX is requested.");
assert(~logical(estInfo.ScalarFastPathUsed), ...
    "Selective fading truth validation must not silently use the scalar fast path.");
assert(contains(string(estInfo.ScalarFastPathDisabledReason), "Selective fading"), ...
    "Selective truth validation should record why the scalar shortcut was disabled.");
end

function cfg = localBasicPDSCHCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = 'QPSK';
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.enablePTRS = false;
end

function cfg = localBasicPUSCHCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.pusch.prbSet = 0:5;
cfg.phy.pusch.symbolAllocation = [0 10];
cfg.phy.pusch.modulation = 'QPSK';
cfg.phy.pusch.codeRate = 0.30;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.transformPrecoding = true;
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPUSCH", "file") == 2 ...
    && exist("nrPUSCHDecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2 ...
    && exist("nrOFDMDemodulate", "file") == 2;
end
