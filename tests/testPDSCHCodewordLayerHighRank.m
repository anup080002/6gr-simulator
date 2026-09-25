function ok = testPDSCHCodewordLayerHighRank()
%TESTPDSCHCODEWORDLAYERHIGHRANK Exact PDSCH codeword/layer contracts.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    error("sixgr:test:Required5GToolboxUnavailable", ...
        ["testPDSCHCodewordLayerHighRank requires the 5G Toolbox APIs " ...
        "checked by localHaveRequired5G; unavailable tests cannot pass."]);
end

rng(8308, "twister");
maxLayerInverseErr = 0;
maxBER = 0;
% Include asymmetric codeword modulation: identical QPSK on both codewords
% can hide a one-based/zero-based mismatch in the measurement consumer.
rankCases = [1:8 5 8 5];
for caseIndex = 1:numel(rankCases)
    nLayers = rankCases(caseIndex);
    cfg = localCfg(nLayers);
    if caseIndex == 9 || caseIndex == 10
        cfg.phy.pdsch.modulation = {'QPSK','16QAM'};
    elseif caseIndex == 11
        % One unsegmented and one segmented CW: neither population can
        % inherit the other codeword's CRC applicability or failure count.
        cfg.phy.pdsch.modulation = {'QPSK','64QAM'};
        cfg.phy.pdsch.prbSet = 0:17;
        cfg.phy.pdsch.codeRate = [0.3 0.8];
    end
    W = eye(nLayers);
    [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, "PrecodingMatrix", W);
    expectedCW = 1 + double(nLayers > 4);
    if expectedCW == 1
        expectedCodewordByLayer = zeros(1,nLayers);
    else
        % TS 38.211 Table 7.3.1.3-1: q=0 takes floor(v/2) layers.
        expectedCodewordByLayer = [zeros(1,floor(nLayers/2)), ...
            ones(1,ceil(nLayers/2))];
    end
    assert(isequal(tx.CodewordLayerMapping.CodewordIndexByLayer, expectedCodewordByLayer), ...
        'PDSCH physical codeword IDs must be q=0,1, not MATLAB cell positions.');

    assert(double(tx.NumCodewords) == expectedCW, "Rank-%d PDSCH must materialize %d codeword(s).", nLayers, expectedCW);
    assert(numel(tx.Codewords) == expectedCW && isequal(int8(tx.Codewords{1}(:)), int8(tx.Codeword(:))), ...
        "Rank-%d PDSCH codeword cell must preserve legacy Codeword field as codeword 1.", nLayers);
    assert(sum(double(tx.RateMatchedBitCountPerCodeword)) == double(tx.G), ...
        "Rank-%d PDSCH per-codeword G must sum to total G.", nLayers);
    assert(double(tx.CodewordLayerMapping.NumLayers) == nLayers, ...
        "Rank-%d PDSCH mapping contract reports wrong NumLayers.", nLayers);
    assert(double(tx.CodewordLayerMapping.ActualLayerColumns) == nLayers, ...
        "Rank-%d PDSCH did not emit the requested number of layer columns.", nLayers);
    assert(logical(tx.CodewordLayerMapping.AllLayerStreamsNonzero), ...
        "Rank-%d PDSCH must carry nonzero symbols on every layer.", nLayers);
    assert(size(tx.PDSCHLayerSymbols, 2) == nLayers, ...
        "Rank-%d PDSCH layer-symbol matrix has wrong width.", nLayers);

    demapped = sixgr.phy.mimo.layerDemap(tx.PDSCHLayerSymbols, "ReturnCell", true);
    assert(iscell(demapped) && numel(demapped) == expectedCW, ...
        "Rank-%d PDSCH layer demap must return %d codeword stream(s).", nLayers, expectedCW);
    if expectedCW == 1
        remapped = sixgr.phy.mimo.layerMap(demapped{1}, nLayers);
    else
        remapped = sixgr.phy.mimo.layerMap(demapped, nLayers);
    end
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
        "CodingPlan", tx.CodingPlans, ...
        "CodingLayout", tx.CodingLayouts, ...
        "PrecodingMatrix", W, ...
        "NoiseVar", 1e-12, ...
        "NoiseVarDomain", "grid", ...
        "SkipTimingEstimate", true);
    assert(logical(rx.Ok) && ~logical(rx.CRCError), "Rank-%d no-noise PDSCH must pass CRC.", nLayers);
    localAssertCodeBlockEvidence(tx,rx);
    if caseIndex == 11
        counts=cellfun(@(x)double(x.NumCodeBlocks),tx.CodingLayouts);
        assert(counts(1)==1 && counts(2)>1,'Mixed segmentation fixture is required.');
    end
    if nLayers == 1
        % Deterministic received-noise experiment, not a fabricated CRC flag.
        noisy = tx.Waveform + 20*sqrt(mean(abs(tx.Waveform(:)).^2)/2) ...
            .* (randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
        [failed,~] = sixgr.phy.dl.PDSCH_Rx(noisy,cfg, ...
            "Carrier",tx.Carrier,"PDSCH",tx.PDSCH,"PDSCHIndices",tx.PDSCHIndices, ...
            "TransportBlockSize",tx.TransportBlockSize,"TargetCodeRate",tx.TargetCodeRate, ...
            "RV",tx.RV,"CodingPlan",tx.CodingPlans,"CodingLayout",tx.CodingLayouts, ...
            "PrecodingMatrix",W,"SkipTimingEstimate",true);
        assert(~failed.Ok && failed.CRCError,'Noise experiment must exercise a failed TB.');
        localAssertCodeBlockEvidence(tx,failed);
        assert(failed.MeasuredCodeBlockDecodeErrorCount==1 && ...
            failed.MeasuredCodeBlockDecodeFailureRate==1, ...
            'A failed one-CB TB must not be exported as zero decoded-block errors.');
        coding=sixgr.link.deriveCodingTrialMetrics(tx,txInfo,failed,cfg);
        assert(coding.CodeBlockCount==1 && coding.CodeBlockErrors==1);
    end
    cfg.outputs.constellationCaptureScope = "full_allocation";
    [~, samples] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, "DL");
    assert(height(samples) == numel(tx.PDSCHLayerSymbolsForEvidence) && ...
        all(samples.CaptureScope == "full_allocation_paired_symbols"), ...
        "Rank-%d must export the complete measured allocation.", nLayers);
    expectedIndices = reshape(expectedCodewordByLayer(samples.LayerIndex), [], 1);
    assert(isequal(samples.CodewordIndex, expectedIndices), ...
        "Rank-%d capture must preserve the actual codeword-to-layer mapping.", nLayers);
    expectedModulations = string(cfg.phy.pdsch.modulation);
    expectedSampleModulations = reshape(expectedModulations(expectedIndices+1), [], 1);
    assert(size(samples.Modulation, 2) == 1 && isequal(samples.Modulation, expectedSampleModulations), ...
        "Rank-%d must preserve one modulation label per sample, not a vector-valued CSV cell.", nLayers);
    assert(isequal(rx.CodewordLayerMapping.CodewordIndexByLayer, expectedCodewordByLayer), ...
        'RX must independently retain NR physical codeword IDs.');
    for codewordCell = 1:expectedCW
        assert(isequal(int8(rx.TransportBlocks{codewordCell}(:)), int8(tx.TransportBlocks{codewordCell}(:))), ...
            'Every codeword must recover its actual transport block.');
    end
    ber = sum(int8(rx.TransportBlock(:)) ~= int8(tx.TransportBlock(:))) / numel(tx.TransportBlock);
    maxBER = max(maxBER, ber);
    assert(ber == 0, "Rank-%d no-noise PDSCH must recover the exact TB.", nLayers);
    assert(double(rx.NumCodewords) == expectedCW && double(rx.ActualNumCodewords) == expectedCW, ...
        "Rank-%d PDSCH RX must preserve %d explicit codeword stream(s).", nLayers, expectedCW);
    assert(all(double(rx.CodewordLLRCountPerCodeword) == double(tx.RateMatchedBitCountPerCodeword)), ...
        "Rank-%d PDSCH RX per-codeword LLR count must match G.", nLayers);
    assert(logical(rx.CodewordLayerMapping.ActualLayersEqualGrantLayers), ...
        "Rank-%d PDSCH RX equalized-layer contract must match the grant layers.", nLayers);
    assert(double(rxInfo.CodewordLayerMapping.TotalDemapperLLRCount) == double(tx.G), ...
        "Rank-%d PDSCH RX info must expose the exact demapper LLR count.", nLayers);
    assert(logical(txInfo.CodewordLayerMapping.ActualLayersEqualGrantLayers), ...
        "Rank-%d PDSCH TX info must expose the actual layer count.", nLayers);
    if expectedCW == 2
        harqDiag = sixgr.link.evaluateHARQDecode(tx, rx, cfg, ...
            struct("LLRCell", {rx.RecLLRCell}, "CodingLayouts", {rx.CodingLayouts}));
        assert(iscell(harqDiag.CombinedLLR) && numel(harqDiag.CombinedLLR) == 2, ...
            "Rank-%d HARQ diagnostic must preserve per-codeword soft buffers.", nLayers);
        assert(logical(harqDiag.CombinedDecodeOK), ...
            "Rank-%d HARQ combined per-codeword decode must pass in no-noise loopback.", nLayers);
    end
