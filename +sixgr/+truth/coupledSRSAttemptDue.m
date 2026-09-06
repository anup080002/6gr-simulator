function due = coupledSRSAttemptDue(state,cfg,slotIdx,ueIdx)
% Shared SRS eligibility for current execution and causal future planning.
due = false;
if ~logical(sixgr.util.structGet(cfg,"phy.srs.enable",false)), return; end
knowledge = double(sixgr.util.structGet(state,"PlanningDecisionSlot",state.CurrentSlot));
if slotIdx~=state.CurrentSlot || knowledge>slotIdx
    error("sixgr:truth:InvalidSRSPlanningClock", ...
        "Bind the requested resource calendar without advancing decision knowledge.");
end
period = double(state.SRSSlotPeriod);
validateattributes(period,{'numeric'},{'real','scalar','finite','integer','positive'});
lastAttempt = state.LastSRSSlotByUE(ueIdx);
if isfinite(lastAttempt) && lastAttempt>knowledge
    error("sixgr:truth:NoncausalSRSAttemptHistory", ...
        "An SRS attempt after the decision slot is not available to its planner.");
end
due = ~isfinite(lastAttempt) || lastAttempt==0 || slotIdx-lastAttempt>=period;
if logical(sixgr.util.structGet(state.ControlGating,"SRSRequired",false))
    lastAccess = state.LastSuccessfulPRACHSlotByUE(ueIdx);
    due = due && state.AccessState(ueIdx)=="succeeded" && ...
        isfinite(lastAccess) && lastAccess<=knowledge && slotIdx>lastAccess;
end
due = due && sixgr.truth.coupledSRSResourceOpportunity(cfg,slotIdx,ueIdx, ...
    state.NumUsers,period,cfg.phy.srs.schedulingPolicy,cfg.phy.srs.maxUEsPerSlot);
end
