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
%     "PHYGrant"    : frozen canonical grant dimensional contract
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
%     Ranks 1-4 use one codeword. Ranks 5-8 use two independent DL-SCH
%     codeword paths with per-codeword RV, CodingLayout and soft buffers.

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCHIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSSymbols', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CSIRSInfo', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('CSIRSTransmitted', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('TransportBlockSize', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>0)));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>0 & x(:)<1)));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>=0 & x(:)<=3)));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('HARQSoftBufferLLR', [], @(x) isempty(x) || isnumeric(x) || iscell(x) || isstruct(x));
ip.addParameter('HARQSoftBufferLayout', struct(), @(x) isempty(x) || isstruct(x) || iscell(x));
ip.addParameter('CodingLayout', struct(), @(x) isempty(x) || isstruct(x) || iscell(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ReceiverTrackingState', [], @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;
phyGrant = opt.PHYGrant;
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "pdsch_rx_entry");
    cfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, phyGrant);
    if isempty(opt.PrecodingMatrix)
        opt.PrecodingMatrix = double(phyGrant.PrecodingState.Matrix);
    end
end
localValidateSupportedCodewordScope(cfg, opt.PDSCH);
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
rv = double(rv(:).');

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pdsch.codeRate', 0.4785));
end
targetCodeRate = double(targetCodeRate(:).');

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
phyGrantContract = struct();
if hasPHYGrant
    phyGrantContract = sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pdsch_rx_after_config", ...
        "PDSCH", pdsch, ...
        "Precoding", prec);
end

% Expected TB size
nCodewords = localResolvePDSCHNumCodewords(pdsch, round(double(pdsch.NumLayers)));
rv = localExpandPerCodewordRV(rv, nCodewords);
targetCodeRate = localExpandPerCodewordDouble(targetCodeRate, nCodewords, "PDSCH TargetCodeRate");
modulationPerCodeword = localPDSCHModulationPerCodeword(pdsch, nCodewords);
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, localObjectValue(pdsch, "SymbolAllocation", [0 14]));
    nPRB = numel(pdsch.PRBSet);
    nrePerPRB = localResolvePDSCHNREPerPRBOrError(carrier, pdsch, pdschInfo, nPRB);
    trBlkSize = nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
