function out = runDLPDSCHThroughput(cfg, varargin)
%RUNDLPDSCHTHROUGHPUT DL PDSCH throughput/BLER sweep at one SNR point.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumFrames", sixgr.util.structGet(cfg, "run.numFrames", 10), @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 18), @(x) isnumeric(x) && isscalar(x));
p.addParameter("InitialLinkAdaptationState", [], @(x) isempty(x) || isstruct(x));
p.addParameter("StartFrameIndex", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("StartSlotIndex", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("LiveTrialCallback", [], @(x) isempty(x) || isa(x, "function_handle"));
p.addParameter("LiveCallbackInterval", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("TransportBlockBits", [], @(x) isempty(x) || isnumeric(x) || islogical(x) || iscell(x));
p.addParameter("RV", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0 && x <= 3));
p.addParameter("HARQContext", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("GrantSnapshot", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("PHYGrant", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("PreviousCombinedLLR", [], @(x) isempty(x) || isnumeric(x) || isstruct(x) || iscell(x));
p.addParameter("InterferenceBundle", struct([]), @(x) isempty(x) || isstruct(x));
p.addParameter("ChannelState", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("ExecutionProfile", "", @(x) ischar(x) || isstring(x));
p.addParameter("Assignment", [], @(x) true);
p.addParameter("ResourcePlan", [], @(x) true);
p.addParameter("Carrier", [], @(x) true);
p.addParameter("ReferenceSignalConfig", struct(), @(x) true);
p.addParameter("ReceiverConfig", struct(), @(x) true);
p.addParameter("PrecoderBundle", [], @(x) true);
p.addParameter("IntegrationContext", struct(), @(x) true);
p.addParameter("HARQManager", [], @(x) true);
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
configuredPDSCH = logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "scheduled_pdsch", ...
    configuredPDSCH, "sixgr.link.runDLPDSCHThroughput");
if ~configuredPDSCH
    % Coverage enablement is the outermost contract.  In strict/no-proxy
    % mode it must fail with the coverage identifier before an execution
    % profile or assignment is inspected; disabled PHY cannot be rescued
    % by, or confused with, a missing downstream profile.
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.pdsch.enable=true for PDSCH coverage.");
end
if ~(isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride)))
    grantSnapshotOverride = sixgr.util.structGet(harqContext, "GrantSnapshot", struct());
end
if ~(isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride)))
    phyGrantOverride = sixgr.util.structGet(grantSnapshotOverride, "PHYGrant", struct());
end
schedulerDrivenGrant = (isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride))) || ...
    (isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride)));
executionContract = localResolvePDSCHThroughputExecutionContract( ...
    cfg, p.Results, schedulerDrivenGrant);
if isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride))
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrantOverride, "run_dl_pdsch_throughput_entry");
    if ~(isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride)))
        grantSnapshotOverride = sixgr.util.structGet(phyGrantOverride, "LegacyGrantSnapshot", struct());
    end
    grantSnapshotOverride = localAlignGrantSnapshotToPHYGrant(grantSnapshotOverride, phyGrantOverride);
    grantSnapshotOverride.PHYGrant = phyGrantOverride;
    grantSnapshotOverride.PHYGrantContextId = char(string(phyGrantOverride.GrantContextId));
end
if executionContract.IsStrict
    isRetransmission = false;
else
    [grantSnapshotOverride, phyGrantOverride] = localNormalizeHARQReplayGrantInputs( ...
        cfg, grantSnapshotOverride, phyGrantOverride, transportBlockBits, harqContext, snr_dB, startFrameIndex, startSlotIndex);
    isRetransmission = localInferHARQReplayMode(grantSnapshotOverride, phyGrantOverride, harqContext, transportBlockBits);
    if isRetransmission
        harqContext.IsRetransmission = true;
    end
end

[prepareOnly, receivedCompletion, preparedTransmission, preparedBinding] = ...
    sixgr.link.validateDataStreamRequest(cfg,p.Results,"DL", ...
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
out.DecodeLatency_ms = NaN;
out.EarlyStopRate = NaN;
out.DecoderComplexityUnits = NaN;
out.NormalizedDecoderComplexity = NaN;
out.AreaEfficiencyProxy = NaN;
out.TrialTable = localEmptyTrialTable();
out.CSIRSTrialTable = localEmptyCSIRSTrialTable();
out.ObservedREAllocationTable = table();
out.ConstellationSamples = table();
out.SignalDiagnostic = struct( ...
    "Available", false, ...
    "Reason", "capture_not_attempted", ...
    "Direction", "DL", ...
    "SnapshotID", "", ...
    "Metadata", struct(), ...
    "SourceTable", table());
out.HARQ = struct();
out.ExecutionProfile = executionContract.Profile;
out.ExecutionTaxonomy = executionContract.Taxonomy;
out.ExecutionBackend = executionContract.Backend;
out.ApproximationMode = "none";
out.StrictSchedulingOwnership = executionContract.IsStrict;
out.ConnectedStrictCertified = false;
out.CalibrationProvenance = executionContract.CalibrationProvenance;
out.ISACWaveformCapture = struct();
isacCaptureRequired = logical(sixgr.util.structGet(cfg,"isac.enabled",false));
isacWaveformCapture = struct();
out.TxWaveformCapture = struct();
txWaveformCaptureRequired = logical(sixgr.util.structGet(cfg, ...
    "outputs.rawIQCaptureEnabled", false)) && logical(sixgr.util.structGet( ...
    cfg, "outputs.saveRawWaveforms", false));
txWaveformCapture = struct();

if ~configuredPDSCH
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.pdsch.enable=true for PDSCH coverage.");
    sixgr.perf.TimeProfiler.markSkipped("sixgr.link.runDLPDSCHThroughput", "dl_pdsch", ...
        "phy.pdsch.enable=false");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.pdsch.enable=false";
    return;
end

if exist("nrPDSCH","file") ~= 2 || exist("nrPDSCHDecode","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrPDSCH/nrPDSCHDecode for PDSCH coverage.");
    sixgr.perf.TimeProfiler.markSkipped("sixgr.link.runDLPDSCHThroughput", "dl_pdsch", ...
        "nrPDSCH_or_nrPDSCHDecode_unavailable");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPDSCH APIs unavailable.";
    return;
end

if executionContract.IsStrict
    out = localRunCanonicalStrictPDSCHPoint( ...
        cfg, p.Results, executionContract, numFrames, snr_dB, ...
        startFrameIndex, startSlotIndex);
    return;
end

profScope = sixgr.perf.TimeProfiler.scope("sixgr.link.runDLPDSCHThroughput", ...
    "Stage", "dl_pdsch", ...
    "Metadata", struct( ...
    "NumFrames", double(numFrames), ...
    "NSubcarriers", double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)) * 12, ...
    "NSymbols", 14, ...
    "NRx", double(sixgr.util.structGet(cfg, "channel.nRxAnt", 1)), ...
    "NTx", double(sixgr.util.structGet(cfg, "channel.nTxAnt", 1)), ...
    "NLayers", double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))); %#ok<NASGU>

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
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
chanModel = localResolveTrialChannelModel(cfg);
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", ...
    sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
cfgDyn = cfg;
laState = initialLAState;
slotDur_s = localSlotDuration(cfg);

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
trialCSIRSRPPhysical = NaN(numFrames,1);
trialCSIRSRPPhysicalSource = strings(numFrames,1);
trialCSIRSRPPhysicalStatus = strings(numFrames,1);
trialCSIRSRPPowerReferencePlane = strings(numFrames,1);
trialCSIRSSI = NaN(numFrames,1);
trialCSIRSSISource = strings(numFrames,1);
trialCSIRSRQ = NaN(numFrames,1);
trialCSIRSRQSource = strings(numFrames,1);
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
trialCSIReportMode = strings(numFrames,1);
trialCSIPayloadBits = NaN(numFrames,1);
trialCSIPayloadHex = strings(numFrames,1);
trialCSIComputationStatus = strings(numFrames,1);
trialCSIComputationErrorIdentifier = strings(numFrames,1);
trialCSIMeasurementID = strings(numFrames,1);
trialCSIMeasurementDigest = strings(numFrames,1);
trialCSIMeasurementProvenance = strings(numFrames,1);
trialCSIMeasurementSlot = NaN(numFrames,1);
trialSubbandCQI = strings(numFrames,1);
trialSubbandSINR = strings(numFrames,1);
trialSubbandSizePRB = NaN(numFrames,1);
trialSubbandCount = NaN(numFrames,1);
trialWidebandOrSubband = strings(numFrames,1);
trialSubbandCQISource = strings(numFrames,1);
trialSubbandCQIStatus = strings(numFrames,1);
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
trialDLSCHDecodeAttempted = false(numFrames,1);
trialDLSCHDecodeAvailable = false(numFrames,1);
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
trialEqualizerType = strings(numFrames,1);
trialEqualizerRequestedType = strings(numFrames,1);
trialEqualizerEngine = strings(numFrames,1);
trialEqualizerCovarianceFactorizationCount = NaN(numFrames,1);
trialInterferenceCovarianceAvailable = false(numFrames,1);
trialInterferenceCovarianceSource = strings(numFrames,1);
trialInterferenceCovarianceStatus = strings(numFrames,1);
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
trialConditionNumberStatus = strings(numFrames,1);
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
trialBeamformingApplied = false(numFrames,1);
trialAppliedBeamIndexSet = strings(numFrames,1);
trialAppliedPrecoderPMI = NaN(numFrames,1);
trialRequestedPrecoderPMI = NaN(numFrames,1);
trialRequestedPrecoderSource = strings(numFrames,1);
trialAppliedPrecoderPMIType = strings(numFrames,1);
trialAppliedPrecoderCodebookMode = strings(numFrames,1);
trialPrecodingNumPorts = NaN(numFrames,1);
trialPrecodingNumLayers = NaN(numFrames,1);
trialPrecodingMatrixRows = NaN(numFrames,1);
trialPrecodingMatrixCols = NaN(numFrames,1);
trialAppliedPrecoderMatrixSHA256 = strings(numFrames,1);
trialRequestedPrecoderSHA256 = strings(numFrames,1);
trialAppliedPrecoderSHA256 = strings(numFrames,1);
trialPrecoderDigestDomain = strings(numFrames,1);
trialFrozenGrantContextId = strings(numFrames,1);
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
trialRuntimeEvidence = cell(numFrames,1);
trialMeasuredPHYEvidence = cell(numFrames,1);
csirsRows = repmat(localEmptyCSIRSRuntimeTrialRow(), 0, 1);
constellationChunks = cell(numFrames,1);
waveformChunks = cell(numFrames,1);
observedREChunks = cell(numFrames,1);
signalDiagnostic = out.SignalDiagnostic;
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
trialChan = repmat(chanModel, numFrames, 1);
trialDopp = dopplerHz * ones(numFrames,1);
liveCallbackWarned = false;
lastHARQ = struct();

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
            [cfgDyn, laState, laApplyEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "DL", trialSlot(n), "Phase", "before");
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
        cfgFrame = localApplyReplayGrantConfig(cfgFrame, grantSnapshotOverride, "DL");
        % StartFrameIndex is also the Monte-Carlo trial sequence in the
        % standalone runner.  Only scheduler-owned grants carry an
        % independently authoritative NR frame/slot pair.  In every case
        % nrCarrierConfig timing is derived from the absolute slot; for a
        % scheduler grant the supplied frame is additionally checked.
        authoritativeFrame = NaN;
        if schedulerDrivenGrant
            authoritativeFrame = frameIdx;
        end
        [cfgFrame, ~] = sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
            cfgFrame, trialSlot(n), authoritativeFrame);
        % CSI-RS is a separately scheduled reference resource and is not
        % owned by the frozen PDSCH grant. Keep the YAML feature switch
        % unchanged on HARQ replay; the replay may freeze data-channel
        % dimensions, but it cannot silently disable CSI-RS.
        trialMCS(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.mcsIndex", NaN));
        trialModulation(n) = string(sixgr.util.structGet(cfgFrame, "phy.pdsch.modulation", ""));
        trialCodeRate(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.codeRate", NaN));
        trialLinkAdaptationMode(n) = string(localResolveLinkAdaptationMode(cfgFrame, "DL"));
        trialActualMCSSelectionMode(n) = string(localResolveActualMCSSelectionMode(cfgFrame, "DL"));
        trialSchedulerGrantMCSSelectionMode(n) = string(sixgr.util.structGet(grantSnapshotOverride, "AMCMode", ""));
        trialMCSValueStatus(n) = string(sixgr.util.structGet(grantSnapshotOverride, "MCSValueStatus", ""));
        grantCQIUsed = double(sixgr.util.structGet(grantSnapshotOverride, "CQIUsed", NaN));
        grantRawCQIDerivedMCS = localFirstFiniteScalar( ...
            sixgr.util.structGet(grantSnapshotOverride, "RawCQIDerivedMCS", NaN));
        grantCQIBasedMCS = localFirstFiniteScalar( ...
            sixgr.util.structGet(grantSnapshotOverride, "CQIBasedMCS", NaN));
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
        trialCQITable(n) = string(localResolveCQITable(cfgFrame, "DL"));
        trialMCSTable(n) = string(localResolveMCSTable(cfgFrame, "DL"));
        trialCfgPMI(n) = localFirstFiniteScalar(sixgr.util.structGet(cfgFrame, "phy.pdsch.PMI", NaN));
        trialCfgCRI(n) = double(sixgr.util.structGet(cfgFrame, "phy.beamManagement.selectedCRI", NaN));
        trialConfiguredBeamSelectionStrategy(n) = string(sixgr.util.structGet(cfgFrame, "lls6g.userContext.BeamSelectionStrategy", ""));
        if isRetransmission
            [trialMCS(n), trialModulation(n), trialCodeRate(n)] = localOverrideReportedGrantFields( ...
                trialMCS(n), trialModulation(n), trialCodeRate(n), grantSnapshotOverride);
        end

        txArgs = {"ExecutionProfile", char(executionContract.Profile)};
        if executionContract.Profile == "scheduler_truth"
            txArgs = [txArgs {"SchedulerGrantContext", grantSnapshotOverride}]; %#ok<AGROW>
        end
        txArgs = localAppendGrantReplayTxArgs( ...
            txArgs, grantSnapshotOverride, cfgFrame);
        if isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride))
            txArgs = [txArgs {"PHYGrant", phyGrantOverride}]; %#ok<AGROW>
        end
        if ~isempty(transportBlockBits)
            localAssertReplayTBConsistency(transportBlockBits, grantSnapshotOverride, "DL");
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        if ~isempty(rvOverride)
            txArgs = [txArgs {"RV", rvOverride}]; %#ok<AGROW>
        end
        localAssertReplayPHYGrantReady(isRetransmission, grantSnapshotOverride, phyGrantOverride, transportBlockBits);
        localDLStageProgressLog(cfgFrame, ...
            "frame=%g slot=%g stage=tx_start tbs=%g mcs=%g layers=%g", ...
            frameIdx, trialSlot(n), ...
            double(sixgr.util.structGet(grantSnapshotOverride, "TBSBits", NaN)), ...
            trialMCS(n), trialLayers(n));
        stageTic = tic;
        if receivedCompletion
            tx = preparedTransmission.Tx;
            txInfo = preparedTransmission.TxInfo;
        else
            [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfgFrame, txArgs{:});
        end
        trialRuntimeAbsoluteSlot0(n) = double(sixgr.util.structGet(cfgFrame, ...
            "lls6g.runtime.AbsoluteSlotIndex0", NaN));
        trialCarrierNSlot(n) = double(tx.Carrier.NSlot);
        trialCarrierNFrame(n) = double(tx.Carrier.NFrame);
        trialSFN(n) = mod(trialCarrierNFrame(n), 1024);
        localAssertExecutedCarrierTimeline(cfgFrame, tx.Carrier, "DL");
        observedUEIndex = double(sixgr.util.structGet(grantSnapshotOverride, ...
            "UEIndex", sixgr.util.structGet(cfgFrame, ...
            "lls6g.userContext.UEIndex", NaN)));
        observedBaseStationID = double(sixgr.util.structGet( ...
            grantSnapshotOverride, "BaseStationID", ...
            sixgr.util.structGet(cfgFrame, ...
            "lls6g.userContext.RuntimeServingCell", NaN)));
        observedREChunks{n} = sixgr.truth.buildObservedREAllocation(tx, ...
            "Direction", "DL", "AbsoluteSlot", trialSlot(n) - 1, ...
            "CellID", observedBaseStationID, "UEID", observedUEIndex, ...
            "LayerCount", trialLayers(n), "AllocationID", ...
            string(sixgr.util.structGet(grantSnapshotOverride, ...
                "PHYGrantContextId", sixgr.util.structGet( ...
                grantSnapshotOverride, "GrantContextId", ""))));
        trialTxWaveformColumns(n) = double(size(tx.Waveform, 2));
        trialPhysicalTxAntennas(n) = double(sixgr.util.structGet(tx, ...
            "NPhysicalTxAntennas", size(tx.Waveform, 2)));
        txPrecoding = sixgr.util.structGet(txInfo, "Precoding", struct());
        trialTxWaveformDomain(n) = string(sixgr.util.structGet(txPrecoding, ...
            "WaveformDomain", "logical_port"));
        trialHybridElementDomainApplied(n) = logical(sixgr.util.structGet( ...
            txPrecoding, "HybridElementDomainApplied", false));
        localAssertDLHybridElementDomainExecution(cfgFrame, tx, txInfo);
        localDLStageProgressLog(cfgFrame, ...
            "frame=%g slot=%g stage=tx_done elapsed_s=%.3f waveform_samples=%g", ...
            frameIdx, trialSlot(n), toc(stageTic), double(size(tx.Waveform, 1)));
        if receivedCompletion
            powerContext = tx.PowerContext;
            cfgFrame = preparedTransmission.ReceiverConfig;
        else
            [tx.Waveform, powerContext] = sixgr.rf.applyPowerContext( ...
                tx.Waveform, cfgFrame, "DL", txInfo,"ApplyPA",~prepareOnly);
        end
        tx.PowerContext = powerContext;
        txInfo.PowerContext = powerContext;
        cfgFrame = sixgr.util.structSet(cfgFrame, "lls6g.runtimePowerContext", powerContext);
        if prepareOnly
            out.PreparedTransmission = sixgr.link.PreparedDataTransmission( ...
                "DL",cfg,preparedBinding,tx,txInfo,cfgFrame, ...
                localResolveSampleRate(tx,txInfo),1e3*toc(trialPipelineTic));
            out.ExecutionStage = "transmit_prepared_not_received";
            out.ExecutionTaxonomy = "authored_scheduler_grant_coded_transmission";
            out.ExecutionBackend = "scheduler_coded_transmitter_pre_node_rf";
            out.Notes = "Coded PDSCH prepared; no node RF, channel, decoder or received trial executed.";
            out.ChannelState = chStateIn;
            return;
        end
        if receivedCompletion
            tx.Waveform = preparedTransmission.readObservation( ...
                p.Results.ReceivedContext.TransmitterObservation,preparedTransmission.NumPhysicalTransmitAntennas,"transmitter");
            trialTxWaveformColumns(n) = size(tx.Waveform,2);
            trialPhysicalTxAntennas(n) = size(tx.Waveform,2);
            trialTxWaveformDomain(n) = "physical_antenna_transmitter_composite";
        elseif sixgr.rf.hasExplicitTransmitConfig(cfgFrame)
            txRfOut = sixgr.rf.applyRFImpairmentChain(tx.Waveform, cfgFrame, ...
                "SampleRateHz", localResolveSampleRate(tx, txInfo), ...
                "Direction", "DL", ...
                "MeasurementPoint", "tx_output", ...
                "Endpoint", "tx", ...
                "StrictMutationRequired", false, ...
                "UseLegacyGlobalConfig", false, ...
                "ApplyPA", false, ...
                "ApplyADC", false);
            tx.Waveform = cast(txRfOut.Waveform, "like", tx.Waveform);
            tx.TxRFImpairmentReplay = txRfOut.Replay;
            txInfo.TxRFImpairmentReplay = txRfOut.Replay;
            cfgFrame = sixgr.util.structSet(cfgFrame, "lls6g.txRFImpairmentReplay", txRfOut.Replay);
        end
        if isacCaptureRequired && isempty(fieldnames(isacWaveformCapture))
            % Capture the exact post-power-context/post-Tx-RF PDSCH samples
            % that continue into the production channel and receiver.  The
            % sensing branch is attached later by the serial coordinator;
            % it never regenerates or substitutes a configured waveform.
            isacWaveformCapture = struct( ...
                "Waveform",tx.Waveform, ...
                "SampleRateHz",double(localResolveSampleRate(tx,txInfo)), ...
                "Frame",double(frameIdx), ...
                "Slot",double(trialSlot(n)), ...
                "CapturePoint","post_power_and_tx_rf_pre_channel", ...
                "WaveformAuthority","exact_runtime_pdsch_waveform");
        end
        if txWaveformCaptureRequired && isempty(fieldnames(txWaveformCapture))
            txWaveformCapture = struct( ...
                "Waveform",tx.Waveform, ...
                "SampleRateHz",double(localResolveSampleRate(tx,txInfo)), ...
                "Frame",double(frameIdx), ...
                "Slot",double(trialSlot(n)), ...
                "CapturePoint","post_power_and_tx_rf_pre_channel", ...
                "WaveformAuthority","exact_runtime_pdsch_waveform");
        end
        if receivedCompletion
            if ~isempty(fieldnames(isacWaveformCapture))
                isacWaveformCapture.WaveformAuthority = "exact_runtime_transmitter_composite_observation";
            end
            if ~isempty(fieldnames(txWaveformCapture))
                txWaveformCapture.WaveformAuthority = "exact_runtime_transmitter_composite_observation";
            end
        end
        grantSnapshot = localBuildHARQGrantSnapshot(tx, trialMCS(n), cfgFrame, ...
            grantSnapshotOverride, frameIdx, trialSlot(n), trialSeed(n));
        [grantSnapshot, harqContext, harqTBContext, harqTBStatus] = localApplyHARQTransportBlockContext( ...
            "DL", cfgFrame, grantSnapshot, tx, harqContext, previousCombinedLLR);
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
        harqTrace = localResolveDLHARQTrialTrace(cfgFrame, grantSnapshot, harqContext, frameIdx, isRetransmission);
        trialHARQProcess(n) = double(harqTrace.HARQProcess);
        trialHARQRound(n) = double(harqTrace.HARQRound);
        trialHARQNDI(n) = double(harqTrace.NDI);
        trialHARQIsRetransmission(n) = logical(harqTrace.IsRetransmission);
        if isfinite(double(harqTrace.RV))
            trialRV(n) = double(harqTrace.RV);
        end
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
        dlPrecoding = localResolveDLPrecodingTrace(cfgFrame, tx, grantSnapshot);
        trialPrecoderSource(n) = string(dlPrecoding.PrecoderSource);
        trialPrecodingMode(n) = string(dlPrecoding.PrecodingMode);
        trialPrecodingApplicationStage(n) = string(dlPrecoding.PrecodingApplicationStage);
        trialPrecodingActive(n) = logical(dlPrecoding.PrecodingActive);
        trialExplicitBeamWeightsApplied(n) = logical(dlPrecoding.ExplicitBeamWeightsApplied);
        trialTransformPrecodingApplied(n) = logical(dlPrecoding.TransformPrecodingApplied);
        trialBeamformingApplied(n) = logical(dlPrecoding.BeamformingApplied);
        trialAppliedBeamIndexSet(n) = string(dlPrecoding.AppliedBeamIndexSet);
        trialAppliedPrecoderPMI(n) = double(dlPrecoding.AppliedPrecoderPMI);
        trialRequestedPrecoderPMI(n) = double(dlPrecoding.RequestedPrecoderPMI);
        trialRequestedPrecoderSource(n) = string(dlPrecoding.RequestedPrecoderSource);
        trialAppliedPrecoderPMIType(n) = string(dlPrecoding.AppliedPrecoderPMIType);
        trialAppliedPrecoderCodebookMode(n) = string(dlPrecoding.AppliedPrecoderCodebookMode);
        trialPrecodingNumPorts(n) = double(dlPrecoding.PrecodingNumPorts);
        trialPrecodingNumLayers(n) = double(dlPrecoding.PrecodingNumLayers);
        trialPrecodingMatrixRows(n) = double(dlPrecoding.PrecodingMatrixRows);
        trialPrecodingMatrixCols(n) = double(dlPrecoding.PrecodingMatrixCols);
        trialAppliedPrecoderMatrixSHA256(n) = string(dlPrecoding.AppliedPrecoderMatrixSHA256);
        trialRequestedPrecoderSHA256(n) = string(dlPrecoding.RequestedPrecoderSHA256);
        trialAppliedPrecoderSHA256(n) = string(dlPrecoding.AppliedPrecoderSHA256);
        trialPrecoderDigestDomain(n) = string(dlPrecoding.PrecoderDigestDomain);
        trialFrozenGrantContextId(n) = string(dlPrecoding.FrozenGrantContextId);
        if isfield(tx, "PDSCH")
            try
                trialPRB(n) = numel(tx.PDSCH.PRBSet);
            catch
            end
            try
                trialLayers(n) = double(tx.PDSCH.NumLayers);
            catch
            end
            try
                trialModulation(n) = localCommonTextToken( ...
                    tx.PDSCH.Modulation);
            catch
            end
        end
        if isfield(tx, "TransportBlockSize")
            trialTB(n) = sum(double(tx.TransportBlockSize(:)));
        end
        if isfield(tx, "RV")
            trialRV(n) = localCommonFiniteScalar(tx.RV);
        end
        if isfield(tx, "TargetCodeRate")
            trialCodeRate(n) = localCommonFiniteScalar( ...
                tx.TargetCodeRate);
        end
        if receivedCompletion
            chState = p.Results.ReceivedContext.ChannelState;
        elseif externalChannelState
            chState = localPrepareRuntimeChannelState(chState, cfgFrame, tx, txInfo, "DL");
        elseif ~chState.Initialized
            chState = localInitChannelState(cfgFrame, tx, txInfo, snr_dB, trialSeed(n));
        end
        useIdealTimingSync = localUseIdealTimingSync(cfgFrame);
        localDLStageProgressLog(cfgFrame, ...
            "frame=%g slot=%g stage=channel_start interferers=%g", ...
            frameIdx, trialSlot(n), double(numel(interferenceBundle)));
        stageTic = tic;
        captureDiagnosticPathGains = logical(sixgr.util.structGet( ...
            cfgFrame, "outputs.phySignalDiagnosticEnabled", false)) && ...
            ~logical(sixgr.util.structGet(signalDiagnostic, "Available", false));
        if receivedCompletion
            rxWave = p.Results.ReceivedContext.Observation.readComplete();
            physicalMeasurementWaveform = ...
                p.Results.ReceivedContext.PhysicalMeasurementObservation.readComplete();
            replay = p.Results.ReceivedContext.Replay;
        else
            [rxWave, replay, chState, physicalMeasurementWaveform] = ...
                localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState, ...
                cfgFrame, tx, txInfo, interferenceBundle, ...
                captureDiagnosticPathGains);
        end
        trialRxWaveformBranches(n) = double(size(rxWave, 2));
        trialPhysicalRxAntennas(n) = double(size(rxWave, 2));
        localDLStageProgressLog(cfgFrame, ...
            "frame=%g slot=%g stage=channel_done elapsed_s=%.3f rx_samples=%g", ...
            frameIdx, trialSlot(n), toc(stageTic), double(size(rxWave, 1)));
        if ~receivedCompletion
            cfgFrame = localAttachReceiverSyncRuntimeContext(cfgFrame, chState, replay);
        end

        physicalMeasurementSource = "runDLPDSCHThroughput_post_channel_interference_noise_pre_rx_rf_adc";
        if receivedCompletion
            physicalMeasurementSource = "shared_stream_receiver_antenna_connector_observation";
        end
        rxArgs = {"ExecutionProfile", char(executionContract.Profile), ...
            "Carrier", tx.Carrier, ...
            "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, ...
            "CSIRSIndices", sixgr.util.structGet(tx, "CSIRSIndices", []), ...
            "CSIRSSymbols", sixgr.util.structGet(tx, "CSIRSSymbols", []), ...
            "CSIRSInfo", sixgr.util.structGet(tx, "CSIRSInfo", struct()), ...
            "CSIRSConfig", sixgr.util.structGet(tx, "CSIRS", []), ...
            "CSIRSScheduled", logical(sixgr.util.structGet(sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct()), "Scheduled", false)), ...
            "CSIRSTransmitted", logical(sixgr.util.structGet(sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct()), "Transmitted", false)), ...
            "PhysicalMeasurementWaveform", physicalMeasurementWaveform, ...
            "PhysicalMeasurementReferencePlane", ...
                "receiver_antenna_connector_pre_composite_front_end", ...
            "PhysicalMeasurementSource", ...
                physicalMeasurementSource, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "CodingPlan", tx.CodingPlans, ...
            "CodingLayout", tx.CodingLayout, ...
            "SkipTimingEstimate", useIdealTimingSync};
        if receivedCompletion
            rxArgs=[rxArgs {'TimingSearchWindowSamples', ...
                preparedTransmission.receiverTimingSearchWindow(p.Results.ReceivedContext.Observation)}];
        end
        if executionContract.Profile == "scheduler_truth"
            rxArgs = [rxArgs {"SchedulerGrantContext", grantSnapshotOverride}]; %#ok<AGROW>
        end
        if isstruct(phyGrantOverride) && ~isempty(fieldnames(phyGrantOverride))
            rxArgs = [rxArgs {"PHYGrant", phyGrantOverride}]; %#ok<AGROW>
        end
        injectedNoiseVariance = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
        % Shared samples have passed RF/ADC and measured gain compensation.
        % Do not replace the received DM-RS disturbance estimate with the
        % pre-front-end injected thermal variance retained for scoring.
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
        localDLStageProgressLog(cfgFrame, ...
            "frame=%g slot=%g stage=rx_start noise_var=%g noise_domain=%s", ...
            frameIdx, trialSlot(n), injectedNoiseVariance, "time");
        stageTic = tic;
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgFrame, rxArgs{:});
        if receivedCompletion
            out.ReceiveTiming=rx.ReceiveTiming;
        end
        rxCallElapsed_s = toc(stageTic);
        trialReceiverPipelineLatency(n) = 1e3 * rxCallElapsed_s;
        trialReceiverPipelineLatencySource(n) = "matlab_tic_toc_pdsch_receiver_call";
        trialChannelEstimationLatency(n) = double(sixgr.util.structGet( ...
            rx, "ChannelEstimationLatency_ms", NaN));
        trialEqualizationLatency(n) = double(sixgr.util.structGet( ...
            rx, "EqualizationLatency_ms", NaN));
        trialReceiverStageLatencySource(n) = string(sixgr.util.structGet( ...
            rx, "ReceiverStageLatencySource", "unavailable"));
        localDLStageProgressLog(cfgFrame, ...
            "frame=%g slot=%g stage=rx_done elapsed_s=%.3f crc_pass=%g decoder_iter=%g", ...
            frameIdx, trialSlot(n), rxCallElapsed_s, double(logical(sixgr.util.structGet(rx, "CRCPass", false))), ...
            double(sixgr.util.structGet(rx, "DecoderIterations", NaN)));
        trialMeasuredPHYEvidence{n} = sixgr.link.deriveMeasuredPHYEvidence(rx);
        replay = localFinalizeImpairmentReplay(replay, cfgFrame, rx, tx, txInfo, useIdealTimingSync);
        waveformChunks{n} = sixgr.link.buildWaveformPreviewTable("DL", snr_dB, trialFrame(n), trialSlot(n), ...
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
        trialEqualizerType(n) = string(sixgr.util.structGet(rx, "EqualizerType", ""));
        trialEqualizerRequestedType(n) = string(sixgr.util.structGet(rx, "EqualizerRequestedType", ""));
        trialEqualizerEngine(n) = string(sixgr.util.structGet(rx, "EqualizerEngine", ""));
        trialEqualizerCovarianceFactorizationCount(n) = double(sixgr.util.structGet( ...
            rx, "EqualizerCovarianceFactorizationCount", NaN));
        trialInterferenceCovarianceAvailable(n) = logical(sixgr.util.structGet(rx, "InterferenceCovarianceAvailable", false));
        trialInterferenceCovarianceSource(n) = string(sixgr.util.structGet(rx, "InterferenceCovarianceSource", ""));
        trialInterferenceCovarianceStatus(n) = string(sixgr.util.structGet(rx, "InterferenceCovarianceStatus", ""));
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
        trialDLSCHDecodeAttempted(n) = logical(sixgr.util.structGet(rx, "DLSCHDecodeAttempted", trialDecodeAttempted(n)));
        trialDLSCHDecodeAvailable(n) = logical(sixgr.util.structGet(rx, "DLSCHDecodeAvailable", false));
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
        trialConfiguredSNR(n) = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
        trialAppliedAWGNSNR(n) = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
        trialDesiredSignalPowerBeforeNoise(n) = double(sixgr.util.structGet(replay, "DesiredSignalPowerBeforeNoise", NaN));
        trialCompositeSignalPowerBeforeNoise(n) = double(sixgr.util.structGet(replay, "CompositeSignalPowerBeforeNoise", NaN));
        trialAppliedNoiseSNR(n) = double(sixgr.util.structGet(replay, "AppliedNoiseSNR_dB", NaN));
        trialNoiseVarianceSource(n) = string(sixgr.util.structGet(replay, "NoiseVarianceSource", ""));
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
        trialTrueTiming(n) = trialInjectedTiming(n);
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
        trialRuntimeEvidence{n} = localBuildRuntimeAntennaTimingEvidence("DL", cfgFrame, grantSnapshot, tx, txInfo, chState, replay);
        if ~trialDecodeUsable(n)
            % CSI-RS is an independently observable reference signal.  A
            % failed or unavailable PDSCH decode must not erase a valid
            % CSI-RS measurement made earlier in the same receiver chain.
            % Preserve that measurement before terminating this data-trial
            % branch so field-power and low-SINR runs retain truthful CSI
            % evidence without fabricating a successful data decode.
            unavailableMetrics = localAnalyzeChannelMetrics( ...
                sixgr.util.structGet(rx, "ChannelEstimate", []), ...
                trialNoise(n), cfgFrame, rx, dlPrecoding);
            trialCSIRSRP(n) = unavailableMetrics.CSI_RSRP_dB;
            trialCSIRSRPSource(n) = string(unavailableMetrics.CSI_RSRPSource);
            trialCSIRSRPPhysical(n) = unavailableMetrics.CSI_RSRP_dBm;
            trialCSIRSRPPhysicalSource(n) = string(unavailableMetrics.CSI_RSRPPhysicalSource);
            trialCSIRSRPPhysicalStatus(n) = string(unavailableMetrics.CSI_RSRPPhysicalStatus);
            trialCSIRSRPPowerReferencePlane(n) = string(unavailableMetrics.CSI_RSRPPowerReferencePlane);
            trialCSIRSSI(n) = unavailableMetrics.CSI_RSSI_dB;
            trialCSIRSSISource(n) = string(unavailableMetrics.CSI_RSSISource);
            trialCSIRSRQ(n) = unavailableMetrics.CSI_RSRQ_dB;
            trialCSIRSRQSource(n) = string(unavailableMetrics.CSI_RSRQSource);
            trialCSIComputationStatus(n) = string(unavailableMetrics.CSIComputationStatus);
            trialCSIComputationErrorIdentifier(n) = string(unavailableMetrics.CSIComputationErrorIdentifier);
            trialCSIMeasurementID(n) = string(unavailableMetrics.CSIMeasurementID);
            trialCSIMeasurementDigest(n) = string(unavailableMetrics.CSIMeasurementDigest);
            trialCSIMeasurementProvenance(n) = string(unavailableMetrics.CSIMeasurementProvenance);
            trialCSIMeasurementSlot(n) = double(unavailableMetrics.CSIMeasurementSlot);
            unavailableCSIRSRow = localBuildCSIRSRuntimeTrialRow( ...
                cfgFrame, grantSnapshot, tx, rx, unavailableMetrics, ...
                frameIdx, trialSlot(n), snr_dB, slotDur_s);
            if logical(unavailableCSIRSRow.RuntimeEventObserved)
                csirsRows(end+1, 1) = unavailableCSIRSRow; %#ok<AGROW>
            end
            blockErr = blockErr + 1;
            trialStatus(n) = "NA";
            trialCRC(n) = NaN;
            if strlength(strtrim(trialFailureReason(n))) == 0
                trialFailureReason(n) = "dl_receiver_decode_unavailable";
            end
            trialNotes(n) = "PDSCH decode unavailable: " + trialFailureReason(n);
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
        end
        pilotTrack = localPilotTrackingMetrics(rx);
        metrics = localAnalyzeChannelMetrics( ...
            sixgr.util.structGet(rx, "ChannelEstimate", []), ...
            trialNoise(n), cfgFrame, rx, dlPrecoding);
        trialNMSE(n) = metrics.NMSE_dB;
        trialDet(n) = metrics.DetectionMetric;
        if isfinite(trialPostEqSINR(n))
            trialSINR(n) = double(trialPostEqSINR(n));
            trialSINRValueRole(n) = string(trialPostEqSINRValueRole(n));
            trialSINRSource(n) = string(trialPostEqSINRSource(n));
            trialMeasuredTrialSINR(n) = double(trialPostEqSINR(n));
            trialMeasuredSINRSource(n) = string(trialPostEqSINRSource(n));
            trialMeasuredTrialSINRValueRole(n) = string(trialPostEqSINRValueRole(n));
            trialMeasuredTrialSINRValueStatus(n) = string(trialPostEqSINRValueStatus(n));
            trialMeasuredTrialSINRNAReason(n) = string(trialPostEqSINRNAReason(n));
        end
        trialCSIRSRP(n) = metrics.CSI_RSRP_dB;
        trialCSIRSRPSource(n) = string(metrics.CSI_RSRPSource);
        trialCSIRSRPPhysical(n) = metrics.CSI_RSRP_dBm;
        trialCSIRSRPPhysicalSource(n) = string(metrics.CSI_RSRPPhysicalSource);
        trialCSIRSRPPhysicalStatus(n) = string(metrics.CSI_RSRPPhysicalStatus);
        trialCSIRSRPPowerReferencePlane(n) = string(metrics.CSI_RSRPPowerReferencePlane);
        trialCSIRSSI(n) = metrics.CSI_RSSI_dB;
        trialCSIRSSISource(n) = string(metrics.CSI_RSSISource);
        trialCSIRSRQ(n) = metrics.CSI_RSRQ_dB;
        trialCSIRSRQSource(n) = string(metrics.CSI_RSRQSource);
        csirsRow = localBuildCSIRSRuntimeTrialRow(cfgFrame, grantSnapshot, tx, rx, metrics, ...
            frameIdx, trialSlot(n), snr_dB, slotDur_s);
        if logical(csirsRow.RuntimeEventObserved)
            csirsRows(end+1, 1) = csirsRow; %#ok<AGROW>
        end
        receiverCQI = double(sixgr.util.normalizeReportedCQI(metrics.CQI));
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
            [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "DL");
            if isfinite(cqiMCS) && cqiMCS >= 0
                trialCQIDerivedMCS(n) = double(cqiMCS);
                trialCQIDerivedCodeRate(n) = double(cqiRate);
                trialCQIDerivedModulation(n) = string(cqiMod);
            elseif isfinite(grantRawCQIDerivedMCS)
                trialCQIDerivedMCS(n) = double(round(grantRawCQIDerivedMCS));
                profile = sixgr.link.resolveMCSProfile(char(trialMCSTable(n)), trialCQIDerivedMCS(n));
                if isstruct(profile) && isfield(profile, "Valid") && logical(profile.Valid)
                    trialCQIDerivedCodeRate(n) = double(profile.TargetCodeRate);
                    trialCQIDerivedModulation(n) = string(profile.Modulation);
                end
            end
            if ~isfinite(trialCQIDerivedMCS(n))
                [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "DL");
                trialCQIDerivedMCS(n) = double(cqiMCS);
                trialCQIDerivedCodeRate(n) = double(cqiRate);
                trialCQIDerivedModulation(n) = string(cqiMod);
            end
        elseif isfinite(receiverCQI)
            trialCQI(n) = receiverCQI;
            trialCQISource(n) = string(sixgr.util.structGet(metrics, "CQISource", "receiver_csi_feedback"));
            if strlength(strtrim(trialCQISource(n))) == 0
                trialCQISource(n) = "receiver_csi_feedback";
            end
            [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "DL");
            trialCQIDerivedMCS(n) = double(cqiMCS);
            trialCQIDerivedCodeRate(n) = double(cqiRate);
            trialCQIDerivedModulation(n) = string(cqiMod);
        elseif schedulerDrivenGrant && isfinite(grantCQIUsed) && grantCQIUsed > 0
            trialCQI(n) = double(sixgr.util.normalizeReportedCQI(grantCQIUsed));
            trialCQISource(n) = "scheduler_grant_cqi_used_no_current_receiver_cqi";
            [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "DL");
            trialCQIDerivedMCS(n) = double(cqiMCS);
            trialCQIDerivedCodeRate(n) = double(cqiRate);
            trialCQIDerivedModulation(n) = string(cqiMod);
        elseif schedulerDrivenGrant && ~isfinite(trialCQI(n))
            trialCQISource(n) = "current_receiver_cqi_unavailable_no_scheduler_grant_cqi";
            trialCQIDerivedMCS(n) = NaN;
            trialCQIDerivedCodeRate(n) = NaN;
            trialCQIDerivedModulation(n) = "";
        end
        executedRI = localFirstFiniteScalar( ...
            sixgr.util.structGet(grantSnapshot, "RIUsed", NaN), ...
            sixgr.util.structGet(grantSnapshot, "RankIndicator", NaN), ...
            sixgr.util.structGet(grantSnapshot, "RI", NaN), ...
            sixgr.util.structGet(grantSnapshot, "Rank", NaN), ...
            sixgr.util.structGet(grantSnapshot, "NumLayers", NaN), ...
            sixgr.util.structGet(grantSnapshot, "Layers", NaN), ...
            trialLayers(n));
        if schedulerDrivenGrant && isfinite(executedRI) && executedRI >= 1
            trialRI(n) = max(1, round(double(executedRI)));
        else
            trialRI(n) = metrics.RI;
        end
        trialPMI(n) = metrics.PMI;
        trialCRI(n) = metrics.CRI;
        trialPMIType(n) = string(metrics.PMIType);
        trialPMICodebookMode(n) = string(metrics.PMICodebookMode);
        trialCSIReportMode(n) = string(metrics.CSIReportMode);
        trialCSIPayloadBits(n) = metrics.CSIPayloadBitLength;
        trialCSIPayloadHex(n) = string(metrics.CSIPayloadHex);
        trialCSIComputationStatus(n) = string(metrics.CSIComputationStatus);
        trialCSIComputationErrorIdentifier(n) = string(metrics.CSIComputationErrorIdentifier);
        trialCSIMeasurementID(n) = string(metrics.CSIMeasurementID);
        trialCSIMeasurementDigest(n) = string(metrics.CSIMeasurementDigest);
        trialCSIMeasurementProvenance(n) = string(metrics.CSIMeasurementProvenance);
        trialCSIMeasurementSlot(n) = double(metrics.CSIMeasurementSlot);
        trialSubbandCQI(n) = string(metrics.SubbandCQIVector);
        trialSubbandSINR(n) = string(metrics.SubbandSINRVector_dB);
        trialSubbandSizePRB(n) = metrics.SubbandSizePRB;
        trialSubbandCount(n) = metrics.SubbandCount;
        trialWidebandOrSubband(n) = string(metrics.WidebandOrSubband);
        trialSubbandCQISource(n) = string(metrics.SubbandCQISource);
        trialSubbandCQIStatus(n) = string(metrics.SubbandCQIValueStatus);
        trialGain(n) = metrics.ChannelGain_dB;
        trialRank(n) = metrics.RankEstimate;
        trialCond(n) = metrics.ConditionNumber_dB;
        trialConditionNumberStatus(n) = string(metrics.ConditionNumberStatus);
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
        trialDecIt(n) = double(sixgr.util.structGet(coding, "DecoderIterations", NaN));
        trialOfferedBits(n) = double(sixgr.util.structGet(coding, "OfferedBits", NaN));
        if logical(trialHARQIsRetransmission(n))
            % Retransmissions carry a previously offered TB; do not count
            % them as new source traffic in goodput/offered-throughput KPIs.
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
        [modTrack, constT] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfgFrame, "DL");
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
        if isfinite(trialCQI(n)) && ~isfinite(trialCQIDerivedMCS(n))
            [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "DL");
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
            "XOverhead", sixgr.util.structGet(cfgFrame, "phy.pdsch.xOverhead", NaN)));
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
                cfgFrame, "DL", tx, rxWave, rx, constT, diagnosticContext);
        end

        txBits = int8(tx.TransportBlock(:));
        rxBits = int8(rx.TransportBlock(:));
        finalRxBits = rxBits;
        currentRecLLR = sixgr.util.structGet(rx, "RecLLR", []);
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
            if isfield(rx, "ActiveIterations") && ~isempty(rx.ActiveIterations)
                combinedDecodeIt = mean(double(rx.ActiveIterations(:)), "omitnan");
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
            metrics.SINRSource = char(string(trialSINRSource(n)));
            metrics.SINRValueRole = char(string(trialSINRValueRole(n)));
            metrics.SINRValueStatus = char(string(trialMeasuredTrialSINRValueStatus(n)));
            metrics.CRCPass = logical(finalDecodeOK);
            metrics.CurrentDecodeOK = logical(currentDecodeOK);
            metrics.CombinedDecodeOK = logical(finalDecodeOK);
            metrics.AckObserved = logical(finalDecodeOK);
            metrics.DecoderIterations = double(combinedDecodeIt);
            metrics.SourceSlot = double(trialSlot(n));
            metrics.RV = double(trialRV(n));
            metrics.IsRetransmission = false;
            [cfgDyn, laState, laObserveEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "DL", trialSlot(n), ...
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
            rethrow(ME); % A broken stage cannot become a received CRC-failure row.
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
        detail = crashIdentifier + " | " + string(ME.message);
        if ~isempty(crashStack)
            detail = detail + " | stack=" + strjoin(crashStack, " <- ");
        end
        if strlength(firstCrashMsg) == 0
            firstCrashMsg = detail;
        end
        trialCrash(n) = true;
        trialStatus(n) = "CRASH";
        trialCRC(n) = 0;
        trialNotes(n) = detail;
        if ~isempty(log) && frameCrash <= 2
            log.warn("runDLPDSCHThroughput frame failed: " + detail);
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
out.TotalRetxTTIs = double(nnz(trialHARQIsRetransmission));
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
out.DecodeLatency_ms = mean(trialDecodeLatency, "omitnan");
out.EarlyStopRate = mean(trialEarlyStop, "omitnan");
out.DecoderComplexityUnits = mean(trialDecoderComplexity, "omitnan");
out.NormalizedDecoderComplexity = mean(trialNormDecoderComplexity, "omitnan");
out.AreaEfficiencyProxy = mean(trialAreaEfficiency, "omitnan");
out.Ok = frameCrash == 0 && out.BLER < 1;
out.Notes = "Frames=" + string(numFrames) + ", SNR=" + string(snr_dB) + " dB";
out.ConstellationSamples = localBuildConstellationSlice(numFrames);
out.WaveformPreviewTable = localBuildWaveformPreviewSlice(numFrames);
out.SignalDiagnostic = signalDiagnostic;
out.LinkAdaptationState = laState;
out.StartFrameIndex = double(startFrameIndex);
out.StartSlotIndex = double(startSlotIndex);
out.EndFrameIndex = double(trialFrame(max(1, numFrames)));
out.EndSlotIndex = double(trialSlot(max(1, numFrames)));
out.HARQ = lastHARQ;
out.ChannelState = chState;
out.ISACWaveformCapture = isacWaveformCapture;
out.TxWaveformCapture = txWaveformCapture;
out.ObservedREAllocationTable = localCombineObservedREChunks(observedREChunks);
if receivedCompletion
    out.ExecutionStage = "received_shared_stream_completed";
    out.PreparationComputeTime_ms = preparedTransmission.PreparationComputeTime_ms;
out.TransmitWaveformAuthority = "exact_runtime_transmitter_composite_observation";
end

if frameCrash == numFrames
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnsupported", ...
        "Strict mode forbids skipping PDSCH coverage because every frame crashed: " + firstCrashMsg);
    out.Skipped = false;
    out.Ok = false;
    out.BER = NaN;
    out.BLER = NaN;
    out.Throughput_Mbps = NaN;
    out.Notes = "Failed: every DL waveform trial crashed (" + firstCrashMsg + ")";
