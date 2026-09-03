function [cfgOut, grantOut, evidence] = bindScheduledGrantPowerBudget(cfg, direction, grant, scheduledGrants)
%BINDSCHEDULEDGRANTPOWERBUDGET Bind a grant to its physical transmitter budget.
%
% A configured gNB transmit power is a cell-transmitter budget, not a
% per-UE grant budget.  Concurrent DL grants from the same cell and slot
% therefore share that budget.  UL grants originate at independent UEs and
% retain their per-UE power-control budgets.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2
    direction = "DL";
end
if nargin < 3 || ~isstruct(grant)
    grant = struct();
end
if nargin < 4 || ~isstruct(scheduledGrants)
    scheduledGrants = grant;
end

cfgOut = cfg;
grantOut = grant;
direction = upper(strtrim(string(direction)));
if direction ~= "UL"
    direction = "DL";
end

base = sixgr.rf.PowerContext(cfg, direction, "NumPorts", ...
    localPositiveInteger(sixgr.util.structGet(grant, "NumLogicalPorts", ...
    sixgr.util.structGet(grant, "NumLayers", 1)), 1));
evidence = struct( ...
    "ContractVersion", "sixgr.rf.ScheduledGrantPowerBudget/v1", ...
    "Direction", char(direction), ...
    "ServingCell", double(sixgr.util.structGet(grant, "ServingCell", NaN)), ...
    "Frame", double(sixgr.util.structGet(grant, "Frame", NaN)), ...
    "Slot", double(sixgr.util.structGet(grant, "Slot", NaN)), ...
    "CellTotalTxPower_dBm", NaN, ...
    "EndpointPowerBudget_dBm", double(base.TotalTxPower_dBm), ...
    "ConcurrentTransmitterGrantCount", 1, ...
    "GrantPowerFraction", 1, ...
    "GrantTargetTxPower_dBm", double(base.TotalTxPower_dBm), ...
    "Policy", "per_transmitter_full_budget", ...
    "Authority", "configured_endpoint_power_budget", ...
    "SharedCellBudgetApplied", false);

if direction == "DL"
    evidence.CellTotalTxPower_dBm = double(base.TotalTxPower_dBm);
    matching = localMatchingCellOccasionGrants(scheduledGrants, grant);
    nConcurrent = nnz(matching);
    if nConcurrent < 1
        error("sixgr:rf:ScheduledGrantMissingFromPowerOccasion", ...
            "The DL grant is absent from its scheduled cell/slot power occasion.");
    end
    policy = localResolveDLPolicy(cfg);
    switch policy
        case {"equal", "equal_total_power_per_scheduled_ue", ...
                "equal_per_layer_unit_total_power"}
            fraction = 1 / double(nConcurrent);
            authority = "scheduler_same_cell_same_slot_equal_share";
        otherwise
            error("sixgr:rf:UnsupportedDLScheduledPowerPolicy", ...
                "Unsupported PDSCH power_allocation_policy '%s'.", char(policy));
    end
    evidence.ConcurrentTransmitterGrantCount = double(nConcurrent);
    evidence.GrantPowerFraction = double(fraction);
    evidence.GrantTargetTxPower_dBm = double(base.TotalTxPower_dBm) + 10 * log10(fraction);
    evidence.Policy = char(policy);
    evidence.Authority = char(authority);
    evidence.SharedCellBudgetApplied = nConcurrent > 1;
end

cfgOut = sixgr.util.structSet(cfgOut, "lls6g.runtimeScheduledPowerContext", evidence);
grantOut.ScheduledPowerContractVersion = char(evidence.ContractVersion);
grantOut.ScheduledPowerPolicy = char(evidence.Policy);
grantOut.ScheduledPowerAuthority = char(evidence.Authority);
grantOut.CellTotalTxPower_dBm = double(evidence.CellTotalTxPower_dBm);
grantOut.EndpointPowerBudget_dBm = double(evidence.EndpointPowerBudget_dBm);
grantOut.ConcurrentTransmitterGrantCount = double(evidence.ConcurrentTransmitterGrantCount);
grantOut.GrantPowerFraction = double(evidence.GrantPowerFraction);
grantOut.GrantTargetTxPower_dBm = double(evidence.GrantTargetTxPower_dBm);
grantOut.SharedCellBudgetApplied = logical(evidence.SharedCellBudgetApplied);
end

function matching = localMatchingCellOccasionGrants(grants, reference)
matching = false(numel(grants), 1);
cellId = double(sixgr.util.structGet(reference, "ServingCell", NaN));
frame = double(sixgr.util.structGet(reference, "Frame", NaN));
slot = double(sixgr.util.structGet(reference, "Slot", NaN));
for i = 1:numel(grants)
    candidate = grants(i);
    candidateDirection = upper(strtrim(string(sixgr.util.structGet(candidate, ...
        "Direction", sixgr.util.structGet(candidate, "SignalType", "DL")))));
    isDL = candidateDirection == "DL" || candidateDirection == "PDSCH";
    matching(i) = isDL && ...
        localEqualFiniteOrMissing(double(sixgr.util.structGet(candidate, "ServingCell", NaN)), cellId) && ...
        localEqualFiniteOrMissing(double(sixgr.util.structGet(candidate, "Frame", NaN)), frame) && ...
        localEqualFiniteOrMissing(double(sixgr.util.structGet(candidate, "Slot", NaN)), slot);
end
end

function tf = localEqualFiniteOrMissing(a, b)
if isfinite(a) && isfinite(b)
    tf = a == b;
else
    tf = ~isfinite(a) && ~isfinite(b);
end
end

function policy = localResolveDLPolicy(cfg)
policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.pdsch.powerAllocationPolicy", ...
    sixgr.util.structGet(cfg, "lls6g.resolvedConfig.pdsch.power_allocation_policy", "")))));
if strlength(policy) == 0
    error("sixgr:rf:MissingDLScheduledPowerPolicy", ...
        "Concurrent DL scheduling requires pdsch.power_allocation_policy authority.");
end
end

function value = localPositiveInteger(raw, fallback)
raw = double(raw);
if isscalar(raw) && isfinite(raw) && raw >= 1
    value = max(1, round(raw));
else
    value = max(1, round(double(fallback)));
end
end
