function status = applyPersistedMIMOConfiguredEffectiveStatus(status, runFolder, cfg)
%APPLYPERSISTEDMIMOCONFIGUREDEFFECTIVESTATUS Fail closed on MIMO evidence.
% This separately testable reducer prevents recovery from promoting a
% configured/effective result when the persisted four-gate MIMO evidence is
% absent, incomplete, or failing.

arguments
    status (1,1) struct
    runFolder {mustBeTextScalar}
    cfg (1,1) struct
end

layout = sixgr.report.resultLayout(char(string(runFolder)));
mimoPath = fullfile(layout.BeamformingCSVDir, ...
    "mimo_configured_vs_effective.csv");
mimoT = localReadOptionalTable(mimoPath);
muRequested = logical(sixgr.util.structGet(cfg, ...
    "mac.scheduler.muMimoEnabled", sixgr.util.structGet(cfg, ...
    "phy.mimo.muMimoEnabled", false))) || ...
    logical(sixgr.util.structGet(cfg, ...
    "mac.scheduler.ulMuMimoEnabled", sixgr.util.structGet(cfg, ...
    "phy.mimo.ulMuMimoEnabled", false)));
rankRequested = max([double(sixgr.util.structGet(cfg, ...
    "phy.pdsch.numLayers", 1)), double(sixgr.util.structGet(cfg, ...
    "phy.pusch.numLayers", 1))]) > 1;
mimoRequired = logical(muRequested || rankRequested || ...
    sixgr.util.structGet(cfg, ...
    "phy.beamManagement.hybridBeamformingEnabled", false));

