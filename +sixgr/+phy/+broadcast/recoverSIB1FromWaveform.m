function [result, mibContext] = recoverSIB1FromWaveform(rxWaveform, cfg, varargin)
%RECOVERSIB1FROMWAVEFORM Recover MIB, SI-RNTI DCI, PDSCH/DL-SCH, and SIB1.

% Streaming callers may submit a completed observation. Keep this guard
% outside decoder error recovery: an incomplete capture is not a failed
% BCH/SIB1 trial, and must not create a CRC/BLER row.
mibContext=[];
originalCapture=rxWaveform;
captureStartSample=NaN;
if isa(rxWaveform, 'sixgr.phy.waveform.WaveformObservationBuffer')
    captureStartSample=rxWaveform.StartSample;
    rxWaveform = rxWaveform.readComplete();
end

p = inputParser;
p.addParameter('RecoveryScope',"SSB_MIB_SIB1",@(x) ...
    (ischar(x)||isstring(x)) && isscalar(string(x)) && ...
    any(string(x)==["SSB_MIB_SIB1","SSB_MIB"]));
p.addParameter("ReceiverRNTI", 65535, @(x) isnumeric(x) && isscalar(x));
p.addParameter("FaultMode", "", @(x) ischar(x) || isstring(x));
p.addParameter('PhysicalMeasurementObservation',[],@(x)isempty(x) || ...
    (isa(x,'sixgr.phy.waveform.WaveformObservationBuffer') && isscalar(x)));
p.addParameter("CandidateSSBIndex", [], ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && x == round(x)));
p.parse(varargin{:});
sixgr.runtime.RuntimeCallLedger.record( ...
    "sixgr.phy.broadcast.recoverSIB1FromWaveform", "SIB1", "DL", ...
    struct("Stage","RX","RecoveryScope",string(p.Results.RecoveryScope)));
physicalSamples=[];
if ~isempty(p.Results.PhysicalMeasurementObservation)
    physicalSamples=p.Results.PhysicalMeasurementObservation.readComplete();
    if ~isequal(size(physicalSamples),size(rxWaveform))
        error('sixgr:phy:broadcast:MeasurementPlaneLayout','Physical and decoder observations need identical receive antenna and sample layouts.');
    end
end

result = localEmptyResult();
powerReceipt=sixgr.phy.refsig.buildSSBPowerMeasurementReceipt();
for name=string(fieldnames(powerReceipt)).'
    result.(name)=powerReceipt.(name);
end
frequencyEvidence=sixgr.phy.broadcast.measurePBCHResidualFrequency();
for name=string(fieldnames(frequencyEvidence)).'
    result.(name)=frequencyEvidence.(name);
end
evidence = sixgr.phy.sync.ssbDetectionEvidence();
for name = string(fieldnames(evidence)).'
    result.(name) = evidence.(name);
