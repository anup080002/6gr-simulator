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
p.addParameter("TransportBlockBits", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
p.addParameter("RV", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0 && x <= 3));
p.addParameter("HARQContext", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("GrantSnapshot", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("PreviousCombinedLLR", [], @(x) isempty(x) || isnumeric(x));
p.addParameter("InterferenceBundle", struct([]), @(x) isempty(x) || isstruct(x));
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
out.ConstellationSamples = table();
out.HARQ = struct();

if ~logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", true))
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.pdsch.enable=true for PDSCH coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.pdsch.enable=false";
    return;
end

if exist("nrPDSCH","file") ~= 2 || exist("nrPDSCHDecode","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrPDSCH/nrPDSCHDecode for PDSCH coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPDSCH APIs unavailable.";
    return;
end

blockErr = 0;
bitErr = 0;
bitTot = 0;
bitGood = 0;
frameCrash = 0;
firstCrashMsg = "";
chState = struct("Initialized", false, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0);
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
trialMeasuredSINRSource = strings(numFrames,1);
trialReceiverHestSINR = NaN(numFrames,1);
trialReceiverHestSINRSource = strings(numFrames,1);
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
trialCQI = NaN(numFrames,1);
trialCQIDerivedMCS = NaN(numFrames,1);
trialCQIDerivedCodeRate = NaN(numFrames,1);
trialRI = NaN(numFrames,1);
trialPMI = NaN(numFrames,1);
trialCRI = NaN(numFrames,1);
trialLinkAdaptationMode = strings(numFrames,1);
trialActualMCSSelectionMode = strings(numFrames,1);
trialSchedulerGrantMCSSelectionMode = strings(numFrames,1);
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
trialTiming = NaN(numFrames,1);
trialConfiguredSNR = snr_dB * ones(numFrames,1);
trialAppliedAWGNSNR = NaN(numFrames,1);
trialAppliedLargeScaleGain = NaN(numFrames,1);
trialAppliedLargeScaleLoss = NaN(numFrames,1);
trialAppliedBasePathloss = NaN(numFrames,1);
trialAppliedPathloss = NaN(numFrames,1);
trialAppliedShadow = NaN(numFrames,1);
trialAppliedO2I = NaN(numFrames,1);
trialAppliedLargeScaleGainSource = strings(numFrames,1);
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
trialRuntimeEvidence = cell(numFrames,1);
csirsRows = repmat(localEmptyCSIRSRuntimeTrialRow(), 0, 1);
constellationChunks = cell(numFrames,1);
waveformChunks = cell(numFrames,1);
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
    try
        if isRetransmission || schedulerDrivenGrant
            cfgFrame = cfgDyn;
            trialLAApplied(n) = false;
        else
            [cfgDyn, laState, laApplyEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "DL", frameIdx, "Phase", "before");
            cfgFrame = cfgDyn;
            trialLAApplied(n) = logical(laApplyEvent.Applied);
        end
        cfgFrame = localApplyReplayGrantConfig(cfgFrame, grantSnapshotOverride, "DL");
        trialMCS(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.mcsIndex", NaN));
        trialModulation(n) = string(sixgr.util.structGet(cfgFrame, "phy.pdsch.modulation", ""));
        trialCodeRate(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.codeRate", NaN));
        trialLinkAdaptationMode(n) = string(localResolveLinkAdaptationMode(cfgFrame, "DL"));
        trialActualMCSSelectionMode(n) = string(localResolveActualMCSSelectionMode(cfgFrame, "DL"));
        trialSchedulerGrantMCSSelectionMode(n) = string(sixgr.util.structGet(grantSnapshotOverride, "AMCMode", ""));
        if schedulerDrivenGrant
            trialLinkAdaptationMode(n) = "scheduler_grant_replay";
            trialActualMCSSelectionMode(n) = "scheduler_grant";
        end
        trialCQITable(n) = string(localResolveCQITable(cfgFrame, "DL"));
        trialMCSTable(n) = string(localResolveMCSTable(cfgFrame, "DL"));
        trialCfgPMI(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.PMI", NaN));
        trialCfgCRI(n) = double(sixgr.util.structGet(cfgFrame, "phy.beamManagement.selectedCRI", NaN));
        trialConfiguredBeamSelectionStrategy(n) = string(sixgr.util.structGet(cfgFrame, "lls6g.userContext.BeamSelectionStrategy", ""));
        if isRetransmission
            [trialMCS(n), trialModulation(n), trialCodeRate(n)] = localOverrideReportedGrantFields( ...
                trialMCS(n), trialModulation(n), trialCodeRate(n), grantSnapshotOverride);
        end

        txArgs = {};
        txArgs = localAppendGrantReplayTxArgs(txArgs, grantSnapshotOverride);
        if ~isempty(transportBlockBits)
            localAssertReplayTBConsistency(transportBlockBits, grantSnapshotOverride, "DL");
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        if ~isempty(rvOverride)
            txArgs = [txArgs {"RV", rvOverride}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfgFrame, txArgs{:});
        grantSnapshot = localBuildHARQGrantSnapshot(tx, trialMCS(n), cfgFrame, grantSnapshotOverride);
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
        trialAppliedPrecoderPMIType(n) = string(dlPrecoding.AppliedPrecoderPMIType);
        trialAppliedPrecoderCodebookMode(n) = string(dlPrecoding.AppliedPrecoderCodebookMode);
        trialPrecodingNumPorts(n) = double(dlPrecoding.PrecodingNumPorts);
        trialPrecodingNumLayers(n) = double(dlPrecoding.PrecodingNumLayers);
        trialPrecodingMatrixRows(n) = double(dlPrecoding.PrecodingMatrixRows);
        trialPrecodingMatrixCols(n) = double(dlPrecoding.PrecodingMatrixCols);
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
                trialModulation(n) = string(tx.PDSCH.Modulation);
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
            chState = localInitChannelState(cfgFrame, tx, txInfo);
        end
        useIdealTimingSync = localUseIdealTimingSync(cfgFrame);
        [rxWave, replay] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState, cfgFrame, tx, txInfo, interferenceBundle);

        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgFrame, ...
            "Carrier", tx.Carrier, ...
            "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, ...
            "CSIRSIndices", sixgr.util.structGet(tx, "CSIRSIndices", []), ...
            "CSIRSSymbols", sixgr.util.structGet(tx, "CSIRSSymbols", []), ...
            "CSIRSInfo", sixgr.util.structGet(tx, "CSIRSInfo", struct()), ...
            "CSIRSTransmitted", logical(sixgr.util.structGet(sixgr.util.structGet(tx, "CSIRSRuntimeEvent", struct()), "Transmitted", false)), ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "NoiseVar", sixgr.util.structGet(replay, "InjectedNoiseVariance", []), ...
            "SkipTimingEstimate", useIdealTimingSync);
        replay = localFinalizeImpairmentReplay(replay, cfgFrame, rx, tx, txInfo, useIdealTimingSync);
        waveformChunks{n} = sixgr.link.buildWaveformPreviewTable("DL", snr_dB, trialFrame(n), trialSlot(n), ...
            tx.Waveform, rxWave, localResolveSampleRate(tx, txInfo));

        trialTiming(n) = double(sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", ...
            sixgr.util.structGet(rx, "TimingOffset", NaN)));
        trialNoise(n) = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
        trialConfiguredSNR(n) = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
        trialAppliedAWGNSNR(n) = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", snr_dB));
        trialAppliedLargeScaleGain(n) = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
        trialAppliedLargeScaleLoss(n) = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
        trialAppliedBasePathloss(n) = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
        trialAppliedPathloss(n) = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
        trialAppliedShadow(n) = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
        trialAppliedO2I(n) = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
        trialAppliedLargeScaleGainSource(n) = string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", ""));
        trialInjectedCFO(n) = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
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
        pilotTrack = localPilotTrackingMetrics(rx);
        metrics = localAnalyzeChannelMetrics(sixgr.util.structGet(rx, "ChannelEstimate", []), trialNoise(n), cfgFrame, rx);
        trialNMSE(n) = metrics.NMSE_dB;
        trialDet(n) = metrics.DetectionMetric;
        trialSINR(n) = metrics.SINR_dB;
        trialReceiverHestSINR(n) = metrics.SINR_dB;
        if isfinite(trialSINR(n))
            trialMeasuredSINRSource(n) = "receiver_hest_csi_feedback_wideband_effective_sinr";
            trialReceiverHestSINRSource(n) = trialMeasuredSINRSource(n);
            trialSINRValueRole(n) = "estimated";
            trialSINRSource(n) = trialMeasuredSINRSource(n);
        end
        trialCSIRSRP(n) = metrics.CSI_RSRP_dB;
        trialCSIRSRPSource(n) = string(metrics.CSI_RSRPSource);
        csirsRow = localBuildCSIRSRuntimeTrialRow(cfgFrame, grantSnapshot, tx, rx, metrics, ...
            frameIdx, trialSlot(n), snr_dB, slotDur_s);
        if logical(csirsRow.RuntimeEventObserved)
            csirsRows(end+1, 1) = csirsRow; %#ok<AGROW>
        end
        trialCQI(n) = metrics.CQI;
        if isfinite(trialCQI(n)) && trialCQI(n) >= 0
            [cqiMod, cqiRate, cqiMCS] = sixgr.link.amcFromCQI(trialCQI(n), "", NaN, cfgFrame, "DL");
            trialCQIDerivedMCS(n) = double(cqiMCS);
            trialCQIDerivedCodeRate(n) = double(cqiRate);
            trialCQIDerivedModulation(n) = string(cqiMod);
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
        trialRuntimeEvidence{n} = localBuildRuntimeAntennaTimingEvidence("DL", cfgFrame, grantSnapshot, tx, txInfo, chState, replay);

        coding = sixgr.link.deriveCodingTrialMetrics(tx, txInfo, rx, cfgFrame);
        trialDecIt(n) = double(sixgr.util.structGet(coding, "DecoderIterations", NaN));
        trialOfferedBits(n) = double(sixgr.util.structGet(coding, "OfferedBits", NaN));
        trialComputeLatency(n) = double(sixgr.util.structGet(coding, "ComputeLatency_ms", ...
            sixgr.util.structGet(coding, "Latency_ms", NaN)));
        trialProcedureDelay(n) = double(sixgr.util.structGet(coding, "ProcedureDelay_ms", NaN));
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
        [modTrack, constT] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfgFrame, "DL");
        trialEVM(n) = double(sixgr.util.structGet(modTrack, "EVM_rms", trialEVM(n)));
        [trialDecoderTruthProxySINR(n), decoderTruthProxyMeta] = sixgr.link.deriveDecoderTruthProxySINR(modTrack);
        trialDecoderTruthProxySINRSource(n) = string(sixgr.util.structGet(decoderTruthProxyMeta, "Source", ""));
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
            constT.Frame = repmat(double(trialFrame(n)), height(constT), 1);
            constT.Slot = repmat(double(trialSlot(n)), height(constT), 1);
            constellationChunks{n} = constT;
        end

        if isRetransmission || schedulerDrivenGrant
            trialLAScheduled(n) = false;
        else
            [cfgDyn, laState, laObserveEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "DL", frameIdx, ...
                "Phase", "after", "Metrics", metrics);
            trialLAScheduled(n) = logical(laObserveEvent.Scheduled);
        end

        txBits = int8(tx.TransportBlock(:));
        rxBits = int8(rx.TransportBlock(:));
        currentRecLLR = sixgr.util.structGet(rx, "RecLLR", []);
        combinedLLR = localCombineRateRecoveredLLR(previousCombinedLLR, currentRecLLR);
        [combinedDecodeOK, combinedDecodeIt] = localDecodeCombinedLLR(tx, combinedLLR, cfgFrame);
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

        currentDecodeOK = rx.Ok && be == 0 && numel(rxBits) == numel(txBits);
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
        lastHARQ = struct( ...
            "TransportBlockBits", txBits, ...
            "CombinedLLR", combinedLLR, ...
            "CurrentDecodeOK", logical(currentDecodeOK), ...
            "CombinedDecodeOK", logical(currentDecodeOK || combinedDecodeOK), ...
            "DecoderIterations", combinedDecodeIt, ...
            "GrantSnapshot", grantSnapshot, ...
            "Context", harqContext);
    catch ME
        blockErr = blockErr + 1;
        frameCrash = frameCrash + 1;
        detail = string(ME.message);
        if ~isempty(ME.stack)
            detail = detail + " [" + string(ME.stack(1).name) + ":" + string(ME.stack(1).line) + "]";
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
out.Throughput_Mbps = (bitGood / max(simDur_s, eps)) / 1e6;
out.Goodput_Mbps = out.Throughput_Mbps;
offeredBits = sum(trialOfferedBits(isfinite(trialOfferedBits)), "omitnan");
out.OfferedThroughput_Mbps = (offeredBits / max(simDur_s, eps)) / 1e6;
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
        "Strict mode forbids skipping PDSCH coverage because every frame crashed: " + firstCrashMsg);
    out.Skipped = true;
    out.Ok = true;
    out.BER = NaN;
    out.BLER = NaN;
    out.Throughput_Mbps = NaN;
    out.Notes = "Skipped: DL chain unsupported in this release (" + firstCrashMsg + ")";
end

out.TrialTable = localBuildTrialSlice(numFrames);
out.CSIRSTrialTable = localBuildCSIRSTrialTable(csirsRows);

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
            trialLinkAdaptationMode(idx), trialActualMCSSelectionMode(idx), trialSchedulerGrantMCSSelectionMode(idx), trialCQITable(idx), trialMCSTable(idx), ...
            trialRI(idx), trialPMI(idx), trialCRI(idx), ...
            trialPMIType(idx), trialPMICodebookMode(idx), trialCSIReportMode(idx), trialCSIPayloadBits(idx), trialCSIPayloadHex(idx), ...
            trialGain(idx), trialNoise(idx), trialTiming(idx), trialRank(idx), trialCond(idx), trialRxAnt(idx), trialTxPorts(idx), ...
            trialSelectedBeam(idx), trialBestBeam(idx), trialBeamHit(idx), trialTopKBeamHit(idx), trialBeamCount(idx), ...
            trialSelectedBeamGain(idx), trialBestBeamGain(idx), trialBeamGap(idx), ...
            trialCfgPMI(idx), trialCfgCRI(idx), trialBitErr(idx), trialBitTot(idx), ...
            trialOfferedBits(idx), trialGoodBits(idx), trialOfferedThr(idx), trialGoodput(idx), ...
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
            trialEstDoppler(idx), trialDopplerErr(idx), trialPhaseTrackErr(idx), trialQCL(idx), ...
            trialAgingLoss(idx), trialInterpLoss(idx), trialMismatch(idx), ...
            trialStatus(idx), trialCrash(idx), ...
            trialLAApplied(idx), trialLAScheduled(idx), trialNotes(idx), ...
            'VariableNames', {'Direction','SNR_dB','SFN','UEIndex','RNTI','BaseStationID','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
            'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
            'MeasuredSINR_dB','WidebandCQI','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
            'LinkAdaptationMode','ActualMCSSelectionMode','SchedulerGrantMCSSelectionMode','CQITable','MCSTable','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
            'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','ChannelGain_dB','NoiseVariance', ...
            'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
            'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
            'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
            'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
            'OfferedBits','GoodBits','OfferedThroughput_Mbps','Goodput_Mbps', ...
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
            'EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
            'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB', ...
            'Status','Crash', ...
            'LinkAdaptationApplied','LinkAdaptationScheduled','Notes'});
        T.ConfiguredSNR_dB = trialConfiguredSNR(idx);
        T.AllocatedPRBCount = trialPRB(idx);
        T.PRBStart = trialPRBStart(idx);
        T.AppliedAWGNSNR_dB = trialAppliedAWGNSNR(idx);
        T.ReceiverHestSINR_dB = trialReceiverHestSINR(idx);
        T.ReceiverHestSINRSource = trialReceiverHestSINRSource(idx);
        T.DecoderTruthProxySINR_dB = trialDecoderTruthProxySINR(idx);
        T.DecoderTruthProxySINRSource = trialDecoderTruthProxySINRSource(idx);
        T.SINRValueRole = trialSINRValueRole(idx);
        T.SINRSource = trialSINRSource(idx);
        T.MeasuredTrialSINR_dB = trialSINR(idx);
        T.MeasuredTrialSINRSource = trialMeasuredSINRSource(idx);
        T.LargeScaleSINR_dB = trialLargeScaleSINR(idx);
        T.LargeScaleSINRSource = trialLargeScaleSINRSource(idx);
        T.ServingRSRP_dBm = trialServingRSRP(idx);
        T.ServingRSRPSource = trialServingRSRPSource(idx);
        T.CSI_RSRP_dB = trialCSIRSRP(idx);
        T.CSI_RSRPSource = trialCSIRSRPSource(idx);
        T.AppliedLargeScaleGain_dB = trialAppliedLargeScaleGain(idx);
        T.AppliedLargeScaleLoss_dB = trialAppliedLargeScaleLoss(idx);
        T.AppliedBasePathloss_dB = trialAppliedBasePathloss(idx);
        T.AppliedPathloss_dB = trialAppliedPathloss(idx);
        T.AppliedShadowFading_dB = trialAppliedShadow(idx);
        T.AppliedO2I_dB = trialAppliedO2I(idx);
        T.AppliedLargeScaleGainSource = trialAppliedLargeScaleGainSource(idx);
        T.TimingEstimateUsed = trialTimingEstimateUsed(idx);
        T.UseIdealTimingSync = trialUseIdealTimingSync(idx);
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
        T = localDecorateTrialTruthFields(T, "DL", cfg);
    end
