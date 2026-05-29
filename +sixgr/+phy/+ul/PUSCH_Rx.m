function [rx, info] = PUSCH_Rx(rxWaveform, cfg, varargin)
%PUSCH_Rx Recover a basic PUSCH transmission (OFDM -> PUSCH -> UL-SCH).
%
%   [RX,INFO] = sixgr.phy.ul.PUSCH_Rx(RXWAVEFORM, CFG) performs
%   DMRS-aided timing, OFDM demodulation, channel estimation,
%   MMSE equalization, nrPUSCHDecode demodulation, LDPC rate recovery,
%   LDPC decoding, and transport block CRC checking.
%
%   Name-Value options:
%     "Carrier"     : nrCarrierConfig override
%     "PUSCH"       : nrPUSCHConfig override
%     "PUSCHIndices": mapping indices override
%     "TransportBlockSize": expected TB size (bits)
%     "TargetCodeRate": code rate (0..1)
%     "RV"          : redundancy version (0..3)
%     "NoiseVar"    : explicit runtime noise variance metadata
%     "ConfiguredNoiseVariance": explicit configured/derived AWGN variance
%     "MaxIterations": LDPC iterations
%     "Algorithm"   : LDPC algorithm ("Normalized min-sum" by default)
%
%   Outputs:
%     RX.TransportBlock     : recovered TB bits
%     RX.CRCError           : true if TB CRC fails
%     RX.Ok                 : ~CRCError
%     RX.CodewordLLR        : soft bits before rate recovery
%     RX.ChannelEstimate    : H estimate
%     RX.NoiseVar           : used noise variance
%     RX.NoiseVarStatus     : "OK" or "NOT_AVAILABLE"
%     RX.NoiseVarSource     : provenance for the used/unavailable noise variance
%     RX.NoiseVarReason     : explicit unavailable/validation reason
%     RX.TimingOffset       : raw estimated timing offset (samples)
%     RX.AppliedTimingCorrection_samples : applied waveform correction (samples)

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCHIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('TransportBlockSize', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ConfiguredNoiseVariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ConfiguredNoiseVarianceSource', 'configured_awgn_derivation', @(x) ischar(x) || isstring(x));
ip.addParameter('StrictNoiseVarianceRequired', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ReceiverTrackingState', [], @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% PUSCH config and indices
if isempty(opt.PUSCH)
    [puschInd, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg);
else
    pusch = opt.PUSCH;
    if isempty(opt.PUSCHIndices)
        try
            [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index');
        catch
            [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch);
        end
    else
        puschInd = opt.PUSCHIndices;
        try
            [~, puschInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index'); %#ok<ASGLU>
        catch
            [~, puschInfo] = nrPUSCHIndices(carrier, pusch); %#ok<ASGLU>
        end
    end
end

% Rx params
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pusch.rv', 0));
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pusch.codeRate', 0.4785));
end

maxIter = opt.MaxIterations;
if isempty(maxIter)
    maxIter = double(sixgr.util.structGet(cfg, 'phy.ldpc.maxIterations', ...
        sixgr.util.structGet(cfg, 'phy.ldpc.maxIter', 12)));
end

alg = opt.Algorithm;
if isempty(alg)
    alg = sixgr.util.structGet(cfg, 'phy.ldpc.algorithm', 'Normalized min-sum');
end
alg = char(string(alg));

% Determine TB size
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = double(sixgr.util.structGet(cfg, 'phy.pusch.xOverhead', 0));
    nPRB = numel(pusch.PRBSet);
    nrePerPRB = [];
    if isfield(puschInfo, 'NREPerPRB')
        nrePerPRB = double(puschInfo.NREPerPRB);
    elseif isfield(puschInfo, 'NRE')
        nrePerPRB = floor(double(puschInfo.NRE) / max(nPRB,1));
    elseif isfield(puschInfo, 'G')
        qm = localQm(pusch.Modulation);
        nrePerPRB = floor(double(puschInfo.G) / max(qm * pusch.NumLayers * nPRB, 1));
    end
    if isempty(nrePerPRB) || ~isfinite(nrePerPRB) || nrePerPRB <= 0
        nrePerPRB = 144;
    end
    trBlkSize = nrTBS(pusch.Modulation, pusch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
end
trBlkSize = double(trBlkSize);

% Base graph
tbCRCType = '24A';
tbCRCLen = 24;
try
    ulschInfo = nrULSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(ulschInfo.BGN);
    [tbCRCType, tbCRCLen] = localResolveTBCRCSpec(ulschInfo, tbCRCType, tbCRCLen);
catch
    bgn = 2;
end

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);
useFastAWGNPath = logical(opt.FastAWGNPath);
strictMode = logical(sixgr.util.structGet(cfg, 'run.strictMode', false));
channelModelToken = localResolveEstimatorChannelModel(cfg);
numTxPorts = localExpectedTxPorts(pusch);
localValidateFastScalarShortcut(channelModelToken, numTxPorts, max(1, size(rxWaveform, 2)), useFastAWGNPath, "PUSCH_Rx");

% Timing estimate
trackingCorrection = localResolveReceiverTrackingCorrection(opt.ReceiverTrackingState, cfg);
sampleRateHz = localCarrierSampleRateHz(carrier);
if logical(trackingCorrection.CFOEstimateAvailable) && isfinite(double(trackingCorrection.EstimatedCFO_Hz)) && ...
        isfinite(sampleRateHz) && sampleRateHz > 0
    rxWaveform = localApplyFrequencyCorrection(rxWaveform, sampleRateHz, -double(trackingCorrection.EstimatedCFO_Hz));
    trackingCorrection.CFOCorrectionApplied = true;
    trackingCorrection.CFOCorrectionApplied_Hz = double(trackingCorrection.EstimatedCFO_Hz);
elseif logical(trackingCorrection.CFOEstimateAvailable)
    trackingCorrection.CFONAReason = "receiver_tracking_cfo_estimate_present_but_sample_rate_unavailable";
end

rawTimingEstimate = NaN;
timingEstimateUsed = false;
timingEstimateSource = "unavailable";
if logical(trackingCorrection.TimingEstimateAvailable) && isfinite(double(trackingCorrection.TimingEstimate_samples))
    rawTimingEstimate = double(trackingCorrection.TimingEstimate_samples);
    timingEstimateUsed = true;
    timingEstimateSource = string(trackingCorrection.Source);
    trackingCorrection.TimingCorrectionApplied = true;
elseif ~useFastAWGNPath && ~logical(opt.SkipTimingEstimate)
    try
        rawTimingEstimate = double(nrTimingEstimate(carrier, rxWaveform, dmrsInd, dmrsSym));
        timingEstimateUsed = true;
        timingEstimateSource = "nrTimingEstimate_dmrs";
    catch
        rawTimingEstimate = NaN;
        timingEstimateUsed = false;
        timingEstimateSource = "nrTimingEstimate_failed";
    end
end

timingResolution = sixgr.phy.sync.resolveTimingApplication(rawTimingEstimate, ...
    "EstimateUsed", timingEstimateUsed, ...
    "ApplicationMode", "signed_waveform_shift", ...
    "SkipRequested", logical(opt.SkipTimingEstimate), ...
    "Source", timingEstimateSource);
trackingCorrection.TimingCorrectionApplied = logical(timingResolution.EstimateUsed);
rxWaveform = localApplyTimingCorrection(rxWaveform, timingResolution.AppliedCorrection_samples);

% OFDM demod
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);

% Channel estimate
Hest = [];
nVarEst = [];
estInfo = struct();
useFastChEstMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if useFastAWGNPath
    Hest = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 0;
    estInfo = struct( ...
        "EngineUsed", "unit-flat-shortcut", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true);
else
    [Hest, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym, ...
        "UseFastMex", useFastChEstMex, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", numTxPorts, ...
        "ContextLabel", "PUSCH_Rx");
end

% Noise variance
noiseCandidate = opt.NoiseVar;
noiseSource = "runtime_metadata";
if isempty(noiseCandidate)
    noiseCandidate = nVarEst;
    noiseSource = "runtime_channel_estimate";
else
    noiseCandidate = localConvertNoiseVarToGridDomain(noiseCandidate, ofdmInfo);
end
configuredNoiseVariance = opt.ConfiguredNoiseVariance;
if ~isempty(configuredNoiseVariance)
    configuredNoiseVariance = localConvertNoiseVarToGridDomain(configuredNoiseVariance, ofdmInfo);
end
[nVar, noiseStatus] = sixgr.phy.ul.resolveULNoiseVariance(noiseCandidate, cfg, ...
    "ChannelType", "PUSCH", ...
    "OriginalSource", noiseSource, ...
    "StrictRequired", opt.StrictNoiseVarianceRequired, ...
    "ConfiguredNoiseVariance", configuredNoiseVariance, ...
    "ConfiguredNoiseVarianceSource", opt.ConfiguredNoiseVarianceSource);
nVar = double(nVar);
if ~logical(noiseStatus.IsValid)
    [rx, info] = localBuildUnavailableNoiseVarianceRx( ...
        trBlkSize, Hest, rxGrid, dmrsInd, dmrsSym, carrier, pusch, puschInfo, ...
        cinfo, ofdmInfo, estInfo, trackingCorrection, timingResolution, ...
        nVar, noiseStatus, logical(opt.CompactOutput));
    return;
end

% Extract resources
[rxSym, hestSym] = nrExtractResources(puschInd, rxGrid, Hest);

% Equalize
[eqSym, csi] = nrEqualizeMMSE(rxSym, hestSym, nVar);
receiverSINR = localReceiverHestSINR(Hest, nVar, cfg, "UL", rxGrid, dmrsInd, dmrsSym);

% Decode PUSCH to codeword LLR
puschRxSym = [];
try
    [cwLLR, puschRxSym] = nrPUSCHDecode(carrier, pusch, eqSym, nVar);
catch
    cwLLR = nrPUSCHDecode(carrier, pusch, eqSym, nVar);
end

if iscell(cwLLR)
    cwLLR = cwLLR{1};
end
cwLLR = localApplyCSIToCodewordLLR(cwLLR, csi, pusch.Modulation);

% Rate recover (to code blocks)
recLLR = sixgr.phy.phycode.rateRecoverLDPC(cwLLR, trBlkSize, targetCodeRate, rv, pusch.Modulation, pusch.NumLayers);
recLLRBatch = localEnsureLLRBatch(recLLR);

% LDPC decode each code block
C = size(recLLRBatch, 2);
actIter = zeros(1, C);
parity = zeros(1, C);
decodeTic = tic;
useMexLDPC = logical(sixgr.util.structGet(cfg, 'phy.ldpc.useMexBatchDecode', false)) ...
    && (exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3 || exist("sixgr_ldpc_decode_batch_kernel","file") == 2);

if useMexLDPC
    useNormMinSum = uint8(strcmpi(char(alg), 'Normalized min-sum'));
    try
        if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
            [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
        else
            [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
        end
        maxLen = max(1, min(size(decMat,1), round(max(decLen(:)))));
        decCbs = int8(decMat(1:maxLen, :));
        actIter(:) = reshape(actIterV(:), 1, []);
        parity(:) = reshape(parityV(:), 1, []);
    catch
        useMexLDPC = false;
    end
end

if ~useMexLDPC
    nRow = size(recLLRBatch, 1);
    decCbs = zeros(nRow, C, 'int8');
    maxLen = 0;
    usePar = (C > 1) && logical(sixgr.util.structGet(cfg, 'run.useParallel', false)) ...
        && license('test','Distrib_Computing_Toolbox') && ~isempty(gcp('nocreate'));
    if usePar
        dCell = cell(C,1);
        dLen = zeros(C,1);
        itV = zeros(C,1);
        pcV = zeros(C,1);
        parfor c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            dCell{c} = d;
            dLen(c) = min(numel(d), nRow);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = 0; end
            if isempty(pc), pc = 0; end
            itV(c) = it(1);
            pcV(c) = pc(1);
        end
        for c = 1:C
            actIter(c) = itV(c);
            parity(c) = pcV(c);
            Ld = dLen(c);
            if Ld > 0
                decCbs(1:Ld, c) = dCell{c}(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    else
        for c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = 0; end
            if isempty(pc), pc = 0; end
            actIter(c) = it(1);
            parity(c) = pc(1);
            d = int8(d(:));
            Ld = min(numel(d), nRow);
            if Ld > 0
                decCbs(1:Ld, c) = d(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    end
    if maxLen <= 0
        decCbs = zeros(1, C, 'int8');
    else
        decCbs = decCbs(1:maxLen, :);
    end
end
decodeLatency_s = toc(decodeTic);

% Code block desegmentation + TB CRC check
B = trBlkSize + tbCRCLen;
[tbCrc, cbCrcErr] = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);
[tbBits, crcOK, crcErr] = sixgr.phy.tb.checkCRC(tbCrc, tbCRCType);

% Outputs
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOK);
rx.NoiseVar = nVar;
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
rx.ReceiverUsable = true;
rx.DecodeAttempted = true;
rx.DecodeUsable = true;
rx.FailureReason = "";
rx.TimingOffset = double(timingResolution.RawEstimate_samples);
rx.RawTimingEstimate_samples = double(timingResolution.RawEstimate_samples);
rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
rx.TimingEstimateUsed = logical(timingResolution.EstimateUsed);
rx.TimingEstimateSource = char(timingEstimateSource);
rx.TimingEstimateStatus = char(string(timingResolution.Status));
rx.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
rx.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
rx.DecodeLatency_s = double(decodeLatency_s);
rx.MaxDecoderIterations = double(maxIter);
rx.CFOEstimateAvailable = logical(trackingCorrection.CFOEstimateAvailable);
rx.EstimatedCFO_Hz = double(trackingCorrection.EstimatedCFO_Hz);
rx.CFOCorrectionApplied = logical(trackingCorrection.CFOCorrectionApplied);
rx.CFOCorrectionApplied_Hz = double(trackingCorrection.CFOCorrectionApplied_Hz);
rx.ReceiverTrackingCorrectionSource = char(string(trackingCorrection.Source));
rx.ReceiverTrackingCorrectionStatus = char(string(trackingCorrection.Status));
rx.ReceiverTrackingCorrectionNAReason = char(string(trackingCorrection.NAReason));
rx.ReceiverHestSINR_dB = double(receiverSINR.Value);
rx.ReceiverHestSINRSource = char(receiverSINR.Source);
rx.ReceiverHestSINRValueRole = char(receiverSINR.ValueRole);
rx.ReceiverHestSINRValueStatus = char(receiverSINR.ValueStatus);
rx.ReceiverHestSINRNAReason = char(receiverSINR.NAReason);
rx.EqualizedSymbolsForEvidence = eqSym;
rx.PUSCHRxSymbolsForEvidence = puschRxSym;
if ~logical(opt.CompactOutput)
    rx.TransportBlock = int8(tbBits(:));
    rx.CodewordLLR = cwLLR;
    rx.RateRecoveredLLR = recLLR;
    rx.DecodedCodeBlocks = decCbs;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.CodeBlockCRCError = cbCrcErr;
    rx.ChannelEstimate = Hest;
    rx.RxGrid = rxGrid;
    rx.DMRSIndices = dmrsInd;
    rx.DMRSSymbols = dmrsSym;
    rx.Carrier = carrier;
    rx.PUSCH = pusch;
    rx.PUSCHInfo = puschInfo;
    rx.EqualizedSymbols = eqSym;
    rx.PUSCHRxSymbols = puschRxSym;
    rx.CSI = csi;
end

info = struct();
info.CarrierInfo = cinfo;
info.OFDM = ofdmInfo;
info.ChannelEstimation = estInfo;
info.ReceiverTrackingCorrection = trackingCorrection;
info.NoiseVariance = noiseStatus;
info.TimingEstimate = timingResolution;

end

function tracking = localResolveReceiverTrackingCorrection(explicitState, cfg)
tracking = struct( ...
    "TRSProcessed", false, ...
    "TimingEstimateAvailable", false, ...
    "TimingEstimate_samples", NaN, ...
    "TimingCorrectionApplied", false, ...
    "CFOEstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, ...
    "CFOCorrectionApplied", false, ...
    "CFOCorrectionApplied_Hz", NaN, ...
    "Source", "unavailable_receiver_tracking_state", ...
    "Status", "unavailable", ...
    "NAReason", "no_receiver_tracking_state", ...
    "CFONAReason", "");

raw = explicitState;
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
end
if ~(isstruct(raw) && ~isempty(fieldnames(raw)))
    return;
end

processed = localFirstLogical(raw, ["TRSProcessed","RuntimeTRSProcessed"], false);
tracking.TRSProcessed = logical(processed);
tracking.Source = localFirstString(raw, ["RuntimeTRSRuntimeEvidenceSource","RuntimeEvidenceSource","TrackingEstimateSource"], ...
    "trs_receiver_tracking_state");
if ~processed
    tracking.NAReason = "trs_tracking_state_not_processed";
    return;
end

stateTokens = [ ...
    localFirstString(raw, ["TrackingState","RuntimeTRSTrackingStateAfter"], ""), ...
    localFirstString(raw, ["TRSValidityState","RuntimeTRSValidityState"], ""), ...
    localFirstString(raw, ["ChannelTrackingFreshnessState","RuntimeTRSChannelTrackingFreshnessState"], "")];
stateTokensLower = lower(stateTokens);
if any(contains(stateTokensLower, "stale") | contains(stateTokensLower, "expired") | ...
        contains(stateTokensLower, "invalid") | contains(stateTokensLower, "fail") | ...
        contains(stateTokensLower, "inactive"))
    tracking.NAReason = "trs_tracking_state_stale_or_invalid";
    return;
end

timingAvailable = localFirstLogical(raw, ["TimingEstimateAvailable","RuntimeTRSTimingEstimateAvailable"], false);
timingSamples = localFirstFinite(raw, ["TimingEstimate_samples","RuntimeTRSTimingEstimate_samples","EstimatedTimingOffset_samples"], NaN);
cfoAvailable = localFirstLogical(raw, ["CFOEstimateAvailable","RuntimeTRSCFOEstimateAvailable"], false);
cfoHz = localFirstFinite(raw, ["EstimatedCFO_Hz","RuntimeTRSEstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN);

tracking.TimingEstimateAvailable = logical(timingAvailable && isfinite(timingSamples));
tracking.TimingEstimate_samples = double(timingSamples);
tracking.CFOEstimateAvailable = logical(cfoAvailable && isfinite(cfoHz));
tracking.EstimatedCFO_Hz = double(cfoHz);
if tracking.TimingEstimateAvailable || tracking.CFOEstimateAvailable
    tracking.Status = "available";
    tracking.NAReason = "";
else
    tracking.NAReason = "trs_tracking_state_has_no_timing_or_cfo_estimate";
end
end

function y = localApplyFrequencyCorrection(x, sampleRateHz, correctionHz)
if ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0 && isfinite(double(correctionHz)))
    y = x;
    return;
end
n = (0:size(x, 1)-1).';
rot = exp(1j * 2 * pi * (double(correctionHz) / double(sampleRateHz)) * n);
y = x .* cast(rot, "like", x);
end

function y = localApplyTimingCorrection(x, timingOffset)
timingOffset = round(double(timingOffset));
if ~isfinite(timingOffset) || timingOffset == 0
    y = x;
elseif timingOffset > 0
    if timingOffset < size(x, 1)
        y = [x(1+timingOffset:end, :); zeros(timingOffset, size(x, 2), "like", x)];
    else
        y = zeros(size(x), "like", x);
    end
else
    lead = abs(timingOffset);
    if lead < size(x, 1)
        y = [zeros(lead, size(x, 2), "like", x); x(1:end-lead, :)];
    else
        y = zeros(size(x), "like", x);
    end
end
end

function fs = localCarrierSampleRateHz(carrier)
fs = NaN;
try
    ofdmInfo = nrOFDMInfo(carrier);
    fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", NaN));
catch
end
end

function value = localFirstLogical(s, names, defaultValue)
value = logical(defaultValue);
for i = 1:numel(names)
    name = char(names(i));
    if isfield(s, name)
        raw = s.(name);
        if ~isempty(raw)
            value = logical(raw(1));
            return;
        end
    end
end
end

function value = localFirstFinite(s, names, defaultValue)
value = double(defaultValue);
for i = 1:numel(names)
    name = char(names(i));
    if isfield(s, name)
        raw = double(s.(name));
        raw = raw(isfinite(raw));
        if ~isempty(raw)
            value = raw(1);
            return;
        end
    end
end
end

function value = localFirstString(s, names, defaultValue)
value = string(defaultValue);
for i = 1:numel(names)
    name = char(names(i));
    if isfield(s, name)
        raw = string(s.(name));
        if ~isempty(raw) && strlength(strtrim(raw(1))) > 0
            value = raw(1);
            return;
        end
    end
end
end

function evidence = localReceiverHestSINR(Hest, nVar, cfg, direction, rxGrid, refInd, refSym)
evidence = struct( ...
    "Value", NaN, ...
    "Source", "unavailable_ul_receiver_measurement_failed", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "ul_receiver_measurement_not_available");
if isempty(Hest)
    evidence.NAReason = "ul_receiver_hest_grid_empty";
    return;
end
try
    ulMetric = sixgr.phy.ul.measureULLinkState(Hest, nVar, cfg, ...
        "ReceivedGrid", rxGrid, ...
        "ReferenceIndices", refInd, ...
        "ReferenceSymbols", refSym);
    sinr = double(sixgr.util.structGet(ulMetric, "SINR_dB", NaN));
    if isfinite(sinr)
        evidence.Value = sinr;
        evidence.Source = char(string(sixgr.util.structGet(ulMetric, "SINRSource", "reference_signal_pilot_residual_nmse")));
        evidence.ValueRole = char(string(sixgr.util.structGet(ulMetric, "SINRValueRole", "estimated")));
        evidence.ValueStatus = char(string(sixgr.util.structGet(ulMetric, "SINRValueStatus", "OK")));
        evidence.NAReason = "";
    else
        evidence.Source = char(string(sixgr.util.structGet(ulMetric, "SINRSource", evidence.Source)));
        evidence.ValueRole = char(string(sixgr.util.structGet(ulMetric, "SINRValueRole", evidence.ValueRole)));
        evidence.ValueStatus = char(string(sixgr.util.structGet(ulMetric, "SINRValueStatus", evidence.ValueStatus)));
        evidence.NAReason = char(string(sixgr.util.structGet(ulMetric, "SINRNAReason", evidence.NAReason)));
    end
catch ME
    evidence.NAReason = "ul_receiver_measurement_failed:" + string(ME.identifier);
end
end

function [crcType, crcLen] = localResolveTBCRCSpec(schInfo, defaultType, defaultLen)
crcType = defaultType;
crcLen = defaultLen;
if nargin < 1 || ~isstruct(schInfo)
    return;
end
rawType = char(string(sixgr.util.structGet(schInfo, 'CRC', defaultType)));
if ~isempty(rawType)
    crcType = rawType;
end
rawLen = double(sixgr.util.structGet(schInfo, 'L', defaultLen));
if isfinite(rawLen) && rawLen >= 0
    crcLen = rawLen;
end
end

function qm = localQm(modScheme)
switch upper(char(string(modScheme)))
    case {'PI/2-BPSK','BPSK'}
        qm = 1;
    case 'QPSK'
        qm = 2;
    case '16QAM'
        qm = 4;
    case '64QAM'
        qm = 6;
    case '256QAM'
        qm = 8;
    case '1024QAM'
        qm = 10;
    case '4096QAM'
        qm = 12;
    otherwise
        qm = 2;
end
end

function llrOut = localApplyCSIToCodewordLLR(llrIn, csi, modScheme)
% 5G Toolbox decoders expect equalizer reliability to weight codeword LLRs.
llrOut = double(llrIn(:));
if isempty(csi)
    return;
end
try
    csiCW = nrLayerDemap(csi);
    if iscell(csiCW)
        csiVec = csiCW{1};
    else
        csiVec = csiCW;
    end
catch
    csiVec = csi;
end
csiVec = double(real(csiVec(:)));
csiVec(~isfinite(csiVec) | csiVec < 0) = 0;
if isempty(csiVec) || ~any(csiVec > 0)
    return;
end
qm = max(1, round(double(localQm(modScheme))));
if numel(csiVec) * qm == numel(llrOut)
    weights = repelem(csiVec, qm);
elseif numel(csiVec) == numel(llrOut)
    weights = csiVec;
else
    return;
end
llrOut = llrOut .* weights;
end

function x = localEnsureLLRBatch(xIn)
% Ensure a dense 2-D floating matrix for batch LDPC decode kernels.
x = xIn;
if ~(isa(x, 'double') || isa(x, 'single'))
    x = double(x);
end
if ~ismatrix(x)
    x = reshape(x, size(x,1), []);
else
    x = reshape(x, size(x,1), size(x,2));
end
end

function numTxPorts = localExpectedTxPorts(pusch)
numTxPorts = 1;
try
    numTxPorts = max(numTxPorts, double(pusch.NumAntennaPorts));
catch
end
try
    numTxPorts = max(numTxPorts, double(pusch.NumLayers));
catch
end
if ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1)
    numTxPorts = 1;
end
numTxPorts = max(1, round(numTxPorts));
end

function localValidateFastScalarShortcut(channelToken, numTxPorts, numRxAnt, useFastAWGNPath, contextLabel)
if ~logical(useFastAWGNPath)
    return;
end
if ~(localIsExplicitFlatChannel(channelToken) && numTxPorts <= 1 && numRxAnt <= 1)
    error("sixgr:phy:rx:InvalidFastScalarShortcut", ...
        "%s requires an explicit AWGN/flat SISO validation mode. Channel='%s', TxPorts=%d, RxAnt=%d.", ...
        contextLabel, localDisplayChannelToken(channelToken), numTxPorts, numRxAnt);
end
end

function channelToken = localResolveEstimatorChannelModel(cfg)
awgnOnly = logical(sixgr.util.structGet(cfg, 'channel.awgnOnly', false));
modelToken = localNormalizeChannelToken(sixgr.util.structGet(cfg, 'channel.model', ''));
fadingModelToken = localNormalizeChannelToken(sixgr.util.structGet(cfg, 'channel.fading.model', ''));
if awgnOnly || any(modelToken == ["AWGN", "NONE", "OFF"]) || any(fadingModelToken == ["AWGN", "NONE", "OFF"])
    channelToken = "AWGN";
    return;
end

candidates = { ...
    sixgr.util.structGet(cfg, 'channel.tdlProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.cdlProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.delayProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.fading.profile', ''), ...
    sixgr.util.structGet(cfg, 'channel.model', ''), ...
    sixgr.util.structGet(cfg, 'channel.fading.model', '') ...
    };

channelToken = "";
for i = 1:numel(candidates)
    token = localNormalizeChannelToken(candidates{i});
    if startsWith(token, "TDL") || startsWith(token, "CDL")
        channelToken = token;
        return;
    end
    if strlength(token) > 0 && strlength(channelToken) == 0
        channelToken = token;
    end
end
end

function nVarGrid = localConvertNoiseVarToGridDomain(nVarTime, ofdmInfo)
nVarGrid = double(nVarTime);
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
if isfinite(nfft) && nfft > 0
    nVarGrid = nVarGrid * nfft;
end
end

function [rx, info] = localBuildUnavailableNoiseVarianceRx( ...
        trBlkSize, Hest, rxGrid, dmrsInd, dmrsSym, carrier, pusch, puschInfo, ...
        cinfo, ofdmInfo, estInfo, trackingCorrection, timingResolution, ...
        nVar, noiseStatus, compactOutput)
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.TransportBlock = int8([]);
rx.CRCError = true;
rx.Ok = false;
rx.NoiseVar = double(nVar);
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
rx.ReceiverUsable = false;
rx.DecodeAttempted = false;
rx.DecodeUsable = false;
rx.FailureReason = char(string(noiseStatus.Reason));
rx.TimingOffset = double(timingResolution.RawEstimate_samples);
rx.RawTimingEstimate_samples = double(timingResolution.RawEstimate_samples);
rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
rx.TimingEstimateUsed = logical(timingResolution.EstimateUsed);
rx.TimingEstimateSource = char(string(timingResolution.Source));
rx.TimingEstimateStatus = char(string(timingResolution.Status));
rx.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
rx.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
rx.DecodeLatency_s = NaN;
rx.MaxDecoderIterations = NaN;
rx.CFOEstimateAvailable = logical(trackingCorrection.CFOEstimateAvailable);
rx.EstimatedCFO_Hz = double(trackingCorrection.EstimatedCFO_Hz);
rx.CFOCorrectionApplied = logical(trackingCorrection.CFOCorrectionApplied);
rx.CFOCorrectionApplied_Hz = double(trackingCorrection.CFOCorrectionApplied_Hz);
rx.ReceiverTrackingCorrectionSource = char(string(trackingCorrection.Source));
rx.ReceiverTrackingCorrectionStatus = char(string(trackingCorrection.Status));
rx.ReceiverTrackingCorrectionNAReason = char(string(trackingCorrection.NAReason));
rx.ReceiverHestSINR_dB = NaN;
rx.ReceiverHestSINRSource = "unavailable_ul_noise_variance_required";
rx.ReceiverHestSINRValueRole = "unavailable";
rx.ReceiverHestSINRValueStatus = "unavailable";
rx.ReceiverHestSINRNAReason = char(string(noiseStatus.Reason));
rx.EqualizedSymbolsForEvidence = complex([]);
rx.PUSCHRxSymbolsForEvidence = complex([]);
if ~compactOutput
    rx.CodewordLLR = double([]);
    rx.RateRecoveredLLR = double([]);
    rx.DecodedCodeBlocks = int8([]);
    rx.ActiveIterations = double([]);
    rx.ParityChecks = double([]);
    rx.CodeBlockCRCError = double([]);
    rx.ChannelEstimate = Hest;
    rx.RxGrid = rxGrid;
    rx.DMRSIndices = dmrsInd;
    rx.DMRSSymbols = dmrsSym;
    rx.Carrier = carrier;
    rx.PUSCH = pusch;
    rx.PUSCHInfo = puschInfo;
    rx.EqualizedSymbols = complex([]);
    rx.PUSCHRxSymbols = complex([]);
    rx.CSI = double([]);
end

info = struct();
info.CarrierInfo = cinfo;
info.OFDM = ofdmInfo;
info.ChannelEstimation = estInfo;
info.ReceiverTrackingCorrection = trackingCorrection;
info.NoiseVariance = noiseStatus;
info.TimingEstimate = timingResolution;
end

function token = localNormalizeChannelToken(rawValue)
token = upper(strtrim(string(rawValue)));
end

function tf = localIsExplicitFlatChannel(channelToken)
tf = any(strcmpi(char(string(channelToken)), {'AWGN', 'NONE', 'OFF'}));
end

function token = localDisplayChannelToken(channelToken)
token = char(string(channelToken));
if isempty(token)
    token = '<unspecified>';
end
end
