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
p.addParameter("PreviousCombinedLLR", [], @(x) isempty(x) || isnumeric(x));
p.addParameter("InterferenceBundle", struct([]), @(x) isempty(x) || isstruct(x));
p.addParameter("ExpectedUCIBits", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
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
previousCombinedLLR = p.Results.PreviousCombinedLLR;
interferenceBundle = p.Results.InterferenceBundle;
isRetransmission = logical(sixgr.util.structGet(harqContext, "IsRetransmission", false));
if ~(isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride)))
    grantSnapshotOverride = sixgr.util.structGet(harqContext, "GrantSnapshot", struct());
end
schedulerDrivenGrant = isstruct(grantSnapshotOverride) && ~isempty(fieldnames(grantSnapshotOverride));
expectedUCIBits = localResolveExpectedUCIBits(p.Results.ExpectedUCIBits, grantSnapshotOverride, harqContext);

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
out.ConstellationSamples = table();
out.HARQ = struct();

if ~logical(sixgr.util.structGet(cfg, "phy.pusch.enable", true))
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

profScope = sixgr.perf.TimeProfiler.scope("sixgr.link.runULPUSCHThroughput", ...
    "Stage", "ul_pusch", ...
    "Metadata", struct( ...
    "NumFrames", double(numFrames), ...
    "NSubcarriers", double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)) * 12, ...
    "NSymbols", 14, ...
    "NRx", double(sixgr.util.structGet(cfg, "channel.nRxAnt", 1)), ...
    "NTx", double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1)), ...
    "NLayers", double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))); %#ok<NASGU>

cfgUL = cfg;

blockErr = 0;
bitErr = 0;
bitTot = 0;
bitGood = 0;
frameCrash = 0;
firstCrashMsg = "";
chState = struct("Initialized", false, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0, "WarmupSamples", 0);
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
trialSFN = trialFrame;
trialUEIndex = NaN(numFrames,1);
trialRNTI = NaN(numFrames,1);
trialBaseStationID = NaN(numFrames,1);
trialMCS = NaN(numFrames,1);
trialPRB = NaN(numFrames,1);
trialPRBStart = NaN(numFrames,1);
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
trialOLLADeltaMCS = NaN(numFrames,1);
trialOLLAUpdateCount = NaN(numFrames,1);
trialOLLAState = strings(numFrames,1);
trialCQITable = strings(numFrames,1);
trialMCSTable = strings(numFrames,1);
trialCQIDerivedModulation = strings(numFrames,1);
trialPMIType = strings(numFrames,1);
trialPMICodebookMode = strings(numFrames,1);
trialCSIReportMode = strings(numFrames,1);
trialCSIPayloadBits = NaN(numFrames,1);
trialCSIPayloadHex = strings(numFrames,1);
trialGain = NaN(numFrames,1);
trialNoise = NaN(numFrames,1);
trialNoiseVarStatus = strings(numFrames,1);
trialNoiseVarSource = strings(numFrames,1);
trialNoiseVarReason = strings(numFrames,1);
trialNoiseVarStrictFailure = false(numFrames,1);
trialUCIOnPUSCHApplied = false(numFrames,1);
trialUCIOnPUSCHSource = strings(numFrames,1);
trialHARQACKBitCount = zeros(numFrames,1);
trialHARQACKContentMatch = false(numFrames,1);
trialHARQACKDecodeStatus = strings(numFrames,1);
trialHARQACKDecodeReason = strings(numFrames,1);
trialEqualizerType = strings(numFrames,1);
trialEqualizerRequestedType = strings(numFrames,1);
trialEqualizerEngine = strings(numFrames,1);
trialInterferenceCovarianceAvailable = false(numFrames,1);
trialInterferenceCovarianceSource = strings(numFrames,1);
trialInterferenceCovarianceStatus = strings(numFrames,1);
trialReceiverUsable = false(numFrames,1);
trialDecodeAttempted = false(numFrames,1);
trialDecodeUsable = false(numFrames,1);
trialFailureReason = strings(numFrames,1);
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
trialAppliedPrecoderPMIType = strings(numFrames,1);
trialAppliedPrecoderCodebookMode = strings(numFrames,1);
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
trialOfferedThr = NaN(numFrames,1);
trialGoodput = NaN(numFrames,1);
trialComputeLatency = NaN(numFrames,1);
trialProcedureDelay = NaN(numFrames,1);
trialAirInterfaceTTI = slotDur_s * 1e3 * ones(numFrames,1);
trialAirInterfaceObservation = slotDur_s * 1e3 * ones(numFrames,1);
trialLatency = NaN(numFrames,1);
trialDecodeLatency = NaN(numFrames,1);
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
trialGrantControlState = strings(numFrames,1);
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
trialRuntimeEvidence = cell(numFrames,1);
trialStatus = strings(numFrames,1);
trialStatus(:) = "FAIL";
trialCrash = false(numFrames,1);
trialLAApplied = false(numFrames,1);
trialLAScheduled = false(numFrames,1);
trialNotes = strings(numFrames,1);
trialChan = repmat(chanModel, numFrames, 1);
trialDopp = dopplerHz * ones(numFrames,1);
liveCallbackWarned = false;
lastHARQ = struct();