end

function [y, nVar] = localAddAwgn(x, replay, referenceWaveform)
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "configured_snr_anchor_after_large_scale_gain"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localResolveThermalNoiseVariance(replay, referenceWaveform);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
end
[y, nVar] = sixgr.util.addAwgnComplex(x, double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN)));
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
requestedPMI = double(localOptionalColumn(T, "PMI", NaN));
configuredPMI = double(localOptionalColumn(T, "ConfiguredPMI", NaN));
configuredMask = ~isfinite(requestedPMI) & isfinite(configuredPMI);
requestedPMI(configuredMask) = configuredPMI(configuredMask);
T.RequestedPrecoderPMI = requestedPMI;
T.RequestedPrecoderSource = repmat("", n, 1);
T.RequestedPrecoderSource(isfinite(double(localOptionalColumn(T, "PMI", NaN)))) = "scheduler_grant_or_csi_feedback_request";
T.RequestedPrecoderSource(configuredMask) = "configured_pmi_reference";
T.AppliedPrecoderSource = string(localOptionalColumn(T, "PrecoderSource", ""));
T = localDecorateBeamAndPrecoderTruthFields(T, direction);
configuredLinkMode = repmat(localResolveLinkAdaptationMode(cfg, direction), n, 1);
configuredSelectionMode = repmat(localResolveActualMCSSelectionMode(cfg, direction), n, 1);
T.ConfiguredLinkAdaptationMode = configuredLinkMode;
T.ConfiguredMCSSelectionPolicy = configuredSelectionMode;
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
row.ResourceID = double(sixgr.util.structGet(txEvent, "ResourceID", sixgr.util.structGet(rxObs, "ResourceID", 0)));
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
if row.Observed && strcmpi(string(sixgr.util.structGet(metrics, "CSI_RSRPSource", "")), "received_reference_signal_power")
    row.Consumed = true;
    row.Consumer = "csi_feedback_reference_power_measurement";
