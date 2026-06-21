function [rx, info] = PDSCH_Rx(rxWaveform, cfg, varargin)
%PDSCH_Rx Recover a basic PDSCH transmission (OFDM -> PDSCH -> DL-SCH).
%
%   [RX,INFO] = sixgr.phy.dl.PDSCH_Rx(RXWAVEFORM, CFG) performs
%   DMRS-aided timing, OFDM demodulation, channel estimation,
%   MMSE equalization, nrPDSCHDecode demodulation, LDPC rate recovery,
%   LDPC decoding, and transport block CRC checking.
%
%   Name-Value options:
%     "Carrier"     : nrCarrierConfig override
%     "PDSCH"       : nrPDSCHConfig override
%     "PDSCHIndices": mapping indices override
%     "TransportBlockSize": expected TB size (bits)
%     "TargetCodeRate": code rate (0..1)
%     "RV"          : redundancy version (0..3)
%     "NoiseVar"    : noise variance (if known)
%     "NoiseVarDomain": "time", "grid", "frequency", or "auto"
%     "MaxIterations": LDPC iterations (default from cfg)
%     "Algorithm"   : LDPC algorithm ("Normalized min-sum" by default)
%     "PrecodingMatrix": wideband PDSCH precoder used by the transmitter
%
%   Outputs:
%     RX.TransportBlock     : recovered TB bits (if CRC passes)
%     RX.CRCError           : true if TB CRC fails
%     RX.Ok                 : ~CRCError
%     RX.CodewordLLR        : soft bits before rate recovery
%     RX.ChannelEstimate    : H estimate
%     RX.NoiseVar           : used noise variance
%     RX.TimingOffset       : raw estimated timing offset (samples)
%     RX.AppliedTimingCorrection_samples : applied waveform correction (samples)
%
%   Notes:
%     This receiver assumes a single codeword and (by default) uses the same
%     PDSCH allocation and explicit wideband precoder as the transmitter.

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCHIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSSymbols', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSInfo', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('CSIRSTransmitted', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('TransportBlockSize', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('HARQSoftBufferLLR', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ReceiverTrackingState', [], @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;
localGuardUnsupportedNumLayers(cfg, opt.PDSCH);
profScope = sixgr.perf.TimeProfiler.scope("sixgr.phy.dl.PDSCH_Rx", ...
    "Stage", "dl_pdsch_rx", ...
    "Metadata", struct( ...
    "NSamples", double(numel(rxWaveform)), ...
    "NSubcarriers", double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)) * 12, ...
    "NSymbols", 14, ...
    "NRx", double(max(1, size(rxWaveform, 2))), ...
    "NTx", double(sixgr.util.structGet(cfg, "channel.nTxAnt", 1)), ...
    "NLayers", double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)), ...
    "TBSBits", double(localScalarOrNaN(opt.TransportBlockSize)), ...
    "MaxIterations", double(localScalarOrNaN(opt.MaxIterations)))); %#ok<NASGU>

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% PDSCH config and indices
if isempty(opt.PDSCH)
    [pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg);
else
    pdsch = opt.PDSCH;
    if isempty(opt.PDSCHIndices)
        try
            [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
        catch
            [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
        end
    else
        pdschInd = opt.PDSCHIndices;
        try
            [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
        catch
            [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
        end
    end
end

% Parameters
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pdsch.rv', 0));
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pdsch.codeRate', 0.4785));
end

maxIter = opt.MaxIterations;
if isempty(maxIter)
    maxIter = sixgr.phy.phycode.resolveLDPCMaxIterations(cfg, "Direction", "DL");
end

alg = opt.Algorithm;
if isempty(alg)
    alg = string(sixgr.util.structGet(cfg, 'phy.ldpc.algorithm', "Normalized min-sum"));
else
    alg = string(alg);
end

prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg, ...
    "PrecodingMatrix", opt.PrecodingMatrix);

% Expected TB size
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, localObjectValue(pdsch, "SymbolAllocation", [0 14]));
    nPRB = numel(pdsch.PRBSet);
    nrePerPRB = localResolvePDSCHNREPerPRBOrError(carrier, pdsch, pdschInfo, nPRB);
    trBlkSize = nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
end
trBlkSize = double(trBlkSize);

% Base graph
tbCRCType = '24A';
tbCRCLen = 24;
try
    dlschInfo = nrDLSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(dlschInfo.BGN);
    [tbCRCType, tbCRCLen] = localResolveTBCRCSpec(dlschInfo, tbCRCType, tbCRCLen);
catch
    bgn = 2;
end
ldpcSeg = localResolveExpectedLDPCSegmentation(trBlkSize, bgn, tbCRCType);

% DMRS
[dmrsInd, dmrsSym, dmrsInfo] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);
useFastAWGNPath = logical(opt.FastAWGNPath);
strictMode = logical(sixgr.util.structGet(cfg, 'run.strictMode', false));
channelModelToken = localResolveEstimatorChannelModel(cfg);
numTxPorts = localExpectedTxPorts(pdsch, prec);
localValidateFastScalarShortcut(channelModelToken, numTxPorts, max(1, size(rxWaveform, 2)), useFastAWGNPath, "PDSCH_Rx");

pdschAntInd = pdschInd;
dmrsAntInd = dmrsInd;
dmrsAntSym = dmrsSym;
if prec.Active
    pdschAntInd = localPrecodeIndices(carrier, pdschInd, prec.MatrixNR);
    [dmrsAntSym, dmrsAntInd] = nrPDSCHPrecode(carrier, dmrsSym, dmrsInd, prec.MatrixNR);
end

% ---------------------- Timing estimate ----------------------
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
elseif ~useFastAWGNPath && ~logical(opt.SkipTimingEstimate) && ~isempty(dmrsInd)
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

% Apply timing correction
rxWave = localApplyTimingCorrection(rxWaveform, timingResolution.AppliedCorrection_samples);

% ---------------------- OFDM demodulate ----------------------
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWave);
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
        [cpCFOHz, cpCFOInfo] = sixgr.phy.rx.estimateCFOFromCyclicPrefix(rxWave, ofdmInfo, sampleRateHz);
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
    carrier, rxWave, sampleRateHz, rxGrid, ofdmInfo, trackingCorrection, cfg);