end

localAssertInvalidScopesFail();
localAssertDelayedSharedCFO();
fprintf("PDSCH codeword/layer cases=%d ranks=1:8 mixed_modulation_and_segmentation=PASS failed_single_CB=PASS maxLayerInverseErr=%.3g maxBER=%.3g\n", ...
    numel(rankCases), maxLayerInverseErr, maxBER);
ok = true;
end

function localAssertCodeBlockEvidence(tx,rx)
counts=cellfun(@(x)double(x.NumCodeBlocks),tx.CodingLayouts);
checks=sum(counts(counts>1));
assert(rx.MeasuredCodeBlockDecodeCount==sum(counts));
assert(rx.MeasuredCodeBlockCRCCount==checks, ...
    'Count actual per-CB CRC checks, not codewords or absent one-CB CRCs.');
assert(numel(rx.CodeBlockCRCError)==checks);
assert(rx.MeasuredCodeBlockCRCErrorCount==sum(double(rx.CodeBlockCRCError)));
if checks==0, assert(isnan(rx.MeasuredCodeBlockCRCFailureRate)); end
end

function localAssertDelayedSharedCFO()
% Received-waveform timing/frequency test, not a channel-delay oracle.
cfg=localCfg(1);
cfg.phy.rx.cfoCorrectionEnabled=true;
cfg.phy.impairments.cfoEstimationMethod='cyclic_prefix';
[tx,~]=sixgr.phy.dl.PDSCH_Tx(cfg,'PrecodingMatrix',1);
ofdm=nrOFDMInfo(tx.Carrier);
delay=7;
for injectedCFO=[-220 0 220]
    % Explicit test channel: integer delay and frequency rotation, with
    % actual idle samples after transmission. Nothing is supplied to RX
    % about the injected delay or frequency; only its bounded search window.
    observed=[complex(zeros(delay,1));tx.Waveform;complex(zeros(32,1))];
    observed=observed.*exp(1j*2*pi*injectedCFO/ofdm.SampleRate*(0:size(observed,1)-1).');
    [rx,~]=sixgr.phy.dl.PDSCH_Rx(observed,cfg, ...
        'Carrier',tx.Carrier,'PDSCH',tx.PDSCH,'PDSCHIndices',tx.PDSCHIndices, ...
        'TransportBlockSize',tx.TransportBlockSize,'TargetCodeRate',tx.TargetCodeRate, ...
        'RV',tx.RV,'CodingPlan',tx.CodingPlans,'CodingLayout',tx.CodingLayouts, ...
        'PrecodingMatrix',1,'NoiseVar',1e-12,'NoiseVarDomain','grid', ...
        'SkipTimingEstimate',false,'TimingSearchWindowSamples',[0 20]);
    assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,tx.TransportBlock));
    assert(rx.ReceiveTiming.TimingOffsetSamples==delay && ...
        ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
    assert(abs(rx.EstimatedCFO_Hz-injectedCFO)<5, ...
        'Shared PDSCH frequency estimation must use aligned received symbols.');
    assert(abs(rx.ResidualCFO_EstimatedPostCorrection_Hz)<5, ...
        'Residual CFO must be measured on the actual aligned/corrected FFT interval.');
    fprintf('SHARED_PDSCH_CFO_PASS injected=%g measured=%.12g residual=%.12g timing=%g\n', ...
        injectedCFO,rx.EstimatedCFO_Hz,rx.ResidualCFO_EstimatedPostCorrection_Hz, ...
        rx.ReceiveTiming.TimingOffsetSamples);
end
end

function cfg = localCfg(nLayers)
cfg = sixgr.config.defaultConfig();
% Isolated narrow-carrier PDSCH calibration; no SS/PBCH is transmitted here.
% SSB reservation/collision coverage remains in testSSBPRBSymbolReservation.
cfg.phy.ssb.enable = false;
cfg.run.shortRun = true;
cfg.run.pdschExecutionProfile = "phy_calibration";
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
if nLayers > 4
    cfg.phy.pdsch.modulation = {'QPSK','QPSK'};
    cfg.phy.pdsch.mcsTable = ...
        ["calibration_explicit","calibration_explicit"];
    cfg.phy.pdsch.mcsIndex = [0 1];
else
    cfg.phy.pdsch.modulation = 'QPSK';
    cfg.phy.pdsch.mcsTable = "calibration_explicit";
    cfg.phy.pdsch.mcsIndex = 0;
end
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.mcsContext = localCalibrationMCSContext();
cfg.phy.pdsch.numLayers = nLayers;
cfg.phy.pdsch.nLayers = nLayers;
cfg.phy.pdsch.numPorts = nLayers;
cfg.phy.pdsch.nPorts = nLayers;
cfg.phy.pdsch.dmrs.availablePortSet = 0:(nLayers - 1);
cfg.phy.pdsch.RNTI = 1000 + nLayers;
cfg.phy.pdsch.NID = 42 + nLayers;
if nLayers > 4
    cfg.phy.pdsch.codeRate = [0.30 0.30];
else
    cfg.phy.pdsch.codeRate = 0.30;
end
cfg.phy.pdsch.xOverhead = 0;
if nLayers > 4
    cfg.phy.pdsch.rv = [0 0];
else
    cfg.phy.pdsch.rv = 0;
end
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pdsch.precoding.matrix = eye(nLayers);
cfg.phy.pdsch.precodingMatrix = eye(nLayers);
cfg.phy.pdsch.W = eye(nLayers);
if nLayers > 4
    cfg.phy.pdsch.dmrs.configurationType = 2;
    cfg.phy.pdsch.dmrs.length = 2;
    cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = 3;
end
cfg.phy.csirs.enable = false;
end

function context = localCalibrationMCSContext()
context = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", ...
    "OperatingBand", "n78", ...
    "DeploymentClass", "controlled_test");