end
result.RecoveryScope=string(p.Results.RecoveryScope);
result.SIB1ReceptionAttempted=false;
result.SIB1ObservationComplete=false;
result.SIB1ObservationStatus="not_evaluated";
result.SIB1ObservationStartSample=NaN;
result.SIB1ObservationEndSampleExclusive=NaN;
result.SIB1CaptureStartSample=captureStartSample;
result.ReceivedFrameOriginInCapture_samples=NaN;
result.SIB1RadioFrameClock="not_resolved";
result.Type0FrameNumberSource="not_resolved";
result.SIB1ObservationSampleDomain="relative_to_original_received_capture_start_zero_based";
result.SIB1AvailableCaptureSamples=size(rxWaveform,1);
result.SSBMIBComplete=false;
result.Status = "started";
try
    [siSupported, siReason] = sixgr.phy.broadcast.siRNTIWaveformSupported();
    if ~siSupported && result.RecoveryScope=="SSB_MIB_SIB1"
        result.Status = "unsupported_si_rnti_waveform";
        result.FailureReason = string(siReason);
        result.Errors = string(siReason);
        result.StrictOk = false;
        return;
    end
    cfg = localNormalizeReceiverCfg(cfg, double(p.Results.ReceiverRNTI));
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
    sampleRate = localSampleRate(carrier);
    result.SampleRateHz = sampleRate;
    result.DCIRNTI = double(p.Results.ReceiverRNTI);
    result.DetectionAttempted = true;
    result.MeasurementAttempted = true;
    [rxSSB, sync] = sixgr.phy.dl.SSB_Rx(rxWaveform, cfg, ...
        "SampleRate_Hz", sampleRate, ...
        "CandidateSSBIndex", p.Results.CandidateSSBIndex, ...
        "DetectionObserver", @retainDetectionDecision);
    result.PSSDetected = logical(sixgr.util.structGet(sync, "PSSDetected", false));
    result.SSSDetected = logical(sixgr.util.structGet(sync, "SSSDetected", false));
    result.NCellIDRecovered = logical(sixgr.util.structGet(sync, "NCellIDRecovered", false));
    result.PSSDetectionSource = string(sixgr.util.structGet(sync, "PSSDetectionSource", ""));
    result.SSSDetectionSource = string(sixgr.util.structGet(sync, "SSSDetectionSource", ""));
    result.ResourceExtractionAttempted = true;
    result.ChannelEstimateAttempted = true;
    result.EqualizationAttempted = true;
    result.DecodeAttempted = true;
    [pbch, pbchInfo] = sixgr.phy.dl.PBCH_Recovery(rxSSB, sync, cfg);
    result.PBCHEqualizedSymbols = pbch.EqualizedSymbols;
    result.PBCHSymbolIndicesOneBased = pbch.SymbolIndicesOneBased;
    frequencyEvidence=sixgr.phy.broadcast.measurePBCHResidualFrequency(rxSSB,sync,pbch);
    for name=string(fieldnames(frequencyEvidence)).'
        result.(name)=frequencyEvidence.(name);
    end
    % Bounded post-decode scoring snapshot. No simulated channel or TX bits
    % are supplied to synchronization, channel estimation or BCH decoding.
    if pbch.ChannelEstimateAvailable
        operator=struct();
        for field=["SampleRate_Hz","SCS_SSB_kHz","Nfft","DemodulationSlot", ...
                "SSBSymbolColumnsOneBased","SSBDemodulationSampleCount", ...
                "SSBDemodulationStartSampleZeroBased", ...
                "SymbolPhaseCompensationCarrierFrequencyHz", ...
                "CFOCorrectionApplied_Hz","CFOCorrectionSampleOrigin", ...
                "SSBPlacementCorrectionAppliedHz"]
            operator.(field)=sync.(field);
        end
        result.PBCHChannelScoringSnapshot=struct('ChannelEstimateAvailable',true, ...
            'ChannelEstimateGrid',pbch.ChannelEstimateGrid,'NCellID',pbch.NCellID, ...
            'iBar_SSB',pbch.iBar_SSB,'ReceiverOperator',operator);
    end
    result.NCellID = double(sync.NCellID);
    result.TimingOffset = double(sixgr.util.structGet(sync, "TimingOffset", NaN));
    result.RawTimingEstimate_samples = double(sixgr.util.structGet( ...
        sync, "RawTimingEstimate_samples", result.TimingOffset));
    result.TimingEstimateUsed = logical(sync.TimingEstimateUsed);
    result.AppliedTimingCorrection_samples = double(sixgr.util.structGet( ...
        sync, "AppliedTimingCorrection_samples", NaN));
    result.TimingEstimateApplicationPolicy = string(sixgr.util.structGet( ...
        sync, "TimingEstimateApplicationPolicy", ""));
    result.TimingEstimateStatus = string(sixgr.util.structGet( ...
        sync, "TimingEstimateStatus", ""));
    result.TimingEstimateWasClipped = logical(sixgr.util.structGet( ...
        sync, "TimingEstimateWasClipped", false));
    result.SSBTimingSearchGuardSamples = double(sync.TimingSearchGuardSamples);
    result.SSBTimingSearchGuardSource = string(sync.TimingSearchGuardSource);
    result.FrequencyOffsetHz = double(sixgr.util.structGet(sync, "FreqOffset_Hz", NaN));
    for name = ["CFOCorrectionEnabled","CFOCorrectionApplied","CFOCorrectionApplied_Hz", ...
            "CFOCorrectionSampleOrigin","CFOCorrectionSource"]
        result.(name) = sync.(name);
    end
    fineCFO = sixgr.util.structGet(sync, "FreqInfo.FineCFO", struct());
    coarseHypotheses = double(sixgr.util.structGet( ...
        sync, "FreqInfo.Candidates_Hz", []));
    cfoEstimateAvailable = logical(sixgr.util.structGet( ...
        fineCFO, "Available", false)) || numel(unique(coarseHypotheses)) > 1;
    if cfoEstimateAvailable && isfinite(result.FrequencyOffsetHz)
        result.CFOEstimateAvailability = "available";
        result.CFOValueStatus = "MEASURED";
    else
        result.CFOEstimateAvailability = "missing";
        result.CFOValueStatus = "NOT_AVAILABLE";
    end
    result.CFOEstimatorDetail = string(sixgr.util.structGet( ...
        fineCFO, "Method", "coarse_pss_hypothesis_search"));
    result.SSBCenterFrequencyOffsetHz = double(sixgr.util.structGet( ...
        sync, "SSBCenterFrequencyOffsetHz", NaN));
    result.SSBPlacementCorrectionAppliedHz = double(sixgr.util.structGet( ...
        sync, "SSBPlacementCorrectionAppliedHz", NaN));
    result.SSBIndex = double(sixgr.util.structGet(pbch, "SSBIndex", NaN));
    identity = sixgr.phy.sync.receivedSSBOccasionIdentity(sync, pbch);
    for field = string(fieldnames(identity)).'
        result.(field) = identity.(field);
    end
    result.SSBReceivedPower_dB = localGridMeanPowerDb(rxSSB);
    result.PBCHDMRSMetric = double(sixgr.util.structGet(pbchInfo, "Selected.metric", NaN));
    result.PSSMetric = double(sixgr.util.structGet(sync, "FreqInfo.Metric", NaN));
    result.SSSMetric = double(sixgr.util.structGet(sync, "SSSInfo.Metric", NaN));
    result.SSSMetricMargin = double(sixgr.util.structGet(sync, "SSSInfo.MetricMargin", NaN));
    result.PSSSearchSamples = double(sixgr.util.structGet(sync, "FreqInfo.SearchSamples", NaN));
    result.PSSTimingLagsEvaluated = double(sixgr.util.structGet(sync, "FreqInfo.TimingLagsEvaluated", NaN));
    result.PSSSequences = double(sixgr.util.structGet(sync, "FreqInfo.PSSSequences", NaN));
    result.PSSCorrelationVectors = double(sixgr.util.structGet(sync, "FreqInfo.PSSCorrelationVectors", NaN));
    result.SSSSequenceHypotheses = double(sixgr.util.structGet(sync, "SSSInfo.SearchSpaceSize", NaN));
    result.PBCHDMRSHypothesesTested = double(numel(sixgr.util.structGet(pbchInfo, "PerCandidate", struct([]))));
    result.PBCHNoiseVar = double(sixgr.util.structGet(pbch, "NoiseVar", NaN));
    result.EVM_rms = double(sixgr.util.structGet(pbch, "EVM_rms", NaN));
    result.EVMReferenceSource = string(sixgr.util.structGet( ...
        pbch, "EVMReferenceSource", ""));
    result.EVMValueStatus = string(sixgr.util.structGet( ...
        pbch, "EVMValueStatus", "NOT_AVAILABLE"));
    for name = ["EVMErrorEnergy","EVMReferenceEnergy","EVMSymbolCount", ...
            "EVMEnergyUnit","EVMComputationDomain"]
        result.(name) = pbch.(name);
    end
    result.PreEqualizationNoiseVariance = double(sixgr.util.structGet( ...
        pbch, "PreEqualizationNoiseVariance", NaN));
    result.PreEqualizationNoiseVarianceDomain = string(sixgr.util.structGet( ...
        pbch, "PreEqualizationNoiseVarianceDomain", ""));
    result.PreEqualizationNoiseVarianceSource = string(sixgr.util.structGet( ...
        pbch, "PreEqualizationNoiseVarianceSource", ""));
    result.BCHTransportBlockNumBits = double(sixgr.util.structGet(pbch, "BCHTransportBlockNumBits", NaN));
    result.BCHTransportBlockHex = string(sixgr.util.structGet(pbch, "BCHTransportBlockHex", ""));
    result.BCHTransportBlockHash = string(sixgr.util.structGet(pbch, "BCHTransportBlockHash", ""));
    result.BCHScrambledBlockNumBits = double(sixgr.util.structGet(pbch, "BCHScrambledBlockNumBits", NaN));
    result.BCHScrambledBlockHex = string(sixgr.util.structGet(pbch, "BCHScrambledBlockHex", ""));
    result.BCHScrambledBlockHash = string(sixgr.util.structGet(pbch, "BCHScrambledBlockHash", ""));
    result.MIBDecodedBitSource = string(sixgr.util.structGet(pbch, "MIBDecodedBitSource", ""));
    result.MIBSFN4LSBValue = double(sixgr.util.structGet(pbch, "MIBSFN4LSBValue", NaN));
    result.MIBSFN4LSBBitString = string(sixgr.util.structGet(pbch, "MIBSFN4LSBBitString", ""));
    result.MIBHalfFrameBit = double(sixgr.util.structGet(pbch, "MIBHalfFrameBit", NaN));
    result.MIBKSSBSubcarrierOffset = double(sixgr.util.structGet(pbch, "MIBKSSBSubcarrierOffset", NaN));
    result.MIBSSBIndex = double(sixgr.util.structGet(pbch, "MIBSSBIndex", NaN));
    result.MIBPDCCHConfigSIB1Recovered = double(sixgr.util.structGet(pbch, "PDCCHConfigSIB1", NaN));
    result.MIBPDCCHConfigSIB1BitString = string(sixgr.util.structGet(pbch, "PDCCHConfigSIB1BitString", ""));
    result.MIBCORESET0Index = double(sixgr.util.structGet(pbch, "CORESET0Index", NaN));
    result.MIBSearchSpaceZero = double(sixgr.util.structGet(pbch, "SearchSpaceZero", NaN));
    result.MIBDMRSTypeAPosition = double(sixgr.util.structGet(pbch, "MIBDMRSTypeAPosition", NaN));
    result.PBCHiBarSSB = double(sixgr.util.structGet(pbch, "iBar_SSB", NaN));
    result.PBCHv = double(sixgr.util.structGet(pbch, "v", NaN));
    for name=["KSSBContractVersion","Lmax","MIBKSSBLow4","PBCHKSSBMSB", ...
            "PBCHKSSBHighContribution","KSSBHighBitApplicable","DecodedKSSB", ...
            "k_SSB","BCHCRCValid","CandidateIdentityConsistent"]
        result.(name)=pbch.(name);
    end
    if isempty(physicalSamples)
        result.SSBPhysicalMeasurementReferencePlane="received_post_RX_front_end_columns_RF_reference_unqualified";
        result = localMeasurePhysicalSSB(result, rxSSB, sync, pbch, cfg);
    else
        % Decode remains on post-RF samples. Received power is measured on
        % the retained pre-RF plane, with its own measured synchronization;
        % AGC/ADC/CFO are not inverted using a guessed scalar gain.
        [physicalSSB,physicalSync]=sixgr.phy.dl.SSB_Rx(physicalSamples,cfg, ...
            'SampleRate_Hz',sampleRate,'CandidateSSBIndex',p.Results.CandidateSSBIndex);
        physicalIdentity = sixgr.phy.sync.receivedSSBOccasionIdentity(physicalSync, pbch);
        if physicalSync.NCellID~=sync.NCellID || ...
                physicalIdentity.ObservedSSBOccasionIndex ~= result.ObservedSSBOccasionIndex
            error('sixgr:phy:broadcast:MeasurementCellMismatch','Connector measurement detected a different cell from the decoded PBCH.');
        end
        result.SSBPhysicalMeasurementReferencePlane="received_pre_RX_front_end_columns_RF_reference_unqualified";
        result=localMeasurePhysicalSSB(result,physicalSSB,physicalSync,pbch,cfg);
        receipt=sixgr.phy.refsig.buildSSBPowerMeasurementReceipt( ...
            p.Results.PhysicalMeasurementObservation,physicalSSB,physicalSync,result,cfg);
        for name=string(fieldnames(receipt)).'
            result.(name)=receipt.(name);
        end
    end
    result.ChannelEstimateAvailable = logical(sixgr.util.structGet(pbch, "ChannelEstimateAvailable", false));
    result.ChannelEstimateSource = string(sixgr.util.structGet(pbch, "ChannelEstimateSource", ""));
    result.EqualizationAvailable = logical(sixgr.util.structGet(pbch, "EqualizationAvailable", false));
    result.EqualizerType = string(sixgr.util.structGet(pbch, "EqualizerType", ""));
    result.ReceiverHestSINR_dB = double(sixgr.util.structGet(pbch, "ReceiverHestSINR_dB", NaN));
    result.ReceiverHestSINRSource = string(sixgr.util.structGet(pbch, "ReceiverHestSINRSource", ""));
    result.ReceiverHestSINRValueRole = string(sixgr.util.structGet(pbch, "ReceiverHestSINRValueRole", ""));
    result.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(pbch, "ReceiverHestSINRValueStatus", ""));
    result.ReceiverHestSINRNAReason = string(sixgr.util.structGet(pbch, "ReceiverHestSINRNAReason", ""));
    result.MeasuredTrialSINR_dB = double(sixgr.util.structGet(pbch, "MeasuredTrialSINR_dB", NaN));
    result.MeasuredTrialSINRSource = string(sixgr.util.structGet(pbch, "MeasuredTrialSINRSource", ""));
    result.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(pbch, "MeasuredTrialSINRValueRole", ""));
    result.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(pbch, "MeasuredTrialSINRValueStatus", ""));
    result.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(pbch, "MeasuredTrialSINRNAReason", ""));
    result.PostEqSINR_dB = double(sixgr.util.structGet(pbch, "PostEqSINR_dB", NaN));
    result.PostEqSINRAvailable = logical(sixgr.util.structGet( ...
        pbch, "PostEqSINRAvailable", false));
    result.PostEqSINRSource = string(sixgr.util.structGet(pbch, "PostEqSINRSource", ""));
    result.PostEqSINRValueRole = string(sixgr.util.structGet(pbch, "PostEqSINRValueRole", ""));
    result.PostEqSINRValueStatus = string(sixgr.util.structGet(pbch, "PostEqSINRValueStatus", ""));
    result.PostEqSINRNAReason = string(sixgr.util.structGet(pbch, "PostEqSINRNAReason", ""));
    result.PostEqualizationNoiseVariance = double(sixgr.util.structGet( ...
        pbch, "PostEqualizationNoiseVariance", NaN));
    result.PostEqualizationNoiseVarianceDomain = string(sixgr.util.structGet( ...
        pbch, "PostEqualizationNoiseVarianceDomain", ""));
    result.PostEqualizationNoiseVarianceSource = string(sixgr.util.structGet( ...
        pbch, "PostEqualizationNoiseVarianceSource", ""));
    result.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(pbch, "StrictReceiverEvidenceOk", false));
    result.LLRAvailable = logical(sixgr.util.structGet(pbch, "PBCHDecodeAvailable", false));
    result.LLRFinite = result.LLRAvailable && isfinite(double(sixgr.util.structGet(pbch, "NoiseVar", NaN)));
    result.BCHCrcPass = pbch.BCHCRCValid;
    result.MIBDecoded = logical(pbch.Ok) && pbch.CandidateIdentityConsistent;
    if ~result.BCHCrcPass
        result.Status = "mib_decode_failed";
        result.FailureReason = "BCH/MIB CRC failed before CORESET0/SearchSpace0 derivation";
        result.StrictOk = false;
        return;
    end
    if ~result.MIBDecoded
        result.Status="decoded_pbch_candidate_identity_mismatch";
        result.FailureIdentifier="sixgr:phy:broadcast:PBCHCandidateIdentityMismatch";
        result.FailureReason="BCH CRC passed but the decoded candidate identity is inconsistent; no MIB/SI authority was installed";
        result.StrictReceiverEvidenceOk=false;
        return;
    end
    if ~result.SSBIdentityVerified
        result.Status = "decoded_ssb_identity_mismatch";
        result.FailureReason = "CRC-passing PBCH identity does not match the received PSS occasion";
        result.StrictReceiverEvidenceOk = false;
        result.StrictOk = false;
        return;
    end
    % This original BCH receiver fact must survive a later SI failure.
    % StrictReceiverEvidenceOk below remains the combined-procedure value.
    result.PBCHStrictReceiverEvidenceOk=result.StrictReceiverEvidenceOk;
    mib = sixgr.phy.broadcast.decodeMIBTransportBlock(pbch.TransportBlock);
    % The SSB index is carried by the PBCH/DM-RS hypothesis, not by the
    % 24-bit MIB payload. Never let Type-0 derivation fall back to the TX
    % configuration's selected beam after an independent PBCH decode.
    mib.SSBIndex=double(result.ObservedSSBOccasionIndex);
    result.MIBSystemFrameNumber = 16*double(mib.SystemFrameNumberMSB6) + result.MIBSFN4LSBValue;
    mib.SystemFrameNumber=result.MIBSystemFrameNumber;
    result.SSBMIBComplete=true;
    % Keep the original capture clock before the MIB-only early return.
    % The context is an optional second output, never a synthetic primary
    % PBCH/SIB1 row or a replacement for runtime configuration installation.
    [frameOriginLocal,receivedFrame,frameClock]=localReceivedFrameClock( ...
        cfg,result,captureStartSample,sampleRate);
    % PCI is receiver-derived, not a TX/configuration substitute.
    cfg.phy.carrier.NCellID=result.NCellID;
    mibContext=sixgr.phy.broadcast.ReceivedMIBContext.fromDecodedBCH( ...
        pbch,result,originalCapture,cfg,frameOriginLocal,receivedFrame,frameClock);
    if result.RecoveryScope=="SSB_MIB"
        result.Status="SSB_MIB_COMPLETE_SIB1_NOT_ATTEMPTED";
        return;
    end
    originalReceiverEvidence=result.StrictReceiverEvidenceOk;
    si=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(originalCapture,cfg,mibContext, ...
        'ReceiverRNTI',p.Results.ReceiverRNTI,'FaultMode',p.Results.FaultMode);
    % Preserve the established combined result contract. New SI-only
    % provenance does not pretend that this combined call skipped PBCH.
    separate=["PriorMIBAvailable","PriorBCHContextSHA256","PriorBCHSource", ...
        "PriorBCHAvailableAtSample","PriorBCHStrictReceiverEvidenceOk", ...
        "PriorReceivedNCellID","PriorReceivedSSBIndex","NewBCHReceptionAttempted", ...
        "SIB1CFOPhaseOriginSample","SIB1CFOPhaseOriginInOriginalCapture_samples", ...
        "SIB1InputSampleSHA256","SIB1CFOPhaseStartSample","SIB1CFOCorrectedSampleSHA256", ...
        "Type0MonitoringWindowSHA256"];
    for name=string(fieldnames(si)).'
        if ~ismember(name,separate), result.(name)=si.(name); end
    end
    result.StrictReceiverEvidenceOk=originalReceiverEvidence;
    if isfield(si,'SIB1PDSCHStrictReceiverEvidenceOk')
        result.StrictReceiverEvidenceOk=originalReceiverEvidence && si.SIB1PDSCHStrictReceiverEvidenceOk;
    end
    result.StrictOk=si.StrictOk && localStrictOk(result);