[ptrsInd, ptrsSym, ptrsInfo] = localResolvePDSCHPTRS(carrier, pdsch, cfg);
ptrsAntInd = ptrsInd;
ptrsAntSym = ptrsSym;
if prec.Active && ~isempty(ptrsInd)
    try
        [ptrsAntSym, ptrsAntInd] = nrPDSCHPrecode(carrier, ptrsSym, ptrsInd, prec.MatrixNR);
    catch ME
        ptrsAntInd = [];
        ptrsAntSym = [];
        ptrsInfo.Available = false;
        ptrsInfo.Source = "nrPDSCHPTRS_precode_failed";
        ptrsInfo.NAReason = string(ME.identifier);
    end
end
cpeCorrInfo = struct('Enabled', false, 'NumSymbolsCorrected', 0, ...
    'MeanCPE_deg', NaN, 'NAReason', "ptrs_cpe_correction_deferred_until_equalization");
enablePTRSCPECorrection = logical(sixgr.util.structGet(cfg, "phy.pdsch.ptrs.enableCPECorrection", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enableCPECorrection", true)));
[csirsInd, csirsSym, csirsInfo, csirsObservation] = localObserveCSIRSRuntimeResource(carrier, cfg, rxGrid, opt);
[csirsHest, csirsNVar, csirsEstInfo] = localEstimateCSIRSChannelForPMI(carrier, rxGrid, csirsInd, csirsSym, csirsInfo, cfg, ...
    strictMode, channelModelToken, numTxPorts);
if ~isempty(csirsHest)
    csirsObservation.Consumed = true;
    csirsObservation.Consumer = "CSI_PMI_CRI_beam_metrics";
    csirsObservation.UpdateOutcome = "observed_and_channel_estimated_after_ofdm_demodulation";
elseif logical(sixgr.util.structGet(csirsObservation, "Observed", false))
    csirsObservation.UpdateOutcome = "observed_but_channel_estimate_unavailable";
end

% ---------------------- Channel estimate ----------------------
estInfo = struct();
useFastChEstMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if useFastAWGNPath
    hEst = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 10^(-double(sixgr.util.structGet(cfg, 'channel.snr_dB', 20))/10);
    estInfo = struct( ...
        "EngineUsed", "unit-flat-shortcut", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true);
elseif ~isempty(dmrsInd)
    % Estimate the effective PDSCH layer channel from the DM-RS port
    % resources. Precoding is transparent to the UE and is included in this
    % effective channel rather than exposed as antenna-domain references.
    [hEst, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym, ...
        "CDMLengths", sixgr.util.structGet(dmrsInfo, "CDMLengths", []), ...
        "UseFastMex", useFastChEstMex, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", numTxPorts, ...
        "Method", localResolveChannelEstimationMethod(cfg), ...
        "Config", cfg, ...
        "ContextLabel", "PDSCH_Rx");
else
    localValidateNoDMRSUnitChannelFallback(channelModelToken, numTxPorts, max(1, size(rxGrid, 3)), "PDSCH_Rx");
    hEst = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 0;
    estInfo = struct( ...
        "EngineUsed", "unit-channel-no-dmrs", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true);
end

noiseCandidate = opt.NoiseVar;
if isempty(noiseCandidate)
    % nrChannelEstimate returns grid-domain noise variance.
    noiseCandidate = nVarEst;
else
    domain = lower(strtrim(char(string(opt.NoiseVarDomain))));
    if strcmp(domain, 'auto') || strcmp(domain, 'time')
        noiseCandidate = localConvertNoiseVarToGridDomain(noiseCandidate, ofdmInfo);
    end
end
nVar = noiseCandidate;
nVar = double(max(0, nVar));

% ---------------------- Extract and equalize PDSCH REs ----------------------
[rxSym, hestSym] = nrExtractResources(pdschInd, rxGrid, hEst);
[equalizerAlg, equalizerRequested] = localResolveEqualizerAlgorithm(cfg, "DL");
if equalizerAlg == "IRC"
    [Rint, rintInfo] = sixgr.phy.rx.estimateInterferenceCovarianceIRC(rxGrid, hEst, dmrsInd, dmrsSym, nVar);
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
[eqSym, cpeCorrInfo] = localCorrectEqualizedPDSCHCPEFromPTRS(eqSym, pdschInd, rxGrid, hEst, ...
    ptrsInd, ptrsSym, carrier, nVar, equalizerAlg, Rint, enablePTRSCPECorrection);
try
    [postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo] = sixgr.phy.rx.computePostEqSINR( ...
        hestSym, nVar, ...
        "Method", char(lower(string(equalizerAlg))), ...
        "Rint", Rint, ...
        "Layers", double(localObjectValue(pdsch, "NumLayers", min(size(hestSym, 2), max(1, size(hestSym, 3))))), ...
        "MaxTrustedSINR_dB", double(sixgr.util.structGet(cfg, "phy.csi.maxTrustedReferenceSINR_dB", NaN)));
catch ME
    postEqSINR_dB = NaN;
    postEqSINRPerRE_dB = [];
    postEqSINRInfo = struct( ...
        "ValueStatus", "failed", ...
        "NAReason", string(ME.identifier), ...
        "PerLayerSINR_dB", NaN, ...
        "Source", "post_equalization_sinr_from_equalizer_channel_estimate", ...
        "ValueRole", "measured_post_equalization_scheduling_input");
end
receiverSINR = localReceiverHestSINR(hEst, nVar, cfg, "DL", rxGrid, dmrsInd, dmrsSym);
[nVarDecode, nVarDecodeInfo] = sixgr.phy.rx.postEqualizationNoiseVariance(nVar, ...
    "PostEqSINRPerRE_dB", postEqSINRPerRE_dB, ...
    "PostEqSINR_dB", postEqSINR_dB, ...
    "CSI", csi);
% ---------------------- PDSCH demodulate to soft bits ----------------------
% nrPDSCHDecode returns a cell array (one per codeword). Newer releases can
% also return the sliced symbol estimates used during demodulation.
pdschRxSym = [];
nVarForDecode = double(nVarDecode);
if ~(isscalar(nVarForDecode) && isfinite(nVarForDecode) && nVarForDecode > 0)
    nVarForDecode = double(nVar);
end
nVarForDecode = double(max(nVarForDecode, eps));
try
    [llrCW, pdschRxSym] = nrPDSCHDecode(carrier, pdsch, eqSym, nVarForDecode);
catch
    llrCW = nrPDSCHDecode(carrier, pdsch, eqSym, nVarForDecode);
end
if iscell(llrCW)
    llr = llrCW{1};
else
    llr = llrCW;
end
[llr, llrCSIInfo] = localApplyCSIToCodewordLLR(llr, csi, pdsch.Modulation, postEqSINR_dB);

% ---------------------- DL-SCH decode (rate recovery + LDPC decode) ----------------------
[recLLR, rateRecoverInfo] = sixgr.phy.phycode.rateRecoverLDPC(llr, trBlkSize, targetCodeRate, rv, pdsch.Modulation, pdsch.NumLayers, ldpcSeg.NumCodeBlocks);
[recLLR, harqCombiningInfo] = sixgr.phy.harq.combineSoftLLR(recLLR, opt.HARQSoftBufferLLR);
recLLRBatch = localEnsureLLRBatch(recLLR);

% LDPC decode each code block
C = size(recLLRBatch, 2);
actIter = NaN(1, C);
parity = NaN(1, C);
decodeTic = tic;
useMexLDPC = logical(sixgr.util.structGet(cfg, 'phy.ldpc.useMexBatchDecode', false)) ...
    && (exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3 || exist("sixgr_ldpc_decode_batch_kernel","file") == 2);

if useMexLDPC
    useNormMinSum = uint8(strcmpi(char(alg), 'Normalized min-sum'));
    try
        if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
            try
                [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
            catch
                [decMat, decLen] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
                actIterV = NaN(C, 1);
                parityV = NaN(C, 1);
            end
        else
            try
                [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
            catch
                [decMat, decLen] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
                actIterV = NaN(C, 1);
                parityV = NaN(C, 1);
            end
        end
        maxLen = max(1, min(size(decMat,1), round(max(decLen(:)))));
        decCbs = int8(decMat(1:maxLen, :));
        actIter = reshape(double(actIterV(:)), 1, []);
        parity = reshape(double(parityV(:)), 1, []);
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
        itV = NaN(C,1);
        pcV = NaN(C,1);
        parfor c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            dCell{c} = d;
            dLen(c) = min(numel(d), nRow);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = NaN; end
            if isempty(pc), pc = NaN; end
            itV(c) = double(it(1));
            pcV(c) = double(pc(1));
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
            if isempty(it), it = NaN; end
            if isempty(pc), pc = NaN; end
            actIter(c) = double(it(1));
            parity(c) = double(pc(1));
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

% Desegment to TB+CRC using the exact segmentation implied by this TBS.
B = ldpcSeg.TransportBlockLenWithCRC;
[tbCrcRx, cbCrcErr] = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);

% CRC check must match the transmitter's TB CRC type for this TBS.
[tbRx, crcOk, crcErr] = sixgr.phy.tb.checkCRC(tbCrcRx, tbCRCType);

% ---------------------- Outputs ----------------------
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOk);
rx.CRCPass = logical(crcOk);
rx.TBCRCPass = logical(crcOk);
rx.TransportBlock = int8(tbRx(:));
rx.TimingOffset = double(timingResolution.RawEstimate_samples);
rx.RawTimingEstimate_samples = double(timingResolution.RawEstimate_samples);
rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
rx.TimingEstimateUsed = logical(timingResolution.EstimateUsed);
rx.TimingEstimateSource = char(timingEstimateSource);
rx.TimingEstimateStatus = char(string(timingResolution.Status));
rx.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
rx.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
rx.NoiseVar = nVarForDecode;
rx.NoiseVarStatus = "OK";
rx.NoiseVarSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "post_equalization_decoder_noise_variance")));
rx.NoiseVarReason = "";
rx.NoiseVarStrictFailure = false;
rx.NoiseVarDomain = "post_equalization_decoder_symbol_domain";
rx.PreEqualizationNoiseVar = double(nVar);
rx.PreEqualizationNoiseVarDomain = "resource_grid_pre_equalization";
rx.DecoderNoiseVar = double(nVarForDecode);
rx.PostEqualizationNoiseVar = double(nVarDecode);
rx.DecoderNoiseVarStatus = char(string(sixgr.util.structGet(nVarDecodeInfo, "ValueStatus", "OK")));
rx.DecoderNoiseVarSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "")));
rx.DecoderNoiseVarReductionMethod = char(string(sixgr.util.structGet(nVarDecodeInfo, "ReductionMethod", "")));
rx.ReceiverUsable = true;
rx.DecodeAttempted = true;
rx.DecodeUsable = true;
rx.FailureReason = "";
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
rx.XOverhead = double(sixgr.phy.dl.resolvePDSCHXOverhead(cfg, localObjectValue(pdsch, "SymbolAllocation", [0 14])));
rx.CFOEstimateAvailable = logical(trackingCorrection.CFOEstimateAvailable);
rx.EstimatedCFO_Hz = double(trackingCorrection.EstimatedCFO_Hz);
rx.CFOCorrectionApplied = logical(trackingCorrection.CFOCorrectionApplied);
rx.CFOCorrectionApplied_Hz = double(trackingCorrection.CFOCorrectionApplied_Hz);
rx.CPECorrectionApplied = logical(cpeCorrInfo.Enabled);
rx.CPECorrectedSymbols = double(sixgr.util.structGet(cpeCorrInfo, "NumSymbolsCorrected", 0));
rx.CPEMeanCorrection_deg = double(sixgr.util.structGet(cpeCorrInfo, "MeanCPE_deg", NaN));
rx.CPECorrectionNAReason = char(string(sixgr.util.structGet(cpeCorrInfo, "NAReason", "")));
rx.PTRSCPECorrectionEnabled = logical(cpeCorrInfo.Enabled);
rx.PTRSCPECorrectionSymbols = double(sixgr.util.structGet(cpeCorrInfo, "NumSymbolsCorrected", NaN));
rx.PTRSMeanCPE_deg = double(sixgr.util.structGet(cpeCorrInfo, "MeanCPE_deg", NaN));
rx.PTRSCPECorrectionReason = char(string(sixgr.util.structGet(cpeCorrInfo, "NAReason", "")));
rx.ReceiverTrackingCorrectionSource = char(string(trackingCorrection.Source));
rx.ReceiverTrackingCorrectionStatus = char(string(trackingCorrection.Status));
rx.ReceiverTrackingCorrectionNAReason = char(string(trackingCorrection.NAReason));
rx.ReceiverHestSINR_dB = double(receiverSINR.Value);
rx.ReceiverHestSINRSource = char(receiverSINR.Source);
rx.ReceiverHestSINRValueRole = char(receiverSINR.ValueRole);
rx.ReceiverHestSINRValueStatus = char(receiverSINR.ValueStatus);
rx.ReceiverHestSINRNAReason = char(receiverSINR.NAReason);
rx.PostEqSINR_dB = double(postEqSINR_dB);
rx.PostEqSINRSource = char(string(sixgr.util.structGet(postEqSINRInfo, "Source", "post_equalization_sinr_from_equalizer_channel_estimate")));
rx.PostEqSINRValueRole = char(string(sixgr.util.structGet(postEqSINRInfo, "ValueRole", "measured_post_equalization_scheduling_input")));
rx.PostEqSINRValueStatus = char(string(sixgr.util.structGet(postEqSINRInfo, "ValueStatus", "unavailable")));
rx.PostEqSINRNAReason = char(string(sixgr.util.structGet(postEqSINRInfo, "NAReason", "")));
rx.PostEqSINRPerLayer_dB = double(sixgr.util.structGet(postEqSINRInfo, "PerLayerSINR_dB", NaN));
rx.EqualizerType = char(string(equalizerInfo.AlgorithmUsed));
rx.EqualizerRequestedType = char(equalizerRequested);
rx.EqualizerEngine = char(string(equalizerInfo.EngineUsed));
rx.InterferenceCovarianceAvailable = logical(rintInfo.Available);
rx.InterferenceCovarianceSource = char(string(rintInfo.Source));
rx.InterferenceCovarianceStatus = char(string(rintInfo.Status));
rx.EqualizedSymbolsForEvidence = eqSym;
if isempty(pdschRxSym)
    rx.PDSCHRxSymbolsForEvidence = rxSym;
