function policy = resolveStrictControlEvidencePolicy(scfg, cfg)
%RESOLVESTRICTCONTROLEVIDENCEPOLICY Decide strict control evidence gates.
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
puschUCITargeted = any(targetCases == "pusch_uci");

pdcchObjective = any(objectives == "pdcch_strict_validation");
pucchObjective = any(objectives == "pucch_strict_validation");
puschUCIObjective = any(objectives == "pusch_uci_strict_validation");
pdcchRequired = localPDCCHRequired(scfg, cfg);
pucchRequired = localPUCCHRequired(scfg, cfg);
puschUCIRequired = localPUSCHUCIRequired(scfg, cfg);

pdcchEnabled = logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false));
pucchEnabled = logical(sixgr.util.structGet(cfg, "phy.pucch.enable", false));
puschEnabled = logical(sixgr.util.structGet(cfg, "phy.pusch.enable", true));
uciOnPUSCHEnabled = localAnyTruthy(scfg, cfg, [
    "pucch_resources.overlap_policy.uci_on_pusch_enabled"
    "phy.pucch.uciOnPUSCHEnabled"
    "phy.pucch.uci_on_pusch_enabled"
    ]);

policy = struct();
policy.TargetCases = targetCases(:);
policy.ValidationObjectives = objectives(:);
policy.PDCCHRequired = logical(pdcchRequired);
policy.PUCCHRequired = logical(pucchRequired);
policy.PUSCHUCIRequired = logical(puschUCIRequired);
policy.UCIOnPUSCHEnabled = logical(uciOnPUSCHEnabled);
policy.EnablePDCCH = pdcchEnabled && (pdcchTargeted || pdcchObjective || pdcchRequired);
% An explicit PUSCH-UCI requirement supersedes a broad control target for
% standalone PUCCH. Requiring both remains possible by setting both YAML
% gates true.
policy.EnablePUCCH = pucchEnabled && (pucchRequired || ...
    ((pucchTargeted || pucchObjective) && ~puschUCIRequired));
policy.EnablePUSCHUCI = puschEnabled && uciOnPUSCHEnabled && ...
    (puschUCITargeted || puschUCIObjective || puschUCIRequired);
policy.ShouldRun = logical(policy.EnablePDCCH || policy.EnablePUCCH || policy.EnablePUSCHUCI);

reasons = strings(0, 1);
if logical(policy.EnablePDCCH)
    reasons(end+1, 1) = "pdcch_target_objective_or_required"; %#ok<AGROW>
end
if logical(policy.EnablePUCCH)
    reasons(end+1, 1) = "pucch_target_objective_or_required"; %#ok<AGROW>
end
if logical(policy.EnablePUSCHUCI)
    reasons(end+1, 1) = "pusch_uci_target_objective_or_required"; %#ok<AGROW>
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

function tf = localPUSCHUCIRequired(scfg, cfg)
tf = localAnyTruthy(scfg, cfg, [
    "run.controlGating.puschUCIRequired"
    "control_gating.pusch_uci_required"
    "control_gating.puschUCIRequired"
    "control.pusch_uci_required"
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
