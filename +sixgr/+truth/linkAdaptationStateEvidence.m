function evidence=linkAdaptationStateEvidence(state,ue)
%LINKADAPTATIONSTATEEVIDENCE Read receiver-owned state, not grant-applied AMC.
% A received ACK can update OLLA before the first delivered CSI report.
% Do not overwrite frozen grant fields with that newer state or infer state
% from decoder CRCs, pending UE reports, or the scheduler's local OLLA copy.
evidence=struct();
for direction=["DL","UL"]
    prefix="Runtime"+direction;
    adaptation=struct(); latest=struct();
    states=sixgr.util.structGet(state,direction+"LinkAdaptationState",{});
    reports=sixgr.util.structGet(state,"Latest"+direction+"Feedback",struct([]));
    if isfinite(ue) && ue>=1 && ue==fix(ue)
        if iscell(states) && ue<=numel(states) && isstruct(states{ue}) && isscalar(states{ue})
            adaptation=states{ue};
        end
        if isstruct(reports) && ue<=numel(reports)
            latest=reports(ue);
        end
    end
    evidence.(prefix+"AdaptationStatePresent")=~isempty(fieldnames(adaptation));
    evidence.(prefix+"ILLAUpdateCount")=double(sixgr.util.structGet(adaptation,'UpdateCount',NaN));
    evidence.(prefix+"HasAcceptedSpatialDecision")=logical(sixgr.util.structGet(adaptation,'HasAcceptedSpatialDecision',false));
    evidence.(prefix+"InitialSpatialConfirmationRequired")=double(sixgr.util.structGet(adaptation,'InitialSpatialRequiredCount',NaN));
    evidence.(prefix+"SpatialConfigurationEpoch")=double(sixgr.util.structGet(adaptation,'SpatialConfigurationEpoch',NaN));
    evidence.(prefix+"AcceptedRank")=double(sixgr.util.structGet(adaptation,'SchedulerAcceptedRank',NaN));
    evidence.(prefix+"PendingRankIncrease")=double(sixgr.util.structGet(adaptation,'RankIncreaseCandidate',NaN));
    evidence.(prefix+"RankConfirmationCount")=double(sixgr.util.structGet(adaptation,'RankIncreaseConfirmationCount',NaN));
    evidence.(prefix+"RankConfirmationRequired")=double(sixgr.util.structGet(adaptation,'RankIncreaseRequiredCount',NaN));
    evidence.(prefix+"OLLAUpdateCount")=double(sixgr.util.structGet(adaptation,'OLLAUpdateCount',NaN));
    % DeltaMCS is the historical internal name; its value is a dB margin,
    % not an additive integer MCS step. Export its actual unit explicitly.
    evidence.(prefix+"OLLAMargin_dB")=double(sixgr.util.structGet(adaptation,'DeltaMCS',NaN));
    evidence.(prefix+"OLLAStateAuthority")=string(sixgr.util.structGet(adaptation,'OLLAStateAuthority',""));
    evidence.(prefix+"LastOLLAFeedbackSourceSlot")=double(sixgr.util.structGet(adaptation,'LastOLLAFeedbackSourceSlot',NaN));
    evidence.(prefix+"LastOLLAFeedbackEligible")=logical(sixgr.util.structGet(adaptation,'LastOLLAFeedbackEligible',false));
    evidence.(prefix+"LastOLLAFeedbackReason")=string(sixgr.util.structGet(adaptation,'LastOLLAFeedbackExclusionReason',""));
    evidence.(prefix+"AMCFeedbackValid")=logical(sixgr.util.structGet(latest,'Valid',false));
    evidence.(prefix+"AMCFeedbackSourceSlot")=double(sixgr.util.structGet(latest,'SourceSlot',NaN));
    evidence.(prefix+"AMCFeedbackDeliveredSlot")=double(sixgr.util.structGet(latest,'DeliveredSlot',NaN));
    evidence.(prefix+"AdaptationEvidenceRole")="receiver_state_for_future_grants_not_frozen_grant_applied_state";
end
end