for n = 1:numFrames
    frameIdx = double(trialFrame(n));
    trialSeed(n) = seedBase + frameIdx - 1;
    rng(localRNGSeed(trialSeed(n)), 'twister');
    try
        if isRetransmission || schedulerDrivenGrant
            cfgFrame = cfgDyn;
            trialLAApplied(n) = false;
        else
            [cfgDyn, laState, laApplyEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "UL", frameIdx, "Phase", "before");
            cfgFrame = cfgDyn;
            trialLAApplied(n) = logical(laApplyEvent.Applied);
        end
        cfgFrame = localApplyReplayGrantConfig(cfgFrame, grantSnapshotOverride, "UL");
        trialMCS(n) = double(sixgr.util.structGet(cfgFrame, "phy.pusch.mcsIndex", NaN));
        trialModulation(n) = string(sixgr.util.structGet(cfgFrame, "phy.pusch.modulation", ""));
        trialCodeRate(n) = double(sixgr.util.structGet(cfgFrame, "phy.pusch.codeRate", NaN));
        trialLinkAdaptationMode(n) = string(localResolveLinkAdaptationMode(cfgFrame, "UL"));
        trialActualMCSSelectionMode(n) = string(localResolveActualMCSSelectionMode(cfgFrame, "UL"));
        trialSchedulerGrantMCSSelectionMode(n) = string(sixgr.util.structGet(grantSnapshotOverride, "AMCMode", ""));
        grantCQIUsed = double(sixgr.util.structGet(grantSnapshotOverride, "CQIUsed", NaN));
        if schedulerDrivenGrant
            trialLinkAdaptationMode(n) = "scheduler_grant_replay";
            trialActualMCSSelectionMode(n) = "scheduler_grant";
        end
        trialCQITable(n) = string(localResolveCQITable(cfgFrame, "UL"));
        trialMCSTable(n) = string(localResolveMCSTable(cfgFrame, "UL"));
        trialCfgPMI(n) = double(sixgr.util.structGet(cfgFrame, "phy.pusch.PMI", NaN));
        trialCfgCRI(n) = double(sixgr.util.structGet(cfgFrame, "phy.beamManagement.selectedCRI", NaN));
        trialConfiguredBeamSelectionStrategy(n) = string(sixgr.util.structGet(cfgFrame, "lls6g.userContext.BeamSelectionStrategy", ""));
        if isRetransmission
            [trialMCS(n), trialModulation(n), trialCodeRate(n)] = localOverrideReportedGrantFields( ...
                trialMCS(n), trialModulation(n), trialCodeRate(n), grantSnapshotOverride);
        end

        txArgs = {};
        txArgs = localAppendGrantReplayTxArgs(txArgs, grantSnapshotOverride);
        if ~isempty(transportBlockBits)
            localAssertReplayTBConsistency(transportBlockBits, grantSnapshotOverride, "UL");
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        if ~isempty(rvOverride)
            txArgs = [txArgs {"RV", rvOverride}]; %#ok<AGROW>
        end
        if ~isempty(expectedUCIBits)
            txArgs = [txArgs {"HARQACKBits", expectedUCIBits}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfgFrame, txArgs{:});
        grantSnapshot = localBuildHARQGrantSnapshot(tx, trialMCS(n), cfgFrame, grantSnapshotOverride);
        trialOuterLoopEnabled(n) = logical(sixgr.util.structGet(grantSnapshot, "OuterLoopEnabled", false));
        trialOuterLoopAppliedFromGrant(n) = logical(sixgr.util.structGet(grantSnapshot, "OuterLoopApplied", false));
        trialOLLADeltaMCS(n) = double(sixgr.util.structGet(grantSnapshot, "OLLADeltaMCS", NaN));
        trialOLLAUpdateCount(n) = double(sixgr.util.structGet(grantSnapshot, "OLLAUpdateCount", NaN));
        trialOLLAState(n) = string(sixgr.util.structGet(grantSnapshot, "OLLAState", ""));
        trialPBCHGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "PBCHGatingActive", false));
        trialPRACHGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "PRACHGatingActive", false));
        trialPDCCHGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "PDCCHGatingActive", false));
        trialSRSGatingActive(n) = logical(sixgr.util.structGet(grantSnapshot, "SRSGatingActive", false));
        trialControlEligible(n) = logical(sixgr.util.structGet(grantSnapshot, "ControlEligible", false));
        trialControlDecodeOk(n) = logical(sixgr.util.structGet(grantSnapshot, "ControlDecodeOk", false));
        trialGrantControlState(n) = string(sixgr.util.structGet(grantSnapshot, "GrantControlState", ""));
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
        ulPrecoding = localResolveULPrecodingTrace(cfgFrame, tx, grantSnapshot);
        trialPrecoderSource(n) = string(ulPrecoding.PrecoderSource);
        trialPrecodingMode(n) = string(ulPrecoding.PrecodingMode);
        trialPrecodingApplicationStage(n) = string(ulPrecoding.PrecodingApplicationStage);
        trialPrecodingActive(n) = logical(ulPrecoding.PrecodingActive);
        trialExplicitBeamWeightsApplied(n) = logical(ulPrecoding.ExplicitBeamWeightsApplied);
        trialTransformPrecodingApplied(n) = logical(ulPrecoding.TransformPrecodingApplied);
        trialBeamformingApplied(n) = logical(ulPrecoding.BeamformingApplied);
        trialAppliedBeamIndexSet(n) = string(ulPrecoding.AppliedBeamIndexSet);
        trialAppliedPrecoderPMI(n) = double(ulPrecoding.AppliedPrecoderPMI);
        trialAppliedPrecoderPMIType(n) = string(ulPrecoding.AppliedPrecoderPMIType);
        trialAppliedPrecoderCodebookMode(n) = string(ulPrecoding.AppliedPrecoderCodebookMode);
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
        if ~chState.Initialized
            chState = localInitChannelState(cfgFrame, tx, txInfo, snr_dB, trialSeed(n));
        end
        useIdealTimingSync = localUseIdealTimingSync(cfgFrame);
        [txWaveformPC, powerCtrl, cfgFrameRx] = localApplyPUSCHOpenLoopPowerControl(tx.Waveform, cfgFrame, tx, grantSnapshot);
        tx.Waveform = txWaveformPC;
        trialPUSCHPowerControlEnabled(n) = logical(powerCtrl.Enabled);
        trialPUSCHPowerControlStatus(n) = string(powerCtrl.Status);
        trialPUSCHTxPower(n) = double(powerCtrl.TxPower_dBm);
        trialPUSCHPcmax(n) = double(powerCtrl.Pcmax_dBm);
        trialPUSCHPowerHeadroom(n) = double(powerCtrl.PowerHeadroom_dB);
        trialPUSCHPowerScale(n) = double(powerCtrl.AmplitudeScale);
        trialPUSCHPowerControlPathloss(n) = double(powerCtrl.Pathloss_dB);
        [rxWave, replay] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState, cfgFrameRx, tx, txInfo, interferenceBundle);

        rxArgs = {"Carrier", tx.Carrier, ...
            "PUSCH", tx.PUSCH, ...
            "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "SkipTimingEstimate", useIdealTimingSync};
        if ~isempty(expectedUCIBits)
            rxArgs = [rxArgs {"ExpectedHARQACKBits", expectedUCIBits}]; %#ok<AGROW>
        end
        injectedNoiseVariance = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
        if isfinite(injectedNoiseVariance) && injectedNoiseVariance >= 0
            rxArgs = [rxArgs {"NoiseVar", injectedNoiseVariance, "NoiseVarDomain", "time"}]; %#ok<AGROW>
        end
        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgFrame, rxArgs{:});
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
        trialNoiseVarStatus(n) = string(sixgr.util.structGet(rx, "NoiseVarStatus", ""));
        trialNoiseVarSource(n) = string(sixgr.util.structGet(rx, "NoiseVarSource", ""));
        trialNoiseVarReason(n) = string(sixgr.util.structGet(rx, "NoiseVarReason", ""));
        trialNoiseVarStrictFailure(n) = logical(sixgr.util.structGet(rx, "NoiseVarStrictFailure", false));
        trialUCIOnPUSCHApplied(n) = logical(sixgr.util.structGet(rx, "UCIOnPUSCHApplied", false));
        trialUCIOnPUSCHSource(n) = string(sixgr.util.structGet(rx, "UCIOnPUSCHSource", ""));
        trialHARQACKBitCount(n) = double(sixgr.util.structGet(rx, "HARQACKBitCount", numel(expectedUCIBits)));
        trialHARQACKContentMatch(n) = logical(sixgr.util.structGet(rx, "HARQACKContentMatch", false));
        trialHARQACKDecodeStatus(n) = string(sixgr.util.structGet(rx, "HARQACKDecodeStatus", ""));
        trialHARQACKDecodeReason(n) = string(sixgr.util.structGet(rx, "HARQACKDecodeReason", ""));
        trialEqualizerType(n) = string(sixgr.util.structGet(rx, "EqualizerType", ""));
        trialEqualizerRequestedType(n) = string(sixgr.util.structGet(rx, "EqualizerRequestedType", ""));
        trialEqualizerEngine(n) = string(sixgr.util.structGet(rx, "EqualizerEngine", ""));
        trialInterferenceCovarianceAvailable(n) = logical(sixgr.util.structGet(rx, "InterferenceCovarianceAvailable", false));
        trialInterferenceCovarianceSource(n) = string(sixgr.util.structGet(rx, "InterferenceCovarianceSource", ""));
        trialInterferenceCovarianceStatus(n) = string(sixgr.util.structGet(rx, "InterferenceCovarianceStatus", ""));
        trialReceiverUsable(n) = logical(sixgr.util.structGet(rx, "ReceiverUsable", false));
        trialDecodeAttempted(n) = logical(sixgr.util.structGet(rx, "DecodeAttempted", false));
        trialDecodeUsable(n) = logical(sixgr.util.structGet(rx, "DecodeUsable", false));
        trialFailureReason(n) = string(sixgr.util.structGet(rx, "FailureReason", ""));
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
        trialRuntimeEvidence{n} = localBuildRuntimeAntennaTimingEvidence("UL", cfgFrame, grantSnapshot, tx, txInfo, chState, replay);
        if ~trialDecodeUsable(n)
            blockErr = blockErr + 1;
            trialStatus(n) = "NA";
            trialCRC(n) = NaN;
            if strlength(strtrim(trialFailureReason(n))) == 0
                trialFailureReason(n) = "ul_noise_variance_unavailable";
            end
            trialNotes(n) = "PUSCH decode unavailable: " + trialFailureReason(n);
            trialGoodBits(n) = NaN;
            trialGoodput(n) = NaN;
            lastHARQ = struct( ...
                "TransportBlockBits", int8(tx.TransportBlock(:)), ...
                "CombinedLLR", previousCombinedLLR, ...
                "CurrentDecodeOK", false, ...
                "CombinedDecodeOK", false, ...
                "DecoderIterations", NaN, ...
                "GrantSnapshot", grantSnapshot, ...
                "Context", harqContext);
            continue;
        end
        pilotTrack = localPilotTrackingMetrics(rx);
        metrics = localAnalyzeChannelMetrics(sixgr.util.structGet(rx, "ChannelEstimate", []), trialNoise(n), cfgFrame, rx, ulPrecoding);
        trialNMSE(n) = metrics.NMSE_dB;
        trialDet(n) = metrics.DetectionMetric;
        selectedSINR = localSelectULMeasuredTrialSINRFromEvidence( ...
            trialPostEqSINR(n), trialPostEqSINRSource(n), trialPostEqSINRValueRole(n), ...
            trialPostEqSINRValueStatus(n), trialPostEqSINRNAReason(n), ...
            trialReceiverHestSINR(n), trialReceiverHestSINRSource(n), trialReceiverHestSINRValueRole(n), ...
            trialReceiverHestSINRValueStatus(n), trialReceiverHestSINRNAReason(n));
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
        trialCSIRSRP(n) = metrics.CSI_RSRP_dB;
        trialCSIRSRPSource(n) = string(metrics.CSI_RSRPSource);
        trialCSIRSSI(n) = metrics.CSI_RSSI_dB;
        trialCSIRSSISource(n) = string(metrics.CSI_RSSISource);
        trialCSIRSRQ(n) = metrics.CSI_RSRQ_dB;
        trialCSIRSRQSource(n) = string(metrics.CSI_RSRQSource);
        rawMeasuredCQI = double(sixgr.util.structGet(metrics, "CQI", NaN));
        if isfinite(rawMeasuredCQI)
            trialCQI(n) = double(sixgr.util.normalizeReportedCQI(rawMeasuredCQI));
        else
            trialCQI(n) = NaN;
        end
        if isfinite(trialCQI(n))
            trialCQISource(n) = string(sixgr.util.structGet(metrics, "CQISource", "ul_link_state_reference_signal_cqi"));
            if strlength(strtrim(trialCQISource(n))) == 0
                trialCQISource(n) = "ul_link_state_reference_signal_cqi";
            end
        end
        if schedulerDrivenGrant && ~isfinite(trialCQI(n))
            trialCQISource(n) = "current_receiver_cqi_unavailable_no_scheduler_grant_backfill";
        end
        trialRI(n) = metrics.RI;
        trialPMI(n) = metrics.PMI;
        trialCRI(n) = metrics.CRI;
        trialPMIType(n) = string(metrics.PMIType);
        trialPMICodebookMode(n) = string(metrics.PMICodebookMode);
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
        trialProcedureDelay(n) = double(sixgr.util.structGet(coding, "ProcedureDelay_ms", NaN));
        if ~isfinite(trialProcedureDelay(n))
            % The pure link-level UL PHY chain executes within the same grant observation.
            % When no extra procedure delay is instrumented, the truthful residual is zero.
            trialProcedureDelay(n) = 0;
        end
        % The generic Latency_ms alias stays unavailable in new exports.
        trialLatency(n) = NaN;
        trialDecodeLatency(n) = double(sixgr.util.structGet(coding, "DecodeLatency_ms", NaN));
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
        trialDMRSRECount(n) = double(sixgr.util.structGet(modTrack, "DMRSRECount", NaN));
        trialPTRSRECount(n) = double(sixgr.util.structGet(modTrack, "PTRSRECount", NaN));
        trialRSOverhead(n) = double(sixgr.util.structGet(modTrack, "RSOverheadFraction", NaN));
        trialEstDoppler(n) = double(sixgr.util.structGet(modTrack, "EstimatedDopplerHz", NaN));
        trialDopplerErr(n) = trialEstDoppler(n) - dopplerHz;
        trialPhaseTrackErr(n) = double(sixgr.util.structGet(modTrack, "PhaseTrackingError_deg", NaN));
        trialQCL(n) = double(sixgr.util.structGet(modTrack, "QCLAccuracy", NaN));
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
            constT.Normalization = repmat("post_equalized_and_reference_unit_power_constellation", nConst, 1);
            constT.TruthStatus = repmat("real_lls_evidence", nConst, 1);
            constT.direction = string(constT.Direction);
            constT.ue_id = nan(nConst, 1);
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

        txBits = int8(tx.TransportBlock(:));
        rxBits = int8(rx.TransportBlock(:));
        currentRecLLR = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
        combinedLLR = localCombineRateRecoveredLLR(previousCombinedLLR, currentRecLLR);
        harqCombining = localHARQCombiningDiagnostics(previousCombinedLLR, currentRecLLR, combinedLLR);
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
                "CombinedLLR", combinedLLR, ...
                "PreviousLLRCount", harqCombining.PreviousLLRCount, ...
                "CurrentLLRCount", harqCombining.CurrentLLRCount, ...
                "CombinedLLRCount", harqCombining.CombinedLLRCount, ...
                "HARQCombiningApplied", harqCombining.CombiningApplied, ...
                "LLRCombiningGain_dB", harqCombining.LLRCombiningGain_dB, ...
                "CurrentDecodeOK", false, ...
                "CombinedDecodeOK", false, ...
                "DecoderIterations", combinedDecodeIt, ...
                "GrantSnapshot", grantSnapshot, ...
                "Context", harqContext);
            continue;
        end

        be = sum(txBits(1:L) ~= rxBits(1:L));
        trialBitErr(n) = double(be);
        trialBitTot(n) = double(L);
        bitErr = bitErr + double(be);
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

        currentDecodeOK = rx.Ok && be == 0 && numel(rxBits) == numel(txBits);
        hasPriorHARQEvidence = ~isempty(previousCombinedLLR);
        if hasPriorHARQEvidence && ~currentDecodeOK
            [combinedDecodeOK, combinedDecodeIt] = localDecodeCombinedLLR(tx, combinedLLR, cfgFrame);
        else
            combinedDecodeOK = logical(currentDecodeOK);
            if isfinite(trialDecIt(n))
                combinedDecodeIt = double(trialDecIt(n));
            end
        end
        if currentDecodeOK
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
            metrics.CRCPass = logical(currentDecodeOK);
            metrics.CurrentDecodeOK = logical(currentDecodeOK);
            metrics.CombinedDecodeOK = logical(combinedDecodeOK);
            metrics.AckObserved = logical(combinedDecodeOK);
            metrics.DecoderIterations = double(combinedDecodeIt);
            [cfgDyn, laState, laObserveEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "UL", frameIdx, ...
                "Phase", "after", "Metrics", metrics);
            trialLAScheduled(n) = logical(laObserveEvent.Scheduled);
        end
        lastHARQ = struct( ...
            "TransportBlockBits", txBits, ...
            "CombinedLLR", combinedLLR, ...
            "PreviousLLRCount", harqCombining.PreviousLLRCount, ...
            "CurrentLLRCount", harqCombining.CurrentLLRCount, ...
            "CombinedLLRCount", harqCombining.CombinedLLRCount, ...
            "HARQCombiningApplied", harqCombining.CombiningApplied, ...
            "LLRCombiningGain_dB", harqCombining.LLRCombiningGain_dB, ...
            "CurrentDecodeOK", logical(currentDecodeOK), ...
            "CombinedDecodeOK", logical(combinedDecodeOK), ...
            "DecoderIterations", combinedDecodeIt, ...
            "GrantSnapshot", grantSnapshot, ...
            "Context", harqContext);
    catch ME
        blockErr = blockErr + 1;
        frameCrash = frameCrash + 1;
        if strlength(firstCrashMsg) == 0
            firstCrashMsg = string(ME.message);
        end
        trialCrash(n) = true;
        trialStatus(n) = "CRASH";
        trialCRC(n) = 0;
        trialNotes(n) = string(ME.message);
        if ~isempty(log) && frameCrash <= 2
            log.warn("runULPUSCHThroughput frame failed: " + string(ME.message));
        end
    end
    localMaybeEmitLiveSnapshot(n);
