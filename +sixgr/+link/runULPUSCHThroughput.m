function out = runULPUSCHThroughput(cfg, varargin)
%RUNULPUSCHTHROUGHPUT UL PUSCH throughput/BLER at one SNR point.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumFrames", sixgr.util.structGet(cfg, "run.numFrames", 10), @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 18), @(x) isnumeric(x) && isscalar(x));
p.addParameter("InitialLinkAdaptationState", [], @(x) isempty(x) || isstruct(x));
p.addParameter("StartFrameIndex", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("StartSlotIndex", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("LiveTrialCallback", [], @(x) isempty(x) || isa(x, "function_handle"));
p.addParameter("LiveCallbackInterval", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("TransportBlockBits", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
p.addParameter("RV", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0 && x <= 3));
p.addParameter("HARQContext", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("GrantSnapshot", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("PHYGrant", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("ExecutionProfile", "", @(x) ischar(x) || isstring(x));
p.addParameter("PreviousCombinedLLR", [], @(x) isempty(x) || isnumeric(x) || isstruct(x) || iscell(x));
p.addParameter("InterferenceBundle", struct([]), @(x) isempty(x) || isstruct(x));
p.addParameter("ExpectedUCIBits", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
p.addParameter("ExpectedUCIPayload", [], @(x) isempty(x) || ...
    isa(x, "sixgr.phy.ul.pusch.PUSCHUCIPayload"));
p.addParameter("ChannelState", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("PrepareOnly", false, @(x) islogical(x) && isscalar(x));
p.addParameter("ReceivedContext", struct(), @(x) isstruct(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
numFrames = max(1, round(double(p.Results.NumFrames)));
snr_dB = double(p.Results.SNR_dB);
initialLAState = p.Results.InitialLinkAdaptationState;
startFrameIndex = max(1, round(double(p.Results.StartFrameIndex)));
startSlotIndex = max(1, round(double(p.Results.StartSlotIndex)));
liveTrialCallback = p.Results.LiveTrialCallback;
liveCallbackInterval = max(1, round(double(p.Results.LiveCallbackInterval)));
transportBlockBits = p.Results.TransportBlockBits;
rvOverride = p.Results.RV;
harqContext = p.Results.HARQContext;
grantSnapshotOverride = p.Results.GrantSnapshot;
phyGrantOverride = p.Results.PHYGrant;
previousCombinedLLR = p.Results.PreviousCombinedLLR;
interferenceBundle = p.Results.InterferenceBundle;
chStateIn = p.Results.ChannelState;
externalChannelState = isstruct(chStateIn) && isfield(chStateIn, "ContractVersion");
if ~(isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride)))
    grantSnapshotOverride = sixgr.util.structGet(harqContext, "GrantSnapshot", struct());
end
if ~(isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride)))
    phyGrantOverride = sixgr.util.structGet(grantSnapshotOverride, "PHYGrant", struct());
end
if isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride))
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrantOverride, "run_ul_pusch_throughput_entry");
    if ~(isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride)))
        grantSnapshotOverride = sixgr.util.structGet(phyGrantOverride, "LegacyGrantSnapshot", struct());
    end
    grantSnapshotOverride.PHYGrant = phyGrantOverride;
    grantSnapshotOverride.PHYGrantContextId = char(string(phyGrantOverride.GrantContextId));
end
[grantSnapshotOverride, phyGrantOverride] = localNormalizeHARQReplayGrantInputs( ...
    cfg, grantSnapshotOverride, phyGrantOverride, transportBlockBits, harqContext, snr_dB, startFrameIndex, startSlotIndex);
isRetransmission = localInferHARQReplayMode(grantSnapshotOverride, phyGrantOverride, harqContext, transportBlockBits);
if isRetransmission
    harqContext.IsRetransmission = true;
end
schedulerDrivenGrant = (isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride))) || ...
    (isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride)));
executionContract = localResolvePUSCHThroughputExecutionContract( ...
    cfg, p.Results.ExecutionProfile, schedulerDrivenGrant, ...
    grantSnapshotOverride, phyGrantOverride);
expectedUCIPayload = p.Results.ExpectedUCIPayload;
expectedUCIBits = int8([]);
if isempty(expectedUCIPayload)
    expectedUCIPayload = sixgr.util.structGet(grantSnapshotOverride, ...
        "ExpectedUCIPayload", []);
end
if isempty(expectedUCIPayload)
    expectedUCIPayload = sixgr.util.structGet(harqContext, ...
        "ExpectedUCIPayload", []);
end
if isempty(expectedUCIPayload)
    expectedUCIBits = localResolveExpectedUCIBits( ...
        p.Results.ExpectedUCIBits, grantSnapshotOverride, harqContext);
    expectedUCIPayload = sixgr.phy.ul.pusch.PUSCHUCIPayload( ...
        "HARQACK", expectedUCIBits);
elseif ~isa(expectedUCIPayload, "sixgr.phy.ul.pusch.PUSCHUCIPayload")
    error("sixgr:pusch:InvalidExpectedUCIPayload", ...
        "ExpectedUCIPayload must be a typed PUSCHUCIPayload, not a raw bit container.");
end
% The typed payload is the immutable UCI authority for this PUSCH trial.
% Keep the HARQ-ACK comparison vector aligned with that object even when
% the caller supplied the typed payload directly.  Previously this local
% was assigned only by the legacy raw-bit conversion branch and the real
% UCI-on-PUSCH path crashed after decoding.
expectedUCIBits = int8(expectedUCIPayload.HARQACK(:));

[prepareOnly, receivedCompletion, preparedTransmission, preparedBinding] = ...
    sixgr.link.validateDataStreamRequest(cfg,p.Results,"UL", ...
    executionContract.Profile,grantSnapshotOverride,phyGrantOverride);
if receivedCompletion
    executionContract.Backend = "scheduler_shared_stream_receiver";
end

out = struct();
out.Ok = false;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.NumFrames = numFrames;
out.SNR_dB = snr_dB;
out.Goodput_Mbps = NaN;
out.OfferedThroughput_Mbps = NaN;
out.CodeBlockBLER = NaN;
out.CBGBLER = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceTTI_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.DecodeLatency_ms = NaN;
out.EarlyStopRate = NaN;
out.DecoderComplexityUnits = NaN;
out.NormalizedDecoderComplexity = NaN;
out.AreaEfficiencyProxy = NaN;
out.TrialTable = localEmptyTrialTable();
out.ObservedREAllocationTable = table();
out.ConstellationSamples = table();
out.SignalDiagnostic = struct( ...
    "Available", false, ...
    "Reason", "capture_not_attempted", ...
    "Direction", "UL", ...
    "SnapshotID", "", ...
    "Metadata", struct(), ...
    "SourceTable", table());
out.HARQ = struct();
out.ExecutionProfile = executionContract.Profile;
out.ExecutionTaxonomy = executionContract.Taxonomy;
out.ExecutionBackend = executionContract.Backend;
out.ApproximationMode = "none";
out.CalibrationProvenance = executionContract.CalibrationProvenance;
out.StrictSchedulingOwnership = executionContract.Profile == "scheduler_truth";
out.TxWaveformCapture = struct();
txWaveformCaptureRequired = logical(sixgr.util.structGet(cfg, ...
    "outputs.rawIQCaptureEnabled", false)) && logical(sixgr.util.structGet( ...
    cfg, "outputs.saveRawWaveforms", false));
txWaveformCapture = struct();

configuredPUSCH = logical(sixgr.util.structGet(cfg, "phy.pusch.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "scheduled_pusch", ...
    configuredPUSCH, "sixgr.link.runULPUSCHThroughput");
if ~configuredPUSCH
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.pusch.enable=true for PUSCH coverage.");
    sixgr.perf.TimeProfiler.markSkipped("sixgr.link.runULPUSCHThroughput", "ul_pusch", ...
        "phy.pusch.enable=false");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.pusch.enable=false";
    return;
end

if exist("nrPUSCH","file") ~= 2 || exist("nrPUSCHDecode","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrPUSCH/nrPUSCHDecode for PUSCH coverage.");
    sixgr.perf.TimeProfiler.markSkipped("sixgr.link.runULPUSCHThroughput", "ul_pusch", ...
        "nrPUSCH_or_nrPUSCHDecode_unavailable");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPUSCH APIs unavailable.";
    return;
end

profNTx = localConfiguredULAntennaCount(cfg, "tx", 1);
profNRx = localConfiguredULAntennaCount(cfg, "rx", 1);
profScope = sixgr.perf.TimeProfiler.scope("sixgr.link.runULPUSCHThroughput", ...
    "Stage", "ul_pusch", ...
    "Metadata", struct( ...
    "NumFrames", double(numFrames), ...
    "NSubcarriers", double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)) * 12, ...
    "NSymbols", 14, ...
    "NRx", profNRx, ...
    "NTx", profNTx, ...
    "NLayers", double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))); %#ok<NASGU>

cfgUL = cfg;

blockErr = 0;
bitErr = 0;
bitTot = 0;
bitGood = 0;
frameCrash = 0;
firstCrashMsg = "";
if externalChannelState
    chState = chStateIn;
else
    chState = struct("Initialized", false, "UseFading", false, "Obj", [], ...
        "ChannelPadSamples", 0, "ChannelTrimSamples", 0, "WarmupSamples", 0);
end
seedBase = double(sixgr.util.structGet(cfgUL, "run.seed", 1));
chanModel = localResolveTrialChannelModel(cfgUL);
dopplerHz = double(sixgr.util.structGet(cfgUL, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgUL, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgUL, "channel.fading.maxDoppler_Hz", 0))));
cfgDyn = cfgUL;
laState = initialLAState;
slotDur_s = localSlotDuration(cfgUL);

trialSeed = NaN(numFrames,1);
trialFrame = startFrameIndex + (0:numFrames-1).';
trialSlot = startSlotIndex + (0:numFrames-1).';
% Reporting Frame is one-based; radio SFN is owned by the executed carrier.
trialSFN = NaN(numFrames,1);
trialRuntimeAbsoluteSlot0 = NaN(numFrames,1);
trialCarrierNSlot = NaN(numFrames,1);
trialCarrierNFrame = NaN(numFrames,1);
trialUEIndex = NaN(numFrames,1);
trialRNTI = NaN(numFrames,1);
trialBaseStationID = NaN(numFrames,1);
trialMCS = NaN(numFrames,1);
trialMCSValueStatus = strings(numFrames,1);
trialRV = NaN(numFrames,1);
trialHARQProcess = NaN(numFrames,1);
trialHARQRound = NaN(numFrames,1);
trialHARQNDI = NaN(numFrames,1);
trialHARQIsRetransmission = false(numFrames,1);
trialHARQNDIEpoch = NaN(numFrames,1);
trialHARQTBId = strings(numFrames,1);
trialOriginalTBSBits = NaN(numFrames,1);
trialCurrentTBSBits = NaN(numFrames,1);
trialOriginalRateMatchedBits = NaN(numFrames,1);
trialCurrentRateMatchedBits = NaN(numFrames,1);
trialEffectiveInitialCodeRate = NaN(numFrames,1);
trialEffectiveCurrentTxCodeRate = NaN(numFrames,1);
trialShortIRRetx = false(numFrames,1);
trialCodeBlockLayoutHash = strings(numFrames,1);
trialHARQContextHash = strings(numFrames,1);
trialHARQContextStatus = strings(numFrames,1);
trialPRB = NaN(numFrames,1);
trialPRBStart = NaN(numFrames,1);
trialSymbolStart = NaN(numFrames,1);
trialNumSymbols = NaN(numFrames,1);
trialLayers = NaN(numFrames,1);
trialModulation = strings(numFrames,1);
trialCodeRate = NaN(numFrames,1);
trialTB = NaN(numFrames,1);
trialCRC = NaN(numFrames,1);
trialDecIt = NaN(numFrames,1);
trialEVM = NaN(numFrames,1);
trialNMSE = NaN(numFrames,1);
trialDet = NaN(numFrames,1);
trialSINR = NaN(numFrames,1);
trialMeasuredTrialSINR = NaN(numFrames,1);
trialMeasuredSINRSource = strings(numFrames,1);
trialMeasuredTrialSINRValueRole = strings(numFrames,1);
trialMeasuredTrialSINRValueStatus = strings(numFrames,1);
trialMeasuredTrialSINRNAReason = strings(numFrames,1);
trialReceiverHestSINR = NaN(numFrames,1);
trialReceiverHestSINRSource = strings(numFrames,1);
trialReceiverHestSINRValueRole = strings(numFrames,1);
trialReceiverHestSINRValueStatus = strings(numFrames,1);
trialReceiverHestSINRNAReason = strings(numFrames,1);
trialPostEqSINR = NaN(numFrames,1);
trialPostEqSINRSource = strings(numFrames,1);
trialPostEqSINRValueRole = strings(numFrames,1);
trialPostEqSINRValueStatus = strings(numFrames,1);
trialPostEqSINRNAReason = strings(numFrames,1);
trialPostEqSINRPerLayer = strings(numFrames,1);
trialPostEqSINRRawEqualizer = NaN(numFrames,1);
trialPostEqSINRDMRSResidualBoundApplied = false(numFrames,1);
trialPostEqSINRDMRSResidual = NaN(numFrames,1);
trialPostEqDMRSResidualNoiseVar = NaN(numFrames,1);
trialPostEqDMRSResidualSource = strings(numFrames,1);
trialPostEqDecisionResidual = NaN(numFrames,1);
trialPostEqDecisionResidualNoiseVar = NaN(numFrames,1);
trialPostEqDecisionResidualSource = strings(numFrames,1);
trialEVMProxySINR = NaN(numFrames,1);
trialEVMProxySINRSource = strings(numFrames,1);
trialEVMProxySINRValueRole = strings(numFrames,1);
trialEVMProxySINRValueStatus = strings(numFrames,1);
trialEVMProxySINRNAReason = strings(numFrames,1);
trialDecoderTruthProxySINR = NaN(numFrames,1);
trialDecoderTruthProxySINRSource = strings(numFrames,1);
trialSINRValueRole = strings(numFrames,1);
trialSINRSource = strings(numFrames,1);
trialLargeScaleSINR = NaN(numFrames,1);
trialLargeScaleSINRSource = strings(numFrames,1);
trialServingRSRP = NaN(numFrames,1);
trialServingRSRPSource = strings(numFrames,1);
trialCSIRSRP = NaN(numFrames,1);
trialCSIRSRPSource = strings(numFrames,1);
trialCSIRSSI = NaN(numFrames,1);
trialCSIRSSISource = strings(numFrames,1);
trialCSIRSRQ = NaN(numFrames,1);
trialCSIRSRQSource = strings(numFrames,1);
trialULNormalizedPowerEvidence = strings(numFrames,1);
trialCQI = NaN(numFrames,1);
trialCQISource = strings(numFrames,1);
trialCQIDerivedMCS = NaN(numFrames,1);
trialCQIDerivedCodeRate = NaN(numFrames,1);
trialRI = NaN(numFrames,1);
trialPMI = NaN(numFrames,1);
trialCRI = NaN(numFrames,1);
trialLinkAdaptationMode = strings(numFrames,1);
trialActualMCSSelectionMode = strings(numFrames,1);
trialSchedulerGrantMCSSelectionMode = strings(numFrames,1);
trialOuterLoopEnabled = false(numFrames,1);
trialOuterLoopAppliedFromGrant = false(numFrames,1);
trialSchedulerCQIRawCQI = nan(numFrames,1);
trialSchedulerAdjustedSINR = nan(numFrames,1);
trialSchedulerSINRBackoff = nan(numFrames,1);
trialSchedulerCQISource = strings(numFrames,1);
trialOLLADeltaDb = NaN(numFrames,1);
trialOLLADeltaMCS = NaN(numFrames,1);
trialOLLAAdjustedMCSBeforeCQICeiling = NaN(numFrames,1);
trialOLLABaseRequiredSINR = NaN(numFrames,1);
trialOLLATargetRequiredSINR = NaN(numFrames,1);
trialOLLAThresholdSource = strings(numFrames,1);
trialOLLAUpdateCount = NaN(numFrames,1);
trialOLLAStateAuthority = strings(numFrames,1);
trialOLLAState = strings(numFrames,1);
trialRankSelectionPolicy = strings(numFrames,1);
trialRankSelectionSource = strings(numFrames,1);
trialRankDecisionReason = strings(numFrames,1);
trialRankDowngradeApplied = false(numFrames,1);
trialMaxSupportedLayers = NaN(numFrames,1);
trialCQITable = strings(numFrames,1);
trialMCSTable = strings(numFrames,1);
trialCQIDerivedModulation = strings(numFrames,1);
trialPMIType = strings(numFrames,1);
trialPMICodebookMode = strings(numFrames,1);
trialPMISource = strings(numFrames,1);
trialULSpatialMeasurementEvidence = strings(numFrames,1);
trialCSIReportMode = strings(numFrames,1);
trialCSIPayloadBits = NaN(numFrames,1);
trialCSIPayloadHex = strings(numFrames,1);
trialGain = NaN(numFrames,1);
trialNoise = NaN(numFrames,1);
trialReplaySampleNoiseVariance = NaN(numFrames,1);
trialReplayGridNoiseVariance = NaN(numFrames,1);
trialReceiverInputSampleNoiseVariance = NaN(numFrames,1);
trialPreEqualizationNoiseVariance = NaN(numFrames,1);
trialPostEqualizationNoiseVariance = NaN(numFrames,1);
trialSampleToGridNoiseVarianceGain = NaN(numFrames,1);
trialReplaySampleNoiseVarianceDomain = strings(numFrames,1);
trialReplayGridNoiseVarianceDomain = strings(numFrames,1);
trialReceiverInputSampleNoiseVarianceDomain = strings(numFrames,1);
trialDesiredSignalPowerDomain = strings(numFrames,1);
trialCompositeSignalPowerDomain = strings(numFrames,1);
trialSNRReferencePlane = strings(numFrames,1);
trialAppliedNoiseSNRSource = strings(numFrames,1);
trialRequestedAWGNReferenceSNR = NaN(numFrames,1);
trialSignalEnergyPerOccupiedRE = NaN(numFrames,1);
trialReplaySampleNoiseVarianceSource = strings(numFrames,1);
trialReplayGridNoiseVarianceSource = strings(numFrames,1);
trialReceiverInputSampleNoiseVarianceSource = strings(numFrames,1);
trialPreEqualizationNoiseVarianceSource = strings(numFrames,1);
trialPostEqualizationNoiseVarianceSource = strings(numFrames,1);
trialLLRNoiseVarianceSource = strings(numFrames,1);
trialNoiseVarStatus = strings(numFrames,1);
trialNoiseVarSource = strings(numFrames,1);
trialNoiseVarReason = strings(numFrames,1);
trialNoiseVarStrictFailure = false(numFrames,1);
trialUCIOnPUSCHApplied = false(numFrames,1);
trialUCIOnPUSCHSource = strings(numFrames,1);
trialUCIOnPUSCHEvidenceSource = strings(numFrames,1);
trialHARQACKBitCount = zeros(numFrames,1);
trialExpectedHARQACKBits = strings(numFrames,1);
trialDecodedHARQACKBits = strings(numFrames,1);
trialCSI1BitCount = zeros(numFrames,1);
trialCSI2BitCount = zeros(numFrames,1);
trialExpectedCSIPart1Bits = strings(numFrames,1);
trialExpectedCSIPart2Bits = strings(numFrames,1);
trialDecodedCSIPart1Bits = strings(numFrames,1);
trialDecodedCSIPart2Bits = strings(numFrames,1);
trialUCIReceiverEvidenceJSON = strings(numFrames,1);
trialCSI1ContentMatch = false(numFrames,1);
trialCSI2ContentMatch = false(numFrames,1);
trialHARQACKContentMatch = false(numFrames,1);
trialHARQACKDecodeStatus = strings(numFrames,1);
trialHARQACKDecodeReason = strings(numFrames,1);
trialEqualizerType = strings(numFrames,1);
trialEqualizerRequestedType = strings(numFrames,1);
trialEqualizerEngine = strings(numFrames,1);
trialEqualizerCovarianceFactorizationCount = NaN(numFrames,1);
trialInterferenceCovarianceAvailable = false(numFrames,1);
trialInterferenceCovarianceSource = strings(numFrames,1);
trialInterferenceCovarianceStatus = strings(numFrames,1);
trialMUMIMOReceiveCombinerApplied = false(numFrames,1);
trialMUMIMOReceiveCombinerStatus = strings(numFrames,1);
trialMUMIMOReceiveCombinerSource = strings(numFrames,1);
trialMUMIMOReceiveCombinerInputBranches = NaN(numFrames,1);
trialMUMIMOReceiveCombinerOutputBranches = NaN(numFrames,1);
trialMUMIMOReceiveCombinerMatrixSHA256 = strings(numFrames,1);
trialMUMIMOReceiveCombinerInterferenceProjected = false(numFrames,1);
trialMUMIMOReceiveCombinerFullObservationPreserved = false(numFrames,1);
trialMUMIMOReceiveCombinerIdentityResidual = NaN(numFrames,1);
trialMUMIMOReceiverAlgorithmApplied = strings(numFrames,1);
trialReceiverUsable = false(numFrames,1);
trialDecodeAttempted = false(numFrames,1);
trialDecodeUsable = false(numFrames,1);
trialFailureReason = strings(numFrames,1);
trialStrictReceiverEvidenceOk = false(numFrames,1);
trialStrictOk = false(numFrames,1);
trialTruthStatus = strings(numFrames,1);
trialChannelEstimateAttempted = false(numFrames,1);
trialChannelEstimateAvailable = false(numFrames,1);
trialChannelEstimateSource = strings(numFrames,1);
trialResourceExtractionAttempted = false(numFrames,1);
trialResourceExtractionAvailable = false(numFrames,1);
trialEqualizationAttempted = false(numFrames,1);
trialEqualizationAvailable = false(numFrames,1);
trialULSCHDecodeAttempted = false(numFrames,1);
trialULSCHDecodeAvailable = false(numFrames,1);
trialLLRAvailable = false(numFrames,1);
trialLLRFinite = false(numFrames,1);
trialLLRScaleSource = strings(numFrames,1);
trialLLRNoiseVariance = NaN(numFrames,1);
trialPostEqSINRAvailable = false(numFrames,1);
trialPostEqSINRReceiverDerived = false(numFrames,1);
trialSINRValidationStatus = strings(numFrames,1);
trialSINRValidationReason = strings(numFrames,1);
trialSINRComputationMethod = strings(numFrames,1);
trialConfiguredSNRLikeSourceRejected = false(numFrames,1);
trialTiming = NaN(numFrames,1);
trialAppliedTimingCorrection = NaN(numFrames,1);
trialTimingEstimateApplicationPolicy = strings(numFrames,1);
trialTimingEstimateStatus = strings(numFrames,1);
trialTimingEstimateWasClipped = false(numFrames,1);
trialConfiguredSNR = snr_dB * ones(numFrames,1);
trialAppliedAWGNSNR = NaN(numFrames,1);
trialDesiredSignalPowerBeforeNoise = NaN(numFrames,1);
trialCompositeSignalPowerBeforeNoise = NaN(numFrames,1);
trialAppliedNoiseSNR = NaN(numFrames,1);
trialNoiseVarianceSource = strings(numFrames,1);
trialAppliedLargeScaleGain = NaN(numFrames,1);
trialAppliedLargeScaleLoss = NaN(numFrames,1);
trialAppliedBasePathloss = NaN(numFrames,1);
trialAppliedPathloss = NaN(numFrames,1);
trialPUSCHPowerControlEnabled = false(numFrames,1);
trialPUSCHPowerControlStatus = strings(numFrames,1);
trialPUSCHTxPower = NaN(numFrames,1);
trialPUSCHPcmax = NaN(numFrames,1);
trialPUSCHPowerHeadroom = NaN(numFrames,1);
trialPUSCHRequestedPower = NaN(numFrames,1);
trialPUSCHMeasuredWaveformPower = NaN(numFrames,1);
trialPUSCHPowerClosureError = NaN(numFrames,1);
trialPUSCHPowerClipped = false(numFrames,1);
trialPUSCHPathlossReferenceRS = strings(numFrames,1);
trialPUSCHPowerControlSource = strings(numFrames,1);
trialPUSCHPowerScale = NaN(numFrames,1);
trialPUSCHPowerControlPathloss = NaN(numFrames,1);
trialAppliedShadow = NaN(numFrames,1);
trialAppliedO2I = NaN(numFrames,1);
trialAppliedLargeScaleGainSource = strings(numFrames,1);
trialChannelComplianceMode = strings(numFrames,1);
trialPathlossModelSource = strings(numFrames,1);
trialPathlossComplianceStatus = strings(numFrames,1);
trialFallbackUsedForPathloss = false(numFrames,1);
trialO2IModelSource = strings(numFrames,1);
trialO2IComplianceStatus = strings(numFrames,1);
trialO2IComplianceReason = strings(numFrames,1);
trialLOSProbabilitySource = strings(numFrames,1);
trialLOSComplianceStatus = strings(numFrames,1);
trialLOSComplianceReason = strings(numFrames,1);
trialIQImbalanceConfigured = false(numFrames,1);
trialIQImbalanceApplied = false(numFrames,1);
trialIQImbalanceModel = strings(numFrames,1);
trialConfiguredIQGainImbalance = NaN(numFrames,1);
trialConfiguredIQPhaseImbalance = NaN(numFrames,1);
trialIQImbalanceMirrorPowerRatio = NaN(numFrames,1);
trialIQImbalanceImageRejection = NaN(numFrames,1);
trialIQImbalanceIQPowerRatio = NaN(numFrames,1);
trialIQImbalanceIQCorrelation = NaN(numFrames,1);
trialIQImbalanceEstimatedAlphaAbs = NaN(numFrames,1);
trialIQImbalanceEstimatedBetaAbs = NaN(numFrames,1);
trialIQImbalanceMeasurementSource = strings(numFrames,1);
trialIQImbalanceMeasurementStatus = strings(numFrames,1);
trialInjectedCFO = NaN(numFrames,1);
trialEstimatedCFOPre = NaN(numFrames,1);
trialResidualCFOPost = NaN(numFrames,1);
trialEstimatedCFO = NaN(numFrames,1);
trialTrueCFO = NaN(numFrames,1);
trialCFOError = NaN(numFrames,1);
trialInjectedTiming = NaN(numFrames,1);
trialEstimatedTimingPre = NaN(numFrames,1);
trialResidualTimingPost = NaN(numFrames,1);
trialTrueTiming = NaN(numFrames,1);
trialTimingError = NaN(numFrames,1);
trialRank = NaN(numFrames,1);
trialCond = NaN(numFrames,1);
trialRxAnt = NaN(numFrames,1);
trialTxPorts = NaN(numFrames,1);
trialTxWaveformColumns = NaN(numFrames,1);
trialPhysicalTxAntennas = NaN(numFrames,1);
trialRxWaveformBranches = NaN(numFrames,1);
trialPhysicalRxAntennas = NaN(numFrames,1);
trialTxWaveformDomain = strings(numFrames,1);
trialHybridElementDomainApplied = false(numFrames,1);
trialSelectedBeam = NaN(numFrames,1);
trialBestBeam = NaN(numFrames,1);
trialBeamHit = NaN(numFrames,1);
trialTopKBeamHit = NaN(numFrames,1);
trialBeamCount = NaN(numFrames,1);
trialSelectedBeamGain = NaN(numFrames,1);
trialBestBeamGain = NaN(numFrames,1);
trialBeamGap = NaN(numFrames,1);
trialBeamScoreVector = strings(numFrames,1);
trialTopBeamIndexSet = strings(numFrames,1);
trialTopBeamGainSet = strings(numFrames,1);
trialBeamScoreSource = strings(numFrames,1);
trialConfiguredBeamSelectionStrategy = strings(numFrames,1);
trialPrecoderSource = strings(numFrames,1);
trialPrecodingMode = strings(numFrames,1);
trialPrecodingApplicationStage = strings(numFrames,1);
trialPrecodingActive = false(numFrames,1);
trialExplicitBeamWeightsApplied = false(numFrames,1);
trialTransformPrecodingApplied = false(numFrames,1);
trialFrequencyHoppingApplied = false(numFrames,1);
trialFrequencyHoppingMode = strings(numFrames,1);
trialFrequencyHoppingToolboxMode = strings(numFrames,1);
trialSecondHopStartPRB = NaN(numFrames,1);
trialBeamformingApplied = false(numFrames,1);
trialAppliedBeamIndexSet = strings(numFrames,1);
trialAppliedCodebookPortIndexSet = strings(numFrames,1);
trialAppliedCodebookPortIndexDefinition = strings(numFrames,1);
trialPrecodingNumLogicalPorts = NaN(numFrames,1);
trialAppliedPrecoderPMI = NaN(numFrames,1);
trialAppliedPrecoderPMIType = strings(numFrames,1);
trialAppliedPrecoderCodebookMode = strings(numFrames,1);
trialAppliedPrecoderMatrixSHA256 = strings(numFrames,1);
trialRequestedPrecoderSHA256 = strings(numFrames,1);
trialAppliedPrecoderSHA256 = strings(numFrames,1);
trialPrecoderDigestDomain = strings(numFrames,1);
trialFrozenGrantContextId = strings(numFrames,1);
trialRequestedVsAppliedPrecoderPMIMatchStatus = strings(numFrames,1);
trialPrecodingNumPorts = NaN(numFrames,1);
trialPrecodingNumLayers = NaN(numFrames,1);
trialPrecodingMatrixRows = NaN(numFrames,1);
trialPrecodingMatrixCols = NaN(numFrames,1);
trialCfgPMI = NaN(numFrames,1);
trialCfgCRI = NaN(numFrames,1);
trialBitErr = NaN(numFrames,1);
trialBitTot = NaN(numFrames,1);
trialOfferedBits = NaN(numFrames,1);
trialGoodBits = NaN(numFrames,1);
trialThroughput = NaN(numFrames,1);
trialOfferedThr = NaN(numFrames,1);
trialGoodput = NaN(numFrames,1);
trialComputeLatency = NaN(numFrames,1);
trialComputeLatencySource = strings(numFrames,1);
trialProcedureDelay = NaN(numFrames,1);
trialAirInterfaceTTI = slotDur_s * 1e3 * ones(numFrames,1);
trialAirInterfaceObservation = slotDur_s * 1e3 * ones(numFrames,1);
trialLatency = NaN(numFrames,1);
trialDecodeLatency = NaN(numFrames,1);
trialDecodeLatencySource = strings(numFrames,1);
trialReceiverPipelineLatency = NaN(numFrames,1);
trialReceiverPipelineLatencySource = strings(numFrames,1);
trialChannelEstimationLatency = NaN(numFrames,1);
trialEqualizationLatency = NaN(numFrames,1);
trialReceiverStageLatencySource = strings(numFrames,1);
trialEarlyStop = NaN(numFrames,1);
trialDecoderComplexity = NaN(numFrames,1);
trialNormDecoderComplexity = NaN(numFrames,1);
trialAreaEfficiency = NaN(numFrames,1);
trialNumCB = NaN(numFrames,1);
trialCBLen = NaN(numFrames,1);
trialSegOccurred = NaN(numFrames,1);
trialSegPadding = NaN(numFrames,1);
trialTBCRC = NaN(numFrames,1);
trialTBWithCRC = NaN(numFrames,1);
trialBaseGraph = NaN(numFrames,1);
trialEncodedBits = NaN(numFrames,1);
trialRateMatchedBits = NaN(numFrames,1);
trialRateMatchPuncture = NaN(numFrames,1);
trialRateMatchRepetition = NaN(numFrames,1);
trialCBErr = NaN(numFrames,1);
trialCBCount = NaN(numFrames,1);
trialCBBLER = NaN(numFrames,1);
trialCBGErr = NaN(numFrames,1);
trialCBGCount = NaN(numFrames,1);
trialCBGBLER = NaN(numFrames,1);
trialPAPR = NaN(numFrames,1);
trialClipEvents = NaN(numFrames,1);
trialSymErr = NaN(numFrames,1);
trialSymTot = NaN(numFrames,1);
trialSER = NaN(numFrames,1);
trialSymbolDecisionStatus = repmat("unavailable_not_measured", numFrames, 1);
trialResidualInterference = NaN(numFrames,1);
trialLLRMeanAbs = NaN(numFrames,1);
trialLLRStdAbs = NaN(numFrames,1);
trialLLRImbalance = NaN(numFrames,1);
trialMapSens = NaN(numFrames,1);
trialShapeLoss = NaN(numFrames,1);
trialDMLatency = NaN(numFrames,1);
trialHighOrderRobustness = NaN(numFrames,1);
trialDetectorComplexity = NaN(numFrames,1);
trialDataRECount = NaN(numFrames,1);
trialDataRECountPerLayer = NaN(numFrames,1);
trialTotalDataRECount = NaN(numFrames,1);
trialTBSInputNREPerPRB = NaN(numFrames,1);
trialTBSInputXOverhead = NaN(numFrames,1);
trialTBSInputSource = strings(numFrames,1);
trialModulationOrderQm = NaN(numFrames,1);
trialComputedE_TS38212 = NaN(numFrames,1);
trialDMRSRECount = NaN(numFrames,1);
trialPTRSRECount = NaN(numFrames,1);
trialRSOverhead = NaN(numFrames,1);
trialCarrierPhaseOffsetDeg = NaN(numFrames,1);
trialCarrierPhaseOffsetRad = NaN(numFrames,1);
trialCarrierPhaseOffsetApplied = false(numFrames,1);
trialCarrierPhaseOffsetSource = strings(numFrames,1);
trialCarrierPhaseOffsetStatus = strings(numFrames,1);
trialEstDoppler = NaN(numFrames,1);
trialDopplerErr = NaN(numFrames,1);
trialPhaseTrackErr = NaN(numFrames,1);
trialQCL = NaN(numFrames,1);
trialChannelReferenceCorrelation = NaN(numFrames,1);
trialAgingLoss = NaN(numFrames,1);
trialInterpLoss = NaN(numFrames,1);
trialMismatch = NaN(numFrames,1);
trialTimingEstimateUsed = false(numFrames,1);
trialUseIdealTimingSync = false(numFrames,1);
trialInterferenceMode = strings(numFrames,1);
trialInterferenceContributorCount = zeros(numFrames,1);
trialInterferenceAggregatedRxPower = NaN(numFrames,1);
trialInterferencePowerSource = strings(numFrames,1);
trialFullInterfererChannelTruthUsed = false(numFrames,1);
trialInterfererBeamformingAppliedCount = zeros(numFrames,1);
trialInterfererExplicitBeamWeightCount = zeros(numFrames,1);
trialInterfererTransformPrecodingCount = zeros(numFrames,1);
trialInterfererPrecoderSourceSet = strings(numFrames,1);
trialInterfererPrecodingModeSet = strings(numFrames,1);
trialInterfererBeamIndexSetSummary = strings(numFrames,1);
trialPBCHGatingActive = false(numFrames,1);
trialPRACHGatingActive = false(numFrames,1);
trialPDCCHGatingActive = false(numFrames,1);
trialSRSGatingActive = false(numFrames,1);
trialControlEligible = false(numFrames,1);
trialControlDecodeOk = false(numFrames,1);
trialDCICrcPass = false(numFrames,1);
trialPDCCHPayloadMatch = false(numFrames,1);
trialPDCCHCausalGrantDecodeOk = false(numFrames,1);
trialPDCCHMissedDetection = false(numFrames,1);
trialPDCCHFalseAlarm = false(numFrames,1);
trialGrantValid = false(numFrames,1);
trialNegativeExpectedOk = false(numFrames,1);
trialPDCCHBlindSearchEnabled = false(numFrames,1);
trialPDCCHREGMappingAvailable = false(numFrames,1);
trialPDCCHGrantBindingRequired = false(numFrames,1);
trialPDCCHGrantBindingOk = false(numFrames,1);
trialPDCCHGrantBindingStatus = strings(numFrames,1);
trialPDCCHGrantBindingFailureCode = strings(numFrames,1);
trialPDCCHGrantDCIId = strings(numFrames,1);
trialPDCCHGrantDCIFieldsHash = strings(numFrames,1);
trialPDCCHGrantFieldsHash = strings(numFrames,1);
trialPDCCHGrantSearchSpaceId = NaN(numFrames,1);
trialPDCCHGrantCORESETId = NaN(numFrames,1);
trialPDCCHGrantAggregationLevel = NaN(numFrames,1);
trialPDCCHGrantCandidateIndex = NaN(numFrames,1);
trialPDCCHGrantDCIFormat = strings(numFrames,1);
trialGrantControlState = strings(numFrames,1);
trialPDCCHControlFailureReason = strings(numFrames,1);
trialPDCCHControlEvidenceSource = strings(numFrames,1);
trialControlDecodeSource = strings(numFrames,1);
trialCellAcquisitionState = strings(numFrames,1);
trialAccessState = strings(numFrames,1);
trialSRSValidityState = strings(numFrames,1);
trialCSIValidityState = strings(numFrames,1);
trialSRSValid = false(numFrames,1);
trialSRSAgeSlots = NaN(numFrames,1);
trialTRSGatingActive = false(numFrames,1);
trialTRSValidityState = strings(numFrames,1);
trialTrackingEligibility = false(numFrames,1);
trialTRSAgeSlots = NaN(numFrames,1);
trialLastSuccessfulTRSSlot = NaN(numFrames,1);
trialLastEstimatedTRSDopplerHz = NaN(numFrames,1);
trialTRSStateSource = strings(numFrames,1);
trialTRSRuntimeConsumer = strings(numFrames,1);
trialTRSInfluencedDecision = false(numFrames,1);
trialTRSInfluenceDefinition = strings(numFrames,1);
trialTRSReceiverIntegrationStatus = strings(numFrames,1);
trialTRSReceiverIntegrationBlocker = strings(numFrames,1);
trialGrantContextId = strings(numFrames,1);
trialGrantWorkerSafe = false(numFrames,1);
trialGrantSharedStateCommitMode = strings(numFrames,1);
constellationChunks = cell(numFrames,1);
waveformChunks = cell(numFrames,1);
observedREChunks = cell(numFrames,1);
signalDiagnostic = out.SignalDiagnostic;
trialRuntimeEvidence = cell(numFrames,1);
trialMeasuredPHYEvidence = cell(numFrames,1);
trialStatus = strings(numFrames,1);
trialStatus(:) = "FAIL";
trialCrash = false(numFrames,1);
trialLAApplied = false(numFrames,1);
trialLAScheduled = false(numFrames,1);
trialLAFeedbackDelaySlots = NaN(numFrames,1);
trialLAFeedbackDelaySource = strings(numFrames,1);
trialLAFeedbackDelayStatus = strings(numFrames,1);
trialLAAppliedSourceSlot = NaN(numFrames,1);
trialLAAppliedAgeSlots = NaN(numFrames,1);
trialLAScheduledSourceSlot = NaN(numFrames,1);
trialLAScheduledApplySlot = NaN(numFrames,1);
trialLAAppliedDecisionCQI = NaN(numFrames,1);
trialLAAppliedDecisionCQIBasedMCS = NaN(numFrames,1);
trialLAAppliedDecisionMCS = NaN(numFrames,1);
trialLAAppliedDecisionOLLADeltaDb = NaN(numFrames,1);
trialLAAppliedDecisionOLLAUpdateCount = NaN(numFrames,1);
trialLAAppliedDecisionOLLAFeedbackEligible = false(numFrames,1);
trialLAScheduledDecisionCQI = NaN(numFrames,1);
trialLAScheduledDecisionMCS = NaN(numFrames,1);
trialLAScheduledDecisionOLLADeltaDb = NaN(numFrames,1);
trialLAScheduledDecisionOLLAUpdateCount = NaN(numFrames,1);
trialLAScheduledDecisionOLLAFeedbackEligible = false(numFrames,1);
trialLAScheduledDecisionOLLAFeedbackExclusionReason = strings(numFrames,1);
trialNotes = strings(numFrames,1);
trialULTransmissionAuthority = strings(numFrames,1);
trialULReceivedAssignmentDigest = strings(numFrames,1);
trialULReceiveAllocationAuthority = strings(numFrames,1);
trialUEHARQAttempt = NaN(numFrames,1);
trialUEHARQInitialAssignmentDigest = strings(numFrames,1);
trialChan = repmat(chanModel, numFrames, 1);
trialDopp = dopplerHz * ones(numFrames,1);
liveCallbackWarned = false;
lastHARQ = struct();
lastExpectedHARQACKBits = int8([]);
lastDecodedHARQACKBits = int8([]);
lastExpectedCSIPart1Bits = int8([]);
lastExpectedCSIPart2Bits = int8([]);
lastDecodedCSIPart1Bits = int8([]);
lastDecodedCSIPart2Bits = int8([]);
lastUCIReceiverEvidence = struct();
lastCSI1ContentMatch = false;
lastCSI2ContentMatch = false;
puschPowerControlState = struct( ...
    "PreviousF_dB", 0, ...
    "UpdateCount", 0, ...
    "LastTPCCommandBits", NaN, ...
    "LastTPCDelta_dB", 0);

for n = 1:numFrames
    trialPipelineTic = tic;
    frameIdx = double(trialFrame(n));
    trialSeed(n) = seedBase + frameIdx - 1;
    if ~receivedCompletion
        rng(localRNGSeed(trialSeed(n)), 'twister');
    end
    try
        if isRetransmission || schedulerDrivenGrant
            cfgFrame = cfgDyn;
            trialLAApplied(n) = false;
        else
            [cfgDyn, laState, laApplyEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "UL", trialSlot(n), "Phase", "before");
            cfgFrame = cfgDyn;
            trialLAApplied(n) = logical(laApplyEvent.Applied);
            trialLAFeedbackDelaySlots(n) = double(laApplyEvent.ConfiguredFeedbackDelaySlots);
            trialLAFeedbackDelaySource(n) = string(laApplyEvent.FeedbackDelaySource);
            trialLAFeedbackDelayStatus(n) = string(laApplyEvent.FeedbackDelayStatus);
            if logical(laApplyEvent.Applied)
                appliedDecision = laApplyEvent.Decision;
                trialLAAppliedSourceSlot(n) = double(laApplyEvent.FeedbackSourceSlot);
                trialLAAppliedAgeSlots(n) = double(laApplyEvent.FeedbackAgeSlots);
                trialLAAppliedDecisionCQI(n) = double(sixgr.util.structGet(appliedDecision, "ResolvedCQI", NaN));
                trialLAAppliedDecisionCQIBasedMCS(n) = double(sixgr.util.structGet(appliedDecision, "CQIBasedMCS", NaN));
                trialLAAppliedDecisionMCS(n) = double(sixgr.util.structGet(appliedDecision, "MCSIndex", NaN));
                trialLAAppliedDecisionOLLADeltaDb(n) = double(sixgr.util.structGet(appliedDecision, "OLLADeltaDb", NaN));
                trialLAAppliedDecisionOLLAUpdateCount(n) = double(sixgr.util.structGet(appliedDecision, "OLLAUpdateCount", NaN));
                trialLAAppliedDecisionOLLAFeedbackEligible(n) = logical(sixgr.util.structGet(appliedDecision, "OLLAFeedbackEligible", false));
            end
        end
        cfgFrame = localApplyReplayGrantConfig(cfgFrame, grantSnapshotOverride, "UL");
        % StartFrameIndex is a trial-sequence identifier for standalone
        % campaigns.  Scheduler-owned grants are the only calls where it
        % is an independently authoritative NR radio-frame value.
        authoritativeFrame = NaN;
        if schedulerDrivenGrant
            authoritativeFrame = frameIdx;
        end
        [cfgFrame, ~] = sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
            cfgFrame, trialSlot(n), authoritativeFrame);
        trialMCS(n) = double(sixgr.util.structGet(cfgFrame, "phy.pusch.mcsIndex", NaN));
        trialModulation(n) = string(sixgr.util.structGet(cfgFrame, "phy.pusch.modulation", ""));
        trialCodeRate(n) = double(sixgr.util.structGet(cfgFrame, "phy.pusch.codeRate", NaN));
        trialLinkAdaptationMode(n) = string(localResolveLinkAdaptationMode(cfgFrame, "UL"));
        trialActualMCSSelectionMode(n) = string(localResolveActualMCSSelectionMode(cfgFrame, "UL"));
        trialSchedulerGrantMCSSelectionMode(n) = string(sixgr.util.structGet(grantSnapshotOverride, "AMCMode", ""));
        trialMCSValueStatus(n) = string(sixgr.util.structGet(grantSnapshotOverride, "MCSValueStatus", ""));
        grantCQIUsed = double(sixgr.util.structGet(grantSnapshotOverride, "CQIUsed", NaN));
        grantRawCQIDerivedMCS = localFirstFiniteScalar( ...
            sixgr.util.structGet(grantSnapshotOverride, "RawCQIDerivedMCS", NaN));
        grantCQIBasedMCS = localFirstFiniteScalar( ...
            sixgr.util.structGet(grantSnapshotOverride, "CQIBasedMCS", NaN), ...
            sixgr.util.structGet(grantSnapshotOverride, "LinkAdaptationMCSIndex", NaN));
        grantCQIProvenance = string(sixgr.util.structGet(grantSnapshotOverride, "CQIProvenance", ""));
        grantMCSSelectionSource = string(sixgr.util.structGet(grantSnapshotOverride, "MCSSelectionSource", ""));
        trialSchedulerCQIRawCQI(n) = double(sixgr.util.structGet(grantSnapshotOverride, "SchedulerCQIRawCQI", NaN));
        trialSchedulerAdjustedSINR(n) = double(sixgr.util.structGet(grantSnapshotOverride, "SchedulerAdjustedSINR_dB", NaN));
        trialSchedulerSINRBackoff(n) = double(sixgr.util.structGet(grantSnapshotOverride, "SchedulerSINRBackoff_dB", NaN));
        trialSchedulerCQISource(n) = string(sixgr.util.structGet(grantSnapshotOverride, "SchedulerCQISource", ""));
        if schedulerDrivenGrant
            trialLinkAdaptationMode(n) = "scheduler_grant_replay";
            trialActualMCSSelectionMode(n) = "scheduler_grant";
            trialLAApplied(n) = localScalarLogicalGrantField( ...
                grantSnapshotOverride, "LinkAdaptationFeedbackApplied", false);
            if trialLAApplied(n)
                trialLAAppliedSourceSlot(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "LinkAdaptationAppliedFeedbackSourceSlot", NaN));
                trialLAAppliedAgeSlots(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "LinkAdaptationAppliedFeedbackAgeSlots", NaN));
                trialLAAppliedDecisionCQI(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "AppliedLinkAdaptationResolvedCQI", grantCQIUsed));
                trialLAAppliedDecisionCQIBasedMCS(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "AppliedLinkAdaptationCQIBasedMCS", grantCQIBasedMCS));
                trialLAAppliedDecisionMCS(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "AppliedLinkAdaptationMCS", trialMCS(n)));
                trialLAAppliedDecisionOLLADeltaDb(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "AppliedLinkAdaptationOLLADeltaDb", NaN));
                trialLAAppliedDecisionOLLAUpdateCount(n) = double(sixgr.util.structGet( ...
                    grantSnapshotOverride, "AppliedLinkAdaptationOLLAUpdateCount", NaN));
                trialLAAppliedDecisionOLLAFeedbackEligible(n) = logical(sixgr.util.structGet( ...
                    grantSnapshotOverride, "AppliedLinkAdaptationOLLAFeedbackEligible", false));
                deliveredSlot = double(sixgr.util.structGet(grantSnapshotOverride, ...
                    "LinkAdaptationAppliedFeedbackDeliveredSlot", NaN));
                if isfinite(deliveredSlot) && isfinite(trialLAAppliedSourceSlot(n))
                    trialLAFeedbackDelaySlots(n) = max(0, deliveredSlot - trialLAAppliedSourceSlot(n));
                    trialLAFeedbackDelaySource(n) = "scheduler_frozen_grant_feedback_lineage";
                    trialLAFeedbackDelayStatus(n) = "measured_runtime_value";
                end
            end
        end
        trialCQITable(n) = string(localResolveCQITable(cfgFrame, "UL"));
        trialMCSTable(n) = string(localResolveMCSTable(cfgFrame, "UL"));
        % Non-codebook PUSCH legitimately has no scalar TPMI/PMI. Preserve
        % an unavailable value without assigning an empty RHS
        % into one trial cell or inventing codebook index zero. The actual
        % precoding matrix remains the transmitter's unchanged authority.
        trialCfgPMI(n) = localOptionalPUSCHPMI(sixgr.util.structGet(cfgFrame, "phy.pusch.PMI", []));
        trialCfgCRI(n) = double(sixgr.util.structGet(cfgFrame, "phy.beamManagement.selectedCRI", NaN));
        trialConfiguredBeamSelectionStrategy(n) = string(sixgr.util.structGet(cfgFrame, "lls6g.userContext.BeamSelectionStrategy", ""));
        if isRetransmission
            [trialMCS(n), trialModulation(n), trialCodeRate(n)] = localOverrideReportedGrantFields( ...
                trialMCS(n), trialModulation(n), trialCodeRate(n), grantSnapshotOverride);
        end

        txArgs = {};
        txArgs = localAppendGrantReplayTxArgs( ...
            txArgs, grantSnapshotOverride, cfgFrame);
        if isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride))
            txArgs = [txArgs {"PHYGrant", phyGrantOverride}]; %#ok<AGROW>
        end
        if ~isempty(transportBlockBits)
            localAssertReplayTBConsistency(transportBlockBits, grantSnapshotOverride, "UL");
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        if ~isempty(rvOverride)
            txArgs = [txArgs {"RV", rvOverride}]; %#ok<AGROW>
        end
        if expectedUCIPayload.hasPayload()
            txArgs = [txArgs {"UCIPayload", expectedUCIPayload, ...
                "InitialIMCSPerCodeword", trialMCS(n)}]; %#ok<AGROW>
        end
        if receivedCompletion
            tx = preparedTransmission.Tx;
            txInfo = preparedTransmission.TxInfo;
        elseif isfield(cfgFrame.phy.pusch,'receivedDCIAssignment')
            if isfield(cfgFrame.phy.pusch,'receivedHARQState')
                ueState=cfgFrame.phy.pusch.receivedHARQState;
                assert(isa(ueState,'sixgr.link.ReceivedULHARQState'), ...
                    'sixgr:link:ReceivedULHARQStateRequired','UE HARQ must be endpoint-owned typed state.');
                assignment=cfgFrame.phy.pusch.receivedDCIAssignment;
                prior=ueState.Processes{assignment.HARQProcess+1};
                ueBits=transportBlockBits;
                if ~isempty(prior) && prior.NDI==assignment.NDI, ueBits=[]; end
                [tx,txInfo,out.UEHARQState]=ueState.transmit(cfgFrame,assignment,ueBits,expectedUCIPayload);
            else
            assert(~isRetransmission,'sixgr:link:ReceivedULHARQStateRequired', ...
                'Received-command retransmission requires UE-owned HARQ TB state; new-TB sizing is not a substitute.');
            [tx,txInfo]=sixgr.link.transmitReceivedPUSCH(cfgFrame, ...
                cfgFrame.phy.pusch.receivedDCIAssignment,transportBlockBits,expectedUCIPayload);
            end
        else
            [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfgFrame, txArgs{:});
        end
        trialULTransmissionAuthority(n)=string(sixgr.util.structGet(tx,'TransmissionAuthority', ...
            'configured_or_scheduled_transmitter'));
        trialULReceivedAssignmentDigest(n)=string(sixgr.util.structGet(tx,'ReceivedDCIAssignmentDigest',''));
        trialUEHARQAttempt(n)=double(sixgr.util.structGet(tx,'UEHARQAttempt',NaN));
        trialUEHARQInitialAssignmentDigest(n)=string(sixgr.util.structGet(tx,'UEHARQInitialAssignmentDigest',''));
        trialRuntimeAbsoluteSlot0(n) = double(sixgr.util.structGet(cfgFrame, ...
            "lls6g.runtime.AbsoluteSlotIndex0", NaN));
        trialCarrierNSlot(n) = double(tx.Carrier.NSlot);
        trialCarrierNFrame(n) = double(tx.Carrier.NFrame);
        trialSFN(n) = mod(trialCarrierNFrame(n), 1024);
        localAssertExecutedCarrierTimeline(cfgFrame, tx.Carrier, "UL");
        observedUEIndex = double(sixgr.util.structGet(grantSnapshotOverride, ...
            "UEIndex", sixgr.util.structGet(cfgFrame, ...
            "lls6g.userContext.UEIndex", NaN)));
        observedBaseStationID = double(sixgr.util.structGet( ...
            grantSnapshotOverride, "BaseStationID", ...
            sixgr.util.structGet(cfgFrame, ...
            "lls6g.userContext.RuntimeServingCell", NaN)));
        observedREChunks{n} = sixgr.truth.buildObservedREAllocation(tx, ...
            "Direction", "UL", "AbsoluteSlot", trialSlot(n) - 1, ...
            "CellID", observedBaseStationID, "UEID", observedUEIndex, ...
            "LayerCount", trialLayers(n), "AllocationID", ...
            string(sixgr.util.structGet(grantSnapshotOverride, ...
                "PHYGrantContextId", sixgr.util.structGet( ...
                grantSnapshotOverride, "GrantContextId", ""))));
        trialTxWaveformColumns(n) = double(size(tx.Waveform, 2));
        trialPhysicalTxAntennas(n) = double(sixgr.util.structGet(txInfo, ...
            "UEPhysicalTxAntennas", size(tx.Waveform, 2)));
        ulTxPrecoding = sixgr.util.structGet(txInfo, "Precoding", struct());
        trialTxWaveformDomain(n) = string(sixgr.util.structGet(ulTxPrecoding, ...
            "WaveformDomain", "logical_port"));
        trialHybridElementDomainApplied(n) = logical(sixgr.util.structGet( ...
            ulTxPrecoding, "HybridElementDomainApplied", false));
        localAssertULHybridTransmitElementDomain(cfgFrame, tx, txInfo);
        grantSnapshot = localBuildHARQGrantSnapshot(tx, trialMCS(n), cfgFrame, ...
            grantSnapshotOverride, frameIdx, trialSlot(n), trialSeed(n));
        [grantSnapshot, harqContext, harqTBContext, harqTBStatus] = localApplyHARQTransportBlockContext( ...
            "UL", cfgFrame, grantSnapshot, tx, harqContext, previousCombinedLLR);
        trialRV(n) = double(sixgr.util.structGet(tx, "RV", sixgr.util.structGet(harqContext, "RV", NaN)));
        trialHARQProcess(n) = double(sixgr.util.structGet(harqContext, "HarqID", ...
            sixgr.util.structGet(harqContext, "HARQProcess", NaN)));
        trialHARQRound(n) = double(sixgr.util.structGet(harqContext, ...
            "HARQRound", double(logical(sixgr.util.structGet( ...
            harqContext, "IsRetransmission", false)))));
        trialHARQNDI(n) = double(sixgr.util.structGet(harqTBContext, "NDI", ...
            sixgr.util.structGet(harqContext, "NDI", NaN)));
        trialHARQIsRetransmission(n) = logical(sixgr.util.structGet(harqContext, "IsRetransmission", false));
        trialHARQNDIEpoch(n) = double(sixgr.util.structGet(harqTBContext, "NDIEpoch", NaN));
        trialHARQTBId(n) = string(localSafeCharToken(sixgr.util.structGet(harqTBContext, "TBId", "")));
        trialOriginalTBSBits(n) = double(sixgr.util.structGet(harqTBStatus, "OriginalTBSBits", NaN));
        trialCurrentTBSBits(n) = double(sixgr.util.structGet(harqTBStatus, "CurrentTBSBits", NaN));
        trialOriginalRateMatchedBits(n) = double(sixgr.util.structGet(harqTBStatus, "OriginalRateMatchedBits", NaN));
        trialCurrentRateMatchedBits(n) = double(sixgr.util.structGet(harqTBStatus, "CurrentRateMatchedBits", NaN));
        trialEffectiveInitialCodeRate(n) = double(sixgr.util.structGet(harqTBStatus, "EffectiveInitialCodeRate", NaN));
        trialEffectiveCurrentTxCodeRate(n) = double(sixgr.util.structGet(harqTBStatus, "EffectiveCurrentTxCodeRate", NaN));
        trialShortIRRetx(n) = logical(sixgr.util.structGet(harqTBStatus, "ShortIRRetx", false));
        trialCodeBlockLayoutHash(n) = string(localSafeCharToken(sixgr.util.structGet(harqTBStatus, "CodeBlockLayoutHash", "")));
        trialHARQContextHash(n) = string(localSafeCharToken(sixgr.util.structGet(harqTBStatus, "HARQContextHash", "")));
        trialHARQContextStatus(n) = string(localSafeCharToken(sixgr.util.structGet(harqTBStatus, "HARQContextStatus", "")));
        trialOuterLoopEnabled(n) = logical(sixgr.util.structGet(grantSnapshot, "OuterLoopEnabled", false));
        trialOuterLoopAppliedFromGrant(n) = logical(sixgr.util.structGet(grantSnapshot, "OuterLoopApplied", false));
        trialOLLADeltaDb(n) = double(sixgr.util.structGet(grantSnapshot, "OLLADeltaDb", ...
            sixgr.util.structGet(grantSnapshot, "OLLADeltaMCS", NaN)));
        trialOLLADeltaMCS(n) = double(sixgr.util.structGet(grantSnapshot, "OLLADeltaMCS", NaN));
        trialOLLAAdjustedMCSBeforeCQICeiling(n) = double(sixgr.util.structGet(grantSnapshot, "OLLAAdjustedMCSBeforeCQICeiling", NaN));
        trialOLLABaseRequiredSINR(n) = double(sixgr.util.structGet(grantSnapshot, "OLLABaseRequiredSINR_dB", NaN));
        trialOLLATargetRequiredSINR(n) = double(sixgr.util.structGet(grantSnapshot, "OLLATargetRequiredSINR_dB", NaN));
        trialOLLAThresholdSource(n) = string(sixgr.util.structGet(grantSnapshot, "OLLAThresholdSource", ""));
        trialOLLAUpdateCount(n) = double(sixgr.util.structGet(grantSnapshot, "OLLAUpdateCount", NaN));
        trialOLLAStateAuthority(n) = string(sixgr.util.structGet(grantSnapshot, "OLLAStateAuthority", ""));
        trialOLLAState(n) = string(sixgr.util.structGet(grantSnapshot, "OLLAState", ""));
        trialRankSelectionPolicy(n) = string(sixgr.util.structGet(grantSnapshot, "RankSelectionPolicy", ""));
        trialRankSelectionSource(n) = string(sixgr.util.structGet(grantSnapshot, "RankSelectionSource", ""));
        trialRankDecisionReason(n) = string(sixgr.util.structGet(grantSnapshot, "RankDecisionReason", ""));
        trialRankDowngradeApplied(n) = logical(sixgr.util.structGet(grantSnapshot, "RankDowngradeApplied", false));
        trialMaxSupportedLayers(n) = double(sixgr.util.structGet(grantSnapshot, "MaxSupportedLayers", NaN));
        trialPBCHGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "PBCHGatingActive", false));
        trialPRACHGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "PRACHGatingActive", false));
        trialPDCCHGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHGatingActive", false));
        trialSRSGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "SRSGatingActive", false));
        trialControlEligible(n) = logical(sixgr.util.structGet(grantSnapshot, "ControlEligible", false));
        trialControlDecodeOk(n) = logical(sixgr.util.structGet(grantSnapshot, "ControlDecodeOk", false));
        trialDCICrcPass(n) = logical(sixgr.util.structGet(grantSnapshot, "DCICrcPass", ...
            sixgr.util.structGet(grantSnapshot, "PDCCHDCICrcPass", false)));
        trialPDCCHPayloadMatch(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHPayloadMatch", false));
        trialPDCCHCausalGrantDecodeOk(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHCausalGrantDecodeOk", false));
        trialPDCCHMissedDetection(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHMissedDetection", false));
        trialPDCCHFalseAlarm(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHFalseAlarm", false));
        trialGrantValid(n) = logical(sixgr.util.structGet(grantSnapshot, "GrantValid", ...
            sixgr.util.structGet(grantSnapshot, "PDCCHGrantValid", false)));
        trialNegativeExpectedOk(n) = logical(sixgr.util.structGet(grantSnapshot, "NegativeExpectedOk", false));
        trialPDCCHBlindSearchEnabled(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHBlindSearchEnabled", false));
        trialPDCCHREGMappingAvailable(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHREGMappingAvailable", false));
        trialPDCCHGrantBindingRequired(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHGrantBindingRequired", false));
        trialPDCCHGrantBindingOk(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHGrantBindingOk", false));
        trialPDCCHGrantBindingStatus(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHGrantBindingStatus", ""));
        trialPDCCHGrantBindingFailureCode(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHGrantBindingFailureCode", ""));
        trialPDCCHGrantDCIId(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHGrantDCIId", ""));
        trialPDCCHGrantDCIFieldsHash(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHGrantDCIFieldsHash", ""));
        trialPDCCHGrantFieldsHash(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHGrantFieldsHash", ""));
        trialPDCCHGrantSearchSpaceId(n) = double(sixgr.util.structGet(grantSnapshot, "PDCCHGrantSearchSpaceId", NaN));
        trialPDCCHGrantCORESETId(n) = double(sixgr.util.structGet(grantSnapshot, "PDCCHGrantCORESETId", NaN));
        trialPDCCHGrantAggregationLevel(n) = double(sixgr.util.structGet(grantSnapshot, "PDCCHGrantAggregationLevel", NaN));
        trialPDCCHGrantCandidateIndex(n) = double(sixgr.util.structGet(grantSnapshot, "PDCCHGrantCandidateIndex", NaN));
        trialPDCCHGrantDCIFormat(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHGrantDCIFormat", ""));
        trialGrantControlState(n) = string(sixgr.util.structGet(grantSnapshot, "GrantControlState", ""));
        trialPDCCHControlFailureReason(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHControlFailureReason", ""));
        trialPDCCHControlEvidenceSource(n) = string(sixgr.util.structGet(grantSnapshot, "PDCCHControlEvidenceSource", ""));
        trialControlDecodeSource(n) = string(sixgr.util.structGet(grantSnapshot, "ControlDecodeSource", ""));
        trialCellAcquisitionState(n) = string(sixgr.util.structGet(grantSnapshot, "CellAcquisitionState", ""));
        trialAccessState(n) = string(sixgr.util.structGet(grantSnapshot, "AccessState", ""));
        trialSRSValidityState(n) = string(sixgr.util.structGet(grantSnapshot, "SRSValidityState", ""));
        trialCSIValidityState(n) = string(sixgr.util.structGet(grantSnapshot, "CSIValidityState", ""));
        trialSRSValid(n) = logical(sixgr.util.structGet(grantSnapshot, "SRSValid", false));
        trialSRSAgeSlots(n) = double(sixgr.util.structGet(grantSnapshot, "SRSAgeSlots", NaN));
        trsTrace = localResolveTRSRuntimeTrace(cfgFrame, grantSnapshot);
        trialTRSGatingActive(n) = logical(trsTrace.TRSGatingActive);
        trialTRSValidityState(n) = string(trsTrace.TRSValidityState);
        trialTrackingEligibility(n) = logical(trsTrace.TrackingEligibility);
        trialTRSAgeSlots(n) = double(trsTrace.TRSAgeSlots);
        trialLastSuccessfulTRSSlot(n) = double(trsTrace.LastSuccessfulTRSSlot);
        trialLastEstimatedTRSDopplerHz(n) = double(trsTrace.LastEstimatedTRSDopplerHz);
        trialTRSStateSource(n) = string(trsTrace.TRSStateSource);
        trialTRSRuntimeConsumer(n) = string(trsTrace.TRSRuntimeConsumer);
        trialTRSInfluencedDecision(n) = logical(trsTrace.TRSInfluencedDecision);
        trialTRSInfluenceDefinition(n) = string(trsTrace.TRSInfluenceDefinition);
        trialTRSReceiverIntegrationStatus(n) = string(trsTrace.TRSReceiverIntegrationStatus);
        trialTRSReceiverIntegrationBlocker(n) = string(trsTrace.TRSReceiverIntegrationBlocker);
        trialGrantContextId(n) = string(sixgr.util.structGet(grantSnapshot, "GrantContextId", ""));
        trialGrantWorkerSafe(n) = logical(sixgr.util.structGet(grantSnapshot, "GrantWorkerSafe", false));
        trialGrantSharedStateCommitMode(n) = string(sixgr.util.structGet(grantSnapshot, "GrantSharedStateCommitMode", ""));
        trialUEIndex(n) = double(sixgr.util.structGet(grantSnapshot, "UEIndex", NaN));
        trialRNTI(n) = double(sixgr.util.structGet(grantSnapshot, "RNTI", sixgr.util.structGet(cfgFrame, "phy.rnti", NaN)));
        trialBaseStationID(n) = double(sixgr.util.structGet(grantSnapshot, "BaseStationID", ...
            sixgr.util.structGet(cfgFrame, "lls6g.userContext.RuntimeServingCell", NaN)));
        prbSetSnapshot = double(sixgr.util.structGet(grantSnapshot, "PRBSet", []));
        prbSetSnapshot = prbSetSnapshot(isfinite(prbSetSnapshot));
        if ~isempty(prbSetSnapshot)
            trialPRBStart(n) = double(prbSetSnapshot(1));
        else
            trialPRBStart(n) = double(sixgr.util.structGet(grantSnapshot, "PRBStart", NaN));
        end
        frozenPHYGrant = sixgr.util.structGet(grantSnapshot, ...
            "PHYGrant", struct());
        symbolAllocationSnapshot = double(sixgr.util.structGet( ...
            grantSnapshot, "SymbolAllocation", sixgr.util.structGet( ...
            frozenPHYGrant, "ResourceAllocation.SymbolAllocation", [])));
        if numel(symbolAllocationSnapshot) >= 2 && ...
                all(isfinite(symbolAllocationSnapshot(1:2)))
            trialSymbolStart(n) = symbolAllocationSnapshot(1);
            trialNumSymbols(n) = symbolAllocationSnapshot(2);
        else
            trialSymbolStart(n) = double(sixgr.util.structGet( ...
                grantSnapshot, "SymbolStart", sixgr.util.structGet( ...
                frozenPHYGrant, "ResourceAllocation.SymbolStart", NaN)));
            trialNumSymbols(n) = double(sixgr.util.structGet( ...
                grantSnapshot, "NumSymbols", sixgr.util.structGet( ...
                frozenPHYGrant, "ResourceAllocation.NumSymbols", NaN)));
        end
        ulPrecoding = localResolveULPrecodingTrace(cfgFrame, tx, grantSnapshot);
        trialPrecoderSource(n) = string(ulPrecoding.PrecoderSource);
        trialPrecodingMode(n) = string(ulPrecoding.PrecodingMode);
        trialPrecodingApplicationStage(n) = string(ulPrecoding.PrecodingApplicationStage);
        trialPrecodingActive(n) = logical(ulPrecoding.PrecodingActive);
        trialExplicitBeamWeightsApplied(n) = logical(ulPrecoding.ExplicitBeamWeightsApplied);
        trialTransformPrecodingApplied(n) = logical(ulPrecoding.TransformPrecodingApplied);
        trialFrequencyHoppingApplied(n) = logical(sixgr.util.structGet( ...
            tx, "FrequencyHoppingApplied", false));
        trialFrequencyHoppingMode(n) = string(sixgr.util.structGet( ...
            tx, "FrequencyHoppingMode", ""));
        trialFrequencyHoppingToolboxMode(n) = string(sixgr.util.structGet( ...
            tx, "FrequencyHoppingToolboxMode", ""));
        trialSecondHopStartPRB(n) = double(sixgr.util.structGet( ...
            tx, "SecondHopStartPRB", NaN));
        trialBeamformingApplied(n) = logical(ulPrecoding.BeamformingApplied);
        trialAppliedBeamIndexSet(n) = string(ulPrecoding.AppliedBeamIndexSet);
        trialAppliedCodebookPortIndexSet(n)=string(ulPrecoding.AppliedCodebookPortIndexSet);
        trialAppliedCodebookPortIndexDefinition(n)=string(ulPrecoding.AppliedCodebookPortIndexDefinition);
        trialPrecodingNumLogicalPorts(n)=ulPrecoding.PrecodingNumLogicalPorts;
        trialAppliedPrecoderPMI(n) = double(ulPrecoding.AppliedPrecoderPMI);
        trialAppliedPrecoderPMIType(n) = string(ulPrecoding.AppliedPrecoderPMIType);
        trialAppliedPrecoderCodebookMode(n) = string(ulPrecoding.AppliedPrecoderCodebookMode);
        trialAppliedPrecoderMatrixSHA256(n) = string(ulPrecoding.AppliedPrecoderMatrixSHA256);
        trialRequestedPrecoderSHA256(n) = string(ulPrecoding.RequestedPrecoderSHA256);
        trialAppliedPrecoderSHA256(n) = string(ulPrecoding.AppliedPrecoderSHA256);
        trialPrecoderDigestDomain(n) = string(ulPrecoding.PrecoderDigestDomain);
        trialFrozenGrantContextId(n) = string(ulPrecoding.FrozenGrantContextId);
        trialRequestedVsAppliedPrecoderPMIMatchStatus(n) = string(ulPrecoding.RequestedVsAppliedPrecoderPMIMatchStatus);
        trialPrecodingNumPorts(n) = double(ulPrecoding.PrecodingNumPorts);
        trialPrecodingNumLayers(n) = double(ulPrecoding.PrecodingNumLayers);
        trialPrecodingMatrixRows(n) = double(ulPrecoding.PrecodingMatrixRows);
        trialPrecodingMatrixCols(n) = double(ulPrecoding.PrecodingMatrixCols);
        if isfield(tx, "PUSCH")
            try
                trialPRB(n) = numel(tx.PUSCH.PRBSet);
            catch
            end
            try
                trialLayers(n) = double(tx.PUSCH.NumLayers);
            catch
            end
            try
                trialModulation(n) = string(tx.PUSCH.Modulation);
            catch
            end
        end
        if isfield(tx, "TransportBlockSize")
            trialTB(n) = double(tx.TransportBlockSize);
        end
        if isfield(tx, "TargetCodeRate")
            trialCodeRate(n) = double(tx.TargetCodeRate);
        end
        if ~(prepareOnly || receivedCompletion)
            % Preserve the legacy call ordering for the immediate path.
            if externalChannelState
                chState = localPrepareRuntimeChannelState(chState, cfgFrame, tx, txInfo, "UL");
            elseif ~chState.Initialized
                chState = localInitChannelState(cfgFrame, tx, txInfo, snr_dB, trialSeed(n));
            end
        end
        useIdealTimingSync = localUseIdealTimingSync(cfgFrame);
        if receivedCompletion
            powerCtrl = preparedTransmission.PowerControl;
            puschPowerControlState = preparedTransmission.PowerControlState;
            cfgFrameRx = preparedTransmission.ReceiverConfig;
            powerContext = tx.PowerContext;
        else
        powerGrant=grantSnapshot;
        if isfield(cfgFrame.phy.pusch,'receivedDCIAssignment')
            powerGrant=struct('PRBSet',tx.PUSCH.PRBSet, ...
                'DecodedDCIFields',cfgFrame.phy.pusch.receivedDCIAssignment.Fields);
        end
        [txWaveformPC, powerCtrl, cfgFrameRx, puschPowerControlState] = ...
            sixgr.link.bindPUSCHPowerControlContext(tx.Waveform, cfgFrame, tx, ...
            powerGrant, puschPowerControlState);
        tx.Waveform = txWaveformPC;
        [tx.Waveform, powerContext] = sixgr.rf.applyPowerContext( ...
            tx.Waveform, cfgFrameRx, "UL", txInfo,"ApplyPA",~prepareOnly);
        if logical(powerCtrl.Enabled)
            powerCtrl.AmplitudeScale = double(powerContext.AmplitudeScale);
            powerCtrl.MeasuredWaveformPower_dBm = double(powerContext.OutputTotalPower_dBm);
            powerCtrl.PowerClosureError_dB = double(powerContext.PowerClosureError_dB);
            % The scheduler reserves a UE transmission occasion, but the
            % physical PUSCH power is resolved only after causal reference-
            % signal pathloss and TS 38.213 power control are available.
            % Replace the provisional endpoint-budget description with the
            % exact applied PUSCH ledger before exporting runtime evidence.
            % PCMAX remains the endpoint budget; GrantTarget is the power
            % actually requested/applied to this waveform.
            powerContext.CellTotalTxPower_dBm = NaN;
            powerContext.EndpointPowerBudget_dBm = double(powerCtrl.Pcmax_dBm);
            powerContext.ConcurrentTransmitterGrantCount = 1;
            powerContext.GrantPowerFraction = 1;
            powerContext.GrantTargetTxPower_dBm = double(powerCtrl.TxPower_dBm);
            powerContext.ScheduledPowerPolicy = ...
                "ts_38_213_pusch_power_control_per_ue_transmitter";
            powerContext.ScheduledPowerAuthority = char(string(powerCtrl.Source));
            powerContext.SharedCellBudgetApplied = false;
            powerContext.SignalSpecificPowerControl = true;
            powerContext.SignalSpecificPowerControlSource = ...
                "ts_38_213_pusch_power_control";
        end
        powerContext.PowerControlAmplitudeScale = double(powerCtrl.AmplitudeScale);
        end
        tx.PowerContext = powerContext;
        txInfo.PowerContext = powerContext;
        cfgFrameRx = sixgr.util.structSet(cfgFrameRx, "lls6g.runtimePowerContext", powerContext);
        if prepareOnly
            out.PreparedTransmission = sixgr.link.PreparedDataTransmission( ...
                "UL",cfg,preparedBinding,tx,txInfo,cfgFrameRx, ...
                localResolveSampleRate(tx,txInfo),1e3*toc(trialPipelineTic), ...
                powerCtrl,puschPowerControlState);
            out.ExecutionStage = "transmit_prepared_not_received";
            out.ExecutionTaxonomy = "decoded_ul_grant_coded_transmission";
            out.ExecutionBackend = "scheduler_coded_transmitter_pre_node_rf";
            out.Notes = "Coded PUSCH/UCI prepared; no node RF, channel, decoder or received trial executed.";
            out.ChannelState = chStateIn;
            return;
        end
        if receivedCompletion
            tx.Waveform = preparedTransmission.readObservation( ...
                p.Results.ReceivedContext.TransmitterObservation,preparedTransmission.NumPhysicalTransmitAntennas,"transmitter");
            trialTxWaveformColumns(n) = size(tx.Waveform,2);
            trialPhysicalTxAntennas(n) = size(tx.Waveform,2);
            trialTxWaveformDomain(n) = "physical_antenna_transmitter_composite";
        elseif sixgr.rf.hasExplicitTransmitConfig(cfgFrameRx)
            txRfOut = sixgr.rf.applyRFImpairmentChain(tx.Waveform, cfgFrameRx, ...
                "SampleRateHz", localResolveSampleRate(tx, txInfo), ...
                "Direction", "UL", ...
                "MeasurementPoint", "tx_output", ...
                "Endpoint", "tx", ...
                "StrictMutationRequired", false, ...
                "UseLegacyGlobalConfig", false, ...
                "ApplyPA", false, ...
                "ApplyADC", false);
            tx.Waveform = cast(txRfOut.Waveform, "like", tx.Waveform);
            tx.TxRFImpairmentReplay = txRfOut.Replay;
            txInfo.TxRFImpairmentReplay = txRfOut.Replay;
            cfgFrameRx = sixgr.util.structSet(cfgFrameRx, "lls6g.txRFImpairmentReplay", txRfOut.Replay);
        end
        if txWaveformCaptureRequired && isempty(fieldnames(txWaveformCapture))
            txWaveformCapture = struct( ...
                "Waveform",tx.Waveform, ...
                "SampleRateHz",double(localResolveSampleRate(tx,txInfo)), ...
                "Frame",double(frameIdx), ...
                "Slot",double(trialSlot(n)), ...
                "CapturePoint","post_power_control_power_context_and_tx_rf_pre_channel", ...
                "WaveformAuthority","exact_runtime_pusch_waveform");
        end
        if receivedCompletion && ~isempty(fieldnames(txWaveformCapture))
            txWaveformCapture.WaveformAuthority = "exact_runtime_transmitter_composite_observation";
        end
        trialPUSCHPowerControlEnabled(n) = logical(powerCtrl.Enabled);
        trialPUSCHPowerControlStatus(n) = string(powerCtrl.Status);
        trialPUSCHTxPower(n) = double(powerCtrl.TxPower_dBm);
        trialPUSCHPcmax(n) = double(powerCtrl.Pcmax_dBm);
        trialPUSCHPowerHeadroom(n) = double(powerCtrl.PowerHeadroom_dB);
        trialPUSCHRequestedPower(n) = double(powerCtrl.RequestedPower_dBm);
        trialPUSCHMeasuredWaveformPower(n) = double(powerCtrl.MeasuredWaveformPower_dBm);
        trialPUSCHPowerClosureError(n) = double(powerCtrl.PowerClosureError_dB);
        trialPUSCHPowerClipped(n) = logical(powerCtrl.Clipped);
        trialPUSCHPathlossReferenceRS(n) = string(powerCtrl.PathlossReferenceRS);
        trialPUSCHPowerControlSource(n) = string(powerCtrl.Source);
        trialPUSCHPowerScale(n) = double(powerCtrl.AmplitudeScale);
        trialPUSCHPowerControlPathloss(n) = double(powerCtrl.Pathloss_dB);
        captureDiagnosticPathGains = logical(sixgr.util.structGet( ...
            cfgFrameRx, "outputs.phySignalDiagnosticEnabled", false)) && ...
            ~logical(sixgr.util.structGet(signalDiagnostic, "Available", false));
        if receivedCompletion
            chState = p.Results.ReceivedContext.ChannelState;
            rxWave = p.Results.ReceivedContext.Observation.readComplete();
            replay = p.Results.ReceivedContext.Replay;
        else
            [rxWave, replay, chState] = localApplyChannelAndAwgn( ...
                tx.Waveform, snr_dB, chState, cfgFrameRx, tx, txInfo, ...
                interferenceBundle, captureDiagnosticPathGains);
        end
        trialRxWaveformBranches(n) = double(size(rxWave, 2));
        trialPhysicalRxAntennas(n) = double(size(rxWave, 2));
        localAssertULHybridReceiveElementDomain(cfgFrameRx, rxWave);
        if ~receivedCompletion
            cfgFrame = localAttachReceiverSyncRuntimeContext(cfgFrame, chState, replay);
            cfgFrameRx = localAttachReceiverSyncRuntimeContext(cfgFrameRx, chState, replay);
        end

        rxArgs = {"Carrier", tx.Carrier, ...
            "PUSCH", tx.PUSCH, ...
            "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "CodingLayout", tx.CodingLayout, ...
            "SkipTimingEstimate", useIdealTimingSync};
        trialULReceiveAllocationAuthority(n)="legacy_transmitter_metadata";
        if receivedCompletion && isfield(cfgFrame.phy.pusch,'receivedDCIAssignment')
            % gNB receives using its own frozen scheduling state, not what
            % the UE decoded and not the UE transmitter's resource objects.
            rxArgs={"SkipTimingEstimate",useIdealTimingSync};
            trialULReceiveAllocationAuthority(n)="gnb_own_scheduled_grant";
            cfgFrame.phy.pusch=rmfield(cfgFrame.phy.pusch,'receivedDCIAssignment');
            if isfield(cfgFrame.phy.pusch,'receivedHARQState')
                cfgFrame.phy.pusch=rmfield(cfgFrame.phy.pusch,'receivedHARQState');
            end
        end
        if receivedCompletion
            rxArgs=[rxArgs {"TimingSearchWindowSamples", ...
                preparedTransmission.receiverTimingSearchWindow(p.Results.ReceivedContext.Observation)}];
        end
        if isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride))
            rxArgs = [rxArgs {"PHYGrant", phyGrantOverride}]; %#ok<AGROW>
        end
        receiveCombiner = sixgr.util.structGet(grantSnapshotOverride, ...
            "MUMIMOReceiveCombiningMatrix", sixgr.util.structGet(phyGrantOverride, ...
            "LegacyGrantSnapshot.MUMIMOReceiveCombiningMatrix", []));
        receiveCombinerDigest = string(sixgr.util.structGet(grantSnapshotOverride, ...
            "MUMIMOReceiveCombiningMatrixSHA256", sixgr.util.structGet(phyGrantOverride, ...
            "LegacyGrantSnapshot.MUMIMOReceiveCombiningMatrixSHA256", "")));
        if ~isempty(receiveCombiner)
            rxArgs = [rxArgs { ...
                "ReceiveCombiningMatrix", receiveCombiner, ...
                "ReceiveCombiningMatrixSHA256", receiveCombinerDigest}]; %#ok<AGROW>
        end
        if expectedUCIPayload.hasPayload()
            rxArgs = [rxArgs {"ExpectedUCIPayload", expectedUCIPayload, ...
                "InitialIMCSPerCodeword", trialMCS(n)}]; %#ok<AGROW>
        end
        injectedNoiseVariance = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
        % Shared samples have passed RF/ADC and measured gain compensation.
        % Pre-front-end injection variance remains scoring metadata, not a
        % receiver-domain disturbance estimate. Let DM-RS estimate it here.
        if ~receivedCompletion && isfinite(injectedNoiseVariance) && injectedNoiseVariance >= 0
            rxArgs = [rxArgs {"NoiseVar", injectedNoiseVariance, "NoiseVarDomain", "time"}]; %#ok<AGROW>
        end
        if logical(sixgr.util.structGet(replay, "InterferenceContributionTensorAvailable", false)) && ...
                isfield(replay, "InterferenceContributionTensor")
            rxArgs = [rxArgs { ...
                "InterferenceContributionTensor", replay.InterferenceContributionTensor, ...
                "InterferenceContributionSource", sixgr.util.structGet(replay, "InterferenceContributionSourceIdSet", ""), ...
                "InterferenceContributionDomain", sixgr.util.structGet(replay, "InterferenceContributionDomain", "receiver_sample_waveform_pre_noise")}]; %#ok<AGROW>
        elseif logical(sixgr.util.structGet(replay, "InterferenceCovarianceAvailableFromContributions", false)) && ...
                isfield(replay, "InterferenceCovariance")
            rxArgs = [rxArgs { ...
                "InterferenceCovariance", replay.InterferenceCovariance, ...
                "InterferenceCovarianceSource", sixgr.util.structGet(replay, "InterferenceCovarianceSourceFromContributions", ""), ...
                "InterferenceCovarianceIncludesNoise", false}]; %#ok<AGROW>
        end
        rxCallTic = tic;
        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgFrame, rxArgs{:});
        if receivedCompletion
            out.ReceiveTiming = rx.ReceiveTiming;
        end
        trialReceiverPipelineLatency(n) = 1e3 * toc(rxCallTic);
        trialReceiverPipelineLatencySource(n) = "matlab_tic_toc_pusch_receiver_call";
        trialChannelEstimationLatency(n) = double(sixgr.util.structGet( ...
            rx, "ChannelEstimationLatency_ms", NaN));
        trialEqualizationLatency(n) = double(sixgr.util.structGet( ...
            rx, "EqualizationLatency_ms", NaN));
        trialReceiverStageLatencySource(n) = string(sixgr.util.structGet( ...
            rx, "ReceiverStageLatencySource", "unavailable"));
        trialMeasuredPHYEvidence{n} = sixgr.link.deriveMeasuredPHYEvidence(rx);
        replay = localFinalizeImpairmentReplay(replay, cfgFrame, rx, tx, txInfo, useIdealTimingSync);
        waveformChunks{n} = sixgr.link.buildWaveformPreviewTable("UL", snr_dB, trialFrame(n), trialSlot(n), ...
            tx.Waveform, rxWave, localResolveSampleRate(tx, txInfo));

        trialTiming(n) = double(sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", ...
            sixgr.util.structGet(rx, "RawTimingEstimate_samples", ...
            sixgr.util.structGet(rx, "TimingOffset", NaN))));
        trialAppliedTimingCorrection(n) = double(sixgr.util.structGet(replay, "AppliedTimingCorrection_samples", ...
            sixgr.util.structGet(rx, "AppliedTimingCorrection_samples", NaN)));
        trialTimingEstimateApplicationPolicy(n) = string(sixgr.util.structGet(replay, "TimingEstimateApplicationPolicy", ...
            sixgr.util.structGet(rx, "TimingEstimateApplicationPolicy", "")));
        trialTimingEstimateStatus(n) = string(sixgr.util.structGet(replay, "TimingEstimateStatus", ...
            sixgr.util.structGet(rx, "TimingEstimateStatus", "")));
        trialTimingEstimateWasClipped(n) = logical(sixgr.util.structGet(replay, "TimingEstimateWasClipped", ...
            sixgr.util.structGet(rx, "TimingEstimateWasClipped", false)));
        trialNoise(n) = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
        trialPreEqualizationNoiseVariance(n) = double(sixgr.util.structGet(rx, ...
            "PreEqualizationNoiseVariance", sixgr.util.structGet(rx, "PreEqualizationNoiseVar", NaN)));
        trialPostEqualizationNoiseVariance(n) = double(sixgr.util.structGet(rx, ...
            "PostEqualizationNoiseVariance", sixgr.util.structGet(rx, "PostEqualizationNoiseVar", NaN)));
        trialSampleToGridNoiseVarianceGain(n) = double(sixgr.util.structGet(rx, ...
            "SampleToGridNoiseVarianceGain", sixgr.util.structGet(tx, ...
            "OFDMInfo.SampleToGridNoiseVarianceGain", NaN)));
        trialPreEqualizationNoiseVarianceSource(n) = string(sixgr.util.structGet(rx, ...
            "PreEqualizationNoiseVarianceSource", ""));
        trialPostEqualizationNoiseVarianceSource(n) = string(sixgr.util.structGet(rx, ...
            "PostEqualizationNoiseVarianceSource", ""));
        trialNoiseVarStatus(n) = string(sixgr.util.structGet(rx, "NoiseVarStatus", ""));
        trialNoiseVarSource(n) = string(sixgr.util.structGet(rx, "NoiseVarSource", ""));
        trialNoiseVarReason(n) = string(sixgr.util.structGet(rx, "NoiseVarReason", ""));
        trialNoiseVarStrictFailure(n) = logical(sixgr.util.structGet(rx, "NoiseVarStrictFailure", false));
        trialUCIOnPUSCHApplied(n) = logical(sixgr.util.structGet(rx, "UCIOnPUSCHApplied", false));
        trialUCIOnPUSCHSource(n) = string(sixgr.util.structGet(rx, "UCIOnPUSCHSource", ""));
        trialUCIOnPUSCHEvidenceSource(n) = string(sixgr.util.structGet( ...
            rx, "UCIOnPUSCHEvidenceSource", ""));
        trialHARQACKBitCount(n) = double(sixgr.util.structGet(rx, "HARQACKBitCount", numel(expectedUCIBits)));
        lastExpectedHARQACKBits = int8(sixgr.util.structGet(rx, "ExpectedHARQACKBits", expectedUCIBits));
        lastDecodedHARQACKBits = int8(sixgr.util.structGet(rx, "DecodedHARQACKBits", int8([])));
        lastExpectedCSIPart1Bits = int8(sixgr.util.structGet(rx, "ExpectedCSIPart1Bits", int8([])));
        lastExpectedCSIPart2Bits = int8(sixgr.util.structGet(rx, "ExpectedCSIPart2Bits", int8([])));
        lastDecodedCSIPart1Bits = int8(sixgr.util.structGet(rx, "DecodedCSIPart1Bits", int8([])));
        lastDecodedCSIPart2Bits = int8(sixgr.util.structGet(rx, "DecodedCSIPart2Bits", int8([])));
        lastUCIReceiverEvidence=sixgr.util.structGet(rx,'UCIReceiverEvidence',struct());
        if ~isempty(fieldnames(lastUCIReceiverEvidence))
            trialUCIReceiverEvidenceJSON(n)=string(jsonencode(lastUCIReceiverEvidence));
        end
        lastCSI1ContentMatch = logical(sixgr.util.structGet(rx, "CSI1ContentMatch", ...
            isempty(lastExpectedCSIPart1Bits)));
        lastCSI2ContentMatch = logical(sixgr.util.structGet(rx, "CSI2ContentMatch", ...
            isempty(lastExpectedCSIPart2Bits)));
        trialExpectedHARQACKBits(n) = localBitVectorToken(lastExpectedHARQACKBits);
        trialDecodedHARQACKBits(n) = localBitVectorToken(lastDecodedHARQACKBits);
        trialCSI1BitCount(n) = double(sixgr.util.structGet(rx, ...
            "CSI1BitCount", numel(lastExpectedCSIPart1Bits)));
        trialCSI2BitCount(n) = double(sixgr.util.structGet(rx, ...
            "CSI2BitCount", numel(lastExpectedCSIPart2Bits)));
        trialExpectedCSIPart1Bits(n) = localBitVectorToken(lastExpectedCSIPart1Bits);
        trialExpectedCSIPart2Bits(n) = localBitVectorToken(lastExpectedCSIPart2Bits);
        trialDecodedCSIPart1Bits(n) = localBitVectorToken(lastDecodedCSIPart1Bits);
        trialDecodedCSIPart2Bits(n) = localBitVectorToken(lastDecodedCSIPart2Bits);
        trialCSI1ContentMatch(n) = lastCSI1ContentMatch;
        trialCSI2ContentMatch(n) = lastCSI2ContentMatch;
        trialHARQACKContentMatch(n) = logical(sixgr.util.structGet(rx, "HARQACKContentMatch", false));
        trialHARQACKDecodeStatus(n) = string(sixgr.util.structGet(rx, "HARQACKDecodeStatus", ""));
        trialHARQACKDecodeReason(n) = string(sixgr.util.structGet(rx, "HARQACKDecodeReason", ""));
        trialEqualizerType(n) = string(sixgr.util.structGet(rx, "EqualizerType", ""));
        trialEqualizerRequestedType(n) = string(sixgr.util.structGet(rx, "EqualizerRequestedType", ""));
        trialEqualizerEngine(n) = string(sixgr.util.structGet(rx, "EqualizerEngine", ""));
        trialEqualizerCovarianceFactorizationCount(n) = double(sixgr.util.structGet( ...
            rx, "EqualizerCovarianceFactorizationCount", NaN));
        trialInterferenceCovarianceAvailable(n) = logical(sixgr.util.structGet(rx, "InterferenceCovarianceAvailable", false));
        trialInterferenceCovarianceSource(n) = string(sixgr.util.structGet(rx, "InterferenceCovarianceSource", ""));
        trialInterferenceCovarianceStatus(n) = string(sixgr.util.structGet(rx, "InterferenceCovarianceStatus", ""));
        trialMUMIMOReceiveCombinerApplied(n) = logical(sixgr.util.structGet(rx, "MUMIMOReceiveCombinerApplied", false));
        trialMUMIMOReceiveCombinerStatus(n) = string(sixgr.util.structGet(rx, "MUMIMOReceiveCombinerStatus", ""));
        trialMUMIMOReceiveCombinerSource(n) = string(sixgr.util.structGet(rx, "MUMIMOReceiveCombinerSource", ""));
        trialMUMIMOReceiveCombinerInputBranches(n) = double(sixgr.util.structGet(rx, "MUMIMOReceiveCombinerInputBranches", NaN));
        trialMUMIMOReceiveCombinerOutputBranches(n) = double(sixgr.util.structGet(rx, "MUMIMOReceiveCombinerOutputBranches", NaN));
        trialMUMIMOReceiveCombinerMatrixSHA256(n) = string(sixgr.util.structGet(rx, "MUMIMOReceiveCombinerMatrixSHA256", ""));
        trialMUMIMOReceiveCombinerInterferenceProjected(n) = logical(sixgr.util.structGet(rx, ...
            "MUMIMOReceiveCombinerInterferenceContributionProjected", false)) || logical(sixgr.util.structGet(rx, ...
            "MUMIMOReceiveCombinerInterferenceCovarianceProjected", false));
        trialMUMIMOReceiveCombinerFullObservationPreserved(n) = logical(sixgr.util.structGet(rx, ...
            "MUMIMOReceiveCombinerFullObservationPreserved", false));
        trialMUMIMOReceiveCombinerIdentityResidual(n) = double(sixgr.util.structGet(rx, ...
            "MUMIMOReceiveCombinerIdentityResidual", NaN));
        trialMUMIMOReceiverAlgorithmApplied(n) = string(sixgr.util.structGet(rx, ...
            "MUMIMOReceiverAlgorithmApplied", ""));
        trialReceiverUsable(n) = logical(sixgr.util.structGet(rx, "ReceiverUsable", false));
        trialDecodeAttempted(n) = logical(sixgr.util.structGet(rx, "DecodeAttempted", false));
        trialDecodeUsable(n) = logical(sixgr.util.structGet(rx, "DecodeUsable", false));
        trialFailureReason(n) = string(sixgr.util.structGet(rx, "FailureReason", ""));
        trialStrictReceiverEvidenceOk(n) = logical(sixgr.util.structGet(rx, "StrictReceiverEvidenceOk", false));
        trialStrictOk(n) = logical(sixgr.util.structGet(rx, "StrictOk", false));
        trialTruthStatus(n) = string(sixgr.util.structGet(rx, "TruthStatus", ""));
        trialChannelEstimateAttempted(n) = logical(sixgr.util.structGet(rx, "ChannelEstimateAttempted", false));
        trialChannelEstimateAvailable(n) = logical(sixgr.util.structGet(rx, "ChannelEstimateAvailable", false));
        trialChannelEstimateSource(n) = string(sixgr.util.structGet(rx, "ChannelEstimateSource", ""));
        trialResourceExtractionAttempted(n) = logical(sixgr.util.structGet(rx, "ResourceExtractionAttempted", false));
        trialResourceExtractionAvailable(n) = logical(sixgr.util.structGet(rx, "ResourceExtractionAvailable", false));
        trialEqualizationAttempted(n) = logical(sixgr.util.structGet(rx, "EqualizationAttempted", false));
        trialEqualizationAvailable(n) = logical(sixgr.util.structGet(rx, "EqualizationAvailable", false));
        trialULSCHDecodeAttempted(n) = logical(sixgr.util.structGet(rx, "ULSCHDecodeAttempted", trialDecodeAttempted(n)));
        trialULSCHDecodeAvailable(n) = logical(sixgr.util.structGet(rx, "ULSCHDecodeAvailable", false));
        trialLLRAvailable(n) = logical(sixgr.util.structGet(rx, "LLRAvailable", false));
        trialLLRFinite(n) = logical(sixgr.util.structGet(rx, "LLRFinite", false));
        trialLLRScaleSource(n) = string(sixgr.util.structGet(rx, "LLRScaleSource", ""));
        trialLLRNoiseVariance(n) = double(sixgr.util.structGet(rx, "LLRNoiseVariance", NaN));
        trialLLRNoiseVarianceSource(n) = string(sixgr.util.structGet(rx, ...
            "LLRNoiseVarianceSource", ""));
        trialPostEqSINRAvailable(n) = logical(sixgr.util.structGet(rx, "PostEqSINRAvailable", false));
        trialPostEqSINRReceiverDerived(n) = logical(sixgr.util.structGet(rx, "PostEqSINRReceiverDerived", false));
        trialSINRValidationStatus(n) = string(sixgr.util.structGet(rx, "SINRValidationStatus", ""));
        trialSINRValidationReason(n) = string(sixgr.util.structGet(rx, "SINRValidationReason", ""));
        trialSINRComputationMethod(n) = string(sixgr.util.structGet(rx, "SINRComputationMethod", ""));
        trialConfiguredSNRLikeSourceRejected(n) = logical(sixgr.util.structGet(rx, "ConfiguredSNRLikeSourceRejected", false));
        trialReceiverHestSINR(n) = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
        trialReceiverHestSINRSource(n) = string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", ""));
        trialReceiverHestSINRValueRole(n) = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueRole", ""));
        trialReceiverHestSINRValueStatus(n) = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueStatus", ""));
        trialReceiverHestSINRNAReason(n) = string(sixgr.util.structGet(rx, "ReceiverHestSINRNAReason", ""));
        trialPostEqSINR(n) = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
        trialPostEqSINRSource(n) = string(sixgr.util.structGet(rx, "PostEqSINRSource", ""));
        trialPostEqSINRValueRole(n) = string(sixgr.util.structGet(rx, "PostEqSINRValueRole", ""));
        trialPostEqSINRValueStatus(n) = string(sixgr.util.structGet(rx, "PostEqSINRValueStatus", ""));
        trialPostEqSINRNAReason(n) = string(sixgr.util.structGet(rx, "PostEqSINRNAReason", ""));
        trialPostEqSINRPerLayer(n) = localFormatNumericVector(sixgr.util.structGet(rx, "PostEqSINRPerLayer_dB", NaN));
        trialPostEqSINRRawEqualizer(n) = double(sixgr.util.structGet(rx, "PostEqSINRRawEqualizer_dB", NaN));
        trialPostEqSINRDMRSResidualBoundApplied(n) = logical(sixgr.util.structGet(rx, "PostEqSINRDMRSResidualBoundApplied", false));
        trialPostEqSINRDMRSResidual(n) = double(sixgr.util.structGet(rx, "PostEqSINRDMRSResidual_dB", NaN));
        trialPostEqDMRSResidualNoiseVar(n) = double(sixgr.util.structGet(rx, "PostEqDMRSResidualNoiseVar", NaN));
        trialPostEqDMRSResidualSource(n) = string(sixgr.util.structGet(rx, "PostEqDMRSResidualSource", ""));
        trialPostEqDecisionResidual(n) = double(sixgr.util.structGet(rx, "PostEqDecisionResidual_dB", NaN));
        trialPostEqDecisionResidualNoiseVar(n) = double(sixgr.util.structGet(rx, "PostEqDecisionResidualNoiseVar", NaN));
        trialPostEqDecisionResidualSource(n) = string(sixgr.util.structGet(rx, "PostEqDecisionResidualSource", ""));
        trialConfiguredSNR(n) = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
        trialAppliedAWGNSNR(n) = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
        trialDesiredSignalPowerBeforeNoise(n) = double(sixgr.util.structGet(replay, "DesiredSignalPowerBeforeNoise", NaN));
        trialCompositeSignalPowerBeforeNoise(n) = double(sixgr.util.structGet(replay, "CompositeSignalPowerBeforeNoise", NaN));
        trialAppliedNoiseSNR(n) = double(sixgr.util.structGet(replay, "AppliedNoiseSNR_dB", NaN));
        trialNoiseVarianceSource(n) = string(sixgr.util.structGet(replay, ...
            "NoiseVarianceSource", trialNoiseVarSource(n)));
        trialReplaySampleNoiseVariance(n) = double(sixgr.util.structGet(replay, ...
            "InjectedNoiseVariancePreCompositeFrontEnd", sixgr.util.structGet(replay, ...
            "SampleNoiseVariance", NaN)));
        trialReceiverInputSampleNoiseVariance(n) = double(sixgr.util.structGet(replay, ...
            "InjectedNoiseVariancePostCompositeFrontEnd", sixgr.util.structGet(replay, ...
            "InjectedNoiseVariance", NaN)));
        trialReplayGridNoiseVariance(n) = double(sixgr.util.structGet(replay, ...
            "GridNoiseVariance", NaN));
        if ~isfinite(trialReplayGridNoiseVariance(n)) && ...
                isfinite(trialReplaySampleNoiseVariance(n)) && ...
                isfinite(trialSampleToGridNoiseVarianceGain(n))
            trialReplayGridNoiseVariance(n) = trialReplaySampleNoiseVariance(n) .* ...
                trialSampleToGridNoiseVarianceGain(n);
        end
        trialReplaySampleNoiseVarianceDomain(n) = string(sixgr.util.structGet(replay, ...
            "InjectedNoiseVariancePreCompositeFrontEndDomain", ...
            "receiver_sample_waveform_pre_composite_front_end"));
        trialReplayGridNoiseVarianceDomain(n) = string(sixgr.util.structGet(replay, ...
            "GridNoiseVarianceDomain", "resource_grid_pre_equalization"));
        trialReceiverInputSampleNoiseVarianceDomain(n) = string(sixgr.util.structGet(replay, ...
            "InjectedNoiseVariancePostCompositeFrontEndDomain", ...
            "receiver_sample_waveform_post_composite_front_end"));
        trialDesiredSignalPowerDomain(n) = string(sixgr.util.structGet(replay, ...
            "DesiredSignalPowerBeforeNoiseDomain", ...
            "receiver_sample_waveform_pre_noise_pre_composite_front_end"));
        trialCompositeSignalPowerDomain(n) = string(sixgr.util.structGet(replay, ...
            "CompositeSignalPowerBeforeNoiseDomain", ...
            "receiver_sample_waveform_pre_noise_pre_composite_front_end"));
        trialSNRReferencePlane(n) = string(sixgr.util.structGet(replay, ...
            "SNRReferencePlane", ""));
        trialAppliedNoiseSNRSource(n) = string(sixgr.util.structGet(replay, ...
            "AppliedNoiseSNRSource", ""));
        trialRequestedAWGNReferenceSNR(n) = double(sixgr.util.structGet(replay, ...
            "RequestedAWGNReferenceSNR_dB", NaN));
        trialSignalEnergyPerOccupiedRE(n) = double(sixgr.util.structGet(replay, ...
            "SignalEnergyPerOccupiedRE", NaN));
        trialReplaySampleNoiseVarianceSource(n) = string(sixgr.util.structGet(replay, ...
            "InjectedNoiseVariancePreCompositeFrontEndSource", ...
            sixgr.util.structGet(replay, "NoiseVarianceSource", "")));
        trialReplayGridNoiseVarianceSource(n) = string(sixgr.util.structGet(replay, ...
            "NoiseVarianceSource", "")) + "_ofdm_sample_to_grid_transform";
        trialReceiverInputSampleNoiseVarianceSource(n) = string(sixgr.util.structGet(replay, ...
            "InjectedNoiseVariancePostCompositeFrontEndSource", ...
            sixgr.util.structGet(replay, "NoiseVarianceSource", "")));
        trialAppliedLargeScaleGain(n) = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
        trialAppliedLargeScaleLoss(n) = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
        trialAppliedBasePathloss(n) = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
        trialAppliedPathloss(n) = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
        trialAppliedShadow(n) = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
        trialAppliedO2I(n) = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
        trialAppliedLargeScaleGainSource(n) = string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", ""));
        trialChannelComplianceMode(n) = string(sixgr.util.structGet(replay, "ChannelComplianceMode", ""));
        trialPathlossModelSource(n) = string(sixgr.util.structGet(replay, "PathlossModelSource", ""));
        trialPathlossComplianceStatus(n) = string(sixgr.util.structGet(replay, "PathlossComplianceStatus", ""));
        trialFallbackUsedForPathloss(n) = logical(sixgr.util.structGet(replay, "FallbackUsedForPathloss", false));
        trialO2IModelSource(n) = string(sixgr.util.structGet(replay, "O2IModelSource", ""));
        trialO2IComplianceStatus(n) = string(sixgr.util.structGet(replay, "O2IComplianceStatus", ""));
        trialO2IComplianceReason(n) = string(sixgr.util.structGet(replay, "O2IComplianceReason", ""));
        trialLOSProbabilitySource(n) = string(sixgr.util.structGet(replay, "LOSProbabilitySource", ""));
        trialLOSComplianceStatus(n) = string(sixgr.util.structGet(replay, "LOSComplianceStatus", ""));
        trialLOSComplianceReason(n) = string(sixgr.util.structGet(replay, "LOSComplianceReason", ""));
        trialIQImbalanceConfigured(n) = logical(sixgr.util.structGet(replay, "IQImbalanceConfigured", false));
        trialIQImbalanceApplied(n) = logical(sixgr.util.structGet(replay, "IQImbalanceApplied", false));
        trialIQImbalanceModel(n) = string(sixgr.util.structGet(replay, "IQImbalanceModel", ""));
        trialConfiguredIQGainImbalance(n) = double(sixgr.util.structGet(replay, "ConfiguredIQGainImbalance_dB", NaN));
        trialConfiguredIQPhaseImbalance(n) = double(sixgr.util.structGet(replay, "ConfiguredIQPhaseImbalance_deg", NaN));
        trialIQImbalanceMirrorPowerRatio(n) = double(sixgr.util.structGet(replay, "IQImbalanceMirrorPowerRatio_dB", NaN));
        trialIQImbalanceImageRejection(n) = double(sixgr.util.structGet(replay, "IQImbalanceImageRejection_dB", NaN));
        trialIQImbalanceIQPowerRatio(n) = double(sixgr.util.structGet(replay, "IQImbalanceIQPowerRatio_dB", NaN));
        trialIQImbalanceIQCorrelation(n) = double(sixgr.util.structGet(replay, "IQImbalanceIQCorrelation", NaN));
        trialIQImbalanceEstimatedAlphaAbs(n) = double(sixgr.util.structGet(replay, "IQImbalanceEstimatedAlphaAbs", NaN));
        trialIQImbalanceEstimatedBetaAbs(n) = double(sixgr.util.structGet(replay, "IQImbalanceEstimatedBetaAbs", NaN));
        trialIQImbalanceMeasurementSource(n) = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementSource", ""));
        trialIQImbalanceMeasurementStatus(n) = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementStatus", ""));
        trialInjectedCFO(n) = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
        trialCarrierPhaseOffsetDeg(n) = double(sixgr.util.structGet(replay, "InjectedCarrierPhaseOffset_deg", NaN));
        trialCarrierPhaseOffsetRad(n) = double(sixgr.util.structGet(replay, "InjectedCarrierPhaseOffset_rad", NaN));
        trialCarrierPhaseOffsetApplied(n) = logical(sixgr.util.structGet(replay, "CarrierPhaseOffsetApplied", false));
        trialCarrierPhaseOffsetSource(n) = string(sixgr.util.structGet(replay, "CarrierPhaseOffsetSource", ""));
        trialCarrierPhaseOffsetStatus(n) = string(sixgr.util.structGet(replay, "CarrierPhaseOffsetExecutionStatus", ""));
        trialEstimatedCFOPre(n) = double(sixgr.util.structGet(replay, "EstimatedCFO_PreCorrection_Hz", NaN));
        trialResidualCFOPost(n) = double(sixgr.util.structGet(replay, "ResidualCFO_PostCorrection_Hz", NaN));
        trialEstimatedCFO(n) = trialEstimatedCFOPre(n);
        trialTrueCFO(n) = trialInjectedCFO(n);
        if isfinite(trialEstimatedCFOPre(n))
            trialCFOError(n) = trialResidualCFOPost(n);
        else
            trialCFOError(n) = NaN;
        end
        trialInjectedTiming(n) = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN));
        trialEstimatedTimingPre(n) = trialTiming(n);
        trialResidualTimingPost(n) = double(sixgr.util.structGet(replay, "ResidualTimingError_PostCorrection_samples", NaN));
        trialTrueTiming(n) = double(sixgr.util.structGet(replay, ...
            "TrueReceiverTimingOffset_samples", trialInjectedTiming(n)));
        trialTimingError(n) = trialResidualTimingPost(n);
        trialTimingEstimateUsed(n) = logical(sixgr.util.structGet(replay, "TimingEstimateUsed", false));
        trialUseIdealTimingSync(n) = logical(sixgr.util.structGet(replay, "UseIdealTimingSync", useIdealTimingSync));
        trialInterferenceMode(n) = string(sixgr.util.structGet(replay, "InterferenceMode", "none"));
        trialInterferenceContributorCount(n) = double(sixgr.util.structGet(replay, "InterferenceContributorCount", 0));
        trialInterferenceAggregatedRxPower(n) = double(sixgr.util.structGet(replay, "InterferenceAggregatedRxPower_dBm", NaN));
        trialInterferencePowerSource(n) = string(sixgr.util.structGet(replay, "InterferencePowerSource", ""));
        trialFullInterfererChannelTruthUsed(n) = logical(sixgr.util.structGet(replay, "FullInterfererChannelTruthUsed", false));
        interferencePrecoding = localResolveInterferencePrecodingTrace(replay);
        trialInterfererBeamformingAppliedCount(n) = double(interferencePrecoding.InterfererBeamformingAppliedCount);
        trialInterfererExplicitBeamWeightCount(n) = double(interferencePrecoding.InterfererExplicitBeamWeightCount);
        trialInterfererTransformPrecodingCount(n) = double(interferencePrecoding.InterfererTransformPrecodingCount);
        trialInterfererPrecoderSourceSet(n) = string(interferencePrecoding.InterfererPrecoderSourceSet);
        trialInterfererPrecodingModeSet(n) = string(interferencePrecoding.InterfererPrecodingModeSet);
        trialInterfererBeamIndexSetSummary(n) = string(interferencePrecoding.InterfererBeamIndexSetSummary);
        trialLargeScaleSINR(n) = double(sixgr.util.structGet(replay, "LargeScaleSINR_dB", NaN));
        trialLargeScaleSINRSource(n) = string(sixgr.util.structGet(replay, "LargeScaleSINRSource", ""));
        trialServingRSRP(n) = double(sixgr.util.structGet(replay, "ServingRSRP_dBm", NaN));
        trialServingRSRPSource(n) = string(sixgr.util.structGet(replay, "ServingRSRPSource", ""));
        trialRuntimeEvidence{n} = localBuildRuntimeAntennaTimingEvidence("UL", cfgFrame, grantSnapshot, tx, txInfo, chState, replay);
        decodeEvidenceAvailable = trialDecodeAttempted(n) && trialULSCHDecodeAvailable(n) && ...
            trialLLRAvailable(n) && trialLLRFinite(n) && isfield(rx, "TransportBlock") && ...
            ~isempty(rx.TransportBlock);
        if ~decodeEvidenceAvailable
            blockErr = blockErr + 1;
            trialStatus(n) = "NA";
            trialCRC(n) = NaN;
            if strlength(strtrim(trialFailureReason(n))) == 0
                trialFailureReason(n) = "ulsch_decode_evidence_unavailable";
            end
            trialNotes(n) = "PUSCH decode unavailable: " + trialFailureReason(n);
            trialGoodBits(n) = NaN;
            trialGoodput(n) = NaN;
            lastHARQ = struct( ...
                "TransportBlockBits", int8(tx.TransportBlock(:)), ...
                "DecodedTransportBlockBits", int8([]), ...
                "CombinedLLR", previousCombinedLLR, ...
                "CurrentDecodeOK", false, ...
                "CombinedDecodeOK", false, ...
                "DecoderIterations", NaN, ...
                "GrantSnapshot", grantSnapshot, ...
                "TransportBlockContext", sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
                "HARQTBContext", sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
                "HARQContextStatus", char(string(sixgr.util.structGet(harqContext, "HARQContextStatus", ""))), ...
                "Context", harqContext);
            continue;
        elseif ~trialDecodeUsable(n)
            trialNotes(n) = "PUSCH receiver evidence incomplete: " + trialFailureReason(n);
        end
        pilotTrack = localPilotTrackingMetrics(rx);
        metrics = localAnalyzeChannelMetrics(sixgr.util.structGet(rx, "ChannelEstimate", []), trialNoise(n), cfgFrame, rx, ulPrecoding);
        trialNMSE(n) = metrics.NMSE_dB;
        trialDet(n) = metrics.DetectionMetric;
        selectedSINR = localSelectULMeasuredTrialSINRFromEvidence( ...
            trialPostEqSINR(n), trialPostEqSINRSource(n), trialPostEqSINRValueRole(n), ...
            trialPostEqSINRValueStatus(n), trialPostEqSINRNAReason(n));
        if isfinite(double(selectedSINR.Value))
            trialSINR(n) = double(selectedSINR.Value);
            trialSINRValueRole(n) = string(selectedSINR.ValueRole);
            trialSINRSource(n) = string(selectedSINR.Source);
            trialMeasuredTrialSINR(n) = double(selectedSINR.Value);
            trialMeasuredSINRSource(n) = string(selectedSINR.Source);
            trialMeasuredTrialSINRValueRole(n) = string(selectedSINR.ValueRole);
            trialMeasuredTrialSINRValueStatus(n) = string(selectedSINR.ValueStatus);
            trialMeasuredTrialSINRNAReason(n) = string(selectedSINR.NAReason);
        end
        trialCSIRSRP(n) = metrics.ULNormalizedReferencePower_dB;
        trialCSIRSRPSource(n) = string(metrics.ULNormalizedReferencePowerSource);
        trialCSIRSSI(n) = metrics.ULNormalizedWindowRSSI_dB;
        trialCSIRSSISource(n) = string(metrics.ULNormalizedWindowRSSISource);
        trialCSIRSRQ(n) = metrics.ULNormalizedWindowPowerRatio_dB;
        trialCSIRSRQSource(n) = string(metrics.ULNormalizedWindowPowerRatioSource);
        trialULNormalizedPowerEvidence(n)=metrics.ULNormalizedPowerEvidenceJSON;
        rawMeasuredCQI = double(sixgr.util.structGet(metrics, "CQI", NaN));
        receiverCQI = NaN;
        if isfinite(rawMeasuredCQI)
            receiverCQI = double(sixgr.util.normalizeReportedCQI(rawMeasuredCQI));
        end
        schedulerCQIHasGrantLineage = schedulerDrivenGrant && ...
            isfinite(grantCQIUsed) && grantCQIUsed > 0 && ...
            (isfinite(grantRawCQIDerivedMCS) || isfinite(grantCQIBasedMCS) || ...
            strlength(strtrim(grantCQIProvenance)) > 0 || ...
            strlength(strtrim(grantMCSSelectionSource)) > 0);
        if schedulerCQIHasGrantLineage
            trialCQI(n) = double(sixgr.util.normalizeReportedCQI(grantCQIUsed));
            sourceToken = strtrim(grantCQIProvenance);
            if strlength(sourceToken) == 0
                sourceToken = strtrim(grantMCSSelectionSource);
            end
            if strlength(sourceToken) == 0
                trialCQISource(n) = "scheduler_grant_cqi_used";
            else
                trialCQISource(n) = "scheduler_grant:" + sourceToken;
            end
        elseif isfinite(receiverCQI)
            trialCQI(n) = receiverCQI;
            trialCQISource(n) = string(sixgr.util.structGet(metrics, "CQISource", "ul_link_state_reference_signal_cqi"));
            if strlength(strtrim(trialCQISource(n))) == 0
                trialCQISource(n) = "ul_link_state_reference_signal_cqi";
            end
        elseif schedulerDrivenGrant && isfinite(grantCQIUsed) && grantCQIUsed > 0
            trialCQI(n) = double(sixgr.util.normalizeReportedCQI(grantCQIUsed));
            trialCQISource(n) = "scheduler_grant_cqi_used_no_current_receiver_cqi";
        elseif schedulerDrivenGrant && ~isfinite(trialCQI(n))
            trialCQISource(n) = "current_receiver_cqi_unavailable_no_scheduler_grant_cqi";
        end
        trialRI(n) = metrics.RI;
        trialPMI(n) = metrics.PMI;
        trialCRI(n) = metrics.CRI;
        trialPMIType(n) = string(metrics.PMIType);
        trialPMICodebookMode(n) = string(metrics.PMICodebookMode);
        trialPMISource(n) = string(metrics.PMISource);
        spatialFields={'ChannelEstimateDomain','RankEstimate','RI','RISource', ...
            'PMI','PMISource','ConfiguredPMI','RuntimeAppliedPMI','CSIReportMode', ...
            'SRSRITPMIValid','SRSRITPMIStatus','SelectedCodebookPortIndices1Based'};
        spatialEvidence=struct();
        for spatialFieldIndex=1:numel(spatialFields)
            spatialField=spatialFields{spatialFieldIndex};
            spatialEvidence.(spatialField)=metrics.(spatialField);
        end
        trialULSpatialMeasurementEvidence(n)=string(jsonencode(spatialEvidence));
        trialCSIReportMode(n) = string(metrics.CSIReportMode);
        trialCSIPayloadBits(n) = metrics.CSIPayloadBitLength;
        trialCSIPayloadHex(n) = string(metrics.CSIPayloadHex);
        trialGain(n) = metrics.ChannelGain_dB;
        trialRank(n) = metrics.RankEstimate;
        trialCond(n) = metrics.ConditionNumber_dB;
        trialRxAnt(n) = metrics.NumRxAnt;
        trialTxPorts(n) = metrics.NumTxPorts;
        trialSelectedBeam(n) = metrics.SelectedBeamIndex;
        trialBestBeam(n) = metrics.BestBeamIndex;
        trialBeamHit(n) = metrics.BeamHit;
        trialTopKBeamHit(n) = metrics.TopKBeamHit;
        trialBeamCount(n) = metrics.BeamCandidateCount;
        trialSelectedBeamGain(n) = metrics.SelectedBeamGain_dB;
        trialBestBeamGain(n) = metrics.BestBeamGain_dB;
        trialBeamGap(n) = metrics.BeamGainGap_dB;
        trialBeamScoreVector(n) = string(metrics.BeamScoreVector_dB);
        trialTopBeamIndexSet(n) = string(metrics.TopBeamIndexSet);
        trialTopBeamGainSet(n) = string(metrics.TopBeamGainSet_dB);
        trialBeamScoreSource(n) = string(metrics.BeamScoreSource);
        coding = sixgr.link.deriveCodingTrialMetrics(tx, txInfo, rx, cfgFrame);
        if ~isfinite(trialDecIt(n))
            trialDecIt(n) = double(sixgr.util.structGet(coding, "DecoderIterations", NaN));
        end
        trialOfferedBits(n) = double(sixgr.util.structGet(coding, "OfferedBits", NaN));
        if isRetransmission
            % Retransmissions consume TTIs but do not represent newly offered
            % source traffic for goodput/offered-throughput KPIs.
            trialOfferedBits(n) = 0;
        end
        trialComputeLatency(n) = double(sixgr.util.structGet(coding, "ComputeLatency_ms", ...
            sixgr.util.structGet(coding, "Latency_ms", NaN)));
        if isfinite(trialComputeLatency(n))
            trialComputeLatencySource(n) = "receiver_instrumented_ldpc_decode";
        else
            trialComputeLatencySource(n) = "unavailable";
        end
        trialProcedureDelay(n) = double(sixgr.util.structGet(coding, "ProcedureDelay_ms", NaN));
        if ~isfinite(trialProcedureDelay(n))
            % The pure link-level UL PHY chain executes within the same grant observation.
            % Absence of an instrumented procedure stage remains unavailable;
            % it is not silently converted into a measured zero.
            trialProcedureDelay(n) = NaN;
        end
        % The generic Latency_ms alias stays unavailable in new exports.
        trialLatency(n) = NaN;
        trialDecodeLatency(n) = double(sixgr.util.structGet(coding, "DecodeLatency_ms", NaN));
        if isfinite(trialDecodeLatency(n))
            trialDecodeLatencySource(n) = "receiver_instrumented_ldpc_decode";
        else
            trialDecodeLatencySource(n) = "unavailable";
        end
        if ~isfinite(trialReceiverPipelineLatency(n))
            trialReceiverPipelineLatency(n) = 1e3 * toc(trialPipelineTic);
            trialReceiverPipelineLatencySource(n) = "matlab_tic_toc_tx_channel_rx_trial";
        end
        trialEarlyStop(n) = double(sixgr.util.structGet(coding, "EarlyStopRate", NaN));
        trialDecoderComplexity(n) = double(sixgr.util.structGet(coding, "DecoderComplexityUnits", NaN));
        trialNormDecoderComplexity(n) = double(sixgr.util.structGet(coding, "NormalizedDecoderComplexity", NaN));
        trialAreaEfficiency(n) = double(sixgr.util.structGet(coding, "AreaEfficiencyProxy", NaN));
        trialNumCB(n) = double(sixgr.util.structGet(coding, "NumCodeBlocks", NaN));
        trialCBLen(n) = double(sixgr.util.structGet(coding, "CodeBlockLength_bits", NaN));
        trialSegOccurred(n) = double(sixgr.util.structGet(coding, "SegmentationOccurred", NaN));
        trialSegPadding(n) = double(sixgr.util.structGet(coding, "SegmentationPaddingBits", NaN));
        trialTBCRC(n) = double(sixgr.util.structGet(coding, "TBCRCLength_bits", NaN));
        trialTBWithCRC(n) = double(sixgr.util.structGet(coding, "TBLengthWithCRC_bits", NaN));
        trialBaseGraph(n) = double(sixgr.util.structGet(coding, "BaseGraph", NaN));
        trialEncodedBits(n) = double(sixgr.util.structGet(coding, "EncodedBits", NaN));
        trialRateMatchedBits(n) = double(sixgr.util.structGet(coding, "RateMatchedBits", NaN));
        trialRateMatchPuncture(n) = double(sixgr.util.structGet(coding, "RateMatchPunctureBits", NaN));
        trialRateMatchRepetition(n) = double(sixgr.util.structGet(coding, "RateMatchRepetitionBits", NaN));
        trialCBErr(n) = double(sixgr.util.structGet(coding, "CodeBlockErrors", NaN));
        trialCBCount(n) = double(sixgr.util.structGet(coding, "CodeBlockCount", NaN));
        trialCBBLER(n) = double(sixgr.util.structGet(coding, "CodeBlockBLER", NaN));
        trialCBGErr(n) = double(sixgr.util.structGet(coding, "CBGErrors", NaN));
        trialCBGCount(n) = double(sixgr.util.structGet(coding, "CBGCount", NaN));
        trialCBGBLER(n) = double(sixgr.util.structGet(coding, "CBGBLER", NaN));
        if isfinite(trialOfferedBits(n))
            trialOfferedThr(n) = trialOfferedBits(n) / max(slotDur_s, eps) / 1e6;
        end
        if isfinite(trialTB(n))
            trialThroughput(n) = trialTB(n) / max(slotDur_s, eps) / 1e6;
        end
        [modTrack, constT] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfgFrame, "UL");
        trialEVM(n) = double(sixgr.util.structGet(modTrack, "EVM_rms", trialEVM(n)));
        [trialDecoderTruthProxySINR(n), decoderTruthProxyMeta] = sixgr.link.deriveDecoderTruthProxySINR(modTrack);
        trialDecoderTruthProxySINRSource(n) = string(sixgr.util.structGet(decoderTruthProxyMeta, "Source", ""));
        [dataSINR, dataSINRMeta] = localEVMProxySINR(modTrack);
        if isfinite(dataSINR)
            trialEVMProxySINR(n) = double(dataSINR);
            trialEVMProxySINRSource(n) = string(dataSINRMeta.Source);
            trialEVMProxySINRValueRole(n) = string(dataSINRMeta.ValueRole);
            trialEVMProxySINRValueStatus(n) = string(dataSINRMeta.ValueStatus);
            trialEVMProxySINRNAReason(n) = string(dataSINRMeta.NAReason);
        else
            trialEVMProxySINRSource(n) = string(dataSINRMeta.Source);
            trialEVMProxySINRValueRole(n) = string(dataSINRMeta.ValueRole);
            trialEVMProxySINRValueStatus(n) = string(dataSINRMeta.ValueStatus);
            trialEVMProxySINRNAReason(n) = string(dataSINRMeta.NAReason);
        end
        if isfinite(trialCQI(n))
            [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "UL");
            trialCQIDerivedMCS(n) = double(cqiMCS);
            trialCQIDerivedCodeRate(n) = double(cqiRate);
            trialCQIDerivedModulation(n) = string(cqiMod);
        end
        trialPAPR(n) = double(sixgr.util.structGet(modTrack, "PAPR_dB", NaN));
        trialClipEvents(n) = double(sixgr.util.structGet(modTrack, "PeakClippingEvents", NaN));
        trialSymErr(n) = double(sixgr.util.structGet(modTrack, "SymbolErrors", NaN));
        trialSymTot(n) = double(sixgr.util.structGet(modTrack, "SymbolsCompared", NaN));
        trialSER(n) = double(sixgr.util.structGet(modTrack, "SymbolErrorRate", NaN));
        trialSymbolDecisionStatus(n) = string(modTrack.SymbolDecisionStatus);
        trialResidualInterference(n) = double(sixgr.util.structGet(modTrack, "ResidualInterferencePower_dB", NaN));
        trialLLRMeanAbs(n) = double(sixgr.util.structGet(modTrack, "LLRMeanAbs", NaN));
        trialLLRStdAbs(n) = double(sixgr.util.structGet(modTrack, "LLRStdAbs", NaN));
        trialLLRImbalance(n) = double(sixgr.util.structGet(modTrack, "LLRImbalance", NaN));
        trialMapSens(n) = double(sixgr.util.structGet(modTrack, "ModulationMappingSensitivity", NaN));
        trialShapeLoss(n) = double(sixgr.util.structGet(modTrack, "ShapingRateLoss", NaN));
        trialDMLatency(n) = double(sixgr.util.structGet(modTrack, "DistributionMatchingLatency_ms", NaN));
        trialHighOrderRobustness(n) = double(sixgr.util.structGet(modTrack, "HighOrderRobustness", NaN));
        trialDetectorComplexity(n) = double(sixgr.util.structGet(modTrack, "DetectorComplexityUnits", NaN));
        trialDataRECount(n) = double(sixgr.util.structGet(modTrack, "DataRECount", NaN));
        trialDataRECountPerLayer(n) = double(sixgr.util.structGet(modTrack, "DataRECountPerLayer", trialDataRECount(n)));
        trialTotalDataRECount(n) = double(sixgr.util.structGet(modTrack, "TotalDataRECount", NaN));
        tbsAccounting = sixgr.util.structGet(tx, "ResourceAccounting", struct());
        trialTBSInputNREPerPRB(n) = double(sixgr.util.structGet( ...
            tbsAccounting, "NREPerPRBForTBS", sixgr.util.structGet(tx, "NREPerPRB", NaN)));
        trialTBSInputXOverhead(n) = double(sixgr.util.structGet(tx, ...
            "XOverhead", sixgr.util.structGet(cfgFrame, "phy.pusch.xOverhead", NaN)));
        trialTBSInputSource(n) = string(sixgr.util.structGet( ...
            tbsAccounting, "Source", ""));
        trialModulationOrderQm(n) = double(sixgr.util.structGet(modTrack, "ModulationOrderQm", NaN));
        trialComputedE_TS38212(n) = double(sixgr.util.structGet(modTrack, "ComputedE_TS38212", NaN));
        trialDMRSRECount(n) = double(sixgr.util.structGet(modTrack, "DMRSRECount", NaN));
        trialPTRSRECount(n) = double(sixgr.util.structGet(modTrack, "PTRSRECount", NaN));
        trialRSOverhead(n) = double(sixgr.util.structGet(modTrack, "RSOverheadFraction", NaN));
        trialEstDoppler(n) = double(sixgr.util.structGet(modTrack, "EstimatedDopplerHz", NaN));
        trialDopplerErr(n) = trialEstDoppler(n) - dopplerHz;
        trialPhaseTrackErr(n) = double(sixgr.util.structGet(modTrack, "PhaseTrackingError_deg", NaN));
        trialQCL(n) = double(sixgr.util.structGet(modTrack, "QCLAccuracy", NaN));
        trialChannelReferenceCorrelation(n) = double(modTrack.EstimatedChannelReferenceCorrelationMagnitude);
        trialAgingLoss(n) = double(sixgr.util.structGet(modTrack, "ChannelAgingLoss_dB", NaN));
        trialInterpLoss(n) = double(sixgr.util.structGet(modTrack, "InterpolationLoss_dB", NaN));
        trialMismatch(n) = double(sixgr.util.structGet(modTrack, "MismatchSensitivity_dB", NaN));
        if isfinite(double(sixgr.util.structGet(pilotTrack, "NMSE_dB", NaN)))
            trialNMSE(n) = double(pilotTrack.NMSE_dB);
            trialDet(n) = double(sixgr.util.structGet(pilotTrack, "DetectionMetric", trialDet(n)));
        end
        if isfinite(double(sixgr.util.structGet(pilotTrack, "EstimatedDopplerHz", NaN)))
            trialEstDoppler(n) = double(pilotTrack.EstimatedDopplerHz);
            trialDopplerErr(n) = trialEstDoppler(n) - dopplerHz;
        end
        if isfinite(double(sixgr.util.structGet(pilotTrack, "PhaseTrackingError_deg", NaN)))
            trialPhaseTrackErr(n) = double(pilotTrack.PhaseTrackingError_deg);
        end
        trialEstDoppler(n) = localSanitizeEstimatedDoppler(trialEstDoppler(n), cfgFrame, trialNMSE(n));
        if isfinite(trialEstDoppler(n)) && isfinite(dopplerHz)
            trialDopplerErr(n) = trialEstDoppler(n) - dopplerHz;
        else
            trialDopplerErr(n) = NaN;
        end
        if istable(constT) && ~isempty(constT)
            nConst = height(constT);
            snrLineage_dB = NaN;
            if isfinite(double(trialAppliedNoiseSNR(n)))
                snrLineage_dB = double(trialAppliedNoiseSNR(n));
            elseif isfinite(double(trialAppliedAWGNSNR(n)))
                snrLineage_dB = double(trialAppliedAWGNSNR(n));
            elseif isfinite(double(trialConfiguredSNR(n)))
                snrLineage_dB = double(trialConfiguredSNR(n));
            elseif isfinite(double(snr_dB))
                snrLineage_dB = double(snr_dB);
            end
            constT.Frame = repmat(double(trialFrame(n)), height(constT), 1);
            constT.Slot = repmat(double(trialSlot(n)), height(constT), 1);
            constT.SFN = repmat(trialSFN(n), nConst, 1);
            constT.CarrierNFrame = repmat(trialCarrierNFrame(n), nConst, 1);
            constT.CarrierNSlot = repmat(trialCarrierNSlot(n), nConst, 1);
            constT.UEIndex = repmat(trialUEIndex(n), nConst, 1);
            constT.RNTI = repmat(trialRNTI(n), nConst, 1);
            constT.BaseStationID = repmat(trialBaseStationID(n), nConst, 1);
            % Cell identity comes from the actual grant/attached UE context,
            % not a guessed PCI or the reporting frame/UE identifier.
            constT.ServingCell = repmat(double(sixgr.util.structGet(grantSnapshot, ...
                "ServingCell", sixgr.util.structGet(cfgFrame, ...
                "lls6g.userContext.RuntimeServingCell", NaN))), nConst, 1);
            if ismember("SNR_dB", string(constT.Properties.VariableNames))
                sampleSNR = double(constT.SNR_dB);
                sampleSNR(~isfinite(sampleSNR)) = snrLineage_dB;
                constT.SNR_dB = sampleSNR;
            else
                constT.SNR_dB = repmat(snrLineage_dB, nConst, 1);
            end
            constT.TBId = repmat(double(n), nConst, 1);
            constT.MCSIndex = repmat(double(trialMCS(n)), nConst, 1);
            constT.MCS = repmat(double(trialMCS(n)), nConst, 1);
            constT.Layers = repmat(double(trialLayers(n)), nConst, 1);
            constT.PostEqSINR_dB = repmat(double(trialSINR(n)), nConst, 1);
            constT.MeasuredSINR_dB = repmat(double(trialSINR(n)), nConst, 1);
            constT.EVM_rms = repmat(double(trialEVM(n)), nConst, 1);
            constT.EVM_rms_pct = repmat(double(trialEVM(n)) * 100, nConst, 1);
            constT.EVM_dB = repmat(20 * log10(max(double(trialEVM(n)), realmin)), nConst, 1);
            constT.Normalization = repmat(string(modTrack.EVMComputationDomain), nConst, 1);
            constT.TruthStatus = repmat("real_lls_evidence", nConst, 1);
            constT.direction = string(constT.Direction);
            constT.ue_id = constT.UEIndex;
            constT.slot = double(constT.Slot);
            constT.tb_id = double(constT.TBId);
            constT.layer = double(constT.LayerIndex);
            constT.modulation = string(constT.Modulation);
            constT.mcs_index = double(constT.MCSIndex);
            constT.snr_db = double(constT.SNR_dB);
            constT.posteq_sinr_db = double(constT.PostEqSINR_dB);
            constT.symbol_index = double(constT.SampleIndex);
            constT.reference_symbol_i = double(constT.ReferenceSymbolReal);
            constT.reference_symbol_q = double(constT.ReferenceSymbolImag);
            constT.equalized_i = double(constT.EqualizedReal);
            constT.equalized_q = double(constT.EqualizedImag);
            constT.evm_rms_pct = double(constT.EVM_rms_pct);
            constT.evm_db = double(constT.EVM_dB);
            constT.normalization = string(constT.Normalization);
            constT.truth_status = string(constT.TruthStatus);
            constellationChunks{n} = constT;
        end

        if ~logical(sixgr.util.structGet(signalDiagnostic, "Available", false))
            diagnosticTBId = string(trialHARQTBId(n));
            if strlength(strtrim(diagnosticTBId)) == 0
                diagnosticTBId = string(n);
            end
            diagnosticContext = struct( ...
                "Frame", double(trialFrame(n)), ...
                "Slot", double(trialSlot(n)), ...
                "UEIndex", double(trialUEIndex(n)), ...
                "RNTI", double(trialRNTI(n)), ...
                "TBId", diagnosticTBId, ...
                "LayerIndex", 1, ...
                "Layers", double(trialLayers(n)), ...
                "Modulation", string(trialModulation(n)), ...
                "MCSIndex", double(trialMCS(n)), ...
                "ConfiguredSNR_dB", double(trialConfiguredSNR(n)), ...
                "ConfiguredSNRSource", string(sixgr.util.structGet(replay, "ConfiguredSNRSource", "runner_configured_stimulus")), ...
                "PostEqSINR_dB", double(trialPostEqSINR(n)), ...
                "PostEqSINRSource", string(trialPostEqSINRSource(n)), ...
                "PostEqSINRValueRole", string(trialPostEqSINRValueRole(n)), ...
                "EVM_rms", double(trialEVM(n)), ...
                "CRCPass", double(sixgr.util.structGet(rx, "CRCPass", NaN)), ...
                "SampleRate_Hz", double(localResolveSampleRate(tx, txInfo)), ...
                "PostChannelWaveform", sixgr.util.structGet(replay, ...
                    "PostChannelWaveformPreview", complex([])), ...
                "PostChannelWaveformSHA256", string(sixgr.util.structGet(replay, ...
                    "PostChannelWaveformSHA256", "")), ...
                "RuntimeChannelPathGains", sixgr.util.structGet(replay, ...
                    "RuntimeChannelPathGainsPreview", complex([])), ...
                "RuntimeChannelPathGainSampleTimes_s", sixgr.util.structGet(replay, ...
                    "RuntimeChannelPathGainSampleTimes_s", []), ...
                "RuntimeChannelPathDelays_s", sixgr.util.structGet(replay, ...
                    "RuntimeChannelPathDelays_s", []), ...
                "RuntimeChannelPathGainsSHA256", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelPathGainsSHA256", "")), ...
                "RuntimeChannelStateKey", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelStateKey", "")), ...
                "RuntimeChannelLinkKey", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelLinkKey", "")), ...
                "RuntimeChannelSeed", double(sixgr.util.structGet(replay, ...
                    "RuntimeChannelSeed", NaN)), ...
                "RuntimeChannelReciprocityExact", logical(sixgr.util.structGet(replay, ...
                    "RuntimeChannelReciprocityExact", false)), ...
                "RuntimeChannelReciprocityDirection", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelReciprocityDirection", "")), ...
                "RuntimeChannelReciprocitySource", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelReciprocitySource", "")), ...
                "RuntimeChannelReciprocityApproximationMode", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelReciprocityApproximationMode", "")), ...
                "RuntimeChannelTransmitAndReceiveSwapped", logical(sixgr.util.structGet(replay, ...
                    "RuntimeChannelTransmitAndReceiveSwapped", false)), ...
                "RuntimeChannelAngleEvidenceAvailable", logical(sixgr.util.structGet(replay, ...
                    "RuntimeChannelAngleEvidenceAvailable", false)), ...
                "RuntimeChannelAnglesAoD_deg", sixgr.util.structGet(replay, ...
                    "RuntimeChannelAnglesAoD_deg", []), ...
                "RuntimeChannelAnglesAoA_deg", sixgr.util.structGet(replay, ...
                    "RuntimeChannelAnglesAoA_deg", []), ...
                "RuntimeChannelAnglesZoD_deg", sixgr.util.structGet(replay, ...
                    "RuntimeChannelAnglesZoD_deg", []), ...
                "RuntimeChannelAnglesZoA_deg", sixgr.util.structGet(replay, ...
                    "RuntimeChannelAnglesZoA_deg", []), ...
                "RuntimeChannelAngleCoordinateFrame", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelAngleCoordinateFrame", "")), ...
                "RuntimeChannelAngleEvidenceSource", string(sixgr.util.structGet(replay, ...
                    "RuntimeChannelAngleEvidenceSource", "")));
            signalDiagnostic = sixgr.link.buildPHYSignalDiagnosticSnapshot( ...
                cfgFrame, "UL", tx, rxWave, rx, constT, diagnosticContext);
        end

        txBits = int8(tx.TransportBlock(:));
        rxBits = int8(rx.TransportBlock(:));
        finalRxBits = rxBits;
        currentRecLLR = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
        currentCodingLayout = sixgr.util.structGet(rx, "CodingLayout", sixgr.util.structGet(tx, "CodingLayout", struct()));
        [combinedLLR, harqCombining] = localCombineRateRecoveredLLR(previousCombinedLLR, currentRecLLR, currentCodingLayout);
        combinedDecodeOK = false;
        combinedDecodeIt = NaN;
        L = min(numel(txBits), numel(rxBits));
        if L == 0
            blockErr = blockErr + 1;
            trialGoodBits(n) = 0;
            if isfinite(trialOfferedBits(n))
                trialGoodput(n) = 0;
            end
            lastHARQ = struct( ...
                "TransportBlockBits", txBits, ...
                "DecodedTransportBlockBits", rxBits, ...
                "CombinedLLR", combinedLLR, ...
                "SoftBuffer", harqCombining.SoftBuffer, ...
                "HARQSoftBuffer", harqCombining.SoftBuffer, ...
                "PreviousLLRCount", harqCombining.PreviousLLRCount, ...
                "CurrentLLRCount", harqCombining.CurrentLLRCount, ...
                "CombinedLLRCount", harqCombining.CombinedLLRCount, ...
                "HARQCombiningApplied", harqCombining.CombiningApplied, ...
                "HARQSoftCombiningPositionAware", harqCombining.PositionAware, ...
                "HARQSoftCombiningReason", harqCombining.CombiningSkipReason, ...
                "LLRCombiningGain_dB", harqCombining.LLRCombiningGain_dB, ...
                "CurrentDecodeOK", false, ...
                "CombinedDecodeOK", false, ...
                "DecoderIterations", combinedDecodeIt, ...
                "GrantSnapshot", grantSnapshot, ...
                "TransportBlockContext", sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
                "HARQTBContext", sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
                "HARQContextStatus", char(string(sixgr.util.structGet(harqContext, "HARQContextStatus", ""))), ...
                "Context", harqContext);
            continue;
        end

        currentBe = sum(txBits(1:L) ~= rxBits(1:L));
        finalBe = currentBe;
        finalBitsCompared = L;
        bitTot = bitTot + double(numel(txBits));
        if isfield(rx, "ActiveIterations") && ~isempty(rx.ActiveIterations)
            trialDecIt(n) = mean(double(rx.ActiveIterations(:)), "omitnan");
        end
        if ~isfinite(trialEVM(n)) && isfield(rx, "EqualizedSymbols") && isfield(tx, "PUSCHSymbols")
            try
                refSym = double(tx.PUSCHSymbols(:));
                eqSym = double(rx.EqualizedSymbols(:));
                Lsym = min(numel(refSym), numel(eqSym));
                [eqNorm, refNorm] = localNormalizeEVMInputs(eqSym(1:Lsym), refSym(1:Lsym));
                if ~isempty(eqNorm)
                    e = eqNorm - refNorm;
                    trialEVM(n) = sqrt(mean(abs(e).^2, "omitnan"));
                end
            catch
            end
        end

        currentDecodeOK = rx.Ok && currentBe == 0 && numel(rxBits) == numel(txBits);
        hasPriorHARQEvidence = localHARQPriorAvailable(previousCombinedLLR);
        if hasPriorHARQEvidence && ~currentDecodeOK
            [combinedDecodeOK, combinedDecodeIt, combinedRxBits] = localDecodeCombinedLLR(tx, combinedLLR, cfgFrame);
            if combinedDecodeOK
                [combinedBe, combinedBitsCompared] = localFinalBitErrors(txBits, combinedRxBits);
                combinedDecodeOK = combinedBitsCompared == numel(txBits) && combinedBe == 0;
                finalBe = combinedBe;
                finalBitsCompared = combinedBitsCompared;
                if combinedDecodeOK
                    finalRxBits = int8(combinedRxBits(:));
                end
            end
        else
            combinedDecodeOK = logical(currentDecodeOK);
            if isfinite(trialDecIt(n))
                combinedDecodeIt = double(trialDecIt(n));
            end
        end
        finalDecodeOK = logical(combinedDecodeOK);
        trialBitErr(n) = double(finalBe);
        trialBitTot(n) = double(finalBitsCompared);
        bitErr = bitErr + double(finalBe);
        if finalDecodeOK
            bitGood = bitGood + double(numel(txBits));
            trialCRC(n) = 1;
            trialStatus(n) = "PASS";
            trialGoodBits(n) = double(numel(txBits));
        else
            blockErr = blockErr + 1;
            trialCRC(n) = 0;
            trialStatus(n) = "FAIL";
            trialGoodBits(n) = 0;
        end
        if isfinite(trialGoodBits(n))
            trialGoodput(n) = trialGoodBits(n) / max(slotDur_s, eps) / 1e6;
        end
        if isRetransmission || schedulerDrivenGrant
            trialLAScheduled(n) = false;
        else
            metrics.CQI = double(trialCQI(n));
            metrics.SINR_dB = double(trialSINR(n));
            metrics.CRCPass = logical(finalDecodeOK);
            metrics.CurrentDecodeOK = logical(currentDecodeOK);
            metrics.CombinedDecodeOK = logical(finalDecodeOK);
            metrics.AckObserved = logical(finalDecodeOK);
            metrics.DecoderIterations = double(combinedDecodeIt);
            metrics.SourceSlot = double(trialSlot(n));
            metrics.RV = double(trialRV(n));
            metrics.IsRetransmission = false;
            [cfgDyn, laState, laObserveEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "UL", trialSlot(n), ...
                "Phase", "after", "Metrics", metrics);
            trialLAScheduled(n) = logical(laObserveEvent.Scheduled);
            trialLAFeedbackDelaySlots(n) = double(laObserveEvent.ConfiguredFeedbackDelaySlots);
            trialLAFeedbackDelaySource(n) = string(laObserveEvent.FeedbackDelaySource);
            trialLAFeedbackDelayStatus(n) = string(laObserveEvent.FeedbackDelayStatus);
            if logical(laObserveEvent.Scheduled)
                scheduledDecision = laObserveEvent.Decision;
                trialLAScheduledSourceSlot(n) = double(laObserveEvent.FeedbackSourceSlot);
                trialLAScheduledApplySlot(n) = double(laObserveEvent.ApplySlot);
                trialLAScheduledDecisionCQI(n) = double(sixgr.util.structGet(scheduledDecision, "ResolvedCQI", NaN));
                trialLAScheduledDecisionMCS(n) = double(sixgr.util.structGet(scheduledDecision, "MCSIndex", NaN));
                trialLAScheduledDecisionOLLADeltaDb(n) = double(sixgr.util.structGet(scheduledDecision, "OLLADeltaDb", NaN));
                trialLAScheduledDecisionOLLAUpdateCount(n) = double(sixgr.util.structGet(scheduledDecision, "OLLAUpdateCount", NaN));
                trialLAScheduledDecisionOLLAFeedbackEligible(n) = logical(sixgr.util.structGet(scheduledDecision, "OLLAFeedbackEligible", false));
                trialLAScheduledDecisionOLLAFeedbackExclusionReason(n) = string(sixgr.util.structGet(scheduledDecision, "OLLAFeedbackExclusionReason", ""));
            end
        end
        lastHARQ = struct( ...
            "TransportBlockBits", txBits, ...
            "DecodedTransportBlockBits", finalRxBits, ...
            "CombinedLLR", combinedLLR, ...
            "SoftBuffer", harqCombining.SoftBuffer, ...
            "HARQSoftBuffer", harqCombining.SoftBuffer, ...
            "PreviousLLRCount", harqCombining.PreviousLLRCount, ...
            "CurrentLLRCount", harqCombining.CurrentLLRCount, ...
            "CombinedLLRCount", harqCombining.CombinedLLRCount, ...
            "HARQCombiningApplied", harqCombining.CombiningApplied, ...
            "HARQSoftCombiningPositionAware", harqCombining.PositionAware, ...
            "HARQSoftCombiningReason", harqCombining.CombiningSkipReason, ...
            "LLRCombiningGain_dB", harqCombining.LLRCombiningGain_dB, ...
            "CurrentDecodeOK", logical(currentDecodeOK), ...
            "CombinedDecodeOK", logical(finalDecodeOK), ...
            "DecoderIterations", combinedDecodeIt, ...
            "GrantSnapshot", grantSnapshot, ...
            "TransportBlockContext", sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
            "HARQTBContext", sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
            "HARQContextStatus", char(string(sixgr.util.structGet(harqContext, "HARQContextStatus", ""))), ...
            "Context", harqContext);
    catch ME
        if prepareOnly || receivedCompletion
            rethrow(ME); % Never turn an invalid stream context into a decoded trial.
        end
        blockErr = blockErr + 1;
        frameCrash = frameCrash + 1;
        crashIdentifier = string(ME.identifier);
        if strlength(crashIdentifier) == 0
            crashIdentifier = "MATLAB:unidentified";
        end
        crashStack = strings(0, 1);
        for stackIdx = 1:numel(ME.stack)
            crashStack(end + 1, 1) = string(ME.stack(stackIdx).name) + ...
                ":" + string(ME.stack(stackIdx).line); %#ok<AGROW>
        end
        crashDiagnostic = crashIdentifier + " | " + string(ME.message);
        if ~isempty(crashStack)
            crashDiagnostic = crashDiagnostic + " | stack=" + ...
                strjoin(crashStack, " <- ");
        end
        if strlength(firstCrashMsg) == 0
            firstCrashMsg = crashDiagnostic;
        end
        trialCrash(n) = true;
        trialStatus(n) = "CRASH";
        trialCRC(n) = 0;
        trialNotes(n) = crashDiagnostic;
        if ~isempty(log) && frameCrash <= 2
            log.warn("runULPUSCHThroughput frame failed: " + crashDiagnostic);
        end
    end
    localMaybeEmitLiveSnapshot(n);
end

simDur_s = numFrames * slotDur_s;

out.BER = bitErr / max(bitTot, 1);
out.BLER = blockErr / max(numFrames, 1);
% Scheduled PHY throughput counts every transmitted transport block,
% including HARQ retransmissions. Goodput counts only CRC-clean delivery;
% offered throughput counts newly offered traffic and excludes retransmitted
% copies. These three quantities must never be aliases.
out.Throughput_Mbps = (bitTot / max(simDur_s, eps)) / 1e6;
out.Goodput_Mbps = (bitGood / max(simDur_s, eps)) / 1e6;
offeredBits = sum(trialOfferedBits(isfinite(trialOfferedBits)), "omitnan");
out.OfferedThroughput_Mbps = (offeredBits / max(simDur_s, eps)) / 1e6;
out.TotalTTIs = double(numFrames);
out.TotalRetxTTIs = double(numFrames) * double(logical(isRetransmission));
out.HARQ_IR_Overhead = out.TotalRetxTTIs / max(double(numFrames), 1);
out.GoodputDenominator_s = double(simDur_s);
cbErrSum = sum(trialCBErr(isfinite(trialCBErr)), "omitnan");
cbCntSum = sum(trialCBCount(isfinite(trialCBCount)), "omitnan");
if cbCntSum > 0
    out.CodeBlockBLER = cbErrSum / cbCntSum;
end
cbgErrSum = sum(trialCBGErr(isfinite(trialCBGErr)), "omitnan");
cbgCntSum = sum(trialCBGCount(isfinite(trialCBGCount)), "omitnan");
if cbgCntSum > 0
    out.CBGBLER = cbgErrSum / cbgCntSum;
end
out.ComputeLatency_ms = mean(trialComputeLatency, "omitnan");
out.ProcedureDelay_ms = mean(trialProcedureDelay, "omitnan");
out.AirInterfaceTTI_ms = slotDur_s * 1e3;
out.AirInterfaceObservation_ms = mean(trialAirInterfaceObservation, "omitnan");
out.DecodeLatency_ms = mean(trialDecodeLatency, "omitnan");
out.EarlyStopRate = mean(trialEarlyStop, "omitnan");
out.DecoderComplexityUnits = mean(trialDecoderComplexity, "omitnan");
out.NormalizedDecoderComplexity = mean(trialNormDecoderComplexity, "omitnan");
out.AreaEfficiencyProxy = mean(trialAreaEfficiency, "omitnan");
out.Ok = frameCrash == 0 && out.BLER < 1;
out.Notes = "Frames=" + string(numFrames) + ", SNR=" + string(snr_dB) + " dB";
strictTruthRequired = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
if strictTruthRequired && any(~trialStrictReceiverEvidenceOk(1:numFrames))
    out.Ok = false;
    missingEvidence = unique(trialSINRValidationReason(~trialStrictReceiverEvidenceOk(1:numFrames)));
    missingEvidence = missingEvidence(strlength(strtrim(missingEvidence)) > 0);
    if isempty(missingEvidence)
        missingEvidence = "strict_ul_pusch_receiver_evidence_incomplete";
    end
    out.Notes = out.Notes + ", strict UL receiver evidence failed: " + strjoin(missingEvidence, "|");
end
out.ConstellationSamples = localBuildConstellationSlice(numFrames);
out.WaveformPreviewTable = localBuildWaveformPreviewSlice(numFrames);
out.SignalDiagnostic = signalDiagnostic;
out.LinkAdaptationState = laState;
out.StartFrameIndex = double(startFrameIndex);
out.StartSlotIndex = double(startSlotIndex);
out.EndFrameIndex = double(trialFrame(max(1, numFrames)));
out.EndSlotIndex = double(trialSlot(max(1, numFrames)));
out.HARQ = lastHARQ;
if isstruct(out.HARQ)
    out.HARQ.ExpectedHARQACKBits = int8(lastExpectedHARQACKBits(:));
    out.HARQ.DecodedHARQACKBits = int8(lastDecodedHARQACKBits(:));
    finalTrialIndex = max(1, numFrames);
    out.HARQ.HARQACKDecodeStatus = char(string(trialHARQACKDecodeStatus(finalTrialIndex)));
    out.HARQ.HARQACKContentMatch = logical(trialHARQACKContentMatch(finalTrialIndex));
    out.HARQ.ExpectedCSIPart1Bits = int8(lastExpectedCSIPart1Bits(:));
    out.HARQ.ExpectedCSIPart2Bits = int8(lastExpectedCSIPart2Bits(:));
    out.HARQ.DecodedCSIPart1Bits = int8(lastDecodedCSIPart1Bits(:));
    out.HARQ.DecodedCSIPart2Bits = int8(lastDecodedCSIPart2Bits(:));
    out.HARQ.UCIReceiverEvidence=lastUCIReceiverEvidence;
    out.HARQ.CSI1ContentMatch = logical(lastCSI1ContentMatch);
    out.HARQ.CSI2ContentMatch = logical(lastCSI2ContentMatch);
    out.HARQ.UCIOnPUSCHEvidenceSource = char(string( ...
        trialUCIOnPUSCHEvidenceSource(finalTrialIndex)));
end
out.ChannelState = chState;
out.TxWaveformCapture = txWaveformCapture;
out.ObservedREAllocationTable = localCombineObservedREChunks(observedREChunks);
if receivedCompletion
    out.ExecutionStage = "received_shared_stream_completed";
    out.PreparationComputeTime_ms = preparedTransmission.PreparationComputeTime_ms;
out.TransmitWaveformAuthority = "exact_runtime_transmitter_composite_observation";
    out.PUSCHPowerControlState = puschPowerControlState;
    out.PhysicalTiming = preparedTransmission.PhysicalTiming;
end

if frameCrash == numFrames
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnsupported", ...
        "Strict mode forbids skipping PUSCH coverage because every frame crashed: " + firstCrashMsg);
    out.Skipped = false;
    out.Ok = false;
    out.BER = NaN;
    out.BLER = NaN;
    out.Throughput_Mbps = NaN;
    out.Notes = "Failed: every UL waveform trial crashed (" + firstCrashMsg + ")";
end

out.TrialTable = localBuildTrialSlice(numFrames);
if receivedCompletion && ~isempty(out.TrialTable)
    powerFields=sixgr.truth.measureReceivedDataCarrierPower( ...
        preparedTransmission,p.Results.ReceivedContext,out.ReceiveTiming);
    for name=string(fieldnames(powerFields)).'
        out.TrialTable.(name)=repmat(powerFields.(name),height(out.TrialTable),1);
    end
end
strictTruthRequired = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
out.NoiseDomainValidation = sixgr.phy.rx.validateNoiseDomainEvidence( ...
    out.TrialTable, "ThrowOnFailure", strictTruthRequired, "RequireRows", true);

    function localMaybeEmitLiveSnapshot(stopIdx)
        if isempty(liveTrialCallback)
            return;
        end
        stopIdx = max(0, min(numFrames, round(double(stopIdx))));
        if stopIdx < 1
            return;
        end
        if stopIdx ~= numFrames && mod(stopIdx, liveCallbackInterval) ~= 0
            return;
        end
        try
            trialSlice = localBuildTrialSlice(stopIdx);
            constSlice = localBuildConstellationSlice(stopIdx);
            meta = struct( ...
                "Direction", "UL", ...
                "CompletedFrames", double(stopIdx), ...
                "TotalFrames", double(numFrames), ...
                "SNR_dB", double(snr_dB), ...
                "WaveformPreviewTable", localBuildWaveformPreviewSlice(stopIdx));
            feval(liveTrialCallback, trialSlice, constSlice, meta);
        catch ME
            if ~liveCallbackWarned && ~isempty(log)
                log.warn("runULPUSCHThroughput live publish failed: " + string(ME.message));
            end
            liveCallbackWarned = true;
        end
    end

    function constT = localBuildConstellationSlice(stopIdx)
        constT = table();
        stopIdx = max(0, min(numFrames, round(double(stopIdx))));
        if stopIdx < 1
            return;
        end
        chunks = constellationChunks(1:stopIdx);
        chunks = chunks(~cellfun(@isempty, chunks));
        if ~isempty(chunks)
            constT = vertcat(chunks{:});
        end
    end

    function waveT = localBuildWaveformPreviewSlice(stopIdx)
        waveT = table();
        stopIdx = max(0, min(numFrames, round(double(stopIdx))));
        if stopIdx < 1
            return;
        end
        chunks = waveformChunks(1:stopIdx);
        chunks = chunks(~cellfun(@isempty, chunks));
        if ~isempty(chunks)
            waveT = vertcat(chunks{:});
        end
    end

    function T = localBuildTrialSlice(stopIdx)
        stopIdx = max(0, min(numFrames, round(double(stopIdx))));
        if stopIdx < 1
            T = localEmptyTrialTable();
            return;
        end
        idx = 1:stopIdx;
         T = table( ...
            repmat("UL", stopIdx, 1), snr_dB * ones(stopIdx,1), trialSFN(idx), trialUEIndex(idx), trialRNTI(idx), trialBaseStationID(idx), trialSeed(idx), trialFrame(idx), trialSlot(idx), ...
            trialMCS(idx), trialPRB(idx), trialLayers(idx), trialModulation(idx), trialCodeRate(idx), trialTB(idx), trialChan(idx), trialDopp(idx), trialCRC(idx), trialDecIt(idx), ...
            trialEVM(idx), trialNMSE(idx), trialDet(idx), trialSINR(idx), trialCQI(idx), trialCQIDerivedMCS(idx), trialCQIDerivedModulation(idx), trialCQIDerivedCodeRate(idx), ...
            trialLinkAdaptationMode(idx), trialActualMCSSelectionMode(idx), trialSchedulerGrantMCSSelectionMode(idx), trialMCSValueStatus(idx), trialCQITable(idx), trialMCSTable(idx), ...
            trialRI(idx), trialPMI(idx), trialCRI(idx), ...
            trialPMIType(idx), trialPMICodebookMode(idx), trialCSIReportMode(idx), trialCSIPayloadBits(idx), trialCSIPayloadHex(idx), ...
            trialGain(idx), trialNoise(idx), trialDesiredSignalPowerBeforeNoise(idx), trialCompositeSignalPowerBeforeNoise(idx), trialAppliedNoiseSNR(idx), trialNoiseVarianceSource(idx), ...
            trialTiming(idx), trialRank(idx), trialCond(idx), trialRxAnt(idx), trialTxPorts(idx), ...
            trialSelectedBeam(idx), trialBestBeam(idx), trialBeamHit(idx), trialTopKBeamHit(idx), trialBeamCount(idx), ...
            trialSelectedBeamGain(idx), trialBestBeamGain(idx), trialBeamGap(idx), ...
            trialCfgPMI(idx), trialCfgCRI(idx), trialBitErr(idx), trialBitTot(idx), ...
            trialOfferedBits(idx), trialGoodBits(idx), trialThroughput(idx), trialOfferedThr(idx), trialGoodput(idx), ...
            trialComputeLatency(idx), trialProcedureDelay(idx), trialAirInterfaceTTI(idx), trialAirInterfaceObservation(idx), ...
            trialLatency(idx), trialDecodeLatency(idx), trialEarlyStop(idx), trialDecoderComplexity(idx), trialNormDecoderComplexity(idx), trialAreaEfficiency(idx), ...
            trialNumCB(idx), trialCBLen(idx), trialSegOccurred(idx), trialSegPadding(idx), trialTBCRC(idx), trialTBWithCRC(idx), trialBaseGraph(idx), ...
            trialEncodedBits(idx), trialRateMatchedBits(idx), trialRateMatchPuncture(idx), trialRateMatchRepetition(idx), ...
            trialCBErr(idx), trialCBCount(idx), trialCBBLER(idx), trialCBGErr(idx), trialCBGCount(idx), trialCBGBLER(idx), ...
            trialPAPR(idx), trialClipEvents(idx), trialSymErr(idx), trialSymTot(idx), trialSER(idx), trialResidualInterference(idx), ...
            trialLLRMeanAbs(idx), trialLLRStdAbs(idx), trialLLRImbalance(idx), trialMapSens(idx), ...
            trialShapeLoss(idx), trialDMLatency(idx), trialHighOrderRobustness(idx), trialDetectorComplexity(idx), ...
            trialDataRECount(idx), trialDMRSRECount(idx), trialPTRSRECount(idx), trialRSOverhead(idx), ...
            trialInjectedCFO(idx), trialEstimatedCFOPre(idx), trialResidualCFOPost(idx), ...
            trialEstimatedCFO(idx), trialTrueCFO(idx), trialCFOError(idx), ...
            trialInjectedTiming(idx), trialEstimatedTimingPre(idx), trialResidualTimingPost(idx), ...
            trialTrueTiming(idx), trialTimingError(idx), ...
            trialIQImbalanceConfigured(idx), trialIQImbalanceApplied(idx), trialIQImbalanceModel(idx), ...
            trialConfiguredIQGainImbalance(idx), trialConfiguredIQPhaseImbalance(idx), ...
            trialIQImbalanceMirrorPowerRatio(idx), trialIQImbalanceImageRejection(idx), ...
            trialIQImbalanceIQPowerRatio(idx), trialIQImbalanceIQCorrelation(idx), ...
            trialIQImbalanceEstimatedAlphaAbs(idx), trialIQImbalanceEstimatedBetaAbs(idx), ...
            trialIQImbalanceMeasurementSource(idx), trialIQImbalanceMeasurementStatus(idx), ...
            trialEstDoppler(idx), trialDopplerErr(idx), trialPhaseTrackErr(idx), trialQCL(idx), ...
            trialAgingLoss(idx), trialInterpLoss(idx), trialMismatch(idx), ...
            trialStatus(idx), trialCrash(idx), ...
            trialLAApplied(idx), trialLAScheduled(idx), trialNotes(idx), ...
            'VariableNames', {'Direction','SNR_dB','SFN','UEIndex','RNTI','BaseStationID','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
            'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
            'MeasuredSINR_dB','WidebandCQI','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
            'LinkAdaptationMode','ActualMCSSelectionMode','SchedulerGrantMCSSelectionMode','MCSValueStatus','CQITable','MCSTable','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
            'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','ChannelGain_dB','NoiseVariance', ...
            'DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
            'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
            'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
            'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
            'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
            'OfferedBits','GoodBits','Throughput_Mbps','OfferedThroughput_Mbps','Goodput_Mbps', ...
            'ComputeLatency_ms','ProcedureDelay_ms','AirInterfaceTTI_ms','AirInterfaceObservation_ms', ...
            'Latency_ms','DecodeLatency_ms','EarlyStopRate','DecoderComplexityUnits','NormalizedDecoderComplexity','AreaEfficiencyProxy', ...
            'NumCodeBlocks','CodeBlockLength_bits','SegmentationOccurred','SegmentationPaddingBits','TBCRCLength_bits','TBLengthWithCRC_bits','BaseGraph', ...
            'EncodedBits','RateMatchedBits','RateMatchPunctureBits','RateMatchRepetitionBits', ...
            'CodeBlockErrors','CodeBlockCount','CodeBlockBLER','CBGErrors','CBGCount','CBGBLER', ...
            'PAPR_dB','PeakClippingEvents','SymbolErrors','SymbolsCompared','SymbolErrorRate','ResidualInterferencePower_dB', ...
            'LLRMeanAbs','LLRStdAbs','LLRImbalance','ModulationMappingSensitivity', ...
            'ShapingRateLoss','DistributionMatchingLatency_ms','HighOrderRobustness','DetectorComplexityUnits_Modulation', ...
            'DataRECount','DMRSRECount','PTRSRECount','RSOverheadFraction', ...
            'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz', ...
            'EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
            'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples', ...
            'TrueTimingOffset_samples','TimingError_samples', ...
            'IQImbalanceConfigured','IQImbalanceApplied','IQImbalanceModel', ...
            'ConfiguredIQGainImbalance_dB','ConfiguredIQPhaseImbalance_deg', ...
            'IQImbalanceMirrorPowerRatio_dB','IQImbalanceImageRejection_dB', ...
            'IQImbalanceIQPowerRatio_dB','IQImbalanceIQCorrelation', ...
            'IQImbalanceEstimatedAlphaAbs','IQImbalanceEstimatedBetaAbs', ...
            'IQImbalanceMeasurementSource','IQImbalanceMeasurementStatus', ...
            'EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
            'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB', ...
            'Status','Crash', ...
             'LinkAdaptationApplied','LinkAdaptationScheduled','Notes'});
        T.ComputeLatencySource = trialComputeLatencySource(idx);
        T.QCLMeasurementStatus = repmat("not_measured_requires_QCL_TCI_binding_evidence",stopIdx,1);
        T.EstimatedChannelReferenceCorrelationMagnitude = trialChannelReferenceCorrelation(idx);
        T.SymbolDecisionStatus = trialSymbolDecisionStatus(idx);
        T.RuntimeAbsoluteSlotIndex0 = trialRuntimeAbsoluteSlot0(idx);
        T.CarrierNSlot = trialCarrierNSlot(idx);
        T.CarrierNFrame = trialCarrierNFrame(idx);
        T.LinkAdaptationFeedbackDelaySlots = trialLAFeedbackDelaySlots(idx);
        T.LinkAdaptationFeedbackDelaySource = trialLAFeedbackDelaySource(idx);
        T.LinkAdaptationFeedbackDelayStatus = trialLAFeedbackDelayStatus(idx);
        T.LinkAdaptationAppliedFeedbackSourceSlot = trialLAAppliedSourceSlot(idx);
        T.LinkAdaptationAppliedFeedbackAgeSlots = trialLAAppliedAgeSlots(idx);
        T.LinkAdaptationScheduledFeedbackSourceSlot = trialLAScheduledSourceSlot(idx);
        T.LinkAdaptationScheduledApplySlot = trialLAScheduledApplySlot(idx);
        T.AppliedLinkAdaptationResolvedCQI = trialLAAppliedDecisionCQI(idx);
        T.AppliedLinkAdaptationCQIBasedMCS = trialLAAppliedDecisionCQIBasedMCS(idx);
        T.AppliedLinkAdaptationMCS = trialLAAppliedDecisionMCS(idx);
        T.AppliedLinkAdaptationOLLADeltaDb = trialLAAppliedDecisionOLLADeltaDb(idx);
        T.AppliedLinkAdaptationOLLAUpdateCount = trialLAAppliedDecisionOLLAUpdateCount(idx);
        T.AppliedLinkAdaptationOLLAFeedbackEligible = trialLAAppliedDecisionOLLAFeedbackEligible(idx);
        T.ScheduledLinkAdaptationResolvedCQI = trialLAScheduledDecisionCQI(idx);
        T.ScheduledLinkAdaptationMCS = trialLAScheduledDecisionMCS(idx);
        T.ScheduledLinkAdaptationOLLADeltaDb = trialLAScheduledDecisionOLLADeltaDb(idx);
        T.ScheduledLinkAdaptationOLLAUpdateCount = trialLAScheduledDecisionOLLAUpdateCount(idx);
        T.ScheduledLinkAdaptationOLLAFeedbackEligible = trialLAScheduledDecisionOLLAFeedbackEligible(idx);
        T.ScheduledLinkAdaptationOLLAFeedbackExclusionReason = trialLAScheduledDecisionOLLAFeedbackExclusionReason(idx);
        T.DecodeLatencySource = trialDecodeLatencySource(idx);
        T.ReceiverPipelineLatency_ms = trialReceiverPipelineLatency(idx);
        T.ReceiverPipelineLatencySource = trialReceiverPipelineLatencySource(idx);
        T.ChannelEstimationLatency_ms = trialChannelEstimationLatency(idx);
        T.EqualizationLatency_ms = trialEqualizationLatency(idx);
        T.ReceiverStageLatencySource = trialReceiverStageLatencySource(idx);
        T.ExecutionProfile = repmat(executionContract.Profile, stopIdx, 1);
        T.ExecutionTaxonomy = repmat(executionContract.Taxonomy, stopIdx, 1);
        T.ExecutionBackend = repmat(executionContract.Backend, stopIdx, 1);
        T.ApproximationMode = repmat("none", stopIdx, 1);
        T.CalibrationProvenance = repmat( ...
            executionContract.CalibrationProvenance, stopIdx, 1);
        T.StrictSchedulingOwnership = repmat( ...
            executionContract.Profile == "scheduler_truth", stopIdx, 1);
        T.DataRECountPerLayer = trialDataRECountPerLayer(idx);
        T.TotalDataRECount = trialTotalDataRECount(idx);
        T.TBSInputModulation = trialModulation(idx);
        T.TBSInputNumLayers = trialLayers(idx);
        T.TBSInputNPRB = trialPRB(idx);
        T.TBSInputNREPerPRB = trialTBSInputNREPerPRB(idx);
        T.TBSInputTargetCodeRate = trialCodeRate(idx);
        T.TBSInputXOverhead = trialTBSInputXOverhead(idx);
        T.TBSInputSource = trialTBSInputSource(idx);
        T.ReplaySampleNoiseVariance = trialReplaySampleNoiseVariance(idx);
        T.ReplayGridNoiseVariance = trialReplayGridNoiseVariance(idx);
        T.ReceiverInputSampleNoiseVariance = trialReceiverInputSampleNoiseVariance(idx);
        T.PreEqualizationNoiseVariance = trialPreEqualizationNoiseVariance(idx);
        T.PostEqualizationNoiseVariance = trialPostEqualizationNoiseVariance(idx);
        T.SampleToGridNoiseVarianceGain = trialSampleToGridNoiseVarianceGain(idx);
        T.ReplaySampleNoiseVarianceDomain = trialReplaySampleNoiseVarianceDomain(idx);
        T.ReplayGridNoiseVarianceDomain = trialReplayGridNoiseVarianceDomain(idx);
        T.ReceiverInputSampleNoiseVarianceDomain = trialReceiverInputSampleNoiseVarianceDomain(idx);
        T.DesiredSignalPowerBeforeNoiseDomain = trialDesiredSignalPowerDomain(idx);
        T.CompositeSignalPowerBeforeNoiseDomain = trialCompositeSignalPowerDomain(idx);
        T.SNRReferencePlane = trialSNRReferencePlane(idx);
        T.AppliedNoiseSNRSource = trialAppliedNoiseSNRSource(idx);
        T.RequestedAWGNReferenceSNR_dB = trialRequestedAWGNReferenceSNR(idx);
        T.SignalEnergyPerOccupiedRE = trialSignalEnergyPerOccupiedRE(idx);
        T.PreEqualizationNoiseVarianceDomain = repmat("resource_grid_pre_equalization", stopIdx, 1);
        T.PostEqualizationNoiseVarianceDomain = repmat("unit_constellation_layer_symbol_post_equalization", stopIdx, 1);
        T.LLRNoiseVarianceDomain = repmat("unit_constellation_soft_demapper_input", stopIdx, 1);
        T.NoiseVarianceUnit = repmat("normalized_complex_power", stopIdx, 1);
        T.NoiseVarianceNormalization = repmat("native_domain_power_per_complex_value", stopIdx, 1);
        T.NoiseVarianceAliasOf = repmat("PreEqualizationNoiseVariance", stopIdx, 1);
        T.ReplaySampleNoiseVarianceSource = trialReplaySampleNoiseVarianceSource(idx);
        T.ReplayGridNoiseVarianceSource = trialReplayGridNoiseVarianceSource(idx);
        T.ReceiverInputSampleNoiseVarianceSource = trialReceiverInputSampleNoiseVarianceSource(idx);
        T.PreEqualizationNoiseVarianceSource = trialPreEqualizationNoiseVarianceSource(idx);
        T.PostEqualizationNoiseVarianceSource = trialPostEqualizationNoiseVarianceSource(idx);
        T.LLRNoiseVarianceSource = trialLLRNoiseVarianceSource(idx);
        T.ModulationOrderQm = trialModulationOrderQm(idx);
        T.ComputedE_TS38212 = trialComputedE_TS38212(idx);
        T.RateMatchedBitsDelta_TS38212 = trialRateMatchedBits(idx) - trialComputedE_TS38212(idx);
        T.ConfiguredSNR_dB = trialConfiguredSNR(idx);
        % UL-SCH transport-block CRC is applicable whenever the real
        % decoder produced a usable TB decision.  Keep unavailable/crashed
        % attempts as not applicable instead of defaulting every data row
        % to false in downstream lifecycle normalization.
        T.CRCApplicable = logical(trialULSCHDecodeAttempted(idx) & ...
            trialULSCHDecodeAvailable(idx) & isfinite(trialCRC(idx)));
        T.TxWaveformColumns = trialTxWaveformColumns(idx);
        T.PhysicalTxAntennas = trialPhysicalTxAntennas(idx);
        T.RxWaveformBranches = trialRxWaveformBranches(idx);
        T.PhysicalRxAntennas = trialPhysicalRxAntennas(idx);
        T.TxWaveformDomain = trialTxWaveformDomain(idx);
        T.HybridElementDomainApplied = trialHybridElementDomainApplied(idx);
        configuredLayers = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN), ...
            sixgr.util.structGet(cfg, "phy.pusch.numLayers", NaN));
        if isfinite(configuredLayers)
            configuredLayers = max(1, round(double(configuredLayers)));
        end
        configuredTxAnt = localConfiguredULAntennaCount(cfg, "tx", ...
            localFirstFiniteScalar(trialTxPorts(idx), 1));
        configuredRxAnt = localConfiguredULAntennaCount(cfg, "rx", ...
            localFirstFiniteScalar(trialRxAnt(idx), 1));
        T.ConfiguredLayers = repmat(configuredLayers, stopIdx, 1);
        T.ConfiguredTxAntennas = repmat(configuredTxAnt, stopIdx, 1);
        T.ConfiguredRxAntennas = repmat(configuredRxAnt, stopIdx, 1);
        T.RV = trialRV(idx);
        T.HARQProcess = trialHARQProcess(idx);
        T.HARQProcessId = trialHARQProcess(idx);
        T.HarqID = trialHARQProcess(idx);
        T.HARQRound = trialHARQRound(idx);
        T.NDI = trialHARQNDI(idx);
        T.HARQNDI = trialHARQNDI(idx);
        T.IsRetransmission = trialHARQIsRetransmission(idx);
        T.HARQIsRetransmission = trialHARQIsRetransmission(idx);
        T.HARQRV = trialRV(idx);
        T.NDIEpoch = trialHARQNDIEpoch(idx);
        T.TBId = trialHARQTBId(idx);
        T.OriginalTBSBits = trialOriginalTBSBits(idx);
        T.CurrentTBSBits = trialCurrentTBSBits(idx);
        T.OriginalRateMatchedBits = trialOriginalRateMatchedBits(idx);
        T.CurrentRateMatchedBits = trialCurrentRateMatchedBits(idx);
        T.EffectiveInitialCodeRate = trialEffectiveInitialCodeRate(idx);
        T.EffectiveCurrentTxCodeRate = trialEffectiveCurrentTxCodeRate(idx);
        T.ShortIRRetx = trialShortIRRetx(idx);
        T.CodeBlockLayoutHash = trialCodeBlockLayoutHash(idx);
        T.HARQContextHash = trialHARQContextHash(idx);
        T.HARQContextStatus = trialHARQContextStatus(idx);
        T.AllocatedPRBCount = trialPRB(idx);
        T.PRBStart = trialPRBStart(idx);
        T.PRBCount = trialPRB(idx);
        T.SymbolStart = trialSymbolStart(idx);
        T.NumSymbols = trialNumSymbols(idx);
        T.AppliedAWGNSNR_dB = trialAppliedAWGNSNR(idx);
        T.InjectedCarrierPhaseOffset_deg = trialCarrierPhaseOffsetDeg(idx);
        T.InjectedCarrierPhaseOffset_rad = trialCarrierPhaseOffsetRad(idx);
        T.CarrierPhaseOffsetApplied = trialCarrierPhaseOffsetApplied(idx);
        T.CarrierPhaseOffsetSource = trialCarrierPhaseOffsetSource(idx);
        T.CarrierPhaseOffsetExecutionStatus = trialCarrierPhaseOffsetStatus(idx);
        T.NoiseVarStatus = trialNoiseVarStatus(idx);
        T.NoiseVarSource = trialNoiseVarSource(idx);
        T.NoiseVarReason = trialNoiseVarReason(idx);
        T.NoiseVarStrictFailure = trialNoiseVarStrictFailure(idx);
        T.UCIOnPUSCHApplied = trialUCIOnPUSCHApplied(idx);
        T.UCIOnPUSCHSource = trialUCIOnPUSCHSource(idx);
        T.HARQACKBitCount = trialHARQACKBitCount(idx);
        T.ExpectedHARQACKBits = trialExpectedHARQACKBits(idx);
        T.DecodedHARQACKBits = trialDecodedHARQACKBits(idx);
        T.CSI1BitCount = trialCSI1BitCount(idx);
        T.CSI2BitCount = trialCSI2BitCount(idx);
        T.ExpectedCSIPart1Bits = trialExpectedCSIPart1Bits(idx);
        T.ExpectedCSIPart2Bits = trialExpectedCSIPart2Bits(idx);
        T.DecodedCSIPart1Bits = trialDecodedCSIPart1Bits(idx);
        T.DecodedCSIPart2Bits = trialDecodedCSIPart2Bits(idx);
        T.UCIReceiverEvidenceJSON = trialUCIReceiverEvidenceJSON(idx);
        T.CSI1ContentMatch = trialCSI1ContentMatch(idx);
        T.CSI2ContentMatch = trialCSI2ContentMatch(idx);
        T.UCIOnPUSCHCSIReportIdentity = repmat(string(sixgr.util.structGet( ...
            grantSnapshotOverride, "UCIOnPUSCHCSIReportIdentity", "")), ...
            height(T), 1);
        T.UCIOnPUSCHFeedbackGrantIds = repmat(string(sixgr.util.structGet( ...
            grantSnapshotOverride, "UCIOnPUSCHFeedbackGrantIds", "")), height(T), 1);
        T.UCIOnPUSCHFeedbackSourceSlots = repmat(localFormatNumericVector( ...
            sixgr.util.structGet(grantSnapshotOverride, ...
            "UCIOnPUSCHFeedbackSourceSlots", [])), height(T), 1);
        T.UCIOnPUSCHFeedbackHARQIds = repmat(localFormatNumericVector( ...
            sixgr.util.structGet(grantSnapshotOverride, ...
            "UCIOnPUSCHFeedbackHARQIds", [])), height(T), 1);
        T.UCIOnPUSCHFeedbackBitCount = repmat(double(sixgr.util.structGet( ...
            grantSnapshotOverride, "UCIOnPUSCHFeedbackBitCount", 0)), height(T), 1);
        % This field is receiver evidence, not a reservation-time grant
        % annotation. Export the source emitted only after the actual PUSCH
        % waveform has been demultiplexed and decoded.
        T.UCIOnPUSCHEvidenceSource = trialUCIOnPUSCHEvidenceSource(idx);
        T.HARQACKContentMatch = trialHARQACKContentMatch(idx);
        T.HARQACKDecodeStatus = trialHARQACKDecodeStatus(idx);
        T.HARQACKDecodeReason = trialHARQACKDecodeReason(idx);
        T.EqualizerType = trialEqualizerType(idx);
        T.EqualizerRequestedType = trialEqualizerRequestedType(idx);
        T.EqualizerEngine = trialEqualizerEngine(idx);
        T.EqualizerCovarianceFactorizationCount = ...
            trialEqualizerCovarianceFactorizationCount(idx);
        T.InterferenceCovarianceAvailable = trialInterferenceCovarianceAvailable(idx);
        T.InterferenceCovarianceSource = trialInterferenceCovarianceSource(idx);
        T.InterferenceCovarianceStatus = trialInterferenceCovarianceStatus(idx);
        T.MUMIMOReceiveCombinerApplied = trialMUMIMOReceiveCombinerApplied(idx);
        T.MUMIMOReceiveCombinerStatus = trialMUMIMOReceiveCombinerStatus(idx);
        T.MUMIMOReceiveCombinerSource = trialMUMIMOReceiveCombinerSource(idx);
        T.MUMIMOReceiveCombinerInputBranches = trialMUMIMOReceiveCombinerInputBranches(idx);
        T.MUMIMOReceiveCombinerOutputBranches = trialMUMIMOReceiveCombinerOutputBranches(idx);
        T.MUMIMOReceiveCombinerMatrixSHA256 = trialMUMIMOReceiveCombinerMatrixSHA256(idx);
        T.MUMIMOReceiveCombinerInterferenceProjected = trialMUMIMOReceiveCombinerInterferenceProjected(idx);
        T.MUMIMOReceiveCombinerFullObservationPreserved = trialMUMIMOReceiveCombinerFullObservationPreserved(idx);
        T.MUMIMOReceiveCombinerIdentityResidual = trialMUMIMOReceiveCombinerIdentityResidual(idx);
        T.MUMIMOReceiverAlgorithmApplied = trialMUMIMOReceiverAlgorithmApplied(idx);
        T.ReceiverUsable = trialReceiverUsable(idx);
        T.DecodeAttempted = trialDecodeAttempted(idx);
        T.DecodeUsable = trialDecodeUsable(idx);
        T.FailureReason = trialFailureReason(idx);
        T.StrictReceiverEvidenceOk = trialStrictReceiverEvidenceOk(idx);
        T.StrictOk = trialStrictOk(idx);
        T.TruthStatus = trialTruthStatus(idx);
        T.ChannelEstimateAttempted = trialChannelEstimateAttempted(idx);
        T.ChannelEstimateAvailable = trialChannelEstimateAvailable(idx);
        T.ChannelEstimateSource = trialChannelEstimateSource(idx);
        T.ResourceExtractionAttempted = trialResourceExtractionAttempted(idx);
        T.ResourceExtractionAvailable = trialResourceExtractionAvailable(idx);
        T.EqualizationAttempted = trialEqualizationAttempted(idx);
        T.EqualizationAvailable = trialEqualizationAvailable(idx);
        T.ULSCHDecodeAttempted = trialULSCHDecodeAttempted(idx);
        T.ULSCHDecodeAvailable = trialULSCHDecodeAvailable(idx);
        T.LLRAvailable = trialLLRAvailable(idx);
        T.LLRFinite = trialLLRFinite(idx);
        T.LLRScaleSource = trialLLRScaleSource(idx);
        T.LLRNoiseVariance = trialLLRNoiseVariance(idx);
        T.ReceiverHestSINR_dB = trialReceiverHestSINR(idx);
        T.ReceiverHestSINRApplicable = logical(isfinite(trialReceiverHestSINR(idx)) & ...
            trialChannelEstimateAvailable(idx) & trialDMRSRECount(idx) > 0);
        T.ReceiverHestSINRSource = trialReceiverHestSINRSource(idx);
        T.ReceiverHestSINRValueRole = trialReceiverHestSINRValueRole(idx);
        T.ReceiverHestSINRValueStatus = trialReceiverHestSINRValueStatus(idx);
        T.ReceiverHestSINRNAReason = trialReceiverHestSINRNAReason(idx);
        T.PostEqSINR_dB = trialPostEqSINR(idx);
        T.PostEqSINRWidebanddB = trialPostEqSINR(idx);
        T.PostEqSINRSource = trialPostEqSINRSource(idx);
        T.PostEqSINRValueRole = trialPostEqSINRValueRole(idx);
        T.PostEqSINRValueStatus = trialPostEqSINRValueStatus(idx);
        T.PostEqSINRNAReason = trialPostEqSINRNAReason(idx);
        T.PostEqSINRPerLayer_dB = trialPostEqSINRPerLayer(idx);
        T.PostEqSINRRawEqualizer_dB = trialPostEqSINRRawEqualizer(idx);
        T.PostEqSINRDMRSResidualBoundApplied = trialPostEqSINRDMRSResidualBoundApplied(idx);
        T.PostEqSINRDMRSResidual_dB = trialPostEqSINRDMRSResidual(idx);
        T.PostEqDMRSResidualNoiseVar = trialPostEqDMRSResidualNoiseVar(idx);
        T.PostEqDMRSResidualSource = trialPostEqDMRSResidualSource(idx);
        T.PostEqDecisionResidual_dB = trialPostEqDecisionResidual(idx);
        T.PostEqDecisionResidualNoiseVar = trialPostEqDecisionResidualNoiseVar(idx);
        T.PostEqDecisionResidualSource = trialPostEqDecisionResidualSource(idx);
        T.PostEqSINRAvailable = trialPostEqSINRAvailable(idx);
        T.PostEqSINRReceiverDerived = trialPostEqSINRReceiverDerived(idx);
        T.SINRValidationStatus = trialSINRValidationStatus(idx);
        T.SINRValidationReason = trialSINRValidationReason(idx);
        T.SINRComputationMethod = trialSINRComputationMethod(idx);
        T.ConfiguredSNRLikeSourceRejected = trialConfiguredSNRLikeSourceRejected(idx);
        T.CQISource = trialCQISource(idx);
        T.SchedulerCQIRawCQI = trialSchedulerCQIRawCQI(idx);
        T.SchedulerAdjustedSINR_dB = trialSchedulerAdjustedSINR(idx);
        T.SchedulerSINRBackoff_dB = trialSchedulerSINRBackoff(idx);
        T.SchedulerCQISource = trialSchedulerCQISource(idx);
        T.OuterLoopEnabled = trialOuterLoopEnabled(idx);
        T.OuterLoopApplied = trialOuterLoopAppliedFromGrant(idx);
        T.OLLADeltaDb = trialOLLADeltaDb(idx);
        T.OLLADeltaMCS = trialOLLADeltaMCS(idx);
        T.OLLAAdjustedMCSBeforeCQICeiling = trialOLLAAdjustedMCSBeforeCQICeiling(idx);
        T.OLLABaseRequiredSINR_dB = trialOLLABaseRequiredSINR(idx);
        T.OLLATargetRequiredSINR_dB = trialOLLATargetRequiredSINR(idx);
        T.OLLAThresholdSource = trialOLLAThresholdSource(idx);
        T.OLLAUpdateCount = trialOLLAUpdateCount(idx);
        T.OLLAStateAuthority = trialOLLAStateAuthority(idx);
        T.OLLAState = trialOLLAState(idx);
        T.RankSelectionPolicy = trialRankSelectionPolicy(idx);
        T.RankSelectionSource = trialRankSelectionSource(idx);
        T.RankDecisionReason = trialRankDecisionReason(idx);
        T.RankDowngradeApplied = trialRankDowngradeApplied(idx);
        T.MaxSupportedLayers = trialMaxSupportedLayers(idx);
        T.DecoderTruthProxySINR_dB = trialDecoderTruthProxySINR(idx);
        T.DecoderTruthProxySINRSource = trialDecoderTruthProxySINRSource(idx);
        T.SINRValueRole = trialSINRValueRole(idx);
        T.SINRSource = trialSINRSource(idx);
        T.MeasuredTrialSINR_dB = trialMeasuredTrialSINR(idx);
        T.MeasuredTrialSINRSource = trialMeasuredSINRSource(idx);
        T.MeasuredTrialSINRValueRole = trialMeasuredTrialSINRValueRole(idx);
        T.MeasuredTrialSINRValueStatus = trialMeasuredTrialSINRValueStatus(idx);
        T.MeasuredTrialSINRNAReason = trialMeasuredTrialSINRNAReason(idx);
        T.EVMProxySINR_dB = trialEVMProxySINR(idx);
        T.EVMProxySINRSource = trialEVMProxySINRSource(idx);
        T.EVMProxySINRValueRole = trialEVMProxySINRValueRole(idx);
        T.EVMProxySINRValueStatus = trialEVMProxySINRValueStatus(idx);
        T.EVMProxySINRNAReason = trialEVMProxySINRNAReason(idx);
        T.AirInterfaceObservation_ms = trialAirInterfaceObservation(idx);
        T.LargeScaleSINR_dB = trialLargeScaleSINR(idx);
        T.LargeScaleSINRSource = trialLargeScaleSINRSource(idx);
        T.ServingRSRP_dBm = trialServingRSRP(idx);
        T.ServingRSRPSource = trialServingRSRPSource(idx);
        T.ULNormalizedReferencePower_dB = trialCSIRSRP(idx);
        T.ULNormalizedReferencePowerSource = trialCSIRSRPSource(idx);
        T.ULNormalizedWindowRSSI_dB = trialCSIRSSI(idx);
        T.ULNormalizedWindowRSSISource = trialCSIRSSISource(idx);
        T.ULNormalizedWindowPowerRatio_dB = trialCSIRSRQ(idx);
        T.ULNormalizedWindowPowerRatioSource = trialCSIRSRQSource(idx);
        T.ULNormalizedPowerEvidenceJSON=trialULNormalizedPowerEvidence(idx);
        T.BeamScoreVector_dB = trialBeamScoreVector(idx);
        T.TopBeamIndexSet = trialTopBeamIndexSet(idx);
        T.TopBeamGainSet_dB = trialTopBeamGainSet(idx);
        T.BeamScoreSource = trialBeamScoreSource(idx);
        T.PMISource = trialPMISource(idx);
        T.ULSpatialMeasurementEvidenceJSON=trialULSpatialMeasurementEvidence(idx);
        T.AppliedLargeScaleGain_dB = trialAppliedLargeScaleGain(idx);
        T.AppliedLargeScaleLoss_dB = trialAppliedLargeScaleLoss(idx);
        T.AppliedBasePathloss_dB = trialAppliedBasePathloss(idx);
        T.AppliedPathloss_dB = trialAppliedPathloss(idx);
        T.PUSCHPowerControlEnabled = trialPUSCHPowerControlEnabled(idx);
        T.PUSCHPowerControlStatus = trialPUSCHPowerControlStatus(idx);
        T.PUSCHTxPower_dBm = trialPUSCHTxPower(idx);
        T.PUSCHRequestedPower_dBm = trialPUSCHRequestedPower(idx);
        T.PUSCHPcmax_dBm = trialPUSCHPcmax(idx);
        T.PUSCHPowerHeadroom_dB = trialPUSCHPowerHeadroom(idx);
        T.PUSCHMeasuredWaveformPower_dBm = trialPUSCHMeasuredWaveformPower(idx);
        T.PUSCHPowerClosureError_dB = trialPUSCHPowerClosureError(idx);
        T.PUSCHPowerClipped = trialPUSCHPowerClipped(idx);
        T.PUSCHPathlossReferenceRS = trialPUSCHPathlossReferenceRS(idx);
        T.PUSCHPowerControlSource = trialPUSCHPowerControlSource(idx);
        T.PUSCHPowerAmplitudeScale = trialPUSCHPowerScale(idx);
        T.PUSCHPowerControlPathloss_dB = trialPUSCHPowerControlPathloss(idx);
        T.AppliedShadowFading_dB = trialAppliedShadow(idx);
        T.AppliedO2I_dB = trialAppliedO2I(idx);
        T.AppliedLargeScaleGainSource = trialAppliedLargeScaleGainSource(idx);
        T.ChannelComplianceMode = trialChannelComplianceMode(idx);
        T.PathlossModelSource = trialPathlossModelSource(idx);
        T.PathlossComplianceStatus = trialPathlossComplianceStatus(idx);
        T.FallbackUsedForPathloss = trialFallbackUsedForPathloss(idx);
        T.O2IModelSource = trialO2IModelSource(idx);
        T.O2IComplianceStatus = trialO2IComplianceStatus(idx);
        T.O2IComplianceReason = trialO2IComplianceReason(idx);
        T.LOSProbabilitySource = trialLOSProbabilitySource(idx);
        T.LOSComplianceStatus = trialLOSComplianceStatus(idx);
        T.LOSComplianceReason = trialLOSComplianceReason(idx);
        T.TimingEstimateUsed = trialTimingEstimateUsed(idx);
        T.UseIdealTimingSync = trialUseIdealTimingSync(idx);
        T.AppliedTimingCorrection_samples = trialAppliedTimingCorrection(idx);
        T.TimingEstimateApplicationPolicy = trialTimingEstimateApplicationPolicy(idx);
        T.TimingEstimateStatus = trialTimingEstimateStatus(idx);
        T.TimingEstimateWasClipped = trialTimingEstimateWasClipped(idx);
        T.InterferenceMode = trialInterferenceMode(idx);
        T.InterferenceContributorCount = trialInterferenceContributorCount(idx);
        T.InterferenceAggregatedRxPower_dBm = trialInterferenceAggregatedRxPower(idx);
        T.InterferencePowerSource = trialInterferencePowerSource(idx);
        T.FullInterfererChannelTruthUsed = trialFullInterfererChannelTruthUsed(idx);
        T.PBCHGatingActive = trialPBCHGatingActive(idx);
        T.PRACHGatingActive = trialPRACHGatingActive(idx);
        T.PDCCHGatingActive = trialPDCCHGatingActive(idx);
        T.SRSGatingActive = trialSRSGatingActive(idx);
        T.ControlEligible = trialControlEligible(idx);
        T.ControlDecodeOk = trialControlDecodeOk(idx);
        T.DCICrcPass = trialDCICrcPass(idx);
        T.PDCCHPayloadMatch = trialPDCCHPayloadMatch(idx);
        T.PDCCHCausalGrantDecodeOk = trialPDCCHCausalGrantDecodeOk(idx);
        T.PDCCHMissedDetection = trialPDCCHMissedDetection(idx);
        T.PDCCHFalseAlarm = trialPDCCHFalseAlarm(idx);
        T.GrantValid = trialGrantValid(idx);
        T.NegativeExpectedOk = trialNegativeExpectedOk(idx);
        T.PDCCHBlindSearchEnabled = trialPDCCHBlindSearchEnabled(idx);
        T.PDCCHREGMappingAvailable = trialPDCCHREGMappingAvailable(idx);
        T.PDCCHGrantBindingRequired = trialPDCCHGrantBindingRequired(idx);
        T.PDCCHGrantBindingOk = trialPDCCHGrantBindingOk(idx);
        T.PDCCHGrantBindingStatus = trialPDCCHGrantBindingStatus(idx);
        T.PDCCHGrantBindingFailureCode = trialPDCCHGrantBindingFailureCode(idx);
        T.PDCCHGrantDCIId = trialPDCCHGrantDCIId(idx);
        T.PDCCHGrantDCIFieldsHash = trialPDCCHGrantDCIFieldsHash(idx);
        T.PDCCHGrantFieldsHash = trialPDCCHGrantFieldsHash(idx);
        T.PDCCHGrantSearchSpaceId = trialPDCCHGrantSearchSpaceId(idx);
        T.PDCCHGrantCORESETId = trialPDCCHGrantCORESETId(idx);
        T.PDCCHGrantAggregationLevel = trialPDCCHGrantAggregationLevel(idx);
        T.PDCCHGrantCandidateIndex = trialPDCCHGrantCandidateIndex(idx);
        T.PDCCHGrantDCIFormat = trialPDCCHGrantDCIFormat(idx);
        T.GrantControlState = trialGrantControlState(idx);
        T.PDCCHControlFailureReason = trialPDCCHControlFailureReason(idx);
        T.PDCCHControlEvidenceSource = trialPDCCHControlEvidenceSource(idx);
        T.ControlDecodeSource = trialControlDecodeSource(idx);
        T.CellAcquisitionState = trialCellAcquisitionState(idx);
        T.AccessState = trialAccessState(idx);
        T.SRSValidityState = trialSRSValidityState(idx);
        T.CSIValidityState = trialCSIValidityState(idx);
        T.SRSValid = trialSRSValid(idx);
        T.SRSAgeSlots = trialSRSAgeSlots(idx);
        T.TRSGatingActive = trialTRSGatingActive(idx);
        T.TRSValidityState = trialTRSValidityState(idx);
        T.TrackingEligibility = trialTrackingEligibility(idx);
        T.TRSAgeSlots = trialTRSAgeSlots(idx);
        T.LastSuccessfulTRSSlot = trialLastSuccessfulTRSSlot(idx);
        T.LastEstimatedTRSDopplerHz = trialLastEstimatedTRSDopplerHz(idx);
        T.TRSStateSource = trialTRSStateSource(idx);
        T.TRSRuntimeConsumer = trialTRSRuntimeConsumer(idx);
        T.TRSInfluencedDecision = trialTRSInfluencedDecision(idx);
        T.TRSInfluenceDefinition = trialTRSInfluenceDefinition(idx);
        T.TRSReceiverIntegrationStatus = trialTRSReceiverIntegrationStatus(idx);
        T.TRSReceiverIntegrationBlocker = trialTRSReceiverIntegrationBlocker(idx);
        T.GrantContextId = trialGrantContextId(idx);
        T.GrantWorkerSafe = trialGrantWorkerSafe(idx);
        T.GrantSharedStateCommitMode = trialGrantSharedStateCommitMode(idx);
        T.ConfiguredBeamSelectionStrategy = trialConfiguredBeamSelectionStrategy(idx);
        T.PrecoderSource = trialPrecoderSource(idx);
        T.PrecodingMode = trialPrecodingMode(idx);
        T.PrecodingApplicationStage = trialPrecodingApplicationStage(idx);
        T.PrecodingActive = trialPrecodingActive(idx);
        T.ExplicitBeamWeightsApplied = trialExplicitBeamWeightsApplied(idx);
        T.TransformPrecodingApplied = trialTransformPrecodingApplied(idx);
        T.FrequencyHoppingApplied = trialFrequencyHoppingApplied(idx);
        T.FrequencyHoppingMode = trialFrequencyHoppingMode(idx);
        T.FrequencyHoppingToolboxMode = trialFrequencyHoppingToolboxMode(idx);
        T.SecondHopStartPRB = trialSecondHopStartPRB(idx);
        T.BeamformingApplied = trialBeamformingApplied(idx);
        T.AppliedBeamIndexSet = trialAppliedBeamIndexSet(idx);
        T.AppliedCodebookPortIndexSet=trialAppliedCodebookPortIndexSet(idx);
        T.AppliedCodebookPortIndexDefinition=trialAppliedCodebookPortIndexDefinition(idx);
        T.PrecodingNumLogicalPorts=trialPrecodingNumLogicalPorts(idx);
        T.AppliedPrecoderPMI = trialAppliedPrecoderPMI(idx);
        T.AppliedPrecoderPMIType = trialAppliedPrecoderPMIType(idx);
        T.AppliedPrecoderCodebookMode = trialAppliedPrecoderCodebookMode(idx);
        T.AppliedPrecoderMatrixSHA256 = trialAppliedPrecoderMatrixSHA256(idx);
        T.RequestedPrecoderSHA256 = trialRequestedPrecoderSHA256(idx);
        T.AppliedPrecoderSHA256 = trialAppliedPrecoderSHA256(idx);
        T.PrecoderDigestDomain = trialPrecoderDigestDomain(idx);
        T.FrozenGrantContextId = trialFrozenGrantContextId(idx);
        T.ULTransmissionAuthority = trialULTransmissionAuthority(idx);
        T.ULReceivedAssignmentDigest = trialULReceivedAssignmentDigest(idx);
        T.ULReceiveAllocationAuthority = trialULReceiveAllocationAuthority(idx);
        T.UEHARQAttempt = trialUEHARQAttempt(idx);
        T.UEHARQInitialAssignmentDigest = trialUEHARQInitialAssignmentDigest(idx);
        T.RequestedVsAppliedPrecoderPMIMatchStatus = trialRequestedVsAppliedPrecoderPMIMatchStatus(idx);
        T.PrecodingNumPorts = trialPrecodingNumPorts(idx);
        T.PrecodingNumLayers = trialPrecodingNumLayers(idx);
        T.PrecodingMatrixRows = trialPrecodingMatrixRows(idx);
        T.PrecodingMatrixCols = trialPrecodingMatrixCols(idx);
        T.InterfererBeamformingAppliedCount = trialInterfererBeamformingAppliedCount(idx);
        T.InterfererExplicitBeamWeightCount = trialInterfererExplicitBeamWeightCount(idx);
        T.InterfererTransformPrecodingCount = trialInterfererTransformPrecodingCount(idx);
        T.InterfererPrecoderSourceSet = trialInterfererPrecoderSourceSet(idx);
        T.InterfererPrecodingModeSet = trialInterfererPrecodingModeSet(idx);
        T.InterfererBeamIndexSetSummary = trialInterfererBeamIndexSetSummary(idx);
        T = localApplyRuntimeEvidenceColumns(T, trialRuntimeEvidence(idx));
        T = sixgr.link.appendMeasuredPHYEvidenceColumns(T, trialMeasuredPHYEvidence(idx));
        T = localDecorateTrialTruthFields(T, "UL", cfg);
        if receivedCompletion
            % One received frozen grant: these are actual observation
            % extents, not values reconstructed from nominal slot numbers.
            context=p.Results.ReceivedContext;
            T.SharedStreamSampleRateHz=repmat(preparedTransmission.SampleRateHz,stopIdx,1);
            T.TXStartSample=repmat(context.TransmitterObservation.StartSample,stopIdx,1);
            T.TXEndSampleExclusive=repmat(context.TransmitterObservation.EndSampleExclusive,stopIdx,1);
            T.RXStartSample=repmat(context.Observation.StartSample,stopIdx,1);
            T.RXEndSampleExclusive=repmat(context.Observation.EndSampleExclusive,stopIdx,1);
            physical=preparedTransmission.PhysicalTiming;
            T.WaveformTimingApplied=repmat(physical.WaveformTimingApplied,stopIdx,1);
            T.WaveformTimingSource=repmat(string(physical.Source),stopIdx,1);
            if physical.WaveformTimingApplied
                T.TimingAdvanceNTA_Tc=repmat(physical.NTA_Tc,stopIdx,1);
                T.TimingAdvanceOffset_Tc=repmat(physical.NTAOffset_Tc,stopIdx,1);
                T.TimingAdvanceTotal_Tc=repmat(physical.TotalAdvanceTicks,stopIdx,1);
                T.TimingAdvanceEffectiveAtSample=repmat(physical.TimingAdvanceEffectiveAtSample,stopIdx,1);
                T.TimeAlignmentExpirySampleExclusive=repmat(physical.TimeAlignmentExpirySampleExclusive,stopIdx,1);
            end
        end
end
end

function T = localCombineObservedREChunks(chunks)
if isempty(chunks)
    T = table();
    return;
end
keep = cellfun(@(x) istable(x) && ~isempty(x), chunks);
chunks = chunks(keep);
if isempty(chunks)
    T = table();
else
    T = vertcat(chunks{:});
end
end

function [y, nVar, noiseInfo] = localAddAwgn(x, replay, referenceWaveform, txInfo, carrier, occupiedIndices)
noiseInfo = localNoiseCalibrationInfo(x, referenceWaveform, NaN, "unavailable", txInfo);
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    thermalNVar = localResolveThermalNoiseVariance(replay, referenceWaveform, txInfo);
    [nVar, source] = localReceiverEffectiveNoiseVariance(thermalNVar, replay, "thermal_noise_plus_receiver_nf");
    noiseInfo = localNoiseCalibrationInfo(x, referenceWaveform, nVar, source, txInfo);
    if isfinite(thermalNVar) && thermalNVar > 0
        n = sqrt(thermalNVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
    y = x;
    return;
end
appliedSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
if isempty(carrier)
    error("sixgr:link:MissingOFDMNoiseCalibration", ...
        "Standalone AWGN requires the transmitting carrier for occupied-grid noise calibration.");
end
[signalEnergyPerOccupiedRE, receivedEnergyEvidence] = ...
    sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        carrier,referenceWaveform,occupiedIndices,"SignalFamily","PUSCH");
[y, referenceNoise] = sixgr.phy.waveform.addOccupiedREAWGN( ...
    x, carrier, appliedSNR_dB, ...
    "SignalEnergyPerOccupiedRE", signalEnergyPerOccupiedRE);
[nVar, source] = localReceiverEffectiveNoiseVariance( ...
    referenceNoise.SampleNoiseVariance, replay, ...
    "standalone_awgn_occupied_grid_esn0_reference");
noiseInfo = localNoiseCalibrationInfo(x, referenceWaveform, nVar, source, txInfo);
effectiveGridNoiseVariance = double(nVar) .* ...
    double(referenceNoise.SampleToGridNoiseVarianceGain);
noiseInfo.RequestedAWGNReferenceSNR_dB = ...
    double(referenceNoise.RequestedEsN0_dB);
noiseInfo.AppliedNoiseSNR_dB = 10 .* log10(max( ...
    double(referenceNoise.SignalEnergyPerOccupiedRE) ./ ...
    max(effectiveGridNoiseVariance, realmin), realmin));
noiseInfo.AppliedNoiseSNRSource = ...
    "occupied_re_signal_energy_over_effective_grid_noise_variance";
noiseInfo.SignalEnergyMeasurementSource = char(string(receivedEnergyEvidence.Source));
noiseInfo.SignalEnergyMeasurementPlane = char(string(receivedEnergyEvidence.MeasurementPlane));
noiseInfo.SignalEnergyObservationCount = double(receivedEnergyEvidence.ObservationCount);
noiseInfo.SignalEnergyReceiveBranchCount = double(receivedEnergyEvidence.ReceiveBranchCount);
noiseInfo.SNRReferencePlane = ...
    "occupied_resource_grid_re_after_ofdm_demodulation";
noiseInfo.ReferenceAWGNGridNoiseVariance = ...
    double(referenceNoise.GridNoiseVariance);
noiseInfo.ReferenceAWGNSampleNoiseVariance = ...
    double(referenceNoise.SampleNoiseVariance);
noiseInfo.GridNoiseVariance = effectiveGridNoiseVariance;
noiseInfo.SampleNoiseVariance = double(nVar);
noiseInfo.GridNoiseVarianceDomain = "resource_grid_pre_equalization";
noiseInfo.SampleNoiseVarianceDomain = ...
    "receiver_sample_waveform_pre_composite_front_end";
noiseInfo.SampleToGridNoiseVarianceGain = ...
    double(referenceNoise.SampleToGridNoiseVarianceGain);
noiseInfo.NoiseCalibrationVersion = char(string(referenceNoise.Version));
noiseInfo.WaveformPowerUsedForAWGN = false;
noiseInfo.SignalEnergyPerOccupiedRE = ...
    double(referenceNoise.SignalEnergyPerOccupiedRE);
end

function signalEnergy = localOccupiedRESignalEnergy(txInfo)
% The native PUSCH mapper emits unit-energy data symbols. Physical power
% control scales those symbols before the standalone AWGN reference plane,
% so the grid-domain noise variance must carry the same net scale.
signalEnergy = 1;
powerContext = sixgr.util.structGet(txInfo, "PowerContext", struct());
if ~isstruct(powerContext)
    return;
end
powerScale = double(sixgr.util.structGet(powerContext, "AmplitudeScale", 1));
powerControlScale = double(sixgr.util.structGet(powerContext, ...
    "PowerControlAmplitudeScale", 1));
netScale = powerScale .* powerControlScale;
if isscalar(netScale) && isfinite(netScale) && netScale > 0
    signalEnergy = netScale .^ 2;
end
end

function [effectiveNVar, source] = localReceiverEffectiveNoiseVariance(baseNVar, replay, baseSource)
effectiveNVar = double(baseNVar);
source = string(baseSource);
interferenceNVar = double(sixgr.util.structGet(replay, "InterferenceWaveformVariance", NaN));
if isfinite(interferenceNVar) && interferenceNVar > 0
    hasSharedSlotInterferenceCovariance = logical(sixgr.util.structGet(replay, ...
        "InterferenceContributionTensorAvailable", false)) || ...
        logical(sixgr.util.structGet(replay, "InterferenceCovarianceAvailableFromContributions", false));
    if hasSharedSlotInterferenceCovariance
        source = source + "_excluding_interference_modeled_by_shared_slot_covariance";
    else
        % Without a covariance/tensor, model unresolved interference as
        % spatially white impairment variance rather than silently ignoring it.
        if isfinite(effectiveNVar) && effectiveNVar >= 0
            effectiveNVar = effectiveNVar + interferenceNVar;
        else
            effectiveNVar = interferenceNVar;
        end
        source = source + "_with_unresolved_interference_in_composite_waveform_as_white_variance";
    end
end
end

function info = localNoiseCalibrationInfo(compositeWaveform, desiredWaveform, nVar, source, txInfo)
desiredPower = localUsefulOFDMReferencePower(desiredWaveform, txInfo);
compositePower = localUsefulOFDMReferencePower(compositeWaveform, txInfo);
appliedSNR = NaN;
if isfinite(desiredPower) && desiredPower > 0 && isfinite(nVar) && nVar > 0
    appliedSNR = 10 * log10(desiredPower / nVar);
end
info = struct( ...
    "DesiredSignalPowerBeforeNoise", double(desiredPower), ...
    "CompositeSignalPowerBeforeNoise", double(compositePower), ...
    "AppliedNoiseSNR_dB", double(appliedSNR), ...
    "AppliedNoiseSNRSource", "desired_signal_power_over_effective_sample_noise_variance", ...
    "SNRReferencePlane", "receiver_sample_waveform_pre_composite_front_end", ...
    "SampleNoiseVariance", double(nVar), ...
    "SampleNoiseVarianceDomain", "receiver_sample_waveform_pre_composite_front_end", ...
    "GridNoiseVariance", NaN, ...
    "GridNoiseVarianceDomain", "not_available", ...
    "DesiredSignalPowerBeforeNoiseDomain", "receiver_sample_waveform_pre_noise_pre_composite_front_end", ...
    "CompositeSignalPowerBeforeNoiseDomain", "receiver_sample_waveform_pre_noise_pre_composite_front_end", ...
    "NoiseVarianceSource", char(string(source)));
end

function nVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, snr_dB, txInfo)
nVar = NaN;
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB))
    return;
end
ofdmInfo = sixgr.util.structGet(txInfo, "OFDM", struct());
gain = double(sixgr.util.structGet(ofdmInfo, ...
    "SampleToGridNoiseVarianceGain", NaN));
if ~(isscalar(gain) && isfinite(gain) && gain > 0)
    return;
end
nVar = 10.^(-snr_dB / 10) / gain;
end

function refPower = localUsefulOFDMReferencePower(waveform, txInfo)
ofdmInfo = sixgr.util.structGet(txInfo, "OFDM", struct());
[refPower, ~] = sixgr.phy.waveform.ofdmReferencePower(waveform, ofdmInfo, ...
    "Domain", "active_samples");
end

function model = localResolveTrialChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
if strlength(model) == 0 || model == "NONE" || model == "OFF"
    model = "AWGN";
    return;
end
if model == "TDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
elseif model == "CDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
end
end

function T = localApplyRuntimeEvidenceColumns(T, evidenceCells)
if ~(istable(T) && ~isempty(T))
    T = localEnsureRuntimeEvidenceColumns(table(), 0);
    return;
end
rows = repmat(localEmptyRuntimeEvidenceRow(), numel(evidenceCells), 1);
for i = 1:numel(evidenceCells)
    ev = evidenceCells{i};
    if ~(isstruct(ev) && ~isempty(fieldnames(ev)))
        continue;
    end
    names = fieldnames(rows(i));
    for fi = 1:numel(names)
        name = names{fi};
        if isfield(ev, name)
            rows(i).(name) = ev.(name);
        end
    end
end
evidenceT = struct2table(rows);
for vi = 1:numel(evidenceT.Properties.VariableNames)
    varName = evidenceT.Properties.VariableNames{vi};
    T.(varName) = evidenceT.(varName);
end
end

function T = localDecorateTrialTruthFields(T, direction, cfg)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
strategy = strtrim(string(localOptionalColumn(T, "ConfiguredBeamSelectionStrategy", "")));
T.BeamSelectionStrategy = strategy;
T.BeamSelectionAuthority = repmat("configured_beam_policy_reference", n, 1);
fixedPolicyMask = startsWith(lower(strategy), "fixed");
dynamicPolicyMask = strlength(strategy) > 0 & ~fixedPolicyMask;
T.BeamSelectionPolicyType = repmat("", n, 1);
T.BeamSelectionPolicyType(fixedPolicyMask) = "fixed_policy";
T.BeamSelectionPolicyType(dynamicPolicyMask) = "dynamic_policy";
T.BeamSelectionPolicyFixed = fixedPolicyMask;
requestedBeam = strings(n, 1);
configuredBeamSet = strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamIndexSet", "")));
if strlength(configuredBeamSet) > 0
    requestedBeam(:) = configuredBeamSet;
end
beamSetColumn = strtrim(string(localOptionalColumn(T, "BeamIndexSet", "")));
beamSetMask = strlength(beamSetColumn) > 0;
requestedBeam(beamSetMask) = beamSetColumn(beamSetMask);
selectedBeam = double(localOptionalColumn(T, "SelectedBeamIndex", NaN));
requestedBeam(isfinite(selectedBeam)) = string(round(selectedBeam(isfinite(selectedBeam))));
T.RequestedBeamIndexSet = requestedBeam;
requestedPMI = double(localOptionalColumn(T, "PMI", NaN));
configuredPMI = double(localOptionalColumn(T, "ConfiguredPMI", NaN));
configuredMask = ~isfinite(requestedPMI) & isfinite(configuredPMI);
ulConfiguredMask = upper(string(direction)) == "UL" & isfinite(configuredPMI);
requestedPMI(configuredMask) = configuredPMI(configuredMask);
requestedPMI(ulConfiguredMask) = configuredPMI(ulConfiguredMask);
T.RequestedPrecoderPMI = requestedPMI;
T.RequestedPrecoderSource = repmat("", n, 1);
T.RequestedPrecoderSource(isfinite(double(localOptionalColumn(T, "PMI", NaN)))) = "scheduler_grant_or_csi_feedback_request";
T.RequestedPrecoderSource(configuredMask) = "configured_pmi_reference";
T.RequestedPrecoderSource(ulConfiguredMask) = "configured_pusch_tpmi_runtime_request";
precoderSource = localNormalizeULAppliedPrecoderSource( ...
    string(localOptionalColumn(T, "PrecoderSource", "")), ...
    string(localOptionalColumn(T, "PrecodingMode", "")), ...
    logical(localOptionalColumn(T, "TransformPrecodingApplied", false)));
T.PrecoderSource = precoderSource;
T.AppliedPrecoderSource = precoderSource;
T = localDecorateBeamAndPrecoderTruthFields(T, direction);
configuredLinkMode = repmat(localResolveLinkAdaptationMode(cfg, direction), n, 1);
configuredSelectionMode = repmat(localResolveActualMCSSelectionMode(cfg, direction), n, 1);
configuredDomain = repmat(sixgr.link.resolveLinkAdaptationDomain(cfg, direction), n, 1);
T.ConfiguredLinkAdaptationMode = configuredLinkMode;
T.ConfiguredMCSSelectionPolicy = configuredSelectionMode;
T.LinkAdaptationDomain = configuredDomain;
fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false",""];
adaptiveTokens = ["amc","adaptive","cqi","cqi_driven","baseline","actual_bler_based","effective_sinr_driven"];
modeTokens = lower(strtrim(string(configuredLinkMode)));
selectionTokens = lower(strtrim(string(configuredSelectionMode)));
T.FixedAnchorMode = ismember(modeTokens, fixedTokens) & ...
    ~ismember(selectionTokens, adaptiveTokens);
T.AdaptiveMode = ismember(modeTokens, adaptiveTokens) | ...
    ismember(selectionTokens, adaptiveTokens);
T.CQISource = localResolveCQISourceColumn(T, configuredDomain);
[mcsSelectionSource, mcsValueStatus] = localResolveMCSSelectionEvidenceColumns(T, cfg, direction);
T.MCSSelectionSource = mcsSelectionSource;
T.MCSValueStatus = mcsValueStatus;
% Distinguish "AMC enabled" from "a causal receiver-feedback decision was
% applied".  A conservative bootstrap grant has no feedback lineage and
% must not be labelled as an applied link-adaptation decision.
bootstrapSelection = contains(lower(strtrim(string(mcsSelectionSource))), "bootstrap");
feedbackSourceSlot = double(localOptionalColumn(T, ...
    "LinkAdaptationAppliedFeedbackSourceSlot", NaN));
if ismember("LinkAdaptationApplied", string(T.Properties.VariableNames))
    T.LinkAdaptationApplied(bootstrapSelection & ~isfinite(feedbackSourceSlot)) = false;
end
T.OLLADomain = repmat(localResolveOLLADomainToken(cfg, direction), n, 1);
outerLoopEnabled = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", false));
innerLoopEnabled = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.innerLoopFlag", false));
linkModeColumn = lower(string(localOptionalColumn(T, "LinkAdaptationMode", configuredLinkMode)));
schedulerReplayMask = linkModeColumn == "scheduler_grant_replay";
linkAdaptationRuntimeMask = ~schedulerReplayMask & ~ismember(lower(string(configuredLinkMode)), ["fixed","disabled","none","off","false",""]);
existingOuterLoopEnabled = logical(localOptionalColumn(T, "OuterLoopEnabled", outerLoopEnabled));
existingOuterLoopApplied = logical(localOptionalColumn(T, "OuterLoopApplied", false));
existingInnerLoopApplied = logical(localOptionalColumn(T, "InnerLoopApplied", false));
existingOLLADeltaMCS = double(localOptionalColumn(T, "OLLADeltaMCS", NaN));
existingOLLAUpdateCount = double(localOptionalColumn(T, "OLLAUpdateCount", NaN));
existingOLLAState = string(localOptionalColumn(T, "OLLAState", ""));
runtimeDecisionApplied = logical(localOptionalColumn(T, "LinkAdaptationApplied", false));
runtimeDecisionScheduled = logical(localOptionalColumn(T, "LinkAdaptationScheduled", false));
appliedDecisionCQI = double(localOptionalColumn(T, "AppliedLinkAdaptationResolvedCQI", NaN));
appliedDecisionOLLADelta = double(localOptionalColumn(T, "AppliedLinkAdaptationOLLADeltaDb", NaN));
appliedDecisionOLLAUpdates = double(localOptionalColumn(T, "AppliedLinkAdaptationOLLAUpdateCount", NaN));
scheduledDecisionCQI = double(localOptionalColumn(T, "ScheduledLinkAdaptationResolvedCQI", NaN));
scheduledOLLAEligible = logical(localOptionalColumn(T, "ScheduledLinkAdaptationOLLAFeedbackEligible", false));
resolvedOuterLoopEnabled = repmat(outerLoopEnabled, n, 1) | existingOuterLoopEnabled;
resolvedInnerLoopEnabled = repmat(innerLoopEnabled, n, 1);
runtimeOuterApplied = resolvedOuterLoopEnabled & linkAdaptationRuntimeMask & ...
    runtimeDecisionApplied & isfinite(appliedDecisionOLLAUpdates) & appliedDecisionOLLAUpdates >= 1;
runtimeInnerApplied = resolvedInnerLoopEnabled & linkAdaptationRuntimeMask & ...
    runtimeDecisionApplied & isfinite(appliedDecisionCQI);
schedulerInnerApplied = resolvedInnerLoopEnabled & schedulerReplayMask & ...
    runtimeDecisionApplied & isfinite(appliedDecisionCQI);
T.OuterLoopEnabled = resolvedOuterLoopEnabled;
T.InnerLoopEnabled = resolvedInnerLoopEnabled;
T.OuterLoopApplied = (T.OuterLoopEnabled & schedulerReplayMask & existingOuterLoopApplied) | ...
    runtimeOuterApplied;
T.InnerLoopApplied = (T.InnerLoopEnabled & schedulerReplayMask & existingInnerLoopApplied) | ...
    schedulerInnerApplied | runtimeInnerApplied;
T.ILLAUpdateScheduled = T.InnerLoopEnabled & linkAdaptationRuntimeMask & ...
    runtimeDecisionScheduled & isfinite(scheduledDecisionCQI);
T.OLLAFeedbackUpdateScheduled = T.OuterLoopEnabled & ...
    linkAdaptationRuntimeMask & runtimeDecisionScheduled & scheduledOLLAEligible;
runtimeOLLAValue = linkAdaptationRuntimeMask & isfinite(appliedDecisionOLLADelta);
existingOLLADeltaMCS(runtimeOLLAValue) = appliedDecisionOLLADelta(runtimeOLLAValue);
runtimeOLLAUpdateValue = linkAdaptationRuntimeMask & isfinite(appliedDecisionOLLAUpdates);
existingOLLAUpdateCount(runtimeOLLAUpdateValue) = appliedDecisionOLLAUpdates(runtimeOLLAUpdateValue);
T.OLLADeltaMCS = existingOLLADeltaMCS;
T.OLLADeltaDb(runtimeOLLAValue) = appliedDecisionOLLADelta(runtimeOLLAValue);
T.OLLAUpdateCount = existingOLLAUpdateCount;
T.OLLAState = repmat("disabled", n, 1);
T.OLLAState(T.OuterLoopEnabled & schedulerReplayMask) = "configured_enabled_waiting_for_scheduler_ack_nack_feedback";
T.OLLAState(T.OuterLoopEnabled & linkAdaptationRuntimeMask & ~T.OuterLoopApplied) = "configured_enabled_waiting_for_runtime_feedback";
T.OLLAState(T.OLLAFeedbackUpdateScheduled & ~T.OuterLoopApplied) = "feedback_update_scheduled_for_future_slot";
T.OLLAState(T.OuterLoopApplied) = "applied_runtime_link_adaptation_decision";
preserveStateMask = strlength(strtrim(existingOLLAState)) > 0 & lower(strtrim(existingOLLAState)) ~= "disabled";
T.OLLAState(preserveStateMask) = existingOLLAState(preserveStateMask);
ollaPolicy = sixgr.link.resolveOLLAConfig(cfg);
ollaAuthority = string(localOptionalColumn(T, "OLLAStateAuthority", ""));
ollaAuthority(strlength(strtrim(ollaAuthority)) == 0 & T.OuterLoopEnabled) = string(ollaPolicy.StateAuthority);
T.OLLAStateAuthority = ollaAuthority;
T.CalibrationProfile = repmat(localResolveLinkAdaptationCalibrationProfile(cfg, direction), n, 1);
T.RequestedOperatingPointSource = localResolveOperatingPointSourceColumn(configuredSelectionMode, configuredLinkMode);
T.SchedulerGrantMCSSelectionMode = string(localOptionalColumn(T, "SchedulerGrantMCSSelectionMode", ""));
operatingPointSource = localResolveOperatingPointSourceColumn(localOptionalColumn(T, "ActualMCSSelectionMode", ""), localOptionalColumn(T, "LinkAdaptationMode", ""));
T.GrantOperatingPointSource = operatingPointSource;
T.AppliedOperatingPointSource = operatingPointSource;
T.MCSAuthority = operatingPointSource;
T.ModulationAuthority = operatingPointSource;
% Export the nominal configured point and the exact transmitted/effective
% point with the same schema used by DL.  Adaptive scheduling may correctly
% choose a point different from the nominal YAML request, but blank effective
% columns make that decision impossible to audit from the persisted UL CSV.
configuredMCS = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.mcsIndex", NaN), ...
    sixgr.util.structGet(cfg, "pusch6gr.MCSIndex", NaN));
configuredModulation = string(sixgr.util.structGet(cfg, ...
    "phy.pusch.modulation", ...
    sixgr.util.structGet(cfg, "pusch6gr.Modulation", "")));
configuredRank = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.rank", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN), ...
    sixgr.util.structGet(cfg, "mimo.rank", NaN));
if ~isfinite(configuredRank)
    transmittedLayers = double(localOptionalColumn(T, "Layers", NaN));
    transmittedLayers = transmittedLayers(isfinite(transmittedLayers));
    if ~isempty(transmittedLayers)
        configuredRank = transmittedLayers(1);
    end
end
T.ConfiguredMCSIndex = repmat(configuredMCS, n, 1);
T.ConfiguredModulation = repmat(configuredModulation, n, 1);
T.ConfiguredRank = repmat(configuredRank, n, 1);
T.EffectiveMCSIndex = double(localOptionalColumn(T, "MCS", NaN));
T.EffectiveModulation = string(localOptionalColumn(T, "Modulation", ""));
T.EffectiveLayers = double(localOptionalColumn(T, "Layers", NaN));
T.EffectiveRank = T.EffectiveLayers;
T = sixgr.link.applyScheduledOperatingPointEvidence(T);
T = sixgr.util.applyLLSRawTrialLifecycle(T);
T.RunUUID = repmat(string(localArtifactStoreField("RunUUID")), n, 1);
T.RunTag = repmat(string(sixgr.util.structGet(cfg, "run.runTag", "")), n, 1);
T.ScenarioID = repmat(string(sixgr.util.structGet(cfg, "run.scenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", ""))), n, 1);
T.RunnerProfile = repmat(string(sixgr.util.structGet(cfg, "run.runnerProfile", "waveform_bundle")), n, 1);
T.ConfigHash = repmat(string(sixgr.util.structGet(cfg, "meta.configHash", "")), n, 1);
T.SourceArtifact = repmat("air_interface/csv/ul_pusch_trials.csv", n, 1);
T.SourceTable = repmat("air_interface/csv/ul_pusch_trials.csv", n, 1);
T.ArtifactClass = repmat("raw_runtime_trial_evidence", n, 1);
T.SemanticState = string(T.RowLifecycleState);
T.CountsTowardCoverage = ~logical(localOptionalColumn(T, "Crash", false)) & ~logical(localOptionalColumn(T, "IsWarmupFrame", false));
runtimeStatus = strtrim(string(localOptionalColumn(T, "RuntimeMaterializationStatus", "")));
runtimeEvidence = strtrim(string(localOptionalColumn(T, "RuntimeEvidenceSource", "")));
activeRuntimeMask = ~logical(localOptionalColumn(T, "Crash", false));
runtimeStatus(activeRuntimeMask & strlength(runtimeStatus) == 0) = "active_waveform_pusch_runtime";
runtimeEvidence(activeRuntimeMask & strlength(runtimeEvidence) == 0) = "sixgr.link.runULPUSCHThroughput";
T.RuntimeMaterializationStatus = runtimeStatus;
T.RuntimeEvidenceSource = runtimeEvidence;
T.MachineReadable = true(n, 1);
T.HumanReadable = true(n, 1);
end

function T = localDecorateBeamAndPrecoderTruthFields(T, direction)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
requestedBeam = strtrim(string(localOptionalColumn(T, "RequestedBeamIndexSet", "")));
requestedPMI = double(localOptionalColumn(T, "RequestedPrecoderPMI", NaN));
appliedBeam = strtrim(string(localOptionalColumn(T, "AppliedBeamIndexSet", "")));
appliedPMI = double(localOptionalColumn(T, "AppliedPrecoderPMI", NaN));
appliedSource = strtrim(string(localOptionalColumn(T, "AppliedPrecoderSource", localOptionalColumn(T, "PrecoderSource", ""))));
precodingMode = lower(strtrim(string(localOptionalColumn(T, "PrecodingMode", ""))));
transformApplied = logical(localOptionalColumn(T, "TransformPrecodingApplied", false)) | precodingMode == "transform_precoding";
explicitBeamWeights = logical(localOptionalColumn(T, "ExplicitBeamWeightsApplied", false));
beamformingApplied = logical(localOptionalColumn(T, "BeamformingApplied", false));
isUL = upper(string(direction)) == "UL";
codebookMask = isUL & (precodingMode == "ul_codebook_tpmi" | lower(appliedSource) == "ul_pusch_native_codebook_tpmi");
T.RequestedBeamIndexSet = requestedBeam;

T.RequestedBeamTruthClassification = repmat("", n, 1);
T.RequestedPrecoderPMITruthClassification = repmat("", n, 1);
T.AppliedBeamApplicationSource = appliedSource;
T.AppliedBeamTruthClassification = repmat("", n, 1);
T.AppliedPrecoderPMIApplicationSource = appliedSource;
T.AppliedPrecoderPMITruthClassification = repmat("", n, 1);

requestedBeamMask = strlength(requestedBeam) > 0;
requestedPMIMask = isfinite(requestedPMI);
appliedBeamMask = strlength(appliedBeam) > 0;
appliedPMIMask = isfinite(appliedPMI);

T.RequestedBeamTruthClassification(requestedBeamMask) = "requested_reference";
T.RequestedPrecoderPMITruthClassification(requestedPMIMask) = "requested_reference";
T.AppliedBeamTruthClassification(appliedBeamMask) = "applied_runtime_value";
T.AppliedPrecoderPMITruthClassification(appliedPMIMask) = "applied_runtime_value";
matchStatus = strings(n, 1);
for ii = 1:n
    matchStatus(ii) = localRequestedVsAppliedPMIStatus(requestedPMI(ii), appliedPMI(ii));
end
T.RequestedVsAppliedPrecoderPMIMatchStatus = matchStatus;

if ~isUL
    return;
end

directMask = ~transformApplied & ~codebookMask;
missingAppliedBeamMask = ~appliedBeamMask;
missingAppliedPMIMask = ~appliedPMIMask;

beamAppSource = T.AppliedBeamApplicationSource;
pmiAppSource = T.AppliedPrecoderPMIApplicationSource;
beamAppSource(missingAppliedBeamMask & directMask) = "ul_direct_mapping_no_materialized_beam_index_set";
beamAppSource(missingAppliedBeamMask & transformApplied) = "ul_transform_precoding_no_materialized_beam_index_set";
beamAppSource(missingAppliedBeamMask & codebookMask) = "ul_pusch_native_codebook_no_materialized_beam_index_set";
pmiAppSource(missingAppliedPMIMask & directMask) = "ul_direct_mapping_no_materialized_applied_pmi";
pmiAppSource(missingAppliedPMIMask & transformApplied) = "ul_transform_precoding_no_materialized_applied_pmi";
pmiAppSource(missingAppliedPMIMask & codebookMask) = "ul_pusch_native_codebook_no_runtime_tpmi";
T.AppliedBeamApplicationSource = beamAppSource;
T.AppliedPrecoderPMIApplicationSource = pmiAppSource;
T.AppliedBeamTruthClassification(missingAppliedBeamMask) = "not_materialized_in_active_ul_path";
T.AppliedPrecoderPMITruthClassification(missingAppliedPMIMask) = "not_materialized_in_active_ul_path";
T.BeamformingApplied(missingAppliedBeamMask & ~beamformingApplied) = false;
end

function source = localNormalizeULAppliedPrecoderSource(source, mode, transformApplied)
source = strtrim(string(source));
mode = lower(strtrim(string(mode)));
transformApplied = logical(transformApplied);
directMask = mode == "direct_mapping_no_explicit_beam_weights" | (~transformApplied & strlength(mode) == 0);
transformMask = mode == "transform_precoding" | transformApplied;
repairMask = strlength(source) == 0 | lower(source) == "codebook_dft";
source(repairMask & directMask) = "ul_direct_mapping_no_explicit_beam_weights";
source(repairMask & transformMask) = "ul_pusch_transform_precoding";
end

function values = localResolveOperatingPointSourceColumn(actualMode, linkMode)
values = repmat("", numel(actualMode), 1);
actualMode = lower(strtrim(string(actualMode)));
linkMode = lower(strtrim(string(linkMode)));
values(actualMode == "scheduler_grant") = "scheduler_grant";
values(actualMode == "cqi_driven") = "cqi_link_adaptation";
values(actualMode == "cqi_table") = "cqi_link_adaptation";
values(actualMode == "configured_fixed") = "configured_fixed_mcs";
values(actualMode == "feedback_cqi_derived_reference") = "feedback_cqi_derived_reference";
values(actualMode == "bootstrap_large_scale_preview_cqi_lab_default") = "bootstrap_large_scale_preview_cqi_lab_default";
values(actualMode == "bootstrap_cqi_conservative_lab_default") = "bootstrap_cqi_conservative_lab_default";
mask = strlength(values) == 0 & strlength(linkMode) > 0;
values(mask) = "link_adaptation_mode_reference";
end

function value = localArtifactStoreField(fieldName)
value = "";
try
    state = sixgr.db.artifactStore("get_state");
    value = sixgr.util.structGet(state, char(string(fieldName)), "");
catch
    value = "";
end
end

function col = localOptionalColumn(T, name, defaultValue)
if ismember(string(name), string(T.Properties.VariableNames))
    col = T.(char(name));
else
    if isstring(defaultValue) && numel(defaultValue) == height(T) && ~isscalar(defaultValue)
        col = reshape(string(defaultValue), height(T), 1);
    elseif islogical(defaultValue) && numel(defaultValue) == height(T) && ~isscalar(defaultValue)
        col = reshape(logical(defaultValue), height(T), 1);
    elseif isnumeric(defaultValue) && numel(defaultValue) == height(T) && ~isscalar(defaultValue)
        col = reshape(double(defaultValue), height(T), 1);
    elseif ischar(defaultValue) || (isstring(defaultValue) && isscalar(defaultValue))
        col = repmat(string(defaultValue), height(T), 1);
    elseif islogical(defaultValue)
        col = repmat(logical(defaultValue), height(T), 1);
    else
        col = repmat(double(defaultValue), height(T), 1);
    end
end
end

function row = localBuildRuntimeAntennaTimingEvidence(direction, cfg, grant, tx, txInfo, chState, replay)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
bsMeta = localResolveRuntimeAntennaMeta(userMeta, "RuntimeServingBSAntennaMeta", "RuntimeServingBSAntenna");
ueMeta = localResolveRuntimeAntennaMeta(userMeta, "RuntimeUEAntennaMeta", "RuntimeUEAntenna");
[distance_m, geometricDelay_s] = localResolveGeometryDelay(userMeta);
[distance_m, geometricDelay_s, geometricDelayForReport_s, geometrySource] = ...
    localFixedSNRGeometryReporting(cfg, distance_m, geometricDelay_s, replay);
[dominantPathDelay_s, channelFilterDelay_s, channelDelaySource] = localResolveChannelDelayTerms(chState, tx, txInfo);
slotStart_s = double(sixgr.util.structGet(userMeta, "RuntimeSlotStartTime_s", NaN));
toa_s = NaN;
if isfinite(slotStart_s)
    toa_s = slotStart_s + geometricDelay_s + dominantPathDelay_s;
end
toaEstimate_s = localResolveTimingEstimateToA(slotStart_s, replay, tx, txInfo);
channelMeta = localResolveChannelRuntimeMeta(chState, cfg, userMeta);
interferenceMeta = localResolveInterferenceChannelRuntimeMeta(replay, channelMeta);

row = localEmptyRuntimeEvidenceRow();
row.Direction = string(direction);
row.GrantContextId = string(sixgr.util.structGet(grant, "GrantContextId", ""));
row.BSAntennaArrayClass = string(sixgr.util.structGet(bsMeta, "ArrayClass", ""));
row.BSAntennaElementClass = string(sixgr.util.structGet(bsMeta, "ElementClass", ""));
row.BSAntennaArrayType = string(sixgr.util.structGet(bsMeta, "ArrayType", ""));
row.BSAntennaRows = double(sixgr.util.structGet(bsMeta, "NumRows", NaN));
row.BSAntennaCols = double(sixgr.util.structGet(bsMeta, "NumCols", NaN));
row.BSAntennaElements = double(sixgr.util.structGet(bsMeta, "NumElements", NaN));
row.BSAntennaSpacingH_lambda = double(sixgr.util.structGet(bsMeta, "SpacingH_lambda", NaN));
row.BSAntennaSpacingV_lambda = double(sixgr.util.structGet(bsMeta, "SpacingV_lambda", NaN));
row.BSAntennaPolarization = string(sixgr.util.structGet(bsMeta, "Polarization", ""));
row.BSAntennaAzimuth_deg = double(sixgr.util.structGet(userMeta, "RuntimeServingBSAzimuth_deg", sixgr.util.structGet(bsMeta, "Azimuth_deg", NaN)));
row.BSAntennaNumPorts = double(sixgr.util.structGet(bsMeta, "NumPorts", NaN));
row.BSAntennaHasPhasedArrayObject = logical(sixgr.util.structGet(bsMeta, "HasPhasedArrayObject", false));
row.UEAntennaArrayClass = string(sixgr.util.structGet(ueMeta, "ArrayClass", ""));
row.UEAntennaElementClass = string(sixgr.util.structGet(ueMeta, "ElementClass", ""));
row.UEAntennaArrayType = string(sixgr.util.structGet(ueMeta, "ArrayType", ""));
row.UEAntennaRows = double(sixgr.util.structGet(ueMeta, "NumRows", NaN));
row.UEAntennaCols = double(sixgr.util.structGet(ueMeta, "NumCols", NaN));
row.UEAntennaElements = double(sixgr.util.structGet(ueMeta, "NumElements", NaN));
row.UEAntennaSpacingH_lambda = double(sixgr.util.structGet(ueMeta, "SpacingH_lambda", NaN));
row.UEAntennaSpacingV_lambda = double(sixgr.util.structGet(ueMeta, "SpacingV_lambda", NaN));
row.UEAntennaPolarization = string(sixgr.util.structGet(ueMeta, "Polarization", ""));
row.UEAntennaHeading_deg = double(sixgr.util.structGet(userMeta, "RuntimeUEHeading_deg", sixgr.util.structGet(ueMeta, "Heading_deg", NaN)));
row.UEAntennaNumPorts = double(sixgr.util.structGet(ueMeta, "NumPorts", NaN));
row.UEAntennaHasPhasedArrayObject = logical(sixgr.util.structGet(ueMeta, "HasPhasedArrayObject", false));
row.AntennaConfigSource = string(sixgr.util.structGet(userMeta, "RuntimeAntennaConfigSource", ""));
row.RuntimeAntennaObjectSource = string(sixgr.util.structGet(userMeta, "RuntimeAntennaObjectSource", ""));
row.AntennaRuntimeObjectCreated = logical(isfinite(row.BSAntennaElements) && isfinite(row.UEAntennaElements));
row.ChannelArrayModel = string(channelMeta.ChannelArrayModel);
row.ChannelObjectSource = string(channelMeta.ChannelObjectSource);
row.ChannelObjectClass = string(channelMeta.ChannelObjectClass);
row.ChannelArrayHandlingStatus = string(channelMeta.ChannelArrayHandlingStatus);
row.ChannelArrayHandlingBlocker = string(channelMeta.ChannelArrayHandlingBlocker);
row.ChannelGeometryCouplingLevel = string(channelMeta.ChannelGeometryCouplingLevel);
row.GeometryAdapterType = string(channelMeta.GeometryAdapterType);
row.GeometryAdapterSource = string(channelMeta.GeometryAdapterSource);
row.GeometryAdapterLimitation = string(channelMeta.GeometryAdapterLimitation);
row.GeometryAdapterPortMapping = string(channelMeta.GeometryAdapterPortMapping);
row.ChannelUsesCountOnlyAntennaModel = logical(channelMeta.ChannelUsesCountOnlyAntennaModel);
row.ChannelUsesSameRuntimeAntennaAssumptions = logical(channelMeta.ChannelUsesSameRuntimeAntennaAssumptions);
row.TransmitElementPatternApplied = logical(channelMeta.TransmitElementPatternApplied);
row.ReceiveElementPatternApplied = logical(channelMeta.ReceiveElementPatternApplied);
row.TransmitElementPatternSource = string(channelMeta.TransmitElementPatternSource);
row.ReceiveElementPatternSource = string(channelMeta.ReceiveElementPatternSource);
row.ChannelComplianceMode = string(channelMeta.ChannelComplianceMode);
row.PathlossModelSource = string(channelMeta.PathlossModelSource);
row.PathlossComplianceStatus = string(channelMeta.PathlossComplianceStatus);
row.FallbackUsedForPathloss = logical(channelMeta.FallbackUsedForPathloss);
row.O2IModelSource = string(channelMeta.O2IModelSource);
row.O2IComplianceStatus = string(channelMeta.O2IComplianceStatus);
row.O2IComplianceReason = string(channelMeta.O2IComplianceReason);
row.LOSProbabilitySource = string(channelMeta.LOSProbabilitySource);
row.LOSComplianceStatus = string(channelMeta.LOSComplianceStatus);
row.LOSComplianceReason = string(channelMeta.LOSComplianceReason);
row.InterferenceChannelObjectSource = string(interferenceMeta.ChannelObjectSource);
row.InterferenceChannelObjectClass = string(interferenceMeta.ChannelObjectClass);
row.InterferenceChannelArrayHandlingStatus = string(interferenceMeta.ChannelArrayHandlingStatus);
row.InterferenceChannelArrayHandlingBlocker = string(interferenceMeta.ChannelArrayHandlingBlocker);
row.InterferenceUsesSameRuntimeAntennaAssumptions = logical(interferenceMeta.ChannelUsesSameRuntimeAntennaAssumptions);
row.InterferencePathUsesSameArrayAssumptions = logical(interferenceMeta.InterferencePathUsesSameArrayAssumptions);
row.PropagationDistance_m = double(distance_m);
row.RuntimeGeometryDistance2D_m=double(localFixedSNRGeometryValue(cfg, ...
    sixgr.util.structGet(replay,'RuntimeGeometryDistance2D_m',NaN)));
row.RuntimeGeometryDistance3D_m=double(localFixedSNRGeometryValue(cfg, ...
    sixgr.util.structGet(replay,'RuntimeGeometryDistance3D_m',NaN)));
row.RuntimeGeometrySource=string(geometrySource);
row.GeometricPropagationDelay_s = double(geometricDelayForReport_s);
row.DominantPathDelay_s = double(dominantPathDelay_s);
row.ChannelFilterDelay_s = double(channelFilterDelay_s);
row.PropagationDelay_s = double(geometricDelay_s + dominantPathDelay_s);
row.ToD_s = double(slotStart_s);
row.ToA_s = double(toa_s);
row.ToAEstimate_s = double(toaEstimate_s);
row.ToDSource = "runtime_slot_start_reference";
if localConfiguredSNRIsLinkAuthority(cfg)
    row.ToASource = "runtime_slot_start_plus_cdl_path_delay_no_geometry";
else
    row.ToASource = "runtime_geometry_plus_channel_path_delay";
end
row.ToAEstimateSource = string(ternaryString(isfinite(toaEstimate_s), "receiver_timing_estimate_pre_correction", ""));
row.ChannelDelaySource = string(channelDelaySource);
row.AntennaGeometrySource = string(sixgr.util.structGet(userMeta, ...
    "RuntimeAntennaGeometrySource", "CoupledTruthRuntime.applyUserContextImpl"));
row.RuntimeTraceSource = "runULPUSCHThroughput_active_trial";
row.AntennaEvidenceSource = "active_runtime_user_context";
row.SameFlowEvidenceSource = string(sixgr.util.structGet(userMeta, ...
    "RuntimeSameFlowEvidenceSource", ...
    "CoupledTruthRuntime.applyUserContextImpl->runULPUSCHThroughput"));
row.ChannelRealizationId = string(sixgr.util.structGet(replay, "ChannelRealizationId", ""));
row.RuntimeChannelStateKey = string(sixgr.util.structGet(replay, "RuntimeChannelStateKey", ""));
row.RuntimeChannelLinkKey = string(sixgr.util.structGet(replay, "RuntimeChannelLinkKey", ""));
row.RuntimeChannelSeed = double(sixgr.util.structGet(replay, "RuntimeChannelSeed", NaN));
row.RuntimeChannelReciprocityExact = logical(sixgr.util.structGet(replay, "RuntimeChannelReciprocityExact", false));
row.RuntimeChannelReciprocityDirection = string(sixgr.util.structGet(replay, "RuntimeChannelReciprocityDirection", ""));
row.RuntimeChannelReciprocitySource = string(sixgr.util.structGet(replay, "RuntimeChannelReciprocitySource", ""));
row.RuntimeChannelReciprocityApproximationMode = string(sixgr.util.structGet(replay, "RuntimeChannelReciprocityApproximationMode", ""));
row.RuntimeChannelTransmitAndReceiveSwapped = logical(sixgr.util.structGet(replay, "RuntimeChannelTransmitAndReceiveSwapped", false));
row.RuntimeChannelAngleEvidenceAvailable = logical(sixgr.util.structGet(replay, "RuntimeChannelAngleEvidenceAvailable", false));
row.RuntimeChannelAngleEvidenceSource = string(sixgr.util.structGet(replay, "RuntimeChannelAngleEvidenceSource", ""));
row.RuntimeChannelAnglePathCount = double(numel(sixgr.util.structGet(replay, "RuntimeChannelAnglesAoD_deg", [])));
row.RuntimeChannelCanonicalInputSamples = double(sixgr.util.structGet(replay, "RuntimeChannelCanonicalInputSamples", NaN));
row.RuntimeChannelAlignmentLookaheadSamples = double(sixgr.util.structGet(replay, "RuntimeChannelAlignmentLookaheadSamples", NaN));
row.RuntimeChannelAlignmentLookaheadExecutedOnFork = logical(sixgr.util.structGet(replay, "RuntimeChannelAlignmentLookaheadExecutedOnFork", false));
row.RuntimeChannelObjectClockExact = logical(sixgr.util.structGet(replay, "RuntimeChannelObjectClockExact", false));
row.RuntimeChannelResetCount = double(sixgr.util.structGet(replay, "RuntimeChannelResetCount", NaN));
row.RuntimeChannelStartSample = double(sixgr.util.structGet(replay, "RuntimeChannelStartSample", NaN));
row.RuntimeChannelEndSample = double(sixgr.util.structGet(replay, "RuntimeChannelEndSample", NaN));
row.RuntimeChannelInputWaveformSHA256 = string(sixgr.util.structGet(replay, "RuntimeChannelInputWaveformSHA256", ""));
row.RuntimeChannelOutputWaveformSHA256 = string(sixgr.util.structGet(replay, "RuntimeChannelOutputWaveformSHA256", ""));
row.RuntimeChannelPathGainsSHA256 = string(sixgr.util.structGet(replay, "RuntimeChannelPathGainsSHA256", ""));
row.RuntimeChannelPathGainElementCount = double(sixgr.util.structGet(replay, "RuntimeChannelPathGainElementCount", 0));
row.RuntimeChannelPathGainDimensions = string(sixgr.util.structGet(replay, "RuntimeChannelPathGainDimensions", ""));
row.ChannelFadingObjectClass = string(sixgr.util.structGet(replay, "ChannelFadingObjectClass", ""));
txRFReplay = sixgr.util.structGet(tx, "TxRFImpairmentReplay", struct());
row.TxRFImpairmentChainId = string(sixgr.util.structGet(txRFReplay, "RFImpairmentChainId", ""));
row.TxRFInputWaveformSHA256 = string(sixgr.util.structGet(txRFReplay, "RFInputWaveformSHA256", ""));
row.TxRFOutputWaveformSHA256 = string(sixgr.util.structGet(txRFReplay, "RFOutputWaveformSHA256", ""));
row.TxRFExecutionStatus = localRFExecutionStatus(txRFReplay, "tx");
row.TxRFStageOrder = string(sixgr.util.structGet(txRFReplay, "RFStageOrder", ""));
row.TxRFAppliedStageCount = double(sixgr.util.structGet(txRFReplay, "RFAppliedStageCount", 0));
row.TxRFConfiguredStageCount = double(sixgr.util.structGet(txRFReplay, "RFConfiguredStageCount", 0));
row.RxRFImpairmentChainId = string(sixgr.util.structGet(replay, "RFImpairmentChainId", ""));
row.RxRFInputWaveformSHA256 = string(sixgr.util.structGet(replay, "RFInputWaveformSHA256", ""));
row.RxRFOutputWaveformSHA256 = string(sixgr.util.structGet(replay, "RFOutputWaveformSHA256", ""));
row.RxRFExecutionStatus = string(sixgr.util.structGet(replay, "RFExecutionStatus", ""));
row.RxRFStageOrder = string(sixgr.util.structGet(replay, "RFStageOrder", ""));
row.RxRFAppliedStageCount = double(sixgr.util.structGet(replay, "RFAppliedStageCount", 0));
row.RxRFConfiguredStageCount = double(sixgr.util.structGet(replay, "RFConfiguredStageCount", 0));
row.CompositeReceiverFrontEndApplied = logical(sixgr.util.structGet(replay, "CompositeReceiverFrontEndApplied", false));
row.CompositeReceiverFrontEndStatus = string(sixgr.util.structGet(replay, "CompositeReceiverFrontEndStatus", ""));
row.RFStrictOk = logical(sixgr.util.structGet(replay, "RFStrictOk", true));
row.CFOApplied = logical(sixgr.util.structGet(replay, "CFOApplied", false));
row.PhaseNoiseConfigured = logical(sixgr.util.structGet(replay, "PhaseNoiseConfigured", false));
row.PhaseNoiseApplied = logical(sixgr.util.structGet(replay, "PhaseNoiseApplied", false));
row.PAEnabled = logical(sixgr.util.structGet(txRFReplay, "PAEnabled", false));
row.PAApplied = logical(sixgr.util.structGet(txRFReplay, "PAApplied", false));
row.PAModel = string(sixgr.util.structGet(txRFReplay, "PAModel", ""));
row.PABackoff_dB = double(sixgr.util.structGet(txRFReplay, "PABackoff_dB", NaN));
row.TimingOffsetApplied = logical(sixgr.util.structGet(replay, "TimingOffsetApplied", false));
row.ADCQuantizationApplied = logical(sixgr.util.structGet(replay, "ADCQuantizationApplied", false));
row.ADCBits = double(sixgr.util.structGet(replay, "ADCBits", NaN));
row.DACBits = double(sixgr.util.structGet(replay, "DACBits", NaN));
row.NoiseOperatingMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", ""));
row.RFImpairmentChainId = localCompositeRFChainId(row.TxRFImpairmentChainId, row.RxRFImpairmentChainId);
row.ReferenceTxPower_dBm = double(sixgr.util.structGet(replay, "ReferenceTxPower_dBm", NaN));
row.ReferenceTxPowerSource = string(sixgr.util.structGet(replay, "ReferenceTxPowerSource", ""));
row.ServingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
row.ServingRxPowerSource = string(sixgr.util.structGet(replay, "ServingRxPowerSource", ""));
row.ThermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
row.NoisePowerSource = string(sixgr.util.structGet(replay, "NoisePowerSource", ""));
row.NoiseFigure_dB = double(sixgr.util.structGet(replay, "NoiseFigure_dB", NaN));
row.NoiseBandwidth_Hz = double(sixgr.util.structGet(replay, "NoiseBandwidth_Hz", NaN));
row.PowerContextTotalTxPower_dBm = double(sixgr.util.structGet(replay, "PowerContextTotalTxPower_dBm", NaN));
row.PowerContextTxGain_dB = double(sixgr.util.structGet(replay, "PowerContextTxGain_dB", NaN));
row.PowerContextRxGain_dB = double(sixgr.util.structGet(replay, "PowerContextRxGain_dB", NaN));
row.PowerContextAdditionalLoss_dB = double(sixgr.util.structGet(replay, "PowerContextAdditionalLoss_dB", NaN));
powerContext = sixgr.util.structGet(replay, "PowerContext", ...
    sixgr.util.structGet(txInfo, "PowerContext", struct()));
row.CellTotalTxPower_dBm = double(sixgr.util.structGet(powerContext, "CellTotalTxPower_dBm", NaN));
row.EndpointPowerBudget_dBm = double(sixgr.util.structGet(powerContext, "EndpointPowerBudget_dBm", NaN));
row.ConcurrentTransmitterGrantCount = double(sixgr.util.structGet(powerContext, "ConcurrentTransmitterGrantCount", NaN));
row.GrantPowerFraction = double(sixgr.util.structGet(powerContext, "GrantPowerFraction", NaN));
row.GrantTargetTxPower_dBm = double(sixgr.util.structGet(powerContext, "GrantTargetTxPower_dBm", NaN));
row.ScheduledPowerPolicy = string(sixgr.util.structGet(powerContext, "ScheduledPowerPolicy", ""));
row.ScheduledPowerAuthority = string(sixgr.util.structGet(powerContext, "ScheduledPowerAuthority", ""));
row.SharedCellBudgetApplied = logical(sixgr.util.structGet(powerContext, "SharedCellBudgetApplied", false));
row.PowerNormalizationPolicy = string(sixgr.util.structGet(powerContext, "PowerNormalizationPolicy", ""));
row.PowerNormalizationSource = string(sixgr.util.structGet(powerContext, "PowerNormalizationSource", ""));
row.PowerNormalizationGridSource = string(sixgr.util.structGet(powerContext, "NormalizationGridSource", ""));
row.PowerNormalizationGridSubcarrierCount = double(sixgr.util.structGet(powerContext, "NormalizationGridSubcarrierCount", NaN));
row.PowerNormalizationGridActiveSymbolCount = double(sixgr.util.structGet(powerContext, "NormalizationGridActiveSymbolCount", NaN));
row.PowerNormalizationGridMeanEnergyPerRE = double(sixgr.util.structGet(powerContext, "NormalizationGridMeanEnergyPerRE", NaN));
row.FullBWPActivityFactor = double(sixgr.util.structGet(powerContext, "FullBWPActivityFactor", NaN));
row.ReferenceInputPower_dBm = double(sixgr.util.structGet(powerContext, "ReferenceInputPower_dBm", NaN));
row.ReferenceOutputPower_dBm = double(sixgr.util.structGet(powerContext, "ReferenceOutputPower_dBm", NaN));
row.ActualEmittedPower_dBm = double(sixgr.util.structGet(powerContext, "OutputTotalPower_dBm", NaN));
row.ActualEmittedPowerBackoffFromBudget_dB = double(sixgr.util.structGet(powerContext, "ActualEmittedPowerBackoffFromBudget_dB", NaN));
row.PowerClosureError_dB = double(sixgr.util.structGet(powerContext, "PowerClosureError_dB", NaN));
row.PowerConversionEquation = string(sixgr.util.structGet(powerContext, "ConversionEquation", ""));
row.AbsolutePowerReferencePlane = string(sixgr.util.structGet(replay, "AbsolutePowerReferencePlane", ""));
row.SamplePowerReferencePlane = string(sixgr.util.structGet(replay, "SamplePowerReferencePlane", ""));
row.InterferencePowerReferencePlane = string(sixgr.util.structGet(replay, "InterferencePowerReferencePlane", ""));
end

function [distance_m, delayForTiming_s, delayForReport_s, source] = localFixedSNRGeometryReporting(cfg, distance_m, delay_s, replay)
source = string(sixgr.util.structGet(replay, ...
    'RuntimeGeometrySource','unavailable_executed_link_geometry'));
delayForTiming_s = delay_s;
delayForReport_s = delay_s;
if localConfiguredSNRIsLinkAuthority(cfg)
    distance_m = NaN;
    delayForTiming_s = 0;
    delayForReport_s = NaN;
    source = "not_applicable_fixed_configured_esn0";
end
end

function value = localFixedSNRGeometryValue(cfg, value)
value = double(value);
if localConfiguredSNRIsLinkAuthority(cfg)
    value = NaN;
end
end

function tf = localConfiguredSNRIsLinkAuthority(cfg)
tf = strcmpi(string(sixgr.util.structGet( ...
    cfg, "integration.run_mode", "")), "FIXED_SNR_SWEEP") && ...
    logical(sixgr.util.structGet(cfg, ...
    "integration.configured_snr_is_link_authority", false));
end

function meta = localResolveRuntimeAntennaMeta(userMeta, metaField, antennaField)
meta = sixgr.util.structGet(userMeta, metaField, struct());
if isstruct(meta) && ~isempty(fieldnames(meta))
    return;
end
arr = sixgr.util.structGet(userMeta, antennaField, struct());
if ~(isstruct(arr) && ~isempty(fieldnames(arr)))
    meta = struct();
    return;
end
sizeVec = double(sixgr.util.structGet(arr, "Size", [NaN NaN 1]));
if numel(sizeVec) < 2
    sizeVec = [sizeVec(:).' NaN];
end
spacing = double(sixgr.util.structGet(arr, "ElementSpacing_m", [NaN NaN]));
lambda = double(sixgr.util.structGet(arr, "Lambda_m", NaN));
spacingLambda = [NaN NaN];
if isfinite(lambda) && lambda > 0 && numel(spacing) >= 2
    spacingLambda = spacing(1:2) ./ lambda;
end
meta = struct( ...
    "ArrayClass", string(localRuntimeObjectClassToken(sixgr.util.structGet(arr, "ArrayObj", []), "sixgr.rf.AntennaArrayFactory.struct")), ...
    "ElementClass", string(localRuntimeObjectClassToken(sixgr.util.structGet(arr, "ElementObj", []), "numeric_isotropic_placeholder")), ...
    "ArrayType", string(sixgr.util.structGet(arr, "Type", "")), ...
    "NumRows", double(sizeVec(1)), ...
    "NumCols", double(sizeVec(2)), ...
    "NumElements", double(sixgr.util.structGet(arr, "Nant", NaN)), ...
    "SpacingH_lambda", double(spacingLambda(1)), ...
    "SpacingV_lambda", double(spacingLambda(2)), ...
    "Polarization", string(ternaryString(double(sixgr.util.structGet(arr, "NPol", 1)) > 1, "dual", "single")), ...
    "NumPorts", double(sixgr.util.structGet(arr, "NumPorts", sixgr.util.structGet(arr, "Nant", NaN))), ...
    "HasPhasedArrayObject", logical(sixgr.util.structGet(arr, "HasPhased", false)));
end

function [distance_m, delay_s] = localResolveGeometryDelay(userMeta)
distance_m = NaN;
delay_s = NaN;
runtimeDistance = double(sixgr.util.structGet(userMeta, "RuntimeServingDistance3D_m", NaN));
runtimeDelay = double(sixgr.util.structGet(userMeta, "RuntimeServingPropagationDelay_s", NaN));
if isfinite(runtimeDistance) && isfinite(runtimeDelay)
    distance_m = runtimeDistance;
    delay_s = runtimeDelay;
    return;
end
bsPos = double(sixgr.util.structGet(userMeta, "RuntimeServingBSPosition_m", nan(1, 3)));
uePos = double(sixgr.util.structGet(userMeta, "RuntimeUEPosition_m", nan(1, 3)));
if numel(bsPos) < 3 || numel(uePos) < 3 || ~all(isfinite(bsPos(1:3))) || ~all(isfinite(uePos(1:3)))
    return;
end
distance_m = norm(bsPos(1:3) - uePos(1:3));
delay_s = distance_m / physconst("LightSpeed");
end

function [dominantDelay_s, filterDelay_s, sourceToken] = localResolveChannelDelayTerms(chState, tx, txInfo)
dominantDelay_s = 0;
filterDelay_s = 0;
sourceToken = "awgn_or_no_channel_delay";
sampleRate = localResolveSampleRate(tx, txInfo);
if ~(isstruct(chState) && logical(sixgr.util.structGet(chState, "UseFading", false)) && isfield(chState, "Obj") && ~isempty(chState.Obj))
    return;
end
pathDelays = [];
try
    chInfo = info(chState.Obj);
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
catch
    chInfo = struct();
end
if isempty(pathDelays)
    pathDelays = sixgr.util.structGet(chState.Obj, "PathDelays", []);
end
pathDelays = double(pathDelays(:));
pathDelays = pathDelays(isfinite(pathDelays) & pathDelays >= 0);
if ~isempty(pathDelays)
    dominantDelay_s = min(pathDelays);
end
if isfinite(sampleRate) && sampleRate > 0
    filterDelay_s = max(0, double(sixgr.util.structGet(chState, "ChannelTrimSamples", 0))) / sampleRate;
end
sourceToken = string(class(chState.Obj)) + ".PathDelays";
end

function toaEstimate_s = localResolveTimingEstimateToA(slotStart_s, replay, tx, txInfo)
toaEstimate_s = NaN;
if ~(isfinite(slotStart_s) && isstruct(replay) && logical(sixgr.util.structGet(replay, "TimingEstimateUsed", false)))
    return;
end
sampleRate = localResolveSampleRate(tx, txInfo);
timingEstimate = double(sixgr.util.structGet(replay, "RawTimingEstimate_samples", ...
    sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", NaN)));
if ~(isfinite(sampleRate) && sampleRate > 0 && isfinite(timingEstimate))
    return;
end
toaEstimate_s = slotStart_s + timingEstimate / sampleRate;
end

function token = localRuntimeObjectClassToken(obj, fallback)
if ~isempty(obj)
    token = char(string(class(obj)));
else
    token = char(string(fallback));
end
end

function meta = localResolveChannelRuntimeMeta(chState, cfg, userMeta)
meta = sixgr.util.structGet(chState, "Meta", struct());
if ~(isstruct(meta) && ~isempty(fieldnames(meta)))
    meta = struct();
end
meta.ChannelComplianceMode = string(sixgr.util.structGet(userMeta, "RuntimeChannelComplianceMode", ...
    sixgr.util.structGet(meta, "ChannelComplianceMode", "")));
meta.PathlossModelSource = string(sixgr.util.structGet(userMeta, "RuntimePathlossModelSource", ...
    sixgr.util.structGet(meta, "PathlossModelSource", "")));
meta.PathlossComplianceStatus = string(sixgr.util.structGet(userMeta, "RuntimePathlossComplianceStatus", ...
    sixgr.util.structGet(meta, "PathlossComplianceStatus", "")));
meta.FallbackUsedForPathloss = logical(sixgr.util.structGet(userMeta, "RuntimeFallbackUsedForPathloss", ...
    sixgr.util.structGet(meta, "FallbackUsedForPathloss", false)));
meta.O2IModelSource = string(sixgr.util.structGet(userMeta, "RuntimeO2IModelSource", ...
    sixgr.util.structGet(meta, "O2IModelSource", "")));
meta.O2IComplianceStatus = string(sixgr.util.structGet(userMeta, "RuntimeO2IComplianceStatus", ...
    sixgr.util.structGet(meta, "O2IComplianceStatus", "")));
meta.O2IComplianceReason = string(sixgr.util.structGet(userMeta, "RuntimeO2IComplianceReason", ...
    sixgr.util.structGet(meta, "O2IComplianceReason", "")));
meta.LOSProbabilitySource = string(sixgr.util.structGet(userMeta, "RuntimeLOSProbabilitySource", ...
    sixgr.util.structGet(meta, "LOSProbabilitySource", "")));
meta.LOSComplianceStatus = string(sixgr.util.structGet(userMeta, "RuntimeLOSComplianceStatus", ...
    sixgr.util.structGet(meta, "LOSComplianceStatus", "")));
meta.LOSComplianceReason = string(sixgr.util.structGet(userMeta, "RuntimeLOSComplianceReason", ...
    sixgr.util.structGet(meta, "LOSComplianceReason", "")));
fallbackModel = string(sixgr.util.structGet(userMeta, "RuntimeChannelArrayModel", localResolveChannelArrayModel(cfg)));
meta = localNormalizeChannelRuntimeMeta(meta, fallbackModel);
end

function meta = localNormalizeChannelRuntimeMeta(metaIn, fallbackModel)
meta = struct();
meta.ChannelArrayModel = string(sixgr.util.structGet(metaIn, "ChannelArrayModel", fallbackModel));
meta.ChannelObjectSource = string(sixgr.util.structGet(metaIn, "ChannelObjectSource", ""));
meta.ChannelObjectClass = string(sixgr.util.structGet(metaIn, "ChannelObjectClass", ""));
meta.ChannelArrayHandlingStatus = string(sixgr.util.structGet(metaIn, "ChannelArrayHandlingStatus", ""));
meta.ChannelArrayHandlingBlocker = string(sixgr.util.structGet(metaIn, "ChannelArrayHandlingBlocker", ""));
meta.ChannelGeometryCouplingLevel = string(sixgr.util.structGet(metaIn, "ChannelGeometryCouplingLevel", ""));
meta.GeometryAdapterType = string(sixgr.util.structGet(metaIn, "GeometryAdapterType", ""));
meta.GeometryAdapterSource = string(sixgr.util.structGet(metaIn, "GeometryAdapterSource", ""));
meta.GeometryAdapterLimitation = string(sixgr.util.structGet(metaIn, "GeometryAdapterLimitation", ""));
meta.GeometryAdapterPortMapping = string(sixgr.util.structGet(metaIn, "GeometryAdapterPortMapping", ""));
meta.ChannelUsesCountOnlyAntennaModel = logical(sixgr.util.structGet(metaIn, "ChannelUsesCountOnlyAntennaModel", ...
    any(strcmpi(strtrim(string(meta.ChannelArrayModel)), ["nrtdl_count_only_fading_channel", "awgn_no_array_channel"]))));
meta.ChannelUsesSameRuntimeAntennaAssumptions = logical(sixgr.util.structGet(metaIn, "ChannelUsesSameRuntimeAntennaAssumptions", false));
meta.TransmitElementPatternApplied = logical(sixgr.util.structGet(metaIn, "TransmitElementPatternApplied", false));
meta.ReceiveElementPatternApplied = logical(sixgr.util.structGet(metaIn, "ReceiveElementPatternApplied", false));
meta.TransmitElementPatternSource = string(sixgr.util.structGet(metaIn, "TransmitElementPatternSource", ""));
meta.ReceiveElementPatternSource = string(sixgr.util.structGet(metaIn, "ReceiveElementPatternSource", ""));
meta.ChannelComplianceMode = string(sixgr.util.structGet(metaIn, "ChannelComplianceMode", ""));
meta.PathlossModelSource = string(sixgr.util.structGet(metaIn, "PathlossModelSource", ""));
meta.PathlossComplianceStatus = string(sixgr.util.structGet(metaIn, "PathlossComplianceStatus", ""));
meta.FallbackUsedForPathloss = logical(sixgr.util.structGet(metaIn, "FallbackUsedForPathloss", false));
meta.O2IModelSource = string(sixgr.util.structGet(metaIn, "O2IModelSource", ""));
meta.O2IComplianceStatus = string(sixgr.util.structGet(metaIn, "O2IComplianceStatus", ""));
meta.O2IComplianceReason = string(sixgr.util.structGet(metaIn, "O2IComplianceReason", ""));
meta.LOSProbabilitySource = string(sixgr.util.structGet(metaIn, "LOSProbabilitySource", ""));
meta.LOSComplianceStatus = string(sixgr.util.structGet(metaIn, "LOSComplianceStatus", ""));
meta.LOSComplianceReason = string(sixgr.util.structGet(metaIn, "LOSComplianceReason", ""));
end

function meta = localResolveInterferenceChannelRuntimeMeta(replay, channelMeta)
meta = struct( ...
    "ChannelObjectSource", string(sixgr.util.structGet(replay, "InterferenceChannelObjectSource", "")), ...
    "ChannelObjectClass", string(sixgr.util.structGet(replay, "InterferenceChannelObjectClass", "")), ...
    "ChannelArrayHandlingStatus", string(sixgr.util.structGet(replay, "InterferenceChannelArrayHandlingStatus", "")), ...
    "ChannelArrayHandlingBlocker", string(sixgr.util.structGet(replay, "InterferenceChannelArrayHandlingBlocker", "")), ...
    "ChannelUsesSameRuntimeAntennaAssumptions", logical(sixgr.util.structGet(replay, "InterferenceUsesSameRuntimeAntennaAssumptions", false)), ...
    "InterferencePathUsesSameArrayAssumptions", false);
statusSet = localNormalizedTokenSet(meta.ChannelArrayHandlingStatus);
channelStatus = localNormalizedTokenSet(string(sixgr.util.structGet(channelMeta, "ChannelArrayHandlingStatus", "")));
if ~isempty(statusSet) && ~isempty(channelStatus) && isequal(statusSet, channelStatus)
    meta.InterferencePathUsesSameArrayAssumptions = true;
end
end

function values = localNormalizedTokenSet(value)
values = string(value);
values = split(join(values(:), ";"), ";");
values = strip(values);
values = values(strlength(values) > 0);
if isempty(values)
    return;
end
values = unique(values, "stable");
end

function mode = localResolveChannelArrayModel(cfg)
model = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
if model == "TDL"
    mode = "nrtdl_count_only_fading_channel";
elseif model == "CDL"
    mode = "nrcdl_config_array_shape_channel";
elseif any(model == ["AWGN", "NONE", "OFF", ""])
    mode = "awgn_no_array_channel";
else
    mode = "other_channel_model";
end
end

function row = localEmptyRuntimeEvidenceRow()
row = struct( ...
    "Direction", "", ...
    "GrantContextId", "", ...
    "BSAntennaArrayClass", "", ...
    "BSAntennaElementClass", "", ...
    "BSAntennaArrayType", "", ...
    "BSAntennaRows", NaN, ...
    "BSAntennaCols", NaN, ...
    "BSAntennaElements", NaN, ...
    "BSAntennaSpacingH_lambda", NaN, ...
    "BSAntennaSpacingV_lambda", NaN, ...
    "BSAntennaPolarization", "", ...
    "BSAntennaAzimuth_deg", NaN, ...
    "BSAntennaNumPorts", NaN, ...
    "BSAntennaHasPhasedArrayObject", false, ...
    "UEAntennaArrayClass", "", ...
    "UEAntennaElementClass", "", ...
    "UEAntennaArrayType", "", ...
    "UEAntennaRows", NaN, ...
    "UEAntennaCols", NaN, ...
    "UEAntennaElements", NaN, ...
    "UEAntennaSpacingH_lambda", NaN, ...
    "UEAntennaSpacingV_lambda", NaN, ...
    "UEAntennaPolarization", "", ...
    "UEAntennaHeading_deg", NaN, ...
    "UEAntennaNumPorts", NaN, ...
    "UEAntennaHasPhasedArrayObject", false, ...
    "AntennaConfigSource", "", ...
    "RuntimeAntennaObjectSource", "", ...
    "AntennaRuntimeObjectCreated", false, ...
    "ChannelArrayModel", "", ...
    "ChannelObjectSource", "", ...
    "ChannelObjectClass", "", ...
    "ChannelArrayHandlingStatus", "", ...
    "ChannelArrayHandlingBlocker", "", ...
    "ChannelGeometryCouplingLevel", "", ...
    "GeometryAdapterType", "", ...
    "GeometryAdapterSource", "", ...
    "GeometryAdapterLimitation", "", ...
    "GeometryAdapterPortMapping", "", ...
    "ChannelUsesCountOnlyAntennaModel", false, ...
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
    "TransmitElementPatternApplied", false, ...
    "ReceiveElementPatternApplied", false, ...
    "TransmitElementPatternSource", "", ...
    "ReceiveElementPatternSource", "", ...
    "ChannelComplianceMode", "", ...
    "PathlossModelSource", "", ...
    "PathlossComplianceStatus", "", ...
    "FallbackUsedForPathloss", false, ...
    "O2IModelSource", "", ...
    "O2IComplianceStatus", "", ...
    "O2IComplianceReason", "", ...
    "LOSProbabilitySource", "", ...
    "LOSComplianceStatus", "", ...
    "LOSComplianceReason", "", ...
    "InterferenceChannelObjectSource", "", ...
    "InterferenceChannelObjectClass", "", ...
    "InterferenceChannelArrayHandlingStatus", "", ...
    "InterferenceChannelArrayHandlingBlocker", "", ...
    "InterferenceUsesSameRuntimeAntennaAssumptions", false, ...
    "InterferencePathUsesSameArrayAssumptions", false, ...
    "PropagationDistance_m", NaN, ...
    "RuntimeGeometryDistance2D_m",NaN,"RuntimeGeometryDistance3D_m",NaN, ...
    "RuntimeGeometrySource","unavailable_executed_link_geometry", ...
    "GeometricPropagationDelay_s", NaN, ...
    "DominantPathDelay_s", NaN, ...
    "ChannelFilterDelay_s", NaN, ...
    "PropagationDelay_s", NaN, ...
    "ToD_s", NaN, ...
    "ToA_s", NaN, ...
    "ToAEstimate_s", NaN, ...
    "ToDSource", "", ...
    "ToASource", "", ...
    "ToAEstimateSource", "", ...
    "ChannelDelaySource", "", ...
    "AntennaGeometrySource", "", ...
    "RuntimeTraceSource", "", ...
    "AntennaEvidenceSource", "", ...
    "SameFlowEvidenceSource", "", ...
    "ChannelRealizationId", "", ...
    "RuntimeChannelStateKey", "", ...
    "RuntimeChannelLinkKey", "", ...
    "RuntimeChannelSeed", NaN, ...
    "RuntimeChannelReciprocityExact", false, ...
    "RuntimeChannelReciprocityDirection", "", ...
    "RuntimeChannelReciprocitySource", "", ...
    "RuntimeChannelReciprocityApproximationMode", "", ...
    "RuntimeChannelTransmitAndReceiveSwapped", false, ...
    "RuntimeChannelAngleEvidenceAvailable", false, ...
    "RuntimeChannelAngleEvidenceSource", "", ...
    "RuntimeChannelAnglePathCount", 0, ...
    "RuntimeChannelCanonicalInputSamples", NaN, ...
    "RuntimeChannelAlignmentLookaheadSamples", NaN, ...
    "RuntimeChannelAlignmentLookaheadExecutedOnFork", false, ...
    "RuntimeChannelObjectClockExact", false, ...
    "RuntimeChannelResetCount", NaN, ...
    "RuntimeChannelStartSample", NaN, ...
    "RuntimeChannelEndSample", NaN, ...
    "RuntimeChannelInputWaveformSHA256", "", ...
    "RuntimeChannelOutputWaveformSHA256", "", ...
    "RuntimeChannelPathGainsSHA256", "", ...
    "RuntimeChannelPathGainElementCount", 0, ...
    "RuntimeChannelPathGainDimensions", "", ...
    "ChannelFadingObjectClass", "", ...
    "TxRFImpairmentChainId", "", ...
    "TxRFInputWaveformSHA256", "", ...
    "TxRFOutputWaveformSHA256", "", ...
    "TxRFExecutionStatus", "", ...
    "TxRFStageOrder", "", ...
    "TxRFAppliedStageCount", 0, ...
    "TxRFConfiguredStageCount", 0, ...
    "RxRFImpairmentChainId", "", ...
    "RxRFInputWaveformSHA256", "", ...
    "RxRFOutputWaveformSHA256", "", ...
    "RxRFExecutionStatus", "", ...
    "RxRFStageOrder", "", ...
    "RxRFAppliedStageCount", 0, ...
    "RxRFConfiguredStageCount", 0, ...
    "CompositeReceiverFrontEndApplied", false, ...
    "CompositeReceiverFrontEndStatus", "", ...
    "RFStrictOk", false, ...
    "CFOApplied", false, ...
    "PhaseNoiseConfigured", false, ...
    "PhaseNoiseApplied", false, ...
    "PAEnabled", false, ...
    "PAApplied", false, ...
    "PAModel", "", ...
    "PABackoff_dB", NaN, ...
    "TimingOffsetApplied", false, ...
    "ADCQuantizationApplied", false, ...
    "ADCBits", NaN, ...
    "DACBits", NaN, ...
    "NoiseOperatingMode", "", ...
    "RFImpairmentChainId", "", ...
    "ReferenceTxPower_dBm", NaN, "ReferenceTxPowerSource", "", ...
    "ServingRxPower_dBm", NaN, "ServingRxPowerSource", "", ...
    "ThermalNoisePower_dBm", NaN, "NoisePowerSource", "", ...
    "NoiseFigure_dB", NaN, "NoiseBandwidth_Hz", NaN, ...
    "PowerContextTotalTxPower_dBm", NaN, "PowerContextTxGain_dB", NaN, ...
    "PowerContextRxGain_dB", NaN, "PowerContextAdditionalLoss_dB", NaN, ...
    "CellTotalTxPower_dBm", NaN, "EndpointPowerBudget_dBm", NaN, ...
    "ConcurrentTransmitterGrantCount", NaN, "GrantPowerFraction", NaN, ...
    "GrantTargetTxPower_dBm", NaN, "ScheduledPowerPolicy", "", ...
    "ScheduledPowerAuthority", "", "SharedCellBudgetApplied", false, ...
    "PowerNormalizationPolicy", "", "PowerNormalizationSource", "", ...
    "PowerNormalizationGridSource", "", ...
    "PowerNormalizationGridSubcarrierCount", NaN, ...
    "PowerNormalizationGridActiveSymbolCount", NaN, ...
    "PowerNormalizationGridMeanEnergyPerRE", NaN, ...
    "FullBWPActivityFactor", NaN, "ReferenceInputPower_dBm", NaN, ...
    "ReferenceOutputPower_dBm", NaN, "ActualEmittedPower_dBm", NaN, ...
    "ActualEmittedPowerBackoffFromBudget_dB", NaN, ...
    "PowerClosureError_dB", NaN, "PowerConversionEquation", "", ...
    "AbsolutePowerReferencePlane", "", "SamplePowerReferencePlane", "", ...
    "InterferencePowerReferencePlane", "");
end

function id = localCompositeRFChainId(txId, rxId)
txId = strtrim(string(txId));
rxId = strtrim(string(rxId));
if strlength(txId) == 0 && strlength(rxId) == 0
    id = "";
    return;
end
digest = lower(string(sixgr.channel.hashChannelRFConfig(struct( ...
    "TxRFImpairmentChainId", txId, "RxRFImpairmentChainId", rxId))));
id = "rfpath_" + extractBefore(digest, 17);
end

function status = localRFExecutionStatus(replay, endpoint)
if ~(isstruct(replay) && ~isempty(fieldnames(replay)))
    status = "not_configured";
    return;
end
applied = double(sixgr.util.structGet(replay, "RFAppliedStageCount", 0));
configured = double(sixgr.util.structGet(replay, "RFConfiguredStageCount", 0));
if applied > 0
    status = "applied_ordered_" + string(endpoint) + "_rf_chain";
elseif configured > 0
    status = "configured_identity_or_zero_stage";
else
    status = "disabled_identity";
end
end

function T = localEnsureRuntimeEvidenceColumns(T, nRows)
if nargin < 2
    nRows = 0;
end
template = localEmptyRuntimeEvidenceRow();
names = fieldnames(template);
for i = 1:numel(names)
    name = names{i};
    value = template.(name);
    if isnumeric(value)
        T.(name) = nan(nRows, 1);
    elseif islogical(value)
        T.(name) = false(nRows, 1);
    else
        T.(name) = strings(nRows, 1);
    end
end
end

function out = ternaryString(tf, whenTrue, whenFalse)
if logical(tf)
    out = char(string(whenTrue));
else
    out = char(string(whenFalse));
end
end

function state = localPrepareRuntimeChannelState(state, cfg, tx, txInfo, direction)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
if ~(isstruct(state) && isfield(state, "ContractVersion"))
    state = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, direction, ...
        "UEIndex", double(sixgr.util.structGet(userMeta, "RuntimeUEIndex", sixgr.util.structGet(userMeta, "UEIndex", 1))), ...
        "ServingCell", double(sixgr.util.structGet(userMeta, "RuntimeServingCell", 1)));
end

numTx = max(1, size(tx.Waveform, 2));
runtimeNumTx = localResolveRuntimeTxPortCapacity(userMeta, cfg, numTx);
numRx = localResolveULNumRxAnt(cfg, numTx);
[txRuntimeAntenna, txRuntimeMeta] = localRuntimeSignalAntennaView(userMeta, ...
    "RuntimeUEAntenna", "RuntimeUEAntennaMeta", numTx, ...
    "pusch_runtime_waveform_port_count");
rxRuntimeAntenna = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
rxRuntimeMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
state = sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state, cfg, tx.Waveform, txInfo, ...
    "NumTxAnt", runtimeNumTx, ...
    "NumRxAnt", numRx, ...
    "TransmitAntennaRuntime", txRuntimeAntenna, ...
    "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
    "TransmitAntennaMeta", txRuntimeMeta, ...
    "ReceiveAntennaMeta", rxRuntimeMeta);
slotStart_s = double(sixgr.util.structGet(userMeta, "RuntimeSlotStartTime_s", NaN));
if isfinite(slotStart_s) && slotStart_s >= 0
    state = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(state, slotStart_s, runtimeNumTx, tx.Waveform);
end
end

function localAssertULHybridTransmitElementDomain(cfg, tx, txInfo)
hybridRequired = logical(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.hybridBeamformingEnabled", ...
    sixgr.util.structGet(cfg, "mimo.hybrid_beamforming_flag", false)));
if ~hybridRequired
    return;
end
expectedElements = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", NaN), ...
    sixgr.util.structGet(cfg, "antenna.ue.numElements", NaN), ...
    sixgr.util.structGet(cfg, "channel.ul.nTxAnt", NaN), ...
    sixgr.util.structGet(cfg, "phy.ul.nTxAnt", NaN));
actualColumns = double(size(sixgr.util.structGet(tx, "Waveform", []), 2));
declaredPhysical = double(sixgr.util.structGet(txInfo, ...
    "UEPhysicalTxAntennas", NaN));
prec = sixgr.util.structGet(txInfo, "Precoding", struct());
elementDomainApplied = logical(sixgr.util.structGet(prec, ...
    "HybridElementDomainApplied", false));
waveformDomain = lower(strtrim(string(sixgr.util.structGet(prec, ...
    "WaveformDomain", ""))));
if ~(isfinite(expectedElements) && expectedElements >= 1 && ...
        actualColumns == round(expectedElements) && ...
        declaredPhysical == round(expectedElements) && ...
        elementDomainApplied && waveformDomain == "element")
    error("sixgr:link:ULHybridElementDomainExecutionMismatch", ...
        ['Hybrid PUSCH requires %d physical UE element-domain waveform columns; ' ...
        'the transmitter emitted %d, declared %g physical antennas, domain=%s, applied=%d.'], ...
        round(double(expectedElements)), round(actualColumns), declaredPhysical, ...
        char(waveformDomain), double(elementDomainApplied));
end
end

function localAssertULHybridReceiveElementDomain(cfg, rxWave)
hybridRequired = logical(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.hybridBeamformingEnabled", ...
    sixgr.util.structGet(cfg, "mimo.hybrid_beamforming_flag", false)));
if ~hybridRequired
    return;
end
expectedBranches = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", NaN), ...
    sixgr.util.structGet(cfg, "antenna.bs.numElements", NaN), ...
    sixgr.util.structGet(cfg, "channel.ul.nRxAnt", NaN), ...
    sixgr.util.structGet(cfg, "phy.ul.nRxAnt", NaN));
actualBranches = double(size(rxWave, 2));
if ~(isfinite(expectedBranches) && expectedBranches >= 1 && ...
        actualBranches == round(expectedBranches))
    error("sixgr:link:ULPhysicalReceiveBranchMismatch", ...
        ['Hybrid PUSCH reception requires %d physical gNB receive branches; ' ...
        'the channel produced %d.'], ...
        round(double(expectedBranches)), round(actualBranches));
end
end

function numTx = localResolveRuntimeTxPortCapacity(userMeta, cfg, activePortCount)
activePortCount = max(1, round(double(activePortCount)));
numTx = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumLogicalPorts", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumLogicalPorts", []), ...
    sixgr.util.structGet(cfg, "phy.maxULLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.maxLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.numPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.nPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.numLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", []), ...
    activePortCount);
if isfinite(numTx) && numTx > localMaxNRLogicalPUSCHPorts()
    numTx = activePortCount;
end
numTx = max(activePortCount, round(double(numTx)));
end

function nPorts = localMaxNRLogicalPUSCHPorts()
nPorts = 4;
end

function [ant, meta] = localRuntimeSignalAntennaView(userMeta, antField, metaField, numPorts, sourceToken)
ant = sixgr.util.structGet(userMeta, antField, struct());
meta = sixgr.util.structGet(userMeta, metaField, struct());
if nargin < 4 || ~(isnumeric(numPorts) && isscalar(numPorts) && isfinite(numPorts) && numPorts >= 1)
    return;
end
if nargin < 5 || strlength(strtrim(string(sourceToken))) == 0
    sourceToken = "pusch_runtime_waveform_port_count";
end
[ant, meta] = sixgr.rf.AntennaArrayFactory.logicalPortView(ant, meta, ...
    max(1, round(double(numPorts))), sourceToken);
end

function state = localInitChannelState(cfg, tx, txInfo, snr_dB, trialSeed)
if nargin < 4
    snr_dB = NaN;
end
if nargin < 5
    trialSeed = NaN;
end
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0, ...
    "WarmupSamples", 0, ...
    "Meta", localNormalizeChannelRuntimeMeta(struct(), localResolveChannelArrayModel(cfg)));

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
    return;
end

cfgCh = cfg;
dopp = double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0))));
cfgCh.channel.doppler_Hz = max(0, dopp);

if startsWith(modelRaw, "TDL")
    cfgCh.channel.model = "TDL";
    if modelRaw ~= "TDL"
        cfgCh.channel.tdlProfile = char(modelRaw);
    end
elseif startsWith(modelRaw, "CDL")
    cfgCh.channel.model = "CDL";
    if modelRaw ~= "CDL"
        cfgCh.channel.cdlProfile = char(modelRaw);
    end
else
    cfgCh.channel.model = char(modelRaw);
end

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(tx.Waveform, 2));
numRx = localResolveULNumRxAnt(cfg, numTx);
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
[txRuntimeAntenna, txRuntimeMeta] = localRuntimeSignalAntennaView(userMeta, ...
    "RuntimeUEAntenna", "RuntimeUEAntennaMeta", numTx, ...
    "pusch_runtime_waveform_port_count");
rxRuntimeAntenna = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
rxRuntimeMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", localChannelSeed(cfg, snr_dB, trialSeed), ...
    "TransmitAntennaRuntime", txRuntimeAntenna, ...
    "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
    "TransmitAntennaMeta", txRuntimeMeta, ...
    "ReceiveAntennaMeta", rxRuntimeMeta);
state.Meta = localNormalizeChannelRuntimeMeta(sixgr.util.structGet(ch, "Meta", struct()), localResolveChannelArrayModel(cfgCh));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
    state.WarmupSamples = max(256, padSamples);
    try
        reset(state.Obj);
    catch
    end
    try
        warmup = zeros(state.WarmupSamples, numTx, 'like', tx.Waveform);
        try
            state.Obj(warmup);
        catch
            [~, ~] = state.Obj(warmup);
        end
    catch
        state.WarmupSamples = 0;
    end
end
end

function numRx = localResolveULNumRxAnt(cfg, fallback)
numRx = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", fallback));
end

function count = localConfiguredULAntennaCount(cfg, role, fallback)
if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2
    role = "tx";
end
if nargin < 3 || ~(isnumeric(fallback) && isscalar(fallback) && isfinite(fallback) && fallback >= 1)
    fallback = 1;
end
role = upper(string(role));
if role == "RX"
    count = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", fallback);
else
    count = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", fallback);
end
count = max(1, round(double(count)));
end

function [waveOut, pc, cfgOut, stateOut] = localApplyPUSCHPowerControl(waveIn, cfg, tx, grant, stateIn)
[waveOut, pc, cfgOut, stateOut] = ...
    sixgr.link.bindPUSCHPowerControlContext(waveIn, cfg, tx, grant, stateIn);
end

function [y, replay, state] = localApplyChannelAndAwgn(x, snr_dB, state, cfg, tx, txInfo, interferenceBundle, captureDiagnosticPathGains)
if nargin < 8
    captureDiagnosticPathGains = false;
end
% Channel state (state.Obj) is NOT reset between calls.
% Temporal correlation is preserved per TR 38.901 7.7.3.
% The channel was reset once during localInitChannelState.
y = x;
replay = struct( ...
    "RawWaveform", x, ...
    "CorrectedWaveform", x, ...
    "InjectedCFO_Hz", NaN, ...
    "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "ResidualCFO_PostCorrection_Hz", NaN, ...
    "InjectedTimingOffset_samples", NaN, ...
    "RawTimingEstimate_samples", NaN, ...
    "AppliedTimingCorrection_samples", NaN, ...
    "EstimatedTimingOffset_PreCorrection_samples", NaN, ...
    "ResidualTimingError_PostCorrection_samples", NaN, ...
    "TimingEstimateApplicationPolicy", "", ...
    "TimingEstimateStatus", "", ...
    "TimingEstimateWasClipped", false, ...
    "SampleRate_Hz", localResolveSampleRate(tx, txInfo), ...
    "CFOCorrectionApplied", false, ...
    "InjectedNoiseVariance", NaN, ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", NaN, ...
    "AppliedLargeScaleLoss_dB", 0, ...
    "AppliedLargeScaleGain_dB", 0, ...
    "AppliedBasePathloss_dB", NaN, ...
    "AppliedPathloss_dB", NaN, ...
    "AppliedShadowFading_dB", NaN, ...
    "AppliedO2I_dB", NaN, ...
    "AppliedLargeScaleGainSource", "none", ...
    "ChannelComplianceMode", "", ...
    "PathlossModelSource", "", ...
    "PathlossComplianceStatus", "", ...
    "FallbackUsedForPathloss", false, ...
    "O2IModelSource", "", ...
    "O2IComplianceStatus", "", ...
    "O2IComplianceReason", "", ...
    "LOSProbabilitySource", "", ...
    "LOSComplianceStatus", "", ...
    "LOSComplianceReason", "", ...
    "ServingRSRP_dBm", NaN, ...
    "ServingRSRPSource", "", ...
    "LargeScaleSINR_dB", NaN, ...
    "LargeScaleSINRSource", "", ...
    "InterferenceMode", char(localResolveInterferenceMode(cfg)), ...
    "InterferenceContributorCount", 0, ...
    "InterferenceAggregatedRxPower_dBm", NaN, ...
    "InterferencePowerSource", "", ...
    "FullInterfererChannelTruthUsed", false, ...
    "InterferenceChannelObjectSource", "", ...
    "InterferenceChannelObjectClass", "", ...
    "InterferenceChannelArrayHandlingStatus", "", ...
    "InterferenceChannelArrayHandlingBlocker", "", ...
    "InterferenceUsesSameRuntimeAntennaAssumptions", false, ...
    "ChannelFadingApplied", false, ...
    "ChannelFadingExecutionStatus", "not_requested", ...
    "ChannelFadingObjectClass", "", ...
    "ChannelPathGainsAvailable", false);
if isstruct(state) && isfield(state, "ContractVersion")
    if logical(captureDiagnosticPathGains)
        [y, channelReplay, state] = ...
            sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
            state, x, "CapturePathGains", true);
    else
        % Keep the factory-owned first-executed-waveform capture active for
        % primary UL provenance. An explicit false would suppress the exact
        % fading tensor even though the waveform traversed the channel.
        [y, channelReplay, state] = ...
            sixgr.channel.ChannelFactory.applyRuntimeChannelState(state, x);
    end
    channelFields = fieldnames(channelReplay);
    for ci = 1:numel(channelFields)
        replay.(channelFields{ci}) = channelReplay.(channelFields{ci});
    end
elseif isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    replay.ChannelFadingExecutionStatus = "attempted";
    replay.ChannelFadingObjectClass = class(state.Obj);
    xIn = x;
    padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
    trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
    if padSamples > 0
        xIn = [x; zeros(padSamples, size(x,2), 'like', x)];
    end
    try
        [yRaw, pathGains] = state.Obj(xIn);
    catch
        yRaw = state.Obj(xIn);
        pathGains = [];
    end
    replay.ChannelFadingApplied = true;
    replay.ChannelFadingExecutionStatus = "applied_runtime_channel_object";
    replay.ChannelPathGainsAvailable = ~isempty(pathGains);
    if trimSamples > 0 && size(yRaw,1) >= (trimSamples + size(x,1))
        y = yRaw(1+trimSamples:trimSamples+size(x,1), :);
    else
        y = yRaw;
        if size(y,1) > size(x,1)
            y = y(1:size(x,1), :);
        elseif size(y,1) < size(x,1)
            y(end+1:size(x,1), :) = cast(0, 'like', y); %#ok<AGROW>
        end
    end
end
sampleRateHz = localResolveSampleRate(tx, txInfo);
diagnosticSampleLimit = double(sixgr.util.structGet( ...
    cfg, "outputs.phySignalDiagnosticWaveformSamples", 1024));
if ~(isscalar(diagnosticSampleLimit) && isfinite(diagnosticSampleLimit))
    diagnosticSampleLimit = 1024;
end
diagnosticSamples = min(size(y,1), ...
    max(64, min(4096, round(diagnosticSampleLimit))));
if diagnosticSamples > 0
    replay.PostChannelWaveformPreview = y(1:diagnosticSamples,:);
    replay.PostChannelWaveformSHA256 = ...
        sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(y);
end
cfgReplay = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz, ...
    "ApplyRFChain", false);
impairFields = fieldnames(impairmentReplay);
for fi = 1:numel(impairFields)
    replay.(impairFields{fi}) = impairmentReplay.(impairFields{fi});
end
appliedSNR = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if ~(isscalar(appliedSNR) && isfinite(appliedSNR)) && noiseMode ~= "receiver_noise_figure_thermal_noise"
    replay.AppliedAWGNSNR_dB = double(snr_dB);
end
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
desiredWaveform = y;
[interferenceWaveform, interferenceMeta] = sixgr.link.synthesizeInterferenceWaveform("UL", desiredWaveform, replay, interferenceBundle);
interferenceWaveformVariance = NaN;
if ~isempty(interferenceWaveform)
    interferenceWaveformVariance = localUsefulOFDMReferencePower(interferenceWaveform, txInfo);
    y = y + cast(interferenceWaveform, "like", y);
end
replay.InterferenceWaveformVariance = double(interferenceWaveformVariance);
replay.InterferenceMode = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterferenceMode", replay.InterferenceMode));
replay.InterferenceContributorCount = double(sixgr.util.structGet(interferenceMeta, "Contributors", 0));
replay.InterferenceAggregatedRxPower_dBm = double(sixgr.util.structGet(interferenceMeta, "AggregatedRxPower_dBm", NaN));
replay.InterferencePowerSource = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "PowerSource", ""));
replay.InterferencePowerReferencePlane = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterferencePowerReferencePlane", ""));
replay.FullInterfererChannelTruthUsed = logical(sixgr.util.structGet(interferenceMeta, "FullPerLinkChannelTruthUsed", false));
replay.InterferenceChannelObjectSource = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "ChannelObjectSource", ""));
replay.InterferenceChannelObjectClass = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "ChannelObjectClass", ""));
replay.InterferenceChannelArrayHandlingStatus = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "ChannelArrayHandlingStatus", ""));
replay.InterferenceChannelArrayHandlingBlocker = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "ChannelArrayHandlingBlocker", ""));
replay.InterferenceUsesSameRuntimeAntennaAssumptions = logical(sixgr.util.structGet(interferenceMeta, "ChannelUsesSameRuntimeAntennaAssumptions", false));
replay.InterfererBeamformingAppliedCount = double(sixgr.util.structGet(interferenceMeta, "InterfererBeamformingAppliedCount", 0));
replay.InterfererExplicitBeamWeightCount = double(sixgr.util.structGet(interferenceMeta, "InterfererExplicitBeamWeightCount", 0));
replay.InterfererTransformPrecodingCount = double(sixgr.util.structGet(interferenceMeta, "InterfererTransformPrecodingCount", 0));
replay.InterfererPrecoderSourceSet = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterfererPrecoderSourceSet", ""));
replay.InterfererPrecodingModeSet = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterfererPrecodingModeSet", ""));
replay.InterfererBeamIndexSetSummary = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterfererBeamIndexSetSummary", ""));
replay.InterferenceContributionTensorAvailable = logical(sixgr.util.structGet(interferenceMeta, "ContributionTensorAvailable", false));
replay.InterferenceContributionSourceIdSet = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "ContributionSourceIdSet", ""));
replay.InterferenceSampleExactSuperpositionOk = logical(sixgr.util.structGet(interferenceMeta, "SampleExactSuperpositionOk", true));
replay.InterferenceSampleExactSuperpositionError = double(sixgr.util.structGet(interferenceMeta, "SampleExactSuperpositionError", 0));
replay.InterferenceCovarianceAvailableFromContributions = logical(sixgr.util.structGet(interferenceMeta, "InterferenceCovarianceAvailable", false));
replay.InterferenceCovarianceSourceFromContributions = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterferenceCovarianceSource", ""));
replay.InterferenceCovarianceStatusFromContributions = localSafeCharToken(sixgr.util.structGet(interferenceMeta, "InterferenceCovarianceStatus", ""));
if logical(sixgr.util.structGet(interferenceMeta, "ContributionTensorAvailable", false))
    replay.InterferenceContributionTensor = sixgr.util.structGet(interferenceMeta, "ContributionTensor", []);
end
if logical(sixgr.util.structGet(interferenceMeta, "InterferenceCovarianceAvailable", false))
    replay.InterferenceCovariance = sixgr.util.structGet(interferenceMeta, "InterferenceCovariance", []);
end
replay.InterferenceTxRegenerationUsed = logical(sixgr.util.structGet(interferenceMeta, "TxRegenerationUsed", false));
replay.InterferencePostChannelNormalizationApplied = logical(sixgr.util.structGet(interferenceMeta, "PostChannelNormalizationApplied", false));
replay.InterferenceRandomPhaseApplied = logical(sixgr.util.structGet(interferenceMeta, "RandomPhaseApplied", false));
if strlength(strtrim(string(replay.InterferencePowerSource))) == 0 && replay.InterferenceContributorCount > 0
    replay.InterferencePowerSource = "sample_domain_interference_sum";
end
[y, replay.InjectedNoiseVariance, noiseInfo] = localAddAwgn( ...
    y, replay, desiredWaveform, txInfo, ...
    sixgr.util.structGet(tx, "Carrier", []), ...
    sixgr.util.structGet(tx, "PUSCHIndices", []));
noiseFields = fieldnames(noiseInfo);
for ni = 1:numel(noiseFields)
    replay.(noiseFields{ni}) = noiseInfo.(noiseFields{ni});
end
[y, replay] = sixgr.link.applyCompositeReceiverFrontEnd(y, cfgReplay, sampleRateHz, replay, ...
    "Direction", "UL");
replay = sixgr.link.applyCompositeFrontEndVarianceReplay(replay);
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
end

function replay = localFinalizeImpairmentReplay(replay, cfg, rx, tx, txInfo, useIdealTimingSync)
if nargin < 1 || ~isstruct(replay)
    replay = struct();
end
replay.SampleRate_Hz = localResolveSampleRate(tx, txInfo);
replay.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", localResolveInjectedCFOHz(cfg)));
replay.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", localResolveInjectedTimingOffsetSamples(cfg)));
timingTruth = double(sixgr.util.structGet(replay, ...
    "TrueReceiverTimingOffset_samples", replay.InjectedTimingOffset_samples));
replay.EstimatedCFO_PreCorrection_Hz = NaN;
replay.CFOCorrectionApplied = false;
replay.ResidualCFO_PostCorrection_Hz = NaN;
replay.EstimatedCFO_Hz = NaN;
replay.CFOEstimateAvailability = "missing";
replay.UseIdealTimingSync = logical(useIdealTimingSync);
syncState = sixgr.util.structGet(rx, "SynchronizationState", struct());

estimatedCFO = double(sixgr.util.structGet(rx, "EstimatedCFO_Hz", NaN));
cfoCorrectionApplied = logical(sixgr.util.structGet(rx, "CFOCorrectionApplied", false));
if cfoCorrectionApplied && isfinite(estimatedCFO)
    replay.EstimatedCFO_PreCorrection_Hz = estimatedCFO;
    replay.EstimatedCFO_Hz = estimatedCFO;
    replay.CFOCorrectionApplied = true;
    replay.CFOEstimateAvailability = "available";
    if isfinite(replay.InjectedCFO_Hz)
        replay.ResidualCFO_PostCorrection_Hz = double(replay.InjectedCFO_Hz) - estimatedCFO;
    else
        replay.ResidualCFO_PostCorrection_Hz = NaN;
    end
end
replay = localApplyReceiverSynchronizationReplay(replay, syncState, rx);

timingEstimate = double(sixgr.util.structGet(rx, "TimingOffset", NaN));
rawTimingEstimate = double(sixgr.util.structGet(rx, "RawTimingEstimate_samples", timingEstimate));
appliedTimingCorrection = double(sixgr.util.structGet(rx, "AppliedTimingCorrection_samples", NaN));
if logical(useIdealTimingSync)
    timingEstimateUsed = false;
else
    timingEstimateUsed = logical(sixgr.util.structGet(rx, "TimingEstimateUsed", isfinite(rawTimingEstimate)));
end
if timingEstimateUsed
    replay.UseIdealTimingSync = false;
end
replay.RawTimingEstimate_samples = rawTimingEstimate;
replay.AppliedTimingCorrection_samples = appliedTimingCorrection;
replay.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(rx, "TimingEstimateApplicationPolicy", ""));
replay.TimingEstimateStatus = string(sixgr.util.structGet(rx, "TimingEstimateStatus", ""));
replay.TimingEstimateWasClipped = logical(sixgr.util.structGet(rx, "TimingEstimateWasClipped", false));
if ~timingEstimateUsed || ~isfinite(rawTimingEstimate)
    replay.TimingEstimateUsed = false;
    replay.EstimatedTimingOffset_PreCorrection_samples = NaN;
    replay.AppliedTimingCorrection_samples = NaN;
    if isfinite(timingTruth)
        replay.ResidualTimingError_PostCorrection_samples = timingTruth;
    else
        replay.ResidualTimingError_PostCorrection_samples = NaN;
    end
    replay = localApplyReceiverSynchronizationReplay(replay, syncState, rx);
    return;
end
replay.TimingEstimateUsed = true;
replay.EstimatedTimingOffset_PreCorrection_samples = rawTimingEstimate;
if isfinite(timingTruth)
    replay.ResidualTimingError_PostCorrection_samples = timingTruth - appliedTimingCorrection;
else
    replay.ResidualTimingError_PostCorrection_samples = NaN;
end
replay = localApplyReceiverSynchronizationReplay(replay, syncState, rx);
end

function cfg = localAttachReceiverSyncRuntimeContext(cfg, chState, replay)
delay = double(sixgr.util.structGet(replay, "ChannelTrimSamples", ...
    sixgr.util.structGet(chState, "ChannelTrimSamples", 0)));
if ~isfinite(delay)
    delay = 0;
end
padSamples = double(sixgr.util.structGet(replay, "ChannelPadSamples", ...
    sixgr.util.structGet(chState, "ChannelPadSamples", NaN)));
pathDelay = NaN;
if isfinite(padSamples)
    pathDelay = max(0, double(padSamples) - max(0, double(delay)));
end
cfg = sixgr.util.structSet(cfg, "lls6g.receiverSync.ChannelFilterDelay_samples", double(delay));
cfg = sixgr.util.structSet(cfg, "lls6g.receiverSync.ChannelTrimSamples", double(delay));
cfg = sixgr.util.structSet(cfg, "lls6g.userContext.RuntimeChannelFilterDelay_samples", double(delay));
cfg = sixgr.util.structSet(cfg, "lls6g.userContext.RuntimeChannelTrimSamples", double(delay));
if isfinite(padSamples)
    cfg = sixgr.util.structSet(cfg, "lls6g.receiverSync.ChannelPadSamples", max(0, double(padSamples)));
    cfg = sixgr.util.structSet(cfg, "lls6g.userContext.RuntimeChannelPadSamples", max(0, double(padSamples)));
end
if isfinite(pathDelay)
    cfg = sixgr.util.structSet(cfg, "lls6g.receiverSync.ChannelPathDelay_samples", double(pathDelay));
    cfg = sixgr.util.structSet(cfg, "lls6g.userContext.RuntimeChannelPathDelay_samples", double(pathDelay));
end
cfg = sixgr.util.structSet(cfg, "lls6g.receiverSync.RuntimeWaveformSampleAligned", true);
end

function replay = localApplyReceiverSynchronizationReplay(replay, syncState, rx)
if ~(isstruct(syncState) && ~isempty(fieldnames(syncState)))
    return;
end
replay.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(syncState, ...
    "EstimatedOscillatorCFO_Hz", replay.EstimatedCFO_PreCorrection_Hz));
replay.EstimatedCFO_Hz = replay.EstimatedCFO_PreCorrection_Hz;
replay.EstimatedCommonFrequency_Hz = double(sixgr.util.structGet(syncState, "EstimatedCommonFrequency_Hz", NaN));
replay.PhysicalDoppler_Hz = double(sixgr.util.structGet(syncState, "PhysicalDoppler_Hz", NaN));
replay.CFOCorrectionApplied = logical(sixgr.util.structGet(rx, "CFOCorrectionApplied", replay.CFOCorrectionApplied));
replay.CFOCorrectionApplied_Hz = double(sixgr.util.structGet(syncState, "AppliedCFOCorrection_Hz", ...
    sixgr.util.structGet(rx, "CFOCorrectionApplied_Hz", NaN)));
replay.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(syncState, ...
    "ResidualCFO_PostCorrection_Hz", replay.ResidualCFO_PostCorrection_Hz));
replay.ResidualCFO_EstimatedPostCorrection_Hz = double(sixgr.util.structGet(syncState, ...
    "ResidualCFO_EstimatedPostCorrection_Hz", NaN));
if ~logical(replay.CFOCorrectionApplied) && isfinite(double(replay.InjectedCFO_Hz))
    replay.ResidualCFO_PostCorrection_Hz = double(replay.InjectedCFO_Hz);
end
if isfinite(replay.EstimatedCFO_PreCorrection_Hz)
    replay.CFOEstimateAvailability = "available";
end
replay.RawTimingEstimate_samples = double(sixgr.util.structGet(syncState, ...
    "RawTimingEstimate_samples", sixgr.util.structGet(replay, "RawTimingEstimate_samples", NaN)));
replay.KnownTimingDelay_samples = double(sixgr.util.structGet(syncState, "KnownTimingDelay_samples", NaN));
replay.EstimatedTimingOffset_PreCorrection_samples = double(sixgr.util.structGet(syncState, ...
    "RawTimingEstimate_samples", sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", NaN)));
replay.EstimatedTimingOffsetForCorrection_samples = double(sixgr.util.structGet(syncState, ...
    "EstimatedTimingOffsetForCorrection_samples", NaN));
replay.AppliedTimingCorrection_samples = double(sixgr.util.structGet(syncState, ...
    "AppliedTimingCorrection_samples", sixgr.util.structGet(replay, "AppliedTimingCorrection_samples", NaN)));
replay.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(syncState, ...
    "ResidualTimingError_PostCorrection_samples", sixgr.util.structGet(replay, "ResidualTimingError_PostCorrection_samples", NaN)));
timingTruth = double(sixgr.util.structGet(replay, ...
    "TrueReceiverTimingOffset_samples", NaN));
if isfinite(timingTruth)
    appliedTiming = double(sixgr.util.structGet(replay, ...
        "AppliedTimingCorrection_samples", NaN));
    if isfinite(appliedTiming)
        replay.ResidualTimingError_PostCorrection_samples = timingTruth - appliedTiming;
    else
        replay.ResidualTimingError_PostCorrection_samples = timingTruth;
    end
    replay.TimingResidualDefinition = ...
        "true_receiver_acquisition_offset_minus_applied_sample_correction";
end
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0)));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0)));
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function useIdealTimingSync = localUseIdealTimingSync(cfg)
useIdealTimingSync = logical(sixgr.util.structGet(cfg, "phy.rx.useIdealTimingSync", false));
end

function mode = localResolveInterferenceMode(cfg)
mode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
mode = strtrim(lower(mode));
if strlength(mode) == 0 && logical(sixgr.util.structGet(cfg, "run.useAbstractInterferenceModel", false))
    error("sixgr:link:AbstractInterferenceModeRemoved", ...
        "run.useAbstractInterferenceModel=true is not allowed in no-proxy waveform LLS.");
end
if strlength(mode) == 0
    mode = "none";
end
end

function nVar = localResolveThermalNoiseVariance(replay, referenceWaveform, txInfo) %#ok<INUSD>
nVar = sixgr.link.resolveReceiverThermalNoiseVariance(replay);
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
if isempty(fs) || ~isfinite(double(fs)) || double(fs) <= 0
    fs = 30.72e6;
else
    fs = double(fs);
end
end

function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, fs)
padSamples = 0;
trimSamples = 0;
if isempty(chObj) || ~isfinite(double(fs)) || double(fs) <= 0
    return;
end
filterDelay = 0;
pathDelays = [];
try
    chInfo = info(chObj);
    filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", 0));
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
catch
end
if isempty(pathDelays)
    try
        pathDelays = double(chObj.PathDelays);
    catch
        pathDelays = [];
    end
end
maxPathDelay = 0;
if ~isempty(pathDelays)
    maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
end
% Pad for full channel memory, but only trim the implementation filter
% delay. Timing estimation must still see the physical path delay.
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function slotDur_s = localSlotDuration(cfg)
slotDur_s = sixgr.time.slotDurationSec(cfg);
end

function bits = localResolveExpectedUCIBits(inputBits, grantSnapshot, harqContext)
bits = localNormalizeUCIInput(inputBits);
if ~isempty(bits)
    return;
end
candidatePaths = ["ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits","MultiplexedHARQACKBits"];
for i = 1:numel(candidatePaths)
    raw = sixgr.util.structGet(grantSnapshot, char(candidatePaths(i)), []);
    bits = localNormalizeUCIInput(raw);
    if ~isempty(bits)
        return;
    end
end
for i = 1:numel(candidatePaths)
    raw = sixgr.util.structGet(harqContext, char(candidatePaths(i)), []);
    bits = localNormalizeUCIInput(raw);
    if ~isempty(bits)
        return;
    end
end
end

function bits = localNormalizeUCIInput(raw)
if isempty(raw)
    bits = int8([]);
    return;
end
bits = int8(logical(raw(:)));
end

function T = localEmptyTrialTable()
varNames = {'Direction','SNR_dB','SFN','UEIndex','RNTI','BaseStationID','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'MeasuredSINR_dB','WidebandCQI','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
    'LinkAdaptationMode','ActualMCSSelectionMode','CQITable','MCSTable','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
    'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','ChannelGain_dB','NoiseVariance', ...
    'DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
    'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
    'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
    'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
    'BeamScoreVector_dB','TopBeamIndexSet','TopBeamGainSet_dB','BeamScoreSource', ...
    'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
    'OfferedBits','GoodBits','Throughput_Mbps','OfferedThroughput_Mbps','Goodput_Mbps', ...
    'ComputeLatency_ms','ProcedureDelay_ms','AirInterfaceTTI_ms','AirInterfaceObservation_ms', ...
    'Latency_ms','DecodeLatency_ms','EarlyStopRate','DecoderComplexityUnits','NormalizedDecoderComplexity','AreaEfficiencyProxy', ...
    'NumCodeBlocks','CodeBlockLength_bits','SegmentationOccurred','SegmentationPaddingBits','TBCRCLength_bits','TBLengthWithCRC_bits','BaseGraph', ...
    'EncodedBits','RateMatchedBits','RateMatchPunctureBits','RateMatchRepetitionBits', ...
    'CodeBlockErrors','CodeBlockCount','CodeBlockBLER','CBGErrors','CBGCount','CBGBLER', ...
    'PAPR_dB','PeakClippingEvents','SymbolErrors','SymbolsCompared','SymbolErrorRate','ResidualInterferencePower_dB', ...
    'LLRMeanAbs','LLRStdAbs','LLRImbalance','ModulationMappingSensitivity', ...
    'ShapingRateLoss','DistributionMatchingLatency_ms','HighOrderRobustness','DetectorComplexityUnits_Modulation', ...
    'DataRECount','DMRSRECount','PTRSRECount','RSOverheadFraction', ...
    'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz', ...
    'EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
    'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples', ...
    'TrueTimingOffset_samples','TimingError_samples', ...
    'IQImbalanceConfigured','IQImbalanceApplied','IQImbalanceModel', ...
    'ConfiguredIQGainImbalance_dB','ConfiguredIQPhaseImbalance_deg', ...
    'IQImbalanceMirrorPowerRatio_dB','IQImbalanceImageRejection_dB', ...
    'IQImbalanceIQPowerRatio_dB','IQImbalanceIQCorrelation', ...
    'IQImbalanceEstimatedAlphaAbs','IQImbalanceEstimatedBetaAbs', ...
    'IQImbalanceMeasurementSource','IQImbalanceMeasurementStatus', ...
    'ChannelComplianceMode','PathlossModelSource','PathlossComplianceStatus','FallbackUsedForPathloss', ...
    'O2IModelSource','O2IComplianceStatus','O2IComplianceReason','LOSProbabilitySource','LOSComplianceStatus','LOSComplianceReason', ...
    'EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
    'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB', ...
    'Status','Crash','LinkAdaptationApplied','LinkAdaptationScheduled','Notes'};
varTypes = {'string','double','double','double','double','double','double','double','double','double','double','double','string','double','double', ...
    'string','double','double','double','double','double','double', ...
    'double','double','double','string','double','string','string','string','string','double','double','double','string','string', ...
    'string','double','string','double','double', ...
    'double','double','double','string', ...
    'double','double','double','double','double', ...
    'double','double','double','double','double','double','double','double', ...
    'string','string','string','string', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double','double','double', ...
    'double','double','double','double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double','double','double', ...
    'double','double','double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double', ...
    'double','double','double', ...
    'double','double','double', ...
    'double','double', ...
    'logical','logical','string', ...
    'double','double', ...
    'double','double', ...
    'double','double', ...
    'double','double', ...
    'string','string', ...
    'string','string','string','logical','string','string','string','string','string','string', ...
    'double','double','double','double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'string','logical','logical','logical','string'};
% Throughput_Mbps is the scheduled-TB bitrate and is deliberately distinct
% from offered traffic and CRC-delivered goodput.  Keep the legacy explicit
% type vector aligned with the additive canonical column.
throughputIdx = find(strcmp(varNames, 'Throughput_Mbps'), 1);
if numel(varTypes) + 1 == numel(varNames)
    varTypes = [varTypes(1:throughputIdx-1), {'double'}, varTypes(throughputIdx:end)];
end
assert(numel(varTypes) == numel(varNames), ...
    'sixgr:link:ULTrialSchemaTypeCountMismatch');
T = table('Size', [0, numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
T.ComputeLatencySource = strings(0,1);
T.ULTransmissionAuthority = strings(0,1);
T.ULReceivedAssignmentDigest = strings(0,1);
T.ULReceiveAllocationAuthority = strings(0,1);
T.UEHARQAttempt = zeros(0,1);
T.UEHARQInitialAssignmentDigest = strings(0,1);
T.QCLMeasurementStatus = strings(0,1);
T.EstimatedChannelReferenceCorrelationMagnitude = zeros(0,1);
T.SymbolDecisionStatus = strings(0,1);
T.RuntimeAbsoluteSlotIndex0 = zeros(0,1);
T.CarrierNSlot = zeros(0,1);
T.CarrierNFrame = zeros(0,1);
T.DecodeLatencySource = strings(0,1);
T.ReceiverPipelineLatency_ms = zeros(0,1);
T.ReceiverPipelineLatencySource = strings(0,1);
T.ChannelEstimationLatency_ms = zeros(0,1);
T.EqualizationLatency_ms = zeros(0,1);
T.ReceiverStageLatencySource = strings(0,1);
T.ExecutionProfile = strings(0,1);
T.ExecutionTaxonomy = strings(0,1);
T.ExecutionBackend = strings(0,1);
T.ApproximationMode = strings(0,1);
T.CalibrationProvenance = strings(0,1);
T.StrictSchedulingOwnership = false(0,1);
T.ConfiguredSNR_dB = zeros(0,1);
T.CRCApplicable = false(0,1);
T.TxWaveformColumns = zeros(0,1);
T.PhysicalTxAntennas = zeros(0,1);
T.RxWaveformBranches = zeros(0,1);
T.PhysicalRxAntennas = zeros(0,1);
T.TxWaveformDomain = strings(0,1);
T.HybridElementDomainApplied = false(0,1);
T.ConfiguredLayers = zeros(0,1);
T.ConfiguredTxAntennas = zeros(0,1);
T.ConfiguredRxAntennas = zeros(0,1);
T.RV = zeros(0,1);
T.HARQProcess = zeros(0,1);
T.HARQProcessId = zeros(0,1);
T.HarqID = zeros(0,1);
T.HARQRound = zeros(0,1);
T.NDI = zeros(0,1);
T.HARQNDI = zeros(0,1);
T.IsRetransmission = false(0,1);
T.HARQIsRetransmission = false(0,1);
T.HARQRV = zeros(0,1);
T.NDIEpoch = zeros(0,1);
T.TBId = strings(0,1);
T.OriginalTBSBits = zeros(0,1);
T.CurrentTBSBits = zeros(0,1);
T.OriginalRateMatchedBits = zeros(0,1);
T.CurrentRateMatchedBits = zeros(0,1);
T.EffectiveInitialCodeRate = zeros(0,1);
T.EffectiveCurrentTxCodeRate = zeros(0,1);
T.ShortIRRetx = false(0,1);
T.CodeBlockLayoutHash = strings(0,1);
T.HARQContextHash = strings(0,1);
T.HARQContextStatus = strings(0,1);
T.AppliedAWGNSNR_dB = zeros(0,1);
T.NoiseVarStatus = strings(0,1);
T.NoiseVarSource = strings(0,1);
T.NoiseVarReason = strings(0,1);
T.NoiseVarStrictFailure = false(0,1);
T.DataRECountPerLayer = zeros(0,1);
T.TotalDataRECount = zeros(0,1);
T.TBSInputModulation = strings(0,1);
T.TBSInputNumLayers = zeros(0,1);
T.TBSInputNPRB = zeros(0,1);
T.TBSInputNREPerPRB = zeros(0,1);
T.TBSInputTargetCodeRate = zeros(0,1);
T.TBSInputXOverhead = zeros(0,1);
T.TBSInputSource = strings(0,1);
T.ReplaySampleNoiseVariance = zeros(0,1);
T.ReplayGridNoiseVariance = zeros(0,1);
T.ReceiverInputSampleNoiseVariance = zeros(0,1);
T.PreEqualizationNoiseVariance = zeros(0,1);
T.PostEqualizationNoiseVariance = zeros(0,1);
T.SampleToGridNoiseVarianceGain = zeros(0,1);
T.ReplaySampleNoiseVarianceDomain = strings(0,1);
T.ReplayGridNoiseVarianceDomain = strings(0,1);
T.ReceiverInputSampleNoiseVarianceDomain = strings(0,1);
T.DesiredSignalPowerBeforeNoiseDomain = strings(0,1);
T.CompositeSignalPowerBeforeNoiseDomain = strings(0,1);
T.SNRReferencePlane = strings(0,1);
T.AppliedNoiseSNRSource = strings(0,1);
T.RequestedAWGNReferenceSNR_dB = zeros(0,1);
T.SignalEnergyPerOccupiedRE = zeros(0,1);
T.PreEqualizationNoiseVarianceDomain = strings(0,1);
T.PostEqualizationNoiseVarianceDomain = strings(0,1);
T.LLRNoiseVarianceDomain = strings(0,1);
T.NoiseVarianceUnit = strings(0,1);
T.NoiseVarianceNormalization = strings(0,1);
T.NoiseVarianceAliasOf = strings(0,1);
T.ReplaySampleNoiseVarianceSource = strings(0,1);
T.ReplayGridNoiseVarianceSource = strings(0,1);
T.ReceiverInputSampleNoiseVarianceSource = strings(0,1);
T.PreEqualizationNoiseVarianceSource = strings(0,1);
T.PostEqualizationNoiseVarianceSource = strings(0,1);
T.LLRNoiseVarianceSource = strings(0,1);
T.ModulationOrderQm = zeros(0,1);
T.ComputedE_TS38212 = zeros(0,1);
T.RateMatchedBitsDelta_TS38212 = zeros(0,1);
T.UCIOnPUSCHApplied = false(0,1);
T.UCIOnPUSCHSource = strings(0,1);
T.HARQACKBitCount = zeros(0,1);
T.ExpectedHARQACKBits = strings(0,1);
T.DecodedHARQACKBits = strings(0,1);
T.CSI1BitCount = zeros(0,1);
T.CSI2BitCount = zeros(0,1);
T.ExpectedCSIPart1Bits = strings(0,1);
T.ExpectedCSIPart2Bits = strings(0,1);
T.DecodedCSIPart1Bits = strings(0,1);
T.DecodedCSIPart2Bits = strings(0,1);
T.UCIReceiverEvidenceJSON = strings(0,1);
T.CSI1ContentMatch = false(0,1);
T.CSI2ContentMatch = false(0,1);
T.UCIOnPUSCHCSIReportIdentity = strings(0,1);
T.UCIOnPUSCHFeedbackGrantIds = strings(0,1);
T.UCIOnPUSCHFeedbackSourceSlots = strings(0,1);
T.UCIOnPUSCHFeedbackHARQIds = strings(0,1);
T.UCIOnPUSCHFeedbackBitCount = zeros(0,1);
T.UCIOnPUSCHEvidenceSource = strings(0,1);
T.HARQACKContentMatch = false(0,1);
T.HARQACKDecodeStatus = strings(0,1);
T.HARQACKDecodeReason = strings(0,1);
T.EqualizerType = strings(0,1);
T.EqualizerRequestedType = strings(0,1);
T.EqualizerEngine = strings(0,1);
T.EqualizerCovarianceFactorizationCount = zeros(0,1);
T.InterferenceCovarianceAvailable = false(0,1);
T.InterferenceCovarianceSource = strings(0,1);
T.InterferenceCovarianceStatus = strings(0,1);
T.MUMIMOReceiveCombinerApplied = false(0,1);
T.MUMIMOReceiveCombinerStatus = strings(0,1);
T.MUMIMOReceiveCombinerSource = strings(0,1);
T.MUMIMOReceiveCombinerInputBranches = zeros(0,1);
T.MUMIMOReceiveCombinerOutputBranches = zeros(0,1);
T.MUMIMOReceiveCombinerMatrixSHA256 = strings(0,1);
T.MUMIMOReceiveCombinerInterferenceProjected = false(0,1);
T.MUMIMOReceiveCombinerFullObservationPreserved = false(0,1);
T.MUMIMOReceiveCombinerIdentityResidual = zeros(0,1);
T.MUMIMOReceiverAlgorithmApplied = strings(0,1);
T.ReceiverUsable = false(0,1);
T.DecodeAttempted = false(0,1);
T.DecodeUsable = false(0,1);
T.FailureReason = strings(0,1);
T.StrictReceiverEvidenceOk = false(0,1);
T.StrictOk = false(0,1);
T.TruthStatus = strings(0,1);
T.ChannelEstimateAttempted = false(0,1);
T.ChannelEstimateAvailable = false(0,1);
T.ChannelEstimateSource = strings(0,1);
T.ResourceExtractionAttempted = false(0,1);
T.ResourceExtractionAvailable = false(0,1);
T.EqualizationAttempted = false(0,1);
T.EqualizationAvailable = false(0,1);
T.ULSCHDecodeAttempted = false(0,1);
T.ULSCHDecodeAvailable = false(0,1);
T.LLRAvailable = false(0,1);
T.LLRFinite = false(0,1);
T.LLRScaleSource = strings(0,1);
T.LLRNoiseVariance = zeros(0,1);
T.ReceiverHestSINR_dB = zeros(0,1);
T.ReceiverHestSINRApplicable = false(0,1);
T.ReceiverHestSINRSource = strings(0,1);
T.ReceiverHestSINRValueRole = strings(0,1);
T.ReceiverHestSINRValueStatus = strings(0,1);
T.ReceiverHestSINRNAReason = strings(0,1);
T.PostEqSINR_dB = zeros(0,1);
T.PostEqSINRWidebanddB = zeros(0,1);
T.PostEqSINRSource = strings(0,1);
T.PostEqSINRValueRole = strings(0,1);
T.PostEqSINRValueStatus = strings(0,1);
T.PostEqSINRNAReason = strings(0,1);
T.PostEqSINRPerLayer_dB = strings(0,1);
T.PostEqSINRRawEqualizer_dB = zeros(0,1);
T.PostEqSINRDMRSResidualBoundApplied = false(0,1);
T.PostEqSINRDMRSResidual_dB = zeros(0,1);
T.PostEqDMRSResidualNoiseVar = zeros(0,1);
T.PostEqDMRSResidualSource = strings(0,1);
T.PostEqDecisionResidual_dB = zeros(0,1);
T.PostEqDecisionResidualNoiseVar = zeros(0,1);
T.PostEqDecisionResidualSource = strings(0,1);
T.PostEqSINRAvailable = false(0,1);
T.PostEqSINRReceiverDerived = false(0,1);
T.SINRValidationStatus = strings(0,1);
T.SINRValidationReason = strings(0,1);
T.SINRComputationMethod = strings(0,1);
T.ConfiguredSNRLikeSourceRejected = false(0,1);
T.DecoderTruthProxySINR_dB = zeros(0,1);
T.DecoderTruthProxySINRSource = strings(0,1);
T.SINRValueRole = strings(0,1);
T.SINRSource = strings(0,1);
T.MeasuredTrialSINR_dB = zeros(0,1);
T.MeasuredTrialSINRSource = strings(0,1);
T.MeasuredTrialSINRValueRole = strings(0,1);
T.MeasuredTrialSINRValueStatus = strings(0,1);
T.MeasuredTrialSINRNAReason = strings(0,1);
T.EVMProxySINR_dB = zeros(0,1);
T.EVMProxySINRSource = strings(0,1);
T.EVMProxySINRValueRole = strings(0,1);
T.EVMProxySINRValueStatus = strings(0,1);
T.EVMProxySINRNAReason = strings(0,1);
T.LargeScaleSINR_dB = zeros(0,1);
T.LargeScaleSINRSource = strings(0,1);
T.ServingRSRP_dBm = zeros(0,1);
T.ServingRSRPSource = strings(0,1);
T.ULNormalizedReferencePower_dB = zeros(0,1);
T.ULNormalizedReferencePowerSource = strings(0,1);
T.ULNormalizedWindowRSSI_dB = zeros(0,1);
T.ULNormalizedWindowRSSISource = strings(0,1);
T.ULNormalizedWindowPowerRatio_dB = zeros(0,1);
T.ULNormalizedWindowPowerRatioSource = strings(0,1);
T.ULNormalizedPowerEvidenceJSON = strings(0,1);
T.AppliedLargeScaleGain_dB = zeros(0,1);
T.AppliedLargeScaleLoss_dB = zeros(0,1);
T.AppliedBasePathloss_dB = zeros(0,1);
T.AppliedPathloss_dB = zeros(0,1);
T.PUSCHPowerControlEnabled = false(0,1);
T.PUSCHPowerControlStatus = strings(0,1);
T.PUSCHTxPower_dBm = zeros(0,1);
T.PUSCHRequestedPower_dBm = zeros(0,1);
T.PUSCHPcmax_dBm = zeros(0,1);
T.PUSCHPowerHeadroom_dB = zeros(0,1);
T.PUSCHMeasuredWaveformPower_dBm = zeros(0,1);
T.PUSCHPowerClosureError_dB = zeros(0,1);
T.PUSCHPowerClipped = false(0,1);
T.PUSCHPathlossReferenceRS = strings(0,1);
T.PUSCHPowerControlSource = strings(0,1);
T.PUSCHPowerAmplitudeScale = zeros(0,1);
T.PUSCHPowerControlPathloss_dB = zeros(0,1);
T.AppliedShadowFading_dB = zeros(0,1);
T.AppliedO2I_dB = zeros(0,1);
T.AppliedLargeScaleGainSource = strings(0,1);
T.ChannelComplianceMode = strings(0,1);
T.PathlossModelSource = strings(0,1);
T.PathlossComplianceStatus = strings(0,1);
T.FallbackUsedForPathloss = false(0,1);
T.O2IModelSource = strings(0,1);
T.O2IComplianceStatus = strings(0,1);
T.O2IComplianceReason = strings(0,1);
T.LOSProbabilitySource = strings(0,1);
T.LOSComplianceStatus = strings(0,1);
T.LOSComplianceReason = strings(0,1);
T.IQImbalanceConfigured = false(0,1);
T.IQImbalanceApplied = false(0,1);
T.IQImbalanceModel = strings(0,1);
T.ConfiguredIQGainImbalance_dB = zeros(0,1);
T.ConfiguredIQPhaseImbalance_deg = zeros(0,1);
T.IQImbalanceMirrorPowerRatio_dB = zeros(0,1);
T.IQImbalanceImageRejection_dB = zeros(0,1);
T.IQImbalanceIQPowerRatio_dB = zeros(0,1);
T.IQImbalanceIQCorrelation = zeros(0,1);
T.IQImbalanceEstimatedAlphaAbs = zeros(0,1);
T.IQImbalanceEstimatedBetaAbs = zeros(0,1);
T.IQImbalanceMeasurementSource = strings(0,1);
T.IQImbalanceMeasurementStatus = strings(0,1);
T.TimingEstimateUsed = false(0,1);
T.UseIdealTimingSync = false(0,1);
T.AppliedTimingCorrection_samples = zeros(0,1);
T.TimingEstimateApplicationPolicy = strings(0,1);
T.TimingEstimateStatus = strings(0,1);
T.TimingEstimateWasClipped = false(0,1);
T.LinkAdaptationDomain = strings(0,1);
T.FixedAnchorMode = false(0,1);
T.AdaptiveMode = false(0,1);
T.LinkAdaptationFeedbackDelaySlots = zeros(0,1);
T.LinkAdaptationFeedbackDelaySource = strings(0,1);
T.LinkAdaptationFeedbackDelayStatus = strings(0,1);
T.LinkAdaptationAppliedFeedbackSourceSlot = zeros(0,1);
T.LinkAdaptationAppliedFeedbackAgeSlots = zeros(0,1);
T.LinkAdaptationScheduledFeedbackSourceSlot = zeros(0,1);
T.LinkAdaptationScheduledApplySlot = zeros(0,1);
T.AppliedLinkAdaptationResolvedCQI = zeros(0,1);
T.AppliedLinkAdaptationCQIBasedMCS = zeros(0,1);
T.AppliedLinkAdaptationMCS = zeros(0,1);
T.AppliedLinkAdaptationOLLADeltaDb = zeros(0,1);
T.AppliedLinkAdaptationOLLAUpdateCount = zeros(0,1);
T.AppliedLinkAdaptationOLLAFeedbackEligible = false(0,1);
T.ScheduledLinkAdaptationResolvedCQI = zeros(0,1);
T.ScheduledLinkAdaptationMCS = zeros(0,1);
T.ScheduledLinkAdaptationOLLADeltaDb = zeros(0,1);
T.ScheduledLinkAdaptationOLLAUpdateCount = zeros(0,1);
T.ScheduledLinkAdaptationOLLAFeedbackEligible = false(0,1);
T.ScheduledLinkAdaptationOLLAFeedbackExclusionReason = strings(0,1);
T.CQISource = strings(0,1);
T.MCSSelectionSource = strings(0,1);
T.MCSValueStatus = strings(0,1);
T.OLLADomain = strings(0,1);
T.OuterLoopEnabled = false(0,1);
T.InnerLoopEnabled = false(0,1);
T.OuterLoopApplied = false(0,1);
T.InnerLoopApplied = false(0,1);
T.ILLAUpdateScheduled = false(0,1);
T.OLLAFeedbackUpdateScheduled = false(0,1);
T.OLLADeltaDb = zeros(0,1);
T.OLLADeltaMCS = zeros(0,1);
T.OLLAUpdateCount = zeros(0,1);
T.OLLAStateAuthority = strings(0,1);
T.OLLAState = strings(0,1);
T.RankSelectionPolicy = strings(0,1);
T.RankSelectionSource = strings(0,1);
T.RankDecisionReason = strings(0,1);
T.RankDowngradeApplied = false(0,1);
T.MaxSupportedLayers = zeros(0,1);
T.CalibrationProfile = strings(0,1);
T.InterferenceMode = strings(0,1);
T.InterferenceContributorCount = zeros(0,1);
T.InterferenceAggregatedRxPower_dBm = zeros(0,1);
T.InterferencePowerSource = strings(0,1);
T.FullInterfererChannelTruthUsed = false(0,1);
T.PBCHGatingActive = false(0,1);
T.PRACHGatingActive = false(0,1);
T.PDCCHGatingActive = false(0,1);
T.SRSGatingActive = false(0,1);
T.ControlEligible = false(0,1);
T.ControlDecodeOk = false(0,1);
T.DCICrcPass = false(0,1);
T.PDCCHPayloadMatch = false(0,1);
T.PDCCHCausalGrantDecodeOk = false(0,1);
T.PDCCHMissedDetection = false(0,1);
T.PDCCHFalseAlarm = false(0,1);
T.GrantValid = false(0,1);
T.NegativeExpectedOk = false(0,1);
T.PDCCHBlindSearchEnabled = false(0,1);
T.PDCCHREGMappingAvailable = false(0,1);
T.PDCCHGrantBindingRequired = false(0,1);
T.PDCCHGrantBindingOk = false(0,1);
T.PDCCHGrantBindingStatus = strings(0,1);
T.PDCCHGrantBindingFailureCode = strings(0,1);
T.PDCCHGrantDCIId = strings(0,1);
T.PDCCHGrantDCIFieldsHash = strings(0,1);
T.PDCCHGrantFieldsHash = strings(0,1);
T.PDCCHGrantSearchSpaceId = zeros(0,1);
T.PDCCHGrantCORESETId = zeros(0,1);
T.PDCCHGrantAggregationLevel = zeros(0,1);
T.PDCCHGrantCandidateIndex = zeros(0,1);
T.PDCCHGrantDCIFormat = strings(0,1);
T.GrantControlState = strings(0,1);
T.PDCCHControlFailureReason = strings(0,1);
T.PDCCHControlEvidenceSource = strings(0,1);
T.ControlDecodeSource = strings(0,1);
T.CellAcquisitionState = strings(0,1);
T.AccessState = strings(0,1);
T.SRSValidityState = strings(0,1);
T.CSIValidityState = strings(0,1);
T.SRSValid = false(0,1);
T.SRSAgeSlots = zeros(0,1);
T.TRSGatingActive = false(0,1);
T.TRSValidityState = strings(0,1);
T.TrackingEligibility = false(0,1);
T.TRSAgeSlots = zeros(0,1);
T.LastSuccessfulTRSSlot = zeros(0,1);
T.LastEstimatedTRSDopplerHz = zeros(0,1);
T.TRSStateSource = strings(0,1);
T.TRSRuntimeConsumer = strings(0,1);
T.TRSInfluencedDecision = false(0,1);
T.TRSInfluenceDefinition = strings(0,1);
T.TRSReceiverIntegrationStatus = strings(0,1);
T.TRSReceiverIntegrationBlocker = strings(0,1);
T.GrantContextId = strings(0,1);
T.GrantWorkerSafe = false(0,1);
T.GrantSharedStateCommitMode = strings(0,1);
T.ConfiguredBeamSelectionStrategy = strings(0,1);
T.PrecoderSource = strings(0,1);
T.PrecodingMode = strings(0,1);
T.PrecodingApplicationStage = strings(0,1);
T.PrecodingActive = false(0,1);
T.ExplicitBeamWeightsApplied = false(0,1);
T.TransformPrecodingApplied = false(0,1);
T.FrequencyHoppingApplied = false(0,1);
T.FrequencyHoppingMode = strings(0,1);
T.FrequencyHoppingToolboxMode = strings(0,1);
T.SecondHopStartPRB = zeros(0,1);
T.BeamformingApplied = false(0,1);
T.AppliedBeamIndexSet = strings(0,1);
T.AppliedCodebookPortIndexSet = strings(0,1);
T.AppliedCodebookPortIndexDefinition = strings(0,1);
T.PrecodingNumLogicalPorts = NaN(0,1);
T.AppliedPrecoderPMI = zeros(0,1);
T.AppliedPrecoderPMIType = strings(0,1);
T.AppliedPrecoderCodebookMode = strings(0,1);
T.AppliedPrecoderMatrixSHA256 = strings(0,1);
T.RequestedPrecoderSHA256 = strings(0,1);
T.AppliedPrecoderSHA256 = strings(0,1);
T.PrecoderDigestDomain = strings(0,1);
T.FrozenGrantContextId = strings(0,1);
T.RequestedVsAppliedPrecoderPMIMatchStatus = strings(0,1);
T.RequestedBeamTruthClassification = strings(0,1);
T.RequestedPrecoderPMITruthClassification = strings(0,1);
T.AppliedBeamApplicationSource = strings(0,1);
T.AppliedBeamTruthClassification = strings(0,1);
T.AppliedPrecoderPMIApplicationSource = strings(0,1);
T.AppliedPrecoderPMITruthClassification = strings(0,1);
T.PMISource = strings(0,1);
T.ULSpatialMeasurementEvidenceJSON = strings(0,1);
T.PrecodingNumPorts = zeros(0,1);
T.PrecodingNumLayers = zeros(0,1);
T.PrecodingMatrixRows = zeros(0,1);
T.PrecodingMatrixCols = zeros(0,1);
T.InterfererBeamformingAppliedCount = zeros(0,1);
T.InterfererExplicitBeamWeightCount = zeros(0,1);
T.InterfererTransformPrecodingCount = zeros(0,1);
T.InterfererPrecoderSourceSet = strings(0,1);
T.InterfererPrecodingModeSet = strings(0,1);
T.InterfererBeamIndexSetSummary = strings(0,1);
T = localEnsureRuntimeEvidenceColumns(T, 0);
T = sixgr.link.appendMeasuredPHYEvidenceColumns(T, {});
end

function mode = localResolveLinkAdaptationMode(cfg, direction)
mode = "fixed";
dir = upper(string(direction));
globalMode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
if dir == "UL"
    policy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulPolicy", globalMode)));
else
    policy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", globalMode)));
end
if strlength(strtrim(policy)) > 0
    mode = policy;
elseif strlength(strtrim(globalMode)) > 0
    mode = globalMode;
end
end

function trace = localResolveTRSRuntimeTrace(cfg, grantSnapshot)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
trace = struct( ...
    "TRSGatingActive", logical(localResolveTRSField(grantSnapshot, userMeta, "TRSGatingActive", "RuntimeTRSGatingActive", false)), ...
    "TRSValidityState", string(localResolveTRSField(grantSnapshot, userMeta, "TRSValidityState", "RuntimeTRSValidityState", "")), ...
    "TrackingEligibility", logical(localResolveTRSField(grantSnapshot, userMeta, "TrackingEligibility", "RuntimeTrackingEligibility", false)), ...
    "TRSAgeSlots", double(localResolveTRSField(grantSnapshot, userMeta, "TRSAgeSlots", "RuntimeTRSAgeSlots", NaN)), ...
    "LastSuccessfulTRSSlot", double(localResolveTRSField(grantSnapshot, userMeta, "LastSuccessfulTRSSlot", "RuntimeLastSuccessfulTRSSlot", NaN)), ...
    "LastEstimatedTRSDopplerHz", double(localResolveTRSField(grantSnapshot, userMeta, "LastEstimatedTRSDopplerHz", "RuntimeLastEstimatedTRSDopplerHz", NaN)), ...
    "TRSStateSource", string(localResolveTRSField(grantSnapshot, userMeta, "TRSStateSource", "RuntimeTRSStateSource", "")), ...
    "TRSRuntimeConsumer", string(localResolveTRSField(grantSnapshot, userMeta, "TRSRuntimeConsumer", "RuntimeTRSRuntimeConsumer", "")), ...
    "TRSInfluencedDecision", logical(localResolveTRSField(grantSnapshot, userMeta, "TRSInfluencedDecision", "RuntimeTRSInfluencedDecision", false)), ...
    "TRSInfluenceDefinition", string(localResolveTRSField(grantSnapshot, userMeta, "TRSInfluenceDefinition", "RuntimeTRSInfluenceDefinition", "")), ...
    "TRSReceiverIntegrationStatus", string(localResolveTRSField(grantSnapshot, userMeta, "TRSReceiverIntegrationStatus", "RuntimeTRSReceiverIntegrationStatus", "")), ...
    "TRSReceiverIntegrationBlocker", string(localResolveTRSField(grantSnapshot, userMeta, "TRSReceiverIntegrationBlocker", "RuntimeTRSReceiverIntegrationBlocker", "")));
end

function value = localResolveTRSField(grantSnapshot, userMeta, grantField, userField, defaultValue)
if isstruct(grantSnapshot) && isfield(grantSnapshot, grantField)
    value = grantSnapshot.(grantField);
    return;
end
if isstruct(userMeta) && isfield(userMeta, userField)
    value = userMeta.(userField);
    return;
end
value = defaultValue;
end

function mode = localResolveActualMCSSelectionMode(cfg, direction)
mode = "configured_fixed";
if localResolveLinkAdaptationMode(cfg, direction) ~= "fixed"
    switch sixgr.link.resolveLinkAdaptationDomain(cfg, direction)
        case "effective_sinr"
            mode = "effective_sinr_driven";
        case "bler_margin"
            mode = "bler_margin_proxy";
        case "legacy_mcs"
            mode = "legacy_mcs_smoothed";
        otherwise
            mode = "cqi_driven";
    end
end
end

function [sinr_dB, meta] = localEVMProxySINR(modTrack)
sinr_dB = NaN;
meta = struct( ...
    "Source", "evm_proxy_not_true_post_equalization_sinr", ...
    "ValueRole", "diagnostic_evm_proxy_not_scheduling_input", ...
    "ValueStatus", "unavailable", ...
    "Definition", "10log10(1/EVM_rms^2)_post_decode_diagnostic_proxy_not_ts38214_post_equalization_sinr", ...
    "SchedulingEligible", false, ...
    "NAReason", "evm_unavailable");
evm = double(sixgr.util.structGet(modTrack, "EVM_rms", NaN));
if ~(isscalar(evm) && isfinite(evm) && evm > 0)
    return;
end
sinr_dB = 10 * log10(1 / max(evm .^ 2, eps));
meta.ValueStatus = "OK";
meta.NAReason = "";
end

function [cqi, modulation, targetCodeRate, mcsIndex] = localCQIAndMCSFromSINR(sinr_dB, cfg, direction)
cqi = NaN;
modulation = "";
targetCodeRate = NaN;
mcsIndex = NaN;
if ~(isscalar(sinr_dB) && isfinite(sinr_dB))
    return;
end
try
    feedback = sixgr.link.resolveWidebandCQI(struct( ...
        "WidebandSINR_dB", double(sinr_dB), ...
        "SINRSource", "post_equalization_sinr_from_equalizer_channel_estimate", ...
        "SINRValueRole", "measured_post_equalization_scheduling_input", ...
        "SINRValueStatus", "OK"), cfg, direction);
    cqi = double(sixgr.util.normalizeReportedCQI(sixgr.util.structGet(feedback, "WidebandCQI", NaN)));
    if isfinite(cqi)
        [modulation, targetCodeRate, mcsIndex] = sixgr.link.amcFromCQI(cqi, "", NaN, cfg, direction);
    end
catch
    cqi = NaN;
    modulation = "";
    targetCodeRate = NaN;
    mcsIndex = NaN;
end
end

function tf = localCQIReportingEnabled(cfg, direction)
tf = true;
direction = upper(string(direction));
if direction == "UL"
    paths = ["phy.csi.reportULCQI", "phy.csi.ul.reportCQI", ...
        "phy.ul.csi.reportCQI", "phy.pusch.reportCQI", "phy.csi.reportCQI"];
else
    paths = ["phy.csi.reportDLCQI", "phy.csi.dl.reportCQI", ...
        "phy.dl.csi.reportCQI", "phy.pdsch.reportCQI", "phy.csi.reportCQI"];
end
for idx = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(idx), []);
    if isempty(raw)
        continue;
    end
    [ok, value] = localParseLogicalScalar(raw);
    if ok
        tf = value;
        return;
    end
end
end

function [ok, value] = localParseLogicalScalar(raw)
ok = false;
value = false;
if islogical(raw) && isscalar(raw)
    ok = true;
    value = logical(raw);
    return;
end
if isnumeric(raw) && isscalar(raw) && isfinite(raw)
    ok = true;
    value = raw ~= 0;
    return;
end
if ischar(raw) || (isstring(raw) && isscalar(raw))
    token = lower(strtrim(string(raw)));
    if any(token == ["true", "enabled", "enable", "on", "yes", "1"])
        ok = true;
        value = true;
    elseif any(token == ["false", "disabled", "disable", "off", "no", "0"])
        ok = true;
        value = false;
    end
end
end

function source = localResolveCQISourceColumn(T, configuredDomain)
n = height(T);
source = repmat("unavailable", n, 1);
existingSource = string(localOptionalColumn(T, "CQISource", ""));
existingMask = strlength(strtrim(existingSource)) > 0 & lower(strtrim(existingSource)) ~= "unavailable";
widebandCQI = double(localOptionalColumn(T, "WidebandCQI", NaN));
postEqSINR = double(localOptionalColumn(T, "PostEqSINR_dB", localOptionalColumn(T, "MeasuredTrialSINR_dB", localOptionalColumn(T, "MeasuredSINR_dB", NaN))));
postEqSource = lower(strtrim(string(localOptionalColumn(T, "PostEqSINRSource", localOptionalColumn(T, "MeasuredTrialSINRSource", "")))));
cqiMask = isfinite(widebandCQI);
source(cqiMask) = "runtime_reported_cqi";
source(existingMask) = existingSource(existingMask);
dataDomainMask = cqiMask & ~existingMask & contains(postEqSource, "post_equalization");
source(dataDomainMask) = "post_equalization_sinr_to_cqi";
effMask = ~existingMask & ~cqiMask & configuredDomain == "effective_sinr" & isfinite(postEqSINR);
source(effMask) = "runtime_effective_sinr";
blerMask = ~existingMask & ~cqiMask & configuredDomain == "bler_margin" & isfinite(postEqSINR);
source(blerMask) = "runtime_effective_sinr_proxy_for_bler_margin";
end

function source = localResolveMCSSelectionSourceToken(cfg, direction)
selectionMode = lower(strtrim(string( ...
    localResolveActualMCSSelectionMode(cfg, direction))));
linkMode = lower(strtrim(string(localResolveLinkAdaptationMode(cfg, direction))));
fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled", ...
    "off","none","false",""];
adaptiveTokens = ["amc","adaptive","cqi","cqi_driven","baseline", ...
    "actual_bler_based","effective_sinr_driven"];
if ismember(linkMode, fixedTokens) && ~ismember(selectionMode, adaptiveTokens)
    if selectionMode == "fixed_modulation"
        source = "configured_modulation_code_rate";
    else
        source = "configured_fixed_mcs";
    end
    return;
end
switch sixgr.link.resolveLinkAdaptationDomain(cfg, direction)
    case "effective_sinr"
        source = "effective_sinr_to_cqi_to_amc";
    case "bler_margin"
        source = "bler_margin_proxy_to_amc";
    case "legacy_mcs"
        source = "legacy_mcs_domain_smoothing";
    otherwise
        source = "runtime_cqi_to_amc";
end
end

function [source, status] = localResolveMCSSelectionEvidenceColumns(T, cfg, direction)
n = height(T);
configuredSource = localResolveMCSSelectionSourceToken(cfg, direction);
source = repmat(configuredSource, n, 1);
status = repmat("configured_runtime_policy", n, 1);
fixedByConfiguration = any(configuredSource == ...
    ["configured_fixed_mcs","configured_modulation_code_rate"]);
if fixedByConfiguration
    status(:) = "configured";
end
if ~(istable(T) && n > 0)
    return;
end
mode = lower(strtrim(string(localOptionalColumn(T, "SchedulerGrantMCSSelectionMode", ""))));
bootstrapMask = mode == "bootstrap_cqi_conservative";
source(bootstrapMask) = "bootstrap_cqi_conservative_lab_default";
status(bootstrapMask) = "bootstrap_not_measured_cqi";
cqiMask = mode == "cqi_table";
source(cqiMask) = "runtime_cqi_table";
status(cqiMask) = "measured_cqi_mapped";
ollaApplied = logical(localOptionalColumn(T, "OuterLoopApplied", false));
ollaDelta = double(localOptionalColumn(T, "OLLADeltaDb", localOptionalColumn(T, "OLLADeltaMCS", NaN)));
feedbackAdaptedMask = cqiMask & ollaApplied & isfinite(ollaDelta) & abs(ollaDelta) > 0;
status(feedbackAdaptedMask) = "measured_feedback_adapted";
fixedMCSMask = mode == "fixed_mcs";
source(fixedMCSMask) = "configured_fixed_mcs";
status(fixedMCSMask) = "configured";
fixedModMask = mode == "fixed_modulation";
source(fixedModMask) = "configured_modulation_code_rate";
status(fixedModMask) = "configured";
existingSource = strtrim(string(localOptionalColumn(T, "MCSSelectionSource", "")));
existingStatus = strtrim(string(localOptionalColumn(T, "MCSValueStatus", "")));
source(strlength(existingSource) > 0) = existingSource(strlength(existingSource) > 0);
status(strlength(existingStatus) > 0) = existingStatus(strlength(existingStatus) > 0);
if fixedByConfiguration
    % A fixed calibration point cannot truthfully inherit the generic CQI
    % default carried by an undecorated trial row.  Its operating point is
    % owned by the configured MCS/modulation policy and ILA/OLLA are not
    % executed.
    source(:) = configuredSource;
    status(:) = "configured";
end
end

function token = localResolveOLLADomainToken(cfg, direction)
if ~logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", false))
    token = "disabled";
    return;
end
domain = sixgr.link.resolveLinkAdaptationDomain(cfg, direction);
if domain == "bler_margin"
    token = "bler_margin_proxy_delta_db";
elseif domain == "legacy_mcs"
    token = "delta_mcs";
else
    token = "delta_db_required_sinr_margin";
end
end

function profile = localResolveLinkAdaptationCalibrationProfile(cfg, direction)
switch sixgr.link.resolveLinkAdaptationDomain(cfg, direction)
    case "effective_sinr"
        profile = "effective_sinr:" + localResolveSINRToCQIModeToken(cfg, direction);
    case "bler_margin"
        profile = "heuristic_bler_margin_proxy";
    case "legacy_mcs"
        profile = "legacy_mcs_domain_smoothing";
    otherwise
        profile = "cqi_table_amc";
end
end

function token = localResolveSINRToCQIModeToken(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.pusch.sinrToCQIMode"
        "phy.csi.ulSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
else
    candidates = [ ...
        "phy.pdsch.sinrToCQIMode"
        "phy.csi.dlSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
end
token = "threshold_table";
for i = 1:numel(candidates)
    raw = lower(strtrim(string(sixgr.util.structGet(cfg, candidates(i), ""))));
    if strlength(raw) > 0
        token = raw;
        return;
    end
end
end

function tableToken = localResolveCQITable(cfg, direction)
tableToken = string(sixgr.link.resolveConfiguredCQITable(cfg, direction));
end

function tableToken = localResolveMCSTable(cfg, direction)
tableToken = string(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
end

function trace = localResolveULPrecodingTrace(cfg, tx, grant)
if nargin < 3 || ~isstruct(grant)
    grant = struct();
end
pusch = sixgr.util.structGet(tx, "PUSCH", []);
prec = sixgr.phy.ul.validatePUSCHPrecoderEvidence(tx);
transformPrecoding = logical(pusch.TransformPrecoding);
precodingActive = logical(prec.Active);
beamformingApplied = logical(prec.BeamformingApplied);
appliedPMI = localOptionalPUSCHPMI(prec.PMI);
requestedPMI = localOptionalPUSCHPMI(sixgr.util.structGet(grant, "PMI", ...
    sixgr.util.structGet(cfg, "phy.pusch.TPMI", ...
    sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN))));
digestEvidence = sixgr.phy.grant.resolvePrecoderDigestEvidence(grant, prec);
appliedPrecoderMatrixSHA256 = string(digestEvidence.AppliedPrecoderMatrixSHA256);
trace = struct( ...
    "ConfiguredBeamSelectionStrategy", string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")), ...
    "PrecoderSource", string(prec.Source), ...
    "PrecodingMode", string(prec.Mode), ...
    "PrecodingApplicationStage", string(prec.ApplicationStage), ...
    "PrecodingActive", logical(precodingActive), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(prec, "ExplicitBeamWeightsApplied", false)), ...
    "TransformPrecodingApplied", logical(transformPrecoding), ...
    "BeamformingApplied", logical(beamformingApplied), ...
    "AppliedBeamIndexSet", localFormatIndexSet(prec.BeamIndices), ...
    "AppliedCodebookPortIndexSet", localFormatIndexSet(prec.CodebookPortIndices1Based), ...
    "AppliedCodebookPortIndexDefinition", string(prec.CodebookPortIndexDefinition), ...
    "AppliedPrecoderPMI", double(appliedPMI), ...
    "AppliedPrecoderPMIType", string(prec.PMIType), ...
    "AppliedPrecoderCodebookMode", string(prec.CodebookMode), ...
    "AppliedPrecoderMatrixSHA256", appliedPrecoderMatrixSHA256, ...
    "RequestedPrecoderSHA256", string(digestEvidence.RequestedPrecoderSHA256), ...
    "AppliedPrecoderSHA256", string(digestEvidence.AppliedPrecoderSHA256), ...
    "PrecoderDigestDomain", string(digestEvidence.PrecoderDigestDomain), ...
    "FrozenGrantContextId", string(digestEvidence.FrozenGrantContextId), ...
    "RequestedVsAppliedPrecoderPMIMatchStatus", localRequestedVsAppliedPMIStatus(requestedPMI, appliedPMI), ...
    "PrecodingNumPorts", double(prec.NumPorts), ...
    "PrecodingNumLogicalPorts", double(prec.NumLogicalPorts), ...
    "PrecodingNumLayers", double(prec.NumLayers), ...
    "PrecodingMatrixRows", double(prec.MatrixRows), ...
    "PrecodingMatrixCols", double(prec.MatrixCols));
end

function contract = localResolvePUSCHThroughputExecutionContract( ...
        cfg, requestedProfile, schedulerDrivenGrant, grant, phyGrant)
% Resolve one immutable execution-ownership label for the entire UL call.
% Scheduler truth is never inferred from a PHY result: it must agree with
% both the YAML-derived configuration and the explicit worker-job value.
configuredPHY = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "phy.pusch.executionProfile", ""))));
configuredRun = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "run.puschExecutionProfile", ""))));
if strlength(configuredPHY) > 0 && strlength(configuredRun) > 0 ...
        && configuredPHY ~= configuredRun
    error("sixgr:pusch:ExecutionProfileMismatch", ...
        ['phy.pusch.executionProfile=''%s'' conflicts with ' ...
        'run.puschExecutionProfile=''%s''.'], configuredPHY, configuredRun);
end
configured = configuredPHY;
if strlength(configured) == 0
    configured = configuredRun;
end
requested = lower(strtrim(string(requestedProfile)));
if ~isscalar(requested)
    error("sixgr:pusch:InvalidExecutionProfile", ...
        "PUSCH ExecutionProfile must be a scalar string.");
end
if strlength(requested) > 0 && strlength(configured) > 0 ...
        && requested ~= configured
    error("sixgr:pusch:ExecutionProfileMismatch", ...
        "Requested PUSCH profile '%s' conflicts with configured '%s'.", ...
        requested, configured);
end
profile = requested;
if strlength(profile) == 0
    profile = configured;
end

allowed = ["connected_strict","scheduler_truth","phy_calibration"];
if strlength(profile) > 0 && ~any(profile == allowed)
    error("sixgr:pusch:UnsupportedExecutionProfile", ...
        "Unsupported PUSCH execution profile '%s'.", profile);
end
if schedulerDrivenGrant
    if strlength(profile) == 0
        error("sixgr:pusch:MissingSchedulerExecutionProfile", ...
            ['A scheduler/frozen UL grant requires pusch.execution_profile=' ...
            '''scheduler_truth'' and an explicit scheduler-owned worker job.']);
    end
    if profile ~= "scheduler_truth"
        error("sixgr:pusch:CalibrationSchedulerOwnershipForbidden", ...
            ['A scheduler/frozen grant cannot be relabeled as %s. ' ...
            'Use scheduler_truth with decoded control binding evidence.'], ...
            profile);
    end
    localRequirePUSCHSchedulerTruthGrant(grant, phyGrant);
elseif profile == "scheduler_truth"
    error("sixgr:pusch:MissingSchedulerTruthGrant", ...
        "scheduler_truth requires an exact scheduler/frozen UL grant.");
end

if profile == "scheduler_truth"
    taxonomy = "decoded_scheduler_grant_owned_pusch";
    backend = "scheduler_grant_waveform_chain";
    calibrationProvenance = "";
elseif profile == "phy_calibration"
    taxonomy = "isolated_phy_calibration";
    backend = "canonical_pusch_waveform_chain";
    calibrationProvenance = "explicit_phy_calibration_request";
elseif profile == "connected_strict"
    taxonomy = "connected_ul_waveform_execution";
    backend = "canonical_pusch_waveform_chain";
    calibrationProvenance = "";
else
    % Legacy direct calls remain executable, but their evidence is
    % deliberately unclassified and therefore cannot be promoted to
    % scheduler truth by a downstream exporter.
    profile = "unclassified_direct_link";
    taxonomy = "unclassified_direct_ul_waveform";
    backend = "canonical_pusch_waveform_chain";
    calibrationProvenance = "";
end
contract = struct( ...
    "Profile", profile, ...
    "Taxonomy", taxonomy, ...
    "Backend", backend, ...
    "CalibrationProvenance", calibrationProvenance);
end

function localRequirePUSCHSchedulerTruthGrant(grant, phyGrant)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    grant = sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot", struct());
end
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    error("sixgr:pusch:MissingSchedulerTruthGrant", ...
        "scheduler_truth requires a nonempty exact UL scheduler grant.");
end
if ~logical(sixgr.util.structGet(grant, ...
        "ExactPHYFeasibilityChecked", false)) || ...
        ~logical(sixgr.util.structGet(grant, "ExactPHYFeasible", false))
    error("sixgr:pusch:SchedulerTruthGrantNotFeasible", ...
        "scheduler_truth requires a finalized exactly feasible UL PHY grant.");
end
if ~logical(sixgr.util.structGet(grant, ...
        "PDCCHGrantBindingRequired", false)) || ...
        ~logical(sixgr.util.structGet(grant, "PDCCHGrantBindingOk", false)) || ...
        ~logical(sixgr.util.structGet(grant, "ControlDecodeOk", false)) || ...
        ~logical(sixgr.util.structGet(grant, "DCICrcPass", false)) || ...
        ~logical(sixgr.util.structGet(grant, "PDCCHPayloadMatch", false))
    error("sixgr:pusch:SchedulerTruthControlBindingMissing", ...
        ['scheduler_truth requires decoded UL DCI CRC/payload agreement ' ...
        'and a successful exact PDCCH-to-grant binding.']);
end
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)))
    phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
end
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)))
    error("sixgr:pusch:SchedulerTruthFrozenGrantMissing", ...
        "scheduler_truth requires the immutable frozen UL PHYGrant.");
end
sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
    "run_ul_pusch_scheduler_truth_entry");
end

function digest = localResolveAppliedPrecoderMatrixSHA256(prec)
digest = lower(strtrim(string(sixgr.util.structGet(prec, ...
    "AppliedMatrixSHA256", ""))));
if strlength(digest) == 0
    matrix = sixgr.util.structGet(prec, "MatrixPorts", []);
    if ~isempty(matrix)
        digest = lower(string(sixgr.phy.mimo.MatrixContract.digest(double(matrix))));
    end
end
if strlength(digest) > 0 && isempty(regexp(char(digest), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:link:runULPUSCHThroughput:InvalidAppliedPrecoderDigest", ...
        "Runtime PUSCH precoder emitted an invalid applied-matrix SHA-256 identity.");
end
end

function trace = localResolveInterferencePrecodingTrace(replay)
trace = sixgr.link.resolveInterferencePrecodingTrace(replay);
end

function token = localFormatIndexSet(values)
if isstring(values) || ischar(values)
    token = string(values);
    return;
end
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
token = join(string(round(values)), "|");
end

function token = localFormatNumericVector(values)
if isstring(values) || ischar(values)
    token = string(values);
    return;
end
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
parts = strings(1, numel(values));
for ii = 1:numel(values)
    parts(ii) = string(sprintf("%.6g", values(ii)));
end
token = join(parts, "|");
end

function token = localBitVectorToken(bits)
% Preserve the receiver-observed HARQ-ACK vector exactly in CSV-safe form.
% Empty means no UCI bits were produced; it is never replaced with the
% configured/expected payload.
if isempty(bits)
    token = "";
    return;
end
bits = int8(bits(:).');
if any(~ismember(double(bits), [0 1]))
    error("sixgr:link:InvalidDecodedHARQACKBits", ...
        "Decoded HARQ-ACK evidence must contain only binary values.");
end
token = join(string(double(bits)), "|");
end

function value = localOptionalPUSCHPMI(raw)
% Scalar reporting contract only; do not alter the native PUSCH configuration.
if isempty(raw)
    value = NaN;
    return;
end
if ~(isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
        (isnan(raw) || (isfinite(raw) && raw >= 0 && raw == fix(raw))))
    error("sixgr:link:InvalidPUSCHPMIEvidence", ...
        "PUSCH PMI evidence must be empty, NaN, or one nonnegative integer; non-scalar indices cannot be truncated into a TPMI.");
end
value = double(raw);
end

function status = localRequestedVsAppliedPMIStatus(requestedPMI, appliedPMI)
requestedPMI = localOptionalPUSCHPMI(requestedPMI);
appliedPMI = localOptionalPUSCHPMI(appliedPMI);
requestedFinite = isfinite(requestedPMI);
appliedFinite = isfinite(appliedPMI);
if requestedFinite && appliedFinite
    if round(double(requestedPMI)) == round(double(appliedPMI))
        status = "requested_matches_runtime_applied";
    else
        status = "requested_differs_from_runtime_applied";
    end
elseif requestedFinite && ~appliedFinite
    status = "requested_present_applied_unavailable";
elseif ~requestedFinite && appliedFinite
    status = "runtime_applied_without_request_reference";
else
    status = "no_requested_or_applied_pmi";
end
end

function source = localResolveULPrecoderSource(transformPrecoding)
if logical(transformPrecoding)
    source = "ul_pusch_transform_precoding";
else
    source = "ul_direct_mapping_no_explicit_beam_weights";
end
end

function mode = localResolveULPrecodingMode(transformPrecoding)
if logical(transformPrecoding)
    mode = "transform_precoding";
else
    mode = "direct_mapping_no_explicit_beam_weights";
end
end

function stage = localResolveULPrecodingStage(transformPrecoding)
if logical(transformPrecoding)
    stage = "dft_spread_before_re_mapping";
else
    stage = "re_mapping_without_explicit_beam_weights";
end
end

function metrics = localAnalyzeChannelMetrics(Hest, nVar, cfg, rx, precoderTrace)
if nargin < 4
    rx = struct();
end
if nargin < 5
    precoderTrace = struct();
end
metrics = sixgr.phy.ul.measureULLinkState(Hest, nVar, cfg, ...
    "ReceivedGrid", sixgr.util.structGet(rx, "RxGrid", []), ...
    "ReferenceIndices", sixgr.util.structGet(rx, "DMRSIndices", []), ...
    "ReferenceSymbols", sixgr.util.structGet(rx, "DMRSSymbols", []), ...
    "PrecoderInfo", precoderTrace, ...
    "ChannelEstimateDomain", "pusch_dmrs_effective_layer_domain");
% A PUSCH DM-RS estimate observes the already-precoded effective layer
% channel.  It cannot be reused as an unprecoded SRS port-domain estimate
% to rescore alternative TPMIs.  Preserve the waveform-applied TPMI as
% runtime truth and make the unavailable recommendation/beam comparison
% explicit instead of manufacturing a best-beam hit from the wrong
% codebook/domain.
metrics.BeamObservationDomain = "pusch_dmrs_effective_layer_channel";
if strcmpi(string(sixgr.util.structGet(precoderTrace, "PrecodingMode", "")), "ul_codebook_tpmi")
    metrics.PMI = metrics.RuntimeAppliedPMI;
    if isfinite(metrics.RuntimeAppliedPMI)
        metrics.PMISource = "ul_runtime_applied_codebook_tpmi_from_pusch_waveform";
    end
    metrics.CSIReportMode = "ul_pusch_dmrs_effective_channel_no_tpmi_recommendation";
    metrics.SRSRITPMIValid = false;
    metrics.TPMICandidateCount = NaN;
    metrics.TPMIMutualInformation = NaN;
end
metrics.PilotSINR_dB = double(sixgr.util.structGet(metrics, "SINR_dB", NaN));
metrics.PilotSINRSource = string(sixgr.util.structGet(metrics, "SINRSource", ""));
postEqSINR = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
postEqSource = string(sixgr.util.structGet(rx, "PostEqSINRSource", ""));
postEqRole = string(sixgr.util.structGet(rx, "PostEqSINRValueRole", ""));
postEqStatus = string(sixgr.util.structGet(rx, "PostEqSINRValueStatus", ""));
postEqReason = string(sixgr.util.structGet(rx, "PostEqSINRNAReason", ""));
reportCQI = localCQIReportingEnabled(cfg, "UL");
selectedSINR = localSelectULMeasuredTrialSINRFromEvidence( ...
    postEqSINR, postEqSource, postEqRole, postEqStatus, postEqReason);
if isfinite(double(selectedSINR.Value))
    metrics.SINR_dB = double(selectedSINR.Value);
    metrics.SINRSource = char(string(selectedSINR.Source));
    metrics.SINRValueRole = char(string(selectedSINR.ValueRole));
    metrics.SINRValueStatus = char(string(selectedSINR.ValueStatus));
    metrics.SINRNAReason = char(string(selectedSINR.NAReason));
    if reportCQI
        feedback = sixgr.link.resolveWidebandCQI(struct( ...
            "WidebandSINR_dB", double(selectedSINR.Value), ...
            "SINRSource", char(string(selectedSINR.Source)), ...
            "SINRValueRole", char(string(selectedSINR.ValueRole)), ...
            "SINRValueStatus", char(string(selectedSINR.ValueStatus))), cfg, "UL");
        rawCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
        if isfinite(rawCQI)
            metrics.CQI = double(max(0, min(15, round(rawCQI))));
            metrics.CQISource = "ul_selected_receiver_evidence_sinr_to_cqi:" + string(sixgr.util.structGet(feedback, "Mode", "sinr_threshold_table"));
            metrics.CQIValueStatus = "OK";
        else
            metrics.CQI = NaN;
            metrics.CQISource = "ul_selected_receiver_evidence_sinr_to_cqi_unavailable";
            metrics.CQIValueStatus = "unavailable";
        end
    else
        metrics.CQI = NaN;
        metrics.CQISource = "cqi_reporting_disabled";
        metrics.CQIValueStatus = "disabled";
    end
else
    metrics.SINR_dB = NaN;
    metrics.SINRSource = "post_equalization_sinr_unavailable";
    metrics.SINRValueRole = "unavailable";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "post_equalization_sinr_missing_or_not_scheduler_eligible";
    metrics.CQI = NaN;
    metrics.CQISource = "ul_post_equalization_sinr_unavailable_no_cqi";
    metrics.CQIValueStatus = "unavailable";
end

if isempty(Hest)
    return;
end

gain = mean(abs(Hest(:)).^2, "omitnan");
if isfinite(gain) && gain > 0
    metrics.ChannelGain_dB = 10 * log10(gain);
    [pilotNmseLin, detectionMetric] = localPilotResidualChannelMetrics(rx, Hest);
    if isfinite(pilotNmseLin) && pilotNmseLin >= 0
        metrics.NMSE_dB = 10 * log10(max(pilotNmseLin, eps));
        metrics.DetectionMetric = detectionMetric;
    else
        nmseLin = max(double(nVar), eps) / max(gain, eps);
        metrics.NMSE_dB = 10 * log10(max(nmseLin, eps));
        metrics.DetectionMetric = 1 / (1 + nmseLin);
    end
end

Hwb = localWidebandChannelMatrix(Hest);
if isempty(Hwb)
    return;
end
metrics.NumRxAnt = size(Hwb, 1);
metrics.NumTxPorts = size(Hwb, 2);
try
    [metrics.ConditionNumber_dB, metrics.ConditionNumberStatus, metrics.RankEstimate] = ...
        sixgr.mimo.channelConditionNumber(Hwb);
catch
end
beamMetrics = localComputeBeamMetrics(Hwb, cfg, metrics);
beamFields = fieldnames(beamMetrics);
for f = 1:numel(beamFields)
    metrics.(beamFields{f}) = beamMetrics.(beamFields{f});
end
end

function selected = localSelectULMeasuredTrialSINRFromEvidence( ...
    postEqSINR, postEqSource, postEqRole, postEqStatus, postEqReason)
selected = struct( ...
    "Value", NaN, ...
    "Source", "", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "no_scheduler_eligible_ul_receiver_sinr");
postEqSINR = double(postEqSINR);
postEqSource = string(postEqSource);
postEqRole = string(postEqRole);
postEqStatus = string(postEqStatus);
postEqReason = string(postEqReason);

postEqAvailable = isfinite(postEqSINR) && localPostEqSINRIsSchedulerEligible(postEqSource, postEqRole, postEqStatus);
if postEqAvailable
    % The scheduler-facing UL SINR is the receiver's data-domain
    % post-equalization measurement. DM-RS/SRS reconstruction quality is
    % retained as separately named diagnostic evidence; it is not a bound
    % on the data-domain SINR and must never replace or clip this value.
    selected.Value = double(postEqSINR);
    selected.Source = char(postEqSource);
    selected.ValueRole = char(postEqRole);
    selected.ValueStatus = char(postEqStatus);
    selected.NAReason = char(postEqReason);
end
end

function tf = localPostEqSINRIsSchedulerEligible(source, role, status)
token = lower(strjoin([string(source), string(role), string(status)], " "));
words = string(regexp(char(token), '[a-z0-9]+', 'match'));
blocked = ["receiverhest", "receiver_hest", "pilot", ...
    "reference_signal", "evm_proxy", "proxy", "fallback", "configured", "sweep", ...
    "unavailable", "failed", "rejected"];
tf = contains(token, "post_equalization") && ~any(words == "hest") && ~any(contains(token, blocked));
end

function args = localBuildCSIFeedbackArgs(rx)
args = {};
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
rxGrid = sixgr.util.structGet(rx, "RxGrid", []);
refInd = sixgr.util.structGet(rx, "DMRSIndices", []);
refSym = sixgr.util.structGet(rx, "DMRSSymbols", []);
if isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    return;
end
args = {"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym};
end

function Hwb = localWidebandChannelMatrix(Hest)
% Preserve frequency/time-selective channel energy.  A coherent complex
% average across the resource grid can cancel valid phase rotations and
% must not be used for spatial-condition or codebook metrics.
Hwb = sixgr.mimo.channelEstimateSnapshots(Hest);
end

function beam = localComputeBeamMetrics(Hwb, cfg, metrics)
beam = struct( ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "BeamHit", NaN, ...
    "TopKBeamHit", NaN, ...
    "BeamCandidateCount", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "BeamScoreVector_dB", "", ...
    "TopBeamIndexSet", "", ...
    "TopBeamGainSet_dB", "", ...
    "BeamScoreSource", "");

if isempty(Hwb) || ndims(Hwb) > 3
    return;
end
observationDomain = lower(strtrim(string(sixgr.util.structGet(metrics, ...
    "BeamObservationDomain", ""))));
if observationDomain == "pusch_dmrs_effective_layer_channel"
    % PUSCH DM-RS is precoded with the scheduled TPMI.  Its channel
    % estimate is therefore an effective layer-domain observation and
    % contains no independent port-domain evidence for counterfactual
    % TPMI/beam scoring.  Applied beam/TPMI truth remains available in the
    % dedicated Applied* columns; BestBeam/BeamHit must stay N/A.
    beam.BeamScoreSource = ...
        "not_evaluated_pusch_dmrs_effective_layer_channel_cannot_rescore_tpmi";
    return;
end
nTx = size(Hwb, 2);
if ~(isfinite(nTx) && nTx >= 1)
    return;
end

codebookBeam = localComputePMICodebookCandidateMetrics(Hwb, cfg, metrics);
if ~isempty(fieldnames(codebookBeam)) && isfinite(double(codebookBeam.BeamCandidateCount))
    beam = codebookBeam;
    return;
end

beamCountCfg = max(1, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", nTx))));
selectedBeamHint = double(sixgr.util.structGet(metrics, "SelectedBeamIndices", []));
selectedBeamHint = selectedBeamHint(isfinite(selectedBeamHint));
maxSelectedBeam = 0;
if ~isempty(selectedBeamHint)
    maxSelectedBeam = max(selectedBeamHint);
end
usePMICodebook = isfinite(double(sixgr.util.structGet(metrics, "PMI", NaN))) || ~isempty(selectedBeamHint);
if ~usePMICodebook
    return;
end
if usePMICodebook
    numBeams = max([beamCountCfg, maxSelectedBeam, 2 * nTx]);
    W = localOversampledDFTCodebook(nTx, numBeams);
else
    arr = localInferBeamArrayGeometry(cfg, nTx);
    try
        W = sixgr.rf.BeamRefinementCSIRS.makeCodebookFromArray(arr);
    catch
        W = [];
    end
    if ~isempty(W)
        W = W(:, 1:min(size(W, 2), beamCountCfg));
    end
end
if isempty(W)
    return;
end

metric = sum(abs(double(Hwb) * double(W)).^2, 1);
if isempty(metric) || ~any(isfinite(metric))
    return;
end
metricDb = 10 * log10(max(metric, eps));
[bestMetric, bestIdx] = max(metric);
selectedSet = localResolveSelectedBeamSet(cfg, W, metrics);
selectedSet = localClampBeamIndexSet(selectedSet, size(W, 2));
hasSelected = ~isempty(selectedSet);

order = find(isfinite(metric));
[~, ordLocal] = sort(metric(order), "descend");
ord = order(ordLocal);
topK = max(1, min(2, numel(ord)));
traceK = max(1, min(8, numel(ord)));
beamStrategy = lower(string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")));
if ~hasSelected
    selectedIdx = NaN;
    selectedMetric = NaN;
elseif beamStrategy == "fixed_first_beam"
    selectedIdx = selectedSet(1);
    selectedMetric = metric(selectedIdx);
else
    selectedMetrics = metric(selectedSet);
    [selectedMetric, selectedLocalIdx] = max(selectedMetrics);
    selectedIdx = selectedSet(selectedLocalIdx);
end

beam.BeamCandidateCount = double(size(W, 2));
beam.SelectedBeamIndex = double(selectedIdx);
beam.BestBeamIndex = double(bestIdx);
if ~hasSelected
    beam.BeamHit = NaN;
    beam.TopKBeamHit = NaN;
elseif beamStrategy == "fixed_first_beam"
    beam.BeamHit = double(selectedIdx == bestIdx);
    beam.TopKBeamHit = double(ismember(selectedIdx, ord(1:topK)));
else
    beam.BeamHit = double(any(selectedSet == bestIdx));
    beam.TopKBeamHit = double(any(ismember(ord(1:topK), selectedSet)));
end
beam.SelectedBeamGain_dB = localPositivePowerToDb(selectedMetric);
beam.BestBeamGain_dB = localPositivePowerToDb(bestMetric);
beam.BeamGainGap_dB = localFiniteDifference(beam.BestBeamGain_dB, ...
    beam.SelectedBeamGain_dB);
beam.BeamScoreVector_dB = localFormatNumericVector(metricDb);
beam.TopBeamIndexSet = localFormatIndexSet(ord(1:traceK));
beam.TopBeamGainSet_dB = localFormatNumericVector(metricDb(ord(1:traceK)));
beam.BeamScoreSource = "wideband_hest_codebook_projection";
end

function beam = localComputePMICodebookCandidateMetrics(Hwb, cfg, metrics)
beam = struct();
if isempty(Hwb) || ndims(Hwb) > 3 || size(Hwb, 2) <= 1
    return;
end
nTx = size(Hwb, 2);
nLayers = localResolveLayerCount(cfg, metrics);
codebookMode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ...
    sixgr.util.structGet(cfg, "phy.pusch.codebookType", "type1_su_mimo")));
try
    candidates = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, nTx, "Mode", codebookMode);
catch
    candidates = struct([]);
end
if isempty(candidates)
    return;
end
metric = nan(1, numel(candidates));
for ii = 1:numel(candidates)
    W = candidates(ii).W;
    if isempty(W) || size(W, 1) ~= nTx
        continue;
    end
    metric(ii) = sixgr.phy.dl.frequencySelectivePrecoderPower(Hwb, W);
end
if ~any(isfinite(metric))
    return;
end
metricDb = 10 * log10(max(metric, eps));
[bestMetric, bestIdx] = max(metric);
selectedIdx = localResolveSelectedPMICandidateIndex(cfg, metrics, candidates);
hasSelected = isfinite(selectedIdx) && selectedIdx >= 1 && selectedIdx <= numel(candidates);
if hasSelected
    selectedMetric = metric(selectedIdx);
else
    selectedMetric = NaN;
end
order = find(isfinite(metric));
[~, ordLocal] = sort(metric(order), "descend");
ord = order(ordLocal);
topK = max(1, min(2, numel(ord)));
traceK = max(1, min(8, numel(ord)));
beam = struct( ...
    "SelectedBeamIndex", double(selectedIdx), ...
    "BestBeamIndex", double(bestIdx), ...
    "BeamHit", double(localNaNWhenFalse(hasSelected, selectedIdx == bestIdx)), ...
    "TopKBeamHit", double(localNaNWhenFalse(hasSelected, ismember(selectedIdx, ord(1:topK)))), ...
    "BeamCandidateCount", double(numel(candidates)), ...
    "SelectedBeamGain_dB", localPositivePowerToDb(selectedMetric), ...
    "BestBeamGain_dB", localPositivePowerToDb(bestMetric), ...
    "BeamGainGap_dB", localFiniteDifference(localPositivePowerToDb(bestMetric), ...
        localPositivePowerToDb(selectedMetric)), ...
    "BeamScoreVector_dB", localFormatNumericVector(metricDb), ...
    "TopBeamIndexSet", localFormatIndexSet(ord(1:traceK)), ...
    "TopBeamGainSet_dB", localFormatNumericVector(metricDb(ord(1:traceK))), ...
    "BeamScoreSource", "wideband_hest_3gpp_type1_pmi_candidate_projection");
end

function valueDb = localPositivePowerToDb(value)
valueDb = NaN;
if isscalar(value) && isfinite(value) && value > 0
    valueDb = double(10 * log10(value));
end
end

function delta = localFiniteDifference(lhs, rhs)
delta = NaN;
if isscalar(lhs) && isscalar(rhs) && isfinite(lhs) && isfinite(rhs)
    delta = double(lhs - rhs);
end
end

function out = localNaNWhenFalse(hasValue, value)
if logical(hasValue)
    out = double(value);
else
    out = NaN;
end
end

function selectedIdx = localResolveSelectedPMICandidateIndex(cfg, metrics, candidates)
selectedIdx = NaN;
pmi = double(sixgr.util.structGet(metrics, "PMI", NaN));
if ~isfinite(pmi)
    pmi = double(sixgr.util.structGet(cfg, "phy.pusch.TPMI", sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)));
end
if isfinite(pmi)
    idx = round(pmi) + 1;
    if idx >= 1 && idx <= numel(candidates)
        selectedIdx = double(idx);
        return;
    end
end
selectedBeams = double(sixgr.util.structGet(metrics, "SelectedBeamIndices", []));
selectedBeams = selectedBeams(isfinite(selectedBeams));
if isempty(selectedBeams)
    return;
end
for ii = 1:numel(candidates)
    candBeams = double(sixgr.util.structGet(candidates(ii), "BeamIndices", []));
    if ~isempty(candBeams) && any(ismember(round(candBeams), round(selectedBeams)))
        selectedIdx = double(ii);
        return;
    end
end
end

function arr = localInferBeamArrayGeometry(cfg, nTx)
arr = localResolveRuntimeBeamArray(cfg, nTx);
if ~isempty(arr)
    return;
end
panelCount = max(1, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.panelCount", 1))));
nRow = max(1, floor(sqrt(double(nTx))));
nCol = max(1, ceil(double(nTx) / max(nRow, 1)));
if nRow * nCol ~= nTx
    if panelCount > 1 && mod(nTx, panelCount) == 0
        nRow = panelCount;
        nCol = nTx / panelCount;
    else
        nRow = 1;
        nCol = nTx;
    end
end
arr = struct("Nant", double(nTx), "nRow", double(nRow), "nCol", double(nCol));
end

function arr = localResolveRuntimeBeamArray(cfg, nTx)
arr = [];
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
candidate = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
if ~(isstruct(candidate) && ~isempty(fieldnames(candidate)))
    candidate = struct();
    shape = double(sixgr.util.structGet(cfg, "phy.bsArray", [1 nTx 1]));
    if numel(shape) >= 2
        candidate.Size = double(shape(1:2));
        candidate.Nant = double(max(1, prod(max(1, round(shape(1:2))))));
    end
end
if ~(isstruct(candidate) && ~isempty(fieldnames(candidate)))
    return;
end
nant = double(sixgr.util.structGet(candidate, "Nant", NaN));
if ~(isfinite(nant) && round(nant) == round(double(nTx)))
    return;
end
shape = double(sixgr.util.structGet(candidate, "Size", [1 nTx]));
if numel(shape) < 2
    shape = [1 double(nTx)];
end
arr = struct("Nant", double(nTx), "nRow", double(max(1, round(shape(1)))), "nCol", double(max(1, round(shape(2)))));
end

function selectedSet = localResolveSelectedBeamSet(cfg, W, metrics)
selectedSet = [];
beamSet = string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamIndexSet", ""));
if strlength(beamSet) > 0
    toks = regexp(char(beamSet), "\d+", "match");
    if ~isempty(toks)
        selectedSet = localClampBeamIndexSet(str2double(string(toks)), size(W, 2));
    end
end
if ~isempty(selectedSet)
    return;
end

selectedSet = localClampBeamIndexSet(sixgr.util.structGet(metrics, "SelectedBeamIndices", []), size(W, 2));
if ~isempty(selectedSet)
    return;
end

selectedIdx = double(sixgr.util.structGet(cfg, "phy.beamManagement.selectedBeamIndex", NaN));
if isfinite(selectedIdx)
    selectedSet = localClampBeamIndexSet(selectedIdx, size(W, 2));
    if ~isempty(selectedSet)
        return;
    end
end

% UL PMI/TPMI authority is measured SRS state carried in metrics. Do not
% fall back to phy.pusch.PMI/TPMI when that state is missing or stale.
selectedSet = localResolveBeamSetFromPMI(cfg, metrics, size(W, 1), size(W, 2));
end

function [nmseLin, detectionMetric] = localPilotResidualChannelMetrics(rx, Hest)
nmseLin = NaN;
detectionMetric = NaN;
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
rxGrid = sixgr.util.structGet(rx, "RxGrid", []);
dmrsInd = sixgr.util.structGet(rx, "DMRSIndices", []);
dmrsSym = sixgr.util.structGet(rx, "DMRSSymbols", []);
if isempty(rxGrid) || isempty(Hest) || isempty(dmrsInd) || isempty(dmrsSym)
    return;
end
try
    [dmrsRx, dmrsHest] = nrExtractResources(dmrsInd, rxGrid, Hest);
catch
    return;
end
[pilotObsH, pilotEstH] = localPilotChannelObservation(dmrsRx, dmrsHest, dmrsSym);
if isempty(pilotObsH) || isempty(pilotEstH)
    return;
end
nmseLin = localNormalizedPilotMSE(pilotEstH, pilotObsH);
if isfinite(nmseLin) && nmseLin >= 0
    detectionMetric = 1 / (1 + nmseLin);
else
    nmseLin = NaN;
end
end
function metrics = localPilotTrackingMetrics(rx)
metrics = struct( ...
    "NMSE_dB", NaN, ...
    "DetectionMetric", NaN, ...
    "EstimatedDopplerHz", NaN, ...
    "PhaseTrackingError_deg", NaN);
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
rxGrid = sixgr.util.structGet(rx, "RxGrid", []);
Hest = sixgr.util.structGet(rx, "ChannelEstimate", []);
dmrsInd = sixgr.util.structGet(rx, "DMRSIndices", []);
dmrsSym = sixgr.util.structGet(rx, "DMRSSymbols", []);
carrier = sixgr.util.structGet(rx, "Carrier", []);
if isempty(rxGrid) || isempty(Hest) || isempty(dmrsInd) || isempty(dmrsSym) || isempty(carrier)
    return;
end
try
    [dmrsRx, dmrsHest] = nrExtractResources(dmrsInd, rxGrid, Hest);
catch
    return;
end
[pilotObsH, pilotEstH] = localPilotChannelObservation(dmrsRx, dmrsHest, dmrsSym);
if isempty(pilotObsH) || isempty(pilotEstH)
    return;
end
nmseLin = localNormalizedPilotMSE(pilotEstH, pilotObsH);
if isfinite(nmseLin) && nmseLin >= 0
    metrics.NMSE_dB = 10 * log10(max(nmseLin, eps));
    metrics.DetectionMetric = 1 / (1 + nmseLin);
end

pilotH = localCollapsePilotEstimate(pilotEstH);
symTimes_s = localPilotSymbolTimes(carrier, dmrsInd);
estHz = localEstimatePilotDoppler(symTimes_s, pilotH);
metrics.EstimatedDopplerHz = estHz;
if isfinite(estHz)
    metrics.PhaseTrackingError_deg = localPilotPhaseTrackingError(symTimes_s, pilotH);
end
end

function [pilotObsH, pilotEstH] = localPilotChannelObservation(dmrsRx, dmrsHest, dmrsSym)
pilotObsH = [];
pilotEstH = [];
dmrsRef = double(dmrsSym(:));
L = min([size(dmrsRx, 1), size(dmrsHest, 1), numel(dmrsRef)]);
if ~(isfinite(L) && L >= 1)
    return;
end
dmrsRx = double(dmrsRx(1:L, :, :, :));
dmrsHest = double(dmrsHest(1:L, :, :, :));
dmrsRef = reshape(dmrsRef(1:L), [L, 1, 1, 1]);
valid = abs(dmrsRef) > sqrt(eps);
if ~any(valid(:))
    return;
end
pilotObsH = dmrsRx(valid) ./ dmrsRef(valid);
pilotEstH = dmrsHest(valid);
end

function nmseLin = localNormalizedPilotMSE(hEst, hObs)
nmseLin = NaN;
hEst = double(hEst(:));
hObs = double(hObs(:));
N = min(numel(hEst), numel(hObs));
if N == 0
    return;
end
hEst = hEst(1:N);
hObs = hObs(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hObs)) & isfinite(imag(hObs));
if ~any(mask)
    return;
end
hEst = hEst(mask);
hObs = hObs(mask);
alpha = (hObs' * hEst) / max(hObs' * hObs, eps);
ref = alpha * hObs;
den = mean(abs(ref).^2, "omitnan");
if ~(isfinite(den) && den > 0)
    return;
end
err = hEst - ref;
nmseLin = mean(abs(err).^2, "omitnan") / max(den, eps);
end

function pilotH = localCollapsePilotEstimate(dmrsHest)
pilotH = squeeze(mean(dmrsHest, [2 3 4], "omitnan"));
pilotH = double(pilotH(:));
end

function symTimes_s = localPilotSymbolTimes(carrier, pilotInd)
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
[~, symIdx, ~] = ind2sub([K, L, 1], double(pilotInd(:)));
symIdx = double(symIdx(:));
symbolTimes = localSymbolCenterTimes(carrier);
symTimes_s = symbolTimes(symIdx);
end

function symbolTimes_s = localSymbolCenterTimes(carrier)
L = double(carrier.SymbolsPerSlot);
symbolTimes_s = [];
try
    ofdmInfo = nrOFDMInfo(carrier);
    sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", NaN));
    symbolLengths = double(sixgr.util.structGet(ofdmInfo, "SymbolLengths", []));
    if isfinite(sampleRateHz) && sampleRateHz > 0 && ~isempty(symbolLengths)
        symbolLengths = symbolLengths(:);
        if numel(symbolLengths) < L
            symbolLengths(end+1:L, 1) = symbolLengths(end);
        end
        symbolLengths = symbolLengths(1:L);
        symbolTimes_s = (cumsum(symbolLengths) - 0.5 * symbolLengths) / sampleRateHz;
    end
catch
end
if isempty(symbolTimes_s)
    slotDur_s = localSlotDuration(struct("phy", struct("carrier", struct("SubcarrierSpacing", carrier.SubcarrierSpacing))));
    symbolTimes_s = ((0:L-1).' + 0.5) * (slotDur_s / max(L, 1));
end
end

function estHz = localEstimatePilotDoppler(symTimes_s, hEst)
estHz = NaN;
symTimes_s = symTimes_s(:);
hEst = hEst(:);
N = min(numel(symTimes_s), numel(hEst));
if N < 2
    return;
end
symTimes_s = symTimes_s(1:N);
hEst = hEst(1:N);
mask = isfinite(symTimes_s) & isfinite(real(hEst)) & isfinite(imag(hEst));
if nnz(mask) < 2
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
if numel(phaseObs) < 2
    return;
end
p = polyfit(uTimes(:), phaseObs(:), 1);
estHz = p(1) / (2 * pi);
end

function phaseErr_deg = localPilotPhaseTrackingError(symTimes_s, hEst)
phaseErr_deg = NaN;
symTimes_s = symTimes_s(:);
hEst = hEst(:);
N = min(numel(symTimes_s), numel(hEst));
if N < 2
    return;
end
symTimes_s = symTimes_s(1:N);
hEst = hEst(1:N);
mask = isfinite(symTimes_s) & isfinite(real(hEst)) & isfinite(imag(hEst));
if nnz(mask) < 2
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
if numel(phaseObs) < 2
    return;
end
p = polyfit(uTimes(:), phaseObs(:), 1);
phaseFit = polyval(p, uTimes(:));
phaseErr_deg = sqrt(mean((phaseObs - phaseFit).^2, "omitnan")) * (180 / pi);
end

function y = localComplexMean(x)
x = x(isfinite(real(x)) & isfinite(imag(x)));
if isempty(x)
    y = complex(NaN, NaN);
else
    y = mean(x, "omitnan");
end
end

function selectedSet = localResolveBeamSetFromPMI(cfg, metrics, nTx, beamCount)
selectedSet = [];
pmi = double(sixgr.util.structGet(metrics, "PMI", NaN));
ri = double(sixgr.util.structGet(metrics, "RI", NaN));
if ~isfinite(pmi) || ~(isfinite(ri) && ri >= 1)
    return;
end

nLayers = round(ri);
codebookMode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo"));
try
    candidates = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, nTx, "Mode", codebookMode);
catch
    candidates = struct([]);
end
if isempty(candidates)
    return;
end

pmiIdx = round(pmi) + 1;
if pmiIdx < 1 || pmiIdx > numel(candidates)
    return;
end
selectedSet = localClampBeamIndexSet(candidates(pmiIdx).BeamIndices, beamCount);
end

function nLayers = localResolveLayerCount(cfg, metrics)
nLayers = double(sixgr.util.structGet(metrics, "RI", NaN));
if ~(isfinite(nLayers) && nLayers >= 1)
    nLayers = double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))));
end
nLayers = max(1, round(nLayers));
end

function selectedSet = localClampBeamIndexSet(selectedSet, beamCount)
selectedSet = double(selectedSet(:).');
if isempty(selectedSet)
    return;
end
selectedSet = selectedSet(isfinite(selectedSet));
selectedSet = round(selectedSet);
selectedSet = selectedSet(selectedSet >= 1 & selectedSet <= beamCount);
selectedSet = unique(selectedSet, "stable");
end

function B = localOversampledDFTCodebook(numTxPorts, numBeams)
n = (0:(numTxPorts - 1)).';
m = 0:(numBeams - 1);
B = exp(-1j * 2 * pi * (n * m) / max(numBeams, 1));
B = B ./ sqrt(max(numTxPorts, 1));
end

function selectedIdx = localResolveSelectedBeamIndex(cfg, W, metrics)
selectedSet = localResolveSelectedBeamSet(cfg, W, metrics);
if isempty(selectedSet)
    selectedIdx = 1;
else
    selectedIdx = selectedSet(1);
end
end

function estHz = localSanitizeEstimatedDoppler(estHz, cfg, nmse_dB)
if ~isfinite(estHz)
    estHz = NaN;
    return;
end
expectedHz = abs(double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", NaN))));
if isfinite(expectedHz) && expectedHz > 0
    if abs(estHz) > max(5 * expectedHz, 200)
        estHz = NaN;
        return;
    end
end
if isfinite(nmse_dB) && nmse_dB > 6
    estHz = NaN;
end
end

function [combined, diag] = localCombineRateRecoveredLLR(prev, cur, currentLayout)
if nargin < 3
    currentLayout = struct();
end
[combined, info] = sixgr.phy.harq.combineSoftLLR(localEnsureLLRMatrix(cur), prev, ...
    "CurrentLayout", currentLayout);
diag = localHARQCombiningDiagnostics(prev, cur, combined, info);
end

function diag = localHARQCombiningDiagnostics(prev, cur, combined, info)
if nargin < 4
    info = struct();
end
prevShape = localLLRShape(prev);
curShape = localLLRShape(cur);
combinedShape = localLLRShape(combined);
compatibleShape = logical(sixgr.util.structGet(info, "Applied", false));
skipReason = string(sixgr.util.structGet(info, "Reason", ""));
diag = struct( ...
    "PreviousLLRCount", localLLRCount(prev), ...
    "CurrentLLRCount", double(numel(cur)), ...
    "CombinedLLRCount", double(numel(combined)), ...
    "CombiningApplied", compatibleShape, ...
    "CombiningSkipReason", char(skipReason), ...
    "PositionAware", logical(sixgr.util.structGet(info, "PositionAware", false)), ...
    "OverlapPositionCount", double(sixgr.util.structGet(info, "OverlapPositionCount", NaN)), ...
    "SoftBuffer", sixgr.util.structGet(info, "SoftBuffer", struct()), ...
    "PreviousLLRRows", double(prevShape(1)), ...
    "PreviousLLRCodeBlocks", double(prevShape(2)), ...
    "CurrentLLRRows", double(curShape(1)), ...
    "CurrentLLRCodeBlocks", double(curShape(2)), ...
    "CombinedLLRRows", double(combinedShape(1)), ...
    "CombinedLLRCodeBlocks", double(combinedShape(2)), ...
    "LLRCombiningGain_dB", double(sixgr.util.structGet(info, "LLRCombiningGain_dB", NaN)));
if isempty(cur) || isempty(combined)
    return;
end
if isfinite(diag.LLRCombiningGain_dB)
    return;
end
try
    curVals = double(cur(:));
    combinedVals = double(combined(:));
    curVals = curVals(isfinite(curVals));
    combinedVals = combinedVals(isfinite(combinedVals));
    curEnergy = mean(abs(curVals).^2, "omitnan");
    combinedEnergy = mean(abs(combinedVals).^2, "omitnan");
    if isfinite(curEnergy) && curEnergy > 0 && isfinite(combinedEnergy) && combinedEnergy > 0
        diag.LLRCombiningGain_dB = 10 * log10(combinedEnergy / curEnergy);
    end
catch
end
end

function [ok, meanIter, tbBits] = localDecodeCombinedLLR(tx, recLLR, cfg)
ok = false;
meanIter = NaN;
tbBits = int8([]);
if isempty(recLLR)
    return;
end
X = localEnsureLLRMatrix(recLLR);
if isempty(X)
    return;
end
nRow = size(X, 1);
nCB = size(X, 2);
if ~localIsValidLDPCDecodeRows(nRow, double(tx.BaseGraph))
    return;
end
decCbs = zeros(nRow, nCB, 'int8');
itVec = NaN(nCB, 1);
maxLen = 0;
alg = localSafeCharToken(sixgr.util.structGet(cfg, "phy.ldpc.algorithm", "Normalized min-sum"));
maxIter = sixgr.phy.phycode.resolveLDPCMaxIterations(cfg, "Direction", "UL");
for c = 1:nCB
    [d, it] = sixgr.phy.phycode.ldpcDecode(X(:, c), double(tx.BaseGraph), maxIter, alg);
    d = int8(d(:));
    Ld = min(numel(d), nRow);
    if Ld > 0
        decCbs(1:Ld, c) = d(1:Ld);
        maxLen = max(maxLen, Ld);
    end
    it = it(:);
    if ~isempty(it)
        itVec(c) = double(it(1));
    end
end
if maxLen <= 0
    return;
end
decCbs = decCbs(1:maxLen, :);
B = double(tx.TransportBlockSize) + double(sixgr.util.structGet(tx, "TransportBlockCRCLength", 24));
tbCrc = sixgr.phy.tb.desegmentLDPC(decCbs, double(tx.BaseGraph), B);
[tbBits, crcOk] = sixgr.phy.tb.checkCRC(tbCrc, localSafeCharToken(sixgr.util.structGet(tx, "TransportBlockCRCType", "24A")));
tbBits = int8(tbBits(:));
ok = logical(crcOk);
meanIter = mean(itVec(isfinite(itVec)), "omitnan");
end

function [bitErrors, bitsCompared] = localFinalBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
bitsCompared = min(numel(txBits), numel(rxBits));
if bitsCompared == 0
    bitErrors = numel(txBits);
    bitsCompared = numel(txBits);
    return;
end
bitErrors = sum(txBits(1:bitsCompared) ~= rxBits(1:bitsCompared));
if numel(txBits) ~= numel(rxBits)
    bitErrors = bitErrors + abs(numel(txBits) - numel(rxBits));
    bitsCompared = max(numel(txBits), numel(rxBits));
end
end

function X = localEnsureLLRMatrix(v)
if isstruct(v)
    v = sixgr.util.structGet(v, "LLR", sixgr.util.structGet(v, "RateRecoveredLLR", []));
end
X = double(v);
if isvector(X)
    X = X(:);
end
end

function n = localLLRCount(v)
n = double(numel(v));
if isstruct(v)
    if isfield(v, "LLRSum")
        n = double(numel(v.LLRSum));
    elseif isfield(v, "SoftBuffer")
        soft = sixgr.util.structGet(v, "SoftBuffer", struct());
        if isstruct(soft) && isfield(soft, "LLRSum")
            n = double(numel(soft.LLRSum));
        end
    else
        x = sixgr.util.structGet(v, "LLR", sixgr.util.structGet(v, "RateRecoveredLLR", []));
        n = double(numel(x));
    end
end
end

function tf = localHARQPriorAvailable(v)
tf = ~isempty(v);
if isstruct(v)
    tf = ~isempty(fieldnames(v));
elseif iscell(v)
    tf = any(~cellfun(@isempty, v));
end
end

function shape = localLLRShape(v)
if isempty(v)
    shape = [0 0];
    return;
end
X = localEnsureLLRMatrix(v);
shape = [size(X, 1) size(X, 2)];
end

function tf = localIsValidLDPCDecodeRows(nRows, bgn)
tf = false;
if ~(isscalar(nRows) && isfinite(nRows) && nRows > 0 && isscalar(bgn) && isfinite(bgn))
    return;
end
if round(bgn) == 1
    zc = double(nRows) / 66;
elseif round(bgn) == 2
    zc = double(nRows) / 50;
else
    return;
end
validZc = [2:16 18:2:32 36:4:64 72:8:128 144:16:256 288:32:384];
tf = abs(zc - round(zc)) < 1e-9 && any(abs(validZc - round(zc)) < 1e-9);
end

function seed = localRNGSeed(seedValue)
seed = double(seedValue);
if ~(isfinite(seed) && seed >= 0)
    seed = 1;
end
seed = mod(round(seed), 2^32);
end

function seed = localChannelSeed(cfg, snr_dB, trialSeed)
baseSeed = double(sixgr.util.structGet(cfg, "run.seed", 1));
if ~(isfinite(baseSeed) && baseSeed >= 0)
    baseSeed = 1;
end
snrKey = 0;
if isfinite(double(snr_dB))
    snrKey = round((double(snr_dB) + 200) * 1000);
end
trialKey = 0;
if isfinite(double(trialSeed))
    trialKey = round(double(trialSeed));
end
seed = mod(round(baseSeed) + snrKey * 7919 + trialKey * 104729, 2^31 - 1);
end

function grant = localBuildHARQGrantSnapshot(tx, mcsIndex, cfg, seedGrant, frameIdx, slotIdx, trialSeed)
if nargin < 4 || ~isstruct(seedGrant)
    seedGrant = struct();
end
pusch = sixgr.util.structGet(tx, "PUSCH", []);
prec = sixgr.phy.ul.validatePUSCHPrecoderEvidence(tx);
tbBitsActual = sixgr.util.structGet(tx, "TransportBlock", []);
tbSizeActual = double(numel(tbBitsActual));
if ~(isfinite(tbSizeActual) && tbSizeActual > 0)
    tbSizeActual = double(sixgr.util.structGet(seedGrant, "TBSBits", ...
        sixgr.util.structGet(seedGrant, "TransportBlockSize", ...
        sixgr.util.structGet(tx, "TransportBlockSize", NaN))));
end
scheduledTBSize = double(sixgr.util.structGet(tx, "TransportBlockSize", NaN));
numTxAnt = NaN;
if isfield(tx, "Grid") && ~isempty(tx.Grid)
    numTxAnt = double(size(tx.Grid, 3));
end
puschMod = localObjectValue(pusch, "Modulation", "");
puschLayers = localObjectValue(pusch, "NumLayers", NaN);
puschPRBSet = localObjectValue(pusch, "PRBSet", []);
puschSymbolAllocation = localObjectValue(pusch, "SymbolAllocation", []);
puschMappingType = localObjectValue(pusch, "MappingType", "");
puschTransformPrecoding = localObjectValue(pusch, "TransformPrecoding", false);
acct = sixgr.util.structGet(tx, "ResourceAccounting", struct());
acctNREPerPRB = double(sixgr.util.structGet(acct, "NREPerPRBForTBS", sixgr.util.structGet(tx, "NREPerPRB", NaN)));
acctG = double(sixgr.util.structGet(acct, "CodedBitCountG", sixgr.util.structGet(tx, "G", NaN)));
acctLayerRE = double(sixgr.util.structGet(acct, "LayerDataRE", sixgr.util.structGet(tx, "LayerDataRE", NaN)));
acctPortRE = double(sixgr.util.structGet(acct, "PortMappedRE", sixgr.util.structGet(tx, "PortMappedRE", NaN)));
acctModSymbols = double(sixgr.util.structGet(acct, "ModulationSymbolCount", sixgr.util.structGet(tx, "ModulationSymbolCount", NaN)));
xOverhead = double(sixgr.util.structGet(tx, "XOverhead", sixgr.util.structGet(cfg, "phy.pusch.xOverhead", 0)));
appliedPMI = localOptionalPUSCHPMI(sixgr.util.structGet(prec, "PMI", NaN));
requestedPMI = localOptionalPUSCHPMI(sixgr.util.structGet(seedGrant, "PMI", sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)));
grant = struct( ...
    "Direction", "UL", ...
    "MCS", double(mcsIndex), ...
    "MCSIndex", double(sixgr.util.structGet(seedGrant, "MCSIndex", mcsIndex)), ...
    "Modulation", localSafeCharToken(puschMod), ...
    "TargetCodeRate", double(sixgr.util.structGet(tx, "TargetCodeRate", NaN)), ...
    "NumLayers", double(puschLayers), ...
    "Layers", double(puschLayers), ...
    "PRBs", double(numel(puschPRBSet)), ...
    "PRBSet", puschPRBSet, ...
    "SymbolAllocation", puschSymbolAllocation, ...
    "MappingType", localSafeCharToken(puschMappingType), ...
    "TransformPrecoding", logical(puschTransformPrecoding), ...
    "CarrierConfig", sixgr.util.structGet(tx, "Carrier", []), ...
    "PUSCHConfig", pusch, ...
    "TransportBlockSize", double(tbSizeActual), ...
    "ScheduledTransportBlockSize", double(scheduledTBSize), ...
    "TBSBits", double(tbSizeActual), ...
    "TBSBytes", floor(double(tbSizeActual) / 8), ...
    "XOverhead", double(xOverhead), ...
    "NREPerPRB", double(acctNREPerPRB), ...
    "LayerDataRE", double(acctLayerRE), ...
    "PortMappedRE", double(acctPortRE), ...
    "ModulationSymbolCount", double(acctModSymbols), ...
    "CodedBitCountG", double(acctG), ...
    "TBSInputModulation", localSafeCharToken(puschMod), ...
    "TBSInputNumLayers", double(puschLayers), ...
    "TBSInputNPRB", double(numel(puschPRBSet)), ...
    "TBSInputNREPerPRB", double(acctNREPerPRB), ...
    "TBSInputTargetCodeRate", double(sixgr.util.structGet(tx, "TargetCodeRate", NaN)), ...
    "TBSInputXOverhead", double(xOverhead), ...
    "ResourceAccountingSource", localSafeCharToken(sixgr.util.structGet(acct, "Source", "")), ...
    "NumTxAnt", double(numTxAnt), ...
    "ConfiguredBeamSelectionStrategy", localSafeCharToken(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")), ...
    "PrecoderSource", localSafeCharToken(sixgr.util.structGet(prec, "Source", localResolveULPrecoderSource(logical(puschTransformPrecoding)))), ...
    "PrecodingMode", localSafeCharToken(sixgr.util.structGet(prec, "Mode", localResolveULPrecodingMode(logical(puschTransformPrecoding)))), ...
    "PrecodingApplicationStage", localSafeCharToken(sixgr.util.structGet(prec, "ApplicationStage", localResolveULPrecodingStage(logical(puschTransformPrecoding)))), ...
    "PrecodingActive", logical(sixgr.util.structGet(prec, "Active", logical(puschTransformPrecoding))), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(prec, "ExplicitBeamWeightsApplied", false)), ...
    "TransformPrecodingApplied", logical(puschTransformPrecoding), ...
    "BeamformingApplied", logical(sixgr.util.structGet(prec, "BeamformingApplied", false)), ...
    "AppliedBeamIndexSet", char(localFormatIndexSet(sixgr.util.structGet(prec, "BeamIndices", []))), ...
    "AppliedCodebookPortIndexSet", char(localFormatIndexSet(prec.CodebookPortIndices1Based)), ...
    "AppliedCodebookPortIndexDefinition", char(prec.CodebookPortIndexDefinition), ...
    "AppliedPrecoderPMI", double(appliedPMI), ...
    "AppliedPrecoderPMIType", localSafeCharToken(sixgr.util.structGet(prec, "PMIType", "")), ...
    "AppliedPrecoderCodebookMode", localSafeCharToken(sixgr.util.structGet(prec, "CodebookMode", "")), ...
    "AppliedPrecoderMatrixSHA256", localSafeCharToken(localResolveAppliedPrecoderMatrixSHA256(prec)), ...
    "RequestedVsAppliedPrecoderPMIMatchStatus", localSafeCharToken(localRequestedVsAppliedPMIStatus(requestedPMI, appliedPMI)), ...
    "PrecodingNumPorts", double(sixgr.util.structGet(prec, "NumPorts", numTxAnt)), ...
    "PrecodingNumLayers", double(sixgr.util.structGet(prec, "NumLayers", puschLayers)), ...
    "PrecodingMatrixRows", double(sixgr.util.structGet(prec, "MatrixRows", NaN)), ...
    "PrecodingMatrixCols", double(sixgr.util.structGet(prec, "MatrixCols", NaN)), ...
    "NumLogicalPorts", double(sixgr.util.structGet(prec, "NumLogicalPorts", NaN)), ...
    "NumRFChains", double(sixgr.util.structGet(prec, "NumRFChains", NaN)));
preserveFields = ["UEIndex","RNTI","ServingCell","CQIUsed","RIUsed","PMI","CRI","MCSTable","CQITable","AMCMode", ...
    "OuterLoopEnabled","OuterLoopApplied","OLLADeltaDb","OLLADeltaMCS","OLLAMarginMinDb","OLLAMarginMaxDb", ...
    "OLLAAdjustedMCSBeforeCQICeiling","OLLABaseRequiredSINR_dB","OLLATargetRequiredSINR_dB","OLLAThresholdSource", ...
    "OLLAUpdateCount","OLLAStateAuthority","OLLAState", ...
    "RankSelectionPolicy","RankSelectionSource","RankDecisionReason","RankDowngradeApplied","MaxSupportedLayers", ...
    "RawCQIDerivedMCS","LinkAdaptationMCSIndex","LinkAdaptationDecisionReason", ...
    "CQIBasedMCS","SmoothedCQI","InstantaneousCQIMCS","DeltaMCS","StaticDeltaMCS", ...
    "MCSSelectionSource","CQIProvenance","MCSValueStatus","GrantReason","Frame","Slot","HARQ","IsRetransmission", ...
    "DMRSPortSet","DMRSPortSetSource","PTRSEnabled","PTRSPortSet","PTRSPortSetSource", ...
    "MUMIMOEnabled","MUMIMOGroupSize","MUMIMOGroupId","MUMIMOPairingStatus", ...
    "MUMIMOPairingMetricSource","MUMIMOPairingMetricValue_dB","MUMIMOPairingEvidenceSource","MUMIMOPrecoderType", ...
    "MUMIMOPairingWorstMetricValue_dB","MUMIMORequiredLeakageThreshold_dB", ...
    "MUMIMODesiredSubspaceGain_dB","MUMIMORequiredMinimumDesiredGain_dB", ...
    "MUMIMOSpatialDesignStatus","MUMIMOSpatialDesignContractVersion", ...
    "MUMIMOSpatialSignatureSubspaceMode", ...
    "MUMIMOSpatialDesignEvidenceSource","MUMIMOSpatialFilterMatrixSHA256", ...
    "MUMIMOReceiveCombiningMatrix", ...
    "MUMIMOReceiveCombiningMatrixSHA256","MUMIMOReceiverAlgorithm", ...
    "MUMIMOAdmissionReceiveCombiningMatrix", ...
    "MUMIMOAdmissionReceiveCombiningMatrixSHA256","MUMIMOReceiveProcessingMode", ...
    "MUMIMOHybridRFDesignPolicy","MUMIMOHybridRFDesignStatus", ...
    "HybridElementToPortMatrixSHA256","BaseHybridElementToPortMatrixSHA256", ...
    "NumLogicalPorts","NumRFChains", ...
    "SchedulerCQIRawCQI","SchedulerAdjustedSINR_dB","SchedulerSINRBackoff_dB","SchedulerCQISource", ...
    "MCSIndexAuthority","GrantOperatingPointSource", ...
    "TimingDecision","K0","K1","K2","ControlAbsoluteSlot", ...
    "ScheduledAbsoluteSlot","HARQFeedbackAbsoluteSlot", ...
    "SchedulingCCID","ScheduledCCID","CarrierIndicator", ...
    "SourceBWPID","TargetBWPID", ...
    "PBCHGatingActive","PRACHGatingActive","PDCCHGatingActive","SRSGatingActive","ControlEligible","ControlDecodeOk", ...
    "DCICrcPass","PDCCHPayloadMatch","PDCCHCausalGrantDecodeOk", ...
    "PDCCHMissedDetection","PDCCHFalseAlarm","GrantValid", ...
    "NegativeExpectedOk","PDCCHBlindSearchEnabled","PDCCHREGMappingAvailable", ...
    "PDCCHGrantBindingRequired","PDCCHGrantBindingOk","PDCCHGrantBindingStatus","PDCCHGrantBindingFailureCode", ...
    "PDCCHGrantDCIId","PDCCHGrantDCIFieldsHash","PDCCHGrantFieldsHash","PDCCHGrantSearchSpaceId", ...
    "PDCCHGrantCORESETId","PDCCHGrantAggregationLevel","PDCCHGrantCandidateIndex","PDCCHGrantDCIFormat","GrantControlState", ...
    "PDCCHControlFailureReason","PDCCHControlEvidenceSource","ControlDecodeSource", ...
    "CellAcquisitionState","AccessState","SRSValidityState","CSIValidityState","SRSValid","SRSAgeSlots", ...
    "TRSGatingActive","TRSValidityState","TrackingEligibility","TRSAgeSlots","LastSuccessfulTRSSlot","LastEstimatedTRSDopplerHz", ...
    "TRSStateSource","TRSRuntimeConsumer","TRSInfluencedDecision","TRSInfluenceDefinition","TRSReceiverIntegrationStatus","TRSReceiverIntegrationBlocker", ...
    "ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits","MultiplexedHARQACKBits","UCIOnPUSCHApplied","UCIOnPUSCHSource", ...
    "PUCCHCollisionPolicy","PUCCHSourceSlot","PUCCHGrantId","UCIOnPUSCHEvidenceSource", ...
    "UCIOnPUSCHFeedbackGrantIds","UCIOnPUSCHFeedbackSourceSlots", ...
    "UCIOnPUSCHFeedbackHARQIds","UCIOnPUSCHFeedbackBitCount", ...
    "UCIOnPUSCHCSIReportIdentity","UCIOnPUSCHCSIPart1BitCount", ...
    "UCIOnPUSCHCSIPart2BitCount", ...
    "GrantContextId","GrantWorkerSafe","GrantSharedStateCommitMode","PHYGrant","PHYGrantContextId", ...
    "DCI","Valid","GrantBlocker","ExactPHYFeasibilityChecked","ExactPHYFeasible", ...
    "ExactPHYFeasibilitySource","ExactPHYInfeasibilityReason","ExecutableTBSMode", ...
    "ExactAllocationCapacityBits","ExactAllocationCapacityBytes","ExactTBSBits","ExactTBSBytes", ...
    "ExactNREPerPRB","ExactTBSUsedFastNREApprox","ExactTBSInfo","PlanningOnlyApproximation", ...
    "HARQTBContext","OriginalTBSBits","CurrentTBSBits","OriginalRateMatchedBits","CurrentRateMatchedBits", ...
    "EffectiveInitialCodeRate","EffectiveCurrentTxCodeRate","ShortIRRetx","CodeBlockLayoutHash","HARQContextHash","HARQContextStatus", ...
    "TransportBlockId","ProtocolPayloadSameWaveformTruth","ProtocolPacketId", ...
    "ProtocolApplicationPacketId","ProtocolFragmentId","ProtocolSegmentIndex", ...
    "ProtocolPayloadOffsetBits","ProtocolPayloadBits","ProtocolPayloadSHA256", ...
    "ProtocolSDAPHeaderHex","ProtocolPDCPHeaderHex","ProtocolRLCHeaderHex", ...
    "ProtocolEncodedRLC_SHA256","ProtocolMACSHA256","ProtocolMACPDUBytes", ...
    "ProtocolMACPaddingBytes","ProtocolEvidenceSource"];
for i = 1:numel(preserveFields)
    fieldName = char(preserveFields(i));
    if isfield(seedGrant, fieldName)
        grant.(fieldName) = seedGrant.(fieldName);
    end
end
% These two fields describe the architecture that actually emitted this
% waveform.  A heterogeneous scheduler array can legitimately carry an
% unavailable placeholder in the input grant; that must not overwrite the
% applied PUSCH precoder/antenna result.
appliedLogicalPorts = double(sixgr.util.structGet(prec, "NumLogicalPorts", NaN));
appliedRFChains = double(sixgr.util.structGet(prec, "NumRFChains", NaN));
if isscalar(appliedLogicalPorts) && isfinite(appliedLogicalPorts) && appliedLogicalPorts >= 1
    grant.NumLogicalPorts = appliedLogicalPorts;
end
if isscalar(appliedRFChains) && isfinite(appliedRFChains) && appliedRFChains >= 1
    grant.NumRFChains = appliedRFChains;
end
txPHYGrant = sixgr.util.structGet(tx, "PHYGrant", struct());
if isstruct(txPHYGrant) && ~isempty(fieldnames(txPHYGrant))
    grant.PHYGrant = txPHYGrant;
    grant.PHYGrantContextId = char(string(txPHYGrant.GrantContextId));
end
grant = sixgr.link.finalizeHARQGrantSpatialSnapshot(grant, "UL");
if ~(isfield(grant, "GrantContextId") && strlength(strtrim(string(grant.GrantContextId))) > 0)
    grant.GrantContextId = localComposeReplayGrantContextId( ...
        seedGrant, "UL", frameIdx, slotIdx, trialSeed);
end
if ~isfield(grant, "GrantWorkerSafe")
    grant.GrantWorkerSafe = true;
end
if ~(isfield(grant, "GrantSharedStateCommitMode") && strlength(strtrim(string(grant.GrantSharedStateCommitMode))) > 0)
    grant.GrantSharedStateCommitMode = "serial_coordinator_commit";
end
end

function [mcsIndex, modStr, codeRate] = localOverrideReportedGrantFields(mcsIndex, modStr, codeRate, grant)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
grantMCS = double(sixgr.util.structGet(grant, "MCS", NaN));
grantMod = string(sixgr.util.structGet(grant, "Modulation", ""));
grantRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
if isfinite(grantMCS)
    mcsIndex = grantMCS;
end
if strlength(strtrim(grantMod)) > 0
    modStr = grantMod;
end
if isfinite(grantRate) && grantRate > 0
    codeRate = grantRate;
end
end

function txArgs = localAppendGrantReplayTxArgs(txArgs, grant, cfgFrame)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
carrier = sixgr.util.structGet(grant, "CarrierConfig", []);
pusch = sixgr.util.structGet(grant, "PUSCHConfig", []);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
xOverhead = double(sixgr.util.structGet(grant, "XOverhead", NaN));
numTxAnt = double(sixgr.util.structGet(grant, "NumTxAnt", NaN));
storedTBSize = double(sixgr.util.structGet(grant, "TBSBits", ...
    sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
if hasPHYGrant
    [runtimeCarrier, ~] = sixgr.phy.grid.materializeRuntimeCarrier( ...
        cfgFrame, carrier, "UL");
    txArgs = [txArgs {"Carrier", runtimeCarrier}]; %#ok<AGROW>
elseif ~isempty(carrier)
    txArgs = [txArgs {"Carrier", carrier}]; %#ok<AGROW>
end
if ~hasPHYGrant && ~isempty(pusch)
    txArgs = [txArgs {"PUSCH", pusch}]; %#ok<AGROW>
end
if localGrantRequiresTransportBlockSizeOverride(grant, hasPHYGrant) && isfinite(storedTBSize) && storedTBSize > 0
    txArgs = [txArgs {"TransportBlockSizeOverride", round(storedTBSize)}]; %#ok<AGROW>
end
if ~hasPHYGrant && isfinite(targetCodeRate) && targetCodeRate > 0
    txArgs = [txArgs {"TargetCodeRate", targetCodeRate}]; %#ok<AGROW>
end
if ~hasPHYGrant && isfinite(xOverhead) && xOverhead >= 0
    txArgs = [txArgs {"XOverhead", xOverhead}]; %#ok<AGROW>
end
if ~hasPHYGrant && isfinite(numTxAnt) && numTxAnt >= 1
    txArgs = [txArgs {"NumTxAnt", numTxAnt}]; %#ok<AGROW>
end
end

function localAssertExecutedCarrierTimeline(cfg, carrier, direction)
expectedSlot = double(sixgr.util.structGet(cfg, ...
    "lls6g.runtime.CarrierSlotIndex0", NaN));
expectedFrame = double(sixgr.util.structGet(cfg, ...
    "lls6g.runtime.CarrierFrameIndex0", NaN));
actualSlot = double(carrier.NSlot);
actualFrame = double(carrier.NFrame);
if ~(isfinite(expectedSlot) && isfinite(expectedFrame) && ...
        actualSlot == expectedSlot && actualFrame == expectedFrame)
    error("sixgr:grid:ExecutedCarrierTimelineMismatch", ...
        "%s transmitter executed frame/slot %g/%g; runtime authority requires %g/%g.", ...
        char(string(direction)), actualFrame, actualSlot, ...
        expectedFrame, expectedSlot);
end
end

function tf = localGrantRequiresTransportBlockSizeOverride(grant, hasPHYGrant)
tf = false;
if logical(hasPHYGrant) || ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
tf = logical(sixgr.util.structGet(grant, "IsRetransmission", false)) || ...
    logical(sixgr.util.structGet(grant, "HARQIsRetransmission", false)) || ...
    logical(sixgr.util.structGet(grant, "HARQProcessKey.IsRetransmission", false)) || ...
    contains(lower(strtrim(string(sixgr.util.structGet(grant, "GrantReason", "")))), "retrans");
end

function token = localComposeReplayGrantContextId(grant, direction, fallbackFrame, fallbackSlot, trialSeed)
direction = localSafeCharToken(upper(string(direction)));
if nargin < 1 || ~isstruct(grant)
    grant = struct();
end
rnti = localIntegerToken(sixgr.util.structGet(grant, "RNTI", NaN));
ueIdx = localIntegerToken(sixgr.util.structGet(grant, "UEIndex", NaN));
servingCell = localIntegerToken(sixgr.util.structGet(grant, "ServingCell", NaN));
frameValue = double(sixgr.util.structGet(grant, "Frame", NaN));
slotValue = double(sixgr.util.structGet(grant, "Slot", NaN));
if ~(isscalar(frameValue) && isfinite(frameValue)), frameValue = double(fallbackFrame); end
if ~(isscalar(slotValue) && isfinite(slotValue)), slotValue = double(fallbackSlot); end
frame = localIntegerToken(frameValue);
slot = localIntegerToken(slotValue);
seed = localIntegerToken(trialSeed);
grantReason = strtrim(localSafeCharToken(sixgr.util.structGet(grant, "GrantReason", "")));
token = sprintf('%s|cell=%s|ue=%s|rnti=%s|frame=%s|slot=%s|seed=%s', ...
    direction, servingCell, ueIdx, rnti, frame, slot, seed);
if ~isempty(grantReason)
    token = token + "|reason=" + grantReason;
end
end

function token = localSafeCharToken(value)
value = string(value);
value = value(~ismissing(value));
if isempty(value)
    token = "";
    return;
end
value = strip(value(1));
if strlength(value) < 1
    token = "";
    return;
end
token = char(value);
end

function token = localIntegerToken(value)
value = round(double(value));
if ~(isfinite(value) && isscalar(value))
    token = "na";
    return;
end
token = sprintf('%d', value);
end

function [grant, phyGrant] = localNormalizeHARQReplayGrantInputs(cfg, grant, phyGrant, tbBits, harqContext, snr_dB, frameIdx, slotIdx)
isRetx = localInferHARQReplayMode(grant, phyGrant, harqContext, tbBits);
if ~isRetx
    % New-data TB context does not authorize a second grant freeze. Preserve
    % the scheduler's exact frozen spatial and coding contract; only an
    % explicitly identified retransmission may enter the replay normalizer.
    return;
end
replayBits = double(numel(tbBits));
tbContext = localReplayTBContext(grant, harqContext);
resolvedTBSBits = double(sixgr.util.structGet(tbContext, "TBSBits", NaN));
if ~(isfinite(replayBits) && replayBits > 0) && ~(isfinite(resolvedTBSBits) && resolvedTBSBits > 0)
    return;
end
if ~(isfinite(resolvedTBSBits) && resolvedTBSBits > 0)
    resolvedTBSBits = double(replayBits);
elseif isfinite(replayBits) && replayBits > 0 && round(resolvedTBSBits) ~= round(replayBits)
    error("sixgr:HARQReplay:BadStoredTBContext", ...
        "UL HARQ replay context TBSBits=%d does not match stored TB bits=%d.", ...
        round(resolvedTBSBits), round(replayBits));
end
if ~isstruct(grant)
    grant = struct();
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
if ~isstruct(harq)
    harq = struct();
end
if isRetx
    harq.IsRetransmission = true;
end
copyFields = ["HARQProcess","HarqID","RV","NDI","NDIEpoch","CodewordIndex","TBIdentity"];
for i = 1:numel(copyFields)
    f = char(copyFields(i));
    v = sixgr.util.structGet(harqContext, f, []);
    if ~isempty(v)
        harq.(f) = v;
    end
end
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    if ~isfield(harq, "NDI") || isempty(harq.NDI)
        harq.NDI = logical(sixgr.util.structGet(tbContext, "NDI", false));
    end
    if ~isfield(harq, "NDIEpoch") || ~(isfinite(double(sixgr.util.structGet(harq, "NDIEpoch", NaN))))
        harq.NDIEpoch = double(sixgr.util.structGet(tbContext, "NDIEpoch", NaN));
    end
    if ~isfield(harq, "HarqID") || ~(isfinite(double(sixgr.util.structGet(harq, "HarqID", NaN))))
        harq.HarqID = double(sixgr.util.structGet(tbContext, "HARQProcessId", NaN));
    end
    if ~isfield(harq, "HARQProcess") || ~(isfinite(double(sixgr.util.structGet(harq, "HARQProcess", NaN))))
        harq.HARQProcess = double(sixgr.util.structGet(tbContext, "HARQProcessId", NaN));
    end
end
grant.HARQ = harq;
grant.IsRetransmission = isRetx;
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    grant.HARQTBContext = tbContext;
end
grant.TransportBlockSize = double(resolvedTBSBits);
grant.TBSBits = double(resolvedTBSBits);
grant.TBSBytes = floor(double(resolvedTBSBits) / 8);
grant.ScheduledTransportBlockSize = double(resolvedTBSBits);
phyTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
phyRetx = logical(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false));
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)) && ...
        isfinite(phyTBS) && round(phyTBS) == round(resolvedTBSBits) && (~isRetx || phyRetx))
    if isfield(grant, "PHYGrant") && ~(isstruct(tbContext) && ~isempty(fieldnames(tbContext)))
        grant = rmfield(grant, "PHYGrant");
    end
    phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, "UL", grant, ...
        "SNR_dB", snr_dB, ...
        "Frame", frameIdx, ...
        "Slot", slotIdx, ...
        "HARQContext", harqContext);
end
grant.TransportBlockSize = double(resolvedTBSBits);
grant.TBSBits = double(resolvedTBSBits);
grant.TBSBytes = floor(double(resolvedTBSBits) / 8);
grant.ScheduledTransportBlockSize = double(resolvedTBSBits);
grant.PHYGrant = phyGrant;
grant.PHYGrantContextId = char(string(phyGrant.GrantContextId));
end

function tf = localInferHARQReplayMode(grant, phyGrant, harqContext, tbBits)
if nargin < 1 || ~isstruct(grant)
    grant = struct();
end
if nargin < 2 || ~isstruct(phyGrant)
    phyGrant = struct();
end
if nargin < 3 || ~isstruct(harqContext)
    harqContext = struct();
end
if nargin < 4
    tbBits = [];
end
tbContext = localReplayTBContext(grant, harqContext);
replayBits = double(numel(tbBits));
ctxBits = double(sixgr.util.structGet(tbContext, "TBSBits", NaN));
hasReplayPayload = (isfinite(replayBits) && replayBits > 0) || (isfinite(ctxBits) && ctxBits > 0);
if ~hasReplayPayload
    tf = false;
    return;
end
    tf = sixgr.phy.grant.isExplicitHARQRetransmission( ...
        grant, phyGrant, harqContext);
end

function tf = localHARQNDIMatchesTBContext(grant, harqContext, tbContext)
tf = false;
if ~(isstruct(tbContext) && ~isempty(fieldnames(tbContext)) && ...
        isfinite(double(sixgr.util.structGet(tbContext, "TBSBits", NaN))))
    return;
end
currentNDI = sixgr.util.structGet(harqContext, "NDI", []);
if isempty(currentNDI)
    currentNDI = sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "NDI", ...
        sixgr.util.structGet(grant, "NDI", []));
end
ctxNDI = sixgr.util.structGet(tbContext, "NDI", []);
if isempty(currentNDI) || isempty(ctxNDI)
    tf = true;
    return;
end
if isnumeric(currentNDI) || islogical(currentNDI)
    currentNDI = double(currentNDI(1));
end
if isnumeric(ctxNDI) || islogical(ctxNDI)
    ctxNDI = double(ctxNDI(1));
end
if isfinite(double(currentNDI)) && isfinite(double(ctxNDI))
    tf = logical(currentNDI) == logical(ctxNDI);
end
end

function localAssertReplayTBConsistency(tbBits, grant, direction)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
tbContext = localReplayTBContext(grant, struct());
expectedBits = double(sixgr.util.structGet(tbContext, "TBSBits", ...
    sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
if isfinite(expectedBits) && expectedBits > 0 && numel(tbBits) ~= round(expectedBits)
    error("sixgr:HARQReplay:BadStoredTB", ...
        "%s HARQ replay TB length %d does not match stored transport block size %d.", ...
        upper(string(direction)), numel(tbBits), round(expectedBits));
end
end

function tbContext = localReplayTBContext(grant, harqContext)
tbContext = struct();
if nargin < 1 || ~isstruct(grant)
    grant = struct();
end
if nargin < 2 || ~isstruct(harqContext)
    harqContext = struct();
end
candidates = { ...
    sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
    sixgr.util.structGet(harqContext, "HARQTBContext", struct()), ...
    sixgr.util.structGet(grant, "HARQTBContext", struct())};
for i = 1:numel(candidates)
    candidate = candidates{i};
    if isstruct(candidate) && ~isempty(fieldnames(candidate))
        tbContext = candidate;
        return;
    end
end
end

function [grantSnapshot, harqContext, tbContext, status] = localApplyHARQTransportBlockContext(direction, cfg, grantSnapshot, tx, harqContext, previousCombinedLLR)
if nargin < 5 || ~isstruct(harqContext)
    harqContext = struct();
end
if nargin < 6
    previousCombinedLLR = [];
end
tbContext = localReplayTBContext(grantSnapshot, harqContext);
softCombiningEvidence = localHARQPriorAvailable(previousCombinedLLR);
rvSequence = double(sixgr.util.structGet(tbContext, "RVSequence", ...
    sixgr.util.structGet(cfg, "phy.harq.rvSequence", [0 2 3 1])));
rateMatchedBitsPerCB = double(sixgr.util.structGet(sixgr.util.structGet(tx, "CodingLayout", struct()), "E_r", []));
rateMatchedBitsTotal = double(sixgr.util.structGet(grantSnapshot, "CodedBitCountG", ...
    sixgr.util.structGet(tx, "G", sum(rateMatchedBitsPerCB))));
if ~(isfinite(rateMatchedBitsTotal) && rateMatchedBitsTotal > 0) && ~isempty(rateMatchedBitsPerCB)
    rateMatchedBitsTotal = double(sum(rateMatchedBitsPerCB));
end
meta = struct( ...
    "Direction", char(upper(string(direction))), ...
    "Grant", grantSnapshot, ...
    "PHYGrant", sixgr.util.structGet(grantSnapshot, "PHYGrant", struct()), ...
    "CodingLayout", sixgr.util.structGet(tx, "CodingLayout", struct()), ...
    "PreviousContext", tbContext, ...
    "TransportBlockContext", tbContext, ...
    "IsRetransmission", logical(sixgr.util.structGet(harqContext, "IsRetransmission", false)), ...
    "RateMatchedBitsTotal", double(rateMatchedBitsTotal), ...
    "RateMatchedBitsPerCB", double(rateMatchedBitsPerCB), ...
    "TBSBits", double(sixgr.util.structGet(tx, "TransportBlockSize", sixgr.util.structGet(grantSnapshot, "TBSBits", NaN))), ...
    "ExpectedTBSBits", double(sixgr.util.structGet(grantSnapshot, "TBSBits", ...
        sixgr.util.structGet(grantSnapshot, "TransportBlockSize", NaN))), ...
    "RV", double(sixgr.util.structGet(tx, "RV", sixgr.util.structGet(harqContext, "RV", NaN))), ...
    "PreviousRV", double(sixgr.util.structGet(tbContext, "LastObservedRV", NaN)), ...
    "RVSequence", rvSequence, ...
    "SoftCombiningEvidenceAvailable", logical(softCombiningEvidence), ...
    "PreviousCombinedLLRAvailable", logical(softCombiningEvidence));
[tbContext, status] = sixgr.harq.validateTBContextForTransmission(meta);
grantHarq = sixgr.util.structGet(grantSnapshot, "HARQ", struct());
if ~isstruct(grantHarq)
    grantHarq = struct();
end
grantHarq.NDI = logical(tbContext.NDI);
grantHarq.NDIEpoch = double(tbContext.NDIEpoch);
if ~isfinite(double(sixgr.util.structGet(grantHarq, "HarqID", NaN))) && isfinite(double(tbContext.HARQProcessId))
    grantHarq.HarqID = double(tbContext.HARQProcessId);
end
if ~isfinite(double(sixgr.util.structGet(grantHarq, "HARQProcess", NaN))) && isfinite(double(tbContext.HARQProcessId))
    grantHarq.HARQProcess = double(tbContext.HARQProcessId);
end
grantHarq.RV = double(sixgr.util.structGet(meta, "RV", NaN));
grantHarq.IsRetransmission = logical(sixgr.util.structGet(harqContext, "IsRetransmission", false));
grantSnapshot.HARQ = grantHarq;
grantSnapshot.IsRetransmission = logical(grantHarq.IsRetransmission);
grantSnapshot.HARQTBContext = tbContext;
grantSnapshot.OriginalTBSBits = double(status.OriginalTBSBits);
grantSnapshot.CurrentTBSBits = double(status.CurrentTBSBits);
grantSnapshot.OriginalRateMatchedBits = double(status.OriginalRateMatchedBits);
grantSnapshot.CurrentRateMatchedBits = double(status.CurrentRateMatchedBits);
grantSnapshot.EffectiveInitialCodeRate = double(status.EffectiveInitialCodeRate);
grantSnapshot.EffectiveCurrentTxCodeRate = double(status.EffectiveCurrentTxCodeRate);
grantSnapshot.ShortIRRetx = logical(status.ShortIRRetx);
grantSnapshot.CodeBlockLayoutHash = char(string(status.CodeBlockLayoutHash));
grantSnapshot.HARQContextHash = char(string(status.HARQContextHash));
grantSnapshot.HARQContextStatus = char(string(status.HARQContextStatus));
harqContext.TransportBlockContext = tbContext;
harqContext.HARQTBContext = tbContext;
harqContext.NDI = logical(tbContext.NDI);
harqContext.NDIEpoch = double(tbContext.NDIEpoch);
harqContext.RV = double(sixgr.util.structGet(meta, "RV", NaN));
harqContext.HARQContextHash = char(string(status.HARQContextHash));
harqContext.HARQContextStatus = char(string(status.HARQContextStatus));
if ~isfinite(double(sixgr.util.structGet(harqContext, "HarqID", NaN))) && isfinite(double(tbContext.HARQProcessId))
    harqContext.HarqID = double(tbContext.HARQProcessId);
end
if ~isfinite(double(sixgr.util.structGet(harqContext, "HARQProcess", NaN))) && isfinite(double(tbContext.HARQProcessId))
    harqContext.HARQProcess = double(tbContext.HARQProcessId);
end
end

function cfgOut = localApplyReplayGrantConfig(cfgIn, grant, direction)
cfgOut = cfgIn;
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
if hasPHYGrant
    cfgOut = sixgr.phy.grant.applyPHYGrantToConfig(cfgOut, phyGrant);
end
direction = upper(string(direction));
if direction == "UL"
    root = "phy.pusch";
else
    root = "phy.pdsch";
end
mcsIndex = double(sixgr.util.structGet(grant, "MCSIndex", sixgr.util.structGet(grant, "MCS", NaN)));
numLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
modulation = string(sixgr.util.structGet(grant, "Modulation", ""));
prbSet = sixgr.util.structGet(grant, "PRBSet", []);
symbolAllocation = sixgr.util.structGet(grant, "SymbolAllocation", []);
grantPMI = double(sixgr.util.structGet(grant, "PMI", NaN));
if hasPHYGrant
    ant = phyGrant.AntennaArchitecture;
    ra = phyGrant.ResourceAllocation;
    cl = phyGrant.CodingLayout;
    if ~isfinite(mcsIndex), mcsIndex = double(cl.MCSIndex); end
    if ~isfinite(numLayers), numLayers = double(ant.NumLayers); end
    if ~isfinite(targetCodeRate), targetCodeRate = double(cl.TargetCodeRate); end
    if strlength(strtrim(modulation)) == 0, modulation = string(cl.Modulation); end
    if isempty(prbSet), prbSet = double(ra.PRBSet(:).'); end
    if isempty(symbolAllocation), symbolAllocation = double(ra.SymbolAllocation(:).'); end
end

if ~(isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end

if hasPHYGrant
    txAnt = double(phyGrant.AntennaArchitecture.NumWaveformColumns);
    rxAnt = double(phyGrant.AntennaArchitecture.NumRxAntennas);
else
    txAnt = localReplayEffectiveTxAntennas(cfgOut, direction, numLayers);
    rxAnt = localReplayEffectiveRxAntennas(cfgOut, direction, numLayers);
end
cfgOut = sixgr.util.structSet(cfgOut, "phy.nTxAnt", txAnt);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nRxAnt", rxAnt);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nTxAnt", txAnt);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nRxAnt", rxAnt);
if hasPHYGrant && direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.NumAntennaPorts", double(phyGrant.AntennaArchitecture.NumLogicalPorts));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.numPorts", double(phyGrant.AntennaArchitecture.NumLogicalPorts));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nPorts", double(phyGrant.AntennaArchitecture.NumLogicalPorts));
end

[cfgOut, prbSet] = localAlignReplayCarrierToGrant(cfgOut, grant, prbSet);

if isfinite(mcsIndex)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsIndex", mcsIndex);
end
if isfinite(numLayers) && numLayers >= 1
    cfgOut = sixgr.util.structSet(cfgOut, root + ".numLayers", numLayers);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nLayers", numLayers);
end
if isfinite(targetCodeRate) && targetCodeRate > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".codeRate", targetCodeRate);
end
if strlength(strtrim(modulation)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".modulation", char(modulation));
end
if ~isempty(prbSet)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".prbSet", prbSet);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nPRB", numel(double(prbSet)));
end
if ~isempty(symbolAllocation)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".symbolAllocation", symbolAllocation);
end
if isfinite(grantPMI)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".PMI", grantPMI);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".TPMI", grantPMI);
end
end

function [cfgOut, prbSetOut] = localAlignReplayCarrierToGrant(cfgIn, grant, prbSetIn)
cfgOut = cfgIn;
prbSetOut = prbSetIn;
prbSet = double(prbSetIn(:).');
prbSet = unique(prbSet(isfinite(prbSet) & prbSet >= 0));
useGrantLocalGrid = logical(sixgr.util.structGet(cfgOut, "system.waveform.useGrantLocalGrid", false));

requiredNSizeGrid = NaN;
prbOffset = 0;
if ~isempty(prbSet)
    if useGrantLocalGrid
        prbOffset = min(prbSet);
        requiredNSizeGrid = max(prbSet) - prbOffset + 1;
    else
        requiredNSizeGrid = max(prbSet) + 1;
    end
else
    nprb = double(sixgr.util.structGet(grant, "NPRB", NaN));
    if isfinite(nprb) && nprb >= 1
        requiredNSizeGrid = round(nprb);
    end
end

if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    return;
end

currentNSizeGrid = double(sixgr.util.structGet(cfgOut, "phy.carrier.NSizeGrid", NaN));
if ~(isfinite(currentNSizeGrid) && currentNSizeGrid >= 1)
    currentNSizeGrid = requiredNSizeGrid;
end

if useGrantLocalGrid
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", max(1, round(requiredNSizeGrid)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NStartGrid", max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0))) + round(prbOffset)));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", double(prbOffset));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "grant_allocation");
    if ~isempty(prbSet)
        prbSetOut = prbSet - prbOffset;
    end
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", max(round(currentNSizeGrid), round(requiredNSizeGrid)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NStartGrid", max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0)))));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", 0);
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "full_carrier");
    if ~isempty(prbSet)
        prbSetOut = prbSet;
    end
end
end

function n = localReplayEffectiveTxAntennas(cfg, direction, numLayers)
direction = upper(string(direction));
if direction == "UL"
    explicitUL = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "channel.ul.nTxAnt", []), ...
        sixgr.util.structGet(cfg, "phy.ul.nTxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", []));
    if isfinite(explicitUL) && explicitUL >= 1
        n = localApplyReplayAntennaCap(cfg, explicitUL, numLayers);
        return;
    end
end

explicit = double(sixgr.util.structGet(cfg, "channel.nTxAnt", ...
    sixgr.util.structGet(cfg, "phy.nTxAnt", NaN)));
if isfinite(explicit) && explicit >= 1
    n = localApplyReplayAntennaCap(cfg, explicit, numLayers);
    return;
end
if direction == "UL"
    ueTx = double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1));
    n = localApplyReplayAntennaCap(cfg, ueTx, numLayers);
else
    n = max(1, round(double(numLayers)));
end
end

function n = localReplayEffectiveRxAntennas(cfg, direction, numLayers)
direction = upper(string(direction));
if direction == "UL"
    explicitUL = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "channel.ul.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "phy.ul.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", []));
    if isfinite(explicitUL) && explicitUL >= 1
        n = localApplyReplayAntennaCap(cfg, explicitUL, numLayers);
        return;
    end
end

explicit = double(sixgr.util.structGet(cfg, "channel.nRxAnt", ...
    sixgr.util.structGet(cfg, "phy.nRxAnt", NaN)));
if isfinite(explicit) && explicit >= 1
    n = localApplyReplayAntennaCap(cfg, explicit, numLayers);
    return;
end
if direction == "UL"
    bsRx = double(sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", ...
        sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", 1)));
    n = localApplyReplayAntennaCap(cfg, bsRx, numLayers);
else
    ueRx = double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", 1));
    n = localApplyReplayAntennaCap(cfg, ueRx, numLayers);
end
end

function n = localApplyReplayAntennaCap(cfg, value, numLayers)
n = max(1, round(double(value)));
if logical(sixgr.util.structGet(cfg, "system.waveform.capReplayAntennasToLayers", false))
    n = max(1, min(n, max(1, round(double(numLayers)))));
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function [eqNorm, refNorm] = localNormalizeEVMInputs(eqSym, refSym)
eqNorm = [];
refNorm = [];
eqSym = eqSym(:);
refSym = refSym(:);
valid = isfinite(real(eqSym)) & isfinite(imag(eqSym)) & ...
    isfinite(real(refSym)) & isfinite(imag(refSym));
eqSym = eqSym(valid);
refSym = refSym(valid);
if isempty(eqSym) || isempty(refSym)
    return;
end
eqPower = mean(abs(eqSym).^2, "omitnan");
refPower = mean(abs(refSym).^2, "omitnan");
if ~(isfinite(eqPower) && eqPower > eps && isfinite(refPower) && refPower > eps)
    return;
end
eqNorm = eqSym ./ sqrt(eqPower);
refNorm = refSym ./ sqrt(refPower);
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    raw = obj.(propName);
catch
    return;
end
if isempty(raw)
    return;
end
value = raw;
end

function value = localScalarLogicalGrantField(grant, fieldName, defaultValue)
raw = sixgr.util.structGet(grant, fieldName, defaultValue);
validLogical = islogical(raw) && isscalar(raw);
validNumeric = isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
    isfinite(double(raw)) && any(double(raw) == [0 1]);
if ~(validLogical || validNumeric)
    error("sixgr:link:InvalidGrantLineage", ...
        "UL grant field %s must be a scalar logical authority, received class %s with %d elements.", ...
        string(fieldName), string(class(raw)), numel(raw));
end
value = logical(raw);
end
