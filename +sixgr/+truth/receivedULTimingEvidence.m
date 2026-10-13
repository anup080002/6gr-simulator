function evidence=receivedULTimingEvidence(state,ue)
% Distinct received command and gNB pilot-observation planes. No TX origin,
% geometry, injected delay or generic capture trim may manufacture a TA.
evidence=struct('TimingAdvanceCommandStatus',"unavailable_no_received_TAG", ...
    'TimingAdvanceCommandSource',"",'TimingAdvanceKnownAtSample',NaN, ...
    'ReceivedTimingAdvanceCommand',NaN,'ReceivedTimingAdvanceNTA_Tc',NaN, ...
    'ReceivedTimingAdvanceOffset_Tc',NaN,'ReceivedTimingAdvanceTotal_Tc',NaN, ...
    'ReceivedTimingAdvanceSamples',NaN,'ReceivedTimingAdvanceTotalSamples',NaN, ...
    'TimingAdvanceAvailableAtSample',NaN,'TimingAdvanceEffectiveAtSample',NaN, ...
    'TimingAdvanceExpirySampleExclusive',NaN, ...
    'ULArrivalOffsetFromNominal_samples',NaN,'ULCaptureExtractionOffset_samples',NaN, ...
    'ULArrivalObservationStartSample',NaN,'ULArrivalReferenceNominalStartSample',NaN, ...
    'ULArrivalReferenceAvailableAtSample',NaN,'ULArrivalReferenceAgeSlots',NaN, ...
    'ULArrivalReferenceSource',"",'ULArrivalReferenceStatus',"unavailable_no_received_pilot");
contexts=sixgr.util.structGet(state,'ConnectedULTimingByUE',{});
if numel(contexts)<ue || isempty(contexts{ue}), return; end
context=sixgr.truth.CoupledTruthRuntime.receivedULTimingContextRuntime( ...
    state,ue,state.CurrentServingIdx(ue));
ta=context.ReceivedRARTiming;
fs=ta.SampleRateHz;
assert(isequaln(ta,sixgr.phy.ra.resolveRARTimingAdvance(ta.Command,ta.FirstULSCSkHz,fs)), ...
    'sixgr:truth:TimingEvidenceAuthorityMismatch','TA evidence must retain the exact received RAR conversion.');
offset=context.Offset;
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',offset.IEPresent, ...
    'TimingAdvanceOffset',offset.ReceivedIE);
assert(isequaln(offset,sixgr.phy.frame.resolveULTimingAdvanceOffset(common,offset.FrequencyRange)), ...
    'sixgr:truth:TimingEvidenceAuthorityMismatch','TA offset must retain its decoded common-cell authority.');
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
if isfield(state,'SharedWaveformStream') && isa(state.SharedWaveformStream,'sixgr.truth.CoupledWaveformStream')
    assert(fs==state.SharedWaveformStream.SampleRateHz, ...
        'sixgr:truth:TimingEvidenceClockMismatch','TAG and observed shared stream must use the same sample clock.');
    now=state.SharedWaveformStream.Events.NextSampleIndex;
else
    slot=double(state.CurrentSlot);
    if string(sixgr.util.structGet(state,'RuntimeViewMode','execution'))=="future_ul_grant_planning"
        slot=double(state.PlanningDecisionSlot);
    end
    % Component/runtime snapshots without a shared sample engine know only
    % the entered slot boundary, not the end of a future observation.
    now=sixgr.phy.frame.slotStartSample(carrier,max(0,slot-1),fs);
