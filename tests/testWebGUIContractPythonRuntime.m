function ok = testWebGUIContractPythonRuntime()
%TESTWEBGUICONTRACTPYTHONRUNTIME DB materialization must not use YAML-only Python.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
runtime = sixgr.lls6g.runners.resolveWebGUIContractPython();
assert(logical(runtime.Ok), ...
    "A WebGUI contract Python runtime with mysql.connector and yaml is required: %s", ...
    string(runtime.Message));
assert(strlength(string(runtime.Executable)) > 0, ...
    "The resolved WebGUI Python executable must be explicit.");
command = sprintf('"%s" -c "import mysql.connector, yaml"', ...
    strrep(char(string(runtime.Executable)), '"', '\"'));
[status, output] = system(command);
assert(status == 0, ...
    "The selected WebGUI Python runtime failed its DB-module probe: %s", ...
    string(output));

repoRoot = fileparts(fileparts(mfilename("fullpath")));
repoVenvRoot = lower(replace(string(fullfile(repoRoot, ...
    "apps", ".webgui-venv")), "\", "/"));
resolved = lower(replace(string(runtime.Executable), "\", "/"));
if exist(char(fullfile(repoRoot, "apps", ".webgui-venv")), "dir") == 7
    assert(startsWith(resolved, repoVenvRoot), ...
        "The repository WebGUI venv must take precedence over a generic YAML-only Python runtime.");
end
ok = true;
end