catch ME
    result.StrictOk = false;
    result.Status = "ERROR";
    result.FailureIdentifier = string(ME.identifier);
    result.Crash = result.FailureIdentifier ~= "sixgr:phy:ia:SSBNotDetected";
    if ~result.Crash, result.Status = "FAIL"; end
    result.FailureReason = string(ME.identifier) + ":" + string(ME.message);
    % Preserve the complete receiver call stack in diagnostic evidence.  A
    % caught waveform failure otherwise collapses to a message with no
    % actionable production location, which made qualification triage
    % ambiguous while correctly keeping StrictOk=false.
    result.Errors = string(getReport(ME, "extended", "hyperlinks", "off"));
end

    function retainDetectionDecision(stage, decision)
        % A measured non-detection must survive the receiver's early error
        % return. This observer cannot influence the physical decision.
        result.(stage+"NormalizedMetric") = decision.NormalizedMetric;
        result.(stage+"DetectionThreshold") = decision.Threshold;
        result.(stage+"DetectionHypothesisCount") = decision.HypothesisCount;
        result.(stage+"DetectionMetricValid") = decision.MetricValid;
        result.(stage+"DetectionDecisionAvailable") = true;
        result.(stage+"Detected") = decision.Detected;
        result.DetectionMetric = decision.NormalizedMetric;
        result.DetectionThreshold = decision.Threshold;
        result.DetectionHypothesisCount = decision.HypothesisCount;
        result.DetectionStage = stage;
        result.DetectionMetricSource = stage+":"+decision.Source;
    end