end
trBlkSize = localExpandPerCodewordInteger(double(trBlkSize(:).'), nCodewords, "PDSCH transport block size");

% Canonical coding layout.
rateMatchedBits = localRateMatchedBitCountFromInfo(pdschInfo);
rateMatchedBits = localExpandPerCodewordInteger(rateMatchedBits, nCodewords, "PDSCH rate-matched bit count");
codingLayouts = localResolveRxCodingLayouts(opt.CodingLayout, phyGrant, "DL", ...
    trBlkSize, targetCodeRate, rv, modulationPerCodeword, pdsch.NumLayers, ...
    rateMatchedBits);
codingLayout = codingLayouts{1};
codewordLayerMapping = localBuildPDSCHRxCodewordLayerContract(pdsch, rateMatchedBits, codingLayouts);
bgn = double(codingLayout.BaseGraph);
tbCRCType = char(string(codingLayout.TBCRCType));
tbCRCLen = double(codingLayout.TBCRCLength);
ldpcSeg = localLDPCSegmentationFromLayout(codingLayout);

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
knownTimingDelaySamples = localResolveKnownTimingDelaySamples(cfg, trackingCorrection);
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
timingEstimateForCorrection = rawTimingEstimate;
if timingEstimateUsed && isfinite(rawTimingEstimate)
    timingEstimateForCorrection = rawTimingEstimate - double(knownTimingDelaySamples);
end
timingResolution = sixgr.phy.sync.resolveTimingApplication(timingEstimateForCorrection, ...
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
    if ~logical(trackingCorrection.CFOEstimateAvailable) && any(cfoEstimationMethod == ["cyclic_prefix", "cp"])
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
        trackingCorrection.Source = char(string(cfoEstimationMethod));
        trackingCorrection.NAReason = "cfo_estimate_unavailable_or_disabled_by_method";
    end
end
[rxGrid, ofdmInfo, trackingCorrection] = localApplyEstimatedCFOAndRedemodulate( ...
    carrier, rxWave, sampleRateHz, rxGrid, ofdmInfo, trackingCorrection, cfg);
syncState = sixgr.phy.sync.resolveSynchronizationState( ...
    "SampleRate_Hz", sampleRateHz, ...
    "InjectedCFO_Hz", localResolveInjectedCFOHz(cfg), ...
    "EstimatedCFO_Hz", double(sixgr.util.structGet(trackingCorrection, "EstimatedCFO_Hz", NaN)), ...
    "AppliedCFOCorrection_Hz", double(sixgr.util.structGet(trackingCorrection, "CFOCorrectionApplied_Hz", NaN)), ...
    "ResidualCFOEstimate_Hz", double(sixgr.util.structGet(trackingCorrection, "ResidualCFOEstimate_Hz", NaN)), ...
    "EstimatedCommonFrequency_Hz", double(sixgr.util.structGet(trackingCorrection, "EstimatedCommonFrequency_Hz", NaN)), ...
    "PhysicalDoppler_Hz", double(sixgr.util.structGet(trackingCorrection, "PhysicalDoppler_Hz", NaN)), ...
    "InjectedTimingOffset_samples", localResolveInjectedTimingOffsetSamples(cfg), ...
    "RawTimingEstimate_samples", rawTimingEstimate, ...
    "KnownTimingDelay_samples", knownTimingDelaySamples, ...
    "AppliedTimingCorrection_samples", double(timingResolution.AppliedCorrection_samples), ...
    "TimingEstimateUsed", logical(timingResolution.EstimateUsed), ...
    "TimingSource", timingEstimateSource, ...
    "FrequencySource", string(sixgr.util.structGet(trackingCorrection, "Source", "")), ...
    "TrackingState", string(sixgr.util.structGet(trackingCorrection, "TrackingState", "")), ...
    "TrackingAgeSlots", double(sixgr.util.structGet(trackingCorrection, "AgeSlots", NaN)));
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
noiseTransformInfo = struct( ...
    "InputDomain", "grid", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "runtime_channel_estimate_grid_domain");
if isempty(noiseCandidate)
    % nrChannelEstimate returns grid-domain noise variance.
    noiseCandidate = nVarEst;
else
    domain = lower(strtrim(char(string(opt.NoiseVarDomain))));
    [noiseCandidate, noiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        noiseCandidate, ofdmInfo, ...
        "InputDomain", domain, ...
        "Source", "runtime_metadata");
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
equalizerResult = sixgr.util.structGet(equalizerInfo, "EqualizerResult", struct());
try
    [postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo] = sixgr.phy.rx.computePostEqSINR( ...
        hestSym, nVar, ...
        "Method", char(lower(string(equalizerAlg))), ...
        "Rint", Rint, ...
        "EqualizerResult", equalizerResult, ...
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
csiFromEqualizerResult = sixgr.util.structGet(postEqSINRInfo, "DemapperReliability", []);
if ~isempty(csiFromEqualizerResult)
    csi = csiFromEqualizerResult;
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
[llrCWCell, codewordLLRInfo] = localNormalizePDSCHCodewordLLR(llrCW, codewordLayerMapping);
[llrCell, llrCSIInfoCell] = localApplyCSIToPDSCHCodewordLLRCell(llrCWCell, csi, pdsch.Modulation, ...
    postEqSINR_dB, codewordLayerMapping, nVarForDecode, nVarDecodeInfo);
llr = llrCell{1};
llrCSIInfo = llrCSIInfoCell{1};
codewordLayerMapping = localFinalizePDSCHRxCodewordLayerContract(codewordLayerMapping, llrCell, eqSym);

% ---------------------- DL-SCH decode (rate recovery + LDPC decode) ----------------------
decode = localDecodePDSCHCodewords(llrCell, codingLayouts, trBlkSize, targetCodeRate, rv, ...
    modulationPerCodeword, double(pdsch.NumLayers), cfg, maxIter, alg, opt.HARQSoftBufferLLR, opt.HARQSoftBufferLayout);
recLLR = decode.RecLLRCell{1};
rateRecoverInfo = decode.RateRecoverInfoCell{1};
harqCombiningInfo = decode.HARQCombiningSummary;
recLLRBatch = decode.RecLLRBatchCell{1};
actIter = decode.ActiveIterations;
parity = decode.ParityChecks;
decodeLatency_s = decode.DecodeLatency_s;
useMexLDPC = decode.UseMexLDPC;
decCbs = decode.DecodedCodeBlocksCell{1};
B = decode.TransportBlockLenWithCRCPerCodeword(1);
tbCrcRx = decode.TransportBlockCRCPerCodeword{1};
cbCrcErr = decode.CodeBlockCRCError;
tbRx = vertcat(decode.TransportBlockCell{:});
crcOk = all(decode.CRCPassPerCodeword);
crcErr = ~crcOk;
ldpcSeg = decode.LDPCSegmentationCell{1};

% ---------------------- Outputs ----------------------
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.TransportBlockSizePerCodeword = double(trBlkSize);
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOk);
rx.CRCPass = logical(crcOk);
rx.TBCRCPass = logical(crcOk);
rx.TransportBlock = int8(tbRx(:));
rx.TransportBlocks = decode.TransportBlockCell;
rx.CRCPassPerCodeword = logical(decode.CRCPassPerCodeword);
rx.CRCErrorPerCodeword = logical(decode.CRCErrorPerCodeword);
rx.TimingOffset = double(rawTimingEstimate);
rx.RawTimingEstimate_samples = double(rawTimingEstimate);
rx.KnownTimingDelay_samples = double(knownTimingDelaySamples);
rx.TimingEstimateForCorrection_samples = double(timingEstimateForCorrection);
rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
rx.TimingEstimateUsed = logical(timingResolution.EstimateUsed);
rx.TimingEstimateSource = char(timingEstimateSource);
rx.TimingEstimateStatus = char(string(timingResolution.Status));
rx.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
rx.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
rx.SynchronizationState = syncState;
rx.NoiseVar = nVarForDecode;
rx.NoiseVarStatus = "OK";
rx.NoiseVarSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "post_equalization_decoder_noise_variance")));
rx.NoiseVarReason = "";
rx.NoiseVarStrictFailure = false;
rx.NoiseVarDomain = "post_equalization_decoder_symbol_domain";
rx.PreEqualizationNoiseVar = double(nVar);
rx.PreEqualizationNoiseVarDomain = "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarTransformSource = char(string(sixgr.util.structGet(noiseTransformInfo, "TransformSource", "")));
rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet(noiseTransformInfo, "SampleToGridNoiseVarianceGain", NaN));
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
rx.NumCodeBlocksPerCodeword = double(cellfun(@(x) double(x.NumCodeBlocks), decode.LDPCSegmentationCell));
rx.CodeBlockLength_bits = double(ldpcSeg.CodeBlockLength);
rx.CodeBlockLengthPerCodeword_bits = double(cellfun(@(x) double(x.CodeBlockLength), decode.LDPCSegmentationCell));
rx.TransportBlockCRCLength = double(tbCRCLen);
rx.TransportBlockCRCLengthPerCodeword = double(cellfun(@(x) double(x.TBCRCLength), codingLayouts));
rx.TransportBlockLenWithCRC = double(ldpcSeg.TransportBlockLenWithCRC);
rx.TransportBlockLenWithCRCPerCodeword = double(decode.TransportBlockLenWithCRCPerCodeword);
rx.CodingLayout = codingLayout;
rx.CodingLayouts = codingLayouts;
rx.CodewordLayerMapping = codewordLayerMapping;
rx.NumCodewords = double(codewordLayerMapping.NumCodewords);
rx.ActualNumCodewords = double(codewordLayerMapping.ActualNumCodewords);
rx.CodewordLLRCountPerCodeword = double(codewordLayerMapping.DemapperLLRCountPerCodeword);
rx.DecodedBitLineage = decode.DecodedBitLineageCell{1};
rx.DecodedBitLineagePerCodeword = decode.DecodedBitLineageCell;
rx.LDPCRateRecoverNumCodeBlocks = double(sixgr.util.structGet(rateRecoverInfo, "numCBUsed", ldpcSeg.NumCodeBlocks));
rx.LDPCRateRecoverNumCodeBlocksPerCodeword = double(cellfun(@(x) double(sixgr.util.structGet(x, "numCBUsed", NaN)), decode.RateRecoverInfoCell));
rx.HARQSoftCombiningApplied = logical(harqCombiningInfo.Applied);
rx.HARQSoftCombiningReason = char(string(harqCombiningInfo.Reason));
rx.HARQSoftCombiningCurrentNumel = double(harqCombiningInfo.CurrentNumel);
rx.HARQSoftCombiningPriorNumel = double(harqCombiningInfo.PriorNumel);
rx.HARQSoftCombiningPositionAware = logical(sixgr.util.structGet(harqCombiningInfo, "PositionAware", false));
rx.HARQSoftCombiningOverlapPositionCount = double(sixgr.util.structGet(harqCombiningInfo, "OverlapPositionCount", NaN));
rx.XOverhead = double(sixgr.phy.dl.resolvePDSCHXOverhead(cfg, localObjectValue(pdsch, "SymbolAllocation", [0 14])));
rx.CFOEstimateAvailable = logical(trackingCorrection.CFOEstimateAvailable);
rx.EstimatedCFO_Hz = double(trackingCorrection.EstimatedCFO_Hz);
rx.EstimatedCommonFrequency_Hz = double(sixgr.util.structGet(syncState, "EstimatedCommonFrequency_Hz", NaN));
rx.PhysicalDoppler_Hz = double(sixgr.util.structGet(syncState, "PhysicalDoppler_Hz", NaN));
rx.CFOCorrectionApplied = logical(trackingCorrection.CFOCorrectionApplied);
rx.CFOCorrectionApplied_Hz = double(trackingCorrection.CFOCorrectionApplied_Hz);
rx.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(syncState, "ResidualCFO_PostCorrection_Hz", NaN));
rx.ResidualCFO_EstimatedPostCorrection_Hz = double(sixgr.util.structGet(syncState, "ResidualCFO_EstimatedPostCorrection_Hz", NaN));
rx.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(syncState, "ResidualTimingError_PostCorrection_samples", NaN));
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
rx.EqualizerResultContract = char(string(sixgr.util.structGet(equalizerInfo, "EqualizerResult.ContractVersion", "")));
rx.EqualizerEquation = char(string(sixgr.util.structGet(equalizerInfo, "EqualizerResult.Equation", "")));
rx.EqualizerCovarianceIncludesNoise = logical(sixgr.util.structGet(equalizerInfo, "EqualizerResult.CovarianceIncludesNoise", false));
rx.EqualizerNoiseAddedExactlyOnce = logical(sixgr.util.structGet(equalizerInfo, "EqualizerResult.NoiseAddedExactlyOnce", false));
rx.EqualizerUniqueSolveCount = double(sixgr.util.structGet(equalizerInfo, "EqualizerResult.UniqueSolveCount", NaN));
rx.EqualizerSolveCount = double(sixgr.util.structGet(equalizerInfo, "EqualizerResult.SolveCount", NaN));
rx.InterferenceCovarianceAvailable = logical(rintInfo.Available);
rx.InterferenceCovarianceSource = char(string(rintInfo.Source));
rx.InterferenceCovarianceStatus = char(string(rintInfo.Status));
rx.EqualizedSymbolsForEvidence = eqSym;
rx.LayerEqualizedSymbolsForEvidence = eqSym;
rx.LayerEqualizedSymbols = eqSym;
rx.EqualizedSymbolDomain = "layer";
rx.LayerSymbolOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, pdschInd, "layer");
rx.DemapperLLRCount = double(codewordLayerMapping.TotalDemapperLLRCount);
rx.RateRecoveredLLRCount = double(sum(cellfun(@numel, decode.RecLLRCell)));
rx.RateRecoveredLLRCountPerCodeword = double(cellfun(@numel, decode.RecLLRCell));
if isempty(pdschRxSym)
    rx.PDSCHRxSymbolsForEvidence = rxSym;