end

out.TrialTable = localBuildTrialSlice(numFrames);
if receivedCompletion && ~isempty(out.TrialTable)
    powerFields=sixgr.truth.measureReceivedDataCarrierPower( ...
        preparedTransmission,p.Results.ReceivedContext,out.ReceiveTiming);
    for name=string(fieldnames(powerFields)).'
        out.TrialTable.(name)=repmat(powerFields.(name),height(out.TrialTable),1);
    end
end
out.CSIRSTrialTable = localBuildCSIRSTrialTable(csirsRows);
strictTruthRequired = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
out.NoiseDomainValidation = sixgr.phy.rx.validateNoiseDomainEvidence( ...
    out.TrialTable, "ThrowOnFailure", strictTruthRequired, "RequireRows", true);
dlObjective = sixgr.truth.evaluatePDSCHObjectiveStrict(out.TrialTable, cfg, ...
    "RunId", string(sixgr.util.structGet(cfg, "run.runId", sixgr.util.structGet(cfg, "run.runTag", ""))), ...
    "ScenarioName", string(sixgr.util.structGet(cfg, "run.scenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", ""))), ...
    "StrictMode", strictTruthRequired);
out.DLPDSCHObjective = dlObjective;
out.PDSCHObjectiveSummary = dlObjective.Summary;
out.PDSCHObjectiveFailures = dlObjective.Failures;
if strictTruthRequired && ~logical(dlObjective.ObjectivePass)
    out.Ok = false;
    failText = string(dlObjective.Summary.FailureReason(1));
    if strlength(strtrim(failText)) == 0
        failText = "dl_pdsch_objective_failed";
    end
    out.Notes = out.Notes + ", strict DL PDSCH objective failed: " + failText;