end
row.MeasurementRSRP_dB = double(sixgr.util.structGet(rxObs, "MeasurementRSRP_dB", NaN));
if ~isfinite(row.MeasurementRSRP_dB)
    row.MeasurementRSRP_dB = double(sixgr.util.structGet(metrics, "CSI_RSRP_dB", NaN));
end
row.MeasurementSource = string(sixgr.util.structGet(rxObs, "MeasurementSource", ""));
row.UpdateOutcome = string(sixgr.util.structGet(rxObs, "UpdateOutcome", sixgr.util.structGet(txEvent, "UpdateOutcome", "")));
row.RuntimeMaterializationStatus = string(sixgr.util.structGet(txEvent, "RuntimeMaterializationStatus", ...
    sixgr.util.structGet(rxObs, "RuntimeMaterializationStatus", "")));
row.RuntimeBlocker = string(sixgr.util.structGet(txEvent, "Blocker", sixgr.util.structGet(rxObs, "Blocker", "")));
row.RuntimeEvidenceSource = string(sixgr.util.structGet(rxObs, "RuntimeEvidenceSource", ...
    sixgr.util.structGet(txEvent, "RuntimeEvidenceSource", "")));
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
    "MeasurementRSRP_dB", NaN, "MeasurementSource", "", "UpdateOutcome", "", ...
    "RuntimeMaterializationStatus", "", "RuntimeBlocker", "", "RuntimeEvidenceSource", "", ...
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
values(actualMode == "configured_fixed") = "configured_fixed_mcs";
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
row.RuntimeTraceSource = "runDLPDSCHThroughput_active_trial";
row.AntennaEvidenceSource = "active_runtime_user_context";
row.SameFlowEvidenceSource = "CoupledTruthRuntime.applyUserContextImpl->runDLPDSCHThroughput";
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
timingEstimate = double(sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", NaN));
if ~(isfinite(sampleRate) && sampleRate > 0 && isfinite(timingEstimate))
    return;
end
toaEstimate_s = slotStart_s + max(0, timingEstimate) / sampleRate;
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

function state = localInitChannelState(cfg, tx, txInfo)
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0, ...
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

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", sixgr.util.structGet(cfg, "run.seed", 1), ...
    "TransmitAntennaRuntime", sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct()), ...
    "ReceiveAntennaRuntime", sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct()), ...
    "TransmitAntennaMeta", sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct()), ...
    "ReceiveAntennaMeta", sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct()));
