function state=completeInitialNRRRCExpiry(state,item)
% original T300 callback -> initial UE MAC reset.
id='sixgr:truth:NRRRCInitialReset';
owner=state.SharedWaveformStream;
owner.validateOriginalRRCSetupExpiry(item);
ue=item.UE;
assert(isfield(state,'NRRRCSetupAttemptsByUE') && numel(state.NRRRCSetupAttemptsByUE)>=ue, ...
    id,'Retain the original RRC attempt.');
attempt=state.NRRRCSetupAttemptsByUE{ue};
assert(attempt.Context.RunID==item.Context.RunID && ...
    attempt.Context.UEIndex==ue && attempt.StartSample==item.Context.StartSample && ...
    attempt.Context.ServingCell==state.CurrentServingIdx(ue) && ...
    attempt.Context.ConfigurationEpoch==owner.Physical.ConfigurationEpoch && ...
    attempt.Context.SampleRateHz==owner.SampleRateHz,id,'A timer cannot cross UE/cell/clock/attempt.');
[expired,expiry]=attempt.expire(item.Context.ExpirySample);
if ~expiry.Expired
    state.NRRRCSetupAttemptsByUE{ue}=expired;
    return; % Original received Setup stopped this timer, including equal-clock delivery.
end
% Validate the complete reset domain BEFORE cancelling samples or handles.
plan=sixgr.truth.prepareInitialNRMACReset(state,ue,expiry);
retirement=owner.retireInitialRRCAccess(item,attempt.MACAttemptRunIDs);
state=sixgr.truth.commitInitialNRMACReset(state,ue,expired,plan,retirement);
end