end

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
                "Direction", "DL", ...
                "CompletedFrames", double(stopIdx), ...
                "TotalFrames", double(numFrames), ...
                "SNR_dB", double(snr_dB), ...
                "WaveformPreviewTable", localBuildWaveformPreviewSlice(stopIdx));
            feval(liveTrialCallback, trialSlice, constSlice, meta);
        catch ME
            if ~liveCallbackWarned && ~isempty(log)
                log.warn("runDLPDSCHThroughput live publish failed: " + string(ME.message));
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
            repmat("DL", stopIdx, 1), snr_dB * ones(stopIdx,1), trialSFN(idx), trialUEIndex(idx), trialRNTI(idx), trialBaseStationID(idx), trialSeed(idx), trialFrame(idx), trialSlot(idx), ...
            trialMCS(idx), trialPRB(idx), trialLayers(idx), trialModulation(idx), trialCodeRate(idx), trialTB(idx), trialChan(idx), trialDopp(idx), trialCRC(idx), trialDecIt(idx), ...
            trialEVM(idx), trialNMSE(idx), trialDet(idx), trialSINR(idx), trialCQI(idx), trialCQIDerivedMCS(idx), trialCQIDerivedModulation(idx), trialCQIDerivedCodeRate(idx), ...
            trialLinkAdaptationMode(idx), trialActualMCSSelectionMode(idx), trialSchedulerGrantMCSSelectionMode(idx), trialMCSValueStatus(idx), trialCQITable(idx), trialMCSTable(idx), ...
            trialRI(idx), trialPMI(idx), trialCRI(idx), ...
            trialPMIType(idx), trialPMICodebookMode(idx), trialCSIReportMode(idx), trialCSIPayloadBits(idx), trialCSIPayloadHex(idx), ...
            trialSubbandCQI(idx), trialSubbandSINR(idx), trialSubbandSizePRB(idx), trialSubbandCount(idx), trialWidebandOrSubband(idx), trialSubbandCQISource(idx), trialSubbandCQIStatus(idx), ...
            trialGain(idx), trialNoise(idx), trialDesiredSignalPowerBeforeNoise(idx), trialCompositeSignalPowerBeforeNoise(idx), trialAppliedNoiseSNR(idx), trialNoiseVarianceSource(idx), ...
            trialTiming(idx), trialRank(idx), trialCond(idx), trialRxAnt(idx), trialTxPorts(idx), ...
            trialSelectedBeam(idx), trialBestBeam(idx), trialBeamHit(idx), trialTopKBeamHit(idx), trialBeamCount(idx), ...
            trialSelectedBeamGain(idx), trialBestBeamGain(idx), trialBeamGap(idx), ...
            trialCfgPMI(idx), trialCfgCRI(idx), trialBitErr(idx), trialBitTot(idx), ...
            trialOfferedBits(idx), trialGoodBits(idx), trialThroughput(idx), trialOfferedThr(idx), trialGoodput(idx), ...
            trialComputeLatency(idx), trialProcedureDelay(idx), trialAirInterfaceTTI(idx), ...
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
            'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','SubbandCQIVector','SubbandSINRVector_dB','SubbandSizePRB','SubbandCount','WidebandOrSubband','SubbandCQISource','SubbandCQIValueStatus','ChannelGain_dB','NoiseVariance', ...
            'DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
            'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
            'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
            'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
            'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
            'OfferedBits','GoodBits','Throughput_Mbps','OfferedThroughput_Mbps','Goodput_Mbps', ...
            'ComputeLatency_ms','ProcedureDelay_ms','AirInterfaceTTI_ms', ...
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
        % One row represents one scheduled DL TTI.  Persist the exact
        % observation interval used by the already-computed throughput so a
        % CSV-only verifier can independently reproduce Mbps from bits/time.
        % This is allocation timing evidence, not a configured-SNR proxy.
        T.AirInterfaceObservation_ms = T.AirInterfaceTTI_ms;
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
        T.NoiseVarianceAliasOf = repmat("PostEqualizationNoiseVariance", stopIdx, 1);
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
        % DL-SCH transport-block CRC is applicable whenever the real
        % decoder produced a usable TB decision.  Do not let a missing
        % generic default relabel decoded data-channel rows as CRC N/A.
        T.CRCApplicable = logical(trialDLSCHDecodeAttempted(idx) & ...
            trialDLSCHDecodeAvailable(idx) & isfinite(trialCRC(idx)));
        T.TxWaveformColumns = trialTxWaveformColumns(idx);
        T.PhysicalTxAntennas = trialPhysicalTxAntennas(idx);
        T.RxWaveformBranches = trialRxWaveformBranches(idx);
        T.PhysicalRxAntennas = trialPhysicalRxAntennas(idx);
        T.TxWaveformDomain = trialTxWaveformDomain(idx);
        T.HybridElementDomainApplied = trialHybridElementDomainApplied(idx);
        configuredLayers = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.pdsch.nLayers", NaN), ...
            sixgr.util.structGet(cfg, "phy.pdsch.numLayers", NaN), ...
            sixgr.util.structGet(cfg, "pdsch6gr.NumLayers", NaN));
        if isfinite(configuredLayers)
            configuredLayers = max(1, round(double(configuredLayers)));
        end
        configuredTxAnt = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", NaN), ...
            sixgr.util.structGet(cfg, "channel.nTxAnt", NaN), ...
            sixgr.util.structGet(cfg, "phy.nTxAnt", NaN), ...
            trialTxPorts(idx), 1);
        configuredTxAnt = max(1, round(double(configuredTxAnt)));
        configuredRxAnt = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", NaN), ...
            sixgr.util.structGet(cfg, "channel.nRxAnt", NaN), ...
            sixgr.util.structGet(cfg, "phy.nRxAnt", NaN), ...
            trialRxAnt(idx), 1);
        configuredRxAnt = max(1, round(double(configuredRxAnt)));
        T.ConfiguredLayers = repmat(configuredLayers, stopIdx, 1);
        T.ConfiguredTxAntennas = repmat(configuredTxAnt, stopIdx, 1);
        T.ConfiguredRxAntennas = repmat(configuredRxAnt, stopIdx, 1);
        configuredMCS = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.pdsch.mcsIndex", NaN), ...
            sixgr.util.structGet(cfg, "pdsch6gr.MCSIndex", NaN));
        configuredModulation = string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", ...
            sixgr.util.structGet(cfg, "pdsch6gr.Modulation", "")));
        configuredRank = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.pdsch.rank", NaN), ...
            sixgr.util.structGet(cfg, "mimo.rank", NaN), configuredLayers);
        T.ConfiguredMCSIndex = repmat(configuredMCS, stopIdx, 1);
        T.ConfiguredModulation = repmat(configuredModulation, stopIdx, 1);
        T.ConfiguredRank = repmat(configuredRank, stopIdx, 1);
        T.EffectiveMCSIndex = T.MCS;
        T.EffectiveModulation = T.Modulation;
        T.EffectiveLayers = T.Layers;
        T.EffectiveRank = T.Layers;
        T.CSIComputationStatus = trialCSIComputationStatus(idx);
        T.CSIComputationErrorIdentifier = trialCSIComputationErrorIdentifier(idx);
        T.CSIMeasurementID = trialCSIMeasurementID(idx);
        T.CSIMeasurementDigest = trialCSIMeasurementDigest(idx);
        T.CSIMeasurementProvenance = trialCSIMeasurementProvenance(idx);
        T.CSIMeasurementSlot = trialCSIMeasurementSlot(idx);
        T.RankSelectionPolicy = trialRankSelectionPolicy(idx);
        T.RankSelectionSource = trialRankSelectionSource(idx);
        T.RankDecisionReason = trialRankDecisionReason(idx);
        T.RankDowngradeApplied = trialRankDowngradeApplied(idx);
        T.MaxSupportedLayers = trialMaxSupportedLayers(idx);
        T.UEID = T.UEIndex;
        T.RV = trialRV(idx);
        T.HARQProcess = trialHARQProcess(idx);
        T.HARQProcessId = trialHARQProcess(idx);
        T.HarqID = trialHARQProcess(idx);
        T.HARQRound = trialHARQRound(idx);
        T.NDI = trialHARQNDI(idx);
        T.HARQNDI = trialHARQNDI(idx);
        T.IsRetransmission = trialHARQIsRetransmission(idx);
        T.HARQIsRetransmission = trialHARQIsRetransmission(idx);
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
        T.HARQRV = trialRV(idx);
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
        T.ReceiverHestSINR_dB = trialReceiverHestSINR(idx);
        T.ReceiverHestSINRApplicable = logical(isfinite(trialReceiverHestSINR(idx)) & ...
            trialChannelEstimateAvailable(idx) & trialDMRSRECount(idx) > 0);
        T.ReceiverHestSINRSource = trialReceiverHestSINRSource(idx);
        T.ReceiverHestSINRValueRole = trialReceiverHestSINRValueRole(idx);
        T.ReceiverHestSINRValueStatus = trialReceiverHestSINRValueStatus(idx);
        T.ReceiverHestSINRNAReason = trialReceiverHestSINRNAReason(idx);
        T.PostEqSINR_dB = trialPostEqSINR(idx);
        T.PostEqSINRSource = trialPostEqSINRSource(idx);
        T.PostEqSINRValueRole = trialPostEqSINRValueRole(idx);
        T.PostEqSINRValueStatus = trialPostEqSINRValueStatus(idx);
        T.PostEqSINRNAReason = trialPostEqSINRNAReason(idx);
        T.PostEqSINRPerLayer_dB = trialPostEqSINRPerLayer(idx);
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
        T.LargeScaleSINR_dB = trialLargeScaleSINR(idx);
        T.LargeScaleSINRSource = trialLargeScaleSINRSource(idx);
        T.ServingRSRP_dBm = trialServingRSRP(idx);
        T.ServingRSRPSource = trialServingRSRPSource(idx);
        T.CSI_RSRP_dB = trialCSIRSRP(idx);
        T.CSI_RSRPSource = trialCSIRSRPSource(idx);
        T.CSI_RSRP_dBm = trialCSIRSRPPhysical(idx);
        T.CSI_RSRPPhysicalSource = trialCSIRSRPPhysicalSource(idx);
        T.CSI_RSRPPhysicalStatus = trialCSIRSRPPhysicalStatus(idx);
        T.CSI_RSRPPowerReferencePlane = trialCSIRSRPPowerReferencePlane(idx);
        % Keep absolute received power and relative digital-grid power in
        % separate unit-bearing fields.  A relative CSI measurement is not
        % a valid fallback for an unavailable dBm link-budget quantity.
        T.RSRP_dBm = T.ServingRSRP_dBm;
        T.RSRP_dB = T.CSI_RSRP_dB;
        T.CSI_RSSI_dB = trialCSIRSSI(idx);
        T.CSI_RSSISource = trialCSIRSSISource(idx);
        T.CSI_RSRQ_dB = trialCSIRSRQ(idx);
        T.CSI_RSRQSource = trialCSIRSRQSource(idx);
        T.EqualizerType = trialEqualizerType(idx);
        T.EqualizerRequestedType = trialEqualizerRequestedType(idx);
        T.EqualizerEngine = trialEqualizerEngine(idx);
        T.EqualizerCovarianceFactorizationCount = ...
            trialEqualizerCovarianceFactorizationCount(idx);
        T.InterferenceCovarianceAvailable = trialInterferenceCovarianceAvailable(idx);
        T.InterferenceCovarianceSource = trialInterferenceCovarianceSource(idx);
        T.InterferenceCovarianceStatus = trialInterferenceCovarianceStatus(idx);
        T.NoiseVarStatus = trialNoiseVarStatus(idx);
        T.NoiseVarSource = trialNoiseVarSource(idx);
        T.NoiseVarReason = trialNoiseVarReason(idx);
        T.NoiseVarStrictFailure = trialNoiseVarStrictFailure(idx);
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
        T.DLSCHDecodeAttempted = trialDLSCHDecodeAttempted(idx);
        T.DLSCHDecodeAvailable = trialDLSCHDecodeAvailable(idx);
        T.LLRAvailable = trialLLRAvailable(idx);
        T.LLRFinite = trialLLRFinite(idx);
        T.LLRScaleSource = trialLLRScaleSource(idx);
        T.LLRNoiseVariance = trialLLRNoiseVariance(idx);
        T.PostEqSINRWidebanddB = trialPostEqSINR(idx);
        T.PostEqSINRAvailable = trialPostEqSINRAvailable(idx);
        T.PostEqSINRReceiverDerived = trialPostEqSINRReceiverDerived(idx);
        T.SINRValidationStatus = trialSINRValidationStatus(idx);
        T.SINRValidationReason = trialSINRValidationReason(idx);
        T.SINRComputationMethod = trialSINRComputationMethod(idx);
        T.ConfiguredSNRLikeSourceRejected = trialConfiguredSNRLikeSourceRejected(idx);
        T.ConditionNumberStatus = trialConditionNumberStatus(idx);
        T.BeamScoreVector_dB = trialBeamScoreVector(idx);
        T.TopBeamIndexSet = trialTopBeamIndexSet(idx);
        T.TopBeamGainSet_dB = trialTopBeamGainSet(idx);
        T.BeamScoreSource = trialBeamScoreSource(idx);
        T.AppliedLargeScaleGain_dB = trialAppliedLargeScaleGain(idx);
        T.AppliedLargeScaleLoss_dB = trialAppliedLargeScaleLoss(idx);
        T.AppliedBasePathloss_dB = trialAppliedBasePathloss(idx);
        T.AppliedPathloss_dB = trialAppliedPathloss(idx);
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
        T.GrantSource = repmat("scenario_static_grant", stopIdx, 1);
        replayGrantMask = strlength(strtrim(string(T.GrantContextId))) > 0 & ...
            lower(strtrim(string(T.LinkAdaptationMode))) == "scheduler_grant_replay";
        T.GrantSource(replayGrantMask) = "scheduler_grant_replay";
        configuredGrantSource = string(sixgr.util.structGet(cfg, "phy.pdsch.grantSource", ""));
        configuredGrantSource = strtrim(configuredGrantSource);
        if strlength(configuredGrantSource) > 0
            T.GrantSource(:) = configuredGrantSource;
        end
        T.PDCCHGrantReferenceId = strings(stopIdx, 1);
        pdcchGrantMask = logical(T.PDCCHGatingActive) | logical(T.ControlEligible) | ...
            lower(strtrim(string(T.GrantSource))) == "decoded_pdcch";
        T.PDCCHGrantReferenceId(pdcchGrantMask) = string(T.GrantContextId(pdcchGrantMask));
        T.GrantWorkerSafe = trialGrantWorkerSafe(idx);
        T.GrantSharedStateCommitMode = trialGrantSharedStateCommitMode(idx);
        T.ConfiguredBeamSelectionStrategy = trialConfiguredBeamSelectionStrategy(idx);
        T.PrecoderSource = trialPrecoderSource(idx);
        T.PrecodingMode = trialPrecodingMode(idx);
        T.PrecodingApplicationStage = trialPrecodingApplicationStage(idx);
        T.PrecodingActive = trialPrecodingActive(idx);
        T.ExplicitBeamWeightsApplied = trialExplicitBeamWeightsApplied(idx);
        T.TransformPrecodingApplied = trialTransformPrecodingApplied(idx);
        T.BeamformingApplied = trialBeamformingApplied(idx);
        T.AppliedBeamIndexSet = trialAppliedBeamIndexSet(idx);
        T.AppliedPrecoderPMI = trialAppliedPrecoderPMI(idx);
        T.RequestedPrecoderPMI = trialRequestedPrecoderPMI(idx);
        T.RequestedPrecoderSource = trialRequestedPrecoderSource(idx);
        T.AppliedPrecoderPMIType = trialAppliedPrecoderPMIType(idx);
        T.AppliedPrecoderCodebookMode = trialAppliedPrecoderCodebookMode(idx);
        T.PrecodingNumPorts = trialPrecodingNumPorts(idx);
        T.PrecodingNumLayers = trialPrecodingNumLayers(idx);
        T.PrecodingMatrixRows = trialPrecodingMatrixRows(idx);
        T.PrecodingMatrixCols = trialPrecodingMatrixCols(idx);
        T.AppliedPrecoderMatrixSHA256 = trialAppliedPrecoderMatrixSHA256(idx);
        T.RequestedPrecoderSHA256 = trialRequestedPrecoderSHA256(idx);
        T.AppliedPrecoderSHA256 = trialAppliedPrecoderSHA256(idx);
        T.PrecoderDigestDomain = trialPrecoderDigestDomain(idx);
        T.FrozenGrantContextId = trialFrozenGrantContextId(idx);
        T.InterfererBeamformingAppliedCount = trialInterfererBeamformingAppliedCount(idx);
        T.InterfererExplicitBeamWeightCount = trialInterfererExplicitBeamWeightCount(idx);
        T.InterfererTransformPrecodingCount = trialInterfererTransformPrecodingCount(idx);
        T.InterfererPrecoderSourceSet = trialInterfererPrecoderSourceSet(idx);
        T.InterfererPrecodingModeSet = trialInterfererPrecodingModeSet(idx);
        T.InterfererBeamIndexSetSummary = trialInterfererBeamIndexSetSummary(idx);
        T = localApplyRuntimeEvidenceColumns(T, trialRuntimeEvidence(idx));
        T = sixgr.link.appendMeasuredPHYEvidenceColumns(T, trialMeasuredPHYEvidence(idx));
        T = localDecorateTrialTruthFields(T, "DL", cfg);
        T = localDecoratePDSCHExecutionContract(T, executionContract);
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
        carrier,referenceWaveform,occupiedIndices,"SignalFamily","PDSCH");
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

function localAssertDLHybridElementDomainExecution(cfg, tx, txInfo)
hybridRequired = logical(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.hybridBeamformingEnabled", ...
    sixgr.util.structGet(cfg, "mimo.hybrid_beamforming_flag", false)));
if ~hybridRequired
    return;
end
expectedElements = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", NaN), ...
    sixgr.util.structGet(cfg, "antenna.bs.numElements", NaN), ...
    sixgr.util.structGet(cfg, "channel.nTxAnt", NaN), ...
    sixgr.util.structGet(cfg, "phy.nTxAnt", NaN));
actualColumns = double(size(sixgr.util.structGet(tx, "Waveform", []), 2));
declaredPhysical = double(sixgr.util.structGet(tx, ...
    "NPhysicalTxAntennas", NaN));
prec = sixgr.util.structGet(txInfo, "Precoding", struct());
elementDomainApplied = logical(sixgr.util.structGet(prec, ...
    "HybridElementDomainApplied", false));
waveformDomain = lower(strtrim(string(sixgr.util.structGet(prec, ...
    "WaveformDomain", ""))));
if ~(isfinite(expectedElements) && expectedElements >= 1 && ...
        actualColumns == round(expectedElements) && ...
        declaredPhysical == round(expectedElements) && ...
        elementDomainApplied && waveformDomain == "element")
    error("sixgr:link:DLHybridElementDomainExecutionMismatch", ...
        ['Hybrid PDSCH requires %d physical gNB element-domain waveform columns; ' ...
        'the transmitter emitted %d, declared %g physical antennas, domain=%s, applied=%d.'], ...
        round(double(expectedElements)), round(actualColumns), declaredPhysical, ...
        char(waveformDomain), double(elementDomainApplied));
end
end

function signalEnergy = localOccupiedRESignalEnergy(txInfo)
% The native PDSCH mapper emits unit-energy data symbols. Preserve the
% requested grid Es/N0 after the physical transmit-power scale is applied.
signalEnergy = 1;
powerContext = sixgr.util.structGet(txInfo, "PowerContext", struct());
if ~isstruct(powerContext)
    return;
end
netScale = double(sixgr.util.structGet(powerContext, "AmplitudeScale", 1));
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
selectedMask = strlength(requestedBeam) == 0 & isfinite(selectedBeam);
requestedBeam(selectedMask) = string(round(selectedBeam(selectedMask)));
T.RequestedBeamIndexSet = requestedBeam;
% T.PMI is produced by this trial's receiver. It cannot retrospectively
% select the precoder used to generate the already transmitted samples.
[T.RequestedPrecoderPMI,T.RequestedPrecoderSource] = ...
    sixgr.phy.grant.requestedPrecoderColumns(T,upper(string(direction)));
T.AppliedPrecoderSource = string(localOptionalColumn(T, "PrecoderSource", ""));
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
T.FixedAnchorMode = ismember(modeTokens, fixedTokens) & ~ismember(selectionTokens, adaptiveTokens);
T.AdaptiveMode = ismember(modeTokens, adaptiveTokens) | ismember(selectionTokens, adaptiveTokens);
T.CQISource = localResolveCQISourceColumn(T, configuredDomain);
[mcsSelectionSource, mcsValueStatus] = localResolveMCSSelectionEvidenceColumns(T, cfg, direction);
T.MCSSelectionSource = mcsSelectionSource;
T.MCSValueStatus = mcsValueStatus;
% "LinkAdaptationApplied" means that a causal receiver-feedback decision
% selected this grant's operating point.  Merely enabling AMC does not make
% the conservative pre-feedback bootstrap grant an applied LA decision.
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
T = sixgr.link.applyScheduledOperatingPointEvidence(T);
T = sixgr.util.applyLLSRawTrialLifecycle(T);
T.RunUUID = repmat(string(localArtifactStoreField("RunUUID")), n, 1);
T.RunTag = repmat(string(sixgr.util.structGet(cfg, "run.runTag", "")), n, 1);
T.ScenarioID = repmat(string(sixgr.util.structGet(cfg, "run.scenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", ""))), n, 1);
T.RunnerProfile = repmat(string(sixgr.util.structGet(cfg, "run.runnerProfile", "waveform_bundle")), n, 1);
T.ConfigHash = repmat(string(sixgr.util.structGet(cfg, "meta.configHash", "")), n, 1);
T.SourceArtifact = repmat("air_interface/csv/dl_pdsch_trials.csv", n, 1);
T.SourceTable = repmat("air_interface/csv/dl_pdsch_trials.csv", n, 1);
T.ArtifactClass = repmat("raw_runtime_trial_evidence", n, 1);
T.SemanticState = string(T.RowLifecycleState);
T.CountsTowardCoverage = ~logical(localOptionalColumn(T, "Crash", false)) & ~logical(localOptionalColumn(T, "IsWarmupFrame", false));
T.MachineReadable = true(n, 1);
T.HumanReadable = true(n, 1);
end

function row = localBuildCSIRSRuntimeTrialRow(cfg, grantSnapshot, tx, rx, metrics, frameIdx, slotIdx, snr_dB, slotDur_s)
txEvent = sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct());
rxObs = sixgr.util.structGet(rx, "CSIRSObservation", struct());
row = localEmptyCSIRSRuntimeTrialRow();
row.RuntimeEventObserved = logical(sixgr.util.structGet(txEvent, "Scheduled", false)) || ...
    logical(sixgr.util.structGet(txEvent, "Transmitted", false)) || ...
    logical(sixgr.util.structGet(rxObs, "Observed", false));
if ~logical(row.RuntimeEventObserved)
    return;
end
row.Direction = "DL";
row.SignalFamily = "CSI-RS";
row.SNR_dB = double(snr_dB);
row.SFN = double(frameIdx);
row.Frame = double(frameIdx);
row.Slot = double(slotIdx);
row.Time_s = (double(slotIdx) - 1) * double(slotDur_s);
row.CellID = double(sixgr.util.structGet(grantSnapshot, "BaseStationID", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingCell", ...
    localCarrierCellID(sixgr.util.structGet(tx, "Carrier", [])))));
row.BWPID = double(sixgr.util.structGet(cfg, "phy.csirs.bwpID", 0));
row.UEIndex = double(sixgr.util.structGet(grantSnapshot, "UEIndex", NaN));
row.RNTI = double(sixgr.util.structGet(grantSnapshot, "RNTI", sixgr.util.structGet(cfg, "phy.rnti", NaN)));
row.ResourceID = double(sixgr.util.structGet(rxObs, "ResourceID", ...
    sixgr.util.structGet(txEvent, "ResourceID", 0)));
row.ResourceSetID = double(sixgr.util.structGet(txEvent, "ResourceSetID", sixgr.util.structGet(rxObs, "ResourceSetID", 0)));
row.CSIRSType = string(sixgr.util.structGet(txEvent, "CSIRSType", "nzp"));
row.NumPorts = double(sixgr.util.structGet(txEvent, "NumPorts", sixgr.util.structGet(rxObs, "NumPorts", NaN)));
row.RowNumber = double(sixgr.util.structGet(txEvent, "RowNumber", sixgr.util.structGet(rxObs, "RowNumber", NaN)));
row.Density = string(sixgr.util.structGet(txEvent, "Density", ""));
row.Periodicity = string(sixgr.util.structGet(txEvent, "Periodicity", ""));
row.SymbolLocations = string(sixgr.util.structGet(txEvent, "SymbolLocations", ""));
row.SubcarrierLocations = string(sixgr.util.structGet(txEvent, "SubcarrierLocations", ""));
row.RBOffset = double(sixgr.util.structGet(txEvent, "RBOffset", NaN));
row.NumRB = double(sixgr.util.structGet(txEvent, "NumRB", NaN));
row.NRE = double(sixgr.util.structGet(txEvent, "NRE", sixgr.util.structGet(rxObs, "NRE", NaN)));
row.Scheduled = logical(sixgr.util.structGet(txEvent, "Scheduled", false));
row.Transmitted = logical(sixgr.util.structGet(txEvent, "Transmitted", false));
row.Observed = logical(sixgr.util.structGet(rxObs, "Observed", false));
row.Consumer = "";
row.Consumed = false;
row.ResourceExtractionAttempted = logical(sixgr.util.structGet(rxObs, "ResourceExtractionAttempted", false));
row.ResourceExtractionAvailable = logical(sixgr.util.structGet(rxObs, "ResourceExtractionAvailable", false));
row.ChannelEstimationAttempted = logical(sixgr.util.structGet(rxObs, "ChannelEstimationAttempted", false));
row.ChannelEstimateAvailable = logical(sixgr.util.structGet(rxObs, "ChannelEstimateAvailable", false));
row.ChannelEstimateSource = string(sixgr.util.structGet(rxObs, "ChannelEstimateSource", ""));
row.ChannelEstimator = string(sixgr.util.structGet(rxObs, "ChannelEstimator", ""));
row.ChannelInterpolationMethod = string(sixgr.util.structGet(rxObs, "ChannelInterpolationMethod", ""));
row.ChannelEstimateConvention = string(sixgr.util.structGet(rxObs, "ChannelEstimateConvention", ""));
row.ChannelEstimateNoiseVariance = double(sixgr.util.structGet(rxObs, "ChannelEstimateNoiseVariance", NaN));
row.ChannelEstimationLatency_ms = double(sixgr.util.structGet( ...
    rxObs, "ChannelEstimationLatency_ms", NaN));
row.ReceiverPipelineLatency_ms = double(sixgr.util.structGet( ...
    rxObs, "ReceiverPipelineLatency_ms", NaN));
row.ReceiverStageLatencySource = string(sixgr.util.structGet( ...
    rxObs, "ReceiverStageLatencySource", ""));
row.ChannelEstimateCDMType = string(sixgr.util.structGet( ...
    rxObs, "ChannelEstimateCDMType", ""));
row.ChannelEstimateCDMLengths = string(sixgr.util.structGet( ...
    rxObs, "ChannelEstimateCDMLengths", ""));
row.PilotRECount = double(sixgr.util.structGet(rxObs, "PilotRECount", NaN));
row.PilotResidualPower = double(sixgr.util.structGet(rxObs, "PilotResidualPower", NaN));
row.PilotResidualNMSE_dB = double(sixgr.util.structGet(rxObs, "PilotResidualNMSE_dB", NaN));
row.ReferenceMeasuredSINR_dB = double(sixgr.util.structGet( ...
    rxObs, "ReferenceMeasuredSINR_dB", NaN));
row.ReferenceMeasuredSINRSource = string(sixgr.util.structGet( ...
    rxObs, "ReferenceMeasuredSINRSource", ""));
row.ReferenceMeasuredSINRStatus = string(sixgr.util.structGet( ...
    rxObs, "ReferenceMeasuredSINRStatus", "not_attempted"));
row.HestDimensions = string(sixgr.util.structGet(rxObs, "HestDimensions", ""));
row.HestRxPorts = double(sixgr.util.structGet(rxObs, "HestRxPorts", NaN));
row.HestTxPorts = double(sixgr.util.structGet(rxObs, "HestTxPorts", NaN));
row.SINRMeasurementDomain = string(sixgr.util.structGet(rxObs, "SINRMeasurementDomain", ...
    "csi_rs_resource_selective_channel_estimate"));
row.PowerReferencePlane = string(sixgr.util.structGet(rxObs, "PowerReferencePlane", ...
    "normalized_ofdm_resource_grid_after_receiver_synchronization"));
row.CQI = double(sixgr.util.structGet(metrics, "CQI", NaN));
row.RI = double(sixgr.util.structGet(metrics, "RI", NaN));
row.PMI = double(sixgr.util.structGet(metrics, "PMI", NaN));
for field=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    row.(field)=double(sixgr.util.structGet(metrics,field,NaN));
end
row.LI = double(sixgr.util.structGet(metrics, "LI", NaN));
row.CRI = double(sixgr.util.structGet(metrics, "CRI", NaN));
row.CQISource = string(sixgr.util.structGet(metrics, "CQISource", ""));
row.CSIReportMode = string(sixgr.util.structGet(metrics, "CSIReportMode", ""));
row.CSIPayloadBitLength = double(sixgr.util.structGet(metrics, "CSIPayloadBitLength", NaN));
row.CSIPayloadHex = string(sixgr.util.structGet(metrics, "CSIPayloadHex", ""));
row.CSIComputationStatus = string(sixgr.util.structGet(metrics, "CSIComputationStatus", "not_attempted"));
row.CSIComputationErrorIdentifier = string(sixgr.util.structGet(metrics, "CSIComputationErrorIdentifier", ""));
row.CSIMeasurementID = string(sixgr.util.structGet(metrics, "CSIMeasurementID", ...
    sixgr.util.structGet(rxObs, "CSIMeasurementID", "")));
row.CSIMeasurementDigest = string(sixgr.util.structGet(metrics, "CSIMeasurementDigest", ...
    sixgr.util.structGet(rxObs, "CSIMeasurementDigest", "")));
row.CSIMeasurementProvenance = string(sixgr.util.structGet(metrics, "CSIMeasurementProvenance", ...
    sixgr.util.structGet(rxObs, "CSIMeasurementProvenance", "")));
row.CSIMeasurementStateAvailable = logical(sixgr.util.structGet( ...
    rxObs, "CSIMeasurementStateAvailable", false));
row.CSIMeasurementStatus = string(sixgr.util.structGet( ...
    rxObs, "CSIMeasurementStatus", "not_attempted"));
row.CSIMeasurementSlot = double(sixgr.util.structGet(metrics, "CSIMeasurementSlot", ...
    sixgr.util.structGet(rxObs, "CSIMeasurementSlot", NaN)));
row.CSIMeasurementNoiseVariance = double(sixgr.util.structGet(rxObs, ...
    "CSIMeasurementNoiseVariance", NaN));
row.NumConfiguredResources = double(sixgr.util.structGet(rxObs, ...
    "NumConfiguredResources", sixgr.util.structGet(txEvent, "NumResources", NaN)));
row.NumMeasuredResources = double(sixgr.util.structGet(rxObs, ...
    "NumMeasuredResources", NaN));
row.ResourceObjectiveValues = string(sixgr.util.structGet(rxObs, ...
    "ResourceObjectiveValues", ""));
row.CRISelectionSource = string(sixgr.util.structGet(rxObs, ...
    "CRISelectionSource", ""));
row.ConfiguredResourceIDs = string(sixgr.util.structGet(txEvent, ...
    "ResourceIDs", ""));
row.CSIRSPhysicalPortCount = double(sixgr.util.structGet(txEvent, ...
    "PhysicalPortCount", NaN));
row.CSIRSWaveformPortCount = double(sixgr.util.structGet(txEvent, ...
    "WaveformPortCount", NaN));
row.CSIRSPrecoderSource = string(sixgr.util.structGet(txEvent, ...
    "PrecoderSource", ""));
row.CSIRSPrecoderDigests = strjoin(string(sixgr.util.structGet(txEvent, ...
    "PrecoderDigests", strings(0,1))), "|");
row.CSIRSWaveformPrecoderDigests = strjoin(string(sixgr.util.structGet( ...
    txEvent, "WaveformPrecoderDigests", strings(0,1))), "|");
row.CSIRSPortToElementMatrixDigests = strjoin(string(sixgr.util.structGet( ...
    txEvent, "PortToElementMatrixDigests", strings(0,1))), "|");
row.CSIRSPortProjectionSource = string(sixgr.util.structGet(txEvent, ...
    "PortProjectionSource", ""));
row.CSIRSPortProjectionResidualMax = double(sixgr.util.structGet(txEvent, ...
    "PortProjectionResidualMax", NaN));
row.PMIType = string(sixgr.util.structGet(metrics, "PMIType", ""));
row.PMICodebookMode = string(sixgr.util.structGet(metrics, "PMICodebookMode", ""));
row.ConditionNumber_dB = double(sixgr.util.structGet(metrics, ...
    "ConditionNumber_dB", NaN));
row.ConditionNumberStatus = string(sixgr.util.structGet(metrics, ...
    "ConditionNumberStatus", "not_evaluated"));
row.RankEstimate = double(sixgr.util.structGet(metrics, "RankEstimate", NaN));
row.SingularValues = string(sixgr.util.structGet(metrics, "SingularValues", ""));
row.SpatialChannelEstimateConvention = string(sixgr.util.structGet(metrics, ...
    "SpatialChannelEstimateConvention", ""));
row.SpatialChannelSnapshotCount = double(sixgr.util.structGet(metrics, ...
    "SpatialChannelSnapshotCount", NaN));
row.SpatialSignatureToken = string(sixgr.util.structGet(metrics, ...
    "SpatialSignatureToken", ""));
row.SpatialSignatureSHA256 = string(sixgr.util.structGet(metrics, ...
    "SpatialSignatureSHA256", ""));
row.SpatialSignatureSource = string(sixgr.util.structGet(metrics, ...
    "SpatialSignatureSource", ""));
row.SpatialSignatureSourceSlot = double(row.Slot);
row.SpatialSignatureMeasurementDirection = "DL";
row.SpatialSignatureReciprocityMode = "direct_dl_csirs";
row.SpatialSignatureRawRank = double(sixgr.util.structGet(metrics, ...
    "SpatialSignatureRawRank", NaN));
row.SpatialSignatureRetainedRank = double(sixgr.util.structGet(metrics, ...
    "SpatialSignatureRetainedRank", NaN));
row.SpatialSignatureDetectionThreshold = double(sixgr.util.structGet(metrics, ...
    "SpatialSignatureDetectionThreshold", NaN));
row.SpatialSignatureNoiseVariance = double(sixgr.util.structGet(metrics, ...
    "SpatialSignatureNoiseVariance", NaN));
row.SpatialSignatureNoiseMargin_dB = double(sixgr.util.structGet(metrics, ...
    "SpatialSignatureNoiseMargin_dB", NaN));
row.SpatialSignatureSnapshotCount = double(sixgr.util.structGet(metrics, ...
    "SpatialSignatureSnapshotCount", NaN));
row.SpatialSignatureReductionMode = string(sixgr.util.structGet(metrics, ...
    "SpatialSignatureReductionMode", ""));
row.SpatialSignatureDomain = string(sixgr.util.structGet(metrics, ...
    "SpatialSignatureDomain", ""));
row.SpatialSignatureStatus = string(sixgr.util.structGet(metrics, ...
    "SpatialSignatureStatus", "not_attempted"));
row.SINR_dB = double(sixgr.util.structGet(metrics, "SINR_dB", NaN));
row.SINRSource = string(sixgr.util.structGet(metrics, "SINRSource", ""));
row.SINRValueRole = string(sixgr.util.structGet(metrics, "SINRValueRole", ""));
row.SINRValueStatus = string(sixgr.util.structGet(metrics, "SINRValueStatus", ""));
if contains(lower(row.SINRSource), "post_equal") || contains(lower(row.SINRSource), "equalized")
    row.SINRMeasurementDomain = "pdsch_post_equalization_data_re";
elseif contains(lower(row.SINRSource), "csi") || contains(lower(row.SINRSource), "hest")
    row.SINRMeasurementDomain = "csi_rs_resource_selective_channel_estimate";
end
row.MeasurementRSRP_dB = double(sixgr.util.structGet(rxObs, "MeasurementRSRP_dB", NaN));
if ~isfinite(row.MeasurementRSRP_dB)
    row.MeasurementRSRP_dB = double(sixgr.util.structGet(metrics, "CSI_RSRP_dB", NaN));
end
row.MeasurementRelativeRSRP_dB = double(sixgr.util.structGet( ...
    rxObs, "MeasurementRelativeRSRP_dB", row.MeasurementRSRP_dB));
row.MeasurementRelativeSource = string(sixgr.util.structGet( ...
    rxObs, "MeasurementRelativeSource", ""));
row.MeasurementRSRP_dBm = double(sixgr.util.structGet( ...
    rxObs, "MeasurementRSRP_dBm", NaN));
row.MeasurementRSRP_dB_re_UnitOccupiedRE_Es = double( ...
    sixgr.util.structGet(rxObs, ...
    "MeasurementRSRP_dB_re_UnitOccupiedRE_Es", NaN));
