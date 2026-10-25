function result=recoverSIB1UsingReceivedMIB(capture,cfg,context,varargin)
%RECOVERSIB1USINGRECEIVEDMIB Actual SI decode using an earlier received MIB.
% No SSB/PBCH receiver is called. Prior BCH identity is never a new BCH row.
% AbsoluteMonitoringSlot is a receive search choice checked against the
% received-MIB Type-0 calendar, not evidence that a transmitter emitted SI.
p=inputParser;
p.addParameter('ReceiverRNTI',65535,@(x)isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x));
p.addParameter('FaultMode',"",@(x)(ischar(x)||isstring(x))&&isscalar(string(x)));
p.addParameter('AbsoluteMonitoringSlot',[],@(x)isempty(x)||(isa(x,'double')&&isreal(x)&& ...
    isscalar(x)&&isfinite(x)&&x>=0&&x==fix(x)&&x<flintmax/160));
p.parse(varargin{:});
assert(isa(context,'sixgr.phy.broadcast.ReceivedMIBContext') && isscalar(context), ...
    'sixgr:phy:broadcast:InvalidReceivedMIBContext','Use the retained original typed BCH context.');
context.validate(cfg);
cfg=sixgr.phy.broadcast.ReceivedMIBContext.normalizeReceiverConfig(cfg,p.Results.ReceiverRNTI);
d=context.Data;
sampleRate=d.SampleRateHz;
[carrier,~]=sixgr.phy.grid.makeCarrier(cfg);
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
assert(sampling.SampleRateHz==sampleRate, ...
    'sixgr:phy:broadcast:ReceivedMIBSampleRateMismatch','SI and retained MIB must use one sample clock.');
typed=isa(capture,'sixgr.phy.waveform.WaveformObservationBuffer');
if typed
    assert(isscalar(capture) && capture.SampleRateHz==sampleRate && ...
        capture.NumReceiveAntennas==d.NumReceiveAntennas, ...
        'sixgr:phy:broadcast:ReceivedMIBSampleRateMismatch','SI capture clock and receive-column layout must match the original receiver.');
    rxWaveform=capture.readComplete(); % incomplete buffers are not CRC trials
    assert(d.GlobalCaptureEpochBound, ...
        'sixgr:phy:broadcast:ReceivedMIBGlobalEpochRequired','Raw-array MIB context cannot authorize a global later capture.');
    captureStartSample=capture.StartSample;
    sameCapture=captureStartSample==d.CaptureStartSample && ...
        capture.EndSampleExclusive==d.CaptureEndSampleExclusive;
    if sameCapture
        assert(capture.sampleHash()==d.CaptureSampleSHA256, ...
            'sixgr:phy:broadcast:ReceivedMIBCaptureMismatch','Original capture bounds cannot be reused for changed samples.');
    else
        assert(captureStartSample>=d.AvailableAtSample, ...
            'sixgr:phy:broadcast:ReceivedMIBNotYetAvailable','A separately received SI capture cannot precede availability of its prior MIB.');
    end
    frameOriginLocal=d.ReceivedFrameOriginSample-captureStartSample;
    phaseOffset=captureStartSample-d.CFOPhaseOriginSample;
else
    validateattributes(capture,{'single','double'},{'2d','finite','nonempty'});
    assert(~d.GlobalCaptureEpochBound && ...
        size(capture,1)==d.CaptureSampleCount && size(capture,2)==d.NumReceiveAntennas && ...
        sixgr.phy.waveform.WaveformHash.runtimeArray(capture)==d.CaptureSampleSHA256, ...
        'sixgr:phy:broadcast:ReceivedMIBCaptureMismatch', ...
        'Unbound array context is reusable only with the exact original capture.');
    rxWaveform=capture; captureStartSample=NaN;
    frameOriginLocal=d.FrameOriginInOriginalCapture_samples;
    phaseOffset=-d.CFOPhaseOriginInOriginalCapture_samples;
end
mib=d.MIB; receivedFrame=d.AbsoluteFrameNumber;
result=localEmptySIResult();
result.PriorMIBAvailable=true;
result.PriorBCHContextSHA256=context.SHA256;
result.PriorBCHSource=d.Source;
result.PriorBCHAvailableAtSample=d.AvailableAtSample;
result.PriorBCHStrictReceiverEvidenceOk=d.OriginalStrictReceiverEvidenceOk;
result.PriorReceivedNCellID=d.NCellID;
result.PriorReceivedSSBIndex=d.SSBIndex;
result.NewBCHReceptionAttempted=false;
result.SIB1CaptureStartSample=captureStartSample;
result.ReceivedFrameOriginInCapture_samples=frameOriginLocal;
result.SIB1RadioFrameClock=d.RadioFrameClock;
result.SIB1AvailableCaptureSamples=size(rxWaveform,1);
result.SampleRateHz=sampleRate;
result.FrequencyOffsetHz=d.FrequencyOffsetHz;
result.SIB1CFOPhaseOriginSample=d.CFOPhaseOriginSample;
result.SIB1CFOPhaseOriginInOriginalCapture_samples=d.CFOPhaseOriginInOriginalCapture_samples;
sixgr.runtime.RuntimeCallLedger.record( ...
    "sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB","SIB1","DL", ...
    struct('Stage',"RX",'RecoveryScope',"SI_ONLY_USING_PRIOR_RECEIVED_MIB"));
