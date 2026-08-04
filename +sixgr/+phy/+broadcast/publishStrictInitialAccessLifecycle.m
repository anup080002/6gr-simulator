function artifacts = publishStrictInitialAccessLifecycle(runFolder, strictLifecycle)
%PUBLISHSTRICTINITIALACCESSLIFECYCLE Publish strict-anchor lifecycle safely.
%
% The strict mini-anchor lifecycle is a validation-stage summary.  It must
% not overwrite the canonical per-UE runtime event lifecycle consumed by
% access-delay and control-plane reporting.

arguments
    runFolder {mustBeTextScalar}
    strictLifecycle table
end

layout = sixgr.report.resultLayout(char(string(runFolder)));
sixgr.util.ensureFolder(layout.ControlCSVDir);
strictPath = fullfile(layout.ControlCSVDir, ...
    "strict_initial_access_validation_lifecycle.csv");
sixgr.util.csvWriteTable(strictPath, strictLifecycle);

legacyPath = fullfile(layout.ControlCSVDir, ...
    "initial_access_lifecycle_trace.csv");
preservedCanonicalRuntime = false;
if exist(legacyPath, "file") == 2
    try
        existing = readtable(legacyPath, "FileType", "text", ...
            "Delimiter", ",", "ReadVariableNames", true, ...
            "VariableNamingRule", "preserve");
        preservedCanonicalRuntime = localIsCanonicalRuntimeLifecycle(existing);
    catch
        preservedCanonicalRuntime = false;
    end
end
if ~preservedCanonicalRuntime
    % Retain the historical standalone-mini-anchor path when no canonical
    % runtime lifecycle owns that namespace.
    sixgr.util.csvWriteTable(legacyPath, strictLifecycle);
end

artifacts = struct( ...
    "InitialAccessLifecycleCSV", string(legacyPath), ...
    "StrictInitialAccessValidationLifecycleCSV", string(strictPath), ...
    "InitialAccessLifecycleRows", height(strictLifecycle), ...
    "CanonicalRuntimeLifecyclePreserved", logical(preservedCanonicalRuntime));
end

function tf = localIsCanonicalRuntimeLifecycle(T)
required = ["UEIndex","EventName","Slot","Time_s"];
tf = istable(T) && ~isempty(T) && ...
    all(ismember(required, string(T.Properties.VariableNames)));
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:phy:broadcast:BadLifecycleRunFolder", ...
        "runFolder must be a character vector or scalar string.");
end
end