end

simDur_s = numFrames * slotDur_s;

out.BER = bitErr / max(bitTot, 1);
out.BLER = blockErr / max(numFrames, 1);
out.Throughput_Mbps = (bitGood / max(simDur_s, eps)) / 1e6;
out.Goodput_Mbps = out.Throughput_Mbps;
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
out.Ok = out.BLER < 1;
out.Notes = "Frames=" + string(numFrames) + ", SNR=" + string(snr_dB) + " dB";
out.ConstellationSamples = localBuildConstellationSlice(numFrames);
out.WaveformPreviewTable = localBuildWaveformPreviewSlice(numFrames);
out.LinkAdaptationState = laState;
out.StartFrameIndex = double(startFrameIndex);
out.StartSlotIndex = double(startSlotIndex);
out.EndFrameIndex = double(trialFrame(max(1, numFrames)));
out.EndSlotIndex = double(trialSlot(max(1, numFrames)));
out.HARQ = lastHARQ;

if frameCrash == numFrames
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnsupported", ...
        "Strict mode forbids skipping PUSCH coverage because every frame crashed: " + firstCrashMsg);
    out.Skipped = true;
    out.Ok = true;
    out.BER = NaN;
    out.BLER = NaN;
    out.Throughput_Mbps = NaN;
    out.Notes = "Skipped: UL chain unsupported in this release (" + firstCrashMsg + ")";
end