end

function localAssertInvalidScopesFail()
cfgScalarRate = localCfg(5);
cfgScalarRate.phy.pdsch.codeRate = 0.30;
localAssertThrows(@() sixgr.phy.dl.PDSCH_Tx( ...
    cfgScalarRate, "PrecodingMatrix", eye(5)), ...
    "sixgr:pdsch:CalibrationCodeRateCountMismatch");

cfgTwoCW = localCfg(2);
cfgTwoCW.phy.pdsch.numCodewords = 2;
localAssertThrows(@() sixgr.phy.dl.PDSCH_Tx(cfgTwoCW, "PrecodingMatrix", eye(2)), ...
    "sixgr:phy:dl:PDSCHCodewordLayerScope");

cfgRank9 = localCfg(8);
cfgRank9.phy.pdsch.numLayers = 9;
cfgRank9.phy.pdsch.nLayers = 9;
cfgRank9.phy.pdsch.numPorts = 9;
cfgRank9.phy.pdsch.nPorts = 9;
cfgRank9.phy.nTxAnt = 9;
localAssertThrows(@() sixgr.phy.dl.PDSCH_Tx(cfgRank9, "PrecodingMatrix", eye(9)), ...
    "sixgr:phy:dl:PDSCHCodewordLayerScope");
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
