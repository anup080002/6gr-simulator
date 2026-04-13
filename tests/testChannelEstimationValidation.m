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
localTestZeroReferenceSymbolsFailClosed();
localTestMixedZeroReferenceSymbolsPrunedWithoutWarning();
localTestPUSCHRxNoZeroReferenceWarning();

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

function localTestZeroReferenceSymbolsFailClosed()
cfg = localBasicPUSCHCfg();
[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg);
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPUSCH(tx.Carrier, tx.PUSCH);
[rxGrid, ~] = sixgr.phy.waveform.ofdmDemodulate(tx.Carrier, tx.Waveform);

lastwarn("");
threw = false;
try
    sixgr.phy.rx.channelEstimate(tx.Carrier, rxGrid, dmrsInd, zeros(size(dmrsSym), "like", dmrsSym), ...
        "ChannelModel", "AWGN", ...
        "ExpectedTxPorts", 1, ...
        "ContextLabel", "testChannelEstimationValidation");
catch ME
    threw = strcmp(ME.identifier, "sixgr:phy:channelEstimate:InvalidReference");
    assert(contains(string(ME.message), "no non-zero reference symbols"), ...
        "Zero-reference failure must explain the missing DMRS/CSI-RS evidence.");
end
[msg, id] = lastwarn;
assert(threw, "Zero reference symbols must fail closed before nrChannelEstimate is called.");
assert(strlength(string(msg)) == 0 && strlength(string(id)) == 0, ...
    "Zero reference symbols should not leak as a MATLAB nrChannelEstimate warning.");
end

function localTestMixedZeroReferenceSymbolsPrunedWithoutWarning()
cfg = localBasicPUSCHCfg();
[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg);
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPUSCH(tx.Carrier, tx.PUSCH);
[rxGrid, ~] = sixgr.phy.waveform.ofdmDemodulate(tx.Carrier, tx.Waveform);

dmrsSymWithZeros = dmrsSym;
zeroMask = false(size(dmrsSymWithZeros));
zeroMask(1:2:end) = true;
dmrsSymWithZeros(zeroMask) = 0;
expectedZeroCount = nnz(zeroMask);

lastwarn("");
[Hest, ~, estInfo] = sixgr.phy.rx.channelEstimate(tx.Carrier, rxGrid, dmrsInd, dmrsSymWithZeros, ...
    "ChannelModel", "AWGN", ...
    "ExpectedTxPorts", 1, ...
    "ContextLabel", "testChannelEstimationValidation");
[msg, id] = lastwarn;

assert(~isempty(Hest), "Mixed zero/nonzero PUSCH DM-RS evidence should still produce Hest from nonzero references.");
assert(logical(estInfo.PrunedZeroReferenceSymbols), ...
    "Channel estimator should record that zero-valued reference entries were pruned.");
assert(double(estInfo.ZeroReferenceSymbolCount) == expectedZeroCount, ...
    "Channel estimator should record the exact zero reference symbol count.");
assert(double(estInfo.ReferenceSymbolsUsedCount) == numel(dmrsSymWithZeros) - expectedZeroCount, ...
    "Channel estimator should record how many nonzero references were used.");
assert(~contains(lower(string(msg)), "reference symbols contain zeros") ...
    && ~contains(lower(string(id)), "nrchannelestimate"), ...
    "Mixed zero reference symbols should be handled before nrChannelEstimate emits its warning.");
end

function localTestPUSCHRxNoZeroReferenceWarning()
cfg = localBasicPUSCHCfg();
cfg.run.strictMode = true;
cfg.phy.pusch.transformPrecoding = false;

[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg);
lastwarn("");
[rx, info] = sixgr.phy.ul.PUSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PUSCH", tx.PUSCH, ...
    "PUSCHIndices", tx.PUSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV);
[msg, id] = lastwarn;
assert(rx.Ok, "Real PUSCH DMRS channel estimation should decode successfully.");
assert(strcmp(string(info.ChannelEstimation.EngineUsed), "nrChannelEstimate"), ...
    "PUSCH truth RX should use nrChannelEstimate on the real DMRS evidence path.");
assert(~contains(lower(string(msg)), "zero reference") && ~contains(lower(string(id)), "nrchannelestimate"), ...
    "Real PUSCH RX should not emit the nrChannelEstimate zero-reference warning.");
end

function cfg = localBasicPDSCHCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = 'QPSK';
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.csirs.enable = false;
end

function cfg = localBasicPUSCHCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
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