out.TrialTable = localBuildTrialSlice(numFrames);

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
            trialLinkAdaptationMode(idx), trialActualMCSSelectionMode(idx), trialSchedulerGrantMCSSelectionMode(idx), trialCQITable(idx), trialMCSTable(idx), ...
            trialRI(idx), trialPMI(idx), trialCRI(idx), ...
            trialPMIType(idx), trialPMICodebookMode(idx), trialCSIReportMode(idx), trialCSIPayloadBits(idx), trialCSIPayloadHex(idx), ...
            trialGain(idx), trialNoise(idx), trialDesiredSignalPowerBeforeNoise(idx), trialCompositeSignalPowerBeforeNoise(idx), trialAppliedNoiseSNR(idx), trialNoiseVarianceSource(idx), ...
            trialTiming(idx), trialRank(idx), trialCond(idx), trialRxAnt(idx), trialTxPorts(idx), ...
            trialSelectedBeam(idx), trialBestBeam(idx), trialBeamHit(idx), trialTopKBeamHit(idx), trialBeamCount(idx), ...
            trialSelectedBeamGain(idx), trialBestBeamGain(idx), trialBeamGap(idx), ...
            trialCfgPMI(idx), trialCfgCRI(idx), trialBitErr(idx), trialBitTot(idx), ...
            trialOfferedBits(idx), trialGoodBits(idx), trialOfferedThr(idx), trialGoodput(idx), ...
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
            'LinkAdaptationMode','ActualMCSSelectionMode','SchedulerGrantMCSSelectionMode','CQITable','MCSTable','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
            'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','ChannelGain_dB','NoiseVariance', ...
            'DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
            'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
            'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
            'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
            'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
            'OfferedBits','GoodBits','OfferedThroughput_Mbps','Goodput_Mbps', ...
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
        T.ConfiguredSNR_dB = trialConfiguredSNR(idx);
        configuredLayers = localFirstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN), ...
            sixgr.util.structGet(cfg, "phy.pusch.numLayers", NaN), ...
            trialLayers(idx), 1);
        configuredLayers = max(1, round(double(configuredLayers)));
        configuredTxAnt = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", ...
            localFirstFiniteScalar(trialTxPorts(idx), 1));
        configuredRxAnt = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", ...
            localFirstFiniteScalar(trialRxAnt(idx), 1));
        T.ConfiguredLayers = repmat(configuredLayers, stopIdx, 1);
        T.ConfiguredTxAntennas = repmat(configuredTxAnt, stopIdx, 1);
        T.ConfiguredRxAntennas = repmat(configuredRxAnt, stopIdx, 1);
        T.AllocatedPRBCount = trialPRB(idx);
        T.PRBStart = trialPRBStart(idx);
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
        T.HARQACKContentMatch = trialHARQACKContentMatch(idx);
        T.HARQACKDecodeStatus = trialHARQACKDecodeStatus(idx);
        T.HARQACKDecodeReason = trialHARQACKDecodeReason(idx);
        T.EqualizerType = trialEqualizerType(idx);
        T.EqualizerRequestedType = trialEqualizerRequestedType(idx);
        T.EqualizerEngine = trialEqualizerEngine(idx);
        T.InterferenceCovarianceAvailable = trialInterferenceCovarianceAvailable(idx);
        T.InterferenceCovarianceSource = trialInterferenceCovarianceSource(idx);
        T.InterferenceCovarianceStatus = trialInterferenceCovarianceStatus(idx);
        T.ReceiverUsable = trialReceiverUsable(idx);
        T.DecodeAttempted = trialDecodeAttempted(idx);
        T.DecodeUsable = trialDecodeUsable(idx);
        T.FailureReason = trialFailureReason(idx);
        T.ReceiverHestSINR_dB = trialReceiverHestSINR(idx);
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
        T.OuterLoopEnabled = trialOuterLoopEnabled(idx);
        T.OuterLoopApplied = trialOuterLoopAppliedFromGrant(idx);
        T.OLLADeltaMCS = trialOLLADeltaMCS(idx);
        T.OLLAUpdateCount = trialOLLAUpdateCount(idx);
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
        T.AirInterfaceObservation_ms = trialAirInterfaceObservation(idx);
        T.LargeScaleSINR_dB = trialLargeScaleSINR(idx);
        T.LargeScaleSINRSource = trialLargeScaleSINRSource(idx);
        T.ServingRSRP_dBm = trialServingRSRP(idx);
        T.ServingRSRPSource = trialServingRSRPSource(idx);
        T.CSI_RSRP_dB = trialCSIRSRP(idx);
        T.CSI_RSRPSource = trialCSIRSRPSource(idx);
        T.CSI_RSSI_dB = trialCSIRSSI(idx);
        T.CSI_RSSISource = trialCSIRSSISource(idx);
        T.CSI_RSRQ_dB = trialCSIRSRQ(idx);
        T.CSI_RSRQSource = trialCSIRSRQSource(idx);
        T.BeamScoreVector_dB = trialBeamScoreVector(idx);
        T.TopBeamIndexSet = trialTopBeamIndexSet(idx);
        T.TopBeamGainSet_dB = trialTopBeamGainSet(idx);
        T.BeamScoreSource = trialBeamScoreSource(idx);
        T.AppliedLargeScaleGain_dB = trialAppliedLargeScaleGain(idx);
        T.AppliedLargeScaleLoss_dB = trialAppliedLargeScaleLoss(idx);
        T.AppliedBasePathloss_dB = trialAppliedBasePathloss(idx);
        T.AppliedPathloss_dB = trialAppliedPathloss(idx);
        T.PUSCHPowerControlEnabled = trialPUSCHPowerControlEnabled(idx);
        T.PUSCHPowerControlStatus = trialPUSCHPowerControlStatus(idx);
        T.PUSCHTxPower_dBm = trialPUSCHTxPower(idx);
        T.PUSCHPcmax_dBm = trialPUSCHPcmax(idx);
        T.PUSCHPowerHeadroom_dB = trialPUSCHPowerHeadroom(idx);
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
        T.GrantControlState = trialGrantControlState(idx);
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
        T.BeamformingApplied = trialBeamformingApplied(idx);
        T.AppliedBeamIndexSet = trialAppliedBeamIndexSet(idx);
        T.AppliedPrecoderPMI = trialAppliedPrecoderPMI(idx);
        T.AppliedPrecoderPMIType = trialAppliedPrecoderPMIType(idx);
        T.AppliedPrecoderCodebookMode = trialAppliedPrecoderCodebookMode(idx);
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
        T = localDecorateTrialTruthFields(T, "UL", cfg);
    end
end

function [y, nVar, noiseInfo] = localAddAwgn(x, replay, referenceWaveform, txInfo)
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
awgnNVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, appliedSNR_dB, txInfo);
[nVar, source] = localReceiverEffectiveNoiseVariance(awgnNVar, replay, "standalone_awgn_snr_argument_post_channel_units");
noiseInfo = localNoiseCalibrationInfo(x, referenceWaveform, nVar, source, txInfo);
if isfinite(awgnNVar) && awgnNVar >= 0
    if awgnNVar > 0
        n = sqrt(awgnNVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
    else
        y = x;
    end
    return;
end
[y, nVar] = sixgr.util.addAwgnComplex(x, appliedSNR_dB);
[nVar, source] = localReceiverEffectiveNoiseVariance(nVar, replay, "legacy_addAwgnComplex_last_resort");
noiseInfo = localNoiseCalibrationInfo(x, referenceWaveform, nVar, source, txInfo);
end

function [effectiveNVar, source] = localReceiverEffectiveNoiseVariance(baseNVar, replay, baseSource)
effectiveNVar = double(baseNVar);
source = string(baseSource);
interferenceNVar = double(sixgr.util.structGet(replay, "InterferenceWaveformVariance", NaN));
if isfinite(interferenceNVar) && interferenceNVar > 0
    if isfinite(effectiveNVar) && effectiveNVar >= 0
        effectiveNVar = effectiveNVar + interferenceNVar;
    else
        effectiveNVar = interferenceNVar;
    end
    source = source + "_plus_full_waveform_interference_power";
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
    "NoiseVarianceSource", char(string(source)));
end

function nVar = localResolveConfiguredSNRNoiseVariance(referenceWaveform, snr_dB, txInfo)
nVar = NaN;
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB))
    return;
end
if isempty(referenceWaveform)
    return;
end
refPower = localUsefulOFDMReferencePower(referenceWaveform, txInfo);
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
nVar = refPower / max(10.^(snr_dB / 10), eps);
end

function refPower = localUsefulOFDMReferencePower(waveform, txInfo)
refPower = NaN;
if isempty(waveform)
    return;
end
ofdmInfo = sixgr.util.structGet(txInfo, "OFDM", struct());
nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
cpLens = double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", []));
if ~(isfinite(nfft) && nfft > 0 && ~isempty(cpLens))
    refPower = mean(abs(double(waveform(:))).^2, "omitnan");
    return;
end
cpLens = cpLens(:);
idx = [];
offset = 0;
nSamp = size(waveform, 1);
while offset < nSamp
    for s = 1:numel(cpLens)
        cp = max(0, round(double(cpLens(s))));
        useful = offset + cp + (1:round(nfft));
        useful = useful(useful <= nSamp);
        idx = [idx useful]; %#ok<AGROW>
        offset = offset + cp + round(nfft);
        if offset >= nSamp
            break;
        end
    end
end
if isempty(idx)
    refPower = mean(abs(double(waveform(:))).^2, "omitnan");
else
    refPower = mean(abs(double(waveform(idx, :))).^2, "all", "omitnan");
end
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
T.CQISource = localResolveCQISourceColumn(T, configuredDomain);
[mcsSelectionSource, mcsValueStatus] = localResolveMCSSelectionEvidenceColumns(T, cfg, direction);
T.MCSSelectionSource = mcsSelectionSource;
T.MCSValueStatus = mcsValueStatus;
T.OLLADomain = repmat(localResolveOLLADomainToken(cfg, direction), n, 1);
outerLoopEnabled = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", true));
innerLoopEnabled = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.innerLoopFlag", true));
linkModeColumn = lower(string(localOptionalColumn(T, "LinkAdaptationMode", configuredLinkMode)));
schedulerReplayMask = linkModeColumn == "scheduler_grant_replay";
linkAdaptationRuntimeMask = ~schedulerReplayMask & ~ismember(lower(string(configuredLinkMode)), ["fixed","disabled","none","off","false",""]);
existingOuterLoopEnabled = logical(localOptionalColumn(T, "OuterLoopEnabled", outerLoopEnabled));
existingOuterLoopApplied = logical(localOptionalColumn(T, "OuterLoopApplied", false));
existingInnerLoopApplied = logical(localOptionalColumn(T, "InnerLoopApplied", false));
existingOLLADeltaMCS = double(localOptionalColumn(T, "OLLADeltaMCS", NaN));
existingOLLAUpdateCount = double(localOptionalColumn(T, "OLLAUpdateCount", NaN));
existingOLLAState = string(localOptionalColumn(T, "OLLAState", ""));
T.OuterLoopEnabled = repmat(outerLoopEnabled, n, 1) | existingOuterLoopEnabled;
T.InnerLoopEnabled = repmat(innerLoopEnabled, n, 1);
T.OuterLoopApplied = (T.OuterLoopEnabled & schedulerReplayMask & existingOuterLoopApplied) | ...
    (T.OuterLoopEnabled & linkAdaptationRuntimeMask & logical(localOptionalColumn(T, "LinkAdaptationScheduled", false)));
