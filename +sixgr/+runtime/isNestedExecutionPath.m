function tf = isNestedExecutionPath(runFolder, candidatePath)
%ISNESTEDEXECUTIONPATH True when a path belongs to a child execution.
%   Generic-sweep children are complete executions rooted below the
%   parent's top-level sweeps/ directory.  A parent may reference those
%   executions through sweep_summary.csv, but recursive artifact scanners
%   must not ingest or mutate their evidence.

root = localCanonical(runFolder);
candidate = localCanonical(candidatePath);
tf = false;
if strlength(root) == 0 || strlength(candidate) == 0
    return;
end
prefix = root + string(filesep);
if ~startsWith(candidate, prefix, "IgnoreCase", ispc)
    return;
end
relativePath = extractAfter(candidate, strlength(prefix));
relativePath = replace(relativePath, "\", "/");
segments = split(relativePath, "/");
segments = segments(strlength(segments) > 0);
tf = ~isempty(segments) && strcmpi(segments(1), "sweeps");
end

function value = localCanonical(pathValue)
value = "";
try
    value = string(char(java.io.File(char(string(pathValue))).getCanonicalPath()));
catch
end
end