else
rx.PDSCHRxSymbolsForEvidence = pdschRxSym;
end
rx.RecLLR = recLLR;
rx.RateRecoveredLLR = recLLR;
rx.RecLLRCell = decode.RecLLRCell;
rx.RateRecoveredLLRCell = decode.RecLLRCell;
rx.RateRecoverInfoCell = decode.RateRecoverInfoCell;
rx.HARQSoftCombiningInfoPerCodeword = decode.HARQCombiningInfoCell;
rx.HARQSoftBuffer = sixgr.util.structGet(harqCombiningInfo, "SoftBuffer", struct());
rx.HARQSoftBufferCell = decode.HARQSoftBufferCell;
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx, carrier, dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo, ...
    llr, recLLR, recLLRBatch, rateRecoverInfo, actIter, parity, cbCrcErr, alg, useMexLDPC, crcErr);
if hasPHYGrant
    rx.PHYGrant = phyGrant;
    rx.PHYGrantDimensionContract = phyGrantContract;
end
rx.ChannelEstimateAttempted = useFastAWGNPath || ~isempty(dmrsInd);
rx.ChannelEstimateAvailable = ~isempty(hEst);
if useFastAWGNPath
    rx.ChannelEstimateSource = "explicit_awgn_flat_validation_shortcut";
elseif ~isempty(dmrsAntInd)
    rx.ChannelEstimateSource = "pdsch_dmrs_channel_estimate";
else
    rx.ChannelEstimateSource = "unit_channel_no_dmrs_awgn_only";
end
rx.ChannelEstimateMethod = char(string(sixgr.util.structGet(estInfo, "Method", "")));
rx.ChannelEstimateEngine = char(string(sixgr.util.structGet(estInfo, "EngineUsed", "")));
rx.ChannelEstimateInterpolationMethod = char(string(sixgr.util.structGet(estInfo, "InterpolationMethod", "")));
rx.ChannelEstimateEffectiveConvention = char(string(sixgr.util.structGet(estInfo, "EffectiveChannelConvention", "")));
rx.ChannelEstimatePilotRECount = double(sixgr.util.structGet(estInfo, "PilotRECount", NaN));
rx.ChannelEstimatePilotResidualPower = double(sixgr.util.structGet(estInfo, "PilotResidualPower", NaN));
rx.ChannelEstimatePilotResidualNMSE_dB = double(sixgr.util.structGet(estInfo, "PilotResidualNMSE_dB", NaN));
rx.ResourceExtractionAttempted = true;
rx.ResourceExtractionAvailable = ~isempty(rxSym);
rx.EqualizationAttempted = true;
rx.EqualizationAvailable = ~isempty(eqSym);
rx.DLSCHDecodeAttempted = true;
rx.DLSCHDecodeAvailable = ~isempty(tbRx) || ~isempty(decCbs) || ~isempty(recLLR);
rx.LLRAvailable = ~isempty(llr);
rx.LLRFinite = ~isempty(llr) && all(isfinite(double(llr(:))));
rx.LLRScaleSource = string(llrCSIInfo.Source);
rx.LLRScalingConvention = char(string(llrCSIInfo.Convention));
rx.DemapperNoiseVarianceConvention = char(string(llrCSIInfo.NoiseVarianceConvention));
rx.DemapperLLRDomain = char(string(llrCSIInfo.OutputDomain));
rx.LLRDoubleWeightingGuard = logical(llrCSIInfo.NoSecondCSIWeighting);
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
    rx.CodewordLLRCell = llrCell;
    rx.DLSCHCodewordLLRCell = llrCell;
    rx.CodewordLLRInfo = codewordLLRInfo;
    rx.LLRCSIInfoPerCodeword = llrCSIInfoCell;
    rx.BaseGraph = bgn;
    rx.BaseGraphPerCodeword = double(cellfun(@(x) double(x.BaseGraph), codingLayouts));
    rx.DecodedCodeBlocks = decCbs;
    rx.DecodedCodeBlocksCell = decode.DecodedCodeBlocksCell;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.CodeBlockCRCError = cbCrcErr;
    rx.ChannelEstimate = hEst;
    rx.ChannelEstimation = estInfo;
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
info.ReceiverSynchronizationState = syncState;
info.NoiseVariance = nVarDecodeInfo;
info.OFDMNoiseTransform = sixgr.util.structGet(ofdmInfo, "NoiseTransform", struct());
info.PreEqualizationNoiseVarianceTransform = noiseTransformInfo;
info.HARQSoftCombining = harqCombiningInfo;
info.HARQSoftBuffer = rx.HARQSoftBuffer;
info.PreEqualizationNoiseVariance = double(nVar);
info.PostEqualizationNoiseVariance = double(nVarDecode);
info.TimingEstimate = timingResolution;
info.Equalizer = equalizerInfo;
info.InterferenceCovariance = rintInfo;
info.CodingLayout = codingLayout;
info.CodingLayouts = codingLayouts;
info.CodewordLayerMapping = codewordLayerMapping;
info.CodewordLLRInfo = codewordLLRInfo;
info.LLRScalingPerCodeword = llrCSIInfoCell;
info.DecodedBitLineagePerCodeword = decode.DecodedBitLineageCell;
info.RateRecoverPerCodeword = decode.RateRecoverInfoCell;
info.HARQSoftCombiningPerCodeword = decode.HARQCombiningInfoCell;
info.HARQSoftBufferPerCodeword = decode.HARQSoftBufferCell;
info.DecodePerCodeword = decode;
info.StrictReceiverEvidence = strictEvidence;
if hasPHYGrant
    info.PHYGrant = phyGrant;
    info.PHYGrantDimensionContract = phyGrantContract;
