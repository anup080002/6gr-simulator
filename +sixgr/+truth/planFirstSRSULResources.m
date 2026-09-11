function [keep,decisions] = planFirstSRSULResources(plan,cfg,userCfg,grants)
% Resolve authored first-SRS priority before emitting an UL scheduling DCI.
% All outputs are allocation/decision evidence, never transmitted RS rows.
keep = true(numel(grants),1);
decisions = table();
if isempty(grants) || ~logical(sixgr.util.structGet(cfg,"phy.srs.enable",false)) || ...
        string(cfg.phy.srs.puschCollisionPolicy)~="prioritize_srs_until_first_valid_measurement"
    return;
end
assert(string(sixgr.util.structGet(plan,"RuntimeViewMode",""))=="future_ul_grant_planning", ...
    'sixgr:truth:MissingSRSResourcePlanningView','Use the decision-time future UL resource view.');
slot = double(plan.CurrentSlot);
knowledge = double(plan.PlanningDecisionSlot);
if ~plan.CurrentSlotULAllowed || numel(userCfg)~=plan.NumUsers
    error("sixgr:truth:InvalidSRSResourcePlanningContext", ...
        "SRS planning requires a legal UL calendar and every UE configuration.");
end
for gi=1:numel(grants)
    if sixgr.truth.puschHasCommittedControlOrUCI(plan,grants(gi))
        error("sixgr:truth:SRSReservationAfterULCommit", ...
            "First-SRS allocation must precede DCI and UCI commitment.");
    end
    if ~isequal(sixgr.truth.runtimeULGrantSlot(grants(gi)),slot)
        error("sixgr:truth:SRSPUSCHCollisionSlotMismatch","Plan only grants for this UL occasion.");
    end
end
plannedSRS = 0;
for ue=1:plan.NumUsers
    cfgU=userCfg{ue};
    if ~sixgr.truth.coupledSRSAttemptDue(plan,cfgU,slot,ue), continue; end
    if plannedSRS>=cfg.phy.srs.maxUEsPerSlot, break; end
    lastSuccess = plan.LastSuccessfulSRSSlotByUE(ue);
    if isfinite(lastSuccess)
        if lastSuccess>knowledge
            error("sixgr:truth:NoncausalSRSMeasurementHistory", ...
                "A future SRS success cannot decide an earlier UL allocation.");
        end
    end
    % Do not reserve SRS against already-due standalone PUCCH. Moving a
    % collision earlier does not give SRS authority to discard HARQ/CSI.
    pucchConflict=false;
    T=sixgr.util.structGet(plan,"PUCCHGrantTraceTable",table());
    if istable(T) && ~isempty(T)
        due=double(T.ScheduledAbsoluteSlot)==slot & ~logical(T.GrantExecutedFlag);
        for name=["RightCensored","CanceledAtSweepBoundary","MultiplexedOnPUSCH"]
            if ismember(name,string(T.Properties.VariableNames)), due=due & ~logical(T.(name)); end
        end
        for ri=reshape(find(due),1,[])
            check=sixgr.phy.frame.resolveSRSPUCCHCollision(cfgU,T(ri,:),slot,ue);
            pucchConflict=pucchConflict || check.Collision;
        end
    end
    if isfinite(lastSuccess)
        % A previously measured UE's SRS is deferred behind data, just as
        % at execution. A blocked SRS must not consume the per-slot budget
        % and starve a later UE that still needs its first measurement.
        puschConflict=false;
        for gi=reshape(find(keep),1,[])
            check=sixgr.phy.frame.resolveSRSPUSCHCollision(cfgU,grants(gi),slot,ue);
            puschConflict=puschConflict || check.Collision;
        end
        if ~pucchConflict && ~puschConflict, plannedSRS=plannedSRS+1; end
        continue;
    end
    for gi=reshape(find(keep),1,[])
        row=sixgr.phy.frame.resolveSRSPUSCHCollision(cfgU,grants(gi),slot,ue);
        row.CollisionPair="SRS_PUSCH";
        row.GrantOrdinal=double(gi);
        row.ControlSlot=knowledge;
        row.DecisionStage="before_ul_dci_transmission";
        row.SchedulingKnowledgeSlot=knowledge;
        row.ValueSource="sixgr.truth.planFirstSRSULResources:configured_resource_allocation";
        row.ValueDefinition="Pre-DCI allocation decision, not an observed SRS/PUSCH transmission.";
        row.PUSCHGrantCancelled=false;
        row.PUSCHCandidateDeferred=row.Collision && ~pucchConflict;
        row.SRSPUCCHConflictKnownAtDecision=pucchConflict;
        row.RuntimePriorityReason="";
        if row.PUSCHCandidateDeferred
            row.Action="defer_pusch_candidate_reserve_first_srs_before_dci";
            row.Status="PRE_DCI_RESOURCE_RESERVATION";
            row.RuntimePriorityReason="first_valid_srs_measurement_missing";
            keep(gi)=false;
        elseif row.Collision && pucchConflict
            row.Action="preserve_pusch_candidate_srs_blocked_by_due_pucch";
            row.Status="PRE_DCI_PUCCH_PRIORITY";
            row.RuntimePriorityReason="due_pucch_prevents_first_srs_reservation";
        end
        row.OverlapCoordinates0Based=string(mat2str(row.OverlapCoordinates0Based));
        if isempty(decisions), decisions=struct2table(row,'AsArray',true);
        else, decisions=[decisions;struct2table(row,'AsArray',true)]; end %#ok<AGROW>
    end
    if ~pucchConflict, plannedSRS=plannedSRS+1; end
end
end
