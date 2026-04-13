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

script = [ ...
    "import json", newline, ...
    "import sys", newline, ...
    "import yaml", newline, ...
    "with open(sys.argv[1], 'r', encoding='utf-8') as f:", newline, ...
    "    obj = yaml.safe_load(f)", newline, ...
    "print(json.dumps(obj))", newline];
tmpPy = char(string(tempname) + ".py");
fid = fopen(tmpPy, "w");
if fid < 0
    error("sixgr:lls6g:config:YAMLTempScriptFail", ...
        "Unable to create temporary YAML helper for '%s'.", string(filePath));
end
cleanupObj = onCleanup(@() localDeleteFile(tmpPy)); %#ok<NASGU>
fprintf(fid, "%s", script);
fclose(fid);

cmd = sprintf('python "%s" "%s"', localQuotePath(tmpPy), localQuotePath(filePath));
[status, outTxt] = system(cmd);
if status ~= 0
    error("sixgr:lls6g:config:YAMLParseFailed", ...
        "Failed to parse YAML config '%s'. Ensure Python with PyYAML is available.", string(filePath));
end
data = jsondecode(outTxt);
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

function localDeleteFile(filePath)
if exist(filePath, "file") == 2
    delete(filePath);
end
end

function p = localQuotePath(pathStr)
p = strrep(char(string(pathStr)), '"', '""');
end
