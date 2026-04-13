function info = ensureYAMLRuntime(varargin)
%ENSUREYAMLRUNTIME Detect/configure Python + PyYAML for MATLAB YAML loading.
% Keep this file ASCII-only.

p = inputParser;
p.addParameter("Verbose", false, @(x) islogical(x) && isscalar(x));
p.addParameter("RequireYAML", false, @(x) islogical(x) && isscalar(x));
p.addParameter("ConfigurePyEnv", true, @(x) islogical(x) && isscalar(x));
p.addParameter("ForceRefresh", false, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

persistent cache
if ~opt.ForceRefresh && ~isempty(cache)
    info = cache;
    if opt.Verbose
        localPrintInfo(info);
    end
    if opt.RequireYAML && ~logical(info.CanParseYAML)
        localThrowMissingYAML(info);
    end
    return;
end

info = localDefaultInfo();

[pyenvInfo, detectedExe] = localProbePyEnv(opt.ConfigurePyEnv);
info.MATLABPythonSupported = logical(pyenvInfo.MATLABPythonSupported);
info.PyenvStatus = char(string(pyenvInfo.Status));
info.PythonExecutable = char(string(pyenvInfo.Executable));
info.PythonVersion = char(string(pyenvInfo.Version));
info.PythonSource = char(string(pyenvInfo.Source));

if strlength(string(info.PythonExecutable)) == 0
    info.PythonExecutable = char(string(detectedExe));
    if strlength(string(info.PythonExecutable)) > 0
        info.PythonSource = "shell_detection";
    end
end

if strlength(string(info.PythonExecutable)) > 0
    extProbe = localProbeExternalPython(info.PythonExecutable);
    if strlength(string(info.PythonVersion)) == 0
        info.PythonVersion = char(string(extProbe.Version));
    end
    info.ExternalPythonAvailable = logical(extProbe.PythonAvailable);
    info.ExternalPyYAMLAvailable = logical(extProbe.PyYAMLAvailable);
    info.ExternalProbeMessage = char(string(extProbe.Message));
end

matlabProbe = localProbeMATLABPython(info.PythonExecutable, opt.ConfigurePyEnv);
info.MATLABPythonReady = logical(matlabProbe.PythonReady);
info.MATLABPyYAMLAvailable = logical(matlabProbe.PyYAMLAvailable);
info.MATLABProbeMessage = char(string(matlabProbe.Message));
if strlength(string(matlabProbe.Executable)) > 0
    info.PythonExecutable = char(string(matlabProbe.Executable));
end
if strlength(string(matlabProbe.Version)) > 0
    info.PythonVersion = char(string(matlabProbe.Version));
end

if info.MATLABPyYAMLAvailable
    info.LoaderBackend = "matlab_pyrun";
elseif info.ExternalPyYAMLAvailable
    info.LoaderBackend = "external_python";
else
    info.LoaderBackend = "unavailable";
end

info.CanParseYAML = info.LoaderBackend ~= "unavailable";
info.RecommendedInstallCommand = char(string(localRecommendedInstallCommand(info.PythonExecutable)));
if info.CanParseYAML
    info.Status = "ready";
else
    if strlength(string(info.PythonExecutable)) == 0
        info.Status = "python_not_found";
    else
        info.Status = "pyyaml_missing";
    end
end

cache = info;

if opt.Verbose
    localPrintInfo(info);
end
if opt.RequireYAML && ~logical(info.CanParseYAML)
    localThrowMissingYAML(info);
end
end

function info = localDefaultInfo()
info = struct( ...
    "Status", "unknown", ...
    "LoaderBackend", "unavailable", ...
    "CanParseYAML", false, ...
    "MATLABPythonSupported", false, ...
    "MATLABPythonReady", false, ...
    "MATLABPyYAMLAvailable", false, ...
    "MATLABProbeMessage", "", ...
    "ExternalPythonAvailable", false, ...
    "ExternalPyYAMLAvailable", false, ...
    "ExternalProbeMessage", "", ...
    "PyenvStatus", "", ...
    "PythonExecutable", "", ...
    "PythonVersion", "", ...
    "PythonSource", "", ...
    "RecommendedInstallCommand", "");
end

function [info, detectedExe] = localProbePyEnv(configurePyEnv)
info = struct("MATLABPythonSupported", false, "Status", "", "Executable", "", "Version", "", "Source", "");
detectedExe = "";

if ~localHasMATLABSymbol("pyenv")
    return;
end

info.MATLABPythonSupported = true;
try
    envInfo = pyenv;
    info.Status = char(string(envInfo.Status));
    info.Executable = char(string(envInfo.Executable));
    info.Version = char(string(envInfo.Version));
    info.Source = "pyenv";
catch
    return;
end

if ~configurePyEnv
    return;
end

if strlength(string(info.Executable)) == 0
    detectedExe = char(string(localDetectPythonExecutable()));
else
    detectedExe = char(string(info.Executable));
end

if strlength(string(detectedExe)) == 0
    return;
end

statusUpper = upper(strtrim(string(info.Status)));
if statusUpper == "NOTLOADED"
    try
        pyenv("Version", detectedExe);
        envInfo = pyenv;
        info.Status = char(string(envInfo.Status));
        info.Executable = char(string(envInfo.Executable));
        info.Version = char(string(envInfo.Version));
        info.Source = "pyenv_configured";
    catch
        if strlength(string(info.Executable)) == 0
            info.Executable = detectedExe;
            info.Source = "pyenv_detected_only";
        end
    end
end
end

function exe = localDetectPythonExecutable()
exe = "";
commands = { ...
    'python -c "import sys; print(sys.executable)"', ...
    'py -3.11 -c "import sys; print(sys.executable)"', ...
    'py -3 -c "import sys; print(sys.executable)"'};
for i = 1:numel(commands)
    [status, outTxt] = system(commands{i});
    if status == 0
        candidate = strtrim(string(outTxt));
        if strlength(candidate) > 0
            exe = char(candidate);
            return;
        end
    end
end
end

function probe = localProbeExternalPython(executable)
probe = struct("PythonAvailable", false, "PyYAMLAvailable", false, "Version", "", "Message", "");
if strlength(string(executable)) == 0 || exist(char(string(executable)), "file") ~= 2
    probe.Message = "python_executable_not_found";
    return;
end
script = [ ...
    "import importlib.util", newline, ...
    "import json", newline, ...
    "import sys", newline, ...
    "spec = importlib.util.find_spec('yaml')", newline, ...
    "print(json.dumps({'python_available': True, 'yaml_available': spec is not None, 'version': sys.version.split()[0], 'executable': sys.executable}))", newline];
tmpPy = localWriteTempPythonScript(script);
cleanupObj = onCleanup(@() localDeleteFile(tmpPy)); %#ok<NASGU>
cmd = sprintf('"%s" "%s"', localEscapeCmdPath(executable), localEscapeCmdPath(tmpPy));
[status, outTxt] = system(cmd);
if status ~= 0
    probe.Message = strtrim(string(outTxt));
    return;
end
try
    payload = jsondecode(outTxt);
    probe.PythonAvailable = logical(payload.python_available);
    probe.PyYAMLAvailable = logical(payload.yaml_available);
    probe.Version = char(string(payload.version));
    probe.Message = "ok";
catch ME
    probe.Message = string(ME.message);
end
end

function probe = localProbeMATLABPython(executable, configurePyEnv)
probe = struct("PythonReady", false, "PyYAMLAvailable", false, "Executable", "", "Version", "", "Message", "");
if ~localHasMATLABSymbol("pyenv") || ~localHasMATLABSymbol("pyrun")
    probe.Message = "matlab_python_unavailable";
    return;
end

try
    envInfo = pyenv;
    if configurePyEnv && strlength(string(executable)) > 0 && upper(strtrim(string(envInfo.Status))) == "NOTLOADED" && ...
            ~strcmpi(char(string(envInfo.Executable)), char(string(executable)))
        pyenv("Version", char(string(executable)));
        envInfo = pyenv;
    end
    probe.Executable = char(string(envInfo.Executable));
    probe.Version = char(string(envInfo.Version));
catch ME
    probe.Message = string(ME.message);
    return;
end

try
    [yamlOk, pyExe, pyVer] = pyrun([ ...
        "import importlib.util", newline, ...
        "import sys", newline, ...
        "yaml_ok = importlib.util.find_spec('yaml') is not None", newline, ...
        "py_exe = sys.executable", newline, ...
        "py_ver = sys.version.split()[0]", newline], ...
        ["yaml_ok","py_exe","py_ver"]);
    probe.PythonReady = true;
    probe.PyYAMLAvailable = logical(yamlOk);
    if strlength(string(probe.Executable)) == 0
        probe.Executable = char(string(pyExe));
    end
    probe.Version = char(string(pyVer));
    probe.Message = "ok";
catch ME
    probe.Message = string(ME.message);
end
end

function cmd = localRecommendedInstallCommand(executable)
if strlength(string(executable)) > 0 && exist(char(string(executable)), "file") == 2
    cmd = '"' + string(executable) + '" -m pip install pyyaml';
else
    cmd = "py -3.11 -m pip install pyyaml";
end
end

function scriptPath = localWriteTempPythonScript(script)
scriptPath = char(string(tempname) + ".py");
fid = fopen(scriptPath, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:lls6g:config:YAMLTempScriptFail", ...
        "Unable to create a temporary Python helper script.");
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", script);
end

function localDeleteFile(filePath)
if exist(filePath, "file") == 2
    delete(filePath);
end
end

function p = localEscapeCmdPath(pathStr)
p = strrep(char(string(pathStr)), '"', '""');
end

function localPrintInfo(info)
backend = char(string(info.LoaderBackend));
exe = char(string(info.PythonExecutable));
ver = char(string(info.PythonVersion));
status = char(string(info.Status));
fprintf("[setup] YAML runtime: %-10s backend=%s\n", status, backend);
if strlength(string(exe)) > 0
    fprintf("[setup] YAML python:  %s\n", exe);
end
if strlength(string(ver)) > 0
    fprintf("[setup] YAML version: %s\n", ver);
end
if ~logical(info.CanParseYAML)
    fprintf("[setup] YAML remedy:  %s\n", char(string(info.RecommendedInstallCommand)));
end
end

function localThrowMissingYAML(info)
exe = char(string(info.PythonExecutable));
if strlength(string(exe)) == 0
    exe = "<not detected>";
end
error("sixgr:lls6g:config:YAMLRuntimeUnavailable", ...
    "Unable to parse YAML configs from MATLAB. Python executable: %s. Status: %s. Install PyYAML with: %s", ...
    exe, char(string(info.Status)), char(string(info.RecommendedInstallCommand)));
end

function tf = localHasMATLABSymbol(name)
tf = any(exist(char(string(name)), "file") == [2 3 5 6 8]) || exist(char(string(name)), "builtin") == 5;
end
