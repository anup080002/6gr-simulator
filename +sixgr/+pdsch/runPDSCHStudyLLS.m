function study = runPDSCHStudyLLS(inputCfg, varargin)
%runPDSCHStudyLLS Run the truthful 6GR PDSCH waveform/resource-grid study.

opts = struct("ScenarioMatrix", [], "WriteOutputs", true, "Verbose", false, ...
    "OutputDir", "", "ScenarioID", "pdsch6gr_truth_study");
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end
if strlength(string(opts.OutputDir)) == 0
    timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    opts.OutputDir = fullfile("results", "pdsch6gr_truth_" + timestamp);
end
sixgr.util.ensureFolder(opts.OutputDir);

baseCfg = sixgr.pdsch.PDSCHStudyConfig(inputCfg, "RunFolder", opts.OutputDir, "ScenarioID", opts.ScenarioID);
points = localBuildScenarioPoints(baseCfg, opts.ScenarioMatrix);

trialRows = repmat(localEmptyTrialRow(), 0, 1);
tbRows = repmat(localEmptyTBRow(), 0, 1);
cwRows = repmat(localEmptyCWRow(), 0, 1);
fdraRows = repmat(localEmptyFDRARow(), 0, 1);
tdraRows = repmat(localEmptyTDRARow(), 0, 1);
harqRows = repmat(localEmptyHARQRow(), 0, 1);
chEstRows = repmat(localEmptyChEstRow(), 0, 1);
paramRows = repmat(localEmptyParamRow(), 0, 1);
grantRows = repmat(localEmptyGrantRow(), 0, 1);
dlTrialRows = repmat(localEmptyDLTrialRow(), 0, 1);
complexityRows = repmat(localEmptyComplexityRow(), 0, 1);
mrssRows = repmat(localEmptyMRSSRow(), 0, 1);
layerTraceT = table();
dmrsMapT = table();
ptrsMapT = table();

trialIndex = 0;
for p = 1:numel(points)
    point = points(p);
    if opts.Verbose
        fprintf("[PDSCH6GR] %d/%d SNR=%.2f fdra=%s rank=%d rep=%s\n", ...
            p, numel(points), point.SNRdB, point.FDRAType, point.Rank, point.RepetitionMode);
    end
    for rep = 1:point.NumTrials
        trialIndex = trialIndex + 1;
        trialSeed = double(baseCfg.Seed + 1000 * p + rep);
        [trialRow, tbT, cwT, fdraT, tdraT, dmrsT, ptrsT, chT, paramT, harqT, grantT, dlTrialT, compT, mrssT, layerT] = ...
            localRunOneTrial(baseCfg, point, trialIndex, trialSeed);
        trialRows(end+1,1) = trialRow; %#ok<AGROW>
        tbRows = [tbRows; tbT]; %#ok<AGROW>
        cwRows = [cwRows; cwT]; %#ok<AGROW>
        fdraRows = [fdraRows; fdraT]; %#ok<AGROW>
        tdraRows = [tdraRows; tdraT]; %#ok<AGROW>
        dmrsMapT = localVertcat(dmrsMapT, dmrsT);
        ptrsMapT = localVertcat(ptrsMapT, ptrsT);
        chEstRows = [chEstRows; chT]; %#ok<AGROW>
        paramRows = [paramRows; paramT]; %#ok<AGROW>
        harqRows = [harqRows; harqT]; %#ok<AGROW>
        grantRows = [grantRows; grantT]; %#ok<AGROW>
        dlTrialRows = [dlTrialRows; dlTrialT]; %#ok<AGROW>
        complexityRows = [complexityRows; compT]; %#ok<AGROW>
        mrssRows = [mrssRows; mrssT]; %#ok<AGROW>
        layerTraceT = localVertcat(layerTraceT, layerT);
    end
end

trialT = struct2table(trialRows);
tbLevelT = struct2table(tbRows);
cwLevelT = struct2table(cwRows);
fdraAllocT = struct2table(fdraRows);
tdraAllocT = struct2table(tdraRows);
harqTraceT = struct2table(harqRows);
chEstT = struct2table(chEstRows);
paramEstT = struct2table(paramRows);
grantTraceT = struct2table(grantRows);
dlTrialT = struct2table(dlTrialRows);
complexityT = struct2table(complexityRows);
mrssT = struct2table(mrssRows);

metrics = sixgr.pdsch.PDSCHMetrics(trialT);

study = struct();
study.Config = baseCfg;
study.OutputDir = string(opts.OutputDir);
study.TrialLevelResults = trialT;
study.TBLevelResults = tbLevelT;
study.CodewordLevelResults = cwLevelT;
study.LayerMappingTrace = layerTraceT;
study.FDRAAllocations = fdraAllocT;
study.TDRAAllocations = tdraAllocT;
study.DMRSMapping = dmrsMapT;
study.PTRSMapping = ptrsMapT;
study.ChannelEstimationMetrics = chEstT;
study.ParameterEstimationMetrics = paramEstT;
study.HARQTrace = harqTraceT;
study.SummaryBySNR = metrics.SummaryBySNR;
study.SummaryByBand = metrics.SummaryByBand;
study.SummaryByFDRAType = metrics.SummaryByFDRAType;
study.SummaryByTDRAMode = metrics.SummaryByTDRAMode;
study.SummaryByDMRSSetting = metrics.SummaryByDMRSSetting;
study.SummaryByPTRSSetting = metrics.SummaryByPTRSSetting;
study.SummaryByRank = metrics.SummaryByRank;
study.SummaryByRepetition = metrics.SummaryByRepetition;
study.ComplexitySummary = metrics.ComplexitySummary;
study.DLTrialTable = dlTrialT;
study.DLGrantTrace = grantTraceT;
study.MRSSOverlapEvents = mrssT;

if logical(opts.WriteOutputs)
    localWriteOutputs(study);
    localWritePlots(study);
end
end

function points = localBuildScenarioPoints(cfg, scenarioMatrix)
if ~isempty(scenarioMatrix)
    points = scenarioMatrix;
    return;
end
s = cfg.StudySweep;
[A,B,C,D,E,F,G,H,I,J,K] = ndgrid(1:numel(s.SNRdB), 1:numel(s.FDRATypes), 1:numel(s.MappingStarts), ...
    1:numel(s.NumSymbols), 1:numel(s.ChannelModels), 1:numel(s.DelaySpread_ns), ...
    1:numel(s.Ranks), 1:numel(s.RepetitionModes), 1:numel(s.SpeedKmh), ...
    1:numel(s.PTRSModes), 1:numel(s.DMRSAdditionalPositions));