status.ConfiguredEffectiveSupplementalEvaluated = false;
status.ConfiguredEffectiveSupplementalArtifact = ...
    replace(string(mimoPath), "\", "/");
if ~(istable(mimoT) && height(mimoT) > 0)
    if mimoRequired
        status.ConfiguredEffectiveOk = false;
        status.ConfiguredEffectivePolicyOk = false;
        status.StatusNotes = localJoinStatusNotes( ...
            sixgr.util.structGet(status, "StatusNotes", ""), ...
            "Strict MIMO configured/effective evidence is required but " + ...
            "the persisted summary is missing.");
    end
    return;
end

status.ConfiguredEffectiveSupplementalEvaluated = true;
requiredColumns = ["Direction","StrictEligibleRowCount", ...
    "ExactMatchPercent","SpatialContractMatch", ...
    "FixedOperatingPointMatch","AdaptivePolicyConformance", ...
    "MUExecutionMatch","ScenarioObjectivePass"];
schemaOk = all(ismember(requiredColumns, ...
    string(mimoT.Properties.VariableNames)));
if ~schemaOk
    missingColumns = requiredColumns(~ismember(requiredColumns, ...
        string(mimoT.Properties.VariableNames)));
    status.ConfiguredEffectiveOk = false;
    status.ConfiguredEffectivePolicyOk = false;
    status.StatusNotes = localJoinStatusNotes( ...
        sixgr.util.structGet(status, "StatusNotes", ""), ...
        "Persisted MIMO configured/effective evidence uses an incomplete " + ...
        "schema; missing columns: " + strjoin(missingColumns, ",") + ".");
    return;
end
directionsOk = schemaOk && all(ismember(["DL","UL"], ...
    upper(string(mimoT.Direction))));
strictEligible = localNumericColumn(mimoT.StrictEligibleRowCount);
evidenceRowsOk = schemaOk && all(isfinite(strictEligible) & strictEligible > 0);
fixedRequired = localPolicyRequirement(mimoT, ...
    "FixedOperatingPointRequired", "AdaptiveMode", true);
adaptiveRequired = localPolicyRequirement(mimoT, ...
    "AdaptivePolicyRequired", "AdaptiveMode", false);
spatialRequired = localExplicitRequirement(mimoT, ...
    "SpatialContractRequired");
spatialPolicyOk = ~spatialRequired | ...
    localLogicalColumn(mimoT.SpatialContractMatch);
fixedPolicyOk = ~fixedRequired | localLogicalColumn(mimoT.FixedOperatingPointMatch);
adaptivePolicyOk = ~adaptiveRequired | localLogicalColumn(mimoT.AdaptivePolicyConformance);
policyRowsOk = schemaOk && evidenceRowsOk && ...
    all(spatialPolicyOk) && ...
    all(fixedPolicyOk) && all(adaptivePolicyOk) && ...
    all(localLogicalColumn(mimoT.MUExecutionMatch)) && ...
    all(localLogicalColumn(mimoT.ScenarioObjectivePass));
threshold = double(sixgr.util.structGet(cfg, ...
    "scenario.required_configured_match_rate", sixgr.util.structGet(cfg, ...
    "validation.required_configured_match_rate", 0.999)));
if ~(isscalar(threshold) && isfinite(threshold) && threshold >= 0 && threshold <= 1)
    threshold = 0.999;
end
exactRate = localNumericColumn(mimoT.ExactMatchPercent);
exactRowsOk = schemaOk && evidenceRowsOk && ...
    all(isfinite(exactRate) & exactRate + eps >= threshold);
exactOk = schemaOk && directionsOk && exactRowsOk;
policyOk = schemaOk && directionsOk && policyRowsOk;
status.ConfiguredEffectiveOk = logical(sixgr.util.structGet(status, ...
    "ConfiguredEffectiveOk", false)) && logical(exactOk);
status.ConfiguredEffectivePolicyOk = logical(sixgr.util.structGet(status, ...
    "ConfiguredEffectivePolicyOk", false)) && logical(policyOk);
if ~exactOk
    status.StatusNotes = localJoinStatusNotes( ...
        sixgr.util.structGet(status, "StatusNotes", ""), ...
        "Persisted MIMO exact configured/effective evidence failed or is " + ...
        "incomplete; recovery cannot promote exact equality to success.");
end
if ~policyOk
    status.StatusNotes = localJoinStatusNotes( ...
        sixgr.util.structGet(status, "StatusNotes", ""), ...
        "Persisted MIMO execution-policy evidence failed or is incomplete; " + ...
        "recovery cannot promote policy conformance to success.");
end
end

function T = localReadOptionalTable(pathStr)
T = table();
if exist(pathStr, "file") ~= 2
    return;
end
try
    T = readtable(pathStr, "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function values = localLogicalColumn(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    values = ismember(lower(strtrim(string(raw(:)))), ...
        ["true","1","yes","pass","ok"]);
end
end

function values = localNumericColumn(raw)
if isnumeric(raw) || islogical(raw)
    values = double(raw(:));
else
    values = str2double(string(raw(:)));
end
end

function required = localPolicyRequirement(T, explicitName, adaptiveName, fixedDefault)
names = string(T.Properties.VariableNames);
if ismember(explicitName, names)
    required = localLogicalColumn(T.(char(explicitName)));
elseif ismember(adaptiveName, names)
    adaptive = localLogicalColumn(T.(char(adaptiveName)));
    if fixedDefault
        required = ~adaptive;
    else
        required = adaptive;
    end
else
    % Legacy evidence did not distinguish policy applicability. Preserve
    % the old fail-closed requirement until the versioned schema is present.
    required = true(height(T), 1);
end
end

function required = localExplicitRequirement(T, explicitName)
names = string(T.Properties.VariableNames);
if ismember(explicitName, names)
    required = localLogicalColumn(T.(char(explicitName)));
else
    required = true(height(T), 1);
end
end

function notes = localJoinStatusNotes(existing, addition)
existing = string(existing);
addition = string(addition);
parts = strtrim([existing(:); addition(:)]);
parts = unique(parts(strlength(parts) > 0), "stable");
notes = strjoin(parts, " | ");
end
