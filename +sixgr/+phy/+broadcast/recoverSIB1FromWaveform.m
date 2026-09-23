function result = recoverSIB1FromWaveform(rxWaveform, cfg, varargin)
%RECOVERSIB1FROMWAVEFORM Recover MIB, SI-RNTI DCI, PDSCH/DL-SCH, and SIB1.

% Streaming callers may submit a completed observation. Keep this guard
% outside decoder error recovery: an incomplete capture is not a failed
% BCH/SIB1 trial, and must not create a CRC/BLER row.
if isa(rxWaveform, 'sixgr.phy.waveform.WaveformObservationBuffer')
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
physicalSamples=[];
if ~isempty(p.Results.PhysicalMeasurementObservation)
    physicalSamples=p.Results.PhysicalMeasurementObservation.readComplete();
    if ~isequal(size(physicalSamples),size(rxWaveform))
        error('sixgr:phy:broadcast:MeasurementPlaneLayout','Physical and decoder observations need identical receive antenna and sample layouts.');
    end
end

result = localEmptyResult();
result.RecoveryScope=string(p.Results.RecoveryScope);
result.SIB1ReceptionAttempted=false;
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
        "CandidateSSBIndex", p.Results.CandidateSSBIndex);
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
    result.NCellID = double(sync.NCellID);
    result.TimingOffset = double(sixgr.util.structGet(sync, "TimingOffset", NaN));
    result.SSBTimingSearchGuardSamples = double(sync.TimingSearchGuardSamples);
    result.SSBTimingSearchGuardSource = string(sync.TimingSearchGuardSource);
    result.FrequencyOffsetHz = double(sixgr.util.structGet(sync, "FreqOffset_Hz", NaN));
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
    if isempty(physicalSamples)
        result = localMeasurePhysicalSSB(result, rxSSB, sync, pbch, cfg);
    else
        % Decode remains on post-RF samples. Connector power is measured on
        % the retained pre-RF plane, with its own measured synchronization;
        % AGC/ADC/CFO are not inverted using a guessed scalar gain.
        [physicalSSB,physicalSync]=sixgr.phy.dl.SSB_Rx(physicalSamples,cfg, ...
            'SampleRate_Hz',sampleRate,'CandidateSSBIndex',p.Results.CandidateSSBIndex);
        physicalIdentity = sixgr.phy.sync.receivedSSBOccasionIdentity(physicalSync, pbch);
        if physicalSync.NCellID~=sync.NCellID || ...
                physicalIdentity.ObservedSSBOccasionIndex ~= result.ObservedSSBOccasionIndex
            error('sixgr:phy:broadcast:MeasurementCellMismatch','Connector measurement detected a different cell from the decoded PBCH.');
        end
        result=localMeasurePhysicalSSB(result,physicalSSB,physicalSync,pbch,cfg);
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
    result.BCHCrcPass = logical(pbch.Ok) && double(pbch.ErrFlag) == 0;
    result.MIBDecoded = result.BCHCrcPass;
    if ~logical(result.MIBDecoded)
        result.Status = "mib_decode_failed";
        result.FailureReason = "BCH/MIB CRC failed before CORESET0/SearchSpace0 derivation";
        result.StrictOk = false;
        return;
    end
    if ~result.SSBIdentityVerified
        result.Status = "decoded_ssb_identity_mismatch";
        result.FailureReason = "CRC-passing PBCH identity does not match the received PSS occasion";
        result.StrictReceiverEvidenceOk = false;
        result.StrictOk = false;
        return;
    end
    mib = sixgr.phy.broadcast.decodeMIBTransportBlock(pbch.TransportBlock);
    result.MIBSystemFrameNumber = 16*double(mib.SystemFrameNumberMSB6) + result.MIBSFN4LSBValue;
    result.SSBMIBComplete=true;
    if result.RecoveryScope=="SSB_MIB"
        % A complete received SS/PBCH occasion need not wait for SIB1.
        % StrictOk remains false: it means full SIB1 recovery, not this stage.
        result.Status="SSB_MIB_COMPLETE_SIB1_NOT_ATTEMPTED";
        return;
    end
    result.SIB1ReceptionAttempted=true;
    [type0, cfgSI] = sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier, cfg, mib, ...
        "RNTI", double(p.Results.ReceiverRNTI));
    monitoringOccasionOrdinal = localMonitoringOccasionOrdinal(cfg);
    if monitoringOccasionOrdinal > height(type0.MonitoringOccasions)
        error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
            "Type0 monitoring occasion ordinal %d exceeds the %d resolved occasions.", ...
            monitoringOccasionOrdinal, height(type0.MonitoringOccasions));
    end
    monitoringOccasion = type0.MonitoringOccasions( ...
        monitoringOccasionOrdinal, :);
    sib1AbsoluteSlot = double(monitoringOccasion.AbsoluteSlot);
    carrier = localCarrierAtAbsoluteSlot(carrier, sib1AbsoluteSlot);
    cfgSI = sixgr.util.structSet(cfgSI, ...
        "phy.carrier.NSlot", double(carrier.NSlot));
    cfgSI = sixgr.util.structSet(cfgSI, ...
        "phy.carrier.NFrame", double(carrier.NFrame));
    cfgSI = sixgr.util.structSet(cfgSI, ...
        "phy.sib1.pdcchAbsoluteSlot", sib1AbsoluteSlot);
    result.SIB1AbsoluteSlot = sib1AbsoluteSlot;
    result.Type0MonitoringOccasionOrdinal = monitoringOccasionOrdinal;
    result.PDCCHConfigSIB1 = double(type0.PDCCHConfigSIB1);
    result.CORESET0Present = true;
    result.CORESET0Pattern = string(type0.CORESET0.Pattern);
    result.CORESET0RBStart = double(type0.CORESET0.RBStart);
    result.SearchSpace0ID = double(type0.SearchSpace0.SearchSpaceID);
    result.CORESET0Duration = double(type0.CORESET0.DurationSymbols);
    result.CORESET0NumRB = double(type0.CORESET0.NumRB);
    result.SearchSpace0SlotPeriod = double(type0.SearchSpace0.SlotPeriod);
    result.SearchSpace0SlotOffset = double(type0.SearchSpace0.SlotOffset);
    result.SearchSpace0StartSymbol = double(type0.SearchSpace0.StartSymbolWithinSlot);
    result.SearchSpace0AggregationLevel = double(type0.SearchSpace0.AggregationLevel);
    result.PDCCHConfigSIB1Source = "decoded_mib_bch_transport_block";

    % SSB_Rx corrects its own extraction, not the caller's full capture.
    % Transfer that RECEIVER estimate to the same noisy full-carrier samples
    % before SI-RNTI PDCCH/PDSCH demodulation. The deterministic SSB placement
    % shift is deliberately not applied to the full carrier.
    cfoHz=double(result.FrequencyOffsetHz);
    if ~(isscalar(cfoHz) && isfinite(cfoHz))
        error("sixgr:phy:broadcast:MissingSIB1FrequencyEstimate", ...
            "SIB1 reception requires the finite frequency estimate recovered from received SSB samples.");
    end
    sampleTime=(0:size(rxWaveform,1)-1).'/sampleRate;
    correctedSI=rxWaveform.*cast(exp(-1j*2*pi*cfoHz*sampleTime),"like",rxWaveform);
    result.SIB1CFOCorrectionApplied_Hz=cfoHz;
    result.SIB1CFOCorrectionSource="received_ssb_pss_cp_frequency_estimate";
    siWave = localExtractSIB1Waveform( ...
        correctedSI, carrier, sampleRate, sib1AbsoluteSlot);
    faultMode = lower(strtrim(string(p.Results.FaultMode)));
    if faultMode == "nosignal"
        siWave(:) = 0;
    end

    if faultMode == "corruptpdcch"
        siWave = localCorruptPDCCHResources(siWave, carrier, type0.PDCCH);
    end
    [pdcchRx, pdcchInfo] = sixgr.phy.dl.PDCCH_Rx(siWave, cfgSI, ...
        "Carrier", carrier, "PDCCH", type0.PDCCH, ...
        "K", double(type0.DCIPayloadBits), ...
        "RNTI", double(p.Results.ReceiverRNTI), ...
        "PDCCHScramblingRNTI", 0, "SampleRate_Hz", sampleRate);
    result.PDCCHCandidatesAttempted = double(sixgr.util.structGet(pdcchInfo, "NumCandidatesTried", 0));
    result.DCIBlindDecodeSuccess = logical(pdcchRx.Ok);
    result.DCICrcPass = logical(pdcchRx.Ok);
    result.DCIFormat = "1_0";
    result.DCIPayloadHex = sixgr.rrc.asn1.bitsToHex(pdcchRx.DCIBits);
    result.WrongRNTIRejectCount = double(~logical(pdcchRx.Ok) && double(p.Results.ReceiverRNTI) ~= 65535);
    result.NoSignalRejectCount = double(~logical(pdcchRx.Ok) && faultMode == "nosignal");
    result.FalseCandidateCount = 0;
    if ~logical(pdcchRx.Ok)
        result.Status = "pdcch_decode_failed";
        result.FailureReason = "SI-RNTI DCI blind decode failed";
        result.CandidateTable = sixgr.util.structGet(pdcchInfo, "CandidateResults", table());
        result.StrictOk = false;
        return;
    end

    controlEvent = sixgr.pdsch.RASIPDSCHContext.decodedControlEvent( ...
        pdcchRx, pdcchInfo, "sib1", 65535, "1_0", int8([]), ...
        "PDCCHAbsoluteSlot", sib1AbsoluteSlot, ...
        "EvidenceRole", "receiver_decode");
    [dci, pdsch] = sixgr.phy.broadcast.buildSIB1DCI10(carrier, cfgSI, "Bits", pdcchRx.DCIBits);
    cfgSI = localSanitizeSIB1PDSCHPrecoding(cfgSI, pdsch);
    strict = sixgr.pdsch.RASIPDSCHContext.materialize( ...
        carrier, pdsch, controlEvent, ...
        localProcedureContext(cfgSI, carrier, dci, pdsch, result.SSBIndex), ...
        "NPhysicalRxAntennas", size(siWave, 2), ...
        "ChannelModel", sixgr.channel.resolveConcreteProfile(cfgSI), ...
        "MaxIterations", sixgr.phy.phycode.resolveLDPCMaxIterations( ...
            cfgSI, "Direction", "DL"));
    result.DCIRNTI = 65535;
    result.PDSCHRBStart = double(dci.PRBStart);
    result.PDSCHNumRB = double(dci.PRBCount);
    result.PDSCHSymbolStart = double(dci.SymbolStart);
    result.PDSCHNumSymbols = double(dci.NumSymbols);
    result.PDSCHModulation = string(dci.Modulation);
    result.CORESET0NumRB = double(type0.CORESET0.NumRB);
    if faultMode == "corruptpdsch"
        siWave = localCorruptPDSCHResources(siWave, carrier, pdsch);
    end
    [pdschRx, ~] = sixgr.phy.dl.PDSCH_Rx(siWave, cfgSI, ...
        "Carrier", carrier, ...
        "Assignment", strict.Assignment, ...
        "ResourcePlan", strict.ResourcePlan, ...
        "ReferenceSignalConfig", strict.ReferenceSignalConfig, ...
        "ReceiverConfig", strict.ReceiverConfig, ...
        "CodingPlan", strict.CodingPlans, ...
        "PrecoderBundle", strict.PrecoderBundle, ...
        "IntegrationContext", strict.IntegrationContext, ...
        "ExecutionProfile", "ra_si_strict");
    pdschRx = sixgr.pdsch.RASIPDSCHContext. ...
        addCompatibilityEvidence(pdschRx);
    result.PDSCHControlEvent = strict.ControlEvent;
    result.PDSCHAssignmentId = strict.Assignment.AssignmentId;
    result.PDSCHExecutionProfile = "ra_si_strict";
    result.PDSCHCanonicalDelegation = logical(sixgr.util.structGet( ...
        pdschRx, "CanonicalDelegation", false));
    result.PDSCHDMRSOk = isfield(pdschRx, "ChannelEstimate") && ~isempty(pdschRx.ChannelEstimate);
    result.SIB1PDSCHChannelEstimateAvailable = logical(sixgr.util.structGet(pdschRx, "ChannelEstimateAvailable", result.PDSCHDMRSOk));
    result.SIB1PDSCHEqualizationAvailable = logical(sixgr.util.structGet(pdschRx, "EqualizationAvailable", false));
    result.SIB1PDSCHReceiverHestSINR_dB = double(sixgr.util.structGet(pdschRx, "ReceiverHestSINR_dB", NaN));
    result.SIB1PDSCHReceiverHestSINRSource = string(sixgr.util.structGet(pdschRx, "ReceiverHestSINRSource", ""));
    result.SIB1PDSCHStrictReceiverEvidenceOk = logical(sixgr.util.structGet(pdschRx, "StrictReceiverEvidenceOk", ...
        result.SIB1PDSCHChannelEstimateAvailable && result.SIB1PDSCHEqualizationAvailable && isfinite(result.SIB1PDSCHReceiverHestSINR_dB)));
    result.SIB1PDSCHEqualizedSymbols = sixgr.util.structGet(pdschRx, ...
        "LayerEqualizedSymbolsForEvidence", sixgr.util.structGet(pdschRx, ...
        "EqualizedSymbolsForEvidence", complex(zeros(0, 1))));
    result.SIB1PDSCHEqualizedSymbolDomain = string(sixgr.util.structGet(pdschRx, ...
        "EqualizedSymbolDomain", ""));
    result.StrictReceiverEvidenceOk = logical(result.StrictReceiverEvidenceOk) && logical(result.SIB1PDSCHStrictReceiverEvidenceOk);
    result.DLSCHCrcPass = logical(pdschRx.Ok);
    if ~logical(pdschRx.Ok)
        result.Status = "pdsch_dlsch_crc_failed";
        result.FailureReason = "SIB1 PDSCH/DL-SCH CRC failed";
        result.StrictOk = false;
        return;
    end
    transportBlockBits = int8(pdschRx.TransportBlock(:));
    if faultMode == "corruptasn1"
        % This explicit receiver-test fault is injected after a successful
        % DL-SCH CRC.  Use a deterministic noncanonical PER payload rather
        % than a small mutation that can legally decode as different SIB1.
        transportBlockBits(:) = int8(1);
    end
    result.SIB1TransportBlockBits = transportBlockBits;
    result.SIB1TransportBlockSize = double(numel(transportBlockBits));
    [rxTree, rxMeta] = ...
        sixgr.rrc.asn1.decodeSIB1UPER(transportBlockBits);
    sibBits = localHexToBits(rxMeta.EncodedHex);
    result.SIB1PayloadBits = sibBits;
    result.SIB1PayloadBytes = ceil(numel(sibBits) / 8);
    result.SIB1TrailingTransportBlockPaddingBits = ...
        double(rxMeta.TrailingTransportBlockPaddingBits);
    result.SIB1ASN1DecodeOk = true;
    result.SIB1SemanticValid = true;
    result.SIB1PayloadHashRx = string(rxMeta.PayloadHash);
    result.SIB1RxTree = rxTree;
    [~, rxSelfHash] = sixgr.rrc.asn1.compareSIB1Trees(rxTree, rxTree);
    result.SIB1RxTreeHash = rxSelfHash.TxTreeHash;
    result.SIB1PayloadHashTx = "";
    result.SIB1TxTreeHash = "";
    result.SIB1TreeEqual = false;
    result.StrictOk = localStrictOk(result);
    if result.StrictOk
        result.Status = "PASS";
        result.FailureReason = "";
    else
        result.Status = "FAIL";
        result.FailureReason = "strict_sib1_condition_failed";
    end
    result.CandidateTable = sixgr.util.structGet(pdcchInfo, "CandidateResults", table());
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
end

