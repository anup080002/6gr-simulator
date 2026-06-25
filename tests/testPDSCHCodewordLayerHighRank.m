function ok = testPDSCHCodewordLayerHighRank()
%TESTPDSCHCODEWORDLAYERHIGHRANK Exact PDSCH codeword/layer contracts.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

rng(8308, "twister");
maxLayerInverseErr = 0;
maxBER = 0;
for nLayers = 1:4
    cfg = localCfg(nLayers);
    W = eye(nLayers);
    [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, "PrecodingMatrix", W);

    assert(double(tx.NumCodewords) == 1, "Rank-%d PDSCH must materialize one codeword.", nLayers);
    assert(numel(tx.Codewords) == 1 && isequal(int8(tx.Codewords{1}(:)), int8(tx.Codeword(:))), ...
        "Rank-%d PDSCH codeword cell must match legacy Codeword field.", nLayers);
    assert(double(tx.RateMatchedBitCountPerCodeword(1)) == double(tx.G), ...
        "Rank-%d PDSCH per-codeword G must match total G for single-CW ranks.", nLayers);
    assert(double(tx.CodewordLayerMapping.NumLayers) == nLayers, ...
        "Rank-%d PDSCH mapping contract reports wrong NumLayers.", nLayers);
    assert(double(tx.CodewordLayerMapping.ActualLayerColumns) == nLayers, ...
        "Rank-%d PDSCH did not emit the requested number of layer columns.", nLayers);
    assert(logical(tx.CodewordLayerMapping.AllLayerStreamsNonzero), ...
        "Rank-%d PDSCH must carry nonzero symbols on every layer.", nLayers);
    assert(size(tx.PDSCHLayerSymbols, 2) == nLayers, ...
        "Rank-%d PDSCH layer-symbol matrix has wrong width.", nLayers);

    demapped = sixgr.phy.mimo.layerDemap(tx.PDSCHLayerSymbols, "ReturnCell", true);
    assert(iscell(demapped) && numel(demapped) == 1, ...
        "Rank-%d PDSCH layer demap must return one codeword stream.", nLayers);
    remapped = sixgr.phy.mimo.layerMap(demapped{1}, nLayers);
    layerInverseErr = localMaxAbs(remapped(:) - tx.PDSCHLayerSymbols(:));
    maxLayerInverseErr = max(maxLayerInverseErr, layerInverseErr);
    assert(layerInverseErr < 1e-12, "Rank-%d PDSCH layer map/demap inverse failed.", nLayers);

    if nLayers == 2
        e = sum(abs(tx.PDSCHLayerSymbols).^2, 1);
        assert(all(e > 0), "Rank-2 PDSCH must energize both layers.");
        assert(localMaxAbs(tx.PDSCHLayerSymbols(:,1) - tx.PDSCHLayerSymbols(:,2)) > 0, ...
            "Rank-2 PDSCH layers must carry independent symbol streams, not a collapsed duplicate.");
    end

    [rx, rxInfo] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
        "Carrier", tx.Carrier, ...
        "PDSCH", tx.PDSCH, ...
        "PDSCHIndices", tx.PDSCHIndices, ...
        "TransportBlockSize", tx.TransportBlockSize, ...
        "TargetCodeRate", tx.TargetCodeRate, ...
        "RV", tx.RV, ...
        "CodingLayout", tx.CodingLayout, ...
        "PrecodingMatrix", W, ...
        "NoiseVar", 1e-12, ...
        "NoiseVarDomain", "grid", ...
        "SkipTimingEstimate", true);
    assert(logical(rx.Ok) && ~logical(rx.CRCError), "Rank-%d no-noise PDSCH must pass CRC.", nLayers);
    ber = sum(int8(rx.TransportBlock(:)) ~= int8(tx.TransportBlock(:))) / numel(tx.TransportBlock);
    maxBER = max(maxBER, ber);
    assert(ber == 0, "Rank-%d no-noise PDSCH must recover the exact TB.", nLayers);
    assert(double(rx.NumCodewords) == 1 && double(rx.ActualNumCodewords) == 1, ...
        "Rank-%d PDSCH RX must preserve a single explicit codeword stream.", nLayers);
    assert(double(rx.CodewordLLRCountPerCodeword(1)) == double(tx.G), ...
        "Rank-%d PDSCH RX per-codeword LLR count must match G.", nLayers);
    assert(logical(rx.CodewordLayerMapping.ActualLayersEqualGrantLayers), ...
        "Rank-%d PDSCH RX equalized-layer contract must match the grant layers.", nLayers);
    assert(double(rxInfo.CodewordLayerMapping.TotalDemapperLLRCount) == double(tx.G), ...
        "Rank-%d PDSCH RX info must expose the exact demapper LLR count.", nLayers);
    assert(logical(txInfo.CodewordLayerMapping.ActualLayersEqualGrantLayers), ...
        "Rank-%d PDSCH TX info must expose the actual layer count.", nLayers);
end

localAssertUnsupportedScopesFail();
fprintf("PDSCH codeword/layer ranks=1:4 maxLayerInverseErr=%.3g maxBER=%.3g\n", ...
    maxLayerInverseErr, maxBER);
ok = true;
end

function cfg = localCfg(nLayers)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 80;
cfg.phy.carrier.NSizeGrid = 18;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.NCellID = 42 + nLayers;
cfg.phy.nTxAnt = nLayers;
cfg.channel.nTxAnt = nLayers;
cfg.channel.nRxAnt = nLayers;
cfg.scenario.bs.nTxAnt = nLayers;
cfg.antenna.bs.numElements = nLayers;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.mappingType = 'A';
cfg.phy.pdsch.modulation = 'QPSK';
cfg.phy.pdsch.numLayers = nLayers;
cfg.phy.pdsch.nLayers = nLayers;
cfg.phy.pdsch.numPorts = nLayers;
cfg.phy.pdsch.nPorts = nLayers;
cfg.phy.pdsch.RNTI = 1000 + nLayers;
cfg.phy.pdsch.NID = 42 + nLayers;
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.xOverhead = 0;
cfg.phy.pdsch.rv = 0;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pdsch.precoding.matrix = eye(nLayers);
cfg.phy.pdsch.precodingMatrix = eye(nLayers);
cfg.phy.pdsch.W = eye(nLayers);
cfg.phy.csirs.enable = false;
end

function localAssertUnsupportedScopesFail()
cfgRank5 = localCfg(4);
cfgRank5.phy.pdsch.numLayers = 5;
cfgRank5.phy.pdsch.nLayers = 5;
cfgRank5.phy.nTxAnt = 5;
localAssertThrows(@() sixgr.phy.dl.PDSCH_Tx(cfgRank5, "PrecodingMatrix", eye(5)), ...
    "sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported");

cfgTwoCW = localCfg(2);
cfgTwoCW.phy.pdsch.numCodewords = 2;
localAssertThrows(@() sixgr.phy.dl.PDSCH_Tx(cfgTwoCW, "PrecodingMatrix", eye(2)), ...
    "sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported");
end

function localAssertThrows(fn, id)
thrown = false;
try
    fn();
catch ME
    thrown = strcmp(ME.identifier, id);
    if ~thrown
        rethrow(ME);
    end
end
assert(thrown, "Expected error %s was not thrown.", id);
end

function value = localMaxAbs(x)
if isempty(x)
    value = 0;
else
    value = max(abs(x(:)));
end
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPDSCHPrecode", "file") == 2 ...
    && exist("nrLayerMap", "file") == 2 ...
    && exist("nrLayerDemap", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2;
end