end
evidence.TimingAdvanceKnownAtSample=now;
available=context.TimingAdvanceAvailableAtSample;
effective=context.TimingAdvanceEffectiveAtSample;
expiry=context.TimeAlignmentExpirySampleExclusive;
validateattributes(available,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(effective,{'numeric'},{'scalar','real','finite','integer','>=',available});
validateattributes(expiry,{'numeric'},{'scalar','real','nonnan','positive'});
if now<available
    evidence.TimingAdvanceCommandStatus="unavailable_not_yet_received";
    return;
end
evidence.ReceivedTimingAdvanceCommand=ta.Command;
evidence.ReceivedTimingAdvanceNTA_Tc=ta.NTA_Tc;
evidence.ReceivedTimingAdvanceOffset_Tc=double(offset.NTAOffset_Tc);
evidence.ReceivedTimingAdvanceTotal_Tc=ta.NTA_Tc+double(offset.NTAOffset_Tc);
evidence.ReceivedTimingAdvanceSamples=ta.Samples;
evidence.ReceivedTimingAdvanceTotalSamples=evidence.ReceivedTimingAdvanceTotal_Tc / ...
    (double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs);
evidence.TimingAdvanceAvailableAtSample=available;
evidence.TimingAdvanceEffectiveAtSample=effective;
evidence.TimingAdvanceExpirySampleExclusive=expiry;
evidence.TimingAdvanceCommandSource="received_initial_TAG_RAR";
if now>=expiry
    evidence.TimingAdvanceCommandStatus="expired";
elseif now<effective
    evidence.TimingAdvanceCommandStatus="received_pending_application";
else
    evidence.TimingAdvanceCommandStatus="effective";
end
reference=sixgr.truth.selectReceivedULTimingReference(state,ue,now);
if isempty(reference), return; end
if ~isequaln(reference.TAG,context)
    evidence.ULArrivalReferenceStatus="unavailable_prior_TAG";
    return;
end
rnti=sixgr.truth.CoupledRadioIdentity.resolve(state,ue,state.CurrentServingIdx(ue));
expectedIdentity=struct('RNTI',double(rnti),'NCellID',context.DLReference.NCellID, ...
    'SCSkHz',carrier.SubcarrierSpacing,'NSizeGrid',carrier.NSizeGrid, ...
    'NStartGrid',carrier.NStartGrid,'CyclicPrefix',carrier.CyclicPrefix, ...
    'SampleRateHz',fs,'CenterFrequencyHz',state.CfgMobility.frequency.centerFrequencyHz, ...
    'ComponentCarrier',state.CfgMobility.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ULBWPID',state.CfgMobility.phy.frame.DefaultIdentity.ULBWPID);
assert(isequaln(reference.Identity,expectedIdentity) && reference.SampleRateHz==fs, ...
    'sixgr:truth:TimingEvidenceIdentityMismatch', ...
    'A received UL pilot cannot be published as another UE, cell, BWP, carrier or sample clock.');
evidence.ULArrivalOffsetFromNominal_samples=reference.ArrivalOffsetFromNominalSamples;
evidence.ULCaptureExtractionOffset_samples=reference.NominalStartSample+ ...
    reference.ArrivalOffsetFromNominalSamples-reference.ObservationStartSample;
evidence.ULArrivalObservationStartSample=reference.ObservationStartSample;
evidence.ULArrivalReferenceNominalStartSample=reference.NominalStartSample;
evidence.ULArrivalReferenceAvailableAtSample=reference.AvailableAtSample;
evidence.ULArrivalReferenceSource=reference.SourceSignal;
sourceSlot=sixgr.phy.frame.slotIndexFromStartSample(carrier,reference.NominalStartSample,fs);
% The canonical slot index already owns numerology-aware frame timing.
consumerSlot=double(sixgr.util.structGet(state,'CurrentCanonicalSlot',state.CurrentSlot))-1;
evidence.ULArrivalReferenceAgeSlots=consumerSlot-sourceSlot;
maxAge=sixgr.util.structGet(state.CfgMobility,'phy.synchronization.maxReceivedULTimingAgeSlots',NaN);
evidence.ULArrivalReferenceStatus="measured";
if ~isfinite(maxAge) || evidence.ULArrivalReferenceAgeSlots<0 || ...
        evidence.ULArrivalReferenceAgeSlots>maxAge
    evidence.ULArrivalReferenceStatus="measured_stale_not_current_alignment";
end
end