numPoints = numel(A);
points = repmat(struct("ScenarioID","", "SNRdB", NaN, "FDRAType","", "StartSymbol", NaN, ...
    "NumSymbols", NaN, "ChannelModel","", "DelaySpread_ns", NaN, "Rank", NaN, ...
    "RepetitionMode","", "PTRSMode","", "SpeedKmh", NaN, ...
    "CarrierFrequencyHz", NaN, "Numerology", NaN, "DuplexMode","", ...
    "ChannelBandwidthMHz", NaN, "NSizeGrid", NaN, ...
    "DMRSAdditionalPosition", NaN, "NumTrials", 1), numPoints, 1);
for i = 1:numPoints
    points(i).ScenarioID = sprintf("pdsch6gr_%03d", i);
    points(i).SNRdB = s.SNRdB(A(i));
    points(i).FDRAType = char(s.FDRATypes{B(i)});
    points(i).StartSymbol = s.MappingStarts(C(i));
    points(i).NumSymbols = s.NumSymbols(D(i));
    points(i).ChannelModel = char(s.ChannelModels{E(i)});
    points(i).DelaySpread_ns = s.DelaySpread_ns(F(i));
    points(i).Rank = s.Ranks(G(i));
    points(i).RepetitionMode = char(s.RepetitionModes{H(i)});
    points(i).SpeedKmh = s.SpeedKmh(I(i));
    points(i).PTRSMode = char(s.PTRSModes{J(i)});
    points(i).CarrierFrequencyHz = cfg.CarrierFrequencyHz;
    points(i).Numerology = cfg.Numerology;
    points(i).DuplexMode = cfg.DuplexMode;
    points(i).ChannelBandwidthMHz = cfg.ChannelBandwidthMHz;
    points(i).NSizeGrid = cfg.NSizeGrid;
    points(i).DMRSAdditionalPosition = s.DMRSAdditionalPositions(K(i));
    points(i).NumTrials = s.NumTrials;
end
end

function [trialRow, tbT, cwT, fdraT, tdraT, dmrsT, ptrsT, chT, paramT, harqT, grantT, dlTrialT, compT, mrssT, layerT] = ...
        localRunOneTrial(baseCfg, point, trialIndex, seed)
cfg = baseCfg;
cfg.SNRdB = double(point.SNRdB);
cfg.ChannelModel = char(string(point.ChannelModel));
cfg.DelaySpread_s = double(point.DelaySpread_ns) * 1e-9;
cfg.CarrierFrequencyHz = double(sixgr.util.structGet(point, "CarrierFrequencyHz", cfg.CarrierFrequencyHz));
cfg.Numerology = double(sixgr.util.structGet(point, "Numerology", cfg.Numerology));
cfg.DuplexMode = char(string(sixgr.util.structGet(point, "DuplexMode", cfg.DuplexMode)));
cfg.ChannelBandwidthMHz = double(sixgr.util.structGet(point, "ChannelBandwidthMHz", cfg.ChannelBandwidthMHz));
cfg.NSizeGrid = double(sixgr.util.structGet(point, "NSizeGrid", cfg.NSizeGrid));
cfg.CodewordLayer.Rank = double(point.Rank);
cfg.NumLayers = double(point.Rank);
cfg.RepetitionMode = char(string(point.RepetitionMode));
cfg.EnablePDSCHRepetition = ~strcmpi(cfg.RepetitionMode, "none");
cfg.RepetitionCount = localRepetitionCount(cfg);
cfg.EnablePTRS = strcmpi(point.PTRSMode, "enabled");
cfg.PTRS.PTRSEnabled = cfg.EnablePTRS;
cfg.TDRA.StartSymbol = double(point.StartSymbol);
cfg.TDRA.NumSymbols = double(point.NumSymbols);
cfg.DMRS.AdditionalPosition = double(point.DMRSAdditionalPosition);
cfg.TDRA.MappingType = "single_mapping_type_baseline";
cfg.TDRA.EnableCrossSlot = false;
cfg.FDRA.FDRAType = char(string(point.FDRAType));
cfg.SpeedKmh = max(0, double(sixgr.util.structGet(point, "SpeedKmh", cfg.SpeedKmh)));
cfg.DopplerHz = localSpeedToDoppler(cfg.SpeedKmh, cfg.CarrierFrequencyHz);
cfg.SlotNumber = mod(trialIndex - 1, 10 * 2^cfg.Numerology);
cfg.Seed = double(seed);

fdraAlloc = sixgr.pdsch.FDRAAllocator(localResolveFDRAForPoint(cfg), cfg.NSizeGrid, "TransmissionIndex", trialIndex);
[fdraAlloc, mrssOverlap] = sixgr.pdsch.MRSSCoordinator(cfg, fdraAlloc);
tdraAlloc = sixgr.pdsch.TDRAAllocator(cfg.TDRA, "RepetitionMode", cfg.RepetitionMode, "RepetitionCount", cfg.RepetitionCount);
amc = sixgr.pdsch.AMCSelector(cfg, "EstimatedSNR_dB", cfg.SNRdB);
rvSeq = [0 2 3 1];

tbRows = repmat(localEmptyTBRow(), 0, 1);
cwRows = repmat(localEmptyCWRow(), 0, 1);
fdraRows = repmat(localEmptyFDRARow(), 0, 1);
tdraRows = repmat(localEmptyTDRARow(), 0, 1);
chRows = repmat(localEmptyChEstRow(), 0, 1);
paramRows = repmat(localEmptyParamRow(), 0, 1);
harqRows = repmat(localEmptyHARQRow(), 0, 1);
grantRows = repmat(localEmptyGrantRow(), 0, 1);
dlTrialRows = repmat(localEmptyDLTrialRow(), 0, 1);
compRows = repmat(localEmptyComplexityRow(), 0, 1);
mrssRows = repmat(localEmptyMRSSRow(), 0, 1);
dmrsT = table();
ptrsT = table();
layerT = table();