function context = localProcedureContext(cfg, carrier, dci, pdsch, receivedSSBIndex)
absoluteSlot = double(sixgr.util.structGet( ...
    cfg, "phy.sib1.pdcchAbsoluteSlot", NaN));
if ~(isscalar(absoluteSlot) && isfinite(absoluteSlot) && ...
        absoluteSlot >= 0 && absoluteSlot == round(absoluteSlot))
    error("sixgr:phy:broadcast:MissingSIB1AbsoluteSlot", ...
        "SIB1 PDCCH/PDSCH absolute slot must be resolved before materialization.");
end
context = struct( ...
    "Procedure", "sib1", ...
    "RNTI", 65535, "RNTIType", "SI-RNTI", ...
    "UEId", 0, ...
    "ServingCellId", double(carrier.NCellID), ...
    "SchedulingCellId", double(carrier.NCellID), ...
    "CCId", 0, "BWPId", 0, "ConfigurationEpoch", 0, ...
    "PDCCHAbsoluteSlot", absoluteSlot, ...
    "PDSCHAbsoluteSlot", absoluteSlot, "K0", 0, ...
    "MCSTable", "qam64", "MCSIndex", double(dci.MCSIndex), ...
    "TargetCodeRate", double(dci.TargetCodeRate), ...
    "XOverhead", sixgr.phy.dl.resolvePDSCHXOverhead( ...
        cfg, pdsch.SymbolAllocation), ...
    "RV", double(dci.RV), "NDI", 1, ...
    "HARQProcessId", 0, "TCIStateId", 0, ...
    "ActiveBWPContextPresent", true, "EpochCurrent", true, ...
    "ServingCellActive", true, "MCSContextSupported", true, ...
    "TCIStateActive", true, "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, "DeploymentAllows1024QAM", false, ...
    "FrequencyRange", string(sixgr.util.structGet(cfg, ...
        "frequency.range_name", sixgr.util.structGet(cfg, ...
        "phy.frequencyRange", "FR1"))), ...
    "OperatingBand", string(sixgr.util.structGet(cfg, ...
        "frequency.band_name", sixgr.util.structGet(cfg, ...
        "initial_access.band_context", "unspecified"))), ...
    "DeploymentClass", "common_search_space_ra_si", ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false);
