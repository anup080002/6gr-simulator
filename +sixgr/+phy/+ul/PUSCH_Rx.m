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
%     "PHYGrant"    : frozen canonical grant dimensional contract
%     "ReceiveCombiningMatrix": frozen Nrx-by-Nout MU receive projection
%     "ReceiveCombiningMatrixSHA256": expected digest of that projection
%
%   CFG.phy.pusch.dmrs.dataToDMRSEPREDifference_dB controls the PUSCH
%   data-EPRE minus DM-RS-EPRE difference. The default is 0 dB. The
%   normative -3 dB token maps to exact beta=sqrt(2), matching the
%   transmitter and retaining configured versus realized dB provenance.
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

sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.ul.PUSCH_Rx", ...
    "PUSCH", "UL", struct("Stage","RX"));

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCHIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('TransportBlockSize', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x) && all(x>0)));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x) && all(x>0 & x<1)));
ip.addParameter('RV', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x) && all(x>=0 & x<=3)));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('ConfiguredNoiseVariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ConfiguredNoiseVarianceSource', 'configured_awgn_derivation', @(x) ischar(x) || isstring(x));
ip.addParameter('StrictNoiseVarianceRequired', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('ExpectedUCIPayload', [], @(x) isempty(x) || isa(x, "sixgr.phy.ul.pusch.PUSCHUCIPayload"));
ip.addParameter('InitialIMCSPerCodeword', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('HARQSoftBufferLLR', [], @(x) isempty(x) || isnumeric(x) || isstruct(x));
ip.addParameter('HARQSoftBufferLayout', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('CodingLayout', struct(), @(x) isempty(x) || isstruct(x) || iscell(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ReceiverTrackingState', [], @(x) isempty(x) || isstruct(x));
ip.addParameter('InterferenceContributionTensor', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('InterferenceContributionSource', "", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('InterferenceContributionDomain', "receiver_sample_waveform_pre_noise", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('InterferenceCovariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('InterferenceCovarianceSource', "", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('InterferenceCovarianceIncludesNoise', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ReceiveCombiningMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ReceiveCombiningMatrixSHA256', "", @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('TrueChannel', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('OracleTestMode', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('ExecutionProfile', "data_pusch", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
executionProfile = lower(strtrim(string(opt.ExecutionProfile)));
sixgr.config.assertRuntimeFeatureUse(cfg, "cfo_correction", ...
    sixgr.util.structGet(cfg, "phy.rx.cfoCorrectionEnabled", false), ...
    "PUSCH_Rx.cfoCorrection");
sixgr.config.assertRuntimeFeatureUse(cfg, "iq_imbalance_correction", ...
    sixgr.util.structGet(cfg, "phy.rx.iqImbalanceCorrectionEnabled", false), ...
    "PUSCH_Rx.iqImbalanceCorrection");
phyGrant = opt.PHYGrant;
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "pusch_rx_entry");
    cfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, phyGrant);
end
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
sixgr.config.assertRuntimeFeatureUse(cfg, ...
    localProcedureFeature("ptrs", executionProfile), ...
    logical(localObjectValue(pusch, "EnablePTRS", false)), ...
    "PUSCH_Rx." + executionProfile + ".nrPUSCHConfig.EnablePTRS");
sixgr.config.assertRuntimeFeatureUse(cfg, ...
    localProcedureFeature("transform_precoding", executionProfile), ...
    logical(localObjectValue(pusch, "TransformPrecoding", false)), ...
    "PUSCH_Rx." + executionProfile + ".nrPUSCHConfig.TransformPrecoding");
sixgr.config.assertRuntimeFeatureUse(cfg, "ptrs_cpe_correction", ...
    sixgr.util.structGet(cfg, "phy.pusch.ptrs.enableCPECorrection", false), ...
    "PUSCH_Rx.ptrsCPECorrection");

% Rx params
nCodewords = double(pusch.NumCodewords);
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pusch.rv', []));
end
rv = double(rv(:).');
if numel(rv) ~= nCodewords || any(~isfinite(rv) | rv ~= fix(rv) | rv < 0 | rv > 3)
    error("sixgr:phy:ul:PUSCHBadRV", ...
        "PUSCH RX requires one integer RV in [0,3] per codeword.");
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pusch.codeRate', []));
end
targetCodeRate = double(targetCodeRate(:).');
if numel(targetCodeRate) ~= nCodewords || ...
        any(~isfinite(targetCodeRate) | targetCodeRate <= 0 | targetCodeRate >= 1)
    error("sixgr:phy:ul:PUSCHBadCodeRate", ...
        "PUSCH RX requires one finite TargetCodeRate in (0,1) per codeword.");
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
expectedUCIPayload = opt.ExpectedUCIPayload;
if isempty(expectedUCIPayload)
    expectedUCIPayload = sixgr.phy.ul.pusch.PUSCHUCIPayload();
end
initialIMCS = opt.InitialIMCSPerCodeword;
if isempty(initialIMCS)
    initialIMCS = double(sixgr.util.structGet(phyGrant, ...
        "CodingLayout.InitialMCSIndex", ...
        sixgr.util.structGet(phyGrant, "CodingLayout.MCSIndex", 0)));
end

% Determine TB size
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = localResolvePUSCHXOverhead(pusch, cfg);
    nPRB = numel(pusch.PRBSet);
    nrePerPRB = localResolvePUSCHNREPerPRBOrError(carrier, pusch, puschInfo, nPRB);
    trBlkSize = nrTBS(pusch.Modulation, pusch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
end
trBlkSize = double(trBlkSize(:).');
if numel(trBlkSize) ~= nCodewords || ...
        any(~isfinite(trBlkSize) | trBlkSize <= 0 | trBlkSize ~= fix(trBlkSize))
    error("sixgr:phy:ul:PUSCHBadTransportBlockSize", ...
        "PUSCH RX requires one positive integer transport block size per codeword.");
end

% Canonical coding layout. For UCI-on-PUSCH the LDPC rate-recovery input is
% GULSCH, not the total PUSCH coded-bit count G.
ulschRateMatchedBitCount = localResolveRxULSCHBitCount( ...
    pusch, targetCodeRate, trBlkSize, puschInfo, expectedUCIPayload);
codingLayouts = localResolveRxCodingLayouts(opt.CodingLayout, phyGrant, "UL", ...
    trBlkSize, targetCodeRate, rv, pusch.Modulation, pusch.NumLayers, ...
    ulschRateMatchedBitCount);
codingLayout = codingLayouts{1};
bgn = double(cellfun(@(x) x.BaseGraph, codingLayouts));
tbCRCType = string(cellfun(@(x) string(x.TBCRCType), codingLayouts));
tbCRCLen = double(cellfun(@(x) x.TBCRCLength, codingLayouts));
ldpcSeg = localLDPCSegmentationFromLayout(codingLayout);

% DMRS
[dmrsInd, dmrsSym, dmrsInfo] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);
[dmrsSym, dmrsPowerInfo] = localApplyPUSCHDMRSEPREDifference(dmrsSym, cfg);
dmrsInfo.DataToDMRSEPREDifference_dB = double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
dmrsInfo.DMRSPowerBoost_dB = double(dmrsPowerInfo.DMRSPowerBoost_dB);
dmrsInfo.ConfiguredDMRSPowerBoost_dB = double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
dmrsInfo.RealizedDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
dmrsInfo.DMRSAmplitudeScale = double(dmrsPowerInfo.DMRSAmplitudeScale);
dmrsInfo.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
dmrsInfo.EPREConfigSource = char(string(dmrsPowerInfo.Source));
dmrsInfo.EPREScalePolicy = char(string(dmrsPowerInfo.ScalePolicy));
[rxPUSCH, rxPUSCHInd, chEstDMRSInd, chEstDMRSSym, effectiveRxInfo] = ...
    localResolvePUSCHEffectiveRxReference(carrier, pusch, puschInd, dmrsInd, dmrsSym);
if logical(effectiveRxInfo.Applied)
    [chEstDMRSSym, ~] = localApplyPUSCHDMRSEPREDifference(chEstDMRSSym, cfg);
end
useFastAWGNPath = logical(opt.FastAWGNPath);
strictMode = logical(sixgr.util.structGet(cfg, 'run.strictMode', false));
channelModelToken = localResolveEstimatorChannelModel(cfg);
numTxPorts = localExpectedTxPorts(pusch);
[rxWaveform, fastAWGNColumnInfo] = localTrimInactiveFastAWGNColumns( ...
    rxWaveform, channelModelToken, numTxPorts, useFastAWGNPath);
[rxWaveform, opt, receiveCombinerInfo] = localApplyScheduledReceiveCombiner( ...
    rxWaveform, opt, phyGrant);
localValidateFastScalarShortcut(channelModelToken, numTxPorts, ...
    fastAWGNColumnInfo.ActiveColumnCount, useFastAWGNPath, "PUSCH_Rx");
phyGrantContract = struct();
if hasPHYGrant
    phyGrantContract = sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pusch_rx_after_config", ...
        "PUSCH", pusch);
end

% Timing estimate
trackingCorrection = localResolveReceiverTrackingCorrection(opt.ReceiverTrackingState, cfg);
sampleRateHz = localCarrierSampleRateHz(carrier);
knownTimingDelaySamples = localResolveKnownTimingDelaySamples(cfg, trackingCorrection, sampleRateHz);
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
runtimeAlignedTimingBypass = localRuntimeAlignedTimingBypass(cfg);
% The link wrapper sets RuntimeWaveformSampleAligned only after applying
% the materialized channel and its exact sample trim.  That boundary owns
% alignment for both FDD and TDD.  A receiver-side RS observation remains
% valuable evidence, but it must not be applied a second time unless YAML
% explicitly injects a timing offset (which disables this bypass).
if runtimeAlignedTimingBypass
    timingEstimateSource = "runtime_aligned_waveform_no_timing_reacquisition";
    trackingCorrection.TimingCorrectionApplied = false;
elseif logical(trackingCorrection.TimingEstimateAvailable) && isfinite(double(trackingCorrection.TimingEstimate_samples))
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

timingEstimateForCorrection = rawTimingEstimate;
if timingEstimateUsed && isfinite(rawTimingEstimate)
    knownDelayForCorrection = double(knownTimingDelaySamples);
    if isfinite(knownDelayForCorrection) && rawTimingEstimate > 0 && knownDelayForCorrection > rawTimingEstimate
        knownDelayForCorrection = rawTimingEstimate;
    end
    timingEstimateForCorrection = rawTimingEstimate - knownDelayForCorrection;
end
timingResolution = sixgr.phy.sync.resolveTimingApplication(timingEstimateForCorrection, ...
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
    if ~logical(trackingCorrection.CFOEstimateAvailable) && any(cfoEstimationMethod == ["cyclic_prefix", "cp"])
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
        trackingCorrection.Source = char(string(cfoEstimationMethod));
        trackingCorrection.NAReason = "cfo_estimate_unavailable_or_disabled_by_method";
    end
end
[rxGrid, ofdmInfo, trackingCorrection] = localApplyEstimatedCFOAndRedemodulate( ...
    carrier, rxWaveform, sampleRateHz, rxGrid, ofdmInfo, ...
    trackingCorrection, cfg, dmrsInd, dmrsSym);
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
        "Method", "explicit_unit_flat_awgn_validation", ...
        "EngineUsed", "unit-flat-shortcut", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true, ...
        "FastAWGNOriginalWaveformColumns", double(fastAWGNColumnInfo.OriginalColumnCount), ...
        "FastAWGNActiveWaveformColumns", double(fastAWGNColumnInfo.ActiveColumnCount), ...
        "FastAWGNInactiveColumnTrimmed", logical(fastAWGNColumnInfo.Trimmed));
else
    [Hest, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, chEstDMRSInd, chEstDMRSSym, ...
        "CDMLengths", sixgr.util.structGet(dmrsInfo, "CDMLengths", []), ...
        "UseFastMex", useFastChEstMex, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", double(effectiveRxInfo.EffectiveTxPorts), ...
        "Method", localResolveChannelEstimationMethod(cfg), ...
        "TrueChannel", opt.TrueChannel, ...
        "OracleTestMode", logical(opt.OracleTestMode), ...
        "Config", cfg, ...
        "ContextLabel", "PUSCH_Rx");
end

% Noise variance
noiseCandidate = opt.NoiseVar;
noiseSource = "runtime_metadata";
noiseTransformInfo = struct( ...
    "InputDomain", "grid", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "runtime_channel_estimate_grid_domain");
configuredNoiseTransformInfo = struct( ...
    "InputDomain", "time", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "not_requested");
if isempty(noiseCandidate)
    % nrChannelEstimate returns grid-domain noise variance.
    noiseCandidate = nVarEst;
    noiseSource = "runtime_channel_estimate";
else
    domain = lower(strtrim(char(string(opt.NoiseVarDomain))));
    [noiseCandidate, noiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        noiseCandidate, ofdmInfo, ...
        "InputDomain", domain, ...
        "Source", noiseSource);
end
configuredNoiseVariance = opt.ConfiguredNoiseVariance;
if ~isempty(configuredNoiseVariance)
    [configuredNoiseVariance, configuredNoiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        configuredNoiseVariance, ofdmInfo, ...
        "InputDomain", "time", ...
        "Source", opt.ConfiguredNoiseVarianceSource);
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
    rx.DMRSEPREDifference = dmrsPowerInfo;
    rx.DMRSDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
    rx.DMRSPowerBoost_dB = double(dmrsPowerInfo.DMRSPowerBoost_dB);
    rx.DMRSConfiguredPowerBoost_dB = double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
    rx.DMRSRealizedDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
    rx.DMRSAmplitudeScale = double(dmrsPowerInfo.DMRSAmplitudeScale);
    rx.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
    info.DMRS = dmrsInfo;
    info.DMRSEPREDifference = dmrsPowerInfo;
    rx = localAnnotateReceiveCombiner(rx, receiveCombinerInfo);
    info.ReceiveCombiner = receiveCombinerInfo;
    return;
end

% Extract resources in the effective layer domain for codebook PUSCH. The
% DM-RS is precoded by the same TPMI as data, so estimating eight
% independent physical-port channels from five layer pilots is
% underdetermined. The non-codebook clone exposes the exact effective
% layer references without using transmitted data or true channel state.
[rxSym, hestSym] = nrExtractResources(rxPUSCHInd, rxGrid, Hest);
hestSymForSINR = hestSym;
sinrProjectionInfo = struct( ...
    "Applied", logical(effectiveRxInfo.Applied), ...
    "Status", string(effectiveRxInfo.Status), ...
    "TPMI", double(effectiveRxInfo.TPMI));

% Equalize
[equalizerAlg, equalizerRequested] = localResolveEqualizerAlgorithm(cfg, "UL");
RIncludesNoise = false;
if equalizerAlg == "IRC"
    [Rint, rintInfo, RIncludesNoise] = localResolvePUSCHInterferenceCovariance(opt, carrier, ...
        rxPUSCHInd, timingResolution.AppliedCorrection_samples, nVar, rxGrid, Hest, chEstDMRSInd, chEstDMRSSym);
else
    Rint = [];
    rintInfo = struct("Available", false, "Source", "irc_not_requested", ...
        "Status", "not_applicable", "NAReason", "equalizer_algorithm_is_not_irc", ...
        "CovarianceIncludesNoise", false, "Domain", "not_applicable");
end
if equalizerAlg == "IRC" && ~logical(rintInfo.Available)
    error("sixgr:mimo:MissingInterferenceCovariance", ...
        "PUSCH strict IRC requested, but no qualified covariance is available (%s).", ...
        char(string(sixgr.util.structGet(rintInfo, "NAReason", "unknown"))));
end
[eqSym, csi, equalizerInfo] = sixgr.phy.rx.mimoDetect(rxSym, hestSym, nVar, ...
    "Algorithm", equalizerAlg, "Rint", Rint, "RIncludesNoise", RIncludesNoise);
[ptrsInd, ptrsSym, ptrsInfo] = localResolvePUSCHPTRS(carrier, pusch, cfg);
enablePTRSCPECorrection = logical(sixgr.util.structGet(cfg, "phy.pusch.ptrs.enableCPECorrection", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enableCPECorrection", false)));
[eqSym, cpeCorrInfo] = localCorrectEqualizedPUSCHCPEFromPTRS(eqSym, rxPUSCHInd, rxGrid, Hest, ...
    ptrsInd, ptrsSym, carrier, rxPUSCH, nVar, equalizerAlg, Rint, RIncludesNoise, ...
    enablePTRSCPECorrection);
try
    numLayersForSINR = double(pusch.NumLayers);
catch
    numLayersForSINR = min(size(hestSym, 2), max(1, size(hestSym, 3)));
end
equalizerResultForSINR = sixgr.util.structGet(equalizerInfo, "EqualizerResult", struct());
if logical(sinrProjectionInfo.Applied)
    equalizerResultForSINR = struct();
end
try
    [postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo] = sixgr.phy.rx.computePostEqSINR( ...
        hestSymForSINR, nVar, ...
        "Method", char(lower(string(equalizerAlg))), ...
        "Rint", Rint, ...
        "RIncludesNoise", RIncludesNoise, ...
        "EqualizerResult", equalizerResultForSINR, ...
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
csiFromEqualizerResult = sixgr.util.structGet(postEqSINRInfo, "DemapperReliability", []);
if ~isempty(csiFromEqualizerResult)
    csi = csiFromEqualizerResult;
end
pilotPostEqInfo = localEstimatePUSCHDMRSPostEqResidual(rxGrid, Hest, chEstDMRSInd, chEstDMRSSym, ...
    nVar, equalizerAlg, Rint, RIncludesNoise, rxPUSCH);
dmrsResidualBoundEnabled = logical(sixgr.util.structGet(cfg, ...
    "phy.pusch.measurements.dmrsResidualPostEqSINRBoundEnabled", true));
if dmrsResidualBoundEnabled
    [postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo] = localApplyPUSCHDMRSPostEqSINRBound( ...
        postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo, pilotPostEqInfo);
end
[layerEqSym, layerEqInfo] = localResolvePUSCHLayerEqualizedSymbols(eqSym, [], pusch);
decisionPostEqInfo = localEstimatePUSCHDecisionDirectedPostEqResidual(layerEqSym, pusch);
decisionDirectedBoundEnabled = logical(sixgr.util.structGet(cfg, ...
    "phy.pusch.measurements.decisionDirectedPostEqSINRBoundEnabled", true));
if decisionDirectedBoundEnabled
    [postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo] = localApplyPUSCHDMRSPostEqSINRBound( ...
        postEqSINR_dB, postEqSINRPerRE_dB, postEqSINRInfo, decisionPostEqInfo);
end
% Hest was estimated in the effective receive-layer domain.  Use the same
% receiver-only DM-RS reference that produced Hest; the physical-port
% DM-RS matrices are dimensionally incompatible for codebook PUSCH when
% NumAntennaPorts exceeds NumLayers and would double-count pilot ports.
receiverSINR = localReceiverHestSINR(Hest, nVar, cfg, "UL", rxGrid, ...
    chEstDMRSInd, chEstDMRSSym);
[nVarPostEqDiagnostic, nVarPostEqInfo] = sixgr.phy.rx.postEqualizationNoiseVariance(nVar, ...
    "PostEqSINRPerRE_dB", postEqSINRPerRE_dB, ...
    "PostEqSINR_dB", postEqSINR_dB, ...
    "CSI", csi);
if dmrsResidualBoundEnabled
    [nVarPostEqDiagnostic, nVarPostEqInfo] = localApplyPUSCHDMRSPostEqNoiseBound( ...
        nVarPostEqDiagnostic, nVarPostEqInfo, pilotPostEqInfo);
end
if decisionDirectedBoundEnabled
    [nVarPostEqDiagnostic, nVarPostEqInfo] = localApplyPUSCHDMRSPostEqNoiseBound( ...
        nVarPostEqDiagnostic, nVarPostEqInfo, decisionPostEqInfo);
end
[nVarForDecode, nVarDecodeInfo] = localResolvePUSCHDecoderNoiseVariance(nVar, ...
    nVarPostEqDiagnostic, nVarPostEqInfo, cfg);

% Decode PUSCH to codeword LLR.  nrPUSCHDecode consumes layer-domain
% equalized REs for non-codebook PUSCH, while native codebook PUSCH
% consumes the port-domain equalized symbols and applies the codebook-aware
% de-layering internally.
[decoderInputSym, decoderInputInfo] = localResolvePUSCHDecoderInputSymbols(eqSym, layerEqSym, rxPUSCH);
puschRxSym = [];
if ~(isscalar(nVarForDecode) && isfinite(nVarForDecode) && nVarForDecode > 0)
    nVarForDecode = double(nVar);
end
nVarForDecode = double(max(nVarForDecode, eps));
try
    [cwLLR, puschRxSym] = nrPUSCHDecode(carrier, rxPUSCH, decoderInputSym, nVarForDecode);
catch
    cwLLR = nrPUSCHDecode(carrier, rxPUSCH, decoderInputSym, nVarForDecode);
end
if nCodewords == 2
    qamEqSym = layerEqSym;
    qamEqInfo = struct( ...
        "Status", "two_codeword_layer_domain_equalized_symbols", ...
        "Source", "explicit_layer_equalizer_output");
else
    [qamEqSym, qamEqInfo] = localResolvePUSCHQAMEqualizedSymbols(puschRxSym, layerEqSym);
end

[cwLLR, cwLLRCell, codewordLLRInfo] = localNormalizePUSCHCodewordLLR(cwLLR, nCodewords);
codewordLayerMapping = localBuildPUSCHRxCodewordLayerContract( ...
    pusch, cwLLRCell, codingLayouts, eqSym);
if nCodewords == 1
    [cwLLR, llrCSIInfo] = localApplyCSIToCodewordLLR(cwLLR, csi, ...
        pusch.Modulation, postEqSINR_dB, nVarForDecode, nVarDecodeInfo);
    cwLLRCell = {cwLLR};
else
    llrCSIInfo = struct( ...
        "Source", "nrPUSCHDecode_native_per_codeword_llr_scaling", ...
        "Convention", "toolbox_demapper_llr_per_codeword", ...
        "NoiseVarianceConvention", "explicit_decoder_noise_variance", ...
        "OutputDomain", "two_ulsch_codeword_llr_cells", ...
        "NoSecondCSIWeighting", true, ...
        "Applied", false, ...
        "Status", "native_high_rank_scaling_retained", ...
        "InputKind", "two_codeword_cell", ...
        "RawCSIMedian", NaN, ...
        "WeightMedianBeforeNormalization", NaN, ...
        "NormalizationScale", 1);
end
[cwLLRForULSCH, uciOnPUSCH] = localDemultiplexTypedUCIFromPUSCH( ...
    localUnwrapSingleCell(cwLLRCell), pusch, targetCodeRate, trBlkSize, ...
    expectedUCIPayload, initialIMCS);

if nCodewords == 2
    decodeTic = tic;
    decoder = nrULSCHDecoder( ...
        "MultipleHARQProcesses", false, ...
        "TargetCodeRate", targetCodeRate, ...
        "TransportBlockLength", trBlkSize, ...
        "LDPCDecodingAlgorithm", alg, ...
        "MaximumLDPCIterationCount", maxIter);
    [tbBitsCell, crcErr] = decoder(cwLLRForULSCH, ...
        pusch.Modulation, pusch.NumLayers, rv);
    decodeLatency_s = toc(decodeTic);
    tbBitsCell = reshape(tbBitsCell, 1, []);
    crcErr = logical(crcErr(:).');
    if numel(tbBitsCell) ~= 2 || numel(crcErr) ~= 2
        error("sixgr:phy:ul:PUSCHDecodedCodewordCountMismatch", ...
            "High-rank UL-SCH decoder did not return exactly two transport blocks.");
    end
    rx = localBuildHighRankPUSCHRx( ...
        tbBitsCell, crcErr, trBlkSize, cwLLRCell, cwLLRForULSCH, ...
        codingLayouts, codewordLayerMapping, codewordLLRInfo, ...
        carrier, pusch, puschInfo, puschInd, puschRxSym, ...
        Hest, estInfo, eqSym, layerEqSym, decoderInputSym, decoderInputInfo, ...
        qamEqSym, qamEqInfo, dmrsInd, dmrsSym, dmrsInfo, dmrsPowerInfo, ...
        ptrsInd, ptrsSym, ptrsInfo, cpeCorrInfo, nVar, nVarForDecode, ...
        noiseStatus, noiseTransformInfo, postEqSINR_dB, postEqSINRInfo, ...
        receiverSINR, timingResolution, rawTimingEstimate, ...
        knownTimingDelaySamples, timingEstimateForCorrection, timingEstimateSource, ...
        decodeLatency_s, maxIter, alg, llrCSIInfo, uciOnPUSCH, ...
        enablePTRSCPECorrection, opt.CompactOutput);
    if hasPHYGrant
        rx.PHYGrant = phyGrant;
        rx.PHYGrantDimensionContract = phyGrantContract;
    end
    rx = localAnnotateReceiveCombiner(rx, receiveCombinerInfo);
    info = struct( ...
        "CarrierInfo", cinfo, ...
        "PUSCHInfo", puschInfo, ...
        "CodingLayouts", {codingLayouts}, ...
        "CodewordLayerMapping", codewordLayerMapping, ...
        "UCIOnPUSCH", uciOnPUSCH, ...
        "ReceiveCombiner", receiveCombinerInfo, ...
        "DecodeLatency_s", decodeLatency_s, ...
        "ExecutionBackend", "nrPUSCHDecode_nrULSCHDecoder_two_codeword_truth");
    return;
end
cwLLRForULSCH = cwLLRForULSCH{1};

% Rate recover (to code blocks)
if numel(cwLLRForULSCH) ~= double(codingLayout.RateMatchedBitCount)
    if ~logical(uciOnPUSCH.Applied)
        error("sixgr:phy:ul:PUSCHCodewordLLRCountContract", ...
            "PUSCH UL-SCH LLR count %d does not match CodingLayout RateMatchedBitCount=%d and no UCI demultiplexing explains the mismatch.", ...
            numel(cwLLRForULSCH), round(double(codingLayout.RateMatchedBitCount)));
    end
    codingLayout = sixgr.phy.phycode.resolveCodingLayout( ...
        "Direction", "UL", ...
        "TransportBlockSize", trBlkSize, ...
        "TargetCodeRate", targetCodeRate, ...
        "RV", rv, ...
        "Modulation", pusch.Modulation, ...
        "NumLayers", pusch.NumLayers, ...
        "RateMatchedBitCount", numel(cwLLRForULSCH), ...
        "TBCRCType", tbCRCType);
    bgn = double(codingLayout.BaseGraph);
    ldpcSeg = localLDPCSegmentationFromLayout(codingLayout);
end
codewordLayerMapping.ULSCHDemapperLLRCountPerCodeword = double(numel(cwLLRForULSCH));
codewordLayerMapping.TotalULSCHDemapperLLRCount = double(numel(cwLLRForULSCH));
[recLLR, rateRecoverInfo] = sixgr.phy.phycode.rateRecoverLDPC(cwLLRForULSCH, trBlkSize, targetCodeRate, rv, pusch.Modulation, pusch.NumLayers, ldpcSeg.NumCodeBlocks, [], ...
    "CodingLayout", codingLayout);
[recLLR, harqCombiningInfo] = sixgr.phy.harq.combineSoftLLR(recLLR, opt.HARQSoftBufferLLR, ...
    "CurrentLayout", codingLayout, "PriorLayout", opt.HARQSoftBufferLayout);
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
decodedBitLineage = localBuildPUSCHDecodedBitLineage(cwLLR, cwLLRForULSCH, recLLR, decCbs, ...
    codingLayout, trBlkSize, B, crcOK, uciOnPUSCH);

% Outputs
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOK);
rx.CRCPass = logical(crcOK);
rx.TBCRCPass = logical(crcOK);
rx.TransportBlock = int8(tbBits(:));
rx.NoiseVar = double(nVar);
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarStrictFailure = false;
rx.NoiseVarDomain = "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVar = double(nVar);
rx.PreEqualizationNoiseVariance = double(nVar);
rx.PreEqualizationNoiseVarDomain = "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarianceDomain = "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarianceSource = char(string(noiseStatus.Source));
rx.PreEqualizationNoiseVarTransformSource = char(string(sixgr.util.structGet(noiseTransformInfo, "TransformSource", "")));
rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet(noiseTransformInfo, "SampleToGridNoiseVarianceGain", NaN));
rx.DecoderNoiseVar = double(nVarForDecode);
rx.PostEqualizationNoiseVar = double(nVarPostEqDiagnostic);
rx.PostEqualizationNoiseVariance = double(nVarPostEqDiagnostic);
rx.PostEqualizationNoiseVarianceDomain = ...
    "unit_constellation_layer_symbol_post_equalization";
rx.PostEqualizationNoiseVarianceSource = char(string(sixgr.util.structGet( ...
    nVarPostEqInfo, "Source", "post_equalization_noise_variance_unavailable")));
rx.DecoderNoiseVarStatus = char(string(sixgr.util.structGet(nVarDecodeInfo, "ValueStatus", "OK")));
rx.DecoderNoiseVarSource = char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "")));
rx.DecoderNoiseVarReductionMethod = char(string(sixgr.util.structGet(nVarDecodeInfo, "ReductionMethod", "")));
rx.ReceiverUsable = true;
rx.DecodeAttempted = true;
rx.DecodeUsable = true;
rx.FailureReason = "";
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
rx.DecodeLatency_s = double(decodeLatency_s);
rx.UseMexLDPC = logical(useMexLDPC);
if useMexLDPC
    if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
        rx.LDPCDecoderEngine = "sixgr_ldpc_decode_batch_kernel_mex";
    else
        rx.LDPCDecoderEngine = "sixgr_ldpc_decode_batch_kernel";
    end
else
    rx.LDPCDecoderEngine = "sixgr.phy.phycode.ldpcDecode";
end
rx.MaxDecoderIterations = double(maxIter);
rx.DecoderIterations = mean(double(actIter(:)), "omitnan");
rx.NumCodeBlocks = double(ldpcSeg.NumCodeBlocks);
rx.CodeBlockLength_bits = double(ldpcSeg.CodeBlockLength);
rx.TransportBlockCRCLength = double(tbCRCLen);
rx.TransportBlockLenWithCRC = double(ldpcSeg.TransportBlockLenWithCRC);
rx.CodingLayout = codingLayout;
rx.CodewordLayerMapping = codewordLayerMapping;
rx.DMRSEPREDifference = dmrsPowerInfo;
rx.DMRSDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
rx.DMRSPowerBoost_dB = double(dmrsPowerInfo.DMRSPowerBoost_dB);
rx.DMRSConfiguredPowerBoost_dB = double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
rx.DMRSRealizedDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
rx.DMRSAmplitudeScale = double(dmrsPowerInfo.DMRSAmplitudeScale);
rx.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
rx.NumCodewords = double(codewordLayerMapping.NumCodewords);
rx.ActualNumCodewords = double(codewordLayerMapping.ActualNumCodewords);
rx.CodewordLLRCountPerCodeword = double(codewordLayerMapping.DemapperLLRCountPerCodeword);
rx.DecodedBitLineage = decodedBitLineage;
rx.LDPCRateRecoverNumCodeBlocks = double(sixgr.util.structGet(rateRecoverInfo, "numCBUsed", ldpcSeg.NumCodeBlocks));
rx.HARQSoftCombiningApplied = logical(harqCombiningInfo.Applied);
rx.HARQSoftCombiningReason = char(string(harqCombiningInfo.Reason));
rx.HARQSoftCombiningCurrentNumel = double(harqCombiningInfo.CurrentNumel);
rx.HARQSoftCombiningPriorNumel = double(harqCombiningInfo.PriorNumel);
rx.HARQSoftCombiningPositionAware = logical(sixgr.util.structGet(harqCombiningInfo, "PositionAware", false));
rx.HARQSoftCombiningOverlapPositionCount = double(sixgr.util.structGet(harqCombiningInfo, "OverlapPositionCount", NaN));
rx.HARQSoftBuffer = sixgr.util.structGet(harqCombiningInfo, "SoftBuffer", struct());
rx.CFOEstimateAvailable = logical(trackingCorrection.CFOEstimateAvailable);
rx.EstimatedCFO_Hz = double(trackingCorrection.EstimatedCFO_Hz);
rx.EstimatedCommonFrequency_Hz = double(sixgr.util.structGet(syncState, "EstimatedCommonFrequency_Hz", NaN));
rx.PhysicalDoppler_Hz = double(sixgr.util.structGet(syncState, "PhysicalDoppler_Hz", NaN));
rx.CFOCorrectionApplied = logical(trackingCorrection.CFOCorrectionApplied);
rx.CFOCorrectionApplied_Hz = double(trackingCorrection.CFOCorrectionApplied_Hz);
rx.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(syncState, "ResidualCFO_PostCorrection_Hz", NaN));
rx.ResidualCFO_EstimatedPostCorrection_Hz = double(sixgr.util.structGet(syncState, "ResidualCFO_EstimatedPostCorrection_Hz", NaN));
rx.ResidualCFOEstimateSource = char(string(sixgr.util.structGet( ...
    trackingCorrection, "ResidualCFOEstimateSource", "")));
rx.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(syncState, "ResidualTimingError_PostCorrection_samples", NaN));
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
rx.PostEqSINRRawEqualizer_dB = double(sixgr.util.structGet(postEqSINRInfo, "RawEqualizerSINR_dB", ...
    sixgr.util.structGet(postEqSINRInfo, "RawSINR_dB", NaN)));
rx.PostEqSINRDMRSResidualBoundApplied = logical(sixgr.util.structGet(postEqSINRInfo, "DMRSResidualBoundApplied", false));
rx.DMRSResidualPostEqSINRBoundEnabled = logical(dmrsResidualBoundEnabled);
rx.DecisionDirectedPostEqSINRBoundEnabled = logical(decisionDirectedBoundEnabled);
rx.PostEqSINRDMRSResidual_dB = double(sixgr.util.structGet(pilotPostEqInfo, "SINR_dB", NaN));
rx.PostEqDMRSResidualNoiseVar = double(sixgr.util.structGet(pilotPostEqInfo, "NoiseVariance", NaN));
rx.PostEqDMRSResidualSource = char(string(sixgr.util.structGet(pilotPostEqInfo, "Source", "")));
rx.PostEqDecisionResidual_dB = double(sixgr.util.structGet(decisionPostEqInfo, "SINR_dB", NaN));
rx.PostEqDecisionResidualNoiseVar = double(sixgr.util.structGet(decisionPostEqInfo, "NoiseVariance", NaN));
rx.PostEqDecisionResidualSource = char(string(sixgr.util.structGet(decisionPostEqInfo, "Source", "")));
rx.SINRComputationMethod = char(string(sixgr.util.structGet(postEqSINRInfo, "Method", char(lower(string(equalizerAlg))))));
rx.EqualizerType = char(string(equalizerInfo.AlgorithmUsed));
rx.EqualizerRequestedType = char(equalizerRequested);
rx.EqualizerEngine = char(string(equalizerInfo.EngineUsed));
rx.EqualizerResultContract = char(string(sixgr.util.structGet(equalizerInfo, "EqualizerResult.ContractVersion", "")));
rx.EqualizerEquation = char(string(sixgr.util.structGet(equalizerInfo, "EqualizerResult.Equation", "")));
rx.EqualizerCovarianceIncludesNoise = logical(sixgr.util.structGet(equalizerInfo, "EqualizerResult.CovarianceIncludesNoise", false));
rx.EqualizerNoiseAddedExactlyOnce = logical(sixgr.util.structGet(equalizerInfo, "EqualizerResult.NoiseAddedExactlyOnce", false));
rx.EqualizerUniqueSolveCount = double(sixgr.util.structGet(equalizerInfo, "EqualizerResult.UniqueSolveCount", NaN));
rx.EqualizerSolveCount = double(sixgr.util.structGet(equalizerInfo, "EqualizerResult.SolveCount", NaN));
rx.EqualizerCovarianceFactorizationCount = double(sixgr.util.structGet( ...
    equalizerInfo, "EqualizerResult.CovarianceFactorizationCount", NaN));
rx.InterferenceCovarianceAvailable = logical(rintInfo.Available);
rx.InterferenceCovarianceSource = char(string(rintInfo.Source));
rx.InterferenceCovarianceStatus = char(string(rintInfo.Status));
rx.InterferenceCovarianceIncludesNoise = logical(sixgr.util.structGet(rintInfo, "CovarianceIncludesNoise", RIncludesNoise));
rx.InterferenceCovarianceDomain = char(string(sixgr.util.structGet(rintInfo, "Domain", "")));
rx.ChannelEstimateAttempted = true;
rx.ChannelEstimateAvailable = ~isempty(Hest);
rx.ChannelEstimateSource = "pusch_dmrs_channel_estimate";
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
rx.ULSCHDecodeAttempted = true;
rx.ULSCHDecodeAvailable = ~isempty(tbBits) || ~isempty(decCbs) || ~isempty(recLLR);
rx.LLRAvailable = ~isempty(cwLLRForULSCH);
rx.LLRFinite = ~isempty(cwLLRForULSCH) && all(isfinite(double(cwLLRForULSCH(:))));
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
rx.LLRNoiseVarianceDomain = "unit_constellation_soft_demapper_input";
rx.LLRNoiseVarianceSource = char(string(sixgr.util.structGet( ...
    nVarDecodeInfo, "Source", "pusch_soft_demapper")));
rx.DecoderNoiseVarianceConfiguredMode = char(string(sixgr.util.structGet( ...
    nVarDecodeInfo, "ConfiguredMode", "")));
rx.NoiseVarianceUnit = "normalized_complex_power";
rx.NoiseVarianceNormalization = ...
    "native_ofdm_grid_then_unit_constellation_equalizer_domains";
rx.EqualizedSymbolsForEvidence = layerEqSym;
rx.LayerEqualizedSymbolsForEvidence = layerEqSym;
rx.LayerEqualizedSymbols = layerEqSym;
rx.PortEqualizedSymbolsForEvidence = eqSym;
rx.PortEqualizedSymbols = eqSym;
rx.DecoderInputSymbolsForEvidence = decoderInputSym;
rx.DecoderInputSymbolDomain = char(string(decoderInputInfo.Domain));
rx.DecoderInputSymbolSource = char(string(decoderInputInfo.Status));
rx.EqualizedSymbolDomain = "layer";
rx.EqualizedSymbolSource = char(string(layerEqInfo.Status));
rx.LayerSymbolOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, ...
    localLayerIndicesFromPUSCHIndices(puschInd, layerEqSym), "layer");
rx.QAMEqualizedSymbolsForEvidence = qamEqSym;
rx.PUSCHQAMSymbolsForEvidence = qamEqSym;
rx.PUSCHDFTInputSymbolsForEvidence = qamEqSym;
rx.QAMEqualizedSymbolDomain = "layer";
rx.QAMEqualizedSymbolSource = char(string(qamEqInfo.Status));
rx.QAMSymbolOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, ...
    localLayerIndicesFromPUSCHIndices( ...
    localPUSCHQAMIndicesFromAllocatedIndices( ...
    puschInd,ptrsInd,carrier,qamEqSym),qamEqSym), "layer");
rx.DemapperLLRCount = double(codewordLayerMapping.TotalDemapperLLRCount);
rx.ULSCHDemapperLLRCount = double(numel(cwLLRForULSCH));
rx.RateRecoveredLLRCount = double(numel(recLLR));
rx.PUSCHRxSymbolsForEvidence = puschRxSym;
rx.PTRSCPECorrectionEnabled = logical(cpeCorrInfo.Enabled);
rx.PTRSConfiguredEnabled = logical(localObjectValue(pusch, "EnablePTRS", false));
rx.PTRSCPECorrectionConfigured = logical(enablePTRSCPECorrection);
rx.PTRSCPECorrectionApplied = logical(cpeCorrInfo.Enabled);
rx.PTRSCPECorrectionSymbols = double(cpeCorrInfo.NumSymbolsCorrected);
rx.PTRSMeanCPE_deg = double(cpeCorrInfo.MeanCPE_deg);
rx.PTRSCPECorrectionReason = char(string(cpeCorrInfo.NAReason));
rx.PTRSCPECorrectionStatus = char(localPTRSCorrectionStatus(cpeCorrInfo));
rx.PTRSReceiverEvidenceSource = "sixgr.phy.ul.PUSCH_Rx.ptrs_cpe";
rx.RecLLR = recLLR;
rx.RateRecoveredLLR = recLLR;
rx.RateRecoverInfo = rateRecoverInfo;
rx = sixgr.phy.rx.appendMeasuredPHYEvidence(rx, carrier, dmrsInd, dmrsInd, dmrsSym, dmrsInfo, ...
    cwLLRForULSCH, recLLR, recLLRBatch, rateRecoverInfo, actIter, parity, cbCrcErr, alg, useMexLDPC, crcErr);
if hasPHYGrant
    rx.PHYGrant = phyGrant;
    rx.PHYGrantDimensionContract = phyGrantContract;
end
rx.UCIOnPUSCHApplied = logical(uciOnPUSCH.Applied);
rx.UCIOnPUSCHSource = char(string(uciOnPUSCH.Source));
if rx.UCIOnPUSCHApplied
    rx.UCIOnPUSCHEvidenceSource = "same_waveform_pusch_rx_uci_demultiplexer";
else
    rx.UCIOnPUSCHEvidenceSource = "";
end
rx.HARQACKBitCount = double(uciOnPUSCH.HARQACKBitCount);
rx.ExpectedHARQACKBits = int8(uciOnPUSCH.ExpectedHARQACKBits(:));
rx.DecodedHARQACKBits = int8(uciOnPUSCH.DecodedHARQACKBits(:));
rx.HARQACKContentMatch = logical(uciOnPUSCH.ContentMatch);
rx.HARQACKDecodeStatus = char(string(uciOnPUSCH.Status));
rx.HARQACKDecodeReason = char(string(uciOnPUSCH.Reason));
rx.CSI1BitCount = double(uciOnPUSCH.CSI1BitCount);
rx.CSI2BitCount = double(uciOnPUSCH.CSI2BitCount);
rx.ConfiguredGrantUCIBitCount = double(uciOnPUSCH.ConfiguredGrantUCIBitCount);
rx.ExpectedCSIPart1Bits = int8(uciOnPUSCH.ExpectedCSIPart1Bits(:));
rx.ExpectedCSIPart2Bits = int8(uciOnPUSCH.ExpectedCSIPart2Bits(:));
rx.ExpectedConfiguredGrantUCIBits = int8(uciOnPUSCH.ExpectedConfiguredGrantUCIBits(:));
rx.DecodedCSIPart1Bits = int8(uciOnPUSCH.DecodedCSIPart1Bits(:));
rx.DecodedCSIPart2Bits = int8(uciOnPUSCH.DecodedCSIPart2Bits(:));
rx.DecodedConfiguredGrantUCIBits = int8(uciOnPUSCH.DecodedConfiguredGrantUCIBits(:));
rx.CSI1ContentMatch = logical(uciOnPUSCH.CSI1ContentMatch);
rx.CSI2ContentMatch = logical(uciOnPUSCH.CSI2ContentMatch);
rx.ConfiguredGrantUCIContentMatch = logical(uciOnPUSCH.ConfiguredGrantUCIContentMatch);
if ~logical(opt.CompactOutput)
    rx.CodewordLLR = cwLLR;
    rx.CodewordLLRCell = cwLLRCell;
    rx.ULSCHCodewordLLR = cwLLRForULSCH;
    rx.ULSCHCodewordLLRCell = {cwLLRForULSCH};
    rx.CodewordLLRInfo = codewordLLRInfo;
    rx.HARQACKLLR = uciOnPUSCH.HARQACKLLR;
    rx.CSI1LLR = uciOnPUSCH.CSI1LLR;
    rx.CSI2AndCGUCILLR = uciOnPUSCH.CSI2AndCGUCILLR;
    rx.DecodedCodeBlocks = decCbs;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.CodeBlockCRCError = cbCrcErr;
    rx.ChannelEstimate = Hest;
    rx.ChannelEstimation = estInfo;
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
    rx.EqualizedSymbols = layerEqSym;
    rx.PortEqualizedSymbols = eqSym;
    rx.DecoderInputSymbols = decoderInputSym;
    rx.PUSCHRxSymbols = puschRxSym;
    rx.QAMEqualizedSymbols = qamEqSym;
    rx.PUSCHQAMSymbols = qamEqSym;
    rx.CSI = csi;
    rx.EqualizerInfo = equalizerInfo;
    rx.InterferenceCovariance = Rint;
    rx.InterferenceCovarianceInfo = rintInfo;
end
rx = localAnnotateReceiveCombiner(rx, receiveCombinerInfo);

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
info.DMRS = dmrsInfo;
info.DMRSEPREDifference = dmrsPowerInfo;
info.ReceiverTrackingCorrection = trackingCorrection;
info.ReceiverSynchronizationState = syncState;
info.NoiseVariance = noiseStatus;
info.OFDMNoiseTransform = sixgr.util.structGet(ofdmInfo, "NoiseTransform", struct());
info.PreEqualizationNoiseVarianceTransform = noiseTransformInfo;
info.ConfiguredNoiseVarianceTransform = configuredNoiseTransformInfo;
info.HARQSoftCombining = harqCombiningInfo;
info.HARQSoftBuffer = rx.HARQSoftBuffer;
info.PreEqualizationNoiseVariance = double(nVar);
info.PostEqualizationNoiseVariance = nVarPostEqInfo;
info.DecoderNoiseVariance = nVarDecodeInfo;
info.PostEqualizationDMRSResidual = pilotPostEqInfo;
info.PostEqualizationDecisionResidual = decisionPostEqInfo;
info.TimingEstimate = timingResolution;
info.Equalizer = equalizerInfo;
info.InterferenceCovariance = rintInfo;
info.ReceiveCombiner = receiveCombinerInfo;
info.PTRS = ptrsInfo;
info.CPECorrection = cpeCorrInfo;
info.CodingLayout = codingLayout;
info.CodewordLayerMapping = codewordLayerMapping;
info.CodewordLLRInfo = codewordLLRInfo;
info.LLRScaling = llrCSIInfo;
info.RateRecover = rateRecoverInfo;
info.DecodedBitLineage = decodedBitLineage;
info.StrictReceiverEvidence = strictEvidence;
if hasPHYGrant
    info.PHYGrant = phyGrant;
    info.PHYGrantDimensionContract = phyGrantContract;
end

end

function [cwLLR, cwLLRCell, info] = localNormalizePUSCHCodewordLLR(cwLLRRaw, expectedCount)
if iscell(cwLLRRaw)
    cwLLRCell = reshape(cwLLRRaw, 1, []);
    sourceWasCell = true;
else
    cwLLRCell = {cwLLRRaw};
    sourceWasCell = false;
end
if numel(cwLLRCell) ~= expectedCount
    error("sixgr:phy:ul:PUSCHDecodedCodewordCountMismatch", ...
        "nrPUSCHDecode returned %d codeword LLR stream(s); expected %d.", ...
        numel(cwLLRCell), expectedCount);
end
for cw = 1:numel(cwLLRCell)
    cwLLRCell{cw} = double(cwLLRCell{cw}(:));
    if isempty(cwLLRCell{cw}) || any(~isfinite(cwLLRCell{cw}))
        error("sixgr:phy:ul:PUSCHInvalidCodewordLLR", ...
            "Codeword %d LLR stream must be nonempty and finite.", cw - 1);
    end
end
cwLLR = cwLLRCell{1};
info = struct( ...
    "ContractVersion", "PUSCHCodewordLLR/v1", ...
    "SourceWasCell", logical(sourceWasCell), ...
    "ExpectedNumCodewords", double(expectedCount), ...
    "ActualNumCodewords", double(numel(cwLLRCell)), ...
    "LLRCountPerCodeword", double(cellfun(@numel, cwLLRCell)));
end

function mapping = localBuildPUSCHRxCodewordLayerContract(pusch, cwLLRCell, codingLayouts, eqSym)
nLayers = max(1, round(double(localObjectValue(pusch, "NumLayers", 1))));
counts = double(cellfun(@numel, cwLLRCell));
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
nCodewords = double(pusch.NumCodewords);
expected = double(cellfun(@(x) x.RateMatchedBitCount, codingLayouts));
if numel(cwLLRCell) ~= nCodewords || numel(codingLayouts) ~= nCodewords
    error("sixgr:phy:ul:PUSCHDecodedCodewordCountMismatch", ...
        "PUSCH RX codeword and coding-layout containers must match NumCodewords=%d.", nCodewords);
end
if any(counts < expected)
    error("sixgr:phy:ul:PUSCHCodewordLLRCountContract", ...
        "PUSCH demapper LLR count %s is smaller than CodingLayout rate-matched count %s.", ...
        mat2str(counts), mat2str(expected));
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
mapping = struct();
mapping.ContractVersion = "PUSCHCodewordLayer/v1";
mapping.Direction = "UL";
mapping.MappingStandard = "3GPP_TS_38_211_ULSCH_codeword_to_layer_mapping";
mapping.MappingEngine = "nrPUSCH_internal_nrLayerMap";
mapping.InverseEngine = "nrPUSCHDecode_internal_nrLayerDemap";
mapping.SupportedScope = "release_valid_one_or_two_ulsch_codeword_ranks_1_to_8";
mapping.NumCodewords = nCodewords;
mapping.ActualNumCodewords = double(numel(cwLLRCell));
mapping.NumLayers = double(nLayers);
[layerCounts, ~] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(nLayers);
mapping.CodewordIndexByLayer = repelem(0:nCodewords-1, layerCounts);
mapping.LayerIndexWithinCodeword = cell2mat(arrayfun( ...
    @(n) 0:n-1, layerCounts, "UniformOutput", false));
mapping.LayerCountPerCodeword = double(layerCounts);
mapping.RateMatchedBitCountPerCodeword = double(counts);
mapping.CodingLayoutRateMatchedBitCountPerCodeword = double(expected);
mapping.UCIOrControlMuxedBitCount = double(max(0, counts - expected));
mapping.DemapperLLRCountPerCodeword = double(counts);
mapping.TotalDemapperLLRCount = double(sum(counts));
mapping.ActualLayerColumns = double(nCols);
mapping.ActualLayersEqualGrantLayers = logical(nCols == nLayers);
mapping.Equation = "port_observations_to_equalized_layers_S_hat_to_one_or_two_ULSCH_codeword_LLRs";
end

function lineage = localBuildPUSCHDecodedBitLineage(demapperLLR, ulschLLR, recLLR, decCbs, layout, trBlkSize, transportBlockLenWithCRC, crcPass, uciOnPUSCH)
lineage = struct( ...
    "ContractVersion", "PUSCHDecodedBitLineage/v1", ...
    "CodewordIndex", 1, ...
    "DemapperDomain", "rate_matched_pusch_codeword_llr", ...
    "DemapperLLRCount", double(numel(demapperLLR)), ...
    "ULSCHDemapperLLRCount", double(numel(ulschLLR)), ...
    "RateMatchedBitCount", double(layout.RateMatchedBitCount), ...
    "RateRecoveryInputDomain", "rate_matched_ulsch_codeword_llr", ...
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
    "UCIOnPUSCHApplied", logical(sixgr.util.structGet(uciOnPUSCH, "Applied", false)), ...
    "HARQACKBitCount", double(sixgr.util.structGet(uciOnPUSCH, "HARQACKBitCount", 0)), ...
    "RateMatchSignature", char(string(layout.RateMatchSignature)), ...
    "CombineSignature", char(string(layout.CombineSignature)));
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
    ptrsInd = sixgr.phy.resource.puschPTRSGridIndices( ...
        carrier, pusch, "IndexBase", "1based");
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
        ptrsInd, ptrsSym, carrier, pusch, nVar, equalizerAlg, Rint, RIncludesNoise, enabled)
info = struct('Enabled', false, 'NumSymbolsCorrected', 0, ...
    'MeanCPE_deg', NaN, 'NAReason', "", ...
    'EstimatorDomain', "not_applicable", ...
    'TransformDeprecodingApplied', false);
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

refPTRS = ptrsSym(:);
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
if transformPrecoding
    % TS 38.211 6.3.1.4 multiplexes PUSCH data and PT-RS before the
    % transform.  Consequently nrPUSCHPTRSIndices is allocation-relative
    % in this mode and must never index rxGrid/Hest.  Recover the exact
    % pre-transform sequence from the already equalized allocation, then
    % select the PT-RS samples with those allocation-relative indices.
    mrb = double(numel(pusch.PRBSet));
    msc = 12*mrb;
    if mrb < 1 || mod(size(eqSym,1),msc) ~= 0
        info.NAReason = "transform_precoded_pusch_allocation_shape_mismatch";
        return;
    end
    try
        deprecoded = nrTransformDeprecode(eqSym,mrb);
        relativePTRSInd = nrPUSCHPTRSIndices(carrier,pusch);
    catch ME
        info.NAReason = "ptrs_transform_deprecoding_failed:" + string(ME.identifier);
        return;
    end
    if isempty(relativePTRSInd) || any(double(relativePTRSInd(:)) > numel(deprecoded))
        info.NAReason = "ptrs_allocation_relative_index_mismatch";
        return;
    end
    eqPTRS = deprecoded(relativePTRSInd);
    info.EstimatorDomain = "transform_deprecoded_allocation";
    info.TransformDeprecodingApplied = true;
else
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
            "Algorithm", equalizerAlg, "Rint", Rint, "RIncludesNoise", RIncludesNoise);
    catch ME
        info.NAReason = "ptrs_equalization_failed:" + string(ME.identifier);
        return;
    end
    eqPTRS = localSelectPTRSObservation(eqPTRS, refPTRS);
    info.EstimatorDomain = "frequency_domain_grid_ptrs";
end
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
    if size(puschInd,1) ~= size(eqSymOut,1)
        info.NAReason = "pusch_index_equalized_row_mismatch";
        return;
    end
    [~, dataL, ~] = ind2sub([K L P], double(puschInd(:,1)));
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

for row = 1:size(eqSymOut,1)
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

function [Rint, info, includesNoise] = localResolvePUSCHInterferenceCovariance(opt, carrier, ...
        puschInd, appliedTimingCorrection, nVar, rxGrid, hEst, dmrsInd, dmrsSym)
includesNoise = false;
[Rint, info] = sixgr.phy.rx.estimateContributionGridCovariance(opt.InterferenceContributionTensor, ...
    carrier, puschInd, appliedTimingCorrection, opt.InterferenceContributionSource, ...
    opt.InterferenceContributionDomain, "pusch");
if logical(info.Available)
    return;
end

[Rint, info, includesNoise] = localResolveProvidedInterferenceCovariance(opt.InterferenceCovariance, ...
    opt.InterferenceCovarianceSource, opt.InterferenceCovarianceIncludesNoise, max(1, size(rxGrid, 3)));
if logical(info.Available)
    return;
end

[Rint, info] = sixgr.phy.rx.estimateInterferenceCovarianceIRC(rxGrid, hEst, dmrsInd, dmrsSym, nVar);
includesNoise = true;
info.CovarianceIncludesNoise = true;
info.Domain = "dmrs_pilot_residual_receive_antenna_covariance";
if ~isfield(info, "NAReason")
    info.NAReason = "";
end
end

function [Rint, info, includesNoise] = localResolveProvidedInterferenceCovariance(Rprovided, source, includesNoiseIn, nRx)
Rint = [];
includesNoise = logical(includesNoiseIn);
info = struct("Available", false, ...
    "Source", "provided_interference_covariance_unavailable", ...
    "Status", "unavailable", ...
    "NAReason", "no_provided_interference_covariance", ...
    "Domain", "provided_receive_antenna_covariance", ...
    "CovarianceIncludesNoise", logical(includesNoise), ...
    "NumRxAnt", double(nRx));
if isempty(Rprovided)
    return;
end
if ~isnumeric(Rprovided)
    info.NAReason = "provided_interference_covariance_must_be_numeric";
    return;
end
R = double(Rprovided);
if ~(ismatrix(R) && size(R, 1) == nRx && size(R, 2) == nRx)
    info.NAReason = "provided_interference_covariance_shape_mismatch";
    return;
end
if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
    info.NAReason = "provided_interference_covariance_nonfinite";
    return;
end
Rint = (R + R') ./ 2;
src = string(source);
if strlength(strtrim(src)) == 0
    src = "provided_interference_covariance";
end
info.Available = true;
info.Source = char(src);
info.Status = "OK";
info.NAReason = "";
info.CovarianceIncludesNoise = logical(includesNoise);
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
    "KnownTimingDelay_samples", NaN, ...
    "MeasurementDirection", "", ...
    "ConsumerDirection", "UL", ...
    "DirectionCompatible", true, ...
    "AuthorityStatus", "legacy_untagged_tracking_state");

raw = explicitState;
usingRuntimeUserContext = isempty(raw);
if usingRuntimeUserContext
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

measurementDirection = upper(strtrim(localFirstString(raw, ...
    ["TrackingMeasurementDirection","RuntimeTRSMeasurementDirection"], "")));
consumerDirection = upper(strtrim(localFirstString(raw, ...
    ["TrackingConsumerDirection","RuntimeReceiverTrackingConsumerDirection"], "UL")));
directionCompatibilityDeclared = localFirstLogical(raw, ...
    ["TrackingDirectionCompatible","RuntimeReceiverTrackingDirectionCompatible"], true);
authorityStatus = localFirstString(raw, ...
    ["TrackingAuthorityStatus","RuntimeReceiverTrackingAuthorityStatus"], ...
    "legacy_untagged_tracking_state");
authorityReason = localFirstString(raw, ...
    ["TrackingAuthorityReason","RuntimeReceiverTrackingAuthorityReason"], "");
tracking.MeasurementDirection = char(measurementDirection);
tracking.ConsumerDirection = char(consumerDirection);
tracking.DirectionCompatible = logical(directionCompatibilityDeclared);
tracking.AuthorityStatus = char(authorityStatus);
if (~directionCompatibilityDeclared) || ...
        (strlength(measurementDirection) > 0 && measurementDirection ~= "UL") || ...
        (strlength(consumerDirection) > 0 && consumerDirection ~= "UL")
    tracking.Status = "rejected_cross_direction_receiver_state";
    if strlength(strtrim(authorityReason)) > 0
        tracking.NAReason = char(authorityReason);
    else
        tracking.NAReason = "measurement_and_ul_receiver_directions_differ";
    end
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
oscillatorCFOHz = localFirstFinite(raw, ["EstimatedOscillatorCFO_Hz","RuntimeTRSEstimatedOscillatorCFO_Hz"], NaN);
legacyCFOHz = localFirstFinite(raw, ["EstimatedCFO_Hz","RuntimeTRSEstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN);
allowRuntimeCommonAsCFO = logical(sixgr.util.structGet(cfg, ...
    "phy.rx.applyRuntimeTRSCommonFrequencyAsCFO", false));
injectedCFOHz = localResolveInjectedCFOHz(cfg);
hasInjectedOscillatorCFO = isfinite(injectedCFOHz) && abs(double(injectedCFOHz)) > 1e-9;
runtimeLegacyZeroCFO = usingRuntimeUserContext && isfinite(legacyCFOHz) && abs(double(legacyCFOHz)) <= 1e-9;
runtimeNonzeroTRSCFOWithoutInjectedOscillator = usingRuntimeUserContext && ...
    ~allowRuntimeCommonAsCFO && ~hasInjectedOscillatorCFO && ~runtimeLegacyZeroCFO && ...
    isfinite(oscillatorCFOHz) && abs(double(oscillatorCFOHz)) > 1e-9;
if runtimeNonzeroTRSCFOWithoutInjectedOscillator
    cfoHz = NaN;
elseif runtimeLegacyZeroCFO
    cfoHz = legacyCFOHz;
elseif usingRuntimeUserContext && ~allowRuntimeCommonAsCFO
    cfoHz = oscillatorCFOHz;
else
    cfoHz = localFirstFiniteValue(oscillatorCFOHz, legacyCFOHz);
end
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
tracking.KnownTimingDelay_samples = localFirstFinite(raw, ["KnownTimingDelay_samples","RuntimeKnownTimingDelay_samples"], NaN);
if tracking.TimingEstimateAvailable || tracking.CFOEstimateAvailable
    tracking.Status = "available";
    tracking.NAReason = "";
else
    tracking.NAReason = "trs_tracking_state_has_no_timing_or_cfo_estimate";
end
end

function tf = localRuntimeAlignedTimingBypass(cfg)
runtimeAligned = logical(sixgr.util.structGet(cfg, ...
    "lls6g.receiverSync.RuntimeWaveformSampleAligned", false));
injectedTiming = localResolveInjectedTimingOffsetSamples(cfg);
hasInjectedTiming = isfinite(injectedTiming) && abs(double(injectedTiming)) > 1e-9;
% RuntimeWaveformSampleAligned is asserted only after the link wrapper has
% applied the materialized channel and its exact sample trim.  A zero-delay
% AWGN channel is therefore just as aligned as a fading channel with a
% nonzero filter delay.  Requiring a nonzero trim here caused a second blind
% DM-RS acquisition on AWGN waveforms; for multi-port PUSCH that acquisition
% can lock to a later OFDM-symbol replica and shift the entire slot.  An
% explicitly injected timing offset remains the YAML-owned way to exercise
% receiver timing acquisition/correction.
tf = runtimeAligned && ~hasInjectedTiming;
end

function value = localFirstFiniteValue(varargin)
value = NaN;
for k = 1:nargin
    candidate = double(varargin{k});
    if ~isempty(candidate) && isfinite(candidate(1))
        value = candidate(1);
        return;
    end
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
    carrier, rxWaveform, sampleRateHz, rxGrid, ofdmInfo, tracking, cfg, ...
    dmrsInd, dmrsSym)
enabled = logical(sixgr.util.structGet(cfg, "phy.rx.cfoCorrectionEnabled", ...
    sixgr.util.structGet(cfg, "phy.impairments.cfoCorrectionEnabled", false)));
if ~enabled
    if logical(sixgr.util.structGet(tracking, "CFOEstimateAvailable", false))
        tracking.CFONAReason = "cfo_correction_disabled_by_config";
    end
    return;
end
if logical(sixgr.util.structGet(tracking, "CFOCorrectionApplied", false))
    tracking = localEstimateResidualCFOAfterCorrection( ...
        rxWaveform, rxGrid, carrier, dmrsInd, dmrsSym, ofdmInfo, ...
        sampleRateHz, tracking, cfg, "post_tracking_correction");
    return;
end
estimatedCFOHz = double(sixgr.util.structGet(tracking, "EstimatedCFO_Hz", NaN));
if ~(logical(sixgr.util.structGet(tracking, "CFOEstimateAvailable", false)) && ...
        isfinite(estimatedCFOHz) && isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
if localSuppressBlindCFOCorrectionForRuntimeAligned(cfg, tracking)
    tracking.CFOCorrectionApplied = false;
    tracking.CFOCorrectionApplied_Hz = NaN;
    tracking.Status = "available_measurement_only";
    tracking.CFONAReason = "runtime_aligned_zero_injected_cfo_blind_correction_suppressed";
    return;
end
correctedWaveform = localApplyFrequencyCorrection(rxWaveform, sampleRateHz, -estimatedCFOHz);
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, correctedWaveform);
tracking.CFOCorrectionApplied = true;
tracking.CFOCorrectionApplied_Hz = estimatedCFOHz;
tracking.Status = "available_corrected";
tracking.NAReason = "";
tracking.CFONAReason = "";
tracking = localEstimateResidualCFOAfterCorrection( ...
    correctedWaveform, rxGrid, carrier, dmrsInd, dmrsSym, ofdmInfo, ...
    sampleRateHz, tracking, cfg, "post_receiver_correction");
end

function tf = localSuppressBlindCFOCorrectionForRuntimeAligned(cfg, tracking)
runtimeAligned = logical(sixgr.util.structGet(cfg, ...
    "lls6g.receiverSync.RuntimeWaveformSampleAligned", false));
forceBlindCorrection = logical(sixgr.util.structGet(cfg, ...
    "phy.rx.applyBlindCFOCorrectionOnAlignedRuntimeWaveform", false));
injectedCFOHz = localResolveInjectedCFOHz(cfg);
hasInjectedCFO = isfinite(injectedCFOHz) && abs(double(injectedCFOHz)) > 1e-9;
source = lower(strtrim(string(sixgr.util.structGet(tracking, "Source", ""))));
sourceIsBlindEstimator = any(contains(source, ["cyclic_prefix", "dmrs_reference_symbol_phase_slope", "reference_symbol_phase_slope"]));
tf = runtimeAligned && ~forceBlindCorrection && ~hasInjectedCFO && sourceIsBlindEstimator;
end

function tracking = localEstimateResidualCFOAfterCorrection( ...
        rxWaveform, rxGrid, carrier, dmrsInd, dmrsSym, ofdmInfo, ...
        sampleRateHz, tracking, cfg, source)
tracking.ResidualCFOEstimate_Hz = NaN;
method = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.impairments.cfoEstimationMethod", "cyclic_prefix"))));
tracking.ResidualCFOEstimateSource = method + "_" + string(source);
if ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
try
    if any(method == ["dmrs_two_symbol", "dmrs", ...
            "reference_symbol_phase_slope"])
        [residualHz, residualInfo] = ...
            sixgr.phy.rx.estimateCFOFromReferenceSymbols( ...
            rxGrid, dmrsInd, dmrsSym, carrier, sampleRateHz);
        tracking.ResidualCFOEstimateSource = ...
            "dmrs_reference_symbol_phase_slope_" + string(source);
    elseif any(method == ["cyclic_prefix", "cp"])
        [residualHz, residualInfo] = ...
            sixgr.phy.rx.estimateCFOFromCyclicPrefix( ...
            rxWaveform, ofdmInfo, sampleRateHz);
        tracking.ResidualCFOEstimateSource = ...
            "cyclic_prefix_" + string(source);
    else
        tracking.ResidualCFOEstimateSource = ...
            "unsupported_residual_cfo_method_" + method;
        return;
    end
    if logical(sixgr.util.structGet(residualInfo, "EstimateAvailable", false)) && isfinite(double(residualHz))
        tracking.ResidualCFOEstimate_Hz = double(residualHz);
    end
catch
    tracking.ResidualCFOEstimateSource = ...
        tracking.ResidualCFOEstimateSource + "_failed";
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

function delay = localResolveKnownTimingDelaySamples(cfg, tracking, sampleRateHz)
delay = double(sixgr.util.structGet(tracking, "KnownTimingDelay_samples", NaN));
if isfinite(delay)
    return;
end
delay = double(sixgr.util.structGet(cfg, "phy.rx.knownTimingDelay_samples", NaN));
if isfinite(delay)
    return;
end
filterDelay = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelFilterDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelFilterDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelTrimSamples", 0))));
if ~isfinite(filterDelay)
    filterDelay = 0;
end
pathDelay = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelPathDelay_samples", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelPathDelay_samples", NaN)));
if ~isfinite(pathDelay)
    padSamples = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelPadSamples", ...
        sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelPadSamples", NaN)));
    trimSamples = double(sixgr.util.structGet(cfg, "lls6g.receiverSync.ChannelTrimSamples", ...
        sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeChannelTrimSamples", filterDelay)));
    if isfinite(padSamples) && isfinite(trimSamples)
        pathDelay = max(0, padSamples - trimSamples);
    else
        pathDelay = 0;
    end
end
propDelay_s = double(sixgr.util.structGet(cfg, "channel.propagationDelay_s", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingPropagationDelay_s", NaN)));
propDelaySamples = 0;
if isfinite(propDelay_s) && isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0
    propDelaySamples = max(0, double(propDelay_s) * double(sampleRateHz));
end
delay = max(0, double(filterDelay)) + max(0, double(pathDelay)) + double(propDelaySamples);
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
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
fs = double(sampling.SampleRateHz);
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
        "ReferenceSymbols", refSym, ...
        "ChannelEstimateDomain", "pusch_dmrs_effective_layer_domain");
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
if scheme ~= "codebook" || ~isfinite(tpmi) || size(Hport, 3) <= nLayers
    return;
end

[Wlayer, codebookStatus] = sixgr.phy.ul.puschCodebookProjectionMatrix(nLayers, nPorts, tpmi, transformPrecoding);
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

function layerInd = localLayerIndicesFromPUSCHIndices(portInd, layerSym)
if isempty(portInd) || isempty(layerSym)
    layerInd = zeros(0, 1);
    return;
end
if isvector(layerSym)
    layerSym = layerSym(:);
end
nRows = size(layerSym, 1);
nLayers = size(layerSym, 2);
if size(portInd, 1) == nRows && size(portInd, 2) >= nLayers
    layerInd = portInd(:, 1:nLayers);
    return;
end
if numel(portInd) == numel(layerSym)
    layerInd = reshape(portInd, size(layerSym));
    return;
end
error("sixgr:phy:ul:PUSCHLayerIndexDomainMismatch", ...
    "Cannot attach PUSCH layer ordering: index shape %s does not match layer-symbol shape %s.", ...
    mat2str(size(portInd)), mat2str(size(layerSym)));
end

function qamInd = localPUSCHQAMIndicesFromAllocatedIndices( ...
        allocatedInd,ptrsInd,carrier,qamSym)
% nrPUSCHIndices describes frequency-domain allocated PUSCH resources in
% the configured antenna-port domain.  nrPUSCHDecode returns QAM symbols
% in the layer domain, so the number of columns need not match when the
% number of logical ports exceeds the scheduled rank.
% With PT-RS enabled, nrPUSCHDecode returns the QAM-domain data symbols
% after removing PT-RS-reserved coordinates (and after transform
% deprecoding when requested).  Preserve an exact ordering map by removing
% those same runtime PT-RS coordinates from every layer column.
qamInd = allocatedInd;
if isempty(ptrsInd) || isempty(allocatedInd)
    return;
end
K = double(carrier.NSizeGrid)*12;
L = double(carrier.SymbolsPerSlot);
plane = K*L;
allocatedBase = mod(double(allocatedInd)-1,plane)+1;
ptrsBase = unique(mod(double(ptrsInd(:))-1,plane)+1);
keepRows = ~any(ismember(allocatedBase,ptrsBase),2);
candidate = allocatedInd(keepRows,:);
if isvector(qamSym)
    qamShape = [numel(qamSym) 1];
else
    qamShape = size(qamSym);
end
expectedRows = qamShape(1);
expectedLayers = qamShape(2);
if size(candidate,1) ~= expectedRows || size(candidate,2) < expectedLayers
    error("sixgr:phy:ul:PUSCHQAMIndexDomainMismatch", ...
        "Removing the exact PT-RS coordinates from PUSCH indices produced " + ...
        "%d layer indices (allocated shape %s, candidate shape %s, removed rows %d), " + ...
        "but the decoded QAM domain requires %d ordered rows and %d layer columns " + ...
        "with shape %s.", ...
        numel(candidate),mat2str(size(allocatedInd)),mat2str(size(candidate)), ...
        size(allocatedInd,1)-size(candidate,1),expectedRows,expectedLayers, ...
        mat2str(size(qamSym)));
end
qamInd = candidate;
end

function [layerSym, info] = localResolvePUSCHLayerEqualizedSymbols(eqSym, puschRxSym, pusch)
eqSym = localEnsureSymbolMatrix(eqSym);
puschRxSym = localEnsureSymbolMatrix(puschRxSym);
nLayers = localObjectFiniteScalar(pusch, "NumLayers", size(eqSym, 2));
nPorts = localObjectFiniteScalar(pusch, "NumAntennaPorts", size(eqSym, 2));
tpmi = localObjectFiniteScalar(pusch, "TPMI", NaN);
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", ""))));
nLayers = max(1, round(double(nLayers)));
nPorts = max(1, round(double(nPorts)));
info = struct( ...
    "Status", "native_equalizer_layer_symbols", ...
    "NumLayers", double(nLayers), ...
    "NumPorts", double(nPorts), ...
    "TPMI", double(tpmi));

if ~isempty(eqSym) && size(eqSym, 2) == nLayers
    layerSym = eqSym;
    return;
end
if ~isempty(puschRxSym) && size(puschRxSym, 2) == nLayers
    layerSym = puschRxSym;
    info.Status = "nrPUSCHDecode_layer_symbol_estimates";
    return;
end
if scheme == "codebook" && ~isempty(eqSym) && size(eqSym, 2) == nPorts && nPorts > nLayers
    [~, status, ~, Winv] = sixgr.phy.ul.puschCodebookProjectionMatrix(nLayers, nPorts, tpmi, transformPrecoding);
    if isempty(Winv)
        error("sixgr:phy:ul:PUSCHEqualizedDomainUnsupported", ...
            "Cannot derive layer-domain equalized PUSCH symbols: %s.", char(string(status)));
    end
    layerSym = eqSym * Winv;
    info.Status = string(status) + "_inverse_projected_equalized_symbols";
    return;
end
error("sixgr:phy:ul:PUSCHEqualizedDomainMismatch", ...
    "PUSCH equalized symbol domain mismatch: equalized shape %s, decoder symbol shape %s, NumLayers=%d, NumPorts=%d.", ...
    mat2str(size(eqSym)), mat2str(size(puschRxSym)), nLayers, nPorts);
end

function [rxPUSCH, rxPUSCHInd, rxDMRSInd, rxDMRSSym, info] = ...
        localResolvePUSCHEffectiveRxReference(carrier, pusch, puschInd, dmrsInd, dmrsSym)
rxPUSCH = pusch;
rxPUSCHInd = puschInd;
rxDMRSInd = dmrsInd;
rxDMRSSym = dmrsSym;
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", ""))));
info = struct( ...
    "Applied", false, ...
    "Status", "native_noncodebook_effective_channel", ...
    "TPMI", double(localObjectValue(pusch, "TPMI", NaN)), ...
    "EffectiveTxPorts", double(localObjectValue(pusch, "NumLayers", 1)), ...
    "PhysicalTxPorts", double(localObjectValue(pusch, "NumAntennaPorts", 1)));
if scheme ~= "codebook"
    return;
end
% nrPUSCHConfig is a value object; assignment preserves the caller-owned
% runtime configuration while materializing a receiver-only view.
rxPUSCH = pusch;
rxPUSCH.TransmissionScheme = "nonCodebook";
try
    [rxPUSCHInd, ~] = nrPUSCHIndices(carrier, rxPUSCH, "IndexStyle", "index");
catch
    rxPUSCHInd = nrPUSCHIndices(carrier, rxPUSCH);
end
try
    rxDMRSInd = nrPUSCHDMRSIndices(carrier, rxPUSCH, "IndexStyle", "index");
catch
    rxDMRSInd = nrPUSCHDMRSIndices(carrier, rxPUSCH);
end
rxDMRSSym = nrPUSCHDMRS(carrier, rxPUSCH);
if size(rxPUSCHInd, 2) ~= double(pusch.NumLayers) || ...
        size(rxDMRSSym, 2) ~= double(pusch.NumLayers)
    error("sixgr:phy:ul:PUSCHEffectiveReferenceShapeMismatch", ...
        "Codebook PUSCH effective references must expose NumLayers=%d columns.", ...
        double(pusch.NumLayers));
end
info.Applied = true;
info.Status = "codebook_dmrs_precoder_effective_layer_channel_estimation";
end

function [decoderSym, info] = localResolvePUSCHDecoderInputSymbols(eqSym, layerSym, pusch)
eqSym = localEnsureSymbolMatrix(eqSym);
layerSym = localEnsureSymbolMatrix(layerSym);
nLayers = max(1, round(double(localObjectFiniteScalar(pusch, "NumLayers", size(layerSym, 2)))));
nPorts = max(1, round(double(localObjectFiniteScalar(pusch, "NumAntennaPorts", size(eqSym, 2)))));
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", ""))));
info = struct( ...
    "Status", "layer_equalized_symbols_for_nrPUSCHDecode", ...
    "Domain", "layer", ...
    "NumLayers", double(nLayers), ...
    "NumPorts", double(nPorts));

if scheme == "codebook" && ~isempty(eqSym) && size(eqSym, 2) == nPorts && nPorts > nLayers
    decoderSym = eqSym;
    info.Status = "port_equalized_symbols_for_native_codebook_nrPUSCHDecode";
    info.Domain = "port";
    return;
end

decoderSym = layerSym;
if isempty(decoderSym)
    error("sixgr:phy:ul:PUSCHDecoderInputUnavailable", ...
        "PUSCH decoder input symbols are unavailable after equalization.");
end
end

function [qamSym, info] = localResolvePUSCHQAMEqualizedSymbols(puschRxSym, layerSym)
puschRxSym = localEnsureSymbolMatrix(puschRxSym);
layerSym = localEnsureSymbolMatrix(layerSym);
info = struct( ...
    "Status", "nrPUSCHDecode_qam_symbol_estimates", ...
    "Source", "nrPUSCHDecode_second_output", ...
    "FallbackUsed", false);

if ~isempty(puschRxSym)
    if isempty(layerSym) || size(puschRxSym, 2) == size(layerSym, 2)
        qamSym = puschRxSym;
        return;
    end
    if ~isempty(layerSym) && numel(puschRxSym) == numel(layerSym)
        qamSym = reshape(puschRxSym(:), size(layerSym, 2), []).';
        info.Status = "nrPUSCHDecode_qam_symbol_estimates_reshaped_to_layer_matrix";
        return;
    end
    error("sixgr:phy:ul:PUSCHQAMSymbolDomainMismatch", ...
        "PUSCH decoder QAM symbol estimate shape %s does not match layer-domain symbol shape %s.", ...
        mat2str(size(puschRxSym)), mat2str(size(layerSym)));
end

qamSym = layerSym;
info.Status = "nrPUSCHDecode_qam_symbol_estimates_unavailable_using_layer_equalized_symbols";
info.Source = "layer_equalized_symbols";
info.FallbackUsed = true;
end

function x = localEnsureSymbolMatrix(x)
if isempty(x)
    return;
end
if iscell(x)
    x = x{1};
end
if isvector(x)
    x = x(:);
end
end

function info = localPUSCHProjectionInfo(status)
info = struct( ...
    "Applied", false, ...
    "Status", char(string(status)), ...
    "TPMI", NaN, ...
    "NumPorts", NaN, ...
    "NumLayers", NaN);
end

function info = localEstimatePUSCHDMRSPostEqResidual(rxGrid, Hest, dmrsInd, dmrsSym, ...
        nVar, equalizerAlg, Rint, RIncludesNoise, pusch)
info = struct( ...
    "Available", false, ...
    "Source", "post_equalization_dmrs_residual_unavailable", ...
    "Status", "unavailable", ...
    "NAReason", "not_computed", ...
    "NoiseVariance", NaN, ...
    "SINR_dB", NaN, ...
    "PerLayerSINR_dB", NaN, ...
    "ResidualMSE", NaN, ...
    "ReferencePower", NaN, ...
    "SampleCount", 0, ...
    "EqualizerAlgorithm", char(string(equalizerAlg)), ...
    "CovarianceSource", "not_used", ...
    "CovarianceIncludesNoise", false, ...
    "NumLayers", NaN, ...
    "NumPorts", NaN);

if isempty(rxGrid) || isempty(Hest) || isempty(dmrsInd) || isempty(dmrsSym)
    info.NAReason = "missing_rx_grid_hest_or_dmrs_reference";
    return;
end
if ~(isscalar(double(nVar)) && isfinite(double(nVar)) && double(nVar) > 0)
    info.NAReason = "invalid_pre_equalization_noise_variance";
    return;
end

try
    [rxRef, hRef] = nrExtractResources(dmrsInd, rxGrid, Hest);
catch ME
    info.NAReason = "dmrs_resource_extraction_failed:" + string(ME.identifier);
    return;
end
if isempty(rxRef) || isempty(hRef)
    info.NAReason = "empty_dmrs_resource_extraction";
    return;
end
if ndims(hRef) == 2
    hRef = reshape(hRef, size(hRef, 1), size(hRef, 2), 1);
end

[Rpilot, covInfo] = localPUSCHDMRSPilotCovariance(Rint, RIncludesNoise, size(rxRef, 2));
args = {"Algorithm", equalizerAlg};
if ~isempty(Rpilot)
    args = [args, {"Rint", Rpilot, "RIncludesNoise", logical(RIncludesNoise)}]; %#ok<AGROW>
end
try
    [eqRef, ~, eqInfo] = sixgr.phy.rx.mimoDetect(rxRef, hRef, double(nVar), args{:});
catch ME
    info.NAReason = "dmrs_post_equalization_failed:" + string(ME.identifier);
    return;
end
eqRef = localEnsureSymbolMatrix(eqRef);
refSym = localEnsureSymbolMatrix(dmrsSym);
[refSym, eqRef, alignInfo] = localAlignPUSCHDMRSSymbols(refSym, eqRef);
if ~logical(alignInfo.Available)
    info.NAReason = char(string(alignInfo.NAReason));
    return;
end

valid = isfinite(real(eqRef)) & isfinite(imag(eqRef)) & ...
    isfinite(real(refSym)) & isfinite(imag(refSym));
if ~any(valid(:))
    info.NAReason = "dmrs_post_equalization_residual_has_no_finite_pairs";
    return;
end
err = eqRef - refSym;
err(~valid) = NaN;
refUse = refSym;
refUse(~valid) = NaN;
residualByLayer = mean(abs(err).^2, 1, "omitnan");
signalByLayer = mean(abs(refUse).^2, 1, "omitnan");
good = isfinite(residualByLayer) & residualByLayer >= 0 & ...
    isfinite(signalByLayer) & signalByLayer > 0;
if ~any(good)
    info.NAReason = "dmrs_post_equalization_residual_invalid_power";
    return;
end
noiseVar = mean(max(residualByLayer(good), eps), "omitnan");
signalPower = mean(signalByLayer(good), "omitnan");
sinrByLayer = signalByLayer(good) ./ max(residualByLayer(good), eps);
sinr_dB = 10 * log10(exp(mean(log(max(sinrByLayer, eps)), "omitnan")));

info.Available = true;
info.Source = "post_equalization_sinr_from_dmrs_residual_bound";
info.Status = "OK";
info.NAReason = "";
info.BoundKind = "dmrs_residual";
info.BoundSourceToken = "dmrs_residual";
info.BoundDescription = "dmrs_post_eq_residual";
info.NoiseVariance = double(max(noiseVar, eps));
info.SINR_dB = double(sinr_dB);
perLayer = NaN(1, size(eqRef, 2));
perLayer(good) = 10 .* log10(max(sinrByLayer, eps));
info.PerLayerSINR_dB = double(perLayer);
info.ResidualMSE = double(noiseVar);
info.ReferencePower = double(signalPower);
info.SampleCount = double(nnz(valid));
info.EqualizerAlgorithm = char(string(sixgr.util.structGet(eqInfo, "AlgorithmUsed", equalizerAlg)));
info.CovarianceSource = char(string(covInfo.Source));
info.CovarianceIncludesNoise = logical(covInfo.IncludesNoise);
info.NumLayers = double(localObjectFiniteScalar(pusch, "NumLayers", size(eqRef, 2)));
info.NumPorts = double(size(eqRef, 2));
end

function info = localEstimatePUSCHDecisionDirectedPostEqResidual(layerEqSym, pusch)
info = struct( ...
    "Available", false, ...
    "Source", "post_equalization_decision_residual_unavailable", ...
    "Status", "unavailable", ...
    "NAReason", "not_computed", ...
    "BoundKind", "decision_residual", ...
    "BoundSourceToken", "decision_directed_symbol_residual", ...
    "BoundDescription", "decision_directed_data_symbol_residual", ...
    "NoiseVariance", NaN, ...
    "SINR_dB", NaN, ...
    "PerLayerSINR_dB", NaN, ...
    "ResidualMSE", NaN, ...
    "ReferencePower", NaN, ...
    "SampleCount", 0, ...
    "Modulation", "", ...
    "NumLayers", NaN);
layerEqSym = localEnsureSymbolMatrix(layerEqSym);
if isempty(layerEqSym)
    info.NAReason = "empty_layer_equalized_symbols";
    return;
end
if logical(localObjectValue(pusch, "TransformPrecoding", false))
    info.NAReason = "decision_directed_qam_residual_invalid_before_dfts_ofdm_inverse_transform";
    return;
end
modulation = string(localObjectValue(pusch, "Modulation", ""));
info.Modulation = char(modulation);
[constellation, constInfo] = localPUSCHDecisionConstellation(modulation);
if isempty(constellation)
    info.NAReason = char(string(constInfo.NAReason));
    return;
end

nLayers = size(layerEqSym, 2);
residualByLayer = NaN(1, nLayers);
signalByLayer = NaN(1, nLayers);
sampleCount = 0;
constellation = double(constellation(:));
for layer = 1:nLayers
    x = layerEqSym(:, layer);
    valid = isfinite(real(x)) & isfinite(imag(x));
    x = double(x(valid));
    if isempty(x)
        continue;
    end
    d2 = abs(x - reshape(constellation, 1, [])).^2;
    [~, idx] = min(d2, [], 2);
    nearest = constellation(idx);
    gainDen = sum(abs(nearest).^2, "omitnan");
    if isfinite(gainDen) && gainDen > 0
        gain = sum(x(:) .* conj(nearest(:)), "omitnan") ./ gainDen;
    else
        gain = NaN;
    end
    if isfinite(real(gain)) && isfinite(imag(gain)) && abs(gain) > 0
        fitted = gain .* nearest(:);
    else
        fitted = nearest(:);
    end
    err = x(:) - fitted(:);
    residualByLayer(layer) = mean(abs(err).^2, "omitnan");
    signalByLayer(layer) = mean(abs(fitted).^2, "omitnan");
    sampleCount = sampleCount + numel(x);
end
good = isfinite(residualByLayer) & residualByLayer >= 0 & ...
    isfinite(signalByLayer) & signalByLayer > 0;
if ~any(good)
    info.NAReason = "decision_directed_residual_invalid_power";
    return;
end
noiseVar = mean(max(residualByLayer(good), eps), "omitnan");
signalPower = mean(signalByLayer(good), "omitnan");
sinrByLayer = signalByLayer(good) ./ max(residualByLayer(good), eps);
sinr_dB = 10 * log10(exp(mean(log(max(sinrByLayer, eps)), "omitnan")));
perLayer = NaN(1, nLayers);
perLayer(good) = 10 .* log10(max(sinrByLayer, eps));

info.Available = true;
info.Source = "post_equalization_sinr_from_decision_directed_symbol_residual_bound";
info.Status = "OK";
info.NAReason = "";
info.NoiseVariance = double(max(noiseVar, eps));
info.SINR_dB = double(sinr_dB);
info.PerLayerSINR_dB = double(perLayer);
info.ResidualMSE = double(noiseVar);
info.ReferencePower = double(signalPower);
info.SampleCount = double(sampleCount);
info.NumLayers = double(nLayers);
end

function [constellation, info] = localPUSCHDecisionConstellation(modulation)
constellation = [];
info = struct("NAReason", "unsupported_modulation");
token = upper(strrep(strrep(char(string(modulation)), "-", ""), " ", ""));
switch token
    case "QPSK"
        qm = 2;
        modName = "QPSK";
    case "16QAM"
        qm = 4;
        modName = "16QAM";
    case "64QAM"
        qm = 6;
        modName = "64QAM";
    case "256QAM"
        qm = 8;
        modName = "256QAM";
    otherwise
        info.NAReason = "decision_directed_residual_unsupported_modulation_" + string(modulation);
        return;
end
M = 2 ^ qm;
bits = zeros(M * qm, 1, "int8");
for symIdx = 0:M-1
    base = symIdx * qm;
    for bitIdx = 1:qm
        bits(base + bitIdx) = int8(bitget(uint32(symIdx), qm - bitIdx + 1));
    end
end
try
    constellation = nrSymbolModulate(bits, char(modName));
catch ME
    constellation = [];
    info.NAReason = "nrSymbolModulate_failed:" + string(ME.identifier);
end
end

function [Rpilot, info] = localPUSCHDMRSPilotCovariance(Rint, RIncludesNoise, nRx)
Rpilot = [];
info = struct("Source", "white_noise_variance", "IncludesNoise", false);
if isempty(Rint) || ~isnumeric(Rint)
    return;
end
R = double(Rint);
if ismatrix(R) && size(R, 1) == nRx && size(R, 2) == nRx
    Rpilot = (R + R') ./ 2;
    info.Source = "static_receiver_covariance_reused_for_dmrs_residual_bound";
    info.IncludesNoise = logical(RIncludesNoise);
end
end

function [refSym, eqSym, info] = localAlignPUSCHDMRSSymbols(refSym, eqSym)
info = struct("Available", false, "NAReason", "not_computed");
if isempty(refSym) || isempty(eqSym)
    info.NAReason = "empty_dmrs_reference_or_equalized_symbols";
    return;
end
if isequal(size(refSym), size(eqSym))
    info.Available = true;
    info.NAReason = "";
    return;
end
if numel(refSym) == numel(eqSym)
    refSym = reshape(refSym(:), size(eqSym));
    info.Available = true;
    info.NAReason = "";
    return;
end
if size(refSym, 2) == 1 && size(eqSym, 2) > 1 && mod(size(refSym, 1), size(eqSym, 2)) == 0 && ...
        numel(refSym) >= numel(eqSym)
    refSym = reshape(refSym(1:numel(eqSym)), size(eqSym));
    info.Available = true;
    info.NAReason = "";
    return;
end
info.NAReason = sprintf("dmrs_reference_shape_%s_does_not_match_equalized_shape_%s", ...
    mat2str(size(refSym)), mat2str(size(eqSym)));
end

function [postEqSINR_dB, postEqSINRPerRE_dB, info] = localApplyPUSCHDMRSPostEqSINRBound( ...
        postEqSINR_dB, postEqSINRPerRE_dB, info, dmrsInfo)
if ~(isstruct(dmrsInfo) && logical(sixgr.util.structGet(dmrsInfo, "Available", false)))
    return;
end
dmrsSINR = double(sixgr.util.structGet(dmrsInfo, "SINR_dB", NaN));
if ~(isscalar(dmrsSINR) && isfinite(dmrsSINR))
    return;
end
boundKind = char(string(sixgr.util.structGet(dmrsInfo, "BoundKind", "dmrs_residual")));
boundToken = char(string(sixgr.util.structGet(dmrsInfo, "BoundSourceToken", boundKind)));
boundDescription = char(string(sixgr.util.structGet(dmrsInfo, "BoundDescription", boundKind)));
oldSINR = double(postEqSINR_dB);
oldSource = string(sixgr.util.structGet(info, "Source", "post_equalization_sinr_from_equalizer_channel_estimate"));
oldStatus = string(sixgr.util.structGet(info, "ValueStatus", "unavailable"));
oldReason = string(sixgr.util.structGet(info, "NAReason", ""));
if ~(isscalar(oldSINR) && isfinite(oldSINR)) || dmrsSINR < oldSINR
    if ~(isscalar(oldSINR) && isfinite(oldSINR))
        oldSINR = NaN;
    end
    postEqSINR_dB = double(dmrsSINR);
    if ~isempty(postEqSINRPerRE_dB)
        postEqSINRPerRE_dB = min(double(postEqSINRPerRE_dB), double(dmrsSINR));
    end
    perLayer = double(sixgr.util.structGet(info, "PerLayerSINR_dB", NaN));
    dmrsPerLayer = double(sixgr.util.structGet(dmrsInfo, "PerLayerSINR_dB", NaN));
    if ~isempty(dmrsPerLayer) && any(isfinite(dmrsPerLayer(:)))
        if isscalar(perLayer) && ~(isfinite(perLayer))
            perLayer = dmrsPerLayer;
        elseif numel(perLayer) == numel(dmrsPerLayer)
            perLayer = min(perLayer, dmrsPerLayer);
        else
            perLayer = repmat(double(dmrsSINR), 1, max(1, numel(perLayer)));
        end
    else
        perLayer = repmat(double(dmrsSINR), 1, max(1, numel(perLayer)));
    end
    info.PerLayerSINR_dB = double(perLayer);
    info.SINR_dB = double(postEqSINR_dB);
    info.RawEqualizerSINR_dB = double(oldSINR);
    info.UnboundedSource = char(oldSource);
    info.UnboundedValueStatus = char(oldStatus);
    info.UnboundedNAReason = char(oldReason);
    info.Source = "post_equalization_sinr_from_" + string(boundToken) + "_bounded_equalizer_channel_estimate";
    info.ValueRole = "measured_post_equalization_scheduling_input";
    info.ValueStatus = "OK_" + string(boundKind) + "_bounded";
    info.NAReason = sprintf("equalizer_sinr_%s_dB_bounded_by_%s_%.6g_dB", ...
        localFiniteDisplay(oldSINR), boundDescription, double(dmrsSINR));
    info.DMRSResidualBoundApplied = true;
    info.DMRSResidualSINR_dB = double(dmrsSINR);
    info.DMRSResidualNoiseVariance = double(sixgr.util.structGet(dmrsInfo, "NoiseVariance", NaN));
    info.ReceiverResidualBoundKind = char(string(boundKind));
    info.ReceiverResidualBoundSource = char(string(sixgr.util.structGet(dmrsInfo, "Source", "")));
end
end

function [nVarOut, info] = localApplyPUSCHDMRSPostEqNoiseBound(nVarIn, info, dmrsInfo)
nVarOut = double(nVarIn);
if ~(isstruct(dmrsInfo) && logical(sixgr.util.structGet(dmrsInfo, "Available", false)))
    return;
end
dmrsNVar = double(sixgr.util.structGet(dmrsInfo, "NoiseVariance", NaN));
if ~(isscalar(dmrsNVar) && isfinite(dmrsNVar) && dmrsNVar > 0)
    return;
end
if ~(isscalar(nVarOut) && isfinite(nVarOut) && nVarOut > 0) || dmrsNVar > nVarOut
    old = nVarOut;
    boundKind = char(string(sixgr.util.structGet(dmrsInfo, "BoundKind", "dmrs_residual")));
    boundToken = char(string(sixgr.util.structGet(dmrsInfo, "BoundSourceToken", boundKind)));
    nVarOut = double(dmrsNVar);
    info.ValueStatus = "OK";
    info.Source = "post_equalization_" + string(boundToken) + "_noise_variance_bound";
    info.NAReason = "";
    info.PostEqualizationNoiseVar = double(nVarOut);
    info.ReductionMethod = "max_equalizer_sinr_noise_and_" + string(boundToken) + "_noise";
    info.SampleCount = double(max(1, sixgr.util.structGet(dmrsInfo, "SampleCount", 1)));
    info.DMRSResidualBoundApplied = true;
    info.DMRSResidualNoiseVariance = double(dmrsNVar);
    info.UnboundedPostEqualizationNoiseVar = double(old);
    info.ReceiverResidualBoundKind = char(string(boundKind));
end
end

function txt = localFiniteDisplay(value)
if isscalar(value) && isfinite(value)
    txt = sprintf("%.6g", double(value));
else
    txt = "NaN";
end
end

function [nVarForDecode, info] = localResolvePUSCHDecoderNoiseVariance(nVarPreEq, nVarPostEq, postInfo, cfg)
% Keep nrPUSCHDecode aligned with the DL receiver convention: demapper LLRs
% are scaled exactly once by the effective post-equalization noise variance.
pre = double(localScalarOrNaN(nVarPreEq));
post = double(localScalarOrNaN(nVarPostEq));
postSource = char(string(sixgr.util.structGet(postInfo, "Source", "")));
postMethod = char(string(sixgr.util.structGet(postInfo, "ReductionMethod", "")));
postSampleCount = double(sixgr.util.structGet(postInfo, "SampleCount", 0));
configuredMode = lower(string(sixgr.util.structGet(cfg, ...
    "phy.pusch.measurements.decoderNoiseVarianceMode", "post_equalization")));
if ~any(configuredMode == ["post_equalization","pre_equalization"])
    error("sixgr:phy:ul:InvalidDecoderNoiseVarianceMode", ...
        "phy.pusch.measurements.decoderNoiseVarianceMode must be " + ...
        "'post_equalization' or 'pre_equalization', not '%s'.",configuredMode);
end
info = struct( ...
    "ValueStatus", "unavailable", ...
    "Source", "pusch_decoder_noise_variance_unavailable", ...
    "ValueRole", "pusch_decoder_llr_noise_variance", ...
    "NAReason", "invalid_noise_variance", ...
    "PreEqualizationNoiseVar", double(pre), ...
    "PostEqualizationNoiseVar", double(post), ...
    "ReductionMethod", "", ...
    "SampleCount", 0, ...
    "Convention", configuredMode + "_variance_only", ...
    "ConfiguredMode", configuredMode, ...
    "PostEqualizationDiagnosticSource", postSource, ...
    "PostEqualizationDiagnosticReductionMethod", postMethod, ...
    "PostEqualizationDiagnosticSampleCount", double(postSampleCount), ...
    "Domain", "post_equalization_decoder_symbol_domain");

if configuredMode == "post_equalization" && localValidNoiseScalar(post)
    nVarForDecode = double(post);
    info.ValueStatus = "OK";
    info.Source = "post_equalization_sinr_decoder_noise_variance";
    info.NAReason = "";
    info.ReductionMethod = postMethod;
    info.SampleCount = double(max(postSampleCount, 1));
    return;
end

if configuredMode == "pre_equalization" && localValidNoiseScalar(pre)
    nVarForDecode = double(pre);
    info.ValueStatus = "OK";
    info.Source = "configured_pre_equalization_noise_variance";
    info.NAReason = "";
    info.ReductionMethod = "configured_pre_equalization_noise_variance";
    info.SampleCount = 1;
    info.Domain = "pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode";
    return;
end

strictRequired = logical(sixgr.util.structGet(cfg,"run.strictNoiseVarianceRequired",false));
if strictRequired
    error("sixgr:phy:ul:ConfiguredDecoderNoiseVarianceUnavailable", ...
        "Configured PUSCH decoder-noise mode '%s' has no finite positive " + ...
        "variance in its required domain (pre=%g, post=%g).", ...
        configuredMode,pre,post);
end
if localValidNoiseScalar(post)
    nVarForDecode = double(post);
    info.ValueStatus = "OK_non_strict_fallback";
    info.Source = "non_strict_post_equalization_noise_variance_fallback";
    info.NAReason = "configured_domain_unavailable";
    info.ReductionMethod = postMethod;
    info.SampleCount = double(max(postSampleCount,1));
elseif localValidNoiseScalar(pre)
    nVarForDecode = double(pre);
    info.ValueStatus = "OK_non_strict_fallback";
    info.Source = "non_strict_pre_equalization_noise_variance_fallback";
    info.NAReason = "configured_domain_unavailable";
    info.ReductionMethod = "explicit_non_strict_pre_equalization_fallback";
    info.SampleCount = 1;
    info.Domain = "pre_equalization_channel_estimator_noise_variance_for_nrPUSCHDecode";
else
    nVarForDecode = double(max(eps,realmin));
end
end

function tf = localValidNoiseScalar(value)
value = double(value);
tf = isscalar(value) && isfinite(value) && value > 0;
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

function layouts = localResolveRxCodingLayouts(layoutIn, phyGrant, direction, ...
        trBlkSize, targetCodeRate, rv, modulation, numLayers, rateMatchedBits)
nCodewords = numel(trBlkSize);
[layerCounts, ~] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(numLayers);
if numel(layerCounts) ~= nCodewords
    error("sixgr:phy:ul:PUSCHCodingLayoutMismatch", ...
        "NumLayers=%d implies %d codeword(s), but %d transport block(s) were supplied.", ...
        numLayers, numel(layerCounts), nCodewords);
end
if iscell(layoutIn)
    layouts = reshape(layoutIn, 1, []);
elseif nCodewords == 1 && isstruct(layoutIn) && ...
        ~isempty(fieldnames(layoutIn)) && isfield(layoutIn, "RateMatchPositionMap")
    layouts = {layoutIn};
else
    layouts = cell(1, nCodewords);
end
grantLayout = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
if nCodewords == 1 && isempty(layouts{1}) && isstruct(grantLayout) && ...
        ~isempty(fieldnames(grantLayout)) && isfield(grantLayout, "RateMatchPositionMap")
    layouts{1} = grantLayout;
elseif nCodewords > 1 && isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
    error("sixgr:phy:ul:PUSCHFrozenGrantCodewordMismatch", ...
        "A high-rank PUSCH PHYGrant must expose one immutable CodingLayout per codeword.");
end
if numel(layouts) ~= nCodewords
    error("sixgr:phy:ul:PUSCHCodingLayoutMismatch", ...
        "CodingLayout must provide one contract per codeword.");
end
for cw = 1:nCodewords
    if isstruct(layouts{cw}) && ~isempty(fieldnames(layouts{cw})) && ...
            isfield(layouts{cw}, "RateMatchPositionMap")
        localAssertCodingLayoutMatches(layouts{cw}, trBlkSize(cw), rv(cw), ...
            localModulationAt(modulation, cw), layerCounts(cw), rateMatchedBits(cw));
    else
        layouts{cw} = sixgr.phy.phycode.resolveCodingLayout( ...
            "Direction", direction, ...
            "TransportBlockSize", trBlkSize(cw), ...
            "TargetCodeRate", targetCodeRate(cw), ...
            "RV", rv(cw), ...
            "Modulation", localModulationAt(modulation, cw), ...
            "NumLayers", layerCounts(cw), ...
            "RateMatchedBitCount", rateMatchedBits(cw));
    end
end
end

function localAssertCodingLayoutMatches(layout, trBlkSize, rv, modulation, numLayers, rateMatchedBits)
if double(layout.TransportBlockSize) ~= double(trBlkSize) || ...
        double(layout.RV) ~= double(rv) || ...
        ~strcmpi(char(string(layout.Modulation)), char(string(modulation))) || ...
        double(layout.NumLayers) ~= double(numLayers)
    error("sixgr:phy:ul:PUSCHCodingLayoutMismatch", ...
        "Supplied CodingLayout does not match PUSCH RX grant dimensions.");
end
layoutE = double(layout.RateMatchedBitCount);
rxE = double(rateMatchedBits);
if layoutE == rxE
    return;
end
error("sixgr:phy:ul:PUSCHCodingLayoutMismatch", ...
    "Supplied CodingLayout RateMatchedBitCount=%d does not match PUSCH demapper G=%d.", ...
    round(layoutE), round(rxE));
end

function seg = localLDPCSegmentationFromLayout(layout)
seg = struct( ...
    "TransportBlockLenWithCRC", double(layout.TransportBlockLengthWithCRC), ...
    "NumCodeBlocks", double(layout.NumCodeBlocks), ...
    "CodeBlockLength", double(layout.CodeBlockLength), ...
    "SegmentationInfo", sixgr.util.structGet(layout, "Segmentation", struct()));
end

function E = localRateMatchedBitCountFromInfo(info)
E = double(sixgr.util.structGet(info, "G", NaN));
E = E(:).';
if isempty(E) || any(~isfinite(E) | E <= 0 | E ~= fix(E))
    error("sixgr:phy:ul:PUSCHCodingLayoutMissingG", ...
        "PUSCH RX requires one positive integer rate-matched bit count per codeword.");
end
E = round(E);
end

function pusch = localEnsureTransformPrecodingOwnership(pusch, cfg)
try
    modToken = upper(strrep(char(string(pusch.Modulation)), ' ', ''));
catch
    error("sixgr:phy:ul:PUSCHMissingModulation", ...
        "An explicit PUSCH modulation is required.");
end
try
    runtimeValue = logical(pusch.TransformPrecoding);
catch ME
    error("sixgr:phy:ul:PUSCHTransformPrecodingUnavailable", ...
        "The runtime PUSCH object does not expose TransformPrecoding: %s", ME.message);
end
if (strcmp(modToken, 'PI/2-BPSK') || strcmp(modToken, 'PI2-BPSK')) && ~runtimeValue
    error("sixgr:phy:ul:PI2BPSKRequiresTransformPrecoding", ...
        "PI/2-BPSK requires TransformPrecoding=true; the receiver will not silently change the configured waveform.");
end
configuredValue = sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', []);
if ~isempty(configuredValue) && logical(configuredValue) ~= runtimeValue
    error("sixgr:phy:ul:PUSCHTransformPrecodingOwnershipMismatch", ...
        "Runtime TransformPrecoding=%d does not match configured phy.pusch.transformPrecoding=%d.", ...
        runtimeValue, logical(configuredValue));
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
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = NaN;
end
end

function sa = localSymAlloc(pusch)
try
    sa = double(pusch.SymbolAllocation);
catch
    sa = [];
end
if numel(sa) < 2
    sa = [];
else
    sa = reshape(sa(1:2), 1, 2);
end
end

function E = localResolveRxULSCHBitCount(pusch, targetCodeRate, trBlkSize, puschInfo, payload)
E = localRateMatchedBitCountFromInfo(puschInfo);
if ~payload.hasPayload()
    return;
end
if exist("nrULSCHInfo", "file") ~= 2
    error("sixgr:pusch:UCIProcessingUnavailable", ...
        "Typed UCI on PUSCH requires nrULSCHInfo from 5G Toolbox.");
end
p = payload.toStruct();
rmInfo = nrULSCHInfo(pusch, targetCodeRate, trBlkSize, ...
    p.OACK, p.OCSI1, p.OCSI2 + p.OCGUCI);
E = double(rmInfo.GULSCH);
E = E(:).';
if numel(E) ~= double(pusch.NumCodewords) || ...
        any(~isfinite(E) | E <= 0 | E ~= fix(E))
    error("sixgr:pusch:InvalidUCIBitBudget", ...
        "Typed UCI produced an invalid per-codeword GULSCH=%s.", mat2str(E));
end
end

function [ulschLLR, info] = localDemultiplexTypedUCIFromPUSCH( ...
        cwLLR, pusch, targetCodeRate, trBlkSize, expectedPayload, initialIMCS)
p = expectedPayload.toStruct();
info = struct( ...
    "Applied", false, ...
    "Source", "no_uci_payload_requested", ...
    "HARQACKBitCount", double(p.OACK), ...
    "CSI1BitCount", double(p.OCSI1), ...
    "CSI2BitCount", double(p.OCSI2), ...
    "ConfiguredGrantUCIBitCount", double(p.OCGUCI), ...
    "ExpectedHARQACKBits", int8(expectedPayload.HARQACK(:)), ...
    "ExpectedCSIPart1Bits", int8(expectedPayload.CSIPart1(:)), ...
    "ExpectedCSIPart2Bits", int8(expectedPayload.CSIPart2(:)), ...
    "ExpectedConfiguredGrantUCIBits", int8(expectedPayload.ConfiguredGrantUCI(:)), ...
    "DecodedHARQACKBits", int8([]), ...
    "DecodedCSIPart1Bits", int8([]), ...
    "DecodedCSIPart2Bits", int8([]), ...
    "DecodedConfiguredGrantUCIBits", int8([]), ...
    "HARQACKLLR", double([]), ...
    "CSI1LLR", double([]), ...
    "CSI2AndCGUCILLR", double([]), ...
    "ContentMatch", true, ...
    "CSI1ContentMatch", true, ...
    "CSI2ContentMatch", true, ...
    "ConfiguredGrantUCIContentMatch", true, ...
    "Status", "not_requested", ...
    "Reason", "");
cwLLRCells = localCellify(cwLLR);
for cw = 1:numel(cwLLRCells)
    cwLLRCells{cw} = double(cwLLRCells{cw}(:));
end
ulschLLR = cwLLRCells;
if ~expectedPayload.hasPayload()
    return;
end
if exist("nrULSCHDemultiplex", "file") ~= 2 || exist("nrUCIDecode", "file") ~= 2
    error("sixgr:pusch:UCIProcessingUnavailable", ...
        "Mandatory typed UCI demultiplex/decode requires nrULSCHDemultiplex and nrUCIDecode.");
end
try
    result = sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex( ...
        pusch, targetCodeRate, trBlkSize, localUnwrapSingleCell(cwLLRCells), ...
        expectedPayload, initialIMCS);
catch ME
    throwAsCaller(MException("sixgr:phy:ul:PUSCHUCIDemultiplexFailed", ...
        "Typed UCI demultiplex/decode failed (%s): %s", ME.identifier, ME.message));
end
ulschLLR = result.ULSCHLLR;
info.Applied = true;
info.Source = result.Source;
info.DecodedHARQACKBits = result.DecodedHARQACK;
info.DecodedCSIPart1Bits = result.DecodedCSIPart1;
info.DecodedCSIPart2Bits = result.DecodedCSIPart2;
info.DecodedConfiguredGrantUCIBits = result.DecodedConfiguredGrantUCI;
info.HARQACKLLR = result.HARQACKLLR;
info.CSI1LLR = result.CSI1LLR;
info.CSI2AndCGUCILLR = result.CSI2AndCGUCILLR;
info.ContentMatch = result.HARQACKCRCOK;
info.CSI1ContentMatch = result.CSI1CRCOK;
info.CSI2ContentMatch = result.CSI2CRCOK;
info.ConfiguredGrantUCIContentMatch = result.ConfiguredGrantUCIMatch;
% This exported status is HARQ-ACK-specific. CSI and configured-grant UCI
% retain their independent content-match fields.
if info.ContentMatch
    info.Status = "decoded_match";
else
    info.Status = "decoded_mismatch";
end
end

function [llrOut, info] = localApplyCSIToCodewordLLR(llrIn, csi, modScheme, postEqSINR_dB, nVarForDecode, nVarDecodeInfo)
llrOut = double(llrIn(:));
rawCSI = double(csi(:));
rawCSI = rawCSI(isfinite(rawCSI));
if isempty(rawCSI)
    rawMedian = NaN;
else
    rawMedian = median(rawCSI, "omitnan");
end
meanAbsLLR = mean(abs(llrOut), "omitnan");
info = struct( ...
    "ContractVersion", "PUSCHDemapperLLRScaling/v1", ...
    "Convention", "post_equalization_variance_only", ...
    "NoiseVarianceConvention", "post_equalized_symbol_variance_passed_to_nrPUSCHDecode", ...
    "Source", "nrPUSCHDecode_post_equalization_noise_variance_only", ...
    "NoiseVarianceSource", char(string(sixgr.util.structGet(nVarDecodeInfo, "Source", "post_equalization_decoder_noise_variance"))), ...
    "OutputDomain", "rate_matched_codeword_llr", ...
    "Applied", false, ...
    "Status", "not_applied_post_equalization_variance_convention", ...
    "Reason", "nrPUSCHDecode already consumed the effective post-equalization noise variance; applying CSI again would double-count reliability.", ...
    "InputKind", "not_used_for_second_weighting", ...
    "NoSecondCSIWeighting", true, ...
    "DemapperOutputAlreadyWeightedByNoiseVariance", true, ...
    "Modulation", char(string(modScheme)), ...
    "LLRCount", double(numel(llrOut)), ...
    "NoiseVariance", double(nVarForDecode), ...
    "PostEqSINR_dB", double(postEqSINR_dB), ...
    "RawCSIMedian", double(rawMedian), ...
    "WeightMedianBeforeNormalization", 1, ...
    "NormalizationScale", 1, ...
    "InputLLRMeanAbs", double(meanAbsLLR), ...
    "OutputLLRMeanAbs", double(meanAbsLLR));
end

function rx = localBuildHighRankPUSCHRx( ...
        tbBitsCell, crcErr, trBlkSize, cwLLRCell, ulschLLRCell, ...
        codingLayouts, codewordLayerMapping, codewordLLRInfo, ...
        carrier, pusch, puschInfo, puschInd, puschRxSym, ...
        Hest, estInfo, eqSym, layerEqSym, decoderInputSym, decoderInputInfo, ...
        qamEqSym, qamEqInfo, dmrsInd, dmrsSym, dmrsInfo, dmrsPowerInfo, ...
        ptrsInd, ptrsSym, ptrsInfo, cpeCorrInfo, nVar, nVarForDecode, ...
        noiseStatus, noiseTransformInfo, postEqSINR_dB, postEqSINRInfo, ...
        receiverSINR, timingResolution, rawTimingEstimate, ...
        knownTimingDelaySamples, timingEstimateForCorrection, timingEstimateSource, ...
        decodeLatency_s, maxIter, alg, llrCSIInfo, uci, ...
        enablePTRSCPECorrection, compactOutput)
tbBitsCell = reshape(tbBitsCell, 1, []);
ulschLLRCell = reshape(ulschLLRCell, 1, []);
rx = struct();
rx.ExecutionBackend = "nrPUSCHDecode_nrULSCHDecoder_two_codeword_truth";
rx.ApproximationMode = "none";
rx.TransportBlockSize = double(trBlkSize);
rx.TransportBlocks = cellfun(@(x) int8(x(:)), tbBitsCell, "UniformOutput", false);
rx.TransportBlock = rx.TransportBlocks{1};
rx.CRCError = logical(crcErr);
rx.CRCPass = logical(~crcErr);
rx.TBCRCPass = logical(~crcErr);
rx.Ok = logical(all(~crcErr));
rx.NumCodewords = 2;
rx.ActualNumCodewords = 2;
rx.CodingLayouts = codingLayouts;
rx.CodingLayout = codingLayouts{1};
rx.CodewordLayerMapping = codewordLayerMapping;
rx.CodewordLLRInfo = codewordLLRInfo;
rx.CodewordLLRCell = cwLLRCell;
rx.ULSCHCodewordLLRCell = ulschLLRCell;
rx.CodewordLLR = cwLLRCell{1};
rx.ULSCHCodewordLLR = ulschLLRCell{1};
rx.CodewordLLRCountPerCodeword = double(cellfun(@numel, cwLLRCell));
rx.ULSCHDemapperLLRCountPerCodeword = double(cellfun(@numel, ulschLLRCell));
rx.DemapperLLRCount = double(sum(cellfun(@numel, cwLLRCell)));
rx.ULSCHDemapperLLRCount = double(sum(cellfun(@numel, ulschLLRCell)));
rx.LLRAvailable = all(~cellfun(@isempty, ulschLLRCell));
rx.LLRFinite = all(cellfun(@(x) all(isfinite(double(x(:)))), ulschLLRCell));
rx.DecodeAttempted = true;
rx.DecodeUsable = true;
rx.ReceiverUsable = true;
rx.ULSCHDecodeAttempted = true;
rx.ULSCHDecodeAvailable = true;
rx.FailureReason = "";
rx.DecodeLatency_s = double(decodeLatency_s);
rx.MaxDecoderIterations = double(maxIter);
rx.LDPCDecodingAlgorithm = char(string(alg));
rx.HARQSoftCombiningApplied = false;
rx.HARQSoftCombiningPositionAware = false;
rx.HARQSoftCombiningReason = "no_prior_high_rank_soft_buffer_supplied";
rx.NoiseVar = double(nVar);
rx.PreEqualizationNoiseVar = double(nVar);
rx.DecoderNoiseVar = double(nVarForDecode);
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarDomain = "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarDomain = "resource_grid_pre_equalization";
rx.PreEqualizationNoiseVarTransformSource = char(string( ...
    sixgr.util.structGet(noiseTransformInfo, "TransformSource", "")));
rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet( ...
    noiseTransformInfo, "SampleToGridNoiseVarianceGain", NaN));
rx.ReceiverHestSINR_dB = double(receiverSINR.Value);
rx.ReceiverHestSINRSource = char(receiverSINR.Source);
rx.PostEqSINR_dB = double(postEqSINR_dB);
rx.PostEqSINRWidebanddB = double(postEqSINR_dB);
rx.PostEqSINRSource = char(string(sixgr.util.structGet( ...
    postEqSINRInfo, "Source", "measured_post_equalization_sinr")));
rx.PostEqSINRValueStatus = char(string(sixgr.util.structGet( ...
    postEqSINRInfo, "ValueStatus", "unavailable")));
rx.PostEqSINRPerLayer_dB = double(sixgr.util.structGet( ...
    postEqSINRInfo, "PerLayerSINR_dB", NaN));
rx.TimingOffset = double(rawTimingEstimate);
rx.RawTimingEstimate_samples = double(rawTimingEstimate);
rx.KnownTimingDelay_samples = double(knownTimingDelaySamples);
rx.TimingEstimateForCorrection_samples = double(timingEstimateForCorrection);
rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
rx.TimingEstimateUsed = logical(timingResolution.EstimateUsed);
rx.TimingEstimateSource = char(string(timingEstimateSource));
rx.TimingEstimateStatus = char(string(timingResolution.Status));
rx.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
rx.ChannelEstimateAttempted = true;
rx.ChannelEstimateAvailable = ~isempty(Hest);
rx.ChannelEstimateSource = "pusch_dmrs_channel_estimate";
rx.ChannelEstimateMethod = char(string(sixgr.util.structGet(estInfo, "Method", "")));
rx.ResourceExtractionAttempted = true;
rx.ResourceExtractionAvailable = ~isempty(eqSym);
rx.EqualizationAttempted = true;
rx.EqualizationAvailable = ~isempty(layerEqSym);
rx.EqualizedSymbolsForEvidence = layerEqSym;
rx.LayerEqualizedSymbolsForEvidence = layerEqSym;
rx.PortEqualizedSymbolsForEvidence = eqSym;
rx.DecoderInputSymbolsForEvidence = decoderInputSym;
rx.DecoderInputSymbolDomain = char(string(decoderInputInfo.Domain));
rx.QAMEqualizedSymbolsForEvidence = qamEqSym;
rx.QAMEqualizedSymbolSource = char(string(qamEqInfo.Status));
rx.PUSCHRxSymbolsForEvidence = puschRxSym;
rx.LLRScaleSource = string(llrCSIInfo.Source);
rx.LLRScalingConvention = char(string(llrCSIInfo.Convention));
rx.LLRDoubleWeightingGuard = logical(llrCSIInfo.NoSecondCSIWeighting);
rx.DMRSEPREDifference = dmrsPowerInfo;
rx.DMRSDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
rx.DMRSPowerBoost_dB = double(dmrsPowerInfo.DMRSPowerBoost_dB);
rx.PTRSCPECorrectionEnabled = logical(cpeCorrInfo.Enabled);
rx.PTRSConfiguredEnabled = logical(localObjectValue(pusch, "EnablePTRS", false));
rx.PTRSCPECorrectionConfigured = logical(enablePTRSCPECorrection);
rx.PTRSCPECorrectionApplied = logical(cpeCorrInfo.Enabled);
rx.PTRSCPECorrectionSymbols = double(cpeCorrInfo.NumSymbolsCorrected);
rx.PTRSMeanCPE_deg = double(cpeCorrInfo.MeanCPE_deg);
rx.PTRSCPECorrectionReason = char(string(cpeCorrInfo.NAReason));
rx.PTRSCPECorrectionStatus = char(localPTRSCorrectionStatus(cpeCorrInfo));
rx.PTRSReceiverEvidenceSource = "sixgr.phy.ul.PUSCH_Rx.ptrs_cpe";
rx.UCIOnPUSCHApplied = logical(uci.Applied);
rx.UCIOnPUSCHSource = char(string(uci.Source));
if rx.UCIOnPUSCHApplied
    rx.UCIOnPUSCHEvidenceSource = "same_waveform_pusch_rx_uci_demultiplexer";
else
    rx.UCIOnPUSCHEvidenceSource = "";
end
rx.HARQACKBitCount = double(uci.HARQACKBitCount);
rx.CSI1BitCount = double(uci.CSI1BitCount);
rx.CSI2BitCount = double(uci.CSI2BitCount);
rx.ConfiguredGrantUCIBitCount = double(uci.ConfiguredGrantUCIBitCount);
rx.ExpectedHARQACKBits = int8(uci.ExpectedHARQACKBits(:));
rx.DecodedHARQACKBits = int8(uci.DecodedHARQACKBits(:));
rx.DecodedCSIPart1Bits = int8(uci.DecodedCSIPart1Bits(:));
rx.DecodedCSIPart2Bits = int8(uci.DecodedCSIPart2Bits(:));
rx.DecodedConfiguredGrantUCIBits = int8(uci.DecodedConfiguredGrantUCIBits(:));
rx.HARQACKContentMatch = logical(uci.ContentMatch);
rx.CSI1ContentMatch = logical(uci.CSI1ContentMatch);
rx.CSI2ContentMatch = logical(uci.CSI2ContentMatch);
rx.ConfiguredGrantUCIContentMatch = logical(uci.ConfiguredGrantUCIContentMatch);
rx.HARQACKDecodeStatus = char(string(uci.Status));
if ~logical(compactOutput)
    rx.ChannelEstimate = Hest;
    rx.Carrier = carrier;
    rx.PUSCH = pusch;
    rx.PUSCHInfo = puschInfo;
    rx.PUSCHIndices = puschInd;
    rx.DMRSIndices = dmrsInd;
    rx.DMRSSymbols = dmrsSym;
    rx.DMRSInfo = dmrsInfo;
    rx.PTRSIndices = ptrsInd;
    rx.PTRSSymbols = ptrsSym;
    rx.PTRSInfo = ptrsInfo;
    rx.EqualizedSymbols = layerEqSym;
    rx.PortEqualizedSymbols = eqSym;
    rx.DecoderInputSymbols = decoderInputSym;
end
end

function cells = localCellify(value)
if iscell(value)
    cells = reshape(value, 1, []);
else
    cells = {value};
end
end

function value = localUnwrapSingleCell(cells)
if iscell(cells) && isscalar(cells)
    value = cells{1};
else
    value = cells;
end
end

function value = localModulationAt(raw, index)
if iscell(raw)
    value = char(string(raw{index}));
else
    values = string(raw);
    value = char(values(index));
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

function status = localPTRSCorrectionStatus(info)
if logical(sixgr.util.structGet(info, "Enabled", false))
    status = "explicit_ptrs_cpe_corrected_after_mimo_equalization";
else
    status = string(sixgr.util.structGet(info, "NAReason", "unavailable"));
end
end

function [waveOut, optOut, info] = localApplyScheduledReceiveCombiner(waveIn, optIn, phyGrant)
% Apply the exact scheduler-frozen UL receive preprocessor in sample space.
% Production MU-MIMO freezes an identity matrix so every antenna branch is
% retained for per-RE IRC. Explicit non-MU component probes may still supply
% a semi-unitary projection and are reported as a reduced observation.
waveOut = waveIn;
optOut = optIn;
legacy = sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot", struct());
W = optIn.ReceiveCombiningMatrix;
source = "explicit_receiver_option";
if isempty(W)
    W = sixgr.util.structGet(legacy, "MUMIMOReceiveCombiningMatrix", []);
    source = "frozen_phy_grant_legacy_snapshot";
end
expectedDigest = strtrim(string(optIn.ReceiveCombiningMatrixSHA256));
if strlength(expectedDigest) == 0
    expectedDigest = strtrim(string(sixgr.util.structGet(legacy, ...
        "MUMIMOReceiveCombiningMatrixSHA256", "")));
end
muRequired = logical(sixgr.util.structGet(legacy, "MUMIMOEnabled", false));
receiverAlgorithm = lower(strtrim(string(sixgr.util.structGet(legacy, ...
    "MUMIMOReceiverAlgorithm", ""))));
info = struct( ...
    "ContractVersion", "PUSCHScheduledReceiveCombiner/v2", ...
    "Applied", false, ...
    "Status", "not_requested", ...
    "Source", "no_scheduler_frozen_receive_combiner", ...
    "InputBranches", double(size(waveIn, 2)), ...
    "OutputBranches", double(size(waveIn, 2)), ...
    "MatrixRows", 0, ...
    "MatrixCols", 0, ...
    "MatrixSHA256", "", ...
    "ExpectedMatrixSHA256", char(expectedDigest), ...
    "OrthonormalityResidual", NaN, ...
    "InterferenceContributionProjected", false, ...
    "InterferenceCovarianceProjected", false, ...
    "NoiseVarianceInvariant", true, ...
    "FullObservationPreserved", false, ...
    "IdentityResidual", NaN, ...
    "ReceiverAlgorithm", char(receiverAlgorithm), ...
    "Domain", "receiver_sample_waveform");
if isempty(W)
    if muRequired
        error("sixgr:phy:ul:MissingMUMIMOReceiveCombiner", ...
            "A frozen UL MU-MIMO grant requires its measured receive " + ...
            "combining matrix, but the matrix is absent.");
    end
    return;
end
if ~isnumeric(W) || ~ismatrix(W) || isempty(W) || ...
        size(W, 1) ~= size(waveIn, 2) || size(W, 2) < 1
    error("sixgr:phy:ul:MUMIMOReceiveCombinerShapeMismatch", ...
        "The frozen UL MU receive combiner must be Nrx-by-Nout. " + ...
        "Received %s for an Nrx=%d waveform.", ...
        mat2str(size(W)), size(waveIn, 2));
end
W = double(W);
if any(~isfinite(real(W(:)))) || any(~isfinite(imag(W(:))))
    error("sixgr:phy:ul:MUMIMOReceiveCombinerNonfinite", ...
        "The frozen UL MU receive combiner contains nonfinite entries.");
end
digest = string(sixgr.phy.mimo.MatrixContract.digest(W));
if strlength(expectedDigest) > 0 && lower(digest) ~= lower(expectedDigest)
    error("sixgr:phy:ul:MUMIMOReceiveCombinerDigestMismatch", ...
        "Frozen UL MU receive-combiner digest %s differs from expected %s.", ...
        char(digest), char(expectedDigest));
end
gram = W' * W;
orthResidual = norm(gram - eye(size(gram)), "fro") ./ max(1, norm(gram, "fro"));
if ~(isfinite(orthResidual) && orthResidual <= 1e-8)
    error("sixgr:phy:ul:MUMIMOReceiveCombinerNotSemiUnitary", ...
        "The frozen UL MU receive combiner must be semi-unitary so the " + ...
        "scalar thermal-noise variance remains valid; residual=%.12g.", ...
        orthResidual);
end
identityResidual = Inf;
if size(W, 1) == size(W, 2)
    identityResidual = norm(W - eye(size(W)), "fro") ./ ...
        max(1, norm(eye(size(W)), "fro"));
end
fullObservationPreserved = size(W, 1) == size(W, 2) && ...
    isfinite(identityResidual) && identityResidual <= 1e-12;
if muRequired
    if receiverAlgorithm ~= "full_dimensional_per_re_irc"
        error("sixgr:phy:ul:InvalidMUMIMOReceiverAlgorithm", ...
            "A production UL MU-MIMO grant must declare " + ...
            "MUMIMOReceiverAlgorithm=full_dimensional_per_re_irc; received '%s'.", ...
            char(receiverAlgorithm));
    end
    if ~fullObservationPreserved
        error("sixgr:phy:ul:RankReducingMUMIMOReceivePreprocessor", ...
            "Production UL MU-MIMO must preserve every receiver branch for " + ...
            "per-RE IRC. Frozen matrix %s has identity residual %.12g.", ...
            mat2str(size(W)), identityResidual);
    end
end

waveOut = waveIn * conj(cast(W, "like", waveIn));
tensor = optIn.InterferenceContributionTensor;
contributionProjected = false;
if ~isempty(tensor)
    if size(tensor, 2) ~= size(W, 1)
        error("sixgr:phy:ul:MUMIMOInterferenceTensorShapeMismatch", ...
            "Interference contribution tensor has %d branches; combiner requires %d.", ...
            size(tensor, 2), size(W, 1));
    end
    projected = complex(zeros(size(tensor, 1), size(W, 2), size(tensor, 3), "like", tensor));
    Wlike = conj(cast(W, "like", tensor));
    for contributor = 1:size(tensor, 3)
        projected(:, :, contributor) = tensor(:, :, contributor) * Wlike;
    end
    optOut.InterferenceContributionTensor = projected;
    contributionProjected = true;
end
R = optIn.InterferenceCovariance;
covarianceProjected = false;
if ~isempty(R)
    if ~ismatrix(R) || size(R, 1) ~= size(W, 1) || size(R, 2) ~= size(W, 1)
        error("sixgr:phy:ul:MUMIMOInterferenceCovarianceShapeMismatch", ...
            "Interference covariance has shape %s; combiner requires %d-by-%d.", ...
            mat2str(size(R)), size(W, 1), size(W, 1));
    end
    optOut.InterferenceCovariance = W' * double(R) * W;
    covarianceProjected = true;
end
info.Applied = true;
if fullObservationPreserved
    info.Status = "applied_full_dimensional_identity_preprocessor_for_per_re_irc";
else
    info.Status = "applied_explicit_semi_unitary_reduced_observation";
end
info.Source = char(source);
info.OutputBranches = double(size(waveOut, 2));
info.MatrixRows = double(size(W, 1));
info.MatrixCols = double(size(W, 2));
info.MatrixSHA256 = char(digest);
info.OrthonormalityResidual = double(orthResidual);
info.FullObservationPreserved = logical(fullObservationPreserved);
info.IdentityResidual = double(identityResidual);
info.InterferenceContributionProjected = logical(contributionProjected);
info.InterferenceCovarianceProjected = logical(covarianceProjected);
end

function rx = localAnnotateReceiveCombiner(rx, info)
rx.MUMIMOReceiveCombinerApplied = logical(info.Applied);
rx.MUMIMOReceiveCombinerStatus = char(string(info.Status));
rx.MUMIMOReceiveCombinerSource = char(string(info.Source));
rx.MUMIMOReceiveCombinerInputBranches = double(info.InputBranches);
rx.MUMIMOReceiveCombinerOutputBranches = double(info.OutputBranches);
rx.MUMIMOReceiveCombinerMatrixRows = double(info.MatrixRows);
rx.MUMIMOReceiveCombinerMatrixCols = double(info.MatrixCols);
rx.MUMIMOReceiveCombinerMatrixSHA256 = char(string(info.MatrixSHA256));
rx.MUMIMOReceiveCombinerExpectedMatrixSHA256 = char(string(info.ExpectedMatrixSHA256));
rx.MUMIMOReceiveCombinerOrthonormalityResidual = double(info.OrthonormalityResidual);
rx.MUMIMOReceiveCombinerInterferenceContributionProjected = logical(info.InterferenceContributionProjected);
rx.MUMIMOReceiveCombinerInterferenceCovarianceProjected = logical(info.InterferenceCovarianceProjected);
rx.MUMIMOReceiveCombinerFullObservationPreserved = logical(info.FullObservationPreserved);
rx.MUMIMOReceiveCombinerIdentityResidual = double(info.IdentityResidual);
rx.MUMIMOReceiverAlgorithmApplied = char(string(info.ReceiverAlgorithm));
end

function [waveOut, info] = localTrimInactiveFastAWGNColumns(waveIn, channelToken, numTxPorts, useFastAWGNPath)
waveOut = waveIn;
numCols = max(1, size(waveIn, 2));
activeCols = localActiveWaveformColumns(waveIn);
info = struct( ...
    "OriginalColumnCount", double(numCols), ...
    "ActiveColumnCount", double(max(1, numel(activeCols))), ...
    "ActiveColumns", double(activeCols(:).'), ...
    "Trimmed", false);
if ~logical(useFastAWGNPath) || ~localIsExplicitFlatChannel(channelToken) || ...
        ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts <= 1)
    return;
end
if numCols > 1 && numel(activeCols) == 1
    waveOut = waveIn(:, activeCols);
    info.Trimmed = true;
end
end

function activeCols = localActiveWaveformColumns(waveIn)
if isempty(waveIn)
    activeCols = 1;
    return;
end
if isvector(waveIn)
    activeCols = 1;
    return;
end
energy = sum(abs(waveIn).^2, 1, "omitnan");
energy = double(reshape(energy, 1, []));
if isempty(energy)
    activeCols = 1;
    return;
end
maxEnergy = max(energy(isfinite(energy)), [], "omitnan");
if ~(isscalar(maxEnergy) && isfinite(maxEnergy) && maxEnergy > 0)
    activeCols = 1;
    return;
end
threshold = max(maxEnergy * 1e-12, eps(maxEnergy));
activeCols = find(isfinite(energy) & energy > threshold);
if isempty(activeCols)
    activeCols = 1;
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
rx.LLRScalingConvention = "";
rx.DemapperNoiseVarianceConvention = "";
rx.DemapperLLRDomain = "";
rx.LLRDoubleWeightingGuard = false;
rx.LLRNoiseVariance = NaN;
rx.EqualizedSymbolsForEvidence = complex([]);
rx.LayerEqualizedSymbolsForEvidence = complex([]);
rx.LayerEqualizedSymbols = complex([]);
rx.DecoderInputSymbolsForEvidence = complex([]);
rx.DecoderInputSymbolDomain = "unavailable";
rx.DecoderInputSymbolSource = "unavailable";
rx.EqualizedSymbolDomain = "layer";
rx.LayerSymbolOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, zeros(0, 1), "layer");
rx.QAMEqualizedSymbolsForEvidence = complex([]);
rx.PUSCHQAMSymbolsForEvidence = complex([]);
rx.PUSCHDFTInputSymbolsForEvidence = complex([]);
rx.QAMEqualizedSymbolDomain = "layer";
rx.QAMEqualizedSymbolSource = "unavailable";
rx.QAMSymbolOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, zeros(0, 1), "layer");
rx.DemapperLLRCount = 0;
rx.ULSCHDemapperLLRCount = 0;
rx.RateRecoveredLLRCount = 0;
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
    rx.DecoderInputSymbols = complex([]);
    rx.PUSCHRxSymbols = complex([]);
    rx.QAMEqualizedSymbols = complex([]);
    rx.PUSCHQAMSymbols = complex([]);
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

function [dmrsSym, info] = localApplyPUSCHDMRSEPREDifference(dmrsSym, cfg)
% The configured quantity follows the conformance-table convention:
%   data EPRE / DM-RS EPRE in dB = data EPRE - DM-RS EPRE.
path = "phy.pusch.dmrs.dataToDMRSEPREDifference_dB";
rawDifference = sixgr.util.structGet(cfg, char(path), []);
if isempty(rawDifference)
    difference_dB = 0;
    source = "default_zero_db";
else
    if ~(isnumeric(rawDifference) && isreal(rawDifference) && isscalar(rawDifference) && isfinite(rawDifference))
        error("sixgr:phy:ul:PUSCHDMRSEPREDifferenceInvalid", ...
            "%s must be a finite real numeric scalar.", char(path));
    end
    difference_dB = double(rawDifference);
    source = path;
end

configuredPowerBoost_dB = -difference_dB;
if abs(difference_dB + 3) <= 1e-12
    % TS 38.104 expresses the normative PUSCH-to-DMRS EPRE ratio as
    % -3 dB while the corresponding exact beta is sqrt(2).
    amplitudeScale = sqrt(2);
    powerScale = 2;
    scalePolicy = "ts_38_104_minus3_db_beta_sqrt2";
else
    amplitudeScale = 10.^(configuredPowerBoost_dB ./ 20);
    powerScale = amplitudeScale.^2;
    scalePolicy = "literal_configured_db_ratio";
end
if ~(isfinite(amplitudeScale) && amplitudeScale > 0 && isfinite(powerScale) && powerScale > 0)
    error("sixgr:phy:ul:PUSCHDMRSEPREDifferenceInvalid", ...
        "%s=%g dB produces a non-finite or non-positive DM-RS scale.", ...
        char(path), difference_dB);
end
realizedPowerBoost_dB = 10 .* log10(powerScale);
realizedDifference_dB = -realizedPowerBoost_dB;

dmrsSym = dmrsSym .* cast(amplitudeScale, "like", dmrsSym);
info = struct( ...
    "ContractVersion", "PUSCHDMRSEPREDifference/v1", ...
    "Source", source, ...
    "DataToDMRSEPREDifference_dB", double(difference_dB), ...
    "ConfiguredDMRSPowerBoost_dB", double(configuredPowerBoost_dB), ...
    "RealizedDataToDMRSEPREDifference_dB", double(realizedDifference_dB), ...
    "DMRSPowerBoost_dB", double(realizedPowerBoost_dB), ...
    "DMRSAmplitudeScale", double(amplitudeScale), ...
    "DMRSPowerScale", double(powerScale), ...
    "Applied", logical(abs(difference_dB) > 1e-12), ...
    "NormativeMinus3dBBetaApplied", logical(scalePolicy == "ts_38_104_minus3_db_beta_sqrt2"), ...
    "ScalePolicy", scalePolicy, ...
    "Equation", "normative_minus3_db_uses_beta_sqrt2_otherwise_10_power_minus_delta_db_over_20");
end

function featureName = localProcedureFeature(baseName, executionProfile)
switch lower(strtrim(string(executionProfile)))
    case "ra_msg3"
        featureName = "ra_msg3_" + string(baseName);
    case "ra_setup_complete"
        featureName = "ra_setup_complete_" + string(baseName);
    otherwise
        featureName = string(baseName);
end
end