try
    if d.ReceiverGeometry.FrequencyRange=="FR1" && ...
            any(d.DecodedKSSBEvidence.Lmax==[4 8]) && d.DecodedKSSBEvidence.DecodedKSSB>=24
        % The original CRC-valid PBCH remains valid. This indication refers
        % to the association of this received SS/PBCH block, not proof that
        % the entire cell has no SIB1. Do not attempt control/data decoding.
        result.Status="NO_ASSOCIATED_TYPE0_FOR_RECEIVED_SSB";
        result.SIB1ObservationStatus="not_applicable_no_associated_type0";
        result.FailureReason="Received FR1 kSSB indicates no associated Type0 CORESET/SIB1 for this SS/PBCH block";
        return;
    end
    [supported,reason]=sixgr.phy.broadcast.siRNTIWaveformSupported();
    assert(supported,'sixgr:phy:broadcast:SIRNTIUnsupported','%s',reason);
    [type0, cfgSI] = sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier, cfg, mib, ...
        "RNTI", double(p.Results.ReceiverRNTI));
    if ~isempty(p.Results.AbsoluteMonitoringSlot)
        requested=p.Results.AbsoluteMonitoringSlot;
        assert(d.GlobalCaptureEpochBound, ...
            'sixgr:phy:broadcast:ReceivedMIBGlobalEpochRequired', ...
            'A later monitoring window requires the original typed global capture clock.');
        window=sixgr.phy.pdcch.resolveType0MonitoringWindow(type0.Context,requested,requested+1);
        assert(height(window.MonitoringOccasions)==1, ...
            'sixgr:phy:broadcast:InvalidReceivedSIMonitoringSlot', ...
            'The requested receive slot is not a legal monitoring occasion from the received MIB.');
        type0.MonitoringOccasions=window.MonitoringOccasions;
        monitoringOccasionOrdinal=1;
        result.Type0MonitoringWindowSHA256=window.WindowSHA256;
    else
        monitoringOccasionOrdinal = localMonitoringOccasionOrdinal(cfg);
    end
    if monitoringOccasionOrdinal > height(type0.MonitoringOccasions)
        error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
            "Type0 monitoring occasion ordinal %d exceeds the %d resolved occasions.", ...
            monitoringOccasionOrdinal, height(type0.MonitoringOccasions));
    end
    monitoringOccasion = type0.MonitoringOccasions( ...
        monitoringOccasionOrdinal, :);
    sib1AbsoluteSlot = double(monitoringOccasion.AbsoluteSlot);
    carrier = localCarrierAtAbsoluteSlot(carrier, sib1AbsoluteSlot);
    % Bind the receiver's complete clock from its decoded Type-0 occasion.
    % Updating only carrier.NFrame/NSlot leaves the PDCCH control-event
    % receipt at the old acquisition slot (or NaN) in lls6g.runtime.
    cfgSI=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfgSI,sib1AbsoluteSlot+1);
    cfgSI = sixgr.util.structSet(cfgSI, ...
        "phy.sib1.pdcchAbsoluteSlot", sib1AbsoluteSlot);
    result.SIB1AbsoluteSlot = sib1AbsoluteSlot;
    result.Type0FrameNumberSource=type0.SSBFrameNumberSource;
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

    % The decoded MIB/SSB can point beyond a completed acquisition buffer.
    % That is an unobserved SI occasion, not an attempted CRC failure. The
    % decision uses only decoded scheduling information and capture extent,
    % never the transmitter's selected SI occasion or payload.
    [siWave, firstSample, endSample] = localExtractSIB1Waveform( ...
        rxWaveform, carrier, sampleRate, sib1AbsoluteSlot, ...
        receivedFrame,frameOriginLocal);
    result.SIB1ObservationStartSample=firstSample;
    result.SIB1ObservationEndSampleExclusive=endSample;
    result.SIB1ObservationComplete=firstSample>=0 && endSample<=size(rxWaveform,1);
    result.SIB1ObservationSampleDomain="relative_to_original_received_capture_start_zero_based";
    if ~result.SIB1ObservationComplete
        result.SIB1ObservationStatus="incomplete_capture";
        result.Status="INCOMPLETE_OBSERVATION";
        result.FailureIdentifier="sixgr:phy:broadcast:SIB1WaveformMissing";
        result.FailureReason=string(sprintf( ...
            'Scheduled SIB1 slot [%d,%d) is outside the received capture [0,%d).', ...
            firstSample,endSample,size(rxWaveform,1)));
        return;
    end
    result.SIB1ObservationStatus="complete_received_samples";
    result.SIB1ReceptionAttempted=true;

    % SSB_Rx corrects its own extraction, not the caller's full capture.
    % Transfer that RECEIVER estimate to the same noisy full-carrier samples
    % before SI-RNTI PDCCH/PDSCH demodulation. The deterministic SSB placement
    % shift is deliberately not applied to the full carrier.
    cfoHz=double(result.FrequencyOffsetHz);
    if ~(isscalar(cfoHz) && isfinite(cfoHz))
        error("sixgr:phy:broadcast:MissingSIB1FrequencyEstimate", ...
            "SIB1 reception requires the finite frequency estimate recovered from received SSB samples.");
    end
    sampleTime=(phaseOffset+firstSample+(0:size(siWave,1)-1)).'/sampleRate;
    result.SIB1InputSampleSHA256=sixgr.phy.waveform.WaveformHash.runtimeArray(siWave);
    siWave=siWave.*cast(exp(-1j*2*pi*cfoHz*sampleTime),"like",siWave);
    result.SIB1CFOPhaseStartSample=phaseOffset+firstSample;
    result.SIB1CFOCorrectedSampleSHA256=sixgr.phy.waveform.WaveformHash.runtimeArray(siWave);
    result.SIB1CFOCorrectionApplied_Hz=cfoHz;
    result.SIB1CFOCorrectionSource="received_ssb_pss_cp_frequency_estimate";
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
        localProcedureContext(cfgSI, carrier, dci, pdsch, d.SSBIndex), ...
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
    result.StrictReceiverEvidenceOk = logical(result.SIB1PDSCHStrictReceiverEvidenceOk);
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
    result.StrictOk=false; result.Status="ERROR"; result.Crash=true;
    result.FailureIdentifier=string(ME.identifier);
    result.FailureReason=string(ME.identifier)+":"+string(ME.message);
    result.Errors=string(getReport(ME,'extended','hyperlinks','off'));