else
rx.PDSCHRxSymbolsForEvidence = pdschRxSym;
end
rx.RecLLR = recLLR;
rx.RateRecoveredLLR = recLLR;
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx, carrier, dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo, ...
    llr, recLLR, recLLRBatch, rateRecoverInfo, actIter, parity, cbCrcErr, alg, useMexLDPC, crcErr);
rx.ChannelEstimateAttempted = useFastAWGNPath || ~isempty(dmrsInd);
rx.ChannelEstimateAvailable = ~isempty(hEst);
if useFastAWGNPath
    rx.ChannelEstimateSource = "explicit_awgn_flat_validation_shortcut";
elseif ~isempty(dmrsAntInd)
    rx.ChannelEstimateSource = "pdsch_dmrs_channel_estimate";
else
    rx.ChannelEstimateSource = "unit_channel_no_dmrs_awgn_only";
end
rx.ResourceExtractionAttempted = true;
rx.ResourceExtractionAvailable = ~isempty(rxSym);
rx.EqualizationAttempted = true;
rx.EqualizationAvailable = ~isempty(eqSym);
rx.DLSCHDecodeAttempted = true;
rx.DLSCHDecodeAvailable = ~isempty(tbRx) || ~isempty(decCbs) || ~isempty(recLLR);
rx.LLRAvailable = ~isempty(llr);
rx.LLRFinite = ~isempty(llr) && all(isfinite(double(llr(:))));
rx.LLRScaleSource = "nrPDSCHDecode_noise_variance_plus_" + string(llrCSIInfo.Source);
rx.LLRCSIWeightApplied = logical(llrCSIInfo.Applied);
rx.LLRCSIWeightStatus = char(string(llrCSIInfo.Status));
rx.LLRCSIWeightInputKind = char(string(llrCSIInfo.InputKind));
rx.LLRCSIWeightRawMedian = double(llrCSIInfo.RawCSIMedian);
rx.LLRCSIWeightMedianBeforeNormalization = double(llrCSIInfo.WeightMedianBeforeNormalization);
rx.LLRCSIWeightNormalizationScale = double(llrCSIInfo.NormalizationScale);
rx.LLRNoiseVariance = double(nVarForDecode);
rx.SINRComputationMethod = char(lower(string(equalizerAlg)));
if ~logical(opt.CompactOutput)
    rx.CodewordLLR = llr;
    rx.DLSCHCodewordLLR = llr;
    rx.BaseGraph = bgn;
    rx.DecodedCodeBlocks = decCbs;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.CodeBlockCRCError = cbCrcErr;
    rx.ChannelEstimate = hEst;
    rx.RxGrid = rxGrid;
    rx.DMRSIndices = dmrsInd;
    rx.DMRSSymbols = dmrsSym;
    rx.Carrier = carrier;
    rx.PDSCH = pdsch;
    rx.PDSCHInfo = pdschInfo;
    rx.DMRSAntennaIndices = dmrsAntInd;
    rx.PDSCHAntennaIndices = pdschAntInd;
    rx.PDSCHIndices = pdschInd;
    rx.CSIRSIndices = csirsInd;
    rx.CSIRSSymbols = csirsSym;
    rx.CSIRSInfo = csirsInfo;
    rx.CSIRSObservation = csirsObservation;
    rx.PTRSIndices = ptrsInd;
    rx.PTRSSymbols = ptrsSym;
    rx.PTRSAntennaIndices = ptrsAntInd;
    rx.PTRSAntennaSymbols = ptrsAntSym;
    rx.PTRSInfo = ptrsInfo;
    rx.CPECorrectionInfo = cpeCorrInfo;
    rx.CSIRSChannelEstimate = csirsHest;
    rx.CSIRSNoiseVar = csirsNVar;
    rx.CSIRSChannelEstimation = csirsEstInfo;
    rx.CSIChannelEstimateForPMI = csirsHest;
    rx.CSIChannelNoiseVarForPMI = csirsNVar;
    rx.CSIChannelEstimateSource = char(string(sixgr.util.structGet(csirsEstInfo, "Source", "")));
    rx.CSI = csi;
    rx.EqualizerInfo = equalizerInfo;
    rx.InterferenceCovariance = Rint;
    rx.InterferenceCovarianceInfo = rintInfo;
    rx.PrecodeInfo = prec;
    rx.EqualizedSymbols = eqSym;
    rx.PDSCHRxSymbols = pdschRxSym;