context.CommonQCLReference = sixgr.pdsch.CommonPDSCHQCLReference.create( ...
    "sib1",receivedSSBIndex,carrier.NCellID,"received_ssb_pbch_identity");
end

function result = localEmptyResult()
result = struct( ...
    "StrictOk", false, "Status", "", "Detail", "", "NCellID", NaN, ...
    "Crash", false, "FailureIdentifier", "", ...
    "TimingOffset", NaN, "FrequencyOffsetHz", NaN, ...
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
if ~strcmpi(strtrim(amplitudeUnit), "sqrt_mW")
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
% antenna-connector reference plane. Disturbance is estimated from SSS
% reference REs, not an unconfigured null-RE interference resource.
try
    ssSinr = sixgr.phy.refsig.measureSSSINRFromSSBGrid( ...
        physicalGrid, ncellid, iBarSSB);
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

function bits = localHexToBits(hex)
bytes = uint8(sscanf(char(hex), "%2x"));
bits = zeros(numel(bytes) * 8, 1, "int8");
for ii = 1:numel(bytes)
    for jj = 1:8
        bits((ii - 1) * 8 + jj) = int8( ...
            bitget(bytes(ii), 9 - jj));
    end
end
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

function cfg = localNormalizeReceiverCfg(cfg, rnti)
if ~isfield(cfg, "phy")
    cfg.phy = struct();
end
if ~isfield(cfg.phy, "carrier")
    cfg.phy.carrier = struct();
end
cfg.phy.carrier.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1));
cfg.phy.carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30)));
cfg.phy.carrier.SubcarrierSpacing_kHz = cfg.phy.carrier.SubcarrierSpacing;
cfg.phy.carrier.NSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 52));
cfg.phy.carrier.NStartGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NStartGrid", 0));
cfg.phy.carrier.NSlot = 0;
cfg.phy.carrier.NFrame = 0;
cfg.phy.pdcch.rnti = double(rnti);
cfg.phy.pdcch.scramblingRNTI = 0;
cfg.phy.pdcch.blindSearch = logical(sixgr.util.structGet(cfg, ...
    "phy.pdcch.blindSearch", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "pdcch_blind_search", ...
    cfg.phy.pdcch.blindSearch, "recoverSIB1FromWaveform");
cfg.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfg.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
end

function [pdcch, cfgSI] = localReceiverPDCCH(carrier, cfg, rnti)
cfgSI = localNormalizeReceiverCfg(cfg, rnti);
pdcch = localBuildPDCCHObject(carrier);
cfgSI.phy.sib1.runtimePDCCH = pdcch;
end

function cfgSI = localSanitizeSIB1PDSCHPrecoding(cfgSI, pdsch)
nLayers = max(1, round(double(pdsch.NumLayers)));
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numLayers", nLayers);
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nLayers", nLayers);
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
resolvedPorts = NaN;
for i = 1:numel(paths)
    path = paths(i);
    Wcfg = sixgr.util.structGet(cfgSI, path, []);
    if isempty(Wcfg)
        continue;
    end
    Wsib = localAdaptSIB1PrecoderMatrix(Wcfg, nLayers);
    if isempty(Wsib)
        cfgSI = sixgr.util.structSet(cfgSI, path, []);
    else
        cfgSI = sixgr.util.structSet(cfgSI, path, Wsib);
        resolvedPorts = size(Wsib, 1);
    end
end
if isfinite(resolvedPorts) && resolvedPorts >= nLayers
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numPorts", resolvedPorts);
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nPorts", resolvedPorts);
else
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numPorts", []);
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nPorts", []);
end
end

function Wout = localAdaptSIB1PrecoderMatrix(Wcfg, nLayers)
Wout = [];
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
if ndims(Wcfg) > 2
    if size(Wcfg, 3) == 1
        Wcfg = squeeze(Wcfg);
    else
        return;
    end
end
if ~isnumeric(Wcfg)
    return;
end
sz = size(Wcfg);
if sz(2) >= nLayers
    Wout = double(Wcfg(:, 1:nLayers));
elseif sz(1) >= nLayers
    Wout = double(Wcfg(1:nLayers, :).');
end
if isempty(Wout) || size(Wout, 1) < nLayers || size(Wout, 2) ~= nLayers
    Wout = [];
    return;
end
colNorm = sqrt(sum(abs(Wout).^2, 1));
if any(~isfinite(colNorm)) || any(colNorm <= eps)
    Wout = [];
    return;
end
Wout = Wout ./ colNorm;
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

function siWave = localExtractSIB1Waveform( ...
        rxWaveform, carrier, sampleRate, absoluteSlot)
prefixSamples = localAbsoluteSlotStartSample( ...
    absoluteSlot, carrier, sampleRate);
endSample = localAbsoluteSlotStartSample( ...
    absoluteSlot + 1, carrier, sampleRate);
if prefixSamples >= size(rxWaveform, 1) || ...
        endSample > size(rxWaveform, 1)
    error("sixgr:phy:broadcast:SIB1WaveformMissing", ...
        "Received waveform does not contain the complete scheduled SIB1 slot [%d,%d).", ...
        prefixSamples, endSample);
end
% PDCCH/PDSCH receiver objects and nrChannelEstimate operate on the one-slot
% grid identified by the decoded Type-0 monitoring occasion.  Passing the
% remainder of the acquisition capture silently changes the grid to 5/10
% slots and invalidates both channel estimation and resource indices.
siWave = rxWaveform(prefixSamples + (1:(endSample - prefixSamples)), :);
end

function ordinal = localMonitoringOccasionOrdinal(cfg)
raw = sixgr.util.structGet(cfg, ...
    "initial_access.type0.monitoring_occasion_ordinal", ...
    sixgr.util.structGet(cfg, ...
    "phy.sib1.monitoringOccasionOrdinal", []));
if isempty(raw)
    error("sixgr:phy:broadcast:MissingType0MonitoringOccasion", ...
        "Strict SIB1 recovery requires initial_access.type0.monitoring_occasion_ordinal.");
end
ordinal = double(raw);
if ~(isscalar(ordinal) && isfinite(ordinal) && ordinal >= 1 && ...
        ordinal == round(ordinal))
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "monitoring_occasion_ordinal must be a positive integer.");
end
end

function carrier = localCarrierAtAbsoluteSlot(carrier, absoluteSlot)
absoluteSlot = double(absoluteSlot);
if ~(isscalar(absoluteSlot) && isfinite(absoluteSlot) && ...
        absoluteSlot >= 0 && absoluteSlot == round(absoluteSlot))
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "Resolved Type0 absolute slot must be a nonnegative integer.");
end
slotsPerFrame = 10 * round(double(carrier.SlotsPerSubframe));
carrier.NFrame = floor(absoluteSlot / slotsPerFrame);
carrier.NSlot = mod(absoluteSlot, slotsPerFrame);
end

