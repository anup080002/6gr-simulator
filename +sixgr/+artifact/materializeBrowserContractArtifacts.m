function out = materializeBrowserContractArtifacts(runFolder)
%MATERIALIZEBROWSERCONTRACTARTIFACTS Run the canonical CSV raster publisher.
%
% Filesystem publication is always authoritative and precedes an optional
% MySQL mirror. The Python materializer validates primary CSV semantics
% before replacing any raster and never creates reason-card placeholders.

arguments
    runFolder {mustBeTextScalar}
end

out = struct( ...
    "Ok", false, ...
    "Status", NaN, ...
    "Identifier", "", ...
    "Message", "", ...
    "CreatedCount", 0, ...
    "MissingTableCount", NaN, ...
    "MissingChartCount", NaN, ...
    "RunID", "", ...
    "DatabaseRunID", NaN, ...
    "DatabasePersisted", false, ...
    "FilesystemPersisted", false, ...
    "PublicationBackend", "filesystem", ...
    "BrowserMaterialized", false);

repoRoot = localRepoRoot();
scriptPath = fullfile(repoRoot, "scripts", ...
    "materialize_lls_contract_artifacts.py");
if exist(scriptPath, "file") ~= 2
    out.Identifier = "materializer_script_missing";
    out.Message = [ ...
        "scripts/materialize_lls_contract_artifacts.py was not found " ...
        "in the repo root."];
    return;
end

databaseBackendActive = sixgr.db.isArtifactStoreActive();
pythonRuntime = sixgr.lls6g.runners.resolveWebGUIContractPython( ...
    "RequireMySQL", false);
if ~logical(sixgr.util.structGet(pythonRuntime, "Ok", false))
    out.Identifier = "webgui_contract_python_unavailable";
    out.Message = char(string(sixgr.util.structGet(pythonRuntime, ...
        "Message", "A WebGUI Python runtime was not found.")));
    return;
end

pythonExe = char(string(pythonRuntime.Executable));
runFolder = char(string(runFolder));
if exist(runFolder, "dir") ~= 7
    out.Identifier = "filesystem_run_folder_missing";
    out.Message = [ ...
        "Filesystem browser-contract verification requires the active " ...
        "run folder."];
    return;
end

filesystemCmd = sprintf( ...
    '"%s" "%s" --run-folder "%s" --strict --replace-existing-rasters-from-csv', ...
    localShellEscapeArg(pythonExe), localShellEscapeArg(scriptPath), ...
    localShellEscapeArg(runFolder));
filesystemResult = localExecuteMaterializerCommand(filesystemCmd);
out.Status = double(filesystemResult.Status);
out.CreatedCount = double(filesystemResult.CreatedCount);
out.MissingTableCount = double(filesystemResult.MissingTableCount);
out.MissingChartCount = double(filesystemResult.MissingChartCount);
out.Message = char(filesystemResult.PayloadText);
if filesystemResult.Status ~= 0
    out.Identifier = "browser_contract_materialization_failed";
    return;
end
out.FilesystemPersisted = true;

filesystemComplete = localMaterializationCoverageComplete(filesystemResult);
if ~databaseBackendActive
    out.Ok = true;
    out.PublicationBackend = "filesystem";
    out.BrowserMaterialized = filesystemComplete;
    out.Identifier = "filesystem_browser_contract_verification_ok";
    return;
end

mysqlPython = sixgr.lls6g.runners.resolveWebGUIContractPython( ...
    "RequireMySQL", true);
if ~logical(sixgr.util.structGet(mysqlPython, "Ok", false))
    out.Identifier = "mysql_web_contract_python_unavailable";
    out.Message = char(string(sixgr.util.structGet(mysqlPython, ...
        "Message", [ ...
        "The filesystem contract passed, but the MySQL publication " ...
        "runtime is unavailable."])));
    return;
end
storeState = sixgr.db.artifactStore("get_state");
runID = double(sixgr.util.structGet(storeState, "RunID", NaN));
if ~(isfinite(runID) && runID > 0)
    out.Identifier = "run_id_unavailable";
    out.Message = [ ...
        "The filesystem contract passed, but the active MySQL artifact " ...
        "store did not expose a valid run_id."];
    return;
end
out.DatabaseRunID = double(runID);
out.PublicationBackend = "mysql_web";
databaseCmd = sprintf('"%s" "%s" --run-id %d --strict', ...
    localShellEscapeArg(string(mysqlPython.Executable)), ...
    localShellEscapeArg(scriptPath), round(runID));
databaseResult = localExecuteMaterializerCommand(databaseCmd);
out.Status = double(databaseResult.Status);
out.CreatedCount = out.CreatedCount + double(databaseResult.CreatedCount);
out.MissingTableCount = double(databaseResult.MissingTableCount);
out.MissingChartCount = double(databaseResult.MissingChartCount);
out.Message = char("filesystem=" + filesystemResult.PayloadText + ...
    newline + "mysql=" + databaseResult.PayloadText);
if databaseResult.Status ~= 0
    out.Identifier = "mysql_browser_contract_materialization_failed";
    return;
end
out.DatabasePersisted = true;
out.Ok = true;
out.BrowserMaterialized = filesystemComplete && ...
    localMaterializationCoverageComplete(databaseResult);
out.Identifier = "browser_contract_materialization_ok";
end

function result = localExecuteMaterializerCommand(cmd)
[status, raw] = system(cmd);
payloadText = strtrim(string(raw));
result = struct( ...
    "Status", double(status), ...
    "CreatedCount", 0, ...
    "MissingTableCount", NaN, ...
    "MissingChartCount", NaN, ...
    "PayloadText", payloadText);
jsonStart = strfind(char(payloadText), "{");
if isempty(jsonStart)
    return;
end
jsonText = extractAfter(payloadText, jsonStart(1) - 1);
try
    payload = jsondecode(char(jsonText));
    result.CreatedCount = double(sixgr.util.structGet( ...
        payload, "created_count", 0));
    result.MissingTableCount = double(sixgr.util.structGet( ...
        payload, "tables_missing", NaN));
    result.MissingChartCount = double(sixgr.util.structGet( ...
        payload, "charts_missing", NaN));
    result.PayloadText = jsonText;
catch
    % Preserve raw output. An unparsable response cannot satisfy the
    % BrowserMaterialized completeness flag even when the process exits 0.
end
end

function tf = localMaterializationCoverageComplete(result)
tf = isfinite(double(result.MissingTableCount)) && ...
    double(result.MissingTableCount) == 0 && ...
    isfinite(double(result.MissingChartCount)) && ...
    double(result.MissingChartCount) == 0;
end

function out = localShellEscapeArg(value)
out = strrep(char(string(value)), '"', '""');
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:artifact:materializeBrowserContractArtifacts:BadRunFolder", ...
        "runFolder must be a character vector or string scalar.");
end
end