finalPass = false;
finalThroughputBits = 0;
finalTBSizeBits = NaN;
finalComplexity = NaN;
finalCodedBits = NaN;
finalEstimatedDelaySpread = NaN;
finalEstimatedDoppler = NaN;
finalEstimatedDelay = NaN;
finalEstimatedSNR = NaN;
finalRxMetricSummary = "";
attempts = localHARQAttempts(cfg);
for h = 1:attempts
    rv = rvSeq(min(h, numel(rvSeq)));
    txBundle = sixgr.pdsch.PDSCHWaveformBuilder(cfg, fdraAlloc, tdraAlloc, amc, ...
        "QueueBits", cfg.QueueBits, "RV", rv, "TransmissionIndex", trialIndex * 10 + h);
    layerT = localVertcat(layerT, localAnnotateLayerTrace(txBundle.LayerMappingTrace, point, trialIndex, h));

    copyLLRs = cell(numel(txBundle.Copies), 1);
    postEqEVM = NaN(numel(txBundle.Copies), 1);
    sinrEst = NaN(numel(txBundle.Copies), 1);
    for c = 1:numel(txBundle.Copies)
        copy = txBundle.Copies{c};
        [rxWave, noiseVar] = localApplyChannelAndNoise(copy.Tx.Waveform, cfg, copy.TxInfo, seed + 100 * h + c);
        rxOut = sixgr.pdsch.PDSCHReceiver(rxWave, cfg, copy, ...
            "NoiseVar", noiseVar, "NoiseVarDomain", "time");
        copyLLRs{c} = double(rxOut.Rx.CodewordLLR(:));
        postEqEVM(c) = double(rxOut.PostEqEVM);
        sinrEst(c) = localBestStudySINR(rxOut.Rx);
        dmrsT = localVertcat(dmrsT, localAnnotateMap(copy.DMRSTable, point, trialIndex, h, c, "DMRS"));
        ptrsT = localVertcat(ptrsT, localAnnotateMap(copy.PTRSTable, point, trialIndex, h, c, "PTRS"));
        chRows(end+1,1) = localBuildChEstRow(point, trialIndex, h, c, rxOut); %#ok<AGROW>
        paramRows(end+1,1) = localBuildParamRow(point, trialIndex, h, c, rxOut); %#ok<AGROW>
        tdraRows(end+1,1) = localBuildTDRARow(point, trialIndex, h, c, copy); %#ok<AGROW>
    end

    combined = localCombineLLR(copyLLRs);
    if ~isempty(combined)
        decode = sixgr.pdsch.DLSCHDecoder(combined, ...
            "TransportBlockSize", txBundle.TransportBlockSize, ...
            "TargetCodeRate", txBundle.ActiveAMC.TargetCodeRate, ...
            "RV", rv, ...
            "Modulation", txBundle.ActiveAMC.Modulation, ...
            "NumLayers", cfg.NumLayers);
        crcPass = logical(decode.CRCPass);
    else
        decode = struct("CRCPass", false, "CRCError", true, "DecoderIterations", NaN);
        crcPass = false;
    end

    throughputBits = double(crcPass) * double(txBundle.PayloadBitsBeforePadding);
    finalPass = crcPass;
    finalThroughputBits = throughputBits;
    finalTBSizeBits = double(txBundle.TransportBlockSize);
    finalComplexity = localComplexityProxy(txBundle, decode);
    finalCodedBits = double(sixgr.util.structGet(txBundle.Copies{1}.Tx, "G", NaN));
    finalEstimatedDelaySpread = localTailStructMean(paramRows, numel(txBundle.Copies), "estimated_delay_spread");
    finalEstimatedDoppler = localTailStructMean(paramRows, numel(txBundle.Copies), "estimated_doppler");
    finalEstimatedDelay = localTailStructMean(paramRows, numel(txBundle.Copies), "estimated_delay");
    finalEstimatedSNR = localTailStructMean(paramRows, numel(txBundle.Copies), "estimated_snr");
    finalRxMetricSummary = string("avg_evm=" + num2str(mean(postEqEVM, "omitnan"), "%.4g") + ...
        ",avg_sinr=" + num2str(mean(sinrEst, "omitnan"), "%.4g"));

    tbRows(end+1,1) = localBuildTBRow(cfg, point, trialIndex, h, txBundle, decode, throughputBits, postEqEVM, sinrEst); %#ok<AGROW>
    cwRows(end+1,1) = localBuildCWRow(cfg, point, trialIndex, h, txBundle, decode, throughputBits, postEqEVM, sinrEst); %#ok<AGROW>
    fdraRows(end+1,1) = localBuildFDRARow(point, trialIndex, h, fdraAlloc); %#ok<AGROW>
    harqRows(end+1,1) = localBuildHARQRow(point, trialIndex, h, rv, crcPass, txBundle); %#ok<AGROW>
    grantRows(end+1,1) = localBuildGrantRow(cfg, point, trialIndex, h, txBundle, crcPass, sinrEst); %#ok<AGROW>
    dlTrialRows(end+1,1) = localBuildDLTrialRow(cfg, point, trialIndex, h, txBundle, crcPass, throughputBits, sinrEst, postEqEVM); %#ok<AGROW>
    compRows(end+1,1) = localBuildComplexityRow(point, trialIndex, h, txBundle, finalComplexity); %#ok<AGROW>
    if ~isempty(mrssOverlap)
        mrssRows = [mrssRows; localBuildMRSSRows(mrssOverlap, point, trialIndex, h)]; %#ok<AGROW>
    end
    if crcPass || ~cfg.HARQEnabled
        break;
    end
end

trialRow = localBuildTrialRow(cfg, point, trialIndex, finalPass, finalThroughputBits, finalTBSizeBits, ...
    finalCodedBits, finalComplexity, finalEstimatedDelaySpread, finalEstimatedDoppler, finalEstimatedDelay, ...
    finalEstimatedSNR, finalRxMetricSummary, fdraAlloc);
tbT = tbRows;
cwT = cwRows;
fdraT = fdraRows;
tdraT = tdraRows;
chT = chRows;
paramT = paramRows;
harqT = harqRows;
grantT = grantRows;
dlTrialT = dlTrialRows;
compT = compRows;
mrssT = mrssRows;
end

function [y, noiseVar] = localApplyChannelAndNoise(x, cfg, txInfo, seed)
fs = localResolveSampleRate(txInfo);
cfgCh = struct();
cfgCh.phy.fc_Hz = cfg.CarrierFrequencyHz;
profile = upper(strtrim(char(string(cfg.ChannelModel))));
tdlProfile = "";
cdlProfile = "";
if startsWith(profile, "TDL")
    tdlProfile = profile;
elseif startsWith(profile, "CDL")
    cdlProfile = profile;
