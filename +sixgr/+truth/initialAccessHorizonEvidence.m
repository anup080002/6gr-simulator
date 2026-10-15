function T=initialAccessHorizonEvidence(state,terminalSlot,reason)
%INITIALACCESSHORIZONEVIDENCE Snapshot actual access state, not a PHY trial.
% The experiment boundary is NOT a MAC timer or an attachment deadline.
% Leave receivers, timers, retries and eligibility unchanged. In particular,
% a failed attempt followed by a pending retry is not a terminal RA failure.
T=table();
requirePBCH=logical(sixgr.util.structGet(state,'ControlGating.PBCHRequired',false));
requireRA=logical(sixgr.util.structGet(state,'ControlGating.PRACHRequired',false));
if ~requirePBCH && ~requireRA, return; end
validateattributes(terminalSlot,{'numeric'},{'scalar','integer','nonnegative','finite'});
access=string(state.AccessState(:));
acquisition=string(state.CellAcquisitionState(:));
assert(numel(access)==numel(acquisition),'sixgr:truth:AccessHorizonIdentity', ...
    'Each UE must retain its actual acquisition and access state.');
rows=cell(numel(access),1);
for ue=1:numel(access)
    retry=localCell(state,'RARetryByUE',ue);
    attempt=localCell(state,'PendingRAAttempts',ue);
    retryStatus="not_started"; counter=NaN; limit=NaN;
    expiry=NaN; earliest=NaN; nextStage=""; runId="";
    if ~isempty(retry)
        assert(isa(retry,'sixgr.mac.ra.RARetryState'), ...
            'sixgr:truth:AccessHorizonRetryAuthority','Use the actual UE retry owner.');
        retryStatus=retry.Status; counter=retry.TransmissionCounter;
        limit=retry.PreambleTransMax; runId=retry.RunId;
        if retryStatus=="waiting_rar", expiry=double(retry.ResponseExpiryTicks); end
        if retryStatus=="ready", earliest=double(retry.EarliestNextAttemptTicks); end
    end
    if ~isempty(attempt)
        cp=attempt.Continuation;
        validateattributes(cp.NextStage,{'numeric'},{'scalar','integer','>=',1,'<=',5});
        names=["Msg1","Msg2","Msg3","Msg4","RRCSetupComplete"];
        nextStage=names(cp.NextStage);
        if isfield(cp,'ContentionReceiver') && ...
                isa(cp.ContentionReceiver,'sixgr.phy.ra.Msg4ReceiveWindow') && ...
                any(cp.ContentionReceiver.MAC.Status==["armed","waiting"])
            expiry=double(cp.ContentionReceiver.MAC.ExpiryTicksExclusive);
        end
    elseif requirePBCH && acquisition(ue)~="acquired"
        nextStage="SSB_PBCH_SIB1_reception";
    elseif requireRA && access(ue)~="succeeded"
        nextStage="eligible_PRACH_occasion_after_backoff";
    end
    completed=(~requirePBCH || acquisition(ue)=="acquired") && ...
        (~requireRA || access(ue)=="succeeded");
    exhausted=retryStatus=="exhausted";
    % Legacy single-attempt paths have no retry owner. Preserve their real
    % terminal failure rather than relabelling it as a censored success.
    terminalFailure=exhausted || (requireRA && access(ue)=="failed" && ...
        (isempty(retry) || retryStatus=="completed"));
    censored=~completed && ~terminalFailure;
    status="RIGHT_CENSORED";
    if completed, status="COMPLETED"; nextStage="";
    elseif terminalFailure, status="FAILED_PROCEDURE"; nextStage=""; end
    rows{ue}=table(ue,terminalSlot,acquisition(ue),access(ue),retryStatus, ...
        counter,limit,runId,nextStage,expiry,earliest,completed,exhausted,censored,status, ...
        string(reason),"actual_runtime_access_state_at_finite_horizon",false,false, ...
        'VariableNames',{'UEIndex','TerminalRuntimeSlot1Based','CellAcquisitionState', ...
        'AccessState','RetryState','PreambleTransmissionCounter','PreambleTransMax', ...
        'AttemptRunId','PendingProcedureStage','PendingTimerExpiryTicks', ...
        'EarliestRetryTicks','AccessCompleted','RetryLimitExhausted','RightCensored', ...
        'Status','BoundaryReason','Source','ProxyUsed','FallbackUsed'});
end
if ~isempty(rows), T=vertcat(rows{:}); end
end

function value=localCell(state,name,index)
value=[];
if isfield(state,name) && numel(state.(name))>=index
    value=state.(name){index};
end
end