txRSMeasurement = sixgr.phy.refsig.measureCSIRSRPFromWaveform( ...
    sixgr.util.structGet(tx, "Carrier", []), ...
    sixgr.util.structGet(tx, "CSIRS", []), ...
    sixgr.util.structGet(tx, "Waveform", []), ...
    "ReferencePlane", "transmit_antenna_connector_post_tx_rf_pre_channel", ...
    "Source", "runDLPDSCHThroughput_exact_runtime_tx_waveform", ...
    "AntennaAggregation", "sum_linear", ...
    "PhysicalIndices", sixgr.util.structGet(tx, ...
        "CSIRSPhysicalIndices", zeros(0, 1)));
row.TxMeasurementRSRP_dBm = double(txRSMeasurement.RSRP_dBm);
row.TxMeasurementRSRPPerAntenna_dBm = string(txRSMeasurement.RSRPPerAntenna_dBm);
row.TxMeasurementAntennaAggregation = string(txRSMeasurement.AntennaAggregation);
row.TxMeasurementPowerReferencePlane = string(txRSMeasurement.ReferencePlane);
row.TxMeasurementSource = string(txRSMeasurement.Source);
row.TxMeasurementStatus = string(txRSMeasurement.Status);
row.TxMeasurementMethod = string(txRSMeasurement.MeasurementMethod);
row.TxMeasurementMappedREPerAntenna = string( ...
    txRSMeasurement.MappedREPerAntenna);
fixedNormalizedEsN0 = strcmpi(string(sixgr.util.structGet( ...
    cfg, "integration.run_mode", "")), "FIXED_SNR_SWEEP") && ...
    logical(sixgr.util.structGet(cfg, ...
    "integration.configured_snr_is_link_authority", false));
row.TxMeasurementRSRP_dB_re_UnitOccupiedRE_Es = NaN;
row.TxMeasurementRSRPPerAntenna_dB_re_UnitOccupiedRE_Es = "";
row.MeasuredReferenceSignalChannelGain_dB = NaN;
if fixedNormalizedEsN0
    row.TxMeasurementRSRP_dB_re_UnitOccupiedRE_Es = ...
        row.TxMeasurementRSRP_dBm;
    row.TxMeasurementRSRPPerAntenna_dB_re_UnitOccupiedRE_Es = ...
        row.TxMeasurementRSRPPerAntenna_dBm;
    if logical(txRSMeasurement.Available) && ...
            isfinite(row.MeasurementRSRP_dB_re_UnitOccupiedRE_Es)
        row.MeasuredReferenceSignalChannelGain_dB = ...
            row.MeasurementRSRP_dB_re_UnitOccupiedRE_Es - ...
            row.TxMeasurementRSRP_dB_re_UnitOccupiedRE_Es;
    end
    row.TxMeasurementRSRP_dBm = NaN;
    row.TxMeasurementRSRPPerAntenna_dBm = "";
    row.TxMeasurementPowerReferencePlane = ...
        "normalized_fixed_esn0_unit_occupied_re_es";
    row.TxMeasurementSource = ...
        "actual_ifft_csirs_epre_relative_to_unit_occupied_re_es";
    row.MeasuredReferenceSignalPathloss_dB = NaN;
    row.MeasuredReferenceSignalPathlossSource = ...
        "unavailable_normalized_fixed_esn0_has_no_absolute_link_budget";
    row.PathlossReferenceRS = "";
elseif logical(txRSMeasurement.Available) && isfinite(row.MeasurementRSRP_dBm)
    row.MeasuredReferenceSignalPathloss_dB = ...
        double(txRSMeasurement.RSRP_dBm) - double(row.MeasurementRSRP_dBm);
    row.MeasuredReferenceSignalPathlossSource = ...
        "exact_tx_csirs_epre_minus_ue_measured_csirs_rsrp";
    row.PathlossReferenceRS = "CSI-RS-resource-" + string(row.ResourceID);
else
    row.MeasuredReferenceSignalPathloss_dB = NaN;
    row.MeasuredReferenceSignalPathlossSource = "";
    row.PathlossReferenceRS = "";
end
row.MeasurementRSRPPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
    rxObs, "MeasurementRSRPPerReceiveAntenna_dBm", ""));
row.MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = string( ...
    sixgr.util.structGet(rxObs, ...
    "MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ""));
for field=["MeasurementRSSI_dBm","MeasurementRSRQ_dB", ...
        "MeasurementRSRQReceiveAntennaIndex1Based", ...
        "MeasurementRSRQNumeratorRSRP_dBm","MeasurementRSRQDenominatorRSSI_dBm", ...
        "MeasurementReceiveAntennaIndex1Based","MeasurementNumRB", ...
        "MeasurementFirstPRB0Based","MeasurementSubcarrierSpacing_kHz","MeasurementBandwidth_Hz"]
    row.(field)=double(sixgr.util.structGet(rxObs,field,NaN));
end
for field=["MeasurementRSSIPerReceiveAntenna_dBm","MeasurementRSRQPerReceiveAntenna_dB", ...
        "MeasurementRSRQAntennaAggregation", ...
        "MeasurementRSSIAntennaAggregation","MeasurementRSSIStatus", ...
        "MeasurementSymbolIndices0Based","MeasurementPhysicalResourcesJSON"]
    row.(field)=string(sixgr.util.structGet(rxObs,field,""));
end
row.MeasurementRSRPPerResource_dBm = string(sixgr.util.structGet( ...
    rxObs, "MeasurementRSRPPerResource_dBm", ""));
for field=["MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"]
    row.(field)=string(sixgr.util.structGet(rxObs,field,""));
end
for field=["MeasurementRSSI_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es"]
    row.(field)=double(sixgr.util.structGet(rxObs,field,NaN));
end
row.MeasurementResourceIDs = string(sixgr.util.structGet( ...
    rxObs, "MeasurementResourceIDs", ""));
row.MeasurementSelectedResourceOrdinal = double(sixgr.util.structGet( ...
    rxObs, "MeasurementSelectedResourceOrdinal", NaN));
row.MeasurementAntennaAggregation = string(sixgr.util.structGet( ...
    rxObs, "MeasurementAntennaAggregation", ""));
row.MeasurementFFTSize = double(sixgr.util.structGet( ...
    rxObs, "MeasurementFFTSize", NaN));
row.MeasurementGridScaleToSqrtW = double(sixgr.util.structGet( ...
    rxObs, "MeasurementGridScaleToSqrtW", NaN));
row.MeasurementReceiverGainCorrection_dB = double(sixgr.util.structGet( ...
    rxObs, "MeasurementReceiverGainCorrection_dB", NaN));
row.MeasurementReceiverGainCorrectionSource = string(sixgr.util.structGet( ...
    rxObs, "MeasurementReceiverGainCorrectionSource", ""));
row.PhysicalMeasurementWaveformStatus = string(sixgr.util.structGet( ...
    rxObs, "PhysicalMeasurementWaveformStatus", "not_attempted"));
row.PhysicalMeasurementWaveformSource = string(sixgr.util.structGet( ...
    rxObs, "PhysicalMeasurementWaveformSource", ""));
row.PhysicalMeasurementStatus = string(sixgr.util.structGet( ...
    rxObs, "PhysicalMeasurementStatus", "not_attempted"));
row.PhysicalMeasurementStandard = string(sixgr.util.structGet( ...
    rxObs, "PhysicalMeasurementStandard", ""));
strictCSI = logical(sixgr.util.structGet(cfg, "phy.mimo.strict", false));
identityOk = ~strictCSI || ( ...
    strlength(strtrim(row.CSIMeasurementID)) > 0 && ...
    strlength(strtrim(row.CSIMeasurementDigest)) > 0 && ...
    startsWith(row.CSIMeasurementProvenance, "measured_"));
row.CSIMeasurementAvailable = row.ChannelEstimateAvailable && ...
    all(isfinite([row.CQI, row.RI, row.PMI, row.CRI])) && ...
    row.CSIComputationStatus == "runtime_measured_csi_complete" && identityOk;
if row.Observed && row.ChannelEstimateAvailable && ...
        (row.CSIMeasurementAvailable || isfinite(row.MeasurementRSRP_dB))
    row.Consumed = true;
    row.Consumer = "dl_csi_cri_ri_pmi_cqi_measurement";
end
row.MeasurementSource = string(sixgr.util.structGet(rxObs, "MeasurementSource", ""));
row.ReportSourceSlot = double(slotIdx);
row.UpdateOutcome = string(sixgr.util.structGet(rxObs, "UpdateOutcome", sixgr.util.structGet(txEvent, "UpdateOutcome", "")));
row.TxRuntimeMaterializationStatus = string(sixgr.util.structGet( ...
    txEvent, "RuntimeMaterializationStatus", ""));
row.RxRuntimeObservationStatus = string(sixgr.util.structGet( ...
    rxObs, "RuntimeMaterializationStatus", ""));
row.RuntimeMaterializationStatus = row.TxRuntimeMaterializationStatus;
if strlength(strtrim(row.RuntimeMaterializationStatus)) == 0
    row.RuntimeMaterializationStatus = row.RxRuntimeObservationStatus;
end
row.RuntimeBlocker = string(sixgr.util.structGet(txEvent, "Blocker", sixgr.util.structGet(rxObs, "Blocker", "")));
row.RuntimeEvidenceSource = string(sixgr.util.structGet(rxObs, "RuntimeEvidenceSource", ...
    sixgr.util.structGet(txEvent, "RuntimeEvidenceSource", "")));
powerContext = sixgr.util.structGet(tx, "PowerContext", struct());
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
row.SourceArtifact = "air_interface/csv/csi_rs_trials.csv";
row.SourceTable = "air_interface/csv/csi_rs_trials.csv";
end

function T = localBuildCSIRSTrialTable(rows)
if isempty(rows)
    T = localEmptyCSIRSTrialTable();
else
    T = struct2table(rows);
end
end

function T = localEmptyCSIRSTrialTable()
T = struct2table(repmat(localEmptyCSIRSRuntimeTrialRow(), 0, 1), "AsArray", true);
end

function row = localEmptyCSIRSRuntimeTrialRow()
row = struct( ...
    "Direction", "", "SignalFamily", "CSI-RS", "SNR_dB", NaN, "SFN", NaN, "Frame", NaN, "Slot", NaN, "Time_s", NaN, ...
    "CellID", NaN, "BWPID", NaN, "UEIndex", NaN, "RNTI", NaN, ...
    "ResourceID", NaN, "ResourceSetID", NaN, "CSIRSType", "", "NumPorts", NaN, "RowNumber", NaN, ...
    "Density", "", "Periodicity", "", "SymbolLocations", "", "SubcarrierLocations", "", "RBOffset", NaN, "NumRB", NaN, "NRE", NaN, ...
    "Scheduled", false, "Transmitted", false, "Observed", false, "Consumed", false, "Consumer", "", ...
    "ResourceExtractionAttempted", false, "ResourceExtractionAvailable", false, ...
    "ChannelEstimationAttempted", false, "ChannelEstimateAvailable", false, ...
    "ChannelEstimateSource", "", "ChannelEstimator", "", "ChannelInterpolationMethod", "", ...
    "ChannelEstimateConvention", "", "ChannelEstimateNoiseVariance", NaN, ...
    "ChannelEstimationLatency_ms", NaN, "ReceiverPipelineLatency_ms", NaN, ...
    "ReceiverStageLatencySource", "", ...
    "ChannelEstimateCDMType", "", "ChannelEstimateCDMLengths", "", ...
    "PilotRECount", NaN, "PilotResidualPower", NaN, "PilotResidualNMSE_dB", NaN, ...
    "ReferenceMeasuredSINR_dB", NaN, "ReferenceMeasuredSINRSource", "", ...
    "ReferenceMeasuredSINRStatus", "not_attempted", ...
    "HestDimensions", "", "HestRxPorts", NaN, "HestTxPorts", NaN, ...
    "CQI", NaN, "RI", NaN, "PMI", NaN, "LI", NaN, "CRI", NaN, "CQISource", "", ...
    "PMI_I11",NaN,"PMI_I12",NaN,"PMI_I13",NaN,"PMI_I2",NaN, ...
    "CSIReportMode", "", "CSIPayloadBitLength", NaN, "CSIPayloadHex", "", ...
    "CSIComputationStatus", "not_attempted", "CSIComputationErrorIdentifier", "", ...
    "CSIMeasurementID", "", "CSIMeasurementDigest", "", ...
    "CSIMeasurementProvenance", "", ...
    "CSIMeasurementStateAvailable", false, ...
    "CSIMeasurementStatus", "not_attempted", ...
    "CSIMeasurementSlot", NaN, ...
    "CSIMeasurementNoiseVariance", NaN, ...
    "NumConfiguredResources", NaN, "NumMeasuredResources", NaN, ...
    "ResourceObjectiveValues", "", "CRISelectionSource", "", ...
    "ConfiguredResourceIDs", "", "CSIRSPhysicalPortCount", NaN, ...
    "CSIRSWaveformPortCount", NaN, ...
    "CSIRSPrecoderSource", "", "CSIRSPrecoderDigests", "", ...
    "CSIRSWaveformPrecoderDigests", "", ...
    "CSIRSPortToElementMatrixDigests", "", ...
    "CSIRSPortProjectionSource", "", ...
    "CSIRSPortProjectionResidualMax", NaN, ...
    "PMIType", "", "PMICodebookMode", "", ...
    "ConditionNumber_dB", NaN, "ConditionNumberStatus", "not_evaluated", ...
    "RankEstimate", NaN, "SingularValues", "", ...
    "SpatialChannelEstimateConvention", "", ...
    "SpatialChannelSnapshotCount", NaN, ...
    "SpatialSignatureToken", "", "SpatialSignatureSHA256", "", ...
    "SpatialSignatureSource", "", "SpatialSignatureSourceSlot", NaN, ...
    "SpatialSignatureMeasurementDirection", "", ...
    "SpatialSignatureReciprocityMode", "", ...
    "SpatialSignatureRawRank", NaN, "SpatialSignatureRetainedRank", NaN, ...
    "SpatialSignatureDetectionThreshold", NaN, ...
    "SpatialSignatureNoiseVariance", NaN, ...
    "SpatialSignatureNoiseMargin_dB", NaN, ...
    "SpatialSignatureSnapshotCount", NaN, ...
    "SpatialSignatureReductionMode", "", ...
    "SpatialSignatureDomain", "", ...
    "SpatialSignatureStatus", "not_attempted", ...
    "SINR_dB", NaN, "SINRSource", "", ...
    "SINRValueRole", "", "SINRValueStatus", "", "SINRMeasurementDomain", "", ...
    "PowerReferencePlane", "", "CSIMeasurementAvailable", false, ...
    "ReportSourceSlot", NaN, "ReportDueSlot", NaN, "ReportDeliveredSlot", NaN, ...
    "ReportProcessed", false, "ReportStatus", "not_enqueued", "ReportIdentity", "", ...
    "MeasurementRSRP_dB", NaN, "MeasurementRelativeRSRP_dB", NaN, ...
    "MeasurementRelativeSource", "", ...
    "MeasurementRSRP_dBm", NaN, ...
    "MeasurementRSRP_dB_re_UnitOccupiedRE_Es", NaN, ...
    "MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", "", ...
    "MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es", "", ...
    "MeasurementRSSI_dBm", NaN, "MeasurementRSRQ_dB", NaN, ...
    "MeasurementRSSI_dB_re_UnitOccupiedRE_Es", NaN, ...
    "MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", "", ...
    "MeasurementRSRQReceiveAntennaIndex1Based", NaN, ...
    "MeasurementRSRQNumeratorRSRP_dBm", NaN, "MeasurementRSRQDenominatorRSSI_dBm", NaN, ...
    "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es", NaN, ...
    "MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es", NaN, ...
    "MeasurementRSRQAntennaAggregation", "", ...
    "MeasurementRSSIPerReceiveAntenna_dBm", "", ...
    "MeasurementRSRQPerReceiveAntenna_dB", "", ...
    "MeasurementReceiveAntennaIndex1Based", NaN, ...
    "MeasurementRSSIAntennaAggregation", "", "MeasurementRSSIStatus", "not_attempted", ...
    "MeasurementNumRB", NaN, "MeasurementFirstPRB0Based", NaN, ...
    "MeasurementSymbolIndices0Based", "", "MeasurementSubcarrierSpacing_kHz", NaN, ...
    "MeasurementBandwidth_Hz", NaN, "MeasurementPhysicalResourcesJSON", "", ...
    "TxMeasurementRSRP_dBm", NaN, ...
    "TxMeasurementRSRPPerAntenna_dBm", "", ...
    "TxMeasurementRSRP_dB_re_UnitOccupiedRE_Es", NaN, ...
    "TxMeasurementRSRPPerAntenna_dB_re_UnitOccupiedRE_Es", "", ...
    "TxMeasurementAntennaAggregation", "", ...
    "TxMeasurementPowerReferencePlane", "", ...
    "TxMeasurementSource", "", "TxMeasurementStatus", "not_attempted", ...
    "TxMeasurementMethod", "", ...
    "TxMeasurementMappedREPerAntenna", "", ...
    "MeasuredReferenceSignalPathloss_dB", NaN, ...
    "MeasuredReferenceSignalPathlossSource", "", ...
    "MeasuredReferenceSignalChannelGain_dB", NaN, ...
    "PathlossReferenceRS", "", ...
    "MeasurementRSRPPerReceiveAntenna_dBm", "", ...
    "MeasurementRSRPPerResource_dBm", "", "MeasurementResourceIDs", "", ...
    "MeasurementSelectedResourceOrdinal", NaN, ...
    "MeasurementAntennaAggregation", "", "MeasurementFFTSize", NaN, ...
    "MeasurementGridScaleToSqrtW", NaN, ...
    "MeasurementReceiverGainCorrection_dB", NaN, ...
    "MeasurementReceiverGainCorrectionSource", "", ...
    "PhysicalMeasurementWaveformStatus", "not_attempted", ...
    "PhysicalMeasurementWaveformSource", "", ...
    "PhysicalMeasurementStatus", "not_attempted", ...
    "PhysicalMeasurementStandard", "", ...
    "PowerNormalizationPolicy", "", "PowerNormalizationSource", "", ...
    "PowerNormalizationGridSource", "", ...
    "PowerNormalizationGridSubcarrierCount", NaN, ...
    "PowerNormalizationGridActiveSymbolCount", NaN, ...
    "PowerNormalizationGridMeanEnergyPerRE", NaN, ...
    "FullBWPActivityFactor", NaN, "ReferenceInputPower_dBm", NaN, ...
    "ReferenceOutputPower_dBm", NaN, "ActualEmittedPower_dBm", NaN, ...
    "ActualEmittedPowerBackoffFromBudget_dB", NaN, ...
    "PowerClosureError_dB", NaN, "PowerConversionEquation", "", ...
    "MeasurementSource", "", "UpdateOutcome", "", ...
    "RuntimeMaterializationStatus", "", "TxRuntimeMaterializationStatus", "", ...
    "RxRuntimeObservationStatus", "", "RuntimeBlocker", "", "RuntimeEvidenceSource", "", ...
    "RuntimeEventObserved", false, "SourceArtifact", "", "SourceTable", "");
end

function cellID = localCarrierCellID(carrier)
cellID = NaN;
if isempty(carrier)
    return;
end
try
    cellID = double(carrier.NCellID);
catch
end
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
appliedMatrixDigest = lower(strtrim(string(localOptionalColumn(T, ...
    "AppliedPrecoderMatrixSHA256", ""))));
precodingMode = lower(strtrim(string(localOptionalColumn(T, "PrecodingMode", ""))));
transformApplied = logical(localOptionalColumn(T, "TransformPrecodingApplied", false)) | precodingMode == "transform_precoding";
explicitBeamWeights = logical(localOptionalColumn(T, "ExplicitBeamWeightsApplied", false));

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
matrixIdentifiedWithoutPMI = upper(string(direction)) == "DL" & ...
    ~appliedPMIMask & explicitBeamWeights & ...
    ~cellfun(@isempty, regexp(cellstr(appliedMatrixDigest), ...
    '^[0-9a-f]{64}$', 'once'));
T.AppliedPrecoderPMIApplicationSource(matrixIdentifiedWithoutPMI) = ...
    "not_applicable_explicit_matrix_identified_by_sha256";
T.AppliedPrecoderPMITruthClassification(matrixIdentifiedWithoutPMI) = ...
    "not_applicable_explicit_matrix_without_scalar_pmi";
matchStatus = strings(n, 1);
for ii = 1:n
    matchStatus(ii) = localRequestedVsAppliedPMIStatus(requestedPMI(ii), appliedPMI(ii));
end
T.RequestedVsAppliedPrecoderPMIMatchStatus = matchStatus;

if upper(string(direction)) ~= "UL"
    return;
end

directMask = ~transformApplied;
missingAppliedBeamMask = ~appliedBeamMask & ~explicitBeamWeights;
missingAppliedPMIMask = ~appliedPMIMask & ~explicitBeamWeights;

beamAppSource = T.AppliedBeamApplicationSource;
pmiAppSource = T.AppliedPrecoderPMIApplicationSource;
beamAppSource(missingAppliedBeamMask & directMask) = "ul_direct_mapping_no_materialized_beam_index_set";
beamAppSource(missingAppliedBeamMask & transformApplied) = "ul_transform_precoding_no_materialized_beam_index_set";
pmiAppSource(missingAppliedPMIMask & directMask) = "ul_direct_mapping_no_materialized_applied_pmi";
pmiAppSource(missingAppliedPMIMask & transformApplied) = "ul_transform_precoding_no_materialized_applied_pmi";
T.AppliedBeamApplicationSource = beamAppSource;
T.AppliedPrecoderPMIApplicationSource = pmiAppSource;
T.AppliedBeamTruthClassification(missingAppliedBeamMask) = "not_materialized_in_active_ul_path";
T.AppliedPrecoderPMITruthClassification(missingAppliedPMIMask) = "not_materialized_in_active_ul_path";
T.BeamformingApplied(missingAppliedBeamMask) = false;
end

function status = localRequestedVsAppliedPMIStatus(requestedPMI, appliedPMI)
requestedFinite = isfinite(double(requestedPMI));
appliedFinite = isfinite(double(appliedPMI));
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
row.RuntimeTraceSource = "runDLPDSCHThroughput_active_trial";
row.AntennaEvidenceSource = "active_runtime_user_context";
row.SameFlowEvidenceSource = string(sixgr.util.structGet(userMeta, ...
    "RuntimeSameFlowEvidenceSource", ...
    "CoupledTruthRuntime.applyUserContextImpl->runDLPDSCHThroughput"));
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
row.AGCEnabled = logical(sixgr.util.structGet(replay, "AGCEnabled", false));
row.AGCApplied = logical(sixgr.util.structGet(replay, "AGCApplied", false));
row.AGCGain_dB = double(sixgr.util.structGet(replay, "AGCGain_dB", NaN));
row.AGCExecutionStatus = string(sixgr.util.structGet(replay, "AGCExecutionStatus", ""));
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
row.ADCClippingRatio = double(sixgr.util.structGet(replay, "ADCClippingRatio", NaN));
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
    "AGCEnabled", false, ...
    "AGCApplied", false, ...
    "AGCGain_dB", NaN, ...
    "AGCExecutionStatus", "", ...
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
    "ADCClippingRatio", NaN, ...
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
numRx = max(1, double(sixgr.util.structGet(cfg, "phy.nRxAnt", ...
    sixgr.util.structGet(cfg, "channel.nRxAnt", runtimeNumTx))));
[txRuntimeAntenna, txRuntimeMeta] = localRuntimeSignalAntennaView(userMeta, ...
    "RuntimeServingBSAntenna", "RuntimeServingBSAntennaMeta", numTx, ...
    "pdsch_runtime_waveform_port_count");
rxRuntimeAntenna = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
rxRuntimeMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
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

function numTx = localResolveRuntimeTxPortCapacity(userMeta, cfg, activePortCount)
activePortCount = max(1, round(double(activePortCount)));
numTx = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumLogicalPorts", []), ...
    sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumLogicalPorts", []), ...
    sixgr.util.structGet(cfg, "phy.maxDLLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.nPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.nPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.NumAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", []), ...
    activePortCount);
if isfinite(numTx) && numTx > localMaxNRLogicalPDSCHPorts()
    numTx = activePortCount;
end
numTx = max(activePortCount, round(double(numTx)));
end

function [ant, meta] = localRuntimeSignalAntennaView(userMeta, antField, metaField, numPorts, sourceToken)
ant = sixgr.util.structGet(userMeta, antField, struct());
meta = sixgr.util.structGet(userMeta, metaField, struct());
if nargin < 4 || ~(isnumeric(numPorts) && isscalar(numPorts) && isfinite(numPorts) && numPorts >= 1)
    return;
end
if nargin < 5 || strlength(strtrim(string(sourceToken))) == 0
    sourceToken = "pdsch_runtime_waveform_port_count";
end
waveformDomain = lower(strtrim(string(sixgr.util.structGet(ant, "WaveformDomain", ...
    sixgr.util.structGet(meta, "WaveformDomain", "")))));
hybridEnabled = logical(sixgr.util.structGet(ant, "HybridBeamformingEnabled", ...
    sixgr.util.structGet(meta, "HybridBeamformingEnabled", false)));
if waveformDomain == "element" || hybridEnabled
    expectedColumns = localFirstFiniteScalar( ...
        sixgr.util.structGet(ant, "NumWaveformColumns", []), ...
        sixgr.util.structGet(meta, "NumWaveformColumns", []), ...
        sixgr.util.structGet(ant, "NumElements", []), ...
        sixgr.util.structGet(meta, "NumElements", []));
    if ~(isfinite(expectedColumns) && round(double(expectedColumns)) == round(double(numPorts)))
        error("sixgr:link:DLHybridRuntimeWaveformColumnMismatch", ...
            ['PDSCH emitted %d waveform column(s), but the runtime hybrid gNB ' ...
            'architecture requires %d element-domain column(s).'], ...
            round(double(numPorts)), round(double(expectedColumns)));
    end
    meta.NumWaveformColumns = double(expectedColumns);
    meta.WaveformDomain = "element";
    meta.HybridBeamformingEnabled = true;
    meta.RuntimeObjectSource = "AntennaArrayFactory.element_domain_runtime_view";
    return;
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
numRx = max(1, double(sixgr.util.structGet(cfg, "phy.nRxAnt", numTx)));
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
[txRuntimeAntenna, txRuntimeMeta] = localRuntimeSignalAntennaView(userMeta, ...
    "RuntimeServingBSAntenna", "RuntimeServingBSAntennaMeta", numTx, ...
    "pdsch_runtime_waveform_port_count");
rxRuntimeAntenna = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
rxRuntimeMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());

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

function [y, replay, state, physicalMeasurementWaveform] = localApplyChannelAndAwgn(x, snr_dB, state, cfg, tx, txInfo, interferenceBundle, captureDiagnosticPathGains)
if nargin < 8
    captureDiagnosticPathGains = false;
end
physicalMeasurementWaveform = complex(zeros(0, size(x, 2), "like", x));
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
        % Omitting the optional override preserves ChannelFactory's bounded
        % first-executed-waveform capture policy. Passing false here used to
        % disable primary fading provenance whenever the richer diagnostic
        % snapshot was not requested.
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
replay = localAttachPDSCHBoundaryDiagnostics(replay, tx, desiredWaveform, cfg);
[interferenceWaveform, interferenceMeta] = sixgr.link.synthesizeInterferenceWaveform("DL", desiredWaveform, replay, interferenceBundle);
interferenceWaveformVariance = NaN;
if ~isempty(interferenceWaveform)
    interferenceWaveformVariance = localUsefulOFDMReferencePower(interferenceWaveform, txInfo);
    y = y + cast(interferenceWaveform, "like", y);
end
localLogPDSCHCompositeStageDiagnostics(cfg, tx, interferenceWaveform, y, "pre_noise_composite");
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
    sixgr.util.structGet(tx, "PDSCHIndices", []));
localLogPDSCHCompositeStageDiagnostics(cfg, tx, [], y, "post_noise_pre_front_end");
noiseFields = fieldnames(noiseInfo);
for ni = 1:numel(noiseFields)
    replay.(noiseFields{ni}) = noiseInfo.(noiseFields{ni});
end
% Preserve the exact antenna-connector waveform after propagation,
% interference superposition and receiver noise, but before AGC, ADC and
% the remaining receiver RF stages.  Absolute CSI-RSRP is measured from
% this waveform while decoding continues on the post-front-end waveform.
% Keeping both planes avoids attempting to invert nonlinear/clipped RF
% stages and prevents post-AGC digital power from being mislabeled dBm.
physicalMeasurementWaveform = y;
replay.PhysicalMeasurementWaveformAvailable = ~isempty(physicalMeasurementWaveform);
replay.PhysicalMeasurementReferencePlane = ...
    "receiver_antenna_connector_pre_composite_front_end";
replay.PhysicalMeasurementWaveformSource = ...
    "post_channel_interference_noise_pre_rx_rf_adc";
[y, replay] = sixgr.link.applyCompositeReceiverFrontEnd(y, cfgReplay, sampleRateHz, replay, ...
    "Direction", "DL");
replay = sixgr.link.applyCompositeFrontEndVarianceReplay(replay);
localLogPDSCHCompositeStageDiagnostics(cfg, tx, [], y, "post_front_end_composite");
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
end

function replay = localAttachPDSCHBoundaryDiagnostics(replay, tx, desiredWaveform, cfg)
diag = localPDSCHBoundaryDiagnostics(tx, desiredWaveform);
names = fieldnames(diag);
for ii = 1:numel(names)
    replay.(names{ii}) = diag.(names{ii});