state.Meta = localNormalizeChannelRuntimeMeta(sixgr.util.structGet(ch, "Meta", struct()), localResolveChannelArrayModel(cfgCh));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
end
end

function [y, replay] = localApplyChannelAndAwgn(x, snr_dB, state, cfg, tx, txInfo, interferenceBundle)
y = x;
replay = struct( ...
    "RawWaveform", x, ...
    "CorrectedWaveform", x, ...
    "InjectedCFO_Hz", NaN, ...
    "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "ResidualCFO_PostCorrection_Hz", NaN, ...
    "InjectedTimingOffset_samples", NaN, ...
    "EstimatedTimingOffset_PreCorrection_samples", NaN, ...
    "ResidualTimingError_PostCorrection_samples", NaN, ...
    "SampleRate_Hz", localResolveSampleRate(tx, txInfo), ...
    "CFOCorrectionApplied", false, ...
    "InjectedNoiseVariance", NaN, ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "AppliedLargeScaleLoss_dB", 0, ...
    "AppliedLargeScaleGain_dB", 0, ...
    "AppliedBasePathloss_dB", NaN, ...
    "AppliedPathloss_dB", NaN, ...
    "AppliedShadowFading_dB", NaN, ...
    "AppliedO2I_dB", NaN, ...
    "AppliedLargeScaleGainSource", "none", ...
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
    "InterferenceUsesSameRuntimeAntennaAssumptions", false);
