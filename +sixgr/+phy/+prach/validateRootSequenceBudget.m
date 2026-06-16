function T = validateRootSequenceBudget(runId, configHash, prachCfg)
%VALIDATEROOTSEQUENCEBUDGET Validate root/preamble budget for strict PRACH.

lra = double(sixgr.util.structGet(prachCfg, "ToolboxPRACH.LRA", NaN));
if ~isfinite(lra)
    try
        lra = double(prachCfg.ToolboxPRACH.LRA);
    catch
        lra = NaN;
    end
end
ncs = NaN;
failureReason = "";
try
    ncs = sixgr.phy.prach.deriveNCSFromZeroCorrelationZone( ...
        prachCfg.ZeroCorrelationZone, prachCfg.RestrictedSet, lra);
catch ME
    failureReason = string(ME.identifier);
end
if isfinite(ncs) && ncs > 0
    perRoot = max(1, floor(double(lra) / double(ncs)));
else
    perRoot = 1;
end
requested = min(64, max(1, round(double(sixgr.util.structGet(prachCfg, "NumPreambles", 64)))));
additionalRoots = max(0, ceil(double(requested) / max(double(perRoot), 1)) - 1);
maxRoot = localMaxRootIndex(lra);
budgetOk = isfinite(lra) && isfinite(ncs) && (double(prachCfg.SequenceIndex) + additionalRoots) <= maxRoot;
if ~budgetOk && strlength(failureReason) == 0
    failureReason = "root_sequence_budget_exhausted";
end

T = table( ...
    string(runId), ...
    string(configHash), ...
    double(prachCfg.SequenceIndex), ...
    double(sixgr.util.structGet(prachCfg, "LogicalRootSequenceIndex", prachCfg.SequenceIndex)), ...
    string(prachCfg.RestrictedSet), ...
    double(prachCfg.ZeroCorrelationZone), ...
    double(requested), ...
    double(perRoot), ...
    double(additionalRoots), ...
    logical(budgetOk), ...
    string(failureReason), ...
    'VariableNames', {'RunId','ConfigHash','RootSequenceIndex','LogicalRootSequenceIndex', ...
    'RestrictedSet','ZeroCorrelationZoneConfig','NumPreamblesRequested', ...
    'NumPreamblesAvailable','AdditionalRootSequencesNeeded','BudgetOk','FailureReason'});
end

function maxRoot = localMaxRootIndex(lra)
if round(double(lra)) == 839
    maxRoot = 837;
elseif round(double(lra)) == 139
    maxRoot = 137;
else
    maxRoot = max(0, round(double(lra)) - 2);
end
end