end
if nargin < 4
    cfg = struct();
end
localDLStageProgressLog(cfg, ...
    "stage=pdsch_boundary_diag tx_data_power=%g tx_dmrs_power=%g desired_data_power=%g desired_dmrs_power=%g desired_dmrs_finite=%g", ...
    double(diag.TxPDSCHDataGridPower), ...
    double(diag.TxPDSCHDMRSGridPower), ...
    double(diag.DesiredOnlyPDSCHDataResourcePower), ...
    double(diag.DesiredOnlyPDSCHDMRSResourcePower), ...
    double(diag.DesiredOnlyPDSCHDMRSFiniteFraction));
end

function localLogPDSCHCompositeStageDiagnostics(cfg, tx, interferenceWaveform, compositeWaveform, stage)
if nargin < 1
    cfg = struct();
end
stage = char(string(stage));
intDiag = localPDSCHWaveformResourceDiagnostics(tx, interferenceWaveform);
compDiag = localPDSCHWaveformResourceDiagnostics(tx, compositeWaveform);
localDLStageProgressLog(cfg, ...
    "stage=pdsch_composite_diag point=%s int_data_power=%g int_dmrs_power=%g comp_data_power=%g comp_dmrs_power=%g comp_dmrs_finite=%g", ...
    stage, ...
    double(intDiag.PDSCHDataResourcePower), ...
    double(intDiag.PDSCHDMRSResourcePower), ...
    double(compDiag.PDSCHDataResourcePower), ...
    double(compDiag.PDSCHDMRSResourcePower), ...
    double(compDiag.PDSCHDMRSFiniteFraction));
end

function diag = localPDSCHWaveformResourceDiagnostics(tx, waveform)
diag = struct( ...
    "PDSCHDataResourcePower", NaN, ...
    "PDSCHDMRSResourcePower", NaN, ...
    "PDSCHDMRSFiniteFraction", NaN);
if nargin < 2 || isempty(waveform) || nargin < 1 || ~isstruct(tx)
    return;
end
try
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if isempty(carrier)
        return;
    end
    grid = sixgr.phy.waveform.ofdmDemodulate(carrier, waveform);
    dataInd = sixgr.util.structGet(tx, "PDSCHIndices", sixgr.util.structGet(tx, "PDSCHAntennaIndices", []));
    dmrsInd = sixgr.util.structGet(tx, "DMRSIndices", sixgr.util.structGet(tx, "DMRSAntennaIndices", []));
    diag.PDSCHDataResourcePower = localMeanExtractedResourcePower(grid, dataInd);
    diag.PDSCHDMRSResourcePower = localMeanExtractedResourcePower(grid, dmrsInd);
    diag.PDSCHDMRSFiniteFraction = localFiniteExtractedResourceFraction(grid, dmrsInd);
catch ME
    csiReportingRequired = logical(sixgr.util.structGet(cfg, "phy.csi.reportCSI", false)) || ...
        logical(sixgr.util.structGet(cfg, "phy.csi.reportCQI", false)) || ...
        logical(sixgr.util.structGet(cfg, "phy.csi.reportPMI", false)) || ...
        logical(sixgr.util.structGet(cfg, "phy.csi.reportRI", false)) || ...
        logical(sixgr.util.structGet(cfg, "phy.csi.reportCRI", false));
    if csiReportingRequired && csiChannelSource == "csirs_resource_selective_channel_estimate"
        failure = MException("sixgr:link:CSIRuntimeMeasurementFailed", ...
            "Runtime CSI feedback failed after CSI-RS channel estimation: %s | %s", ...
            string(ME.identifier), string(ME.message));
        failure = addCause(failure, ME);
        throwAsCaller(failure);
    end
end
end

function diag = localPDSCHBoundaryDiagnostics(tx, desiredWaveform)
diag = struct( ...
    "TxPDSCHDataGridPower", NaN, ...
    "TxPDSCHDMRSGridPower", NaN, ...
    "TxPDSCHDMRSAntennaSymbolPower", NaN, ...
    "TxPDSCHDMRSLayerSymbolPower", NaN, ...
    "TxPDSCHDataIndexCount", NaN, ...
    "TxPDSCHDMRSIndexCount", NaN, ...
    "DesiredOnlyPDSCHDataResourcePower", NaN, ...
    "DesiredOnlyPDSCHDMRSResourcePower", NaN, ...
    "DesiredOnlyPDSCHDMRSFiniteFraction", NaN);
if nargin < 1 || ~isstruct(tx)
    return;
end
grid = sixgr.util.structGet(tx, "Grid", []);
dataInd = sixgr.util.structGet(tx, "PDSCHAntennaIndices", sixgr.util.structGet(tx, "PDSCHIndices", []));
dmrsAntInd = sixgr.util.structGet(tx, "DMRSAntennaIndices", sixgr.util.structGet(tx, "DMRSIndices", []));
dmrsLayerInd = sixgr.util.structGet(tx, "DMRSIndices", dmrsAntInd);
diag.TxPDSCHDataIndexCount = double(numel(dataInd));
diag.TxPDSCHDMRSIndexCount = double(numel(dmrsAntInd));
diag.TxPDSCHDataGridPower = localMeanIndexedResourcePower(grid, dataInd);
diag.TxPDSCHDMRSGridPower = localMeanIndexedResourcePower(grid, dmrsAntInd);
diag.TxPDSCHDMRSAntennaSymbolPower = localMeanComplexPowerLocal(sixgr.util.structGet(tx, "DMRSAntennaSymbols", []));
diag.TxPDSCHDMRSLayerSymbolPower = localMeanComplexPowerLocal(sixgr.util.structGet(tx, "DMRSSymbols", []));
if nargin < 2 || isempty(desiredWaveform)
    return;
end
try
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if isempty(carrier)
        return;
    end
    desiredGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, desiredWaveform);
    diag.DesiredOnlyPDSCHDataResourcePower = localMeanExtractedResourcePower(desiredGrid, sixgr.util.structGet(tx, "PDSCHIndices", dataInd));
    diag.DesiredOnlyPDSCHDMRSResourcePower = localMeanExtractedResourcePower(desiredGrid, dmrsLayerInd);
    diag.DesiredOnlyPDSCHDMRSFiniteFraction = localFiniteExtractedResourceFraction(desiredGrid, dmrsLayerInd);
catch
end
end

function p = localMeanIndexedResourcePower(grid, ind)
p = NaN;
if isempty(grid) || isempty(ind)
    return;
end
try
    values = grid(ind(:));
    p = localMeanComplexPowerLocal(values);
catch
end
end

function p = localMeanExtractedResourcePower(grid, ind)
p = NaN;
if isempty(grid) || isempty(ind)
    return;
end
try
    values = nrExtractResources(ind, grid);
    p = localMeanComplexPowerLocal(values);
catch
end
end

function f = localFiniteExtractedResourceFraction(grid, ind)
f = NaN;
if isempty(grid) || isempty(ind)
    return;
end
try
    values = nrExtractResources(ind, grid);
catch
    return;
end
v = values(:);
if isempty(v)
    return;
end
f = double(mean(isfinite(real(v)) & isfinite(imag(v))));
end

function p = localMeanComplexPowerLocal(x)
p = NaN;
if isempty(x) || ~isnumeric(x)
    return;
end
v = x(:);
mask = isfinite(real(v)) & isfinite(imag(v));
if ~any(mask)
    return;
end
p = double(mean(abs(double(v(mask))).^2, "omitnan"));
end

function replay = localFinalizeImpairmentReplay(replay, cfg, rx, tx, txInfo, useIdealTimingSync)
if nargin < 1 || ~isstruct(replay)
    replay = struct();
end
replay.SampleRate_Hz = localResolveSampleRate(tx, txInfo);
replay.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", localResolveInjectedCFOHz(cfg)));
replay.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", localResolveInjectedTimingOffsetSamples(cfg)));
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
    if isfinite(replay.InjectedTimingOffset_samples)
        replay.ResidualTimingError_PostCorrection_samples = double(replay.InjectedTimingOffset_samples);
    else
        replay.ResidualTimingError_PostCorrection_samples = NaN;
    end
    replay = localApplyReceiverSynchronizationReplay(replay, syncState, rx);
    return;
end
replay.TimingEstimateUsed = true;
replay.EstimatedTimingOffset_PreCorrection_samples = rawTimingEstimate;
if isfinite(replay.InjectedTimingOffset_samples)
    replay.ResidualTimingError_PostCorrection_samples = double(replay.InjectedTimingOffset_samples) - appliedTimingCorrection;
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
measurement = struct( ...
    "CompositeReceiverFrontEndApplied", logical(sixgr.util.structGet( ...
        replay, "CompositeReceiverFrontEndApplied", false)), ...
    "CompositeReceiverFrontEndStatus", string(sixgr.util.structGet( ...
        replay, "CompositeReceiverFrontEndStatus", "")), ...
    "AGCEnabled", logical(sixgr.util.structGet(replay, "AGCEnabled", false)), ...
    "AGCApplied", logical(sixgr.util.structGet(replay, "AGCApplied", false)), ...
    "AGCGain_dB", double(sixgr.util.structGet(replay, "AGCGain_dB", NaN)), ...
    "AGCExecutionStatus", string(sixgr.util.structGet( ...
        replay, "AGCExecutionStatus", "")), ...
    "ADCQuantizationApplied", logical(sixgr.util.structGet( ...
        replay, "ADCQuantizationApplied", false)), ...
    "ADCClippingRatio", double(sixgr.util.structGet( ...
        replay, "ADCClippingRatio", NaN)), ...
    "PhysicalMeasurementWaveformAvailable", logical(sixgr.util.structGet( ...
        replay, "PhysicalMeasurementWaveformAvailable", false)), ...
    "PhysicalMeasurementReferencePlane", string(sixgr.util.structGet( ...
        replay, "PhysicalMeasurementReferencePlane", "")), ...
    "PhysicalMeasurementWaveformSource", string(sixgr.util.structGet( ...
        replay, "PhysicalMeasurementWaveformSource", "")));
cfg = sixgr.util.structSet(cfg, "lls6g.receiverMeasurement", measurement);
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
% Pad for the full channel memory so we retain late multipath energy, but
% only pre-trim the implementation filter delay. The physical path delay
% must remain visible to timing/channel estimation on fading channels.
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function slotDur_s = localSlotDuration(cfg)
slotDur_s = sixgr.time.slotDurationSec(cfg);
end

function T = localEmptyTrialTable()
varNames = {'Direction','SNR_dB','SFN','UEIndex','RNTI','BaseStationID','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'MeasuredSINR_dB','WidebandCQI','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
    'LinkAdaptationMode','ActualMCSSelectionMode','CQITable','MCSTable','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
    'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','SubbandCQIVector','SubbandSINRVector_dB','SubbandSizePRB','SubbandCount','WidebandOrSubband','SubbandCQISource','SubbandCQIValueStatus','ChannelGain_dB','NoiseVariance', ...
    'DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
    'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
    'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
    'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
    'BeamScoreVector_dB','TopBeamIndexSet','TopBeamGainSet_dB','BeamScoreSource', ...
    'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
    'OfferedBits','GoodBits','Throughput_Mbps','OfferedThroughput_Mbps','Goodput_Mbps', ...
    'ComputeLatency_ms','ProcedureDelay_ms','AirInterfaceTTI_ms', ...
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
    'string','double','string','string','string','double','double','string','string','string','double','double', ...
    'double','double','double','string', ...
    'double','double','double','double','double', ...
    'double','double','double','double','double','double','double','double', ...
    'string','string','string','string', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double', ...
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
    'sixgr:link:DLTrialSchemaTypeCountMismatch');
T = table('Size', [0, numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
T.ConditionNumberStatus = strings(0,1);
T.ComputeLatencySource = strings(0,1);
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
T.ConfiguredSNR_dB = zeros(0,1);
T.CRCApplicable = false(0,1);
T.TxWaveformColumns = zeros(0,1);
T.PhysicalTxAntennas = zeros(0,1);
T.TxWaveformDomain = strings(0,1);
T.HybridElementDomainApplied = false(0,1);
T.ConfiguredLayers = zeros(0,1);
T.ConfiguredTxAntennas = zeros(0,1);
T.ConfiguredRxAntennas = zeros(0,1);
T.ConfiguredMCSIndex = zeros(0,1);
T.ConfiguredModulation = strings(0,1);
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
T.ConfiguredRank = zeros(0,1);
T.EffectiveMCSIndex = zeros(0,1);
T.EffectiveModulation = strings(0,1);
T.EffectiveLayers = zeros(0,1);
T.EffectiveRank = zeros(0,1);
T.RankSelectionPolicy = strings(0,1);
T.RankSelectionSource = strings(0,1);
T.RankDecisionReason = strings(0,1);
T.RankDowngradeApplied = false(0,1);
T.MaxSupportedLayers = zeros(0,1);
T.UEID = zeros(0,1);
T.RV = zeros(0,1);
T.HARQProcess = zeros(0,1);
T.HARQProcessId = zeros(0,1);
T.HarqID = zeros(0,1);
T.HARQRound = zeros(0,1);
T.NDI = zeros(0,1);
T.HARQNDI = zeros(0,1);
T.IsRetransmission = false(0,1);
T.HARQIsRetransmission = false(0,1);
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
T.HARQRV = zeros(0,1);
T.AppliedAWGNSNR_dB = zeros(0,1);
T.ReceiverHestSINR_dB = zeros(0,1);
T.ReceiverHestSINRApplicable = false(0,1);
T.ReceiverHestSINRSource = strings(0,1);
T.ReceiverHestSINRValueRole = strings(0,1);
T.ReceiverHestSINRValueStatus = strings(0,1);
T.ReceiverHestSINRNAReason = strings(0,1);
T.PostEqSINR_dB = zeros(0,1);
T.PostEqSINRSource = strings(0,1);
T.PostEqSINRValueRole = strings(0,1);
T.PostEqSINRValueStatus = strings(0,1);
T.PostEqSINRNAReason = strings(0,1);
T.PostEqSINRPerLayer_dB = strings(0,1);
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
T.CSI_RSRP_dB = zeros(0,1);
T.CSI_RSRPSource = strings(0,1);
T.CSI_RSRP_dBm = zeros(0,1);
T.CSI_RSRPPhysicalSource = strings(0,1);
T.CSI_RSRPPhysicalStatus = strings(0,1);
T.CSI_RSRPPowerReferencePlane = strings(0,1);
T.RSRP_dBm = zeros(0,1);
T.RSRP_dB = zeros(0,1);
T.CSI_RSSI_dB = zeros(0,1);
T.CSI_RSSISource = strings(0,1);
T.CSI_RSRQ_dB = zeros(0,1);
T.CSI_RSRQSource = strings(0,1);
T.CSIComputationStatus = strings(0,1);
T.CSIComputationErrorIdentifier = strings(0,1);
T.CSIMeasurementID = strings(0,1);
T.CSIMeasurementDigest = strings(0,1);
T.CSIMeasurementProvenance = strings(0,1);
T.CSIMeasurementSlot = zeros(0,1);
T.EqualizerType = strings(0,1);
T.EqualizerRequestedType = strings(0,1);
T.EqualizerEngine = strings(0,1);
T.EqualizerCovarianceFactorizationCount = zeros(0,1);
T.InterferenceCovarianceAvailable = false(0,1);
T.InterferenceCovarianceSource = strings(0,1);
T.InterferenceCovarianceStatus = strings(0,1);
T.NoiseVarStatus = strings(0,1);
T.NoiseVarSource = strings(0,1);
T.NoiseVarReason = strings(0,1);
T.NoiseVarStrictFailure = false(0,1);
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
T.DLSCHDecodeAttempted = false(0,1);
T.DLSCHDecodeAvailable = false(0,1);
T.LLRAvailable = false(0,1);
T.LLRFinite = false(0,1);
T.LLRScaleSource = strings(0,1);
T.LLRNoiseVariance = zeros(0,1);
T.PostEqSINRWidebanddB = zeros(0,1);
T.PostEqSINRAvailable = false(0,1);
T.PostEqSINRReceiverDerived = false(0,1);
T.SINRValidationStatus = strings(0,1);
T.SINRValidationReason = strings(0,1);
T.SINRComputationMethod = strings(0,1);
T.ConfiguredSNRLikeSourceRejected = false(0,1);
T.AppliedLargeScaleGain_dB = zeros(0,1);
T.AppliedLargeScaleLoss_dB = zeros(0,1);
T.AppliedBasePathloss_dB = zeros(0,1);
T.AppliedPathloss_dB = zeros(0,1);
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
T.GrantSource = strings(0,1);
T.PDCCHGrantReferenceId = strings(0,1);
T.GrantWorkerSafe = false(0,1);
T.GrantSharedStateCommitMode = strings(0,1);
T.ConfiguredBeamSelectionStrategy = strings(0,1);
T.PrecoderSource = strings(0,1);
T.PrecodingMode = strings(0,1);
T.PrecodingApplicationStage = strings(0,1);
T.PrecodingActive = false(0,1);
T.ExplicitBeamWeightsApplied = false(0,1);
T.TransformPrecodingApplied = false(0,1);
T.BeamformingApplied = false(0,1);
T.AppliedBeamIndexSet = strings(0,1);
T.AppliedPrecoderPMI = zeros(0,1);
T.AppliedPrecoderPMIType = strings(0,1);
T.AppliedPrecoderCodebookMode = strings(0,1);
T.RequestedBeamTruthClassification = strings(0,1);
T.RequestedPrecoderPMITruthClassification = strings(0,1);
T.AppliedBeamApplicationSource = strings(0,1);
T.AppliedBeamTruthClassification = strings(0,1);
T.AppliedPrecoderPMIApplicationSource = strings(0,1);
T.AppliedPrecoderPMITruthClassification = strings(0,1);
T.RequestedVsAppliedPrecoderPMIMatchStatus = strings(0,1);
T.PrecodingNumPorts = zeros(0,1);
T.PrecodingNumLayers = zeros(0,1);
T.PrecodingMatrixRows = zeros(0,1);
T.PrecodingMatrixCols = zeros(0,1);
T.AppliedPrecoderMatrixSHA256 = strings(0,1);
T.RequestedPrecoderSHA256 = strings(0,1);
T.AppliedPrecoderSHA256 = strings(0,1);
T.PrecoderDigestDomain = strings(0,1);
T.FrozenGrantContextId = strings(0,1);
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

function trace = localResolveDLPrecodingTrace(cfg, tx, grant)
if nargin < 3 || ~isstruct(grant)
    grant = struct();
end
prec = sixgr.util.structGet(tx, "PrecodeInfo", struct());
frozen = sixgr.util.structGet(grant,"PHYGrant.PrecodingState", ...
    sixgr.util.structGet(grant,"PrecodingState",struct()));
requestPMI = double(sixgr.util.structGet(frozen,"PMI",NaN));
requestSource = "";
if isfield(frozen,'PMI')
    % An explicit-matrix grant can legitimately have no scalar PMI.
    requestSource = "frozen_PHYGrant_precoding_state";
end
digestEvidence = sixgr.phy.grant.resolvePrecoderDigestEvidence(grant, prec);
trace = struct( ...
    "RequestedPrecoderPMI", requestPMI, "RequestedPrecoderSource", requestSource, ...
    "ConfiguredBeamSelectionStrategy", string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")), ...
    "PrecoderSource", string(sixgr.util.structGet(prec, "Source", sixgr.util.structGet(grant, "PrecoderSource", "none"))), ...
    "PrecodingMode", string(sixgr.util.structGet(prec, "Mode", sixgr.util.structGet(grant, "PrecodingMode", "siso-bypass"))), ...
    "PrecodingApplicationStage", string(sixgr.util.structGet(prec, "ApplicationStage", sixgr.util.structGet(grant, "PrecodingApplicationStage", "none"))), ...
    "PrecodingActive", logical(sixgr.util.structGet(prec, "Active", sixgr.util.structGet(grant, "PrecodingActive", false))), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(prec, "Active", sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false))), ...
    "TransformPrecodingApplied", false, ...
    "BeamformingApplied", logical(sixgr.util.structGet(prec, "Active", sixgr.util.structGet(grant, "BeamformingApplied", false))), ...
    "AppliedBeamIndexSet", localFormatIndexSet(sixgr.util.structGet(prec, "BeamIndices", sixgr.util.structGet(grant, "AppliedBeamIndexSet", []))), ...
    "AppliedPrecoderPMI", double(sixgr.util.structGet(prec, "PMI", sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN))), ...
    "AppliedPrecoderPMIType", string(sixgr.util.structGet(prec, "PMIType", sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""))), ...
    "AppliedPrecoderCodebookMode", string(sixgr.util.structGet(prec, "CodebookMode", sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""))), ...
    "PrecodingNumPorts", double(sixgr.util.structGet(prec, "NumPorts", sixgr.util.structGet(grant, "PrecodingNumPorts", NaN))), ...
    "PrecodingNumLayers", double(sixgr.util.structGet(prec, "NumLayers", sixgr.util.structGet(grant, "PrecodingNumLayers", NaN))), ...
    "PrecodingMatrixRows", double(sixgr.util.structGet(prec, "MatrixRows", sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN))), ...
    "PrecodingMatrixCols", double(sixgr.util.structGet(prec, "MatrixCols", sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN))), ...
    "AppliedPrecoderMatrixSHA256", string(digestEvidence.AppliedPrecoderMatrixSHA256), ...
    "RequestedPrecoderSHA256", string(digestEvidence.RequestedPrecoderSHA256), ...
    "AppliedPrecoderSHA256", string(digestEvidence.AppliedPrecoderSHA256), ...
    "PrecoderDigestDomain", string(digestEvidence.PrecoderDigestDomain), ...
    "FrozenGrantContextId", string(digestEvidence.FrozenGrantContextId));
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

function metrics = localAnalyzeChannelMetrics(Hest, nVar, cfg, rx, appliedPrecoding)
if nargin < 4
    rx = struct();
end

if nargin < 5 || ~isstruct(appliedPrecoding)
    appliedPrecoding = struct();
end
metrics = struct( ...
    "NMSE_dB", NaN, ...
    "DetectionMetric", NaN, ...
    "SINR_dB", NaN, ...
    "SINRSource", "", ...
    "CQI", NaN, ...
    "CQISource", "", ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "LI", NaN, ...
    "PMI_I11",NaN,"PMI_I12",NaN,"PMI_I13",NaN,"PMI_I2",NaN, ...
    "CRI", NaN, ...
    "PMIType", "", ...
    "PMICodebookMode", "", ...
    "CSIReportMode", "", ...
    "CSIPayloadBitLength", NaN, ...
    "CSIPayloadHex", "", ...
    "CSIComputationStatus", "not_attempted", ...
    "CSIComputationErrorIdentifier", "", ...
    "CSIComputationErrorMessage", "", ...
    "CSIMeasurementID", "", ...
    "CSIMeasurementDigest", "", ...
    "CSIMeasurementProvenance", "", ...
    "CSIMeasurementSlot", NaN, ...
    "ChannelGain_dB", NaN, ...
    "RankEstimate", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "ConditionNumberStatus", "not_evaluated", ...
    "SingularValues", "", ...
    "SpatialChannelEstimateConvention", "", ...
    "SpatialChannelSnapshotCount", NaN, ...
    "SpatialSignatureToken", "", "SpatialSignatureSHA256", "", ...
    "SpatialSignatureSource", "", ...
    "SpatialSignatureRawRank", NaN, "SpatialSignatureRetainedRank", NaN, ...
    "SpatialSignatureDetectionThreshold", NaN, ...
    "SpatialSignatureNoiseVariance", NaN, ...
    "SpatialSignatureNoiseMargin_dB", NaN, ...
    "SpatialSignatureSnapshotCount", NaN, ...
    "SpatialSignatureReductionMode", "", ...
    "SpatialSignatureDomain", "", ...
    "SpatialSignatureStatus", "not_attempted", ...
    "NumRxAnt", NaN, ...
    "NumTxPorts", NaN, ...
    "SelectedBeamIndices", [], ...
    "AppliedBeamIndices", [], ...
    "AppliedPrecoderPMI", NaN, ...
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
    "BeamScoreSource", "", ...
    "ConfiguredPMI", NaN, ...
    "ConfiguredCRI", NaN, ...
    "CSI_RSRP_dB", NaN, ...
    "CSI_RSRPSource", "", ...
    "CSI_RSRP_dBm", NaN, ...
    "CSI_RSRPPhysicalSource", "", ...
    "CSI_RSRPPhysicalStatus", "not_attempted", ...
    "CSI_RSRPPowerReferencePlane", "", ...
    "CSI_RSSI_dB", NaN, ...
    "CSI_RSSISource", "", ...
    "CSI_RSRQ_dB", NaN, ...
    "CSI_RSRQSource", "");
metrics.SubbandCQIVector = "";
metrics.SubbandSINRVector_dB = "";
metrics.SubbandSizePRB = NaN;
metrics.SubbandCount = NaN;
metrics.WidebandOrSubband = "wideband_only";
metrics.SubbandCQISource = "";
metrics.SubbandCQIValueStatus = "NOT_AVAILABLE";
metrics.AppliedBeamIndices = localParseIndexSet(sixgr.util.structGet( ...
    appliedPrecoding, "AppliedBeamIndexSet", ""));
metrics.AppliedPrecoderPMI = double(sixgr.util.structGet( ...
    appliedPrecoding, "AppliedPrecoderPMI", NaN));

% Classify the exact runtime CSI-RS occasion before any channel-estimate
% early return.  Otherwise a receiver row without exported Hest can both
% hide a missing scheduled CSI-RS measurement and leave a valid periodic
% non-occasion ambiguously blank.
strictCSI = logical(sixgr.util.structGet(cfg, "phy.mimo.strict", false));
measurement = sixgr.util.structGet(rx, "CSIMeasurementState", []);
hasCSIMeasurement = isa(measurement, "sixgr.phy.mimo.CSIMeasurementState");
strictCSIMeasurementRequired = strictCSI && ...
    localStrictCSIMeasurementRequiredForCurrentSlot(rx);
if hasCSIMeasurement
    metrics.CSIMeasurementID = measurement.MeasurementID;
    metrics.CSIMeasurementDigest = measurement.Digest;
    metrics.CSIMeasurementProvenance = measurement.Provenance;
    metrics.CSIMeasurementSlot = measurement.Slot;
elseif strictCSIMeasurementRequired
    error("sixgr:mimo:MissingMeasurementState", ...
        char("Strict DL CSI requires the measured CSI-RS state produced by " + ...
         "PDSCH_Rx on a scheduled CSI-RS occasion."));
elseif strictCSI
    metrics.CSIComputationStatus = "not_scheduled_current_slot";
end

if isempty(Hest)
    return;
end
% Runtime spatial dimensions belong to the channel estimate used by the
% PDSCH receiver for this transport block.  A CSI-RS measurement state can
% contain additional resource/snapshot dimensions and is valid for
% RI/PMI/CQI reporting, but it must never redefine the physical receive
% branches or transmit ports of the executed PDSCH waveform.
runtimeHwb = localWidebandChannelMatrix(Hest);
if isempty(runtimeHwb)
    return;
end
metrics.NumRxAnt = size(runtimeHwb, 1);
metrics.NumTxPorts = size(runtimeHwb, 2);
[Hcsi, nVarCSI, csiChannelSource] = localSelectDLCSIChannelEstimate(rx, Hest, nVar);
if hasCSIMeasurement
    Hcsi = measurement.ChannelEstimate;
    nVarCSI = double(measurement.NoiseVariance);
    csiChannelSource = "immutable_measured_csirs_state";
end