end

function result = localEmptyResult()
result = struct( ...
    "StrictOk", false, "Status", "", "Detail", "", "NCellID", NaN, ...
    "Crash", false, "FailureIdentifier", "", ...
    "TimingOffset", NaN, "RawTimingEstimate_samples", NaN, ...
    "AppliedTimingCorrection_samples", NaN, ...
    "TimingEstimateApplicationPolicy", "", ...
    "TimingEstimateStatus", "", "TimingEstimateWasClipped", false, "TimingEstimateUsed", false, ...
    "FrequencyOffsetHz", NaN, ...
    "CFOCorrectionEnabled",false,"CFOCorrectionApplied",false,"CFOCorrectionApplied_Hz",NaN, ...
    "CFOCorrectionSampleOrigin",NaN,"CFOCorrectionSource","not_executed", ...
    "EVM_rms", NaN, "EVMReferenceSource", "", ...
    "EVMValueStatus", "NOT_AVAILABLE", ...
    "EVMErrorEnergy", NaN, "EVMReferenceEnergy", NaN, "EVMSymbolCount", NaN, ...
    "EVMEnergyUnit", "", "EVMComputationDomain", "", ...
    "CFOEstimateAvailability", "missing", ...
    "CFOValueStatus", "NOT_AVAILABLE", "CFOEstimatorDetail", "", ...
    "SSBTimingSearchGuardSamples", NaN, "SSBTimingSearchGuardSource", "", ...
    "SIB1CFOCorrectionApplied_Hz", NaN, "SIB1CFOCorrectionSource", "", ...
    "SSBCenterFrequencyOffsetHz", NaN, ...
    "SSBPlacementCorrectionAppliedHz", NaN, "SSBIndex", NaN, ...
    "ObservedSSBOccasionIndex", NaN, "PBCHHypothesisSSBIndex", NaN, ...
    "SSBIdentityVerified", false, "SSBIndexSource", "", ...
    "SSBReceivedPower_dB", NaN, ...
    "SS_RSRP_dBm", NaN, "SS_RSRPPerReceiveAntenna_dBm", "", ...
    "SS_RSRPRawObserved_dBm", NaN, ...
    "SS_RSRPRawObservedPerReceiveAntenna_dBm", "", ...
    "SSBWindowRSSIPerReceiveAntenna_dBm", "", "SSBWindowPowerMeasurementJSON", "", ...
    "SSBWindowRelativePowerMeasurementJSON", "", ...
    "SSBWindowReferenceRSRQPerReceiveAntenna_dB", "", ...
    "SSBWindowReferenceRSRQScope", "", "SSBWindowReferenceRSRQNumRB", NaN, ...
    "SS_SINR_dB", NaN, "SS_SINRPerReceiveAntenna_dB", "", ...
    "SSMeasurementSource", "", ...
    "SSSINRMeasurementMethod", "", ...
    "SSSINRReferencePlane", "", ...
    "SSSINRNoiseInterferencePowerPerReceiveAntenna_W", "", ...
    "SSSINRDesiredPowerPerReceiveAntenna_W", "", ...
    "SSSINRNoiseInterferenceRECount", NaN, ...
    "SSSINRFailureReason", "", ...
    "SSPhysicalMeasurementStatus", "unavailable", ...
    "SSMeasurementAntennaAggregation", "", ...
    "SSMeasurementFFTSize", NaN, ...
    "SSMeasurementGridScaleToSqrtW", NaN, ...
    "PBCHDMRSMetric", NaN, "PBCHNoiseVar", NaN, ...
    "PreEqualizationNoiseVariance", NaN, ...
    "PreEqualizationNoiseVarianceDomain", "", ...
    "PreEqualizationNoiseVarianceSource", "", ...
    "BCHTransportBlockNumBits", NaN, "BCHTransportBlockHex", "", ...
    "BCHTransportBlockHash", "", "BCHScrambledBlockNumBits", NaN, ...
    "BCHScrambledBlockHex", "", "BCHScrambledBlockHash", "", ...
    "MIBDecodedBitSource", "", "MIBSFN4LSBValue", NaN, ...
    "MIBSFN4LSBBitString", "", "MIBHalfFrameBit", NaN, ...
    "MIBKSSBSubcarrierOffset", NaN, "MIBSSBIndex", NaN, ...
    "MIBPDCCHConfigSIB1Recovered", NaN, "MIBPDCCHConfigSIB1BitString", "", ...
    "MIBCORESET0Index", NaN, "MIBSearchSpaceZero", NaN, ...
    "MIBDMRSTypeAPosition", NaN, ...
    "PBCHiBarSSB", NaN, "PBCHv", NaN, ...
    "ChannelEstimateAvailable", false, "ChannelEstimateSource", "", ...
    "PBCHChannelScoringSnapshot", struct(), ...
    "SSBPowerMeasurementSnapshot", struct(), ...
    "EqualizationAvailable", false, "EqualizerType", "", ...
    "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", ...
    "ReceiverHestSINRValueRole", "", "ReceiverHestSINRValueStatus", "", ...
    "ReceiverHestSINRNAReason", "", "MeasuredTrialSINR_dB", NaN, ...
    "MeasuredTrialSINRSource", "", "MeasuredTrialSINRValueRole", "", ...
    "MeasuredTrialSINRValueStatus", "", "MeasuredTrialSINRNAReason", "", ...
    "PostEqSINR_dB", NaN, "PostEqSINRAvailable", false, ...
    "PostEqSINRSource", "", ...
    "PostEqSINRValueRole", "", "PostEqSINRValueStatus", "", ...
    "PostEqSINRNAReason", "", ...
    "PostEqualizationNoiseVariance", NaN, ...
    "PostEqualizationNoiseVarianceDomain", "", ...
    "PostEqualizationNoiseVarianceSource", "", ...
    "StrictReceiverEvidenceOk", false, ...
    "PBCHStrictReceiverEvidenceOk", false, ...
    "PSSDetected", false, "SSSDetected", false, ...
    "NCellIDRecovered", false, "PSSDetectionSource", "", ...
    "SSSDetectionSource", "", ...
    "DetectionAttempted", false, "MeasurementAttempted", false, ...
    "ResourceExtractionAttempted", false, "ChannelEstimateAttempted", false, ...
    "EqualizationAttempted", false, "DecodeAttempted", false, ...
    "LLRAvailable", false, "LLRFinite", false, ...
    "SIB1PDSCHChannelEstimateAvailable", false, "SIB1PDSCHEqualizationAvailable", false, ...
    "SIB1PDSCHReceiverHestSINR_dB", NaN, "SIB1PDSCHReceiverHestSINRSource", "", ...
    "SIB1PDSCHStrictReceiverEvidenceOk", false, ...
    "SIB1PDSCHEqualizedSymbols", complex(zeros(0, 1)), ...
    "SIB1PDSCHEqualizedSymbolDomain", "", ...
    "BCHCrcPass", false, "MIBDecoded", false, "PDCCHConfigSIB1", NaN, ...
    "BCHCRCValid", false, "CandidateIdentityConsistent", false, ...
    "KSSBContractVersion", "", "Lmax", NaN, "MIBKSSBLow4", NaN, ...
    "PBCHKSSBMSB", NaN, "PBCHKSSBHighContribution", NaN, ...
    "KSSBHighBitApplicable", NaN, "DecodedKSSB", NaN, "k_SSB", NaN, ...
    "PDCCHConfigSIB1Source", "", ...
    "CORESET0Present", false, "CORESET0Pattern", "", "CORESET0RBStart", NaN, ...
    "CORESET0NumRB", NaN, "CORESET0Duration", NaN, "SearchSpace0ID", NaN, ...
    "SearchSpace0SlotPeriod", NaN, "SearchSpace0SlotOffset", NaN, ...
    "SearchSpace0StartSymbol", NaN, "SearchSpace0AggregationLevel", NaN, ...
    "SIB1AbsoluteSlot", NaN, "Type0MonitoringOccasionOrdinal", NaN, ...
    "PDCCHCandidatesAttempted", 0, "DCIBlindDecodeSuccess", false, "DCICrcPass", false, ...
    "DCIRNTI", NaN, "DCIFormat", "", "DCIPayloadHex", "", ...
    "WrongRNTIRejectCount", 0, "NoSignalRejectCount", 0, "FalseCandidateCount", 0, ...
    "PDSCHRBStart", NaN, "PDSCHNumRB", NaN, "PDSCHSymbolStart", NaN, ...
    "PDSCHNumSymbols", NaN, "PDSCHModulation", "", "PDSCHDMRSOk", false, ...
    "DLSCHCrcPass", false, ...
    "SIB1TransportBlockBits", int8([]), "SIB1TransportBlockSize", NaN, ...
    "SIB1TrailingTransportBlockPaddingBits", NaN, ...
    "SIB1PayloadBits", int8([]), "SIB1PayloadBytes", NaN, ...
    "SIB1PayloadHashTx", "", "SIB1PayloadHashRx", "", "SIB1ASN1DecodeOk", false, ...
    "SIB1SemanticValid", false, ...
    "SIB1TxTreeHash", "", "SIB1RxTreeHash", "", "SIB1TreeEqual", false, ...
    "UsedOracleFields", strings(0, 1), "ProxyUsed", false, "Skipped", false, ...
    "ToolboxMissing", false, "Errors", "", "FailureReason", "", ...
    "CandidateTable", table(), "SampleRateHz", NaN, "SIB1RxTree", struct());