if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    try
        reset(state.Obj);
    catch
    end
    xIn = x;
    padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
    trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
    if padSamples > 0
        xIn = [x; zeros(padSamples, size(x,2), 'like', x)];
    end
    try
        yRaw = state.Obj(xIn);
    catch
        [yRaw, ~] = state.Obj(xIn);
    end
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
if ~(isscalar(appliedSNR) && isfinite(appliedSNR))
    replay.AppliedAWGNSNR_dB = double(snr_dB);
end
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
desiredWaveform = y;
[interferenceWaveform, interferenceMeta] = sixgr.link.synthesizeInterferenceWaveform("DL", desiredWaveform, replay, interferenceBundle);
if ~isempty(interferenceWaveform)
    y = y + cast(interferenceWaveform, "like", y);
end
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
[y, replay.InjectedNoiseVariance] = localAddAwgn(y, replay, desiredWaveform);
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
timingEstimateUsed = logical(sixgr.util.structGet(rx, "TimingEstimateUsed", isfinite(timingEstimate)));
if timingEstimateUsed
    replay.UseIdealTimingSync = false;
end
if ~timingEstimateUsed || ~isfinite(timingEstimate)
    replay.TimingEstimateUsed = false;
    replay.EstimatedTimingOffset_PreCorrection_samples = NaN;
    if isfinite(replay.InjectedTimingOffset_samples)
        replay.ResidualTimingError_PostCorrection_samples = double(replay.InjectedTimingOffset_samples);
    else
        replay.ResidualTimingError_PostCorrection_samples = NaN;
    end
    return;