end

strictEvidence = sixgr.phy.dl.validatePDSCHReceiverEvidence(rx, "StrictMode", strictMode);
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
info.PDSCHInfo = pdschInfo;
info.Precoding = prec;
info.ChannelEstimation = estInfo;
info.CSIRS = csirsInfo;
info.CSIRSObservation = csirsObservation;
info.CSIRSChannelEstimation = csirsEstInfo;
info.PTRS = ptrsInfo;
info.CPECorrection = cpeCorrInfo;
info.ReceiverTrackingCorrection = trackingCorrection;
info.NoiseVariance = nVarDecodeInfo;
info.HARQSoftCombining = harqCombiningInfo;
info.PreEqualizationNoiseVariance = double(nVar);
info.PostEqualizationNoiseVariance = double(nVarDecode);
info.TimingEstimate = timingResolution;
info.Equalizer = equalizerInfo;
info.InterferenceCovariance = rintInfo;
info.StrictReceiverEvidence = strictEvidence;

end

function method = localResolveChannelEstimationMethod(cfg)
method = char(string(sixgr.util.structGet(cfg, "phy.channelEstimation.method", ...
    sixgr.util.structGet(cfg, "phy.rx.channelEstimationMethod", "LS"))));
if isempty(strtrim(method))
    method = 'LS';