function startSample = localAbsoluteSlotStartSample( ...
        absoluteSlot, carrier, sampleRate)
slotsPerSubframe = round(double(carrier.SlotsPerSubframe));
if ~(isscalar(slotsPerSubframe) && isfinite(slotsPerSubframe) && ...
        slotsPerSubframe >= 1)
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "Carrier SlotsPerSubframe is invalid.");
end
slotDurationSeconds = 1e-3 / slotsPerSubframe;
startSample = round(double(absoluteSlot) * ...
    slotDurationSeconds * double(sampleRate));
end

function siWave = localCorruptPDCCHResources(siWave, carrier, pdcch)
rxGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, siWave);
slotSymbols = max(1, round(double(carrier.SymbolsPerSlot)));
if size(rxGrid, 2) > slotSymbols
    rxGrid = rxGrid(:, 1:slotSymbols, :);
end
[pdcchInd, ~, dmrsInd] = nrPDCCHResources(carrier, pdcch);
rxGrid(pdcchInd) = 0;
rxGrid(dmrsInd) = 0;
siWave = sixgr.phy.waveform.ofdmModulate(carrier, rxGrid);
end

function siWave = localCorruptPDSCHResources(siWave, carrier, pdsch)
rxGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, siWave);
slotSymbols = max(1, round(double(carrier.SymbolsPerSlot)));
if size(rxGrid, 2) > slotSymbols
    rxGrid = rxGrid(:, 1:slotSymbols, :);
end
try
    [pdschInd, ~] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
catch
    [pdschInd, ~] = nrPDSCHIndices(carrier, pdsch);
end
try
    [dmrsInd, ~] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);
catch
    dmrsInd = [];
end
rxGrid(pdschInd) = 0;
if ~isempty(dmrsInd)
    rxGrid(dmrsInd) = 0;
end
siWave = sixgr.phy.waveform.ofdmModulate(carrier, rxGrid);
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