end

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
    "EstimatedCommonFrequency_Hz", NaN, ...
    "PhysicalDoppler_Hz", NaN, ...
    "CFOCorrectionApplied", false, ...
    "CFOCorrectionApplied_Hz", NaN, ...
    "ResidualCFOEstimate_Hz", NaN, ...
    "Source", "unavailable_receiver_tracking_state", ...
    "Status", "unavailable", ...
    "NAReason", "no_receiver_tracking_state", ...
    "CFONAReason", "", ...
    "TrackingState", "", ...
    "AgeSlots", NaN, ...
    "KnownTimingDelay_samples", NaN);

raw = explicitState;
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
end
if ~(isstruct(raw) && ~isempty(fieldnames(raw)))
    return;
end

processed = localFirstLogical(raw, ["TRSProcessed","RuntimeTRSProcessed"], false);
tracking.TRSProcessed = logical(processed);
tracking.TrackingState = char(localFirstString(raw, ["TrackingState","RuntimeTRSTrackingStateAfter"], ""));
tracking.AgeSlots = double(localFirstFinite(raw, ["TRSAgeSlots","RuntimeTRSAgeSlots"], NaN));
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
cfoHz = localFirstFinite(raw, ["EstimatedOscillatorCFO_Hz","RuntimeTRSEstimatedOscillatorCFO_Hz", ...
    "EstimatedCFO_Hz","RuntimeTRSEstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN);
commonHz = localFirstFinite(raw, ["EstimatedCommonFrequency_Hz","RuntimeTRSEstimatedCommonFrequency_Hz", ...
    "EstimatedCommonPhaseFrequency_Hz"], NaN);
physicalDopplerHz = localFirstFinite(raw, ["PhysicalDoppler_Hz","RuntimeTRSPhysicalDoppler_Hz", ...
    "EstimatedDopplerHz","LastEstimatedTRSDopplerHz","RuntimeLastEstimatedTRSDopplerHz"], NaN);

tracking.TimingEstimateAvailable = logical(timingAvailable && isfinite(timingSamples));
tracking.TimingEstimate_samples = double(timingSamples);
tracking.CFOEstimateAvailable = logical(cfoAvailable && isfinite(cfoHz));
tracking.EstimatedCFO_Hz = double(cfoHz);
tracking.EstimatedCommonFrequency_Hz = double(commonHz);
tracking.PhysicalDoppler_Hz = double(physicalDopplerHz);
tracking.KnownTimingDelay_samples = localFirstFinite(raw, ["KnownTimingDelay_samples","RuntimeChannelFilterDelay_samples", ...
    "RuntimeChannelTrimSamples"], NaN);
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
    tracking = localEstimateResidualCFOAfterCorrection(rxWave, ofdmInfo, sampleRateHz, tracking, ...
        "cyclic_prefix_post_tracking_correction");
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
tracking = localEstimateResidualCFOAfterCorrection(correctedWave, ofdmInfo, sampleRateHz, tracking, ...
    "cyclic_prefix_post_receiver_correction");
end

function tracking = localEstimateResidualCFOAfterCorrection(rxWave, ofdmInfo, sampleRateHz, tracking, source)
tracking.ResidualCFOEstimate_Hz = NaN;
tracking.ResidualCFOEstimateSource = string(source);
if ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
try
    [residualHz, residualInfo] = sixgr.phy.rx.estimateCFOFromCyclicPrefix(rxWave, ofdmInfo, sampleRateHz);
    if logical(sixgr.util.structGet(residualInfo, "EstimateAvailable", false)) && isfinite(double(residualHz))
        tracking.ResidualCFOEstimate_Hz = double(residualHz);
    end
catch
    tracking.ResidualCFOEstimateSource = string(source) + "_failed";
end
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

function delay = localResolveKnownTimingDelaySamples(cfg, tracking)
delay = double(sixgr.util.structGet(tracking, "KnownTimingDelay_samples", NaN));
if isfinite(delay)
    return;
end
delay = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelFilterDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelFilterDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelTrimSamples", ...
    sixgr.util.structGet(cfg, "phy.rx.knownTimingDelay_samples", 0)))));
if ~isfinite(delay)
    delay = 0;
end
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "rf.cfo_Hz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0))));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "rf.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0))));
if ~isfinite(timingOffset)
    timingOffset = 0;
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
        estInfo.InterpolationMethod = string(sixgr.util.structGet(chInfo, "InterpolationMethod", ""));
        estInfo.EffectiveChannelConvention = string(sixgr.util.structGet(chInfo, "EffectiveChannelConvention", ""));
        estInfo.PilotRECount = double(sixgr.util.structGet(chInfo, "PilotRECount", NaN));
        estInfo.PilotResidualPower = double(sixgr.util.structGet(chInfo, "PilotResidualPower", NaN));
        estInfo.PilotResidualNMSE_dB = double(sixgr.util.structGet(chInfo, "PilotResidualNMSE_dB", NaN));
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

function mapping = localBuildPDSCHRxCodewordLayerContract(pdsch, rateMatchedBits, codingLayouts)
nLayers = localPositiveIntegerValue(localObjectValue(pdsch, "NumLayers", 1), "PDSCH.NumLayers");
nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers);
localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);
rateMatchedBits = double(rateMatchedBits);
if numel(rateMatchedBits) == 1 && nCodewords > 1
    rateMatchedBits = repmat(rateMatchedBits, 1, nCodewords);
