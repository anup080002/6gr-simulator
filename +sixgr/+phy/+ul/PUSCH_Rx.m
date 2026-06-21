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
%     "NoiseVarDomain": "time", "grid", "frequency", or "auto"
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
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('ConfiguredNoiseVariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ConfiguredNoiseVarianceSource', 'configured_awgn_derivation', @(x) ischar(x) || isstring(x));
ip.addParameter('StrictNoiseVarianceRequired', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('ExpectedHARQACKBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x));
ip.addParameter('HARQSoftBufferLLR', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ReceiverTrackingState', [], @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;
profScope = sixgr.perf.TimeProfiler.scope("sixgr.phy.ul.PUSCH_Rx", ...
    "Stage", "ul_pusch_rx", ...
    "Metadata", struct( ...
    "NSamples", double(numel(rxWaveform)), ...
    "NSubcarriers", double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)) * 12, ...
    "NSymbols", 14, ...
    "NRx", double(max(1, size(rxWaveform, 2))), ...
    "NTx", double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1)), ...
    "NLayers", double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)), ...
    "TBSBits", double(localScalarOrNaN(opt.TransportBlockSize)), ...
    "MaxIterations", double(localScalarOrNaN(opt.MaxIterations)))); %#ok<NASGU>

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
    pusch = localEnsureTransformPrecodingOwnership(pusch, cfg);
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
    maxIter = sixgr.phy.phycode.resolveLDPCMaxIterations(cfg, "Direction", "UL");
end

alg = opt.Algorithm;
if isempty(alg)
    alg = sixgr.util.structGet(cfg, 'phy.ldpc.algorithm', 'Normalized min-sum');
end
alg = char(string(alg));

% Determine TB size
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = localResolvePUSCHXOverhead(pusch, cfg);
    nPRB = numel(pusch.PRBSet);
    nrePerPRB = localResolvePUSCHNREPerPRBOrError(carrier, pusch, puschInfo, nPRB);
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
ldpcSeg = localResolveExpectedLDPCSegmentation(trBlkSize, bgn, tbCRCType);

% DMRS
[dmrsInd, dmrsSym, dmrsInfo] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);
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
    "Source", timingEstimateSource, ...
    "MaxCorrectionSamples", localMaxTimingCorrectionSamples(carrier));
trackingCorrection.TimingCorrectionApplied = logical(timingResolution.EstimateUsed);
rxWaveform = localApplyTimingCorrection(rxWaveform, timingResolution.AppliedCorrection_samples);

% OFDM demod
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);
if ~logical(trackingCorrection.CFOEstimateAvailable)
    cfoEstimationMethod = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.impairments.cfoEstimationMethod", "cyclic_prefix"))));
    if any(cfoEstimationMethod == ["dmrs_two_symbol", "dmrs", "reference_symbol_phase_slope"])
        [dmrsCFOHz, dmrsCFOInfo] = sixgr.phy.rx.estimateCFOFromReferenceSymbols( ...
            rxGrid, dmrsInd, dmrsSym, carrier, sampleRateHz);
        if logical(dmrsCFOInfo.EstimateAvailable)
            trackingCorrection.CFOEstimateAvailable = true;
            trackingCorrection.EstimatedCFO_Hz = double(dmrsCFOHz);
            trackingCorrection.Status = "available";
            trackingCorrection.Source = "dmrs_reference_symbol_phase_slope";
            trackingCorrection.NAReason = "";
            trackingCorrection.CFOCorrectionApplied = false;
            trackingCorrection.CFOCorrectionApplied_Hz = NaN;
        end
    end
    if ~logical(trackingCorrection.CFOEstimateAvailable) && cfoEstimationMethod ~= "dmrs_two_symbol"
        [cpCFOHz, cpCFOInfo] = sixgr.phy.rx.estimateCFOFromCyclicPrefix(rxWaveform, ofdmInfo, sampleRateHz);
        if logical(cpCFOInfo.EstimateAvailable)
            trackingCorrection.CFOEstimateAvailable = true;
            trackingCorrection.EstimatedCFO_Hz = double(cpCFOHz);
            trackingCorrection.Status = "available";
            trackingCorrection.Source = "cyclic_prefix_cfo_estimator";
            trackingCorrection.NAReason = "";
            trackingCorrection.CFOCorrectionApplied = false;
            trackingCorrection.CFOCorrectionApplied_Hz = NaN;
        end
    elseif ~logical(trackingCorrection.CFOEstimateAvailable)
        trackingCorrection.Status = "not_available";
        trackingCorrection.Source = "dmrs_reference_symbol_phase_slope";
        trackingCorrection.NAReason = "dmrs_cfo_estimate_unavailable";
    end
end
[rxGrid, ofdmInfo, trackingCorrection] = localApplyEstimatedCFOAndRedemodulate( ...
    carrier, rxWaveform, sampleRateHz, rxGrid, ofdmInfo, trackingCorrection, cfg);

% Channel estimate
Hest = [];
nVarEst = [];
estInfo = struct();
useFastChEstMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if useFastAWGNPath
    Hest = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 10^(-double(sixgr.util.structGet(cfg, 'channel.snr_dB', 20))/10);
    estInfo = struct( ...
        "EngineUsed", "unit-flat-shortcut", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true);
else
    [Hest, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym, ...
        "CDMLengths", sixgr.util.structGet(dmrsInfo, "CDMLengths", []), ...
        "UseFastMex", useFastChEstMex, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", numTxPorts, ...
        "Method", localResolveChannelEstimationMethod(cfg), ...
        "Config", cfg, ...
        "ContextLabel", "PUSCH_Rx");
end

% Noise variance
noiseCandidate = opt.NoiseVar;
noiseSource = "runtime_metadata";
if isempty(noiseCandidate)
    % nrChannelEstimate returns grid-domain noise variance.
    noiseCandidate = nVarEst;
    noiseSource = "runtime_channel_estimate";
else
    domain = lower(strtrim(char(string(opt.NoiseVarDomain))));
    if strcmp(domain, 'auto') || strcmp(domain, 'time')
        noiseCandidate = localConvertNoiseVarToGridDomain(noiseCandidate, ofdmInfo);
    end
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
[hestSymForSINR, sinrProjectionInfo] = localProjectPUSCHHestToLayerDomain(hestSym, pusch);
if ~logical(sinrProjectionInfo.Applied)
    hestSymForSINR = hestSym;
end

% Equalize
[equalizerAlg, equalizerRequested] = localResolveEqualizerAlgorithm(cfg, "UL");
if equalizerAlg == "IRC"
    [Rint, rintInfo] = sixgr.phy.rx.estimateInterferenceCovarianceIRC(rxGrid, Hest, dmrsInd, dmrsSym, nVar);