end
end

function [eqSymOut, info] = localCorrectEqualizedPDSCHCPEFromPTRS(eqSym, pdschInd, rxGrid, hEst, ...
        ptrsInd, ptrsSym, carrier, nVar, equalizerAlg, Rint, enabled)
% Estimate PTRS common phase after channel compensation, then rotate PDSCH.
info = struct('Enabled', false, 'NumSymbolsCorrected', 0, ...
    'MeanCPE_deg', NaN, 'NAReason', "");
eqSymOut = eqSym;
if ~logical(enabled)
    info.NAReason = "ptrs_cpe_correction_disabled_by_config";
    return;
end
if isempty(eqSym) || isempty(pdschInd) || isempty(rxGrid) || isempty(hEst)
    info.NAReason = "missing_pdsch_equalized_symbols_or_channel_estimate";
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
    [~, dataL, ~] = ind2sub([K L P], double(pdschInd(:)));
catch ME
    info.NAReason = "ptrs_or_pdsch_symbol_index_decode_failed:" + string(ME.identifier);
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

function [ptrsInd, ptrsSym, info] = localResolvePDSCHPTRS(carrier, pdsch, cfg)
ptrsInd = [];
ptrsSym = [];
info = struct("Available", false, "Enabled", false, "Source", "not_requested", ...
    "NAReason", "");