end
if numel(rateMatchedBits) ~= nCodewords || any(~isfinite(rateMatchedBits) | rateMatchedBits <= 0 | abs(rateMatchedBits - round(rateMatchedBits)) > 1e-9)
    error("sixgr:phy:dl:PDSCHBadRateMatchedBitCount", "PDSCH RX requires a positive integer G for the codeword contract.");
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
layoutBits = zeros(1, nCodewords);
for c = 1:nCodewords
    layoutBits(c) = double(codingLayouts{c}.RateMatchedBitCount);
end
layerCountPerCodeword = localLayerCountPerCodeword(nLayers, nCodewords);
[codewordIndexByLayer, layerIndexWithinCodeword] = localCodewordLayerIndexMap(layerCountPerCodeword);
mapping = struct();
mapping.ContractVersion = "PDSCHCodewordLayer/v1";
mapping.Direction = "DL";
mapping.MappingStandard = "3GPP_TS_38_211_codeword_to_layer_mapping";
mapping.MappingEngine = "nrPDSCH_internal_nrLayerMap";
mapping.InverseEngine = "nrPDSCHDecode_internal_nrLayerDemap";
mapping.SupportedScope = "single_codeword_ranks_1_to_4_and_two_codeword_ranks_5_to_8";
mapping.UnsupportedScope = "";
mapping.NumCodewords = double(nCodewords);
mapping.ActualNumCodewords = NaN;
mapping.NumLayers = double(nLayers);
mapping.GrantNumLayers = double(nLayers);
mapping.CodewordIndexByLayer = double(codewordIndexByLayer);
mapping.LayerIndexWithinCodeword = double(layerIndexWithinCodeword);
mapping.LayerCountPerCodeword = double(layerCountPerCodeword);
mapping.RateMatchedBitCountPerCodeword = double(round(rateMatchedBits));
mapping.CodingLayoutRateMatchedBitCountPerCodeword = double(layoutBits);
mapping.DemapperLLRCountPerCodeword = NaN(1, nCodewords);
mapping.TotalDemapperLLRCount = NaN;
mapping.ActualLayerColumns = NaN;
mapping.ActualLayersEqualGrantLayers = false;
mapping.Equation = "port_observations_to_equalized_layers_S_hat_to_codeword_LLRs_by_inverse_TS38211_7_3_1_3";
end

function [llrCell, info] = localNormalizePDSCHCodewordLLR(llrRaw, mapping)
if iscell(llrRaw)
    llrCell = reshape(llrRaw, 1, []);
    sourceWasCell = true;
else
    llrCell = {llrRaw};
    sourceWasCell = false;
end
expected = double(mapping.NumCodewords);
if numel(llrCell) ~= expected
    error("sixgr:phy:dl:PDSCHDecodedCodewordCountMismatch", ...
        "nrPDSCHDecode returned %d codeword LLR stream(s), but the grant expects %d.", numel(llrCell), expected);
end
for c = 1:numel(llrCell)
    llrCell{c} = double(llrCell{c}(:));
end
info = struct( ...
    "ContractVersion", "PDSCHCodewordLLR/v1", ...
    "SourceWasCell", logical(sourceWasCell), ...
    "ExpectedNumCodewords", double(expected), ...
    "ActualNumCodewords", double(numel(llrCell)), ...
    "LLRCountPerCodeword", double(cellfun(@numel, llrCell)));
end

function [llrCellOut, infoCell] = localApplyCSIToPDSCHCodewordLLRCell(llrCellIn, csi, modScheme, postEqSINR_dB, mapping, nVarForDecode, nVarDecodeInfo)
llrCellOut = llrCellIn;
infoCell = cell(size(llrCellIn));
mods = localNormalizeModulationCell(modScheme, numel(llrCellIn));
csiCell = localDemapCSIByCodeword(csi, mapping);
for c = 1:numel(llrCellIn)
    infoCell{c} = localPDSCHPostEqVarianceLLRInfo(llrCellIn{c}, csiCell{c}, mods{c}, ...
        postEqSINR_dB, nVarForDecode, nVarDecodeInfo);
end
end

function info = localPDSCHPostEqVarianceLLRInfo(llrIn, csi, modScheme, postEqSINR_dB, nVarForDecode, nVarDecodeInfo)
rawCSI = double(csi(:));
rawCSI = rawCSI(isfinite(rawCSI));
if isempty(rawCSI)
    rawMedian = NaN;
else
    rawMedian = median(rawCSI, "omitnan");
end
inputMean = mean(abs(double(llrIn(:))), "omitnan");
source = "nrPDSCHDecode_post_equalization_noise_variance_only";
noiseSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "post_equalization_decoder_noise_variance")));
info = struct( ...
    "ContractVersion", "PDSCHDemapperLLRScaling/v1", ...
    "Convention", "post_equalization_variance_only", ...
    "NoiseVarianceConvention", "post_equalized_symbol_variance_passed_to_nrPDSCHDecode", ...
    "Source", source, ...
    "NoiseVarianceSource", noiseSource, ...
    "OutputDomain", "rate_matched_codeword_llr", ...
    "Applied", false, ...
    "Status", "not_applied_post_equalization_variance_convention", ...
    "Reason", "nrPDSCHDecode already consumed the effective post-equalization noise variance; applying CSI again would double-count reliability.", ...
    "InputKind", "not_used_for_second_weighting", ...
    "NoSecondCSIWeighting", true, ...
    "DemapperOutputAlreadyWeightedByNoiseVariance", true, ...
    "Modulation", char(string(modScheme)), ...
    "LLRCount", double(numel(llrIn)), ...
    "NoiseVariance", double(nVarForDecode), ...
    "PostEqSINR_dB", double(postEqSINR_dB), ...
    "RawCSIMedian", double(rawMedian), ...
    "WeightMedianBeforeNormalization", 1, ...
    "NormalizationScale", 1, ...
    "InputLLRMeanAbs", double(inputMean), ...
    "OutputLLRMeanAbs", double(inputMean));
end

function mapping = localFinalizePDSCHRxCodewordLayerContract(mapping, llrCell, eqSym)
counts = double(cellfun(@numel, llrCell));
expected = double(mapping.RateMatchedBitCountPerCodeword);
if numel(counts) ~= double(mapping.NumCodewords)
    error("sixgr:phy:dl:PDSCHDecodedCodewordCountMismatch", ...
        "PDSCH RX finalized %d codeword LLR stream(s), but the mapping contract expects %d.", ...
        numel(counts), round(double(mapping.NumCodewords)));
end
if any(counts(:).' ~= expected(:).')
    error("sixgr:phy:dl:PDSCHCodewordLLRCountContract", ...
        "PDSCH demapper LLR counts %s do not match per-codeword G %s.", mat2str(counts), mat2str(expected));
end
if isempty(eqSym)
    nCols = 0;
else
    if isvector(eqSym)
        nCols = 1;
    else
        nCols = size(eqSym, 2);
    end