T.InnerLoopApplied = (T.InnerLoopEnabled & schedulerReplayMask & existingInnerLoopApplied) | ...
    (T.InnerLoopEnabled & linkAdaptationRuntimeMask & ...
    (logical(localOptionalColumn(T, "LinkAdaptationApplied", false)) | logical(localOptionalColumn(T, "LinkAdaptationScheduled", false))));
T.OLLADeltaMCS = existingOLLADeltaMCS;
T.OLLAUpdateCount = existingOLLAUpdateCount;
T.OLLAState = repmat("disabled", n, 1);
T.OLLAState(T.OuterLoopEnabled & schedulerReplayMask) = "configured_enabled_waiting_for_scheduler_ack_nack_feedback";
T.OLLAState(T.OuterLoopEnabled & linkAdaptationRuntimeMask & ~T.OuterLoopApplied) = "configured_enabled_waiting_for_runtime_feedback";
T.OLLAState(T.OuterLoopApplied) = "applied_runtime_link_adaptation_decision";
preserveStateMask = strlength(strtrim(existingOLLAState)) > 0 & lower(strtrim(existingOLLAState)) ~= "disabled";
T.OLLAState(preserveStateMask) = existingOLLAState(preserveStateMask);
T.CalibrationProfile = repmat(localResolveLinkAdaptationCalibrationProfile(cfg, direction), n, 1);
T.RequestedOperatingPointSource = localResolveOperatingPointSourceColumn(configuredSelectionMode, configuredLinkMode);
T.SchedulerGrantMCSSelectionMode = string(localOptionalColumn(T, "SchedulerGrantMCSSelectionMode", ""));
operatingPointSource = localResolveOperatingPointSourceColumn(localOptionalColumn(T, "ActualMCSSelectionMode", ""), localOptionalColumn(T, "LinkAdaptationMode", ""));
T.GrantOperatingPointSource = operatingPointSource;
T.AppliedOperatingPointSource = operatingPointSource;
T.MCSAuthority = operatingPointSource;
T.ModulationAuthority = operatingPointSource;
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
implicitTPMIBeamRequestMask = codebookMask & strlength(requestedBeam) == 0 & ...
    strlength(appliedBeam) > 0 & isfinite(requestedPMI);
requestedBeam(implicitTPMIBeamRequestMask) = appliedBeam(implicitTPMIBeamRequestMask);
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
missingAppliedBeamMask = ~appliedBeamMask & ~explicitBeamWeights;
missingAppliedPMIMask = ~appliedPMIMask & ~explicitBeamWeights;
nativeCodebookAppliedBeamMask = appliedBeamMask & codebookMask;

beamAppSource = T.AppliedBeamApplicationSource;
pmiAppSource = T.AppliedPrecoderPMIApplicationSource;
beamAppSource(nativeCodebookAppliedBeamMask) = "ul_pusch_native_codebook_tpmi_port_support";
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
row.GeometricPropagationDelay_s = double(geometricDelay_s);
row.DominantPathDelay_s = double(dominantPathDelay_s);
row.ChannelFilterDelay_s = double(channelFilterDelay_s);
row.PropagationDelay_s = double(geometricDelay_s + dominantPathDelay_s);
row.ToD_s = double(slotStart_s);
row.ToA_s = double(toa_s);
row.ToAEstimate_s = double(toaEstimate_s);
row.ToDSource = "runtime_slot_start_reference";
row.ToASource = "runtime_geometry_plus_channel_path_delay";
row.ToAEstimateSource = string(ternaryString(isfinite(toaEstimate_s), "receiver_timing_estimate_pre_correction", ""));
row.ChannelDelaySource = string(channelDelaySource);
row.AntennaGeometrySource = "CoupledTruthRuntime.applyUserContextImpl";
row.RuntimeTraceSource = "runULPUSCHThroughput_active_trial";
row.AntennaEvidenceSource = "active_runtime_user_context";
row.SameFlowEvidenceSource = "CoupledTruthRuntime.applyUserContextImpl->runULPUSCHThroughput";
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
    "NumPorts", double(sixgr.util.structGet(arr, "Nant", NaN)), ...
    "HasPhasedArrayObject", logical(sixgr.util.structGet(arr, "HasPhased", false)));
end

function [distance_m, delay_s] = localResolveGeometryDelay(userMeta)
distance_m = NaN;
delay_s = NaN;
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
    "SameFlowEvidenceSource", "");
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

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", localChannelSeed(cfg, snr_dB, trialSeed), ...
    "TransmitAntennaRuntime", sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct()), ...
    "ReceiveAntennaRuntime", sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct()), ...
    "TransmitAntennaMeta", sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct()), ...
    "ReceiveAntennaMeta", sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct()));
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

function [waveOut, pc, cfgOut] = localApplyPUSCHOpenLoopPowerControl(waveIn, cfg, tx, grant)
waveOut = waveIn;
cfgOut = cfg;
pc = struct( ...
    "Enabled", false, ...
    "Status", "disabled", ...
    "TxPower_dBm", NaN, ...
    "Pcmax_dBm", NaN, ...
    "PowerHeadroom_dB", NaN, ...
    "AmplitudeScale", 1, ...
    "Pathloss_dB", NaN);

enabled = logical(sixgr.util.structGet(cfg, "phy.pusch.powerControl.enabled", ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.enabled", ...
    sixgr.util.structGet(cfg, "powerAndRF.puschPowerControlEnabled", true))));
pc.Enabled = enabled;
if ~enabled
    return;
end

userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
pathloss_dB = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeServingPathloss_dB", []), ...
    sixgr.util.structGet(userMeta, "RuntimeServingBasePathloss_dB", []), ...
    sixgr.util.structGet(cfg, "channel.pathloss_dB", []), ...
    sixgr.util.structGet(cfg, "channel.largeScale.pathloss_dB", []));
pc.Pathloss_dB = double(pathloss_dB);
if ~(isfinite(pathloss_dB) && pathloss_dB >= 0)
    pc.Status = "pathloss_unavailable_no_power_control_applied";
    return;
end

try
    mRB = numel(tx.PUSCH.PRBSet);
catch
    mRB = numel(double(sixgr.util.structGet(grant, "PRBSet", [])));
end
mRB = max(1, round(double(mRB)));

p0 = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.p0PUSCH_dBm", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.P0_PUSCH_dBm", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.p0_pusch_dbm", []), ...
    -80);
alpha = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.alpha", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.alpha", []), ...
    0.8);
alpha = min(max(double(alpha), 0), 1);
pcmax = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.pcmax_dBm", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.Pcmax_dBm", []), ...
    sixgr.util.structGet(cfg, "powerAndRF.uePcmax_dBm", []), ...
    sixgr.util.structGet(cfg, "lls6g.resolvedConfig.power_and_rf_frontend.ue_pcmax_dbm", []), ...
    23);
deltaTF = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.deltaTF_dB", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.delta_tf_db", []), ...
    0);
closedLoop = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.closedLoopAccumulation_dB", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.closed_loop_accumulation_db", []), ...
    0);
refPower = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.referenceTxPower_dBm", []), ...
    sixgr.util.structGet(cfg, "powerAndRF.referenceTxPower_dBm", []), ...
    0);

requestedPower = double(p0) + double(alpha) * double(pathloss_dB) + 10 * log10(double(mRB)) + ...
    double(deltaTF) + double(closedLoop);
txPower = min(double(pcmax), requestedPower);
scale = 10 .^ ((double(txPower) - double(refPower)) / 20);
if isfinite(scale) && scale > 0
    waveOut = waveIn .* cast(scale, "like", waveIn);
else
    scale = 1;
end

pc.Status = "applied_open_loop_ts38213_fractional_pathloss";
pc.TxPower_dBm = double(txPower);
pc.Pcmax_dBm = double(pcmax);
pc.PowerHeadroom_dB = double(pcmax) - double(txPower);
pc.AmplitudeScale = double(scale);

cfgOut = sixgr.util.structSet(cfgOut, "powerAndRF.ueTxPower_dBm", double(txPower));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.resolvedConfig.power_and_rf_frontend.ue_tx_power_dbm", double(txPower));
end

function [y, replay] = localApplyChannelAndAwgn(x, snr_dB, state, cfg, tx, txInfo, interferenceBundle)
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
if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
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
cfgReplay = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz);
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
if strlength(strtrim(string(replay.InterferencePowerSource))) == 0 && replay.InterferenceContributorCount > 0
    replay.InterferencePowerSource = "sample_domain_interference_sum";
end
[y, replay.InjectedNoiseVariance, noiseInfo] = localAddAwgn(y, replay, desiredWaveform, txInfo);
noiseFields = fieldnames(noiseInfo);
for ni = 1:numel(noiseFields)
    replay.(noiseFields{ni}) = noiseInfo.(noiseFields{ni});
end
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

timingEstimate = double(sixgr.util.structGet(rx, "TimingOffset", NaN));
rawTimingEstimate = double(sixgr.util.structGet(rx, "RawTimingEstimate_samples", timingEstimate));
appliedTimingCorrection = double(sixgr.util.structGet(rx, "AppliedTimingCorrection_samples", NaN));
timingEstimateUsed = logical(sixgr.util.structGet(rx, "TimingEstimateUsed", isfinite(rawTimingEstimate)));
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
    return;
