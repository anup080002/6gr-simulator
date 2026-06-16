function validation = validatePRACHConfigStrict(prachCfg)
%VALIDATEPRACHCONFIGSTRICT Validate strict PRACH config invariants.

reasons = strings(0, 1);
toolboxMissing = false;
try
    assert(~isempty(which("nrPRACHConfig")), "missing nrPRACHConfig");
    assert(~isempty(which("nrPRACH")), "missing nrPRACH");
    assert(~isempty(which("nrPRACHIndices")), "missing nrPRACHIndices");
catch ME
    toolboxMissing = true;
    reasons(end + 1, 1) = "toolbox_missing:" + string(ME.message); %#ok<AGROW>
end

if ~(isfield(prachCfg, "ToolboxPRACH") && isa(prachCfg.ToolboxPRACH, "nrPRACHConfig"))
    reasons(end + 1, 1) = "toolbox_prach_config_missing"; %#ok<AGROW>
end
if ~(isfield(prachCfg, "ToolboxCarrier") && isa(prachCfg.ToolboxCarrier, "nrCarrierConfig"))
    reasons(end + 1, 1) = "toolbox_carrier_config_missing"; %#ok<AGROW>
end

try
    sixgr.phy.prach.deriveNCSFromZeroCorrelationZone( ...
        prachCfg.ZeroCorrelationZone, prachCfg.RestrictedSet, prachCfg.ToolboxPRACH.LRA);
catch ME
    reasons(end + 1, 1) = "zcz_restricted_set_invalid:" + string(ME.identifier); %#ok<AGROW>
end

preambleIdx = round(double(prachCfg.PreambleIndex(:)));
numPreambles = round(double(sixgr.util.structGet(prachCfg, "NumPreambles", 64)));
if isempty(preambleIdx) || any(~isfinite(preambleIdx)) || any(preambleIdx < 0) || ...
        any(preambleIdx >= min(numPreambles, 64))
    reasons(end + 1, 1) = "preamble_index_out_of_range"; %#ok<AGROW>
end
if ~(isfield(prachCfg, "ConfigHash") && strlength(string(prachCfg.ConfigHash)) > 0)
    reasons(end + 1, 1) = "config_hash_missing"; %#ok<AGROW>
end

budget = sixgr.phy.prach.validateRootSequenceBudget("", "", prachCfg);
if istable(budget) && ~isempty(budget) && any(~logical(budget.BudgetOk))
    reasons(end + 1, 1) = "root_sequence_budget_invalid"; %#ok<AGROW>
end

validation = struct();
validation.StrictValid = isempty(reasons);
validation.ToolboxMissing = toolboxMissing;
validation.FailureReasons = reasons(:);
if isempty(reasons)
    validation.Status = "strict_config_valid";
else
    validation.Status = "strict_config_invalid";
end
end