end
mapping.ActualNumCodewords = double(numel(llrCell));
mapping.DemapperLLRCountPerCodeword = double(counts);
mapping.TotalDemapperLLRCount = double(sum(counts));
mapping.ActualLayerColumns = double(nCols);
mapping.ActualLayersEqualGrantLayers = logical(nCols == double(mapping.NumLayers));
end

function decode = localDecodePDSCHCodewords(llrCell, codingLayouts, trBlkSize, targetCodeRate, rv, modulationPerCodeword, numLayers, cfg, maxIter, alg, softBuffers, softLayouts)
nCodewords = numel(llrCell);
recLLRCell = cell(1, nCodewords);
recLLRBatchCell = cell(1, nCodewords);
rateRecoverInfoCell = cell(1, nCodewords);
harqInfoCell = cell(1, nCodewords);
harqSoftBufferCell = cell(1, nCodewords);
decodedCodeBlocksCell = cell(1, nCodewords);
ldpcSegCell = cell(1, nCodewords);
tbCrcCell = cell(1, nCodewords);
tbCell = cell(1, nCodewords);
crcPass = false(1, nCodewords);
crcError = true(1, nCodewords);
cbCrcCell = cell(1, nCodewords);
activeIterCell = cell(1, nCodewords);
parityCell = cell(1, nCodewords);
lineageCell = cell(1, nCodewords);
decodeLatency = zeros(1, nCodewords);
useMexAny = false;

for cw = 1:nCodewords
    layout = codingLayouts{cw};
    ldpcSeg = localLDPCSegmentationFromLayout(layout);
    [recLLR, rateRecoverInfo] = sixgr.phy.phycode.rateRecoverLDPC( ...
        llrCell{cw}, trBlkSize(cw), targetCodeRate(cw), rv(cw), modulationPerCodeword{cw}, ...
        double(layout.NumLayers), ldpcSeg.NumCodeBlocks, [], "CodingLayout", layout);
    [priorLLR, priorLayout] = localSelectHARQSoftBuffer(softBuffers, softLayouts, cw);
    [recLLR, harqInfo] = sixgr.phy.harq.combineSoftLLR(recLLR, priorLLR, ...
        "CurrentLayout", layout, "PriorLayout", priorLayout);
    recLLRBatch = localEnsureLLRBatch(recLLR);
    [decCbs, actIter, parity, usedMex, latency] = localDecodeLDPCCodeBlocks(recLLRBatch, double(layout.BaseGraph), maxIter, alg, cfg);
    B = double(ldpcSeg.TransportBlockLenWithCRC);
    [tbCrcRx, cbCrcErr] = sixgr.phy.tb.desegmentLDPC(decCbs, double(layout.BaseGraph), B);
    [tbRx, ok, err] = sixgr.phy.tb.checkCRC(tbCrcRx, char(string(layout.TBCRCType)));

    recLLRCell{cw} = recLLR;
    recLLRBatchCell{cw} = recLLRBatch;
    rateRecoverInfoCell{cw} = rateRecoverInfo;
    harqInfoCell{cw} = harqInfo;
    harqSoftBufferCell{cw} = sixgr.util.structGet(harqInfo, "SoftBuffer", struct());
    decodedCodeBlocksCell{cw} = decCbs;
    ldpcSegCell{cw} = ldpcSeg;
    tbCrcCell{cw} = tbCrcRx;
    tbCell{cw} = int8(tbRx(:));
    crcPass(cw) = logical(ok);
    crcError(cw) = logical(err);
    cbCrcCell{cw} = cbCrcErr(:).';
    activeIterCell{cw} = actIter(:).';
    parityCell{cw} = parity(:).';
    lineageCell{cw} = localBuildPDSCHDecodedBitLineage(cw, llrCell{cw}, recLLR, decCbs, ...
        layout, trBlkSize(cw), B, ok);
    decodeLatency(cw) = latency;
    useMexAny = useMexAny || logical(usedMex);
end

decode = struct();
decode.RecLLRCell = recLLRCell;
decode.RecLLRBatchCell = recLLRBatchCell;
decode.RateRecoverInfoCell = rateRecoverInfoCell;
decode.HARQCombiningInfoCell = harqInfoCell;
decode.HARQSoftBufferCell = harqSoftBufferCell;
decode.DecodedCodeBlocksCell = decodedCodeBlocksCell;
decode.LDPCSegmentationCell = ldpcSegCell;
decode.TransportBlockCRCPerCodeword = tbCrcCell;
decode.TransportBlockCell = tbCell;
decode.CRCPassPerCodeword = logical(crcPass);
decode.CRCErrorPerCodeword = logical(crcError);
decode.CodeBlockCRCErrorPerCodeword = cbCrcCell;
decode.CodeBlockCRCError = [cbCrcCell{:}];
decode.ActiveIterations = [activeIterCell{:}];
decode.ParityChecks = [parityCell{:}];
decode.DecodedBitLineageCell = lineageCell;
decode.DecodeLatency_s = double(sum(decodeLatency));
decode.DecodeLatencyPerCodeword_s = double(decodeLatency);
decode.UseMexLDPC = logical(useMexAny);
decode.TransportBlockLenWithCRCPerCodeword = double(cellfun(@(x) double(x.TransportBlockLenWithCRC), ldpcSegCell));
decode.HARQCombiningSummary = localSummarizeHARQCombining(harqInfoCell);
end

function lineage = localBuildPDSCHDecodedBitLineage(codewordIndex, demapperLLR, recLLR, decCbs, layout, trBlkSize, transportBlockLenWithCRC, crcPass)
lineage = struct( ...
    "ContractVersion", "PDSCHDecodedBitLineage/v1", ...
    "CodewordIndex", double(codewordIndex), ...
    "DemapperDomain", "rate_matched_codeword_llr", ...
    "DemapperLLRCount", double(numel(demapperLLR)), ...
    "RateMatchedBitCount", double(layout.RateMatchedBitCount), ...
    "RateRecoveryInputDomain", "rate_matched_codeword_llr", ...
    "RateRecoveryOutputDomain", "mother_code_llr_by_code_block", ...
    "RateRecoveredRows", double(size(recLLR, 1)), ...
    "RateRecoveredCodeBlocks", double(size(recLLR, 2)), ...
    "MotherCodeLength", double(layout.MotherCodeLength), ...
    "NumCodeBlocks", double(layout.NumCodeBlocks), ...
    "LDPCDecodedRows", double(size(decCbs, 1)), ...
    "LDPCDecodedCodeBlocks", double(size(decCbs, 2)), ...
    "TransportBlockSize", double(trBlkSize), ...
    "TransportBlockLengthWithCRC", double(transportBlockLenWithCRC), ...
    "TBCRCType", char(string(layout.TBCRCType)), ...
    "CRCPass", logical(crcPass), ...
    "RateMatchSignature", char(string(layout.RateMatchSignature)), ...
    "CombineSignature", char(string(layout.CombineSignature)));
end