end
replay.TimingEstimateUsed = true;
replay.EstimatedTimingOffset_PreCorrection_samples = rawTimingEstimate;
if isfinite(replay.InjectedTimingOffset_samples)
    replay.ResidualTimingError_PostCorrection_samples = double(replay.InjectedTimingOffset_samples) - appliedTimingCorrection;
else
    replay.ResidualTimingError_PostCorrection_samples = NaN;
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

function nVar = localResolveThermalNoiseVariance(replay, referenceWaveform, txInfo)
nVar = NaN;
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
if ~(isfinite(servingRxPower_dBm) && isfinite(thermalNoisePower_dBm))
    return;
end
referencePower = localUsefulOFDMReferencePower(referenceWaveform, txInfo);
if ~(isfinite(referencePower) && referencePower > 0)
    return;
end
signalMilliwatt = 10.^(servingRxPower_dBm / 10);
noiseMilliwatt = 10.^(thermalNoisePower_dBm / 10);
if ~(isfinite(signalMilliwatt) && signalMilliwatt > 0 && isfinite(noiseMilliwatt) && noiseMilliwatt >= 0)
    return;
end
nVar = referencePower * (noiseMilliwatt / signalMilliwatt);
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
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
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
    'OfferedBits','GoodBits','OfferedThroughput_Mbps','Goodput_Mbps', ...
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
T = table('Size', [0, numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
T.ConfiguredSNR_dB = zeros(0,1);
T.ConfiguredLayers = zeros(0,1);
T.ConfiguredTxAntennas = zeros(0,1);
T.ConfiguredRxAntennas = zeros(0,1);
T.AppliedAWGNSNR_dB = zeros(0,1);
T.NoiseVarStatus = strings(0,1);
T.NoiseVarSource = strings(0,1);
T.NoiseVarReason = strings(0,1);
T.NoiseVarStrictFailure = false(0,1);
T.UCIOnPUSCHApplied = false(0,1);
T.UCIOnPUSCHSource = strings(0,1);
T.HARQACKBitCount = zeros(0,1);
T.HARQACKContentMatch = false(0,1);
T.HARQACKDecodeStatus = strings(0,1);
T.HARQACKDecodeReason = strings(0,1);
T.EqualizerType = strings(0,1);
T.EqualizerRequestedType = strings(0,1);
T.EqualizerEngine = strings(0,1);
T.InterferenceCovarianceAvailable = false(0,1);
T.InterferenceCovarianceSource = strings(0,1);
T.InterferenceCovarianceStatus = strings(0,1);
T.ReceiverUsable = false(0,1);
T.DecodeAttempted = false(0,1);
T.DecodeUsable = false(0,1);
T.FailureReason = strings(0,1);
T.ReceiverHestSINR_dB = zeros(0,1);
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
T.CSI_RSSI_dB = zeros(0,1);
T.CSI_RSSISource = strings(0,1);
T.CSI_RSRQ_dB = zeros(0,1);
T.CSI_RSRQSource = strings(0,1);
T.AppliedLargeScaleGain_dB = zeros(0,1);
T.AppliedLargeScaleLoss_dB = zeros(0,1);
T.AppliedBasePathloss_dB = zeros(0,1);
T.AppliedPathloss_dB = zeros(0,1);
T.PUSCHPowerControlEnabled = false(0,1);
T.PUSCHPowerControlStatus = strings(0,1);
T.PUSCHTxPower_dBm = zeros(0,1);
T.PUSCHPcmax_dBm = zeros(0,1);
T.PUSCHPowerHeadroom_dB = zeros(0,1);
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
T.CQISource = strings(0,1);
T.MCSSelectionSource = strings(0,1);
T.MCSValueStatus = strings(0,1);
T.OLLADomain = strings(0,1);
T.OuterLoopEnabled = false(0,1);
T.InnerLoopEnabled = false(0,1);
T.OuterLoopApplied = false(0,1);
T.InnerLoopApplied = false(0,1);
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
T.GrantControlState = strings(0,1);
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
T.BeamformingApplied = false(0,1);
T.AppliedBeamIndexSet = strings(0,1);
T.AppliedPrecoderPMI = zeros(0,1);
T.AppliedPrecoderPMIType = strings(0,1);
T.AppliedPrecoderCodebookMode = strings(0,1);
T.RequestedVsAppliedPrecoderPMIMatchStatus = strings(0,1);
T.RequestedBeamTruthClassification = strings(0,1);
T.RequestedPrecoderPMITruthClassification = strings(0,1);
T.AppliedBeamApplicationSource = strings(0,1);
T.AppliedBeamTruthClassification = strings(0,1);
T.AppliedPrecoderPMIApplicationSource = strings(0,1);
T.AppliedPrecoderPMITruthClassification = strings(0,1);
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
source = repmat(localResolveMCSSelectionSourceToken(cfg, direction), n, 1);
status = repmat("configured_runtime_policy", n, 1);
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
fixedMCSMask = mode == "fixed_mcs";
source(fixedMCSMask) = "configured_fixed_mcs";
status(fixedMCSMask) = "configured";
fixedModMask = mode == "fixed_modulation";
source(fixedModMask) = "configured_modulation_code_rate";
status(fixedModMask) = "configured";
end

function token = localResolveOLLADomainToken(cfg, direction)
if ~logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", true))
    token = "disabled";
    return;
end
if sixgr.link.resolveLinkAdaptationDomain(cfg, direction) == "bler_margin"
    token = "bler_margin_proxy_delta_mcs";
else
    token = "delta_mcs";
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
prec = sixgr.util.structGet(tx, "PrecodeInfo", struct());
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", sixgr.util.structGet(grant, "TransformPrecodingApplied", false)));
precodingActive = logical(sixgr.util.structGet(prec, "Active", transformPrecoding));
beamformingApplied = logical(sixgr.util.structGet(prec, "BeamformingApplied", sixgr.util.structGet(grant, "BeamformingApplied", false)));
appliedPMI = double(sixgr.util.structGet(prec, "PMI", sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN)));
requestedPMI = double(sixgr.util.structGet(grant, "PMI", ...
    sixgr.util.structGet(cfg, "phy.pusch.TPMI", ...
    sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN))));
trace = struct( ...
    "ConfiguredBeamSelectionStrategy", string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")), ...
    "PrecoderSource", string(sixgr.util.structGet(prec, "Source", sixgr.util.structGet(grant, "PrecoderSource", localResolveULPrecoderSource(transformPrecoding)))), ...
    "PrecodingMode", string(sixgr.util.structGet(prec, "Mode", sixgr.util.structGet(grant, "PrecodingMode", localResolveULPrecodingMode(transformPrecoding)))), ...
    "PrecodingApplicationStage", string(sixgr.util.structGet(prec, "ApplicationStage", sixgr.util.structGet(grant, "PrecodingApplicationStage", localResolveULPrecodingStage(transformPrecoding)))), ...
    "PrecodingActive", logical(precodingActive), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(prec, "ExplicitBeamWeightsApplied", false)), ...
    "TransformPrecodingApplied", logical(transformPrecoding), ...
    "BeamformingApplied", logical(beamformingApplied), ...
    "AppliedBeamIndexSet", localFormatIndexSet(sixgr.util.structGet(prec, "BeamIndices", sixgr.util.structGet(grant, "AppliedBeamIndexSet", []))), ...
    "AppliedPrecoderPMI", double(appliedPMI), ...
    "AppliedPrecoderPMIType", string(sixgr.util.structGet(prec, "PMIType", sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""))), ...
    "AppliedPrecoderCodebookMode", string(sixgr.util.structGet(prec, "CodebookMode", sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""))), ...
    "RequestedVsAppliedPrecoderPMIMatchStatus", localRequestedVsAppliedPMIStatus(requestedPMI, appliedPMI), ...
    "PrecodingNumPorts", double(sixgr.util.structGet(prec, "NumPorts", size(sixgr.util.structGet(tx, "Grid", zeros(0,0,0)), 3))), ...
    "PrecodingNumLayers", double(sixgr.util.structGet(prec, "NumLayers", localObjectValue(pusch, "NumLayers", sixgr.util.structGet(grant, "PrecodingNumLayers", NaN)))), ...
    "PrecodingMatrixRows", double(sixgr.util.structGet(prec, "MatrixRows", NaN)), ...
    "PrecodingMatrixCols", double(sixgr.util.structGet(prec, "MatrixCols", NaN)));
end

function trace = localResolveInterferencePrecodingTrace(replay)
trace = struct( ...
    "InterfererBeamformingAppliedCount", double(sixgr.util.structGet(replay, "InterfererBeamformingAppliedCount", 0)), ...
    "InterfererExplicitBeamWeightCount", double(sixgr.util.structGet(replay, "InterfererExplicitBeamWeightCount", 0)), ...
    "InterfererTransformPrecodingCount", double(sixgr.util.structGet(replay, "InterfererTransformPrecodingCount", 0)), ...
    "InterfererPrecoderSourceSet", string(sixgr.util.structGet(replay, "InterfererPrecoderSourceSet", "")), ...
    "InterfererPrecodingModeSet", string(sixgr.util.structGet(replay, "InterfererPrecodingModeSet", "")), ...
    "InterfererBeamIndexSetSummary", string(sixgr.util.structGet(replay, "InterfererBeamIndexSetSummary", "")));
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
    "PrecoderInfo", precoderTrace);
