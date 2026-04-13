function out = runDLPDSCHThroughput(cfg, varargin)
%RUNDLPDSCHTHROUGHPUT DL PDSCH throughput/BLER sweep at one SNR point.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumFrames", sixgr.util.structGet(cfg, "run.numFrames", 10), @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 18), @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
numFrames = max(1, round(double(p.Results.NumFrames)));
snr_dB = double(p.Results.SNR_dB);

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
out.ConstellationSamples = table();

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
laState = [];
slotDur_s = localSlotDuration(cfg);

trialSeed = NaN(numFrames,1);
trialFrame = (1:numFrames).';
trialSlot = trialFrame;
trialMCS = NaN(numFrames,1);
trialPRB = NaN(numFrames,1);
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
trialCQI = NaN(numFrames,1);
trialRI = NaN(numFrames,1);
trialPMI = NaN(numFrames,1);
trialCRI = NaN(numFrames,1);
trialPMIType = strings(numFrames,1);
trialPMICodebookMode = strings(numFrames,1);
trialCSIReportMode = strings(numFrames,1);
trialCSIPayloadBits = NaN(numFrames,1);
trialCSIPayloadHex = strings(numFrames,1);
trialGain = NaN(numFrames,1);
trialNoise = NaN(numFrames,1);
trialTiming = NaN(numFrames,1);
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
constellationChunks = cell(numFrames,1);
trialStatus = strings(numFrames,1);
trialStatus(:) = "FAIL";
trialCrash = false(numFrames,1);
trialLAApplied = false(numFrames,1);
trialLAScheduled = false(numFrames,1);
trialNotes = strings(numFrames,1);
trialChan = repmat(chanModel, numFrames, 1);
trialDopp = dopplerHz * ones(numFrames,1);

for n = 1:numFrames
    trialSeed(n) = seedBase + n - 1;
    try
        [cfgDyn, laState, laApplyEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "DL", n, "Phase", "before");
        cfgFrame = cfgDyn;
        trialLAApplied(n) = logical(laApplyEvent.Applied);
        trialMCS(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.mcsIndex", NaN));
        trialModulation(n) = string(sixgr.util.structGet(cfgFrame, "phy.pdsch.modulation", ""));
        trialCodeRate(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.codeRate", NaN));
        trialCfgPMI(n) = double(sixgr.util.structGet(cfgFrame, "phy.pdsch.PMI", NaN));
        trialCfgCRI(n) = double(sixgr.util.structGet(cfgFrame, "phy.beamManagement.selectedCRI", NaN));

        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfgFrame);
        if isfield(tx, "PDSCH")
            try
                trialPRB(n) = numel(tx.PDSCH.PRBSet);
            catch
            end
            try
                trialLayers(n) = double(tx.PDSCH.NumLayers);
            catch
            end
        end
        if isfield(tx, "TransportBlockSize")
            trialTB(n) = double(tx.TransportBlockSize);
        end
        if ~chState.Initialized
            chState = localInitChannelState(cfgFrame, tx, txInfo);
        end
        [rxWave, replay] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState, cfgFrame, tx, txInfo);

        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgFrame, ...
            "Carrier", tx.Carrier, ...
            "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "NoiseVar", sixgr.util.structGet(replay, "InjectedNoiseVariance", []), ...
            "SkipTimingEstimate", logical(sixgr.util.structGet(chState, "UseFading", false)));
        replay = localFinalizeImpairmentReplay(replay, cfgFrame, rx, tx, txInfo);

        trialTiming(n) = double(sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", ...
            sixgr.util.structGet(rx, "TimingOffset", NaN)));
        trialNoise(n) = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
        trialInjectedCFO(n) = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
        trialEstimatedCFOPre(n) = double(sixgr.util.structGet(replay, "EstimatedCFO_PreCorrection_Hz", NaN));
        trialResidualCFOPost(n) = double(sixgr.util.structGet(replay, "ResidualCFO_PostCorrection_Hz", NaN));
        trialEstimatedCFO(n) = trialEstimatedCFOPre(n);
        trialTrueCFO(n) = trialInjectedCFO(n);
        trialCFOError(n) = trialResidualCFOPost(n);
        trialInjectedTiming(n) = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN));
        trialEstimatedTimingPre(n) = trialTiming(n);
        trialResidualTimingPost(n) = double(sixgr.util.structGet(replay, "ResidualTimingError_PostCorrection_samples", NaN));
        trialTrueTiming(n) = trialInjectedTiming(n);
        trialTimingError(n) = trialResidualTimingPost(n);
        metrics = localAnalyzeChannelMetrics(sixgr.util.structGet(rx, "ChannelEstimate", []), trialNoise(n), cfgFrame);
        trialNMSE(n) = metrics.NMSE_dB;
        trialDet(n) = metrics.DetectionMetric;
        trialSINR(n) = metrics.SINR_dB;
        trialCQI(n) = metrics.CQI;
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
        if istable(constT) && ~isempty(constT)
            constellationChunks{n} = constT;
        end

        [cfgDyn, laState, laObserveEvent] = sixgr.link.updateLinkAdaptationState(cfgDyn, laState, "DL", n, ...
            "Phase", "after", "Metrics", metrics);
        trialLAScheduled(n) = logical(laObserveEvent.Scheduled);

        txBits = int8(tx.TransportBlock(:));
        rxBits = int8(rx.TransportBlock(:));
        L = min(numel(txBits), numel(rxBits));
        if L == 0
            blockErr = blockErr + 1;
            trialGoodBits(n) = 0;
            if isfinite(trialOfferedBits(n))
                trialGoodput(n) = 0;
            end
            continue;
        end

        be = sum(txBits(1:L) ~= rxBits(1:L));
        trialBitErr(n) = double(be);
        trialBitTot(n) = double(L);
        bitErr = bitErr + double(be);
        bitTot = bitTot + double(numel(txBits));

        if rx.Ok && be == 0 && numel(rxBits) == numel(txBits)
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
            log.warn("runDLPDSCHThroughput frame failed: " + string(ME.message));
        end
    end
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
constellationChunks = constellationChunks(~cellfun(@isempty, constellationChunks));
if ~isempty(constellationChunks)
    out.ConstellationSamples = vertcat(constellationChunks{:});
