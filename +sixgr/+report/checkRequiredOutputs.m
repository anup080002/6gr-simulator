function out = checkRequiredOutputs(runFolder, requiredOutputs, varargin)
%CHECKREQUIREDOUTPUTS Verify that every claimed required output exists.

p = inputParser;
p.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
strictMode = logical(p.Results.StrictMode);

runFolder = char(string(runFolder));
required = localNormalizeRequiredOutputs(requiredOutputs);

rows = repmat(struct( ...
    "RequiredPath", "", ...
    "ResolvedPath", "", ...
    "Exists", false, ...
    "Status", "", ...
    "Notes", ""), numel(required), 1);

for i = 1:numel(required)
    reqPath = required(i);
    [resolvedPath, notes] = localResolveRequiredPath(runFolder, reqPath);
    existsNow = localPathExists(resolvedPath);
    status = "ok";
    if ~existsNow
        status = "missing_required";
    end
    rows(i) = struct( ...
        "RequiredPath", string(reqPath), ...
        "ResolvedPath", string(resolvedPath), ...
        "Exists", logical(existsNow), ...
        "Status", status, ...
        "Notes", string(notes));
end

if isempty(rows)
    T = table(string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), string.empty(0,1), ...
        "VariableNames", {"RequiredPath","ResolvedPath","Exists","Status","Notes"});
else
    T = struct2table(rows);
end

missing = string.empty(0,1);
if ~isempty(T)
    missing = string(T.RequiredPath(~logical(T.Exists)));
end

out = struct();
out.Ok = isempty(missing);
out.Table = T;
out.Missing = missing;
out.MissingCount = double(numel(missing));

if strictMode && ~out.Ok
    error("sixgr:report:MissingRequiredOutputs", ...
        "Missing required outputs: %s", strjoin(cellstr(missing), ", "));
end
end

function required = localNormalizeRequiredOutputs(requiredOutputs)
if nargin < 1 || isempty(requiredOutputs)
    required = strings(0,1);
    return;
end

if ischar(requiredOutputs) || isstring(requiredOutputs)
    required = string(requiredOutputs(:));
elseif iscell(requiredOutputs)
    required = string(requiredOutputs(:));
else
    error("sixgr:report:BadRequiredOutputs", ...
        "requiredOutputs must be char, string, or cellstr.");
end

required = strtrim(required);
required = required(strlength(required) > 0);
required = unique(required, "stable");
end

function [resolvedPath, notes] = localResolveRequiredPath(runFolder, reqPath)
reqPath = char(string(reqPath));
notes = "absolute_path";
if localIsAbsolutePath(reqPath)
    resolvedPath = reqPath;
    return;
end

resolvedPath = fullfile(runFolder, reqPath);
notes = "relative_to_run_folder";
end

function tf = localPathExists(pathStr)
tf = false;
if nargin < 1 || strlength(string(pathStr)) == 0
    return;
end
tf = (exist(pathStr, "file") == 2) || isfolder(pathStr);
end

function tf = localIsAbsolutePath(pathStr)
pathStr = char(string(pathStr));
tf = false;
if isempty(pathStr)
    return;
end
tf = ~isempty(regexp(pathStr, "^[A-Za-z]:[\\/]", "once")) || startsWith(pathStr, filesep);
end