enabled = logical(sixgr.util.structGet(cfg, "phy.pdsch.enablePTRS", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enable", ...
    sixgr.util.structGet(cfg, "pdsch6gr.EnablePTRS", false))));
info.Enabled = enabled;
if ~enabled
    info.NAReason = "ptrs_disabled_by_config";
    return;
end
try
    ptrsInd = nrPDSCHPTRSIndices(carrier, pdsch, "IndexStyle", "index");
    ptrsSym = nrPDSCHPTRS(carrier, pdsch);
    info.Available = ~isempty(ptrsInd) && ~isempty(ptrsSym);
    info.Source = "nrPDSCHPTRS_runtime_symbols";
    if ~info.Available
        info.NAReason = "toolbox_returned_empty_ptrs";
    end
catch ME
    ptrsInd = [];
    ptrsSym = [];
    info.Available = false;
    info.Source = "nrPDSCHPTRS_unavailable";
    info.NAReason = string(ME.identifier);
end
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
    carrier, rxWave, sampleRateHz, rxGrid, ofdmInfo, tracking, cfg)
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
correctedWave = localApplyFrequencyCorrection(rxWave, sampleRateHz, -estimatedCFOHz);
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, correctedWave);
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

function evidence = localReceiverHestSINR(hEst, nVar, cfg, direction, rxGrid, refInd, refSym)
evidence = struct( ...
    "Value", NaN, ...
    "Source", "unavailable_receiver_hest_csi_feedback_failed", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "receiver_hest_csi_feedback_metric_not_available");
if isempty(hEst)
    evidence.NAReason = "receiver_hest_grid_empty";
    return;