end

function result = localMeasurePhysicalSSB(result, rxSSB, sync, pbch, cfg)
% Measure linear SSS RE power and practical received-reference disturbance.
% The normalized detection metric remains SSBReceivedPower_dB and is never
% substituted for an absolute UE measurement.
powerContext = sixgr.util.structGet(cfg, "lls6g.runtimePowerContext", struct());
amplitudeUnit = string(sixgr.util.structGet( ...
    powerContext, "WaveformAmplitudeUnit", ""));
result.SSPhysicalMeasurementStatus = ...
    "unavailable_missing_sqrt_mw_power_context";
result.PowerReferencePlane=result.SSBPhysicalMeasurementReferencePlane;
normalized=sixgr.rf.isNormalizedFixedSNRPowerReference(cfg);
normalizedUnit=strcmpi(strtrim(amplitudeUnit),"normalized_complex_baseband");
if normalizedUnit && normalized
    % Validate the applied contract; enabling a measurement is not authority
    % to change samples or claim absolute device power.
    sixgr.rf.appliedWaveformAmplitudeUnit(cfg,powerContext);
elseif ~strcmpi(strtrim(amplitudeUnit), "sqrt_mW") || normalized
    return;
end
nfft = double(sixgr.util.structGet(sync, "Nfft", NaN));
if ~(isscalar(nfft) && isfinite(nfft) && nfft >= 1 && ...
        nfft == round(nfft))
    result.SSPhysicalMeasurementStatus = "unavailable_missing_ssb_fft_size";
    return;