end
cfgCh.channel = struct( ...
    "model", char(cfg.ChannelModel), ...
    "tdlProfile", char(tdlProfile), ...
    "cdlProfile", char(cdlProfile), ...
    "fading", struct("delaySpread_s", double(cfg.DelaySpread_s)), ...
    "doppler_Hz", double(cfg.DopplerHz), ...
    "nTxAnt", size(x, 2), ...
    "nRxAnt", cfg.NRx);
ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", size(x, 2), ...
    "NumRxAnt", cfg.NRx, ...
    "Seed", seed);
if logical(sixgr.util.structGet(ch, "IsFading", false)) && ~isempty(ch.Object)
    try
        reset(ch.Object);
    catch
    end
    xIn = x;
    delay = round(double(sixgr.util.structGet(ch.Object, "ChannelFilterDelay", 0)));
    if delay > 0
        xIn = [x; zeros(delay, size(x, 2), "like", x)];
    end
    try
        yRaw = ch.Object(xIn);
    catch
        [yRaw, ~] = ch.Object(xIn);
    end
    if delay > 0 && size(yRaw, 1) >= delay + size(x, 1)
        y = yRaw(delay + (1:size(x, 1)), :);
    else
        y = yRaw(1:min(size(yRaw, 1), size(x, 1)), :);
        if size(y, 1) < size(x, 1)
            y(end+1:size(x, 1), :) = 0; %#ok<AGROW>
        end
    end
else
    y = x;
end
y = localApplyPhaseNoise(y, cfg, seed);
[y, noiseVar] = sixgr.util.addAwgnComplex(y, cfg.SNRdB);
end

function y = localApplyPhaseNoise(y, cfg, seed)
if ~logical(cfg.EnablePhaseNoise)
    return;
end
rng(double(seed), "twister");
sigma = sqrt(1e-4);
phi = cumsum(sigma * randn(size(y, 1), 1));
y = y .* exp(1j * phi);
end

function fs = localResolveSampleRate(txInfo)
fs = double(sixgr.util.structGet(txInfo, "OFDM.SampleRate", NaN));
if ~(isfinite(fs) && fs > 0)
    fs = 30.72e6;
end
end

function value = localSpeedToDoppler(speedKmh, fcHz)
value = double(speedKmh) / 3.6 * double(fcHz) / physconst("lightspeed");
end

function count = localHARQAttempts(cfg)
if logical(cfg.HARQEnabled)
    count = max(1, round(double(cfg.MaxHARQTx)));
else
    count = 1;
end
end

function value = localRepetitionCount(cfg)
if logical(cfg.EnablePDSCHRepetition)
    value = max(2, round(double(cfg.RepetitionCount)));
else
    value = 1;
end
end

function cfgFdra = localResolveFDRAForPoint(cfg)
cfgFdra = cfg.FDRA;
if strcmpi(cfgFdra.FDRAType, "type0_bitmap") && isempty(cfgFdra.RBBitmap)
    nChunks = max(1, ceil(double(cfgFdra.NumRB) / max(1, double(cfgFdra.GranularityRB))));
    cfgFdra.RBBitmap = ones(1, nChunks);
end
if strcmpi(cfgFdra.FDRAType, "type1_riv")
    cfgFdra.RIV = localEncodeRIV(cfgFdra.RBStart, cfgFdra.NumRB, cfg.NSizeGrid);
end
end

function riv = localEncodeRIV(rbStart, numRB, nSizeGrid)
L = round(double(numRB));
S = round(double(rbStart));
N = round(double(nSizeGrid));
if L - 1 <= floor(N / 2)
    riv = N * (L - 1) + S;
else
    riv = N * (N - L + 1) + (N - 1 - S);
end
end

function combined = localCombineLLR(copyLLRs)
if isempty(copyLLRs)
    combined = [];
    return;
end
lengths = cellfun(@numel, copyLLRs);
if isempty(lengths) || any(lengths ~= lengths(1))
    combined = double(copyLLRs{1}(:));
    return;
end
combined = zeros(lengths(1), 1);
for i = 1:numel(copyLLRs)
    combined = combined + double(copyLLRs{i}(:));
end
end

function value = localTailStructMean(rows, count, fieldName)
if isempty(rows)
    value = NaN;
    return;
end
startIdx = max(1, numel(rows) - max(1, round(double(count))) + 1);
slice = rows(startIdx:end);
vals = NaN(numel(slice), 1);
for i = 1:numel(slice)
    vals(i) = double(sixgr.util.structGet(slice(i), fieldName, NaN));
end
value = mean(vals, "omitnan");
end

function ops = localComplexityProxy(txBundle, decode)
ops = double(txBundle.TransportBlockSize) * max(1, double(txBundle.ActiveAMC.SpectralEfficiency)) * ...
    max(1, double(sixgr.util.structGet(decode, "DecoderIterations", 1))) * max(1, numel(txBundle.Copies));
end

function T = localAnnotateMap(T, point, trialIndex, harqIndex, copyIndex, family)
if isempty(T)
    return;
end
T.ScenarioID = repmat(string(point.ScenarioID), height(T), 1);
T.TrialIndex = repmat(trialIndex, height(T), 1);
T.HARQTx = repmat(harqIndex, height(T), 1);
T.CopyIndex = repmat(copyIndex, height(T), 1);
T.SignalFamily = repmat(string(family), height(T), 1);
end

function T = localAnnotateLayerTrace(T, point, trialIndex, harqIndex)
if isempty(T)
    return;
end
T.ScenarioID = repmat(string(point.ScenarioID), height(T), 1);
T.TrialIndex = repmat(trialIndex, height(T), 1);
T.HARQTx = repmat(harqIndex, height(T), 1);
end