end

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

out.TrialTable = table( ...
    repmat("DL", numFrames, 1), snr_dB * ones(numFrames,1), trialSeed, trialFrame, trialSlot, ...
    trialMCS, trialPRB, trialLayers, trialModulation, trialCodeRate, trialTB, trialChan, trialDopp, trialCRC, trialDecIt, ...
    trialEVM, trialNMSE, trialDet, trialSINR, trialCQI, trialRI, trialPMI, trialCRI, ...
    trialPMIType, trialPMICodebookMode, trialCSIReportMode, trialCSIPayloadBits, trialCSIPayloadHex, ...
    trialGain, trialNoise, trialTiming, trialRank, trialCond, trialRxAnt, trialTxPorts, ...
    trialSelectedBeam, trialBestBeam, trialBeamHit, trialTopKBeamHit, trialBeamCount, ...
    trialSelectedBeamGain, trialBestBeamGain, trialBeamGap, ...
    trialCfgPMI, trialCfgCRI, trialBitErr, trialBitTot, ...
    trialOfferedBits, trialGoodBits, trialOfferedThr, trialGoodput, ...
    trialComputeLatency, trialProcedureDelay, trialAirInterfaceTTI, ...
    trialLatency, trialDecodeLatency, trialEarlyStop, trialDecoderComplexity, trialNormDecoderComplexity, trialAreaEfficiency, ...
    trialNumCB, trialCBLen, trialSegOccurred, trialSegPadding, trialTBCRC, trialTBWithCRC, trialBaseGraph, ...
    trialEncodedBits, trialRateMatchedBits, trialRateMatchPuncture, trialRateMatchRepetition, ...
    trialCBErr, trialCBCount, trialCBBLER, trialCBGErr, trialCBGCount, trialCBGBLER, ...
    trialPAPR, trialClipEvents, trialSymErr, trialSymTot, trialSER, trialResidualInterference, ...
    trialLLRMeanAbs, trialLLRStdAbs, trialLLRImbalance, trialMapSens, ...
    trialShapeLoss, trialDMLatency, trialHighOrderRobustness, trialDetectorComplexity, ...
    trialDataRECount, trialDMRSRECount, trialPTRSRECount, trialRSOverhead, ...
    trialInjectedCFO, trialEstimatedCFOPre, trialResidualCFOPost, ...
    trialEstimatedCFO, trialTrueCFO, trialCFOError, ...
    trialInjectedTiming, trialEstimatedTimingPre, trialResidualTimingPost, ...
    trialTrueTiming, trialTimingError, ...
    trialEstDoppler, trialDopplerErr, trialPhaseTrackErr, trialQCL, ...
    trialAgingLoss, trialInterpLoss, trialMismatch, ...
    trialStatus, trialCrash, ...
    trialLAApplied, trialLAScheduled, trialNotes, ...
    'VariableNames', {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'MeasuredSINR_dB','WidebandCQI','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
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
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
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

function state = localInitChannelState(cfg, tx, txInfo)
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0);

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

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", sixgr.util.structGet(cfg, "run.seed", 1));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
end
end

function [y, replay] = localApplyChannelAndAwgn(x, snr_dB, state, cfg, tx, txInfo)
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
    "InjectedNoiseVariance", NaN);
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
replay.RawWaveform = y;
replay.CorrectedWaveform = y;
[y, replay.InjectedNoiseVariance] = localAddAwgn(y, snr_dB);
end

