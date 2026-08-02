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
        status.StatusNotes = localJoinStatusNotes( ...
            sixgr.util.structGet(status, "StatusNotes", ""), ...
            "Strict MIMO configured/effective evidence is required but " + ...
            "the persisted summary is missing.");
    end
    return;
end

status.ConfiguredEffectiveSupplementalEvaluated = true;
requiredColumns = ["Direction","ScenarioObjectivePass"];
schemaOk = all(ismember(requiredColumns, ...
    string(mimoT.Properties.VariableNames)));
directionsOk = schemaOk && all(ismember(["DL","UL"], ...
    upper(string(mimoT.Direction))));
rowsOk = schemaOk && all(localLogicalColumn( ...
    mimoT.ScenarioObjectivePass));
mimoOk = schemaOk && directionsOk && rowsOk;
status.ConfiguredEffectiveOk = logical(sixgr.util.structGet(status, ...
    "ConfiguredEffectiveOk", false)) && logical(mimoOk);
if ~mimoOk
    status.StatusNotes = localJoinStatusNotes( ...
        sixgr.util.structGet(status, "StatusNotes", ""), ...
        "Persisted MIMO configured/effective evidence failed or is " + ...
        "incomplete; recovery cannot promote it to success.");
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

function notes = localJoinStatusNotes(existing, addition)
existing = string(existing);
addition = string(addition);
parts = strtrim([existing(:); addition(:)]);
parts = unique(parts(strlength(parts) > 0), "stable");
notes = strjoin(parts, " | ");
end