end
ncellid = double(sixgr.util.structGet(sync, "NCellID", NaN));
if ~(isscalar(ncellid) && isfinite(ncellid) && ncellid >= 0 && ...
        ncellid <= 1007 && ncellid == round(ncellid))
    result.SSPhysicalMeasurementStatus = ...
        "unavailable_missing_blind_recovered_ncellid";
    return;
end

scale = nfft * sqrt(1000);
% Internal working scale for the existing per-RE estimator. For normalized
% samples this is numerical conditioning, not a watts claim: convert every
% exposed power field back to occupied-RE units before returning below.
physicalGrid = rxSSB ./ cast(scale, "like", rxSSB);
iBarSSB = double(sixgr.util.structGet(pbch, "iBar_SSB", NaN));
try
    if isfinite(iBarSSB) && iBarSSB >= 0 && iBarSSB <= 7 && ...
            iBarSSB == round(iBarSSB)
        [measured,rssiEvidence] = sixgr.phy.refsig.measureSSBWindowPower( ...
            physicalGrid, ncellid, iBarSSB, sync.SCS_SSB_kHz);
    else
        [measured,rssiEvidence] = sixgr.phy.refsig.measureSSBWindowPower( ...
            physicalGrid, ncellid, NaN, sync.SCS_SSB_kHz);
    end
    result.SSBWindowRSSIPerReceiveAntenna_dBm = localNumericVectorToken(measured.RSSIPerAntenna);
    result.SSBWindowPowerMeasurementJSON = string(jsonencode(rssiEvidence));
    result.SSBWindowReferenceRSRQPerReceiveAntenna_dB = localNumericVectorToken(measured.RSRQPerAntenna);
    result.SSBWindowReferenceRSRQScope = string(rssiEvidence.Scope);
    result.SSBWindowReferenceRSRQNumRB = double(rssiEvidence.NumRB);
