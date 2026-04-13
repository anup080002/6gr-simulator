function data = readConfigFile(filePath)
%READCONFIGFILE Read YAML or JSON config into a scalar struct.

filePath = localResolvePath(filePath);
if strlength(string(filePath)) == 0 || exist(filePath, "file") ~= 2
    error("sixgr:lls6g:config:FileNotFound", "Config file not found: %s", string(filePath));
end

[~,~,ext] = fileparts(filePath);
ext = lower(string(ext));
raw = fileread(filePath);

switch ext
    case ".json"
        data = jsondecode(raw);
    case {".yaml",".yml"}
        data = localReadYAML(raw, filePath);
    otherwise
        error("sixgr:lls6g:config:UnsupportedConfigFormat", ...
            "Unsupported config format '%s' for '%s'.", ext, string(filePath));
end

if ~(builtin("isstruct", data) && isscalar(data))
    error("sixgr:lls6g:config:BadTopLevel", ...
        "Top-level config in '%s' must decode to a scalar struct.", string(filePath));
end
end

function data = localReadYAML(raw, filePath)
try
    data = jsondecode(raw);
    return;
catch
end
runtime = sixgr.lls6g.config.ensureYAMLRuntime("RequireYAML", true, "ConfigurePyEnv", true);
switch lower(string(runtime.LoaderBackend))
    case "matlab_pyrun"
        data = localReadYAMLViaMATLABPython(filePath);
    case "external_python"
        data = localReadYAMLViaExternalPython(filePath, runtime.PythonExecutable);
    otherwise
        error("sixgr:lls6g:config:YAMLParseFailed", ...
            "Failed to parse YAML config '%s'. Python executable: %s. Install PyYAML with: %s", ...
            string(filePath), string(runtime.PythonExecutable), string(runtime.RecommendedInstallCommand));
end
end

function p = localResolvePath(filePath)
if exist(char(string(filePath)), "file") == 2
    p = char(string(filePath));
    return;
end
root = localRepoRoot();
candidate = fullfile(root, char(string(filePath)));
if exist(candidate, "file") == 2
    p = candidate;
    return;
end
p = char(string(filePath));
end

function out = localRepoRoot()
here = fileparts(mfilename("fullpath"));
out = fileparts(fileparts(fileparts(here)));
end

function data = localReadYAMLViaMATLABPython(filePath)
try
    jsonText = pyrun([ ...
        "import json", newline, ...
        "import yaml", newline, ...
        "with open(config_path, 'r', encoding='utf-8') as f:", newline, ...
        "    obj = yaml.safe_load(f)", newline, ...
        "json_text = json.dumps(obj)", newline], ...
        "json_text", config_path=char(string(filePath)));
catch ME
    runtime = sixgr.lls6g.config.ensureYAMLRuntime("RequireYAML", false, "ConfigurePyEnv", true);
    error("sixgr:lls6g:config:YAMLParseFailed", ...
        "Failed to parse YAML config '%s' via MATLAB Python. Python executable: %s. Install PyYAML with: %s. Root cause: %s", ...
        string(filePath), string(runtime.PythonExecutable), string(runtime.RecommendedInstallCommand), string(ME.message));
end
data = jsondecode(char(string(jsonText)));
end

function data = localReadYAMLViaExternalPython(filePath, pythonExecutable)
script = [ ...
    "import json", newline, ...
    "import sys", newline, ...
    "import yaml", newline, ...
    "with open(sys.argv[1], 'r', encoding='utf-8') as f:", newline, ...
    "    obj = yaml.safe_load(f)", newline, ...
    "print(json.dumps(obj))", newline];
tmpPy = char(string(tempname) + ".py");
fid = fopen(tmpPy, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:lls6g:config:YAMLTempScriptFail", ...
        "Unable to create temporary YAML helper for '%s'.", string(filePath));
end
cleanupFile = onCleanup(@() localDeleteFile(tmpPy)); %#ok<NASGU>
try
    fprintf(fid, "%s", script);
    fclose(fid);
catch ME
    fclose(fid);
    rethrow(ME);
end

cmd = sprintf('"%s" "%s" "%s"', localEscapeCmdPath(pythonExecutable), localEscapeCmdPath(tmpPy), localEscapeCmdPath(filePath));
[status, outTxt] = system(cmd);
if status ~= 0
    runtime = sixgr.lls6g.config.ensureYAMLRuntime("RequireYAML", false, "ConfigurePyEnv", true);
    error("sixgr:lls6g:config:YAMLParseFailed", ...
        "Failed to parse YAML config '%s' via external Python. Python executable: %s. Install PyYAML with: %s. Root cause: %s", ...
        string(filePath), string(runtime.PythonExecutable), string(runtime.RecommendedInstallCommand), string(strtrim(outTxt)));
end
data = jsondecode(outTxt);
end

function localDeleteFile(filePath)
if exist(filePath, "file") == 2
    delete(filePath);
end
end

function p = localEscapeCmdPath(pathStr)
p = strrep(char(string(pathStr)), '"', '""');
end