function localWriteOutputs(study)
outDir = char(study.OutputDir);
sixgr.util.jsonWrite(fullfile(outDir, "scenario_config.json"), study.Config);
sixgr.util.csvWriteTable(fullfile(outDir, "trial_level_results.csv"), study.TrialLevelResults);
sixgr.util.csvWriteTable(fullfile(outDir, "tb_level_results.csv"), study.TBLevelResults);
sixgr.util.csvWriteTable(fullfile(outDir, "codeword_level_results.csv"), study.CodewordLevelResults);
sixgr.util.csvWriteTable(fullfile(outDir, "layer_mapping_trace.csv"), study.LayerMappingTrace);
sixgr.util.csvWriteTable(fullfile(outDir, "fdra_allocations.csv"), study.FDRAAllocations);
sixgr.util.csvWriteTable(fullfile(outDir, "tdra_allocations.csv"), study.TDRAAllocations);
sixgr.util.csvWriteTable(fullfile(outDir, "dmrs_mapping.csv"), study.DMRSMapping);
sixgr.util.csvWriteTable(fullfile(outDir, "ptrs_mapping.csv"), study.PTRSMapping);
sixgr.util.csvWriteTable(fullfile(outDir, "channel_estimation_metrics.csv"), study.ChannelEstimationMetrics);
sixgr.util.csvWriteTable(fullfile(outDir, "parameter_estimation_metrics.csv"), study.ParameterEstimationMetrics);
sixgr.util.csvWriteTable(fullfile(outDir, "harq_trace.csv"), study.HARQTrace);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_snr.csv"), study.SummaryBySNR);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_band.csv"), study.SummaryByBand);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_fdra_type.csv"), study.SummaryByFDRAType);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_tdra_mode.csv"), study.SummaryByTDRAMode);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_dmrs_setting.csv"), study.SummaryByDMRSSetting);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_ptrs_setting.csv"), study.SummaryByPTRSSetting);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_rank.csv"), study.SummaryByRank);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_repetition.csv"), study.SummaryByRepetition);
sixgr.util.csvWriteTable(fullfile(outDir, "complexity_summary.csv"), study.ComplexitySummary);
if ~isempty(study.MRSSOverlapEvents)
    sixgr.util.csvWriteTable(fullfile(outDir, "mrss_overlap_events.csv"), study.MRSSOverlapEvents);
end
end

function localWritePlots(study)
outDir = char(study.OutputDir);
localLinePlot(study.SummaryBySNR, "snr_db", "mean_BLER", fullfile(outDir, "bler_vs_snr.png"), "BLER vs SNR");
localLinePlot(study.SummaryBySNR, "snr_db", "mean_Throughput_bps", fullfile(outDir, "throughput_vs_snr.png"), "Throughput vs SNR");
localLinePlot(study.SummaryBySNR, "snr_db", "mean_SE", fullfile(outDir, "se_vs_snr.png"), "SE vs SNR");
localBarPlot(study.SummaryByFDRAType, "fdra_type", "mean_BLER", fullfile(outDir, "bler_by_fdra_type.png"), "BLER by FDRA Type");
localBarPlot(study.SummaryByFDRAType, "fdra_type", "mean_Throughput_bps", fullfile(outDir, "throughput_by_fdra_type.png"), "Throughput by FDRA Type");
localBarPlot(study.SummaryByTDRAMode, "tdra_mode", "mean_BLER", fullfile(outDir, "performance_by_tdra.png"), "Performance by TDRA");
localBarPlot(study.SummaryByRepetition, "repetition_mode", "mean_BLER", fullfile(outDir, "performance_cross_slot_vs_repetition.png"), "Performance by Repetition");
localBarPlot(study.SummaryByDMRSSetting, "dmrs_config_summary", "mean_BLER", fullfile(outDir, "performance_by_dmrs_setting.png"), "Performance by DMRS");
localBarPlot(study.SummaryByPTRSSetting, "ptrs_enabled", "mean_BLER", fullfile(outDir, "performance_by_ptrs_setting.png"), "Performance by PTRS");
localLinePlot(study.ChannelEstimationMetrics, "estimated_sinr_db", "nmse_channel_est", fullfile(outDir, "channel_estimation_nmse_vs_snr.png"), "Channel Estimation NMSE");
localLinePlot(study.ParameterEstimationMetrics, "estimated_snr", "estimated_delay_spread", fullfile(outDir, "parameter_estimation_quality_vs_snr.png"), "Parameter Estimation Quality");
localLinePlot(study.TrialLevelResults, "snr_db", "complexity_proxy_ops", fullfile(outDir, "complexity_vs_snr.png"), "Complexity vs SNR");
localLinePlot(study.ComplexitySummary, "AverageTBSize_bits", "AverageComplexityOps", fullfile(outDir, "complexity_vs_dmrs_overhead.png"), "Complexity vs DMRS Overhead");
localHeatmap(study.TrialLevelResults, "rank", "snr_db", "bler_flag", fullfile(outDir, "rank_vs_bler_heatmap.png"), "Rank vs BLER");
localHeatmap(study.TrialLevelResults, "rank", "snr_db", "throughput_bps", fullfile(outDir, "rank_vs_throughput_heatmap.png"), "Rank vs Throughput");
end

function T = localVertcat(T, addT)
if isempty(addT) || (istable(addT) && height(addT) == 0)
    return;
end
if isempty(T)
    T = addT;
else
    T = [T; addT];
end
end

function row = localEmptyTrialRow()
row = struct("seed",NaN,"scenario_id","","band","","duplex","","scs_khz",NaN,"bandwidth_mhz",NaN, ...
    "snr_db",NaN,"channel_model","","delay_spread_ns",NaN,"speed_kmh",NaN,"fdra_type","", ...
    "rb_start",NaN,"num_rb",NaN,"rb_bitmap_or_riv","","start_symbol",NaN,"num_symbols",NaN, ...
    "cross_slot_enabled",false,"repetition_mode","","repetition_count",NaN,"rank",NaN,"num_codewords",NaN, ...
    "modulation_per_cw","","target_code_rate_per_cw",NaN,"dmrs_config_summary","","ptrs_enabled",false, ...
    "phase_noise_enabled",false,"estimated_delay_spread",NaN,"estimated_doppler",NaN,"estimated_delay",NaN, ...
    "estimated_snr",NaN,"tb_size_bits",NaN,"coded_bits",NaN,"crc_pass",false,"bler_flag",NaN, ...
    "throughput_bits",NaN,"throughput_bps",NaN,"spectral_efficiency",NaN,"equalizer_type","", ...
    "rx_metric_summary","","complexity_proxy_ops",NaN,"trial_index",NaN,"tdra_mode","");
end

function row = localEmptyTBRow()
row = localEmptyTrialRow();
row.harq_tx = NaN;
row.rv = NaN;
row.avg_post_eq_evm = NaN;
row.avg_estimated_sinr_db = NaN;
end

function row = localEmptyCWRow()
row = localEmptyTBRow();
row.codeword_index = NaN;
end

function row = localEmptyFDRARow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"fdra_type","","rb_start",NaN,"num_rb",NaN,"rb_bitmap_or_riv","");
end

function row = localEmptyTDRARow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"copy_index",NaN,"slot_number",NaN,"start_symbol",NaN,"num_symbols",NaN);
end

function row = localEmptyChEstRow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"copy_index",NaN,"nmse_channel_est",NaN, ...
    "estimated_sinr_db",NaN,"estimated_sinr_source","","receiver_hest_sinr_db",NaN,"receiver_hest_sinr_source","", ...
    "post_eq_evm",NaN);
end