catch ME
    result.SSPhysicalMeasurementStatus = ...
        "unavailable_nr_ssb_measurement_failed:" + string(ME.identifier);
    return;
end
% The toolbox's coherent-mean RSRP remains only in the explicitly scoped
% RSSI reference record. Do not seed primary RSRP with that different
% estimator, even temporarily on a later estimation-failure path.
result.SSMeasurementFFTSize = nfft;
result.SSMeasurementGridScaleToSqrtW = scale;
result.SSMeasurementAntennaAggregation = ...
    "maximum_per_receive_antenna_rsrp_ts_38_215_diversity_rule";
result.SSMeasurementSource = ...
    "noise_debiased_linear_sss_re_power_and_received_reference_disturbance";
result.SSPhysicalMeasurementStatus = "unavailable_sss_measurement";

% SS-SINR uses the same detected SS/PBCH block and the same physical UE
% recorded sample plane. A pre-RF capture is not by itself proof of a
% standardized antenna connector/branch reference. Disturbance uses SSS
% reference REs, not an unconfigured null-RE interference resource.
try
    ssSinr = sixgr.phy.refsig.measureSSSINRFromSSBGrid( ...
        physicalGrid, ncellid, iBarSSB);
    ssSinr.ReferencePlane=result.SSBPhysicalMeasurementReferencePlane;
    % Exact original linear estimator operands for independent post-receiver
    % scoring. No scorer/reference value is supplied to this estimator.
    result.SSBPowerMeasurementSnapshot=ssSinr;
    result.SSSINRMeasurementMethod = string(ssSinr.MeasurementMethod);
    result.SSSINRReferencePlane = string(ssSinr.ReferencePlane);
    result.SSSINRNoiseInterferencePowerPerReceiveAntenna_W = ...
        localNumericVectorToken(ssSinr.NoiseInterferencePowerPerReceiveAntenna_W);
    result.SSSINRDesiredPowerPerReceiveAntenna_W = ...
        localNumericVectorToken(ssSinr.DesiredPowerPerReceiveAntenna_W);
    result.SSSINRNoiseInterferenceRECount = ...
        double(ssSinr.NoiseInterferenceRECount);
    result.SS_RSRPRawObserved_dBm = double(ssSinr.RawObservedSS_RSRP_dBm);
    result.SS_RSRPRawObservedPerReceiveAntenna_dBm = ...
        localNumericVectorToken(ssSinr.RawObservedSS_RSRPPerReceiveAntenna_dBm);
    result.SS_RSRP_dBm = double(ssSinr.NoiseDebiasedSS_RSRP_dBm);
    result.SS_RSRPPerReceiveAntenna_dBm = localNumericVectorToken( ...
        ssSinr.NoiseDebiasedSS_RSRPPerReceiveAntenna_dBm);
    if logical(ssSinr.Available)
        result.SS_SINR_dB = double(ssSinr.SS_SINR_dB);
        result.SS_SINRPerReceiveAntenna_dB = localNumericVectorToken( ...
            ssSinr.SS_SINRPerReceiveAntenna_dB);
        result.SSPhysicalMeasurementStatus = "available_rsrp_and_sinr";
        result.SSMeasurementSource = ...
            "noise_debiased_linear_sss_re_power_and_received_reference_disturbance";
    else
        if isfinite(result.SS_RSRP_dBm)
            result.SSPhysicalMeasurementStatus = ...
                "available_rsrp_sinr_failed:" + string(ssSinr.Status);
        else
            result.SSPhysicalMeasurementStatus = ...
                "unavailable_ss_rsrp_and_sinr:" + string(ssSinr.Status);
        end
        result.SSSINRFailureReason = string(ssSinr.FailureReason);
    end