end
end

function result=localEmptySIResult()
result=struct('StrictOk',false,'Status',"started",'FailureReason',"", ...
    'FailureIdentifier',"",'Errors',"",'Crash',false, ...
    'Skipped',false,'ProxyUsed',false,'ToolboxMissing',false,'UsedOracleFields',strings(0,1), ...
    'StrictReceiverEvidenceOk',false,'SIB1ReceptionAttempted',false, ...
    'SIB1ObservationComplete',false,'SIB1ObservationStatus',"not_evaluated", ...
    'SIB1ObservationStartSample',NaN,'SIB1ObservationEndSampleExclusive',NaN, ...
    'SIB1ObservationSampleDomain',"relative_to_original_received_capture_start_zero_based", ...
    'Type0MonitoringWindowSHA256',"",'Type0FrameNumberSource',"not_resolved", ...
    'CORESET0Present',false,'PDCCHCandidatesAttempted',0,'DCIBlindDecodeSuccess',false, ...
    'DCICrcPass',false,'DCIRNTI',NaN,'DCIFormat',"",'FalseCandidateCount',0, ...
    'PDSCHDMRSOk',false,'DLSCHCrcPass',false,'SIB1ASN1DecodeOk',false, ...
    'SIB1SemanticValid',false,'CandidateTable',table());
end

function ok=localStrictOk(result)
ok=~result.Skipped && ~result.ProxyUsed && ~result.ToolboxMissing && ...
    isempty(result.UsedOracleFields) && result.PriorMIBAvailable && ...
    result.PriorBCHStrictReceiverEvidenceOk && result.StrictReceiverEvidenceOk && ...
    result.CORESET0Present && result.PDCCHCandidatesAttempted>0 && ...
    result.DCIBlindDecodeSuccess && result.DCICrcPass && result.DCIRNTI==65535 && ...
    result.DCIFormat=="1_0" && result.FalseCandidateCount==0 && result.PDSCHDMRSOk && ...
    result.DLSCHCrcPass && result.SIB1ASN1DecodeOk && result.SIB1SemanticValid;
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
    "DMRSTypeAPosition", double(cfg.phy.mib.dmrsTypeAPosition), ...
    "Type0MultiplexingPattern", double(cfg.phy.sib1.type0MultiplexingPattern), ...
    "SIB1FrequencyReference", dci.FrequencyReference, ...
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

function [siWave, prefixSamples, endSample] = localExtractSIB1Waveform( ...
        rxWaveform, carrier, sampleRate, absoluteSlot, receivedFrame,frameOriginLocal)
relativeSlot=absoluteSlot-receivedFrame*carrier.SlotsPerFrame;
prefixSamples = localAbsoluteSlotStartSample( ...
    relativeSlot, carrier, sampleRate)+frameOriginLocal;
endSample = localAbsoluteSlotStartSample( ...
    relativeSlot + 1, carrier, sampleRate)+frameOriginLocal;
if prefixSamples < 0 || prefixSamples >= size(rxWaveform, 1) || ...
        endSample > size(rxWaveform, 1)
    siWave=rxWaveform([],:);
    return;
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
% Use physical CP-OFDM boundaries, not a rounded mean slot duration.
startSample=sixgr.phy.frame.slotStartSample(carrier,absoluteSlot,sampleRate);
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