function row = localEmptyParamRow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"copy_index",NaN,"estimated_delay_spread",NaN, ...
    "estimated_doppler",NaN,"estimated_delay",NaN,"estimated_snr",NaN,"estimated_snr_source","");
end

function row = localEmptyHARQRow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"rv",NaN,"crc_pass",false,"tb_size_bits",NaN,"harq_combining_status","");
end

function row = localEmptyComplexityRow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"complexity_proxy_ops",NaN,"dmrs_overhead_re",NaN);
end

function row = localEmptyMRSSRow()
row = struct("scenario_id","","trial_index",NaN,"harq_tx",NaN,"mrss_mode","","overlapped_prb",NaN);
end

function row = localEmptyDLTrialRow()
row = struct("Status","","Frame",NaN,"Slot",NaN,"UE",NaN,"RNTI",NaN,"Modulation","","MCSIndex",NaN, ...
    "NumLayers",NaN,"TBSBits",NaN,"CRCError",false,"BLER",NaN,"ThroughputBits",NaN,"SINR_dB",NaN, ...
    "EVM",NaN,"TrialIndex",NaN,"HARQTx",NaN,"ScenarioID","","DMRSConfigSummary","", ...
    "PTRSEnabled",false,"PhaseNoiseEnabled",false,"FDRAType","","TDRAMode","","RepetitionMode","","QueueFitStatus","");
end

function row = localEmptyGrantRow()
row = struct("Direction","","TTI",NaN,"Time_s",NaN,"Frame",NaN,"Slot",NaN,"CellID",NaN,"BaseStationID",NaN, ...
    "UE",NaN,"UEID",NaN,"RNTI",NaN,"SlotDirection","","PRBStart",NaN,"PRBCount",NaN,"SymbolStart",NaN,"NumSymbols",NaN, ...
    "TBSBits",NaN,"TBSBytes",NaN,"CQIUsed",NaN,"MCSIndex",NaN,"Modulation","","NumLayers",NaN,"TargetCodeRate",NaN, ...
    "SINR_dB",NaN,"BLER",NaN,"Ack",false,"HarqID",NaN,"RV",NaN,"NDI",false,"IsRetransmission",false,"GrantReason","", ...
    "HeadOfLineDelay_ms",NaN,"BufferBytesBefore",NaN,"BufferBytesAfter",NaN,"GrantContextId","","LinkAdaptationMode","", ...
    "SchedulerGrantMCSSelectionMode","","RequestedOperatingPointSource","","AppliedOperatingPointSource","", ...
    "ActualMCSSelectionMode","","InterferenceMode","","Status","","PHYDecisionRole","","PHYDecisionStatus","", ...
    "PHYDecisionSource","","PHYDecisionReason","","WaveformReplayExecuted",false,"WaveformReplayReused",false,"WaveformReplayKey","");
end

function row = localBuildTrialRow(cfg, point, trialIndex, crcPass, throughputBits, tbSizeBits, codedBits, ...
        complexity, estDelaySpread, estDoppler, estDelay, estSNR, rxMetricSummary, fdraAlloc)
row = localEmptyTrialRow();
row.seed = double(cfg.Seed);
row.scenario_id = char(string(point.ScenarioID));
row.band = char(localBandLabel(cfg.CarrierFrequencyHz));
row.duplex = char(cfg.DuplexMode);
row.scs_khz = double(15 * 2^cfg.Numerology);
row.bandwidth_mhz = double(cfg.ChannelBandwidthMHz);
row.snr_db = double(point.SNRdB);
row.channel_model = char(string(point.ChannelModel));
row.delay_spread_ns = double(point.DelaySpread_ns);
row.speed_kmh = double(cfg.SpeedKmh);
row.fdra_type = char(string(fdraAlloc.FDRAType));
row.rb_start = double(fdraAlloc.RBStart);
row.num_rb = double(fdraAlloc.NumRB);
row.rb_bitmap_or_riv = char(string(fdraAlloc.BitmapOrRIV));
row.start_symbol = double(point.StartSymbol);
row.num_symbols = double(point.NumSymbols);
row.cross_slot_enabled = false;
row.repetition_mode = char(string(point.RepetitionMode));
row.repetition_count = double(cfg.RepetitionCount);
row.rank = double(point.Rank);
row.num_codewords = double(cfg.NumCodewords);
row.modulation_per_cw = char(string(cfg.ModulationPerCodeword{1}));
row.target_code_rate_per_cw = double(cfg.TargetCodeRatePerCodeword(1));
row.dmrs_config_summary = sprintf("cfgType%d_addPos%d_ports%d", cfg.DMRS.ConfigType, cfg.DMRS.AdditionalPosition, cfg.DMRS.NumPorts);
row.ptrs_enabled = logical(cfg.PTRS.PTRSEnabled);
row.phase_noise_enabled = logical(cfg.EnablePhaseNoise);
row.estimated_delay_spread = double(estDelaySpread);
row.estimated_doppler = double(estDoppler);
row.estimated_delay = double(estDelay);
row.estimated_snr = double(estSNR);
row.tb_size_bits = double(tbSizeBits);
row.coded_bits = double(codedBits);
row.crc_pass = logical(crcPass);
row.bler_flag = double(~crcPass);
row.throughput_bits = double(throughputBits);
row.throughput_bps = double(localThroughputBps(cfg, throughputBits));
row.spectral_efficiency = double(localSpectralEfficiency(cfg, throughputBits));
row.equalizer_type = char(cfg.ReceiverType);
row.rx_metric_summary = char(string(rxMetricSummary));
row.complexity_proxy_ops = double(complexity);
row.trial_index = double(trialIndex);
row.tdra_mode = char(cfg.TDRA.MappingType);
end

function row = localBuildTBRow(cfg, point, trialIndex, harqTx, txBundle, decode, throughputBits, postEqEVM, sinrEst)
row = localEmptyTBRow();
base = localBuildTrialRow(cfg, point, trialIndex, logical(decode.CRCPass), throughputBits, txBundle.TransportBlockSize, ...
    double(sixgr.util.structGet(txBundle.Copies{1}.Tx, "G", NaN)), localComplexityProxy(txBundle, decode), ...
    NaN, NaN, NaN, mean(sinrEst, "omitnan"), ...
    string("avg_evm=" + num2str(mean(postEqEVM, "omitnan"), "%.4g")), txBundle.FDRA);
fields = fieldnames(base);
for i = 1:numel(fields)
    row.(fields{i}) = base.(fields{i});