catch ME
    % Missing received-reference evidence must not be promoted to an
    % available RSRP or replaced by coherent-mean reference power.
    result.SSPhysicalMeasurementStatus = ...
        "unavailable_sss_measurement:" + string(ME.identifier);
    result.SSSINRFailureReason = string(ME.message);
end
if normalized
    result=sixgr.link.normalizeReceivedSSBPowerReference(result,cfg,"receive");
end
end

function token = localNumericVectorToken(values)
values = double(values(:).');
if isempty(values)
    token = "";
    return;
end
parts = strings(1, numel(values));
for idx = 1:numel(values)
    if isfinite(values(idx))
        parts(idx) = string(sprintf("%.15g", values(idx)));
    else
        parts(idx) = "NaN";
    end
end
token = char(strjoin(parts, "|"));
end

function value = localGridMeanPowerDb(grid)
value = NaN;
if isempty(grid)
    return;
end
samples = grid(:);
samples = samples(isfinite(real(samples)) & isfinite(imag(samples)));
if isempty(samples)
    return;
end
powerLin = mean(abs(samples).^2, "omitnan");
if isfinite(powerLin) && powerLin > 0
    value = 10 * log10(powerLin);
end
end

function cfg = localNormalizeReceiverCfg(cfg,rnti)
cfg=sixgr.phy.broadcast.ReceivedMIBContext.normalizeReceiverConfig(cfg,rnti);
end

function [pdcch, cfgSI] = localReceiverPDCCH(carrier, cfg, rnti)
cfgSI = localNormalizeReceiverCfg(cfg, rnti);
pdcch = localBuildPDCCHObject(carrier);
cfgSI.phy.sib1.runtimePDCCH = pdcch;
end

function pdcch = localBuildPDCCHObject(carrier)
coreset = nrCORESETConfig;
try
    coreset.CORESETID = 0;
catch
end
coreset.Duration = 2;
coreset.FrequencyResources = ones(1, max(1, min(6, ceil(double(carrier.NSizeGrid) / 6))));
coreset.REGBundleSize = 6;
coreset.InterleaverSize = 2;
coreset.ShiftIndex = double(carrier.NCellID);
ss = nrSearchSpaceConfig;
try
    ss.SearchSpaceID = 0;
catch
end
ss.CORESETID = 0;
ss.StartSymbolWithinSlot = 0;
ss.SlotPeriodAndOffset = [1 0];
ss.Duration = 1;
ss.NumCandidates = [0 0 1 0 0];
pdcch = nrPDCCHConfig;
try
    pdcch.NCellID = double(carrier.NCellID);
catch
end
try
    pdcch.RNTI = 0; % Type0 CSS physical scrambling uses nRNTI=0; DCI CRC mask is receiver-selected.
catch
end
pdcch.CORESET = coreset;
pdcch.SearchSpace = ss;
pdcch.AggregationLevel = 4;
try
    pdcch.NStartBWP = double(carrier.NStartGrid);
    pdcch.NSizeBWP = double(carrier.NSizeGrid);
catch
end
end

function [origin,frame,clock] = localReceivedFrameClock(cfg,result,captureStart,fs)
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg, ...
    'SSBIndex',result.MIBSSBIndex,'HalfFrameIndex',result.MIBHalfFrameBit);
symbol=timing.SelectedStartSymbol;
position=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol( ...
    floor(symbol/14),mod(symbol,14),timing.Mu);
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
assert(ticksPerSample==fix(ticksPerSample) && rem(position.Ticks,int64(ticksPerSample))==0, ...
    'sixgr:phy:broadcast:ReceivedFrameOffSampleClock','Received SSB timing must lie on the original sample clock.');
origin=result.TimingOffset-double(position.Ticks)/ticksPerSample;
validateattributes(origin,{'numeric'},{'scalar','real','finite','integer'});
frame=double(result.MIBSystemFrameNumber);
clock="decoded_SFN_cycle_without_global_capture_epoch";
if isfinite(captureStart)
    frameSamples=double(sixgr.phy.frame.AbsoluteTime.TicksPerFrame)/ticksPerSample;
    frame=round((captureStart+origin)/frameSamples);
    assert(frame>=0 && mod(frame,1024)==result.MIBSystemFrameNumber, ...
        'sixgr:phy:broadcast:ReceivedSFNClockMismatch', ...
        'Original capture epoch and decoded BCH SFN disagree; never relabel shifted frame-zero IQ.');
    clock="received_BCH_SFN_on_zero_SFN_shared_sample_epoch";
end
end

function sampleRate = localSampleRate(carrier)
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
sampleRate = double(sampling.SampleRateHz);
end

function n = localSSBObservationSubframes(cfg)
n = double(sixgr.util.structGet(cfg, "phy.sib1.ssbObservationSubframes", ...
    sixgr.util.structGet(cfg, "phy.ssb.pbchObservationSubframes", 5)));
n = max(1, round(n));
end

function value = localPDCCHConfigSIB1(cfg)
coreset0 = double(sixgr.util.structGet(cfg, "phy.sib1.coreset0Index", 0));
search0 = double(sixgr.util.structGet(cfg, "phy.sib1.searchSpaceZero", 0));
value = coreset0 * 16 + search0;
end

function ok = localStrictOk(result)
ok = ~logical(result.Skipped) && ~logical(result.ProxyUsed) && ~logical(result.ToolboxMissing) && ...
    isempty(result.UsedOracleFields) && logical(result.BCHCrcPass) && logical(result.MIBDecoded) && ...
    logical(result.StrictReceiverEvidenceOk) && ...
    logical(result.CORESET0Present) && double(result.PDCCHCandidatesAttempted) > 0 && ...
    logical(result.DCIBlindDecodeSuccess) && logical(result.DCICrcPass) && ...
    double(result.DCIRNTI) == 65535 && string(result.DCIFormat) == "1_0" && ...
    double(result.FalseCandidateCount) == 0 && logical(result.PDSCHDMRSOk) && ...
    logical(result.DLSCHCrcPass) && logical(result.SIB1ASN1DecodeOk) && ...
    logical(result.SIB1SemanticValid);
end