end
try
    args = {"Direction", direction};
    if ~isempty(rxGrid) && ~isempty(refInd) && ~isempty(refSym)
        args = [args, {"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym}];
    end
    csiMetric = sixgr.phy.dl.CSI_Feedback(hEst, nVar, cfg, args{:});
    sinr = double(sixgr.util.structGet(csiMetric, "PilotSINR_dB", ...
        sixgr.util.structGet(csiMetric, "ReferenceMeasuredSINR_dB", NaN)));
    if isfinite(sinr)
        evidence.Value = sinr;
        evidence.Source = char(string(sixgr.util.structGet(csiMetric, "PilotSINRSource", "receiver_hest_reference_signal_measurement")));
        evidence.ValueRole = "estimated";
        measurementStatus = string(sixgr.util.structGet(csiMetric, "ReferenceSINRValueStatus", "OK"));
        if contains(lower(measurementStatus), "dynamic_range_limited")
            evidence.ValueStatus = char(measurementStatus);
        else
            evidence.ValueStatus = "OK";
        end
        evidence.NAReason = "";
    end
catch ME
    evidence.NAReason = "receiver_hest_csi_feedback_failed:" + string(ME.identifier);
end
end

function [csirsInd, csirsSym, csirsInfo, obs] = localObserveCSIRSRuntimeResource(carrier, cfg, rxGrid, opt)
csirsInd = opt.CSIRSIndices;
csirsSym = opt.CSIRSSymbols;
csirsInfo = opt.CSIRSInfo;
obs = localEmptyCSIRSObservation(cfg);
if isempty(csirsInfo) || ~isstruct(csirsInfo)
    csirsInfo = struct("Channel", "CSI-RS", "Enabled", false);
end
if ~isempty(opt.CSIRSTransmitted) && ~logical(opt.CSIRSTransmitted)
    obs.Scheduled = true;
    obs.RuntimeMaterializationStatus = "not_transmitted";
    obs.Blocker = "tx_runtime_csirs_event_not_transmitted";
    obs.UpdateOutcome = "not_observed";
    return;
end
if isempty(csirsInd) || isempty(csirsSym)
    if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
        obs.RuntimeMaterializationStatus = "disabled";
        obs.Blocker = "phy.csirs.enable_false";
        obs.UpdateOutcome = "not_observed";
        return;
    end
    try
        [csirsInd, csirsSym, csirsInfo] = sixgr.phy.refsig.csirs(carrier, cfg);
    catch ME
        obs.RuntimeMaterializationStatus = "blocked_generation_failed";
        obs.Blocker = string(ME.identifier) + ":" + string(ME.message);
        obs.UpdateOutcome = "not_observed";
        return;
    end
end
if isempty(csirsInd) || isempty(csirsSym)
    obs.RuntimeMaterializationStatus = "blocked_empty_resource";
    obs.Blocker = "empty_csirs_indices_or_symbols";
    obs.UpdateOutcome = "not_observed";
    return;
end
obs.Scheduled = true;
obs.NRE = double(numel(csirsSym));
obs.NumPorts = double(sixgr.util.structGet(csirsInfo, "NumCSIRSPorts", NaN));
obs.RowNumber = double(sixgr.util.structGet(csirsInfo, "RowNumber", NaN));
try
    rxRef = nrExtractResources(csirsInd, rxGrid);
catch
    try
        rxRef = rxGrid(double(csirsInd(:)));
    catch
        rxRef = [];
    end
end
if isempty(rxRef)
    obs.RuntimeMaterializationStatus = "blocked_extract_failed";
    obs.Blocker = "csirs_reference_re_extraction_failed";
    obs.UpdateOutcome = "not_observed";
    return;
end
powerLin = mean(abs(rxRef(:)).^2, "omitnan");
obs.Observed = isfinite(powerLin) && powerLin > 0;
obs.MeasurementRSRP_dB = 10 * log10(max(double(powerLin), eps));
obs.MeasurementSource = "received_csirs_reference_signal_power";
obs.RuntimeMaterializationStatus = "runtime_observed";
obs.UpdateOutcome = "observed_after_ofdm_demodulation";
obs.RuntimeEvidenceSource = "sixgr.phy.dl.PDSCH_Rx:csirs_runtime_observation";
end

function [Hest, nVar, estInfo] = localEstimateCSIRSChannelForPMI(carrier, rxGrid, csirsInd, csirsSym, csirsInfo, cfg, strictMode, channelModelToken, numTxPorts)
Hest = [];
nVar = NaN;
numCSIRSPorts = double(sixgr.util.structGet(csirsInfo, "NumCSIRSPorts", NaN));
expectedTxPorts = max([double(numTxPorts), numCSIRSPorts(isfinite(numCSIRSPorts)), 1]);
estInfo = struct( ...
    "Available", false, ...
    "Status", "unavailable", ...
    "Source", "", ...
    "Reason", "", ...
    "ExpectedTxPorts", double(expectedTxPorts), ...
    "NumCSIRSPorts", double(numCSIRSPorts));
if isempty(rxGrid) || isempty(csirsInd) || isempty(csirsSym)
    estInfo.Reason = "missing_csirs_reference_evidence";
    return;
end
if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
    estInfo.Status = "disabled";
    estInfo.Reason = "phy.csirs.enable_false";
    return;
end
try
    [Hest, nVar, chInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, csirsInd, csirsSym, ...
        "UseFastMex", false, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", expectedTxPorts, ...
        "ContextLabel", "PDSCH_Rx_CSI_RS_PMI");
    estInfo.Available = ~isempty(Hest);
    if estInfo.Available
        estInfo.Status = "OK";
        estInfo.Source = "csirs_resource_selective_channel_estimate";
        estInfo.Reason = "";
        estInfo.HestSize = size(Hest);
        estInfo.NoiseVar = double(nVar);
        estInfo.ChannelEstimator = string(sixgr.util.structGet(chInfo, "EngineUsed", ""));
        estInfo.InferredReferencePortCount = double(sixgr.util.structGet(chInfo, "InferredReferencePortCount", NaN));
    else
        estInfo.Status = "NOT_AVAILABLE";
        estInfo.Reason = "empty_csirs_channel_estimate";
    end
catch ME
    Hest = [];
    nVar = NaN;
    estInfo.Status = "NOT_AVAILABLE";
    estInfo.Source = "csirs_resource_selective_channel_estimate";
    estInfo.Reason = "csirs_channel_estimate_failed:" + string(ME.identifier);
end
end

function obs = localEmptyCSIRSObservation(cfg)
obs = struct();
obs.SignalFamily = "CSI-RS";
obs.SignalDirection = "DL";
obs.ResourceID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0));
obs.ResourceSetID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceSetID", 0));
obs.Scheduled = false;
obs.Observed = false;
obs.Consumed = false;
obs.Consumer = "";
obs.RuntimeMaterializationStatus = "";
obs.Blocker = "";
obs.UpdateOutcome = "";
obs.RuntimeEvidenceSource = "";
obs.MeasurementRSRP_dB = NaN;
obs.MeasurementSource = "";
obs.NRE = NaN;
obs.NumPorts = NaN;
obs.RowNumber = NaN;
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
    error("sixgr:phy:dl:PDSCHInvalidTBSForLDPC", ...
        "PDSCH_Rx cannot resolve LDPC segmentation for invalid TBS %.6g.", trBlkSize);