end
row.harq_tx = double(harqTx);
row.rv = double(txBundle.RV);
row.avg_post_eq_evm = double(mean(postEqEVM, "omitnan"));
row.avg_estimated_sinr_db = double(mean(sinrEst, "omitnan"));
end

function row = localBuildCWRow(cfg, point, trialIndex, harqTx, txBundle, decode, throughputBits, postEqEVM, sinrEst)
row = localEmptyCWRow();
base = localBuildTBRow(cfg, point, trialIndex, harqTx, txBundle, decode, throughputBits, postEqEVM, sinrEst);
fields = fieldnames(base);
for i = 1:numel(fields)
    row.(fields{i}) = base.(fields{i});
end
row.codeword_index = 0;
end

function row = localBuildFDRARow(point, trialIndex, harqTx, fdraAlloc)
row = localEmptyFDRARow();
row.scenario_id = char(string(point.ScenarioID));
row.trial_index = double(trialIndex);
row.harq_tx = double(harqTx);
row.fdra_type = char(string(fdraAlloc.FDRAType));
row.rb_start = double(fdraAlloc.RBStart);
row.num_rb = double(fdraAlloc.NumRB);
row.rb_bitmap_or_riv = char(string(fdraAlloc.BitmapOrRIV));
end

function row = localBuildTDRARow(point, trialIndex, harqTx, copyIndex, copy)
row = localEmptyTDRARow();
row.scenario_id = char(string(point.ScenarioID));
row.trial_index = double(trialIndex);
row.harq_tx = double(harqTx);
row.copy_index = double(copyIndex);
row.slot_number = double(copy.TDRA.SlotNumber);
row.start_symbol = double(copy.TDRA.SymbolAllocation(1));
row.num_symbols = double(copy.TDRA.SymbolAllocation(2));
end

function row = localBuildChEstRow(point, trialIndex, harqTx, copyIndex, rxOut)
row = localEmptyChEstRow();
row.scenario_id = char(string(point.ScenarioID));
row.trial_index = double(trialIndex);
row.harq_tx = double(harqTx);
row.copy_index = double(copyIndex);
row.nmse_channel_est = double(sixgr.util.structGet(rxOut.ChannelEstimation, "NMSEProxy", NaN));
row.estimated_sinr_db = localBestStudySINR(rxOut.Rx);
row.estimated_sinr_source = char(localBestStudySINRSource(rxOut.Rx));
row.receiver_hest_sinr_db = double(sixgr.util.structGet(rxOut.Rx, "ReceiverHestSINR_dB", NaN));
row.receiver_hest_sinr_source = char(string(sixgr.util.structGet(rxOut.Rx, "ReceiverHestSINRSource", "")));
row.post_eq_evm = double(rxOut.PostEqEVM);
end

function row = localBuildParamRow(point, trialIndex, harqTx, copyIndex, rxOut)
row = localEmptyParamRow();
row.scenario_id = char(string(point.ScenarioID));
row.trial_index = double(trialIndex);
row.harq_tx = double(harqTx);
row.copy_index = double(copyIndex);
row.estimated_delay_spread = double(sixgr.util.structGet(rxOut.ParameterEstimation, "EstimatedDelaySpread_s", NaN));
row.estimated_doppler = double(sixgr.util.structGet(rxOut.ParameterEstimation, "EstimatedDoppler_Hz", NaN));
row.estimated_delay = double(sixgr.util.structGet(rxOut.ParameterEstimation, "EstimatedDelay_samples", NaN));
row.estimated_snr = double(sixgr.util.structGet(rxOut.ParameterEstimation, "EstimatedSNR_dB", NaN));
row.estimated_snr_source = char(string(sixgr.util.structGet(rxOut.ParameterEstimation, "EstimatedSNRSource", "")));
end

function sinr = localBestStudySINR(rx)
sinr = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
if isfinite(sinr)
    return;
end
sinr = NaN;
end

function source = localBestStudySINRSource(rx)
sinr = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
if isfinite(sinr)
    source = string(sixgr.util.structGet(rx, "PostEqSINRSource", "post_equalization_sinr_from_equalizer_channel_estimate"));
    if strlength(strtrim(source)) == 0
        source = "post_equalization_sinr_from_equalizer_channel_estimate";
    end
else
    source = "post_equalization_sinr_unavailable";
end
end

function row = localBuildHARQRow(point, trialIndex, harqTx, rv, crcPass, txBundle)
row = localEmptyHARQRow();
row.scenario_id = char(string(point.ScenarioID));
row.trial_index = double(trialIndex);
row.harq_tx = double(harqTx);
row.rv = double(rv);
row.crc_pass = logical(crcPass);
row.tb_size_bits = double(txBundle.TransportBlockSize);
row.harq_combining_status = "not_materialized_across_retx_attempts";
end

function row = localBuildGrantRow(cfg, point, trialIndex, harqTx, txBundle, crcPass, sinrEst)
row = localEmptyGrantRow();
row.Direction = "DL";
row.TTI = double(trialIndex);
row.Time_s = double((trialIndex - 1) * 1e-3);
row.Frame = double(cfg.FrameNumber);
row.Slot = double(cfg.SlotNumber);
row.CellID = double(cfg.CellID);
row.BaseStationID = 1;
row.UE = 1;
row.UEID = 1;
row.RNTI = double(cfg.RNTI);
row.SlotDirection = string(cfg.DuplexMode);
row.PRBStart = double(txBundle.FDRA.RBStart);
row.PRBCount = double(txBundle.FDRA.NumRB);
row.SymbolStart = double(txBundle.Copies{1}.TDRA.SymbolAllocation(1));
row.NumSymbols = double(txBundle.Copies{1}.TDRA.SymbolAllocation(2));
row.TBSBits = double(txBundle.TransportBlockSize);
row.TBSBytes = double(txBundle.TransportBlockSize / 8);
row.CQIUsed = NaN;
row.MCSIndex = double(txBundle.ActiveAMC.MCSIndex);
row.Modulation = string(txBundle.ActiveAMC.Modulation);
row.NumLayers = double(cfg.NumLayers);
row.TargetCodeRate = double(txBundle.ActiveAMC.TargetCodeRate);
row.SINR_dB = double(mean(sinrEst, "omitnan"));
row.BLER = double(~crcPass);
row.Ack = logical(crcPass);
row.HarqID = double(mod(harqTx - 1, cfg.HARQProcessCount));
row.RV = double(txBundle.RV);
row.NDI = logical(harqTx == 1);
row.IsRetransmission = logical(harqTx > 1);
row.GrantReason = "pdsch6gr_truth_study";
row.HeadOfLineDelay_ms = 0;
row.BufferBytesBefore = double(ceil(cfg.QueueBits / 8));
row.BufferBytesAfter = double(ceil(max(cfg.QueueBits - double(crcPass) * txBundle.PayloadBitsBeforePadding, 0) / 8));
row.GrantContextId = "pdsch6gr_trial_" + string(trialIndex);
row.LinkAdaptationMode = string(cfg.LinkAdaptationMode);
row.SchedulerGrantMCSSelectionMode = string(txBundle.ActiveAMC.Policy);
row.RequestedOperatingPointSource = "scheduler_fdra_tdra_truth_path";
row.AppliedOperatingPointSource = "scheduler_fdra_tdra_truth_path";
row.ActualMCSSelectionMode = string(txBundle.ActiveAMC.Policy);
row.InterferenceMode = "none";
row.Status = localTernary(crcPass, "PASS", "FAIL");
row.PHYDecisionRole = "truth_phy_chain";
row.PHYDecisionStatus = localTernary(crcPass, "PASS", "FAIL");
row.PHYDecisionSource = "pdsch6gr_truth_waveform_decode";
row.PHYDecisionReason = "";
row.WaveformReplayExecuted = true;
row.WaveformReplayReused = false;
row.WaveformReplayKey = "";
end