metrics.PilotSINR_dB = double(sixgr.util.structGet(metrics, "SINR_dB", NaN));
metrics.PilotSINRSource = string(sixgr.util.structGet(metrics, "SINRSource", ""));
referenceSINR = double(sixgr.util.structGet(metrics, "SINR_dB", NaN));
referenceSource = string(sixgr.util.structGet(metrics, "SINRSource", ""));
referenceRole = string(sixgr.util.structGet(metrics, "SINRValueRole", ""));
referenceStatus = string(sixgr.util.structGet(metrics, "SINRValueStatus", ""));
referenceReason = string(sixgr.util.structGet(metrics, "SINRNAReason", ""));
postEqSINR = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
postEqSource = string(sixgr.util.structGet(rx, "PostEqSINRSource", ""));
postEqRole = string(sixgr.util.structGet(rx, "PostEqSINRValueRole", ""));
postEqStatus = string(sixgr.util.structGet(rx, "PostEqSINRValueStatus", ""));
postEqReason = string(sixgr.util.structGet(rx, "PostEqSINRNAReason", ""));
reportCQI = localCQIReportingEnabled(cfg, "UL");
selectedSINR = localSelectULMeasuredTrialSINRFromEvidence( ...
    postEqSINR, postEqSource, postEqRole, postEqStatus, postEqReason, ...
    referenceSINR, referenceSource, referenceRole, referenceStatus, referenceReason);
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
    s = svd(double(Hwb));
    if ~isempty(s)
        smax = max(s);
        metrics.RankEstimate = sum(s > max(smax * 0.1, eps));
        if numel(s) >= 2 && s(end) > 0
            metrics.ConditionNumber_dB = 20 * log10(s(1) / s(end));
        else
            metrics.ConditionNumber_dB = 0;
        end
    end
catch
end
beamMetrics = localComputeBeamMetrics(Hwb, cfg, metrics);
beamFields = fieldnames(beamMetrics);
for f = 1:numel(beamFields)
    metrics.(beamFields{f}) = beamMetrics.(beamFields{f});
end
end

function selected = localSelectULMeasuredTrialSINRFromEvidence(postEqSINR, postEqSource, postEqRole, postEqStatus, postEqReason, ...
    referenceSINR, referenceSource, referenceRole, referenceStatus, referenceReason)
selected = struct( ...
    "Value", NaN, ...
    "Source", "", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "no_scheduler_eligible_ul_receiver_sinr");
postEqSINR = double(postEqSINR);
referenceSINR = double(referenceSINR);
postEqSource = string(postEqSource);
postEqRole = string(postEqRole);
postEqStatus = string(postEqStatus);
postEqReason = string(postEqReason);
referenceSource = string(referenceSource);
referenceRole = string(referenceRole);
referenceStatus = string(referenceStatus);
referenceReason = string(referenceReason);

postEqAvailable = isfinite(postEqSINR) && localPostEqSINRIsSchedulerEligible(postEqSource, postEqRole, postEqStatus);
referenceAvailable = isfinite(referenceSINR) && localULReferenceSINRIsReceiverMeasured(referenceSource, referenceRole, referenceStatus);
if postEqAvailable && referenceAvailable
    if referenceSINR < postEqSINR
        selected.Value = double(referenceSINR);
        selected.Source = "ul_receiver_evidence_limited_post_equalization_sinr";
        selected.ValueRole = "measured_post_equalization_scheduling_input";
        selected.ValueStatus = "OK";
        selected.NAReason = sprintf("post_eq_sinr_%.6g_dB_limited_by_measured_ul_rs_sinr_%.6g_dB", ...
            double(postEqSINR), double(referenceSINR));
    else
        selected.Value = double(postEqSINR);
        selected.Source = char(postEqSource);
        selected.ValueRole = char(postEqRole);
        selected.ValueStatus = char(postEqStatus);
        selected.NAReason = char(postEqReason);
    end
elseif postEqAvailable
    selected.Value = double(postEqSINR);
    selected.Source = char(postEqSource);
    selected.ValueRole = char(postEqRole);
    selected.ValueStatus = char(postEqStatus);
    selected.NAReason = char(postEqReason);
elseif referenceAvailable
    selected.Value = double(referenceSINR);
    selected.Source = "measured_ul_rs_sinr";
    selected.ValueRole = "measured_ul_rs_cqi_input";
    selected.ValueStatus = char(referenceStatus);
    selected.NAReason = char(referenceReason);
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

function tf = localULReferenceSINRIsReceiverMeasured(source, role, status)
source = lower(strtrim(string(source)));
role = lower(strtrim(string(role)));
status = lower(strtrim(string(status)));
if contains(status, "unavailable") || contains(status, "failed") || contains(status, "rejected")
    tf = false;
    return;
end
isMeasuredULRS = source == "measured_ul_rs_sinr" && role == "measured_ul_rs_cqi_input";
isReceiverHestMeasurement = source == "receiver_hest_reference_signal_measurement" && ...
    (role == "estimated" || role == "measured" || role == "diagnostic_reference_signal_quality_not_for_scheduling");
tf = isMeasuredULRS || isReceiverHestMeasurement;
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
Hwb = [];
if isempty(Hest)
    return;
