function result = resolveWebGUIContractPython(varargin)
%RESOLVEWEBGUICONTRACTPYTHON Locate the complete WebGUI contract runtime.
%
% YAML parsing only needs PyYAML, whereas the browser-contract materializer
% also imports the WebGUI database layer and rasterizes every persisted
% chart to a validated PNG. Selecting the generic YAML runtime (or a
% partially provisioned WebGUI venv) can therefore fail only after a long
% MATLAB execution has completed. Probe the entire production dependency
% surface up front and return only an interpreter that can materialize the
% browser contract. Filesystem materialization deliberately does not
% require mysql.connector; database publication does.

ip = inputParser;
ip.addParameter("RequireMySQL", true, ...
    @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
ip.parse(varargin{:});
requireMySQL = logical(ip.Results.RequireMySQL);

repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
result = struct( ...
    "Ok", false, ...
    "Executable", "", ...
    "Source", "", ...
    "Attempted", strings(0, 1), ...
    "RequireMySQL", requireMySQL, ...
    "Message", localMissingRuntimeMessage(requireMySQL));

candidates = repmat(struct("Executable", "", "Source", ""), 0, 1);
candidates = localAddCandidate(candidates, getenv("SIXGR_WEBGUI_PYTHON"), ...
    "SIXGR_WEBGUI_PYTHON");
if ispc
    candidates = localAddCandidate(candidates, ...
        fullfile(repoRoot, "apps", ".webgui-venv", "Scripts", "python.exe"), ...
        "repo_webgui_venv");
else
    candidates = localAddCandidate(candidates, ...
        fullfile(repoRoot, "apps", ".webgui-venv", "bin", "python"), ...
        "repo_webgui_venv");
end
candidates = localAddCandidate(candidates, getenv("PYTHON_EXE"), ...
    "PYTHON_EXE");
try
    runtimeInfo = sixgr.lls6g.config.ensureYAMLRuntime(ConfigurePyEnv=false);
    candidates = localAddCandidate(candidates, ...
        sixgr.util.structGet(runtimeInfo, "PythonExecutable", ""), ...
        "yaml_runtime");
catch
end
if ~ispc
    candidates = localAddCandidate(candidates, "python3", "PATH_python3");
end
candidates = localAddCandidate(candidates, "python", "PATH_python");

seen = strings(0, 1);
diagnostics = strings(0, 1);
for i = 1:numel(candidates)
    executable = strtrim(string(candidates(i).Executable));
    key = lower(replace(executable, "\", "/"));
    if strlength(executable) == 0 || any(seen == key)
        continue;
    end
    seen(end + 1, 1) = key; %#ok<AGROW>
    result.Attempted(end + 1, 1) = executable; %#ok<AGROW>
    if localLooksLikePath(executable) && exist(char(executable), "file") ~= 2
        diagnostics(end + 1, 1) = executable + ":not_found"; %#ok<AGROW>
        continue;
    end
    if requireMySQL
        probe = "import mysql.connector, yaml, resvg_py; from PIL import Image";
    else
        probe = "import yaml, resvg_py; from PIL import Image";
    end
    command = sprintf('"%s" -c "%s"', ...
        localEscapeDoubleQuotedArgument(executable), char(probe));
    [status, output] = system(command);
    if status == 0
        result.Ok = true;
        result.Executable = executable;
        result.Source = string(candidates(i).Source);
        result.Message = "WebGUI contract Python runtime resolved from " + ...
            result.Source + ".";
        return;
    end
    detail = strtrim(string(output));
    if strlength(detail) > 160
        detail = extractBefore(detail, 161);
    end
    diagnostics(end + 1, 1) = executable + ":probe_exit_" + ...
        string(status) + ":" + detail; %#ok<AGROW>
end
if ~isempty(diagnostics)
    result.Message = result.Message + " Probes: " + strjoin(diagnostics, " | ");
end
end

function value = localMissingRuntimeMessage(requireMySQL)
if requireMySQL
    value = ["No Python runtime with mysql.connector, yaml, Pillow, " + ...
        "and resvg_py was found."];
else
    value = ["No Python runtime with yaml, Pillow, and resvg_py was " + ...
        "found for filesystem browser-contract materialization."];
end
end

function candidates = localAddCandidate(candidates, executable, source)
executable = strtrim(string(executable));
if strlength(executable) == 0
    return;
end
row = struct("Executable", executable, "Source", string(source));
candidates(end + 1, 1) = row;
end

function tf = localLooksLikePath(value)
value = string(value);
tf = contains(value, "/") || contains(value, "\") || ...
    (~ispc && startsWith(value, "."));
end

function value = localEscapeDoubleQuotedArgument(value)
value = char(string(value));
value = strrep(value, '"', '\"');
end