else
    Rint = [];
    rintInfo = struct("Available", false, "Source", "irc_not_requested", ...
        "Status", "not_applicable", "NAReason", "equalizer_algorithm_is_not_irc");
end
if equalizerAlg == "IRC" && ~logical(rintInfo.Available)
    equalizerAlg = "MMSE";
end
[eqSym, csi, equalizerInfo] = sixgr.phy.rx.mimoDetect(rxSym, hestSym, nVar, ...
    "Algorithm", equalizerAlg, "Rint", Rint);
[ptrsInd, ptrsSym, ptrsInfo] = localResolvePUSCHPTRS(carrier, pusch, cfg);
enablePTRSCPECorrection = logical(sixgr.util.structGet(cfg, "phy.pusch.ptrs.enableCPECorrection", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enableCPECorrection", true)));
[eqSym, cpeCorrInfo] = localCorrectEqualizedPUSCHCPEFromPTRS(eqSym, puschInd, rxGrid, Hest, ...
    ptrsInd, ptrsSym, carrier, nVar, equalizerAlg, Rint, enablePTRSCPECorrection);
try
    numLayersForSINR = double(pusch.NumLayers);
catch
    numLayersForSINR = min(size(hestSym, 2), max(1, size(hestSym, 3)));
end
try
    [postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo] = sixgr.phy.rx.computePostEqSINR( ...
        hestSymForSINR, nVar, ...
        "Method", char(lower(string(equalizerAlg))), ...
        "Rint", Rint, ...
        "Layers", double(numLayersForSINR), ...
        "MaxTrustedSINR_dB", double(sixgr.util.structGet(cfg, "phy.csi.maxTrustedReferenceSINR_dB", NaN)));
    if logical(sinrProjectionInfo.Applied)
        postEqSINRInfo.Source = "post_equalization_sinr_from_pusch_codebook_effective_channel";
    end
    postEqSINRInfo.PUSCHCodebookProjectionApplied = logical(sinrProjectionInfo.Applied);
    postEqSINRInfo.PUSCHCodebookProjectionStatus = char(string(sinrProjectionInfo.Status));
    postEqSINRInfo.PUSCHCodebookProjectionTPMI = double(sinrProjectionInfo.TPMI);
catch ME
    if strictMode
        error("sixgr:phy:ul:PUSCHPostEqSINRUnavailable", ...
            "Strict UL PUSCH requires receiver-derived post-equalization SINR; computePostEqSINR failed: %s", ...
            char(string(ME.message)));
    end
    postEqSINR_dB = NaN;
    postEqSINRPerRE_dB = [];
    postEqSINRInfo = struct( ...
        "ValueStatus", "failed", ...
        "NAReason", string(ME.identifier), ...
        "PerLayerSINR_dB", NaN, ...
        "Source", "post_equalization_sinr_from_equalizer_channel_estimate", ...
        "ValueRole", "measured_post_equalization_scheduling_input", ...
        "Method", char(lower(string(equalizerAlg))), ...
        "PUSCHCodebookProjectionApplied", logical(sinrProjectionInfo.Applied), ...
        "PUSCHCodebookProjectionStatus", char(string(sinrProjectionInfo.Status)), ...
        "PUSCHCodebookProjectionTPMI", double(sinrProjectionInfo.TPMI));
end
receiverSINR = localReceiverHestSINR(Hest, nVar, cfg, "UL", rxGrid, dmrsInd, dmrsSym);
[nVarPostEqDiagnostic, nVarPostEqInfo] = sixgr.phy.rx.postEqualizationNoiseVariance(nVar, ...
    "PostEqSINRPerRE_dB", postEqSINRPerRE_dB, ...
    "PostEqSINR_dB", postEqSINR_dB, ...
    "CSI", csi);
[nVarForDecode, nVarDecodeInfo] = localResolvePUSCHDecoderNoiseVariance(nVar, ...
    nVarPostEqDiagnostic, nVarPostEqInfo, cfg);

% Decode PUSCH to codeword LLR
puschRxSym = [];
if ~(isscalar(nVarForDecode) && isfinite(nVarForDecode) && nVarForDecode > 0)
    nVarForDecode = double(nVar);
end
nVarForDecode = double(max(nVarForDecode, eps));
try
    [cwLLR, puschRxSym] = nrPUSCHDecode(carrier, pusch, eqSym, nVarForDecode);
catch
    cwLLR = nrPUSCHDecode(carrier, pusch, eqSym, nVarForDecode);
end

if iscell(cwLLR)
    cwLLR = cwLLR{1};
end
[cwLLR, llrCSIInfo] = localApplyCSIToCodewordLLR(cwLLR, csi, pusch.Modulation, postEqSINR_dB);
expectedHARQACKBits = localNormalizeHARQACKBits(opt.ExpectedHARQACKBits);
[cwLLRForULSCH, uciOnPUSCH] = localDemultiplexHARQACKFromPUSCH( ...
    cwLLR, pusch, targetCodeRate, trBlkSize, expectedHARQACKBits);

% Rate recover (to code blocks)
[recLLR, rateRecoverInfo] = sixgr.phy.phycode.rateRecoverLDPC(cwLLRForULSCH, trBlkSize, targetCodeRate, rv, pusch.Modulation, pusch.NumLayers, ldpcSeg.NumCodeBlocks);
[recLLR, harqCombiningInfo] = sixgr.phy.harq.combineSoftLLR(recLLR, opt.HARQSoftBufferLLR);
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
B = ldpcSeg.TransportBlockLenWithCRC;
[tbCrc, cbCrcErr] = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);
[tbBits, crcOK, crcErr] = sixgr.phy.tb.checkCRC(tbCrc, tbCRCType);

% Outputs
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOK);
rx.CRCPass = logical(crcOK);
rx.TBCRCPass = logical(crcOK);
rx.TransportBlock = int8(tbBits(:));
rx.NoiseVar = nVarForDecode;
rx.NoiseVarStatus = char(string(sixgr.util.structGet(nVarDecodeInfo, "ValueStatus", noiseStatus.Status)));
rx.NoiseVarSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", noiseStatus.Source)));
rx.NoiseVarReason = char(string(sixgr.util.structGet(nVarDecodeInfo, "NAReason", noiseStatus.Reason)));
rx.NoiseVarStrictFailure = false;
rx.NoiseVarDomain = char(string(sixgr.util.structGet(nVarDecodeInfo, "Domain", "pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode")));
rx.PreEqualizationNoiseVar = double(nVar);
rx.PreEqualizationNoiseVarDomain = "resource_grid_pre_equalization";
rx.DecoderNoiseVar = double(nVarForDecode);
rx.PostEqualizationNoiseVar = double(nVarPostEqDiagnostic);
rx.DecoderNoiseVarStatus = char(string(sixgr.util.structGet(nVarDecodeInfo, "ValueStatus", "OK")));
rx.DecoderNoiseVarSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "")));
rx.DecoderNoiseVarReductionMethod = char(string(sixgr.util.structGet(nVarDecodeInfo, "ReductionMethod", "")));
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
rx.DecoderIterations = mean(double(actIter(:)), "omitnan");
rx.NumCodeBlocks = double(ldpcSeg.NumCodeBlocks);
rx.CodeBlockLength_bits = double(ldpcSeg.CodeBlockLength);
rx.TransportBlockCRCLength = double(tbCRCLen);
rx.TransportBlockLenWithCRC = double(ldpcSeg.TransportBlockLenWithCRC);
rx.LDPCRateRecoverNumCodeBlocks = double(sixgr.util.structGet(rateRecoverInfo, "numCBUsed", ldpcSeg.NumCodeBlocks));
rx.HARQSoftCombiningApplied = logical(harqCombiningInfo.Applied);
rx.HARQSoftCombiningReason = char(string(harqCombiningInfo.Reason));
rx.HARQSoftCombiningCurrentNumel = double(harqCombiningInfo.CurrentNumel);
rx.HARQSoftCombiningPriorNumel = double(harqCombiningInfo.PriorNumel);
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
rx.PostEqSINR_dB = double(postEqSINR_dB);
rx.PostEqSINRWidebanddB = double(postEqSINR_dB);
rx.PostEqSINRSource = char(string(sixgr.util.structGet(postEqSINRInfo, "Source", "post_equalization_sinr_from_equalizer_channel_estimate")));
rx.PostEqSINRValueRole = char(string(sixgr.util.structGet(postEqSINRInfo, "ValueRole", "measured_post_equalization_scheduling_input")));
rx.PostEqSINRValueStatus = char(string(sixgr.util.structGet(postEqSINRInfo, "ValueStatus", "unavailable")));
rx.PostEqSINRNAReason = char(string(sixgr.util.structGet(postEqSINRInfo, "NAReason", "")));
rx.PostEqSINRPerLayer_dB = double(sixgr.util.structGet(postEqSINRInfo, "PerLayerSINR_dB", NaN));
rx.SINRComputationMethod = char(string(sixgr.util.structGet(postEqSINRInfo, "Method", char(lower(string(equalizerAlg))))));
rx.EqualizerType = char(string(equalizerInfo.AlgorithmUsed));
rx.EqualizerRequestedType = char(equalizerRequested);
rx.EqualizerEngine = char(string(equalizerInfo.EngineUsed));
rx.InterferenceCovarianceAvailable = logical(rintInfo.Available);
rx.InterferenceCovarianceSource = char(string(rintInfo.Source));
rx.InterferenceCovarianceStatus = char(string(rintInfo.Status));
rx.ChannelEstimateAttempted = true;
rx.ChannelEstimateAvailable = ~isempty(Hest);
rx.ChannelEstimateSource = "pusch_dmrs_channel_estimate";
rx.ResourceExtractionAttempted = true;
rx.ResourceExtractionAvailable = ~isempty(rxSym);
rx.EqualizationAttempted = true;
rx.EqualizationAvailable = ~isempty(eqSym);
rx.ULSCHDecodeAttempted = true;
rx.ULSCHDecodeAvailable = ~isempty(tbBits) || ~isempty(decCbs) || ~isempty(recLLR);
rx.LLRAvailable = ~isempty(cwLLRForULSCH);
rx.LLRFinite = ~isempty(cwLLRForULSCH) && all(isfinite(double(cwLLRForULSCH(:))));
rx.LLRScaleSource = "nrPUSCHDecode_decoder_noise_variance_plus_" + string(llrCSIInfo.Source);
rx.LLRCSIWeightApplied = logical(llrCSIInfo.Applied);
rx.LLRCSIWeightStatus = char(string(llrCSIInfo.Status));
rx.LLRCSIWeightInputKind = char(string(llrCSIInfo.InputKind));
rx.LLRCSIWeightRawMedian = double(llrCSIInfo.RawCSIMedian);
rx.LLRCSIWeightMedianBeforeNormalization = double(llrCSIInfo.WeightMedianBeforeNormalization);
rx.LLRCSIWeightNormalizationScale = double(llrCSIInfo.NormalizationScale);
rx.LLRNoiseVariance = double(nVarForDecode);
rx.EqualizedSymbolsForEvidence = eqSym;
rx.PUSCHRxSymbolsForEvidence = puschRxSym;
rx.PTRSCPECorrectionEnabled = logical(cpeCorrInfo.Enabled);
rx.PTRSCPECorrectionSymbols = double(cpeCorrInfo.NumSymbolsCorrected);
rx.PTRSMeanCPE_deg = double(cpeCorrInfo.MeanCPE_deg);
rx.PTRSCPECorrectionReason = char(string(cpeCorrInfo.NAReason));
rx.RecLLR = recLLR;
rx.RateRecoveredLLR = recLLR;
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx, carrier, dmrsInd, dmrsInd, dmrsSym, dmrsInfo, ...
    cwLLRForULSCH, recLLR, recLLRBatch, rateRecoverInfo, actIter, parity, cbCrcErr, alg, useMexLDPC, crcErr);
