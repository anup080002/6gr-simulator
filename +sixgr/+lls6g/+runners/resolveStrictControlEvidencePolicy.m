function policy = resolveStrictControlEvidencePolicy(scfg, cfg)
%RESOLVESTRICTCONTROLEVIDENCEPOLICY Decide strict PDCCH/PUCCH evidence gates.
% Keep this file ASCII-only.

targetCases = localStringVector(localScenarioGet(scfg, "scenario.target_cases", strings(0, 1)));
targetCases = lower(strtrim(targetCases));
targetCases = targetCases(strlength(targetCases) > 0);

objectives = localStringVector(sixgr.util.structGet(cfg, "validation.objectives", strings(0, 1)));
objectives = lower(strtrim(objectives));
objectives = objectives(strlength(objectives) > 0);

controlTargets = ["control", "control_channels"];
pdcchTargeted = any(targetCases == "pdcch") || any(ismember(targetCases, controlTargets));
pucchTargeted = any(targetCases == "pucch") || any(ismember(targetCases, controlTargets));

pdcchObjective = any(objectives == "pdcch_strict_validation");
pucchObjective = any(objectives == "pucch_strict_validation");
pdcchRequired = localPDCCHRequired(scfg, cfg);
pucchRequired = localPUCCHRequired(scfg, cfg);

pdcchEnabled = logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false));
pucchEnabled = logical(sixgr.util.structGet(cfg, "phy.pucch.enable", false));

policy = struct();
policy.TargetCases = targetCases(:);
policy.ValidationObjectives = objectives(:);
policy.PDCCHRequired = logical(pdcchRequired);
policy.PUCCHRequired = logical(pucchRequired);
policy.EnablePDCCH = pdcchEnabled && (pdcchTargeted || pdcchObjective || pdcchRequired);
policy.EnablePUCCH = pucchEnabled && (pucchTargeted || pucchObjective || pucchRequired);
policy.ShouldRun = logical(policy.EnablePDCCH || policy.EnablePUCCH);

reasons = strings(0, 1);
if logical(policy.EnablePDCCH)
    reasons(end+1, 1) = "pdcch_target_objective_or_required"; %#ok<AGROW>
end
if logical(policy.EnablePUCCH)
    reasons(end+1, 1) = "pucch_target_objective_or_required"; %#ok<AGROW>
end
policy.Reasons = reasons;
end

function tf = localPDCCHRequired(scfg, cfg)
tf = localAnyTruthy(scfg, cfg, [
    "run.controlGating.pdcchRequired"
    "control_gating.pdcch_required"
    "control_gating.pdcchRequired"
    "control.pdcch_required"
    "control.pdcchRequired"
    "sib1_and_initial_access.type0_pdcch_css_required"
    "random_access_evidence.msg2_rar_pdcch_pdsch_required"
    ]);
end

function tf = localPUCCHRequired(scfg, cfg)
tf = localAnyTruthy(scfg, cfg, [
    "run.controlGating.pucchRequired"
    "control_gating.pucch_required"
    "control_gating.pucchRequired"
    "control.pucch_required"
    "control.pucchRequired"
    ]);
end

function tf = localAnyTruthy(scfg, cfg, paths)
tf = false;
for ii = 1:numel(paths)
    path = string(paths(ii));
    if localTruthy(localScenarioGet(scfg, path, [])) || ...
            localTruthy(sixgr.util.structGet(cfg, path, []))
        tf = true;
        return;
    end
end
end

function value = localScenarioGet(scfg, path, defaultValue)
if nargin < 3
    defaultValue = [];
end
value = defaultValue;
try
    if isobject(scfg) && ismethod(scfg, "get")
        value = scfg.get(path, defaultValue);
    elseif isstruct(scfg)
        value = sixgr.util.structGet(scfg, path, defaultValue);
    end
catch
    value = defaultValue;
end
end

function tf = localTruthy(value)
if isempty(value)
    tf = false;
elseif islogical(value) || isnumeric(value)
    tf = any(logical(value(:)));
else
    tokens = lower(strtrim(string(value(:))));
    tf = any(ismember(tokens, ["true", "1", "yes", "on", "required", "enabled"]));
end
end

function values = localStringVector(raw)
if isempty(raw)
    values = strings(0, 1);
elseif iscell(raw)
    values = string(raw(:));
else
    values = string(raw(:));
end
end