end
nd = ndims(Hest);
if nd >= 4
    try
        Havg = mean(mean(Hest, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(Hest, 1), 2);
    end
    Hwb = squeeze(Havg);
elseif nd == 3
    try
        Havg = mean(mean(Hest, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(Hest, 1), 2);
    end
    Hwb = reshape(squeeze(Havg), [], 1);
elseif ismatrix(Hest)
    try
        Havg = mean(Hest(:), "omitnan");
    catch
        Havg = mean(Hest(:));
    end
    Hwb = Havg;
end
if isvector(Hwb)
    Hwb = reshape(Hwb, numel(Hwb), 1);
end
if ~ismatrix(Hwb)
    Hwb = [];
end
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

if isempty(Hwb) || ~ismatrix(Hwb)
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
if isempty(selectedSet)
    selectedSet = 1;
end

order = find(isfinite(metric));
[~, ordLocal] = sort(metric(order), "descend");
ord = order(ordLocal);
topK = max(1, min(2, numel(ord)));
traceK = max(1, min(8, numel(ord)));
beamStrategy = lower(string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")));
if beamStrategy == "fixed_first_beam"
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
beam.SelectedBeamGain_dB = 10 * log10(max(selectedMetric, eps));
beam.BestBeamGain_dB = 10 * log10(max(bestMetric, eps));
beam.BeamGainGap_dB = beam.BestBeamGain_dB - beam.SelectedBeamGain_dB;
beam.BeamScoreVector_dB = localFormatNumericVector(metricDb);
beam.TopBeamIndexSet = localFormatIndexSet(ord(1:traceK));
beam.TopBeamGainSet_dB = localFormatNumericVector(metricDb(ord(1:traceK)));
beam.BeamScoreSource = "wideband_hest_codebook_projection";
end

function beam = localComputePMICodebookCandidateMetrics(Hwb, cfg, metrics)
beam = struct();
if isempty(Hwb) || ~ismatrix(Hwb) || size(Hwb, 2) <= 1
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
    Heff = double(Hwb) * double(W);
    metric(ii) = real(trace(Heff * Heff')) / max(1, size(W, 2));
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
    "SelectedBeamGain_dB", double(10 * log10(max(selectedMetric, eps))), ...
    "BestBeamGain_dB", double(10 * log10(max(bestMetric, eps))), ...
    "BeamGainGap_dB", double(10 * log10(max(bestMetric, eps)) - 10 * log10(max(selectedMetric, eps))), ...
    "BeamScoreVector_dB", localFormatNumericVector(metricDb), ...
    "TopBeamIndexSet", localFormatIndexSet(ord(1:traceK)), ...
    "TopBeamGainSet_dB", localFormatNumericVector(metricDb(ord(1:traceK))), ...
    "BeamScoreSource", "wideband_hest_3gpp_type1_pmi_candidate_projection");
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

selectedSet = localResolveBeamSetFromPMI(cfg, metrics, size(W, 1), size(W, 2));
if ~isempty(selectedSet)
    return;
end

configuredPMI = double(sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN));
configuredTPMI = double(sixgr.util.structGet(cfg, "phy.pusch.TPMI", NaN));
if isfinite(configuredTPMI)
    configuredPMI = configuredTPMI;
end
if isfinite(configuredPMI)
    selectedSet = localResolveBeamSetFromPMI(cfg, struct("PMI", configuredPMI, "RI", metrics.RI), size(W, 1), size(W, 2));
    if ~isempty(selectedSet)
        return;
    end
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

function combined = localCombineRateRecoveredLLR(prev, cur)
if isempty(prev)
    combined = localEnsureLLRMatrix(cur);
    return;
end
if isempty(cur)
    combined = localEnsureLLRMatrix(prev);
    return;
end
X = localEnsureLLRMatrix(prev);
Y = localEnsureLLRMatrix(cur);
if isequal(size(X), size(Y))
    combined = X + Y;
    return;
end
% HARQ soft combining is valid only when the retransmission preserves the
% same LDPC code-block layout. Keep the current observation if the stored
% buffer is incompatible instead of manufacturing a malformed combined CB.
combined = Y;
end

function diag = localHARQCombiningDiagnostics(prev, cur, combined)
prevShape = localLLRShape(prev);
curShape = localLLRShape(cur);
combinedShape = localLLRShape(combined);
compatibleShape = ~isempty(prev) && ~isempty(cur) && ...
    isequal(prevShape, curShape) && isequal(curShape, combinedShape);
skipReason = "";
if ~isempty(prev) && ~isempty(cur) && ~compatibleShape
    skipReason = "code_block_layout_mismatch";
end
diag = struct( ...
    "PreviousLLRCount", double(numel(prev)), ...
    "CurrentLLRCount", double(numel(cur)), ...
    "CombinedLLRCount", double(numel(combined)), ...
    "CombiningApplied", compatibleShape, ...
    "CombiningSkipReason", char(skipReason), ...
    "PreviousLLRRows", double(prevShape(1)), ...
    "PreviousLLRCodeBlocks", double(prevShape(2)), ...
    "CurrentLLRRows", double(curShape(1)), ...
    "CurrentLLRCodeBlocks", double(curShape(2)), ...
    "CombinedLLRRows", double(combinedShape(1)), ...
    "CombinedLLRCodeBlocks", double(combinedShape(2)), ...
    "LLRCombiningGain_dB", NaN);
if isempty(cur) || isempty(combined)
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

function [ok, meanIter] = localDecodeCombinedLLR(tx, recLLR, cfg)
ok = false;
meanIter = NaN;
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
[~, crcOk] = sixgr.phy.tb.checkCRC(tbCrc, localSafeCharToken(sixgr.util.structGet(tx, "TransportBlockCRCType", "24A")));
ok = logical(crcOk);
meanIter = mean(itVec(isfinite(itVec)), "omitnan");
end

function X = localEnsureLLRMatrix(v)
X = double(v);
if isvector(X)
    X = X(:);
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

function grant = localBuildHARQGrantSnapshot(tx, mcsIndex, cfg, seedGrant)
if nargin < 4 || ~isstruct(seedGrant)
    seedGrant = struct();
end
pusch = sixgr.util.structGet(tx, "PUSCH", []);
prec = sixgr.util.structGet(tx, "PrecodeInfo", struct());
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
appliedPMI = double(sixgr.util.structGet(prec, "PMI", NaN));
requestedPMI = double(sixgr.util.structGet(seedGrant, "PMI", sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)));
grant = struct( ...
    "MCS", double(mcsIndex), ...
    "MCSIndex", double(sixgr.util.structGet(seedGrant, "MCSIndex", mcsIndex)), ...
    "Modulation", localSafeCharToken(puschMod), ...
    "TargetCodeRate", double(sixgr.util.structGet(tx, "TargetCodeRate", NaN)), ...
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
    "XOverhead", double(sixgr.util.structGet(cfg, "phy.pusch.xOverhead", 0)), ...
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
    "AppliedPrecoderPMI", double(appliedPMI), ...
    "AppliedPrecoderPMIType", localSafeCharToken(sixgr.util.structGet(prec, "PMIType", "")), ...
    "AppliedPrecoderCodebookMode", localSafeCharToken(sixgr.util.structGet(prec, "CodebookMode", "")), ...
    "RequestedVsAppliedPrecoderPMIMatchStatus", localSafeCharToken(localRequestedVsAppliedPMIStatus(requestedPMI, appliedPMI)), ...
    "PrecodingNumPorts", double(sixgr.util.structGet(prec, "NumPorts", numTxAnt)), ...
    "PrecodingNumLayers", double(sixgr.util.structGet(prec, "NumLayers", puschLayers)), ...
    "PrecodingMatrixRows", double(sixgr.util.structGet(prec, "MatrixRows", NaN)), ...
    "PrecodingMatrixCols", double(sixgr.util.structGet(prec, "MatrixCols", NaN)));
preserveFields = ["UEIndex","RNTI","ServingCell","CQIUsed","RIUsed","PMI","CRI","MCSTable","CQITable","AMCMode", ...
    "OuterLoopEnabled","OuterLoopApplied","OLLADeltaMCS","OLLAUpdateCount","OLLAState", ...
    "MCSSelectionSource","CQIProvenance","MCSValueStatus","GrantReason","Frame","Slot","HARQ", ...
    "MCSIndexAuthority","GrantOperatingPointSource", ...
    "PBCHGatingActive","PRACHGatingActive","PDCCHGatingActive","SRSGatingActive","ControlEligible","ControlDecodeOk","GrantControlState", ...
    "CellAcquisitionState","AccessState","SRSValidityState","CSIValidityState","SRSValid","SRSAgeSlots", ...
    "TRSGatingActive","TRSValidityState","TrackingEligibility","TRSAgeSlots","LastSuccessfulTRSSlot","LastEstimatedTRSDopplerHz", ...
    "TRSStateSource","TRSRuntimeConsumer","TRSInfluencedDecision","TRSInfluenceDefinition","TRSReceiverIntegrationStatus","TRSReceiverIntegrationBlocker", ...
    "ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits","MultiplexedHARQACKBits","UCIOnPUSCHApplied","UCIOnPUSCHSource", ...
    "PUCCHCollisionPolicy","PUCCHSourceSlot","PUCCHGrantId","UCIOnPUSCHEvidenceSource", ...
    "GrantContextId","GrantWorkerSafe","GrantSharedStateCommitMode"];
for i = 1:numel(preserveFields)
    fieldName = char(preserveFields(i));
    if isfield(seedGrant, fieldName)
        grant.(fieldName) = seedGrant.(fieldName);
    end
end
if ~(isfield(grant, "GrantContextId") && strlength(strtrim(string(grant.GrantContextId))) > 0)
    grant.GrantContextId = localComposeReplayGrantContextId(seedGrant, "UL");
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

function txArgs = localAppendGrantReplayTxArgs(txArgs, grant)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
carrier = sixgr.util.structGet(grant, "CarrierConfig", []);
pusch = sixgr.util.structGet(grant, "PUSCHConfig", []);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
xOverhead = double(sixgr.util.structGet(grant, "XOverhead", NaN));
numTxAnt = double(sixgr.util.structGet(grant, "NumTxAnt", NaN));
storedTBSize = double(sixgr.util.structGet(grant, "TBSBits", ...
    sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
if ~isempty(carrier)
    txArgs = [txArgs {"Carrier", carrier}]; %#ok<AGROW>
end
if ~isempty(pusch)
    txArgs = [txArgs {"PUSCH", pusch}]; %#ok<AGROW>
end
if isfinite(storedTBSize) && storedTBSize > 0
    txArgs = [txArgs {"TransportBlockSizeOverride", round(storedTBSize)}]; %#ok<AGROW>
end
if isfinite(targetCodeRate) && targetCodeRate > 0
    txArgs = [txArgs {"TargetCodeRate", targetCodeRate}]; %#ok<AGROW>
end
if isfinite(xOverhead) && xOverhead >= 0
    txArgs = [txArgs {"XOverhead", xOverhead}]; %#ok<AGROW>
end
if isfinite(numTxAnt) && numTxAnt >= 1
    txArgs = [txArgs {"NumTxAnt", numTxAnt}]; %#ok<AGROW>
end
end

function token = localComposeReplayGrantContextId(grant, direction)
direction = localSafeCharToken(upper(string(direction)));
if nargin < 1 || ~isstruct(grant)
    grant = struct();
end
rnti = localIntegerToken(sixgr.util.structGet(grant, "RNTI", NaN));
ueIdx = localIntegerToken(sixgr.util.structGet(grant, "UEIndex", NaN));
servingCell = localIntegerToken(sixgr.util.structGet(grant, "ServingCell", NaN));
frame = localIntegerToken(sixgr.util.structGet(grant, "Frame", NaN));
slot = localIntegerToken(sixgr.util.structGet(grant, "Slot", NaN));
grantReason = strtrim(localSafeCharToken(sixgr.util.structGet(grant, "GrantReason", "")));
token = sprintf('%s|cell=%s|ue=%s|rnti=%s|frame=%s|slot=%s', ...
    direction, servingCell, ueIdx, rnti, frame, slot);
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

function localAssertReplayTBConsistency(tbBits, grant, direction)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
expectedBits = double(sixgr.util.structGet(grant, "TransportBlockSize", NaN));
if isfinite(expectedBits) && expectedBits > 0 && numel(tbBits) ~= round(expectedBits)
    error("sixgr:HARQReplay:BadStoredTB", ...
        "%s HARQ replay TB length %d does not match stored transport block size %d.", ...
        upper(string(direction)), numel(tbBits), round(expectedBits));
end
end

function cfgOut = localApplyReplayGrantConfig(cfgIn, grant, direction)
cfgOut = cfgIn;
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
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

if ~(isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end

txAnt = localReplayEffectiveTxAntennas(cfgOut, direction, numLayers);
rxAnt = localReplayEffectiveRxAntennas(cfgOut, direction, numLayers);
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