rx.UCIOnPUSCHApplied = logical(uciOnPUSCH.Applied);
rx.UCIOnPUSCHSource = char(string(uciOnPUSCH.Source));
rx.HARQACKBitCount = double(uciOnPUSCH.HARQACKBitCount);
rx.ExpectedHARQACKBits = int8(uciOnPUSCH.ExpectedHARQACKBits(:));
rx.DecodedHARQACKBits = int8(uciOnPUSCH.DecodedHARQACKBits(:));
rx.HARQACKContentMatch = logical(uciOnPUSCH.ContentMatch);
rx.HARQACKDecodeStatus = char(string(uciOnPUSCH.Status));
rx.HARQACKDecodeReason = char(string(uciOnPUSCH.Reason));
if ~logical(opt.CompactOutput)
    rx.CodewordLLR = cwLLR;
    rx.ULSCHCodewordLLR = cwLLRForULSCH;
    rx.HARQACKLLR = uciOnPUSCH.HARQACKLLR;
    rx.DecodedCodeBlocks = decCbs;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.CodeBlockCRCError = cbCrcErr;
    rx.ChannelEstimate = Hest;
    rx.RxGrid = rxGrid;
    rx.DMRSIndices = dmrsInd;
    rx.DMRSSymbols = dmrsSym;
    rx.PTRSIndices = ptrsInd;
    rx.PTRSSymbols = ptrsSym;
    rx.PTRSInfo = ptrsInfo;
    rx.CPECorrectionInfo = cpeCorrInfo;
    rx.Carrier = carrier;
    rx.PUSCH = pusch;
    rx.PUSCHInfo = puschInfo;
    rx.EqualizedSymbols = eqSym;
    rx.PUSCHRxSymbols = puschRxSym;
    rx.CSI = csi;
    rx.EqualizerInfo = equalizerInfo;
    rx.InterferenceCovariance = Rint;
    rx.InterferenceCovarianceInfo = rintInfo;