function [decCbs, actIter, parity, useMexLDPC, decodeLatency_s] = localDecodeLDPCCodeBlocks(recLLRBatch, bgn, maxIter, alg, cfg)
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
end

function [priorLLR, priorLayout] = localSelectHARQSoftBuffer(softBuffers, softLayouts, codewordIndex)
priorLLR = [];
priorLayout = struct();
if isempty(softBuffers)
    return;
end
if iscell(softBuffers)
    if numel(softBuffers) >= codewordIndex
        priorLLR = softBuffers{codewordIndex};
    end
elseif isstruct(softBuffers)
    if isfield(softBuffers, "LLRSum") || isfield(softBuffers, "SoftBuffer")
        priorLLR = softBuffers;
        priorLayout = sixgr.util.structGet(softBuffers, "CodingLayout", struct());
        return;
    end
    softCell = sixgr.util.structGet(softBuffers, "SoftBufferCell", []);
    if iscell(softCell) && numel(softCell) >= codewordIndex
        priorLLR = softCell{codewordIndex};
        priorLayout = sixgr.util.structGet(priorLLR, "CodingLayout", struct());
        return;
    end
    raw = sixgr.util.structGet(softBuffers, "LLRCell", []);
    if isempty(raw)
        raw = sixgr.util.structGet(softBuffers, "RateRecoveredLLRCell", []);
    end
    if iscell(raw) && numel(raw) >= codewordIndex
        priorLLR = raw{codewordIndex};
    else
        priorLLR = sixgr.util.structGet(softBuffers, "LLR", sixgr.util.structGet(softBuffers, "RateRecoveredLLR", []));
    end
else
    priorLLR = softBuffers;
end

if isempty(softLayouts)
    return;
end
if iscell(softLayouts)
    if numel(softLayouts) >= codewordIndex
        priorLayout = softLayouts{codewordIndex};
    end
elseif isstruct(softLayouts)
    raw = sixgr.util.structGet(softLayouts, "CodingLayouts", []);
    if iscell(raw) && numel(raw) >= codewordIndex
        priorLayout = raw{codewordIndex};
    elseif numel(softLayouts) >= codewordIndex && isfield(softLayouts(codewordIndex), "RateMatchPositionMap")
        priorLayout = softLayouts(codewordIndex);
    else
        priorLayout = softLayouts;
    end
end
end

function summary = localSummarizeHARQCombining(infoCell)
applied = false(1, numel(infoCell));
cur = zeros(1, numel(infoCell));
prior = zeros(1, numel(infoCell));
reasons = strings(1, numel(infoCell));
for c = 1:numel(infoCell)
    applied(c) = logical(sixgr.util.structGet(infoCell{c}, "Applied", false));
    cur(c) = double(sixgr.util.structGet(infoCell{c}, "CurrentNumel", NaN));
    prior(c) = double(sixgr.util.structGet(infoCell{c}, "PriorNumel", NaN));
    reasons(c) = string(sixgr.util.structGet(infoCell{c}, "Reason", ""));
end
summary = struct( ...
    "Applied", any(applied), ...
    "AppliedPerCodeword", logical(applied), ...
    "PositionAware", any(cellfun(@(x) logical(sixgr.util.structGet(x, "PositionAware", false)), infoCell)), ...
    "Reason", char(strjoin(reasons, "|")), ...
    "CurrentNumel", double(sum(cur(isfinite(cur)))), ...
    "PriorNumel", double(sum(prior(isfinite(prior)))), ...
    "OverlapPositionCount", double(sum(cellfun(@(x) double(sixgr.util.structGet(x, "OverlapPositionCount", 0)), infoCell))), ...
    "SoftBufferCell", {cellfun(@(x) sixgr.util.structGet(x, "SoftBuffer", struct()), infoCell, "UniformOutput", false)});
if numel(summary.SoftBufferCell) == 1
    summary.SoftBuffer = summary.SoftBufferCell{1};
else
    summary.SoftBuffer = struct("ContractVersion", "HARQSoftBufferCollection/v1", ...
        "SoftBufferCell", {summary.SoftBufferCell});
end
end

function nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers)
nCodewords = 1 + (double(nLayers) > 4);
raw = localObjectValue(pdsch, "NumCodewords", []);
if ~isempty(raw)
    nCodewords = double(raw);