end
replay.TimingEstimateUsed = true;
replay.EstimatedTimingOffset_PreCorrection_samples = timingEstimate;
if isfinite(replay.InjectedTimingOffset_samples)
    replay.ResidualTimingError_PostCorrection_samples = double(replay.InjectedTimingOffset_samples) - timingEstimate;
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
timingOffset = round(timingOffset);
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

function nVar = localResolveThermalNoiseVariance(replay, referenceWaveform)
nVar = NaN;
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
if ~(isfinite(servingRxPower_dBm) && isfinite(thermalNoisePower_dBm))
    return;
end
referencePower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
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
% Pad for the full channel memory so we retain late multipath energy, but
% only pre-trim the implementation filter delay. The physical path delay
% must remain visible to timing/channel estimation on fading channels.
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

function T = localEmptyTrialTable()
varNames = {'Direction','SNR_dB','SFN','UEIndex','RNTI','BaseStationID','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'MeasuredSINR_dB','WidebandCQI','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
    'LinkAdaptationMode','ActualMCSSelectionMode','CQITable','MCSTable','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
    'CSIReportMode','CSIPayloadBitLength','CSIPayloadHex','ChannelGain_dB','NoiseVariance', ...
    'TimingOffset_samples','RankEstimate','ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
    'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
    'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
    'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
    'OfferedBits','GoodBits','OfferedThroughput_Mbps','Goodput_Mbps', ...
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
    'EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
    'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB', ...
    'Status','Crash','LinkAdaptationApplied','LinkAdaptationScheduled','Notes'};
varTypes = {'string','double','double','double','double','double','double','double','double','double','double','double','string','double','double', ...
    'string','double','double','double','double','double','double', ...
    'double','double','double','string','double','string','string','string','string','double','double','double','string','string', ...
    'string','double','string','double','double', ...
    'double','double','double','double','double', ...
    'double','double','double','double','double','double','double','double', ...
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
    'double','double','double','double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'string','logical','logical','logical','string'};
T = table('Size', [0, numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
T.ConfiguredSNR_dB = zeros(0,1);
T.AppliedAWGNSNR_dB = zeros(0,1);
T.ReceiverHestSINR_dB = zeros(0,1);
T.ReceiverHestSINRSource = strings(0,1);
T.DecoderTruthProxySINR_dB = zeros(0,1);
T.DecoderTruthProxySINRSource = strings(0,1);
T.SINRValueRole = strings(0,1);
T.SINRSource = strings(0,1);
T.MeasuredTrialSINR_dB = zeros(0,1);
T.MeasuredTrialSINRSource = strings(0,1);
T.LargeScaleSINR_dB = zeros(0,1);
T.LargeScaleSINRSource = strings(0,1);
T.ServingRSRP_dBm = zeros(0,1);
T.ServingRSRPSource = strings(0,1);
T.CSI_RSRP_dB = zeros(0,1);
T.CSI_RSRPSource = strings(0,1);
T.AppliedLargeScaleGain_dB = zeros(0,1);
T.AppliedLargeScaleLoss_dB = zeros(0,1);
T.AppliedBasePathloss_dB = zeros(0,1);
T.AppliedPathloss_dB = zeros(0,1);
T.AppliedShadowFading_dB = zeros(0,1);
T.AppliedO2I_dB = zeros(0,1);
T.AppliedLargeScaleGainSource = strings(0,1);
T.TimingEstimateUsed = false(0,1);
T.UseIdealTimingSync = false(0,1);
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
    mode = "cqi_driven";
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
trace = struct( ...
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
    "PrecodingMatrixCols", double(sixgr.util.structGet(prec, "MatrixCols", sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN))));
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

function metrics = localAnalyzeChannelMetrics(Hest, nVar, cfg, rx)
if nargin < 4
    rx = struct();
end
metrics = struct( ...
    "NMSE_dB", NaN, ...
    "DetectionMetric", NaN, ...
    "SINR_dB", NaN, ...
    "CQI", NaN, ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "PMIType", "", ...
    "PMICodebookMode", "", ...
    "CSIReportMode", "", ...
    "CSIPayloadBitLength", NaN, ...
    "CSIPayloadHex", "", ...
    "ChannelGain_dB", NaN, ...
    "RankEstimate", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "NumRxAnt", NaN, ...
    "NumTxPorts", NaN, ...
    "SelectedBeamIndices", [], ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "BeamHit", NaN, ...
    "TopKBeamHit", NaN, ...
    "BeamCandidateCount", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "ConfiguredPMI", NaN, ...
    "ConfiguredCRI", NaN, ...
    "CSI_RSRP_dB", NaN, ...
    "CSI_RSRPSource", "");

if isempty(Hest)
    return;
end

try
    csiArgs = localBuildCSIFeedbackArgs(rx);
    csiArgs = [{"Direction", "DL"}, csiArgs];
    csi = sixgr.phy.dl.CSI_Feedback(Hest, nVar, cfg, csiArgs{:});
    metrics.SINR_dB = double(sixgr.util.structGet(csi, "SINR_dB", NaN));
    metrics.CQI = double(sixgr.util.structGet(csi, "CQI", NaN));
    metrics.RI = double(sixgr.util.structGet(csi, "RI", NaN));
    metrics.PMI = double(sixgr.util.structGet(csi, "PMI", NaN));
    metrics.CRI = double(sixgr.util.structGet(csi, "CRI", NaN));
    metrics.CSI_RSRP_dB = double(sixgr.util.structGet(csi, "RSRP_dB", NaN));
    metrics.CSI_RSRPSource = string(sixgr.util.structGet(csi, "RSRPSource", ""));
    metrics.PMIType = string(sixgr.util.structGet(csi, "PMIType", ""));
    metrics.PMICodebookMode = string(sixgr.util.structGet(csi, "PMICodebookMode", ""));
    metrics.CSIReportMode = string(sixgr.util.structGet(csi, "ChannelStateInformationMode", ""));
    metrics.CSIPayloadBitLength = double(sixgr.util.structGet(csi, "CSIPayloadBitLength", NaN));
    metrics.CSIPayloadHex = localSafeCharToken(sixgr.util.structGet(csi, "CSIPayloadHex", ""));
    metrics.SelectedBeamIndices = double(sixgr.util.structGet(csi, "SelectedBeamIndices", []));
catch
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

function args = localBuildCSIFeedbackArgs(rx)
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
    "BeamGainGap_dB", NaN);

if isempty(Hwb) || ~ismatrix(Hwb)
    return;
end
nTx = size(Hwb, 2);
if ~(isfinite(nTx) && nTx >= 1)
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

configuredPMI = double(sixgr.util.structGet(cfg, "phy.pdsch.PMI", sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)));
if isfinite(configuredPMI)
    selectedSet = localResolveBeamSetFromPMI(cfg, struct("PMI", configuredPMI, "RI", metrics.RI), size(W, 1), size(W, 2));
    if ~isempty(selectedSet)
        return;
    end