end

strictEvidence = sixgr.phy.ul.validatePUSCHReceiverEvidence(rx, "StrictMode", strictMode);
rx.StrictReceiverEvidenceOk = logical(strictEvidence.StrictReceiverEvidenceOk);
rx.StrictOk = logical(strictEvidence.StrictOk);
rx.TruthStatus = char(string(strictEvidence.TruthStatus));
rx.SINRValidationStatus = char(string(strictEvidence.SINRValidationStatus));
rx.SINRValidationReason = char(string(strictEvidence.SINRValidationReason));
rx.PostEqSINRReceiverDerived = logical(strictEvidence.PostEqSINRReceiverDerived);
rx.PostEqSINRAvailable = logical(strictEvidence.PostEqSINRAvailable);
rx.ConfiguredSNRLikeSourceRejected = logical(strictEvidence.ConfiguredSNRLikeSourceRejected);
if strictMode && ~logical(strictEvidence.StrictReceiverEvidenceOk)
    rx.ReceiverUsable = false;
    rx.DecodeUsable = false;
    if strlength(string(rx.FailureReason)) == 0
        rx.FailureReason = char(string(strictEvidence.FailureReason));
    else
        rx.FailureReason = char(string(rx.FailureReason) + "|" + string(strictEvidence.FailureReason));
    end
end

info = struct();
info.CarrierInfo = cinfo;
info.OFDM = ofdmInfo;
info.ChannelEstimation = estInfo;
info.ReceiverTrackingCorrection = trackingCorrection;
info.NoiseVariance = noiseStatus;
info.HARQSoftCombining = harqCombiningInfo;
info.PreEqualizationNoiseVariance = double(nVar);
info.PostEqualizationNoiseVariance = nVarPostEqInfo;
info.DecoderNoiseVariance = nVarDecodeInfo;
info.TimingEstimate = timingResolution;
info.Equalizer = equalizerInfo;
info.InterferenceCovariance = rintInfo;
info.PTRS = ptrsInfo;
info.CPECorrection = cpeCorrInfo;
info.StrictReceiverEvidence = strictEvidence;

end

function method = localResolveChannelEstimationMethod(cfg)
method = char(string(sixgr.util.structGet(cfg, "phy.channelEstimation.method", ...
    sixgr.util.structGet(cfg, "phy.rx.channelEstimationMethod", "LS"))));
if isempty(strtrim(method))
    method = 'LS';
end
end

function [ptrsInd, ptrsSym, info] = localResolvePUSCHPTRS(carrier, pusch, cfg)
ptrsInd = [];
ptrsSym = [];
info = struct("Available", false, "Enabled", false, "Source", "not_requested", ...
    "NAReason", "");
