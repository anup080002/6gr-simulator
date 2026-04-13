function p = resolveResultsRoot(inPath)
%RESOLVERESULTSROOT Anchor campaign results under the repo-local results tree.
%
% Relative paths are always interpreted from the repository root, never the
% caller's current working directory. Absolute paths are only accepted when
% they already live under <repo>/results; everything else is redirected to
% the repo-local results root to keep artifacts inside the repository.

repoRoot = localRepoRoot();
repoResults = localNormalizePath(fullfile(repoRoot, "results"));

p = localNormalizePath(inPath);
if strlength(string(p)) == 0
    p = repoResults;
    return;
end

if localIsAbsolutePath(p)
    if localPathStartsWith(p, repoResults)
        return;
    end
    p = repoResults;
    return;
end

if strcmpi(p, ".") || strcmpi(p, filesep)
    p = repoResults;
    return;
end

if strcmpi(p, "results") || startsWith(lower(string(p)), lower("results" + filesep))
    p = localNormalizePath(fullfile(repoRoot, p));
else
    p = localNormalizePath(fullfile(repoResults, p));
end
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
root = localNormalizePath(root);
end

function tf = localIsAbsolutePath(p)
p = char(string(p));
if ispc
    tf = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || startsWith(p, "\\");
else
    tf = startsWith(p, "/");
end
end

function tf = localPathStartsWith(pathValue, rootValue)
pathValue = char(string(localNormalizePath(pathValue)));
rootValue = char(string(localNormalizePath(rootValue)));

if ispc
    pathCmp = lower(pathValue);
    rootCmp = lower(rootValue);
else
    pathCmp = pathValue;
    rootCmp = rootValue;
end

tf = strcmp(pathCmp, rootCmp) || startsWith(pathCmp, [rootCmp filesep]);
end

function p = localNormalizePath(inPath)
p = char(string(strtrim(string(inPath))));
if strlength(string(p)) == 0
    p = "";
    return;
end

p = strrep(p, "/", filesep);
p = strrep(p, "\", filesep);

while contains(p, [filesep filesep])
    p = strrep(p, [filesep filesep], filesep);
end

if strlength(string(p)) > 1 && endsWith(p, filesep) && ~(ispc && numel(p) == 3 && p(2) == ':')
    p = extractBefore(string(p), strlength(string(p)));
    p = char(p);
end
end