end

selectedIdx = NaN;
try
    prec = sixgr.util.structGet(cfg, "phy.pdsch.precoding.matrix", []);
    if ~isempty(prec) && size(prec, 1) == size(W, 1)
        refVec = double(prec(:, 1));
        proj = abs((refVec' * double(W))).^2;
        [~, selectedIdx] = max(proj);
    end
catch
    selectedIdx = NaN;
end
if isfinite(selectedIdx)
    selectedSet = localClampBeamIndexSet(selectedIdx, size(W, 2));
    if ~isempty(selectedSet)
        return;
    end
end

if isfinite(metrics.CRI)
    selectedSet = localClampBeamIndexSet(metrics.CRI + 1, size(W, 2));
    if ~isempty(selectedSet)
        return;
    end
end

selectedSet = 1;
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

function combined = localCombineRateRecoveredLLR(prev, cur)
if isempty(prev)
    combined = cur;
    return;
end
if isempty(cur)
    combined = prev;
    return;
end
X = localEnsureLLRMatrix(prev);
Y = localEnsureLLRMatrix(cur);
nRow = max(size(X, 1), size(Y, 1));
nCol = max(size(X, 2), size(Y, 2));
X(end+1:nRow, end+1:nCol) = 0;
Y(end+1:nRow, end+1:nCol) = 0;
combined = X + Y;
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
decCbs = zeros(nRow, nCB, 'int8');
itVec = NaN(nCB, 1);
maxLen = 0;
alg = localSafeCharToken(sixgr.util.structGet(cfg, "phy.ldpc.algorithm", "Normalized min-sum"));
maxIter = double(sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", 8));
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

function grant = localBuildHARQGrantSnapshot(tx, mcsIndex, cfg, seedGrant)
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
scheduledTBSize = double(sixgr.util.structGet(tx, "TransportBlockSize", NaN));
numTxAnt = NaN;
if isfield(tx, "Grid") && ~isempty(tx.Grid)
    numTxAnt = double(size(tx.Grid, 3));
end
pdschMod = localObjectValue(pdsch, "Modulation", "");
pdschLayers = localObjectValue(pdsch, "NumLayers", NaN);
pdschPRBSet = localObjectValue(pdsch, "PRBSet", []);
pdschSymbolAllocation = localObjectValue(pdsch, "SymbolAllocation", []);
pdschMappingType = localObjectValue(pdsch, "MappingType", "");
grant = struct( ...
    "MCS", double(mcsIndex), ...
    "MCSIndex", double(sixgr.util.structGet(seedGrant, "MCSIndex", mcsIndex)), ...
    "Modulation", localSafeCharToken(pdschMod), ...
    "TargetCodeRate", double(sixgr.util.structGet(tx, "TargetCodeRate", NaN)), ...
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
    "TBSBytes", floor(double(tbSizeActual) / 8), ...
    "XOverhead", double(sixgr.util.structGet(cfg, "phy.pdsch.xOverhead", 0)), ...
    "NumTxAnt", double(numTxAnt), ...
    "PrecodingMatrix", sixgr.util.structGet(prec, "MatrixNR", sixgr.util.structGet(prec, "Matrix", [])), ...
    "ConfiguredBeamSelectionStrategy", localSafeCharToken(sixgr.util.structGet(cfg, "lls6g.userContext.BeamSelectionStrategy", "")), ...
    "PrecoderSource", localSafeCharToken(sixgr.util.structGet(prec, "Source", "none")), ...
    "PrecodingMode", localSafeCharToken(sixgr.util.structGet(prec, "Mode", "siso-bypass")), ...
    "PrecodingApplicationStage", localSafeCharToken(sixgr.util.structGet(prec, "ApplicationStage", "none")), ...
    "PrecodingActive", logical(sixgr.util.structGet(prec, "Active", false)), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(prec, "Active", false)), ...
    "TransformPrecodingApplied", false, ...
    "BeamformingApplied", logical(sixgr.util.structGet(prec, "Active", false)), ...
    "AppliedBeamIndexSet", char(localFormatIndexSet(sixgr.util.structGet(prec, "BeamIndices", []))), ...
    "AppliedPrecoderPMI", double(sixgr.util.structGet(prec, "PMI", NaN)), ...
    "AppliedPrecoderPMIType", localSafeCharToken(sixgr.util.structGet(prec, "PMIType", "")), ...
    "AppliedPrecoderCodebookMode", localSafeCharToken(sixgr.util.structGet(prec, "CodebookMode", "")), ...
    "PrecodingNumPorts", double(sixgr.util.structGet(prec, "NumPorts", NaN)), ...
    "PrecodingNumLayers", double(sixgr.util.structGet(prec, "NumLayers", NaN)), ...
    "PrecodingMatrixRows", double(sixgr.util.structGet(prec, "MatrixRows", NaN)), ...
    "PrecodingMatrixCols", double(sixgr.util.structGet(prec, "MatrixCols", NaN)));
preserveFields = ["UEIndex","RNTI","ServingCell","CQIUsed","RIUsed","PMI","CRI","MCSTable","CQITable","AMCMode","GrantReason","Frame","Slot","HARQ", ...
    "PBCHGatingActive","PRACHGatingActive","PDCCHGatingActive","SRSGatingActive","ControlEligible","ControlDecodeOk","GrantControlState", ...
    "CellAcquisitionState","AccessState","SRSValidityState","CSIValidityState","SRSValid","SRSAgeSlots", ...
    "TRSGatingActive","TRSValidityState","TrackingEligibility","TRSAgeSlots","LastSuccessfulTRSSlot","LastEstimatedTRSDopplerHz", ...
    "TRSStateSource","TRSRuntimeConsumer","TRSInfluencedDecision","TRSInfluenceDefinition","TRSReceiverIntegrationStatus","TRSReceiverIntegrationBlocker", ...
    "GrantContextId","GrantWorkerSafe","GrantSharedStateCommitMode"];
for i = 1:numel(preserveFields)
    fieldName = char(preserveFields(i));
    if isfield(seedGrant, fieldName)
        grant.(fieldName) = seedGrant.(fieldName);
    end
end
if ~(isfield(grant, "GrantContextId") && strlength(strtrim(string(grant.GrantContextId))) > 0)
    grant.GrantContextId = localComposeReplayGrantContextId(seedGrant, "DL");
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
pdsch = sixgr.util.structGet(grant, "PDSCHConfig", []);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
xOverhead = double(sixgr.util.structGet(grant, "XOverhead", NaN));
numTxAnt = double(sixgr.util.structGet(grant, "NumTxAnt", NaN));
precodingMatrix = sixgr.util.structGet(grant, "PrecodingMatrix", []);
if ~isempty(carrier)
    txArgs = [txArgs {"Carrier", carrier}]; %#ok<AGROW>
end
if ~isempty(pdsch)
    txArgs = [txArgs {"PDSCH", pdsch}]; %#ok<AGROW>
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
if ~isempty(precodingMatrix)
    txArgs = [txArgs {"PrecodingMatrix", precodingMatrix}]; %#ok<AGROW>
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
    if isfinite(pmi)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", pmi);
    end
    if isfinite(cri)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", cri);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", cri);
    end
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", precodingMatrix);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", precodingMatrix);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", precodingMatrix);
    if ~isempty(precodingMatrix)
        nPorts = localReplayPrecodingPortCount(precodingMatrix, numLayers);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nPorts);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nPorts);
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