if hasCSIMeasurement || ~strictCSI
  try
    if hasCSIMeasurement
        reportConfiguration = sixgr.util.structGet(cfg, ...
            "phy.csi.reportConfiguration", []);
        csiArgs = {"Direction", "DL", ...
            "MeasurementState", measurement, ...
            "ReportConfiguration", reportConfiguration, ...
            "Carrier", sixgr.util.structGet(rx, "Carrier", []), ...
            "CSIRSConfig", sixgr.util.structGet(rx, "SelectedCSIRS", []), ...
            "PDSCHDMRSConfig", localPDSCHDMRSConfig(rx), ...
            "FullChannelEstimate", sixgr.util.structGet(rx, ...
                "CSIRSChannelEstimate", [])};
        % The immutable state proves channel/noise identity.  Preserve the
        % exact received CSI-RS REs as well so ordinary (non-strict)
        % execution computes its scheduler SINR from the same measured
        % resource plane rather than falling back to a zero-noise channel
        % objective or an unrelated PDSCH data observation.
        measuredCSIRSArgs = localBuildDLCSIRSRPArgs(rx);
        if ~isempty(measuredCSIRSArgs)
            csiArgs = [csiArgs, measuredCSIRSArgs]; %#ok<AGROW>
        end
    elseif csiChannelSource == "csirs_resource_selective_channel_estimate"
        csiArgs = localBuildDLCSIRSRPArgs(rx);
        postEqArgs = localBuildPostEqSINRFeedbackArgs(rx);
        if ~isempty(csiArgs)
            csiArgs = [csiArgs, postEqArgs]; %#ok<AGROW>
        elseif ~isempty(postEqArgs)
            csiArgs = postEqArgs;
        else
            csiArgs = localBuildDLSINRFeedbackArgs(rx);
        end
    else
        csiArgs = localBuildDLSINRFeedbackArgs(rx);
    end
    if ~hasCSIMeasurement
        csiArgs = [{"Direction", "DL"}, csiArgs];
    end
    csi = sixgr.phy.dl.CSI_Feedback(Hcsi, nVarCSI, cfg, csiArgs{:});
    metrics.CSIComputationStatus = "runtime_measured_csi_complete";
    metrics.SINR_dB = double(sixgr.util.structGet(csi, "SINR_dB", NaN));
    metrics.SINRSource = string(sixgr.util.structGet(csi, "SINRSource", ""));
    metrics.SINRValueRole = string(sixgr.util.structGet(csi, "SINRValueRole", ""));
    metrics.SINRValueStatus = string(sixgr.util.structGet(csi, "SINRValueStatus", ""));
    metrics.PostEqSINR_dB = double(sixgr.util.structGet(csi, "PostEqSINR_dB", NaN));
    metrics.PostEqSINRSource = string(sixgr.util.structGet(csi, "PostEqSINRSource", ""));
    metrics.PostEqSINRValueRole = string(sixgr.util.structGet(csi, "PostEqSINRValueRole", ""));
    metrics.PostEqSINRValueStatus = string(sixgr.util.structGet(csi, "PostEqSINRValueStatus", ""));
    metrics.CQI = double(sixgr.util.structGet(csi, "CQI", NaN));
    metrics.CQISource = "dl_csi_feedback:" + csiChannelSource;
    metrics.RI = double(sixgr.util.structGet(csi, "RI", NaN));
    metrics.PMI = double(sixgr.util.structGet(csi, "PMI", NaN));
    for field=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
        metrics.(field)=double(sixgr.util.structGet(csi,field,NaN));
    end
    metrics.LI = double(sixgr.util.structGet(csi, "LI", NaN));
    metrics.CRI = double(sixgr.util.structGet(csi, "CRI", NaN));
    metrics.CSI_RSRP_dB = double(sixgr.util.structGet(csi, "RSRP_dB", NaN));
    metrics.CSI_RSRPSource = string(sixgr.util.structGet(csi, "RSRPSource", ""));
    metrics.CSI_RSSI_dB = double(sixgr.util.structGet(csi, "RSSI_dB", NaN));
    metrics.CSI_RSSISource = string(sixgr.util.structGet(csi, "RSSISource", ""));
    metrics.CSI_RSRQ_dB = double(sixgr.util.structGet(csi, "RSRQ_dB", NaN));
    metrics.CSI_RSRQSource = string(sixgr.util.structGet(csi, "RSRQSource", ""));
    metrics.PMIType = string(sixgr.util.structGet(csi, "PMIType", ""));
    metrics.PMICodebookMode = string(sixgr.util.structGet(csi, "PMICodebookMode", ""));
    metrics.CSIReportMode = string(sixgr.util.structGet(csi, "ChannelStateInformationMode", ""));
    metrics.CSIPayloadBitLength = double(sixgr.util.structGet(csi, "CSIPayloadBitLength", NaN));
    metrics.CSIPayloadHex = localSafeCharToken(sixgr.util.structGet(csi, "CSIPayloadHex", ""));
    metrics.SubbandCQIVector = string(sixgr.util.structGet(csi, "SubbandCQIVector", ""));
    metrics.SubbandSINRVector_dB = string(sixgr.util.structGet(csi, "SubbandSINR_dB", ""));
    metrics.SubbandSizePRB = double(sixgr.util.structGet(csi, "SubbandSizePRB", NaN));
    metrics.SubbandCount = double(sixgr.util.structGet(csi, "SubbandCount", NaN));
    metrics.WidebandOrSubband = string(sixgr.util.structGet(csi, "WidebandOrSubband", "wideband_only"));
    metrics.SubbandCQISource = string(sixgr.util.structGet(csi, "SubbandCQISource", ""));
    metrics.SubbandCQIValueStatus = string(sixgr.util.structGet(csi, "SubbandCQIValueStatus", "NOT_AVAILABLE"));
    metrics.SelectedBeamIndices = double(sixgr.util.structGet(csi, "SelectedBeamIndices", []));
    rsrpArgs = localBuildDLCSIRSRPArgs(rx);
    if ~strictCSI && ~isempty(rsrpArgs)
        rsrpArgs = [{"Direction", "DL"}, rsrpArgs];
        csiRSRP = sixgr.phy.dl.CSI_Feedback(Hcsi, nVarCSI, cfg, rsrpArgs{:});
        rsrpVal = double(sixgr.util.structGet(csiRSRP, "RSRP_dB", NaN));
        rsrpSource = string(sixgr.util.structGet(csiRSRP, "RSRPSource", ""));
        if isfinite(rsrpVal)
            metrics.CSI_RSRP_dB = rsrpVal;
            metrics.CSI_RSRPSource = rsrpSource;
            metrics.CSI_RSSI_dB = double(sixgr.util.structGet(csiRSRP, "RSSI_dB", metrics.CSI_RSSI_dB));
            metrics.CSI_RSSISource = string(sixgr.util.structGet(csiRSRP, "RSSISource", metrics.CSI_RSSISource));
            metrics.CSI_RSRQ_dB = double(sixgr.util.structGet(csiRSRP, "RSRQ_dB", metrics.CSI_RSRQ_dB));
            metrics.CSI_RSRQSource = string(sixgr.util.structGet(csiRSRP, "RSRQSource", metrics.CSI_RSRQSource));
        end
    elseif strictCSI
        rxObs = sixgr.util.structGet(rx, "CSIRSObservation", struct());
        measuredRSRP = double(sixgr.util.structGet(rxObs, "MeasurementRSRP_dB", NaN));
        if isfinite(measuredRSRP)
            metrics.CSI_RSRP_dB = measuredRSRP;
            metrics.CSI_RSRPSource = string(sixgr.util.structGet( ...
                rxObs, "MeasurementSource", "received_csirs_reference_signal_power"));
        end
    end
catch ME
    metrics.CSIComputationStatus = "failed";
    metrics.CSIComputationErrorIdentifier = string(ME.identifier);
    metrics.CSIComputationErrorMessage = string(ME.message);
    if strictCSI
        rethrow(ME);
    end
  end
else
    % A periodic CSI-RS configuration does not create a measurement in
    % every PDSCH slot.  On a genuine non-occasion, retain the PDSCH DM-RS
    % receiver metrics and leave CSI feedback explicitly unavailable.  A
    % later actual CSI-RS occasion must still produce the immutable state
    % above or strict execution fails closed.
    metrics.CSIComputationStatus = "not_scheduled_current_slot";
end

% The receiver owns the physical CSI-RSRP reference plane.  Preserve the
% normalized FFT-grid power separately and never infer dBm from it here.
rxObs = sixgr.util.structGet(rx, "CSIRSObservation", struct());
if isstruct(rxObs) && ~isempty(fieldnames(rxObs))
    relativeRSRP = double(sixgr.util.structGet( ...
        rxObs, "MeasurementRelativeRSRP_dB", NaN));
    if isfinite(relativeRSRP)
        metrics.CSI_RSRP_dB = relativeRSRP;
        metrics.CSI_RSRPSource = string(sixgr.util.structGet( ...
            rxObs, "MeasurementRelativeSource", ...
            "received_csirs_reference_signal_power_post_front_end_normalized_grid"));
    end
    metrics.CSI_RSRP_dBm = double(sixgr.util.structGet( ...
        rxObs, "MeasurementRSRP_dBm", NaN));
    metrics.CSI_RSRPPhysicalSource = string(sixgr.util.structGet( ...
        rxObs, "MeasurementSource", ""));
    metrics.CSI_RSRPPhysicalStatus = string(sixgr.util.structGet( ...
        rxObs, "PhysicalMeasurementStatus", "not_attempted"));
    metrics.CSI_RSRPPowerReferencePlane = string(sixgr.util.structGet( ...
        rxObs, "PowerReferencePlane", ""));
end

if ~isfinite(double(metrics.CQI)) && localCQIReportingEnabled(cfg, "DL")
    postEqSINR = double(sixgr.util.structGet(rx, "PostEqSINR_dB", ...
        sixgr.util.structGet(metrics, "PostEqSINR_dB", NaN)));
    postEqSource = string(sixgr.util.structGet(rx, "PostEqSINRSource", ...
        sixgr.util.structGet(metrics, "PostEqSINRSource", "")));
    postEqRole = string(sixgr.util.structGet(rx, "PostEqSINRValueRole", ...
        sixgr.util.structGet(metrics, "PostEqSINRValueRole", "")));
    postEqStatus = string(sixgr.util.structGet(rx, "PostEqSINRValueStatus", ...
        sixgr.util.structGet(metrics, "PostEqSINRValueStatus", "")));
    if isfinite(postEqSINR) && localDLSINRIsCQIEligible(postEqSource, postEqRole, postEqStatus)
        try
            feedback = sixgr.link.resolveWidebandCQI(struct( ...
                "WidebandSINR_dB", double(postEqSINR), ...
                "SINRSource", char(postEqSource), ...
                "SINRValueRole", char(postEqRole), ...
                "SINRValueStatus", char(postEqStatus)), cfg, "DL");
            rawCQI = double(sixgr.util.normalizeReportedCQI(sixgr.util.structGet(feedback, "WidebandCQI", NaN)));
            if isfinite(rawCQI)
                metrics.CQI = double(rawCQI);
                metrics.CQISource = "dl_post_equalization_sinr_to_cqi:" + string(sixgr.util.structGet(feedback, "Mode", "sinr_threshold_table"));
                metrics.SINR_dB = double(postEqSINR);
                metrics.SINRSource = string(postEqSource);
                metrics.SINRValueRole = string(postEqRole);
                metrics.SINRValueStatus = string(postEqStatus);
            end
        catch
        end
    end
end

gain = mean(abs(Hcsi(:)).^2, "omitnan");
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

if hasCSIMeasurement
    % PDSCH_Rx already canonicalizes every immutable CSI-RS state as
    % Nrx-by-Nport-by-Nsnapshot.  This producer contract is independent of
    % whether strict qualification is enabled.  Re-applying the K-by-L
    % resource-grid converter would reinterpret the snapshot axis as
    % receive ports and silently collapse Nport to one in ordinary exact
    % waveform runs.  Always consume the declared canonical convention and
    % fail closed on a producer/consumer mismatch.
    Hwb = sixgr.mimo.spatialSnapshotsFromMeasurementState(measurement);
    metrics.SpatialChannelEstimateConvention = measurement.ChannelEstimateConvention;
else
    Hwb = localWidebandChannelMatrix(Hcsi);
    metrics.SpatialChannelEstimateConvention = "resource_grid_converted_to_rx_by_tx_by_snapshot";
end
if isempty(Hwb)
    return;
end
metrics.SpatialChannelSnapshotCount = size(Hwb, 3);
muMimoEnabled = logical(sixgr.util.structGet(cfg, ...
    "phy.mimo.muMimoEnabled", false));
duplexMode = upper(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.duplex.mode", sixgr.util.structGet(cfg, "phy.duplexMode", "")))));
if muMimoEnabled && duplexMode == "FDD"
    measuredRank = double(sixgr.util.structGet(metrics, "RI", NaN));
    if ~(isscalar(measuredRank) && isfinite(measuredRank) && measuredRank >= 1)
        error("sixgr:mimo:MissingFDDCSIRSMeasuredRank", ...
            "FDD DL MU-MIMO requires a measured CSI-RS RI before spatial pairing.");
    end
    signatureMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.mimo.muMimoSpatialSignatureMode", ""))));
    % Convert canonical Nrx-by-Ntx-by-Nsnapshot CSI into the standard
    % K-by-L-by-Nrx-by-Ntx estimator layout without averaging phase.
    hSpatialGrid = permute(Hwb, [3 4 1 2]);
    if signatureMode == "complete_detectable_subspace"
        [spatialSignature, signatureInfo] = ...
            sixgr.phy.mimo.spatialSignatureFromChannelEstimate( ...
            hSpatialGrid, "Rank", measuredRank, ...
            "SubspaceMode", signatureMode, ...
            "SpatialDomain", "transmitter", ...
            "NoiseVariance", double(nVarCSI), ...
            "NoiseMargin_dB", double(sixgr.util.structGet(cfg, ...
                "phy.mimo.muMimoSpatialSubspaceNoiseMargin_dB", NaN)));
    else
        [spatialSignature, signatureInfo] = ...
            sixgr.phy.mimo.spatialSignatureFromChannelEstimate( ...
            hSpatialGrid, "Rank", measuredRank, ...
            "SubspaceMode", signatureMode, ...
            "SpatialDomain", "transmitter");
    end
    metrics.SpatialSignatureToken = char( ...
        sixgr.phy.mimo.MatrixContract.serialize(spatialSignature));
    metrics.SpatialSignatureSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(spatialSignature));
    metrics.SpatialSignatureSource = ...
        "measured_csirs_receiver_channel_estimate_transmit_subspace";
    metrics.SpatialSignatureRawRank = double(signatureInfo.RawNumericalRank);
    metrics.SpatialSignatureRetainedRank = double(signatureInfo.RetainedRank);
    metrics.SpatialSignatureDetectionThreshold = double(signatureInfo.DetectionThreshold);
    metrics.SpatialSignatureNoiseVariance = double(signatureInfo.NoiseVariance);
    metrics.SpatialSignatureNoiseMargin_dB = double(signatureInfo.NoiseMargin_dB);
    metrics.SpatialSignatureSnapshotCount = double(signatureInfo.SnapshotCount);
    metrics.SpatialSignatureReductionMode = char(signatureInfo.ReductionMode);
    metrics.SpatialSignatureDomain = char(signatureInfo.SpatialDomain);
    metrics.SpatialSignatureStatus = "available_measured_fdd_dl_transmit_subspace";
end
try
    [metrics.ConditionNumber_dB, metrics.ConditionNumberStatus, metrics.RankEstimate, singularValues] = ...
        sixgr.mimo.channelConditionNumber(Hwb);
    metrics.SingularValues = localFormatNumericVector(singularValues);
catch
end
beamMetrics = localComputeBeamMetrics(Hwb, cfg, metrics);
beamFields = fieldnames(beamMetrics);
for f = 1:numel(beamFields)
    metrics.(beamFields{f}) = beamMetrics.(beamFields{f});
end
if strlength(csiChannelSource) > 0 && strlength(string(metrics.BeamScoreSource)) > 0
    metrics.BeamScoreSource = string(metrics.BeamScoreSource) + ":" + csiChannelSource;
end
end

function tf = localStrictCSIMeasurementRequiredForCurrentSlot(rx)
% A strict CSI state is required only when this exact runtime slot carried
% a CSI-RS producer event. Periodic CSI-RS non-occasions are valid PDSCH
% slots and must not be mislabeled as missing receiver evidence.
obs = sixgr.util.structGet(rx, "CSIRSObservation", struct());
tf = logical(sixgr.util.structGet(obs, "Scheduled", false)) || ...
    logical(sixgr.util.structGet(obs, "Observed", false)) || ...
    logical(sixgr.util.structGet(obs, "ChannelEstimateAvailable", false));
end

function dmrs = localPDSCHDMRSConfig(rx)
pdsch = sixgr.util.structGet(rx,"PDSCH",[]);
if isempty(pdsch) || ~isa(pdsch,"nrPDSCHConfig")
    error("sixgr:mimo:MissingCSIReportConfig", ...
        "Strict DL CSI requires the runtime nrPDSCHConfig used by the receiver.");
end
dmrs = pdsch.DMRS;
if isempty(dmrs) || ~isa(dmrs,"nrPDSCHDMRSConfig")
    error("sixgr:mimo:MissingCSIReportConfig", ...
        "Strict DL CSI requires the runtime PDSCH DM-RS configuration.");
end
end

function [Hcsi, nVarCSI, source] = localSelectDLCSIChannelEstimate(rx, Hest, nVar)
Hcsi = Hest;
nVarCSI = nVar;
source = "pdsch_dmrs_effective_channel_estimate";
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
candidates = { ...
    "CSIChannelEstimateForPMI", "CSIChannelNoiseVarForPMI", "CSIChannelEstimateSource"; ...
    "CSIRSChannelEstimate", "CSIRSNoiseVar", "CSIChannelEstimateSource"};
for ii = 1:size(candidates, 1)
    candH = sixgr.util.structGet(rx, candidates{ii, 1}, []);
    if isempty(candH)
        continue;
    end
    Hcsi = candH;
    candNVar = double(sixgr.util.structGet(rx, candidates{ii, 2}, NaN));
    if isfinite(candNVar) && candNVar >= 0
        nVarCSI = candNVar;
    end
    candSource = string(sixgr.util.structGet(rx, candidates{ii, 3}, ""));
    if strlength(candSource) == 0
        candSource = "csirs_resource_selective_channel_estimate";
    end
    source = candSource;
    return;
end
end

function args = localBuildDLSINRFeedbackArgs(rx)
args = {};
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
postEqArgs = localBuildPostEqSINRFeedbackArgs(rx);
rxGrid = sixgr.util.structGet(rx, "RxGrid", []);
refInd = sixgr.util.structGet(rx, "DMRSIndices", []);
refSym = sixgr.util.structGet(rx, "DMRSSymbols", []);
if ~isempty(rxGrid) && ~isempty(refInd) && ~isempty(refSym)
    args = [{"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym}, postEqArgs];
    return;
end
refInd = sixgr.util.structGet(rx, "CSIRSIndices", []);
refSym = sixgr.util.structGet(rx, "CSIRSSymbols", []);
if isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    args = postEqArgs;
    return;
end
args = [{"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym}, postEqArgs];
end

function args = localBuildPostEqSINRFeedbackArgs(rx)
args = {};
postEq = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
if ~(isscalar(postEq) && isfinite(postEq))
    return;
end
args = {"PostEqSINR_dB", postEq, ...
    "PostEqSINRSource", string(sixgr.util.structGet(rx, "PostEqSINRSource", "")), ...
    "PostEqSINRValueRole", string(sixgr.util.structGet(rx, "PostEqSINRValueRole", "")), ...
    "PostEqSINRValueStatus", string(sixgr.util.structGet(rx, "PostEqSINRValueStatus", "")), ...
    "PostEqSINRNAReason", string(sixgr.util.structGet(rx, "PostEqSINRNAReason", ""))};
end

function args = localBuildDLCSIRSRPArgs(rx)
args = {};
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
rxGrid = sixgr.util.structGet(rx, "RxGrid", []);
refInd = sixgr.util.structGet(rx, "CSIRSIndices", []);
refSym = sixgr.util.structGet(rx, "CSIRSSymbols", []);
if ~isempty(rxGrid) && ~isempty(refInd) && ~isempty(refSym)
    args = {"ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym};
    return;
end
end

function Hwb = localWidebandChannelMatrix(Hest)
% Hest is a resource-grid estimate, not a single flat-fading matrix.
% Preserve the complex response of every finite RE as an independent
% spatial snapshot.  Coherently averaging H across frequency/time can
% cancel real multipath phase rotations and flatten PMI/beam scores.
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
nTx = size(Hwb, 2);
if ~(isfinite(nTx) && nTx >= 1)
    return;
end

codebookBeam = localComputePMICodebookCandidateMetrics(Hwb, cfg, metrics);
if ~isempty(fieldnames(codebookBeam)) && isfinite(double(codebookBeam.BeamCandidateCount))
    beam = codebookBeam;
    return;
end

beamCountCfg = max(1, round(double(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.dlCodebookSize", ...
    sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", nTx)))));
selectedBeamHint = double(sixgr.util.structGet(metrics, "SelectedBeamIndices", []));
selectedBeamHint = selectedBeamHint(isfinite(selectedBeamHint));
maxSelectedBeam = 0;
if ~isempty(selectedBeamHint)
    maxSelectedBeam = max(selectedBeamHint);
end
usePMICodebook = isfinite(double(sixgr.util.structGet(metrics, "PMI", NaN))) || ~isempty(selectedBeamHint);
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

metric = localFrequencySelectiveBeamPower(Hwb,W);
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
if beamStrategy == "fixed_first_beam"
    beam.BeamHit = double(selectedIdx == bestIdx);
    beam.TopKBeamHit = double(ismember(selectedIdx, ord(1:topK)));
else
    beam.BeamHit = double(any(selectedSet == bestIdx));
    beam.TopKBeamHit = double(any(ismember(ord(1:topK), selectedSet)));
end
if ~hasSelected
    beam.BeamHit = NaN;
    beam.TopKBeamHit = NaN;
end
beam.SelectedBeamGain_dB = localPositivePowerToDb(selectedMetric);
beam.BestBeamGain_dB = localPositivePowerToDb(bestMetric);
beam.BeamGainGap_dB = localFiniteDifference(beam.BestBeamGain_dB, ...
    beam.SelectedBeamGain_dB);
beam.BeamScoreVector_dB = localFormatNumericVector(metricDb);
beam.TopBeamIndexSet = localFormatIndexSet(ord(1:traceK));
beam.TopBeamGainSet_dB = localFormatNumericVector(metricDb(ord(1:traceK)));
beam.BeamScoreSource = "applied_precoder_vs_current_wideband_hest_codebook_projection";
end

function beam = localComputePMICodebookCandidateMetrics(Hwb, cfg, metrics)
beam = struct();
if isempty(Hwb) || ndims(Hwb) > 3 || size(Hwb, 2) <= 1
    return;
end
nTx = size(Hwb, 2);
nLayers = localResolveLayerCount(cfg, metrics);
codebookMode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo"));
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
    "BeamScoreSource", "applied_pmi_vs_current_wideband_hest_3gpp_type1_candidate_projection");
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
pmi = double(sixgr.util.structGet(metrics, "AppliedPrecoderPMI", NaN));
if isfinite(pmi)
    idx = round(pmi) + 1;
    if idx >= 1 && idx <= numel(candidates)
        selectedIdx = double(idx);
        return;
    end
end
selectedBeams = double(sixgr.util.structGet(metrics, "AppliedBeamIndices", []));
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
selectedSet = localClampBeamIndexSet(sixgr.util.structGet( ...
    metrics, "AppliedBeamIndices", []), size(W, 2));
if ~isempty(selectedSet)
    return;
end
appliedPMI = double(sixgr.util.structGet(metrics, "AppliedPrecoderPMI", NaN));
selectedSet = localResolveBeamSetFromPMI(cfg, ...
    struct("PMI", appliedPMI, "RI", metrics.RI), size(W, 1), size(W, 2));
if ~isempty(selectedSet)
    return;
end
end

function values = localParseIndexSet(token)
if isnumeric(token)
    values = double(token(:).');
    values = values(isfinite(values));
    return;
end
parts = regexp(char(string(token)), '-?\d+(?:\.\d+)?', 'match');
if isempty(parts)
    values = [];
else
    values = str2double(string(parts));
    values = double(values(isfinite(values)));
end
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
    referenceMetrics = sixgr.phy.rx.referenceSignalMetrics( ...
        rxGrid, Hest, dmrsInd, dmrsSym, ...
        "NoiseVariance", double(sixgr.util.structGet( ...
            rx, "PreEqualizationNoiseVar", NaN)), ...
        "ContextLabel", "runDLPDSCHThroughput_channel_metrics");
catch
    return;
end

nmseLin = double(referenceMetrics.NMSELinear);
if isfinite(nmseLin) && nmseLin >= 0
    detectionMetric = 1 / (1 + nmseLin);
else
    nmseLin = NaN;
end
end

function metric = localFrequencySelectiveBeamPower(H,W)
if ismatrix(H)
    H = reshape(H,size(H,1),size(H,2),1);
end
metric = zeros(1,size(W,2));
for snapshot = 1:size(H,3)
    projected = double(H(:,:,snapshot)) * double(W);
    metric = metric + sum(abs(projected).^2,1);
end
metric = metric ./ max(size(H,3),1);
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
    referenceMetrics = sixgr.phy.rx.referenceSignalMetrics( ...
        rxGrid, Hest, dmrsInd, dmrsSym, ...
        "NoiseVariance", double(sixgr.util.structGet( ...
            rx, "PreEqualizationNoiseVar", NaN)), ...
        "ContextLabel", "runDLPDSCHThroughput_tracking_metrics");
catch
    return;
end
nmseLin = double(referenceMetrics.NMSELinear);
if isfinite(nmseLin) && nmseLin >= 0
    metrics.NMSE_dB = 10 * log10(max(nmseLin, eps));
    metrics.DetectionMetric = 1 / (1 + nmseLin);
end

pilotH = localCollapsePilotEstimate( ...
    referenceMetrics.ChannelAtReference);
symTimes_s = localPilotSymbolTimes( ...
    carrier, referenceMetrics.PhysicalLinearIndices);
estHz = localEstimatePilotDoppler(symTimes_s, pilotH);
metrics.EstimatedDopplerHz = estHz;
if isfinite(estHz)
    metrics.PhaseTrackingError_deg = localPilotPhaseTrackingError(symTimes_s, pilotH);
end
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

function tf = localDLSINRIsCQIEligible(source, role, status)
token = lower(strjoin([string(source), string(role), string(status)], " "));
words = string(regexp(char(token), '[a-z0-9]+', 'match'));
blocked = ["receiverhest", "receiver_hest", "pilot", ...
    "reference_signal", "evm_proxy", "proxy", "fallback", "configured", "sweep", ...
    "unavailable", "failed", "rejected"];
tf = contains(token, "post_equalization") && ~any(words == "hest") && ~any(contains(token, blocked));
end

function selectedSet = localResolveBeamSetFromPMI(cfg, metrics, nTx, beamCount)
selectedSet = [];
pmi = double(sixgr.util.structGet(metrics, "PMI", NaN));
if ~isfinite(pmi)
    return;
end

nLayers = localResolveLayerCount(cfg, metrics);
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
    nLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))));
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
maxIter = sixgr.phy.phycode.resolveLDPCMaxIterations(cfg, "Direction", "DL");
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

function evidence = localHARQEvidencePerCodeword(value, nCodewords)
evidence = false(1, nCodewords);
if iscell(value)
    count = min(numel(value), nCodewords);
    for c = 1:count
        evidence(c) = localHARQPriorAvailable(value{c});
    end
elseif nCodewords == 1
    evidence(1) = localHARQPriorAvailable(value);
elseif localHARQPriorAvailable(value)
    error("sixgr:harq:AmbiguousTwoCodewordSoftBuffer", ...
        "Two-codeword HARQ requires one prior soft buffer per codeword.");
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
pdsch = sixgr.util.structGet(tx, "PDSCH", []);
prec = sixgr.util.structGet(tx, "PrecodeInfo", struct());
tbBitsActual = sixgr.util.structGet(tx, "TransportBlock", []);
tbSizeActual = double(numel(tbBitsActual));
if ~(isfinite(tbSizeActual) && tbSizeActual > 0)
    tbSizeActual = double(sixgr.util.structGet(seedGrant, "TBSBits", ...
        sixgr.util.structGet(seedGrant, "TransportBlockSize", ...
        sixgr.util.structGet(tx, "TransportBlockSize", NaN))));
end
tbSizePerCodeword = double(sixgr.util.structGet(tx, ...
    "TransportBlockSizePerCodeword", ...
    sixgr.util.structGet(tx, "TransportBlockSize", NaN)));
tbSizePerCodeword = tbSizePerCodeword(:).';
scheduledTBSize = sum(tbSizePerCodeword, "omitnan");
targetCodeRatePerCodeword = double(sixgr.util.structGet(tx, ...
    "TargetCodeRatePerCodeword", ...
    sixgr.util.structGet(tx, "TargetCodeRate", NaN)));
targetCodeRatePerCodeword = targetCodeRatePerCodeword(:).';
numTxAnt = NaN;
if isfield(tx, "Grid") && ~isempty(tx.Grid)
    numTxAnt = double(size(tx.Grid, 3));
end
pdschMod = localObjectValue(pdsch, "Modulation", "");
pdschLayers = localObjectValue(pdsch, "NumLayers", NaN);
pdschPRBSet = localObjectValue(pdsch, "PRBSet", []);
pdschSymbolAllocation = localObjectValue(pdsch, "SymbolAllocation", []);
pdschMappingType = localObjectValue(pdsch, "MappingType", "");
acct = sixgr.util.structGet(tx, "ResourceAccounting", struct());
acctNREPerPRB = double(sixgr.util.structGet(acct, "NREPerPRBForTBS", sixgr.util.structGet(tx, "NREPerPRB", NaN)));
acctG = double(sixgr.util.structGet(acct, "CodedBitCountG", sixgr.util.structGet(tx, "G", NaN)));
acctLayerRE = double(sixgr.util.structGet(acct, "LayerDataRE", sixgr.util.structGet(tx, "LayerDataRE", NaN)));
acctPortRE = double(sixgr.util.structGet(acct, "PortMappedRE", sixgr.util.structGet(tx, "PortMappedRE", NaN)));
acctModSymbols = double(sixgr.util.structGet(acct, "ModulationSymbolCount", sixgr.util.structGet(tx, "ModulationSymbolCount", NaN)));
xOverhead = double(sixgr.util.structGet(tx, "XOverhead", sixgr.util.structGet(cfg, "phy.pdsch.xOverhead", 0)));
precActive = logical(sixgr.util.structGet(prec, "Active", false));
precodingMatrix = [];
if precActive
    precodingMatrix = sixgr.util.structGet(prec, "MatrixPorts", ...
        sixgr.util.structGet(prec, "MatrixNR", sixgr.util.structGet(prec, "Matrix", [])));
end
grant = struct( ...
    "Direction", "DL", ...
    "MCS", double(mcsIndex), ...
    "MCSIndex", double(sixgr.util.structGet(seedGrant, "MCSIndex", mcsIndex)), ...
    "Modulation", char(localCommonTextToken(pdschMod)), ...
    "TargetCodeRate", localCommonFiniteScalar( ...
        targetCodeRatePerCodeword), ...
    "TargetCodeRatePerCodeword", targetCodeRatePerCodeword, ...
    "NumLayers", double(pdschLayers), ...
    "Layers", double(pdschLayers), ...
    "PRBs", double(numel(pdschPRBSet)), ...
    "PRBSet", pdschPRBSet, ...
    "SymbolAllocation", pdschSymbolAllocation, ...
    "MappingType", localSafeCharToken(pdschMappingType), ...
    "CarrierConfig", sixgr.util.structGet(tx, "Carrier", []), ...
    "PDSCHConfig", pdsch, ...
    "TransportBlockSize", double(tbSizeActual), ...
    "ScheduledTransportBlockSize", double(scheduledTBSize), ...
    "TBSBits", double(tbSizeActual), ...
    "TBSBitsPerCodeword", tbSizePerCodeword, ...
    "TBSBytes", floor(double(tbSizeActual) / 8), ...
    "XOverhead", double(xOverhead), ...
    "NREPerPRB", double(acctNREPerPRB), ...
    "LayerDataRE", double(acctLayerRE), ...
    "PortMappedRE", double(acctPortRE), ...
    "ModulationSymbolCount", double(acctModSymbols), ...
    "CodedBitCountG", double(acctG), ...
    "TBSInputModulation", char(localCommonTextToken(pdschMod)), ...
    "TBSInputNumLayers", double(pdschLayers), ...
    "TBSInputNPRB", double(numel(pdschPRBSet)), ...
    "TBSInputNREPerPRB", double(acctNREPerPRB), ...
    "TBSInputTargetCodeRate", localCommonFiniteScalar( ...
        targetCodeRatePerCodeword), ...
    "TBSInputXOverhead", double(xOverhead), ...
    "ResourceAccountingSource", localSafeCharToken(sixgr.util.structGet(acct, "Source", "")), ...
    "NumTxAnt", double(numTxAnt), ...
    "PrecodingMatrix", precodingMatrix, ...
    "ConfiguredBeamSelectionStrategy", localSafeCharToken(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")), ...
    "PrecoderSource", localSafeCharToken(sixgr.util.structGet(prec, "Source", "none")), ...
    "PrecodingMode", localSafeCharToken(sixgr.util.structGet(prec, "Mode", "siso-bypass")), ...
    "PrecodingApplicationStage", localSafeCharToken(sixgr.util.structGet(prec, "ApplicationStage", "none")), ...
    "PrecodingActive", precActive, ...
    "ExplicitBeamWeightsApplied", precActive, ...
    "TransformPrecodingApplied", false, ...
    "BeamformingApplied", precActive, ...
    "AppliedBeamIndexSet", char(localFormatIndexSet(sixgr.util.structGet(prec, "BeamIndices", []))), ...
    "AppliedPrecoderPMI", double(sixgr.util.structGet(prec, "PMI", NaN)), ...
    "AppliedPrecoderPMIType", localSafeCharToken(sixgr.util.structGet(prec, "PMIType", "")), ...
    "AppliedPrecoderCodebookMode", localSafeCharToken(sixgr.util.structGet(prec, "CodebookMode", "")), ...
    "PrecodingNumPorts", double(sixgr.util.structGet(prec, "NumPorts", NaN)), ...
    "PrecodingNumLayers", double(sixgr.util.structGet(prec, "NumLayers", NaN)), ...
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
    "PUCCHResourceIndicator","PUCCHResourceSetId","PUCCHResourceId", ...
    "PUCCHResourceIndicatorSource","PUCCHResourceAuthority", ...
    "DMRSPortSet","DMRSPortSetSource","PTRSEnabled","PTRSPortSet","PTRSPortSetSource", ...
    "MUMIMOEnabled","MUMIMOGroupSize","MUMIMOGroupId","MUMIMOPairingStatus", ...
    "MUMIMOPairingMetricSource","MUMIMOPairingMetricValue_dB","MUMIMOPairingEvidenceSource","MUMIMOPrecoderType", ...
    "MUMIMOPairingWorstMetricValue_dB","MUMIMORequiredLeakageThreshold_dB", ...
    "MUMIMODesiredSubspaceGain_dB","MUMIMORequiredMinimumDesiredGain_dB", ...
    "MUMIMOSpatialDesignStatus","MUMIMOSpatialDesignContractVersion", ...
    "MUMIMOSpatialSignatureSubspaceMode", ...
    "MUMIMOSpatialDesignEvidenceSource","MUMIMOSpatialFilterMatrixSHA256", ...
    "MUMIMOHybridRFDesignPolicy","MUMIMOHybridRFDesignStatus", ...
    "HybridElementToPortMatrixSHA256","BaseHybridElementToPortMatrixSHA256", ...
    "NumLogicalPorts","NumRFChains", ...
    "PrecodingMatrixLogicalPorts","LogicalPrecodingMatrix","PrecodingMatrix", ...
    "HybridElementToPortMatrix","PrecodingActive","PrecodingMode", ...
    "PrecoderSource","PrecodingApplicationStage", ...
    "SchedulerCQIRawCQI","SchedulerAdjustedSINR_dB","SchedulerSINRBackoff_dB","SchedulerCQISource", ...
    "MCSIndexAuthority","GrantOperatingPointSource", ...
    "TimingDecision","K0","K1","K2","ControlAbsoluteSlot", ...
    "ScheduledAbsoluteSlot","HARQFeedbackAbsoluteSlot", ...
    "SchedulingCCID","ScheduledCCID","CarrierIndicator", ...
    "SourceBWPID","TargetBWPID", ...
    "PBCHGatingActive","PRACHGatingActive","PDCCHGatingActive","SRSGatingActive","ControlEligible","ControlDecodeOk", ...
    "DCICrcPass","PDCCHPayloadMatch","PDCCHCausalGrantDecodeOk","PDCCHMissedDetection","PDCCHFalseAlarm", ...
    "GrantValid","NegativeExpectedOk","PDCCHBlindSearchEnabled","PDCCHREGMappingAvailable", ...
    "PDCCHGrantBindingRequired","PDCCHGrantBindingOk","PDCCHGrantBindingStatus","PDCCHGrantBindingFailureCode", ...
    "PDCCHGrantDCIId","PDCCHGrantDCIFieldsHash","PDCCHGrantFieldsHash","PDCCHGrantSearchSpaceId", ...
    "PDCCHGrantCORESETId","PDCCHGrantAggregationLevel","PDCCHGrantCandidateIndex","PDCCHGrantDCIFormat", ...
    "GrantControlState","PDCCHControlFailureReason","PDCCHControlEvidenceSource","ControlDecodeSource", ...
    "CellAcquisitionState","AccessState","SRSValidityState","CSIValidityState","SRSValid","SRSAgeSlots", ...
    "TRSGatingActive","TRSValidityState","TrackingEligibility","TRSAgeSlots","LastSuccessfulTRSSlot","LastEstimatedTRSDopplerHz", ...
    "TRSStateSource","TRSRuntimeConsumer","TRSInfluencedDecision","TRSInfluenceDefinition","TRSReceiverIntegrationStatus","TRSReceiverIntegrationBlocker", ...
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
% The HARQ snapshot must describe the architecture actually exercised by
% this PDSCH waveform.  Scheduler metadata is preserved above for all
% policy/control fields, but a missing or stale architecture value must not
% overwrite the applied precoder evidence.
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
grant = sixgr.link.finalizeHARQGrantSpatialSnapshot(grant, "DL");
if ~(isfield(grant, "GrantContextId") && strlength(strtrim(string(grant.GrantContextId))) > 0)
    grant.GrantContextId = localComposeReplayGrantContextId( ...
        seedGrant, "DL", frameIdx, slotIdx, trialSeed);
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

function grant = localAlignGrantSnapshotToPHYGrant(grant, phyGrant)
if ~(isstruct(grant) && isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)))
    return;
end
coding = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
ant = sixgr.util.structGet(phyGrant, "AntennaArchitecture", struct());
prec = sixgr.util.structGet(phyGrant, "PrecodingState", struct());
grant.TargetCodeRate = double(sixgr.util.structGet(coding, "TargetCodeRate", ...
    sixgr.util.structGet(grant, "TargetCodeRate", NaN)));
grant.XOverhead = double(sixgr.util.structGet(coding, "XOverhead", ...
    sixgr.util.structGet(grant, "XOverhead", NaN)));
grant.TBSBits = double(sixgr.util.structGet(coding, "TBSBits", ...
    sixgr.util.structGet(grant, "TBSBits", sixgr.util.structGet(grant, "TransportBlockSize", NaN))));
grant.TransportBlockSize = double(grant.TBSBits);
grant.TBSBytes = double(sixgr.util.structGet(coding, "TBSBytes", floor(max(grant.TBSBits, 0) / 8)));
grant.NumLayers = double(sixgr.util.structGet(coding, "NumLayers", ...
    sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN))));
grant.Layers = double(grant.NumLayers);
grant.PrecodingMatrix = sixgr.util.structGet(prec, "MatrixPorts", ...
    sixgr.util.structGet(prec, "Matrix", sixgr.util.structGet(grant, "PrecodingMatrix", [])));
grant.PrecodingMatrixLogicalPorts = sixgr.util.structGet(prec, "MatrixLogicalPorts", ...
    sixgr.util.structGet(grant, "PrecodingMatrixLogicalPorts", grant.PrecodingMatrix));
grant.PrecodingNumPorts = double(sixgr.util.structGet(prec, "NumPorts", ...
    sixgr.util.structGet(grant, "PrecodingNumPorts", NaN)));
grant.PrecodingNumLogicalPorts = double(sixgr.util.structGet(prec, "NumLogicalPorts", ...
    sixgr.util.structGet(grant, "PrecodingNumLogicalPorts", grant.NumLayers)));
grant.PrecodingNumLayers = double(sixgr.util.structGet(prec, "NumLayers", ...
    sixgr.util.structGet(grant, "PrecodingNumLayers", NaN)));
grant.PrecodingMatrixRows = double(sixgr.util.structGet(prec, "MatrixRows", ...
    sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN)));
grant.PrecodingMatrixCols = double(sixgr.util.structGet(prec, "MatrixCols", ...
    sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN)));
