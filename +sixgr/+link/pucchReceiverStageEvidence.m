function evidence=pucchReceiverStageEvidence(rx,assignment)
%PUCCHRECEIVERSTAGEEVIDENCE Export executed receiver stages, not channel policy.
% No transmitter, payload, configured noise or propagation assumptions are
% inputs. This function does not qualify a detection or claim TX success.
mode=string(rx.ChannelEstimationMode);
assert(isscalar(mode) && any(mode==["dmrs_per_resource_mmse_equalization", ...
    "awgn_direct_resource_extraction","format0_noncoherent_sequence_detection"]), ...
    'sixgr:link:UnknownPUCCHReceiverStage','Unrecognized executed PUCCH receiver mode.');
estimated=mode=="dmrs_per_resource_mmse_equalization";
source="not_applicable_"+mode;
if estimated, source="pucch_dmrs_per_resource_nrChannelEstimate"; end
evidence=struct( ...
    'ChannelEstimationMode',mode, ...
    'ChannelEstimateApplicable',estimated, ...
    'ChannelEstimateAttempted',estimated, ...
    'ChannelEstimateAvailable',estimated && ~isempty(rx.ChannelEstimate) && all(isfinite(rx.ChannelEstimate(:))), ...
    'ChannelEstimateSource',source, ...
    'EqualizationApplicable',estimated, ...
    'EqualizationAttempted',estimated, ...
    'EqualizationAvailable',estimated && ...
        ~isempty(fieldnames(sixgr.util.structGet(rx,'EqualizerInfo',struct()))));
% Stage readiness is NOT the same thing as having executed an estimator.
% Noncoherent/direct extraction still requires its receiver and extraction
% checks at the caller, but has no DM-RS equalizer prerequisite.
evidence.ReceiverEstimationStagesReady=~estimated || ...
    (evidence.ChannelEstimateAvailable && evidence.EqualizationAvailable);
if isfield(rx,'EVMApplicable') && isfield(rx,'EVMPercent')
    evidence.ReceiverEVMApplicable=logical(rx.EVMApplicable);
    evidence.ReceiverEVMPercent=double(rx.EVMPercent);
    evidence.EVM_rms=double(rx.EVMPercent)/100;
    evidence.EVMReferenceSource=string(sixgr.util.structGet(rx, ...
        'EVMReferenceSource',"legacy_receiver_constellation_reference_not_retained"));
    evidence.EVMValueStatus="MEASURED_DECISION_DIRECTED";
    if ~rx.EVMApplicable
        evidence.EVMReferenceSource="not_applicable_sequence_detection";
        evidence.EVMValueStatus="NOT_APPLICABLE_SEQUENCE_DETECTION";
    elseif ~isfinite(rx.EVMPercent)
        evidence.EVMValueStatus="UNAVAILABLE_NO_FINITE_RECEIVER_SYMBOL_EVM";
    end
    for name=["EVMReferenceModulation","EVMSymbolCount","EVMErrorEnergy","EVMReferenceEnergy"]
        if isfield(rx,name), evidence.(name)=rx.(name); end
    end
end
% Canonical RX supplies typed HARQ evidence. Copy it to live/final rows,
% including receive-only and CSI/SR-only occasions. Older retained receiver
% structs without this evidence must not gain inferred ACK fields.
for name=["ReceiverExpectedHARQBitCount","DecodedHARQBitCount", ...
        "DecodedHARQBitVector","HARQObservationApplicable","HARQObservationValid", ...
        "ObservedHARQACKBitCount","ObservedHARQNACKBitCount","AckObserved", ...
        "AckObservedValid","HARQObservationStatus","HARQObservationSource"]
    if isfield(rx,name), evidence.(name)=rx.(name); end
end
% Metric validity is distinct from detection or CRC success: a finite zero
% metric can be a valid DTX observation. Copy the executed detector flag;
% leave it absent for legacy inputs that contain no such evidence.
if isfield(rx,'DetectionMetricValid')
    flag=rx.DetectionMetricValid;
    assert((islogical(flag) || isnumeric(flag)) && isscalar(flag) && ...
        isreal(flag) && isfinite(flag) && any(flag==[0 1]), ...
        'sixgr:link:InvalidPUCCHMetricValidity','Detector validity must be a scalar boolean.');
    evidence.DetectionMetricValid=logical(flag);
end
if isfield(rx,'DetectionOutcome')
    outcome=string(rx.DetectionOutcome);
    assert(isscalar(outcome) && any(outcome==["detected","dtx","unavailable"]), ...
        'sixgr:link:InvalidPUCCHDetectionOutcome', ...
        'Detection outcome must come from the receiver presence decision.');
    evidence.DetectionOutcome=outcome;
end
timing=rx.ReceiveTiming;
evidence.ReceiverTimingEvidenceJSON=string(jsonencode(timing));
evidence.EstimatedTimingOffsetSamples=timing.TimingOffsetSamples;
evidence.AppliedTimingCorrectionSamples=timing.AppliedTimingCorrectionSamples;
evidence.TimingEstimateSource=string(timing.TimingSource);
evidence.TimingEstimateUsed=isfinite(timing.TimingOffsetSamples) && ...
    any(string(timing.TimingSource)==["received_reference_correlation_bounded_search", ...
        "received_configured_SR_sequence_bounded_search", ...
        "completed_same_slot_received_UL_pilot_alignment"]) && ...
    ~timing.OracleTimingUsed;
evidence.ReceiverTimingOracleUsed=logical(timing.OracleTimingUsed);
evidence.ReceiverZeroPaddingUsed=logical(timing.ReceiverZeroPaddingUsed);
evidence.ReceiverInputSampleCount=double(sixgr.util.structGet(timing,'InputSampleCount',NaN));
evidence.ReceiverDemodulatedSampleCount=double(sixgr.util.structGet(timing,'DemodulatedSampleCount',NaN));
evidence.EffectiveGridNoiseInterferenceVariance=rx.EffectiveGridNoiseInterferenceVariance;
evidence.DecodeNoiseInterferenceVariance=rx.DecodeNoiseInterferenceVariance;
evidence.EqualizedDecodeNoiseInterferenceVariance=rx.EqualizedDecodeNoiseInterferenceVariance;
evidence.DecodeNoiseVarianceDomain="equalized_symbol";
if ~estimated
    evidence.DecodeNoiseVarianceDomain="resource_grid_direct_extraction";
end
if rx.NoncoherentSequenceDetection && isnan(rx.DecodeNoiseInterferenceVariance)
    evidence.DecodeNoiseVarianceDomain="not_consumed_noncoherent_sequence_detection";
end
if nargin>1
    assert(string(rx.AssignmentDigest)==string(assignment.Digest), ...
        'sixgr:link:PUCCHReceiverEvidenceAssignmentMismatch', ...
        'Resource evidence must belong to the assignment actually decoded.');
    resource=assignment.Resource.Data;
    evidence.ReceiverPUCCHResourceId=string(assignment.Resource.ID);
    evidence.ReceiverPUCCHFormat=assignment.Format;
    evidence.ReceiverPUCCHPRBStart=resource.StartPRB;
    evidence.ReceiverPUCCHPRBCount=resource.NumPRBs;
    evidence.ReceiverPUCCHSymbolStart=resource.StartSymbol;
    evidence.ReceiverPUCCHNumSymbols=resource.NumSymbols;
    evidence.ReceiverPUCCHIntraSlotHopping=resource.IntraSlotHopping;
    evidence.ReceiverPUCCHSecondHopStartPRB=resource.SecondHopStartPRB;
end
end
