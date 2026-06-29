function policy = resolveStrictSupplementalEvidencePolicy(scfg, cfg)
%RESOLVESTRICTSUPPLEMENTALEVIDENCEPOLICY Decide strict supplemental evidence.
% Keep this file ASCII-only. The policy is intentionally conservative: it
% enables only real artifact producers required by the resolved scenario.

targetCases = localStringVector(localScenarioGet(scfg, "scenario.target_cases", strings(0, 1)));
targetCases = lower(strtrim(targetCases));
targetCases = targetCases(strlength(targetCases) > 0);

objectives = localStringVector(sixgr.util.structGet(cfg, "validation.objectives", strings(0, 1)));
objectives = lower(strtrim(objectives));
objectives = objectives(strlength(objectives) > 0);

sib1Targets = ["sib1", "pbch", "ssb", "cell_search", "initial_access", "broadcast"];
sib1Objectives = ["cell_search_mib_sib1", "sib1_strict_validation", ...
    "pbch_strict_validation", "initial_access_strict_validation"];

sib1Enabled = logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.pbch.enable", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false));
sib1Required = localSIB1Required(scfg, cfg);
sib1Targeted = any(ismember(targetCases, sib1Targets));
sib1Objective = any(ismember(objectives, sib1Objectives));

policy = struct();
policy.TargetCases = targetCases(:);
policy.ValidationObjectives = objectives(:);
policy.SIB1Required = logical(sib1Required);
policy.EnableSIB1 = sib1Enabled && (sib1Targeted || sib1Objective || sib1Required);

reasons = strings(0, 1);
if logical(policy.EnableSIB1)
    reasons(end+1, 1) = "sib1_target_objective_or_required"; %#ok<AGROW>
end
policy.Reasons = reasons;
policy.ShouldRun = logical(policy.EnableSIB1);
end

function tf = localSIB1Required(scfg, cfg)
tf = localAnyTruthy(scfg, cfg, [
    "run.controlGating.pbchRequired"
    "control_gating.pbch_required"
    "control_gating.pbchRequired"
    "validation.sib1_and_initial_access.sib1_required"
    "validation.sib1_and_initial_access.cell_search_required"
    "validation.sib1_and_initial_access.sib1_decode_from_waveform_required"
    "validation.sib1_and_initial_access.type0_pdcch_css_required"
    "sib1_and_initial_access.sib1_required"
    "sib1_and_initial_access.cell_search_required"
    "sib1_and_initial_access.sib1_decode_from_waveform_required"
    "sib1_and_initial_access.type0_pdcch_css_required"
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