grant.NumTxAnt = double(sixgr.util.structGet(ant, "NumWaveformColumns", ...
    sixgr.util.structGet(grant, "NumTxAnt", NaN)));
end

function [grant, phyGrant] = localNormalizeHARQReplayGrantInputs(cfg, grant, phyGrant, tbBits, harqContext, snr_dB, frameIdx, slotIdx)
isRetx = localInferHARQReplayMode(grant, phyGrant, harqContext, tbBits);
if ~isRetx
    % A scheduler-owned new-data job already carries the exact frozen grant
    % that produced its transport block.  TB context is lifecycle evidence
    % for both new data and replay; it must not trigger a second freeze from
    % the transient per-user cfg, whose current MU hybrid matrix can differ
    % from the matrix frozen for this scheduled user.
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
        "DL HARQ replay context TBSBits=%d does not match stored TB bits=%d.", ...
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
    phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, "DL", grant, ...
        "SNR_dB", snr_dB, ...
        "Frame", frameIdx, ...
        "Slot", slotIdx, ...
        "HARQContext", harqContext);
end
grant = localAlignGrantSnapshotToPHYGrant(grant, phyGrant);
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

function txArgs = localAppendGrantReplayTxArgs(txArgs, grant, cfgFrame)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
carrier = sixgr.util.structGet(grant, "CarrierConfig", []);
pdsch = sixgr.util.structGet(grant, "PDSCHConfig", []);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
xOverhead = double(sixgr.util.structGet(grant, "XOverhead", NaN));
numTxAnt = double(sixgr.util.structGet(grant, "NumTxAnt", NaN));
precodingMatrix = sixgr.util.structGet(grant, "PrecodingMatrix", []);
storedTBSize = double(sixgr.util.structGet(grant, "TBSBits", ...
    sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
if hasPHYGrant
    [runtimeCarrier, ~] = sixgr.phy.grid.materializeRuntimeCarrier( ...
        cfgFrame, carrier, "DL");
    txArgs = [txArgs {"Carrier", runtimeCarrier}]; %#ok<AGROW>
elseif ~isempty(carrier)
    txArgs = [txArgs {"Carrier", carrier}]; %#ok<AGROW>
end
if ~hasPHYGrant && ~isempty(pdsch)
    txArgs = [txArgs {"PDSCH", pdsch}]; %#ok<AGROW>
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
if ~hasPHYGrant && localGrantHasExplicitDLPrecoding(grant, precodingMatrix)
    txArgs = [txArgs {"PrecodingMatrix", precodingMatrix}]; %#ok<AGROW>
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

function localAssertReplayPHYGrantReady(isRetransmission, grant, phyGrant, tbBits)
if ~logical(isRetransmission)
    return;
end
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)))
    error("sixgr:HARQReplay:MissingPHYGrant", ...
        "DL HARQ replay requires a frozen PHYGrant before PDSCH_Tx.");
end
if ~logical(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false))
    error("sixgr:HARQReplay:PHYGrantNotRetransmission", ...
        "DL HARQ replay reached PDSCH_Tx with PHYGrant retx=false (grant.IsRetransmission=%d, grant.HARQ.IsRetransmission=%d, PHYGrantTBS=%s, StoredTBS=%s, StoredBits=%d).", ...
        logical(sixgr.util.structGet(grant, "IsRetransmission", false)), ...
        logical(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "IsRetransmission", false)), ...
        mat2str(double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN))), ...
        mat2str(double(sixgr.util.structGet(grant, "TBSBits", sixgr.util.structGet(grant, "TransportBlockSize", NaN)))), ...
        numel(tbBits));
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

function tf = localGrantHasExplicitDLPrecoding(grant, precodingMatrix)
tf = false;
if ~(isstruct(grant) && ~isempty(fieldnames(grant))) || isempty(precodingMatrix)
    return;
end
mode = lower(strtrim(string(sixgr.util.structGet(grant, "PrecodingMode", ""))));
source = lower(strtrim(string(sixgr.util.structGet(grant, "PrecoderSource", ""))));
stage = lower(strtrim(string(sixgr.util.structGet(grant, "PrecodingApplicationStage", ""))));
active = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
beamApplied = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
explicitApplied = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
tf = active || beamApplied || explicitApplied || ...
    (strlength(mode) > 0 && mode ~= "siso-bypass" && mode ~= "none") || ...
    (strlength(source) > 0 && source ~= "none" && source ~= "siso-bypass") || ...
    (strlength(stage) > 0 && stage ~= "none");
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

function value = localCommonFiniteScalar(raw)
if ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
values = double(raw(:));
values = values(isfinite(values));
if isempty(values) || any(abs(values - values(1)) > 1e-12)
    value = NaN;
else
    value = double(values(1));
end
end

function token = localCommonTextToken(raw)
values = string(raw);
values = strtrim(values(:));
values = values(strlength(values) > 0);
if isempty(values)
    token = "";
    return;
end
if all(upper(values) == upper(values(1)))
    token = values(1);
else
    token = strjoin(values, "|");
end
end

function token = localIntegerToken(value)
value = round(double(value));
if ~(isfinite(value) && isscalar(value))
    token = "na";
    return;
end
token = sprintf('%d', value);
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
tbsPerCodeword = double(sixgr.util.structGet(tx, ...
    "TransportBlockSizePerCodeword", ...
    sixgr.util.structGet(tx, "TransportBlockSize", NaN)));
tbsPerCodeword = tbsPerCodeword(:).';
rvPerCodeword = double(sixgr.util.structGet(tx, ...
    "RVPerCodeword", sixgr.util.structGet(tx, "RV", NaN)));
rvPerCodeword = rvPerCodeword(:).';
currentRVForGroup = localCommonFiniteScalar(rvPerCodeword);
isRetransmission = logical(sixgr.util.structGet( ...
    harqContext, "IsRetransmission", false));
if numel(tbsPerCodeword) > 1
    codingLayouts = sixgr.util.structGet(tx, "CodingLayouts", {});
    if ~iscell(codingLayouts)
        codingLayouts = num2cell(codingLayouts);
    end
    rateMatchedPerCodeword = cellfun(@(x) double( ...
        sixgr.util.structGet(x, "RateMatchedBitCount", NaN)), ...
        codingLayouts);
    rateMatchedPerCBPerCodeword = cellfun(@(x) double( ...
        sixgr.util.structGet(x, "E_r", [])), codingLayouts, ...
        "UniformOutput", false);
    softEvidencePerCodeword = localHARQEvidencePerCodeword( ...
        previousCombinedLLR, numel(tbsPerCodeword));
    groupMeta = struct( ...
        "Direction", char(upper(string(direction))), ...
        "Grant", grantSnapshot, ...
        "PHYGrant", sixgr.util.structGet( ...
            grantSnapshot, "PHYGrant", struct()), ...
        "CodingLayouts", {codingLayouts}, ...
        "PreviousContext", tbContext, ...
        "IsRetransmission", isRetransmission, ...
        "RateMatchedBitsTotalPerCodeword", ...
            double(rateMatchedPerCodeword), ...
        "RateMatchedBitsPerCBPerCodeword", ...
            {rateMatchedPerCBPerCodeword}, ...
        "TBSBitsPerCodeword", double(tbsPerCodeword), ...
        "ExpectedTBSBitsPerCodeword", double(sixgr.util.structGet( ...
            grantSnapshot, "TBSBitsPerCodeword", tbsPerCodeword)), ...
        "RVPerCodeword", double(rvPerCodeword), ...
        "RVSequence", rvSequence, ...
        "SoftCombiningEvidenceAvailablePerCodeword", ...
            logical(softEvidencePerCodeword));
    [tbContext, status] = ...
        sixgr.harq.validateCodewordTBContexts(groupMeta);
else
    meta = struct( ...
        "Direction", char(upper(string(direction))), ...
        "Grant", grantSnapshot, ...
        "PHYGrant", sixgr.util.structGet(grantSnapshot, "PHYGrant", struct()), ...
        "CodingLayout", sixgr.util.structGet(tx, "CodingLayout", struct()), ...
        "PreviousContext", tbContext, ...
        "TransportBlockContext", tbContext, ...
        "IsRetransmission", isRetransmission, ...
        "RateMatchedBitsTotal", double(rateMatchedBitsTotal), ...
        "RateMatchedBitsPerCB", double(rateMatchedBitsPerCB), ...
        "TBSBits", double(tbsPerCodeword), ...
        "ExpectedTBSBits", double(sixgr.util.structGet(grantSnapshot, "TBSBits", ...
            sixgr.util.structGet(grantSnapshot, "TransportBlockSize", NaN))), ...
        "RV", double(rvPerCodeword), ...
        "PreviousRV", double(sixgr.util.structGet(tbContext, "LastObservedRV", NaN)), ...
        "RVSequence", rvSequence, ...
        "SoftCombiningEvidenceAvailable", logical(softCombiningEvidence), ...
        "PreviousCombinedLLRAvailable", logical(softCombiningEvidence));
    [tbContext, status] = ...
        sixgr.harq.validateTBContextForTransmission(meta);
end
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
grantHarq.RV = double(currentRVForGroup);
grantHarq.IsRetransmission = isRetransmission;
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
harqContext.RV = double(currentRVForGroup);
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

if direction == "DL"
    pmi = double(sixgr.util.structGet(grant, "PMI", NaN));
    cri = double(sixgr.util.structGet(grant, "CRI", NaN));
    precodingMatrix = sixgr.util.structGet(grant, "PrecodingMatrix", []);
    useExplicitPrecoding = localGrantHasExplicitDLPrecoding(grant, precodingMatrix);
    if hasPHYGrant
        precodingMatrix = double(sixgr.util.structGet(phyGrant.PrecodingState, ...
            "MatrixLogicalPorts", phyGrant.PrecodingState.Matrix));
        useExplicitPrecoding = logical(phyGrant.PrecodingState.Active);
    end
    if isfinite(pmi)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", pmi);
    end
    if isfinite(cri)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", cri);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", cri);
    end
    if useExplicitPrecoding
        nPorts = localReplayPrecodingPortCount(precodingMatrix, numLayers);
        if hasPHYGrant
            nPorts = double(phyGrant.AntennaArchitecture.NumLogicalPorts);
        end
        logicalPorts = localResolveDLReplayLogicalPortCount(cfgOut, grant, numLayers);
        if nPorts > localMaxNRLogicalPDSCHPorts() && nPorts ~= logicalPorts
            precodingMatrix = localBuildDLReplayLogicalPrecoder(cfgOut, grant, numLayers, logicalPorts);
            nPorts = localReplayPrecodingPortCount(precodingMatrix, numLayers);
        end
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", precodingMatrix);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", precodingMatrix);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", precodingMatrix);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nPorts);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nPorts);
    else
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", []);
    end
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

function trace = localResolveDLHARQTrialTrace(cfg, grantSnapshot, harqContext, frameIdx, defaultIsRetransmission)
harq = sixgr.util.structGet(grantSnapshot, "HARQ", struct());
trace = struct( ...
    "HARQProcess", NaN, ...
    "HARQRound", NaN, ...
    "NDI", NaN, ...
    "RV", NaN, ...
    "IsRetransmission", logical(defaultIsRetransmission));

trace.HARQProcess = localFirstFiniteAnyScalar( ...
    sixgr.util.structGet(harq, "HarqID", NaN), ...
    sixgr.util.structGet(harq, "HARQProcess", NaN), ...
    sixgr.util.structGet(harq, "HARQProcessId", NaN), ...
    sixgr.util.structGet(grantSnapshot, "HarqID", NaN), ...
    sixgr.util.structGet(grantSnapshot, "HARQProcess", NaN), ...
    sixgr.util.structGet(grantSnapshot, "HARQProcessId", NaN), ...
    sixgr.util.structGet(harqContext, "HarqID", NaN), ...
    sixgr.util.structGet(harqContext, "HARQProcess", NaN), ...
    sixgr.util.structGet(harqContext, "HARQProcessId", NaN));
trace.RV = localFirstFiniteAnyScalar( ...
    sixgr.util.structGet(harq, "RV", NaN), ...
    sixgr.util.structGet(grantSnapshot, "RV", NaN), ...
    sixgr.util.structGet(harqContext, "RV", NaN));
trace.NDI = localFirstFiniteAnyScalar( ...
    sixgr.util.structGet(harq, "NDI", NaN), ...
    sixgr.util.structGet(grantSnapshot, "NDI", NaN), ...
    sixgr.util.structGet(harqContext, "NDI", NaN));
trace.HARQRound = localFirstFiniteAnyScalar( ...
    sixgr.util.structGet(harq, "HARQRound", NaN), ...
    sixgr.util.structGet(harq, "Round", NaN), ...
    sixgr.util.structGet(grantSnapshot, "HARQRound", NaN), ...
    sixgr.util.structGet(grantSnapshot, "Round", NaN), ...
    sixgr.util.structGet(harqContext, "HARQRound", NaN), ...
    sixgr.util.structGet(harqContext, "Round", NaN));
trace.IsRetransmission = logical(sixgr.util.structGet(harq, "IsRetransmission", ...
    sixgr.util.structGet(grantSnapshot, "IsRetransmission", ...
    sixgr.util.structGet(harqContext, "IsRetransmission", defaultIsRetransmission))));

harqEnabled = logical(sixgr.util.structGet(cfg, "phy.harq.enable", ...
    sixgr.util.structGet(cfg, "mac.harq.enable", false)));
if ~isfinite(trace.HARQProcess) && harqEnabled
    nProc = max(1, round(localFirstFiniteAnyScalar( ...
        sixgr.util.structGet(cfg, "phy.harq.nProcesses", NaN), ...
        sixgr.util.structGet(cfg, "mac.harq.numProcesses", NaN), ...
        sixgr.util.structGet(cfg, "pdsch6gr.HARQProcessCount", NaN), ...
        16)));
    trace.HARQProcess = mod(max(0, round(double(frameIdx)) - 1), nProc);
end
if ~isfinite(trace.HARQRound) && isfinite(trace.HARQProcess)
    trace.HARQRound = double(trace.IsRetransmission);
end
if ~isfinite(trace.NDI) && isfinite(trace.HARQProcess)
    trace.NDI = double(~trace.IsRetransmission);
end
end

function value = localFirstFiniteAnyScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if islogical(raw)
        raw = double(raw);
    elseif ~isnumeric(raw)
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

function nPorts = localReplayPrecodingPortCount(Wcfg, nLayers)
nPorts = 0;
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
sz = size(Wcfg);
if ndims(Wcfg) > 2 && sz(3) == 1
    Wcfg = squeeze(Wcfg);
    sz = size(Wcfg);
end
if ndims(Wcfg) > 2 || numel(sz) < 2
    return;
end
if sz(2) == nLayers
    nPorts = sz(1);
elseif sz(1) == nLayers
    nPorts = sz(2);
else
    nPorts = sz(1);
end
end

function nPorts = localResolveDLReplayLogicalPortCount(cfg, grant, nLayers)
nLayers = max(1, round(double(nLayers)));
configuredPorts = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.maxDLLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.nPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.nPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.NumAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", []), NaN);
if isfinite(configuredPorts)
    configuredPorts = max(nLayers, round(double(configuredPorts)));
    if configuredPorts <= localMaxNRLogicalPDSCHPorts()
        nPorts = configuredPorts;
        return;
    end
end
grantPorts = localFirstFiniteScalar( ...
    sixgr.util.structGet(grant, "NumLogicalPorts", []), ...
    sixgr.util.structGet(grant, "PortCount", []), NaN);
if isfinite(grantPorts) && grantPorts <= localMaxNRLogicalPDSCHPorts()
    nPorts = max(nLayers, round(double(grantPorts)));
    return;
end
nPorts = nLayers;
end

function nPorts = localMaxNRLogicalPDSCHPorts()
nPorts = 32;
end

function W = localBuildDLReplayLogicalPrecoder(cfg, grant, nLayers, nPorts)
nLayers = max(1, round(double(nLayers)));
nPorts = max(nLayers, round(double(nPorts)));
W = eye(nPorts, nLayers);
pmi = localFirstFiniteScalar( ...
    sixgr.util.structGet(grant, "AppliedPrecoderPMI", []), ...
    sixgr.util.structGet(grant, "PMI", []), ...
    sixgr.util.structGet(grant, "TPMI", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.PMI", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.pmi", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.TPMI", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.tpmi", []), NaN);
mode = string(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ...
    sixgr.util.structGet(grant, "PMICodebookMode", ...
    sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo"))));
if strlength(strtrim(mode)) == 0
    mode = "type1_su_mimo";
end
try
    [candidates, ~] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, nPorts, "Mode", mode);
    if isempty(candidates)
        return;
    end
    idx = 1;
    if isfinite(pmi)
        pmi0 = round(double(pmi));
        if pmi0 >= 0 && pmi0 < numel(candidates)
            idx = pmi0 + 1;
        end
    end
    Wcand = double(candidates(idx).W);
    if isequal(size(Wcand), [nPorts nLayers])
        W = Wcand;
    end
catch
    % The oversized replay matrix is element-domain metadata, not an NR
    % waveform port contract. Identity preserves the logical-layer path.
end
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

function localDLStageProgressLog(cfg, message, varargin)
enabled = logical(sixgr.util.structGet(cfg, "run.stageProgressLogging", false)) || ...
    localEnvLogical("SIXGR_VERBOSE_STAGE_LOG", false);
if ~enabled
    return;
end
try
    txt = sprintf(char(message), varargin{:});
catch
    txt = char(string(message));
end
fprintf("[%s] DL-PDSCH %s\n", char(sixgr.util.utcNowISO8601()), txt);
drawnow("limitrate");
end

function tf = localEnvLogical(name, defaultValue)
if nargin < 2
    defaultValue = false;
end
raw = strtrim(string(getenv(char(name))));
if strlength(raw) == 0
    tf = logical(defaultValue);
    return;
end
tf = any(lower(raw) == ["1", "true", "yes", "on"]);
end

function contract = localResolvePDSCHThroughputExecutionContract( ...
        cfg, options, schedulerDrivenGrant)
configuredPHY = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "phy.pdsch.executionProfile", ""))));
configuredRun = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "run.pdschExecutionProfile", ""))));
if strlength(configuredPHY) > 0 && strlength(configuredRun) > 0 ...
        && configuredPHY ~= configuredRun
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        ['phy.pdsch.executionProfile=''%s'' conflicts with ' ...
        'run.pdschExecutionProfile=''%s''.'], configuredPHY, configuredRun);
end
configured = configuredPHY;
if strlength(configured) == 0
    configured = configuredRun;
end
requested = lower(strtrim(string(options.ExecutionProfile)));
if strlength(requested) > 0 && strlength(configured) > 0 ...
        && requested ~= configured
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        "Requested PDSCH profile '%s' conflicts with configured '%s'.", ...
        requested, configured);
end
profile = requested;
if strlength(profile) == 0
    profile = configured;
end
if strlength(profile) == 0
    error("sixgr:pdsch:MissingExecutionProfile", ...
        ['runDLPDSCHThroughput requires an explicit PDSCH execution ' ...
        'profile. Use connected_strict/sps_strict/ra_si_strict with ' ...
        'decoded assignment ownership, or explicitly label an isolated ' ...
        'link campaign phy_calibration.']);