enabled = logical(sixgr.util.structGet(cfg, "phy.pusch.enablePTRS", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enable", false)));
info.Enabled = enabled;
if ~enabled
    info.NAReason = "ptrs_disabled_by_config";
    return;
end
try
    ptrsInd = nrPUSCHPTRSIndices(carrier, pusch, "IndexStyle", "index");
    ptrsSym = nrPUSCHPTRS(carrier, pusch);
    info.Available = ~isempty(ptrsInd) && ~isempty(ptrsSym);
    info.Source = "nrPUSCHPTRS_runtime_symbols";
    if ~info.Available
        info.NAReason = "toolbox_returned_empty_ptrs";
    end
catch ME
    ptrsInd = [];
    ptrsSym = [];
    info.Available = false;
    info.Source = "nrPUSCHPTRS_unavailable";
    info.NAReason = string(ME.identifier);
end
end

function [eqSymOut, info] = localCorrectEqualizedPUSCHCPEFromPTRS(eqSym, puschInd, rxGrid, hEst, ...
        ptrsInd, ptrsSym, carrier, nVar, equalizerAlg, Rint, enabled)
info = struct('Enabled', false, 'NumSymbolsCorrected', 0, ...
    'MeanCPE_deg', NaN, 'NAReason', "");
eqSymOut = eqSym;
if ~logical(enabled)
    info.NAReason = "ptrs_cpe_correction_disabled_by_config";
    return;
end
if isempty(eqSym) || isempty(puschInd) || isempty(rxGrid) || isempty(hEst)
    info.NAReason = "missing_pusch_equalized_symbols_or_channel_estimate";
    return;
end
if isempty(ptrsInd) || isempty(ptrsSym)
    info.NAReason = "ptrs_unavailable";
    return;
end

try
    [rxPTRS, hPTRS] = nrExtractResources(ptrsInd, rxGrid, hEst);
catch ME
    info.NAReason = "ptrs_resource_extraction_failed:" + string(ME.identifier);
    return;
end
if isempty(rxPTRS) || isempty(hPTRS)
    info.NAReason = "ptrs_resource_extraction_empty";
    return;
end

try
    [eqPTRS, ~, ~] = sixgr.phy.rx.mimoDetect(rxPTRS, hPTRS, nVar, ...
        "Algorithm", equalizerAlg, "Rint", Rint);
catch ME
    info.NAReason = "ptrs_equalization_failed:" + string(ME.identifier);
    return;
end

refPTRS = ptrsSym(:);
eqPTRS = localSelectPTRSObservation(eqPTRS, refPTRS);
n = min(numel(eqPTRS), numel(refPTRS));
if n <= 0
    info.NAReason = "ptrs_equalized_symbol_count_mismatch";
    return;
end
eqPTRS = eqPTRS(1:n);
refPTRS = refPTRS(1:n);

dims = size(rxGrid);
if numel(dims) < 2
    info.NAReason = "rx_grid_not_resource_grid";
    return;
end
K = dims(1);
L = dims(2);
P = max(1, size(rxGrid, 3));
try
    [~, ptrsL, ~] = ind2sub([K L P], double(ptrsInd(:)));
    [~, dataL, ~] = ind2sub([K L P], double(puschInd(:)));
catch ME
    info.NAReason = "ptrs_or_pusch_symbol_index_decode_failed:" + string(ME.identifier);
    return;
end
ptrsL = ptrsL(1:min(numel(ptrsL), n));
eqPTRS = eqPTRS(1:numel(ptrsL));
refPTRS = refPTRS(1:numel(ptrsL));

valid = isfinite(real(eqPTRS)) & isfinite(imag(eqPTRS)) & ...
    isfinite(real(refPTRS)) & isfinite(imag(refPTRS)) & abs(refPTRS) > 0 & ...
    ptrsL >= 1 & ptrsL <= L;
if ~any(valid)
    info.NAReason = "no_valid_ptrs_cpe_samples";
    return;
end
eqPTRS = eqPTRS(valid);
refPTRS = refPTRS(valid);
ptrsL = ptrsL(valid);

cpeVec = NaN(L, 1);
for lSym = unique(ptrsL(:)).'
    mask = ptrsL == lSym;
    if ~any(mask)
        continue;
    end
    cpe = angle(sum(eqPTRS(mask) .* conj(refPTRS(mask)), "omitnan"));
    if isfinite(cpe)
        cpeVec(lSym) = cpe;
    end
end
finiteMask = isfinite(cpeVec);
if ~any(finiteMask)
    info.NAReason = "no_finite_ptrs_cpe_estimates";
    return;
end

cpeInterp = cpeVec;
finiteIdx = find(finiteMask);
unwrapped = unwrap(double(cpeVec(finiteMask)));
if numel(finiteIdx) == 1
    cpeInterp(:) = unwrapped(1);
else
    cpeInterp(:) = interp1(double(finiteIdx), unwrapped, (1:L).', "linear", "extrap");
end

dataL = dataL(1:min(numel(dataL), size(eqSymOut, 1)));
for row = 1:numel(dataL)
    lSym = dataL(row);
    if lSym >= 1 && lSym <= L && isfinite(cpeInterp(lSym))
        eqSymOut(row, :) = eqSymOut(row, :) .* cast(exp(-1j * cpeInterp(lSym)), "like", eqSymOut);
    end
end

info.Enabled = true;
info.NumSymbolsCorrected = double(numel(unique(dataL(dataL >= 1 & dataL <= L))));
info.MeanCPE_deg = rad2deg(mean(abs(cpeVec(finiteMask)), "omitnan"));
info.NAReason = "";
end

function obs = localSelectPTRSObservation(eqPTRS, refPTRS)
if isempty(eqPTRS)
    obs = complex(zeros(0, 1));
    return;
end
if isvector(eqPTRS)
    obs = eqPTRS(:);
    return;
end
if size(eqPTRS, 1) ~= numel(refPTRS)
    obs = eqPTRS(:);
    return;
end
refPTRS = refPTRS(:);
metric = zeros(1, size(eqPTRS, 2));
for col = 1:size(eqPTRS, 2)
    candidate = eqPTRS(:, col);
    metric(col) = abs(sum(candidate(:) .* conj(refPTRS), "omitnan"));
end
[~, bestCol] = max(metric);
if isempty(bestCol) || ~isfinite(metric(bestCol))
    bestCol = 1;
end
obs = eqPTRS(:, bestCol);
end

function [alg, requested] = localResolveEqualizerAlgorithm(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    requested = string(sixgr.util.structGet(cfg, "phy.pusch.equalizer", ...
        sixgr.util.structGet(cfg, "phy.rx.equalizer", ...
        sixgr.util.structGet(cfg, "phy.rx.algorithm", "MMSE"))));
else
    requested = string(sixgr.util.structGet(cfg, "phy.pdsch.equalizer", ...
        sixgr.util.structGet(cfg, "phy.rx.equalizer", ...
        sixgr.util.structGet(cfg, "phy.rx.algorithm", "MMSE"))));
end
requested = upper(strtrim(requested));
if strlength(requested) == 0
    requested = "MMSE";
end
if contains(requested, "IRC")
    alg = "IRC";
elseif contains(requested, "ZF")
    alg = "ZF";
else
    alg = "MMSE";
end
end

function [Rint, info] = localEstimateDMRSInterferenceCovariance(rxGrid, hEst, dmrsInd, dmrsSym, nVar)
Rint = [];
info = struct("Available", false, "Source", "dmrs_residual_covariance_unavailable", ...
    "Status", "NOT_AVAILABLE", "NumSamples", 0);
if isempty(rxGrid) || isempty(hEst) || isempty(dmrsInd) || isempty(dmrsSym)
    return;
end
try
    [rxRef, hRef] = nrExtractResources(dmrsInd, rxGrid, hEst);
catch
    info.Status = "dmrs_resource_extraction_failed";
    return;
end
if isempty(rxRef) || isempty(hRef)
    return;
end
if ndims(hRef) == 2
    hRef = reshape(hRef, size(hRef,1), size(hRef,2), 1);
end
nRE = min([size(rxRef, 1), size(hRef, 1), numel(dmrsSym)]);
if nRE < 2
    info.Status = "insufficient_dmrs_residual_samples";
    return;
end
nRx = size(rxRef, 2);
nLayer = size(hRef, 3);
residual = complex(zeros(nRE, nRx));
dmrsSym = dmrsSym(:);
for k = 1:nRE
    Hk = squeeze(hRef(k, :, :));
    if isvector(Hk)
        Hk = reshape(Hk, nRx, nLayer);
    end
    sk = repmat(dmrsSym(k), nLayer, 1);
    residual(k, :) = double(rxRef(k, :)) - (Hk * sk).';
end
residual = residual(all(isfinite(real(residual)) & isfinite(imag(residual)), 2), :);
if size(residual, 1) < 2
    info.Status = "dmrs_residual_not_finite";
    return;
end
R = (residual' * residual) ./ max(1, size(residual, 1));
R = (R + R') ./ 2;
noiseFloor = max(double(nVar), eps);
R = R + noiseFloor * eye(size(R, 1));
if any(~isfinite(R(:))) || rcond(double(R)) < 1e-12
    info.Status = "dmrs_residual_covariance_singular";
    return;
end
Rint = R;
info.Available = true;
info.Source = "dmrs_residual_interference_plus_noise_covariance";
info.Status = "OK";
info.NumSamples = double(size(residual, 1));
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

function [rxGrid, ofdmInfo, tracking] = localApplyEstimatedCFOAndRedemodulate( ...
    carrier, rxWaveform, sampleRateHz, rxGrid, ofdmInfo, tracking, cfg)
enabled = logical(sixgr.util.structGet(cfg, "phy.rx.cfoCorrectionEnabled", ...
    sixgr.util.structGet(cfg, "phy.impairments.cfoCorrectionEnabled", false)));
if ~enabled
    if logical(sixgr.util.structGet(tracking, "CFOEstimateAvailable", false))
        tracking.CFONAReason = "cfo_correction_disabled_by_config";
    end
    return;
end
if logical(sixgr.util.structGet(tracking, "CFOCorrectionApplied", false))
    return;
end
estimatedCFOHz = double(sixgr.util.structGet(tracking, "EstimatedCFO_Hz", NaN));
if ~(logical(sixgr.util.structGet(tracking, "CFOEstimateAvailable", false)) && ...
        isfinite(estimatedCFOHz) && isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
correctedWaveform = localApplyFrequencyCorrection(rxWaveform, sampleRateHz, -estimatedCFOHz);
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, correctedWaveform);
tracking.CFOCorrectionApplied = true;
tracking.CFOCorrectionApplied_Hz = estimatedCFOHz;
tracking.Status = "available_corrected";
tracking.NAReason = "";
tracking.CFONAReason = "";
end

function y = localApplyTimingCorrection(x, timingOffset)
timingOffset = double(timingOffset);
if ~isfinite(timingOffset) || abs(timingOffset) < 1e-9
    y = x;
    return;
end
y = sixgr.util.applyFractionalSampleDelay(x, -timingOffset);
end

function maxCorrection = localMaxTimingCorrectionSamples(carrier)
% nrTimingEstimate returns the absolute waveform acquisition offset. In a
% fading replay this can include channel-object filter/group delay, so the
% data receiver must not clamp the applied shift to one CP length.
maxCorrection = inf;
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
    sinr = double(sixgr.util.structGet(ulMetric, "PilotSINR_dB", ...
        sixgr.util.structGet(ulMetric, "SINR_dB", NaN)));
    if isfinite(sinr)
        evidence.Value = sinr;
        evidence.Source = char(string(sixgr.util.structGet(ulMetric, "PilotSINRSource", "receiver_hest_reference_signal_measurement")));
        evidence.ValueRole = "estimated";
        evidence.ValueStatus = char(string(sixgr.util.structGet(ulMetric, "PilotSINRValueStatus", "OK")));
        evidence.NAReason = "";
    else
        evidence.Source = char(string(sixgr.util.structGet(ulMetric, "PilotSINRSource", ...
            sixgr.util.structGet(ulMetric, "SINRSource", evidence.Source))));
        evidence.ValueRole = char(string(sixgr.util.structGet(ulMetric, "PilotSINRValueRole", ...
            sixgr.util.structGet(ulMetric, "SINRValueRole", evidence.ValueRole))));
        evidence.ValueStatus = char(string(sixgr.util.structGet(ulMetric, "PilotSINRValueStatus", ...
            sixgr.util.structGet(ulMetric, "SINRValueStatus", evidence.ValueStatus))));
        evidence.NAReason = char(string(sixgr.util.structGet(ulMetric, "PilotSINRNAReason", ...
            sixgr.util.structGet(ulMetric, "SINRNAReason", evidence.NAReason))));
    end
catch ME
    evidence.NAReason = "ul_receiver_measurement_failed:" + string(ME.identifier);
end
end

function [Hlayer, info] = localProjectPUSCHHestToLayerDomain(Hport, pusch)
info = localPUSCHProjectionInfo("not_applicable");
Hlayer = Hport;
if isempty(Hport) || ndims(Hport) ~= 3 || isempty(pusch)
    info.Status = "unsupported_hest_shape_or_missing_pusch";
    return;
end

nLayers = localObjectFiniteScalar(pusch, "NumLayers", NaN);
nPorts = localObjectFiniteScalar(pusch, "NumAntennaPorts", size(Hport, 3));
tpmi = localObjectFiniteScalar(pusch, "TPMI", NaN);
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", ""))));
if ~(isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
if ~(isfinite(nPorts) && nPorts >= 1)
    nPorts = size(Hport, 3);
end
nLayers = max(1, round(double(nLayers)));
nPorts = max(1, round(double(nPorts)));
info.NumLayers = double(nLayers);
info.NumPorts = double(nPorts);
info.TPMI = double(tpmi);
if scheme ~= "codebook" || transformPrecoding || ~isfinite(tpmi) || size(Hport, 3) <= nLayers
    return;
end

[Wlayer, codebookStatus] = localPUSCHCodebookProjectionMatrix(nLayers, nPorts, tpmi);
if isempty(Wlayer)
    info.Status = codebookStatus;
    return;
end
if size(Wlayer, 1) ~= size(Hport, 3) || size(Wlayer, 2) ~= nLayers
    info.Status = "codebook_matrix_shape_mismatch";
    return;
end

nRE = size(Hport, 1);
nRx = size(Hport, 2);
Hlayer = zeros(nRE, nRx, nLayers, "like", Hport);
for k = 1:nRE
    Hk = squeeze(Hport(k, :, :));
    if isvector(Hk)
        Hk = reshape(Hk, nRx, size(Hport, 3));
    end
    Hlayer(k, :, :) = Hk * cast(Wlayer, "like", Hport);
end
info.Applied = true;
info.Status = codebookStatus + "_projected_to_effective_layer_channel";
end

function info = localPUSCHProjectionInfo(status)
info = struct( ...
    "Applied", false, ...
    "Status", char(string(status)), ...
    "TPMI", NaN, ...
    "NumPorts", NaN, ...
    "NumLayers", NaN);
end

function [nVarForDecode, info] = localResolvePUSCHDecoderNoiseVariance(nVarPreEq, nVarPostEq, postInfo, cfg)
% Keep nrPUSCHDecode aligned with the 5G Toolbox receiver chain: the
% demapper receives the channel-estimator noise variance, while per-RE CSI
% weights carry reliability variation after equalization.
pre = double(localScalarOrNaN(nVarPreEq));
post = double(localScalarOrNaN(nVarPostEq));
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.decoderNoiseVarianceSource", ...
    sixgr.util.structGet(cfg, "phy.rx.puschDecoderNoiseVarianceSource", "pre_equalization")))));
if strlength(mode) == 0
    mode = "pre_equalization";
end

postSource = char(string(sixgr.util.structGet(postInfo, "Source", "")));
postMethod = char(string(sixgr.util.structGet(postInfo, "ReductionMethod", "")));
postSampleCount = double(sixgr.util.structGet(postInfo, "SampleCount", 0));
info = struct( ...
    "ValueStatus", "unavailable", ...
    "Source", "pusch_decoder_noise_variance_unavailable", ...
    "ValueRole", "pusch_decoder_llr_noise_variance", ...
    "NAReason", "invalid_noise_variance", ...
    "PreEqualizationNoiseVar", double(pre), ...
    "PostEqualizationNoiseVar", double(post), ...
    "ReductionMethod", "", ...
    "SampleCount", 0, ...
    "ConfiguredMode", char(mode), ...
    "PostEqualizationDiagnosticSource", postSource, ...
    "PostEqualizationDiagnosticReductionMethod", postMethod, ...
    "PostEqualizationDiagnosticSampleCount", double(postSampleCount), ...
    "Domain", "pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode");

usePost = any(mode == ["post_equalization", "post_equalization_sinr", "posteq", "legacy_post_equalization"]);
if usePost && localValidNoiseScalar(post)
    nVarForDecode = double(post);
    info.ValueStatus = "OK";
    info.Source = "post_equalization_sinr_decoder_noise_variance_configured";
    info.NAReason = "";
    info.ReductionMethod = postMethod;
    info.SampleCount = double(max(postSampleCount, 1));
    info.Domain = "post_equalization_decoder_symbol_domain";
    return;
end

if localValidNoiseScalar(pre)
    nVarForDecode = double(pre);
    info.ValueStatus = "OK";
    info.Source = "pre_equalization_channel_estimator_noise_variance";
    info.NAReason = "";
    info.ReductionMethod = "identity_pre_equalization_noise_variance";
    info.SampleCount = 1;
    return;
end

if localValidNoiseScalar(post)
    nVarForDecode = double(post);
    info.ValueStatus = "OK";
    info.Source = "post_equalization_sinr_decoder_noise_variance_pre_equalization_unavailable";
    info.NAReason = "";
    info.ReductionMethod = postMethod;
    info.SampleCount = double(max(postSampleCount, 1));
    info.Domain = "post_equalization_decoder_symbol_domain";
    return;
end

nVarForDecode = double(max(eps, realmin));
end

function tf = localValidNoiseScalar(value)
value = double(value);
tf = isscalar(value) && isfinite(value) && value > 0;
end

function [Wlayer, status] = localPUSCHCodebookProjectionMatrix(nLayers, nPorts, tpmi)
% NR PUSCH codebook projection for the currently exercised uplink path.
% TS 38.214 defines the two-port, one-layer TPMI entries used by this
% scenario; leave other cases unsupported rather than inventing evidence.
Wlayer = [];
status = "unsupported_pusch_codebook_configuration";
nLayers = round(double(nLayers));
nPorts = round(double(nPorts));
tpmi = round(double(tpmi));
if ~(isfinite(nLayers) && isfinite(nPorts) && isfinite(tpmi))
    status = "invalid_pusch_codebook_parameters";
    return;
end
if nLayers ~= 1 || nPorts ~= 2
    status = sprintf("unsupported_pusch_codebook_%dports_%dlayers", nPorts, nLayers);
    return;
end

switch tpmi
    case 0
        Wlayer = [1; 0];
    case 1
        Wlayer = [0; 1];
    case 2
        Wlayer = [1; 1] ./ sqrt(2);
    case 3
        Wlayer = [1; -1] ./ sqrt(2);
    case 4
        Wlayer = [1; 1i] ./ sqrt(2);
    case 5
        Wlayer = [1; -1i] ./ sqrt(2);
    otherwise
        status = sprintf("unsupported_pusch_2port_1layer_tpmi_%d", tpmi);
        return;
end
status = "nr_pusch_2port_1layer_codebook";
end

function value = localObjectFiniteScalar(obj, propName, defaultValue)
raw = localObjectValue(obj, propName, defaultValue);
if isnumeric(raw) || islogical(raw)
    value = double(raw);
elseif isstring(raw) || ischar(raw)
    value = str2double(string(raw));
else
    value = double(defaultValue);
end
if numel(value) > 1
    value = value(1);
end
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = double(defaultValue);
end
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    if isobject(obj) && isprop(obj, char(propName))
        raw = obj.(char(propName));
    elseif isstruct(obj) && isfield(obj, char(propName))
        raw = obj.(char(propName));
    else
        return;
    end
catch
    return;
end
if ~isempty(raw)
    value = raw;
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

function seg = localResolveExpectedLDPCSegmentation(trBlkSize, bgn, tbCRCType)
% Mirror the Tx-side TB CRC + 38.212 code-block segmentation to recover C.
trBlkSize = double(trBlkSize);
bgn = double(bgn);
if ~(isscalar(trBlkSize) && isfinite(trBlkSize) && trBlkSize > 0)
    error("sixgr:phy:ul:PUSCHInvalidTBSForLDPC", ...
        "PUSCH_Rx cannot resolve LDPC segmentation for invalid TBS %.6g.", trBlkSize);
end
if ~(isscalar(bgn) && isfinite(bgn) && any(round(bgn) == [1 2]))
    error("sixgr:phy:ul:PUSCHInvalidBaseGraphForLDPC", ...
        "PUSCH_Rx cannot resolve LDPC segmentation for base graph %.6g.", bgn);
end
tb = zeros(round(trBlkSize), 1, 'int8');
tbCrc = sixgr.phy.tb.attachCRC(tb, tbCRCType);
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, round(bgn));
seg = struct( ...
    "TransportBlockLenWithCRC", double(numel(tbCrc)), ...
    "NumCodeBlocks", double(size(cbs, 2)), ...
    "CodeBlockLength", double(size(cbs, 1)), ...
    "SegmentationInfo", segInfo);
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

function pusch = localEnsureTransformPrecodingOwnership(pusch, cfg)
try
    modToken = upper(strrep(char(string(pusch.Modulation)), ' ', ''));
catch
    modToken = upper(strrep(char(string(sixgr.util.structGet(cfg, 'phy.pusch.modulation', ''))), ' ', ''));
end
required = strcmp(modToken, 'PI/2-BPSK') || strcmp(modToken, 'PI2-BPSK') || ...
    logical(sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', false));
if required
    try
        pusch.TransformPrecoding = true;
    catch ME
        error('sixgr:phy:ul:PUSCHTransformPrecodingUnavailable', ...
            'PUSCH requires TransformPrecoding=true for modulation/config but nrPUSCHConfig rejected it: %s', ME.message);
    end
end
end

function xOverhead = localResolvePUSCHXOverhead(pusch, cfg)
xOverhead = double(sixgr.util.structGet(cfg, 'phy.pusch.xOverhead', ...
    sixgr.util.structGet(cfg, 'phy.pusch.XOverhead', 0)));
try
    tpEnabled = logical(pusch.TransformPrecoding);
catch
    tpEnabled = false;
end
try
    modToken = upper(strrep(char(string(pusch.Modulation)), ' ', ''));
catch
    modToken = "";
end
if tpEnabled || strcmp(modToken, 'PI/2-BPSK') || strcmp(modToken, 'PI2-BPSK')
    xOverhead = max(double(xOverhead), 6);
end
xOverhead = max(0, round(double(xOverhead)));
end

function nrePerPRB = localResolvePUSCHNREPerPRBOrError(carrier, pusch, puschInfo, nPRB)
nrePerPRB = localResolveNREFromInfo(puschInfo, nPRB, pusch.Modulation, pusch.NumLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    try
        [~, puschInfoFull] = nrPUSCHIndices(carrier, pusch);
        nrePerPRB = localResolveNREFromInfo(puschInfoFull, nPRB, pusch.Modulation, pusch.NumLayers);
    catch
    end
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error('sixgr:phy:ul:PUSCHRx:CannotResolveTBS', ...
        ['Cannot determine nrePerPRB for TBS calculation. Provide TransportBlockSize explicitly. ' ...
         'PRBSet=%s, SymbolAllocation=%s, Modulation=%s, NumLayers=%d.'], ...
        mat2str(double(pusch.PRBSet)), mat2str(localSymAlloc(pusch)), ...
        char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
end
end

function nrePerPRB = localResolveNREFromInfo(info, nPRB, modStr, nLayers)
nrePerPRB = NaN;
if isempty(info) || ~isstruct(info)
    return;
end
if isfield(info, 'NREPerPRB')
    nrePerPRB = double(info.NREPerPRB);
elseif isfield(info, 'NRE')
    nrePerPRB = floor(double(info.NRE) / max(double(nPRB), 1));
elseif isfield(info, 'G')
    qm = localQm(modStr);
    nrePerPRB = floor(double(info.G) / max(double(qm) * double(nLayers) * max(double(nPRB), 1), 1));
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = NaN;
end
end

function sa = localSymAlloc(pusch)
try
    sa = double(pusch.SymbolAllocation);
catch
    sa = [0 14];
end
if numel(sa) < 2
    sa = [0 14];
else
    sa = reshape(sa(1:2), 1, 2);
end
end

function bits = localNormalizeHARQACKBits(rawBits)
if isempty(rawBits)
    bits = int8([]);
    return;
end
bits = int8(logical(rawBits(:)));
end

function [ulschLLR, info] = localDemultiplexHARQACKFromPUSCH(cwLLR, pusch, targetCodeRate, trBlkSize, expectedBits)
ulschLLR = double(cwLLR(:));
expectedBits = localNormalizeHARQACKBits(expectedBits);
oack = numel(expectedBits);
info = struct( ...
    "Applied", false, ...
    "Source", "no_harq_ack_payload_expected", ...
    "HARQACKBitCount", double(oack), ...
    "ExpectedHARQACKBits", expectedBits, ...
    "DecodedHARQACKBits", int8([]), ...
    "HARQACKLLR", double([]), ...
    "ContentMatch", false, ...
    "Status", "not_requested", ...
    "Reason", "");
if oack <= 0
    return;
end
if exist("nrULSCHDemultiplex", "file") ~= 2 || exist("nrUCIDecode", "file") ~= 2
    info.Status = "unavailable";
    info.Reason = "nrULSCHDemultiplex_or_nrUCIDecode_unavailable";
    return;
end
try
    [ulschLLR, ackLLR] = nrULSCHDemultiplex( ...
        pusch, targetCodeRate, trBlkSize, oack, 0, 0, double(cwLLR(:)));
    decoded = int8(logical(nrUCIDecode(ackLLR, oack)));
    info.Applied = true;
    info.Source = "nrULSCHDemultiplex_ts38212_6_2_7_harq_ack_on_pusch";
    info.DecodedHARQACKBits = decoded(:);
    info.HARQACKLLR = double(ackLLR(:));
    info.ContentMatch = numel(decoded) == oack && isequal(decoded(:), expectedBits(:));
    if info.ContentMatch
        info.Status = "decoded_match";
    else
        info.Status = "decoded_mismatch";
    end
catch ME
    ulschLLR = double(cwLLR(:));
    info.Status = "failed";
    info.Reason = char(string(ME.identifier));
end
end

function [llrOut, info] = localApplyCSIToCodewordLLR(llrIn, csi, modScheme, postEqSINR_dB)
[llrOut, info] = sixgr.phy.rx.applyCSIToCodewordLLR(llrIn, csi, modScheme, ...
    "PostEqSINR_dB", postEqSINR_dB);
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
rx.PostEqSINR_dB = NaN;
rx.PostEqSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
rx.PostEqSINRValueRole = "measured_post_equalization_scheduling_input";
rx.PostEqSINRValueStatus = "unavailable";
rx.PostEqSINRNAReason = char(string(noiseStatus.Reason));
rx.PostEqSINRPerLayer_dB = NaN;
rx.PostEqSINRWidebanddB = NaN;
rx.SINRComputationMethod = "unavailable_noise_variance";
rx.ChannelEstimateAttempted = ~isempty(Hest);
rx.ChannelEstimateAvailable = ~isempty(Hest);
rx.ChannelEstimateSource = "pusch_dmrs_channel_estimate_before_noise_gate";
rx.ResourceExtractionAttempted = false;
rx.ResourceExtractionAvailable = false;
rx.EqualizationAttempted = false;
rx.EqualizationAvailable = false;
rx.ULSCHDecodeAttempted = false;
rx.ULSCHDecodeAvailable = false;
rx.LLRAvailable = false;
rx.LLRFinite = false;
rx.LLRScaleSource = "";
rx.LLRNoiseVariance = NaN;
rx.EqualizedSymbolsForEvidence = complex([]);
rx.PUSCHRxSymbolsForEvidence = complex([]);
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx, carrier, dmrsInd, dmrsInd, dmrsSym, struct(), ...
    [], [], [], struct(), [], [], [], "", false);
strictEvidence = sixgr.phy.ul.validatePUSCHReceiverEvidence(rx, "StrictMode", logical(noiseStatus.StrictFailure));
rx.StrictReceiverEvidenceOk = logical(strictEvidence.StrictReceiverEvidenceOk);
rx.StrictOk = logical(strictEvidence.StrictOk);
rx.TruthStatus = char(string(strictEvidence.TruthStatus));
rx.SINRValidationStatus = char(string(strictEvidence.SINRValidationStatus));
rx.SINRValidationReason = char(string(strictEvidence.SINRValidationReason));
rx.PostEqSINRReceiverDerived = logical(strictEvidence.PostEqSINRReceiverDerived);
rx.PostEqSINRAvailable = logical(strictEvidence.PostEqSINRAvailable);
rx.ConfiguredSNRLikeSourceRejected = logical(strictEvidence.ConfiguredSNRLikeSourceRejected);
if ~compactOutput
    rx.CodewordLLR = double([]);
    rx.ULSCHCodewordLLR = double([]);
    rx.HARQACKLLR = double([]);
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
info.StrictReceiverEvidence = strictEvidence;
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

function value = localScalarOrNaN(raw)
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw)
    value = NaN;
else
    value = double(raw(1));
end
end