end
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1 && abs(nCodewords - round(nCodewords)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadCodewordCount", "PDSCH NumCodewords must be a positive integer scalar.");
end
nCodewords = round(nCodewords);
end

function localAssertPDSCHCodewordLayerScope(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nLayers < 1 || nLayers > 8
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH supports ranks 1-8 in this truth path. Requested NumLayers=%d.", nLayers);
end
expected = 1 + double(nLayers > 4);
if nCodewords ~= expected
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d requires NumCodewords=%d by TS 38.211 codeword-to-layer mapping. Requested %d.", ...
        nLayers, expected, nCodewords);
end
end

function counts = localLayerCountPerCodeword(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nCodewords == 1
    counts = double(nLayers);
    return;
end
switch nLayers
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
    otherwise
        error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
            "Two-codeword PDSCH mapping is defined here only for ranks 5-8. Requested rank %d.", nLayers);
end
if numel(counts) ~= nCodewords
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d maps to %d codeword layer groups, not %d.", nLayers, numel(counts), nCodewords);
end
end

function [cwByLayer, layerInCw] = localCodewordLayerIndexMap(layerCountPerCodeword)
cwByLayer = zeros(1, sum(layerCountPerCodeword));
layerInCw = zeros(1, sum(layerCountPerCodeword));
pos = 1;
for c = 1:numel(layerCountPerCodeword)
    n = double(layerCountPerCodeword(c));
    idx = pos:(pos + n - 1);
    cwByLayer(idx) = c;
    layerInCw(idx) = 1:n;
    pos = pos + n;
end
end

function values = localExpandPerCodewordDouble(values, nCodewords, name)
values = double(values(:).');
if numel(values) == 1 && nCodewords > 1
    values = repmat(values, 1, nCodewords);
end
if numel(values) ~= nCodewords || any(~isfinite(values))
    error("sixgr:phy:dl:PDSCHBadPerCodewordVector", ...
        "%s must have one value or exactly NumCodewords=%d values.", char(string(name)), nCodewords);
end
end

function values = localExpandPerCodewordInteger(values, nCodewords, name)
values = localExpandPerCodewordDouble(values, nCodewords, name);
if any(abs(values - round(values)) > 1e-9)
    error("sixgr:phy:dl:PDSCHBadPerCodewordVector", ...
        "%s must contain integer values.", char(string(name)));
end
values = round(values);
end

function rv = localExpandPerCodewordRV(rv, nCodewords)
rv = localExpandPerCodewordInteger(rv, nCodewords, "PDSCH RV");
if any(rv < 0 | rv > 3)
    error("sixgr:phy:dl:PDSCHBadRV", "PDSCH RV must be in [0,3].");
end
end

function mods = localPDSCHModulationPerCodeword(pdsch, nCodewords)
mods = localNormalizeModulationCell(localObjectValue(pdsch, "Modulation", "QPSK"), nCodewords);
end

function mods = localNormalizeModulationCell(raw, nCodewords)
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    tokens = "QPSK";
end
if numel(tokens) == 1 && nCodewords > 1
    tokens = repmat(tokens, 1, nCodewords);
elseif numel(tokens) < nCodewords
    tokens(end+1:nCodewords) = tokens(end);
elseif numel(tokens) > nCodewords
    tokens = tokens(1:nCodewords);
end
mods = cellstr(tokens);
end

function text = localModulationText(raw)
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    text = "";
else
    text = strjoin(tokens, "|");
end
end

function csiCell = localDemapCSIByCodeword(csi, mapping)
nCodewords = double(mapping.NumCodewords);
csiCell = cell(1, nCodewords);
for c = 1:nCodewords
    csiCell{c} = [];
end
if isempty(csi)
    return;
end
try
    out = nrLayerDemap(csi);
    if iscell(out) && numel(out) == nCodewords
        csiCell = reshape(out, 1, []);
        return;
    elseif ~iscell(out) && nCodewords == 1
        csiCell{1} = out;
        return;
    end
catch
end
if nCodewords == 1
    csiCell{1} = csi;
end
end

function cells = localNormalizeCodingLayoutCell(layoutIn, nCodewords)
cells = {};
if isempty(layoutIn)
    return;
end
if iscell(layoutIn)
    cells = reshape(layoutIn, 1, []);
elseif isstruct(layoutIn) && numel(layoutIn) > 1
    cells = num2cell(layoutIn(:).');
elseif isstruct(layoutIn) && isfield(layoutIn, "CodingLayouts") && iscell(layoutIn.CodingLayouts)
    cells = reshape(layoutIn.CodingLayouts, 1, []);
elseif isstruct(layoutIn) && ~isempty(fieldnames(layoutIn)) && isfield(layoutIn, "RateMatchPositionMap")
    cells = {layoutIn};
else
    cells = {};
end
if isempty(cells)
    return;
end
if numel(cells) == 1 && nCodewords > 1
    if isfield(cells{1}, "RateMatchPositionMap")
        cells = {};
        return;
    end
end
if numel(cells) ~= nCodewords
    cells = {};
end
end

function value = localPositiveIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadInteger", "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
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

function layouts = localResolveRxCodingLayouts(layoutIn, phyGrant, direction, trBlkSize, targetCodeRate, rv, modulationPerCodeword, numLayers, rateMatchedBits)
nCodewords = numel(rateMatchedBits);
layerCounts = localLayerCountPerCodeword(double(numLayers), nCodewords);
provided = localNormalizeCodingLayoutCell(layoutIn, nCodewords);
if isempty(provided)
    grantLayout = sixgr.util.structGet(phyGrant, "CodingLayouts", []);
    if isempty(grantLayout)
        grantLayout = sixgr.util.structGet(phyGrant, "CodingLayout.CodingLayouts", []);
    end
    provided = localNormalizeCodingLayoutCell(grantLayout, nCodewords);
    if isempty(provided)
        grantSingle = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
        provided = localNormalizeCodingLayoutCell(grantSingle, nCodewords);
    end
end
layouts = cell(1, nCodewords);
for c = 1:nCodewords
    if ~isempty(provided) && isfield(provided{c}, "RateMatchPositionMap")
        layout = provided{c};
        localAssertCodingLayoutMatches(layout, trBlkSize(c), rv(c), modulationPerCodeword{c}, layerCounts(c), rateMatchedBits(c));
    else
        layout = sixgr.phy.phycode.resolveCodingLayout( ...
            "Direction", direction, ...
            "TransportBlockSize", trBlkSize(c), ...
            "TargetCodeRate", targetCodeRate(c), ...
            "RV", rv(c), ...
            "Modulation", modulationPerCodeword{c}, ...
            "NumLayers", layerCounts(c), ...
            "RateMatchedBitCount", rateMatchedBits(c));
    end
    layout.CodewordIndex = uint8(c);
    layout.NumCodewords = uint8(nCodewords);
    layout.PDSCHNumLayers = uint8(numLayers);
    layout.CodewordLayerCount = uint8(layerCounts(c));
    layout.CodewordLayerCountPerCodeword = uint8(layerCounts);
    layouts{c} = layout;
end
end

function localAssertCodingLayoutMatches(layout, trBlkSize, rv, modulation, numLayers, rateMatchedBits)
if double(layout.TransportBlockSize) ~= double(trBlkSize) || ...
        double(layout.RV) ~= double(rv) || ...
        ~strcmpi(char(string(layout.Modulation)), char(string(modulation))) || ...
        double(layout.NumLayers) ~= double(numLayers) || ...
        double(layout.RateMatchedBitCount) ~= double(rateMatchedBits)
    error("sixgr:phy:dl:PDSCHCodingLayoutMismatch", ...
        "Supplied CodingLayout does not match PDSCH RX grant dimensions.");
end
end

function seg = localLDPCSegmentationFromLayout(layout)
seg = struct( ...
    "TransportBlockLenWithCRC", double(layout.TransportBlockLengthWithCRC), ...
    "NumCodeBlocks", double(layout.NumCodeBlocks), ...
    "CodeBlockLength", double(layout.CodeBlockLength), ...
    "SegmentationInfo", sixgr.util.structGet(layout, "Segmentation", struct()));
end

function E = localRateMatchedBitCountFromInfo(info)
E = double(sixgr.util.structGet(info, "GPerCodeword", ...
    sixgr.util.structGet(info, "CodedBitCountGPerCodeword", ...
    sixgr.util.structGet(info, "G", NaN))));
E = E(:).';
if isempty(E) || any(~isfinite(E) | E <= 0 | abs(E - round(E)) > 1e-9)
    error("sixgr:phy:dl:PDSCHCodingLayoutMissingG", ...
        "PDSCH RX requires an integer rate-matched bit count to resolve CodingLayout.");
end
E = round(E);
end

function localValidateSupportedCodewordScope(cfg, pdsch)
nLayers = 1;
if isempty(pdsch)
    nLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
    nCodewords = double(sixgr.util.structGet(cfg, 'phy.pdsch.numCodewords', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.NumCodewords', 1 + (nLayers > 4))));
else
    try
        nLayers = double(pdsch.NumLayers);
    catch
        nLayers = 1;
    end
    nCodewords = double(localObjectValue(pdsch, "NumCodewords", 1 + (nLayers > 4)));
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = round(nLayers);
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1)
    nCodewords = 1 + (nLayers > 4);
end
nCodewords = round(nCodewords);
localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);
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
        char(localModulationText(pdsch.Modulation)), round(double(pdsch.NumLayers)));
end
end

function nrePerPRB = localResolveNREFromInfo(info, nPRB, modStr, nLayers)
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
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