end
if ~(isscalar(bgn) && isfinite(bgn) && any(round(bgn) == [1 2]))
    error("sixgr:phy:dl:PDSCHInvalidBaseGraphForLDPC", ...
        "PDSCH_Rx cannot resolve LDPC segmentation for base graph %.6g.", bgn);
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

function localGuardUnsupportedNumLayers(cfg, pdsch)
nLayers = 1;
if isempty(pdsch)
    nLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
else
    try
        nLayers = double(pdsch.NumLayers);
    catch
        nLayers = 1;
    end
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = round(nLayers);
if nLayers > 4
    error("sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported", ...
        "PDSCH_Tx/PDSCH_Rx support a single codeword only. Requested %d layer(s) implies 2 codeword(s).", ...
        nLayers);
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

function nrePerPRB = localResolvePDSCHNREPerPRBOrError(carrier, pdsch, pdschInfo, nPRB)
nrePerPRB = localResolveNREFromInfo(pdschInfo, nPRB, pdsch.Modulation, pdsch.NumLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    try
        [~, pdschInfoFull] = nrPDSCHIndices(carrier, pdsch);
        nrePerPRB = localResolveNREFromInfo(pdschInfoFull, nPRB, pdsch.Modulation, pdsch.NumLayers);
    catch
    end
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error('sixgr:phy:dl:PDSCHRx:CannotResolveTBS', ...
        ['Cannot determine nrePerPRB for TBS calculation. Provide TransportBlockSize explicitly. ' ...
         'PRBSet=%s, SymbolAllocation=%s, Modulation=%s, NumLayers=%d.'], ...
        mat2str(double(pdsch.PRBSet)), mat2str(localSymAlloc(pdsch)), ...
        char(string(pdsch.Modulation)), round(double(pdsch.NumLayers)));
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

function sa = localSymAlloc(pdsch)
try
    sa = double(pdsch.SymbolAllocation);
catch
    sa = [0 14];
end
if numel(sa) < 2
    sa = [0 14];
else
    sa = reshape(sa(1:2), 1, 2);
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

function antInd = localPrecodeIndices(carrier, portInd, Wnr)
dummySym = complex(zeros(size(portInd)));
[~, antInd] = nrPDSCHPrecode(carrier, dummySym, portInd, Wnr);
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
try
    if isobject(obj) && isprop(obj, char(propName))
        value = obj.(char(propName));
    elseif isstruct(obj) && isfield(obj, char(propName))
        value = obj.(char(propName));
    end
catch
    value = defaultValue;
end
end

function numTxPorts = localExpectedTxPorts(pdsch, prec)
numTxPorts = 1;
try
    numTxPorts = max(numTxPorts, double(pdsch.NumLayers));
catch
end
if nargin >= 2 && isstruct(prec) && logical(sixgr.util.structGet(prec, "Active", false))
    Wnr = sixgr.util.structGet(prec, "MatrixNR", []);
    if ~isempty(Wnr)
        numTxPorts = max(numTxPorts, size(Wnr, 1));
    end
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

function localValidateNoDMRSUnitChannelFallback(channelToken, numTxPorts, numRxAnt, contextLabel)
if localIsExplicitFlatChannel(channelToken) && numTxPorts <= 1 && numRxAnt <= 1
    return;
end
error("sixgr:phy:rx:MissingDMRSForTruthChannelEstimate", ...
    "%s requires DM-RS-backed resource-selective channel estimation for truthful reception. Channel='%s', TxPorts=%d, RxAnt=%d.", ...
    contextLabel, localDisplayChannelToken(channelToken), numTxPorts, numRxAnt);
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