end
allowed = ["connected_strict","sps_strict","ra_si_strict", ...
    "scheduler_truth","phy_calibration"];
if ~any(profile == allowed)
    error("sixgr:pdsch:UnsupportedExecutionProfile", ...
        "Unsupported PDSCH execution profile '%s'.", profile);
end

strictProfiles = ["connected_strict","sps_strict","ra_si_strict"];
isStrict = any(profile == strictProfiles);
isSchedulerTruth = profile == "scheduler_truth";
if schedulerDrivenGrant
    if isStrict
        error("sixgr:pdsch:ConfiguredGrantNotAllowed", ...
            ['GrantSnapshot/PHYGrant cannot replace an immutable decoded ' ...
            'PDSCHSchedulingAssignment in %s.'], profile);
    end
    if ~isSchedulerTruth
        error("sixgr:pdsch:CalibrationSchedulerOwnershipForbidden", ...
            ['A scheduler/frozen grant cannot be relabeled as phy_calibration. ' ...
            'Use scheduler_truth only with decoded PDCCH binding evidence.']);
    end
elseif isSchedulerTruth
    error("sixgr:pdsch:MissingSchedulerTruthGrant", ...
        "scheduler_truth requires an exact scheduler grant with decoded PDCCH binding evidence.");
end

if isStrict
    localRequireStrictPDSCHThroughputInputs(options, profile);
    taxonomy = "strict_assignment_owned_pdsch";
    backend = "canonical_pdsch_compatibility_facades";
    calibrationProvenance = "";
elseif isSchedulerTruth
    localRequireSchedulerTruthInputs(options);
    taxonomy = "decoded_scheduler_grant_owned_pdsch";
    backend = "scheduler_grant_waveform_chain";
    calibrationProvenance = "";
else
    localRejectMixedCalibrationOwnership(options);
    taxonomy = "isolated_phy_calibration";
    backend = "legacy_pdsch_calibration_facades";
    calibrationProvenance = "explicit_phy_calibration_request";
end

contract = struct( ...
    "Profile", profile, ...
    "Taxonomy", taxonomy, ...
    "Backend", backend, ...
    "IsStrict", logical(isStrict), ...
    "CalibrationProvenance", calibrationProvenance);
end

function localRequireSchedulerTruthInputs(options)
grant = options.GrantSnapshot;
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    grant = sixgr.util.structGet(options.PHYGrant, ...
        "LegacyGrantSnapshot", struct());
end
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    error("sixgr:pdsch:MissingSchedulerTruthGrant", ...
        "scheduler_truth requires a nonempty exact scheduler grant.");
end
if ~logical(sixgr.util.structGet(grant, ...
        "ExactPHYFeasibilityChecked", false)) || ...
        ~logical(sixgr.util.structGet(grant, "ExactPHYFeasible", false))
    error("sixgr:pdsch:SchedulerTruthGrantNotFeasible", ...
        "scheduler_truth requires a finalized exactly feasible PHY grant.");
end
dci = sixgr.util.structGet(grant, "DCI", struct());
if ~(isstruct(dci) && ~isempty(fieldnames(dci)) && ...
        logical(sixgr.util.structGet(dci, "BitExactPDCCHPayload", false)))
    error("sixgr:pdsch:MissingSchedulerTruthDCI", ...
        "scheduler_truth requires the bit-exact DCI payload used by PDCCH.");
end
if options.PrepareOnly
    % TX validates the authored bit-exact DCI against the frozen allocation.
    % Successful UE control reception is still mandatory at completion.
    return;
end
if ~logical(sixgr.util.structGet(grant, "ControlDecodeOk", false)) || ...
        ~logical(sixgr.util.structGet(grant, ...
        "PDCCHGrantBindingOk", false))
    error("sixgr:pdsch:SchedulerTruthPDCCHBindingFailed", ...
        "scheduler_truth requires a successful PDCCH decode and grant binding.");
end
dciId = strtrim(string(sixgr.util.structGet(grant, ...
    "PDCCHGrantDCIId", "")));
dciHash = strtrim(string(sixgr.util.structGet(grant, ...
    "PDCCHGrantDCIFieldsHash", "")));
grantHash = strtrim(string(sixgr.util.structGet(grant, ...
    "PDCCHGrantFieldsHash", "")));
if strlength(dciId) < 1 || strlength(dciHash) < 1 || ...
        strlength(grantHash) < 1 || dciHash ~= grantHash
    error("sixgr:pdsch:SchedulerTruthPDCCHBindingIncomplete", ...
        "scheduler_truth requires matching nonempty decoded-DCI and scheduler-grant hashes.");
end
end

function localRequireStrictPDSCHThroughputInputs(options, profile)
if ~isa(options.Assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    error("sixgr:pdsch:MissingSchedulingAssignment", ...
        "%s throughput requires an immutable PDSCHSchedulingAssignment.", ...
        profile);
end
if options.Assignment.Profile ~= profile
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        "Assignment profile '%s' does not match requested '%s'.", ...
        options.Assignment.Profile, profile);
end
if ~isa(options.ResourcePlan, "sixgr.pdsch.PDSCHResourcePlan")
    error("sixgr:pdsch:MissingResourcePlan", ...
        "%s throughput requires an immutable PDSCHResourcePlan.", profile);
end
if ~isa(options.Carrier, "nrCarrierConfig")
    error("sixgr:pdsch:MissingCanonicalCarrier", ...
        "%s throughput requires an explicit nrCarrierConfig.", profile);
end
if ~isa(options.ReferenceSignalConfig, ...
        "sixgr.pdsch.PDSCHReferenceSignalConfig")
    error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
        "%s throughput requires an immutable " + ...
        "PDSCHReferenceSignalConfig.", ...
        profile);
end
if ~(isstruct(options.ReceiverConfig) ...
        && isscalar(options.ReceiverConfig) ...
        && ~isempty(fieldnames(options.ReceiverConfig)))
    error("sixgr:pdsch:IncompleteReceiverConfiguration", ...
        "%s throughput requires explicit receiver configuration.", profile);
end
if ~isa(options.PrecoderBundle, "sixgr.pdsch.PDSCHPrecoderBundle")
    error("sixgr:pdsch:MissingPrecoderTCIBinding", ...
        "%s throughput requires an immutable applied precoder bundle.", ...
        profile);
end
if ~(isstruct(options.IntegrationContext) ...
        && isscalar(options.IntegrationContext) ...
        && ~isempty(fieldnames(options.IntegrationContext)))
    error("sixgr:pdsch:MissingIntegrationContext", ...
        "%s throughput requires active BWP/CC/TCI integration context.", ...
        profile);
end
if isempty(options.TransportBlockBits)
    error("sixgr:pdsch:MissingTransportBlock", ...
        "%s throughput requires explicit transport block bits.", profile);
end
if round(double(options.NumFrames)) ~= 1
    error("sixgr:pdsch:StrictThroughputFrameCountUnsupported", ...
        ['One immutable PDSCHSchedulingAssignment owns one absolute-slot ' ...
        'occasion. Supply exactly NumFrames=1 per strict invocation.']);
end
if ~isempty(options.RV) || localStructHasFields(options.HARQContext) ...
        || ~isempty(options.PreviousCombinedLLR) ...
        || ~isempty(options.InitialLinkAdaptationState)
    error("sixgr:pdsch:LegacyOverrideNotAllowed", ...
        ['Strict assignment-owned throughput rejects configured RV, ' ...
        'legacy HARQ soft state, and link-adaptation overrides.']);
end
if ~isempty(options.InterferenceBundle)
    error("sixgr:pdsch:StrictInterferenceBundleUnsupported", ...
        ['The canonical strict throughput adapter does not accept legacy ' ...
        'sample-domain interference bundles.']);
end
if localStructHasFields(options.ChannelState)
    error("sixgr:pdsch:StrictExternalChannelStateUnsupported", ...
        ['The canonical strict throughput adapter owns its runtime channel ' ...
        'state and rejects a legacy ChannelState contract.']);
end
if ~isempty(options.LiveTrialCallback)
    error("sixgr:pdsch:StrictLiveCallbackUnsupported", ...
        "Canonical single-occasion strict throughput has no legacy live callback.");
end
if ~isempty(options.HARQManager) ...
        && ~isa(options.HARQManager, "sixgr.pdsch.PDSCHHARQManager")
    error("sixgr:pdsch:InvalidHARQManager", ...
        "HARQManager must be a sixgr.pdsch.PDSCHHARQManager.");
end

options.Assignment.validateForExecution();
assignmentPRB = double(options.Assignment.get( ...
    "PRBSetCarrierRelative"));
assignmentSymbols = double(options.Assignment.get("SymbolAllocation"));
if ~isequal(assignmentPRB(:).', options.ResourcePlan.PRBSet) ...
        || ~isequal(assignmentSymbols(:).', ...
        options.ResourcePlan.SymbolAllocation)
    error("sixgr:pdsch:ResourcePlanAssignmentMismatch", ...
        "Strict throughput assignment and resource plan do not agree.");
end
end

function localRejectMixedCalibrationOwnership(options)
strictObjectPresent = ~isempty(options.Assignment) ...
    || ~isempty(options.ResourcePlan) ...
    || ~isempty(options.Carrier) ...
    || localStructHasFields(options.ReferenceSignalConfig) ...
    || localStructHasFields(options.ReceiverConfig) ...
    || ~isempty(options.PrecoderBundle) ...
    || localStructHasFields(options.IntegrationContext) ...
    || ~isempty(options.HARQManager);
if strictObjectPresent
    error("sixgr:pdsch:MixedExecutionOwnership", ...
        ['phy_calibration legacy throughput cannot consume strict ' ...
        'assignment/resource/integration objects. Use the canonical ' ...
        'PDSCH calibration chain directly.']);
end
end

function tf = localStructHasFields(value)
tf = (isstruct(value) && isscalar(value) ...
    && ~isempty(fieldnames(value))) ...
    || isa(value, "sixgr.pdsch.PDSCHReferenceSignalConfig");
end

function T = localDecoratePDSCHExecutionContract(T, contract)
if ~(istable(T) && height(T) > 0)
    return;
end
n = height(T);
T.ExecutionProfile = repmat(string(contract.Profile), n, 1);
T.ExecutionTaxonomy = repmat(string(contract.Taxonomy), n, 1);
T.ExecutionBackend = repmat(string(contract.Backend), n, 1);
T.ApproximationMode = repmat("none", n, 1);
T.StrictSchedulingOwnership = repmat(logical(contract.IsStrict || ...
    string(contract.Profile) == "scheduler_truth"), n, 1);
T.ConnectedStrictCertified = false(n, 1);
T.CalibrationProvenance = repmat( ...
    string(contract.CalibrationProvenance), n, 1);
end

function out = localRunCanonicalStrictPDSCHPoint( ...
        cfg, options, contract, numFrames, snr_dB, ...
        startFrameIndex, startSlotIndex)
if numFrames ~= 1
    error("sixgr:pdsch:StrictThroughputFrameCountUnsupported", ...
        "Canonical strict throughput accepts one assignment occasion.");
end
seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) ...
    + double(startFrameIndex) - 1;
[cfg, ~] = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg, startSlotIndex);

txArgs = { ...
    "Carrier", options.Carrier, ...
    "TransportBlockBits", options.TransportBlockBits, ...
    "Assignment", options.Assignment, ...
    "ResourcePlan", options.ResourcePlan, ...
    "ReferenceSignalConfig", options.ReferenceSignalConfig, ...
    "PrecoderBundle", options.PrecoderBundle, ...
    "IntegrationContext", options.IntegrationContext, ...
    "ExecutionProfile", char(contract.Profile)};
[tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, txArgs{:});

[rxWaveform, gridNoiseVariance, channelEvidence, channelState] = ...
    localCanonicalStrictPDSCHChannel( ...
        cfg, tx, options.ReceiverConfig, snr_dB, seed);
receiverConfig = options.ReceiverConfig;
receiverConfig.NoiseVariance = double(gridNoiseVariance);
rxArgs = { ...
    "Carrier", options.Carrier, ...
    "Assignment", options.Assignment, ...
    "ResourcePlan", options.ResourcePlan, ...
    "ReferenceSignalConfig", options.ReferenceSignalConfig, ...
    "ReceiverConfig", receiverConfig, ...
    "CodingPlan", tx.CodingPlans, ...
    "CodingLayout", sixgr.util.structGet(tx, "CodingLayout", struct()), ...
    "CSIRSIndices", sixgr.util.structGet(tx, "CSIRSIndices", []), ...
    "CSIRSSymbols", sixgr.util.structGet(tx, "CSIRSSymbols", []), ...
    "CSIRSInfo", sixgr.util.structGet(tx, "CSIRSInfo", struct()), ...
    "CSIRSConfig", sixgr.util.structGet(tx, "CSIRS", []), ...
    "CSIRSScheduled", logical(sixgr.util.structGet( ...
        sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct()), ...
        "Scheduled", false)), ...
    "CSIRSTransmitted", logical(sixgr.util.structGet( ...
        sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct()), ...
        "Transmitted", false)), ...
    "PhysicalMeasurementWaveform", rxWaveform, ...
    "PhysicalMeasurementReferencePlane", ...
        "receiver_antenna_connector_pre_composite_front_end", ...
    "PhysicalMeasurementSource", ...
        "canonical_strict_pdsch_post_channel_noise_pre_rx_rf_adc", ...
    "PrecoderBundle", options.PrecoderBundle, ...
    "IntegrationContext", options.IntegrationContext, ...
    "ExecutionProfile", char(contract.Profile)};
if ~isempty(options.HARQManager)
    rxArgs = [rxArgs, {"HARQManager", options.HARQManager}]; %#ok<AGROW>
end
[rx, rxInfo] = sixgr.phy.dl.PDSCH_Rx(rxWaveform, cfg, rxArgs{:});

binding = localAssertCanonicalPDSCHBindingEvidence( ...
    tx, rx, options.Assignment);
[bitErrors, bitsCompared] = localStrictPDSCHBitErrors( ...
    options.TransportBlockBits, rx.TransportBlocks);
ber = double(bitErrors) / max(double(bitsCompared), 1);
bler = double(~logical(rx.CRCPass));
offeredBits = double(bitsCompared);
goodBits = offeredBits * double(logical(rx.CRCPass));
slotDurationSeconds = localSlotDuration(cfg);
throughputMbps = double(bitsCompared) / max(slotDurationSeconds, eps) / 1e6;
offeredMbps = offeredBits / max(slotDurationSeconds, eps) / 1e6;
goodputMbps = goodBits / max(slotDurationSeconds, eps) / 1e6;
postEqSINR = mean(double( ...
    rx.Metrics.MeasuredPostEqualizationSINRdBPerLayer), "omitnan");
evm = mean(double(rx.Metrics.EVMPerCodeword), "omitnan");
strictEvidenceOK = logical(tx.CanonicalDelegation) ...
    && logical(rx.CanonicalDelegation) ...
    && all(string(tx.StageTrace.Status) == "PASS") ...
    && all(string(rx.StageTrace.Status) == "PASS") ...
    && isfinite(postEqSINR) ...
    && all(cellfun(@(x) all(isfinite(double(x(:)))), ...
        rx.DescrambledLLR));
if ~strictEvidenceOK
    error("sixgr:pdsch:StrictCanonicalEvidenceIncomplete", ...
        "Canonical strict PDSCH TX/RX stage evidence is incomplete.");
end

assignmentId = string(options.Assignment.AssignmentId);
decodedDCIId = string(options.Assignment.get("DecodedDCIId"));
assignmentSource = string(options.Assignment.Source);
channelModel = string(channelEvidence.ChannelModel);
connectedStrictCertified = contract.Profile == "connected_strict";
T = table( ...
    double(startFrameIndex), double(startSlotIndex), double(snr_dB), ...
    assignmentId, decodedDCIId, assignmentSource, ...
    string(contract.Profile), string(contract.Taxonomy), ...
    string(contract.Backend), "none", true, ...
    connectedStrictCertified, "", ...
    true, true, string(binding.Status), ...
    channelModel, logical(channelEvidence.ChannelFadingApplied), ...
    double(seed), double(gridNoiseVariance), ...
    logical(rx.CRCPass), logical(~rx.CRCPass), ...
    double(bitErrors), double(bitsCompared), ber, bler, ...
    offeredBits, goodBits, throughputMbps, offeredMbps, goodputMbps, ...
    postEqSINR, evm, double(rx.Metrics.ChannelEstimateNMSE), ...
    string(rx.ChannelEstimationInfo.EngineUsed), ...
    strictEvidenceOK, strictEvidenceOK, ...
    "canonical_strict_assignment_truth", ...
    "explicit_pdsch_dlsch_production_chain", "PASS", ...
    'VariableNames', { ...
    'Frame','Slot','SNR_dB','AssignmentId','DecodedDCIId', ...
    'AssignmentSource','ExecutionProfile','ExecutionTaxonomy', ...
    'ExecutionBackend','ApproximationMode', ...
    'StrictSchedulingOwnership','ConnectedStrictCertified', ...
    'CalibrationProvenance','CanonicalTXDelegation', ...
    'CanonicalRXDelegation','IntegrationBindingStatus', ...
    'ChannelModel','ChannelFadingApplied','Seed', ...
    'GridNoiseVariance','CRCPass','CRCError','BitErrors', ...
    'BitsCompared','BER','BLER','OfferedBits','GoodBits', ...
    'Throughput_Mbps','OfferedThroughput_Mbps','Goodput_Mbps', ...
    'PostEqSINRWidebanddB','EVM_rms','ChannelEstimateNMSE', ...
    'ChannelEstimateSource','StrictReceiverEvidenceOk', ...
    'StrictOk','TruthStatus','Source','Status'});

out = struct();
out.Ok = true;
out.Skipped = false;
out.BER = ber;
out.BLER = bler;
out.Throughput_Mbps = throughputMbps;
out.Goodput_Mbps = goodputMbps;
out.OfferedThroughput_Mbps = offeredMbps;
out.EVM_rms = evm;
out.Notes = "Canonical strict assignment-owned PDSCH occasion executed.";
out.NumFrames = 1;
out.SNR_dB = double(snr_dB);
out.CodeBlockBLER = bler;
out.CBGBLER = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceTTI_ms = slotDurationSeconds * 1e3;
out.DecodeLatency_ms = NaN;
out.EarlyStopRate = NaN;
out.DecoderComplexityUnits = NaN;
out.NormalizedDecoderComplexity = NaN;
out.AreaEfficiencyProxy = NaN;
out.TrialTable = T;
txCSIEvent = sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct());
rxCSIObservation = sixgr.util.structGet(rx, "CSIRSObservation", struct());
csiRuntimeObserved = logical(sixgr.util.structGet(txCSIEvent, "Scheduled", false)) || ...
    logical(sixgr.util.structGet(txCSIEvent, "Transmitted", false)) || ...
    logical(sixgr.util.structGet(rxCSIObservation, "Observed", false));
if csiRuntimeObserved
    csiMetrics = localAnalyzeChannelMetrics( ...
        sixgr.util.structGet(rx, "ChannelEstimate", []), ...
        double(gridNoiseVariance), cfg, rx, options.PrecoderBundle);
    csiRow = localBuildCSIRSRuntimeTrialRow(cfg, ...
        localStrictGrantSnapshot(options), tx, rx, csiMetrics, ...
        startFrameIndex, startSlotIndex, snr_dB, slotDurationSeconds);
    if logical(csiRow.RuntimeEventObserved)
        out.CSIRSTrialTable = struct2table(csiRow);
    else
        out.CSIRSTrialTable = table();
    end
else
    out.CSIRSTrialTable = table();
end
out.ConstellationSamples = table();
out.SignalDiagnostic = struct( ...
    "Available", false, ...
    "Reason", "canonical_strict_point_does_not_export_legacy_preview", ...
    "Direction", "DL", ...
    "SnapshotID", assignmentId, ...
    "Metadata", struct("AssignmentId", assignmentId), ...
    "SourceTable", table());
out.HARQ = rx.HARQResults;
out.ChannelState = channelState;
out.ChannelEvidence = channelEvidence;
out.StartFrameIndex = double(startFrameIndex);
out.StartSlotIndex = double(startSlotIndex);
out.EndFrameIndex = double(startFrameIndex);
out.EndSlotIndex = double(startSlotIndex);
out.ExecutionProfile = contract.Profile;
out.ExecutionTaxonomy = contract.Taxonomy;
out.ExecutionBackend = contract.Backend;
out.ApproximationMode = "none";
out.StrictSchedulingOwnership = true;
out.ConnectedStrictCertified = connectedStrictCertified;
out.CalibrationProvenance = "";
out.AssignmentId = assignmentId;
out.AssignmentValidationDigest = options.Assignment.validateForExecution();
out.IntegrationBinding = binding;
out.TX = tx;
out.RX = rx;
out.TXInfo = txInfo;
out.RXInfo = rxInfo;
out.DLPDSCHObjective = struct( ...
    "ObjectivePass", NaN, ...
    "EvaluationStatus", ...
    "not_evaluated_by_legacy_multi_frame_objective");
out.PDSCHObjectiveSummary = table();
out.PDSCHObjectiveFailures = table();
end

function grantSnapshot = localStrictGrantSnapshot(options)
grantSnapshot = struct();
if isfield(options, "IntegrationContext") && isstruct(options.IntegrationContext)
    grantSnapshot = sixgr.util.structGet(options.IntegrationContext, ...
        "GrantSnapshot", grantSnapshot);
end
if isempty(fieldnames(grantSnapshot)) && isfield(options, "Assignment") && ...
        isa(options.Assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    grantSnapshot = options.Assignment.toStruct();
end
end

function [waveform, gridNoise, evidence, state] = ...
        localCanonicalStrictPDSCHChannel( ...
        cfg, tx, receiverConfig, snr_dB, seed)
if ~(isstruct(receiverConfig) && isscalar(receiverConfig) ...
        && isfield(receiverConfig, "ChannelModel") ...
        && isfield(receiverConfig, "NPhysicalRxAntennas"))
    error("sixgr:pdsch:IncompleteReceiverConfiguration", ...
        "Strict receiver configuration requires channel and RX-port state.");
end
model = upper(strtrim(string(receiverConfig.ChannelModel)));
nRx = double(receiverConfig.NPhysicalRxAntennas);
if model == "AWGN"
    if nRx ~= size(tx.Waveform, 2)
        error("sixgr:pdsch:AWGNReceivePortCountMismatch", ...
            ['AWGN strict throughput requires NPhysicalRxAntennas=%d to ' ...
            'equal the transmitted physical-port count %d.'], ...
            nRx, size(tx.Waveform, 2));
    end
    waveform = tx.Waveform;
    state = struct( ...
        "ContractVersion", "CanonicalStrictAWGN/v1", ...
        "ChannelModel", "AWGN");
    fadingApplied = false;
    channelClass = "identity_awgn";
elseif startsWith(model, "TDL-") || startsWith(model, "CDL-")
    cfgChannel = localCanonicalStrictChannelConfig(cfg, model);
    state = sixgr.channel.ChannelFactory.createRuntimeChannelState( ...
        cfgChannel, "DL", ...
        "LinkKey", "pdsch_strict_" + string(tx.Assignment.AssignmentId), ...
        "Seed", double(seed));
    state = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        state, cfgChannel, tx.Waveform, ...
        struct("OFDM", tx.OFDMInfo), ...
        "NumTxAnt", double(tx.NPhysicalTxAntennas), ...
        "NumRxAnt", nRx);
    [waveform, replay] = ...
        sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
        state, tx.Waveform);
    fadingApplied = logical(sixgr.util.structGet( ...
        replay, "ChannelFadingApplied", false));
    channelClass = string(sixgr.util.structGet( ...
        replay, "ChannelFadingObjectClass", ""));
    if ~fadingApplied || isempty(waveform) || size(waveform, 2) ~= nRx
        error("sixgr:pdsch:StrictFadingChannelNotApplied", ...
            "Concrete %s did not produce the requested receive waveform.", ...
            model);
    end
else
    error("sixgr:pdsch:UnsupportedStrictChannelProfile", ...
        ['Strict canonical throughput requires AWGN or a concrete ' ...
        'TDL-*/CDL-* profile, not ''%s''.'], model);
end

signalPower = mean(abs(waveform(:)).^2);
if isinf(snr_dB) && snr_dB > 0
    timeNoise = 0;
else
    timeNoise = signalPower / 10^(double(snr_dB) / 10);
end
if ~(isfinite(timeNoise) && timeNoise >= 0)
    error("sixgr:pdsch:InvalidStrictNoiseVariance", ...
        "Strict PDSCH channel produced invalid time-domain noise variance.");
end
rng(localRNGSeed(seed), "twister");
if timeNoise > 0
    noise = sqrt(timeNoise / 2) .* complex( ...
        randn(size(waveform), "like", real(waveform)), ...
        randn(size(waveform), "like", real(waveform)));
    waveform = waveform + cast(noise, "like", waveform);
end
gain = double(tx.OFDMInfo.SampleToGridNoiseVarianceGain);
gridNoise = timeNoise * gain;
if ~(isfinite(gridNoise) && gridNoise >= 0)
    error("sixgr:pdsch:InvalidStrictNoiseVariance", ...
        "Strict PDSCH channel produced invalid grid-domain noise variance.");
end
evidence = struct( ...
    "ChannelModel", model, ...
    "ChannelFadingApplied", logical(fadingApplied), ...
    "ChannelObjectClass", channelClass, ...
    "Seed", double(seed), ...
    "SignalPowerBeforeNoise", double(signalPower), ...
    "TimeNoiseVariance", double(timeNoise), ...
    "GridNoiseVariance", double(gridNoise), ...
    "SNRdB", double(snr_dB), ...
    "Source", "canonical_strict_runtime_channel");
end

function cfg = localCanonicalStrictChannelConfig(cfg, model)
cfg = sixgr.util.structSet(cfg, "channel.model", char(model));
cfg = sixgr.util.structSet(cfg, "channel.awgnOnly", false);
if startsWith(model, "TDL-")
    cfg = sixgr.util.structSet(cfg, "channel.tdlProfile", char(model));
    cfg = sixgr.util.structSet(cfg, "channel.fading.model", "TDL");
    cfg = sixgr.util.structSet( ...
        cfg, "channel.fading.profile", char(model));
else
    cfg = sixgr.util.structSet(cfg, "channel.cdlProfile", char(model));
    cfg = sixgr.util.structSet(cfg, "channel.fading.model", "CDL");
    cfg = sixgr.util.structSet( ...
        cfg, "channel.fading.profile", char(model));
end
end

function binding = localAssertCanonicalPDSCHBindingEvidence( ...
        tx, rx, assignment)
if ~isfield(tx, "IntegrationBinding") ...
        || ~isstruct(tx.IntegrationBinding) ...
        || isempty(fieldnames(tx.IntegrationBinding)) ...
        || ~isfield(rx, "IntegrationBinding") ...
        || ~isstruct(rx.IntegrationBinding) ...
        || isempty(fieldnames(rx.IntegrationBinding))
    error("sixgr:pdsch:MissingIntegrationBindingEvidence", ...
        ['Canonical strict TX and RX must both retain the integration ' ...
        'binding created at their trust boundaries.']);
end
txBinding = tx.IntegrationBinding;
rxBinding = rx.IntegrationBinding;
if string(txBinding.AssignmentId) ~= assignment.AssignmentId ...
        || string(rxBinding.AssignmentId) ~= assignment.AssignmentId
    error("sixgr:pdsch:IntegrationBindingMismatch", ...
        "Canonical TX/RX integration binding belongs to another assignment.");
end
if ~isfield(txBinding, "Status") || ~isfield(rxBinding, "Status") ...
        || string(txBinding.Status) ~= "PASS" ...
        || string(rxBinding.Status) ~= "PASS"
    error("sixgr:pdsch:IntegrationBindingMismatch", ...
        "Canonical TX/RX integration binding did not pass validation.");
end
binding = txBinding;
end

function [errors, compared] = localStrictPDSCHBitErrors( ...
        transmitted, received)
if iscell(transmitted)
    transmitted = reshape(transmitted, 1, []);
else
    transmitted = {transmitted};
end
if iscell(received)
    received = reshape(received, 1, []);
else
    received = {received};
end
if numel(transmitted) ~= numel(received)
    error("sixgr:pdsch:StrictDecodedCodewordCountMismatch", ...
        "Decoded codeword count differs from the transmitted count.");
end
errors = 0;
compared = 0;
for index = 1:numel(transmitted)
    txBits = int8(transmitted{index}(:));
    rxBits = int8(received{index}(:));
    common = min(numel(txBits), numel(rxBits));
    errors = errors + nnz(txBits(1:common) ~= rxBits(1:common)) ...
        + abs(numel(txBits) - numel(rxBits));
    compared = compared + max(numel(txBits), numel(rxBits));
end
end

function value = localScalarLogicalGrantField(grant, fieldName, defaultValue)
raw = sixgr.util.structGet(grant, fieldName, defaultValue);
validLogical = islogical(raw) && isscalar(raw);
validNumeric = isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
    isfinite(double(raw)) && any(double(raw) == [0 1]);
if ~(validLogical || validNumeric)
    error("sixgr:link:InvalidGrantLineage", ...
        "DL grant field %s must be a scalar logical authority, received class %s with %d elements.", ...
        string(fieldName), string(class(raw)), numel(raw));
end
value = logical(raw);
end