function row = localBuildDLTrialRow(cfg, point, trialIndex, harqTx, txBundle, crcPass, throughputBits, sinrEst, postEqEVM)
row = localEmptyDLTrialRow();
row.Status = localTernary(crcPass, "PASS", "FAIL");
row.Frame = double(cfg.FrameNumber);
row.Slot = double(cfg.SlotNumber);
row.UE = 1;
row.RNTI = double(cfg.RNTI);
row.Modulation = string(txBundle.ActiveAMC.Modulation);
row.MCSIndex = double(txBundle.ActiveAMC.MCSIndex);
row.NumLayers = double(cfg.NumLayers);
row.TBSBits = double(txBundle.TransportBlockSize);
row.CRCError = ~logical(crcPass);
row.BLER = double(~crcPass);
row.ThroughputBits = double(throughputBits);
row.SINR_dB = double(mean(sinrEst, "omitnan"));
row.EVM = double(mean(postEqEVM, "omitnan"));
row.TrialIndex = double(trialIndex);
row.HARQTx = double(harqTx);
row.ScenarioID = string(point.ScenarioID);
row.DMRSConfigSummary = sprintf("cfgType%d_addPos%d_ports%d", cfg.DMRS.ConfigType, cfg.DMRS.AdditionalPosition, cfg.DMRS.NumPorts);
row.PTRSEnabled = logical(cfg.PTRS.PTRSEnabled);
row.PhaseNoiseEnabled = logical(cfg.EnablePhaseNoise);
row.FDRAType = string(txBundle.FDRA.FDRAType);
row.TDRAMode = string(cfg.TDRA.MappingType);
row.RepetitionMode = string(cfg.RepetitionMode);
row.QueueFitStatus = string(txBundle.QueueFitStatus);
end

function row = localBuildComplexityRow(point, trialIndex, harqTx, txBundle, complexity)
row = localEmptyComplexityRow();
row.scenario_id = char(string(point.ScenarioID));
row.trial_index = double(trialIndex);
row.harq_tx = double(harqTx);
row.complexity_proxy_ops = double(complexity);
row.dmrs_overhead_re = double(height(txBundle.Copies{1}.DMRSTable));
end

function rows = localBuildMRSSRows(mrssOverlap, point, trialIndex, harqTx)
rows = repmat(localEmptyMRSSRow(), height(mrssOverlap), 1);
for i = 1:height(mrssOverlap)
    rows(i).scenario_id = char(string(point.ScenarioID));
    rows(i).trial_index = double(trialIndex);
    rows(i).harq_tx = double(harqTx);
    rows(i).mrss_mode = char(string(mrssOverlap.MRSSMode(i)));
    rows(i).overlapped_prb = double(mrssOverlap.OverlappedPRB(i));
end
end

function localLinePlot(T, xVar, yVar, filePath, titleText)
xName = char(string(xVar));
yName = char(string(yVar));
if isempty(T) || height(T) == 0 || ~all(ismember({xName, yName}, T.Properties.VariableNames))
    return;
end
fig = figure("Visible", "off");
plot(double(T.(xName)), double(T.(yName)), "-o", "LineWidth", 1.5);
grid on; xlabel(strrep(xName, "_", " ")); ylabel(strrep(yName, "_", " ")); title(titleText);
saveas(fig, filePath);
close(fig);
end

function localBarPlot(T, xVar, yVar, filePath, titleText)
xName = char(string(xVar));
yName = char(string(yVar));
if isempty(T) || height(T) == 0 || ~all(ismember({xName, yName}, T.Properties.VariableNames))
    return;
end
fig = figure("Visible", "off");
bar(categorical(string(T.(xName))), double(T.(yName)));
grid on; xlabel(strrep(xName, "_", " ")); ylabel(strrep(yName, "_", " ")); title(titleText);
saveas(fig, filePath);
close(fig);
end

function localHeatmap(T, xVar, yVar, zVar, filePath, titleText)
if isempty(T) || height(T) == 0
    return;
end
xName = char(string(xVar));
yName = char(string(yVar));
zName = char(string(zVar));
[G, xg, yg] = findgroups(T.(xName), T.(yName));
zg = splitapply(@mean, double(T.(zName)), G);
fig = figure("Visible", "off");
scatter(double(xg), double(yg), 80, zg, "filled");
colorbar; grid on; xlabel(strrep(xName, "_", " ")); ylabel(strrep(yName, "_", " ")); title(titleText);
saveas(fig, filePath);
close(fig);
end

function label = localBandLabel(fcHz)
if fcHz < 1e9
    label = "0p7GHz";
elseif fcHz < 3e9
    label = "2GHz";
elseif fcHz < 6e9
    label = "4GHz";
elseif fcHz < 10e9
    label = "7GHz";
else
    label = "30GHz";
end
end

function bps = localThroughputBps(cfg, bits)
slotDur = 1e-3 / 2^double(cfg.Numerology);
bps = double(bits) / max(slotDur * max(1, cfg.RepetitionCount), eps);
end

function se = localSpectralEfficiency(cfg, bits)
se = localThroughputBps(cfg, bits) / max(double(cfg.ChannelBandwidthMHz) * 1e6, eps);
end

function out = localTernary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
