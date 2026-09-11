function [state, pendingULGrants, decisionTable, collisionRemains, cancelledGrantCount] = ...
        resolveSRSPUSCHRuntimePriority(state, pendingULGrants, ...
        decisionTable, cfg, slotIdx, srsUEIndex)
%RESOLVESRSPUSCHRUNTIMEPRIORITY Apply YAML-owned causal SRS/PUSCH priority.
%
% Exact RE collision detection is performed before this function. This
% function owns only the causal decision that needs runtime measurement
% state: before a UE has one valid SRS measurement, a configured policy may
% discard exact tentative PUSCH candidates BEFORE their DCI transmission.
% An already authorized PUSCH (including its bound UCI) is not tentative.
% Due PUCCH/UCI is never cancelled here. The same decision applies in FDD
% and TDD after the duplex engine has established a legal UL occasion.

arguments
    state (1,1) struct
    pendingULGrants struct
    decisionTable table
    cfg (1,1) struct
    slotIdx (1,1) double {mustBeFinite,mustBeInteger,mustBePositive}
    srsUEIndex (1,1) double {mustBeFinite,mustBeInteger,mustBePositive}
end

collisionRemains = true;
cancelledGrantCount = 0;
if isempty(decisionTable)
    return;
end
requiredColumns = ["CollisionPair", "Collision", "Action", "Status", ...
    "GrantOrdinal"];
if ~all(ismember(requiredColumns, ...
        string(decisionTable.Properties.VariableNames)))
    error("sixgr:truth:InvalidSRSPUSCHCollisionDecisionTable", ...
        "Runtime SRS/PUSCH arbitration requires columns: %s.", ...
        char(strjoin(requiredColumns, ", ")));
end

policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.srs.puschCollisionPolicy", "preserve_pusch_defer_srs"))));
allowedPolicies = ["preserve_pusch_defer_srs", ...
    "prioritize_srs_until_first_valid_measurement"];
if ~isscalar(policy) || ~any(policy == allowedPolicies)
    error("sixgr:truth:InvalidSRSPUSCHCollisionPolicy", ...
        "Unsupported SRS/PUSCH runtime collision policy '%s'.", ...
        char(policy));
end

pair = string(decisionTable.CollisionPair);
collisionMask = logical(decisionTable.Collision);
pucchCollision = any(collisionMask & pair == "SRS_PUCCH");
puschCollisionMask = collisionMask & pair == "SRS_PUSCH";
lastSuccessfulSRS = double(sixgr.util.structGet( ...
    state, "LastSuccessfulSRSSlotByUE", nan(0, 1)));
firstMeasurementMissing = srsUEIndex > numel(lastSuccessfulSRS) || ...
    ~isfinite(lastSuccessfulSRS(srsUEIndex));

decisionTable.PUSCHGrantCancelled = false(height(decisionTable), 1);
decisionTable.RuntimePriorityReason = repmat("", height(decisionTable), 1);

if policy ~= "prioritize_srs_until_first_valid_measurement"
    decisionTable.RuntimePriorityReason(collisionMask) = ...
        "configured_policy_preserves_queued_pusch";
    return;
end
if ~firstMeasurementMissing
    decisionTable.Action(collisionMask) = ...
        "defer_srs_after_first_valid_measurement";
    decisionTable.Status(collisionMask) = ...
        "COLLISION_RESOLVED_PRESERVE_DATA";
    decisionTable.RuntimePriorityReason(collisionMask) = ...
        "first_valid_srs_measurement_already_available";
    return;
end

% PUCCH has already carried due UCI at this boundary and cannot be rolled
% back. Preserve it and defer SRS to the next configured opportunity.
if pucchCollision
    decisionTable.Action(collisionMask) = ...
        "defer_srs_preserve_due_pucch";
    decisionTable.Status(collisionMask) = ...
        "COLLISION_RESOLVED_PRESERVE_DUE_UCI";
    decisionTable.RuntimePriorityReason(collisionMask) = ...
        "due_pucch_uci_already_executed";
    return;
end
if ~any(puschCollisionMask)
    collisionRemains = false;
    return;
end

grantOrdinals = unique(double(decisionTable.GrantOrdinal(puschCollisionMask)));
if isempty(grantOrdinals) || any(~isfinite(grantOrdinals) | ...
        grantOrdinals~=fix(grantOrdinals) | grantOrdinals<1 | ...
        grantOrdinals>numel(pendingULGrants))
    error("sixgr:truth:MissingCollidingQueuedPUSCHGrant", ...
        "Exact SRS/PUSCH collision rows did not identify a queued grant; " + ...
        "the runtime cannot safely prioritize either signal.");
end

% Validate the entire decision before mutating any shared HARQ handle.
for ordinal = reshape(grantOrdinals,1,[])
    grant = pendingULGrants(ordinal);
    scheduled = sixgr.truth.runtimeULGrantSlot(grant);
    if ~isequal(double(scheduled),slotIdx)
        error("sixgr:truth:SRSPUSCHCollisionSlotMismatch", ...
            "SRS arbitration cannot cancel a grant from a different UL occasion.");
    end
    protected = sixgr.truth.puschHasCommittedControlOrUCI(state,grant);
    if protected
        decisionTable.Action(puschCollisionMask) = "defer_srs_preserve_committed_pusch";
        decisionTable.Status(puschCollisionMask) = "COLLISION_RESOLVED_PRESERVE_COMMITTED_UL";
        decisionTable.RuntimePriorityReason(puschCollisionMask) = ...
            "pusch_dci_or_uci_already_committed_requires_pre_dci_resource_planning";
        return;
    end
end

for ordinal = reshape(grantOrdinals, 1, [])
    state = sixgr.truth.CoupledTruthRuntime. ...
        cancelUnexecutedHARQGrantRuntime( ...
        state, pendingULGrants(ordinal), "UL");
end
keepMask = true(numel(pendingULGrants), 1);
keepMask(grantOrdinals) = false;
pendingULGrants = pendingULGrants(keepMask);
cancelledGrantCount = numel(grantOrdinals);
decisionTable.Action(puschCollisionMask) = ...
    "suppress_queued_pusch_execute_first_required_srs";
decisionTable.Status(puschCollisionMask) = ...
    "COLLISION_RESOLVED_SRS_MEASUREMENT_PRIORITY";
decisionTable.PUSCHGrantCancelled(puschCollisionMask) = true;
decisionTable.RuntimePriorityReason(puschCollisionMask) = ...
    "first_valid_srs_measurement_missing";
collisionRemains = false;
end