function replay = localFinalizeImpairmentReplay(replay, cfg, rx, tx, txInfo)
if nargin < 1 || ~isstruct(replay)
    replay = struct();
end
replay.SampleRate_Hz = localResolveSampleRate(tx, txInfo);
replay.InjectedCFO_Hz = localResolveInjectedCFOHz(cfg);
replay.InjectedTimingOffset_samples = localResolveInjectedTimingOffsetSamples(cfg);
replay.EstimatedCFO_PreCorrection_Hz = replay.InjectedCFO_Hz;
replay.CFOCorrectionApplied = logical(sixgr.util.structGet(cfg, "phy.rx.cfoCompensation", false)) && ...
    isfinite(replay.InjectedCFO_Hz) && replay.InjectedCFO_Hz ~= 0;
if replay.CFOCorrectionApplied
    replay.ResidualCFO_PostCorrection_Hz = 0;
else
    replay.ResidualCFO_PostCorrection_Hz = replay.InjectedCFO_Hz;
end

timingEstimate = double(sixgr.util.structGet(rx, "TimingOffset", NaN));
if ~isfinite(timingEstimate)
    timingEstimate = 0;
end
if replay.InjectedTimingOffset_samples ~= 0
    timingEstimate = double(replay.InjectedTimingOffset_samples);
end
replay.EstimatedTimingOffset_PreCorrection_samples = timingEstimate;
replay.ResidualTimingError_PostCorrection_samples = 0;
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
varNames = {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'MeasuredSINR_dB','WidebandCQI','RankIndicator','PMI','CRI','PMIType','PMICodebookMode', ...
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
varTypes = {'string','double','double','double','double','double','double','double','string','double','double', ...
    'string','double','double','double','double','double','double', ...
    'double','double','double','double','double','string','string', ...
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
end

function metrics = localAnalyzeChannelMetrics(Hest, nVar, cfg)
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
    "ConfiguredCRI", NaN);

if isempty(Hest)
    return;
end

try
    csi = sixgr.phy.dl.CSI_Feedback(Hest, nVar, cfg);
    metrics.SINR_dB = double(sixgr.util.structGet(csi, "SINR_dB", NaN));
    metrics.CQI = double(sixgr.util.structGet(csi, "CQI", NaN));
    metrics.RI = double(sixgr.util.structGet(csi, "RI", NaN));
    metrics.PMI = double(sixgr.util.structGet(csi, "PMI", NaN));
    metrics.CRI = double(sixgr.util.structGet(csi, "CRI", NaN));
    metrics.PMIType = string(sixgr.util.structGet(csi, "PMIType", ""));
    metrics.PMICodebookMode = string(sixgr.util.structGet(csi, "PMICodebookMode", ""));
    metrics.CSIReportMode = string(sixgr.util.structGet(csi, "ChannelStateInformationMode", ""));
    metrics.CSIPayloadBitLength = double(sixgr.util.structGet(csi, "CSIPayloadBitLength", NaN));
    metrics.CSIPayloadHex = char(string(sixgr.util.structGet(csi, "CSIPayloadHex", "")));
    metrics.SelectedBeamIndices = double(sixgr.util.structGet(csi, "SelectedBeamIndices", []));
catch
end

gain = mean(abs(Hest(:)).^2, "omitnan");
if isfinite(gain) && gain > 0
    metrics.ChannelGain_dB = 10 * log10(gain);
    nmseLin = max(double(nVar), eps) / max(gain, eps);
    metrics.NMSE_dB = 10 * log10(max(nmseLin, eps));
    metrics.DetectionMetric = 1 / (1 + nmseLin);
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
selectedMetrics = metric(selectedSet);
[selectedMetric, selectedLocalIdx] = max(selectedMetrics);
selectedIdx = selectedSet(selectedLocalIdx);

beam.BeamCandidateCount = double(size(W, 2));
beam.SelectedBeamIndex = double(selectedIdx);
beam.BestBeamIndex = double(bestIdx);
beam.BeamHit = double(any(selectedSet == bestIdx));
beam.TopKBeamHit = double(any(ismember(ord(1:topK), selectedSet)));
beam.SelectedBeamGain_dB = 10 * log10(max(selectedMetric, eps));
beam.BestBeamGain_dB = 10 * log10(max(bestMetric, eps));
beam.BeamGainGap_dB = beam.BestBeamGain_dB - beam.SelectedBeamGain_dB;
end

function arr = localInferBeamArrayGeometry(cfg, nTx)
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

function selectedSet = localResolveSelectedBeamSet(cfg, W, metrics)
selectedSet = localClampBeamIndexSet(sixgr.util.structGet(metrics, "SelectedBeamIndices", []), size(W, 2));
if ~isempty(selectedSet)
    return;
end

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
